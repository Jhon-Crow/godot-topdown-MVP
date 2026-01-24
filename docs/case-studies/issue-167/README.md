# Case Study: Issue #167 - Special "Last Chance" Effect Not Working on Hard Difficulty

## Summary

The special "last chance" time-freeze effect for hard difficulty was not triggering when the player had 1 HP or less. Instead, the regular penultimate hit effect was being used in all cases.

## Root Cause

The bug was caused by **GDScript-C# interoperability issues** when trying to access the C# `HealthComponent.CurrentHealth` property from GDScript.

### Technical Details

In `last_chance_effects_manager.gd`, the `_get_player_health()` function attempted to read the player's current health from the C# `HealthComponent`:

```gdscript
var health_component: Node = _player.get_node_or_null("HealthComponent")
if health_component != null:
    if health_component.has_method("get") and health_component.get("CurrentHealth") != null:
        return health_component.get("CurrentHealth")
    if "CurrentHealth" in health_component:
        return health_component.CurrentHealth
```

However, this always returned `0.0` because:
1. The `get("CurrentHealth")` method doesn't work correctly for C# properties exposed to GDScript
2. The direct property access `health_component.CurrentHealth` also failed silently

### Evidence from Logs

From `game_log_20260121_105319.txt`:
```
[10:53:27] [INFO] [LastChance] Threat detected: @Area2D@538
[10:53:27] [INFO] [LastChance] Player health is 0.0 - effect requires exactly 1 HP or less but alive
[10:53:27] [INFO] [LastChance] Cannot trigger effect - conditions not met
[10:53:27] [INFO] [PenultimateHit] Player damaged: 1.0 damage, current health: 3.0
```

The log shows:
- `LastChanceEffectsManager` read player health as `0.0` (incorrect)
- `PenultimateHitEffectsManager` correctly received health as `3.0` from the `Damaged` signal

When player reached 1 HP:
```
[10:53:31] [INFO] [PenultimateHit] Player damaged: 1.0 damage, current health: 1.0
[10:53:31] [INFO] [PenultimateHit] Triggering penultimate hit effect (HP: 1.0)
...
[10:53:31] [INFO] [LastChance] Threat detected: @Area2D@818
[10:53:31] [INFO] [LastChance] Player health is 0.0 - effect requires exactly 1 HP or less but alive
```

The `LastChanceEffectsManager` still read `0.0` instead of `1.0`.

## Working Solution (penultimate_hit_effects_manager.gd)

The `penultimate_hit_effects_manager.gd` works correctly because it **caches the health from the signal parameters**:

```gdscript
func _on_player_damaged(amount: float, current_health: float) -> void:
    _log("Player damaged: %.1f damage, current health: %.1f" % [amount, current_health])
    _check_penultimate_state(current_health)  # Uses the signal parameter directly
```

The C# `Damaged` signal emits: `EmitSignal(SignalName.Damaged, actualDamage, CurrentHealth);`

## Fix Applied

Modified `last_chance_effects_manager.gd` to:

1. **Added a cached health variable:**
   ```gdscript
   var _player_current_health: float = 0.0
   ```

2. **Cache health from signals instead of querying the component:**
   ```gdscript
   func _on_player_damaged(_amount: float, current_health: float) -> void:
       _player_current_health = current_health
       _log("Player health updated (C# Damaged): %.1f" % _player_current_health)
   ```

3. **Connected to HealthComponent.HealthChanged signal for initial value:**
   ```gdscript
   if health_component != null and health_component.has_signal("HealthChanged"):
       health_component.HealthChanged.connect(_on_health_changed)
   ```

4. **Use cached value in `_can_trigger_effect()`:**
   ```gdscript
   if _player_current_health > 1.0 or _player_current_health <= 0.0:
       _log("Player health is %.1f - effect requires..." % _player_current_health)
       return false
   ```

## Timeline of Events

1. Player starts game on hard difficulty with full health (4 HP)
2. Health updates are received via `HealthChanged`/`Damaged` signals but were NOT being cached
3. Player takes damage, health decreases to 1 HP
4. Enemy bullet enters threat sphere
5. `_can_trigger_effect()` is called
6. `_get_player_health()` tries to read from HealthComponent - returns 0.0 (BUG)
7. Condition `current_health <= 0.0` is true (incorrectly), effect doesn't trigger
8. Regular penultimate effect triggers instead

## Lesson Learned

When working with C#/GDScript interoperability in Godot:
- **Prefer signal parameters over direct property access** for cross-language communication
- **Cache values from signals** when they need to be accessed later
- Direct property access from GDScript to C# nodes may fail silently and return default values

## Files Changed

- `scripts/autoload/last_chance_effects_manager.gd`

## Follow-up Issue: Player Cannot Move During Time Freeze

### Symptom

After the initial fix for health detection, the time-freeze effect triggered correctly, but the player was unable to move or aim during the 6-second freeze period.

### Root Cause

The initial implementation used `Engine.time_scale = 0` to freeze time, with `PROCESS_MODE_ALWAYS` set on the player to allow processing. However, this approach has a critical flaw:

**When `Engine.time_scale = 0`, the physics delta becomes 0.** This affects:
1. `_PhysicsProcess(delta)` receives `delta = 0`
2. `ApplyMovement()` multiplies velocity by delta, resulting in no movement
3. `MoveAndSlide()` doesn't move the character when physics delta is 0

Even though the player node had `PROCESS_MODE_ALWAYS`, the physics system effectively stopped working.

### Evidence from Logs

From `logs-batch4/game_log_20260121_112817.txt`:
```
[11:28:39] [INFO] [LastChance] Triggering last chance effect!
[11:28:39] [INFO] [LastChance] Starting last chance effect:
[11:28:39] [INFO] [LastChance]   - Time will be frozen (except player)
[11:28:39] [INFO] [LastChance]   - Duration: 6.0 real seconds
[11:28:39] [INFO] [LastChance] Player and all children process_mode set to ALWAYS
...
[11:28:45] [INFO] [LastChance] Effect duration expired after 6.00 real seconds
```

The effect lasted exactly 6 seconds as intended, but the player reported they couldn't move during this time.

### Solution (Initial Attempt - Still Broken)

Initially, we tried replacing `Engine.time_scale = 0` with node-based freezing:

1. **Keep `Engine.time_scale` at 1.0** - Physics delta remains normal
2. **Disable processing on all scene nodes** except the player
3. **Skip autoloads** (AudioManager, FileLogger, etc.)
4. **Skip the player node** - Don't set it to DISABLED

However, this still didn't work because of **Godot's process mode inheritance**.

## Follow-up Issue 2: Process Mode Inheritance

### Symptom

Even after implementing node-based freezing (instead of `Engine.time_scale = 0`), the player still couldn't move during the time freeze effect.

### Root Cause Analysis

The logs showed:
```
[11:41:37] [INFO] [LastChance] Skipping player node: Player
[11:41:37] [INFO] [LastChance] Froze all nodes except player and autoloads
```

The code was correctly **skipping** the player node - it didn't set the player to `DISABLED`. But the player still couldn't move. Why?

**The issue was Godot's process mode inheritance:**

1. The player's **parent** (the main scene root) was being set to `PROCESS_MODE_DISABLED`
2. The player node has `PROCESS_MODE_INHERIT` by default
3. When a node has `INHERIT`, it inherits the effective process mode from its parent
4. Since the parent was `DISABLED`, the player inherited `DISABLED` state
5. Therefore, `_PhysicsProcess()` was never called on the player

**Simply not disabling the player node is not enough - we need to explicitly set the player to `PROCESS_MODE_ALWAYS` to override the inherited disabled state from its parent.**

### Solution (Fixed)

The correct approach requires two steps:

1. **First, set the player AND ALL its children to `PROCESS_MODE_ALWAYS`**
   - This overrides the inherited disabled state
   - Must include children (weapon, input handler, animations, etc.)

2. **Then, freeze all other nodes**
   - Skip the player (already handled above)
   - Skip autoloads

```gdscript
func _freeze_time() -> void:
    # CRITICAL FIX: First, set player and all children to PROCESS_MODE_ALWAYS
    # This MUST happen BEFORE freezing the scene, because:
    # 1. The player's parent (scene root) will be set to DISABLED
    # 2. By default, player has INHERIT, which would inherit DISABLED
    # 3. Setting to ALWAYS overrides the parent's disabled state
    if _player != null:
        _enable_player_processing_always(_player)

    # Then freeze all other nodes
    var root := get_tree().root
    for child in root.get_children():
        if child.name in ["FileLogger", "AudioManager", ...]:
            continue  # Skip autoloads
        _freeze_node_except_player(child)

func _enable_player_processing_always(node: Node, depth: int = 0) -> void:
    # Store original process mode for restoration
    _original_process_modes[node] = node.process_mode

    # Set to ALWAYS to override inherited DISABLED
    node.process_mode = Node.PROCESS_MODE_ALWAYS

    # Recursively enable all children (weapon, animations, etc.)
    for child in node.get_children():
        _enable_player_processing_always(child, depth + 1)
```

### Key Insight

The difference between:
- **Not setting to DISABLED** - Node uses INHERIT → inherits DISABLED from parent → NOT processing
- **Setting to ALWAYS** - Node explicitly overrides → processes regardless of parent state

### Files Changed

- `scripts/autoload/last_chance_effects_manager.gd` - Added `_enable_player_processing_always()` function

### Expected Logs After Fix

```
[LastChance] Player health updated (C# Damaged): 1.0
[LastChance] Threat detected: Bullet
[LastChance] Triggering last chance effect!
[LastChance] Set player Player and all 15 children to PROCESS_MODE_ALWAYS
[LastChance] Skipping player node: Player
[LastChance] Froze all nodes except player and autoloads
```

## Follow-up Issue 3: Player Passing Through Walls

### Symptom

After fixing the process mode inheritance issue, the player could move during the time freeze, but they were passing through walls and obstacles.

### Root Cause Analysis

From `logs-round5/game_log_20260121_115113.txt`:
```
[11:51:38] [INFO] [LastChance] Triggering last chance effect!
[11:51:38] [INFO] [LastChance] Set player Player and all 11 children to PROCESS_MODE_ALWAYS
[11:51:38] [INFO] [LastChance] Froze all nodes except player and autoloads
```

The time freeze effect set all non-player nodes to `PROCESS_MODE_DISABLED`, including `StaticBody2D` nodes (walls and obstacles).

In Godot's physics system:
1. `CharacterBody2D.MoveAndSlide()` performs collision detection using the physics server
2. When a `StaticBody2D` has `PROCESS_MODE_DISABLED`, its collision shapes are still registered but the physics interactions may not work correctly
3. The player's physics queries against frozen static bodies failed, allowing the player to phase through walls

### Solution

Modified `_freeze_node_except_player()` to skip `StaticBody2D` nodes:

```gdscript
func _freeze_node_except_player(node: Node) -> void:
    # ... existing checks ...

    # CRITICAL: Skip StaticBody2D nodes (walls, obstacles) to preserve collision detection!
    # If we freeze static bodies, the player's CharacterBody2D.MoveAndSlide() won't
    # detect collisions with them and the player will pass through walls.
    if node is StaticBody2D:
        # Don't freeze the static body, but still process its children (visual elements, etc.)
        for child in node.get_children():
            _freeze_node_except_player(child)
        return

    # ... rest of function ...
```

### Why This Works

1. `StaticBody2D` nodes (walls, obstacles) don't have scripted behavior that needs to be frozen
2. They are purely collision bodies that the physics system uses for collision detection
3. Keeping them active (not DISABLED) allows the player's `MoveAndSlide()` to properly detect collisions
4. Child nodes (ColorRect for visual appearance) can still be frozen if needed

### Files Changed

- `scripts/autoload/last_chance_effects_manager.gd` - Added `StaticBody2D` check in `_freeze_node_except_player()`

## Follow-up Issue 4: Player STILL Passing Through Walls (Container Node Inheritance)

### Symptom

After the previous fix to skip `StaticBody2D` nodes, the player was still passing through walls during the time freeze effect.

### Log File Evidence

From `logs/game_log_20260121_124527.txt`:
```
[12:45:41] [INFO] [LastChance] Triggering last chance effect!
[12:45:41] [INFO] [LastChance] Set player Player and all 11 children to PROCESS_MODE_ALWAYS
[12:45:41] [INFO] [LastChance] Skipping player node: Player
[12:45:41] [INFO] [LastChance] Froze all nodes except player and autoloads
```

During the time freeze (12:45:41 to 12:45:47), the player was shooting from positions like:
- `(120.7353, 402.4353)`
- `(115.875, 388.4586)`
- `(114.6823, 385.0285)`

These positions are near the left wall boundary (x=64), and the user reported the player could pass through walls.

### Root Cause Analysis (Deep Dive)

The previous fix only **skipped** `StaticBody2D` nodes (didn't set them to DISABLED). However, the issue was more fundamental:

**Problem with container nodes:**
1. The scene hierarchy is: `BuildingLevel` → `Environment` (Node2D) → `Walls` (Node2D) → `WallTop` (StaticBody2D)
2. The code set `Environment` to `PROCESS_MODE_DISABLED` **before** processing its children
3. Then it set `Walls` to `PROCESS_MODE_DISABLED`
4. When it reached `WallTop` (StaticBody2D), it was correctly skipped
5. **BUT** the parent containers (`Environment`, `Walls`) were already DISABLED!

**Why skipping isn't enough:**
Even though we didn't set `StaticBody2D` to DISABLED, when parent nodes are DISABLED, their children's physics behavior can be affected because:
- Process mode inheritance in Godot affects how nodes interact with the engine systems
- Physics collision detection relies on the node hierarchy being in a valid processing state
- Container nodes being DISABLED can affect how `MoveAndSlide()` queries the physics server

### Research Findings

From web research on Godot 4 physics and process modes:
- [Godot Forum: Collision shape and process_mode can't work together](https://forum.godotengine.org/t/collision-shape-and-process-mode-cant-work-togheter/106657)
- [Godot GitHub Issue: Pause breaks move_and_collide collision detection](https://forum.godotengine.org/t/bug-pausing-breaks-move-and-collide-collision-detection/6936)
- [Godot GitHub Issue: Disabling process of PhysicsBody2D](https://github.com/godotengine/godot/issues/76219)

Key insight: In Godot 4, `PROCESS_MODE_DISABLED` on a parent node affects how the physics server processes its children, even if those children have different process modes set.

### Solution: Selective Node Freezing

Instead of setting ALL nodes to DISABLED (except specific ones), we now use a **selective approach**:

1. **Container nodes (Node2D, Node, Control)** → **DON'T DISABLE** - just recurse into children
2. **StaticBody2D (walls)** → Set to `PROCESS_MODE_ALWAYS` to ensure collision detection
3. **CollisionShape2D** → Set to `PROCESS_MODE_ALWAYS` to keep collision shapes active
4. **CharacterBody2D (enemies)** → Set to `PROCESS_MODE_DISABLED` to freeze them
5. **RigidBody2D (physics objects)** → Set to `PROCESS_MODE_DISABLED`
6. **Area2D (triggers, bullets)** → Set to `PROCESS_MODE_DISABLED`

**Key insight:** By NOT disabling container nodes, we preserve the physics tree hierarchy. The physics server can properly process collision queries because the node hierarchy remains intact.

### Implementation

```gdscript
func _freeze_node_except_player(node: Node) -> void:
    # ... existing checks for player ...

    # Handle physics collision bodies - set to ALWAYS to preserve collision detection
    if node is StaticBody2D:
        _original_process_modes[node] = node.process_mode
        node.process_mode = Node.PROCESS_MODE_ALWAYS
        _log("Set StaticBody2D '%s' to PROCESS_MODE_ALWAYS for collision" % node.name)
        for child in node.get_children():
            _freeze_node_except_player(child)
        return

    # CollisionShape2D nodes need ALWAYS to stay active
    if node is CollisionShape2D:
        _original_process_modes[node] = node.process_mode
        node.process_mode = Node.PROCESS_MODE_ALWAYS
        return

    # Freeze CharacterBody2D nodes that are NOT the player (enemies)
    if node is CharacterBody2D:
        _original_process_modes[node] = node.process_mode
        node.process_mode = Node.PROCESS_MODE_DISABLED
        for child in node.get_children():
            _freeze_node_except_player(child)
        return

    # Freeze RigidBody2D and Area2D nodes
    if node is RigidBody2D or node is Area2D:
        _original_process_modes[node] = node.process_mode
        node.process_mode = Node.PROCESS_MODE_DISABLED
        for child in node.get_children():
            _freeze_node_except_player(child)
        return

    # For container nodes (Node2D, Node, Control, etc.), DON'T set to DISABLED
    # Just recurse into children to find actual freezable nodes
    # This preserves the physics tree structure and allows collision detection to work
    for child in node.get_children():
        _freeze_node_except_player(child)
```

### Why This Works

1. **Container nodes remain in INHERIT mode** - they don't affect their children's physics
2. **StaticBody2D nodes are ALWAYS** - collision detection works regardless of parent state
3. **CollisionShape2D nodes are ALWAYS** - collision shapes remain active
4. **Enemies (CharacterBody2D) are DISABLED** - they freeze in place
5. **Bullets (Area2D) are DISABLED** - they freeze mid-flight
6. **The physics tree hierarchy is preserved** - `MoveAndSlide()` can properly query collisions

### Files Changed

- `scripts/autoload/last_chance_effects_manager.gd` - Complete rewrite of `_freeze_node_except_player()` function

### Expected Logs After Fix

```
[LastChance] Player health updated (C# Damaged): 1.0
[LastChance] Threat detected: Bullet
[LastChance] Triggering last chance effect!
[LastChance] Set player Player and all 11 children to PROCESS_MODE_ALWAYS
[LastChance] Set StaticBody2D 'WallTop' to PROCESS_MODE_ALWAYS for collision
[LastChance] Set StaticBody2D 'WallBottom' to PROCESS_MODE_ALWAYS for collision
[LastChance] Set StaticBody2D 'WallLeft' to PROCESS_MODE_ALWAYS for collision
[LastChance] Set StaticBody2D 'WallRight' to PROCESS_MODE_ALWAYS for collision
[LastChance] Skipping player node: Player
[LastChance] Froze all nodes except player and autoloads
```

## Testing Instructions

1. Start the game on **Hard** difficulty
2. Take damage until you have **1 HP**
3. Wait for an enemy bullet to fly toward you
4. **Expected:** Blue sepia time-freeze effect should trigger
5. **Expected:** Player should be able to MOVE and AIM during the freeze
6. **Expected:** Player should NOT be able to pass through walls
7. **Expected:** All enemies and bullets should be completely frozen
8. **Expected logs should show:**
   - StaticBody2D nodes set to PROCESS_MODE_ALWAYS
   - Player and children set to PROCESS_MODE_ALWAYS
   - No errors about collision detection
