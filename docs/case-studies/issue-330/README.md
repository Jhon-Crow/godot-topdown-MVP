# Case Study: Issue #330 - Improved Enemy SEARCHING State

## Issue Summary

**Title (Russian):** update SEARCHING врагов
**Title (English):** Update Enemy SEARCHING State

**Original Issue Text (translated from Russian):**
> A search feature was added in [PR #323](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/323), but currently enemies still walk in a group and make large circles (not optimally inspecting the zone).
>
> 1. Add collective behavior - in the search zone, each enemy inspects their own point so that the entire zone is inspected as quickly as possible. Look up how real special forces clear rooms.
> 2. Enemies should NOT return to IDLE state after contact with the player - they should search for the player until they find them.

## Current Implementation Analysis

### Existing SEARCHING State (from PR #323)

The SEARCHING state was implemented in PR #323 with the following features:

#### Search Pattern
- **Expanding square spiral pattern** - generates waypoints in a spiral from last known player position
- Initial radius: 100px
- Expansion increment: 75px per expansion cycle
- Maximum radius: 400px
- Waypoint spacing: 75px

#### Zone Tracking System
```gdscript
var _search_visited_zones: Dictionary = {}
const SEARCH_ZONE_SNAP_SIZE: float = 50.0

func _get_zone_key(pos: Vector2) -> String
func _is_zone_visited(pos: Vector2) -> bool
func _mark_zone_visited(pos: Vector2) -> void
```

#### Current Behavior
1. When triggered (after "Last Chance" effect), enemies transition to SEARCHING
2. Each enemy independently generates waypoints around the last known player position
3. Enemies move to waypoints, pause to scan (rotate), then proceed to next waypoint
4. Search radius expands when all waypoints are visited
5. **TIMEOUT after 30 seconds** - returns to IDLE

### Identified Problems (from Log Analysis)

From the attached log files, I identified two major issues:

#### Problem 1: No Collective Coordination
All enemies search the **same center point** with **identical patterns**:
```
[00:34:07] [Enemy2] SEARCHING started: center=(1464.378, 406.5967), radius=100, waypoints=5
[00:34:07] [Enemy4] SEARCHING started: center=(1464.378, 406.5967), radius=100, waypoints=5
[00:34:07] [Enemy5] SEARCHING started: center=(1464.378, 379.0967), radius=100, waypoints=5
[00:34:07] [Enemy9] SEARCHING started: center=(1464.378, 379.0967), radius=100, waypoints=5
```

**Result:** Enemies walk together in a "crowd" because they're all following the same spiral pattern to the same waypoints.

#### Problem 2: Premature IDLE Transition
Enemies return to IDLE after 30 seconds regardless of whether player was found:
```
[00:34:37] [Enemy2] SEARCHING timeout after 30.0s, returning to IDLE
[00:34:37] [Enemy4] SEARCHING timeout after 30.0s, returning to IDLE
[00:34:37] [Enemy5] SEARCHING timeout after 30.0s, returning to IDLE
[00:34:37] [Enemy9] SEARCHING timeout after 30.0s, returning to IDLE
```

**User Requirement:** After contact with the player, enemies should search until they find the player again, not give up after 30 seconds.

## Research Findings

### Real-World SWAT/CQB Room Clearing Tactics

Based on research into Close Quarters Battle (CQB) and SWAT tactics:

#### Key Principles
1. **Sector responsibility** - Each team member covers a specific sector to avoid duplicate coverage and blind spots
2. **Slicing the pie** - Incrementally clearing angles around corners/doorways
3. **Sequential vs. Simultaneous clearing** - Coordinated entry from multiple points
4. **Communication** - Verbal/hand signals to maintain coordination ("Clear!", "Contact left!")

#### Team Formation (Battle Drill 6A)
- 4-man teams with defined roles
- Each member has pre-assigned sectors (e.g., corners of the room)
- Crisscrossing sectors of fire covering all threats
- Simultaneous entry to "flood" the space

**Sources:**
- [Trango Systems: Tactical Principles in CQB](https://www.trango-sys.com/tactical-principles-and-strategies-in-cqb/)
- [HRT Tactical: Room Clearing Tactics](https://hrttacticalgear.com/overview-of-tactical-room-clearing-tactics/)
- [TI Training: Building Clearing Guide](https://titraining.com/blog/room-clearing-tactics-guide/)

### Game AI: F.E.A.R. Squad Coordination

F.E.A.R. (2005) is considered a benchmark for squad AI in games:

#### Squad Manager Pattern
- Central `SquadManager` coordinates individual NPC goals
- NPCs receive squad-level goals that complement (not duplicate) each other
- NPCs can override squad directives if personally threatened

#### Search Behavior
> "Search splits the squad into pairs who cover each other as they systematically search rooms in an area."

#### Illusion of Coordination
- NPCs don't actually communicate with each other
- Squad Manager assigns complementary goals that appear coordinated
- Audio cues ("flank!", "cover me!") are triggered AFTER decisions, creating illusion of verbal commands

#### Emergent Pincer Movement
> "It appears as though they are executing some kind of coordinated pincer attack, when really they are just moving to nearer cover that happens to be on either side of the player."

**Sources:**
- [GDC Vault: Three States and a Plan - The AI of F.E.A.R.](https://gdcvault.com/play/1013282/Three-States-and-a-Plan)
- [Original Paper PDF](https://www.gamedevs.org/uploads/three-states-plan-ai-of-fear.pdf)
- [Game Developer: Building F.E.A.R. AI](https://www.gamedeveloper.com/design/building-the-ai-of-f-e-a-r-with-goal-oriented-action-planning)

### Godot AI Libraries and Patterns

#### Available Libraries

1. **GDQuest Steering AI Framework**
   - Complete framework for complex AI motion
   - Includes group behaviors: following leader, avoiding neighbors
   - Works in 2D and 3D
   - [GitHub Repository](https://github.com/GDQuest/godot-steering-ai-framework)

2. **LimboAI**
   - C++ module with full GDScript support
   - Behavior Trees + State Machines
   - Built-in editor and debugger
   - [Godot Forum Thread](https://forum.godotengine.org/t/limboai-behavior-trees-and-state-machines-plugin-c-module/36550)

3. **Built-in Navigation**
   - NavigationAgent2D/3D for pathfinding
   - NavigationServer2D for path computation and validation
   - Already used in this codebase

## Proposed Solutions

### Solution 1: Global Search Coordinator (Recommended)

**Concept:** Create a central `SearchCoordinator` singleton that manages all enemies in SEARCHING state and assigns different waypoints to each.

#### Architecture
```gdscript
# Autoload: SearchCoordinator.gd
class_name SearchCoordinator
extends Node

var _active_searchers: Dictionary = {}  # enemy_id -> assigned_waypoints
var _search_zones: Dictionary = {}      # zone_key -> assigned_enemy_id
var _global_visited_zones: Dictionary = {}  # All visited zones (shared)

func register_searcher(enemy: Node, center: Vector2) -> void
func unregister_searcher(enemy: Node) -> void
func get_next_waypoint(enemy: Node) -> Vector2
func mark_zone_searched(zone: Vector2) -> void
func is_zone_assigned(zone: Vector2) -> bool
```

#### Waypoint Assignment Algorithm
1. Generate full set of search waypoints around center
2. Partition waypoints among active searchers (round-robin or sector-based)
3. Each enemy only visits their assigned partition
4. When enemy joins late, redistribute remaining unsearched waypoints

#### Sector-Based Assignment
Divide search area into sectors (like pizza slices):
```
      Sector 0 (N)
         |
  Sec 3  +  Sec 1 (E)
   (W)   |
      Sector 2 (S)
```

Each enemy assigned a sector. New enemies get empty sectors or split existing ones.

**Pros:**
- Efficient: no duplicate searches
- Scalable: works with any number of enemies
- Emergent pincer-like behavior (enemies approach from different directions)

**Cons:**
- Requires new global coordinator
- More complex waypoint distribution logic

### Solution 2: Local Avoidance with Shared Zone Tracking

**Concept:** Share the `_search_visited_zones` dictionary globally so all enemies know which zones have been checked.

#### Changes Required
```gdscript
# In enemy.gd
# Replace instance variable:
# var _search_visited_zones: Dictionary = {}

# With reference to global tracker:
var _global_search_zones: Node = null

func _ready():
    _global_search_zones = get_node_or_null("/root/GlobalSearchTracker")
```

Each enemy still generates its own pattern but:
1. Skips waypoints already marked visited by ANY enemy
2. If all waypoints visited, searches from a new random offset

**Pros:**
- Minimal code changes
- Decoupled enemies (no direct coordination needed)

**Cons:**
- Enemies may cluster if they start searching simultaneously
- Less optimal coverage pattern

### Solution 3: F.E.A.R.-Style Squad Manager Integration

**Concept:** Extend existing `enemy_actions.gd` with a SquadSearchManager that assigns complementary search goals.

#### Architecture
```gdscript
# SquadSearchManager.gd
func assign_search_goals(enemies: Array, last_known_position: Vector2) -> void:
    var num_enemies = enemies.size()

    # Split into pairs (F.E.A.R. style)
    for i in range(0, num_enemies, 2):
        var pair = enemies.slice(i, min(i+2, num_enemies))
        var sector_angle = (2 * PI / num_enemies) * i

        for enemy in pair:
            var search_center = last_known_position + Vector2.from_angle(sector_angle) * 100
            enemy.set_search_goal(search_center)
```

**Pros:**
- Follows proven industry pattern (F.E.A.R.)
- Natural pair coordination
- Integrates with existing GOAP system

**Cons:**
- More architectural changes
- Requires refactoring current search trigger mechanism

### Solution 4: Persistent Search Until Found

**Concept:** Remove the 30-second timeout when enemies have had contact with player.

#### Changes Required
```gdscript
# In enemy.gd

# New flag to track if enemy has made contact
var _has_made_player_contact: bool = false

# Modify _process_searching_state():
func _process_searching_state(delta: float) -> void:
    _search_state_timer += delta

    # Only timeout if NO contact was made
    if _search_state_timer >= SEARCH_MAX_DURATION and not _has_made_player_contact:
        _log_to_file("SEARCHING timeout (no prior contact)")
        _transition_to_idle()
        return

    # If contact was made, search indefinitely until:
    # - Player found (transition to COMBAT)
    # - Player escaped (new Last Chance triggers reset)
    # - Max radius reached AND all zones searched

    # ... rest of function
```

#### Search Termination Conditions (after contact)
1. Player spotted -> COMBAT
2. Max radius reached AND no unvisited zones -> expand patrol area
3. Player uses teleport/Last Chance -> memory reset triggers new search

**Pros:**
- Directly addresses user requirement #2
- Simple flag-based implementation

**Cons:**
- Enemies may search forever if player hides effectively
- Needs balance: maybe cap at 5 minutes or larger area

## Recommended Implementation Plan

### Phase 1: Global Search Coordinator (Requirement #1)

1. Create `SearchCoordinator` autoload singleton
2. Register enemies when entering SEARCHING state
3. Implement sector-based waypoint assignment
4. Share visited zone tracking globally

### Phase 2: Persistent Search (Requirement #2)

1. Add `_has_made_player_contact` flag
2. Set flag when entering COMBAT from IDLE
3. Modify timeout logic:
   - Without contact: 30s timeout -> IDLE
   - With contact: No timeout, only max area limit
4. Add max area safety limit (e.g., 800px radius)

### Phase 3: Enhanced Coordination

1. Add audio cues for search coordination (F.E.A.R. style)
2. Implement pair-based search patterns
3. Add "cover buddy" behavior during search

## Complexity Estimate

| Phase | Effort | Files Modified |
|-------|--------|----------------|
| Phase 1 | Medium | `enemy.gd`, new `search_coordinator.gd` |
| Phase 2 | Low | `enemy.gd` |
| Phase 3 | Medium | `enemy.gd`, `audio_manager.gd` |

**Total:** Medium complexity. Phase 1 requires careful design to integrate with existing navigation.

## Test Plan

1. **Unit tests:**
   - Sector assignment algorithm
   - Global zone tracking
   - Timeout logic with/without contact flag

2. **Integration tests:**
   - Multiple enemies enter SEARCHING simultaneously
   - Verify unique waypoints per enemy
   - Verify persistent search after combat

3. **Manual testing:**
   - Visual verification: enemies spread out (not crowding)
   - Hide and observe: enemies continue searching past 30s
   - Trigger Last Chance: search resets correctly

## References

### SWAT/CQB Tactics
- [Trango: Tactical Principles in CQB](https://www.trango-sys.com/tactical-principles-and-strategies-in-cqb/)
- [HRT Tactical Gear: Room Clearing Overview](https://hrttacticalgear.com/overview-of-tactical-room-clearing-tactics/)
- [Police1: Dynamic vs Deliberate Entry](https://www.police1.com/swat/articles/dynamic-entry-versus-deliberate-entry-s86BB28VVWLfwJXW/)

### Game AI
- [GDC: Three States and a Plan (F.E.A.R.)](https://gdcvault.com/play/1013282/Three-States-and-a-Plan)
- [F.E.A.R. AI Paper PDF](https://www.gamedevs.org/uploads/three-states-plan-ai-of-fear.pdf)
- [Game AI Pro: Combat Dialogue in F.E.A.R.](https://www.gameaipro.com/GameAIPro2/GameAIPro2_Chapter02_Combat_Dialogue_in_FEAR_The_Illusion_of_Communication.pdf)

### Godot Resources
- [GDQuest: Steering AI Framework](https://github.com/GDQuest/godot-steering-ai-framework)
- [Godot Navigation Agents](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationagents.html)
- [LimboAI Plugin](https://forum.godotengine.org/t/limboai-behavior-trees-and-state-machines-plugin-c-module/36550)

### Prior Work in This Codebase
- [Issue #322 Case Study](../issue-322/README.md) - Original SEARCHING state implementation
- [PR #323](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/323) - Search state with zone tracking

---

## Implementation Details (PR #331)

### Solution Implemented

Based on user feedback and log analysis, we implemented **Solution 4: Persistent Search** combined with improved zone coverage.

#### Key Changes to `enemy.gd`:

##### 1. Added `_has_left_idle` Flag (Line 449)

```gdscript
## Flag tracking if enemy has ever left IDLE state (Issue #330).
## Once an enemy leaves IDLE (due to combat contact, sound detection, etc.),
## it should NEVER return to IDLE - it must search infinitely until finding the player.
var _has_left_idle: bool = false
```

##### 2. Updated All State Transition Functions

Every transition function that moves AWAY from IDLE now sets `_has_left_idle = true`:

- `_transition_to_combat()` - Line 2588
- `_transition_to_seeking_cover()` - Line 2608
- `_transition_to_in_cover()` - Line 2615
- `_transition_to_flanking()` - Line 2643
- `_transition_to_suppressed()` - Line 2706
- `_transition_to_pursuing()` - Line 2713
- `_transition_to_assault()` - Line 2727
- `_transition_to_searching()` - Line 2741
- `_transition_to_retreating()` - Line 2756

##### 3. Modified `_process_searching_state()` (Lines 2407-2450)

Key changes:

1. **Timeout only applies to patrol enemies** (never engaged):
   ```gdscript
   if _search_state_timer >= SEARCH_MAX_DURATION and not _has_left_idle:
       _log_to_file("SEARCHING timeout after %.1fs, returning to IDLE (patrol enemy)" % _search_state_timer)
       _transition_to_idle()
       return
   ```

2. **Engaged enemies search forever**, but move center when max radius reached:
   ```gdscript
   if _has_left_idle:
       # Move search center to current position (so enemy explores new area)
       var old_center := _search_center
       _search_center = global_position
       _search_radius = SEARCH_INITIAL_RADIUS
       _search_state_timer = 0.0
       # Keep visited zones to avoid re-visiting same spots
       _generate_search_waypoints()
       _log_to_file("SEARCHING: Max radius reached, moved center from %s to %s" % [old_center, _search_center])
       return
   ```

##### 4. Modified Other State Transitions to Search Instead of IDLE

When engaged enemies lose their target or have other triggers that would normally return to IDLE, they now start searching instead:

- **FLANKING state** - if player lost: start searching (Line 1937-1943)
- **PURSUING state** - if no valid target: start searching (Line 2244-2251)
- **Memory confidence low** - start searching at suspected position (Line 2321-2330)
- **State reset (no target)** - start searching from current position (Line 3889-3895)

### Log Output Changes

Before:
```
[01:07:59] [Enemy1] SEARCHING timeout after 30.0s, returning to IDLE
[01:07:59] [Enemy1] State: SEARCHING -> IDLE
```

After (engaged enemy):
```
[01:07:59] [Enemy1] SEARCHING: Max radius reached, moved center from (645, 715) to (720, 680) (engaged enemy, wps=8)
```

After (patrol enemy):
```
[01:07:59] [Enemy1] SEARCHING timeout after 30.0s, returning to IDLE (patrol enemy)
```

### Zone Coverage Improvement

Instead of clearing `_search_visited_zones` when resetting (which would cause re-visiting), we:
1. Keep the visited zones dictionary intact
2. Move the search center to current position
3. Generate new waypoints from the new center
4. This naturally avoids previously visited areas

The enemy effectively "walks" through the map, exploring new areas as they go, while avoiding spots they've already checked.
