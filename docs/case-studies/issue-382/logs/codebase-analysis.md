# Codebase Analysis for Issue #382

## Analyzed Files

### 1. scripts/components/enemy_grenade_component.gd

**Total size**: 365 lines

#### Purpose
Component extracted from enemy.gd to handle grenade throwing behavior. Manages 7 trigger conditions and throw execution.

#### Key Constants
```gdscript
const HIDDEN_THRESHOLD := 6.0             # Trigger 1: seconds hidden while suppressed
const PURSUIT_SPEED_THRESHOLD := 50.0     # Trigger 2: approach speed threshold
const KILL_THRESHOLD := 2                  # Trigger 3: witnessed kills count
const KILL_WITNESS_WINDOW := 30.0          # Trigger 3: time window for kills
const SOUND_VALIDITY_WINDOW := 5.0         # Trigger 4: sound memory duration
const SUSTAINED_FIRE_THRESHOLD := 10.0     # Trigger 5: seconds of sustained fire
const FIRE_GAP_TOLERANCE := 2.0            # Trigger 5: max gap between shots
const VIEWPORT_ZONE_FRACTION := 6.0        # Zone radius calculation
const DESPERATION_HEALTH_THRESHOLD := 1    # Trigger 6: HP for desperation throw
const SUSPICION_HIDDEN_TIME := 3.0         # Trigger 7: hidden time with suspicion
```

#### Configuration Variables
```gdscript
var grenade_count: int = 0
var grenade_scene: PackedScene = null
var enabled: bool = true
var throw_cooldown: float = 15.0
var max_throw_distance: float = 600.0
var min_throw_distance: float = 275.0    # Updated per Issue #375
var safety_margin: float = 50.0           # Safety margin for blast radius
var inaccuracy: float = 0.15              # ~8.6 degrees
var throw_delay: float = 0.4
var debug_logging: bool = false
```

#### Key Methods

**Trigger Check Methods**:
- `_t1()` - Suppression trigger (hidden after being fired at)
- `_t2(under_fire)` - Pursuit trigger (fast approach while under fire)
- `_t3()` - Witnessed kills trigger
- `_t4(can_see)` - Vulnerable sound trigger
- `_t5()` - Sustained fire trigger
- `_t6(health)` - Desperation trigger
- `_t7()` - Suspicion-based trigger (Issue #379)

**Core Methods**:
```gdscript
func is_ready(can_see: bool, under_fire: bool, health: int) -> bool
func get_target(...) -> Vector2
func try_throw(target: Vector2, is_alive: bool, is_stunned: bool, is_blinded: bool) -> bool
func _get_blast_radius() -> float
func _path_clear(target: Vector2) -> bool
func _execute_throw(target: Vector2, ...) -> void
```

**Missing for Issue #382**:
- No ally notification system
- No "player seen then hidden" trigger
- No post-throw behavior management

---

### 2. scripts/ai/enemy_actions.gd

**Total size**: 371 lines

#### Available Actions

| Action | Base Cost | Preconditions | Effects |
|--------|-----------|---------------|---------|
| SeekCoverAction | 2.0 | has_cover, !in_cover | in_cover, !under_fire |
| EngagePlayerAction | 1.0 | player_visible | player_engaged |
| FlankPlayerAction | 3.0 | !player_visible, !under_fire | at_flank_position, player_visible |
| PatrolAction | 1.0 | !player_visible, !under_fire | area_patrolled |
| StaySuppressedAction | 0.5 | under_fire, in_cover | waiting_for_safe |
| ReturnFireAction | 1.5 | player_visible, in_cover | player_engaged |
| FindCoverAction | 0.5 | !has_cover | has_cover |
| RetreatAction | 4.0 | health_low | in_cover, retreated |
| RetreatWithFireAction | 1.5 | under_fire | in_cover, is_retreating |
| PursuePlayerAction | 2.5 | !player_visible, !player_close | is_pursuing, player_close |
| AssaultPlayerAction | 100.0 | player_visible | is_assaulting, player_engaged |
| AttackDistractedPlayerAction | 0.1 | player_visible, player_distracted | player_engaged |
| AttackVulnerablePlayerAction | 0.1 | player_visible, player_close | player_engaged |
| PursueVulnerablePlayerAction | 0.2 | player_visible, !player_close | is_pursuing, player_close |
| InvestigateHighConfidenceAction | 1.5 | !player_visible, has_suspected_position, confidence_high | is_pursuing, player_visible |
| InvestigateMediumConfidenceAction | 2.5 | !player_visible, has_suspected_position, confidence_medium | is_pursuing |
| SearchLowConfidenceAction | 3.5 | !player_visible, has_suspected_position, confidence_low | area_patrolled |

#### Key Observation
**AssaultPlayerAction is disabled** with cost 1000.0 (per issue #169). The coordinated assault mechanic needs to be reconsidered for the new tactical grenade feature.

**Missing Actions for Issue #382**:
- EvacuateGrenadeZoneAction
- PrepareGrenadeThrowAction
- CoordinatedAssaultAction (re-enabled version)
- WaitForExplosionAction
- PostThrowApproachAction

---

### 3. scripts/ai/goap_planner.gd

**Total size**: 152 lines

#### Core Algorithm
Uses A* search to find optimal action sequences.

```gdscript
func plan(current_state: Dictionary, goal: Dictionary, agent: Node = null) -> Array[GOAPAction]
```

**Key Parameters**:
- `max_depth: int = 10` - Maximum planning depth
- `max_iterations := 1000` - Iteration limit

**Planning Steps**:
1. Check if goal already satisfied
2. A* search with open/closed sets
3. State hashing for duplicate detection
4. Action cost includes agent-specific evaluation

#### Extension Points
The planner can accept new actions via `add_action()`. New actions for tactical grenade coordination can be added without modifying the planner itself.

---

### 4. scripts/ai/enemy_memory.gd

**Total size**: 178 lines

#### Confidence Levels
```gdscript
const HIGH_CONFIDENCE_THRESHOLD: float = 0.8    # Direct pursuit
const MEDIUM_CONFIDENCE_THRESHOLD: float = 0.5  # Cautious approach
const LOW_CONFIDENCE_THRESHOLD: float = 0.3     # Search behavior
const LOST_TARGET_THRESHOLD: float = 0.05       # Target lost
```

#### Information Sources
- Direct visual contact: confidence = 1.0
- Sound (gunshot): confidence = 0.7
- Sound (reload/empty click): confidence = 0.6
- Intel from other enemies: source confidence * 0.9

#### Key Methods
```gdscript
func update_position(pos: Vector2, new_confidence: float) -> bool
func decay(delta: float, decay_rate: float = 0.1) -> void
func receive_intel(other: EnemyMemory, confidence_factor: float = 0.9) -> bool
func get_behavior_mode() -> String
```

#### Potential Extension
`receive_intel()` already exists for inter-enemy communication. This could be extended to include grenade throw warnings.

---

### 5. scripts/components/cover_component.gd

**Total size**: 247 lines

#### Configuration
```gdscript
@export var cover_check_count: int = 16      # Raycast directions
@export var cover_check_distance: float = 300.0
@export var min_cover_distance: float = 50.0
@export var pursuit_min_progress_fraction: float = 0.10
@export var same_obstacle_penalty: float = 4.0
```

#### Key Methods
```gdscript
func find_cover() -> void              # Find defensive cover
func find_pursuit_cover(target_pos: Vector2) -> Vector2  # Cover closer to target
func is_in_cover(tolerance: float = 30.0) -> bool
func _is_protected_from_threat(pos: Vector2) -> bool
```

#### Potential Extension
The cover-finding logic could be extended to find:
1. Cover that protects from a specific point (grenade impact location)
2. Cover that protects from rays emanating from a position

---

### 6. scripts/objects/enemy.gd (Partial - grenade-related sections)

**Total size**: ~5000 lines (CI limit)

#### Grenade Configuration
```gdscript
@export var grenade_count: int = 0
@export var grenade_scene: PackedScene
@export var enable_grenade_throwing: bool = true
@export var grenade_throw_cooldown: float = 15.0
@export var grenade_max_throw_distance: float = 600.0
@export var grenade_min_throw_distance: float = 275.0
@export var grenade_safety_margin: float = 50.0
@export var grenade_inaccuracy: float = 0.15
@export var grenade_throw_delay: float = 0.4
@export var grenade_debug_logging: bool = false
```

#### Grenade Signal
```gdscript
signal grenade_thrown(grenade: Node, target_position: Vector2)
```

#### GOAP World State (grenade-related)
```gdscript
_goap_world_state["has_grenades"] = g.grenades_remaining > 0
_goap_world_state["grenades_remaining"] = g.grenades_remaining
_goap_world_state["ready_to_throw_grenade"] = g.is_ready(...)
```

#### Key Integration Points
- `_update_grenade_triggers(delta)` - Called every physics frame
- `_on_gunshot_heard_for_grenade(position)` - Gunshot notification
- `_on_vulnerable_sound_heard_for_grenade(position)` - Sound notification
- `try_throw_grenade() -> bool` - Execute throw

---

### 7. scripts/projectiles/frag_grenade.gd

**Total size**: 395 lines

#### Key Properties
```gdscript
@export var effect_radius: float = 225.0
@export var shrapnel_count: int = 4
@export var explosion_damage: int = 99
@export var shrapnel_spread_deviation: float = 20.0
```

#### Behavior
- Impact-triggered explosion (no timer)
- Spawns 4 shrapnel pieces
- Deals 99 damage to all enemies in blast zone
- Also damages player in blast zone

---

### 8. scripts/projectiles/grenade_base.gd

**Total size**: 425 lines

#### Physics Properties
```gdscript
@export var fuse_time: float = 4.0
@export var max_throw_speed: float = 850.0
@export var min_throw_speed: float = 100.0
@export var ground_friction: float = 300.0
@export var wall_bounce: float = 0.4
```

#### Key Methods
```gdscript
func activate_timer() -> void
func throw_grenade(direction: Vector2, drag_distance: float) -> void
func throw_grenade_velocity_based(mouse_velocity: Vector2, swing_distance: float) -> void
func is_in_effect_radius(pos: Vector2) -> bool
func get_time_remaining() -> float
```

---

## Architecture Patterns Identified

### 1. Component Pattern
The project uses components (e.g., `EnemyGrenadeComponent`, `CoverComponent`) to separate concerns. New tactical grenade logic should follow this pattern.

### 2. GOAP Pattern
AI decision-making uses GOAP. New behaviors should be implemented as GOAP actions.

### 3. Signal Pattern
Inter-object communication uses signals (e.g., `grenade_thrown`). Ally notification should use signals.

### 4. Group Pattern
Enemies are in "enemies" group. This can be used for broadcasting grenade warnings.

---

## Recommended Architecture Extensions

### New Components

1. **TacticalGrenadeCoordinator** (Autoload)
   ```gdscript
   extends Node

   signal grenade_warning(thrower: Node, target: Vector2, blast_radius: float)
   signal grenade_exploded(position: Vector2)
   signal assault_begin(passage_direction: Vector2)

   func announce_throw(thrower: Node, target: Vector2, blast_radius: float)
   func get_enemies_in_zone(center: Vector2, radius: float) -> Array
   func calculate_evacuation_direction(enemy: Node, blast_center: Vector2) -> Vector2
   ```

2. **EnemyEvacuationState** (extend AI states)
   ```gdscript
   extends EnemyState

   var evacuation_target: Vector2
   var waiting_for_explosion: bool = false
   var assault_on_explosion: bool = false
   ```

### New GOAP Actions

1. **EvacuateGrenadeZoneAction**
   - Preconditions: `in_grenade_zone = true`
   - Effects: `in_safe_zone = true, waiting_for_assault = true`
   - Cost: 0.0 (highest priority)

2. **PrepareGrenadeThrowAction**
   - Preconditions: `has_grenades = true, player_seen_then_hidden = true`
   - Effects: `ready_to_throw = true`

3. **WaitForExplosionAction**
   - Preconditions: `waiting_for_assault = true`
   - Effects: (none until explosion)

4. **PostExplosionAssaultAction**
   - Preconditions: `grenade_exploded = true, waiting_for_assault = true`
   - Effects: `is_assaulting = true`

### Extended World State

```gdscript
# New world state keys
_goap_world_state["player_seen_then_hidden"] = false
_goap_world_state["in_grenade_zone"] = false
_goap_world_state["waiting_for_assault"] = false
_goap_world_state["grenade_exploded"] = false
_goap_world_state["has_evacuation_target"] = false
```

---

## Code Line Budget Estimation

Current enemy.gd: ~5000 lines (at limit)

**Solution**: Extract new features to separate components:
- TacticalGrenadeCoordinator: ~150 lines (new autoload)
- EnemyEvacuationComponent: ~200 lines (new component)
- Extended EnemyGrenadeComponent: +50 lines
- New GOAP actions: +100 lines (in enemy_actions.gd)
- Enemy.gd modifications: +20 lines (signals, integration)

This approach stays within the line limit while adding the required functionality.
