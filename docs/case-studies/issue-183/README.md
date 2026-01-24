# Issue #183: Fix Grenade Position Bug

## Problem Statement

The grenade is periodically thrown from the **activation position** (where the player pulled the pin) instead of the **player's current position** (where the player is when throwing).

Russian: "сейчас граната периодически бросается с позиции активации, а не с позиции игрока"

## Timeline of Events (from logs)

### Log 1 (game_log_20260121_201747.txt)
- Player at spawn position (450, 1250)
- Grenade prepared and dropped at feet (not thrown)

### Log 2 (game_log_20260121_201759.txt)
- **First throw:** Player at (360.78598, 1163.6112), successful throw
- **Second throw:** Player at (450, 1250) - spawn position, successful throw

### Log 3 (game_log_20260121_201843.txt)
- Multiple grenade throws observed
- Some grenades landing at unexpected positions

## Root Cause Analysis

### Previous Fix (Commit 34b7f68)
A previous fix addressed a related issue where `global_position` was being set **before** `add_child()`. In Godot, `global_position` only works correctly when the node is already in the scene tree. The fix reordered operations:

```gdscript
# BEFORE (bug):
_active_grenade.global_position = global_position  # Doesn't work - node not in tree
get_tree().current_scene.add_child(_active_grenade)

# AFTER (fix):
get_tree().current_scene.add_child(_active_grenade)  # Add to tree first
_active_grenade.global_position = global_position    # Now this works
```

This fix was applied to both `player.gd` and `Player.cs`.

### Current Root Cause: RigidBody2D Physics Interference

The grenade (`GrenadeBase`) extends `RigidBody2D`. When a `RigidBody2D` is active (not frozen), the physics engine continuously updates its position. This can cause **race conditions**:

1. **Creation phase:**
   - Grenade is instantiated and added to scene
   - `global_position` is set to player position
   - Physics engine might process a step and reset/modify position

2. **Hold phase:**
   - Player code updates `_active_grenade.global_position = global_position` every frame
   - Physics engine is also running, potentially causing conflicts

3. **Throw phase:**
   - Position is set before applying velocity
   - Physics engine might process differently depending on timing

### Why It's Intermittent

The bug is intermittent because it depends on the **exact timing** of when manual position updates occur relative to physics engine steps. If they happen to align poorly, the physics engine can overwrite or ignore the manual position setting.

## Solution

Freeze the `RigidBody2D` while the grenade is being held by the player. This prevents the physics engine from interfering with manual position updates. Unfreeze it only when thrown.

### Implementation Changes

1. **GrenadeBase (`grenade_base.gd`):**
   - Add `freeze = true` in `_ready()` to start frozen
   - Add method to unfreeze when thrown

2. **Player (`player.gd` and `Player.cs`):**
   - Unfreeze the grenade when calling `throw_grenade()`

This approach ensures:
- No physics interference while grenade follows player
- Clean handoff to physics when thrown
- Position is always accurate at throw time

## Files Changed

- `scripts/projectiles/grenade_base.gd` - Add freeze logic
- `scripts/characters/player.gd` - Unfreeze on throw
- `Scripts/Characters/Player.cs` - Unfreeze on throw (C# version)

## Testing

After the fix, the grenade should:
1. Always be created at the player's current position
2. Follow the player exactly while held (no jitter/offset)
3. Be thrown from the player's current position, not the activation position
4. Have correct physics after being thrown (velocity, friction, etc.)
