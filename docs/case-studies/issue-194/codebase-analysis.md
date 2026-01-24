# Codebase Analysis for Shotgun Implementation

## Current Weapon System Architecture

### Overview

The godot-topdown-MVP uses a hybrid weapon system with:
- **C# weapons**: Primary system with `BaseWeapon` abstract class and `AssaultRifle` implementation
- **GDScript projectiles**: `bullet.gd` handles ricochet, penetration, and hit detection
- **Resource-based configuration**: `WeaponData.cs` and `CaliberData.gd` for weapon/ammo properties

### Key Files

| File | Purpose |
|------|---------|
| `Scripts/AbstractClasses/BaseWeapon.cs` | Abstract base class for all weapons |
| `Scripts/Weapons/AssaultRifle.cs` | M16 assault rifle implementation |
| `Scripts/Data/WeaponData.cs` | Weapon configuration resource |
| `scripts/projectiles/bullet.gd` | Bullet with ricochet/penetration |
| `scripts/data/caliber_data.gd` | Ammunition ballistic properties |
| `scripts/autoload/screen_shake_manager.gd` | Camera shake effects |
| `scripts/ui/armory_menu.gd` | Weapon selection UI |

### Weapon Class Hierarchy

```
BaseWeapon (C# abstract class)
├── WeaponData (configuration resource)
├── BulletScene (projectile prefab)
├── MagazineInventory (ammo management)
├── Fire() / SpawnBullet() / StartReload()
└── InstantReload() / FireChamberBullet()

    └── AssaultRifle (concrete implementation)
        ├── FireMode (Automatic/Burst)
        ├── LaserSight (optional aiming)
        ├── Recoil system
        └── Spread calculation
```

### Current AssaultRifle Specifications

| Property | Value |
|----------|-------|
| Fire Modes | Automatic, Burst (3 rounds) |
| Magazine Size | 30 rounds |
| Fire Rate | 10 shots/second |
| Bullets Per Shot | 1 |
| Spread Angle | 2.0 degrees |
| Has Laser Sight | Yes |
| Screen Shake | 5.0 intensity |

### Bullet System Features

The `bullet.gd` script handles:
- **Ricochet**: Angle-based probability, velocity/damage retention
- **Penetration**: Distance-based, wall thickness awareness
- **Trail effects**: Visual projectile trails
- **Sound propagation**: Alerts enemies to gunfire

### Armory Menu Status

Current weapon slots in `armory_menu.gd`:
- M16: Unlocked (available)
- Flashbang: Unlocked (available)
- Shotgun: Locked ("Coming soon")
- AK47, SMG, Sniper, Pistol: Locked

## Gap Analysis for Shotgun Implementation

### Features Needed

1. **Multiple Pellets Per Shot**
   - Current system: `BulletsPerShot` property exists in `WeaponData.cs` but only used for damage
   - Need: Spawn 6-12 bullets per shot with spread distribution

2. **Cone-Based Spread**
   - Current system: Random spread within angle range
   - Need: 15-degree cone with evenly distributed pellets

3. **Ricochet Angle Limit**
   - Current system: 90-degree max angle (configurable via CaliberData)
   - Need: 35-degree max ricochet angle for buckshot

4. **Wall Penetration Disabled**
   - Current system: Penetration enabled by default
   - Need: `can_penetrate: false` in caliber data

5. **Large Screen Shake**
   - Current system: Shake based on fire rate
   - Need: Single large recoil effect (not sustained shake)

6. **No Laser Sight**
   - Current system: Laser sight enabled by default
   - Need: `LaserSightEnabled = false` for shotgun

7. **Semi-Automatic Fire**
   - Current system: Has semi-auto (one shot per click)
   - Compatible: Use like burst mode but single shot

8. **Manual Reload Sequence**
   - Current system: Magazine-based reload
   - Need: Shell-by-shell loading with mouse drag gestures

### Implementation Complexity

| Feature | Complexity | Reason |
|---------|------------|--------|
| Multiple pellets | Medium | Modify `SpawnBullet()` to loop |
| Cone spread | Low | Already have spread angle logic |
| Ricochet limit | Low | Configure in CaliberData resource |
| No penetration | Low | Configure in CaliberData resource |
| Large shake | Medium | Modify shake formula for single shots |
| No laser | Low | Set property to false |
| Semi-auto fire | Low | Already exists conceptually |
| Shell reload | High | New mechanic entirely |

## Proposed Implementation Approach

### Phase 1: Core Shotgun Class
Create `Shotgun.cs` extending `BaseWeapon` with:
- Multi-pellet spawn logic
- Cone spread distribution
- Semi-automatic fire mode
- Large single-shot screen shake

### Phase 2: Buckshot Caliber
Create `caliber_buckshot.tres` resource with:
- Ricochet angle: 35 degrees max
- No wall penetration
- Higher damage per pellet
- Visual scale for impact effects

### Phase 3: Shotgun Data
Create `ShotgunData.tres` resource with:
- Pellet count range (6-12)
- 15-degree spread angle
- 8 round capacity
- No laser sight
- Higher screen shake intensity

### Phase 4: Shell Reload System
Implement drag-based reload:
- RMB down: Open action
- MMB + RMB down: Load shell (repeat)
- RMB up: Close action
- Track individual shell count

### Phase 5: Armory Integration
Update `armory_menu.gd`:
- Unlock shotgun slot
- Add shotgun icon
- Update description
