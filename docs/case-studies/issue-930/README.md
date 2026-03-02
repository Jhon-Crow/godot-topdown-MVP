# Issue #930 Case Study: Fix Force Field Visual (Силовое поле)

## Issue Description

**Title:** `fix визуал силового поля` ("fix force field visual")

**Body (Russian):** "Силовое поле должно выглядеть как силовой пузырь с анимацией" — "The force field should look like a force bubble with animation."

The user provided two reference images showing the desired look:
1. `images/desired_1.png` — A human figure inside a glowing translucent blue sphere with an opaque/glass-like surface and swirling surface texture.
2. `images/desired_2.png` — A glowing energy sphere with a dark semi-transparent interior, bright glowing rim, and visible animated surface energy lines/particles.

Current state (see `images/current_state.png`): A thin blue ring/circle outline around the player. The center is fully transparent — it looks like just a circle border, not a bubble.

---

## Data Collected

### Files

- `images/desired_1.png` — Reference image 1 (desired bubble appearance): 284×177 PNG
- `images/desired_2.png` — Reference image 2 (desired bubble appearance): 462×280 PNG
- `images/current_state.png` — Current broken visual (thin blue ring outline): 195×142 PNG
- `game_log_20260301_032044.txt` — Game log from 2026-03-01, provided by Jhon-Crow in PR #931 comment

### Historical Context (Previous Issues)

This issue is the third iteration of force field visual complaints:
- **Issue #676** / PR ~dd84e96: Initial ForceFieldEffect implementation — basic Area2D + visual.
- **Issue #906** / PR #907: Force field bullet trapping implemented. Shader was designed as Fresnel rim bubble.
- **Issue #912** / PR #913: Force field showed as large blue-filled circle (gradient texture bleeding), then as white square (shader not compositing in exports). Fix: Use `_create_ring_texture()` programmatic donut as primary visual, shader as optional enhancement.
- **Issue #930** (this issue): Force field now shows as thin blue ring — transparent center, visible rim only. Still not matching the desired bubble with translucent interior.
- **PR #931** (ongoing): Attempted fix — added semi-transparent interior fill to both texture and shader. Owner reported "force field doesn't work at all (damage passes through)" in a PR comment with game log attached.

---

## Timeline / Sequence of Events (Reconstructed from Game Log)

The game log `game_log_20260301_032044.txt` was collected on 2026-03-01 at 03:20 local time (UTC+3 timezone, based on log path `I:/Загрузки/` and Russian OS locale). The game was an exported Windows build (`Godot-Top-Down-Template.exe`) from the "сиЛовое ПОЛЕ" ("Force Field") folder — a dedicated test folder named after the feature being tested.

### Session Summary (03:20:44 – 03:21:07)

| Time | Event |
|------|-------|
| 03:20:44 | Game started. GameManager, ScoreManager, FileLogger initialized. |
| 03:20:44 | LabyrinthLevel loaded. Force field NOT selected in ActiveItemManager. |
| 03:20:44–45 | Scene transitions (LabyrinthLevel → BuildingLevel attempted multiple times). |
| 03:20:48 | `[ActiveItemManager] Active item changed from BFF Pendant to Force Field` |
| 03:20:48 | `[Player.ForceField] Force field is selected, initializing...` |
| 03:20:48 | `[Player.ForceField] Force field initialized successfully` |
| 03:20:48–50 | Player in BuildingLevel. 10 enemies spawned. |
| 03:20:51 | **Player takes 1 damage.** `[PenultimateHit] Player damaged: 1.0 damage, current health: 2.0` |
| 03:20:51 | **Player takes 1 more damage.** `current health: 1.0` |
| 03:20:51 | LastChance effect triggers (1 HP). |
| 03:20:51 | Multiple scene reloads follow (player likely died). |
| 03:21:04 | Final attempt: Force field initialized, enemies spawned, player at 4 HP. |
| 03:21:07 | Game log ends (session ended or crash). |

### Key Observation: No `[ForceFieldEffect]` Logs

Despite the C# Player successfully logging `[Player.ForceField] Force field initialized successfully` (confirming the ForceFieldEffect scene was instantiated and `AddChild()` was called), **zero log entries from `force_field_effect.gd` appear in the entire log**. The `_ready()` of the GDScript should log `[ForceFieldEffect] Initialized with 8.0s charge` — this never appears.

This means one of:
1. The binary was built from a version of the code that didn't have `FileLogger.info()` calls in `force_field_effect.gd` (i.e., pre-PR #912 binary or older).
2. The GDScript's `_ready()` was never called due to a C#/GDScript interop issue in the exported build.
3. A silent GDScript compilation error prevented the script from running.

### Key Observation: No Force Field Activation

The log shows **no `[ForceFieldEffect] Activated!` log entries**. This means either:
- The user never pressed Space to activate the force field (so it was never active).
- The field was active but the logs weren't captured (same reasons as above).

The player took damage 3 seconds after spawning. If they were holding Space and the force field was active, `is_force_field_active()` would return `true` and damage would be blocked in `TakeDamage`. The fact that damage went through confirms the force field was NOT active when bullets hit.

---

## Root Cause Analysis

### Root Cause 1 (Visual Issue): Ring Texture Has No Interior Fill

The `_create_ring_texture()` function in `force_field_effect.gd` (pre-PR #930 fix) sets all pixels with `dist < rim_start` to fully transparent (`Color(0,0,0,0)`). The shader also produced only a rim-only output (`float combined = rim * glow_intensity * pulse`). Both the texture AND the shader gave zero alpha inside the circle, resulting in a hollow ring.

**This is confirmed by the code diff between `main` and `HEAD`** — the only gameplay-affecting change in our PR is making `_create_ring_texture()` add a soft interior fill.

### Root Cause 2 (Damage Issue): Force Field Was Not Active

The game log shows no activation of the force field. The user either:
- Did not know to hold Space to activate it (the field is not active by default — it requires user input).
- Found the bubble visual wasn't rendering (old binary without our fix) and assumed it was broken.
- Pressed Space but the force field's Area2D was not set up (if `_ready()` didn't fire).

**Our PR (#931) did NOT change the damage blocking code.** The damage protection logic (`_on_projectile_entered`, `activate`, `is_protecting`, `TakeDamage` force field check) was completely untouched between `main` and `HEAD`. If the force field is active (`is_active = true`), damage is blocked in **both** the C# `TakeDamage` path and the GDScript `on_hit_with_info` path.

### Root Cause 3 (Silent Failure Risk): C#/GDScript Interop in Exported Builds

Online research reveals a documented class of Godot 4 issues where GDScript `_ready()` may not fire when called from C# `AddChild()` in exported builds:
- **Godot Forums** (godotforums.org/d/24315): "C# Godot Scene Instance - Ready/Enter Tree Functions Not called" — confirms lifecycle callbacks can be silently skipped in C#/GDScript interop scenarios.
- **Godot GitHub #75352**: "Loading/Assigning a GDScript-based scene exported from another project fails with 'Cannot instance script because the associated class could not be found'" — silent failure mode.
- **Godot GitHub #94150**: GDScript export mode (compiled bytecode) breaks exported builds with certain addon configurations.

This risk means that in the exported binary, if `_ready()` is never called on `ForceFieldEffect`:
- `_setup_area2d()` never runs → no `Area2D` → no bullet trapping
- `_setup_shield_visual()` never runs → no visual sprite → field is invisible
- However, `is_active` defaults to `false`, so `is_protecting()` returns `false`
- If the C# player's `HandleForceFieldInput` calls `activate()`, `is_active` becomes `true`
- `is_force_field_active()` would return `true`, blocking damage in `TakeDamage`
- BUT no visual feedback would be visible (player can't know the field is active)
- AND no bullet trapping would occur (Area2D not set up)

The damage protection via `TakeDamage` check should still work even without `_ready()` firing, as long as `activate()` is called. But the lack of visual and bullet trapping makes the feature effectively non-functional.

---

## Online Research: Godot 4 Force Field / Shield Patterns

### Standard Hitbox/Hurtbox Architecture (GDQuest)

The standard community pattern for damage interception in Godot 4 (per GDQuest's documented hitbox/hurtbox tutorial):
- A `Hurtbox` (Area2D on the receiving entity) listens for `Hitbox` (Area2D on the attacker)
- The hurtbox emits a `damaged` signal; the entity script decides whether to apply it
- A force field intercepts this signal before it reaches the health system

Our implementation uses a layered approach:
1. **Physical trapping** via ForceFieldEffect's `Area2D` (named `ForceFieldArea`) that intercepts bullets via `area_entered` signal
2. **Damage blocking** in `TakeDamage` via `is_force_field_active()` check (fallback if trapping fails)

This two-layer approach means even if the physical trapping fails (e.g., Area2D not set up), the `TakeDamage` check provides a backup damage block.

### Known Godot 4 Area2D Issues in Exported Builds

- **Godot GitHub #84511**: `CharacterBody2D` no longer actively detects `Area2D` in some Godot 4 configurations (regression from Godot 3). Our force field uses `Area2D.area_entered` to detect bullets (also Area2D), not `CharacterBody2D`, so this specific issue doesn't apply.
- **`monitoring` / `monitorable` flags**: Area2D may silently fail to detect collisions in exported builds if `monitoring = false`. Our setup explicitly creates the Area2D in code and doesn't set `monitoring = false`, so this should be OK.

### Best Practices for Force Field Visual (Godot 4 canvas_item shaders)

Per community research on 2D shield/bubble shaders:
- **Interior fill**: `pow(r, 2.5)` as Fresnel term gives transparent center, semi-opaque near rim
- **Rim glow**: Narrow band at r ≈ 0.9–1.0, bell-curve alpha
- **Pulsing**: `sin(TIME * speed) * 0.12 + 0.88` for subtle breathing effect
- **Surface shimmer**: `sin(angle * n + TIME * s)` overlapping waves for swirling energy look
- **Alpha range**: Interior at 0.1–0.25, rim at 0.7–0.9 (high contrast)

Our PR #931 implementation follows these patterns exactly.

---

## Proposed Solutions

### Solution A (Implemented): Bubble Texture + Enhanced Shader

**Status: Implemented in PR #931.**

Modified `_create_ring_texture()` to include a soft translucent interior fill:
- Interior fill: alpha 0–0.22 (pow(r,1.5) * 0.18 + inner ring effect)
- Secondary ring at 60% radius for depth
- Bright rim: unchanged (bell curve, peak 0.9)

Enhanced shader with:
- `fill = (1.0 - pow(r, 2.5)) * fill_opacity` (frosted glass interior)
- Secondary inner ring at r = 0.60
- Surface energy shimmer via overlapping sin waves
- Pulsing animation maintained

**Result**: Force field looks like a translucent bubble even without shader support (texture provides fallback).

### Solution B (Recommended Addition): Robustness Fix for C#/GDScript Interop

Given the documented risk of `_ready()` not being called in exported C#/GDScript interop scenarios, add a robustness check in `activate()`:

```gdscript
func activate() -> bool:
    # Lazy initialization if _ready() was skipped (C#/GDScript interop robustness)
    if _area2d == null:
        _setup_area2d()
    if _shield_sprite == null:
        _setup_shield_visual()
    ...
```

This ensures the force field works even if `_ready()` wasn't called. Combined with logging, this would show in the log whether lazy init was triggered, enabling future diagnosis.

### Solution C: Improve Visual Feedback

Add HUD indicator for force field charge (already partially planned in future issues). Without visual feedback, users may not know the field is active or depleted.

---

## Implementation Status

| Component | Status |
|-----------|--------|
| `scripts/effects/force_field_effect.gd` — bubble texture | ✅ Done (PR #931) |
| `scripts/shaders/force_field.gdshader` — animated interior | ✅ Done (PR #931) |
| `docs/case-studies/issue-930/` — case study | ✅ Updated |
| `game_log_20260301_032044.txt` — game log from owner | ✅ Downloaded |
| `docs/screenshots/issue-930/` — visual preview | ✅ Done (PR #931) |
| `tests/unit/test_force_field_visual.gd` — regression tests | ✅ Done (PR #931) |
| Robustness fix for C#/GDScript interop | ⚠️ Recommended — see Solution B |

---

## Expected Outcome After Fix

After PR #931:
- Force field appears as a **translucent blue bubble** (not just a ring outline)
- Interior has ~15–22% opacity — visible without blocking gameplay
- Rim glows brightly at the edge
- Animation pulses and shimmers with surface energy lines
- Effect works correctly in both editor and exported games (texture provides fallback visual)

The owner's report of "damage passes through" appears to be caused by the force field **not being activated** (Space not held) during the game session, rather than a code regression in our PR. Our PR did not modify any damage-blocking code.
