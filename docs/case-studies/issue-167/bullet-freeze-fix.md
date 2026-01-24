# Issue 167 Case Study: Bullet Freezing and Quick Restart During Last Chance Effect

## Problem Description

After implementing the last chance time freeze effect, two issues were reported:

1. **Bullets not freezing properly**: Player-fired bullets during the time freeze would continue moving instead of freezing in place
2. **Quick restart not working**: The Q key for quick restart didn't work during the time freeze effect

## Root Cause Analysis

### Bullet Freezing Issue

The bullet freezing issue had two causes:

1. **New bullets added after freeze started**: When the player fires during the time freeze, `BaseWeapon.SpawnBullet()` calls `GetTree().CurrentScene.AddChild(bullet)` to add the bullet to the scene. Since this happens AFTER the freeze started, these newly-spawned bullets were never frozen.

2. **Missing integration**: While `register_frozen_bullet()` existed in the LastChanceEffectsManager, it was never called by the weapon system when firing bullets.

### Quick Restart Issue

The GameManager's `_input()` function handles the Q key for scene restart. During the time freeze:
- The scene nodes were set to `PROCESS_MODE_DISABLED`
- GameManager didn't have `PROCESS_MODE_ALWAYS`, so it would inherit from its parent
- This prevented input processing during the freeze

## Solution

### Fix 1: Automatic Bullet Freezing via Signal

Added a `node_added` signal connection in `_freeze_time()`:

```gdscript
# Connect to node_added signal to freeze any new bullets fired during the freeze
if not get_tree().node_added.is_connected(_on_node_added_during_freeze):
    get_tree().node_added.connect(_on_node_added_during_freeze)
```

The callback `_on_node_added_during_freeze()` automatically:
1. Checks if the new node is a bullet (Area2D with bullet script)
2. Verifies it's a player bullet (shooter_id matches player)
3. Freezes it immediately by calling `register_frozen_bullet()`

### Fix 2: GameManager Always Processing

Added `PROCESS_MODE_ALWAYS` to GameManager:

```gdscript
func _ready() -> void:
    # ... existing code ...
    # Set PROCESS_MODE_ALWAYS to ensure quick restart (Q key) works during time freeze
    process_mode = Node.PROCESS_MODE_ALWAYS
```

Also added GameManager to the autoload exclusion list in `_freeze_time()`:

```gdscript
if child.name in ["FileLogger", "AudioManager", "DifficultyManager",
                   "LastChanceEffectsManager", "PenultimateHitEffectsManager",
                   "GameManager"]:  # Added GameManager
    continue
```

### Fix 3: Proper Signal Cleanup

Added signal disconnection in:
- `_unfreeze_time()` - when effect ends normally
- `reset_effects()` - when scene changes

## Files Modified

1. `scripts/autoload/last_chance_effects_manager.gd`:
   - Added `_on_node_added_during_freeze()` callback function
   - Connected/disconnected `node_added` signal during freeze
   - Added GameManager to autoload exclusion list

2. `scripts/autoload/game_manager.gd`:
   - Added `PROCESS_MODE_ALWAYS` in `_ready()`

## Testing

The fix ensures:
- Player-fired bullets during time freeze are immediately frozen
- Bullets unfreeze when the time freeze effect ends
- Quick restart (Q key) works at all times, including during time freeze
- Scene reload properly resets all effects and connections
