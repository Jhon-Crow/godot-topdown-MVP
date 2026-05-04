# Case Study: Issue #1953 - RPG Rocket Is Not Shot Down By Player Fire

## Problem

Issue #1953 reports that the RPG rocket is not shot down by player bullets or shotgun pellets:

> сейчас ракета из рпг не сбивается пулями или дробью игрока.

The issue was opened on 2026-05-04. There were no issue comments at the time of analysis.

## Data Collected

- `issue.json` - issue title, body, author, timestamps, and labels.
- `issue-comments.json` - issue comments snapshot.
- `pr-1954.json` - prepared pull request metadata.
- `pr-1134-related.diff` - earlier fix adding rocket interception.
- `pr-1308-related.diff` - earlier fix making rockets explode when hit.

## Timeline

1. PR #599 added RPG enemies and rockets.
2. PR #1134 added support for shooting down rockets by giving `RpgRocket.tscn` projectile-layer masking and adding `on_hit` handling.
3. PR #1308 fixed a follow-up problem where rocket-side `area_entered` skipped projectile-layer areas and changed hits to trigger full explosions.
4. Issue #1953 reports the current gameplay regression: bullets and shotgun pellets still do not reliably shoot down rockets.

## Current Implementation

`scenes/projectiles/RpgRocket.tscn` uses `scripts/projectiles/bullet.gd` with `is_rpg_rocket = true`.

Important collision details:

- Bullets, shotgun pellets, and RPG rockets are `Area2D` projectiles on layer bit `16`.
- The rocket mask includes projectile bit `16`, so overlap signals can detect other projectile areas.
- The rocket also has a raycast fallback in `_physics_process`, but that raycast uses mask `39`, which covers player, enemies, obstacles, and targets. It intentionally does not cover projectile areas.

## Root Cause

The previous fixes relied on `Area2D.area_entered` to detect player bullets and pellets. That catches normal overlaps, but it is not reliable for small, fast projectile-vs-projectile interactions. Player bullets and shotgun pellets can pass across the rocket between physics ticks without producing a discrete overlap callback.

The rocket already solved this class of problem for bodies and walls by sweeping a ray from the previous rocket position to the current rocket position. Projectile interception did not have the same swept fallback.

## Fix

The rocket now performs a swept projectile check each physics frame after spawn immunity ends:

- It builds a capsule covering the segment from the rocket's previous position to its current position.
- It queries only projectile-layer `Area2D` objects.
- It ignores itself and other RPG rockets.
- It calls `on_hit()` for bullets, shotgun pellets, shrapnel, or similar projectile areas found in that swept path.

This preserves the prior `area_entered` behavior while adding a reliable fallback for fast player fire.

## Tests

`tests/unit/test_rpg_rocket_bullet_hit.gd` now includes Issue #1953 regression coverage for the swept geometry:

- A projectile crossing near the rocket path triggers a hit and explosion.
- A far projectile is ignored.
- Other RPG rockets are ignored to avoid mutual destruction.

## Related References

- PR #1134: `feat(#1133): allow shooting down RPG rocket`
- PR #1308: `fix(#1307): RPG rocket now explodes when hit by bullets`
- Godot 4 Area2D and physics shape queries are the relevant engine mechanics for the current fix.
