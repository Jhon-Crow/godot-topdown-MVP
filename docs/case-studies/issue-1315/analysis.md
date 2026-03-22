# Issue #1315: Fine Motor Skills Active Item (Мелкая моторика)

## Problem Statement

Add a new active item "Fine Motor Skills" (Мелкая моторика) that, when activated
(pressing Space), instantly reloads the weapon and brings it to combat-ready state.

### Requirements
- Unlimited charges, no cooldown
- On activation (Space press): reload weapon and bring to combat-ready state
- **Must work with**: Revolver, Shotgun, and Sniper Rifle
- Play reload and combat-ready sounds (as if done manually but very fast)

## Weapon-Specific Reload Mechanics

### Revolver (RSh-12)
- Multi-step cylinder reload: Open cylinder → Insert cartridges → Rotate → Close cylinder
- State machine: `RevolverReloadState` (NotReloading → CylinderOpen → Loading → Closing)
- Per-chamber tracking: `_chamberOccupied[]` array
- Sounds: cylinder open, casings eject, cartridge insert, cylinder rotate, cylinder close

### Shotgun (Pump-action)
- Tube magazine with shell-by-shell loading
- Two state machines: `ShotgunActionState` (pump cycle) + `ShotgunReloadState` (shell loading)
- After firing needs pump cycle: pump up (eject) → pump down (chamber)
- Sounds: action open, shell load, action close

### Sniper Rifle (ASVK)
- Bolt-action with 4-step manual cycle: LEFT (unlock) → DOWN (extract) → UP (chamber) → RIGHT (close)
- State machine: `BoltActionStep` (Ready → NeedsBoltCycle → WaitExtract → WaitChamber → WaitClose → Ready)
- Standard magazine reload via `StartReload()` / `FinishReload()`
- Sounds: 4 bolt step sounds via `play_asvk_bolt_step(step)`

### Standard Weapons (AssaultRifle, Pistols, Uzi)
- Timed magazine reload: `StartReload()` → timer → `FinishReload()`
- Magazine swap to fullest spare
- Sounds: standard reload animation sounds

## Solution Design

### Approach
Create a new active item `FINE_MOTOR_SKILLS` (enum value 19) that:
1. On Space press, calls a weapon-specific instant reload method
2. For each weapon type, performs the full reload sequence programmatically
3. Plays condensed reload sounds (all steps rapidly)
4. Brings weapon to Ready/combat-ready state

### Weapon-Specific Instant Reload Logic

**Revolver**: Open cylinder → fill all empty chambers from reserve → close cylinder
- Play: cylinder open + cartridge insert sounds + cylinder close

**Shotgun**: Fill tube from reserve + reset action state to Ready
- Play: action open + shell load sounds + action close

**Sniper Rifle**: Complete bolt cycle + reload magazine if needed
- Play: bolt step sounds (1-4 rapidly)

**Standard weapons**: Instant magazine swap to fullest
- Play: standard reload sound

### Files to Modify
1. `scripts/autoload/active_item_manager.gd` - Add enum, data, has_method
2. `scripts/characters/player.gd` - Add GDScript init + handle
3. `Scripts/Characters/Player.cs` - Add C# init + handle
4. `scripts/levels/roguelike_level.gd` - No change (active item, not passive)

## Similar Existing Components
- `AutoRefillTube()` in Shotgun.cs - auto-reload passive fills tube without gestures
- `InstantReload()` in BaseWeapon.cs - instant magazine swap
- Drilling Bullets pattern - simple "press Space" activation pattern
