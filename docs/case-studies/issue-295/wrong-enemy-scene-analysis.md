# Case Study: Wrong Enemy Scene Added to Tutorial Map

**Issue:** [#295](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/295) - Enemy Grenade Throw Debug
**Pull Request:** [#296](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/296)
**Date:** 2026-01-24
**Reporter:** Jhon-Crow
**Status:** Fixed

## Problem Description

When the tutorial enemy was added to the Tutorial map (Обучение) in commit `443b341`, a C# placeholder target was added instead of the actual enemy. The user reported:

> "на учебную карту добавилась мишень а не враг - добавился квадрат который реагирует на урон"
>
> Translation: "A target was added to the tutorial map instead of an enemy - a square that reacts to damage was added"

## Timeline of Events

### 1. Initial Implementation (Commit `aea77fb`)
- Tutorial enemy was added to `scenes/levels/TestTier.tscn` (GDScript test map)
- Enemy configured correctly with:
  - Empty weapon (0 bullets, 0 magazines)
  - Infinite flashbangs (999)
  - No flanking enabled
  - Referenced correct enemy scene: `res://scenes/objects/Enemy.tscn`

### 2. Relocation Attempt (Commit `443b341`)
- AI attempted to move tutorial enemy from TestTier.tscn to Tutorial map
- **MISTAKE**: AI incorrectly moved enemy to `scenes/levels/csharp/TestTier.tscn`
- **MISTAKE**: AI used wrong enemy scene reference: `res://scenes/objects/csharp/Enemy.tscn`

### 3. User Testing (2026-01-24 06:47:20)
- User loaded Tutorial map and found a red square target instead of enemy
- Game log shows scene loaded successfully but no enemy behavior
- User reported issue in PR comment

### 4. Root Cause Analysis (2026-01-24)
- Investigation revealed two Enemy.tscn files exist:
  1. `scenes/objects/Enemy.tscn` - Real enemy (CharacterBody2D with sprites, AI, weapons)
  2. `scenes/objects/csharp/Enemy.tscn` - C# placeholder/target (Area2D with red square)

## Root Cause

The AI solver made a **scene reference error** when adding the enemy to the Tutorial map. The error occurred because:

1. **Wrong Scene File Used**: Referenced `res://scenes/objects/csharp/Enemy.tscn` instead of `res://scenes/objects/Enemy.tscn`
2. **Different Scene Types**:
   - **Correct Enemy** (`scenes/objects/Enemy.tscn`):
     - Type: `CharacterBody2D`
     - Script: `res://scripts/objects/enemy.gd` (GDScript)
     - Has: Enemy sprites, weapon system, AI behavior, health system
     - UID: `uid://cx5m8np6u3bwd`

   - **Wrong "Enemy"** (`scenes/objects/csharp/Enemy.tscn`):
     - Type: `Area2D`
     - Script: `res://Scripts/Objects/Enemy.cs` (C#)
     - Has: Red placeholder square sprite (48x48)
     - UID: `uid://dx5m8np6u3bwe`
     - Purpose: C# test/placeholder, not functional enemy

## Technical Details

### Wrong Scene Content (C# Placeholder)
```gdscript
[node name="Enemy" type="Area2D" groups=["enemies"]]
collision_layer = 2
collision_mask = 16
script = ExtResource("1_enemy")  # C# script

[node name="Sprite2D" type="Sprite2D" parent="."]
modulate = Color(0.9, 0.2, 0.2, 1)  # Red square
texture = SubResource("PlaceholderTexture2D_enemy")
```

### Correct Scene Content (Real Enemy)
```gdscript
[node name="Enemy" type="CharacterBody2D" groups=["enemies"]]
collision_layer = 2
collision_mask = 4
script = ExtResource("1_enemy")  # GDScript

[node name="EnemyModel" type="Node2D" parent="."]
# Contains: Body, Head, LeftArm, RightArm, WeaponMount sprites
```

### Game Log Evidence

**Tutorial map load (06:47:52):**
```
[06:47:52] [INFO] [Player.Grenade] Tutorial level detected - infinite grenades enabled
[06:47:52] [INFO] [Player] Ready! Ammo: 30/30, Grenades: 3/3, Health: 3/4
```

**No enemy spawn logs** - The C# placeholder doesn't emit spawn logs like real enemies do.

**Compare with Building map load (06:47:20):**
```
[06:47:20] [ENEMY] [Enemy1] Enemy spawned at (300, 350), health: 4, behavior: GUARD
[06:47:20] [ENEMY] [Enemy2] Enemy spawned at (400, 550), health: 3, behavior: GUARD
...
```

## Impact

- **User Experience**: Tutorial map shows non-functional red square instead of enemy
- **Functionality**: Enemy AI behavior not working (no movement, no grenade throwing)
- **Testing**: Cannot test grenade ricochet and enemy behavior on Tutorial map
- **Confusion**: User thought a "target" was added instead of enemy

## Solution

### Fix Applied
Changed line 8 in `scenes/levels/csharp/TestTier.tscn`:

**Before:**
```gdscript
[ext_resource type="PackedScene" uid="uid://dx5m8np6u3bwe" path="res://scenes/objects/csharp/Enemy.tscn" id="6_enemy"]
```

**After:**
```gdscript
[ext_resource type="PackedScene" uid="uid://cx5m8np6u3bwd" path="res://scenes/objects/Enemy.tscn" id="6_enemy"]
```

### Verification Steps
1. Scene file now references correct enemy UID: `uid://cx5m8np6u3bwd`
2. Enemy scene path corrected: `res://scenes/objects/Enemy.tscn`
3. No changes needed to enemy configuration (lines 331-339) - parameters were correct

## Lessons Learned

### For AI Solvers
1. **Verify Scene References**: Always check scene file paths and UIDs when working with Godot scenes
2. **Distinguish C# vs GDScript**: Scenes in `/csharp/` folders may be placeholders or test files
3. **Check Scene Type**: Verify the root node type matches expected behavior (CharacterBody2D vs Area2D)
4. **Cross-Reference**: Compare with existing working examples before making changes
5. **Test Scene Loading**: Check game logs for expected spawn messages after scene changes

### For Repository
1. **Scene Naming**: Consider renaming `scenes/objects/csharp/Enemy.tscn` to avoid confusion (e.g., `EnemyPlaceholder.tscn`)
2. **Documentation**: Add comments in C# placeholder scenes to indicate they're not production enemies
3. **Directory Structure**: Clearly separate C# test files from GDScript production files

## Prevention Measures

1. **Pre-commit Checks**: Verify scene references before committing scene file changes
2. **Scene Validation**: Add tool to validate that enemy scenes use correct base types
3. **Naming Convention**: Establish clear naming for placeholders vs production scenes
4. **Code Review**: Human review scene file changes to catch incorrect references

## Related Files

- `docs/case-studies/issue-295/game_log_20260124_064720.txt` - User's game log showing the issue
- `scenes/levels/csharp/TestTier.tscn` - Tutorial map scene (fixed)
- `scenes/objects/Enemy.tscn` - Correct enemy scene (GDScript)
- `scenes/objects/csharp/Enemy.tscn` - C# placeholder (should not be used in production maps)
- Commit `443b341` - Where the bug was introduced
- Commit `[PENDING]` - Where the bug was fixed

## References

- Issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/295
- Pull Request: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/296
- Godot Docs: [Scene File Format](https://docs.godotengine.org/en/stable/contributing/development/file_formats/tscn.html)
