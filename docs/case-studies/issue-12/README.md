# Case Study: Issue #12 - Game Balance and Technical Improvements

## Overview

This case study documents the investigation and resolution of multiple issues reported in Issue #12, focusing on game balance improvements, technical fixes for C# resource loading errors, and gameplay enhancements.

## Issues Reported

### 1. C# Resource Loading Error
```
ERROR: No loader found for resource: res://Scripts/Data/WeaponData.cs (expected type: Script)
ERROR: scene/resources/resource_format_text.cpp:40 - res://resources/weapons/AssaultRifleData.tres:6 - Parse Error: .
ERROR: Failed loading resource: res://resources/weapons/AssaultRifleData.tres.
```

### 2. Player Speed Not Changing in EXE Build
The player speed changes were not reflected in the exported executable.

### 3. Enemy Rotation Too Slow
Enemies could aim instantly at the player, making their attacks too accurate and unavoidable without cover.

### 4. Insufficient Starting Ammunition
Player started with only 1 magazine (30 bullets), which was insufficient for the tactical arena gameplay.

## Root Cause Analysis

### C# Resource Loading Error

**Cause:** The project uses a hybrid architecture with both C# scripts (in `Scripts/` folder) and GDScript (in `scripts/` folder). The `.tres` resource file `AssaultRifleData.tres` references a C# script (`WeaponData.cs`), but when exporting without proper .NET support or when the C# assemblies aren't built, Godot cannot load the script.

**Evidence from Godot Community:**
- This is a known issue when exporting Godot 4 projects with C# resources
- The error "No loader found for resource" with `.cs` scripts occurs when:
  1. Export templates are missing C# support
  2. C# assemblies aren't properly built before export
  3. Beta versions have bugs in C# export handling

**References:**
- [Crash on startup of export - No loader found for resource](https://forum.godotengine.org/t/crash-on-startup-of-export-no-loader-found-for-resource-cs-c-script/52771)
- [C# export is broken on 4.3.beta1 - GitHub Issue #92630](https://github.com/godotengine/godot/issues/92630)
- [Godot 4 exports unable to load custom resources - GitHub Issue #77886](https://github.com/godotengine/godot/issues/77886)

### Enemy Instant Rotation

**Cause:** The `_aim_at_player()` function in `enemy.gd` was setting the rotation directly without any interpolation:
```gdscript
# Before (instant rotation)
rotation = direction.angle()
```

This allowed enemies to track the player perfectly, making their shots nearly impossible to dodge without using cover.

**Solution Approach:** Implement gradual rotation using angle difference calculation and rotation speed limit.

**References:**
- [Smoothly rotate node towards an angle - Godot Forums](https://godotforums.org/d/35243-smoothly-rotate-node-towards-an-angle)
- [2D Top Down look_at and lerp_angle smoothing](https://forum.godotengine.org/t/2d-top-down-look-at-and-lerp-angle-smoothing/106208)
- [Smooth rotation in Godot 4 - KidsCanCode](https://kidscancode.org/godot_recipes/4.x/3d/rotate_interpolate/index.html)

## Solutions Implemented

### 1. Restored C# Resource File

**File:** `resources/weapons/AssaultRifleData.tres`

**Problem:** The `.tres` file was previously deleted, but C# scenes still reference it. Even though C# scenes are excluded from export, Godot's mono version validates ALL files during the import phase (before export filters apply). This caused the exe to fail to launch.

**Action:** Recreated the `.tres` resource file with proper configuration:
```ini
[gd_resource type="Resource" script_class="WeaponData" load_steps=2 format=3 uid="uid://b8q2n5x7m3k1w"]

[ext_resource type="Script" path="res://Scripts/Data/WeaponData.cs" id="1_script"]

[resource]
script = ExtResource("1_script")
Name = "Assault Rifle"
Damage = 25.0
FireRate = 10.0
...
```

**Note:** The UID `uid://b8q2n5x7m3k1w` must match the one referenced in `AssaultRifle.tscn` for proper loading.

**Export Configuration:** The `export_presets.cfg` still excludes C# files from final export:
```ini
exclude_filter="*.cs, scenes/characters/csharp/*, scenes/weapons/csharp/*"
```

This ensures the GDScript-only game works without requiring .NET runtime, while the C# code remains valid for import validation.

### 2. Implemented Gradual Enemy Rotation

**File:** `scripts/objects/enemy.gd`

**Changes:**
1. Added new export variable for rotation speed:
```gdscript
## Rotation speed in radians per second.
## Higher values make enemies aim faster. 8.0 = fast reaction, 4.0 = slower/more avoidable.
@export var rotation_speed: float = 8.0
```

2. Modified `_aim_at_player()` to use gradual rotation:
```gdscript
func _aim_at_player(delta: float) -> void:
    if _player == null:
        return
    var direction := (_player.global_position - global_position).normalized()
    var target_rotation := direction.angle()

    # Calculate the shortest rotation direction
    var rotation_diff := angle_difference(rotation, target_rotation)

    # Apply rotation with speed limit
    var max_rotation := rotation_speed * delta
    if absf(rotation_diff) <= max_rotation:
        rotation = target_rotation
    else:
        rotation += signf(rotation_diff) * max_rotation
```

**Rationale:** Using `angle_difference()` ensures the enemy always rotates in the shortest direction to face the player. The rotation speed of 8.0 radians/second allows approximately 0.4 seconds to turn 180 degrees, giving players a window to dodge shots.

### 3. Increased Starting Ammunition

**Files:**
- `scripts/characters/player.gd`
- `scripts/levels/test_tier.gd`
- `scenes/levels/TestTier.tscn`

**Changes:**
- `max_ammo`: 30 → 90 (3 magazines)
- `current_ammo`: 30 → 90
- Updated UI default text from "Ammo: 30/30" to "Ammo: 90/90"

**Balance Analysis:**
- 10 enemies × (2-4 HP) = 20-40 total HP
- 90 bullets available
- Ratio: ~2.25-4.5 bullets per HP (comfortable margin)
- Previous ratio with 30 bullets: ~0.75-1.5 bullets per HP (very tight)

## Technical Details

### Gradual Rotation Algorithm

The implemented rotation algorithm uses:
1. **`angle_difference()`** - Godot's built-in function that calculates the shortest signed angle between two angles
2. **Speed limiting** - Caps the rotation per frame to `rotation_speed * delta`
3. **Snap-to-target** - When close enough to the target angle, snaps directly to avoid oscillation

This approach is preferred over `lerp_angle()` because:
- It provides consistent rotation speed regardless of angle difference
- It doesn't slow down as it approaches the target (lerp would)
- It allows easy tuning of rotation speed in radians/second

### Export Configuration

The export preset changes ensure that:
1. C# script files (`.cs`) are excluded from the export
2. C#-specific scenes in `scenes/characters/csharp/` and `scenes/weapons/csharp/` are excluded
3. The main game using GDScript works without requiring .NET runtime

## Testing Recommendations

1. **C# Error Resolution:**
   - Export the game and verify no "No loader found for resource" errors
   - Verify all scenes load correctly

2. **Enemy Rotation:**
   - Observe enemies tracking the player
   - Verify there's a visible delay when enemies turn to face moving players
   - Test that circling around enemies at close range allows dodging

3. **Ammunition Balance:**
   - Start a new game and verify ammo shows 90/90
   - Play through and verify 90 bullets is comfortable for clearing 10 enemies
   - Verify ammo color changes work at correct thresholds (yellow at ≤10, red at ≤5)

## Lessons Learned

1. **Hybrid C#/GDScript projects require careful export handling** - When using both C# and GDScript, ensure export presets exclude unused C# resources to prevent loading errors.

2. **Instant rotation feels unfair in combat** - Enemies that can track perfectly make gameplay frustrating. Gradual rotation adds realism and skill expression.

3. **Balance testing should include margin** - Initial ammunition of 30 for 20-40 HP worth of enemies left no room for missed shots. 90 bullets (2.25-4.5 per HP) provides comfortable margin while still requiring accuracy.

## Additional Research on C# Export Issues

### Known Issues in Godot 4.3

Based on additional research into Godot 4.3 mono export issues, several potential causes have been identified:

1. **Missing Mono Module in Export Templates**
   - Custom-compiled export templates require `module_mono_enabled=yes` flag
   - Without this, C# scripts won't load in exported builds
   - [Source: Godot Forum - No loader found for resource](https://forum.godotengine.org/t/c-no-loader-found-for-resource/28444)

2. **Godot 4.3 Beta Bug**
   - Confirmed bug in 4.3.beta1 where C# exports failed with "No loader found for resource" errors
   - Fixed in stable release but may affect some builds
   - [Source: GitHub Issue #92630](https://github.com/godotengine/godot/issues/92630)

3. **Export Package (.pck) Problems**
   - Resources that work in editor fail to load in exported .pck/.zip files
   - Can be caused by incorrect export settings or resource path issues
   - [Source: GitHub Issue #86317](https://github.com/godotengine/godot/issues/86317)

4. **Exported Build Crashes on Startup**
   - In Godot 4.3 stable, some projects experience immediate crashes with resource loading errors
   - Often related to missing dependencies or misconfigured export settings
   - [Source: Godot Forum - Exported Build crashes immediately](https://forum.godotengine.org/t/4-3-stable-exported-build-crashes-immediately-upon-starting-up-game-everything-fails-to-load/101339)

### Verification Steps

To confirm the exe works correctly:

1. **Download the artifact from CI** - Get the windows-build.zip from the latest successful CI run
2. **Extract and run** - Extract `Godot-Top-Down-Template.exe` and run it
3. **Check for error messages** - If it crashes, check for console output or error dialogs
4. **Verify export templates** - Ensure using official Godot 4.3 stable mono export templates

### References

- [Crash on startup of export - No loader found for resource](https://forum.godotengine.org/t/crash-on-startup-of-export-no-loader-found-for-resource-cs-c-script/52771)
- [C# export is broken on 4.3.beta1 - GitHub Issue #92630](https://github.com/godotengine/godot/issues/92630)
- [C# - No loader found for resource - Godot Forum](https://forum.godotengine.org/t/c-no-loader-found-for-resource/28444)
- [Exported game crashes due to missing resources - GitHub Issue #86317](https://github.com/godotengine/godot/issues/86317)
- [Exported Build crashes immediately - Godot Forum](https://forum.godotengine.org/t/4-3-stable-exported-build-crashes-immediately-upon-starting-up-game-everything-fails-to-load/101339)

## Files Changed

| File | Change Type | Description |
|------|-------------|-------------|
| `resources/weapons/AssaultRifleData.tres` | Restored | Recreated C# resource file to fix import validation errors |
| `export_presets.cfg` | Modified | Added exclude filters for C# files |
| `scripts/objects/enemy.gd` | Modified | Added gradual rotation with configurable speed |
| `scripts/characters/player.gd` | Modified | Increased ammo to 90 (3 magazines) |
| `scripts/levels/test_tier.gd` | Modified | Updated balance documentation |
| `scenes/levels/TestTier.tscn` | Modified | Updated UI default ammo text |
