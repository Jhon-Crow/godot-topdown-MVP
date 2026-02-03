# Case Study: Issue #409 - Enemy SEARCHING State on Witnessing Ally Death

## Issue Summary

**Title (Russian):** враг должен входить в состояние SEARCHING когда видит, как умер другой враг
**Title (English):** Enemy should enter SEARCHING state when they see another enemy die

**Requirements:**
1. When an enemy sees another enemy die, they should enter the **SEARCHING state**
2. The observing enemy should consider **multiple possible directions** where the player might be
3. Integrate this behavior into the existing **GOAP** system
4. Follow the established **architectural patterns**

## Current System Analysis

### Existing AI Architecture

The enemy AI uses a hybrid approach combining:
- **State Machine**: 10 AI states (IDLE, COMBAT, SEEKING_COVER, IN_COVER, FLANKING, SUPPRESSED, RETREATING, PURSUING, ASSAULT, SEARCHING)
- **GOAP Planner**: Goal-Oriented Action Planning for decision making
- **Memory System**: Tracks player position with confidence levels

### Existing Death Signals

From `scripts/objects/enemy.gd`:
```gdscript
signal died  ## Enemy died
signal died_with_info(is_ricochet_kill: bool, is_penetration_kill: bool)  ## Death with kill info
```

The `_on_death()` function:
```gdscript
func _on_death() -> void:
    _is_alive = false
    died.emit()
    died_with_info.emit(_killed_by_ricochet, _killed_by_penetration)
```

### Existing Communication Systems

1. **Intel Sharing** (`_share_intel_with_nearby_enemies()`):
   - Range: 660px with LOS, 300px without LOS
   - Shares player position with confidence reduction (0.9 factor)
   - Called every 0.5 seconds

2. **Sound Propagation**:
   - Enemies react to gunshots, reloads, empty clicks
   - Uses SoundPropagation autoload

### SEARCHING State (Issue #322)

Already implemented with:
- Expanding square spiral pattern
- Waypoint-based movement with scanning
- Zone tracking to avoid re-checking areas
- Maximum search duration: 30 seconds

## Research Findings

### Game AI Patterns for Witnessing Ally Death

Based on research of tactical shooter AI systems:

1. **F.E.A.R. (2005)**: Soldiers react to fallen comrades, communicate with phrases like "Anyone see him?" and dynamically re-plan their approach.

2. **S.T.A.L.K.E.R. Series**: Enemies respond to ally deaths with tactical behaviors like flanking and alerting others.

3. **Modern Tactical Shooters**: AI uses "situational awareness" - when an ally dies, nearby enemies:
   - Increase alertness state
   - Consider multiple threat directions
   - May flee, seek cover, or aggressively search

### Multiple Direction Estimation

When an enemy witnesses an ally's death, they can estimate possible player directions:

1. **Death Direction Analysis**: The direction the bullet came from
2. **Last Known Position**: Any previously shared intel about player position
3. **Sound Source**: Direction of the gunshot
4. **Environmental Analysis**: Cover positions and sight lines

## Proposed Solution

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                      Enemy Death Event                          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│          Nearby Enemies with Line of Sight Check                │
│   (Within DEATH_OBSERVE_RANGE with _has_line_of_sight_to_pos)   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              on_ally_death_observed()                           │
│   - Record death position                                       │
│   - Calculate possible threat directions                        │
│   - Store in memory with medium confidence                      │
│   - Transition to SEARCHING state                               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│           SEARCHING State with Multiple Directions              │
│   - Generate waypoints covering multiple suspected directions   │
│   - Priority on directions with higher threat probability       │
│   - Use existing SEARCHING behavior (expanding spiral)          │
└─────────────────────────────────────────────────────────────────┘
```

### Implementation Components

#### 1. Death Observation Handler in `enemy.gd`

New function to handle observing ally deaths:
```gdscript
## Called when this enemy witnesses another enemy die.
## Triggers SEARCHING state with multiple suspected directions.
func on_ally_death_observed(death_position: Vector2, attacker_direction: Vector2) -> void:
    # Calculate multiple possible player positions
    # Transition to SEARCHING with the estimated positions
```

#### 2. Death Broadcast System

Modify `_on_death()` to notify nearby enemies:
```gdscript
func _on_death() -> void:
    _is_alive = false
    died.emit()
    died_with_info.emit(_killed_by_ricochet, _killed_by_penetration)
    _notify_nearby_enemies_of_death()  # New function
```

#### 3. Multiple Direction Estimation

Store multiple suspected directions in memory:
```gdscript
## Store multiple suspected positions for multi-direction search
var _suspected_directions: Array[Vector2] = []
```

#### 4. GOAP Integration

New action for responding to witnessed deaths:
```gdscript
class InvestigateAllyDeathAction extends GOAPAction:
    func _init() -> void:
        super._init("investigate_ally_death", 0.8)  # High priority
        preconditions = {
            "witnessed_ally_death": true,
            "player_visible": false
        }
        effects = {
            "is_searching": true
        }
```

### Key Design Decisions

1. **Observation Range**: 400px with line of sight required
2. **Confidence Level**: Medium (0.6) - uncertain of exact player position
3. **Direction Count**: Up to 3 suspected directions
4. **Priority**: Higher than regular patrol, lower than combat

## Implementation Plan

### Phase 1: Death Observation System
1. Add `on_ally_death_observed()` function
2. Modify `_on_death()` to broadcast to nearby enemies
3. Add LOS check for death observation

### Phase 2: Multiple Direction Calculation
1. Calculate primary direction (opposite of hit direction)
2. Add perpendicular directions as alternatives
3. Store directions in new `_suspected_directions` array

### Phase 3: Enhanced SEARCHING State
1. Modify `_transition_to_searching()` to accept multiple directions
2. Generate waypoints prioritizing suspected directions
3. Weight search pattern toward high-probability areas

### Phase 4: GOAP Integration
1. Add `InvestigateAllyDeathAction` to enemy actions
2. Add `witnessed_ally_death` world state variable
3. Clear flag when entering SEARCHING

### Phase 5: Testing
1. Unit tests for direction calculation
2. Unit tests for death observation
3. Integration tests for state transitions

## Existing Components to Leverage

| Component | File | Usage |
|-----------|------|-------|
| EnemyMemory | `scripts/ai/enemy_memory.gd` | Store suspected position |
| GOAPAction | `scripts/ai/goap_action.gd` | Base class for new action |
| SEARCHING state | `scripts/objects/enemy.gd` | Existing search behavior |
| LOS check | `_has_line_of_sight_to_position()` | Visibility verification |
| Intel sharing | `_share_intel_with_nearby_enemies()` | Communication pattern |

## Test Plan

### Unit Tests
1. Test direction calculation from death position
2. Test observation range limits
3. Test LOS requirement for observation
4. Test GOAP action preconditions/effects

### Integration Tests
1. Enemy A dies -> Enemy B transitions to SEARCHING
2. Multiple enemies observe death simultaneously
3. Enemy behind wall does NOT observe death
4. Search pattern covers suspected directions

## References

### Industry Best Practices
- [Building the AI of F.E.A.R.](https://www.gamedeveloper.com/design/building-the-ai-of-f-e-a-r-with-goal-oriented-action-planning) - GOAP implementation
- [GDC: Situational Awareness AI](https://gdcvault.com/play/1015718/Situational-Awareness-Terrain-Reasoning-for) - Terrain reasoning for tactical AI
- [Halo 2 Behavior Trees](https://en.wikipedia.org/wiki/Artificial_intelligence_in_video_games) - Squad-based reactions

### Related Issues in This Repository
- Issue #322: Search State (SEARCHING implemented)
- Issue #297: Memory System (confidence-based tracking)
- Issue #330: Never return to IDLE after engaging

## Implementation Status

- [x] Phase 1: Death Observation System
- [x] Phase 2: Multiple Direction Calculation
- [x] Phase 3: Enhanced SEARCHING State
- [x] Phase 4: GOAP Integration
- [x] Phase 5: Testing

## Implementation Details

### Files Modified

| File | Changes |
|------|---------|
| `scripts/objects/enemy.gd` | Added death notification, ally death observation handler, multi-direction search |
| `scripts/ai/enemy_actions.gd` | Added `InvestigateAllyDeathAction` GOAP action |
| `tests/unit/test_enemy.gd` | Added ally death observation tests |
| `tests/unit/test_enemy_actions.gd` | Added `InvestigateAllyDeathAction` tests |

### New Constants and Variables

```gdscript
# In enemy.gd:
const ALLY_DEATH_OBSERVE_RANGE: float = 500.0  # Max distance to observe ally death
const ALLY_DEATH_CONFIDENCE: float = 0.6  # Medium confidence when observing death
var _suspected_directions: Array[Vector2] = []  # Up to 3 directions to check
```

### New Functions

1. **`_notify_nearby_enemies_of_death()`**: Called when enemy dies, broadcasts to nearby enemies
2. **`on_ally_died(ally_position, killer_is_player, hit_direction)`**: Enhanced to trigger SEARCHING
3. **`_calculate_suspected_directions_from_death(death_position, hit_direction)`**: Calculates primary and perpendicular directions
4. **`_transition_to_searching_with_directions(center_position)`**: Initiates search with prioritized directions
5. **`_generate_search_waypoints_with_directions()`**: Generates waypoints prioritizing suspected directions

### GOAP World State

Added `witnessed_ally_death` boolean to world state dictionary for GOAP action selection.

### Flow Summary

```
Enemy A dies
    ↓
_on_death() emits died signal + calls _notify_nearby_enemies_of_death()
    ↓
Nearby enemies within 500px with FOV check AND LOS receive on_ally_died() call
    ↓
Observer calculates 3 suspected directions from hit_direction
    ↓
Memory updated with medium confidence (0.6)
    ↓
Observer transitions to SEARCHING state
    ↓
Search waypoints prioritize suspected directions
```

## Bug Fix: FOV Not Checked for Ally Death Observation (2026-02-03)

### Issue Report

User reported that enemies facing away from an ally death were still reacting to it:
> "сейчас даже враг, который смотрит в другую сторону видит смерть реагирует на смерть другого врага"
> (Translation: "Currently, even an enemy looking in another direction sees the death and reacts to another enemy's death")

### Root Cause Analysis

The `on_ally_died()` function was only checking:
1. ✅ Distance within `ALLY_DEATH_OBSERVE_RANGE` (500px)
2. ✅ Line of sight via `_can_see_position()` (raycast for obstacles)

But it was **NOT** checking:
3. ❌ Field of view direction via `_is_position_in_fov()` (facing angle)

This meant enemies could "see" deaths happening behind them, which is unrealistic.

### Fix Applied

Added FOV check to `on_ally_died()`:

**Before:**
```gdscript
if distance > ALLY_DEATH_OBSERVE_RANGE or not _can_see_position(ally_position): return
```

**After:**
```gdscript
if distance > ALLY_DEATH_OBSERVE_RANGE or not _is_position_in_fov(ally_position) or not _can_see_position(ally_position): return
```

### Additional Changes: FOV Default Behavior

User also requested that FOV limitation become the default behavior:
> "замени пункт у experimental меню с включить ограниченную область зрения на выключить ограниченную область зрения (то есть ограниченная область зрения теперь не экспериментальная функция)"
> (Translation: "Replace the item in the experimental menu from 'enable limited field of view' to 'disable limited field of view' (meaning limited FOV is now not an experimental feature)")

Changes made:
1. `experimental_settings.gd`: Changed `fov_enabled` default from `false` to `true`
2. `ExperimentalMenu.tscn`: Changed label from "Enable FOV" to "Disable FOV Limitation"
3. `experimental_menu.gd`: Inverted checkbox logic (checked = FOV disabled)

### Updated Flow

```
Enemy A dies
    ↓
_on_death() emits died signal + calls _notify_nearby_enemies_of_death()
    ↓
For each nearby enemy:
    ├── Check distance <= 500px
    ├── Check within FOV cone (100° default)  ← NEW CHECK
    └── Check line of sight (raycast)
    ↓
Only enemies who can ACTUALLY SEE the death receive on_ally_died() call
```

### Log Evidence

From `game_log_20260203_164327.txt`:
```
[16:44:06] [ENEMY] [Enemy2] [AllyDeath] Witnessed at (700, 750), entering SEARCHING
[16:44:06] [ENEMY] [Enemy3] [AllyDeath] Notified 2 enemies
```

Enemy2 was being notified even when facing away from Enemy3's death position. With the fix, Enemy2 will only be notified if the death position is within their 100° FOV cone.
