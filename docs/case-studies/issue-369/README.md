# Case Study: Issue #369 - Update Enemy Search State with Player Position Prediction

## Issue Summary

**Issue Title:** update состояние поиска врагов (update enemy search state)

**Issue Description (translated from Russian):**
> After one observation cycle, enemies should predict where the player is located and conduct a search around that place (each enemy makes their own prediction).

**Related Issues:**
- Issue #322: Add SEARCHING state for methodical enemy search (CLOSED, merged)
- Issue #330: Enemies never return to IDLE after engaging - search infinitely (CLOSED, merged)
- Issue #334: Enemies in SEARCHING state should look into gaps between walls (OPEN)
- Issue #298: Add ability for AI to predict player actions (OPEN)
- Issue #354: Stuck detection for SEARCHING state (CLOSED, merged)

## Current Implementation Analysis

### 1. Enemy AI Architecture

The game uses a hybrid AI system combining:

1. **Finite State Machine (FSM)** - Primary state management via `AIState` enum:
   - `IDLE` - Default patrol or guard behavior
   - `COMBAT` - Actively engaging the player
   - `SEEKING_COVER` - Moving to cover position
   - `IN_COVER` - Taking cover from player fire
   - `FLANKING` - Attempting to flank the player
   - `SUPPRESSED` - Under fire, staying in cover
   - `RETREATING` - Retreating while possibly shooting
   - `PURSUING` - Moving cover-to-cover toward player
   - `ASSAULT` - Coordinated multi-enemy assault (disabled)
   - `SEARCHING` - Methodically searching area where player was last seen

2. **Goal-Oriented Action Planning (GOAP)** - For tactical decision making:
   - Located in `scripts/ai/goap_planner.gd` and `scripts/ai/goap_action.gd`
   - Actions defined in `scripts/ai/enemy_actions.gd`
   - Uses A* search for optimal action sequences
   - Includes memory-based actions: `InvestigateHighConfidenceAction`, `InvestigateMediumConfidenceAction`, `SearchLowConfidenceAction`

3. **Enemy Memory System** - Tracks player position with confidence:
   - Located in `scripts/ai/enemy_memory.gd`
   - Confidence levels: HIGH (>0.8), MEDIUM (0.5-0.8), LOW (0.3-0.5), LOST (<0.05)
   - Sources: Visual (1.0), Gunshot (0.7), Reload/Empty click (0.6)
   - Intel sharing between enemies with 0.9 confidence degradation factor

### 2. Current SEARCHING State Implementation

The SEARCHING state (Issue #322) implements:

```gdscript
# Search State variables (from enemy.gd lines 425-450)
var _search_center: Vector2 = Vector2.ZERO  # Center position for search pattern
var _search_radius: float = 100.0  # Current search radius (expands over time)
const SEARCH_INITIAL_RADIUS: float = 100.0
const SEARCH_RADIUS_EXPANSION: float = 75.0
const SEARCH_MAX_RADIUS: float = 400.0
var _search_waypoints: Array[Vector2] = []  # Waypoints to visit during search
```

**Current Search Pattern:**
- Uses an **expanding square spiral pattern** starting from a fixed center
- Enemies move to waypoints and scan (rotate) at each point
- Zone tracking prevents revisiting same areas
- Expands radius when all waypoints visited
- Maximum 30 seconds search time (unless engaged enemy, then infinite)

**Limitations of Current Implementation:**
1. Search center is fixed (last known position or enemy's current position)
2. Each enemy searches the same area - no individual prediction
3. No consideration of player movement speed/time passed
4. No prediction based on environment (covers, choke points, flank routes)
5. All enemies share the same search pattern

## Problem Statement

The issue requests that enemies should:
1. **Predict** where the player might be after one observation cycle
2. Each enemy should make their **own prediction** (individual, not shared)
3. Conduct search **around the predicted position** rather than the last known position

## Research: Industry Solutions and Patterns

### 1. Occupancy Maps (Third Eye Crime Approach)

**Source:** [Third Eye Crime: Building a Stealth Game Around Occupancy Maps](https://ojs.aaai.org/index.php/AIIDE/article/view/12663) by Damián Isla

**How it works:**
- Uses probability diffusion to represent likelihood of player being in each area
- After line-of-sight breaks, probability spreads to nearby locations
- Probability updates when:
  - Enemy looks at area and doesn't see player (set to 0, rescale rest)
  - Time elapses (distribution becomes more diffuse)
  - Player is spotted (accumulate whole probability at that spot)
- Enemies move to highest probability point

**Applicability:** This is the most sophisticated solution but requires significant implementation effort. Could be simplified for this project.

### 2. Probabilistic Hypothesis System (Issue #298 proposal)

The repo already has a proposed system in Issue #298:
```gdscript
var hypotheses = {
    "flank_left": {"pos": Vector2, "probability": 0.3},
    "flank_right": {"pos": Vector2, "probability": 0.3},
    "cover": {"pos": Vector2, "probability": 0.4}
}
```

This aligns well with the current request.

### 3. Last Known Position + Prediction Radius

**Traditional approach:**
- Store last known position
- Calculate maximum distance player could have traveled: `max_distance = PLAYER_SPEED * time_passed`
- Generate prediction points within this radius based on:
  - Nearby cover positions
  - Escape routes
  - Flank positions

### 4. FEAR-Style GOAP Search Behavior

**Source:** [Building the AI of F.E.A.R. with Goal Oriented Action Planning](https://www.gamedeveloper.com/design/building-the-ai-of-f-e-a-r-with-goal-oriented-action-planning)

F.E.A.R. used GOAP for dynamic planning where:
- Enemies could predict player behavior based on context
- Each enemy independently plans their search route
- Coordination happens through shared world state, not shared plans

### 5. Adaptive Search with Player Behavior Analysis (Metal Gear Solid V)

**Source:** [The Predictable Problem: Why Stealth Game AI Needs an Overhaul](https://www.wayline.io/blog/predictable-problem-stealth-game-ai-overhaul)

- Track player's previous behaviors
- If player frequently flanks, increase probability of checking flanks
- Morale systems affect search aggression

## Proposed Solutions

### Solution 1: Simple Position Prediction (Recommended - Low Complexity)

Add individual position prediction to each enemy:

```gdscript
## Predicted player position (each enemy makes their own prediction)
var _predicted_player_position: Vector2 = Vector2.ZERO
var _prediction_confidence: float = 0.0

## Prediction factors based on environment analysis
func _generate_position_prediction(last_known_pos: Vector2, time_passed: float) -> Vector2:
    var max_distance = PLAYER_SPEED * time_passed

    # Get nearby cover positions
    var covers = _find_nearby_covers(last_known_pos, max_distance)

    # Get flank positions relative to this enemy
    var my_pos = global_position
    var flank_positions = _get_flank_positions(last_known_pos, my_pos)

    # Weight positions by probability
    var candidates = []

    # Covers get higher weight (player likely to use cover)
    for cover in covers:
        candidates.append({
            "pos": cover,
            "weight": 0.4 + randf() * 0.2  # 0.4-0.6 base weight with variance
        })

    # Add flank positions
    for flank in flank_positions:
        if flank.distance_to(last_known_pos) <= max_distance:
            candidates.append({
                "pos": flank,
                "weight": 0.2 + randf() * 0.2  # 0.2-0.4 weight
            })

    # Add last known position (player might stay)
    candidates.append({
        "pos": last_known_pos,
        "weight": 0.1 + randf() * 0.1
    })

    # Select weighted random position (each enemy gets different result)
    return _weighted_random_select(candidates)
```

**Pros:**
- Simple to implement
- Uses existing navigation/cover detection systems
- Each enemy naturally gets different predictions due to randomness and different relative positions

**Cons:**
- No learning from player behavior
- Less sophisticated than occupancy maps

### Solution 2: Probability Hypothesis System (Medium Complexity)

Implement the system proposed in Issue #298:

```gdscript
class_name PlayerHypothesis
extends RefCounted

var hypotheses: Dictionary = {}

func generate_hypotheses(last_known_pos: Vector2, enemy_pos: Vector2, time_passed: float) -> void:
    hypotheses.clear()
    var max_dist = PLAYER_SPEED * time_passed

    # Find nearby covers
    var covers = _find_covers_in_radius(last_known_pos, max_dist)
    var best_cover = _get_best_cover(covers, enemy_pos)
    if best_cover:
        hypotheses["cover"] = {"pos": best_cover, "probability": 0.4}

    # Calculate flank positions
    var left_flank = _calculate_flank(last_known_pos, enemy_pos, -1)
    var right_flank = _calculate_flank(last_known_pos, enemy_pos, 1)

    if _is_reachable(last_known_pos, left_flank, max_dist):
        hypotheses["flank_left"] = {"pos": left_flank, "probability": 0.25}
    if _is_reachable(last_known_pos, right_flank, max_dist):
        hypotheses["flank_right"] = {"pos": right_flank, "probability": 0.25}

    # Stayed in place
    hypotheses["stayed"] = {"pos": last_known_pos, "probability": 0.1}

    # Normalize probabilities
    _normalize_probabilities()

func get_most_probable() -> Dictionary:
    var best = {"pos": Vector2.ZERO, "probability": 0.0}
    for key in hypotheses:
        if hypotheses[key].probability > best.probability:
            best = hypotheses[key]
    return best

func get_random_weighted() -> Dictionary:
    # Returns random hypothesis weighted by probability
    # Ensures each enemy can get different result
    pass
```

**Pros:**
- Structured approach matching Issue #298 proposal
- Extensible for future improvements
- Good balance of complexity and effectiveness

**Cons:**
- Requires new class/file
- More complex than Solution 1

### Solution 3: Simplified Occupancy Map (High Complexity)

Implement a grid-based probability map:

```gdscript
class_name SimpleOccupancyMap
extends RefCounted

var grid_size: float = 50.0
var grid: Dictionary = {}  # key = "x,y", value = probability

func update_from_last_seen(pos: Vector2, confidence: float) -> void:
    _place_probability(pos, confidence)

func diffuse(delta: float, diffusion_rate: float = 0.1) -> void:
    # Spread probability to adjacent cells
    # Decay probability over time
    pass

func update_from_observation(pos: Vector2, can_see: bool) -> void:
    if can_see:
        # Not there - set to 0
        _set_probability(pos, 0.0)
        _renormalize()
    else:
        # Still possible - no change
        pass

func get_highest_probability_position() -> Vector2:
    pass
```

**Pros:**
- Industry-proven technique (Third Eye Crime)
- Most realistic player prediction
- Natural probability decay and diffusion

**Cons:**
- Significant implementation effort
- Memory overhead for grid
- May be overkill for current game scope

## Recommended Implementation

Based on the current codebase architecture and the specific request in Issue #369, I recommend **Solution 1 (Simple Position Prediction)** with elements from **Solution 2 (Hypothesis System)** as a follow-up.

### Implementation Steps:

1. **Add prediction variables to enemy.gd:**
   ```gdscript
   var _predicted_search_center: Vector2 = Vector2.ZERO
   var _prediction_made: bool = false
   ```

2. **Modify `_transition_to_searching()` to use prediction:**
   - Calculate predicted position before starting search
   - Use predicted position as search center instead of last known position

3. **Add prediction function:**
   - Use time since last visual contact
   - Consider nearby covers
   - Consider flank positions relative to this enemy
   - Add randomness for individual predictions

4. **Update `_generate_search_waypoints()` to start from predicted center:**
   - Already uses `_search_center`, just need to set it to predicted position

### Key Files to Modify:
- `scripts/objects/enemy.gd` - Add prediction logic
- `scripts/ai/enemy_memory.gd` - Add last visual contact timestamp

## References

### Academic and Industry Sources:
- [Third Eye Crime: Building a Stealth Game Around Occupancy Maps](https://ojs.aaai.org/index.php/AIIDE/article/view/12663) - AAAI
- [Building the AI of F.E.A.R. with Goal Oriented Action Planning](https://www.gamedeveloper.com/design/building-the-ai-of-f-e-a-r-with-goal-oriented-action-planning) - Game Developer
- [Dynamic Guard Patrol in Stealth Games](https://ojs.aaai.org/index.php/AIIDE/article/download/7425/7308/10903) - AAAI
- [Probabilistic Target-Tracking and Search Using Occupancy Maps](https://www.gameaipro.com/) - AI Game Programming Wisdom 3, 2005
- [Stealthy path planning against dynamic observers](https://dl.acm.org/doi/10.1145/3561975.3562948) - ACM SIGGRAPH
- [The Predictable Problem: Why Stealth Game AI Needs an Overhaul](https://www.wayline.io/blog/predictable-problem-stealth-game-ai-overhaul) - Wayline

### Godot Resources:
- [Enemy AI in Unity](https://gamedevbeginner.com/enemy-ai-in-unity/) - Last known position patterns
- [Godot State Machine Complete Tutorial](https://generalistprogrammer.com/tutorials/godot-state-machine-complete-tutorial-game-ai)
- [Implementing a simple AI for games in Godot](https://robbert.rocks/implementing-a-simple-ai-for-games-in-godot)
- [Making enemies that don't feel completely stupid in Godot](https://toxigon.com/godot-enemy-ai)

### Existing Libraries/Assets:
- [GPGOAP](https://github.com/stolk/GPGOAP) - General Purpose Goal Oriented Action Planning
- [cppGOAP](https://github.com/cpowell/cppGOAP) - C++ GOAP implementation
- [go-goap](https://github.com/jamiecollinson/go-goap) - Go GOAP implementation

## Appendix: Current Codebase Reference

### Key Files:
- `scripts/objects/enemy.gd` - Main enemy AI (large file, ~4600 lines)
- `scripts/ai/enemy_memory.gd` - Memory system with confidence tracking
- `scripts/ai/enemy_actions.gd` - GOAP actions including search-related
- `scripts/ai/goap_planner.gd` - GOAP planning with A* search
- `scripts/ai/states/enemy_state.gd` - Base state class
- `scripts/ai/states/pursuing_state.gd` - Pursuing state implementation
- `scripts/ai/states/idle_state.gd` - Idle state implementation
- `scripts/components/vision_component.gd` - Vision detection system

### Relevant Constants (enemy.gd):
```gdscript
# Search behavior constants
const SEARCH_INITIAL_RADIUS: float = 100.0
const SEARCH_RADIUS_EXPANSION: float = 100.0  # Issue #369: increased from 75.0
const SEARCH_MAX_RADIUS: float = 400.0
const SEARCH_SCAN_DURATION: float = 1.0
const SEARCH_MAX_DURATION: float = 30.0
const SEARCH_WAYPOINT_SPACING: float = 75.0
const SEARCH_ZONE_SNAP_SIZE: float = 50.0

# Issue #369: Prediction constants
const PLAYER_SPEED_ESTIMATE: float = 300.0
const PREDICTION_COVER_WEIGHT: float = 0.5
const PREDICTION_FLANK_WEIGHT: float = 0.3
const PREDICTION_RANDOM_WEIGHT: float = 0.2
const PREDICTION_MIN_PROBABILITY: float = 0.3
const PREDICTION_CHECK_DISTANCE: float = 500.0
```

### Related Signals:
```gdscript
signal state_changed(new_state: AIState)
```

## Game Log Analysis

### Log File: `game_log_20260125_083304.txt`

A detailed game log was captured during testing on 2026-01-25 08:33:04. The log contains ~7774 lines of enemy AI behavior data.

#### Key Observations from Log Analysis:

1. **Search Expansion Timing Analysis:**
   - Search starts at radius=100, expands to 175, 250, 325, 400
   - Original expansion increment: 75 pixels
   - Time between expansions: approximately 7-8 seconds
   - This was identified as too slow by the user

2. **Multiple Enemies Search Same Area:**
   ```
   [08:33:22] Enemy1 SEARCHING started: center=(607.6915, 643.8395)
   [08:33:22] Enemy2 SEARCHING started: center=(666.3936, 699.4895)
   [08:33:22] Enemy3 SEARCHING started: center=(666.3936, 699.4895) <- Same as Enemy2!
   [08:33:22] Enemy4 SEARCHING started: center=(522.1313, 723.0651)
   ```
   Enemy2 and Enemy3 started searching at the identical center position.

3. **No Prediction Logs Found:**
   - The log contained no prediction-related entries
   - All search centers were based on raw last known positions

4. **Timeline of Search Expansion Events:**
   | Time | Enemy | Radius | Notes |
   |------|-------|--------|-------|
   | 08:33:22 | All | 100 | Initial search start |
   | 08:33:30 | 2,3 | 175 | First expansion (~8s) |
   | 08:33:31 | 1 | 175 | First expansion (~9s) |
   | 08:33:32 | 4 | 175 | First expansion (~10s) |
   | 08:33:38 | 1,2,3 | 250 | Second expansion |
   | 08:33:45 | 4 | 250 | Second expansion |
   | 08:33:49 | 2,3 | 325 | Third expansion |
   | 08:33:54 | 1 | 325 | Third expansion |
   | 08:33:59 | 4 | 325 | Third expansion |
   | 08:34:03 | 2,3 | 400 | Max radius reached |

#### Root Cause Analysis:

1. **Slow Expansion Speed:** The `SEARCH_RADIUS_EXPANSION` constant was set to 75.0 pixels, causing slow area coverage.

2. **No Individual Prediction:** The `_transition_to_searching()` function used the raw `center_position` parameter directly without any prediction logic.

3. **Shared Search Centers:** When multiple enemies lost sight of the player at the same position, they all searched the same area.

---

## Implementation (PR #372)

### Changes Made:

#### 1. Increased Search Zone Expansion Speed

**File:** `scripts/objects/enemy.gd`

```gdscript
# Before:
const SEARCH_RADIUS_EXPANSION: float = 75.0

# After:
const SEARCH_RADIUS_EXPANSION: float = 100.0  # Issue #369: increased from 75
```

This change increases the expansion step from 75 to 100 pixels, resulting in:
- Faster area coverage (approximately 33% faster)
- Fewer expansion cycles needed to reach max radius

#### 2. Added Player Position Prediction System

**New Constants Added:**
```gdscript
## Issue #369: Player position prediction for search state.
const PLAYER_SPEED_ESTIMATE: float = 300.0  ## Estimated player max speed (pixels/sec).
const PREDICTION_COVER_WEIGHT: float = 0.5  ## Weight for cover positions in prediction.
const PREDICTION_FLANK_WEIGHT: float = 0.3  ## Weight for flank positions in prediction.
const PREDICTION_RANDOM_WEIGHT: float = 0.2  ## Weight for random offset in prediction.
const PREDICTION_MIN_PROBABILITY: float = 0.3  ## Minimum probability to use prediction (0.0-1.0).
const PREDICTION_CHECK_DISTANCE: float = 500.0  ## Max distance to check for covers/flanks.
```

**New Functions Added:**

1. `_predict_player_position(last_known_pos: Vector2) -> Vector2`
   - Calculates time elapsed since last seeing player
   - Determines maximum distance player could have traveled
   - Collects weighted prediction candidates (covers, flanks, random)
   - Uses weighted random selection for individual predictions

2. `_find_prediction_covers(center: Vector2, max_distance: float) -> Array[Vector2]`
   - Uses existing cover raycast system
   - Finds navigable cover positions within reachable distance

3. `_get_prediction_flanks(center: Vector2, max_distance: float) -> Array[Vector2]`
   - Calculates left/right flank positions relative to enemy
   - Returns only navigable positions

#### 3. Modified `_transition_to_searching()` Function

The function now calls `_predict_player_position()` before setting the search center:

```gdscript
func _transition_to_searching(center_position: Vector2) -> void:
    # Issue #369: Try to predict player position instead of using raw last known position
    var predicted_center := _predict_player_position(center_position)
    _search_center = predicted_center
    # ... rest of initialization
```

### Prediction Algorithm Details:

1. **30% chance to skip prediction** (`PREDICTION_MIN_PROBABILITY = 0.3`) - ensures variety
2. **If player was seen < 0.5 seconds ago** - use last known position (still accurate)
3. **Calculate max travel distance:** `PLAYER_SPEED_ESTIMATE * time_elapsed`
4. **Weight candidates:**
   - Cover positions: 50% weight (players tend to seek cover)
   - Flank positions: 30% weight (relative to enemy, not shared)
   - Random offset: 20% weight (unpredictable movement)
   - Last known position: 10% weight (fallback)
5. **Weighted random selection** - each enemy rolls differently

### Expected Behavior After Changes:

1. **Faster expansion:** Search radius expands 100px per cycle instead of 75px
2. **Individual predictions:** Each enemy calculates their own predicted search center based on:
   - Their relative position to the last known player location
   - Nearby cover positions
   - Random variance
3. **Logged predictions:** New log entries show when prediction is used:
   ```
   Prediction selected: cover at (x, y) (time_elapsed=2.5s, max_dist=750.0)
   SEARCHING started: center=(x, y), radius=100, waypoints=5 (predicted from (orig_x, orig_y))
   ```

---

## Update: Coordinated Search System (PR #372 v2)

Based on user feedback, a second major iteration was implemented to address the issue of enemies walking in circles and slowly reaching new zones.

### User Feedback (2026-01-25):
> "сейчас враги очень много ходят по кругу и медленно добираются до новых зон. сделай чтоб маршрут поиска на итерацию строился в начале итерации. маршрут должен строиться для всех врагов, участвующих в поиске так, чтобы за минимальные передвижения осмотреть всю зону, при этом не ходить 2 раза по одному месту и чтоб один враг не проверял то, что уже проверял другой."

Translation: "Currently enemies walk in circles a lot and slowly reach new zones. Make the search route for the iteration be built at the beginning of the iteration. The route should be built for all enemies participating in the search so that they cover the entire zone with minimal movement, without visiting the same place twice and without one enemy checking what another has already checked."

### Solution: SearchCoordinator Autoload

A new `SearchCoordinator` autoload was created to manage coordinated search operations across all enemies.

#### Key Features:

1. **Voronoi-like Area Partitioning:**
   - Divides the search area into sectors based on enemy count
   - Each enemy is assigned a unique angular sector (360° / N enemies)
   - Prevents overlap between enemy search areas
   - Reference: [Voronoi diagram - Wikipedia](https://en.wikipedia.org/wiki/Voronoi_diagram)

2. **Pre-planned Route Generation:**
   - Routes are generated at the start of each search iteration
   - All waypoints are assigned upfront, not dynamically
   - Enemies follow assigned routes efficiently

3. **Global Zone Tracking:**
   - Shared dictionary of visited zones (`_globally_visited_zones`)
   - Any zone visited by one enemy is marked for all
   - Prevents redundant searches

4. **Coordinated Search Functions:**
   ```gdscript
   # SearchCoordinator API
   func start_coordinated_search(center: Vector2, requesting_enemy: Node) -> int
   func get_next_waypoint(enemy: Node) -> Vector2
   func advance_waypoint(enemy: Node) -> bool
   func is_route_complete(enemy: Node) -> bool
   func expand_search() -> bool
   func mark_zone_visited(pos: Vector2) -> void
   ```

5. **Sector-based Waypoint Distribution:**
   ```gdscript
   # Each enemy gets waypoints within their assigned sector
   var sector_angle := TAU / float(enemy_count)
   var sector_start := i * sector_angle
   var sector_end := (i + 1) * sector_angle
   # Generate waypoints in spiral pattern within sector
   ```

### Files Added:

- `scripts/autoload/search_coordinator.gd` - New coordinated search manager
- `project.godot` - Added SearchCoordinator to autoloads

### Files Modified:

- `scripts/objects/enemy.gd` - Updated to use SearchCoordinator:
  - Removed individual waypoint generation
  - Added `is_searching()` and `should_join_search()` helper methods
  - Modified `_transition_to_searching()` to register with coordinator
  - Modified `_process_searching_state()` to use coordinated waypoints
  - Added `_remove_from_coordinated_search()` cleanup method
  - Added `_process_searching_state_fallback()` for when coordinator unavailable
  - Reduced file size from 5141 to 4990 lines (below 5000 limit)

### Algorithm: Voronoi-like Sector Partitioning

```
1. When first enemy starts search:
   - Create new search iteration with center position
   - Find all nearby enemies that should join

2. Divide search area into sectors:
   - N enemies → 360°/N sectors per enemy
   - Enemy 0: 0° to 72° (if 5 enemies)
   - Enemy 1: 72° to 144°
   - etc.

3. Generate waypoints per sector:
   - Start from sector center
   - Spiral outward within sector bounds
   - Skip globally visited zones
   - Sort by distance for efficient traversal

4. During search:
   - Each enemy follows their assigned waypoints
   - Zones marked visited globally when completed
   - On route completion, expand radius or start new search
```

### Research Sources:

- [Voronoi diagram - Wikipedia](https://en.wikipedia.org/wiki/Voronoi_diagram) - Area partitioning
- [Dynamic Guard Patrol in Stealth Games](https://ojs.aaai.org/index.php/AIIDE/article/download/7425/7308/10903) - AAAI AIIDE
- [Cooperative Target Capture using Voronoi Region Shaping](https://arxiv.org/html/2406.19181) - Multi-agent coordination
- [Weighted Buffered Voronoi Cells for Distributed Semi-Cooperative Behavior](https://sites.bu.edu/pierson/files/2021/05/pierson2020icra.pdf) - ICRA 2020

---

## Conclusion

Issue #369 has been addressed through two major iterations:

### Iteration 1: Individual Prediction
- Increased search expansion speed (75 → 100 pixels per expansion)
- Individual prediction per enemy based on covers, flanks, and random variance
- Logging for debugging prediction selections

### Iteration 2: Coordinated Search (Current)
- New `SearchCoordinator` autoload for multi-enemy coordination
- Voronoi-like area partitioning prevents search overlap
- Pre-planned routes at iteration start for efficient coverage
- Global zone tracking ensures no area is searched twice
- Reduced enemy.gd line count to comply with CI limits

The coordinated search system ensures that when multiple enemies are searching for the player:
1. Each enemy is assigned a unique sector of the search area
2. Routes are planned upfront for minimal movement
3. No enemy visits areas already checked by others
4. The search is completed faster with better coverage

---

## Session 3: User Bug Report Investigation (2026-01-25)

### User Report

In PR #372, user Jhon-Crow reported:
> "враги полностью сломались! проверь C#"
> (Translation: "enemies completely broke! check C#")

An attached game log `game_log_20260125_094956.txt` was provided.

### Log Analysis

#### Key Finding: Wrong Build Tested

The log revealed the user tested with a build from **main branch**, NOT from PR #372:

1. **BloodyFeetComponent Present:**
   ```
   [09:49:56] [INFO] [BloodyFeet:Enemy1] BloodyFeetComponent ready on Enemy1
   [09:49:56] [INFO] [BloodyFeet:Enemy2] BloodyFeetComponent ready on Enemy2
   ...
   ```
   BloodyFeetComponent does NOT exist in the PR branch. It was added to `main` after our last merge.

2. **Zero Enemies Registered:**
   ```
   [09:49:56] [INFO] [BuildingLevel] Child 'Enemy1': script=true, has_died_signal=false
   [09:49:56] [INFO] [BuildingLevel] Enemy tracking complete: 0 enemies registered
   ```
   The `script=true` but `has_died_signal=false` indicates the GDScript wasn't loaded properly.

3. **Enemies Removed from Scene Tree:**
   ```
   [09:49:58] [INFO] [BloodyFeet:Enemy1] ... in_tree=false
   [09:49:58] [INFO] [BloodyFeet:Enemy2] ... in_tree=false
   ```
   All enemies were removed from the scene tree 2 seconds after initialization.

#### Hypothesis

The `main` branch has:
- The old expanding square search pattern (`enemy.gd`)
- BloodyFeetComponent (new feature)

Our PR branch has:
- The new coordinated search system using `SearchCoordinator`
- Different search-related variables and functions

The user likely tested with `main` which may have an unrelated bug, or a mixed state caused script loading issues.

### Verification Steps

Our PR branch was verified:

1. **Signal declarations exist** (`scripts/objects/enemy.gd:188-197`):
   ```gdscript
   signal hit  ## Enemy hit
   signal died  ## Enemy died
   signal died_with_info(is_ricochet_kill: bool, is_penetration_kill: bool)
   ```

2. **No GDScript parsing errors** - file parses cleanly

3. **SearchCoordinator properly registered** in `project.godot` autoloads

4. **Line count compliant**: 4993 lines (under 5000 CI limit)

### Resolution

Commented on PR requesting user test with the correct branch:

```bash
git fetch origin
git checkout issue-369-523c173e52fb
# Export the project from this branch
```

### Log File Added

The problematic game log was saved for reference:
- `logs/game_log_20260125_094956.txt`

---

## Session 4: BloodyFeetComponent class_name Issue (2026-01-25)

### User Report

User continued to report enemies being broken after supposedly testing the PR branch:
> "всё ещё сломано" (Translation: "still broken")
> "вот последний рабочий коммит, сверься с ним"
> (Reference to commit 858a4174838543395f0388ed33ad55977299fcce as last working)

Attached log: `game_log_20260125_101524.txt`

### Log Analysis

#### Evidence of Main Branch Code

The log still shows BloodyFeetComponent output:
```
[10:15:24] [INFO] [BloodyFeet:?] BloodyFeetComponent initializing...
[10:15:24] [INFO] [BloodyFeet:Enemy1] Footprint scene loaded
[10:15:24] [INFO] [BloodyFeet:Enemy1] Blood detector created and attached to Enemy1
[10:15:24] [INFO] [BloodyFeet:Enemy1] Found EnemyModel for facing direction
[10:15:24] [INFO] [BloodyFeet:Enemy1] BloodyFeetComponent ready on Enemy1
```

**Key insight:** BloodyFeetComponent did NOT exist in our PR branch before this session. It only exists in `main`. The user's exported build contained main branch code with BloodyFeetComponent.

#### Same Symptom Pattern as Issue #363

```
[10:15:24] [INFO] [BuildingLevel] Child 'Enemy1': script=true, has_died_signal=false
[10:15:24] [INFO] [BuildingLevel] Child 'Enemy2': script=true, has_died_signal=false
...
[10:15:24] [INFO] [BuildingLevel] Enemy tracking complete: 0 enemies registered
```

And later:
```
[10:15:26] [INFO] [BloodyFeet:Enemy1] Overlap check: ... in_tree=false
[10:15:26] [INFO] [BloodyFeet:Enemy2] Overlap check: ... in_tree=false
```

This is the EXACT same failure pattern we identified in Issue #363!

### Root Cause Identified

**BloodyFeetComponent uses `class_name BloodyFeetComponent`** (line 7 of the original file):

```gdscript
extends Node
## Component that tracks when a character steps in blood and spawns footprints.
##
## Attach this component to any CharacterBody2D (Player or Enemy) to enable
## bloody footprint tracking. The component monitors for blood puddle contact
## and spawns footprint decals at regular intervals while moving.
class_name BloodyFeetComponent
```

This is the SAME pattern that caused Issue #363:

1. **Export build script loading order differs from editor**
2. **When a script references a `class_name`, that class must be loaded first**
3. **In export builds, the loading order can cause the class to not be found**
4. **This causes the referencing script to FAIL TO PARSE**
5. **A script that fails to parse has NO SIGNALS at runtime**
6. **`has_died_signal=false` because the enemy script is broken**
7. **0 enemies registered, game appears to work but enemies don't function**

### Solution Applied

**Removed `class_name BloodyFeetComponent`** from `scripts/components/bloody_feet_component.gd`:

```gdscript
extends Node
## Component that tracks when a character steps in blood and spawns footprints.
##
## Attach this component to any CharacterBody2D (Player or Enemy) to enable
## bloody footprint tracking. The component monitors for blood puddle contact
## and spawns footprint decals at regular intervals while moving.
##
## Note: class_name intentionally omitted to prevent export build script loading issues.
## See Issue #363 root cause analysis for details on why typed component references
## can cause scripts to fail parsing in export builds due to load order differences.
```

### Cross-Reference to Issue #363 Root Cause Analysis

The complete technical analysis of this problem is documented in:
- `docs/case-studies/issue-363/root-cause-analysis-20260125.md`

Key points:
- Using `class_name` in component scripts is risky for export builds
- GDScript class loading order is undefined in exports
- Godot doesn't crash on script parse errors - it runs with broken scripts silently
- The fix is to either remove `class_name` or use duck typing (`var x = null` instead of `var x: MyClass = null`)

### Files Modified

- `scripts/components/bloody_feet_component.gd` - Removed `class_name` declaration

### Log File Added

- `logs/game_log_20260125_101524.txt`

### Recommendations

1. **Never use `class_name` in component scripts** that are attached to scene files
2. **Test export builds regularly** to catch these issues early
3. **Add CI step for export build testing** to verify basic functionality
4. **Use duck typing** for cross-script references when possible

---
