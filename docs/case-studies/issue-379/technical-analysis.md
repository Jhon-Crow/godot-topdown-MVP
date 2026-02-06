# Technical Analysis - Issue #379: Suspicion-Based Grenade Throwing

## Current Architecture

### Grenade System Overview

The enemy grenade system is implemented in `scripts/objects/enemy.gd` and follows this architecture:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Physics Frame Update                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  _physics_process(delta)                                        │
│       │                                                          │
│       ├──► _update_grenade_triggers(delta)                      │
│       │         │                                                │
│       │         ├──► _update_trigger_suppression_hidden()       │
│       │         ├──► _update_trigger_pursuit()                  │
│       │         ├──► _update_trigger_sustained_fire()           │
│       │         └──► _update_grenade_world_state()              │
│       │                    │                                     │
│       │                    └──► Sets GOAP flags                  │
│       │                                                          │
│       └──► try_throw_grenade()  (when ready_to_throw_grenade)   │
│                 │                                                │
│                 ├──► _can_throw_grenade()                       │
│                 ├──► _get_grenade_target_position()             │
│                 ├──► Distance and safety checks                  │
│                 └──► _execute_grenade_throw()                   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Trigger Condition Evaluation

Each trigger has three components:
1. **State update function**: Called every frame to track conditions
2. **Check function**: Returns true/false if trigger should fire
3. **World state flag**: Updated for GOAP planning

Current triggers (1-6) defined in `_update_grenade_world_state()`:

```gdscript
func _update_grenade_world_state() -> void:
    _goap_world_state["trigger_1_suppression_hidden"] = _should_trigger_suppression_grenade()
    _goap_world_state["trigger_2_pursuit"] = _should_trigger_pursuit_grenade()
    _goap_world_state["trigger_3_witness_kills"] = _should_trigger_witness_grenade()
    _goap_world_state["trigger_4_sound_based"] = _should_trigger_sound_grenade()
    _goap_world_state["trigger_5_sustained_fire"] = _should_trigger_sustained_fire_grenade()
    _goap_world_state["trigger_6_desperation"] = _should_trigger_desperation_grenade()

    var any_trigger := t1 or t2 or t3 or t4 or t5 or t6
    _goap_world_state["ready_to_throw_grenade"] = cooldown_ready and has_grenades and any_trigger
```

### Enemy Memory Integration

The `EnemyMemory` class provides:

```gdscript
class_name EnemyMemory

var suspected_position: Vector2 = Vector2.ZERO
var confidence: float = 0.0

const HIGH_CONFIDENCE_THRESHOLD: float = 0.8

func is_high_confidence() -> bool:
    return confidence >= HIGH_CONFIDENCE_THRESHOLD

func has_target() -> bool:
    return confidence > LOST_TARGET_THRESHOLD  # 0.05
```

The enemy already uses `_memory` for tracking suspected player position.

---

## Implementation Plan for Trigger 7

### New Constants

Add to existing grenade constants section (around line 638):

```gdscript
## Trigger 7: Suspicion-based grenade throwing
const GRENADE_SUSPICION_CONFIDENCE_THRESHOLD: float = 0.8  # Match EnemyMemory.HIGH_CONFIDENCE_THRESHOLD
const GRENADE_SUSPICION_HIDDEN_TIME: float = 3.0  # Seconds player must be hidden with high suspicion
```

### New State Variable

Add to grenade state variables section (around line 665):

```gdscript
## Trigger 7 state: Tracks time enemy has high suspicion but cannot see player
var _high_suspicion_hidden_timer: float = 0.0
```

### State Update Function

Add new function:

```gdscript
## Update Trigger 7: High suspicion but player is hidden.
func _update_trigger_suspicion(delta: float) -> void:
    if _memory == null:
        _high_suspicion_hidden_timer = 0.0
        return

    # Check if we have high confidence but can't see player
    if _memory.is_high_confidence() and not _can_see_player and _memory.has_target():
        _high_suspicion_hidden_timer += delta
    else:
        # Player visible OR confidence too low - reset timer
        _high_suspicion_hidden_timer = 0.0
```

### Trigger Check Function

Add new function:

```gdscript
## Check Trigger 7: High suspicion + player hidden for threshold time.
## This implements "enemy strongly suspects player is somewhere" from Issue #379.
func _should_trigger_suspicion_grenade() -> bool:
    if _memory == null or not _memory.has_target():
        return false

    # Must have high confidence (0.8+)
    if not _memory.is_high_confidence():
        return false

    # Must not currently see player
    if _can_see_player:
        return false

    # Player must have been hidden for threshold time
    return _high_suspicion_hidden_timer >= GRENADE_SUSPICION_HIDDEN_TIME
```

### Integration Points

#### 1. Update `_update_grenade_triggers()`:

```gdscript
func _update_grenade_triggers(delta: float) -> void:
    # ... existing code ...

    # Update player hidden timer (Trigger 1)
    _update_trigger_suppression_hidden(delta)

    # Update player approach tracking (Trigger 2)
    _update_trigger_pursuit(delta)

    # Update sustained fire tracking (Trigger 5)
    _update_trigger_sustained_fire(delta)

    # NEW: Update suspicion-based tracking (Trigger 7)
    _update_trigger_suspicion(delta)

    # Update GOAP world state with trigger flags
    _update_grenade_world_state()
```

#### 2. Update `_update_grenade_world_state()`:

```gdscript
func _update_grenade_world_state() -> void:
    # ... existing trigger checks ...

    # Trigger 7: Suspicion-based
    var t7 := _should_trigger_suspicion_grenade()
    _goap_world_state["trigger_7_suspicion"] = t7

    # Combined flag for any trigger
    var any_trigger := t1 or t2 or t3 or t4 or t5 or t6 or t7
    _goap_world_state["ready_to_throw_grenade"] = cooldown_ready and has_grenades and any_trigger

    # Update debug logging to include T7
    if _goap_world_state["ready_to_throw_grenade"] and not was_ready:
        var triggers: PackedStringArray = []
        # ... existing triggers ...
        if t7: triggers.append("T7:Suspicion")
        _log_grenade("TRIGGER ACTIVE: %s" % ", ".join(triggers))
```

#### 3. Update `_get_grenade_target_position()`:

Add Trigger 7 case with appropriate priority (suggested: after T4, before T2):

```gdscript
func _get_grenade_target_position() -> Vector2:
    # Priority order from lowest cost (highest priority) to highest cost

    # Trigger 6: Desperation (cost: 0.1)
    if _should_trigger_desperation_grenade():
        # ... existing code ...

    # Trigger 4: Sound-based (cost: 0.2)
    if _should_trigger_sound_grenade():
        return _vulnerable_sound_position

    # Trigger 2: Pursuit (cost: 0.3)
    if _should_trigger_pursuit_grenade():
        # ... existing code ...

    # NEW: Trigger 7: Suspicion (cost: 0.35)
    if _should_trigger_suspicion_grenade():
        if _memory and _memory.has_target():
            return _memory.suspected_position

    # Trigger 3: Witness kills (cost: 0.4)
    if _should_trigger_witness_grenade():
        # ... existing code ...

    # Trigger 5: Sustained fire (cost: 0.5)
    if _should_trigger_sustained_fire_grenade():
        return _fire_zone_center

    # Trigger 1: Suppression hidden (cost: 0.6)
    if _should_trigger_suppression_grenade():
        # ... existing code ...

    return Vector2.ZERO
```

---

## Post-Throw Assault Behavior (Optional Enhancement)

The issue mentions "и штурмовать" (and assault). To implement this:

### Option A: Simple State Transition

After successful grenade throw, force transition to ASSAULT:

```gdscript
func _execute_grenade_throw(target_position: Vector2) -> void:
    # ... existing throw code ...

    # If this was a suspicion-triggered throw, transition to assault
    if _should_trigger_suspicion_grenade():
        _initiate_assault_after_grenade(target_position)

func _initiate_assault_after_grenade(target_position: Vector2) -> void:
    # Wait for grenade to explode (estimated 1-2 seconds for frag)
    await get_tree().create_timer(1.5).timeout

    if _is_alive and not _is_stunned:
        _current_state = AIState.ASSAULT
        _assault_target_position = target_position
        _log_grenade("Initiating assault toward %s after grenade" % target_position)
```

### Option B: GOAP Integration

Add a new GOAP goal/action that becomes available after suspicion grenade:

```gdscript
# In GOAP world state
_goap_world_state["grenade_thrown_at_suspicion"] = true

# New GOAP action: AssaultAfterGrenade
# Precondition: grenade_thrown_at_suspicion = true
# Effect: position = suspicion_target, grenade_thrown_at_suspicion = false
```

---

## Testing Strategy

### Unit Tests

1. **Memory High Confidence Test**
   ```gdscript
   func test_trigger_7_requires_high_confidence() -> void:
       enemy._memory.confidence = 0.7  # Below threshold
       enemy._high_suspicion_hidden_timer = 10.0
       assert_false(enemy._should_trigger_suspicion_grenade())

       enemy._memory.confidence = 0.8  # At threshold
       assert_true(enemy._should_trigger_suspicion_grenade())
   ```

2. **Hidden Time Threshold Test**
   ```gdscript
   func test_trigger_7_requires_hidden_time() -> void:
       enemy._memory.confidence = 1.0
       enemy._can_see_player = false
       enemy._high_suspicion_hidden_timer = 2.0  # Below 3.0
       assert_false(enemy._should_trigger_suspicion_grenade())

       enemy._high_suspicion_hidden_timer = 3.0
       assert_true(enemy._should_trigger_suspicion_grenade())
   ```

3. **Visibility Blocks Trigger Test**
   ```gdscript
   func test_trigger_7_blocked_when_visible() -> void:
       enemy._memory.confidence = 1.0
       enemy._high_suspicion_hidden_timer = 10.0
       enemy._can_see_player = true  # Can see player
       assert_false(enemy._should_trigger_suspicion_grenade())
   ```

### Integration Tests

1. **Full Scenario Test**: Player enters enemy vision, hides behind cover
   - Verify grenade thrown after ~3 seconds
   - Verify grenade targets `suspected_position`
   - Verify cooldown applies

2. **Confidence Decay Test**: Player enters vision, hides for 10+ seconds
   - Confidence should decay below 0.8
   - Grenade should NOT be thrown

3. **Timer Reset Test**: Player hides, then briefly becomes visible
   - Timer should reset to 0
   - Must wait full 3 seconds again

---

## Risk Assessment

### Low Risk
- Self-contained addition (new trigger doesn't modify existing triggers)
- Uses existing memory system (no new dependencies)
- Clear fallback (if memory unavailable, trigger doesn't fire)

### Medium Risk
- Timer-based logic could have edge cases with frame timing
- Confidence decay interaction needs testing

### Mitigations
- Default to conservative behavior (not throwing) when uncertain
- Use existing grenade safety checks (distance, path clearance)
- Log trigger state changes for debugging

---

## Estimated Complexity

- **Lines of code**: ~50-80 new lines
- **Files modified**: 1 (scripts/objects/enemy.gd)
- **Test coverage**: 3-5 new unit tests

---

---

## Bug Fix: Low Activation Rate (2026-01-25)

### Problem Discovered

After initial implementation, user reported that Trigger 7 fires "very rarely". Analysis of game logs revealed a **mathematical impossibility** in the original design.

### Root Cause

The original implementation required:
- High confidence (≥ 0.8) to track the suspicion timer
- Timer to reach 3.0 seconds while confidence stays high

But confidence decays at 0.1/second:
```
Starting at 1.0 (visual contact):
- After 2 seconds: confidence = 0.8 (at threshold)
- After 3 seconds: confidence = 0.7 (BELOW threshold - timer resets!)
```

**Result**: Timer can NEVER reach 3 seconds while confidence stays ≥ 0.8

### Solution

Changed Trigger 7 to use **medium confidence (0.5+)** instead of high confidence (0.8+):

```gdscript
## Before (broken):
if _memory.is_high_confidence() and not _can_see_player:
    _high_suspicion_hidden_timer += delta

## After (fixed):
var has_suspicion := (_memory.is_medium_confidence() or _memory.is_high_confidence())
if has_suspicion and not _can_see_player:
    _high_suspicion_hidden_timer += delta
```

### Why Medium Confidence Works

| Confidence | Threshold | Time Available from 1.0 |
|------------|-----------|-------------------------|
| High       | ≥ 0.8     | ~2 seconds |
| Medium     | ≥ 0.5     | ~5 seconds |

Using medium confidence gives 5 seconds of tracking time, which is sufficient for the 3-second timer.

### Game Design Justification

- "Strong suspicion" semantically maps to medium confidence (50-80%)
- High confidence (80%+) implies near-certainty, triggering direct pursuit
- Grenade is meant for uncertain-but-suspicious situations
- 5 seconds allows more tactical gameplay opportunities

See [root-cause-analysis-2026-01-25.md](./root-cause-analysis-2026-01-25.md) for detailed analysis.

---

*Technical analysis completed: 2026-01-25*
*Bug fix documentation added: 2026-01-25*
