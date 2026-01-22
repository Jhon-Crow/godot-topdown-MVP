# Issue #199 - Fix Shotgun Mechanics

## Executive Summary

The shotgun weapon was added but has several mechanical issues that deviate from the intended design. This document analyzes the root causes and details the implemented solutions across multiple iterations.

## Issue Translation (Russian to English)

Original issue text:
> A shotgun was added, but it shoots and reloads incorrectly.

### Expected Behavior (CORRECTED - Phase 4)

**Firing Sequence (Pump-Action):**
1. LMB (fire)
2. RMB drag UP (eject spent shell)
3. RMB drag DOWN (chamber next round)

**Reload Sequence (Shell-by-Shell):**
1. RMB drag UP (open bolt) - goes directly to Loading state
2. MMB + RMB drag DOWN (load shell, repeatable up to 8 times)
3. RMB drag DOWN (close bolt and chamber round) - without MMB

Note: After opening bolt, can close immediately with RMB drag DOWN (without MMB) if shells are present.

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

### Phase 3 (Gesture Sequence Correction)
User feedback from PR #201 comment (2026-01-22T03:04:06Z):
> "поменяй в стрельбе ЛКМ (выстрел) -> ПКМ драгндроп вверх -> ПКМ драгндроп вниз
> на ЛКМ (выстрел) -> ПКМ драгндроп вниз -> ПКМ драгндроп вверх
> FIX сейчас не работает перезарядка"

### Phase 4 (Gesture Correction)
User feedback from PR #201 comment (2026-01-22T03:28:24Z):
> "подготовка к выстрелу всё ещё на неправильных драгндропах (должно быть - вверх, затем вниз)"
> (Preparation to fire still on wrong drag-and-drops (should be UP then DOWN))

**Key corrections:**
1. **Pump sequence clarified:** Correctly set to `UP → DOWN` (eject shell first, then chamber)
2. **Reload goes directly to Loading state:** RMB UP opens bolt AND enters Loading state immediately
3. **Tutorial labels updated:** Correct Russian text for controls

### Phase 5 (Tutorial Mode Shell Loading Fix)
User feedback from PR #201 comment (2026-01-22T04:02:15Z):
> "при ММБ+ПКМ драг вниз в дробовик должен добавляться один заряд (сейчас что то не так, хотя звук заряжания есть)"
> (With MMB+RMB drag down, one shell should be added to the shotgun (something is wrong now, although there is loading sound))

**Root cause identified:**
The `LoadShell()` method had a `ReserveAmmo <= 0` check that blocked shell loading in tutorial mode. In tutorial mode, there are no spare magazines (ReserveAmmo = 0), but the shotgun should have infinite shells like grenades do.

**Key corrections:**
1. **Added tutorial level detection** to Shotgun.cs (same logic as Player.cs uses for grenades)
2. **Skip ReserveAmmo check in tutorial mode:** Allow infinite shell loading without consuming reserve ammo
3. **Added debug logging** to trace the LoadShell() function for easier debugging

### Phase 6 (MMB Timing Fix - Current)
User feedback from PR #201 comment (2026-01-22T04:15:20Z):
> "я зажимаю MMB и RMB и делаю драгндроп чтоб зарядить один заряд, но это не работает"
> (I hold MMB and RMB and do drag-and-drop to load one shell, but it doesn't work)

**Root cause identified:**
The code was checking `_isMiddleMouseHeld` at the **moment RMB is released**, but users naturally release both MMB and RMB simultaneously or in quick succession. This creates a race condition where MMB might already be released by the time the gesture is processed.

**Key corrections:**
1. **Added `_wasMiddleMouseHeldDuringDrag` flag:** Tracks whether MMB was held at any point during the drag, not just at release
2. **Updated `HandleDragGestures()`:** Now sets the flag to true whenever MMB is detected during an active drag
3. **Updated `ProcessReloadGesture()`:** Now checks `_wasMiddleMouseHeldDuringDrag || _isMiddleMouseHeld` for more reliable detection

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

### Solution 2: Manual Pump-Action Cycling (Phase 4 Update)
Implemented `ShotgunActionState` machine:
- `Ready` → Can fire
- `NeedsPumpUp` → RMB drag UP required (eject shell)
- `NeedsPumpDown` → RMB drag DOWN required (chamber next round)

```csharp
// After firing:
ActionState = ShotgunActionState.NeedsPumpUp;
// Player must: RMB drag UP (eject) → RMB drag DOWN (chamber) → Ready
```

### Solution 3: Shell-by-Shell Reload (Phase 4 Update)
Implemented `ShotgunReloadState` machine:
- `NotReloading` → Normal operation
- `WaitingToOpen` → (skipped - goes directly to Loading)
- `Loading` → MMB + RMB drag DOWN to load shell, OR RMB drag DOWN to close immediately
- `WaitingToClose` → RMB drag DOWN to close bolt

```csharp
// Reload sequence (StartReload now goes directly to Loading):
// 1. RMB drag UP (when Ready) → Loading (bolt opened directly)
// 2. MMB + RMB drag DOWN → Load one shell (repeat up to 8x)
// 3. RMB drag DOWN (without MMB) → Close bolt and chamber
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
| game_log_20260122_062345.txt | Phase 4 feedback | Incorrect gestures still present |
| game_log_20260122_065828.txt | Phase 5 feedback | Shell loading not working in tutorial (sound plays but shell not added) |
| game_log_20260122_071250.txt | Phase 6 feedback | MMB+RMB drag down still not loading shells (timing issue) |

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
   - Updated shotgun shooting prompt
   - Updated shotgun reload prompt
   - Added comments documenting correct sequences

### Modified Files (Phase 4):
1. `Scripts/Weapons/Shotgun.cs`:
   - Correctly set pump sequence: now `NeedsPumpUp` first (after firing), then `NeedsPumpDown`
   - Fire sets `ActionState = NeedsPumpUp` (was incorrectly `NeedsPumpDown`)
   - RMB UP (drag up) transitions from `NeedsPumpUp` to `NeedsPumpDown`
   - RMB DOWN (drag down) transitions from `NeedsPumpDown` to `Ready`
   - `StartReload()` now goes directly to `Loading` state (skips `WaitingToOpen`)

2. `scripts/levels/tutorial_level.gd`:
   - Updated shotgun shooting prompt: `[ЛКМ стрельба] [ПКМ↑ извлечь] [ПКМ↓ дослать]`
   - Reload prompt already correct: `[ПКМ↑ открыть] [СКМ+ПКМ↓ x8] [ПКМ↓ закрыть]`
   - Updated header comments with correct sequences

### Modified Files (Phase 5):
1. `Scripts/Weapons/Shotgun.cs`:
   - Added `_isTutorialLevel` field for tutorial mode detection
   - Added `DetectTutorialLevel()` method (same logic as Player.cs uses for grenades)
   - Modified `LoadShell()` to skip `ReserveAmmo` check in tutorial mode
   - Modified `LoadShell()` to skip `MagazineInventory.ConsumeAmmo()` in tutorial mode
   - Added debug logging in `LoadShell()` for easier troubleshooting

### Modified Files (Phase 6 - Current):
1. `Scripts/Weapons/Shotgun.cs`:
   - Added `_wasMiddleMouseHeldDuringDrag` field to track MMB state during drag
   - Modified `HandleDragGestures()` to track MMB state throughout the drag gesture
   - Modified `ProcessReloadGesture()` to use the new tracking flag for reliable MMB detection

## Control Summary (Phase 4 - Corrected)

### Shooting (Pump-Action)
| Action | Input |
|--------|-------|
| Fire | LMB |
| Eject shell | RMB drag UP |
| Chamber round | RMB drag DOWN |

### Reloading (Shell-by-Shell)
| Action | Input |
|--------|-------|
| Open bolt | RMB drag UP (when ready, tube not full) - goes directly to Loading |
| Load shell | MMB + RMB drag DOWN (repeat up to 8x) |
| Close bolt | RMB drag DOWN (without MMB) |

### Tutorial Labels (Russian)
| Step | Label |
|------|-------|
| Shooting | [ЛКМ стрельба] [ПКМ↑ извлечь] [ПКМ↓ дослать] |
| Reload | [ПКМ↑ открыть] [СКМ+ПКМ↓ x8] [ПКМ↓ закрыть] |

## References

- [Shotgun Pellet Ricochet Study](https://store.astm.org/jfs11425j.html)
- [2024 Ricochet Research](https://www.sciencedirect.com/science/article/abs/pii/S1355030624000704)
- Previous research: `docs/case-studies/issue-194/research-shotgun-mechanics.md`
- Player.cs grenade system (reference for drag gesture implementation)
