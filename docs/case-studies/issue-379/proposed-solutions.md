# Proposed Solutions - Issue #379: Suspicion-Based Grenade Throwing

## Executive Summary

This document proposes three solution approaches for implementing "enemy throws grenade on suspicion" functionality. All solutions leverage the existing `EnemyMemory` confidence system and integrate with the current 6-trigger grenade system.

---

## Solution 1: Minimal Integration (Recommended)

### Description
Add Trigger 7 as a simple extension to the existing trigger system, using the memory's `is_high_confidence()` check.

### Implementation

```gdscript
# New constants
const GRENADE_SUSPICION_HIDDEN_TIME: float = 3.0

# New state variable
var _high_suspicion_hidden_timer: float = 0.0

# Update function
func _update_trigger_suspicion(delta: float) -> void:
    if _memory != null and _memory.is_high_confidence() and not _can_see_player:
        _high_suspicion_hidden_timer += delta
    else:
        _high_suspicion_hidden_timer = 0.0

# Check function
func _should_trigger_suspicion_grenade() -> bool:
    return (_memory != null and
            _memory.is_high_confidence() and
            not _can_see_player and
            _high_suspicion_hidden_timer >= GRENADE_SUSPICION_HIDDEN_TIME)
```

### Pros
- Minimal code changes (~50 lines)
- Uses existing memory system unchanged
- Easy to test and debug
- Consistent with existing trigger patterns

### Cons
- No assault follow-up behavior
- Basic threshold logic only

### Estimated Effort
- Development: 1-2 hours
- Testing: 1 hour

---

## Solution 2: Full Feature with Assault

### Description
Implement Trigger 7 with automatic transition to ASSAULT state after grenade throw, fulfilling the "и штурмовать" (and assault) part of the request.

### Implementation

Builds on Solution 1, plus:

```gdscript
# Track if we just threw a suspicion grenade
var _suspicion_grenade_thrown: bool = false
var _suspicion_grenade_target: Vector2 = Vector2.ZERO

func _execute_grenade_throw(target_position: Vector2) -> void:
    # ... existing throw code ...

    # Mark for assault follow-up if this was suspicion-triggered
    if _should_trigger_suspicion_grenade():
        _suspicion_grenade_thrown = true
        _suspicion_grenade_target = target_position

func _handle_post_grenade_assault() -> void:
    if not _suspicion_grenade_thrown:
        return

    # Transition to assault state
    _current_state = AIState.ASSAULT
    _assault_target_position = _suspicion_grenade_target
    _suspicion_grenade_thrown = false
    _log_grenade("Assaulting after suspicion grenade toward %s" % _assault_target_position)
```

### Assault Timing Options

**Option A**: Immediate assault
```gdscript
# In _execute_grenade_throw, after throw animation
_handle_post_grenade_assault()
```

**Option B**: Delayed assault (wait for explosion)
```gdscript
# Use timer or await
var timer := get_tree().create_timer(1.5)  # Frag grenade flight time
timer.timeout.connect(_handle_post_grenade_assault)
```

### Pros
- Complete implementation of issue request
- Creates tactical "flush and assault" behavior
- Aligns with F.E.A.R. AI patterns

### Cons
- More complex state management
- Potential for state machine conflicts
- Need to handle edge cases (player moved, enemy killed, etc.)

### Estimated Effort
- Development: 3-4 hours
- Testing: 2 hours

---

## Solution 3: GOAP Action Integration

### Description
Implement as a full GOAP action with dynamic cost based on confidence level, allowing the AI planner to choose grenade throwing as part of larger tactical plans.

### Implementation

**New GOAP Action**: `GrenadeFlushSuspicion`

```gdscript
# In enemy_actions.gd
class GrenadeFlushSuspicionAction extends GOAPAction:
    func get_name() -> String:
        return "GrenadeFlushSuspicion"

    func get_cost(world_state: Dictionary) -> float:
        # Dynamic cost based on confidence
        var confidence: float = world_state.get("suspicion_confidence", 0.0)
        # Higher confidence = lower cost (more likely to use)
        return 1.0 - (confidence * 0.5)  # Range: 0.5-1.0

    func get_preconditions() -> Dictionary:
        return {
            "has_grenades": true,
            "grenade_cooldown_ready": true,
            "has_suspected_position": true,
            "can_see_player": false,
            "suspicion_confidence_high": true
        }

    func get_effects() -> Dictionary:
        return {
            "suspected_position_flushed": true,
            "grenade_thrown": true
        }

    func execute(enemy: Node2D) -> bool:
        return enemy.try_throw_grenade()
```

**GOAP Goal Chain**:
```
Goal: "FlushAndAssault"
├── Action: GrenadeFlushSuspicion
│   └── Effect: suspected_position_flushed = true
└── Action: AssaultPosition
    └── Precondition: suspected_position_flushed = true
```

### Pros
- Most flexible and extensible
- Integrates with existing GOAP planner
- Can be combined with other actions
- Confidence affects action priority

### Cons
- Most complex implementation
- Requires GOAP system modifications
- Harder to predict exact behavior

### Estimated Effort
- Development: 4-6 hours
- Testing: 3 hours

---

## Comparison Matrix

| Criteria | Solution 1 | Solution 2 | Solution 3 |
|----------|-----------|-----------|-----------|
| Complexity | Low | Medium | High |
| Fulfills Issue | Partial | Full | Full |
| Maintenance | Easy | Moderate | Harder |
| Testing | Simple | Moderate | Complex |
| Extensibility | Limited | Good | Excellent |
| Risk | Low | Medium | Medium-High |
| Time to implement | 2-3 hours | 5-6 hours | 7-9 hours |

---

## Recommendation

**Recommended Approach: Solution 1 (Minimal Integration)**

### Rationale

1. **Simplicity**: Follows the pattern of existing triggers
2. **Low Risk**: Self-contained changes, easy to roll back
3. **Quick Delivery**: Can be implemented and tested quickly
4. **Extensible**: Solution 2 can be added later if assault behavior is needed

### Implementation Path

1. Implement Solution 1 (Trigger 7 only)
2. Test and merge
3. If assault behavior is explicitly requested, add Solution 2 as follow-up PR

---

## Existing Components/Libraries

### Already in Codebase

| Component | File | Reuse for Issue #379 |
|-----------|------|---------------------|
| EnemyMemory | `scripts/ai/enemy_memory.gd` | Use `is_high_confidence()`, `suspected_position` |
| Vision Component | `scripts/components/vision_component.gd` | Use for visibility checks |
| Grenade System | `scripts/objects/enemy.gd` | Extend with Trigger 7 |
| GOAP Planner | `scripts/ai/goap_planner.gd` | Optional integration |
| ASSAULT State | `scripts/objects/enemy.gd` | Use for follow-up behavior |

### External Libraries (Not Required)

The existing implementation is self-contained. No external libraries are needed. For reference:

- **LimboAI** (https://github.com/limbonaut/limboai) - Behavior trees for Godot 4
- **Beehave** (https://github.com/bitbrain/beehave) - Another behavior tree addon

These could provide more sophisticated AI planning but would require significant refactoring.

---

## Configuration Recommendations

### Suggested Default Values

```gdscript
## Trigger 7 configuration
@export var grenade_suspicion_enabled: bool = true
@export var grenade_suspicion_confidence_threshold: float = 0.8
@export var grenade_suspicion_hidden_time: float = 3.0
```

### DifficultyManager Integration

| Difficulty | Hidden Time | Notes |
|------------|-------------|-------|
| Easy | 5.0 seconds | More time to relocate |
| Normal | 3.0 seconds | Default |
| Hard | 2.0 seconds | Aggressive flushing |

---

*Proposed solutions document created: 2026-01-25*
