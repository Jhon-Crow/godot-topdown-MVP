# Case Study: Issue #349 - Add Mechanics Understanding to Enemies

## Issue Summary

**Issue Title:** добавь понимание механик врагам (Add mechanics understanding to enemies)

**Requirements:**
1. Enemies with M16 should calculate and use ricochets (up to 2) to hit the player's predicted position
2. Enemies with M16 should also calculate and use penetration shots (wallbangs) if the player's predicted position can be hit through a penetrable wall

## Current Codebase Analysis

### Existing Bullet Mechanics

The codebase already has sophisticated bullet mechanics implemented:

#### Ricochet System (`scripts/projectiles/bullet.gd`)

- **Ricochet calculation**: Uses physics-based reflection formula `r = d - 2(d ⋅ n)n`
- **Impact angle calculation**: Grazing angle from surface (0° = parallel, 90° = perpendicular)
- **Probability curve**:
  - 0-15°: ~100% ricochet probability
  - 45°: ~80% ricochet probability
  - 90°: ~10% ricochet probability
- **Max ricochets**: Configurable via `CaliberData`, default -1 (unlimited)
- **Velocity retention**: Default 85% per ricochet
- **Damage multiplier**: Default 50% damage after ricochet
- **Angle deviation**: Default ±10° random deviation for realism

#### Penetration System (`scripts/projectiles/bullet.gd`)

- **Distance-based penetration**:
  - Point-blank (0-5% viewport): 100% penetration, ignores ricochet
  - 40% viewport: Normal ricochet rules, then penetration if ricochet fails
  - 100% viewport: 30% max penetration chance
- **Max penetration distance**: 48 pixels (2× thinnest wall = 24px)
- **Damage retention**: 90% damage after penetration for 5.45x39mm
- **Penetration vs Ricochet**: Penetration only triggers when ricochet fails

#### Caliber Data (`scripts/data/caliber_data.gd`)

Configurable properties:
- `can_ricochet`: boolean
- `max_ricochets`: int (-1 = unlimited)
- `max_ricochet_angle`: float (degrees)
- `base_ricochet_probability`: float (0.0-1.0)
- `velocity_retention`: float
- `ricochet_damage_multiplier`: float
- `ricochet_angle_deviation`: float (degrees)
- `can_penetrate`: boolean
- `max_penetration_distance`: float (pixels)
- `post_penetration_damage_multiplier`: float

### Existing Enemy AI

#### Aiming & Shooting (`scripts/objects/enemy.gd`)

- **Lead prediction**: Already implemented - predicts player position based on velocity
  - Uses iterative algorithm (3 iterations for convergence)
  - Validates predicted position is visible (not behind cover)
  - Requires continuous visibility timer threshold
- **Shooting checks**:
  - Aim tolerance (cos(30°) = 0.866)
  - Friendly fire avoidance
  - Line of sight validation
- **GOAP-based AI**: Goal-oriented action planning for tactical decisions

#### AI States
- IDLE, COMBAT, SEEKING_COVER, IN_COVER, FLANKING, SUPPRESSED, RETREATING, PURSUING, ASSAULT, SEARCHING

## Technical Research Findings

### Ricochet Shot Prediction Algorithms

From research on billiards AI and ray reflection:

1. **Reflection Formula** (already in codebase):
   ```
   r = d - 2(d ⋅ n)n
   ```
   Where: r = reflected direction, d = incoming direction, n = surface normal

2. **Bank Shot Geometry** (billiards):
   - The approach angle equals the exit angle (law of reflection)
   - Multiple bounces follow sequential application of reflection formula
   - Can be computed recursively for N bounces

3. **Raycasting for Ricochet Paths**:
   - Cast ray from enemy → wall
   - Calculate reflection direction using surface normal
   - Cast second ray from hit point in reflected direction
   - Continue for up to N bounces (requested: 2)
   - Check if final ray path intersects player position

### Wallbang/Penetration Prediction

From Counter-Strike mechanics research:

1. **Key Factors**:
   - Weapon penetration power
   - Material type and thickness
   - Distance traveled through obstacle
   - Damage falloff through walls

2. **AI Wallbang Calculation Approach**:
   - Cast ray from enemy → player (ignoring walls)
   - Detect intervening walls
   - Calculate if bullet can penetrate based on:
     - Wall thickness (multiple raycasts to measure)
     - Caliber penetration power
     - Distance to wall

## Proposed Solutions

### Solution 1: Raycast-Based Ricochet Path Finding

**Algorithm:**
```
1. When player is not directly visible:
   a. Cast N rays in arc around enemy's direction
   b. For each ray hitting a wall:
      - Calculate reflection direction using surface normal
      - Cast reflected ray
      - Check if reflected ray path reaches player (with tolerance)
   c. If found, store ricochet aim point

2. During shooting:
   a. If ricochet path exists and is still valid:
      - Aim at the calculated wall point
      - Fire bullet (bullet ricochet mechanics already implemented)
```

**Complexity:** O(N × R) where N = number of sample rays, R = max ricochets

**Pros:**
- Uses existing bullet ricochet system
- Relatively simple geometric calculation
- Can limit computation by sampling key angles

**Cons:**
- May miss optimal ricochet angles between samples
- Computational cost per enemy per frame
- Needs optimization (caching, throttling)

### Solution 2: Precomputed Ricochet Maps

**Algorithm:**
```
1. At level load:
   a. Build spatial hash of walls/surfaces
   b. Precompute ricochet visibility graphs for key positions

2. At runtime:
   a. Query graph for viable ricochet paths
   b. Use closest precomputed solution
```

**Pros:**
- Very fast runtime queries
- No per-frame raycast overhead

**Cons:**
- Requires level preprocessing
- Memory overhead for storing graphs
- Doesn't adapt to dynamic obstacles
- Complex implementation

### Solution 3: Analytical Geometric Approach

**Algorithm:**
```
1. For single ricochet:
   a. For each wall segment in range:
      - Calculate mirror point of player across wall line
      - If line from enemy to mirror point hits wall segment:
         - Wall intersection is the aim point for ricochet

2. For double ricochet:
   a. Apply same logic recursively with intermediate mirror points
```

**Pros:**
- Mathematically precise
- No sampling artifacts
- Can find optimal ricochet path

**Cons:**
- More complex math
- Need to enumerate wall segments efficiently
- Becomes combinatorially expensive with more bounces

### Solution 4: Wallbang Detection

**Algorithm:**
```
1. When player is occluded:
   a. Cast ray from enemy to player's predicted position
   b. Track all wall intersections
   c. Calculate total wall thickness traversed
   d. If thickness ≤ max_penetration_distance:
      - Mark as wallbang opportunity

2. During shooting:
   a. If wallbang opportunity exists:
      - Aim at predicted player position through wall
      - Fire (penetration mechanics already handle the rest)
```

**Pros:**
- Uses existing penetration system
- Simple implementation
- No complex geometry

**Cons:**
- Need to measure wall thickness accurately
- May require multiple raycasts

## Recommended Implementation Approach

### Phase 1: Wallbang (Penetration) Targeting

**Priority: High** - Simpler to implement, leverages existing systems

1. Add `_check_wallbang_opportunity()` function to `enemy.gd`
2. When player not visible but position known:
   - Raycast to predicted position
   - Calculate wall thickness
   - If penetrable, mark as wallbang target
3. In `_shoot()`: If wallbang target valid, aim at it

### Phase 2: Single Ricochet Targeting

**Priority: Medium** - Adds tactical depth

1. Add `_find_ricochet_path()` function using analytical approach
2. Consider nearby wall segments (within weapon range)
3. Use mirror-point geometry for precise calculation
4. Cache result with invalidation on position change

### Phase 3: Double Ricochet Targeting

**Priority: Lower** - Impressive but computationally expensive

1. Extend ricochet path finding recursively
2. Heavy throttling (compute once per second)
3. Only for stationary/camping targets

## Existing Components That Can Be Reused

| Component | Location | Reusable For |
|-----------|----------|--------------|
| `_get_surface_normal()` | `bullet.gd:417` | Wall normal detection |
| `_calculate_impact_angle()` | `bullet.gd:442` | Ricochet validity check |
| `_calculate_ricochet_probability()` | `bullet.gd:466` | Filtering low-probability shots |
| `_get_max_penetration_distance()` | `bullet.gd:763` | Wallbang thickness check |
| `_calculate_lead_prediction()` | `enemy.gd:4114` | Player position prediction |
| `PhysicsRayQueryParameters2D` | Godot API | Ray casting |
| Cover raycasts array | `enemy.gd:248` | Existing raycast infrastructure |

## Libraries & References

### Relevant Open-Source Projects

1. **PoolTool** (Python) - Billiards simulation with ricochet algorithms
   - https://ekiefl.github.io/2020/12/20/pooltool-alg/

2. **Corona Ray Casting Tutorial** - Game ray reflection examples
   - https://docs.coronalabs.com/tutorial/games/rayCasting/index.html

3. **Godot Ray Reflection Forum** - GDScript reflection examples
   - https://godotforums.org/d/26153-how-can-i-bounce-reflect-a-raycast

### Academic Papers

1. "AI Optimization of a Billiard Player" - Shot selection algorithms
2. "Adaptive Shooting for Bots in First Person Shooter Games" - Aim prediction
3. "Predictive Aim Mathematics for AI Targeting" - Lead prediction math

## Performance Considerations

### Computation Budget

Assuming 60 FPS and 10 enemies:
- Budget per enemy per frame: ~1.6ms
- Recommended: Stagger calculations across frames
- Use visibility/distance culling to skip distant enemies

### Optimization Strategies

1. **Spatial partitioning**: Only check nearby walls
2. **Caching**: Store valid ricochet paths, invalidate on movement
3. **Throttling**: Recalculate every N frames or on significant position change
4. **Early-out**: Skip if player is directly visible (direct shot preferred)
5. **LOD**: Only complex calculations for close/important enemies

## Success Criteria

1. Enemies can hit player via single ricochet when no direct LOS
2. Enemies can hit player via double ricochet (rare, impressive plays)
3. Enemies can wallbang player through thin walls
4. Performance remains acceptable (no frame drops with 10+ enemies)
5. Behavior feels intelligent, not omniscient (add delay/accuracy reduction)

## Bug Report Analysis (2026-02-06)

### Symptom

After implementing the advanced targeting system, the game owner reported "enemies are completely broken" (враги полностью сломались). The game log (`game_log_20260206_141705.txt`) showed:

```
[BuildingLevel] Child 'Enemy1': script=true, has_died_signal=false
...
[BuildingLevel] Child 'Enemy10': script=true, has_died_signal=false
[BuildingLevel] Enemy tracking complete: 0 enemies registered
[ScoreManager] Level started with 0 enemies
```

All 10 enemies had their scripts attached (`script=true`) but the `died` signal was not detected (`has_died_signal=false`), meaning no enemies were tracked by the level system. This caused enemies to be non-functional - they couldn't register deaths, scores wouldn't track, and the game couldn't determine when all enemies were cleared.

### Root Cause

**GDScript indentation parse error** at line 1707 in `enemy.gd`:

```gdscript
# BUGGY CODE (commit 6616e6f):
if not _can_see_player and not _under_fire and not _has_valid_targeting():
    _log_debug("Lost sight of player from cover, transitioning to PURSUING")
        _transition_to_pursuing()  # <-- THREE tabs (invalid!)
```

The `_transition_to_pursuing()` call had 3 tabs of indentation, but `_log_debug(...)` above it only had 2 tabs. In GDScript, you cannot increase indentation after a simple statement (only after `if`, `for`, `func`, etc.). This is a **parse error** that causes the entire `enemy.gd` script to fail to compile.

When a GDScript fails to parse:
1. The node keeps its script reference (`get_script() != null` → `script=true`)
2. But the script class definition is invalid, so signals defined in it are not registered
3. `has_signal("died")` returns `false` because the class couldn't be parsed
4. `building_level.gd._setup_enemy_tracking()` skips all enemies since none have the `died` signal

### Timeline

1. **Commit 569c316** (`feat: implement snap-shooting at suspected positions`): Introduced the `_process_in_cover_state` changes with the indentation bug
2. **Commit 6616e6f** (`refactor: compact advanced targeting code`): Compacted code but didn't fix the indentation error
3. **2026-02-06 14:17:05**: Owner tested the exported build, found enemies completely broken
4. **2026-02-06 11:17:33**: Owner posted game log and bug report on PR #381

### Fix

Changed line 1707 from 3 tabs to 2 tabs:

```gdscript
# FIXED:
if not _can_see_player and not _under_fire and not _has_valid_targeting():
    _log_debug("Lost sight of player from cover, transitioning to PURSUING")
    _transition_to_pursuing()  # <-- TWO tabs (correct)
```

### Additional Changes

- Refactored `_aim_at_player()` to delegate to `_aim_at_position()` (DRY principle, saves 17 lines)
- Compacted advanced targeting functions to bring `enemy.gd` to exactly 5000 lines (CI limit)
- Simplified `_update_advanced_targeting()` logic for cleaner early-return pattern

### Lessons Learned

1. **GDScript indentation errors are silent in exports** - the game doesn't crash, it just makes all nodes using the broken script lose their class behavior
2. **Always verify parse correctness** - a single extra tab/space can break an entire 5000-line script
3. **The `script=true, has_signal=false` pattern** is a clear indicator of a script parse/compile failure in Godot

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Too computationally expensive | High | Throttling, caching, LOD |
| Feels unfair/cheating to player | Medium | Add reaction delay, reduce accuracy |
| Complex geometry edge cases | Medium | Extensive testing, fallback to direct shot |
| Interactions with existing AI states | Medium | Clear state machine integration |
| GDScript parse errors in large files | Critical | Automated syntax validation, CI checks |
