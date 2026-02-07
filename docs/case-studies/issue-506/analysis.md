# Case Study: Issue #506 - Casings Scattered Through Obstacles During Explosions

## Problem Statement

**Issue**: Casings behind walls/obstacles are pushed by explosion shockwave when they should not be.
**Original report (Russian)**: "гильзы не должны отталкиваться, если их не задевает ударная волна (если перекрыты препятствием)"
**Translation**: "casings should not be pushed if the shockwave does not touch them (if blocked by an obstacle)"

## Timeline of Events

### Phase 1: Initial Fix Attempt (2026-02-06)

1. **GDScript fix applied** to `scripts/projectiles/grenade_base.gd` in `_scatter_casings()`:
   - Added `PhysicsRayQueryParameters2D` line-of-sight check with `collision_mask = 4` (obstacles)
   - Casings behind obstacles are skipped (no impulse applied)
   - Commit `23ff65e`: "fix: block casing scatter through obstacles during explosions"

2. **Tests added** to `tests/unit/test_casing_explosion_reaction.gd`:
   - `test_casing_behind_wall_not_pushed`
   - `test_casing_not_behind_wall_still_pushed`
   - `test_some_casings_blocked_some_not`
   - `test_casing_in_proximity_zone_behind_wall_not_pushed`

### Phase 2: User Report - Fix Not Working (2026-02-06 18:48)

User tested the exported build and reported: **"гильзы всё ещё отбрасываются за препятствиями"** (casings are still being scattered behind obstacles), with attached game log `game_log_20260206_184851.txt`.

## Root Cause Analysis

### Dual Explosion Architecture

This project has a **dual-language architecture** where both GDScript and C# components handle grenade explosions:

| Component | Language | File | Purpose |
|-----------|----------|------|---------|
| `GrenadeBase` | GDScript | `scripts/projectiles/grenade_base.gd` | Primary explosion logic |
| `GrenadeTimer` | C# | `Scripts/Projectiles/GrenadeTimer.cs` | "Reliable fallback" for exported builds |

The C# `GrenadeTimer` was introduced as part of **Issue #432** because "GDScript methods called via C# `Call()` silently fail in exported builds, causing grenades to fly infinitely without exploding." It provides a separate, independent explosion pipeline.

### The Bug: Both Paths Execute, Only One Was Fixed

When a grenade explodes, **both** the GDScript and C# paths execute:

```
Explosion Event
    ├── GDScript: GrenadeBase._explode()
    │   └── _on_explode() → _scatter_casings()  ← HAS LOS check (Issue #506 fix)
    │
    └── C#: GrenadeTimer.Explode()
        └── ScatterCasings()                     ← MISSING LOS check!
```

### Evidence from Game Log

The game log shows both systems firing for each explosion:

```
[18:49:07] [GrenadeBase] EXPLODED at (227.8735, 1832.372)!
[18:49:07] [GrenadeBase] Scattered 12 casings (lethal zone) + 0 casings (proximity)
[18:49:07] [GrenadeTimer] EXPLODED at (227.87354, 1832.372)!
[18:49:07] [GrenadeTimer] Scattered 20 casings        ← MORE casings (no LOS filter!)
```

```
[18:49:35] [GrenadeBase] EXPLODED at (151.3239, 1791.56)!
[18:49:35] [GrenadeBase] Scattered 20 casings (lethal zone) + 0 casings (proximity)
[18:49:35] [GrenadeTimer] EXPLODED at (151.32385, 1791.5602)!
[18:49:35] [GrenadeTimer] Scattered 30 casings        ← 50% MORE casings (no LOS filter!)
```

The `GrenadeTimer` consistently scatters **more casings** than `GrenadeBase` for the same explosion, because `GrenadeTimer` pushes ALL casings in range including those behind obstacles, while `GrenadeBase` correctly filters them with LOS.

### Why the Initial Fix Appeared Incomplete

The initial fix only modified the GDScript `_scatter_casings()` in `grenade_base.gd`. However:

1. The C# `GrenadeTimer.ScatterCasings()` executes **after** the GDScript version
2. It re-applies impulse to ALL casings in range, including those the GDScript version correctly skipped
3. The C# version does not check line of sight at all
4. Net result: every casing gets pushed regardless of obstacles (the C# impulse overwrites/adds to any filtering done by GDScript)

### Irony: The LOS Method Already Existed

The C# `GrenadeTimer.cs` already had a `HasLineOfSightTo()` method (line 515) that uses the exact same raycast approach (`collision_mask = 4`, obstacles only). This method was being used for **enemy damage** and **flashbang effects** (Issues #469) but was simply never called in `ScatterCasings()`.

## The Fix

### What Was Changed

**File: `Scripts/Projectiles/GrenadeTimer.cs`** - `ScatterCasings()` method

Added a single line-of-sight check before applying impulse, using the existing `HasLineOfSightTo()` method:

```csharp
// Issue #506: Check line of sight - obstacles block the shockwave
if (!HasLineOfSightTo(position, casingBody.GlobalPosition))
    continue;
```

This is consistent with how the same file already checks LOS for:
- Frag explosion damage (line 367)
- Player damage (line 385)
- Flashbang effects on enemies (line 419)
- Flashbang effects on player (line 437)

### Both Code Paths Now Protected

| Code Path | File | LOS Check |
|-----------|------|-----------|
| GDScript `_scatter_casings()` | `grenade_base.gd:592-602` | `space_state.intersect_ray()` with `collision_mask = 4` |
| C# `ScatterCasings()` | `GrenadeTimer.cs:831-833` | `HasLineOfSightTo()` with `CollisionMask = 4` |

## Lessons Learned

1. **Dual-language architectures require synchronized fixes**: When both GDScript and C# implement the same behavior, bug fixes must be applied to BOTH implementations. A fix in one language alone is insufficient.

2. **The "reliable fallback" pattern creates hidden duplication**: The C# `GrenadeTimer` was meant as a reliability backup, but it created a parallel execution path that must be maintained in sync with the GDScript version.

3. **Log analysis reveals execution patterns**: The game log clearly showed both `[GrenadeBase]` and `[GrenadeTimer]` entries for each explosion, with different scatter counts, making the root cause diagnosable from logs alone.

4. **Existing utilities should be reused**: The `HasLineOfSightTo()` method was already present and tested in the C# code for enemy damage. The bug was simply that it wasn't called for casing scatter.

## Files Modified

| File | Change |
|------|--------|
| `scripts/projectiles/grenade_base.gd` | Added LOS raycast in `_scatter_casings()` (initial fix) |
| `Scripts/Projectiles/GrenadeTimer.cs` | Added `HasLineOfSightTo()` check in `ScatterCasings()` (root cause fix) |
| `tests/unit/test_casing_explosion_reaction.gd` | Added 4 obstacle-blocking test cases |

## References

- [Issue #506](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/506) - Original bug report
- [Issue #432](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/432) - Original casing scatter feature + C# GrenadeTimer introduction
- [Issue #469](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/469) - Flashbang/explosion LOS for enemies and player
- [Godot C# Export Issues (godot#92630)](https://github.com/godotengine/godot/issues/92630) - Context for why dual GDScript/C# architecture exists
