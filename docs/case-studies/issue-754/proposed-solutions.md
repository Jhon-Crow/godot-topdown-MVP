# Proposed Solutions for Issue #754

## Solution 1: MuzzleFlashDetectionComponent (Recommended)

### Overview
Create a new detection component that follows the pattern established by `FlashlightDetectionComponent`. This component tracks active muzzle flashes from the player's weapon and allows enemies to detect them when they have line-of-sight.

### Advantages
- Follows existing codebase patterns
- Clean separation of concerns
- Easy to test independently
- Integrates naturally with GOAP
- Configurable confidence levels

### Implementation Steps

1. **Modify ImpactEffectsManager** to track active muzzle flashes
2. **Create MuzzleFlashDetectionComponent** class
3. **Add ShootAtMuzzleFlashAction** to GOAP actions
4. **Integrate into Enemy** class

### Code Examples

See `CASE_STUDY.md` for complete code examples.

---

## Solution 2: Sound-Based Flash Notification (Alternative)

### Overview
Instead of visual detection, extend the existing `SoundPropagation` system to include muzzle flash position data with gunshot sounds.

### Implementation
```gdscript
# In sound_propagation.gd
func emit_sound_with_visual(
    sound_type: SoundType,
    position: Vector2,
    source_type: SourceType,
    source_node: Node2D = null,
    custom_range: float = -1.0,
    visual_position: Vector2 = Vector2.ZERO,  # Flash position
    visual_direction: Vector2 = Vector2.ZERO   # Flash direction
) -> void:
    # ...existing sound propagation...

    # Additionally notify about visual cue
    for listener in _listeners:
        if listener.has_method("on_visual_cue_detected"):
            listener.on_visual_cue_detected(
                visual_position,
                visual_direction,
                sound_type
            )
```

### Advantages
- Minimal new code
- Reuses existing propagation system

### Disadvantages
- Conflates sound and visual systems
- Less realistic (sound travels differently than light)
- No FOV check for visual detection

---

## Solution 3: Global Muzzle Flash Manager (Alternative)

### Overview
Create a dedicated autoload singleton for managing muzzle flash events that enemies can subscribe to.

### Implementation
```gdscript
# scripts/autoload/muzzle_flash_manager.gd
extends Node

signal muzzle_flash_emitted(position: Vector2, direction: Vector2, source: Node2D)

var _active_flashes: Array[Dictionary] = []

func emit_flash(position: Vector2, direction: Vector2, source: Node2D) -> void:
    _active_flashes.append({
        "position": position,
        "direction": direction,
        "timestamp": Time.get_ticks_msec() / 1000.0,
        "source": source
    })
    muzzle_flash_emitted.emit(position, direction, source)

func _process(delta: float) -> void:
    # Clean up old flashes
    var current := Time.get_ticks_msec() / 1000.0
    _active_flashes = _active_flashes.filter(
        func(f): return current - f.timestamp < 0.5
    )

func get_flashes_visible_from(pos: Vector2, max_range: float) -> Array:
    # Return flashes within range and visibility
    return _active_flashes.filter(
        func(f): return pos.distance_to(f.position) <= max_range
    )
```

### Advantages
- Centralized flash management
- Easy global access
- Signal-based for real-time updates

### Disadvantages
- New autoload singleton
- More architectural changes required
- May be overkill for the feature

---

## Recommended Approach: Solution 1

Solution 1 (MuzzleFlashDetectionComponent) is recommended because:

1. **Consistency**: Follows the same pattern as `FlashlightDetectionComponent`
2. **Minimal Impact**: Changes are localized to specific files
3. **Testability**: Component can be tested in isolation
4. **GOAP Integration**: Clean action-based behavior
5. **Realism**: Includes FOV and line-of-sight checks

---

## Integration Points

### Files to Modify

| File | Change Type | Description |
|------|-------------|-------------|
| `scripts/autoload/impact_effects_manager.gd` | Modify | Add flash tracking |
| `scripts/ai/enemy_actions.gd` | Modify | Add new GOAP action |
| `scripts/objects/enemy.gd` | Modify | Add detection component |

### Files to Create

| File | Description |
|------|-------------|
| `scripts/components/muzzle_flash_detection_component.gd` | New detection component |

### GOAP World State Changes

New state variables:
- `muzzle_flash_detected: bool` - Whether enemy currently sees a muzzle flash
- `muzzle_flash_position: Vector2` - Position of detected flash (optional)

---

## Testing Strategy

### Unit Tests

1. Test MuzzleFlashDetectionComponent in isolation
2. Verify FOV calculations
3. Verify line-of-sight checks
4. Verify confidence level updates

### Integration Tests

1. Test enemy detects flash when player fires behind cover
2. Test enemy does NOT detect when grenade is being thrown
3. Test enemy memory updates with correct confidence
4. Test GOAP planner selects correct action

### Manual Testing

1. Place enemy with FOV facing player's cover position
2. Have player fire from behind cover
3. Observe enemy shooting at muzzle flash location
4. Verify enemy stops shooting when player throws grenade
5. Test with different weapon types (all should work)

---

## Configuration Options

Consider making these values configurable:

```gdscript
## Detection confidence (how certain enemy is about position)
@export var muzzle_flash_confidence: float = 0.65

## Maximum detection range in pixels
@export var muzzle_flash_range: float = 500.0

## Number of suppressive fire rounds
@export var suppressive_fire_count: int = 3

## Spread angle for suppressive fire (radians)
@export var suppressive_fire_spread: float = 0.2
```

---

## Future Enhancements

1. **Multiple Flash Tracking**: Track and prioritize multiple flashes
2. **Weapon-Specific Detection**: Different flash sizes for different weapons
3. **Team Communication**: Share flash detection with nearby allies
4. **Suppression Duration**: Variable suppression based on threat level
5. **Flash Intensity**: Larger/brighter flashes easier to detect

---

## Related Libraries and Tools

### Godot Addons
- [Godot GOAP](https://github.com/GDQuest/godot-ai-examples) - GOAP examples
- [limboai](https://github.com/limbonaut/limboai) - Behavior trees (alternative)

### Design References
- F.E.A.R. AI (GOAP origin)
- ARMA series (muzzle flash detection)
- GROUND BRANCH (suppressive fire AI)
