# Case Study: Issue #312 - Add Silenced Pistol

## Issue Summary
**Issue**: [#312](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/312)
**Title**: добавить пистолет с глушителем (Add silenced pistol)
**Status**: Fixed - weapon fully functional with stun effect and green laser sight

---

## Feature Request #4: Green Laser Sight (2026-01-24)

### Request Description
User requested: "добавь зелёный лазер (как в М16 - но другого цвета)" (add green laser like M16 but different color).

### Implementation Details

**Added laser sight with green color to SilencedPistol.cs**:
- Color: `new Color(0.0f, 1.0f, 0.0f, 0.5f)` (bright green, 50% alpha)
- Uses same raycast-based implementation as M16
- Stops at obstacles
- Follows aim direction with recoil offset

**Properties added**:
```csharp
[Export] public bool LaserSightEnabled { get; set; } = true;
[Export] public float LaserSightLength { get; set; } = 500.0f;
[Export] public Color LaserSightColor { get; set; } = new Color(0.0f, 1.0f, 0.0f, 0.5f);
[Export] public float LaserSightWidth { get; set; } = 2.0f;
```

---

## Bug Report #4: Stun Effect Not Working (2026-01-24)

### Problem Description
User reported: "стан не работает или слишком короткий" (stun is not working or too short).

From game logs (`game_log_20260124_205408.txt`), no stun effect messages were being logged.

### Root Cause Analysis

**Root Cause**: The `SpawnBullet()` method was using `Node.Set("StunDuration", value)` to set the stun duration on the bullet. However, Godot's `Set()` method doesn't reliably work for C# properties when the object is accessed through a base type reference (`Node2D`).

The bullet was instantiated as:
```csharp
var bullet = BulletScene.Instantiate<Node2D>();
bullet.Set("StunDuration", StunDurationOnHit);  // This fails silently!
```

### Fix Applied

Changed to cast to `Bullet` type for direct property access:
```csharp
var bulletNode = BulletScene.Instantiate<Node2D>();
var bullet = bulletNode as Bullet;
if (bullet != null)
{
    bullet.StunDuration = StunDurationOnHit;  // Direct property access works!
}
```

Also increased stun duration from 0.25s to 0.6s for a more noticeable effect.

### Lesson Learned
When setting properties on C# objects from C# code, always cast to the specific type rather than using `Node.Set()`. The `Set()` method is designed for GDScript interoperability and may not work correctly with pure C# properties.

---

## Bug Report #3: Ammo Counter Not Working (2026-01-24)

### Problem Description
User reported: "амmo counter не работает для pistol (возможно проблема C#)" (ammo counter not working for pistol, possibly C# problem).

From game logs, the ammo display constantly showed 30/30 (the M16's magazine size) even when using the silenced pistol (which has 13 rounds).

### Evidence from Logs
```
[20:54:16] [INFO] [Player] Ready! Ammo: 30/30, Grenades: 1/3, Health: 4/4
...
[20:55:35] [ENEMY] [Enemy1] Player ammo empty state changed: false -> true
```

The log shows the ammo was tracked correctly internally (enemy detected player ran out of ammo), but the UI displayed 30/30.

### Root Cause Analysis

**Root Cause**: The level scripts' `_setup_ammo_tracking()` function only checked for three weapon node names:
- `Shotgun`
- `MiniUzi`
- `AssaultRifle`

The `SilencedPistol` node was not included, so the signal connection was never made.

### Fix Applied

Added SilencedPistol detection to all three level scripts:

**`scripts/levels/tutorial_level.gd`**:
```gdscript
var silenced_pistol = _player.get_node_or_null("SilencedPistol")
# ...
elif silenced_pistol != null:
    if silenced_pistol.has_signal("AmmoChanged"):
        silenced_pistol.AmmoChanged.connect(_on_weapon_ammo_changed)
    if silenced_pistol.get("CurrentAmmo") != null and silenced_pistol.get("ReserveAmmo") != null:
        _update_ammo_label_magazine(silenced_pistol.CurrentAmmo, silenced_pistol.ReserveAmmo)
```

Same fix applied to `test_tier.gd` and `building_level.gd`.

---

## Feature Request #3: Stun Effect on Hit

### Request Description
User requested: "добавь особый эффект этому пистолету - после попадания враг станится (не может стрелять или двигаться) на время, минимально достаточное для следующего выстрела" (add a special effect to this pistol - after hitting, the enemy becomes stunned (cannot shoot or move) for time minimally sufficient for the next shot).

### Implementation Details

**Fire Rate Analysis:**
- Fire rate: 5.0 shots per second
- Time between shots: 1/5 = 0.2 seconds
- Stun duration set to: 0.6 seconds (increased from 0.25s for better tactical effect)

**Implementation:**

1. **`Scripts/Projectiles/Bullet.cs`**:
   - Added `StunDuration` property (exported, default 0.0)
   - Added `ApplyStunEffect()` method that uses `StatusEffectsManager.apply_stun()`
   - Modified `OnAreaEntered()` to apply stun when hitting enemies if `StunDuration > 0`

2. **`Scripts/Weapons/SilencedPistol.cs`**:
   - Added `StunDurationOnHit` constant (0.6 seconds - increased from original 0.25s)
   - Overrode `SpawnBullet()` to set `StunDuration` on spawned bullets
   - Uses direct C# property access (not Node.Set()) for reliable stun effect

3. **`scripts/ui/armory_menu.gd`**:
   - Updated weapon description to mention stun effect

### Stun Mechanics

The existing `StatusEffectsManager` autoload handles stun effects:
- Tracks stun duration per entity
- Updates durations each physics frame
- Applies visual feedback (blue tint)
- Calls `set_stunned()` on enemies

When stunned, enemies in `enemy.gd`:
- Have velocity set to Vector2.ZERO
- Skip all AI processing
- Cannot move or shoot

### Gameplay Impact

This makes the silenced pistol a tactical weapon where:
1. First hit stuns the enemy
2. Player can land follow-up shots while enemy is stunned
3. Each hit refreshes the stun duration
4. Enemies cannot retaliate between shots if player maintains fire rate

---

## Bug Report #2: Weapon Selection Not Working

### Problem Description
After the armory registration fix, the silenced pistol appeared in the armory menu but when selected, the player character still spawned with the AssaultRifle instead. The user reported: "пункт в armory добавился, но оружие при выборе не меняется" (item appeared in armory, but weapon doesn't change when selected).

### Evidence from Logs (`game_log_20260124_195249.txt`)

```
[19:52:56] [INFO] [GameManager] Weapon selected: silenced_pistol
[19:52:56] [INFO] [SoundPropagation] Sound emitted: source=PLAYER (AssaultRifle)  # <-- WRONG!
...
[19:53:09] [INFO] [GameManager] Weapon selected: mini_uzi
[19:53:09] [INFO] [SoundPropagation] Sound emitted: source=PLAYER (MiniUzi)  # <-- CORRECT!
...
[19:53:14] [INFO] [GameManager] Weapon selected: silenced_pistol
[19:53:14] [INFO] [SoundPropagation] Sound emitted: source=PLAYER (AssaultRifle)  # <-- STILL WRONG!
```

### Root Cause Analysis

**Root Cause**: The level scripts (`tutorial_level.gd`, `test_tier.gd`, `building_level.gd`) had **hardcoded weapon loading logic** with if-else conditions only for "shotgun", "mini_uzi", and default to "m16". There was **no case for "silenced_pistol"**, so when selected, the code fell through to the default case which equipped the AssaultRifle.

Additionally, the `Player.cs` script's `DetectAndApplyWeaponPose()` method only checked for specific weapon node names (`MiniUzi`, `Shotgun`), not `SilencedPistol`.

### Fix Applied

1. **Level Scripts** - Added `silenced_pistol` case to `_setup_selected_weapon()` in all three level files:
   - `scripts/levels/tutorial_level.gd`
   - `scripts/levels/test_tier.gd`
   - `scripts/levels/building_level.gd`

2. **Player.cs** - Added `Pistol` weapon type and detection for `SilencedPistol`:
   - Added `Pistol` to `WeaponType` enum
   - Added detection for `SilencedPistol` node in `DetectAndApplyWeaponPose()`
   - Added `Pistol` arm pose offsets in `ApplyWeaponArmOffsets()`

### Updated Weapon Addition Checklist

When adding a new weapon, ensure these are updated:

- [ ] Create weapon script (C# or GDScript)
- [ ] Create weapon data resource (.tres)
- [ ] Create weapon scene (.tscn)
- [ ] Add sprite/icon asset
- [ ] Register in `armory_menu.gd` WEAPONS dictionary
- [ ] Register in `game_manager.gd` WEAPON_SCENES dictionary
- [ ] **Add weapon loading case to ALL level scripts** (`tutorial_level.gd`, `test_tier.gd`, `building_level.gd`)
- [ ] **Add ammo tracking in `_setup_ammo_tracking()` for all level scripts**
- [ ] **Add weapon type enum and detection in `Player.cs`** (if new weapon type)
- [ ] Test weapon appears in armory
- [ ] Test weapon is selectable and actually loads
- [ ] Test weapon is functional in gameplay
- [ ] Test ammo counter displays correctly

---

## Bug Report #1: Weapon Not Appearing in Armory

### Problem Description
After initial implementation, the silenced pistol was not appearing in the game's armory menu. The user reported: "пистолет не добавился в armory (возможно проблема с C#)" (pistol was not added to armory, possibly a C# problem).

### Root Cause Analysis

**Root Cause**: The silenced pistol weapon class and scene files were created, but the weapon was **not registered** in the game's weapon registry systems.

In this project, weapons require registration in **two separate GDScript files**:

1. **`scripts/ui/armory_menu.gd`** - Contains `WEAPONS` dictionary for UI display
2. **`scripts/autoload/game_manager.gd`** - Contains `WEAPON_SCENES` dictionary for scene loading

The C# weapon code (`SilencedPistol.cs`) was correctly implemented, but the integration with the GDScript-based armory system was missed.

### Timeline of Events

| Time | Event |
|------|-------|
| 2026-01-24 ~16:27 | Initial PR #315 created with silenced pistol implementation |
| 2026-01-24 19:44:48 | User tested the game build |
| 2026-01-24 19:44:49 | User opened armory menu - no silenced pistol visible |
| 2026-01-24 19:45:05 | User ended game session, filed bug report |
| 2026-01-24 ~16:46 | User reported issue with game log attached |

### Evidence from Logs

Game log (`game_log_20260124_194448.txt`) shows:
```
[19:44:49] [INFO] [PauseMenu] Armory button pressed
[19:44:49] [INFO] [PauseMenu] armory_menu_scene resource path: res://scenes/ui/ArmoryMenu.tscn
[19:44:49] [INFO] [PauseMenu] _populate_weapon_grid method exists
```

The armory menu loaded successfully, but since `silenced_pistol` was not in the `WEAPONS` dictionary, it was never displayed.

### Fix Applied

Added silenced pistol registration to both files:

**`scripts/ui/armory_menu.gd`:**
```gdscript
"silenced_pistol": {
    "name": "Silenced Pistol",
    "icon_path": "res://assets/sprites/weapons/silenced_pistol_topdown.png",
    "unlocked": true,
    "description": "Beretta M9 with suppressor - semi-auto, 9mm, 13 rounds, silent shots (enemies don't hear), 2x recoil, smooth aiming. Press LMB to fire.",
    "is_grenade": false
}
```

**`scripts/autoload/game_manager.gd`:**
```gdscript
"silenced_pistol": "res://scenes/weapons/csharp/SilencedPistol.tscn"
```

### Lessons Learned

1. **Cross-language integration**: When adding C# components to a GDScript-based system, ensure all registration points are updated
2. **Checklist needed**: A weapon addition checklist would prevent similar issues:
   - [ ] Create weapon script (C# or GDScript)
   - [ ] Create weapon data resource (.tres)
   - [ ] Create weapon scene (.tscn)
   - [ ] Add sprite/icon asset
   - [ ] Register in `armory_menu.gd` WEAPONS dictionary
   - [ ] Register in `game_manager.gd` WEAPON_SCENES dictionary
   - [ ] Test weapon appears in armory
   - [ ] Test weapon is selectable and functional

---

## Requirements Analysis

### Original Requirements (translated from Russian):
1. **Caliber**: 9mm
2. **Fire mode**: Semi-automatic (shoots one bullet per trigger pull)
3. **Magazine capacity**: 13 rounds
4. **Sound**: Shots and reload sounds are inaudible to enemies (silenced)
5. **Spread**: Same as M16 (2.0 degrees)
6. **Recoil**: 2x more than M16 per single shot, stays at maximum position for a period (simulates time for human to control recoil)
7. **Bullets**: Ricochet like all 9mm (same as Uzi), do not penetrate walls
8. **Bullet speed**: Slightly higher than other 9mm (due to suppressor effect)
9. **Scope**: No scope/laser sight
10. **Aiming sensitivity**: Lower than all existing weapons (very smooth aiming)
11. **Reload**: Same as M16

### Reference Model
- Beretta M9 with suppressor (as shown in reference images)

## Implementation Details

### Files Created

1. **`Scripts/Weapons/SilencedPistol.cs`** - Main weapon script
   - Inherits from `BaseWeapon`
   - Semi-automatic fire mode
   - Extended recoil recovery delay (0.35s vs 0.08-0.1s for other weapons)
   - 2x recoil offset compared to M16 (±10 degrees vs ±5 degrees)
   - No sound propagation (enemies don't hear shots)

2. **`resources/weapons/SilencedPistolData.tres`** - Weapon configuration
   - Uses existing 9x19mm caliber for bullet properties
   - Magazine: 13 rounds
   - Fire rate: 5.0 shots/sec (semi-auto limited by player click speed)
   - Spread: 2.0 degrees (same as M16)
   - Bullet speed: 1350 px/s (higher than standard 9mm's 1200 px/s)
   - Sensitivity: 2.0 (lower than M16's 4.0 and Uzi's 8.0)
   - Loudness: 0.0 (silent)
   - Screen shake intensity: 10.0 (2x M16's 5.0)

3. **`scenes/weapons/csharp/SilencedPistol.tscn`** - Scene file
   - Uses 9mm bullet scene (same as Uzi)
   - Uses standard casing scene
   - Bullet spawn offset: 22px (accounts for suppressor length)

4. **`assets/sprites/weapons/silenced_pistol_topdown.png`** - Placeholder sprite
   - 44x12 pixels (longer than standard pistol due to suppressor)
   - Grayscale placeholder (to be replaced with proper art)

### Files Modified

1. **`scripts/autoload/audio_manager.gd`**
   - Added `SILENCED_SHOT` constant with placeholder sound
   - Added `VOLUME_SILENCED_SHOT` constant (-18.0 dB, very quiet)
   - Added `play_silenced_shot()` function
   - Added silenced shot to preload list

## Weapon Stats Comparison

| Property | Silenced Pistol | M16 | Mini Uzi |
|----------|-----------------|-----|----------|
| Damage | 1.0 | 1.0 | 0.5 |
| Fire Rate | 5.0 | 10.0 | 25.0 |
| Magazine | 13 | 30 | 32 |
| Bullet Speed | 1350 | 2500 | 1200 |
| Spread | 2.0° | 2.0° | 6.0° |
| Sensitivity | 2.0 | 4.0 | 8.0 |
| Screen Shake | 10.0 | 5.0 | 15.0 |
| Loudness | 0.0 | 1469.0 | 1469.0 |
| Automatic | No | Yes | Yes |
| Recoil Recovery | 0.35s | 0.1s | 0.08s |
| Max Recoil | ±10° | ±5° | ±8° |
| Laser Sight | Green | Red | None |
| Stun on Hit | 0.6s | None | None |

## Key Implementation Decisions

### 1. Recoil System
The silenced pistol implements a distinctive "heavy recoil with slow recovery" system:
- Each shot applies 2x the recoil of M16 per bullet
- Recovery is delayed by 0.35s (vs 0.08-0.1s for automatic weapons)
- This simulates the real-world experience of controlling pistol recoil

### 2. Silent Sound Propagation
- `Loudness` set to 0.0 prevents `SoundPropagation.emit_sound()` from alerting enemies
- Local audio still plays for player feedback (at very low volume)

### 3. Aiming Sensitivity
- Sensitivity of 2.0 (lowest of all weapons) creates smooth, deliberate aim
- Matches the tactical nature of a suppressed weapon

### 4. Bullet Properties
- Uses existing 9x19mm caliber (same as Uzi)
- Can ricochet up to 1 time at shallow angles (≤20°)
- Cannot penetrate walls
- Slightly higher bullet speed (1350 vs 1200) due to suppressor gas containment

## Future Improvements

1. **Proper Sprite Art**: The current placeholder should be replaced with a proper Beretta M9 with suppressor sprite matching the reference images
2. **Dedicated Sound**: Add proper suppressed shot sound effect (current uses pistol bolt sound as placeholder)
3. **Silenced Reload Sound**: Consider adding a quieter reload animation/sound specific to the silenced pistol
4. **Magazine Drop Animation**: The standard casing effect works, but a visible magazine drop during reload would add polish

## Testing Recommendations

1. Verify semi-automatic fire works (no automatic fire on hold)
2. Test recoil feels heavier than other weapons
3. Confirm enemies don't react to shots (no sound propagation)
4. Test ricochet behavior matches Uzi (9mm rules)
5. Verify bullet speed is slightly higher than Uzi
6. Check smooth aiming (low sensitivity)
7. Confirm 13-round magazine capacity
