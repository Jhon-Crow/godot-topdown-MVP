# Case Study: Issue #98 - Tactical Enemy Movement and Wall Detection

## Executive Summary

This case study addresses issue #98 which requests tactical movement for enemies, along with improvements to wall/passage detection to prevent enemies from sticking to walls or attempting to walk through them.

## Issue Overview

### Original Request

**Issue #98** (Created: 2026-01-18)
- **Title**: update ai враги должны перемещаться тактически
- **Author**: Jhon-Crow (Repository Owner)

**Translated Requirements**:
1. Enemies should move tactically (reference: [Building Catch Tactics](https://poligon64.ru/tactics/70-building-catch-tactics))
2. Enemies should understand where passages are (not stick to walls, not try to walk into walls)
3. Update old behavior with new movement (within GOAP framework)
4. Preserve all previous functionality

### Reference Article Analysis

The reference article describes military tactical movement patterns for building clearance:

1. **Formation Movement**: Triangular "clover leaf" formation with leader at apex
2. **Sector Coverage**: Divide rooms into zones, work sector to completion before advancing
3. **Corridor Operations**: Overlapping fields of fire, cross visual axes
4. **Corner/Intersection Handling**: Back-to-back positioning, coordinated simultaneous clearance
5. **Entry Techniques**: "Cross" and "Hook" methods for room entry

---

## Root Cause Analysis

### Problem 1: Enemies Walking Into Walls

**Current Implementation:**
```gdscript
# In _check_wall_ahead()
var avoidance := Vector2.ZERO
for i in range(WALL_CHECK_COUNT):
    # Cast 3 raycasts at -28°, 0°, +28° angles
    # If hit, add perpendicular steering
# Blend 50/50 with target direction
if avoidance != Vector2.ZERO:
    direction = (direction * 0.5 + avoidance * 0.5).normalized()
```

**Issues:**
- Only 3 raycasts with 56° total spread - can miss walls at other angles
- 50/50 blend is too weak when moving toward a wall
- No distinction between solid walls and passageways
- Check distance (40 pixels) is too short for fast movement

### Problem 2: No Passage/Doorway Awareness

**Current Implementation:**
- Enemies treat all obstacle collisions the same
- No concept of "doorway" or "passage" vs solid wall
- Cover selection doesn't consider pathfinding reachability
- Can select cover positions that require navigating around obstacles

### Problem 3: Movement Not Tactical

**Current Implementation:**
- Cover-to-cover movement is linear (direct line)
- No consideration of tactical concepts like:
  - Staying close to walls while moving
  - Using perpendicular approach angles
  - Coordinated room entry patterns
  - Sector-based movement

---

## Proposed Solutions

### Solution 1: Enhanced Wall Avoidance

1. Increase raycast count from 3 to 8 for better coverage
2. Increase check distance from 40 to 60 pixels
3. Use stronger avoidance weight (0.7) when close to walls
4. Add velocity-based collision prediction

### Solution 2: Navigation-Aware Movement

1. Validate cover positions are reachable before selecting
2. Add multi-point pathfinding for complex navigation
3. Implement "slide along wall" behavior when blocked
4. Use intermediate waypoints for path around obstacles

### Solution 3: Tactical Movement Patterns

1. Add wall-hugging mode during approach
2. Implement perpendicular corner approach
3. Add brief pause at corners before advancing
4. Coordinate movement with other enemies (extend ASSAULT)

---

## Implementation Details

See `scripts/objects/enemy.gd` for the implementation of:
- Enhanced `_check_wall_ahead()` with more raycasts
- New `_find_path_around_obstacle()` function
- Updated cover selection with reachability validation
- Tactical movement constants and behaviors

---

## Testing Considerations

1. Test in BuildingLevel.tscn with multiple rooms and corridors
2. Verify enemies don't get stuck on walls
3. Verify enemies can navigate through doorways
4. Verify all existing behaviors (COMBAT, PURSUING, FLANKING, etc.) still work
5. Verify GOAP planning still produces valid action sequences

---

## Files Modified

1. `scripts/objects/enemy.gd` - Main enemy AI script
2. `docs/case-studies/issue-98/README.md` - This case study

---

## Timeline

- **2026-01-18**: Issue #98 created
- **2026-01-18**: Analysis and implementation started
