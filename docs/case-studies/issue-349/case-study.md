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

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Too computationally expensive | High | Throttling, caching, LOD |
| Feels unfair/cheating to player | Medium | Add reaction delay, reduce accuracy |
| Complex geometry edge cases | Medium | Extensive testing, fallback to direct shot |
| Interactions with existing AI states | Medium | Clear state machine integration |
