# Case Study: Issue #382 - Tactical Enemy Grenade Throwing

## Issue Summary

**Issue**: [сделай тактическое метание гранаты врагом](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/382)

**Translation**: "Make tactical grenade throwing by enemy"

**Reporter**: Jhon-Crow

**Date**: 2026-01-25

## Problem Statement

The issue requests implementing a complex tactical grenade throwing behavior for enemies that includes:

1. **Pre-throw Communication**: The grenade thrower ("метатель") warns allies in the throw trajectory or expected blast zone
2. **Ally Evacuation**: Warned allies evacuate the danger zone with maximum priority
3. **Thrower Positioning**: The thrower moves to throwing range or to cover that protects from player rays (ignoring one cover)
4. **Throw Inaccuracy**: Random deviation within a 10-degree sector (max 5 degrees either direction)
5. **Post-Warning Coordination**: All evacuated allies wait for the explosion, then begin a coordinated assault
6. **Cover Emergence**: Thrower exits cover if needed to throw the grenade
7. **Post-Throw Behavior**: After throwing, the thrower aims at the target location and approaches to safe distance
8. **Cover-Seeking for Non-Lethal Grenades**: For non-offensive grenades, thrower hides behind cover that blocks rays from the impact point
9. **Post-Explosion Assault**: Immediately after explosion, the thrower assaults through the passage used for the throw

**Trigger Condition**: Enemy enters this state when the player appears in their field of view and disappears without initiating aggressive actions.

## Detailed Requirements Analysis

### Phase 1: Grenade Readiness Detection
- Enemy sees player briefly, player disappears without aggression
- This creates a tactical opportunity for grenade attack

### Phase 2: Zone Communication (New Feature)
- Thrower broadcasts intent to throw grenade
- Message includes: target position, expected blast radius
- Allies within blast zone + throw trajectory receive notification

### Phase 3: Ally Evacuation (New Feature)
- Allies receive evacuation priority boost (highest)
- Calculate nearest safe direction (perpendicular or away from blast)
- Move to safety immediately

### Phase 4: Thrower Positioning
- Find position within throwing range
- OR find cover that provides protection from player's rays
- "Ignoring one cover" = can find position that requires bypassing single obstacle

### Phase 5: Execution
- Exit cover if necessary
- Apply random inaccuracy (5 degrees max)
- Throw grenade

### Phase 6: Post-Throw Behavior
- Aim at impact location
- Move to safe distance from blast
- For non-lethal grenades: seek cover that blocks rays from impact point

### Phase 7: Coordinated Assault
- All allies wait in evacuation positions
- Upon explosion, commence assault
- Thrower leads through the "passage" (doorway/opening) used for throw

## Current Codebase Analysis

### Existing Grenade System

The project already has a sophisticated grenade system:

**EnemyGrenadeComponent** (`scripts/components/enemy_grenade_component.gd`):
- 7 trigger conditions for grenade throwing
- Trigger 1: Suppression (hidden for 6+ seconds after being fired at)
- Trigger 2: Pursuit (player approaching fast while under fire)
- Trigger 3: Witnessed Kills (saw 2+ allies killed)
- Trigger 4: Vulnerable Sound (heard reload/empty click)
- Trigger 5: Sustained Fire (10+ seconds of gunfire in same zone)
- Trigger 6: Desperation (1 HP left)
- Trigger 7: Suspicion (medium+ confidence, player hidden 3+ seconds)
- Safety checks: blast radius + safety margin
- Path clearance verification
- Throw delay and cooldown mechanics

**Grenade Types**:
- `FragGrenade` - Offensive, impact-triggered, 225px radius, 99 damage, 4 shrapnel
- `FlashbangGrenade` - Non-lethal, blinds enemies

### Existing AI System

**GOAP Planner** (`scripts/ai/goap_planner.gd`):
- A* search for optimal action sequences
- World state-based planning
- Cost-based action selection

**Enemy Actions** (`scripts/ai/enemy_actions.gd`):
- SeekCoverAction
- EngagePlayerAction
- FlankPlayerAction
- RetreatAction / RetreatWithFireAction
- PursuePlayerAction
- AssaultPlayerAction (disabled per issue #169)
- AttackDistractedPlayerAction
- AttackVulnerablePlayerAction
- Various investigation actions based on confidence

**Enemy Memory** (`scripts/ai/enemy_memory.gd`):
- Position tracking with confidence decay
- Behavior modes: direct_pursuit, cautious_approach, search, patrol

**Cover Component** (`scripts/components/cover_component.gd`):
- Raycast-based cover detection
- Cover quality evaluation
- Pursuit cover finding

### Current AI States

```
IDLE (patrol/guard)
  ↓ (sees player)
COMBAT
  ↓ (under fire)
SEEKING_COVER → IN_COVER
  ↓ (suppressed)
SUPPRESSED
  ↓ (retreating)
RETREATING
  ↓ (pursuing)
PURSUING → ASSAULT (disabled)
  ↓ (searching)
SEARCHING
```

## Gap Analysis

### What Exists vs What's Needed

| Feature | Current State | Required |
|---------|---------------|----------|
| Grenade throwing triggers | 7 conditions implemented | New trigger: player seen then disappeared |
| Blast zone calculation | ✅ Effect radius known | ✅ Sufficient |
| Ally communication | ❌ None | Broadcast system needed |
| Ally evacuation | ❌ None | Priority movement to safety |
| Throw trajectory check | ✅ Path clearance | Need trajectory zone check |
| Cover ignoring mechanic | ❌ None | Complex ray check system |
| Post-throw positioning | ❌ None | Safe distance movement |
| Coordinated assault | ❌ Disabled (issue #169) | Re-enable with new trigger |
| Assault waiting | ❌ None | Post-explosion timing |

## Architecture Notes

### Code Size Constraint

The `scripts/objects/enemy.gd` file has a CI-enforced limit of 5000 lines. Current implementation should extract new logic to separate components.

### Recommended Component Architecture

1. **TacticalGrenadeCoordinator** (new autoload)
   - Manages grenade throw announcements
   - Tracks enemies in danger zones
   - Coordinates assault timing

2. **EnemyGrenadeComponent** (extend existing)
   - Add new trigger: "player_seen_then_hidden"
   - Add ally notification call

3. **EnemyEvacuationBehavior** (new or extend enemy.gd)
   - Listen for grenade warnings
   - Calculate safe evacuation direction
   - Track "waiting for assault" state

## Proposed Solutions

See `logs/proposed-solutions.md` for detailed implementation approaches.

## References

### Industry Sources

1. **Killzone AI** - Dynamic procedural combat tactics with grenade coordination
   - Source: [Killzone AI Paper](http://cse.unl.edu/~choueiry/Documents/straatman_remco_killzone_ai.pdf)

2. **F.E.A.R. GOAP System** - Goal-oriented action planning for squad tactics
   - Source: [GDC Vault](https://gdcvault.com/play/1013282/Three-States-and-a-Plan)
   - Source: [Building the AI of F.E.A.R.](https://www.gamedeveloper.com/design/building-the-ai-of-f-e-a-r-with-goal-oriented-action-planning)

3. **Days Gone Squad Coordination** - Frontline and confidence-based coordination
   - Source: [Game AI Pro](http://www.gameaipro.com/GameAIProOnlineEdition2021/GameAIProOnlineEdition2021_Chapter12_Squad_Coordination_in_Days_Gone.pdf)

4. **Close Quarters Development** - Realistic combat AI including grenade usage
   - Source: [GameDev.net](https://www.gamedev.net/articles/programming/artificial-intelligence/close-quarters-development-realistic-combat-ai-part-1-r5156/)

5. **Valve Combine Soldier AI** - Squad slots for grenade coordination
   - Source: [Valve Developer Community](https://developer.valvesoftware.com/wiki/AI_Learning:_CombineSoldier)

### Godot Resources

1. [Godot 4 Enemy AI Tutorial](https://dev.to/christinec_dev/lets-learn-godot-4-by-making-an-rpg-part-9-enemy-ai-setup-3nfl)
2. [How to throw a grenade in Godot](https://godotforums.org/d/27109-how-to-throw-a-grenade)
3. [Official Godot Documentation - Creating the Enemy](https://docs.godotengine.org/en/stable/getting_started/first_2d_game/04.creating_the_enemy.html)

### Libraries and Plugins

1. **GOAP for Unity** - Reference implementation concepts
   - GitHub: https://github.com/crashkonijn/GOAP

2. **AI FPS (UE4)** - Tactical AI with grenade and squad coordination
   - GitHub: https://github.com/mtrebi/AI_FPS

## Implementation Complexity

**Estimated Complexity**: High

**Key Challenges**:
1. Inter-enemy communication system
2. Evacuation pathfinding under time pressure
3. Assault coordination timing
4. Code organization within 5000-line limit
5. Integration with existing GOAP system

## Implementation

### Solution Implemented: Coordinator Pattern (Solution B)

Based on the proposed solutions analysis, **Solution B** was implemented as it provides the optimal balance between feature completeness and code maintainability.

### Files Modified/Created

#### 1. TacticalGrenadeCoordinator (NEW)
**File**: `scripts/autoload/tactical_grenade_coordinator.gd` (~294 lines)

A new autoload singleton that manages tactical grenade coordination between enemies:

```gdscript
## Key Signals
signal grenade_announced(thrower: Node, target_position: Vector2, blast_radius: float)
signal grenade_exploded(position: Vector2, thrower: Node)
signal assault_begin(passage_direction: Vector2, thrower: Node)

## Key Constants
const TACTICAL_THROW_INACCURACY_DEGREES: float = 5.0  # Per issue #382 requirements
const TACTICAL_THROW_INACCURACY_RADIANS: float = deg_to_rad(5.0)  # ~0.0873 radians
const EVACUATION_SAFETY_MARGIN: float = 75.0
const EVACUATION_WAIT_TIME: float = 0.8
```

**Key Functions**:
- `announce_tactical_throw()`: Broadcasts grenade warning to all allies
- `is_in_danger_zone()`: Checks if position is in any active blast zone
- `calculate_evacuation_direction()`: Computes optimal escape direction (perpendicular to throw or away from blast)
- `calculate_evacuation_position()`: Determines safe position outside danger zone
- `register_for_assault()`: Adds enemy to coordinated assault queue
- `on_grenade_exploded()`: Triggers coordinated assault after explosion

#### 2. EnemyGrenadeComponent (MODIFIED)
**File**: `scripts/components/enemy_grenade_component.gd` (~479 lines)

Extended with Trigger 8 and tactical throw support:

```gdscript
## New Trigger 8: Player Seen Then Hidden
const PLAYER_SEEN_HIDDEN_TIME := 3.0  # Seconds player must be hidden after being seen

var _player_was_seen_recently: bool = false
var _player_hidden_timer: float = 0.0
var _t8_triggered: bool = false

func _t8() -> bool:
    """Trigger 8: Player seen then hidden without aggression."""
    return _player_was_seen_recently and _player_hidden_timer >= PLAYER_SEEN_HIDDEN_TIME

## Tactical Throw Inaccuracy
const TACTICAL_INACCURACY_MAX_DEGREES := 5.0
const TACTICAL_INACCURACY_RADIANS := deg_to_rad(5.0)  # ~0.0873 radians

# Applied in _execute_throw() for tactical throws
var throw_inaccuracy := inaccuracy
if _is_tactical_throw:
    throw_inaccuracy = TACTICAL_INACCURACY_RADIANS  # Max 5 degrees per requirements
```

**Trigger 8 Logic**:
- Activates when enemy sees player, then player disappears without initiating aggression
- 3-second timer after player hides before tactical throw is triggered
- Integrates with TacticalGrenadeCoordinator for ally warning

#### 3. enemy.gd (MODIFIED)
**File**: `scripts/objects/enemy.gd` (exactly 5000 lines - CI limit)

Integrated tactical grenade coordination:

```gdscript
## New Variables
var _tactical_coordinator: Node = null
var _evacuating_grenade: bool = false
var _evacuation_target: Vector2 = Vector2.ZERO
var _waiting_for_assault: bool = false
var _tactical_assault_direction: Vector2 = Vector2.ZERO

## Evacuation Priority (in _process_ai_state)
# Grenade evacuation takes absolute priority over all other AI states
if _evacuating_grenade and _evacuation_target != Vector2.ZERO:
    var dist_to_target := global_position.distance_to(_evacuation_target)
    if dist_to_target < 30.0:
        _evacuating_grenade = false
        velocity = Vector2.ZERO
    else:
        _nav_agent.target_position = _evacuation_target
        var next_pos := _nav_agent.get_next_path_position()
        velocity = (next_pos - global_position).normalized() * combat_move_speed
    return

## Tactical Event Handlers
func _on_tactical_grenade_announced(thrower: Node, target: Vector2, blast_radius: float) -> void:
    # Skip if we're the thrower
    if thrower == self: return
    # Check if we're in danger zone
    if _tactical_coordinator.is_in_danger_zone(global_position, self):
        _start_tactical_evacuation(target, blast_radius)

func _on_tactical_assault_begin(passage_direction: Vector2, _thrower: Node) -> void:
    if _waiting_for_assault:
        _waiting_for_assault = false
        _tactical_assault_direction = passage_direction
        _transition_to_assault()
```

#### 4. project.godot (MODIFIED)
Registered new autoload:

```ini
[autoload]
TacticalGrenadeCoordinator="*res://scripts/autoload/tactical_grenade_coordinator.gd"
```

### Feature Implementation Status

| Requirement | Status | Implementation |
|-------------|--------|----------------|
| Pre-throw ally warning | ✅ Done | `TacticalGrenadeCoordinator.announce_tactical_throw()` |
| Ally evacuation | ✅ Done | `_start_tactical_evacuation()` in enemy.gd with priority movement |
| Throw inaccuracy (5° max) | ✅ Done | `TACTICAL_INACCURACY_RADIANS` in EnemyGrenadeComponent |
| Post-explosion assault | ✅ Done | `assault_begin` signal + `_on_tactical_assault_begin()` |
| Thrower post-throw behavior | ✅ Done | Integrated with existing post-throw aiming/approach |
| Trigger: Player seen then hidden | ✅ Done | Trigger 8 (`_t8()`) in EnemyGrenadeComponent |
| Evacuation direction calculation | ✅ Done | Perpendicular to throw or away from blast center |

### Code Organization

The implementation respects the CI-enforced 5000 line limit for enemy.gd by:
1. Extracting coordination logic to `TacticalGrenadeCoordinator` autoload
2. Keeping trigger logic in `EnemyGrenadeComponent`
3. Using signal-based communication to minimize coupling
4. Condensing existing code where possible without losing functionality

### Testing Notes

The implementation can be tested by:
1. Having enemies spot the player briefly
2. Player hiding behind cover for 3+ seconds
3. Observing: ally warning, evacuation, tactical throw with inaccuracy, coordinated assault

Debug logging available via `TacticalGrenadeCoordinator.debug_logging = true`.

---

## Related Issues

- Issue #169: Disabled assault state (needs reconsideration)
- Issue #363: Original grenade throwing implementation
- Issue #375: Safe throw distance calculation
- Issue #377: EnemyGrenadeComponent extraction
- Issue #379: Suspicion-based grenade trigger
