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
3. **User feedback (Round 1)**: Owner reported "it doesn't work" and provided game log (`game_log_20260209_020549.txt`). New requirements specified hold-to-activate with depletable charge and progress bar.
4. **v2 implementation**: Redesigned to support hold-to-activate with depletable charge pool and progress bar.
5. **User feedback (Round 2)**: Owner reported "вообще не работает, вместо значка - знак вопроса" (doesn't work at all, question mark icon instead of proper icon). Provided game log (`game_log_20260209_032340.txt`).
6. **v3 implementation**: Resolved merge conflicts with upstream/main (homing bullets from Issue #677), created force field icon, fixed enum ordering to accommodate all 5 active items.

## Root Cause Analysis

### Round 1: Why "it doesn't work" (game_log_20260209_020549.txt)

The game log shows:
- Force Field was selected in the armory (log line: `[ActiveItemManager] Active item changed from None to Force Field`)
- After level restart, no `[Player.ForceField]` initialization log appeared
- The exported build may have been missing the player.gd force field integration code
- The build was run from a standalone export path, not the editor

### Round 2: Why "вообще не работает" + question mark icon (game_log_20260209_032340.txt)

Two issues identified:

**Issue 1 — Force field not initializing (no `[Player.ForceField]` log)**
The game log from Round 2 shows the same pattern — after selecting Force Field in the armory, the player log only shows:
```
[Player.Flashlight] No flashlight selected in ActiveItemManager
[Player.TeleportBracers] No teleport bracers selected in ActiveItemManager
```
No `[Player.ForceField]` or `[Player.Homing]` lines appear. This means `_init_force_field()` was never called.

**Root cause**: A merge conflict with the homing bullets feature (Issue #677, PR #689) was not resolved. The upstream/main branch added `_init_homing_bullets()` and `_handle_homing_input()` at the same locations where we added `_init_force_field()` and `_handle_force_field_input()`. Git detected a content conflict, and the build contained conflict markers or the wrong branch's code.

**Issue 2 — Question mark icon**
The `icon_path` for the force field in `active_item_manager.gd` was set to `""` (empty string). Godot displays a question mark placeholder when no valid texture is found.

**Root cause**: No icon file was created for the force field active item. All other active items (flashlight, homing bullets, teleport bracers) have 64x48 pixel art PNG icons in `assets/sprites/weapons/`.

### v3 fix: Merge conflict resolution and icon creation

1. **Merge conflict**: Resolved all 3 conflicts in `player.gd`, `active_item_manager.gd`, and `test_active_item_manager.gd` — keeping BOTH homing bullets (from upstream Issue #677) AND force field code side by side.
2. **Enum ordering**: `NONE=0, FLASHLIGHT=1, HOMING_BULLETS=2, TELEPORT_BRACERS=3, FORCE_FIELD=4`
3. **Icon**: Created `force_field_icon.png` (64x48 pixel art, blue shield with glow effect) and set the `icon_path` in the active item data.

### Merge conflict with teleport bracers (Issue #672) — previously resolved in v1

The branch originally diverged from main before the teleport bracers feature was merged. This was resolved in v1 by keeping both TELEPORT_BRACERS and FORCE_FIELD.

### Merge conflict with homing bullets (Issue #677) — resolved in v3

After v2 was pushed, the homing bullets feature (PR #689) was merged to main. This created conflicts in the same 3 files where both features add enum values, initialization, and input handling code. Resolved by keeping all items.

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
| `tests/unit/test_active_item_manager.gd` | Added force field tests, updated enum values |
| `assets/sprites/weapons/force_field_icon.png` | New: 64x48 pixel art force field icon |
| `docs/case-studies/issue-676/game_log_20260209_020549.txt` | Owner's game log (Round 1) |
| `docs/case-studies/issue-676/game_log_20260209_032340.txt` | Owner's game log (Round 2) |
