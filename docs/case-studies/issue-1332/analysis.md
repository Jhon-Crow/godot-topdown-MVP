# Case Study: Issue #1332 — Revolver Bullet Homing (Aim Assist)

## Timeline

| Date | Event |
|------|-------|
| 2026-03-22 | Issue #1332 opened: "добавь небольшое наведение пули на врага" (add slight bullet homing toward enemies) |
| 2026-03-22 | Initial implementation: weak aim-line homing at 4 rad/s steer speed added to Revolver.cs and Bullet.cs |
| 2026-03-22 | PR #1333 created and marked ready |
| 2026-03-24 | Owner feedback (round 1): requested verification of homing, stronger effect, and gameplay menu toggle |
| 2026-03-24 | Steer speed increased to 12 rad/s, gameplay menu toggle added |
| 2026-03-24 | Owner feedback (round 2): "похоже асист не работает" — aim assist still not working |
| 2026-03-24 | **Real root cause found**: C#/GDScript type mismatch — homing never applied to GDScript bullets |

## Data Sources

- `game_log_20260324_085906.txt` — Game log from owner's first test session
- `game_log_20260324_093450.txt` — Game log from owner's second test session (confirming assist still broken)
- Source code: `Scripts/Projectiles/Bullet.cs` (C#), `scripts/projectiles/bullet.gd` (GDScript), `Scripts/Weapons/Revolver.cs`

## Analysis of Game Logs

### Environment
- OS: Windows
- Engine: Godot 4.3-stable
- Difficulty: Hard
- Weapon: Revolver (RSh-12)

### Findings from Second Log (game_log_20260324_093450.txt)

1. GameplaySettings initialized correctly: `revolver_aim_assist: true`
2. Multiple revolver shots fired — no homing behavior observed by the player
3. No homing debug output — confirms homing was never activated on the bullets

## Root Cause Analysis

### The Real Bug: C#/GDScript Type Mismatch

The revolver bullet scene (`scenes/projectiles/Bullet12p7mm.tscn`) uses **GDScript** (`scripts/projectiles/bullet.gd`), not the C# `Bullet.cs` class. Both implement the same homing interface but are separate types.

In `Revolver.SpawnBullet()`, the code searched for the just-spawned bullet using:

```csharp
if (children[i] is GodotTopDownTemplate.Projectiles.Bullet bullet && !bullet.HomingEnabled)
```

This C# `is` type check **always fails** for GDScript bullets because they are `Area2D` nodes with a GDScript attached — not instances of the C# `Bullet` class. The homing code was never reached.

Interestingly, `BaseWeapon.SpawnBullet()` already handled this correctly for the player homing buff — it has a GDScript fallback using `HasMethod("enable_homing_with_aim_line")` and `Call()`. But the Revolver override only had the C# path.

### Why Previous Analysis Was Wrong

The first analysis concluded the homing was "too weak to notice" (4 rad/s). In reality, the homing was **never applied at all**. The steer speed increase to 12 rad/s was also ineffective for the same reason.

## Solution

The fix adds GDScript bullet support to `Revolver.SpawnBullet()`:

1. **C# bullet path**: Uses direct property access (`csBullet.EnableHomingWithAimLine(...)`) — unchanged
2. **GDScript bullet path** (new): Detects `Area2D` nodes with `enable_homing_with_aim_line` method, sets `homing_steer_speed` property, then calls the method via `Call()`

This mirrors the pattern already used in `BaseWeapon.SpawnBullet()` for the full homing buff.

## Comparison: Steer Speed Values

| Value | Effect | Use Case |
|-------|--------|----------|
| 4 rad/s | Gentle nudge | Original design (never actually applied) |
| 12 rad/s | Noticeable correction, still feels natural | Revolver aim assist |
| 50 rad/s | Sharp tracking, guided missile feel | Player homing buff |

## Lessons Learned

1. **C#/GDScript interop requires explicit handling** — `is` type checks in C# cannot match GDScript types. Always provide a `HasMethod()`/`Call()` fallback path.
2. **Silent failures are dangerous** — the homing activation had no logging when `DebugHoming = false`, making it impossible to tell from logs whether homing was applied or just ineffective.
3. **Test with the actual bullet scene** — the bug would have been caught immediately if testing verified that `Bullet12p7mm.tscn` (GDScript) received the homing call.
