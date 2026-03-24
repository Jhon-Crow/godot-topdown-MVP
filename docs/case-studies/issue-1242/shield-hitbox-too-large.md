# Case Study: Shield Hitbox Intercepting Side Hits (Issue #1242)

## Problem Statement

Player reported (2026-03-23) that the SWAT shield enemy's hitbox is too large,
causing it to intercept bullets aimed at the enemy's side/body. The shield
should only block frontal hits, but side shots were also being absorbed.

**User feedback (Russian):** "сделай хитбокс щита меньше (сейчас он перехватывает
попадания сбоку по телу врага)" — "Make the shield hitbox smaller (currently it
intercepts side hits to the enemy's body)."

## Evidence from Game Logs

Analyzed `game_log_20260323_084115.txt` (attached by reporter):
- 34 shield absorption events in a single play session
- Shield absorbed 1 dmg per hit consistently (M16 rounds)
- No shield break events logged — shield was absorbing everything before body
  could take damage, suggesting the hitbox was catching too many hits

## Root Cause Analysis

**Two independent mechanisms** were both too permissive:

### 1. Collision Polygon Too Wide (Primary Cause)

The shield's `CollisionPolygon2D` had a Y-span of **±15 pixels** (30px total),
positioned at X offset +18 from the enemy center. The enemy body is a circle
with **radius 24px**.

```
Enemy body (top-down):   Shield collision (before fix):
     ___                      |
   /     \                    |  Y: -15 to +15
  |   O   |  radius=24      >|< at X offset 18
   \ ___ /                    |
                              |
```

The shield extended from Y=-15 to Y=+15, covering a large portion of the
enemy's frontal arc. Bullets aimed at the body's side (near Y=±15..24) would
clip the shield collision polygon instead of passing through to the body.

### 2. Direction Fallback Too Broad (Secondary Cause)

When a bullet hit the enemy's body `HitArea` (not the shield), a direction-based
fallback check existed in `enemy.gd:4199`:

```gdscript
# BEFORE (too broad — 180° hemisphere):
Vector2.from_angle(_enemy_model.global_rotation).dot(-hit_direction.normalized()) > 0.0
```

A dot product threshold of `> 0.0` means **any hit from the front 180°** was
intercepted — including shots at nearly 90° (perpendicular/side). This is the
"safety net" for when Godot's Area2D signals fire in non-deterministic order,
but it was far too aggressive.

## Fix Applied

### Collision polygon reduced (±15 → ±11)
- Body polygon: Y from ±14 → ±10
- Frame polygon: Y from ±15 → ±11
- Collision polygon: Y from ±15 → ±11
- Viewport window: Y from ±5 → ±4

This shrinks the shield to cover only the direct frontal area, leaving the
enemy's sides exposed for flanking shots.

### Direction fallback tightened (dot > 0.0 → dot > 0.5)
```gdscript
# AFTER (~60° cone from front):
Vector2.from_angle(_enemy_model.global_rotation).dot(-hit_direction.normalized()) > 0.5
```

`dot > 0.5` corresponds to ≈60° cone (±30° from facing direction). Only hits
arriving nearly head-on trigger the fallback. Side shots (60°–180°) now always
deal body damage.

## Files Changed

- `scripts/components/enemy_shield_component.gd` — reduced all polygon sizes
- `scripts/objects/enemy.gd:4199` — tightened direction fallback threshold

## Verification

The fix can be verified by:
1. Shooting the shield enemy from the side (~90° to facing) — bullets should
   deal body damage, not be absorbed by shield
2. Shooting from the front — bullets should still be blocked by shield
3. Flanking should be noticeably more effective with the smaller hitbox

## Attached Logs

- `game_log_20260323_084115.txt` — session where issue was reported
- `game_log_20260323_074545.txt` — earlier session for comparison
- `game_log_20260323_065630.txt` — earlier session
- `game_log_20260323_065400.txt` — earlier session
