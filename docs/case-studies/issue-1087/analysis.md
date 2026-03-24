# Issue #1087: Update Breaching Charges — Case Study

## Issue Summary

**Title:** update Подрывные заряды (Update Breaching Charges)
**Requested by:** Jhon-Crow
**Comment:** "для начала реализуй первые 2 пункта" (First implement the first 2 items)

## Requirements from Issue

The issue references PR #1044 (original breaching charges implementation) and lists these updates:

1. **Sound of explosion should be the same as F-1 grenade** — деtonation sound = `взрыв оборонительной гранаты.wav`
2. **Explosion should be directional toward the wall** (like a flashlight beam but wider sector)
3. Model of explosives should be more realistic (image provided)
4. Add small red glow around placed charge
5. Add dust cloud / wall collapse animation at the breach point
6. Long thin walls currently disappear completely — should create a passage instead

**Comment says to implement only items 1 and 2 first.**

## Current Implementation Analysis

### File: `scripts/effects/breaching_charges_effect.gd`

**Current detonation sound behavior (item 1):**
- Uses `DETONATE_SOUND_PATH = "res://assets/audio/breaching_charge_detonate.wav"`
- This file does NOT exist in `assets/audio/` directory
- Falls back to silence (no sound plays)
- The F-1 grenade uses `play_defensive_grenade_explosion()` via AudioManager

**Current explosion direction behavior (item 2):**
- `_spawn_explosion_effect()` spawns `ExplosionFlash.tscn`
- `_apply_cone_direction()` rotates the effect node and narrows particle spread to 45°
- The particle process material has `spread = 180.0` initially (omnidirectional)
- The cone is applied by: rotating effect node + setting `spread = 45.0`
- The issue asks for a wider sector, more like a flashlight beam but wider

**Problem with current direction (item 2):**
- The `ParticleProcessMaterial` is a shared resource — modifying it directly changes ALL instances of ExplosionFlash
- The code creates a duplicate of the shared material but doesn't explicitly call `.duplicate()`
- `spread = 45°` creates a 90° total cone (±45° from forward direction)
- The issue requests: "как луч фонарика, но сектор шире" = wider than flashlight, so perhaps 90°-120° spread

## Solution Design

### Item 1: F-1 Grenade Sound

Replace the custom WAV file reference with a call to `AudioManager.play_defensive_grenade_explosion()`.

**Implementation:**
- In `_play_detonate_sound()`, use AudioManager if available (same as F-1/defensive grenade)
- Fall back to direct stream player if AudioManager not present
- Use `"res://assets/audio/взрыв оборонительной гранаты.wav"` as the sound path constant

### Item 2: Directional Explosion (Cone Toward Wall)

The explosion should be directional:
- Like a flashlight beam = narrow cone pointing toward wall
- "But wider sector" = sector angle ~90°-120° (±45° to ±60° from wall direction)

**Current issues to fix:**
1. The `ParticleProcessMaterial` is shared — must call `.duplicate()` before modifying
2. The spread should be set to ~90° (wider than current 45°, but still directional)
3. Need to ensure the direction property uses local space (Vector3(1,0,0) when rotated)

**Better implementation:**
- Duplicate the particle material before modifying
- Set `spread = 90.0` for a 180° total cone (wider sector as requested)
- Use `direction = Vector3(1, 0, 0)` in local space (effect node rotated toward wall)
- Increase emission velocity for more dramatic effect

## Existing Resources Used

- `"res://assets/audio/взрыв оборонительной гранаты.wav"` — F-1 explosion sound (exists)
- `AudioManager.play_defensive_grenade_explosion(position)` — plays the F-1 sound
- `"res://scenes/effects/ExplosionFlash.tscn"` — existing explosion visual effect
- `_charge_wall_direction` — already computed direction from player toward wall

## Files to Modify

1. `scripts/effects/breaching_charges_effect.gd` — main implementation
2. `tests/unit/test_breaching_charges_effect.gd` — update/add tests

---

## Implementation Summary (Items 2 & 5 — follow-up comment)

The owner's follow-up comments requested:
- **Item 2** (realistic model) + **Item 5** (passage in thin walls) — implemented in PR #1089

### Item 2 — Realistic Placed Charge Marker

**Problem:** The original `_spawn_placed_charge_marker()` used the existing
`breaching_charges_icon.png` (a very simple brown rectangle with a red dot)
as the marker sprite. The issue requests a more realistic visual.

**Solution:**
- Replaced the single `Sprite2D` with a composite `Node2D` containing multiple `ColorRect` children:
  - Sandy beige body (C4-like block)
  - Dark grey housing/frame
  - Black strap across the middle
  - Metallic detonator cylinder
  - Blinking red LED indicator (animated via `Tween`)
- The LED blinks at ~0.5 s intervals using a looping `Tween` on `modulate.a`
- The root node is rotated so the charge faces out from the wall

### Item 5 — Passage in Thin Walls (Root Cause)

**Root cause:** `_open_wall_passage()` disabled ALL `CollisionShape2D` children
and hid ALL `CanvasItem` children of the hit wall node. This caused the entire
wall `StaticBody2D` to become invisible and passable — even very long walls would
disappear completely, which is unrealistic.

**Solution — passage carving algorithm:**
1. Find the first `CollisionShape2D` with a `RectangleShape2D` (the wall's main shape)
2. Convert the breach world position to the wall's local coordinate space
3. Determine orientation (horizontal = width ≥ height, vertical = height > width)
4. Clamp the breach centre so the passage never exceeds the wall boundary
5. Disable the original shape; add two new `CollisionShape2D` children for the remaining
   left/right (or top/bottom) segments
6. Update visuals: hide the original `ColorRect`; add two replacement `ColorRect` nodes
   sized to match the surviving wall segments, reading the original wall colour
7. If both surviving segments are < 8 px (wall too short to split), fall back to
   removing the wall entirely — preserving the original behaviour for small walls
8. Non-`RectangleShape2D` walls (custom shapes) fall back to the old full-disable path

**Constant added:** `BREACH_PASSAGE_WIDTH = 56.0` px — wide enough for a character
to walk through, smaller than a typical wall segment.
