# Round 6 Analysis: Blood Not Visible on Floor

## User Feedback
- "Blood on the floor is not visible again" (Russian: "кровь на полу опять не видна")
- Game log attached: game_log_20260124_055228.txt

## Root Cause Analysis

### Symptom
The game log shows blood particle effects spawning, but no floor decals:
```
[05:52:28] [INFO] [ImpactEffects] Scenes loaded: DustEffect, BloodEffect, SparksEffect, BloodDecal
[05:52:45] [INFO] [ImpactEffects] Blood decal scene is null - skipping floor decals
```

### Investigation
1. The BloodDecal scene is listed as "loaded" at startup
2. But when `spawn_blood_effect` is called later, `_blood_decal_scene` is null
3. This indicates the scene file exists but `load()` returned null

### Root Cause
**Unicode characters in scene files caused parsing failures in exported builds.**

Specifically:
1. `BloodDecal.tscn` contained the Unicode character `≈` (approximately equal, U+2248) in a comment
2. `blood_decal.gd` contained the Unicode character `→` (right arrow, U+2192) in a comment

These characters may not be handled correctly by Godot's parser when loading scenes in exported builds, even though they work fine in the editor.

### Bug in Logging Code
The original logging code had a bug that reported scenes as "loaded" even when `load()` returned null:
```gdscript
if ResourceLoader.exists(blood_decal_path):
    _blood_decal_scene = load(blood_decal_path)
    loaded_scenes.append("BloodDecal")  # Added BEFORE checking if load succeeded!
```

## Fix Applied

### 1. Removed Unicode characters
- `BloodDecal.tscn`: Removed comments containing `≈`
- `blood_decal.gd`: Changed `→` to "to" in documentation

### 2. Fixed scene loading verification
Updated `_preload_effect_scenes()` to verify `load()` actually succeeded:
```gdscript
if ResourceLoader.exists(blood_decal_path):
    _blood_decal_scene = load(blood_decal_path)
    if _blood_decal_scene != null:  # NEW: Verify load succeeded
        loaded_scenes.append("BloodDecal")
    else:
        missing_scenes.append("BloodDecal (load failed)")
```

### 3. Added auto-reload fallback
If the scene is null when needed, the system now attempts to reload it:
```gdscript
if _blood_decal_scene == null:
    _log_info("Blood decal scene is null - attempting to reload")
    var blood_decal_path := "res://scenes/effects/BloodDecal.tscn"
    if ResourceLoader.exists(blood_decal_path):
        _blood_decal_scene = load(blood_decal_path)
```

## Lessons Learned
1. Avoid Unicode characters in Godot scene files (.tscn) and scripts (.gd) that will be exported
2. Always verify `load()` returns non-null before reporting success
3. Consider adding fallback reload logic for critical resources
