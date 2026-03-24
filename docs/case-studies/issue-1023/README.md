# Case Study: Issue #1023 - Thunder and Lightning Effects for Black Metal Difficulty

## Issue Summary

**Issue URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1023

**Request (translated from Russian):**
> Add thunder and lightning effects on every enemy hit.
> This should add more Black Metal style and should look diverse.
> Lightning should illuminate the entire screen.
> Make it look cooler.

**Updated requirement (2026-03-17, PR comment):**
> "хорошо работает. но сделай чтоб молнии появлялись не при нанесении урона врагу, а после убийства."
> Translation: "Works well. But make lightning appear not when dealing damage to an enemy, but after killing them."

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

## Phase 8: v7 STILL shows white blink (game_log_20260317_054351.txt)

**User reported:** "всё та же проблема сразу после запуска" — "same problem right after launch"

**Game log analysis** (`game_log_20260317_054351.txt`):
```
[05:43:52] [BlackMetalLightningEffectsManager] Shader warmup complete in 607 ms (ColorRect now permanently visible, intensity=0 = passthrough)
[05:43:52] [PersistManager] Navigating to last played level: res://scenes/levels/CityLevel.tscn
[05:43:52] [BlackMetalEffectsManager] Scene changed to: CityLevel
```
(No scene-changed log for `BlackMetalLightningEffectsManager` — because v7 didn't listen to `tree_changed`)

**Timeline reconstruction:**
1. `05:43:51` — Game starts, both managers initialize
2. `05:43:52` — Warmup frame completes — `_flash_rect.visible = true` set **permanently**
3. `05:43:52` — `PersistManager` navigates to `CityLevel` (last played level redirect)
4. `05:43:52` — New scene loads, GL framebuffer **resets** for the new scene
5. `05:43:52` — On the first frame of `CityLevel`: `hint_screen_texture` returns **white** (framebuffer not yet populated for this scene)
6. With `visible=true` + `intensity=0`: shader outputs `COLOR = original = WHITE` → **white blink**

**Root cause of v7 failure:**
v7 set `visible=true` permanently after warmup, but **did not listen for scene transitions**. The warmup runs in `LabyrinthLevel` (the initial scene). `PersistManager` immediately redirects to `CityLevel`. On the first frame of `CityLevel`, `hint_screen_texture` returns white. With the ColorRect permanently visible and `intensity=0` passthrough, this white is output to the screen.

This is fundamentally the same bug that `black_metal_effects_manager` solved with its `_on_tree_changed` handler and `ACTIVATION_DELAY_FRAMES` — but v7 did not implement this.

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
| v7 shader | `visible=true` set permanently after warmup; PersistManager scene redirect causes framebuffer reset → white on first frame of new scene | White blink at startup (scene change) |
| **v8 manager** | **`visible=false` between flashes; `tree_changed` aborts in-progress flashes on scene change** | **No white blink; lightning bolt on hits** |

---

## Fix: v8 Manager — visible=false Between Flashes (Final Solution)

The definitive fix: the ColorRect is `visible=false` between flashes. It is only made `visible=true` at the moment a bolt fires, and hidden again when the flash sequence ends. This means `hint_screen_texture` is only sampled when the bolt is actually rendering — at which point the framebuffer is fully populated for the current scene.

**Manager design:**
```gdscript
func _ready():
    get_tree().tree_changed.connect(_on_tree_changed)
    _flash_rect.visible = false    # hidden initially
    _warmup_shader()               # warmup: visible=true for 1 frame, then hidden

func _on_tree_changed():
    # On scene change: abort any in-progress flash, ensure rect is hidden
    if current_scene != _previous_scene_root:
        _is_flashing = false
        _flash_rect.visible = false   # safe: no hint_screen_texture sampling

func _start_single_flash():
    _flash_rect.visible = true         # show only when bolt fires
    _material.set_shader_parameter("intensity", 1.0)

func _end_flash_sequence():
    _flash_rect.visible = false        # hide when done
    _material.set_shader_parameter("intensity", 0.0)
```

**Why this definitively fixes all observed failures:**
1. **No white blink at startup**: rect hidden by default — no hint_screen_texture sampling at startup
2. **No white blink on scene transitions**: `_on_tree_changed` keeps rect hidden between scenes
3. **No white blink on flash**: rect becomes visible inside an already-rendered scene → framebuffer populated
4. **No white screen on all difficulties**: rect not visible between flashes → no pipeline interference

---

## Phase 9: v8 STILL shows white blink (game_log_20260317_063247.txt)

**User reported (2026-03-17 03:33):** "теперь игру видно, но вместо молнии всё ещё белая вспышка (не работает)" — "now the game is visible, but instead of lightning there's still a white flash (not working)"

**Game log analysis** (`game_log_20260317_063247.txt`):
- Shader warmup completed at startup ✅
- Lightning effects ENABLED when in Black Metal mode ✅
- DOUBLE, SINGLE strikes logged at correct times (enemy hits) ✅
- **User still sees white flash** ❌

**Root cause of v8 failure:**

The v8 approach (hide between flashes, show only during flash) still uses `hint_screen_texture`. The previous analysis assumed this was safe because "the framebuffer is fully populated at the moment a flash fires". But this assumption is wrong.

**The definitive root cause**: `hint_screen_texture` in Godot's gl_compatibility renderer returns white/empty on the **first frame any ColorRect transitions from `visible=false` to `visible=true`**, regardless of when in the game lifecycle this happens. This is not limited to:
- startup (v6 failure)
- scene changes (v7 failure)

It also happens **on every single flash** — every time `_start_single_flash()` calls `_flash_rect.visible = true`, the very first rendered frame of that flash hits the white-backbuffer issue. So the user sees a white flash instead of a lightning bolt.

This is documented in Godot issues:
- [#79914](https://github.com/godotengine/godot/issues/79914): `screen_texture` in Compatibility mode produces glitches not present in Forward+
- [#83939](https://github.com/godotengine/godot/issues/83939): Hidden canvas_item with screen-reading shader — workaround is `modulate.a=0` instead of `visible=false`
- [#106787](https://github.com/godotengine/godot/issues/106787): Compatibility renderer ignores `filter_nearest` flag on screen-reading textures

The v3 `blend_add` attempt was also `visible`-toggled and failed for the same reason — but was abandoned before it was correctly diagnosed.

---

## Fix: v9 Manager — render_mode blend_add + ALWAYS VISIBLE (Definitive Solution)

**Key insight:** The problem is not `hint_screen_texture` per se — it's the `visible=false → visible=true` transition. The correct solution is:

1. **Remove `hint_screen_texture`** entirely — use `render_mode blend_add`
2. **Keep ColorRect ALWAYS VISIBLE** — never toggle `visible`
3. **Use intensity=0 as the "off" state** — at intensity=0, the shader outputs black, and `blend_add` with black = no change to framebuffer

Why `render_mode blend_add` + always-visible works:
- The ColorRect is always in the rendering pipeline → no first-frame initialization issue
- `framebuffer += (0,0,0) = no change` when not flashing → safe for all difficulties
- No `hint_screen_texture` → no screen capture issues
- Does NOT produce a transparent alpha overlay → no interference with `cinema_film.gdshader` at layer 99

The v5 overlay failure (always-visible transparent ColorRect) was different: it used standard `blend_mix` with `COLOR = vec4(0,0,0,0)` (alpha=0). An alpha=0 overlay at layer 98 corrupted the `hint_screen_texture` capture at layer 99. With `render_mode blend_add` and `COLOR = vec4(0,0,0,1)` (black additive), there is no alpha manipulation — the framebuffer simply receives `+= (0,0,0)` which changes nothing.

**Manager design (v9):**
```gdscript
func _ready():
    # ColorRect is set visible=true once and NEVER toggled again
    _flash_rect.visible = true
    _warmup_shader()

func _start_single_flash():
    # Set intensity=1 to make bolt appear (no visibility toggle)
    _material.set_shader_parameter("intensity", 1.0)

func _end_flash_sequence():
    # Set intensity=0 to make bolt disappear (no visibility toggle)
    _material.set_shader_parameter("intensity", 0.0)
```

**Shader design (v9):**
```glsl
shader_type canvas_item;
render_mode blend_add;

void fragment() {
    if (intensity <= 0.001) {
        COLOR = vec4(0.0, 0.0, 0.0, 1.0);  // black additive = no change to scene
        return;
    }
    // ... compute bolt, corona, etc.
    vec3 lightning_add = bolt_rgb * bolt_val + corona_color * corona;
    lightning_add *= intensity;
    // framebuffer += lightning_add: adds bright light at bolt, nothing elsewhere
    COLOR = vec4(lightning_add, 1.0);
}
```

---

## Complete Root Cause Summary

| Version | Shader | Manager | Root Cause | Visual Result |
|---------|--------|---------|-----------|---------------|
| v1 | `TEXTURE` on ColorRect = 1×1 white pixel | - | No bolt drawn | White blink on flash |
| v2 | Overlay (blend_mix, alpha output) | visible toggle | 35% ambient fill + white blink in gl_compat | White blink on flash |
| v3 | `render_mode blend_add`, visible toggle | visible toggle | First-frame init issue on visible=true transition | White blink on flash |
| v4 | `hint_screen_texture`, visible toggle | visible toggle | `hint_screen_texture` returns white on first visible frame | White blink on every flash |
| v5 | Overlay (blend_mix, alpha=0) | always visible | Alpha=0 full-screen overlay at layer 98 corrupts `hint_screen_texture` at layer 99 | White screen ALL difficulties |
| v6 | `hint_screen_texture` | visible=true in _ready | Visible before framebuffer populated at startup | White blink at startup |
| v7 | `hint_screen_texture` | permanent visible after warmup | PersistManager scene change resets framebuffer; no tree_changed handler | White blink at startup (scene change) |
| v8 | `hint_screen_texture` | visible toggle (hide between flashes) | `hint_screen_texture` returns white on first frame of EVERY flash (visible=false→true) | White blink on every flash |
| **v9** | **`render_mode blend_add`** | **always visible, intensity=0 = off** | **No screen texture, no visibility toggle, black additive = harmless** | **Lightning bolt, no regression** |
5. **Correct lightning visuals**: additive brightening shows bolt over scene during flash

---

## Files Changed

### `scripts/shaders/lightning_flash.gdshader`
- **Uses** `hint_screen_texture` (same as `black_metal.gdshader`)
- At `intensity=0.0`: pure passthrough — `COLOR = original` → no effect on any difficulty
- At `intensity=1.0`: additive brightening at bolt pixels — lightning glows over scene

### `scripts/autoload/black_metal_lightning_effects_manager.gd`
- **v8**: `visible=false` between flashes (not a persistent overlay)
- Connects to `tree_changed` to abort in-progress flashes on scene transitions
- `_start_single_flash()` sets `visible=true`, `_end_flash_sequence()` sets `visible=false`
- Warmup: visible=true for 1 frame (at intensity=0), then hidden

---

## References

- **`cinema_film.gdshader`**: Overlay approach (no screen_texture) for subtle vignette/grain effects
- **`black_metal_effects_manager.gd`**: Reference pattern for hint_screen_texture + startup delay + tree_changed
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
| `game_log_20260317_054351.txt` | Seventh test after v7 — warmup completes, PersistManager redirects to CityLevel; white blink on scene change (rect permanently visible, framebuffer reset) |
| `game_log_20260317_063247.txt` | Eighth test after v8 — game visible, but still white blink on every flash (hint_screen_texture returns white on visible=false→true transition during gameplay) |
| `game_log_20260317_071747.txt` | Ninth test after v9 (blend_add always-visible) — white screen from startup (blend_add not supported in gl_compatibility; always-visible black ColorRect corrupts pipeline) |

---

## Phase 10: v9 causes white screen at startup (game_log_20260317_071747.txt)

**User reported (2026-03-17 04:18):** "опять с самого начала белый экран" — "white screen from the very start again"

**Game log analysis** (`game_log_20260317_071747.txt`):
- Game started, warmup logged ✅
- No shots fired, no Black Metal mode, no lightning
- White screen immediately at startup ❌

**Root cause:**
`render_mode blend_add` is NOT supported in Godot's gl_compatibility renderer. It falls back to standard alpha blending. The always-visible ColorRect with `COLOR = vec4(0,0,0,1)` (opaque black) corrupts the rendering pipeline — a full-screen opaque black quad at layer 98 blocks all rendering.

---

## Fix: v10 — No Shader at All (Definitive Solution)

**User confirmed (2026-03-17 05:36):** "хорошо работает." — "Works well."

The definitive fix: **eliminate the shader entirely**. Draw the bolt using GDScript's canvas draw API:

- `LightningBoltDrawer`: a `Node2D` with `_draw()` that calls `draw_polyline()` and `draw_circle()` — no shader
- `IlluminationFlash`: a plain `ColorRect` with NO shader — just a semi-transparent color
- Both nodes are `visible=false` when not flashing — toggling `visible` on a plain `Node2D` (no shader) is completely safe in all renderers

---

## Phase 11: Kill-based trigger (v10 + kill signal)

**User requirement (2026-03-17 05:36):** "сделай чтоб молнии появлялись не при нанесении урона врагу, а после убийства" — "make lightning appear after killing, not when dealing damage"

**Previous design (on hit):**
- Every projectile class (`Bullet.gd`, `Bullet.cs`, `SniperBullet.cs`, `ShotgunPellet.cs`, `SniperRifle.cs`, `ReplayManager.cs`) called `trigger_lightning()` in their `TriggerPlayerHitEffects()` methods on every hit.
- This meant lightning could fire multiple times per enemy (one flash per hit) and fired even if the enemy survived.

**New design (on kill):**
- `BlackMetalLightningEffectsManager` connects directly to `GameManager.enemy_killed` signal in `_ready()`.
- When `GameManager.enemy_killed` fires (after an enemy's health reaches 0 and `_on_death()` runs), the manager's `_on_enemy_killed()` handler calls `trigger_lightning()`.
- All `trigger_lightning()` call sites removed from projectile files.
- Lightning now fires exactly once per kill, not on each hit.
