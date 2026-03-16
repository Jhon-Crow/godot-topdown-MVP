#!/usr/bin/env python3
"""
Simulate grenade physics with Godot's default project linear_damp = 0.1.

In Godot 4.x:
- default linear_damp_mode is COMBINE
- Scene sets linear_damp = 0.0
- In COMBINE mode: effective_damp = node_damp + project_default = 0.0 + 0.1 = 0.1
- Godot applies: velocity *= (1 - damp * delta) each physics step (before forces)

Note: Actually, Godot's 2D physics applies damping as:
  velocity *= 1.0 / (1.0 + damp * delta)
This is slightly different from the naive formula.

BUT: looking at Godot source code (body_2d_sw.cpp), the actual formula is:
  real_t damp = 1.0 - step * total_linear_damp;
  if (damp < 0) damp = 0;
  b.linear_velocity *= damp;

So it's: velocity *= (1 - damp * delta)
"""

import math

def simulate_with_godot_damp(initial_speed, manual_friction, godot_damp, delta=1.0/60.0):
    """Simulate C# manual friction + Godot engine damping."""
    speed = initial_speed
    distance = 0.0
    frames = 0

    while speed > 0.5:
        # Godot applies damping FIRST in the physics step
        damp_factor = 1.0 - godot_damp * delta
        if damp_factor < 0:
            damp_factor = 0
        speed *= damp_factor

        # Then manual friction is applied (via _PhysicsProcess)
        friction_amount = manual_friction * delta
        if friction_amount >= speed:
            speed = 0.0
        else:
            speed -= friction_amount

        # Distance traveled this frame (using the velocity BEFORE friction)
        # Actually, Godot integrates position BEFORE applying forces in the same step
        # Let me check: Godot physics step order:
        # 1. Integrate position: position += velocity * delta
        # 2. Apply forces/damping
        # So the position update uses the velocity FROM THE PREVIOUS STEP
        # This means distance is calculated BEFORE damping/friction this frame

        # Wait, this is more subtle. The order in Godot's 2D physics:
        # - body_2d_sw.cpp integrate_forces():
        #   1. Apply damp to velocity
        #   2. Add gravity and other forces
        # - Then position integration:
        #   position += velocity * delta

        # So velocity is damped FIRST, then position is updated with the damped velocity.
        # Our simulation should reflect this:
        distance += speed * delta  # Use speed AFTER damping (which is what Godot does)

        frames += 1

    return distance, frames


def simulate_with_damp_and_double_friction(initial_speed, gd_friction, cs_friction, godot_damp, delta=1.0/60.0):
    """Simulate GDScript + C# friction + Godot engine damping."""
    speed = initial_speed
    distance = 0.0
    friction_ramp_velocity = 200.0
    min_friction_multiplier = 0.5

    while speed > 0.5:
        # Godot damping first
        damp_factor = 1.0 - godot_damp * delta
        if damp_factor < 0:
            damp_factor = 0
        speed *= damp_factor

        # GDScript velocity-dependent friction
        if gd_friction > 0:
            if speed >= friction_ramp_velocity:
                gd_mult = min_friction_multiplier
            else:
                t = speed / friction_ramp_velocity
                gd_mult = min_friction_multiplier + (1.0 - min_friction_multiplier) * (1.0 - t * t)
            gd_f = gd_friction * gd_mult * delta
        else:
            gd_f = 0

        # C# uniform friction
        cs_f = cs_friction * delta

        total = gd_f + cs_f
        if total >= speed:
            speed = 0.0
        else:
            speed -= total

        distance += speed * delta

    return distance


# Test scenarios
print("=" * 90)
print("SCENARIO: C# friction only + Godot project linear_damp")
print("=" * 90)

# Flashbang: speed=568.7, friction=300, actual=471.0
# Frag: speed=554.9, friction=280, actual=324.7

for damp in [0.0, 0.05, 0.1, 0.15, 0.2]:
    d_fb, _ = simulate_with_godot_damp(568.7, 300.0, damp)
    d_frag, _ = simulate_with_godot_damp(554.9, 280.0, damp)
    print(f"  damp={damp:.2f}: Flashbang={d_fb:.1f}px (target 471), Frag={d_frag:.1f}px (target 325)")

# Check: what if it's double friction + Godot damp?
print("\n" + "=" * 90)
print("SCENARIO: Double friction (GD vel-dep + C# uniform) + Godot project linear_damp")
print("=" * 90)

for damp in [0.0, 0.05, 0.1, 0.15, 0.2]:
    d_fb = simulate_with_damp_and_double_friction(568.7, 300.0, 300.0, damp)
    d_frag = simulate_with_damp_and_double_friction(554.9, 280.0, 280.0, damp)
    print(f"  damp={damp:.2f}: Flashbang={d_fb:.1f}px (target 471), Frag={d_frag:.1f}px (target 325)")

# Also check: GDScript friction disabled for flashbang but NOT for frag
print("\n" + "=" * 90)
print("SCENARIO: Flashbang=C# only, Frag=Double (GD vel-dep + C#) + Godot damp")
print("=" * 90)

for damp in [0.0, 0.05, 0.1, 0.15, 0.2]:
    d_fb, _ = simulate_with_godot_damp(568.7, 300.0, damp)
    d_frag = simulate_with_damp_and_double_friction(554.9, 280.0, 280.0, damp)
    print(f"  damp={damp:.2f}: Flashbang={d_fb:.1f}px (target 471), Frag={d_frag:.1f}px (target 325)")

# Interesting - let me also check with frag using GD friction=300 (default)
print("\n" + "=" * 90)
print("SCENARIO: Flashbang=C# only, Frag=Double (GD=300 + C#=280) + Godot damp")
print("=" * 90)

for damp in [0.0, 0.05, 0.1, 0.15, 0.2]:
    d_fb, _ = simulate_with_godot_damp(568.7, 300.0, damp)
    d_frag = simulate_with_damp_and_double_friction(554.9, 300.0, 280.0, damp)
    print(f"  damp={damp:.2f}: Flashbang={d_fb:.1f}px (target 471), Frag={d_frag:.1f}px (target 325)")

# Now the KEY insight: what if the grenade is affected by the default linear_damp=0.1?
# AND the GDScript friction IS properly disabled?
# The formula should then account for BOTH C# friction AND Godot damp.
print("\n" + "=" * 90)
print("MOST LIKELY SCENARIO: C# friction + Godot default damp=0.1")
print("=" * 90)

damp = 0.1
d_fb, f_fb = simulate_with_godot_damp(568.7, 300.0, damp)
d_frag, f_frag = simulate_with_godot_damp(554.9, 280.0, damp)
print(f"  Flashbang: {d_fb:.1f}px vs actual 471.0px (ratio: {471.0/d_fb:.3f})")
print(f"  Frag:      {d_frag:.1f}px vs actual 324.7px (ratio: {324.7/d_frag:.3f})")
print()
print(f"  If damp=0.1 is the answer, flashbang would match but frag would NOT.")
print(f"  This confirms the frag grenade has ADDITIONAL friction (likely double friction).")

# CORRECTED FORMULA: Account for Godot damping in the throw speed calculation
# For uniform deceleration + exponential damping, the analytical formula is complex.
# But we can numerically solve: what speed do we need to reach the target distance?
print("\n" + "=" * 90)
print("COMPENSATION: Required throw speed with damp=0.1")
print("=" * 90)

for target_d, friction, name in [(540.0, 300.0, "Flashbang"), (550.0, 280.0, "Frag")]:
    # Binary search for the speed needed
    lo, hi = 0.0, 5000.0
    for _ in range(100):
        mid = (lo + hi) / 2
        d, _ = simulate_with_godot_damp(mid, friction, 0.1)
        if d < target_d:
            lo = mid
        else:
            hi = mid
    speed_needed = (lo + hi) / 2

    # What's the simple formula speed?
    simple_speed = math.sqrt(2 * friction * target_d)

    factor = speed_needed / simple_speed
    print(f"  {name}: simple v={simple_speed:.1f}, need v={speed_needed:.1f}, factor={factor:.4f}")

# The solution: either
# 1. Set linear_damp_mode to REPLACE (so linear_damp=0 means exactly 0)
# 2. Set linear_damp to -0.1 (to cancel out project default in COMBINE mode)
#    Wait, can't set negative values...
# 3. Account for damping in the formula by using a compensation factor
# 4. Use _integrate_forces() to disable all damping

print("\n" + "=" * 90)
print("SOLUTION OPTIONS")
print("=" * 90)
print("""
Option 1: Set linear_damp_mode = REPLACE on the grenade
  - grenade.linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
  - Then linear_damp = 0.0 means EXACTLY zero damping
  - This is the cleanest solution

Option 2: Use custom_integrator = true on the grenade
  - Override _integrate_forces() to have full control
  - More complex but gives total control

Option 3: Calculate compensation factor for damp=0.1
  - Factor ≈ 1.18 for most speeds/frictions
  - But this varies slightly with speed/friction ratio
  - Not ideal but workable

Option 4 (BEST): Set damp_mode=REPLACE + fix double friction for frag
  - Eliminates Godot default damping interference
  - Also need to ensure GDScript friction is disabled for ALL grenade types
""")
