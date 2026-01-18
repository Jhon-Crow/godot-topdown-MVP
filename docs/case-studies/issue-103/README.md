# Case Study: Issue #103 - Improve Enemy Movement System

## Issue Summary

**Original Request (Russian):**
> После исчезновения игрока из поля зрения врага он должен считать небольшую невидимую зону, в которой скрылся игрок - зоной потенциального игрока. враг должен строить полный маршрут до этой зоны и затем осматривать её.
> за всеми укрытиями и в углах комнат должны быть невидимые точки, которые враг должен проверить прежде, чем двигаться дальше, если эти точки в зоне потенциального игрока. когда все точки у зоне потенциального игрока проверены - зона считается зоной без игрока.
> при столкновении с игроком зоны обнуляются.

**Translation:**
> After the player disappears from the enemy's field of view, the enemy should consider a small invisible zone where the player hid as a "potential player zone". The enemy should build a full route to this zone and then inspect it.
> Behind all covers and in room corners there should be invisible inspection points that the enemy must check before moving further, if these points are in the potential player zone. When all points in the potential player zone are checked - the zone is considered a "no player zone".
> Upon encountering the player, the zones reset.

## Timeline of Events

### Current Codebase State (Pre-Issue)

The existing AI system in `scripts/objects/enemy.gd` has several states:
- `IDLE` - Patrol or guard behavior
- `COMBAT` - Actively engaging player
- `SEEKING_COVER` - Moving to cover position
- `IN_COVER` - Taking cover from player fire
- `FLANKING` - Attempting to flank the player
- `SUPPRESSED` - Under fire, staying in cover
- `RETREATING` - Retreating to cover while possibly shooting
- `PURSUING` - Moving cover-to-cover toward player
- `ASSAULT` - Coordinated multi-enemy rush

### Problem Identification

When the player escapes from the enemy's line of sight:

1. **Current Behavior (Line 803-809 in enemy.gd):**
   ```gdscript
   # If can't see player, pursue them (move cover-to-cover toward player)
   if not _can_see_player:
       _log_debug("Lost sight of player in COMBAT, transitioning to PURSUING")
       _transition_to_pursuing()
   ```

2. **PURSUING State Behavior:**
   - Moves cover-to-cover toward player's **current position**
   - Does NOT remember where the player was last seen
   - Does NOT search the area methodically
   - Simply tries to find a path to the player

3. **Missing Features:**
   - No "last known position" memory
   - No "potential player zone" concept
   - No inspection point system
   - No methodical search pattern

## Root Cause Analysis

### Architecture Gap

The GOAP system (`scripts/ai/goap_planner.gd` and `scripts/ai/goap_action.gd`) provides the planning framework, but the `enemy_actions.gd` lacks:

1. **SearchZoneAction** - Action to investigate a last-known-position area
2. **InspectPointAction** - Action to check specific hiding spots
3. **World State Variables** for tracking:
   - `last_known_player_position`
   - `search_zone_active`
   - `inspection_points_remaining`

### Behavioral Gap

The state machine transitions directly from `COMBAT` → `PURSUING` when line of sight is lost, without:
1. Recording where the player was last seen
2. Defining a search zone around that position
3. Identifying nearby hiding spots to check

## Proposed Solution

### 1. Add New AI State: SEARCHING

A new state between PURSUING and IDLE that implements:
- Move to last known player position
- Define a circular "potential player zone" around it
- Identify inspection points (corners, behind covers) within the zone
- Visit and "inspect" each point (brief pause + looking around)
- Mark zone as cleared when all points checked

### 2. Add Inspection Point System

Create invisible "InspectionPoint" markers that can be:
- Automatically generated from level geometry (wall corners)
- Manually placed by level designers (behind covers)
- Detected via raycast from wall collision points

### 3. Extend GOAP Actions

Add new actions to `enemy_actions.gd`:
- `SearchAreaAction` - Move to and investigate last-known-position
- `InspectHidingSpotAction` - Check a specific inspection point
- `ClearSearchZoneAction` - Mark zone as cleared

### 4. State Flow

```
Player Visible → COMBAT → Player Escapes → SEARCHING (new) → Zone Cleared → IDLE/PATROL
                                            ↓
                                      Player Found → COMBAT
```

## Implementation Details

### New Variables for Enemy

```gdscript
## Last known position where player was seen
var _last_known_player_position: Vector2 = Vector2.ZERO

## Whether a search zone is active
var _search_zone_active: bool = false

## Radius of the potential player zone
var _search_zone_radius: float = 200.0

## Inspection points within the search zone
var _inspection_points: Array[Vector2] = []

## Index of current inspection point being checked
var _current_inspection_index: int = 0
```

### New GOAP World State

```gdscript
"has_search_zone": false,
"search_zone_cleared": false,
"inspection_points_remaining": 0
```

## Research References

### Industry Best Practices

1. **F.E.A.R. (2005)** - Pioneered GOAP for enemy AI
   - Uses ~70 goals and ~120 actions
   - Maintains "last known position" for search behavior
   - Source: [Building the AI of F.E.A.R. with Goal Oriented Action Planning](https://www.gamedeveloper.com/design/building-the-ai-of-f-e-a-r-with-goal-oriented-action-planning)

2. **Splinter Cell: Blacklist** - Dynamic search patterns
   - Guards don't drop alert after searching
   - Modified patrol routes after alerts
   - Source: [What's the right AI for a stealth game?](https://www.neogaf.com/threads/whats-the-right-ai-for-a-stealth-game.1011199/)

3. **Third Eye Crime** - Occupancy maps
   - Uses probability-based knowledge representation
   - More realistic pursuit and search behavior
   - Source: [Dynamic Guard Patrol in Stealth Games](https://ojs.aaai.org/index.php/AIIDE/article/download/7425/7308/10903)

### Common Patterns

1. **Last Known Position (LKP)**
   - Store position where player was last seen
   - Move to LKP before searching
   - Define search area around LKP

2. **Investigation Points**
   - Pre-defined or dynamically generated
   - Located at corners, behind objects
   - Priority-ordered by proximity to LKP

3. **Alert Decay**
   - Gradual return to patrol after search
   - Modified patrol patterns post-alert
   - Memory of previous encounters

## Files to Modify

1. `scripts/objects/enemy.gd` - Add SEARCHING state and related logic
2. `scripts/ai/enemy_actions.gd` - Add new GOAP actions
3. `scripts/ai/goap_action.gd` - No changes needed (base class sufficient)
4. `scripts/ai/goap_planner.gd` - No changes needed (planner sufficient)
5. Level scenes - Optionally add InspectionPoint nodes

## Testing Strategy

1. **Unit Tests**
   - Test inspection point generation from geometry
   - Test search zone activation/deactivation
   - Test transition from COMBAT → SEARCHING

2. **Integration Tests**
   - Verify enemy moves to last known position
   - Verify inspection points are checked
   - Verify zone is cleared after full search

3. **Manual Testing**
   - Break line of sight with enemy
   - Observe enemy search behavior
   - Verify zone is cleared or player found

## Success Criteria

1. Enemy remembers where player was last seen
2. Enemy moves to that location after losing sight
3. Enemy checks nearby hiding spots methodically
4. Enemy returns to patrol/guard after zone is cleared
5. All existing functionality preserved (shooting, cover, etc.)

---

## Implementation Summary

### Files Modified

1. **`scripts/objects/enemy.gd`**
   - Added `SEARCHING` state to `AIState` enum
   - Added search zone variables (`_last_known_player_position`, `_search_zone_active`, etc.)
   - Added inspection point variables and constants
   - Updated `_initialize_goap_state()` with search-related world state
   - Updated `_update_goap_state()` to track search status
   - Updated `_process_ai_state()` to handle SEARCHING state
   - Updated `_check_player_visibility()` to track last known position
   - Changed COMBAT->PURSUING transition to COMBAT->SEARCHING
   - Added `_transition_to_searching()` function
   - Added `_clear_search_zone()` function
   - Added `_generate_inspection_points()` function
   - Added `_process_searching_state()` function
   - Updated `_get_state_name()` to include SEARCHING
   - Updated `_update_debug_label()` for search state info
   - Updated `_draw()` for search zone visualization

2. **`scripts/ai/enemy_actions.gd`**
   - Added `SearchAreaAction` class
   - Added `InspectHidingSpotAction` class
   - Updated `create_all_actions()` to include new actions

### New Constants Added

```gdscript
const SEARCH_ZONE_RADIUS: float = 200.0
const SEARCH_MAX_DURATION: float = 15.0
const INSPECTION_WAIT_DURATION: float = 1.5
const INSPECTION_POINT_CHECK_COUNT: int = 24
const INSPECTION_CHECK_DISTANCE: float = 250.0
```

### Behavior Flow

```
Player Visible (COMBAT)
    ↓ Player escapes view
Store last_known_player_position
    ↓
Transition to SEARCHING
    ↓
Generate inspection points (behind obstacles + corners)
    ↓
Move to first inspection point
    ↓
Wait and look around (1.5s)
    ↓
Move to next inspection point (repeat until all checked)
    ↓
Search complete OR timeout (15s)
    ↓
Return to IDLE (patrol/guard)

At any point during search:
- If player spotted → COMBAT
- If under fire → RETREATING
```

### Debug Visualization

When `debug_label_enabled` is true (toggle with F7 in-game):
- Orange circle: Search zone boundary
- Red X: Last known player position
- Green circles: Unchecked inspection points
- White circle: Current target inspection point
- Gray circles: Already checked inspection points
- White line: Path to current inspection point
