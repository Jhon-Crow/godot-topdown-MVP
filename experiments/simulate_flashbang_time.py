#!/usr/bin/env python3
"""
Simulate whether flashbang could have exploded before stopping.

Flashbang timer starts at pin pull, not at throw.
If fuse = 4s and pin was pulled ~1s before throw, grenade only has ~3s of flight.
"""

def simulate_with_time_limit(initial_speed, friction, max_time, delta=1.0/60.0):
    """Simulate uniform friction with a time limit."""
    speed = initial_speed
    distance = 0.0
    time = 0.0

    while speed > 0.01 and time < max_time:
        distance += speed * delta
        friction_amount = friction * delta
        if friction_amount >= speed:
            speed = 0.0
        else:
            speed -= friction_amount
        time += delta

    return distance, time, speed

def simulate_double_with_time_limit(initial_speed, friction, max_time, delta=1.0/60.0):
    """Simulate both GDScript vel-dependent + C# uniform friction with time limit."""
    speed = initial_speed
    distance = 0.0
    time = 0.0
    friction_ramp_velocity = 200.0
    min_friction_multiplier = 0.5

    while speed > 0.01 and time < max_time:
        distance += speed * delta

        # GDScript velocity-dependent
        if speed >= friction_ramp_velocity:
            gdscript_multiplier = min_friction_multiplier
        else:
            t = speed / friction_ramp_velocity
            gdscript_multiplier = min_friction_multiplier + (1.0 - min_friction_multiplier) * (1.0 - t * t)

        gdscript_friction = friction * gdscript_multiplier * delta
        csharp_friction = friction * delta

        total = gdscript_friction + csharp_friction
        if total >= speed:
            speed = 0.0
        else:
            speed -= total
        time += delta

    return distance, time, speed


# Flashbang throw 2 from log3
# Timer activated: 08:50:52 (line 531)
# Throw: 08:50:53 (line 542) - approximately 1 second after timer
# Exploded: 08:50:56 (line 561) - 4 seconds after timer, 3 seconds after throw
# Fuse time: 4 seconds
# So grenade had ~3 seconds of flight before explosion

print("=" * 80)
print("FLASHBANG TIME-LIMITED FLIGHT ANALYSIS")
print("=" * 80)

speed = 568.7
friction = 300.0
flight_time = 3.0  # Only 3 seconds before explosion

# Uniform friction only (C# GrenadeTimer)
d_uniform, t_u, v_u = simulate_with_time_limit(speed, friction, flight_time)
print(f"\nWith ~3s flight (uniform friction only):")
print(f"  Distance: {d_uniform:.1f} px, remaining speed: {v_u:.1f}")

# How long until grenade stops with uniform friction?
d_full, t_full, _ = simulate_with_time_limit(speed, friction, 100.0)
print(f"  Full stop: {d_full:.1f} px at {t_full:.2f}s")
print(f"  Grenade stops at {t_full:.2f}s, fuse at 3.0s = {'still moving' if t_full > 3.0 else 'already stopped'}")

# Double friction
d_double, t_d, v_d = simulate_double_with_time_limit(speed, friction, flight_time)
print(f"\nWith ~3s flight (DOUBLE friction):")
print(f"  Distance: {d_double:.1f} px, remaining speed: {v_d:.1f}")

d_full_d, t_full_d, _ = simulate_double_with_time_limit(speed, friction, 100.0)
print(f"  Full stop: {d_full_d:.1f} px at {t_full_d:.2f}s")

print(f"\nActual from log: ~474.2 px (from spawn to explosion)")

# Now for different flight times
print("\n--- Uniform friction (C# only) at different flight times ---")
for ft in [1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0]:
    d, t, v = simulate_with_time_limit(speed, friction, ft)
    print(f"  {ft:.1f}s: distance={d:.1f} px, speed={v:.1f}")

print("\n--- Double friction at different flight times ---")
for ft in [1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0]:
    d, t, v = simulate_double_with_time_limit(speed, friction, ft)
    print(f"  {ft:.1f}s: distance={d:.1f} px, speed={v:.1f}")

# KEY ANALYSIS: For the Frag grenade, it explodes on IMPACT (landing)
# So no time limit applies — it travels until it stops
print("\n" + "=" * 80)
print("FRAG GRENADE (impact-triggered, no time limit)")
print("=" * 80)
speed_f = 554.9
friction_f = 280.0
d_u_frag, _, _ = simulate_with_time_limit(speed_f, friction_f, 100.0)
d_d_frag, _, _ = simulate_double_with_time_limit(speed_f, friction_f, 100.0)
print(f"  Uniform friction: {d_u_frag:.1f} px")
print(f"  Double friction:  {d_d_frag:.1f} px")
print(f"  Actual from log:  322.4 px")
print(f"  Ratio actual/uniform: {322.4/d_u_frag:.3f}")
print(f"  Ratio actual/double: {322.4/d_d_frag:.3f}")

# The Frag grenade is definitely showing less distance than even double friction
# This means TRIPLE friction or something else is happening!
# Let's check with Godot's linear_damp_mode
# Godot 4.x default for new projects: linear_damp_mode = COMBINE
# When linear_damp=0, this shouldn't matter
# But what if the scene file overrides are not applying?

# Actually, let me re-check: the frag grenade's GroundFriction might be different
# GrenadeTimer.cs has: DefaultFragGroundFriction = 280.0f
# But it only applies if GroundFriction >= 300.0f - 0.01f (see line 124)
# The grenade_base.gd has ground_friction = 300.0 as default
# The FragGrenade.tscn might override this

print("\n" + "=" * 80)
print("CHECKING IF GDSCRIPT FRICTION IS RUNNING WITH ITS OWN FRICTION VALUE")
print("=" * 80)

# What if GDScript uses 300 (default) but C# uses 280 for frag?
# That would be: GDScript vel-dep with F=300 + C# uniform with F=280
def simulate_mixed_double(initial_speed, gd_friction, cs_friction, delta=1.0/60.0):
    speed = initial_speed
    distance = 0.0
    friction_ramp_velocity = 200.0
    min_friction_multiplier = 0.5

    while speed > 0.01:
        distance += speed * delta

        if speed >= friction_ramp_velocity:
            gd_mult = min_friction_multiplier
        else:
            t = speed / friction_ramp_velocity
            gd_mult = min_friction_multiplier + (1.0 - min_friction_multiplier) * (1.0 - t * t)

        gd_f = gd_friction * gd_mult * delta
        cs_f = cs_friction * delta

        total = gd_f + cs_f
        if total >= speed:
            speed = 0.0
        else:
            speed -= total

    return distance

# Scenario: GDScript uses ground_friction=300 (default), C# uses 280 (frag override)
d_mixed = simulate_mixed_double(554.9, 300.0, 280.0)
print(f"  Mixed double (GD=300 + CS=280): {d_mixed:.1f} px")

# Scenario: Both use 280
d_both280 = simulate_mixed_double(554.9, 280.0, 280.0)
print(f"  Both 280: {d_both280:.1f} px")

# Scenario: Both use 300
d_both300 = simulate_mixed_double(554.9, 300.0, 300.0)
print(f"  Both 300: {d_both300:.1f} px")

print(f"  Actual: 322.4 px")

# None of these match exactly either.
# What if there's ALSO Godot engine damping on top of everything?
print("\n--- Adding engine damping to double friction ---")
for damp in [0.0, 0.5, 1.0, 1.5, 2.0]:
    speed = 554.9
    friction = 280.0
    delta = 1.0/60.0
    distance = 0.0
    v = speed
    friction_ramp_velocity = 200.0
    min_friction_multiplier = 0.5

    while v > 0.01:
        distance += v * delta

        # Godot linear_damp
        v *= (1.0 - delta * damp)

        # GDScript vel-dependent
        if v >= friction_ramp_velocity:
            gd_mult = min_friction_multiplier
        else:
            t = v / friction_ramp_velocity
            gd_mult = min_friction_multiplier + (1.0 - min_friction_multiplier) * (1.0 - t * t)

        gd_f = 300.0 * gd_mult * delta  # GDScript uses default 300
        cs_f = friction * delta  # C# uses 280

        total = gd_f + cs_f
        if total >= v:
            v = 0.0
        else:
            v -= total

    print(f"  damp={damp}: distance={distance:.1f} px")
