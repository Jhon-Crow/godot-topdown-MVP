# Issue #435: Grenade Flying Forever Bug - Case Study Analysis

## Summary

When throwing a grenade a long distance, it flew almost indefinitely without stopping, violating the user's requirement that "speed drop should be barely noticeable and only at the very end of the path."

## Timeline of Events

1. **Original Issue**: User reported grenades slowed down too quickly throughout their flight path
2. **Initial Fix Attempt**: Implemented velocity-dependent friction with `min_friction_multiplier = 0.15`
3. **Bug Introduced**: The 0.15 multiplier was too low, causing grenades to barely decelerate at high speeds
4. **User Report**: "граната летит вечно" (grenade flies forever) with attached game log

## Root Cause Analysis

### The Bug

In `grenade_base.gd` and `frag_grenade.gd`, the velocity-dependent friction formula:

```gdscript
@export var min_friction_multiplier: float = 0.15  # TOO LOW!
@export var ground_friction: float = 300.0

# At high speeds (>200 px/s):
var effective_friction = ground_friction * min_friction_multiplier
# = 300 * 0.15 = 45 px/s²
```

### Physics Calculation

With only 45 px/s² deceleration at high speeds:
- A grenade at 500 px/s takes: `500 / 45 = 11.1 seconds` to stop
- During this time, it travels: `v² / (2*a) = 500² / (2*45) = 2778 pixels`

For reference:
- Viewport width is ~1280 pixels
- The grenade would travel over 2 viewports before stopping

### Evidence from Game Log

The log file (`game_log_20260204_092300.txt`) shows:

```
[09:23:29] [INFO] [GrenadeBase] Simple mode throw! Dir: (0.992652, -0.121007), Speed: 483.2 (clamped from 483.2, max: 1186.5)
[09:23:29] [INFO] [FragGrenade] Grenade thrown (simple mode) - impact detection enabled
```

A frag grenade was thrown at 483.2 px/s at 09:23:29, but there's no subsequent "Grenade landed" or "EXPLODED" message in the remaining ~4 seconds of the log. The grenade was still flying when the log ended.

## Solution

Changed `min_friction_multiplier` from `0.15` to `0.5`:

```gdscript
@export var min_friction_multiplier: float = 0.5  # FIXED
```

### New Physics

With 50% friction at high speeds:
- Effective friction: `300 * 0.5 = 150 px/s²`
- Time to stop from 500 px/s: `500 / 150 = 3.3 seconds`
- Distance traveled: `500² / (2*150) = 833 pixels` (~0.65 viewports)

This provides:
1. A reasonable flight time (~3 seconds)
2. Still noticeably slower deceleration than constant friction (which would be 1.7 seconds)
3. Smooth transition to full friction at low speeds for natural stop

## Files Modified

1. `scripts/projectiles/grenade_base.gd` - Fixed `min_friction_multiplier` value
2. `scripts/projectiles/frag_grenade.gd` - Merged conflict, uses same base class parameters

## Lessons Learned

1. **Test edge cases**: The original fix focused on making grenades "maintain speed" but didn't verify they would actually stop in a reasonable time
2. **Physics math matters**: A seemingly small multiplier (0.15 vs 0.5) has dramatic effects on real-world behavior
3. **User feedback is crucial**: The user's bug report with attached log was essential for diagnosis

## Related Issues

- Issue #432: Grenade timer not activating (fixed in parallel merge)
- Issue #398: Linear damp causing double-damping (set to 0.0)
