# Grenade Trigger Conditions - Detailed Analysis

This document provides detailed specifications for each of the 6 trigger conditions for enemy grenade throwing.

## Trigger 1: Player Suppressed, Then Hidden for 6 Seconds

### Condition (Russian Original)
> когда игрок подавил врагов в поле зрения метателя или самого метателя, а затем скрылся из виду и не показывается 6 секунд

### Condition (English Translation)
> When the player suppressed enemies in the thrower's field of view or the thrower himself, then hid from sight and hasn't been visible for 6 seconds

### State Variables Required
```gdscript
var _was_suppressed: bool = false           # Was the enemy suppressed by player fire?
var _player_last_visible_time: float = 0.0  # When was the player last visible?
var _suppression_ended_time: float = 0.0    # When did suppression end?
```

### Logic Implementation
```gdscript
const HIDDEN_THRESHOLD: float = 6.0

func _should_trigger_suppression_grenade() -> bool:
    # Player was suppressing us or allies we could see
    if not _was_suppressed and not _saw_ally_suppressed:
        return false

    # Player is no longer visible
    if _can_see_player:
        return false

    # 6 seconds have passed since player hid
    var time_hidden := Time.get_ticks_msec() / 1000.0 - _player_last_visible_time
    return time_hidden >= HIDDEN_THRESHOLD
```

### Integration Points
- Connects to `threat_sphere` component for suppression detection
- Uses `vision_component` for player visibility tracking
- Requires tracking allies in field of view

---

## Trigger 2: Player Pursuing Suppressed Thrower

### Condition (Russian Original)
> когда игрок преследует подавленного метателя

### Condition (English Translation)
> When the player is pursuing a suppressed thrower

### State Variables Required
```gdscript
var _is_currently_suppressed: bool = false  # Currently under fire?
var _player_approach_direction: Vector2     # Direction player is moving
var _player_distance_decreasing: bool       # Is player getting closer?
```

### Logic Implementation
```gdscript
const PURSUIT_DISTANCE_THRESHOLD: float = 50.0  # Player must be getting 50px closer per second

func _should_trigger_pursuit_grenade() -> bool:
    # Must be suppressed
    if not _under_fire:
        return false

    # Player must be approaching
    if not _is_player_approaching():
        return false

    return true

func _is_player_approaching() -> bool:
    if not is_instance_valid(_player):
        return false

    var current_distance := global_position.distance_to(_player.global_position)
    var distance_delta := _previous_player_distance - current_distance
    _previous_player_distance = current_distance

    return distance_delta > PURSUIT_DISTANCE_THRESHOLD * get_physics_process_delta_time()
```

### Integration Points
- Uses existing `_under_fire` flag from suppression system
- Requires player position tracking (already exists)
- May need velocity estimation for player

---

## Trigger 3: Witnessed 2+ Player Kills

### Condition (Russian Original)
> когда игрок на глазах метателя убивает 2 и более врагов

### Condition (English Translation)
> When the player kills 2 or more enemies in front of the thrower

### State Variables Required
```gdscript
var _witnessed_kills_count: int = 0         # Number of ally deaths witnessed
var _kill_witness_reset_timer: float = 0.0  # Timer to reset kill count
```

### Logic Implementation
```gdscript
const KILL_THRESHOLD: int = 2
const KILL_WITNESS_WINDOW: float = 30.0  # Reset after 30 seconds of no kills

func _on_ally_died(ally_position: Vector2, killer_is_player: bool) -> void:
    if not killer_is_player:
        return

    # Check if we can see where the ally died
    if _can_see_position(ally_position):
        _witnessed_kills_count += 1
        _kill_witness_reset_timer = KILL_WITNESS_WINDOW

func _should_trigger_witness_grenade() -> bool:
    return _witnessed_kills_count >= KILL_THRESHOLD
```

### Integration Points
- Requires signal connection: `enemy.died_with_info` → `_on_ally_died()`
- Uses `vision_component.can_see_position()` for line-of-sight check
- May need to filter by "player" as killer source

---

## Trigger 4: Heard Reload/Empty Click (Player Not Visible)

### Condition (Russian Original)
> когда метатель слышит пустой магазин или начало перезарядки, но не видит игрока (будет кидать туда, от куда был звук)

### Condition (English Translation)
> When the thrower hears an empty magazine or reload start, but doesn't see the player (will throw toward the sound source)

### State Variables Required
```gdscript
var _heard_vulnerable_sound: bool = false     # Heard reload/empty click?
var _sound_source_position: Vector2           # Where did the sound come from?
var _vulnerable_sound_timestamp: float = 0.0  # When was the sound heard?
```

### Logic Implementation
```gdscript
const SOUND_VALIDITY_WINDOW: float = 5.0  # Sound position valid for 5 seconds

func on_sound_heard_with_intensity(
    sound_type: int,
    position: Vector2,
    source_type: int,
    source_node: Node2D,
    intensity: float
) -> void:
    # Only react to player sounds
    if source_type != SoundPropagation.SourceType.PLAYER:
        return

    # Check for reload or empty click
    if sound_type == SoundPropagation.SoundType.RELOAD or \
       sound_type == SoundPropagation.SoundType.EMPTY_CLICK:

        # Only trigger if we can't see the player
        if not _can_see_player:
            _heard_vulnerable_sound = true
            _sound_source_position = position
            _vulnerable_sound_timestamp = Time.get_ticks_msec() / 1000.0

func _should_trigger_sound_grenade() -> bool:
    if not _heard_vulnerable_sound:
        return false

    # Sound must be recent
    var sound_age := Time.get_ticks_msec() / 1000.0 - _vulnerable_sound_timestamp
    if sound_age > SOUND_VALIDITY_WINDOW:
        _heard_vulnerable_sound = false
        return false

    # Must still not see player
    return not _can_see_player

func _get_grenade_target_position() -> Vector2:
    return _sound_source_position
```

### Integration Points
- Uses existing `on_sound_heard_with_intensity()` callback
- Leverages `SoundPropagation` autoload constants
- Requires storing position for throw targeting

---

## Trigger 5: 10 Seconds of Sustained Fire in Small Zone

### Condition (Russian Original)
> если услышит не прекращающуюся стрельбу в течении 10 секунд (в смысле в течении 10 секунд будет звучать выстрел) в зоне размером одну шестую вьюпорта

### Condition (English Translation)
> If hears non-stop shooting for 10 seconds (meaning shots will be heard for 10 seconds) in a zone the size of 1/6 of the viewport

### State Variables Required
```gdscript
var _fire_zone_center: Vector2 = Vector2.ZERO    # Center of the fire zone
var _fire_zone_last_sound: float = 0.0           # Last gunshot in zone
var _fire_zone_total_duration: float = 0.0       # Total duration of fire in zone
var _fire_zone_valid: bool = false               # Is the fire zone valid?
```

### Logic Implementation
```gdscript
const SUSTAINED_FIRE_THRESHOLD: float = 10.0  # 10 seconds of continuous fire
const FIRE_GAP_TOLERANCE: float = 2.0         # Max 2 second gap between shots
const VIEWPORT_ZONE_FRACTION: float = 6.0     # Zone is 1/6 of viewport

func _get_zone_radius() -> float:
    var viewport_size := get_viewport().get_visible_rect().size
    var viewport_diagonal := sqrt(viewport_size.x ** 2 + viewport_size.y ** 2)
    return viewport_diagonal / VIEWPORT_ZONE_FRACTION / 2.0  # Radius = half of zone width

func _on_gunshot_heard(position: Vector2) -> void:
    var zone_radius := _get_zone_radius()
    var current_time := Time.get_ticks_msec() / 1000.0

    if _fire_zone_valid:
        var distance_to_zone := position.distance_to(_fire_zone_center)
        var time_since_last := current_time - _fire_zone_last_sound

        if distance_to_zone <= zone_radius and time_since_last <= FIRE_GAP_TOLERANCE:
            # Same zone, continuous fire
            _fire_zone_total_duration += time_since_last
            _fire_zone_last_sound = current_time
        else:
            # Different zone or gap too long, reset
            _start_new_fire_zone(position, current_time)
    else:
        _start_new_fire_zone(position, current_time)

func _start_new_fire_zone(position: Vector2, time: float) -> void:
    _fire_zone_center = position
    _fire_zone_last_sound = time
    _fire_zone_total_duration = 0.0
    _fire_zone_valid = true

func _should_trigger_sustained_fire_grenade() -> bool:
    if not _fire_zone_valid:
        return false

    # Check for timeout (fire stopped)
    var time_since_last := Time.get_ticks_msec() / 1000.0 - _fire_zone_last_sound
    if time_since_last > FIRE_GAP_TOLERANCE:
        _fire_zone_valid = false
        return false

    return _fire_zone_total_duration >= SUSTAINED_FIRE_THRESHOLD
```

### Integration Points
- Uses `on_sound_heard_with_intensity()` for GUNSHOT sounds
- Requires viewport size from `get_viewport()`
- Separate from reload/empty click handling

---

## Trigger 6: Low Health (1 HP or Less)

### Condition (Russian Original)
> когда у метателя осталось 1 hp и меньше

### Condition (English Translation)
> When the thrower has 1 HP or less remaining

### State Variables Required
```gdscript
# Already exists in enemy.gd
var _current_health: int = 0
```

### Logic Implementation
```gdscript
const DESPERATION_HEALTH_THRESHOLD: int = 1

func _should_trigger_desperation_grenade() -> bool:
    return _current_health <= DESPERATION_HEALTH_THRESHOLD and \
           _world_state.get("has_grenades", false)
```

### Integration Points
- Uses existing `_current_health` variable
- Simplest trigger condition
- Should have highest priority (lowest GOAP cost)

---

## Combined Trigger Evaluation

### Priority Order (Recommended)

1. **Desperation (Trigger 6)** - Cost: 0.1 - Immediate life-or-death response
2. **Sound-based (Trigger 4)** - Cost: 0.2 - Time-sensitive opportunity
3. **Pursuit (Trigger 2)** - Cost: 0.3 - Defensive response
4. **Witness kills (Trigger 3)** - Cost: 0.4 - Reactive response
5. **Sustained fire (Trigger 5)** - Cost: 0.5 - Zoning/denial
6. **Suppression hidden (Trigger 1)** - Cost: 0.6 - Flush out behavior

### World State Update Function

```gdscript
func _update_grenade_trigger_states() -> void:
    _world_state["trigger_1_suppression_hidden"] = _should_trigger_suppression_grenade()
    _world_state["trigger_2_pursuit"] = _should_trigger_pursuit_grenade()
    _world_state["trigger_3_witness_kills"] = _should_trigger_witness_grenade()
    _world_state["trigger_4_sound_based"] = _should_trigger_sound_grenade()
    _world_state["trigger_5_sustained_fire"] = _should_trigger_sustained_fire_grenade()
    _world_state["trigger_6_desperation"] = _should_trigger_desperation_grenade()

    # Combined flag for any trigger
    _world_state["ready_to_throw_grenade"] = \
        _world_state["trigger_1_suppression_hidden"] or \
        _world_state["trigger_2_pursuit"] or \
        _world_state["trigger_3_witness_kills"] or \
        _world_state["trigger_4_sound_based"] or \
        _world_state["trigger_5_sustained_fire"] or \
        _world_state["trigger_6_desperation"]
```
