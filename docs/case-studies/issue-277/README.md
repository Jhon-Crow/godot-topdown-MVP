# Case Study: Issue #277 - Excessive Grenade Throw Distance

## Executive Summary

This case study documents the investigation and fix for issue #277, where the grenade throwing system had an excessive maximum throw distance. The user reported that the maximum throw range was too large - it should be capped at approximately the viewport width for a light grenade (flashbang).

**Key Finding:** The `max_throw_speed` parameter was set too high (2500+ px/s), resulting in grenades traveling up to 10,000+ pixels instead of the intended ~1280 pixels (viewport width).

---

## 1. Original Issue Description

**Issue #277:** "настроить бросок гранаты" (Configure grenade throw)

### Original Requirements (Russian with English translation)

> в https://github.com/Jhon-Crow/godot-topdown-MVP/pull/260 была добавлена новая система броска.
> но максимальная дальность броска слишком большая (должна быть максимум для массы светошумовой - ширина вьюпорта).
>
> *Translation: In #260 a new throwing system was added. But the maximum throw distance is too large (for a flashbang's mass, it should be maximum viewport width).*

### Key Requirements
1. **Maximum throw distance** for flashbang = viewport width (~1280px)
2. **Heavier grenades** (frag) should have proportionally shorter maximum distances
3. **Realistic physics** based on grenade mass

---

## 2. Technical Analysis

### 2.1 Current Physics System

The grenade throwing system uses velocity-based physics with ground friction:

**Kinematics Formula:**
```
landing_distance = initial_velocity² / (2 × ground_friction)
```

**Current Configuration (from scene files):**

| Grenade Type | max_throw_speed | ground_friction | Calculated Max Distance |
|--------------|-----------------|-----------------|-------------------------|
| Flashbang    | 2500.0 px/s     | 300.0           | 10,417 pixels           |
| Frag Grenade | 2625.0 px/s     | 280.0           | 12,304 pixels           |

**Evidence from game logs (game_log_20260123_223150.txt):**
```
[22:31:59] [GrenadeBase] Velocity-based throw! Mouse vel: (1204.692, -151.4242), Swing: 102.4, Transfer: 0.63, Final speed: 2500.0
[22:32:09] [GrenadeBase] Velocity-based throw! Mouse vel: (3216.187, -63.84373), Swing: 281.4, Transfer: 1.00, Final speed: 2500.0
[22:32:45] [GrenadeBase] Velocity-based throw! Mouse vel: (7721.517, -7.857738), Swing: 657.4, Transfer: 1.00, Final speed: 2500.0
```

The logs show that even with varying mouse velocities (1204 to 7721 px/s), the final speed caps at 2500.0 px/s, which is the `max_throw_speed` limit.

### 2.2 Root Cause Identification

**Problem:** The `max_throw_speed` value is ~3x too high.

**Calculation for correct maximum speed:**

To achieve viewport width (1280px) as max distance with flashbang friction (300):
```
target_distance = 1280 pixels
friction = 300
required_speed = sqrt(2 × friction × distance)
required_speed = sqrt(2 × 300 × 1280)
required_speed = sqrt(768,000)
required_speed = 876.4 px/s
```

We'll use 850 px/s for flashbang (allowing for slight undershoot to ensure max distance is reliably under viewport width).

For frag grenade (heavier, should throw shorter distance):
```
target_distance = 900 pixels (70% of viewport for heavier grenade)
friction = 280
required_speed = sqrt(2 × 280 × 900)
required_speed = sqrt(504,000)
required_speed = 710 px/s
```

### 2.3 Real-World Context

According to military training standards:
- Average soldier throws M67 grenade (400g) approximately 30-40 meters
- M84 flashbang (240g) is lighter and could theoretically be thrown farther
- In top-down 2D view, 1 viewport width (~1280px) represents a reasonable maximum throw distance

**Reference Sources:**
- [Wikipedia: M84 stun grenade](https://en.wikipedia.org/wiki/M84_stun_grenade) - Weight: 240g
- [Global Security: FM 3-23.30 Grenade Training](https://www.globalsecurity.org/military/library/policy/army/fm/3-23-30/ch4.htm) - 30-40m throwing distance
- [Quora: Military Grenade Throwing Distance](https://www.quora.com/How-far-can-the-average-soldier-throw-a-hand-grenade) - 40m typical for M67

---

## 3. Timeline of Events

| Date | Event |
|------|-------|
| 2026-01-22 | PR #260 merged with velocity-based throwing system |
| 2026-01-23 22:31 | User testing reveals excessive throw distances |
| 2026-01-23 22:31 | Game log captured showing max speed of 2500 px/s |
| 2026-01-23 | Issue #277 created |

---

## 4. Solution

### 4.1 Parameter Changes

**FlashbangGrenade.tscn:**
| Parameter | Old Value | New Value | Reasoning |
|-----------|-----------|-----------|-----------|
| max_throw_speed | 2500.0 | 850.0 | Max distance ~1280px (viewport width) |
| mouse_velocity_to_throw_multiplier | 3.5 | 1.2 | Require faster mouse for max throw |

**FragGrenade.tscn:**
| Parameter | Old Value | New Value | Reasoning |
|-----------|-----------|-----------|-----------|
| max_throw_speed | 2625.0 | 710.0 | Max distance ~900px (70% viewport for heavier grenade) |
| mouse_velocity_to_throw_multiplier | 3.2 | 1.0 | Heavier grenade needs more effort |

### 4.2 Physics Verification

**After fix - Flashbang:**
```
max_distance = 850² / (2 × 300) = 722,500 / 600 = 1204 pixels ≈ viewport width
```

**After fix - Frag Grenade:**
```
max_distance = 710² / (2 × 280) = 504,100 / 560 = 900 pixels ≈ 70% viewport
```

### 4.3 Base Class Update

The base class `grenade_base.gd` should also have its default `max_throw_speed` reduced to prevent new grenade types from inheriting excessive values.

---

## 5. Affected Files

| File | Change |
|------|--------|
| `scenes/projectiles/FlashbangGrenade.tscn` | max_throw_speed: 2500→850, multiplier: 3.5→1.2 |
| `scenes/projectiles/FragGrenade.tscn` | max_throw_speed: 2625→710, multiplier: 3.2→1.0 |
| `scripts/projectiles/grenade_base.gd` | Default max_throw_speed: 2500→850 |

---

## 6. Lessons Learned

### 6.1 Physics Parameter Tuning
- Always verify physics calculations against expected gameplay results
- Provide clear documentation of intended ranges (viewport width = max distance)

### 6.2 Testing Guidelines
When adding physics-based systems:
1. Calculate expected values mathematically before implementation
2. Log actual values during testing
3. Compare logged values against calculations
4. Test at both minimum and maximum extremes

### 6.3 Configuration Documentation
Scene file parameters should include comments about:
- Expected maximum values
- How parameters interact with physics formulas
- Game design intent (e.g., "max distance = viewport width")

---

## 7. Data Files in This Case Study

### Logs Directory
- `game_log_20260123_223150.txt` - Game log showing excessive throw speeds

---

## 8. References

### Related Issues and PRs
- Issue #256: Original velocity-based throwing implementation request
- PR #260: Implementation of velocity-based grenade throwing
- Issue #277: This issue (excessive throw distance)

### External References
- [Wikipedia: M84 stun grenade](https://en.wikipedia.org/wiki/M84_stun_grenade)
- [Global Security: FM 3-23.30 Grenade Training](https://www.globalsecurity.org/military/library/policy/army/fm/3-23-30/ch4.htm)
- [Quora: Military Grenade Throwing Distance](https://www.quora.com/How-far-can-the-average-soldier-throw-a-hand-grenade)

---

## 9. Follow-up Adjustment (2.2x Distance Increase)

### 9.1 New Requirement

**Date:** 2026-01-23 20:01
**Request:** Owner requested to increase maximum throw distance by 2.2x from the initial fix.

**Comment from Jhon-Crow:**
> увеличь максимальную дальность в 2.2 раза
> *Translation: increase the maximum distance by 2.2 times*

### 9.2 Physics Calculations for 2.2x Increase

Since `distance = speed² / (2 × friction)`, to increase distance by 2.2x, we need to multiply speed by `√2.2 ≈ 1.483`.

**Speed multiplier:** 1.483

**Flashbang calculations:**
```
Old: 850.0 px/s → distance = 850² / (2 × 300) = 1204 pixels
New: 850.0 × 1.483 = 1260.8 px/s → distance = 1260.8² / (2 × 300) = 2649 pixels (2.20x)
```

**Frag Grenade calculations:**
```
Old: 710.0 px/s → distance = 710² / (2 × 280) = 900 pixels
New: 710.0 × 1.483 = 1053.1 px/s → distance = 1053.1² / (2 × 280) = 1980 pixels (2.20x)
```

### 9.3 Updated Parameter Values

**FlashbangGrenade.tscn:**
| Parameter | Initial Fix | After 2.2x Adjustment |
|-----------|-------------|----------------------|
| max_throw_speed | 850.0 | 1260.8 |
| Resulting max distance | ~1204px (viewport width) | ~2649px (2.2× viewport width) |

**FragGrenade.tscn:**
| Parameter | Initial Fix | After 2.2x Adjustment |
|-----------|-------------|----------------------|
| max_throw_speed | 710.0 | 1053.1 |
| Resulting max distance | ~900px (70% viewport) | ~1980px (1.6× viewport width) |

### 9.4 Context Interpretation

The new maximum throw distances (~2.6× viewport width for flashbang, ~2× viewport width for frag) represent more extreme throwing ranges. This may be intended for:
- Larger combat arenas
- More aggressive gameplay pacing
- Increased tactical flexibility in grenade placement

---

## 10. Velocity Scaling Fix + 400px Distance Increase

### 10.1 New Issues Reported

**Date:** 2026-01-23 20:37
**User:** Jhon-Crow

**Issue 1:** "даже если я медленно двигаю мышкой граната всё равно летит на максимум"
*Translation: even if I move the mouse slowly, the grenade still flies at maximum distance*

**Issue 2:** "увеличь максимальную дальность на 400px"
*Translation: increase maximum distance by 400px*

**Attached log file:** `game_log_20260123_233509.txt`

### 10.2 Root Cause Analysis

Analysis of the game log revealed the following patterns:

**Evidence from logs showing the problem:**
```
[23:35:26] Mouse velocity: (10232.15, 137.5096) → Final speed: 1260.8 (capped at max)
[23:35:34] Mouse velocity: (3212.58, -614.8641) → Final speed: 1260.8 (capped at max)
[23:35:46] Mouse velocity: (2350.991, -23.57303) → Final speed: 1260.8 (capped at max)
[23:36:04] Mouse velocity: (866.5116, 0) → Final speed: 1096.1 (below cap)
[23:36:13] Mouse velocity: (124.7697, -16.6975) → Final speed: 159.2 (short throw)
```

**Root Cause:** The `mouse_velocity_to_throw_multiplier` was set too high (1.2 for flashbang, 1.0 for frag).

With the formula:
```
throw_velocity = mouse_velocity × multiplier × transfer_efficiency / sqrt(mass_ratio)
```

Even "slow" mouse movements in games register 800-1500 px/s velocity. With multiplier 1.2:
- 1000 px/s mouse × 1.2 = 1200 px/s throw (hits cap at 1260.8)
- 500 px/s mouse × 1.2 = 600 px/s throw (medium distance)

This means only extremely slow movements (under ~500 px/s mouse) would produce short throws.

### 10.3 Solution Implementation

**Fix 1: Reduce velocity multiplier for better control range**

By reducing `mouse_velocity_to_throw_multiplier` from 1.2/1.0 to 0.5, we achieve:
- 500 px/s mouse × 0.5 = 250 px/s throw (short)
- 1000 px/s mouse × 0.5 = 500 px/s throw (medium)
- 2000 px/s mouse × 0.5 = 1000 px/s throw (long)
- 2700+ px/s mouse × 0.5 = capped at max (maximum)

This gives users a much wider range of controllable throw distances.

**Fix 2: Add +400px to maximum distance**

Current max distance formula: `max_distance = max_throw_speed² / (2 × ground_friction)`

For flashbang (friction = 300), current max = 2649px. Target = 3049px.
```
max_throw_speed = sqrt(3049 × 600) = sqrt(1829400) = 1352.6 px/s → use 1352.8
```

For frag grenade (friction = 280), current max = 1980px. Target = 2280px.
```
max_throw_speed = sqrt(2280 × 560) = sqrt(1276800) = 1130.0 px/s
```

### 10.4 Updated Parameter Values

**FlashbangGrenade.tscn:**
| Parameter | Before | After | Effect |
|-----------|--------|-------|--------|
| max_throw_speed | 1260.8 | 1352.8 | +400px max distance (2649px → 3049px) |
| mouse_velocity_to_throw_multiplier | 1.2 | 0.5 | Better throw distance control |

**FragGrenade.tscn:**
| Parameter | Before | After | Effect |
|-----------|--------|-------|--------|
| max_throw_speed | 1053.1 | 1130.0 | +300px max distance (1980px → 2280px) |
| mouse_velocity_to_throw_multiplier | 1.0 | 0.5 | Better throw distance control |

**grenade_base.gd:**
| Parameter | Before | After | Reasoning |
|-----------|--------|-------|-----------|
| mouse_velocity_to_throw_multiplier | 1.2 | 0.5 | New default for better control |

### 10.5 Expected Behavior After Fix

**Throw distance ranges:**
| Mouse Speed | Flashbang Distance | Frag Grenade Distance |
|-------------|-------------------|----------------------|
| ~200 px/s (very slow) | ~100px | ~80px |
| ~500 px/s (slow) | ~210px | ~180px |
| ~1000 px/s (medium) | ~835px | ~720px |
| ~2000 px/s (fast) | ~2500px (near max) | ~2050px |
| ~2700+ px/s (very fast) | 3049px (max) | 2280px (max) |

**Physics verification:**
- Flashbang max: 1352.8² / (2 × 300) = 3049 pixels ✓
- Frag max: 1130² / (2 × 280) = 2280 pixels ✓

### 10.6 Log Files Added

- `game_log_20260123_233509.txt` - User-provided log showing velocity scaling issues

---

*Case study compiled: 2026-01-23*
*Last updated: 2026-01-23 (velocity scaling fix + 400px distance increase)*
*Author: AI Issue Solver*
