# Issue #199 - Fix Shotgun Mechanics

## Executive Summary

The shotgun weapon was added but has several mechanical issues that deviate from the intended design. This document analyzes the root causes and details the implemented solutions across multiple iterations.

## Issue Translation (Russian to English)

Original issue text:
> A shotgun was added, but it shoots and reloads incorrectly.

### Expected Behavior

**Reload Sequence:**
1. RMB drag down (open chamber)
2. MMB → RMB drag down (load shell, repeatable up to 8 times)
3. RMB drag up (close chamber)

**Firing Sequence:**
1. LMB (fire)
2. RMB drag up (eject shell)
3. RMB drag down (chamber next round)

**Additional Requirements:**
- No magazine interface (shotgun doesn't use magazines)
- Fire pellets in "cloud" pattern (not as a burst/sequential fire)
- Ricochet limited to 35 degrees max
- Pellet speed should match assault rifle bullets

## Timeline of Changes

### Phase 1 (Initial Fix)
- Created ShotgunPellet with 35° ricochet limit
- Added 8ms delay between pellet spawns for "swarm" effect
- Updated pellet speed to 2500.0
- Hidden magazine UI

### Phase 2 (User Feedback - Current)
User feedback from PR #201 comment (2026-01-22T02:15:05Z):
> "сейчас дробь вылетает как очередь, а должна как облако дроби"
> (Currently pellets fire like a burst, but should fire as a cloud of pellets)

The 8ms delay approach was incorrect - pellets should spawn **simultaneously** with **spatial distribution**, not with temporal delays.

## Root Cause Analysis

### Issue 1: Pellet Firing Pattern (Updated)
**Original Problem:** Pellets spawn as a "flat wall" pattern
**Phase 1 Fix:** Added 8ms delays between pellets → Created burst fire effect
**Phase 2 Fix:** Removed delays, added spatial offsets for cloud pattern

The key insight is that a "cloud" pattern means:
- All pellets fire at the **same time**
- Some pellets are slightly **ahead** or **behind** others due to **spawn position offsets**
- NOT due to temporal delays which create burst fire

### Issue 2: Pump-Action Not Implemented
**Problem:** Shotgun fired like a semi-automatic weapon
**Root Cause:** Auto-cycling after each shot
**Fix:** Implemented manual pump-action with RMB drag gestures

### Issue 3: Shell-by-Shell Reload Not Implemented
**Problem:** Used magazine-based reload inherited from BaseWeapon
**Root Cause:** No tube magazine implementation
**Fix:** Added `ShotgunReloadState` machine with gesture-based loading

## Implemented Solutions (Phase 2)

### Solution 1: Cloud Pattern Firing
Replaced temporal delays with spatial offsets:

```csharp
// NEW: Cloud pattern with spatial distribution
private void FirePelletsAsCloud(Vector2 fireDirection, int pelletCount,
    float spreadRadians, float halfSpread, PackedScene projectileScene)
{
    for (int i = 0; i < pelletCount; i++)
    {
        // Calculate angular spread
        float baseAngle = CalculateSpreadAngle(i, pelletCount, halfSpread, spreadRadians);

        // Calculate spatial offset for cloud effect (bidirectional)
        float spawnOffset = (float)GD.RandRange(-MaxSpawnOffset, MaxSpawnOffset);

        SpawnPelletWithOffset(pelletDirection, spawnOffset, projectileScene);
    }
}
```

Key change: `MaxSpawnOffset = 15.0f` pixels, applied along the fire direction.

### Solution 2: Manual Pump-Action Cycling
Implemented `ShotgunActionState` machine:
- `Ready` → Can fire
- `NeedsPumpUp` → RMB drag up required (eject shell)
- `NeedsPumpDown` → RMB drag down required (chamber next round)

```csharp
// After firing:
ActionState = ShotgunActionState.NeedsPumpUp;
// Player must: RMB drag up → RMB drag down → Ready
```

### Solution 3: Shell-by-Shell Reload
Implemented `ShotgunReloadState` machine:
- `NotReloading` → Normal operation
- `WaitingToOpen` → RMB drag down to open action
- `Loading` → MMB + RMB drag down to load shell (repeat up to 8x)
- `WaitingToClose` → RMB drag up to close action

```csharp
// Reload sequence:
// 1. RMB drag down → WaitingToOpen → Loading
// 2. MMB + RMB drag down → Load one shell (repeat)
// 3. RMB drag up → Complete reload
```

### Solution 4: Tube Magazine System
Added tube magazine properties:
- `ShellsInTube` - Current shell count
- `TubeMagazineCapacity = 8` - Maximum shells
- Separate from BaseWeapon's magazine system

## Data Analysis

### Log Files Analyzed

| Log File | Timestamp | Key Observations |
|----------|-----------|------------------|
| game_log_20260122_042545.txt | Initial testing | 6-12 pellets/shot, simultaneous spawn, high-angle ricochets |
| game_log_20260122_043643.txt | Follow-up | Confirmed issues |
| game_log_20260122_050729.txt | PR feedback | Shows burst-fire behavior with 8ms delays |
| game_log_20260122_051319.txt | PR feedback | Additional testing |
| game_log_20260122_051523.txt | PR feedback | Final pre-fix state |

### Key Findings from Latest Logs
1. Shotgun fires are being logged correctly
2. Sound propagation working (range=1469)
3. Tutorial level detection working
4. Weapon selection working

## Files Modified

### New Files:
1. `Scripts/Projectiles/ShotgunPellet.cs` - Pellet with 35° ricochet limit
2. `scenes/projectiles/csharp/ShotgunPellet.tscn` - Pellet scene
3. `docs/case-studies/issue-199/analysis.md` - This analysis
4. `docs/case-studies/issue-199/game_log_*.txt` - 5 log files

### Modified Files (Phase 2):
1. `Scripts/Weapons/Shotgun.cs`:
   - Replaced `FirePelletsWithDelay()` with `FirePelletsAsCloud()`
   - Changed `PelletSpawnDelay` to `MaxSpawnOffset`
   - Added `ShotgunActionState` for pump-action
   - Added `ShotgunReloadState` for shell loading
   - Added gesture detection for RMB drag
   - Added `ShellsInTube` and `TubeMagazineCapacity`
   - Added audio feedback for pump/reload actions

## Control Summary

### Shooting (Pump-Action)
| Action | Input |
|--------|-------|
| Fire | LMB |
| Pump Up (eject shell) | RMB drag up |
| Pump Down (chamber) | RMB drag down |

### Reloading (Shell-by-Shell)
| Action | Input |
|--------|-------|
| Open action | RMB drag down (when ready, tube not full) |
| Load shell | MMB + RMB drag down |
| Close action | RMB drag up |

## References

- [Shotgun Pellet Ricochet Study](https://store.astm.org/jfs11425j.html)
- [2024 Ricochet Research](https://www.sciencedirect.com/science/article/abs/pii/S1355030624000704)
- Previous research: `docs/case-studies/issue-194/research-shotgun-mechanics.md`
- Player.cs grenade system (reference for drag gesture implementation)
