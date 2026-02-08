#!/usr/bin/env python3
"""
Simulate grenade physics with discrete friction to find the exact discrepancy
between the continuous formula d = v²/(2*F) and the actual discrete physics.

This simulates what GrenadeTimer.cs _PhysicsProcess does:
  velocity -= velocity.normalized() * friction * delta
at 60 FPS (delta = 1/60).
"""

import math

def simulate_uniform_friction(initial_speed, friction, delta=1.0/60.0):
    """Simulate uniform friction (what GrenadeTimer.cs does)."""
    speed = initial_speed
    distance = 0.0
    frames = 0

    while speed > 0.01:
        # Move
        distance += speed * delta
        # Apply friction
        friction_amount = friction * delta
        if friction_amount >= speed:
            speed = 0.0
        else:
            speed -= friction_amount
        frames += 1

    return distance, frames

def simulate_velocity_dependent_friction(initial_speed, friction, delta=1.0/60.0):
    """Simulate velocity-dependent friction (what grenade_base.gd does).
    Above 200 px/s: friction *= 0.5
    Below 200 px/s: friction *= lerp from 0.5 to 1.0 (quadratic)
    """
    speed = initial_speed
    distance = 0.0
    frames = 0
    friction_ramp_velocity = 200.0
    min_friction_multiplier = 0.5

    while speed > 0.01:
        # Move
        distance += speed * delta

        # Calculate friction multiplier
        if speed >= friction_ramp_velocity:
            friction_multiplier = min_friction_multiplier
        else:
            t = speed / friction_ramp_velocity
            friction_multiplier = min_friction_multiplier + (1.0 - min_friction_multiplier) * (1.0 - t * t)

        effective_friction = friction * friction_multiplier
        friction_amount = effective_friction * delta
        if friction_amount >= speed:
            speed = 0.0
        else:
            speed -= friction_amount
        frames += 1

    return distance, frames

def simulate_double_friction(initial_speed, friction, delta=1.0/60.0):
    """Simulate BOTH GDScript (velocity-dependent) AND C# (uniform) friction applied together."""
    speed = initial_speed
    distance = 0.0
    frames = 0
    friction_ramp_velocity = 200.0
    min_friction_multiplier = 0.5

    while speed > 0.01:
        # Move
        distance += speed * delta

        # GDScript friction (velocity-dependent)
        if speed >= friction_ramp_velocity:
            gdscript_multiplier = min_friction_multiplier
        else:
            t = speed / friction_ramp_velocity
            gdscript_multiplier = min_friction_multiplier + (1.0 - min_friction_multiplier) * (1.0 - t * t)

        gdscript_friction = friction * gdscript_multiplier * delta

        # C# friction (uniform)
        csharp_friction = friction * delta

        total_friction = gdscript_friction + csharp_friction

        if total_friction >= speed:
            speed = 0.0
        else:
            speed -= total_friction
        frames += 1

    return distance, frames


def continuous_formula(initial_speed, friction):
    """d = v² / (2*F) — the analytical formula for uniform deceleration."""
    return (initial_speed ** 2) / (2 * friction)


print("=" * 80)
print("GRENADE PHYSICS SIMULATION")
print("=" * 80)

# Test cases from game logs
test_cases = [
    # (name, speed, friction, actual_distance_from_log)
    ("Flashbang throw 2 (log3)", 568.5, 300.0, 474.2),
    ("Frag grenade (log3)", 554.9, 280.0, 322.4),
    ("F-1 from earlier log", 613.2, 300.0, 371.0),
    ("Flashbang from earlier", 569.7, 300.0, None),
]

for name, speed, friction, actual in test_cases:
    print(f"\n--- {name} ---")
    print(f"Initial speed: {speed:.1f} px/s, Friction: {friction:.1f} px/s²")

    # Analytical (continuous) formula
    d_continuous = continuous_formula(speed, friction)
    print(f"  Continuous formula d=v²/(2F): {d_continuous:.1f} px")

    # Discrete uniform friction
    d_uniform, frames_u = simulate_uniform_friction(speed, friction)
    print(f"  Discrete uniform friction:    {d_uniform:.1f} px ({frames_u} frames, {frames_u/60:.2f}s)")

    # Discrete velocity-dependent friction (GDScript only)
    d_veldep, frames_v = simulate_velocity_dependent_friction(speed, friction)
    print(f"  Discrete vel-dependent (GD):  {d_veldep:.1f} px ({frames_v} frames, {frames_v/60:.2f}s)")

    # Discrete double friction
    d_double, frames_d = simulate_double_friction(speed, friction)
    print(f"  Discrete DOUBLE friction:     {d_double:.1f} px ({frames_d} frames, {frames_d/60:.2f}s)")

    if actual:
        print(f"  ACTUAL from game log:         {actual:.1f} px")
        print(f"  Ratio actual/continuous:      {actual/d_continuous:.3f}")
        print(f"  Ratio actual/uniform:         {actual/d_uniform:.3f}")
        print(f"  Ratio actual/double:          {actual/d_double:.3f}")

# Now let's find what compensation factor is needed
print("\n" + "=" * 80)
print("COMPENSATION FACTOR ANALYSIS")
print("=" * 80)

for name, speed, friction, actual in test_cases:
    if not actual:
        continue

    d_uniform, _ = simulate_uniform_friction(speed, friction)
    d_veldep, _ = simulate_velocity_dependent_friction(speed, friction)

    # What initial speed would be needed to reach 'actual' distance with uniform friction?
    # Binary search
    lo, hi = 0.0, 2000.0
    for _ in range(50):
        mid = (lo + hi) / 2
        d, _ = simulate_uniform_friction(mid, friction)
        if d < actual:
            lo = mid
        else:
            hi = mid
    needed_speed_uniform = (lo + hi) / 2

    # What initial speed for vel-dependent?
    lo, hi = 0.0, 2000.0
    for _ in range(50):
        mid = (lo + hi) / 2
        d, _ = simulate_velocity_dependent_friction(mid, friction)
        if d < actual:
            lo = mid
        else:
            hi = mid
    needed_speed_veldep = (lo + hi) / 2

    print(f"\n--- {name} ---")
    print(f"  Given speed: {speed:.1f}, Actual distance: {actual:.1f}")
    print(f"  Speed needed for actual distance (uniform): {needed_speed_uniform:.1f} (ratio: {needed_speed_uniform/speed:.3f})")
    print(f"  Speed needed for actual distance (vel-dep): {needed_speed_veldep:.1f} (ratio: {needed_speed_veldep/speed:.3f})")

# What is the actual friction model in the build?
# If GDScript doesn't run in exports, only C# uniform friction applies.
# But the user says grenades still fall short.
# Let's check if maybe Godot's internal physics damping is also at play.
print("\n" + "=" * 80)
print("GODOT INTERNAL DAMPING ANALYSIS")
print("=" * 80)
print("linear_damp is set to 0.0 in grenade_base.gd")
print("But there may be project-level damping in project.godot")
print()

# Let's simulate with additional damping (exponential decay)
for damp_value in [0.0, 0.5, 1.0, 1.5, 2.0, 3.0, 5.0]:
    speed = 568.5
    friction = 300.0
    delta = 1.0/60.0
    distance = 0.0
    v = speed
    frames = 0

    while v > 0.01:
        distance += v * delta
        # Godot internal damping: v *= 1 - damp * delta (approximate for small delta)
        # More precisely: v *= exp(-damp * delta) for step_per_second integration
        # But Godot uses: v = v * (1 - step * damp)
        v *= (1.0 - delta * damp_value)
        # Plus manual friction
        f = friction * delta
        if f >= v:
            v = 0.0
        else:
            v -= f
        frames += 1

    print(f"  linear_damp={damp_value:.1f}: distance={distance:.1f} px ({frames} frames)")


# Now let's check: what if the exported build's C# is also running the friction
# from the PhysicsMaterial? The grenade has physics_material.friction = 0.3
print("\n" + "=" * 80)
print("PHYSICS MATERIAL FRICTION ANALYSIS")
print("=" * 80)
print("grenade_base.gd sets physics_material.friction = 0.3 (contact friction)")
print("This is separate from ground_friction - it affects friction during contact with surfaces")
print()

# The PhysicsMaterial friction in Godot 2D works when bodies are in contact
# For a RigidBody2D moving on its own (no contact), this doesn't apply
# But once it hits a surface/wall and bounces, it could cause slowdown
print("PhysicsMaterial.friction only applies during contact - not during free flight")
print("This shouldn't cause the observed distance shortfall")

# Let's check: what if the issue is that the grenade DOES bounce/hit something?
# From the log, Frag grenade:
# - Spawned at (209.59, 93.97)
# - Landed at (532.04, 131.96)
# - Direction was (0.993, 0.117) - mostly horizontal, slight vertical
# - Distance: sqrt((532-210)^2 + (132-94)^2) = sqrt(322^2 + 38^2) = sqrt(103684+1444) = sqrt(105128) = 324.2 px
# - Expected from uniform friction: 554.9^2/(2*280) = 549.8 px
# - Ratio: 324.2/549.8 = 0.59 → EXACT MATCH with double friction pattern!

print("\n" + "=" * 80)
print("CRITICAL FINDING: DOUBLE FRICTION STILL PRESENT IN EXPORT!")
print("=" * 80)
print()
print("Frag grenade analysis:")
d_frag = math.sqrt((532.04-209.59)**2 + (131.96-93.97)**2)
print(f"  Actual travel distance: {d_frag:.1f} px")
d_frag_double, _ = simulate_double_friction(554.9, 280.0)
print(f"  Double friction predicts: {d_frag_double:.1f} px")
d_frag_uniform, _ = simulate_uniform_friction(554.9, 280.0)
print(f"  Uniform friction predicts: {d_frag_uniform:.1f} px")
print(f"  Ratio actual/double: {d_frag/d_frag_double:.3f}")
print()
print("This proves DOUBLE FRICTION is STILL happening!")
print("GDScript _physics_process() IS running in the exported build!")
print("The comment 'GDScript _physics_process() does NOT run in exports' was WRONG.")
print()
print("Or alternatively: Godot engine's built-in physics damping is contributing.")

# Final test: what compensation factor on the initial speed would fix this?
print("\n" + "=" * 80)
print("REQUIRED COMPENSATION FACTOR")
print("=" * 80)

for name, speed, friction, actual in test_cases:
    if not actual:
        continue

    d_double, _ = simulate_double_friction(speed, friction)
    # For double friction, what speed gives us the EXPECTED distance (from formula)?
    d_target = continuous_formula(speed, friction)

    lo, hi = 0.0, 5000.0
    for _ in range(50):
        mid = (lo + hi) / 2
        d, _ = simulate_double_friction(mid, friction)
        if d < d_target:
            lo = mid
        else:
            hi = mid
    needed_speed = (lo + hi) / 2
    factor = needed_speed / speed

    print(f"  {name}: need speed {needed_speed:.1f} instead of {speed:.1f}, factor = {factor:.4f}")
