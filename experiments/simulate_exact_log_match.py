#!/usr/bin/env python3
"""
Try to match the exact distances from the game log by testing different friction scenarios.
"""

import math

def simulate(initial_speed, gd_friction, cs_friction, gd_model="velocity_dependent", delta=1.0/60.0):
    """
    Simulate grenade with optional GDScript + C# friction.
    gd_friction: 0 to disable GDScript friction
    cs_friction: 0 to disable C# friction
    gd_model: "velocity_dependent" or "uniform"
    """
    speed = initial_speed
    distance = 0.0
    friction_ramp_velocity = 200.0
    min_friction_multiplier = 0.5

    while speed > 0.5:  # Using landing threshold ~50 for velocity check
        distance += speed * delta

        total_friction = 0.0

        # GDScript friction
        if gd_friction > 0:
            if gd_model == "velocity_dependent":
                if speed >= friction_ramp_velocity:
                    gd_mult = min_friction_multiplier
                else:
                    t = speed / friction_ramp_velocity
                    gd_mult = min_friction_multiplier + (1.0 - min_friction_multiplier) * (1.0 - t * t)
                total_friction += gd_friction * gd_mult * delta
            else:
                total_friction += gd_friction * delta

        # C# friction
        if cs_friction > 0:
            total_friction += cs_friction * delta

        if total_friction >= speed:
            speed = 0.0
        else:
            speed -= total_friction

    return distance


# Test cases from log
cases = [
    # name, speed, gd_ground_friction, cs_ground_friction, actual_distance
    ("Flashbang #3", 568.7, 300.0, 300.0, 471.0),
    ("Frag", 554.9, 280.0, 280.0, 324.7),
]

print("=" * 90)
print(f"{'Scenario':<55} {'Flashbang':>12} {'Frag':>12}")
print("=" * 90)

scenarios = [
    ("C# uniform only (no GD friction)",
     lambda s, gdf, csf: simulate(s, 0, csf, "uniform")),
    ("GD velocity-dep only (no C# friction)",
     lambda s, gdf, csf: simulate(s, gdf, 0, "velocity_dependent")),
    ("DOUBLE: GD vel-dep + C# uniform",
     lambda s, gdf, csf: simulate(s, gdf, csf, "velocity_dependent")),
    ("DOUBLE: GD uniform + C# uniform",
     lambda s, gdf, csf: simulate(s, gdf, csf, "uniform")),
    ("GD vel-dep + C# uniform (GD uses 300 for frag!)",
     lambda s, gdf, csf: simulate(s, 300.0, csf, "velocity_dependent")),
]

for name, func in scenarios:
    vals = []
    for case_name, speed, gdf, csf, actual in cases:
        d = func(speed, gdf, csf)
        vals.append(d)
    print(f"{name:<55} {vals[0]:>10.1f}px {vals[1]:>10.1f}px")

print(f"\n{'ACTUAL from game log':<55} {'471.0':>10}px {'324.7':>10}px")

# Now let's check: what if for flashbang, GDScript friction IS disabled (csharp_handles_friction=true)
# but for frag, it's NOT? (because of a timing or detection issue)
print("\n" + "=" * 90)
print("MIXED SCENARIO: Flashbang=C# only, Frag=Double friction")
print("=" * 90)

# Flashbang with C# only
d_fb = simulate(568.7, 0, 300.0, "uniform")
# Frag with double friction (GD uses default 300, C# uses 280)
d_frag = simulate(554.9, 300.0, 280.0, "velocity_dependent")
print(f"  Flashbang C# only:    {d_fb:.1f} px (expected ~471, ratio: {471.0/d_fb:.3f})")
print(f"  Frag double friction: {d_frag:.1f} px (expected ~325, ratio: {324.7/d_frag:.3f})")

# Even C# only gives 543.8 for flashbang, but actual is 471. Something else is reducing distance.

# Let's check: what if there's also Godot's default linear_damp?
# In Godot 4.x, the default linear_damp is 0 UNLESS the project settings override it.
# But what about the PhysicsServer2D?
print("\n" + "=" * 90)
print("C# UNIFORM FRICTION + GODOT INTERNAL DAMPING")
print("=" * 90)

for damp in [0.0, 0.25, 0.5, 0.75, 1.0]:
    speed = 568.7
    delta = 1.0/60.0
    distance = 0.0
    v = speed

    while v > 0.5:
        distance += v * delta
        # Godot damping
        v *= (1.0 - delta * damp)
        # C# friction
        f = 300.0 * delta
        if f >= v:
            v = 0.0
        else:
            v -= f

    print(f"  Flashbang damp={damp:.2f}: {distance:.1f} px")

for damp in [0.0, 0.25, 0.5, 0.75, 1.0]:
    speed = 554.9
    delta = 1.0/60.0
    distance = 0.0
    v = speed

    while v > 0.5:
        distance += v * delta
        v *= (1.0 - delta * damp)
        f = 280.0 * delta
        if f >= v:
            v = 0.0
        else:
            v -= f

    print(f"  Frag damp={damp:.2f}:      {distance:.1f} px")

# What if the throw_grenade_simple GDScript call RESETS the velocity?
# Look: C# sets velocity FIRST (line 2617), then calls GDScript throw_grenade_simple (line 2626)
# throw_grenade_simple does: freeze = false (already unfrozen!), then sets linear_velocity
# This should be fine - it's setting the same velocity again.
# BUT: What if there's a 1-frame delay due to C# setting velocity on an already unfrozen body,
# and GDScript resetting it? During that frame, the body could lose velocity due to friction.

# Actually, here's a key point: In Godot 4.x, setting linear_velocity on a RigidBody2D
# while it's not frozen might not take effect immediately if done during _process().
# The proper way is to set it during _integrate_forces() or while frozen.

# The C# code does:
# 1. Freeze = false  (unfreezes)
# 2. LinearVelocity = direction * speed  (sets velocity)
# 3. Call("throw_grenade_simple", ...)  (GDScript also sets velocity)

# In Godot, after unfreezing, the physics engine takes over.
# Setting LinearVelocity AFTER unfreezing might not stick!
# This is a known Godot behavior for RigidBody2D.

print("\n" + "=" * 90)
print("GODOT RIGIDBODY2D VELOCITY SETTING ISSUE")
print("=" * 90)
print("""
POTENTIAL ROOT CAUSE: Setting LinearVelocity on an unfrozen RigidBody2D
may not work reliably in Godot 4.x!

The C# code does:
1. _activeGrenade.Freeze = false;           // Line 2611
2. _activeGrenade.LinearVelocity = ...;     // Line 2617
3. Call("throw_grenade_simple", ...);       // Line 2626

GDScript throw_grenade_simple also does:
1. freeze = false  (redundant)
2. linear_velocity = ... (sets again)

If the velocity doesn't stick after unfreezing, the grenade might start
with reduced velocity on the first physics frame.

BUT: This would cause ALL grenades to undershoot by the same ratio,
which doesn't match our data (flashbang=87%, frag=59%).
""")

# Let me check one more thing: what if the GDScript friction code has a bug
# where _csharp_handles_friction is checked AFTER friction is already applied
# in some code path?

# Looking at grenade_base.gd _physics_process():
# Line 191: if not _csharp_handles_friction and has_node("GrenadeTimer"): set flag
# Line 193: if _has_exploded: return
# Line 212: if linear_velocity.length() > 0 and not _csharp_handles_friction: apply friction

# Wait! Line 193 returns if _has_exploded. This is BEFORE the friction check!
# But that's fine - if exploded, no friction needed.

# The flow is correct. So what's going on?

# Let me try: what if the frag grenade's _csharp_handles_friction stays False
# because the GrenadeTimer child node's Name gets changed or isn't "GrenadeTimer"?
# In Godot 4.x, when adding a child with the same name as an existing node,
# Godot auto-renames it (e.g., "GrenadeTimer2"). But there shouldn't be duplicates.

# Actually - what if the issue is with has_node() vs find_child()?
# has_node("GrenadeTimer") looks for a DIRECT child with that EXACT name.
# If the node tree is different, it might not find it.
# But the C# code adds it directly as a child of the grenade.

print("NEXT STEP: Remove GDScript friction entirely and rely 100% on C# friction")
print("This eliminates ALL possibilities of double friction.")
