# Proposed Solutions - Issue #273

## Feature: Tactical Grenade Throwing for Enemies

Based on the issue requirements and codebase analysis, here are the proposed technical solutions.

## Solution Overview

The implementation requires several interconnected components:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        GRENADE THROWING SYSTEM                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────┐    ┌──────────────────┐    ┌───────────────────┐          │
│  │ Trigger      │───▶│ Throw Mode       │───▶│ Ally Notification │          │
│  │ Conditions   │    │ State Machine    │    │ System            │          │
│  └──────────────┘    └────────┬─────────┘    └─────────┬─────────┘          │
│                               │                        │                     │
│                               ▼                        ▼                     │
│                      ┌────────────────┐       ┌───────────────────┐          │
│                      │ Throw Execution│       │ Ally Evacuation   │          │
│                      │ (Aiming, Cover)│       │ (Clear blast zone)│          │
│                      └────────┬───────┘       └───────────────────┘          │
│                               │                                              │
│                               ▼                                              │
│                      ┌────────────────┐       ┌───────────────────┐          │
│                      │ Post-Throw     │──────▶│ Coordinated       │          │
│                      │ Behavior       │       │ Assault           │          │
│                      └────────────────┘       └───────────────────┘          │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Component 1: Grenade Inventory System

### File: `scripts/components/grenade_inventory.gd`

```gdscript
class_name GrenadeInventory
extends Node

# Grenade types
enum GrenadeType { NONE, OFFENSIVE, FLASHBANG, SMOKE }

# Inventory
@export var offensive_grenades: int = 0
@export var flashbang_grenades: int = 0
@export var smoke_grenades: int = 0

# Configuration
@export var throw_range: float = 400.0  # Maximum throw distance
@export var throw_accuracy_deviation: float = 5.0  # Max degrees deviation (±5°)

signal grenade_count_changed(type: GrenadeType, count: int)
signal grenade_thrown(type: GrenadeType, target_position: Vector2)

func has_grenade(type: GrenadeType = GrenadeType.NONE) -> bool:
    if type == GrenadeType.NONE:
        return offensive_grenades > 0 or flashbang_grenades > 0
    match type:
        GrenadeType.OFFENSIVE:
            return offensive_grenades > 0
        GrenadeType.FLASHBANG:
            return flashbang_grenades > 0
        GrenadeType.SMOKE:
            return smoke_grenades > 0
    return false

func use_grenade(type: GrenadeType) -> bool:
    match type:
        GrenadeType.OFFENSIVE:
            if offensive_grenades > 0:
                offensive_grenades -= 1
                grenade_count_changed.emit(type, offensive_grenades)
                return true
        GrenadeType.FLASHBANG:
            if flashbang_grenades > 0:
                flashbang_grenades -= 1
                grenade_count_changed.emit(type, flashbang_grenades)
                return true
    return false

func get_best_grenade_for_situation(player_in_cover: bool, nearby_enemies: int) -> GrenadeType:
    # Prefer offensive grenades when player is behind cover
    if player_in_cover and offensive_grenades > 0:
        return GrenadeType.OFFENSIVE
    # Use flashbang if allies are near target
    if nearby_enemies > 0 and flashbang_grenades > 0:
        return GrenadeType.FLASHBANG
    # Default to offensive
    if offensive_grenades > 0:
        return GrenadeType.OFFENSIVE
    if flashbang_grenades > 0:
        return GrenadeType.FLASHBANG
    return GrenadeType.NONE
```

## Component 2: Throw Mode Trigger Conditions

### File: `scripts/ai/grenade_trigger_evaluator.gd`

```gdscript
class_name GrenadeTriggerEvaluator
extends Node

# Trigger condition tracking
var player_hidden_timer: float = 0.0
var kills_witnessed: int = 0
var last_kill_time: float = 0.0
var sustained_fire_timer: float = 0.0
var sustained_fire_position: Vector2 = Vector2.ZERO

# Configuration from issue requirements
const PLAYER_HIDDEN_THRESHOLD: float = 6.0  # seconds
const KILLS_TO_TRIGGER: int = 2
const KILL_MEMORY_DURATION: float = 5.0  # seconds to remember kills
const SUSTAINED_FIRE_DURATION: float = 10.0  # seconds
const VIEWPORT_FRACTION: float = 1.0 / 6.0  # 1/6 viewport zone

# References
var enemy: Node2D
var vision_component: Node
var health_component: Node

signal should_throw_grenade(reason: String, target_position: Vector2)

func _ready():
    enemy = get_parent()
    vision_component = enemy.get_node_or_null("VisionComponent")
    health_component = enemy.get_node_or_null("HealthComponent")

func _process(delta: float):
    _update_player_hidden_timer(delta)
    _update_sustained_fire_timer(delta)
    _decay_kill_memory(delta)
    _check_trigger_conditions()

func _update_player_hidden_timer(delta: float):
    if vision_component and not vision_component.can_see_target():
        player_hidden_timer += delta
    else:
        player_hidden_timer = 0.0

func _check_trigger_conditions():
    # Condition 1: Player suppressed then hidden for 6s
    if _check_suppression_and_hidden():
        should_throw_grenade.emit("player_suppressed_and_hidden", _get_last_known_position())
        return

    # Condition 2: Player chasing suppressed thrower
    if _check_being_chased_while_suppressed():
        should_throw_grenade.emit("being_chased_suppressed", _get_player_position())
        return

    # Condition 3: Witnessed 2+ kills
    if kills_witnessed >= KILLS_TO_TRIGGER:
        should_throw_grenade.emit("witnessed_multiple_kills", _get_player_position())
        kills_witnessed = 0  # Reset after triggering
        return

    # Condition 4: Heard reload but can't see player
    # (Handled by signal from sound_propagation)

    # Condition 5: Sustained fire for 10s
    if sustained_fire_timer >= SUSTAINED_FIRE_DURATION:
        should_throw_grenade.emit("sustained_fire", sustained_fire_position)
        sustained_fire_timer = 0.0
        return

    # Condition 6: Low HP (1 or less)
    if health_component and health_component.current_health <= 1:
        should_throw_grenade.emit("low_hp_desperation", _get_player_position())
        return

func on_enemy_killed_nearby(killed_position: Vector2):
    # Check if within line of sight
    if vision_component and _is_position_visible(killed_position):
        kills_witnessed += 1
        last_kill_time = Time.get_ticks_msec() / 1000.0

func on_reload_sound_heard(sound_position: Vector2):
    if vision_component and not vision_component.can_see_target():
        should_throw_grenade.emit("heard_reload", sound_position)

func on_gunfire_heard(sound_position: Vector2):
    var viewport_size = get_viewport().get_visible_rect().size
    var zone_radius = min(viewport_size.x, viewport_size.y) * VIEWPORT_FRACTION

    if sustained_fire_position.distance_to(sound_position) < zone_radius:
        # Continue tracking in same zone
        sustained_fire_timer += get_process_delta_time()
    else:
        # New zone, reset timer
        sustained_fire_position = sound_position
        sustained_fire_timer = get_process_delta_time()
```

## Component 3: Ally Notification System

### File: `scripts/ai/grenade_coordination.gd`

```gdscript
class_name GrenadeCoordination
extends Node

# Notification system for coordinated grenade tactics

signal grenade_incoming(thrower: Node2D, target_position: Vector2, blast_radius: float)
signal evacuation_complete(evacuee: Node2D)
signal assault_signal(passage_direction: Vector2)

static var active_throw: Dictionary = {}  # Singleton pattern for coordination

func notify_grenade_throw(thrower: Node2D, target_position: Vector2, blast_radius: float):
    active_throw = {
        "thrower": thrower,
        "target": target_position,
        "radius": blast_radius,
        "evacuated_allies": []
    }

    # Find all allies in danger zone
    var allies = get_tree().get_nodes_in_group("enemies")
    for ally in allies:
        if ally == thrower:
            continue

        var ally_pos = ally.global_position
        var distance_to_target = ally_pos.distance_to(target_position)
        var distance_to_trajectory = _point_to_line_distance(
            ally_pos,
            thrower.global_position,
            target_position
        )

        # Check if in blast zone or throw trajectory
        if distance_to_target < blast_radius * 1.2 or distance_to_trajectory < 50:
            _order_evacuation(ally, target_position, blast_radius)

func _order_evacuation(ally: Node2D, danger_center: Vector2, danger_radius: float):
    # Find closest safe direction
    var evacuation_dir = (ally.global_position - danger_center).normalized()
    var evacuation_target = ally.global_position + evacuation_dir * (danger_radius + 100)

    # Check if ally has cover component
    var cover_comp = ally.get_node_or_null("CoverComponent")
    if cover_comp:
        cover_comp.set_threat_position(danger_center)
        var cover_pos = cover_comp.find_cover()
        if cover_pos != Vector2.ZERO:
            evacuation_target = cover_pos

    # Signal ally to evacuate
    if ally.has_method("evacuate_from_grenade"):
        ally.evacuate_from_grenade(evacuation_target, danger_center)
        active_throw["evacuated_allies"].append(ally)

func all_allies_evacuated() -> bool:
    if active_throw.is_empty():
        return true

    for ally in active_throw["evacuated_allies"]:
        if not ally.has_method("is_safe_from_grenade"):
            continue
        if not ally.is_safe_from_grenade():
            return false
    return true

func signal_post_explosion_assault(passage_direction: Vector2):
    assault_signal.emit(passage_direction)

    # All evacuated allies transition to assault
    for ally in active_throw.get("evacuated_allies", []):
        if ally.has_method("begin_coordinated_assault"):
            ally.begin_coordinated_assault(passage_direction)

    active_throw.clear()

func _point_to_line_distance(point: Vector2, line_start: Vector2, line_end: Vector2) -> float:
    var line_vec = line_end - line_start
    var point_vec = point - line_start
    var line_len = line_vec.length()

    if line_len == 0:
        return point_vec.length()

    var t = max(0, min(1, point_vec.dot(line_vec) / (line_len * line_len)))
    var projection = line_start + t * line_vec
    return point.distance_to(projection)
```

## Component 4: GOAP Action for Grenade Throwing

### Add to: `scripts/ai/enemy_actions.gd`

```gdscript
class ThrowGrenadeAction extends GOAPAction:
    func _init():
        action_name = "throw_grenade"
        # Preconditions
        preconditions["has_grenades"] = true
        preconditions["player_in_range"] = true
        preconditions["allies_notified"] = true
        # Effects
        effects["area_cleared"] = true
        effects["player_flushed_from_cover"] = true

    func get_cost(world_state: Dictionary) -> float:
        var base_cost = 4.0  # Higher than shooting, lower than flanking

        # Reduce cost if player is in cover
        if world_state.get("player_in_cover", false):
            base_cost -= 1.5

        # Reduce cost if triggered by specific conditions
        if world_state.get("grenade_trigger_active", false):
            base_cost -= 2.0

        # Increase cost if friendlies nearby target
        var friendlies_in_blast = world_state.get("friendlies_in_blast_zone", 0)
        base_cost += friendlies_in_blast * 3.0

        return max(0.5, base_cost)

    func is_valid(world_state: Dictionary) -> bool:
        return world_state.get("has_grenades", false) and \
               world_state.get("can_throw_safely", false)
```

## Component 5: Throw Mode State for Enemy

### Add state to: `scripts/ai/states/throw_grenade_state.gd`

```gdscript
class_name ThrowGrenadeState
extends EnemyState

enum ThrowPhase {
    NOTIFYING_ALLIES,
    WAITING_FOR_EVACUATION,
    MOVING_TO_POSITION,
    AIMING,
    THROWING,
    SEEKING_COVER,
    WAITING_FOR_EXPLOSION,
    ASSAULTING
}

var current_phase: ThrowPhase = ThrowPhase.NOTIFYING_ALLIES
var target_position: Vector2
var throw_position: Vector2
var grenade_type: int
var thrown_grenade: Node2D
var assault_direction: Vector2

const MAX_THROW_DEVIATION_DEGREES: float = 5.0
const THROW_RANGE: float = 400.0

func enter():
    current_phase = ThrowPhase.NOTIFYING_ALLIES
    _notify_allies()

func _notify_allies():
    var coordination = enemy.get_node_or_null("GrenadeCoordination")
    if coordination:
        var blast_radius = _get_blast_radius_for_type(grenade_type)
        coordination.notify_grenade_throw(enemy, target_position, blast_radius)
    current_phase = ThrowPhase.WAITING_FOR_EVACUATION

func update(delta: float):
    match current_phase:
        ThrowPhase.WAITING_FOR_EVACUATION:
            _wait_for_evacuation()
        ThrowPhase.MOVING_TO_POSITION:
            _move_to_throw_position()
        ThrowPhase.AIMING:
            _aim_at_target()
        ThrowPhase.THROWING:
            _execute_throw()
        ThrowPhase.SEEKING_COVER:
            _seek_post_throw_cover()
        ThrowPhase.WAITING_FOR_EXPLOSION:
            _wait_for_explosion()
        ThrowPhase.ASSAULTING:
            _assault_through_passage()

func _wait_for_evacuation():
    var coordination = enemy.get_node_or_null("GrenadeCoordination")
    if coordination and coordination.all_allies_evacuated():
        current_phase = ThrowPhase.MOVING_TO_POSITION
        _calculate_throw_position()

func _calculate_throw_position():
    # Find position that:
    # 1. Is within throw range of target
    # 2. Is behind cover from player (ignoring one obstacle)
    var cover_comp = enemy.get_node_or_null("CoverComponent")
    if cover_comp:
        throw_position = cover_comp.find_grenade_throw_position(
            target_position,
            THROW_RANGE,
            true  # ignore_one_obstacle
        )
    else:
        throw_position = enemy.global_position

func _execute_throw():
    # Apply random deviation within ±5 degrees
    var deviation = randf_range(-MAX_THROW_DEVIATION_DEGREES, MAX_THROW_DEVIATION_DEGREES)
    var throw_direction = (target_position - enemy.global_position).normalized()
    throw_direction = throw_direction.rotated(deg_to_rad(deviation))

    var actual_target = enemy.global_position + throw_direction * target_position.distance_to(enemy.global_position)

    # Spawn and throw grenade
    var inventory = enemy.get_node_or_null("GrenadeInventory")
    if inventory and inventory.use_grenade(grenade_type):
        thrown_grenade = _spawn_grenade(actual_target)
        assault_direction = throw_direction
        current_phase = ThrowPhase.SEEKING_COVER

func _seek_post_throw_cover():
    # Find cover that protects from grenade blast
    var cover_comp = enemy.get_node_or_null("CoverComponent")
    if cover_comp:
        cover_comp.set_threat_position(target_position)
        var safe_position = cover_comp.find_cover()
        if safe_position != Vector2.ZERO:
            enemy.move_to(safe_position)
            if enemy.global_position.distance_to(safe_position) < 20:
                current_phase = ThrowPhase.WAITING_FOR_EXPLOSION
                return

    # If no cover, just wait
    current_phase = ThrowPhase.WAITING_FOR_EXPLOSION

func _wait_for_explosion():
    if thrown_grenade == null or not is_instance_valid(thrown_grenade):
        # Grenade exploded
        current_phase = ThrowPhase.ASSAULTING
        _signal_coordinated_assault()

func _signal_coordinated_assault():
    var coordination = enemy.get_node_or_null("GrenadeCoordination")
    if coordination:
        coordination.signal_post_explosion_assault(assault_direction)

func _assault_through_passage():
    # Move toward where grenade was thrown
    enemy.move_to(target_position)
    # Aim at target location
    enemy.look_at(target_position)
    # Transition to combat state
    if enemy.global_position.distance_to(target_position) < 50:
        transition_to("combat")
```

## Integration Points

### 1. Modify `scripts/objects/enemy.gd`

Add to the enemy script:
- Grenade inventory component reference
- Grenade trigger evaluator reference
- Grenade coordination reference
- `THROWING_GRENADE` state to the state enum
- Methods: `evacuate_from_grenade()`, `is_safe_from_grenade()`, `begin_coordinated_assault()`

### 2. Modify `scripts/autoload/sound_propagation.gd`

Add signals for:
- Reload sound events (to trigger grenade throw)
- Empty magazine sound events

### 3. Modify Building Level Map

In `scenes/levels/building_level.tscn`:
- Find enemy in "main hall" room
- Add GrenadeInventory component
- Set `offensive_grenades = 2`

## Implementation Priority

1. **Phase 1 - Core Components** (Required for basic functionality)
   - GrenadeInventory component
   - ThrowGrenadeState
   - Basic throw mechanics

2. **Phase 2 - Trigger System** (Required for tactical behavior)
   - GrenadeTriggerEvaluator
   - Sound-based triggers
   - HP-based trigger

3. **Phase 3 - Coordination** (Required for squad tactics)
   - GrenadeCoordination
   - Ally notification/evacuation
   - Coordinated assault

4. **Phase 4 - GOAP Integration** (Optional enhancement)
   - ThrowGrenadeAction
   - Cost evaluation
   - Planning integration

## Testing Recommendations

1. **Unit tests for trigger conditions**
   - Test each of the 6 trigger conditions independently
   - Test trigger priority/interaction

2. **Integration tests for coordination**
   - Test ally evacuation timing
   - Test assault signal propagation

3. **Manual playtesting scenarios**
   - Player hides behind cover for 6+ seconds
   - Player kills multiple enemies in view
   - Player reloads while enemy has grenades
   - Low HP enemy with grenades
