#!/usr/bin/env python3
"""
Find the correct formula to calculate initial speed from target distance
for the two-phase friction model used in grenade_base.gd.

The two-phase model:
- Above friction_ramp_velocity: friction = ground_friction * min_friction_multiplier
- Below friction_ramp_velocity: friction ramps from min to full using quadratic curve

We need to find v0 such that the grenade travels exactly distance d.
"""

import math

DELTA = 1.0 / 60.0

def simulate(initial_speed, ground_friction=300.0, min_mult=0.5, ramp_vel=200.0):
    """Simulate grenade physics exactly as grenade_base.gd does.

    In Godot 4, _physics_process modifies linear_velocity,
    and the engine uses the modified velocity for the next position update.

    The actual order in Godot:
    1. Engine integrates: position += velocity * dt (using velocity from end of last frame)
    2. _physics_process: velocity -= friction

    Since position uses velocity from previous _physics_process output,
    this is effectively: velocity updated, then position updated with new velocity.
    """
    velocity = initial_speed
    position = 0.0

    while velocity > 0.001:
        # Calculate friction (this runs in _physics_process)
        if velocity >= ramp_vel:
            friction_multiplier = min_mult
        else:
            t = velocity / ramp_vel
            friction_multiplier = min_mult + (1.0 - min_mult) * (1.0 - t * t)

        effective_friction = ground_friction * friction_multiplier
        friction_force = effective_friction * DELTA

        if friction_force > velocity:
            velocity = 0.0
        else:
            velocity -= friction_force

        # Position updated with new velocity (symplectic Euler)
        position += velocity * DELTA

    return position


def find_speed_for_distance(target_distance, ground_friction=300.0, min_mult=0.5, ramp_vel=200.0):
    """Binary search for the exact speed to reach target distance."""
    lo, hi = 1.0, 5000.0
    for _ in range(100):
        mid = (lo + hi) / 2.0
        dist = simulate(mid, ground_friction, min_mult, ramp_vel)
        if dist < target_distance:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2.0


# The two-phase model analytically:
# Phase 1 (v0 → ramp_vel): constant friction = ground_friction * min_mult
#   d1 = (v0^2 - ramp_vel^2) / (2 * ground_friction * min_mult)
# Phase 2 (ramp_vel → 0): variable friction
#   d2 is a fixed value that depends only on the parameters, not on v0
# Total: d = d1 + d2

def calculate_d2(ground_friction=300.0, min_mult=0.5, ramp_vel=200.0):
    """Calculate the distance traveled in Phase 2 (below ramp_vel)."""
    # Simulate just Phase 2
    return simulate(ramp_vel, ground_friction, min_mult, ramp_vel)


def analytical_speed(target_distance, ground_friction=300.0, min_mult=0.5, ramp_vel=200.0):
    """Calculate speed analytically using the two-phase model.

    d = d1 + d2
    d1 = (v0^2 - ramp_vel^2) / (2 * ground_friction * min_mult)
    d2 = fixed constant

    Solving for v0:
    v0 = sqrt(ramp_vel^2 + 2 * ground_friction * min_mult * (d - d2))

    If d <= d2, the grenade never needs to go above ramp_vel,
    so we need a different formula.
    """
    d2 = calculate_d2(ground_friction, min_mult, ramp_vel)

    if target_distance <= d2:
        # Short throw - stays in Phase 2 (variable friction zone)
        # Use binary search for accuracy
        return find_speed_for_distance(target_distance, ground_friction, min_mult, ramp_vel)

    # Long throw - uses both phases
    d1_needed = target_distance - d2
    effective_friction_phase1 = ground_friction * min_mult
    v0_squared = ramp_vel * ramp_vel + 2.0 * effective_friction_phase1 * d1_needed
    return math.sqrt(v0_squared)


print("=" * 80)
print("FINDING CORRECT FORMULA FOR TWO-PHASE FRICTION MODEL")
print("=" * 80)

# Calculate the Phase 2 distance (constant)
for gf, mm, rv in [(300.0, 0.5, 200.0), (280.0, 0.5, 200.0)]:
    d2 = calculate_d2(gf, mm, rv)
    print(f"\nPhase 2 distance (friction={gf}, mult={mm}, ramp={rv}): {d2:.1f} px")
    print(f"  This is the distance traveled from {rv} px/s to 0, with variable friction.")

print()
print("=" * 80)
print("VERIFICATION: Analytical vs Binary Search")
print("=" * 80)
print()

for friction in [300.0, 280.0]:
    print(f"\n--- Friction = {friction} ---")
    d2 = calculate_d2(friction)
    print(f"Phase 2 distance (d2) = {d2:.1f} px")
    print()
    print(f"{'Target':>10} {'Binary':>10} {'Analyt':>10} {'Match':>8} {'Sim Dist':>10}")
    print("-" * 55)

    for target in [50, 100, 150, 200, 300, 400, 500, 600, 800, 1000, 1200]:
        binary_speed = find_speed_for_distance(target, friction)
        analyt_speed = analytical_speed(target, friction)

        sim_dist = simulate(analyt_speed, friction)
        match = abs(binary_speed - analyt_speed) < 1.0

        print(f"{target:>10.0f} {binary_speed:>10.1f} {analyt_speed:>10.1f} {'✓' if match else '✗':>8} {sim_dist:>10.1f}")

print()
print("=" * 80)
print("FORMULA SUMMARY")
print("=" * 80)

d2_300 = calculate_d2(300.0)
d2_280 = calculate_d2(280.0)

print(f"""
For the two-phase friction model:
  ground_friction = F, min_friction_multiplier = M, friction_ramp_velocity = V

  Phase 2 distance: d2 (fixed constant, ~{d2_300:.0f}px for F=300, ~{d2_280:.0f}px for F=280)

  For target distance d:

  If d <= d2 (short throw):
    Use binary search or lookup table

  If d > d2 (normal/long throw):
    v0 = sqrt(V² + 2 * F * M * (d - d2))
    v0 = sqrt({200**2} + 2 * F * M * (d - d2))

  For F=300, M=0.5:
    v0 = sqrt(40000 + 300 * (d - {d2_300:.0f}))

  For F=280, M=0.5:
    v0 = sqrt(40000 + 280 * (d - {d2_280:.0f}))
""")

print("=" * 80)
print("COMPARISON: Current code vs Correct formula")
print("=" * 80)
print()

print(f"{'Target':>10} {'Current v':>12} {'Correct v':>12} {'Current d':>12} {'Error':>12}")
print("-" * 65)

for target in [100, 200, 300, 400, 500, 600, 800, 1000]:
    current_speed = min(math.sqrt(2 * 300 * target * 1.16), 1352.8)
    correct_speed = analytical_speed(target, 300.0)
    current_dist = simulate(current_speed, 300.0)

    error = ((current_dist - target) / target) * 100
    print(f"{target:>10.0f} {current_speed:>12.1f} {correct_speed:>12.1f} {current_dist:>12.1f} {error:>+12.1f}%")

print()
print("=" * 80)
print("C# IMPLEMENTATION")
print("=" * 80)
print("""
The correct C# implementation should be:

// Calculate the fixed Phase 2 distance (grenade decelerating from ramp velocity to stop)
// This is a constant that can be precomputed:
//   For friction=300, minMult=0.5, rampVel=200: d2 ≈ {d2_300:.1f} px
// But for accuracy, we compute it from the grenade's actual parameters.

float frictionRampVelocity = 200.0f;  // Default
float minFrictionMultiplier = 0.5f;   // Default

// Read actual values from grenade if available
if (_activeGrenade.Get("friction_ramp_velocity").VariantType != Variant.Type.Nil)
    frictionRampVelocity = (float)_activeGrenade.Get("friction_ramp_velocity");
if (_activeGrenade.Get("min_friction_multiplier").VariantType != Variant.Type.Nil)
    minFrictionMultiplier = (float)_activeGrenade.Get("min_friction_multiplier");

// Phase 2 distance: approximate the distance from rampVel to 0 with variable friction
// Since Phase 2 friction is complex (quadratic ramp), we use an approximation
// that accounts for the average friction in this zone.
// Average friction in Phase 2 ≈ ground_friction * (min_mult + 2*(1-min_mult)/3)
float avgPhase2Friction = groundFriction * (minFrictionMultiplier + 2.0f * (1.0f - minFrictionMultiplier) / 3.0f);
float phase2Distance = frictionRampVelocity * frictionRampVelocity / (2.0f * avgPhase2Friction);

float effectiveFriction = groundFriction * minFrictionMultiplier;  // Phase 1 friction

float requiredSpeed;
if (throwDistance <= phase2Distance)
{{
    // Short throw - use simple formula with average Phase 2 friction
    requiredSpeed = Mathf.Sqrt(2.0f * avgPhase2Friction * throwDistance);
}}
else
{{
    // Normal throw - two-phase calculation
    float phase1Distance = throwDistance - phase2Distance;
    requiredSpeed = Mathf.Sqrt(frictionRampVelocity * frictionRampVelocity
                               + 2.0f * effectiveFriction * phase1Distance);
}}
""".format(d2_300=d2_300))

# Now compute the average friction in Phase 2 analytically
# The friction multiplier is: m(v) = 0.5 + 0.5*(1 - (v/200)^2)
# Effective friction: f(v) = 300 * m(v) = 300*(0.5 + 0.5*(1-(v/200)^2)) = 300*(1 - 0.5*(v/200)^2)
# = 300 - 300*0.5*v^2/40000 = 300 - v^2/266.67
#
# Average friction over [0, 200]:
# integral of f(v) dv from 0 to 200, divided by 200
# = integral of (300 - v^2/266.67) dv from 0 to 200, / 200
# = (300*200 - (200^3)/(3*266.67)) / 200
# = (60000 - 8000000/800) / 200
# = (60000 - 10000) / 200
# = 50000 / 200
# = 250

# Wait, that's the velocity-weighted average for work, not path average.
# For distance, we need: d = integral of v dv / f(v) from V to 0
# = integral of v / (300 - v²/266.67) dv from 0 to V

# Let's use numerical integration
print("\n--- Phase 2 exact analysis ---")
print()
v_ramp = 200.0
gf = 300.0
mm = 0.5

# Exact phase 2 distance via numerical integration of v/f(v) dv
# d = integral_0^V v / f(v) dv where f(v) = gf * (mm + (1-mm)*(1-(v/V)^2))
n_steps = 10000
dv = v_ramp / n_steps
integral = 0.0
for i in range(n_steps):
    v = (i + 0.5) * dv
    t = v / v_ramp
    fmult = mm + (1.0 - mm) * (1.0 - t * t)
    fric = gf * fmult
    integral += v / fric * dv

print(f"Phase 2 distance (numerical integration): {integral:.1f} px")
print(f"Phase 2 distance (simulation): {d2_300:.1f} px")

# Calculate effective average friction for Phase 2
avg_fric = v_ramp**2 / (2 * integral)
print(f"Effective average friction in Phase 2: {avg_fric:.1f} px/s²")
print(f"  ground_friction * effective_multiplier = 300 * {avg_fric/300:.4f}")

# So for the short throw case, the effective friction is ~avg_fric
# And Phase 2 distance ≈ V²/(2*avg_fric)
print(f"  Phase 2 distance using avg: {v_ramp**2/(2*avg_fric):.1f} px")
