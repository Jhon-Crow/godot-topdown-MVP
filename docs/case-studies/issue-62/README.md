# Case Study: Issue #62 - Enemy AI Lead Prediction and Cover System

## Issue Summary

**Issue**: Enemies shoot with lead prediction (aiming where the player will be) before the player actually exits cover. This feels unfair to players because the AI appears to "know" where the player will emerge before seeing them.

**Original Issue Text (Russian)**:
> "враги не должны стрелять с упреждением до того как игрок выйдет из-за укрытия. сейчас они начинают стрелять туда, от куда появится игрок до того как его увидят (а должны начинать стрелять только после прямого контакта)."

**Translation**:
> "Enemies should not shoot with lead prediction before the player exits cover. Currently they start shooting where the player will appear before they see them (they should only start shooting after direct visual contact)."

## Problem Analysis

### Current Behavior

1. Player runs behind cover while being observed by enemy
2. Player's velocity is tracked even while partially visible
3. Enemy calculates predicted position based on player velocity
4. Enemy shoots at predicted position (outside cover) even though player is still behind cover
5. Bullets land where the player would emerge, before they actually do

### Root Cause

The enemy AI system has two separate checks:
1. **Visibility check** (`_can_see_player`): Uses raycast to check if player is visible
2. **Shot clearance check** (`_is_shot_clear_of_cover`): Checks if bullet path to TARGET is clear

The problem: When using lead prediction, the TARGET becomes the **predicted future position**, not the player's current position. The shot clearance check validates the path to where the player WILL BE, not where they ARE.

### Code Flow Analysis

```
_shoot() function:
1. target_position = _player.global_position (player's current position)
2. if enable_lead_prediction:
      target_position = _calculate_lead_prediction()  // Now target is PREDICTED position
3. _should_shoot_at_target(target_position)  // Checks path to PREDICTED position
4. Shoots bullet toward target_position
```

The `_calculate_lead_prediction()` function uses player velocity to calculate where they will be:
```gdscript
predicted_pos = player_pos + player_velocity * time_to_target
```

This means if player is running at 200 pixels/sec and bullet takes 0.2s to reach, the predicted position is 40 pixels ahead of current position - which might be outside cover.

### First Fix Attempt (Current PR)

Added `lead_prediction_delay` (0.3 seconds) that requires player to be continuously visible before lead prediction activates. However, this doesn't fully solve the issue because:

1. If player is visible at edge of cover, timer accumulates
2. After 0.3s, lead prediction activates
3. Enemy still aims at predicted position outside cover
4. Problem persists for players who are partially visible

## Industry Research

### "The Computer Is A Cheating Bastard" Phenomenon

From [TV Tropes](https://tvtropes.org/pmwiki/pmwiki.php/Main/TheComputerIsACheatingBastard):
> "The computer player is a cheating bastard whenever the 'rules' differ between you and Video Game A.I.-controlled opponents."

### Perfect Play AI Problem

From [TV Tropes - Perfect Play AI](https://tvtropes.org/pmwiki/pmwiki.php/Main/PerfectPlayAI):
> "Whereas a human opponent must visually deduce and predict what their opponent is about to do next, an AI can immediately and directly identify whatever action the player is currently performing"

### Industry Solutions

**Uncharted Series**:
> "Enemies have a 0% chance of hitting the player on first shot when they emerge from cover."

**F.E.A.R. and Halo**:
> "Give players the impression that opponents are capable of strategizing by making the opponents say the tactic they're going to execute out loud."

**Predictive Aiming Article** ([Game Developer](https://www.gamedeveloper.com/programming/predictive-aim-mathematics-for-ai-targeting)):
> "Maybe the game design will call for a pseudo-random perturbation of the aim vector or diceroll-based dramatic misses to give a sense of skilled vs. unskilled NPCs..."

## Data Collection

### Relevant Code Files

- `scripts/objects/enemy.gd` - Main enemy AI logic
  - Line 1151-1192: `_calculate_lead_prediction()` - Lead prediction calculation
  - Line 1016-1058: `_check_player_visibility()` - Visibility checking
  - Line 859-883: `_is_shot_clear_of_cover()` - Shot clearance validation
  - Line 1085-1135: `_shoot()` - Main shooting logic

### Key Variables

| Variable | Type | Purpose |
|----------|------|---------|
| `_can_see_player` | bool | Whether raycast from enemy hits player |
| `_continuous_visibility_timer` | float | How long player has been continuously visible |
| `lead_prediction_delay` | float | Required visibility time before prediction activates (0.3s) |
| `enable_lead_prediction` | bool | Whether lead prediction is enabled |
| `bullet_speed` | float | Used to calculate time-to-target for prediction |

### Scenarios Where Bug Occurs

1. **Edge of Cover Scenario**:
   - Player peeks out from cover edge
   - Enemy sees player (raycast hits)
   - Timer accumulates while player is at edge
   - After 0.3s, lead prediction calculates position further out
   - Enemy shoots at empty space outside cover

2. **Moving Behind Cover Scenario**:
   - Player runs perpendicular to enemy view behind cover
   - Player is briefly visible through gaps
   - Enemy calculates predicted position on other side of cover
   - Shoots at predicted exit point

3. **Partial Visibility Scenario**:
   - Player's collision shape extends slightly past cover
   - Raycast hits player despite being "behind cover"
   - Lead prediction aims at fully exposed position

## Proposed Solutions

### Solution 1: Validate Predicted Position Visibility (Recommended)

Add a check that the PREDICTED position itself must be visible from the enemy, not just have a clear shot path.

```gdscript
func _calculate_lead_prediction() -> Vector2:
    # ... existing prediction calculation ...

    # Validate that predicted position is visible from enemy
    if not _is_position_visible_to_enemy(predicted_pos):
        return player_pos  # Fall back to current position

    return predicted_pos
```

**Pros**:
- Ensures enemy only aims where they can actually see
- Most accurate fix for the root cause
- No arbitrary delays

**Cons**:
- Additional raycast per shot (minimal performance impact)

### Solution 2: Require Full Body Visibility

Only enable lead prediction when player's full body (center + corners) is visible, not just partially visible.

```gdscript
func _is_player_fully_visible() -> bool:
    # Check center and all 4 corners of player hitbox
    var check_points = _get_player_check_points(_player.global_position)
    for point in check_points:
        if not _is_point_visible_from_enemy(point):
            return false
    return true
```

**Pros**:
- Prevents edge-of-cover exploitation
- More realistic AI behavior

**Cons**:
- May be too restrictive in some scenarios

### Solution 3: Increase Visibility Timer Requirement

Increase `lead_prediction_delay` from 0.3s to 0.5-1.0s.

**Pros**:
- Simple implementation
- Easy to tune

**Cons**:
- Doesn't fix root cause
- May feel unnatural in open combat
- Players can still be hit if staying in sight too long

### Solution 4: Add Accuracy Penalty for New Targets (Industry Standard)

Like Uncharted, add a accuracy penalty when player first becomes visible.

```gdscript
var _first_shot_accuracy_penalty: float = 0.0

func _shoot():
    if _continuous_visibility_timer < first_shot_penalty_duration:
        # Add random deviation to shot direction
        var accuracy_modifier = 1.0 - (_continuous_visibility_timer / first_shot_penalty_duration)
        direction = direction.rotated(randf_range(-max_deviation, max_deviation) * accuracy_modifier)
```

**Pros**:
- Industry-proven approach
- Feels fair to players
- Gradual improvement makes AI feel more "human"

**Cons**:
- Doesn't prevent shooting at predicted position
- May require balance tuning

### Solution 5: Hybrid Approach (Best)

Combine Solutions 1 and 4:
1. Validate predicted position has line of sight
2. Add accuracy penalty for first shots after becoming visible
3. Lead prediction only activates after accuracy penalty period ends

## Recommended Implementation

**Primary Fix**: Solution 1 (Validate Predicted Position Visibility)
- Add check in `_calculate_lead_prediction()` to validate the predicted position
- If predicted position is not visible (blocked by cover), use current player position

**Secondary Enhancement**: Solution 4 (Accuracy Penalty)
- Add gradual accuracy improvement as player stays in sight
- Creates more natural-feeling AI behavior

## Testing Plan

1. **Test Case 1**: Player behind full cover
   - Expected: Enemy does not shoot
   - Verify: No bullets fired

2. **Test Case 2**: Player at edge of cover, not moving
   - Expected: Enemy shoots at current position only
   - Verify: Bullets go to player's actual position

3. **Test Case 3**: Player emerges from cover
   - Expected: First shots aim at current position, lead prediction after delay
   - Verify: No pre-firing at predicted exit point

4. **Test Case 4**: Player in open area (no cover)
   - Expected: Lead prediction works normally after delay
   - Verify: AI accuracy improves over time

5. **Test Case 5**: Player moves behind cover after being visible
   - Expected: Enemy stops shooting, timer resets
   - Verify: No continued firing at last known position

## Implementation Log

### Iteration 1: Predicted Position Visibility Check (Partial Success)

Added `_is_position_visible_to_enemy()` function to check if the predicted position is blocked by cover. This was implemented but didn't fully fix the issue because:

1. The visibility check only validated the **endpoint** (predicted position)
2. It didn't account for the player being at the **edge of cover** where their collision shape might be barely visible
3. Enemies could still "see" players at cover edges due to raycast hitting the player's collision shape extending past visual cover

### Iteration 2: Player Body Visibility Ratio (Current Fix)

The root cause was identified: when a player is at the edge of cover, the raycast check `_can_see_player` might return true because it hits the player's collision shape (radius 16 pixels) even if visually the player appears to be behind cover.

**Solution**: Added multi-point visibility checking for the player's body.

#### New Components

1. **New Export Variable**: `lead_prediction_visibility_threshold` (default: 0.6)
   - Minimum fraction of player body that must be visible before lead prediction activates
   - At 0.6, at least 3 out of 5 check points must be visible (60%)

2. **New State Variable**: `_player_visibility_ratio` (0.0 to 1.0)
   - Tracks what fraction of the player's body is currently visible
   - Updated each frame in `_check_player_visibility()`

3. **New Functions**:
   - `_get_player_check_points(center)` - Returns 5 points (center + 4 corners) on player's body
   - `_is_player_point_visible_to_enemy(point)` - Checks if a single point is visible (no obstacle blocking)
   - `_calculate_player_visibility_ratio()` - Counts visible points / total points
   - `get_player_visibility_ratio()` - Public getter for debugging

4. **Updated Functions**:
   - `_check_player_visibility()` - Now also calculates `_player_visibility_ratio`
   - `_calculate_lead_prediction()` - Now requires `_player_visibility_ratio >= lead_prediction_visibility_threshold`
   - `_reset()` - Resets `_player_visibility_ratio` to 0.0

#### How It Works

```
Player at edge of cover:
1. Raycast from enemy to player center → HIT (player is "visible")
2. Check 5 points on player body:
   - Center: blocked by cover → NOT visible
   - Top-left corner: blocked → NOT visible
   - Top-right corner: blocked → NOT visible
   - Bottom-left corner: visible → 1 point
   - Bottom-right corner: blocked → NOT visible
3. Visibility ratio = 1/5 = 0.2 (20%)
4. Lead prediction threshold = 0.6 (60%)
5. 0.2 < 0.6 → Lead prediction DISABLED
6. Enemy shoots at player's current position (not predicted)
```

This ensures that enemies only use lead prediction when the player is **significantly exposed** (at least 60% visible), not when they're barely peeking from cover.

#### Code Changes Summary

```gdscript
# New export variable (scripts/objects/enemy.gd line 138-142)
@export var lead_prediction_visibility_threshold: float = 0.6

# New state variable (line 263-266)
var _player_visibility_ratio: float = 0.0

# Multi-point visibility check functions (lines 868-933)
func _get_player_check_points(center: Vector2) -> Array[Vector2]
func _is_player_point_visible_to_enemy(point: Vector2) -> bool
func _calculate_player_visibility_ratio() -> float

# Updated _calculate_lead_prediction() (lines 1283-1289)
if _player_visibility_ratio < lead_prediction_visibility_threshold:
    _log_debug("Lead prediction disabled: visibility ratio %.2f < %.2f required (player at cover edge)" % [_player_visibility_ratio, lead_prediction_visibility_threshold])
    return player_pos
```

## References

- [TV Tropes: The Computer Is A Cheating Bastard](https://tvtropes.org/pmwiki/pmwiki.php/Main/TheComputerIsACheatingBastard)
- [TV Tropes: Perfect Play AI](https://tvtropes.org/pmwiki/pmwiki.php/Main/PerfectPlayAI)
- [Game Developer: Predictive Aim Mathematics for AI Targeting](https://www.gamedeveloper.com/programming/predictive-aim-mathematics-for-ai-targeting)
- [Godot Forum: Moving Target Prediction](https://forum.godotengine.org/t/need-help-with-moving-target-prediction-algorithm/128970)
- [yal.cc: Simplest Possible Predictive Aiming](https://yal.cc/simplest-possible-predictive-aiming/)
