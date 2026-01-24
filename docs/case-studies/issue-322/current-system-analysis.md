# Current System Analysis - Enemy AI

This document provides detailed analysis of the current enemy AI implementation relevant to Issue #322.

## File Structure

```
scripts/
├── ai/
│   ├── goap_action.gd      # Base class for GOAP actions (77 lines)
│   ├── goap_planner.gd     # A* planner for action sequences (152 lines)
│   ├── enemy_actions.gd    # 17 enemy GOAP actions (370 lines)
│   ├── enemy_memory.gd     # Confidence-based memory system (178 lines)
│   └── states/
│       ├── enemy_state.gd      # Base state class (39 lines)
│       ├── idle_state.gd       # Patrol/guard behavior (77 lines)
│       └── pursuing_state.gd   # Cover-to-cover pursuit (113 lines)
├── objects/
│   └── enemy.gd            # Main enemy script (~5000 lines)
└── autoload/
    └── last_chance_effects_manager.gd  # Last chance effect (~1059 lines)
```

## AI State Machine

### Current States (AIState enum)

| State | Description | Triggers |
|-------|-------------|----------|
| IDLE | Patrol or guard behavior | Initial, after search fails |
| COMBAT | Active engagement | Player visible and close |
| SEEKING_COVER | Moving to cover | Under fire, health low |
| IN_COVER | Hiding behind cover | Reached cover position |
| FLANKING | Tactical flanking | Lost sight, attempting flank |
| SUPPRESSED | Taking cover under fire | Bullets in threat sphere |
| RETREATING | Moving to cover while shooting | Low health + under fire |
| PURSUING | Cover-to-cover toward player | Player not visible, has memory |
| ASSAULT | Multi-enemy rush (DISABLED) | N/A (disabled per #169) |

### State Transitions Relevant to Search

```
                    ┌────────────────┐
                    │     IDLE       │
                    │ (patrol/guard) │
                    └───────┬────────┘
                            │ Memory: high/medium confidence
                            ▼
                    ┌────────────────┐
        ┌──────────▶│   PURSUING     │◀──────────┐
        │           │(cover-to-cover)│           │
        │           └───────┬────────┘           │
        │                   │                    │
        │  Lost sight       │ Player found       │ Lost sight
        │                   ▼                    │
        │           ┌────────────────┐           │
        └───────────│    COMBAT      │───────────┘
                    │  (engagement)  │
                    └───────┬────────┘
                            │ Memory: low confidence + not found
                            ▼
                    ┌────────────────┐
                    │     IDLE       │
                    │ (return patrol)│
                    └────────────────┘

MISSING STATE:
                    ┌────────────────┐
                    │   SEARCHING    │  <-- NOT IMPLEMENTED
                    │(systematic)    │
                    └────────────────┘
```

## Enemy Memory System (enemy_memory.gd)

### Confidence Levels

| Level | Threshold | Source | Behavior |
|-------|-----------|--------|----------|
| HIGH | ≥ 0.8 | Visual contact (1.0) | Direct pursuit |
| MEDIUM | 0.5 - 0.8 | Gunshot sound (0.7) | Cautious approach |
| LOW | 0.3 - 0.5 | Reload sound (0.6), Intel (var) | Search/patrol |
| LOST | < 0.05 | Decay | Return to idle |

### Key Methods

```gdscript
# Update position with new information
func update_position(pos: Vector2, new_confidence: float) -> bool

# Decay confidence over time (0.1/sec default)
func decay(delta: float, decay_rate: float = 0.1) -> void

# Check confidence level
func has_target() -> bool          # > 0.05
func is_high_confidence() -> bool  # >= 0.8
func is_medium_confidence() -> bool # 0.5 - 0.8
func is_low_confidence() -> bool   # 0.3 - 0.5

# Get recommended behavior mode
func get_behavior_mode() -> String  # "direct_pursuit", "cautious_approach", "search", "patrol"
```

### Confidence Update Logic

From `enemy_memory.gd:68-81`:
```gdscript
func update_position(pos: Vector2, new_confidence: float) -> bool:
    var current_time := Time.get_ticks_msec()
    var time_since_update := current_time - last_updated

    # Accept update if:
    # 1. New confidence is >= current (stronger signal always wins)
    # 2. OR cooldown has elapsed (allow weaker signals after timeout)
    if new_confidence >= confidence or time_since_update > OVERRIDE_COOLDOWN_MS:
        suspected_position = pos
        confidence = clampf(new_confidence, 0.0, 1.0)
        last_updated = current_time
        return true

    return false
```

## GOAP Actions (enemy_actions.gd)

### Memory-Related Actions

| Action | Preconditions | Cost | Behavior |
|--------|---------------|------|----------|
| InvestigateHighConfidence | !visible, has_pos, conf_high | 1.0-1.5 | Direct pursuit |
| InvestigateMediumConfidence | !visible, has_pos, conf_medium | 2.0-2.5 | Cautious approach |
| SearchLowConfidence | !visible, has_pos, conf_low | 3.0-3.5 | Extended patrol |

### SearchLowConfidenceAction (Current Implementation)

From `enemy_actions.gd:328-347`:
```gdscript
class SearchLowConfidenceAction extends GOAPAction:
    func _init() -> void:
        super._init("search_low_confidence", 3.5)
        preconditions = {
            "player_visible": false,
            "has_suspected_position": true,
            "confidence_low": true
        }
        effects = {
            "area_patrolled": true  # Treat as extended patrol
        }

    func get_cost(_agent: Node, world_state: Dictionary) -> float:
        var confidence: float = world_state.get("position_confidence", 0.0)
        return 3.0 + (0.5 - confidence) * 2.0
```

**Limitation:** This action sets `area_patrolled` effect but doesn't actually implement systematic search - it just extends patrol behavior.

## PURSUING State Behavior (enemy.gd)

### Pursuit Logic (Lines 2270-2424)

The PURSUING state handles cover-to-cover movement toward the player or suspected position:

1. **Target Selection** (`_get_target_position()`):
   - Visible player > Memory suspected position > Last known position > Current position

2. **Cover Finding** (`_find_pursuit_cover_toward_player()`):
   - Searches 16 cover positions around enemy
   - Validates covers are closer to target
   - Validates path is clear (no walls)

3. **Movement Phases**:
   - **Cover Movement**: Move to pursuit cover, wait briefly, find next
   - **Approach Phase**: Direct movement if no cover available

4. **Investigation Check** (Lines 2397-2417):
```gdscript
if _memory and _memory.has_target() and not _can_see_player:
    var target_pos := _memory.suspected_position
    var distance_to_target := global_position.distance_to(target_pos)

    # If we're close to the suspected position but haven't found the player
    if distance_to_target < 100.0:
        # We've investigated but player isn't here - reduce confidence
        _memory.decay(0.3)  # Significant confidence reduction
        _log_debug("Reached suspected position but player not found")

        # If confidence is now low, return to idle
        if not _memory.has_target() or _memory.is_low_confidence():
            _log_to_file("Memory confidence too low after investigation - returning to IDLE")
            _transition_to_idle()
            return
```

**Gap:** When enemy reaches suspected position and player not found, it just reduces confidence and returns to IDLE - no systematic area search.

## Last Chance Effect (Issue #318)

### Memory Reset Logic (enemy.gd:3799-3827)

```gdscript
func reset_memory() -> void:
    # Save old position before resetting - enemies will search here
    var old_position := _memory.suspected_position if _memory != null and _memory.has_target() else Vector2.ZERO
    var had_target := old_position != Vector2.ZERO

    # Reset visibility, detection states, apply confusion timer
    _can_see_player = false
    _continuous_visibility_timer = 0.0
    _intel_share_timer = 0.0
    _pursuing_vulnerability_sound = false
    _memory_reset_confusion_timer = MEMORY_RESET_CONFUSION_DURATION

    if had_target:
        # Set LOW confidence (0.35) - puts enemy in search mode at old position
        if _memory != null:
            _memory.suspected_position = old_position
            _memory.confidence = 0.35
            _memory.last_updated = Time.get_ticks_msec()
        _last_known_player_position = old_position
        _log_to_file("Search mode: %s -> PURSUING at %s" % [AIState.keys()[_current_state], old_position])
        _transition_to_pursuing()
```

**Current Behavior:**
- Preserves old position with LOW confidence (0.35)
- Transitions to PURSUING state
- Enemy navigates to old position using cover-to-cover

**Gap:** Transitions to PURSUING, not a dedicated SEARCHING state with systematic pattern.

## World State Variables (GOAP)

From `enemy.gd:978-1002`:
```gdscript
var _goap_world_state: Dictionary = {
    "player_visible": false,
    "in_cover": false,
    "under_fire": false,
    "has_cover": false,
    "health_low": false,
    "player_close": false,
    "can_hit_from_cover": false,
    "is_pursuing": false,
    "is_retreating": false,
    "enemies_in_combat": 0,
    "player_distracted": false,
    "player_reloading": false,
    "player_ammo_empty": false,
    # Memory system states (Issue #297)
    "has_suspected_position": false,
    "position_confidence": 0.0,
    "confidence_high": false,
    "confidence_medium": false,
    "confidence_low": false
}
```

**Missing for Issue #322:**
- `is_searching`: bool
- `area_searched`: bool
- `pursuit_failed`: bool (to trigger search after pursuit fails)

## Debug Visualization (F7 Toggle)

The enemy AI has extensive debug visualization in `_draw()` method (lines 4750-4850):

- Red line: Direction to player
- Green circle / Red X: Clear/blocked bullet spawn
- Yellow triangle: Clear shot target
- Cyan circle: Cover position
- Orange/Magenta: Pursuit/flank targets
- Yellow/Orange line: Suspected position with uncertainty circle

**For Issue #322:** Add visualization for search waypoints and current search progress.

## Key Constants

From `enemy.gd`:
```gdscript
# Pursuit constants
const PURSUING_MIN_DURATION_BEFORE_COMBAT := 0.3
const PURSUIT_COVER_WAIT_DURATION := 1.5
const PURSUIT_APPROACH_MAX_TIME := 2.0
const PURSUIT_STUCK_THRESHOLD := 20.0
const PURSUIT_MIN_PROGRESS := 30.0

# Memory constants
const MEMORY_RESET_CONFUSION_DURATION := 2.0
const INTEL_SHARE_FACTOR := 0.9
const INTEL_SHARE_INTERVAL := 0.5
const INTEL_SHARE_RANGE_LOS := 660.0
const INTEL_SHARE_RANGE_NO_LOS := 300.0

# Combat constants
const CLOSE_COMBAT_DISTANCE := 150.0
const COMBAT_MIN_DURATION_BEFORE_PURSUE := 0.5
```

## Identified Gaps for Issue #322

1. **No SEARCHING state** - Only IDLE, PURSUING, etc.
2. **No systematic search pattern** - Uses cover-to-cover pursuit
3. **No left/right hand rule** - Movement is cover-based, not wall-following
4. **No expanding zone** - Just single point investigation
5. **Abrupt transition** - From PURSUING directly to IDLE when player not found
6. **Missing world states** - `is_searching`, `area_searched`, `pursuit_failed`
7. **Missing GOAP action** - No `SearchAreaAction` with proper preconditions/effects

## Recommendations

1. Add `AIState.SEARCHING` enum value
2. Create `SearchingState` class with systematic search pattern
3. Add `SearchAreaAction` GOAP action
4. Modify `_transition_to_idle()` to transition to SEARCHING first when memory has low confidence
5. Add world states for search tracking
6. Add debug visualization for search pattern
