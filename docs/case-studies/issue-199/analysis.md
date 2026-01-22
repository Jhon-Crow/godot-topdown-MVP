# Issue #199 - Fix Shotgun Mechanics

## Executive Summary

The shotgun weapon was added but has several mechanical issues that deviate from the intended design. This document analyzes the root causes and details the implemented solutions across multiple iterations.

## Issue Translation (Russian to English)

Original issue text:
> A shotgun was added, but it shoots and reloads incorrectly.

### Expected Behavior (CORRECTED - Phase 3)

**Firing Sequence (Pump-Action):**
1. LMB (fire)
2. RMB drag down (extract spent shell)
3. RMB drag up (chamber next round)

**Reload Sequence (Shell-by-Shell):**
1. RMB drag up (open bolt)
2. MMB + RMB drag down (load shell, repeatable up to 8 times)
3. RMB drag down (close bolt and chamber round)

Note: After opening bolt, can close immediately with RMB drag down (without MMB) if shells are present.

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

### Phase 2 (Cloud Pattern + Pump-Action)
User feedback from PR #201 comment (2026-01-22T02:15:05Z):
> "сейчас дробь вылетает как очередь, а должна как облако дроби"
> (Currently pellets fire like a burst, but should fire as a cloud of pellets)

The 8ms delay approach was incorrect - pellets should spawn **simultaneously** with **spatial distribution**, not with temporal delays.

### Phase 3 (Gesture Sequence Correction - Current)
User feedback from PR #201 comment (2026-01-22T03:04:06Z):
> "поменяй в стрельбе ЛКМ (выстрел) -> ПКМ драгндроп вверх -> ПКМ драгндроп вниз
> на ЛКМ (выстрел) -> ПКМ драгндроп вниз -> ПКМ драгндроп вверх
> FIX сейчас не работает перезарядка"

**Key corrections:**
1. **Pump sequence reversed:** Was `up → down`, now `down → up`
2. **Reload sequence clarified:** First RMB up opens bolt, then either load (MMB+down) or close immediately (down without MMB)
3. **Tutorial labels updated:** Showing correct Russian text for controls

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

### Solution 2: Manual Pump-Action Cycling (Phase 3 Update)
Implemented `ShotgunActionState` machine:
- `Ready` → Can fire
- `NeedsPumpDown` → RMB drag down required (extract shell)
- `NeedsPumpUp` → RMB drag up required (chamber next round)

```csharp
// After firing:
ActionState = ShotgunActionState.NeedsPumpDown;
// Player must: RMB drag down (extract) → RMB drag up (chamber) → Ready
```

### Solution 3: Shell-by-Shell Reload (Phase 3 Update)
Implemented `ShotgunReloadState` machine:
- `NotReloading` → Normal operation
- `WaitingToOpen` → RMB drag up to open bolt
- `Loading` → MMB + RMB drag down to load shell, OR RMB drag down to close immediately
- `WaitingToClose` → RMB drag down to close bolt

```csharp
// Reload sequence:
// 1. RMB drag up → WaitingToOpen → Loading (bolt open)
// 2. MMB + RMB drag down → Load one shell (repeat up to 8x)
// 3. RMB drag down (without MMB) → Close bolt and chamber
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
| game_log_20260122_055020.txt | Phase 3 feedback | Incorrect gesture sequence identified |
| game_log_20260122_055128.txt | Phase 3 feedback | Reload not working |
| game_log_20260122_055403.txt | Phase 3 feedback | Additional testing |
| game_log_20260122_055650.txt | Phase 3 feedback | Tutorial testing |
| game_log_20260122_055806.txt | Phase 3 feedback | Final test before fix |

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

### Modified Files (Phase 3):
1. `Scripts/Weapons/Shotgun.cs`:
   - Swapped pump sequence: now `NeedsPumpDown → NeedsPumpUp` (was reversed)
   - Fixed reload sequence: now RMB up opens bolt, RMB down closes bolt
   - Added ability to close bolt immediately with RMB down (skipping shell loading)
   - Updated state descriptions and log messages

2. `scripts/levels/tutorial_level.gd`:
   - Updated shotgun shooting prompt: `[ЛКМ стрельба] [ПКМ↓ извлечь] [ПКМ↑ дослать]`
   - Updated shotgun reload prompt: `[ПКМ↑ открыть] [СКМ+ПКМ↓ x8] [ПКМ↓ закрыть]`
   - Added comments documenting correct sequences

## Control Summary (Phase 3 - Corrected)

### Shooting (Pump-Action)
| Action | Input |
|--------|-------|
| Fire | LMB |
| Extract shell | RMB drag down |
| Chamber round | RMB drag up |

### Reloading (Shell-by-Shell)
| Action | Input |
|--------|-------|
| Open bolt | RMB drag up (when ready, tube not full) |
| Load shell | MMB + RMB drag down (repeat up to 8x) |
| Close bolt | RMB drag down (without MMB) |

### Tutorial Labels (Russian)
| Step | Label |
|------|-------|
| Shooting | [ЛКМ стрельба] [ПКМ↓ извлечь] [ПКМ↑ дослать] |
| Reload | [ПКМ↑ открыть] [СКМ+ПКМ↓ x8] [ПКМ↓ закрыть] |

## References

- [Shotgun Pellet Ricochet Study](https://store.astm.org/jfs11425j.html)
- [2024 Ricochet Research](https://www.sciencedirect.com/science/article/abs/pii/S1355030624000704)
- Previous research: `docs/case-studies/issue-194/research-shotgun-mechanics.md`
- Player.cs grenade system (reference for drag gesture implementation)
