# Case Study: Issue #192 - Grenade Explosion During Last Chance Effect

## Summary

**Issue**: Grenade timer should stop and grenade should not move while time is frozen during the "Last Chance" special effect. Sometimes this did not work correctly.

**Root Cause**: The `_on_node_added_during_freeze()` function in `LastChanceEffectsManager` only detected and froze bullets (Area2D nodes), not grenades (RigidBody2D nodes). Grenades created during the time freeze would continue processing normally, including their timer countdown and physics movement.

**Fix**: Extended the detection logic to also recognize and freeze grenades, tracking them separately for proper restoration when the effect ends.

## Timeline Reconstruction from Log

### Event Sequence (from game_log_20260122_032558.txt)

```
03:26:44 - LastChance effect STARTS (6 real seconds freeze duration)
03:26:46 - Grenade created at (267.1, 871.3) - Timer activated: 4.0 seconds until explosion
03:26:47 - Grenade thrown and starts moving
03:26:50 - Grenade EXPLODES at (424.6, 778.5) - Only 4 seconds after timer started!
03:26:50 - LastChance effect duration expired after 6.00 real seconds
```

**Problem**: The grenade exploded at 03:26:50, which was DURING the 6-second LastChance freeze that started at 03:26:44 (the effect should have prevented the explosion until the freeze ended at 03:26:50).

## Technical Analysis

### 1. Grenade Timer Implementation (`scripts/projectiles/grenade_base.gd`)

The grenade uses `_physics_process(delta)` for its timer:

```gdscript
func _physics_process(delta: float) -> void:
    if _timer_active:
        _time_remaining -= delta
        if _time_remaining <= 0:
            _explode()
```

When `process_mode` is set to `PROCESS_MODE_DISABLED`, this function should stop being called.

### 2. LastChance Time Freeze Strategy (`scripts/autoload/last_chance_effects_manager.gd`)

The LastChance effect freezes time by:
1. Setting all existing nodes to `PROCESS_MODE_DISABLED`
2. Connecting to `node_added` signal to freeze newly created nodes

### 3. The Bug

The `_on_node_added_during_freeze()` function only checked for:
- **Area2D** nodes with "bullet" in script path or name

It did NOT check for:
- **RigidBody2D** nodes with "grenade" in script path

When a grenade was created during the freeze:
1. The grenade was a NEW node, not frozen in the initial pass
2. The `node_added` handler didn't recognize it as needing freeze
3. The grenade's `_physics_process()` continued running
4. Timer counted down and grenade exploded during frozen time

## Solution

Extended `_on_node_added_during_freeze()` to also detect RigidBody2D nodes with "grenade" in their script path:

```gdscript
# Check if this is a grenade (RigidBody2D with grenade script)
if node is RigidBody2D:
    var script: Script = node.get_script()
    if script != null:
        var script_path: String = script.resource_path
        if "grenade" in script_path.to_lower():
            _log("Freezing newly created grenade: %s" % node.name)
            _freeze_grenade(node as RigidBody2D)
            return
```

Added tracking for frozen grenades:
- `_frozen_grenades` array to track grenades frozen during the effect
- `_freeze_grenade()` function to freeze a grenade's processing and physics
- `_unfreeze_grenades()` function to restore grenade processing when effect ends

Also updated `_freeze_node_except_player()` to track grenades that already exist when the effect starts.

## Files Modified

1. `scripts/autoload/last_chance_effects_manager.gd`
   - Added `_frozen_grenades` array (line 66)
   - Extended `_freeze_node_except_player()` to log frozen grenades (lines 489-492)
   - Extended `_on_node_added_during_freeze()` to detect grenades (lines 795-803)
   - Added `_freeze_grenade()` function (lines 750-768)
   - Added `_unfreeze_grenades()` function (lines 771-786)
   - Updated `_unfreeze_time()` to call `_unfreeze_grenades()` (lines 574-575)
   - Updated `reset_effects()` to clear `_frozen_grenades` (line 857)

## Testing

The fix ensures that:
1. Grenades existing when LastChance starts are frozen
2. Grenades created during LastChance are immediately frozen
3. All grenades resume normal operation when LastChance ends
4. Grenade timers do not count down during frozen time
5. Grenade physics movement stops during frozen time

## Lessons Learned

1. When implementing time-freeze mechanics, ALL projectile types must be handled, not just bullets
2. Both existing nodes AND newly created nodes need to be considered
3. Node detection logic should use extensible patterns (script path checking) rather than hardcoded type checks
