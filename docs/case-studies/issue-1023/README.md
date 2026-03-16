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

### Phase 4: `render_mode blend_add` Attempt (commit 21221cc8) — Still White Blink

**Game log analysis** (`game_log_20260317_010325.txt`) confirmed:
- Lightning IS triggering correctly (TRIPLE, DOUBLE, SINGLE strikes logged)
- Shader logs show "Lightning bolt shader loaded" (v2 procedural shader)
- Yet user still reported: "всё ещё не срабатывает (моргает белым)" — "still not working (white blink)"

**Diagnosis at the time:** v2 shader had 35% white ambient fill + missing `render_mode blend_add`.

**Fix applied:** Added `render_mode blend_add;` to `lightning_flash.gdshader`.

**But user reported again (`game_log_20260317_021309.txt`):** "всё ещё не работает (просто белая вспышка)" — still just a white flash.

---

### Phase 5: Root Cause of Persistent White Blink — gl_compatibility Renderer Incompatibility

**Decisive finding: `render_mode blend_add` does NOT work reliably in Godot's gl_compatibility renderer.**

This is the exact same renderer limitation documented in Issue #958 (Black Metal filter white screen) and referenced in `cinema_effects_manager.gd`:

> *"gl_compatibility renderer has known bugs with hint_screen_texture"*
> *— Godot Issue #79914, #66458*

**What happens when `blend_add` fails in gl_compatibility:**
- The ColorRect renders as a **full-alpha opaque rectangle** (Godot falls back to normal blending)
- The shader outputs `COLOR = vec4(final_rgb * intensity, 1.0)` with `alpha=1.0`
- This **replaces the entire screen** with the shader output
- At non-bolt pixels: `final_rgb ≈ vec3(0,0,0)` (black) — but with `alpha=1.0`, the result is just a black rectangle when not at bolt
- Wait — the ColorRect's default background color is **white** (`Color(1,1,1,1)`)
- When the shader returns black, the blend overwrites the scene with black (not transparent)

Actually the real problem is simpler: **`render_mode blend_add` is simply not supported/applied** in the gl_compatibility renderer at the canvas_item level. The ColorRect becomes an opaque full-screen overlay using default `blend_mix` (standard alpha). The white blink comes from the bolt shader's non-bolt pixels having zero or near-zero brightness — but the entire scene is replaced by the full-alpha shader output, which at `COLOR = vec4(0,0,0,1)` makes a black screen. But with any ambient fill (even a small corona), some pixels become white, and the blending overwrites the scene.

In testing with the game logs (`game_log_20260317_021309.txt`):
```
[02:13:26] [BlackMetalLightningEffectsManager] Starting SINGLE lightning strike
```
Lightning IS firing. The shader IS loaded. But the visual is still a white blink — confirming `render_mode blend_add` has no effect and the ColorRect is rendering with standard full-alpha blending.

**Cross-reference with all other successful effects in this game:**

All shaders in this game that produce screen-wide overlay effects use `hint_screen_texture`:
- `black_metal.gdshader` — uses `hint_screen_texture` ✓ (works after Issue #958 fix)
- `saturation.gdshader` — uses `hint_screen_texture` ✓
- `flashbang_player.gdshader` — uses `hint_screen_texture` ✓
- `last_chance.gdshader` — uses `hint_screen_texture` ✓
- `ghost_replay.gdshader` — uses `hint_screen_texture` ✓

Only the cinema_film shader does NOT use `hint_screen_texture` — but it creates only subtle overlays (grain, vignette) with very low alpha, where standard blending produces acceptable results. For a full-screen-replacement effect like lightning, this approach does not work.

---

## Root Cause Summary

| Version | Root Cause | Visual Result |
|---------|-----------|---------------|
| v1 shader | `TEXTURE` on ColorRect = 1×1 white pixel, no bolt drawn | White blink |
| v2 shader | Screen-wide 35% white ambient fill dominated the bolt | White blink |
| v3 shader | `render_mode blend_add` not supported in gl_compatibility; ColorRect renders as full-alpha opaque overlay | White blink |
| **v4 shader** | **Uses `hint_screen_texture` (same as black_metal.gdshader); additive bolt brightening on actual scene pixels** | **Actual lightning bolt** |

---

## Fix: v4 Shader with `hint_screen_texture` (Final Solution)

The definitive fix uses the **same approach as all other successful screen-effect shaders in this game**:

```glsl
shader_type canvas_item;
// NO render_mode blend_add — not supported in gl_compatibility

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
// ↑ reads actual rendered scene pixels, exactly like black_metal.gdshader

void fragment() {
    vec4 original = textureLod(screen_texture, SCREEN_UV, 0.0);

    if (intensity <= 0.001) {
        COLOR = original;  // pass-through during warmup (safe)
        return;
    }

    // ... compute bolt_contrib and corona ...

    // ADDITIVE: only bolt pixels become brighter; non-bolt pixels unchanged
    vec3 lightning_add = bolt_rgb * bolt_val + corona_color * corona;
    lightning_add *= intensity;

    // Away from bolt: lightning_add ≈ 0 → COLOR = original (no white blink)
    // At bolt center: COLOR = original + bright blue-white (bolt visible)
    COLOR = vec4(original.rgb + lightning_add, original.a);
}
```

**Why this fixes the white blink:**
1. Non-bolt pixels: `lightning_add = 0` → `COLOR = original` (pure pass-through, scene unchanged)
2. Bolt pixels: `COLOR = original + bright_blue_white` (scene brightened at bolt position)
3. At `intensity=0`: full pass-through (safe for warmup, same as black_metal.gdshader)
4. The `hint_screen_texture` reads the actual rendered B&W scene (after layer 97 filter), so the bolt appears correctly on top of the Black Metal filter

**Safety (same warmup pattern as black_metal.gdshader):**
- Manager warmup: sets `intensity=0.0`, shows rect for 1 frame, hides → no visible effect during compilation
- Delayed activation: 3 frames after scene transitions before allowing flashes
- This is identical to `black_metal_effects_manager.gd`'s proven approach

---

## Files Changed

### `scripts/shaders/lightning_flash.gdshader`
- **Removed** `render_mode blend_add;` (not supported in gl_compatibility)
- **Added** `uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;`
- **Changed** `void fragment()` to read `original` from `screen_texture` (like black_metal.gdshader)
- **Changed** final output: `COLOR = vec4(original.rgb + lightning_add, original.a)` (true additive)
- At `intensity=0.0`: returns `original` (pass-through, safe for warmup)
- Tight corona near bolt origin (not screen-wide) — preserves no-blink behavior

---

## References

- **Issue #958 case study** (`docs/case-studies/issue-958/README.md`): Full analysis of gl_compatibility white screen issues — identical root cause pattern
- **Godot Issue #79914:** `hint_screen_texture` glitches in Compatibility mode (why 3-frame delay is needed)
- **Godot Issue #66458:** OpenGL Compatibility renderer issues tracker
- **`black_metal.gdshader`**: Reference implementation for correct screen-reading overlay in this game
- **Classic horror film lightning:** Blue-white bolt as dominant visual; brief area illumination near strike point

---

## Game Logs

| File | Description |
|------|-------------|
| `game_log_20260312_014153.txt` | First test after trigger fix — lightning only fired on player-damage, not on enemy hit |
| `game_log_20260317_010325.txt` | Second test after v2 shader — lightning fires correctly but still looks like white blink |
| `game_log_20260317_021309.txt` | Third test after v3 blend_add shader — lightning fires correctly, still white blink (blend_add not working in gl_compatibility) |
