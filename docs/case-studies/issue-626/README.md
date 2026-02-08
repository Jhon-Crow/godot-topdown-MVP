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

The implementation had **four** fundamental problems:

### 1. Wrong Player File Modified (CRITICAL)
**The most critical bug:** The project has TWO player implementations:
- `scripts/characters/player.gd` (GDScript) — modified with revolver reload logic
- `Scripts/Characters/Player.cs` (C#) — the **actual runtime player**, NOT modified

The game runs the C# Player.cs at runtime. All revolver reload changes were made to the GDScript player.gd, which is not the active player script. Evidence from the game log:
- Log shows `[Player] Detected weapon: RSh-12 Revolver (Pistol pose)` — this message comes from **Player.cs line 1349**, NOT from player.gd (which says "Revolver pose")
- Log shows standard magazine reload animations (GrabMagazine → InsertMagazine → ReturnIdle) with no revolver-specific messages

In Player.cs, the Revolver was treated as a pistol with R→R (2-step) magazine swap:
```csharp
bool isPistolReload = CurrentWeapon is MakarovPM || CurrentWeapon is Revolver;  // Line 1597
```
This sent the Revolver through the same reload path as the Makarov PM pistol.

### 2. Wrong Input Mapping (in early iterations)
The F key (`reload_step`) was used for cartridge insertion, inconsistent with the game's gesture-based paradigm where shotgun uses RMB drag gestures.

### 3. Missing Gesture Detection (in Revolver.cs)
Added RMB drag and scroll wheel detection following the Shotgun.cs pattern.

### 4. No Revolver-Specific Audio
Generic sounds (magazine in/out, M16 bolt) are inappropriate for a revolver cylinder mechanism.

## Solution

### Key Fix: Player.cs Reload Routing (Issue #626)

The critical fix was in `Scripts/Characters/Player.cs`:

1. **Skip standard reload for Revolver** in `HandleReloadSequenceInput()`:
   ```csharp
   if (CurrentWeapon is Revolver) { return; }
   ```

2. **Route R key to cylinder reload** via new `HandleRevolverReloadInput()` method:
   - R press when `NotReloading` → calls `revolver.OpenCylinder()`
   - R press when `CylinderOpen` or `Loading` → calls `revolver.CloseCylinder()`

3. **Lock player rotation during cylinder reload** in `UpdatePlayerModelRotation()` (tactical reload pattern, matching shotgun behavior)

4. **Remove Revolver from pistol reload group**:
   ```csharp
   bool isPistolReload = CurrentWeapon is MakarovPM;  // Revolver excluded
   ```

### Other Changes

#### `Scripts/Weapons/Revolver.cs`
- Added RMB drag gesture detection in `_Process()` via `HandleDragGestures()`
- Added scroll wheel input handling in `_Input()` for cylinder rotation
- Added `RotateCylinder(int direction)` method
- Added audio playback methods: `PlayCylinderOpenSound()`, `PlayCylinderCloseSound()`, `PlayCartridgeInsertSound()`, `PlayCylinderRotateSound()`
- `OpenCylinder()` and `CloseCylinder()` now play their respective sounds directly

#### `scripts/characters/player.gd`
- Added `_handle_revolver_reload_input()` to handle R key (open/close) for GDScript path
- RMB drag and scroll wheel inputs are handled by Revolver.cs directly

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
