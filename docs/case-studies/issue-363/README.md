# Case Study: Enemy Grenade Throwing Behavior (Issue #363)

## Overview

**Issue**: [#363 - начать добавлять метание гранат врагами](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/363)

**Summary**: Add a "ready to throw grenade" mode to enemies. This feature requires implementing intelligent decision-making for when enemies should use grenades against the player, integrating with the existing GOAP (Goal-Oriented Action Planning) system.

**Translation of Requirements**:
> Add a "ready to throw grenade" mode.
>
> Grenade throwing mode activates when:
> 1. The player suppressed enemies in the thrower's field of view or the thrower himself, then hid from sight and hasn't been visible for 6 seconds
> 2. The player is pursuing a suppressed thrower
> 3. The player kills 2 or more enemies in front of the thrower
> 4. The thrower hears an empty magazine or reload start, but doesn't see the player (will throw toward the sound source)
> 5. If the thrower hears continuous shooting for 10 seconds (within 1/6 of the viewport area)
> 6. When the thrower has 1 HP or less remaining
>
> On the "Building" map on hard difficulty, give all enemies 2 offensive grenades each, and on normal difficulty - 1 flashbang each.
>
> Integrate the behavior into the existing GOAP system.

---

## Codebase Analysis

### 1. GOAP System Structure

The codebase already implements a sophisticated GOAP system:

#### Core Files:
- **`scripts/ai/goap_planner.gd`**: A* search-based planner for finding optimal action sequences
- **`scripts/ai/goap_action.gd`**: Base class for all GOAP actions with preconditions, effects, and costs
- **`scripts/ai/enemy_actions.gd`**: 16 existing enemy action types

#### Existing Action Types:
| Action | Base Cost | Purpose |
|--------|-----------|---------|
| SeekCoverAction | 2.0 | Move to cover position |
| EngagePlayerAction | 1.0 | Engage player in combat |
| FlankPlayerAction | 3.0 | Flank when player not visible |
| PatrolAction | 1.0 | Patrol area |
| StaySuppressedAction | 0.5 | Wait for fire to stop |
| ReturnFireAction | 1.5 | Fire from cover |
| FindCoverAction | 0.5 | Search for cover positions |
| RetreatAction | 4.0 | Retreat when health low |
| RetreatWithFireAction | 1.5 | Retreat while suppressed |
| PursuePlayerAction | 2.5 | Cover-to-cover pursuit |
| AssaultPlayerAction | 1000.0 | **DISABLED** |
| AttackDistractedPlayerAction | 0.1 | Attack when player aiming away |
| AttackVulnerablePlayerAction | 0.1 | Attack reloading/empty player |
| PursueVulnerablePlayerAction | 0.2 | Rush vulnerable player |
| InvestigateHighConfidenceAction | 1.5 | Memory-based pursuit |
| InvestigateMediumConfidenceAction | 2.5 | Cautious investigation |
| SearchLowConfidenceAction | 3.5 | Low confidence search |

### 2. Grenade System

#### Existing Grenade Types:
- **`scripts/projectiles/grenade_base.gd`**: Base class with timer, physics, and explosion mechanics
- **`scripts/projectiles/frag_grenade.gd`**: Offensive grenade (225px radius, 99 damage, impact-triggered)
- **`scripts/projectiles/flashbang_grenade.gd`**: Defensive grenade (400px radius, 12s blindness, 6s stun)

#### Grenade Characteristics:
| Type | Radius | Effect | Fuse | Trigger |
|------|--------|--------|------|---------|
| Frag (Offensive) | 225px | 99 damage + shrapnel | None | Impact |
| Flashbang | 400px | 12s blind, 6s stun | 4s | Timer |

### 3. Enemy World State Variables

Located in `scripts/objects/enemy.gd`, the following world state dictionary is used for GOAP planning:

```gdscript
# Visibility & Detection
player_visible          # Can currently see the player
player_distracted       # Player aiming >23° away
player_close            # Player within 400px (CLOSE_COMBAT_DISTANCE)
can_hit_from_cover      # Has line of sight from current position

# Player State
player_reloading        # Player is reloading
player_ammo_empty       # Player tried to shoot with no ammo
ammo_depleted           # All player ammo exhausted

# Enemy State
health_low              # Enemy health < 50%
in_cover                # Currently in cover
has_cover               # Valid cover available
is_retreating           # In RETREATING state
is_pursuing             # In PURSUING state
is_assaulting           # In ASSAULT state
hits_taken              # Number of hits taken

# Combat Status
under_fire              # Bullets detected in threat sphere
enemies_in_combat       # Count of other enemies in combat

# Memory-based States
has_suspected_position  # Has target position in memory
position_confidence     # Confidence level (0.0-1.0)
confidence_high         # Confidence > 0.8
confidence_medium       # Confidence 0.5-0.8
confidence_low          # Confidence 0.3-0.5
```

### 4. Sound Detection System

`scripts/autoload/sound_propagation.gd` provides:

| Sound Type | Range (px) | Through Walls |
|------------|------------|---------------|
| GUNSHOT | 1468.6 | No |
| EXPLOSION | 2200.0 | No |
| RELOAD | 900.0 | **Yes** |
| EMPTY_CLICK | 600.0 | **Yes** |
| RELOAD_COMPLETE | 900.0 | **Yes** |
| FOOTSTEP | 180.0 | No |
| IMPACT | 550.0 | No |

### 5. Vision System

`scripts/components/vision_component.gd` characteristics:
- FOV: 100° cone (configurable)
- Detection delay: 0.2s
- Lead prediction delay: 0.3s
- Minimum visibility ratio: 0.6 (60% visible required for lead prediction)

### 6. Suppression Mechanics

- Threat sphere radius: 100px
- Suppression cooldown: 2.0s
- Threat reaction delay: 0.2s
- `under_fire` flag set when bullets detected in threat sphere

---

## External Research

### F.E.A.R. AI - The Gold Standard for GOAP with Grenades

**Source**: [GDC 2006: Three States and a Plan - The AI of F.E.A.R.](https://gdcvault.com/play/1013282/Three-States-and-a-Plan)

F.E.A.R. (2005) is considered the benchmark for GOAP-based combat AI with grenade usage:

- **Flushing Behavior**: Enemies throw grenades to flush players out of cover
- **Suppression Response**: AI throws grenades when suppressed for extended periods
- **Coordinated Tactics**: Grenades combined with flanking maneuvers
- **Cover Denial**: AI uses grenades to deny player access to strategic positions

> "F.E.A.R.'s artificial intelligence allows hostile NPCs an unusually large range of action... taking cover, laying down suppressive fire so that other enemies can flank, and flushing players out of cover using grenades."

### Killzone AI - Position Evaluation for Grenades

**Source**: [Killzone AI: Dynamic Procedural Combat Tactics](http://cse.unl.edu/~choueiry/Documents/straatman_remco_killzone_ai.pdf)

- **Indirect Fire Reasoning**: AI evaluates positions vulnerable to grenade attacks
- **Cover Analysis**: AI identifies when player is in a position susceptible to grenades
- **Suppression Integration**: Grenade attacks heavily use position evaluation

> "The AI can use position picking to reason about a threat's position and how the threat may be vulnerable to indirect fire. It can also reason about the moves available to the threat and how to deny those moves."

### Common Grenade AI Triggers

Based on industry research:

1. **Player in prolonged cover** - Flush out with grenades
2. **Sound-based targeting** - Throw toward reload/empty click sounds
3. **Multi-kill response** - Desperate measure when teammates die
4. **Low health desperation** - Last-resort attack
5. **Suppression counter** - Response to being pinned down
6. **Pursuit deterrent** - Create distance when being chased

---

## Implementation Analysis

### New World State Variables Required

```gdscript
# Grenade-specific state
has_grenades                  # Enemy has grenades available
grenade_count                 # Number of grenades remaining
grenade_type                  # Type of grenade (frag/flashbang)
ready_to_throw_grenade        # Grenade throwing mode active

# Suppression tracking
suppressed_and_player_hidden  # Player suppressed then hid
player_hidden_timer           # Time since player last visible (>6s threshold)

# Kill tracking
observed_player_kills         # Kills observed by this enemy
player_kills_threshold_met    # Saw 2+ kills

# Sound-based targeting
heard_vulnerable_sound        # Heard reload/empty click
last_sound_position           # Position of last heard sound
sustained_fire_timer          # Duration of continuous fire heard
sustained_fire_zone           # Zone with sustained fire (1/6 viewport)

# Pursuit tracking
player_pursuing_me            # Player is pursuing this enemy
```

### New GOAP Actions Required

#### 1. PrepareGrenadeAction
- **Preconditions**: `has_grenades: true`, one of the trigger conditions met
- **Effects**: `ready_to_throw_grenade: true`
- **Cost**: 0.3 (high priority when conditions met)

#### 2. ThrowGrenadeAtCoverAction (Frag)
- **Preconditions**: `ready_to_throw_grenade: true`, `has_suspected_position: true`, `grenade_type: FRAG`
- **Effects**: `grenade_thrown: true`, `player_flushed: true`
- **Cost**: 0.5

#### 3. ThrowFlashbangAction
- **Preconditions**: `ready_to_throw_grenade: true`, `has_suspected_position: true`, `grenade_type: FLASHBANG`
- **Effects**: `grenade_thrown: true`, `player_blinded: true`
- **Cost**: 0.6

#### 4. ThrowGrenadeAtSoundAction
- **Preconditions**: `ready_to_throw_grenade: true`, `heard_vulnerable_sound: true`, NOT `player_visible`
- **Effects**: `grenade_thrown: true`
- **Cost**: 0.4

#### 5. DesperationGrenadeAction
- **Preconditions**: `health_low: true`, `has_grenades: true`, `player_visible: true` OR `player_pursuing_me: true`
- **Effects**: `grenade_thrown: true`
- **Cost**: 0.2 (very high priority when dying)

### Trigger Condition Implementation

#### Trigger 1: Player suppressed enemies, then hid for 6 seconds
```gdscript
var _suppression_ended_timer: float = 0.0
var _player_was_suppressing: bool = false

func _update_suppression_tracking(delta: float) -> void:
    if _was_suppressed and not _under_fire:
        # Suppression ended
        _player_was_suppressing = true

    if _player_was_suppressing and not _can_see_player:
        _suppression_ended_timer += delta
        if _suppression_ended_timer >= 6.0:
            _world_state["suppressed_and_player_hidden"] = true
    else:
        _suppression_ended_timer = 0.0
```

#### Trigger 2: Player pursuing suppressed thrower
```gdscript
func _update_pursuit_detection() -> void:
    var pursuing: bool = _under_fire and _player_approaching()
    _world_state["player_pursuing_me"] = pursuing
```

#### Trigger 3: Player kills 2+ enemies in view
```gdscript
var _observed_kills: int = 0

func _on_ally_died(ally: Node2D) -> void:
    if _can_see_position(ally.global_position):
        _observed_kills += 1
        if _observed_kills >= 2:
            _world_state["player_kills_threshold_met"] = true
```

#### Trigger 4: Heard empty/reload without seeing player
```gdscript
func on_sound_heard_with_intensity(sound_type: int, position: Vector2, ...) -> void:
    if sound_type == SoundPropagation.SoundType.RELOAD or \
       sound_type == SoundPropagation.SoundType.EMPTY_CLICK:
        if not _can_see_player:
            _world_state["heard_vulnerable_sound"] = true
            _world_state["last_sound_position"] = position
```

#### Trigger 5: 10 seconds of continuous fire in 1/6 viewport zone
```gdscript
var _fire_zone_timer: float = 0.0
var _fire_zone_position: Vector2 = Vector2.ZERO
const FIRE_ZONE_SIZE: float = 213.3  # ~1/6 of 1280px

func _update_sustained_fire_detection(sound_pos: Vector2, delta: float) -> void:
    var zone_size: float = get_viewport().size.x / 6.0
    if _fire_zone_position.distance_to(sound_pos) < zone_size:
        _fire_zone_timer += delta
        if _fire_zone_timer >= 10.0:
            _world_state["sustained_fire_zone"] = true
    else:
        _fire_zone_position = sound_pos
        _fire_zone_timer = 0.0
```

#### Trigger 6: Health at 1 HP or less
```gdscript
func _update_health_state() -> void:
    _world_state["health_critical"] = _current_health <= 1
```

---

## Proposed Solutions

### Solution 1: Full GOAP Integration (Recommended)

**Approach**: Create new GOAP actions with the specified trigger conditions as preconditions.

**Components**:
1. **GrenadeInventoryComponent**: Tracks grenade count and type per enemy
2. **GrenadeTriggerSystem**: Monitors all 6 trigger conditions
3. **EnemyGrenadeActions**: New GOAP action classes
4. **EnemyGrenadeState**: AI state for grenade throwing animation/behavior

**Pros**:
- Fully integrated with existing AI architecture
- GOAP planner automatically chooses optimal timing
- Extensible for future grenade types or conditions

**Cons**:
- Most complex implementation
- Requires thorough testing of action interactions

### Solution 2: Hybrid State Machine + GOAP

**Approach**: Use a separate state machine for grenade decisions that feeds into GOAP.

**Components**:
1. **GrenadeDecisionMachine**: Separate FSM that evaluates grenade conditions
2. **ThrowGrenadeAction**: Single GOAP action that activates when FSM signals readiness
3. **GrenadeComponent**: Handles inventory and throwing mechanics

**Pros**:
- Cleaner separation of concerns
- Easier to debug grenade-specific behavior
- Less impact on existing GOAP complexity

**Cons**:
- Two decision systems may conflict
- Additional state management overhead

### Solution 3: Reactive Behavior Layer

**Approach**: Add a reactive layer that interrupts GOAP when grenade conditions are met.

**Components**:
1. **GrenadeReactiveSystem**: High-priority interrupt layer
2. **GrenadeThrowBehavior**: Self-contained throwing behavior
3. **Modified enemy.gd**: Check reactive conditions before GOAP planning

**Pros**:
- Grenades take immediate priority when conditions met
- Simpler implementation
- Clear "interrupt" semantics

**Cons**:
- Bypasses GOAP planning benefits
- May feel less "intelligent"

---

## Recommended Implementation Plan

### Phase 1: Foundation
1. Create `GrenadeInventoryComponent` to track grenades per enemy
2. Add `grenade_type` export to enemy scene for map-based configuration
3. Implement Building map difficulty-based grenade assignment

### Phase 2: Trigger System
1. Add world state variables for all 6 trigger conditions
2. Implement trigger detection logic in enemy.gd
3. Create unit tests for each trigger condition

### Phase 3: GOAP Actions
1. Create `PrepareGrenadeAction` with all trigger conditions as preconditions
2. Create `ThrowFragGrenadeAction` for offensive grenades
3. Create `ThrowFlashbangAction` for defensive grenades
4. Create `ThrowGrenadeAtSoundAction` for sound-based targeting
5. Create `DesperationGrenadeAction` for low-health scenarios

### Phase 4: Throwing Mechanics
1. Add grenade throwing animation/state to enemy
2. Implement trajectory calculation for AI throws
3. Create grenade aiming logic (lead prediction optional)

### Phase 5: Integration & Testing
1. Integration tests for grenade behavior
2. Playtest for balance
3. Adjust costs and trigger thresholds

---

## Existing Libraries and Resources

### Godot Assets
1. **[LimboAI](https://github.com/limbonaut/limboai)** - Behavior trees and state machines for Godot 4
2. **[Beehave](https://github.com/bitbrain/beehave)** - Behavior tree implementation for Godot

### Reference Implementations
1. **[jhlothamer/behavior_tree_enemy_ai_demo](https://github.com/jhlothamer/behavior_tree_enemy_ai_demo)** - Godot behavior tree demo
2. **[mtrebi/AI_FPS](https://github.com/mtrebi/AI_FPS)** - Unreal Engine FPS AI with grenade support

### Research Papers
1. ["Three States and a Plan: The AI of F.E.A.R."](https://www.gamedevs.org/uploads/three-states-plan-ai-of-fear.pdf) - Jeff Orkin, GDC 2006
2. ["Killzone's AI: Dynamic Procedural Combat Tactics"](http://cse.unl.edu/~choueiry/Documents/straatman_remco_killzone_ai.pdf) - Remco Straatman

---

## Summary

The issue requests a sophisticated grenade-throwing AI system with 6 distinct trigger conditions, integrated into the existing GOAP architecture. The codebase already provides strong foundations:

- **Complete GOAP system** with 16 actions
- **Grenade projectiles** (frag and flashbang)
- **Sound propagation** for hearing reload/empty sounds
- **Suppression mechanics** for detecting when under fire
- **Enemy memory system** for tracking suspected positions
- **Difficulty manager** for per-difficulty configuration

The recommended approach is **Solution 1: Full GOAP Integration**, as it maintains architectural consistency and leverages the existing A* planning for optimal grenade timing decisions.

Key implementation challenges:
1. Tracking kills observed by each enemy (requires death signal connection)
2. Sustained fire zone detection (requires audio event aggregation)
3. AI grenade trajectory calculation (existing player throw mechanics can be adapted)
4. Balancing grenade action costs against other combat actions
