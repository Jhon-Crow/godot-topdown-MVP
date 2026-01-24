# Case Study: Issue #322 - Enemy Search State (GOAP)

## Issue Summary

**Title (Russian):** добавь состояние поиска врагам
**Title (English):** Add a search state to enemies

**Requirements:**
1. Add a **GOAP search state** to the enemy AI
2. Enemies should methodically search the area (using **left/right hand rule**) where they last saw/heard the player
3. When all points in the zone are searched, the zone should **expand**
4. This state should be triggered:
   - After the special "last chance" effect ends
   - When the enemy doesn't see/hear the player in the suspicion zone (where the player should be according to enemy memory)

## Current System Analysis

### Existing GOAP States (AIState enum)

The enemy AI currently has 8 states:
```
IDLE        - Patrol or guard (initial state)
COMBAT      - Actively engaging player/investigating sounds
SEEKING_COVER - Moving to cover position
IN_COVER    - Taking cover from fire
FLANKING    - Attempting tactical flank maneuvers
SUPPRESSED  - Under fire, staying in cover
RETREATING  - Moving to cover while shooting
PURSUING    - Cover-to-cover movement toward player
ASSAULT     - Coordinated multi-enemy rush (DISABLED per issue #169)
```

### Current Search-Related Behavior

The existing system has some search-related functionality through the **Memory System** (Issue #297):

1. **EnemyMemory class** (`scripts/ai/enemy_memory.gd`):
   - Tracks `suspected_position` with confidence levels (0.0-1.0)
   - Confidence thresholds: High (>0.8), Medium (0.5-0.8), Low (<0.5)
   - Decay over time (0.1/sec default)

2. **Search-Related GOAP Actions** (`scripts/ai/enemy_actions.gd`):
   - `InvestigateHighConfidenceAction` - Direct pursuit to suspected position
   - `InvestigateMediumConfidenceAction` - Cautious approach with cover checks
   - `SearchLowConfidenceAction` - Area search/extended patrol

3. **Current Limitations:**
   - **No systematic search pattern** - enemies use cover-to-cover pursuit
   - **No left/right hand rule** - movement is random/cover-based
   - **No expanding zone** - just single point investigation
   - **No true "search state"** - uses PURSUING state instead

### Post-Last Chance Behavior (Issue #318)

When the "last chance" effect ends:
1. Enemy memory is reset with **LOW confidence (0.35)**
2. Enemy transitions to **PURSUING state**
3. Enemy navigates to old remembered position
4. If player not found, confidence decays and enemy returns to IDLE

**Gap:** No methodical area search is performed.

## Research Findings

### Left/Right Hand Rule Algorithm

The **wall follower algorithm** (aka left-hand rule or right-hand rule) is a classic maze-solving technique:

**Algorithm steps:**
1. If you can turn left (right for right-hand rule), do it
2. Else if you can continue straight, go straight
3. Else if you can turn right (left for left-hand rule), do it
4. If at dead end, turn around 180 degrees

**Properties:**
- Depth-first in-order tree traversal
- Requires no memory of prior paths
- Guaranteed to find exit in simply-connected mazes

**Source:** [Wikipedia - Maze-solving algorithm](https://en.wikipedia.org/wiki/Maze-solving_algorithm)

### Expanding Square Search Pattern

From Search and Rescue (SAR) operations and robotics:

**Expanding Square Search (SS):**
- Start at datum point (last known position)
- First leg is down drift
- All turns are 90 degrees
- Search leg length increases by one "track space" on every other leg
- Creates an outward spiral pattern

**Properties:**
- Most effective when position is accurately known
- Search area is small initially, then expands
- Can search indefinitely by expanding grid

**Sources:**
- [NASA - Efficient Algorithm for Rectangular Spiral Search](https://ntrs.nasa.gov/citations/20080047208)
- [IAMSAR Search Patterns](https://owaysonline.com/iamsar-search-patterns/)
- [McGill - Spiral Search as Efficient Robotic Search](https://cim.mcgill.ca/~mrl/pubs/scottyb/burl-aaai99.pdf)

### F.E.A.R. AI Search Behavior

F.E.A.R. (2005) is considered a benchmark for GOAP-based enemy AI:

**Search behaviors include:**
- Soldiers split into pairs who cover each other
- Systematically search rooms in an area
- Use dialogue like "Anyone see him?" to communicate
- Can dynamically re-plan if player slips away

**Source:** [GDC Vault - Three States and a Plan: The AI of F.E.A.R.](https://gdcvault.com/play/1013282/Three-States-and-a-Plan)

## Proposed Solutions

### Solution 1: Wall-Following Search State (Recommended)

**Concept:** Implement a new `SEARCHING` state that uses the left/right hand rule adapted for 2D open areas.

**Implementation approach:**
1. Add new `AIState.SEARCHING` enum value
2. Create `SearchingState` class extending `EnemyState`
3. Implement wall-following logic using raycasts:
   - Cast rays in preferred direction (left-hand or right-hand)
   - Follow walls/obstacles while scanning area
   - Mark visited cells in a local grid

**Expansion mechanism:**
- Define initial search radius around last known position
- When search completes (all reachable cells visited), expand radius
- Repeat until max radius reached or player found

**Pros:**
- Methodical, realistic behavior
- Players can learn and exploit the pattern
- Natural integration with existing cover system

**Cons:**
- Complex raycast/navigation logic
- May look robotic if not tuned well

### Solution 2: Expanding Square Spiral Search

**Concept:** Implement SAR-style expanding square search pattern.

**Implementation approach:**
1. Define waypoints in expanding spiral from datum point
2. Enemy moves waypoint-to-waypoint
3. At each waypoint, scan surroundings (raycast for player)
4. Spiral expands on each complete circuit

**Code pseudocode:**
```gdscript
var search_leg_length := 50.0  # Initial leg length
var search_direction := 0  # 0=N, 1=E, 2=S, 3=W
var legs_completed := 0

func generate_next_waypoint():
    var offset := Vector2.ZERO
    match search_direction:
        0: offset = Vector2(0, -search_leg_length)  # North
        1: offset = Vector2(search_leg_length, 0)   # East
        2: offset = Vector2(0, search_leg_length)   # South
        3: offset = Vector2(-search_leg_length, 0)  # West

    legs_completed += 1
    search_direction = (search_direction + 1) % 4

    # Expand every 2 legs
    if legs_completed % 2 == 0:
        search_leg_length += EXPANSION_RATE

    return current_position + offset
```

**Pros:**
- Simple to implement
- Predictable, systematic coverage
- Easy to tune (leg length, expansion rate)

**Cons:**
- Ignores level geometry (may try to walk through walls)
- Less "intelligent" looking than wall-following

### Solution 3: NavMesh-Based Area Search

**Concept:** Use Godot's NavigationServer2D to generate search waypoints within navigable area.

**Implementation approach:**
1. Get navigable polygon near last known position
2. Generate grid of points within polygon
3. Visit points in expanding concentric order
4. Use NavigationAgent2D for pathfinding between points

**Pros:**
- Respects level geometry automatically
- Uses existing navigation infrastructure
- Can be combined with cover system

**Cons:**
- Requires NavigationRegion2D setup
- May not work well in all level designs

### Solution 4: Hybrid Approach (Recommended)

**Concept:** Combine expanding square with navigation and obstacle awareness.

**Implementation:**
1. Generate waypoints using expanding square algorithm
2. Validate each waypoint using NavigationServer2D
3. If waypoint is unreachable, skip to next
4. At each waypoint, perform local scan (raycast cone)
5. If obstruction detected, follow wall briefly (left-hand rule)

**This combines:**
- Systematic coverage (expanding square)
- Geometry awareness (navigation validation)
- Natural obstacle handling (wall following)

## Recommended Implementation Plan

### Phase 1: Core Search State
1. Add `AIState.SEARCHING` enum value
2. Create `SearchingState` class in `scripts/ai/states/`
3. Add search zone tracking variables to `enemy.gd`:
   - `_search_center: Vector2`
   - `_search_radius: float`
   - `_search_waypoints: Array[Vector2]`
   - `_current_search_waypoint_index: int`

### Phase 2: Search Pattern Generation
1. Implement `_generate_search_waypoints()` using expanding square
2. Validate waypoints against navigation mesh
3. Add visual debug mode to show search pattern (F7 toggle)

### Phase 3: GOAP Integration
1. Add new `SearchAreaAction` GOAP action
2. Set preconditions: `has_suspected_position: true`, `player_visible: false`, `confidence_low: true`
3. Set effects: `area_searched: true`
4. Modify `reset_memory()` to trigger search state

### Phase 4: Zone Expansion
1. Track visited waypoints
2. When all waypoints visited, expand `_search_radius`
3. Regenerate waypoints with larger radius
4. Set maximum search duration/radius before returning to patrol

### Phase 5: Triggers
1. **After last chance:** Modify `reset_memory()` to transition to SEARCHING
2. **Memory decay:** When PURSUING fails to find player, transition to SEARCHING

## Existing Libraries/Components

### In This Codebase
- `NavigationAgent2D` - Already used for pathfinding
- `EnemyMemory` - Confidence-based memory system
- `GOAPPlanner` - A* action planning
- `EnemyState` base class - State machine foundation
- `VisionComponent` - Raycast-based visibility checks

### Godot Built-in
- `NavigationServer2D` - Path computation and validation
- `NavigationRegion2D` - Defines navigable areas
- `RayCast2D` - Wall/obstacle detection

### External Resources
- [Godot Navigation 2D Overview](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_introduction_2d.html)
- [GOAP in Excalibur.js](https://excaliburjs.com/blog/goal-oriented-action-planning/) - Reference implementation
- [F.E.A.R. AI Paper](https://www.gamedeveloper.com/design/building-the-ai-of-f-e-a-r-with-goal-oriented-action-planning) - Industry best practices

## Complexity Estimate

| Phase | Effort | Files Modified |
|-------|--------|----------------|
| Phase 1 | Medium | `enemy.gd`, new `searching_state.gd` |
| Phase 2 | Medium | `enemy.gd`, `searching_state.gd` |
| Phase 3 | Low | `enemy_actions.gd`, `goap_planner.gd` |
| Phase 4 | Low | `searching_state.gd` |
| Phase 5 | Low | `enemy.gd`, `last_chance_effects_manager.gd` |

**Total estimated effort:** Medium complexity, requires careful integration with existing GOAP system.

## Test Plan

1. **Unit tests:**
   - Search waypoint generation
   - Zone expansion logic
   - GOAP action selection

2. **Integration tests:**
   - State transitions: PURSUING -> SEARCHING -> IDLE
   - Last chance trigger: Effect ends -> SEARCHING activates
   - Memory decay trigger: Low confidence -> SEARCHING activates

3. **Manual testing:**
   - Visual verification of search pattern (F7 debug)
   - Player hiding and observing enemy search behavior
   - Zone expansion over time

## Implementation Status

### Completed Features

#### Phase 1-5: Core SEARCHING State (Commits 1ef10c3 and earlier)
- Added `AIState.SEARCHING` enum value
- Implemented expanding square spiral pattern
- NavigationServer2D validation for waypoints
- Search zone expansion when all waypoints visited
- Integration with Last Chance effect (triggers SEARCHING after effect ends)
- Timeout and max radius limits

#### Phase 6: Zone Tracking System (Latest Implementation)
**New requirements from user feedback:**
1. Enemies should mark searched zones as "checked" and not re-check them
2. Search zone should expand until player is found
3. After expansion, enemies should only check the outer ring (new unchecked zones)

**Implementation details:**

```gdscript
# New variables added:
var _search_visited_zones: Dictionary = {}  # Tracks visited positions
const SEARCH_ZONE_SNAP_SIZE: float = 50.0  # Grid size for zone identification

# New functions:
func _get_zone_key(pos: Vector2) -> String  # Converts position to grid-snapped key
func _is_zone_visited(pos: Vector2) -> bool  # Checks if zone already visited
func _mark_zone_visited(pos: Vector2) -> void  # Marks zone as visited
```

**Key changes:**
- `_generate_search_waypoints()`: Only adds waypoints in unvisited zones
- `_process_searching_state()`: Marks zones as visited after scanning
- When expanding radius, only generates waypoints in the new outer ring (unvisited zones)

**Grid-based zone tracking:**
- Positions are snapped to a 50-pixel grid for consistent zone identification
- Uses string keys like "100,200" for dictionary lookup (O(1) performance)
- Zones are marked visited when:
  - Scan completes at a waypoint
  - Navigation fails to reach a waypoint (prevents getting stuck)

## Conclusion

The implemented approach is **Solution 4 (Hybrid)** which combines:
- Expanding square pattern for systematic coverage
- Navigation validation for geometry awareness
- **Zone tracking system** for preventing redundant searches
- Automatic outer ring detection when expanding

This provides realistic, methodical enemy search behavior while respecting level geometry and integrating with the existing GOAP system. The zone tracking ensures enemies efficiently search new areas without wasting time re-checking already cleared zones.
