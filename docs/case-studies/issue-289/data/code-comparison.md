# Code Comparison: Player vs Enemy Weapon Shell Casings

## Player Weapon Implementation (C# - BaseWeapon.cs)

### Location
- File: `Scripts/AbstractClasses/BaseWeapon.cs`
- Lines: 390-436

### Key Features
1. **CasingScene Export**: Line 29 - `public PackedScene? CasingScene { get; set; }`
2. **SpawnCasing Method**: Lines 390-436
   - Spawns visual RigidBody2D casing
   - Calculates ejection direction (perpendicular to shooting direction)
   - Applies random velocity (300-450 pixels/sec)
   - Adds angular velocity for spin
   - Sets caliber data for appearance
3. **Called from Fire**: Line 387 - `SpawnCasing(direction, WeaponData?.Caliber);`

### Player AssaultRifle Configuration (AssaultRifle.tscn)
- Line 13: `CasingScene = ExtResource("3_casing")` - References `res://scenes/effects/Casing.tscn`
- Visual casings ARE spawned when player fires

## Enemy Weapon Implementation (GDScript - enemy.gd)

### Location
- File: `scripts/objects/enemy.gd`
- Lines: 3723-3810

### Key Features
1. **NO CasingScene Export**: Enemy script doesn't have a casing scene variable
2. **_shoot Method**: Lines 3723-3810
   - Spawns bullet only
   - Plays M16 shot sound (line 3791-3792)
   - Plays shell casing SOUND only (lines 3800-3801, 3813-3817)
   - **NO visual casing spawning**

### Enemy Scene Configuration (Enemy.tscn)
- Has WeaponSprite (line 44-47) but NO weapon node/component
- Enemy doesn't use BaseWeapon.cs - it has custom shooting logic in enemy.gd
- Visual casings are NOT spawned when enemy fires

## Root Cause Analysis

The enemy's shooting implementation is in GDScript (enemy.gd) and was developed separately from the player's weapon system (BaseWeapon.cs in C#). The enemy script:
1. Directly instantiates bullets
2. Only plays shell casing audio
3. Never instantiates the visual Casing.tscn scene

This is an inconsistency - player weapons spawn visual casings, but enemy weapons don't.
