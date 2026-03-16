#!/usr/bin/env python3
"""
Precise simulation of grenade physics to find root cause of issue #615.
Tests multiple hypotheses about the physics behavior.
"""

import math

# Physics parameters from grenade_base.gd
GROUND_FRICTION = 300.0
MIN_FRICTION_MULTIPLIER = 0.5
FRICTION_RAMP_VELOCITY = 200.0
MAX_THROW_SPEED = 850.0
COMPENSATION = 1.16
DELTA = 1.0 / 60.0

def calc_friction_multiplier(speed, ramp_vel=FRICTION_RAMP_VELOCITY, min_mult=MIN_FRICTION_MULTIPLIER):
    """Calculate friction multiplier exactly as in grenade_base.gd."""
    if speed >= ramp_vel:
        return min_mult
    else:
        t = speed / ramp_vel
        return min_mult + (1.0 - min_mult) * (1.0 - t * t)


def simulate_godot_rigidbody(initial_speed, friction=GROUND_FRICTION):
    """
    Simulate Godot 4 RigidBody2D behavior.

    In Godot 4, the order for RigidBody2D is:
    1. Physics engine integrates: position += velocity * dt
    2. _physics_process runs: velocity -= friction * dt

    Source: Godot docs say _physics_process is called at the same time as
    the physics step, but for RigidBody2D the integration happens within
    the physics engine. When you modify linear_velocity in _physics_process,
    it applies to the NEXT step.

    This is FORWARD EULER (position uses old velocity).
    """
    velocity = initial_speed
    position = 0.0

    while velocity > 0.001:
        # Step 1: Position update with CURRENT velocity (physics engine moves body)
        position += velocity * DELTA

        # Step 2: Friction applied in _physics_process (modifies velocity for next tick)
        mult = calc_friction_multiplier(velocity)
        eff_friction = friction * mult
        friction_force = eff_friction * DELTA

        if friction_force > velocity:
            velocity = 0.0
        else:
            velocity -= friction_force

    return position


def simulate_symplectic(initial_speed, friction=GROUND_FRICTION):
    """
    Simulate symplectic Euler (velocity updated first, then position).

    This is what happens if _physics_process modifies velocity BEFORE
    the physics engine updates position.
    """
    velocity = initial_speed
    position = 0.0

    while velocity > 0.001:
        # Step 1: Friction applied first
        mult = calc_friction_multiplier(velocity)
        eff_friction = friction * mult
        friction_force = eff_friction * DELTA

        if friction_force > velocity:
            velocity = 0.0
        else:
            velocity -= friction_force

        # Step 2: Position updated with NEW velocity
        position += velocity * DELTA

    return position


def simulate_constant_friction(initial_speed, friction=GROUND_FRICTION):
    """Simulate with CONSTANT friction (what the formula assumes)."""
    velocity = initial_speed
    position = 0.0

    while velocity > 0.001:
        position += velocity * DELTA
        friction_force = friction * DELTA
        if friction_force > velocity:
            velocity = 0.0
        else:
            velocity -= friction_force

    return position


def player_cs_speed(target_distance, compensation=COMPENSATION):
    """Calculate speed as Player.cs ThrowSimpleGrenade does."""
    return math.sqrt(2.0 * GROUND_FRICTION * target_distance * compensation)


def find_correct_speed(target_distance, sim_func):
    """Binary search for the correct initial speed to reach target distance."""
    lo, hi = 1.0, 3000.0
    for _ in range(100):
        mid = (lo + hi) / 2.0
        dist = sim_func(mid)
        if dist < target_distance:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2.0


print("=" * 90)
print("GRENADE PHYSICS SIMULATION v2")
print("=" * 90)

print()
print("Test: What speed does Player.cs calculate for various target distances?")
print("And how far does the grenade ACTUALLY travel with that speed?")
print()
print(f"{'Target':>10} {'CS Speed':>10} {'FwdEuler':>12} {'Symplect':>12} {'ConstFric':>12} {'FE Error':>10} {'SE Error':>10}")
print("-" * 80)

for target in [100, 200, 300, 400, 500, 600, 700, 800, 1000, 1200]:
    cs_speed = player_cs_speed(target)
    cs_speed_clamped = min(cs_speed, MAX_THROW_SPEED)

    fe_dist = simulate_godot_rigidbody(cs_speed_clamped)
    se_dist = simulate_symplectic(cs_speed_clamped)
    cf_dist = simulate_constant_friction(cs_speed_clamped)

    fe_err = ((fe_dist - target) / target) * 100
    se_err = ((se_dist - target) / target) * 100

    print(f"{target:>10.0f} {cs_speed_clamped:>10.1f} {fe_dist:>12.1f} {se_dist:>12.1f} {cf_dist:>12.1f} {fe_err:>+10.1f}% {se_err:>+10.1f}%")

print()
print("=" * 90)
print("KEY QUESTION: With the variable friction model, do grenades OVERSHOOT or UNDERSHOOT?")
print("=" * 90)

print()
print("Answer: With current compensation factor of 1.16:")
print()
for target in [300, 500, 700, 1000]:
    cs_speed = min(player_cs_speed(target), MAX_THROW_SPEED)
    fe_dist = simulate_godot_rigidbody(cs_speed)
    se_dist = simulate_symplectic(cs_speed)
    print(f"  Target {target}px → CS speed={cs_speed:.0f}, FwdEuler lands at {fe_dist:.0f}px, Symplectic lands at {se_dist:.0f}px")

print()
print("=" * 90)
print("HYPOTHESIS: The compensation factor was correct with CONSTANT friction.")
print("Let's verify: what compensation would be needed for constant friction to match?")
print("=" * 90)

print()
print("With CONSTANT friction and forward Euler:")
for comp in [1.0, 1.008, 1.16, 1.5, 2.0]:
    speed = math.sqrt(2.0 * GROUND_FRICTION * 500.0 * comp)
    speed_clamped = min(speed, MAX_THROW_SPEED)
    dist = simulate_constant_friction(speed_clamped)
    err = ((dist - 500) / 500) * 100
    print(f"  Compensation={comp:.3f}, Speed={speed_clamped:.1f}, Distance={dist:.1f}, Error={err:+.1f}%")

print()
print("=" * 90)
print("CORRECT SPEEDS for variable friction model:")
print("=" * 90)
print()
print(f"{'Target':>10} {'CS Speed':>10} {'Correct FE':>12} {'Correct SE':>12} {'CS/FE':>8} {'CS/SE':>8}")
print("-" * 60)

for target in [100, 200, 300, 400, 500, 600, 700, 800, 1000, 1200]:
    cs_speed = min(player_cs_speed(target), MAX_THROW_SPEED)
    correct_fe = find_correct_speed(target, simulate_godot_rigidbody)
    correct_se = find_correct_speed(target, simulate_symplectic)

    ratio_fe = cs_speed / correct_fe if correct_fe > 0 else 0
    ratio_se = cs_speed / correct_se if correct_se > 0 else 0

    print(f"{target:>10.0f} {cs_speed:>10.1f} {correct_fe:>12.1f} {correct_se:>12.1f} {ratio_fe:>8.3f} {ratio_se:>8.3f}")

print()
print("=" * 90)
print("TRAJECTORY VISUALIZATION vs ACTUAL THROW MISMATCH:")
print("The _Draw() method does NOT include the compensation factor!")
print("=" * 90)
print()
print("_Draw() calculates landing position using: v² / (2 * friction)")
print("ThrowSimpleGrenade() uses: sqrt(2 * friction * distance * 1.16)")
print()
print("The landing indicator shows where the grenade SHOULD land per uncompensated formula.")
print("The actual throw uses compensated speed, so grenade goes FURTHER.")
print()

for target in [200, 400, 600, 800]:
    # What the visualization shows
    vis_speed = math.sqrt(2.0 * GROUND_FRICTION * target)  # NO compensation
    vis_speed_clamped = min(vis_speed, MAX_THROW_SPEED)
    vis_landing = (vis_speed_clamped ** 2) / (2.0 * GROUND_FRICTION)

    # What the throw actually does
    throw_speed = min(player_cs_speed(target), MAX_THROW_SPEED)
    throw_landing_fe = simulate_godot_rigidbody(throw_speed)
    throw_landing_se = simulate_symplectic(throw_speed)

    print(f"Target={target}px:")
    print(f"  Visual indicator: speed={vis_speed_clamped:.0f}, shows landing at {vis_landing:.0f}px")
    print(f"  Actual throw:     speed={throw_speed:.0f}, lands at FE={throw_landing_fe:.0f}px, SE={throw_landing_se:.0f}px")
    print()

print("=" * 90)
print("WHAT IF the issue is about the TRAJECTORY PREVIEW being wrong?")
print("The user sees the landing indicator at the cursor.")
print("The grenade ACTUALLY overshoots because of higher speed + lower friction.")
print("But wait - the issue says grenades DON'T REACH the cursor...")
print()
print("Unless there is additional damping from Godot that we're not modeling.")
print("The issue #428 case study found ~14% additional damping that was empirical.")
print("=" * 90)

print()
print("=" * 90)
print("HYPOTHESIS: RigidBody2D has hidden internal damping")
print("Let's model it as linear_damp effect even though code sets linear_damp=0")
print("Godot may still apply some minimal internal damping per physics step")
print("=" * 90)

def simulate_with_hidden_damp(initial_speed, friction=GROUND_FRICTION, damp_factor=0.998):
    """Simulate with hidden per-frame velocity damping from Godot engine."""
    velocity = initial_speed
    position = 0.0

    while velocity > 0.001:
        # Hidden engine damping per frame
        velocity *= damp_factor

        # Position update
        position += velocity * DELTA

        # Custom friction
        mult = calc_friction_multiplier(velocity)
        eff_friction = friction * mult
        friction_force = eff_friction * DELTA

        if friction_force > velocity:
            velocity = 0.0
        else:
            velocity -= friction_force

    return position

print()
print("Testing various hidden damping factors:")
print(f"{'Damp/frame':>12} {'Dist(500sp)':>14} {'Dist(850sp)':>14}")
print("-" * 45)
for damp in [1.0, 0.999, 0.998, 0.997, 0.996, 0.995, 0.99, 0.98]:
    d500 = simulate_with_hidden_damp(500.0, damp_factor=damp)
    d850 = simulate_with_hidden_damp(850.0, damp_factor=damp)
    print(f"{damp:>12.4f} {d500:>14.1f} {d850:>14.1f}")

print()
print("Without damping, 500 px/s → ", simulate_godot_rigidbody(500.0))
print("Without damping, 850 px/s → ", simulate_godot_rigidbody(850.0))

print()
print("=" * 90)
print("FINAL ANALYSIS: What compensation factor correctly compensates the variable friction?")
print("This tells us what the compensation SHOULD be.")
print("=" * 90)
print()

for target in [200, 300, 400, 500, 600, 700, 800]:
    correct_speed_fe = find_correct_speed(target, simulate_godot_rigidbody)
    # What compensation factor would give this speed?
    # speed = sqrt(2 * F * d * k) → k = speed² / (2 * F * d)
    k_needed = (correct_speed_fe ** 2) / (2.0 * GROUND_FRICTION * target)
    print(f"  Target {target}px: Correct speed={correct_speed_fe:.1f}, Compensation k={k_needed:.4f}")

print()
print("The current compensation is 1.16. These values show what it SHOULD be.")
print("If k < 1.0, the correct speed is LOWER than even the uncompensated formula,")
print("meaning the formula overestimates speed needed (grenade goes too far).")
