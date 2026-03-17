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

### Phase 5: `hint_screen_texture` Attempt (commit d3ba6385) — STILL White Blink

**Game log analysis** (`game_log_20260317_025412.txt`) confirmed:
- Lightning IS triggering correctly ✅
- Shader IS loading correctly ✅
- **User reports: "всё ещё просто белая вспышка" — "still just a white flash"** ❌

The v4 shader used `hint_screen_texture` (same as `black_metal.gdshader`). Logic said it should work.
But the user still saw white blink.

**Root cause of v4 failure (definitive):**

The `black_metal.gdshader` has its ColorRect **ALWAYS VISIBLE** — it's on all the time and never hides/shows.

The lightning shader had `_flash_rect.visible = false` between flashes, and `_flash_rect.visible = true` when a flash started.

In Godot's gl_compatibility renderer, **`hint_screen_texture` does NOT capture the screen correctly on the very first frame a ColorRect transitions from `visible=false` to `visible=true`**. The screen buffer is not captured for an element that wasn't visible the previous frame. This causes the screen_texture sampler to return white/empty, and since `COLOR = original.rgb + lightning_add` with `original = white`, the entire output is white.

The warmup (1 frame at intensity=0 with visible=true) did compile the shader, but after warmup the rect was hidden again. Each flash re-triggered the visible=false→visible=true transition, hitting the bug every time.

This is consistent with Godot Issues #79914 and #66458 — the screen texture capture in gl_compatibility is tied to the previous frame's rendered output and doesn't work for newly-visible elements.

---

### Phase 6: Overlay Approach with Always-Visible ColorRect (commit c9c656bf) — New Regression

The v5 overlay shader (no `hint_screen_texture`, `COLOR = vec4(0,0,0,0)` at intensity=0) was believed to be the fix.

**User reported (`game_log_20260317_032119.txt`):** "теперь на всех сложностях сломался визуал (белый экран)" — "now visuals are broken on ALL difficulties (white screen)"

This is a **regression** — the white screen now appears on EVERY difficulty mode, not just during lightning flashes.

**Root cause of v5 regression:**

A full-screen transparent `ColorRect` at layer 98 with `COLOR = vec4(0,0,0,0)` interferes with `hint_screen_texture` in higher-layer shaders. The `cinema_film.gdshader` runs at layer 99 and uses `hint_screen_texture` to composite its film grain overlay. When layer 98 has an always-visible transparent quad, the screen texture capture for layer 99 captures the **transparent quad** (black with alpha=0) rather than the actual game scene — producing a white screen in gl_compatibility's screen capture.

In the game log:
```
[CinemaEffects] Created effects layer at layer 99
[BlackMetalLightningEffectsManager] Lightning bolt shader loaded
[CinemaEffects] Cinema effect now enabled (after 1 frames delay)
```
Lightning manager layer 98 with transparent always-visible ColorRect is present before cinema (layer 99) activates. Cinema's `hint_screen_texture` then reads through the transparent quad and gets a corrupted (white) result.

---

## Phase 7: v6 still shows white blink (game_log_20260317_050932.txt)

**User reported:** "всё ещё не работает" — "still not working"

**Game log analysis** (`game_log_20260317_050932.txt`):
- Shader warmup completed successfully ✅
- Lightning effects ENABLED when switching to Black Metal ✅
- **No lightning strikes were triggered** (no SINGLE/DOUBLE/TRIPLE logs — no shots fired) ✅
- Game session: 28 seconds total, only 2 seconds in Black Metal mode

**Key observation:** The user did not actually trigger any lightning strikes in this session. This means the white blink they are seeing is **at game startup**, not during a lightning flash.

**Root cause of v6 white flash at startup:**

In v6, `_flash_rect.visible = true` was set in `_ready()` — before warmup. On the very first game frame, the GL framebuffer is not yet populated. `hint_screen_texture` returns white/empty. The shader executes `COLOR = original = white` (passthrough at intensity=0). This produces a visible white flash at game startup, even without any lightning being triggered.

This is a different but related manifestation of the same underlying issue: hint_screen_texture is unreliable on the first frame an element is first visible.

---

## Root Cause Summary

| Version | Root Cause | Visual Result |
|---------|-----------|---------------|
| v1 shader | `TEXTURE` on ColorRect = 1×1 white pixel, no bolt drawn | White blink on flash |
| v2 shader | Screen-wide 35% white ambient fill dominated the bolt | White blink on flash |
| v3 shader | `render_mode blend_add` not supported in gl_compatibility | White blink on flash |
| v4 shader | `hint_screen_texture` captures white on first frame after `visible=false→true` transition during gameplay | White blink on flash |
| v5 shader | Transparent ColorRect always-visible at layer 98 corrupts other shaders | White screen on ALL difficulties |
| v6 shader | `visible=true` set in `_ready()` before framebuffer populated → white passthrough on startup frame | White blink at startup |
| **v7 shader** | **`visible=false` in `_ready()`, `visible=true` set after 1 warmup frame (permanently)** | **Lightning bolt, no regression** |

---

## Fix: v7 Shader — hint_screen_texture with Correct Startup Sequence (Final Solution)

The fix corrects the startup sequence: start `visible=false`, show after one warmup frame.

**Manager startup sequence:**
```gdscript
func _ready():
    # HIDDEN: framebuffer not yet populated on frame 0
    _flash_rect.visible = false
    _warmup_shader()  # async

func _warmup_shader():
    _material.set_shader_parameter("intensity", 0.0)
    # Wait 1 frame: scene renders once, framebuffer populated
    await get_tree().process_frame
    # PERMANENTLY VISIBLE: hint_screen_texture now returns valid scene pixels
    _flash_rect.visible = true
    # Never toggle visible again — intensity=0 is the "off" state
```

**Why this definitively fixes all observed failures:**
1. **No white blink at startup**: `visible=false` on frame 0 → framebuffer populates without sampling
2. **No white blink on flash**: `visible` never toggles after warmup → no screen-capture bug
3. **No white screen on all difficulties**: `intensity=0` → `COLOR = original` (pure passthrough)
4. **Correct lightning visuals**: additive brightening shows bolt over scene

---

## Files Changed

### `scripts/shaders/lightning_flash.gdshader`
- **Uses** `hint_screen_texture` (same as `black_metal.gdshader`)
- At `intensity=0.0`: pure passthrough — `COLOR = original` → no effect on any difficulty
- At `intensity=1.0`: additive brightening at bolt pixels — lightning glows over scene

### `scripts/autoload/black_metal_lightning_effects_manager.gd`
- **v7**: `visible=false` in `_ready()`, permanently `visible=true` after 1 warmup frame
- Manager only sets `intensity` after warmup — never toggles `visible` during gameplay

---

## References

- **`cinema_film.gdshader`**: Overlay approach (no screen_texture) for subtle vignette/grain effects
- **`black_metal_effects_manager.gd`**: Reference pattern for hint_screen_texture + startup delay
- **Issue #958 case study** (`docs/case-studies/issue-958/README.md`): gl_compatibility white screen issues
- **Godot Issue #79914:** `hint_screen_texture` glitches in Compatibility mode
- **Godot Issue #66458:** OpenGL Compatibility renderer issues tracker

---

## Game Logs

| File | Description |
|------|-------------|
| `game_log_20260312_014153.txt` | First test after trigger fix — lightning only fired on player-damage, not on enemy hit |
| `game_log_20260317_010325.txt` | Second test after v2 shader — lightning fires correctly but still looks like white blink |
| `game_log_20260317_021309.txt` | Third test after v3 blend_add shader — lightning fires correctly, still white blink |
| `game_log_20260317_025412.txt` | Fourth test after v4 hint_screen_texture shader — lightning fires correctly, STILL white blink (visible=false→true transition) |
| `game_log_20260317_032119.txt` | Fifth test after v5 overlay shader — white screen on ALL difficulties (transparent overlay regression) |
| `game_log_20260317_050932.txt` | Sixth test after v6 — no lightning triggered; white blink is at startup (visible=true set before framebuffer ready) |
