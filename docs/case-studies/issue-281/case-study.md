# Case Study: Issue #281 - Grenade Throwing Timing Problem

## Issue Summary

**Problem**: When the player makes a short, quick mouse movement during grenade throwing, the grenade "loses its swing" and falls very close to the player instead of being thrown at the intended distance.

**Russian**: "у гранаты слишком жёсткий тайминг при коротком быстром движении мышью: граната успевает потерять замах и падает очень близко к игроку"

**Translation**: "The grenade has too strict timing for short fast mouse movement: the grenade has time to lose its swing and falls very close to the player"

## Timeline of Events

### Data Collection
Three log files were provided showing grenade throwing behavior:
- `game_log_20260124_000025.txt` - 18,733 lines
- `game_log_20260124_001256.txt` - 3,292 lines
- `game_log_20260124_001617.txt` - 20,316 lines

### Key Observations from Logs

#### Successful Throws (High Transfer Efficiency)
| Mouse Velocity | Swing Distance | Transfer | Final Speed | Result |
|---------------|----------------|----------|-------------|--------|
| 1927.0 px/s | 1327.0 px | 1.00 | 1015.6 | Good throw |
| 3336.2 px/s | 686.1 px | 1.00 | 1352.8 | Max distance |
| 2235.6 px/s | 336.1 px | 1.00 | 1178.3 | Good throw |
| 3146.8 px/s | 445.0 px | 1.00 | 1352.8 | Max distance |

#### Failed Throws (Low Transfer Efficiency)
| Mouse Velocity | Swing Distance | Transfer | Final Speed | Result |
|---------------|----------------|----------|-------------|--------|
| 48.6 px/s | 4.0 px | 0.02 | 0.6 | Drops at feet |
| 486.1 px/s | 41.4 px | 0.26 | 65.4 | Very short |
| 874.2 px/s | 83.7 px | 0.52 | 238.0 | Short |
| 473.8 px/s | 141.1 px | 0.87 | 217.5 | Short |
| 715.2 px/s | 77.7 px | 0.48 | 180.7 | Very short |

## Root Cause Analysis

### The Transfer Efficiency Algorithm

The issue lies in `scripts/projectiles/grenade_base.gd` lines 177-209:

```gdscript
func throw_grenade_velocity_based(mouse_velocity: Vector2, swing_distance: float) -> void:
    # Calculate mass-adjusted minimum swing distance
    var mass_ratio := grenade_mass / 0.4
    var required_swing := min_swing_distance * mass_ratio  # = 200.0 * 1.0 = 200.0

    # Calculate velocity transfer efficiency (0.0 to 1.0)
    var transfer_efficiency := clampf(swing_distance / required_swing, 0.0, 1.0)

    # Convert mouse velocity to throw velocity
    var base_throw_velocity := mouse_velocity * mouse_velocity_to_throw_multiplier * transfer_efficiency
```

### The Problem

1. **Minimum Swing Distance Requirement**: The system requires 200 pixels of mouse movement (`min_swing_distance = 200.0`) for full velocity transfer
2. **Linear Transfer Scaling**: Transfer efficiency scales linearly from 0.0 to 1.0 based on `swing_distance / 200.0`
3. **Quick Flicks Penalized**: A fast flick with high velocity but short distance (e.g., 800 px/s velocity, 80px distance) gets only 40% transfer

### Example Calculation

For a quick flick: Mouse velocity = 1000 px/s, Swing distance = 100px

```
transfer_efficiency = 100 / 200 = 0.5  (only 50% transfer!)
base_throw_velocity = 1000 * 0.5 * 0.5 = 250 px/s
```

The player expects a fast flick to throw far, but the system penalizes short movements regardless of velocity.

## Physics Analysis

### Real-World Physics

In real physics, throwing distance depends on:
1. **Release velocity** - How fast the object is moving when released
2. **Angle of release** - 45 degrees is optimal for distance

The physical "swing distance" (wind-up arc) contributes to building momentum, but the **velocity at release** is what actually determines throw distance.

### Current System Issues

1. **Over-weights swing distance**: Requires 200px minimum movement even for fast flicks
2. **Under-weights velocity**: A 3000 px/s flick over 50px gets very low transfer
3. **Unintuitive behavior**: Fast flicks should result in fast throws, but they don't

## Industry Best Practices

From game design research:

1. **Minimum Distance Threshold**: Use a small minimum distance (5-20px) to filter noise, not to determine power ([Source: Game Developer](https://www.gamedeveloper.com/design/the-5-golden-rules-of-input))

2. **Drag Threshold vs Power**: Drag threshold should distinguish click from drag, not scale throwing power ([Source: O'Reilly](https://www.oreilly.com/library/view/mastering-ui-development/9781787125520/f723d602-0985-4bc1-baba-d45e6931b090.xhtml))

3. **Velocity as Primary Factor**: Release velocity should be the primary determinant of throw distance ([Source: Unity Discussions](https://discussions.unity.com/t/2d-throwing-grenade-aiming-with-mouse-cursor/572348))

## Proposed Solutions

### Solution 1: Reduce Minimum Swing Distance (Simple Fix)
Reduce `min_swing_distance` from 200.0 to 50.0 pixels:
- Quick flicks get more transfer
- Still maintains some "wind-up" feel
- **Pros**: Minimal code change
- **Cons**: Still penalizes very short flicks

### Solution 2: Hybrid Formula (Recommended)
Use a formula that considers both velocity AND distance, but doesn't heavily penalize short distances:

```gdscript
# New transfer formula
var velocity_factor := clampf(velocity_magnitude / 1500.0, 0.0, 1.0)  # Velocity contribution
var swing_factor := clampf(swing_distance / 100.0, 0.2, 1.0)  # Distance contribution (minimum 20%)
var transfer_efficiency := minf(velocity_factor, 1.0) * swing_factor
```

- **Pros**: Respects both velocity and distance
- **Cons**: Requires testing to balance

### Solution 3: Minimum Throw Speed Guarantee
Ensure a minimum throw speed based on velocity alone:

```gdscript
# Guarantee minimum throw based on velocity
var min_velocity_throw := mouse_velocity.length() * 0.3  # 30% of velocity always transfers
var swing_based_throw := calculated_throw_speed
var final_speed := maxf(min_velocity_throw, swing_based_throw)
```

- **Pros**: Fast flicks always result in some throw distance
- **Cons**: May feel inconsistent

### Recommended Fix: Reduce Required Swing + Add Minimum

Combine reducing the required swing distance with a minimum transfer efficiency:

```gdscript
# Reduce required swing from 200 to 80 pixels
@export var min_swing_distance: float = 80.0

# In throw_grenade_velocity_based():
# Add minimum 30% transfer for any intentional throw
var base_transfer := 0.3
var swing_transfer := clampf(swing_distance / required_swing, 0.0, 0.7)
var transfer_efficiency := base_transfer + swing_transfer
```

This ensures:
1. Any intentional throw (swing > 10px) gets at least 30% velocity transfer
2. Full 200px swing still gets 100% transfer
3. Short quick flicks with high velocity will throw reasonably far

## Files to Modify

1. `scripts/projectiles/grenade_base.gd` - Line 47: `min_swing_distance` parameter
2. `scripts/projectiles/grenade_base.gd` - Lines 186-188: Transfer efficiency calculation

## Test Cases

After fix, verify:
1. Fast flick (1000+ px/s, 50px swing) throws at least 400 pixels
2. Full swing (200+ px swing) throws maximum distance
3. Stationary release (0 velocity) still drops at feet
4. Medium speed medium swing maintains expected behavior
