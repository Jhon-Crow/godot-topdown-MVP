# Case Study: Issue #293 - Improve Blood on Floor and Walls

## Overview

This case study documents the investigation and implementation of realistic blood effects for a top-down shooter game built with Godot Engine.

## Timeline of Events

### Phase 1: Initial Issue Creation

**Date:** 2026-01-23

The repository owner created issue #293 requesting improvements to the blood effects on floor and walls. The original requirements were:

1. Match the number of floor drops to the number of particles in the hit effect
2. Merge overlapping drops into unified blobs (puddles)
3. Add directional deformation to drops (splatter/splash effect)

Reference: [Shutterstock blood splatter images](https://www.shutterstock.com/ru/search/blood-splatter)

### Phase 2: Initial Solution (Round 1)

**Date:** 2026-01-24 (Early)

The AI solver implemented the first round of improvements:

- **Particle Count Matching:** Changed from fixed 4-8 drops to matching the actual particle count (~45 for lethal, ~22 for non-lethal)
- **Drop Merging:** Added `_cluster_drops_into_splatters()` method to detect and merge nearby drops within 12 pixels
- **Directional Deformation:** Added velocity-based elongation (1.0-3.0x) and rotation aligned with movement direction

**Files Modified:**
- `scripts/autoload/impact_effects_manager.gd`
- `scenes/effects/BloodDecal.tscn` (increased texture from 8x8 to 16x16)
- `tests/unit/test_impact_effects_manager.gd` (added 9 tests)

### Phase 3: Owner Feedback (Round 2)

**Date:** 2026-01-24 00:50:10 UTC

The owner provided additional feedback in Russian:

1. Overlapping puddles should merge into one complex blob (with gradient on contour)
2. Add smaller drops near the outermost drops (for more realistic look)
3. Try to add best practices for realistic blood

### Phase 4: Enhanced Implementation (Round 2)

**Date:** 2026-01-24 (Current)

Based on owner feedback and research into forensic blood spatter analysis, the following enhancements were implemented:

#### 4.1 Satellite Drops (Secondary Spatter)

Based on forensic science principles, satellite spatter forms when blood separates from the rim of the main drop during impact. This creates small secondary drops around the main stain.

**Implementation:**
- Added constants: `SATELLITE_DROP_PROBABILITY` (0.4), `SATELLITE_DROP_MIN/MAX_DISTANCE` (3-8 px)
- Created `_spawn_satellite_drops()` method that identifies outermost drops (>70th percentile from center)
- Spawns 3 small drops (0.15-0.35 scale) around each selected outermost drop

#### 4.2 Complex Merged Puddles

When 3+ drops merge, instead of a single enlarged circle, the system now spawns 2-4 overlapping decals with:
- Slight position offsets (2-5 px in random directions)
- Rotation variations (+-0.3 radians)
- Scale variations (0.85-1.15x)

This creates irregular blob shapes that look more organic while the radial gradient in each decal creates a soft-edged contour effect where they overlap.

#### 4.3 Crown/Blossom Effect

When blood drops land at nearly 90 degrees (larger drops, scale > 0.9), there's a 25% chance of spawning a crown-like splash pattern with 5 thin spines radiating outward.

**Based on forensic blood pattern analysis:**
> "A blood drop striking a smooth surface at a 90° angle will result in an almost circular stain; there is little elongation, and the spines and satellites are fairly evenly distributed around the outside of the drop."

## Root Cause Analysis

### Problem: Unrealistic Blood Effects

The original blood effect implementation had several issues:

1. **Fixed drop count:** Only 4-8 drops regardless of particle effect intensity
2. **Isolated drops:** Each drop rendered independently, no visual merging
3. **Uniform shapes:** All drops were circular with no directional variation

### Solution: Physically-Based Blood Rendering

The solution applies principles from forensic blood pattern analysis (BPA):

| Phenomenon | Real-World Cause | Implementation |
|------------|------------------|----------------|
| Satellite spatter | Blood separating from drop rim during impact | `_spawn_satellite_drops()` |
| Elongated stains | Blood traveling at an angle to surface | Velocity-based `elongation` factor |
| Crown/blossom | Blood impacting at 90° with high energy | `_spawn_crown_effect()` |
| Merged pools | Multiple drops landing close together | `_cluster_drops_into_splatters()` + overlapping decals |

## Technical Details

### New Constants Added

```gdscript
# Satellite drops
const SATELLITE_DROP_PROBABILITY: float = 0.4
const SATELLITE_DROP_MAX_DISTANCE: float = 8.0
const SATELLITE_DROP_MIN_DISTANCE: float = 3.0
const SATELLITE_DROP_SCALE_MIN: float = 0.15
const SATELLITE_DROP_SCALE_MAX: float = 0.35
const SATELLITE_DROPS_PER_MAIN: int = 3
const OUTERMOST_DROP_PERCENTILE: float = 0.7

# Crown effect
const CROWN_EFFECT_PROBABILITY: float = 0.25
const CROWN_SPINE_COUNT: int = 5
const CROWN_SPINE_SCALE_WIDTH: float = 0.12
const CROWN_SPINE_SCALE_LENGTH_MIN: float = 0.4
const CROWN_SPINE_SCALE_LENGTH_MAX: float = 0.7
const CROWN_SPINE_DISTANCE: float = 4.0
```

### Visual Effect Comparison

| Aspect | Before | After (Round 1) | After (Round 2) |
|--------|--------|-----------------|-----------------|
| Drop count | 4-8 fixed | ~45 (matches particles) | ~45 + satellites |
| Drop shape | Uniform circles | Elongated by velocity | Elongated + crown spines |
| Merging | None | Single enlarged decal | Multiple overlapping decals |
| Secondary drops | None | None | Satellite drops at edges |

## Research Sources

### Forensic Blood Pattern Analysis

- [Bloodstain Pattern Analysis: Principles](https://www.forensicsciencesimplified.org/blood/principles.html)
- [Blood Spatter Analysis - Alabama Forensics Course](https://accessdl.state.al.us/AventaCourses/access_courses/forensic_sci_ua_v17/06_unit/06-01/06-01_learn_text.htm)
- [Wikipedia: Bloodstain Pattern Analysis](https://en.wikipedia.org/wiki/Bloodstain_pattern_analysis)

### Game Development VFX

- [VFX Artist Breaks Down Four Techniques For Blood Splatter Effect](https://80.lv/articles/four-methods-for-creating-blood-splatter-effect-explained)
- [Unreal Engine Forums: Best way to make blood effects](https://forums.unrealengine.com/t/best-way-to-make-blood-effects/1562)

## Files in This Case Study

- `README.md` - This analysis document
- `issue-details.json` - Original issue data
- `issue-comments.json` - Comments on the issue
- `pr-details.json` - Pull request data
- `pr-comments.json` - Comments on the PR
- `solution-draft-log-round1.txt` - AI solver log from first implementation round

## Lessons Learned

1. **Domain Research Matters:** Researching forensic blood pattern analysis provided scientifically-grounded techniques that improved realism significantly.

2. **Iterative Feedback:** The owner's second round of feedback led to discovering satellite drops and crown effects that weren't in the original requirements.

3. **Layered Effects:** Complex visual effects are often better achieved by layering multiple simple elements (overlapping decals) rather than creating complex single elements.

4. **Constants for Tuning:** Using well-named constants allows easy adjustment of visual parameters without code changes.

## Related Links

- [Issue #293](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/293)
- [Pull Request #294](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/294)
- [Related PR #258 (original blood implementation)](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/258)
