# Case Study: Force Field Active Item (Issue #676)

## Requirements (from issue)
- Active item activated on Space key
- Glowing force field appears around the player
- 100% chance to reflect ALL projectiles (bullets, shrapnel, grenades)
- Offensive/frag grenades bounce off WITHOUT detonating on contact
- 8 second charge per fight

## Updated Requirements (from PR #688 feedback)
- Change from press-to-activate to **hold-to-activate** (depletable charge)
- Total charge: 8 seconds, usable in portions (hold 8s continuous, or 8x1s, or 2x4s, etc.)
- Add **progress bar** showing remaining charge when active

## Timeline

1. **Issue created**: User requested force field active item.
2. **Initial implementation (PR #688 v1)**: Implemented as one-shot press-Space activation with 1 charge and 8s fixed duration.
3. **User feedback**: Owner reported "it doesn't work" and provided game log. New requirements specified hold-to-activate with depletable charge and progress bar.
4. **v2 implementation**: Redesigned to support hold-to-activate with depletable charge pool and progress bar.

## Root Cause Analysis

### Why "it doesn't work"

The game log (`game_log_20260209_020549.txt`) shows:
- Force Field was selected in the armory (log line: `[ActiveItemManager] Active item changed from None to Force Field`)
- After level restart, no `[Player.ForceField]` initialization log appeared
- The exported build may have been missing the player.gd force field integration code
- The build was run from a standalone export path, not the editor

### Merge conflict with teleport bracers (Issue #672)

The branch diverged from main before the teleport bracers feature was merged. This caused a conflict in `active_item_manager.gd` where both TELEPORT_BRACERS and FORCE_FIELD enum values were added. Resolved by keeping both.

## Architecture

### v2: Hold-to-activate with depletable charge

1. **`force_field_effect.gd`**: Redesigned from one-shot to depletable charge pool:
   - `MAX_CHARGE = 8.0` seconds total charge
   - `_charge_remaining` tracks charge across multiple activations
   - `activate()` / `deactivate()` can be called multiple times
   - `_depleted` flag prevents reuse after charge reaches 0
   - Progress bar UI via CanvasLayer (blue -> orange -> red color changes)

2. **`player.gd`**: Changed input handling:
   - `Input.is_action_pressed("flashlight_toggle")` (continuous) instead of `is_action_just_pressed` (one-shot)
   - Activates while held, deactivates when released
   - Same hold-to-toggle pattern as the flashlight

3. **Projectile reflection** (unchanged from v1):
   - Bullets/shrapnel: Reflected using surface normal calculation `R = D - 2(D.N)N`
   - Grenades: Velocity reflected with 1.2x boost
   - Frag grenades: Impact detection temporarily disabled during bounce (0.15s)

### Physics interaction:
- Force field DeflectionArea: `collision_layer=0, collision_mask=48` (monitors projectile layer 16 + grenade layer 32)
- Bullets (Area2D, layer 16): Detected via area_entered
- Shrapnel (Area2D, layer 16): Same as bullets
- Grenades (RigidBody2D, layer 32): Detected via body_entered

## Files Changed

| File | Description |
|------|-------------|
| `scripts/effects/force_field_effect.gd` | Redesigned to depletable hold-to-activate with progress bar |
| `scripts/characters/player.gd` | Changed input from press-to-activate to hold-to-activate |
| `scripts/autoload/active_item_manager.gd` | Merged with teleport bracers, kept both items |
| `scripts/projectiles/bullet.gd` | Force field damage protection check |
| `scripts/projectiles/shrapnel.gd` | Force field damage protection check |
| `scripts/shaders/force_field.gdshader` | Glowing shield visual shader |
| `scenes/effects/ForceFieldEffect.tscn` | Force field scene |
| `tests/unit/test_active_item_manager.gd` | Added force field tests |
| `docs/case-studies/issue-676/game_log_20260209_020549.txt` | Owner's game log |
