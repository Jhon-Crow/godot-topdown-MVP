# Case Study: Issue #390 - Enemies Should Not Turn Away From Attacker Direction

## Issue Summary

**Original Issue (Russian):** "враги не должны отворачиваться от направления, с которого в них стреляет игрок"

**Translation:** "Enemies should not turn away from the direction from which the player is shooting at them"

**Description:** During firefights, enemies turn away and lose sight of the player even while being shot at.

## Root Cause Analysis

### Problem Location

The issue is in `scripts/objects/enemy.gd` in the rotation priority system.

### Current Behavior

1. **When hit** (`on_hit_with_bullet_info()` at line 4086-4100):
   - Enemy turns toward attacker using `_force_model_to_face_direction(attacker_direction)`
   - This is a one-time immediate rotation

2. **Every frame** (`_update_enemy_model_rotation()` at line 933-972):
   - Rotation priority system overrides the hit reaction:
     1. Player visible → face player
     2. FLANKING state → face player
     3. Corner check timer → face corner angle
     4. **Velocity > 0 → face movement direction** ← THIS OVERRIDES HIT REACTION
     5. Idle scan → face scan direction

### The Bug

When an enemy is hit while moving (e.g., retreating to cover), the hit reaction turns them toward the attacker for ONE frame, but then `_update_enemy_model_rotation()` immediately turns them back to face their movement direction.

This creates the reported behavior: enemy gets shot, briefly faces attacker, then turns away to continue running to cover.

## Game Log Evidence

From `game_log_20260125_111842.txt`:

```
[11:18:46] [ENEMY] [Enemy3] State: COMBAT -> RETREATING
[11:18:47] [ENEMY] [Enemy1] State: COMBAT -> PURSUING
[11:18:47] [ENEMY] [Enemy2] State: COMBAT -> PURSUING
```

Enemies are transitioning to RETREATING and PURSUING states while being shot at. During these states, they have velocity > 0, so their facing direction is determined by movement, not by the threat direction.

## Industry Research

### Hit Reaction Systems

According to game AI best practices:
- Hit reaction systems should set up animations by resetting timers and apply an impulse at the start
- The reaction lasts for a set duration before being disabled
- Other systems like AI firing logic can check a "staggered" flag to determine behavior

### Threat Priority Systems

In tactical shooters like Killzone:
- Agents have goals like "PursueThreat" and "AttackThreat"
- After threats have been confirmed, the alert level rises when the agent is under attack or getting hit
- AI prioritizes environment-driven movement while maintaining tactical awareness

### Key Insight

**The missing element**: There is no "hit reaction timer" that maintains the facing-attacker behavior for a duration after being hit.

## Proposed Solutions

### Solution 1: Hit Reaction Timer (Recommended)

Add a timer-based hit reaction that takes priority in the rotation system:

```gdscript
## Duration to face attacker after being hit (gives player feedback that enemy is aware of threat)
const HIT_REACTION_DURATION: float = 0.8

var _hit_reaction_timer: float = 0.0
var _hit_reaction_direction: Vector2 = Vector2.ZERO
```

Modify `_update_enemy_model_rotation()` to check hit reaction first:
```gdscript
func _update_enemy_model_rotation() -> void:
    if not _enemy_model:
        return
    var target_angle: float
    var has_target := false

    # HIGHEST PRIORITY: Hit reaction - face attacker for a duration after being hit
    if _hit_reaction_timer > 0 and _hit_reaction_direction.length_squared() > 0.01:
        target_angle = _hit_reaction_direction.angle()
        has_target = true
    elif _player != null and _can_see_player:
        # ... existing code
```

Modify `on_hit_with_bullet_info()`:
```gdscript
var attacker_direction := -hit_direction.normalized()
if attacker_direction.length_squared() > 0.01:
    _hit_reaction_direction = attacker_direction
    _hit_reaction_timer = HIT_REACTION_DURATION
    _force_model_to_face_direction(attacker_direction)
```

Decrement timer in `_physics_process()`:
```gdscript
if _hit_reaction_timer > 0:
    _hit_reaction_timer -= delta
```

**Pros:**
- Clean, isolated change
- Follows industry best practices
- Gives clear visual feedback to player
- Configurable duration

**Cons:**
- Enemy might miss shots if facing wrong direction during retreat

### Solution 2: Under Fire Priority

When `_under_fire` is true, prioritize facing the threat source:

```gdscript
func _update_enemy_model_rotation() -> void:
    # ... existing code

    # HIGH PRIORITY: Under fire - face threat direction
    if _under_fire and _last_hit_direction.length_squared() > 0.01:
        target_angle = (-_last_hit_direction).angle()
        has_target = true
    elif _player != null and _can_see_player:
        # ... existing code
```

**Pros:**
- Simpler implementation
- Uses existing `_under_fire` state

**Cons:**
- `_last_hit_direction` only updates on actual hits, not near misses
- Might be too aggressive (enemy always faces threat even when should retreat)

### Solution 3: Stagger State

Add a "staggered" state that prevents normal rotation:

```gdscript
var _is_staggered: bool = false
var _stagger_timer: float = 0.0

func on_hit_with_bullet_info(...):
    # ... existing code
    _is_staggered = true
    _stagger_timer = 0.5  # Brief stagger
```

**Pros:**
- Can be used for other systems (prevent shooting while staggered)
- More realistic behavior

**Cons:**
- More complex, affects more systems
- May need animation support

## Recommendation

**Solution 1 (Hit Reaction Timer)** is recommended because:

1. It's the most focused fix with minimal side effects
2. It follows established game AI patterns
3. The duration is configurable per-enemy if needed
4. It provides clear player feedback

## Files to Modify

1. `scripts/objects/enemy.gd`:
   - Add `_hit_reaction_timer` and `_hit_reaction_direction` variables
   - Add `HIT_REACTION_DURATION` constant
   - Modify `_update_enemy_model_rotation()` to check hit reaction first
   - Modify `on_hit_with_bullet_info()` to set hit reaction state
   - Add timer decrement in `_physics_process()`

## Testing Plan

1. Shoot an enemy while they are retreating to cover
2. Verify enemy briefly faces attacker (0.8 seconds)
3. After timer expires, verify normal rotation resumes
4. Test multiple rapid hits to ensure timer resets properly
5. Verify enemy can still shoot during hit reaction period

## References

- [Shooter Tutorial – Base Enemy & Hit Reactions](https://kolosdev.com/shooter-tutorial-base-enemy-hit-reactions-behavior-tree/)
- [Game AI Pro 3 - Combat AI Accuracy](http://www.gameaipro.com/GameAIPro3/GameAIPro3_Chapter33_Using_Your_Combat_AI_Accuracy_to_Balance_Difficulty.pdf)
- [Killzone's AI - Tactical AI Systems](http://cse.unl.edu/~choueiry/Documents/straatman_remco_killzone_ai.pdf)
