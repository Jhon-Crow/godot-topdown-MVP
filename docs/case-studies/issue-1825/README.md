# Issue 1825 Case Study

## Summary

Issue: `овальная коричневая стена вокруг карты Замок снова стала проходимой (должна быть непроходимой). так же на карте Замок вспышки проходят сквозь стены.`

Issue URL: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1825

This case study collects the issue payload, attached runtime logs, and the follow-up PR feedback, then records the root causes identified in the local scene data.

## Collected Data

- `game_log_20260413_210446.txt`: original issue runtime log downloaded from the issue attachment
- `game_log_20260415_220259.txt`: follow-up PR comment runtime log downloaded from the PR attachment

## Timeline

- 2026-04-13 21:04:46 UTC: attached game log started on the reporter's Windows build.
- 2026-04-15 18:04:21 UTC: PR review feedback reported that Castle light/flash still passed through obstacles and that Beach small obstacles also leaked light.
- 2026-04-15: issue investigated in the repository branch `issue-1825-fefc5291893b`.

## Findings

- `scenes/levels/CastleLevel.tscn` already had obstacle collision for rectangular castle structures and the outer map boundary boxes.
- The visible oval brown castle perimeter was only a `Polygon2D` named `WallOvalTop`.
- Because `WallOvalTop` had no `StaticBody2D`/`CollisionShape2D`, the player could pass through that perimeter.
- Because it also had no `LightOccluder2D`, flash/light effects were not shadowed by that perimeter.
- The first fix added collider and occluder data to the Castle outer wall, but the occluder polygon was left open at the seam, which can leak shadows in Godot's 2D lighting.
- `scenes/levels/BeachLevel.tscn` had several small cover props with physics collision but no `LightOccluder2D`: `Rock2`, `Rock4`, `Rock6`, `Barrel1`, `Barrel2`, and `Barrel3`.
- `scripts/projectiles/flashbang_grenade.gd` already checks obstacle line of sight using collision layer `4`, so the remaining regressions still pointed back to missing or malformed scene occlusion geometry.

## Root Cause

The root cause was incomplete scene authoring, not a central flashlight/flashbang algorithm regression:

- On Castle, the outer perimeter initially lacked both collision and occlusion, and the later occluder polygon still had an open seam.
- On Beach, multiple small props blocked movement but were missing `LightOccluder2D`, so light and flash effects visually penetrated those objects.

## Fix Direction

- Add a `StaticBody2D` on collision layer `4` for the outer oval perimeter.
- Approximate the oval with multiple `SegmentShape2D` collision segments.
- Add a `LightOccluder2D` using the same perimeter polygon so point-light based flash effects are blocked by the wall.
- Close the Castle occluder polygon explicitly to remove the seam leak.
- Add `LightOccluder2D` nodes to all Beach small cover props that already have blocking collision.
- Add regression tests that assert the Castle and Beach scenes keep these occluders in place.
