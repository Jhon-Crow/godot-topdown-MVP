# Issue 1825 Case Study

## Summary

Issue: `овальная коричневая стена вокруг карты Замок снова стала проходимой (должна быть непроходимой). так же на карте Замок вспышки проходят сквозь стены.`

Issue URL: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1825

This case study collects the issue payload and the attached runtime log, then records the root cause identified in the local scene data.

## Collected Data

- `data/issue.json`: issue metadata and body exported with `gh issue view --json`
- `logs/game_log_20260413_210446.txt`: attached runtime log downloaded from the issue

## Timeline

- 2026-04-13 21:04:46 UTC: attached game log started on the reporter's Windows build.
- 2026-04-15: issue investigated in the repository branch `issue-1825-fefc5291893b`.

## Findings

- `scenes/levels/CastleLevel.tscn` already had obstacle collision for rectangular castle structures and the outer map boundary boxes.
- The visible oval brown castle perimeter was only a `Polygon2D` named `WallOvalTop`.
- Because `WallOvalTop` had no `StaticBody2D`/`CollisionShape2D`, the player could pass through that perimeter.
- Because it also had no `LightOccluder2D`, flash/light effects were not shadowed by that perimeter.
- `scripts/projectiles/flashbang_grenade.gd` already checks obstacle line of sight using collision layer `4`, so the regression source was scene geometry, not flashbang logic.

## Root Cause

The Castle scene represented the outer oval wall as visuals only. Physics collision and light occlusion were missing for the same wall path, so both movement blocking and flashbang wall blocking failed at the same locations.

## Fix Direction

- Add a `StaticBody2D` on collision layer `4` for the outer oval perimeter.
- Approximate the oval with multiple `SegmentShape2D` collision segments.
- Add a `LightOccluder2D` using the same perimeter polygon so point-light based flash effects are blocked by the wall.
- Add a regression test that asserts the castle scene contains this collider/occluder setup.
