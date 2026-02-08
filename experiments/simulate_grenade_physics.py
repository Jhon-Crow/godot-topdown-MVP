#!/usr/bin/env python3
"""
Simulate the exact grenade physics from grenade_base.gd to verify
distance calculations and identify the root cause of issue #615.

This simulation replicates the _physics_process() method's friction model.
"""

import math

# Physics parameters from grenade_base.gd
GROUND_FRICTION = 300.0
MIN_FRICTION_MULTIPLIER = 0.5
FRICTION_RAMP_VELOCITY = 200.0
MAX_THROW_SPEED = 850.0

# Godot physics runs at 60 FPS
DELTA = 1.0 / 60.0

def simulate_grenade_distance(initial_speed, friction=GROUND_FRICTION,
                                min_mult=MIN_FRICTION_MULTIPLIER,
                                ramp_vel=FRICTION_RAMP_VELOCITY):
    """Simulate grenade physics exactly as grenade_base.gd does it."""
    velocity = initial_speed
    position = 0.0
    frame = 0

    while velocity > 0.001:
        current_speed = velocity

        # Calculate friction multiplier exactly as in grenade_base.gd lines 192-201
        if current_speed >= ramp_vel:
            friction_multiplier = min_mult
        else:
            t = current_speed / ramp_vel
            friction_multiplier = min_mult + (1.0 - min_mult) * (1.0 - t * t)

        effective_friction = friction * friction_multiplier
        friction_force = effective_friction * DELTA

        if friction_force > velocity:
            velocity = 0.0
        else:
            velocity -= friction_force

        position += velocity * DELTA  # Note: position update uses NEW velocity (after friction)
        frame += 1

    return position, frame

def simulate_grenade_distance_old_vel(initial_speed, friction=GROUND_FRICTION,
                                       min_mult=MIN_FRICTION_MULTIPLIER,
                                       ramp_vel=FRICTION_RAMP_VELOCITY):
    """Simulate using OLD velocity for position update (Euler forward)."""
    velocity = initial_speed
    position = 0.0
    frame = 0

    while velocity > 0.001:
        current_speed = velocity

        if current_speed >= ramp_vel:
            friction_multiplier = min_mult
        else:
            t = current_speed / ramp_vel
            friction_multiplier = min_mult + (1.0 - min_mult) * (1.0 - t * t)

        effective_friction = friction * friction_multiplier
        friction_force = effective_friction * DELTA

        # Position update uses OLD velocity (before friction)
        position += velocity * DELTA

        if friction_force > velocity:
            velocity = 0.0
        else:
            velocity -= friction_force

        frame += 1

    return position, frame


def player_cs_calculated_speed(target_distance, compensation=1.16):
    """Speed calculated by Player.cs ThrowSimpleGrenade()."""
    return math.sqrt(2.0 * GROUND_FRICTION * target_distance * compensation)


def simple_model_distance(speed, friction=GROUND_FRICTION):
    """Distance predicted by simple constant-friction model."""
    return speed * speed / (2.0 * friction)


print("=" * 80)
print("GRENADE PHYSICS SIMULATION")
print("Replicating grenade_base.gd _physics_process() exactly")
print("=" * 80)

# First, let's understand the order of operations in _physics_process
# In grenade_base.gd:
#   1. Calculate friction_force
#   2. linear_velocity -= friction_force  (update velocity FIRST)
#   3. Position is updated by Godot's physics engine using linear_velocity
#
# IMPORTANT: In Godot's RigidBody2D _physics_process, when you modify
# linear_velocity, the position is updated by the physics engine AFTER
# _physics_process returns, using the MODIFIED velocity.
# This means position += new_velocity * delta (NOT old velocity)

print("\n--- Simulation with velocity-dependent friction ---")
print("(Position updated using NEW velocity, as Godot does for RigidBody2D)")
print()

print(f"{'Target(px)':>12} {'CS Speed':>10} {'Simulated':>12} {'Simple':>12} {'Error(%)':>10} {'Frames':>8}")
print("-" * 70)

for target_dist in [200, 300, 400, 500, 600, 700, 800, 1000, 1200]:
    cs_speed = player_cs_calculated_speed(target_dist)
    cs_speed_clamped = min(cs_speed, MAX_THROW_SPEED)

    actual_dist, frames = simulate_grenade_distance(cs_speed_clamped)
    simple_dist = simple_model_distance(cs_speed_clamped)

    error = ((actual_dist - target_dist) / target_dist) * 100
    print(f"{target_dist:>12.1f} {cs_speed_clamped:>10.1f} {actual_dist:>12.1f} {simple_dist:>12.1f} {error:>+10.1f}% {frames:>8}")

print()
print("--- Checking actual code order: is position updated BEFORE or AFTER friction? ---")
print()
# Let's check: in grenade_base.gd, the code:
#   linear_velocity -= friction_force
# This modifies the RigidBody2D's linear_velocity.
# Godot's physics engine then uses this modified velocity to update position.
#
# So the order is:
#   1. _physics_process: velocity -= friction
#   2. Godot engine: position += velocity * dt  (using modified velocity)
#
# This is equivalent to "symplectic Euler" or "semi-implicit Euler"
# where velocity is updated first, then position uses new velocity.

print(f"{'Speed':>10} {'NewVel Dist':>14} {'OldVel Dist':>14} {'Simple Model':>14}")
print("-" * 55)
for speed in [200, 400, 600, 850]:
    new_vel_dist, _ = simulate_grenade_distance(speed)
    old_vel_dist, _ = simulate_grenade_distance_old_vel(speed)
    simple = simple_model_distance(speed)
    print(f"{speed:>10.0f} {new_vel_dist:>14.1f} {old_vel_dist:>14.1f} {simple:>14.1f}")

print()
print("=" * 80)
print("KEY INSIGHT: The friction model is velocity-dependent!")
print("At high speeds: friction = 300 * 0.5 = 150 px/s²")
print("At low speeds:  friction ramps from 150 to 300 px/s²")
print()
print("The Player.cs formula assumes CONSTANT friction of 300 px/s²")
print("But actual friction is 150 px/s² for most of the flight!")
print("=" * 80)

# Now let's find what speed is actually needed for each target distance
print()
print("--- Finding CORRECT speed for each target distance ---")
print()
print(f"{'Target(px)':>12} {'CS Speed':>10} {'Correct v':>10} {'Ratio':>8} {'CS/Correct':>12}")
print("-" * 55)

for target_dist in [200, 300, 400, 500, 600, 700, 800, 1000, 1200]:
    cs_speed = player_cs_calculated_speed(target_dist)
    cs_speed_clamped = min(cs_speed, MAX_THROW_SPEED)

    # Binary search for correct speed
    lo, hi = 10.0, 2000.0
    for _ in range(100):
        mid = (lo + hi) / 2.0
        dist, _ = simulate_grenade_distance(mid)
        if dist < target_dist:
            lo = mid
        else:
            hi = mid
    correct_speed = (lo + hi) / 2.0

    ratio = cs_speed_clamped / correct_speed if correct_speed > 0 else 0
    print(f"{target_dist:>12.1f} {cs_speed_clamped:>10.1f} {correct_speed:>10.1f} {ratio:>8.3f} {'OVERSHOOT' if ratio > 1.05 else 'UNDERSHOOT' if ratio < 0.95 else 'OK'}")

# Check: with Godot's actual integration (where _physics_process modifies velocity
# and then engine uses it), is the position update using new or old velocity?
print()
print("=" * 80)
print("WAIT: Let me verify how Godot RigidBody2D actually integrates.")
print("In Godot 4, RigidBody2D._physics_process is called AFTER the physics step.")
print("So when we modify linear_velocity in _physics_process, it takes effect")
print("on the NEXT physics tick. This means:")
print("  Tick N: engine moves body with current velocity")
print("  _physics_process: we reduce velocity (friction)")
print("  Tick N+1: engine moves body with reduced velocity")
print("")
print("This is effectively: position += old_velocity * dt, then velocity -= friction")
print("Which is FORWARD Euler integration.")
print("=" * 80)

print()
print("--- FORWARD EULER (old velocity for position) ---")
print()
print(f"{'Target(px)':>12} {'CS Speed':>10} {'Simulated':>12} {'Error(%)':>10}")
print("-" * 50)

for target_dist in [200, 300, 400, 500, 600, 700, 800, 1000, 1200]:
    cs_speed = player_cs_calculated_speed(target_dist)
    cs_speed_clamped = min(cs_speed, MAX_THROW_SPEED)

    actual_dist, frames = simulate_grenade_distance_old_vel(cs_speed_clamped)

    error = ((actual_dist - target_dist) / target_dist) * 100
    print(f"{target_dist:>12.1f} {cs_speed_clamped:>10.1f} {actual_dist:>12.1f} {error:>+10.1f}%")

print()
print("--- Finding CORRECT speed (FORWARD EULER) ---")
print()
print(f"{'Target(px)':>12} {'CS Speed':>10} {'Correct v':>10} {'CS/Correct':>10} {'Result':>12}")
print("-" * 60)

for target_dist in [200, 300, 400, 500, 600, 700, 800, 1000, 1200]:
    cs_speed = player_cs_calculated_speed(target_dist)
    cs_speed_clamped = min(cs_speed, MAX_THROW_SPEED)

    # Binary search for correct speed
    lo, hi = 10.0, 2000.0
    for _ in range(100):
        mid = (lo + hi) / 2.0
        dist, _ = simulate_grenade_distance_old_vel(mid)
        if dist < target_dist:
            lo = mid
        else:
            hi = mid
    correct_speed = (lo + hi) / 2.0

    ratio = cs_speed_clamped / correct_speed if correct_speed > 0 else 0
    overshoot = ((cs_speed_clamped - correct_speed) / correct_speed) * 100 if correct_speed > 0 else 0
    print(f"{target_dist:>12.1f} {cs_speed_clamped:>10.1f} {correct_speed:>10.1f} {ratio:>10.3f} {overshoot:>+10.1f}%")
