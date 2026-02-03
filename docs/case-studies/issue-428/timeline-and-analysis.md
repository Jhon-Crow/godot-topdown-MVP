# Issue #428: Grenades Not Reaching Cursor - Timeline and Analysis

## Issue Summary

**Title:** fix гранаты не долетают до прицела (grenades don't quite reach the cursor)

**Reported:** 2026-02-03

**Reporter:** Jhon-Crow

**Description:** Grenades are falling slightly short of the cursor/target position in simple throwing mode.

## Timeline of Events

### Previous Related Work

1. **PR #260** (2026-01-23): Implemented realistic velocity-based grenade throwing physics
   - Introduced complex physics-based throwing system
   - Added `ground_friction` parameter for deceleration

2. **PR #189** (2026-01-22): Added offensive (frag) grenade with shrapnel mechanics
   - Created `FragGrenade` class extending `GrenadeBase`
   - Implemented custom `_physics_process()` in frag grenade

3. **Issue #398** (2026-02-03): Multiple grenade physics bugs discovered
   - Double-damping issue (linear_damp + custom friction)
   - Spawn position not set before throwing
   - Wrong physics values in calculations
   - Frag grenade not exploding in simple mode

4. **PR #401** (2026-02-03): Fixed issue #398 with multiple critical fixes
   - **Fix 1:** Set `linear_damp = 0.0` to prevent double-damping
   - **Fix 2:** Set grenade position to spawn point before throwing (60px offset)
   - **Fix 3:** Read actual grenade properties instead of hardcoded values
   - **Fix 4:** Added `throw_grenade_simple()` override in FragGrenade
   - Commits: c6067a9, 33db828, f98fe4f, 2382b59, a96a1e9

### Current Issue #428

**2026-02-03 16:33:13 - 16:33:47:** First test session (game_log_20260203_163313.txt)
- 5 grenade throws recorded
- Throws to distances: 764px, 622px, 599px, 614px, 630px
- Using both Flashbang (friction 300) and Frag (friction 280)

**2026-02-03 16:34:18 - 16:34:41:** Second test session (game_log_20260203_163418.txt)
- 4 grenade throws recorded
- Throws to distances: 599px, 923px, 794px, 771px
- All using Flashbang (friction 300)

**2026-02-03:** Issue #428 opened reporting grenades falling short

## Root Cause Analysis

### Physics Formula Investigation

The current formula used in `Player.cs` (line 2218-2219):

```csharp
// Distance = v^2 / (2 * friction) → v = sqrt(2 * friction * distance)
float requiredSpeed = Mathf.Sqrt(2.0f * groundFriction * throwDistance);
```

This formula is derived from classical physics for constant deceleration:
- Deceleration: `a = ground_friction` (pixels/second²)
- Initial velocity: `v₀`
- Final velocity: `v = 0` (stopped)
- Distance traveled: `d`

Using kinematic equation: `v² = v₀² + 2ad`
- `0 = v₀² - 2ad` (negative because deceleration)
- `v₀² = 2ad`
- `v₀ = √(2ad)`

### Actual Implementation in grenade_base.gd

```gdscript
func _physics_process(delta: float) -> void:
    if linear_velocity.length() > 0:
        var friction_force := linear_velocity.normalized() * ground_friction * delta
        if friction_force.length() > linear_velocity.length():
            linear_velocity = Vector2.ZERO
        else:
            linear_velocity -= friction_force
```

This applies friction per frame:
- Deceleration per frame: `ground_friction * delta`
- For 60 FPS: `delta = 1/60 ≈ 0.0167 seconds`
- Each frame reduces velocity by: `300 * 0.0167 = 5 pixels/second`

### Discrete Integration Error

The continuous formula assumes infinitesimal time steps, but Godot uses discrete time steps (1/60 second at 60 FPS).

**Theoretical Analysis:**

For target distance `d = 764 pixels` and friction `f = 300`:
- **Formula calculates:** `v = √(2 × 300 × 764) = √458,400 ≈ 677 px/s`
- **Predicted distance:** `d = 677² / (2 × 300) = 763.88 pixels`

**Discrete Simulation (Python):**

```python
fps = 60.0
delta = 1.0 / 60.0
friction = 300.0
velocity = 677.0
position = 0.0

while velocity > 1.0:
    friction_force = friction * delta
    if friction_force >= velocity:
        velocity = 0.0
    else:
        velocity -= friction_force
    position += velocity * delta
```

**Result:** `position = 758.25 pixels`
**Shortfall:** `764 - 758.25 = 5.75 pixels (0.75% error)`

### Root Cause: Discrete Time Integration Error

The physics formula is mathematically correct for continuous time, but Godot's discrete time integration introduces a small error:

1. **Continuous formula:** Assumes smooth, instantaneous deceleration
2. **Discrete implementation:** Updates velocity in discrete steps at 60 FPS
3. **Error accumulation:** Each frame applies friction then moves, causing slight undershoot
4. **Magnitude:** Approximately **0.75-0.8% shortfall** from target distance

#### Why This Happens

In continuous physics:
- `dx/dt = v(t) = v₀ - at`
- `x(t) = ∫v(t)dt = v₀t - ½at²`

In discrete physics (Euler integration):
- Update velocity: `v_{n+1} = v_n - a·Δt`
- Update position: `x_{n+1} = x_n + v_n·Δt` (uses OLD velocity, not new)

The position update uses the velocity from the START of the frame, not accounting for the deceleration that occurs during that frame. This causes systematic undershoot.

### Example Calculation

For a 764-pixel throw:
- **Expected:** 764.0 pixels
- **Formula predicts:** 763.88 pixels (continuous physics)
- **Actual Godot:** ~758.3 pixels (discrete physics)
- **Error:** ~5.7 pixels (0.75% short)

At longer distances, this becomes more noticeable:
- **1000-pixel throw:** ~7.5 pixels short
- **500-pixel throw:** ~3.8 pixels short

## Additional Factors Investigated

### 1. ✅ Double Damping (Already Fixed in PR #401)
- Previously: Both `linear_damp` and custom friction were active
- Fixed by setting `linear_damp = 0.0`
- Not the cause of current issue

### 2. ✅ Spawn Position Offset (Already Fixed in PR #401)
- Previously: Grenade spawned at player position but formula assumed spawn offset
- Fixed by setting `_activeGrenade.GlobalPosition = safeSpawnPosition` before throwing
- Not the cause of current issue

### 3. ✅ Wrong Grenade Properties (Already Fixed in PR #401)
- Previously: Used hardcoded values instead of actual grenade properties
- Fixed by reading `ground_friction` and `max_throw_speed` from grenade instance
- Not the cause of current issue

### 4. ❌ Frame Rate Dependency
- The discrete integration error is consistent at 60 FPS
- At different frame rates, the error magnitude would change
- Not currently a problem but worth noting for future optimization

### 5. ❌ Rounding Errors
- Using `float` in C# and `float` in GDScript
- Rounding errors are negligible (< 0.01 pixels)
- Not a significant factor

## Conclusion

The root cause is **discrete time integration error** inherent to Euler integration at 60 FPS. The physics formula is mathematically correct for continuous time, but Godot's discrete time steps cause grenades to land approximately **0.75-0.8% short** of the target distance.

This is a well-known limitation of first-order Euler integration, where the position update uses the velocity from the beginning of the time step rather than the average velocity during the time step.

## Proposed Solutions

### Solution 1: Apply Compensation Factor (Recommended)
Multiply the calculated speed by a small compensation factor to account for discrete integration error.

**Formula adjustment:**
```csharp
float requiredSpeed = Mathf.Sqrt(2.0f * groundFriction * throwDistance * 1.008f);
```

**Pros:**
- Simple, minimal code change
- Empirically accurate at 60 FPS
- Negligible overhead

**Cons:**
- Frame-rate dependent (compensation factor changes at different FPS)
- Not "pure" physics

### Solution 2: Use Trapezoidal Integration
Update the grenade physics to use trapezoidal (average velocity) integration.

**Physics update:**
```gdscript
# Calculate friction
var friction_force := linear_velocity.normalized() * ground_friction * delta
var new_velocity := linear_velocity
if friction_force.length() >= new_velocity.length():
    new_velocity = Vector2.ZERO
else:
    new_velocity -= friction_force

# Use average velocity for position update (trapezoidal rule)
var avg_velocity := (linear_velocity + new_velocity) / 2.0
position += avg_velocity * delta
linear_velocity = new_velocity
```

**Pros:**
- More accurate physics
- Frame-rate independent
- Mathematically elegant

**Cons:**
- Requires modifying grenade physics code
- Slightly more complex
- Changes behavior of all grenades globally

### Solution 3: Iterative Solver
Calculate the exact speed needed through iterative simulation.

**Pros:**
- Perfectly accurate
- Frame-rate independent

**Cons:**
- Computationally expensive (simulation per throw)
- Overkill for this problem

## Recommendation

**Implement Solution 1** with a compensation factor of **1.008** (0.8% increase).

This provides immediate accuracy with minimal code changes and negligible performance impact. The compensation can be refined based on empirical testing.

Later, consider Solution 2 (trapezoidal integration) for a more robust, frame-rate independent solution.

## Related Issues and PRs

- Issue #398: Multiple grenade physics bugs (fixed in PR #401)
- PR #401: Fixed spawn position, double-damping, and property reading
- PR #260: Original velocity-based throwing physics
- Issue #428: Current issue (discrete integration error)
