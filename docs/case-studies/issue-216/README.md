# Case Study: Issue #216 - Weapon Selection Causes Game Freeze

## Issue Summary
**Issue:** After selecting a weapon from the armory menu, the game freezes until the user manually opens the ESC menu and clicks restart.

**Reported by:** Jhon-Crow (repo owner)
**Date:** 2026-01-22
**Severity:** High (gameplay blocking bug)

## Timeline of Events

### Initial Implementation (PR #238)
1. Added weapon selection feature to armory menu (`armory_menu.gd`)
2. Added `_setup_selected_weapon()` function to `test_tier.gd` for weapon swapping
3. Implemented auto-restart on weapon selection (line 242 in `armory_menu.gd`)

### Bug Report
User reported that after selecting a weapon in the armory, the game appears "frozen" - player cannot move or interact until:
1. Opening the ESC menu again
2. Clicking the Restart button

## Root Cause Analysis

### Evidence from Game Log (`game_log_20260122_130034.txt`)

Key timestamps showing the issue:

```
[13:00:40] [INFO] [PauseMenu] Armory button pressed
[13:00:41] [INFO] [GameManager] Weapon selected: shotgun
[13:00:41] [INFO] [Player] Ready! Ammo: 30/30, Grenades: 1/3, Health: 2/4
```

Notice that at 13:00:41, after weapon selection and scene reload, the player shows "Ammo: 30/30" which is the assault rifle's ammo count, not the shotgun's 6 shells. This indicates the scene reloaded but remained in a problematic state.

The weapon detection only happens later:
```
[13:00:45] [INFO] [Player] Detected weapon: Shotgun (Shotgun pose)
```

That's a **4-second gap** where the game was unresponsive.

### Root Cause

The bug is in `armory_menu.gd` line 240-242:

```gdscript
# Restart the level to apply the new weapon (like grenades do)
if GameManager:
    GameManager.restart_scene()
```

The problem: **The game tree is paused** when in the armory menu (paused via `pause_menu.gd` line 87: `get_tree().paused = true`), and `GameManager.restart_scene()` only calls `get_tree().reload_current_scene()` **without unpausing first**.

### Why Grenade Selection Works

The `GrenadeManager._restart_current_level()` (lines 99-116) correctly handles this:

```gdscript
func _restart_current_level() -> void:
    # IMPORTANT: Unpause the game before restarting
    get_tree().paused = false  # <-- This is the key!

    # Restore hidden cursor for gameplay
    Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)

    # Use GameManager to restart
    var game_manager: Node = get_node_or_null("/root/GameManager")
    if game_manager and game_manager.has_method("restart_scene"):
        game_manager.restart_scene()
```

### Why Weapon Selection Was Broken

The `armory_menu.gd` `_select_weapon()` function:
1. Updates the weapon selection in GameManager
2. Calls `GameManager.restart_scene()` directly
3. **Does NOT unpause the game**
4. **Does NOT restore the cursor mode**

Result: Scene reloads but remains in paused state with visible cursor.

## Solution

Fix `armory_menu.gd` `_select_weapon()` to unpause and restore cursor before restarting, matching the behavior of `GrenadeManager._restart_current_level()`.

### Code Change

```gdscript
func _select_weapon(weapon_id: String) -> void:
    # ... existing code to check if already selected and update GameManager ...

    # Restart the level to apply the new weapon (like grenades do)
    if GameManager:
        # IMPORTANT: Unpause the game before restarting
        # This prevents the game from getting stuck in paused state when
        # changing weapons from the armory menu while the game is paused
        get_tree().paused = false

        # Restore hidden cursor for gameplay (confined and hidden)
        Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)

        GameManager.restart_scene()
```

## Lessons Learned

1. **Consistency matters**: When implementing similar functionality (weapon restart vs grenade restart), the same edge cases must be handled identically.

2. **State management across scene reloads**: `get_tree().paused` is a global state that persists across scene reloads. Always consider what global state needs to be reset before scene transitions.

3. **Test in actual usage context**: The weapon selection worked in unit testing (direct calls) but failed when used through the actual UI flow (paused menu context).

## Files Affected

- `scripts/ui/armory_menu.gd` - Bug location (missing unpause)
- `scripts/autoload/grenade_manager.gd` - Reference implementation (correct behavior)
- `scripts/levels/test_tier.gd` - Weapon setup (working correctly)
- `scripts/autoload/game_manager.gd` - Restart function (working correctly)

## References

- Issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/216
- PR: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/238
- Game Log: `game_log_20260122_130034.txt` (attached to this case study)
