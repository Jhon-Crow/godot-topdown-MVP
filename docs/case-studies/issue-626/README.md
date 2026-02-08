# Case Study: Issue #626 - Multi-Step Revolver Cylinder Reload

## Issue Description

**Original requirement (Russian):**
1. открыть барабан (высыпаются гильзы)
2. вставить патрон -> повернуть барабан (5 раз)
3. закрыть барабан

**Translation:** Implement multi-step revolver cylinder reload:
1. Open cylinder (casings fall out)
2. Insert cartridge + rotate cylinder (5 times)
3. Close cylinder

## Timeline of Events

### Initial Implementation (commit 640e5ea7)
- Implemented R-F-R reload sequence (R=open/close, F=insert cartridge)
- Added `RevolverReloadState` enum, `OpenCylinder()`, `InsertCartridge()`, `CloseCylinder()` to Revolver.cs
- Added `_handle_revolver_reload_input()` to player.gd
- Used generic reload sounds (magazine in/out sounds) instead of revolver-specific ones

### Problem Identified (PR #634 feedback from @Jhon-Crow)
**Game log:** `game_log_20260208_160452.txt` (attached to this case study)

**Root Cause:** The revolver was reloading like the M16 (standard magazine swap) because:
1. The `_handle_revolver_reload_input()` correctly checked `WeaponType.REVOLVER`, but the F key (`reload_step` action) was not intuitively correct for the revolver
2. The reload animation phases (GrabMagazine → InsertMagazine → ReturnIdle) were from the standard rifle reload, not revolver-specific
3. The game log showed no "[Revolver] Cylinder opened" or "[Revolver] Cartridge inserted" messages, confirming the custom reload logic was not being invoked properly

### Updated Requirements (PR #634 comment from @Jhon-Crow)
The owner clarified the desired input scheme:
1. **R key** = open cylinder
2. **RMB drag up** (like shotgun pump-action) = insert cartridge
3. **Scroll wheel** (up or down) = rotate cylinder by 1 position
4. Repeat steps 2-3 until cylinder is full
5. **R key** = close cylinder
6. Use revolver-specific sounds from `assets/audio`

## Root Cause Analysis

The initial implementation had two fundamental problems:

### 1. Wrong Input Mapping
The F key (`reload_step`) was used for cartridge insertion. This was inconsistent with the existing interaction paradigm in the game, where:
- The shotgun uses **RMB drag gestures** for pump-action mechanics
- The F key is used for bolt-action rifle reload steps
- The revolver, as a cylinder weapon, should use a different input than magazine-based weapons

### 2. Missing Gesture Detection
The Revolver.cs class had no RMB drag gesture detection or scroll wheel input handling. All input was delegated to player.gd, which only checked keyboard inputs. The shotgun (Shotgun.cs) already had a complete gesture detection system with `HandleDragGestures()`, `TryProcessMidDragGesture()`, and `ProcessDragGesture()` methods that the revolver should have followed as a pattern.

### 3. No Revolver-Specific Audio
The implementation used generic sounds (magazine in/out, M16 bolt) that are inappropriate for a revolver cylinder mechanism. The game has suitable sounds that could be repurposed:
- Pistol bolt sound → cylinder open
- Shotgun shell load → cartridge insert
- PM reload actions → cylinder rotate / close

## Solution

### Changes Made

#### `Scripts/Weapons/Revolver.cs`
- Added RMB drag gesture detection in `_Process()` via `HandleDragGestures()`
- Added scroll wheel input handling in `_Input()` for cylinder rotation
- Added `RotateCylinder(int direction)` method
- Added audio playback methods: `PlayCylinderOpenSound()`, `PlayCylinderCloseSound()`, `PlayCartridgeInsertSound()`, `PlayCylinderRotateSound()`
- `OpenCylinder()` and `CloseCylinder()` now play their respective sounds directly

#### `scripts/characters/player.gd`
- Simplified `_handle_revolver_reload_input()` to only handle R key (open/close)
- Removed F key (`reload_step`) handling for cartridge insertion
- RMB drag and scroll wheel inputs are now handled by Revolver.cs directly

#### `scripts/autoload/audio_manager.gd`
- Added revolver audio constants using existing sound files:
  - `REVOLVER_CYLINDER_OPEN` → pistol bolt sound
  - `REVOLVER_CYLINDER_CLOSE` → PM reload action 2
  - `REVOLVER_CARTRIDGE_INSERT` → shotgun shell load sound
  - `REVOLVER_CYLINDER_ROTATE` → PM reload action 1
- Added play methods: `play_revolver_cylinder_open()`, `play_revolver_cylinder_close()`, `play_revolver_cartridge_insert()`, `play_revolver_cylinder_rotate()`

#### `tests/unit/test_revolver_reload.gd`
- Added `rotate_cylinder()` to mock class
- Added cylinder rotation tests (can rotate when open, cannot when closed, multiple rotations)
- Added full sequence test with rotation
- Updated comments to reflect new RMB drag up + scroll wheel input scheme

## Attached Data

- `game_log_20260208_160452.txt` - Game log showing the original problem (revolver reloading like M16)
