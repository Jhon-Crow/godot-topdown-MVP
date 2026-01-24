# Issue #211: Shotgun Pellets Not Stopping in Special Last Chance Mode

## Issue Summary

**Title:** fix дробовик в особом последнем шансе
**Translation:** Fix shotgun in special last chance mode
**Description:** в особом последнем шансе дробь дробовика не останавливается
**Translation:** In special last chance mode, shotgun pellets do not stop

## Timeline of Events

1. The game has a "special last chance" effect for hard difficulty (implemented in `last_chance_effects_manager.gd`)
2. When triggered, time freezes for 6 real seconds, allowing the player to move and shoot
3. Player-fired bullets should stay frozen in place until time unfreezes
4. However, shotgun pellets continue to move during the freeze, which is inconsistent behavior

## Root Cause Analysis

### Problem Location

The issue is in `scripts/autoload/last_chance_effects_manager.gd`, specifically in two functions:

1. **`_on_node_added_during_freeze()`** (lines 791-838)
2. **`_find_bullets_recursive()`** (lines 656-670)

### Detection Logic Flaw

Both functions identify bullets using this check:

```gdscript
if "bullet" in script_path.to_lower():
    is_bullet = true
```

### Why This Fails for Shotgun Pellets

The shotgun pellet script is located at:
- `res://Scripts/Projectiles/ShotgunPellet.cs`

When converted to lowercase: `"res://scripts/projectiles/shotgunpellet.cs"`

The substring `"bullet"` is NOT present in this path, only `"pellet"`. Therefore:
- Regular bullets (`Bullet.cs`) are detected and frozen correctly
- Shotgun pellets (`ShotgunPellet.cs`) are NOT detected and continue moving

### Code Flow During Last Chance Effect

1. Player enters "last chance" state (1 HP, hard mode, threat detected)
2. `_start_last_chance_effect()` is called
3. Time freezes via `_freeze_time()`
4. `get_tree().node_added.connect(_on_node_added_during_freeze)` is established
5. When player fires shotgun:
   - `ShotgunPellet` nodes are created
   - `_on_node_added_during_freeze()` is triggered
   - The pellet's script path does NOT contain "bullet"
   - Pellets are NOT frozen and continue moving

## Affected Code Sections

### File: `scripts/autoload/last_chance_effects_manager.gd`

**Function 1: `_on_node_added_during_freeze()`**
```gdscript
# Line 812-817
var script: Script = node.get_script()
if script != null:
    var script_path: String = script.resource_path
    if "bullet" in script_path.to_lower():  # <-- BUG: doesn't match "pellet"
        is_bullet = true
elif "Bullet" in node.name or "bullet" in node.name:
    is_bullet = true
```

**Function 2: `_find_bullets_recursive()`**
```gdscript
# Line 659-667
var script: Script = node.get_script()
if script != null:
    var script_path: String = script.resource_path
    if "bullet" in script_path.to_lower():  # <-- BUG: doesn't match "pellet"
        if node not in bullets:
            bullets.append(node)
elif "Bullet" in node.name or "bullet" in node.name:
    if node not in bullets:
        bullets.append(node)
```

## Proposed Solution

Modify the bullet detection logic to also recognize "pellet" in the script path and node name:

```gdscript
# Updated detection logic
if "bullet" in script_path.to_lower() or "pellet" in script_path.to_lower():
    is_bullet = true

# And for name-based fallback
elif "Bullet" in node.name or "bullet" in node.name or "Pellet" in node.name or "pellet" in node.name:
    is_bullet = true
```

## Files to Modify

1. `scripts/autoload/last_chance_effects_manager.gd`
   - `_on_node_added_during_freeze()` function
   - `_find_bullets_recursive()` function

## Testing Checklist

- [ ] On hard mode, reduce player HP to 1
- [ ] Trigger threat detection to activate last chance mode
- [ ] Fire shotgun during time freeze
- [ ] Verify pellets are frozen in place
- [ ] Verify pellets resume movement when time unfreezes
- [ ] Verify regular bullets still work correctly
