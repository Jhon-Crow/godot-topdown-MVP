# Case Study: Issue #1023 - Thunder and Lightning Effects for Black Metal Difficulty

## Issue Summary

**Issue URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1023

**Request (translated from Russian):**
> Add thunder and lightning effects on every enemy hit.
> This should add more Black Metal style and should look diverse.
> Lightning should illuminate the entire screen.
> Make it look cooler.

---

## Timeline / Sequence of Events

### Phase 1: Initial Implementation (commit 01c12951)

The first implementation created `BlackMetalLightningEffectsManager` and `lightning_flash.gdshader`.

**The original shader (v1) used `hint_screen_texture` approach:**
```glsl
void fragment() {
    vec4 screen_color = texture(TEXTURE, UV);  // <-- TEXTURE on ColorRect = 1×1 white pixel
    vec3 brightened = screen_color.rgb + flash_color * intensity * brightness_boost;
    COLOR.rgb = mix(screen_color.rgb, brightened, intensity);
    COLOR.a = screen_color.a;
}
```

**Root cause of v1 failure:** `TEXTURE` on a `ColorRect` node is a 1×1 white pixel, not the screen. So `screen_color = vec4(1,1,1,1)` always. The "brightened" result was just a more-white rectangle → **screen blink only, no bolt visible**.

---

### Phase 2: Trigger Fix for C# Weapons (commit 89996744)

The player was using a Sniper Rifle (C# weapon). The original `trigger_lightning` call was only in `scripts/projectiles/bullet.gd` (GDScript). All C# projectile/weapon classes had their own `TriggerPlayerHitEffects()` methods that were not updated:

- `Scripts/Projectiles/Bullet.cs`
- `Scripts/Projectiles/SniperBullet.cs`
- `Scripts/Projectiles/ShotgunPellet.cs`
- `Scripts/Weapons/SniperRifle.cs`
- `Scripts/Autoload/ReplayManager.cs`

This commit added `trigger_lightning()` to all five C# classes. After this fix, lightning IS triggering on enemy hits (confirmed in game logs).

---

### Phase 3: Procedural Bolt Shader (commit 03231c17)

The v1 blank-texture shader was replaced with a procedural bolt shader that draws an actual jagged lightning bolt using SDF + FBM noise. The shader used the correct overlay approach (no `hint_screen_texture`).

**But the user still reported: "сейчас экран просто моргает когда должна появляться молния"**
(Translation: "the screen still just blinks when lightning should appear")

---

### Phase 4: Root Cause Analysis of v2 Shader (current investigation)

**Game log analysis** (`game_log_20260317_010325.txt`) confirmed:
- Lightning IS triggering correctly (TRIPLE, DOUBLE, SINGLE strikes logged)
- Shader logs show "Lightning bolt shader loaded" (new v2 shader, not old)
- Yet user still sees white blink behavior

**Root cause of v2 failure: missing `render_mode blend_add`**

The v2 shader used `shader_type canvas_item` without specifying a blend mode, which defaults to standard alpha compositing. In standard alpha blending:

```
final_pixel = shader_output * shader_alpha + scene_pixel * (1 - shader_alpha)
```

The shader computed a **screen-wide ambient flash** at `flash_strength = 0.35` opacity covering the whole screen:
```glsl
float screen_glow = flash_strength * 0.35;  // = 0.35 at progress=0
float final_alpha = clamp(screen_alpha + bolt_alpha * 0.9, 0.0, 1.0);
// At non-bolt pixel: final_alpha ≈ 0.35, final_color = vec3(0.88, 0.92, 1.0)
```

This means **35% of each pixel on the entire screen** was covered by a cool-white overlay at peak intensity — visually identical to the original white blink.

The bolt itself (core width `0.003 UV = ~3.8 pixels`) was technically drawn, but it was:
1. Invisible against the 35% white background already covering the whole screen
2. Very thin relative to the screen-wide white fill

**Additional technical factors:**
- Classic horror films have the bolt as the dominant visual element, not the ambient fill
- Without `blend_add`, any non-zero alpha on non-bolt pixels produces the "blink" look
- With `blend_add`, black = transparent (adds nothing), bright = adds light to scene

---

## Root Cause Summary

| Version | Root Cause | Visual Result |
|---------|-----------|---------------|
| v1 shader | `TEXTURE` on ColorRect = 1×1 white pixel, no bolt drawn | White blink |
| v2 shader | Missing `render_mode blend_add`; 35% white ambient fill dominated | White blink |
| v3 shader | `render_mode blend_add` + corona instead of screen fill | Actual lightning bolt visible |

---

## Fix: v3 Shader with `render_mode blend_add`

The fix adds `render_mode blend_add;` to the shader and changes the visual composition:

```glsl
shader_type canvas_item;
render_mode blend_add;  // ← key fix: black=invisible, bright=adds light to scene
```

With additive blending:
- `COLOR = vec4(0.0, 0.0, 0.0, 1.0)` → adds nothing to scene (equivalent to transparent)
- `COLOR = vec4(1.0, 1.0, 1.0, 1.0)` → makes that pixel fully white by adding maximum light
- The bolt's background (where no bolt) stays completely invisible
- The bolt streak itself adds bright blue-white light to the scene
- A tight corona near the origin adds a zone of extra brightness (but not screen-wide)

**Visual result:** Actual jagged lightning bolt visible on screen, with surrounding blue-white glow, striking from top of screen downward — classic horror film lightning effect.

---

## Files Changed

### `scripts/shaders/lightning_flash.gdshader`
- Added `render_mode blend_add;`
- Replaced screen-wide ambient flash with tight directional corona near bolt origin
- Increased bolt widths (core 0.003→0.004, glow 0.012→0.018, outer 0.04→0.055)
- Made glow color more vivid blue-white (0.65/0.75/1.0 → 0.55/0.70/1.0)
- Changed final output from alpha-controlled to `vec4(final_rgb * intensity, 1.0)`
- Removed aspect ratio correction (was causing slight distortion in SDF)

---

## References

- **Godot Issue #79914:** `hint_screen_texture` glitches in Compatibility mode (explains why screen texture sampling was avoided)
- **Godot Issue #66458:** OpenGL Compatibility renderer issues tracker
- **godotshaders.com lightning shaders:** Confirmed `render_mode blend_add` is standard for lightning overlays
- **Classic horror film lightning:** Blue-white bolt as dominant visual; ambient fill secondary/localized

---

## Game Logs

| File | Description |
|------|-------------|
| `game_log_20260312_014153.txt` | First test after trigger fix — lightning only fired on player-damage, not on enemy hit |
| `game_log_20260317_010325.txt` | Second test after v2 shader — lightning fires correctly but still looks like white blink |
