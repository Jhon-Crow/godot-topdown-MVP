# Case Study: Issue #42 - Balance and Ammo Economy

## Issue Overview

**Issue:** [#42 - настроить баланс и экономику](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/42)

**Goal:** Configure balance and economy settings for the tactical arena, building upon existing implementations from Issue #12 and PR #38.

## Requirements Analysis

### Original Requirements (Issue #42)
1. Use existing implementations from Issue #12 and PR #38
2. Preserve all created functionality (laser sight, assault rifle)
3. The built exe should have the most complete version

### Additional Requirements (PR #43 Comments)
1. Player should have an assault rifle with laser sight
2. Player should have 3 magazines with 30 bullets each
3. Enemies should have same rifles as player but WITHOUT laser sight
4. Enemies should aim/rotate faster (more challenging)
5. Add 2-second reload time for enemies after each magazine
6. Preserve existing functionality

## Codebase Architecture

### Dual Implementation System
The project has two parallel implementations:
- **GDScript** (`scripts/` folder) - Simpler implementation
- **C#** (`Scripts/` folder) - Full weapon system with advanced features

### C# Weapon System Components
```
Scripts/
├── AbstractClasses/
│   └── BaseWeapon.cs      # Base weapon with ammo, reload, fire rate
├── Weapons/
│   └── AssaultRifle.cs    # Extends BaseWeapon with laser sight
├── Characters/
│   └── Player.cs          # Uses weapon system
└── Data/
    └── WeaponData.cs      # Resource class for weapon config
```

### Key Features by Implementation

| Feature | GDScript | C# |
|---------|----------|-----|
| Basic Movement | Yes | Yes |
| Shooting | Direct bullet spawn | Weapon-based |
| Laser Sight | No | Yes |
| Fire Modes | No | Automatic/Burst |
| Magazine Reload | No | Yes |
| Ammo Management | Simple counter | Magazine + Reserve |

## Solution Implementation

### 1. Weapon System Integration
- Restored `AssaultRifleData.tres` resource file
- Configured weapon parameters:
  - Magazine Size: 30 rounds
  - Reserve Ammo: 60 rounds (2 extra magazines)
  - Fire Rate: 10 shots/second
  - Reload Time: 2 seconds
  - Spread Angle: 2 degrees

### 2. Player Configuration
- Switched to C# Player scene with AssaultRifle
- Laser sight enabled for player
- Magazine-based reload system (Press R)
- Fire mode toggle (Press B)

### 3. Enemy Balance
- Rotation speed increased: 8 → 15 rad/sec
- Existing reload system: 2 seconds, 30 rounds/magazine
- 5 magazines per enemy (150 total rounds)
- No laser sight (as requested)

### 4. UI Updates
- Ammo display format: Magazine/Reserve (e.g., "30/60")
- Color coding:
  - White: Normal
  - Yellow: Magazine ≤ 10
  - Red: Magazine ≤ 5

## Technical Decisions

### Why C# Player?
1. Already has the complete weapon system
2. Laser sight implementation ready
3. Proper ammo/reload mechanics
4. Fire mode support (auto/burst)

### Signal System Adaptation
The test_tier.gd script was updated to handle both:
- GDScript Player signals (`ammo_changed`, `ammo_depleted`)
- C# Weapon signals (`AmmoChanged`)

```gdscript
var weapon = _player.get_node_or_null("AssaultRifle")
if weapon != null:
    # C# Player with weapon
    weapon.AmmoChanged.connect(_on_weapon_ammo_changed)
else:
    # GDScript Player
    _player.ammo_changed.connect(_on_player_ammo_changed)
```

## Balance Summary

### Player Resources
- 30 rounds per magazine
- 60 reserve rounds (2 extra magazines)
- 90 total rounds available

### Enemy Configuration
- 10 enemies (6 guards, 4 patrols)
- 2-4 HP each (random)
- 15 rad/sec rotation speed
- 30 rounds per magazine
- 2-second reload time

### Combat Balance
- Player bullets/HP ratio: ~2.25-4.5 bullets per enemy HP
- Laser sight gives targeting advantage
- Faster enemy rotation increases difficulty
- Cover system encourages tactical play

## Files Modified

| File | Changes |
|------|---------|
| `resources/weapons/AssaultRifleData.tres` | Created - weapon config |
| `scenes/levels/TestTier.tscn` | Switch to C# Player |
| `scripts/levels/test_tier.gd` | Handle C# weapon signals |
| `scripts/objects/enemy.gd` | Increase rotation speed |

## Related Issues and PRs

- Issue #7: Abstract weapon system
- Issue #8: Laser sight implementation
- Issue #12: Balance settings
- PR #38: Parameter configuration
- PR #43: This implementation

## Testing Checklist

- [x] CI builds successfully
- [ ] EXE launches without crash
- [ ] Player has laser sight
- [ ] Ammo counter shows magazine/reserve format
- [ ] Player can reload with R key
- [ ] Player can toggle fire mode with B key
- [ ] Enemies rotate faster than before
- [ ] Enemies reload after emptying magazine
- [ ] Victory message on clearing arena
- [ ] Game over message when out of ammo
