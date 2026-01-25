class_name GrenadeThrowing
extends Node
## Enemy grenade throwing component (Issue #363).
##
## Handles all grenade throwing logic including trigger condition detection,
## GOAP world state integration, and grenade execution.
##
## Implements 6 trigger conditions based on F.E.A.R. AI principles:
## 1. Suppression Hidden: Player suppressed enemy, then hid for 6+ seconds
## 2. Pursuit Defense: Player is pursuing a suppressed thrower
## 3. Witness Kills: Enemy witnessed 2+ player kills
## 4. Sound-Based: Heard reload/empty click without seeing player
## 5. Sustained Fire: 10 seconds of continuous fire in 1/6 viewport zone
## 6. Desperation: Enemy at 1 HP or less

# ============================================================================
# Export Configuration
# ============================================================================

## Number of grenades this enemy carries. Set by DifficultyManager or per-enemy override.
## Default 0 means no grenades unless configured by difficulty/map settings.
@export var grenade_count: int = 0

## Grenade scene to instantiate when throwing.
@export var grenade_scene: PackedScene

## Enable/disable grenade throwing behavior.
@export var enabled: bool = true

## Minimum cooldown between grenade throws (prevents spam).
@export var throw_cooldown: float = 15.0

## Maximum throw distance for grenades (pixels).
@export var max_throw_distance: float = 600.0

## Minimum throw distance for grenades (pixels) - prevents point-blank throws.
@export var min_throw_distance: float = 150.0

## Inaccuracy spread when throwing grenades (radians).
@export var inaccuracy: float = 0.15

## Enable grenade debug logging.
@export var debug_logging: bool = false

## Delay before throwing grenade (seconds) - allows animation/telegraph.
@export var throw_delay: float = 0.4

# ============================================================================
# Signals
# ============================================================================

## Emitted when a grenade is thrown.
signal grenade_thrown(grenade: Node, target_position: Vector2)

# ============================================================================
# Constants (Trigger Thresholds)
# ============================================================================

const HIDDEN_THRESHOLD: float = 6.0  ## Seconds player must be hidden (Trigger 1)
const PURSUIT_SPEED_THRESHOLD: float = 50.0  ## Player approach speed (Trigger 2)
const KILL_THRESHOLD: int = 2  ## Kills to witness (Trigger 3)
const KILL_WITNESS_WINDOW: float = 30.0  ## Window to reset kill count (Trigger 3)
const SOUND_VALIDITY_WINDOW: float = 5.0  ## How long sound position is valid (Trigger 4)
const SUSTAINED_FIRE_THRESHOLD: float = 10.0  ## Seconds of sustained fire (Trigger 5)
const FIRE_GAP_TOLERANCE: float = 2.0  ## Max gap between shots (Trigger 5)
const VIEWPORT_ZONE_FRACTION: float = 6.0  ## Zone is 1/6 of viewport (Trigger 5)
const DESPERATION_HEALTH_THRESHOLD: int = 1  ## HP threshold (Trigger 6)

# ============================================================================
# Internal State
# ============================================================================

## Parent enemy node reference.
var _parent: Node2D = null

## Remaining grenades.
var _grenades_remaining: int = 0

## Cooldown timer.
var _cooldown_timer: float = 0.0

## Currently executing a throw.
var _is_throwing: bool = false

# Trigger 1 (Suppression Hidden) state
var _player_hidden_timer: float = 0.0
var _was_suppressed_before_hidden: bool = false

# Trigger 2 (Pursuit) state
var _saw_ally_suppressed: bool = false
var _previous_player_distance: float = 0.0

# Trigger 3 (Witness Kills) state
var _witnessed_kills_count: int = 0
var _kill_witness_reset_timer: float = 0.0

# Trigger 4 (Sound-Based) state
var _heard_vulnerable_sound: bool = false
var _vulnerable_sound_position: Vector2 = Vector2.ZERO
var _vulnerable_sound_timestamp: float = 0.0

# Trigger 5 (Sustained Fire) state
var _fire_zone_center: Vector2 = Vector2.ZERO
var _fire_zone_last_sound: float = 0.0
var _fire_zone_total_duration: float = 0.0
var _fire_zone_valid: bool = false

# External references (set by parent)
var _player: Node2D = null
var _can_see_player: bool = false
var _under_fire: bool = false
var _is_alive: bool = true
var _is_stunned: bool = false
var _is_blinded: bool = false
var _current_health: int = 100
var _last_known_player_position: Vector2 = Vector2.ZERO
var _memory: Node = null  # AI Memory component
var _goap_world_state: Dictionary = {}

## Logging callback (set by parent for file logging).
var _log_to_file_callback: Callable

# ============================================================================
# Lifecycle
# ============================================================================

func _ready() -> void:
	_parent = get_parent() as Node2D


## Initialize the grenade system. Called by parent after setting references.
func initialize() -> void:
	_cooldown_timer = 0.0
	_is_throwing = false
	_reset_trigger_states()

	# Determine grenade count
	if grenade_count > 0:
		_grenades_remaining = grenade_count
		_log("Using export grenade_count: %d" % grenade_count)
	else:
		# Query DifficultyManager
		var map_name := _get_current_map_name()
		if DifficultyManager.are_enemy_grenades_enabled(map_name):
			_grenades_remaining = DifficultyManager.get_enemy_grenade_count(map_name)
			if _grenades_remaining > 0:
				_log("DifficultyManager assigned %d grenades (map: %s)" % [_grenades_remaining, map_name])
		else:
			_grenades_remaining = 0

	# Load grenade scene if needed
	if grenade_scene == null and _grenades_remaining > 0:
		var map_name := _get_current_map_name()
		var scene_path := DifficultyManager.get_enemy_grenade_scene_path(map_name)
		grenade_scene = load(scene_path)
		if grenade_scene == null:
			grenade_scene = preload("res://scenes/projectiles/FragGrenade.tscn")
			push_warning("[GrenadeThrowing] Failed to load scene: %s, using default" % scene_path)

	if _grenades_remaining > 0:
		_log("Grenade system initialized: %d grenades" % _grenades_remaining)


func _reset_trigger_states() -> void:
	_player_hidden_timer = 0.0
	_was_suppressed_before_hidden = false
	_saw_ally_suppressed = false
	_previous_player_distance = 0.0
	_witnessed_kills_count = 0
	_kill_witness_reset_timer = 0.0
	_heard_vulnerable_sound = false
	_vulnerable_sound_position = Vector2.ZERO
	_vulnerable_sound_timestamp = 0.0
	_fire_zone_center = Vector2.ZERO
	_fire_zone_last_sound = 0.0
	_fire_zone_total_duration = 0.0
	_fire_zone_valid = false


# ============================================================================
# External State Updates (called by parent)
# ============================================================================

## Update player reference.
func set_player(player: Node2D) -> void:
	_player = player


## Update visibility state.
func set_can_see_player(can_see: bool) -> void:
	_can_see_player = can_see


## Update under fire state.
func set_under_fire(under_fire: bool) -> void:
	_under_fire = under_fire


## Update alive state.
func set_is_alive(is_alive: bool) -> void:
	_is_alive = is_alive


## Update stunned state.
func set_is_stunned(is_stunned: bool) -> void:
	_is_stunned = is_stunned


## Update blinded state.
func set_is_blinded(is_blinded: bool) -> void:
	_is_blinded = is_blinded


## Update current health.
func set_current_health(health: int) -> void:
	_current_health = health


## Update last known player position.
func set_last_known_player_position(pos: Vector2) -> void:
	_last_known_player_position = pos


## Set AI memory reference.
func set_memory(memory: Node) -> void:
	_memory = memory


## Set GOAP world state reference.
func set_goap_world_state(world_state: Dictionary) -> void:
	_goap_world_state = world_state


## Set logging callback for file logging.
func set_log_callback(callback: Callable) -> void:
	_log_to_file_callback = callback


# ============================================================================
# Update Loop (called by parent in _physics_process)
# ============================================================================

## Update grenade trigger conditions. Called every physics frame.
func update(delta: float) -> void:
	if not enabled or _grenades_remaining <= 0:
		return

	# Update cooldown timer
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta

	# Update kill witness reset timer (Trigger 3)
	if _kill_witness_reset_timer > 0.0:
		_kill_witness_reset_timer -= delta
		if _kill_witness_reset_timer <= 0.0:
			_witnessed_kills_count = 0

	# Update trigger conditions
	_update_trigger_suppression_hidden(delta)
	_update_trigger_pursuit(delta)
	_update_trigger_sustained_fire(delta)

	# Update GOAP world state
	_update_world_state()


# ============================================================================
# Trigger Condition Updates
# ============================================================================

func _update_trigger_suppression_hidden(delta: float) -> void:
	# Check if currently suppressed
	if _under_fire:
		_was_suppressed_before_hidden = true

	# If player was suppressing but is now hidden
	if _was_suppressed_before_hidden and not _can_see_player:
		_player_hidden_timer += delta
	else:
		if _can_see_player:
			_player_hidden_timer = 0.0
			_was_suppressed_before_hidden = false


func _update_trigger_pursuit(delta: float) -> void:
	if _player == null or not _parent:
		return

	var current_distance := _parent.global_position.distance_to(_player.global_position)

	if _previous_player_distance > 0.0:
		var distance_delta := _previous_player_distance - current_distance
		var approach_speed := distance_delta / delta if delta > 0 else 0.0
		_goap_world_state["player_approaching_speed"] = approach_speed

	_previous_player_distance = current_distance


func _update_trigger_sustained_fire(delta: float) -> void:
	if not _fire_zone_valid:
		return

	var current_time := Time.get_ticks_msec() / 1000.0
	var time_since_last := current_time - _fire_zone_last_sound

	if time_since_last > FIRE_GAP_TOLERANCE:
		_fire_zone_valid = false
		_fire_zone_total_duration = 0.0


# ============================================================================
# Sound Handling (called by parent on sound events)
# ============================================================================

## Handle gunshot sounds for sustained fire tracking (Trigger 5).
func on_gunshot_heard(position: Vector2) -> void:
	if not enabled or _grenades_remaining <= 0:
		return

	var zone_radius := _get_zone_radius()
	var current_time := Time.get_ticks_msec() / 1000.0

	if _fire_zone_valid:
		var distance_to_zone := position.distance_to(_fire_zone_center)
		var time_since_last := current_time - _fire_zone_last_sound

		if distance_to_zone <= zone_radius and time_since_last <= FIRE_GAP_TOLERANCE:
			_fire_zone_total_duration += time_since_last
			_fire_zone_last_sound = current_time

			if debug_logging:
				_log("Sustained fire: %.1fs in zone at %s" % [_fire_zone_total_duration, position])
		else:
			_start_new_fire_zone(position, current_time)
	else:
		_start_new_fire_zone(position, current_time)


func _start_new_fire_zone(position: Vector2, time: float) -> void:
	_fire_zone_center = position
	_fire_zone_last_sound = time
	_fire_zone_total_duration = 0.0
	_fire_zone_valid = true


## Handle reload/empty click sounds for grenade targeting (Trigger 4).
func on_vulnerable_sound_heard(position: Vector2) -> void:
	if not enabled or _grenades_remaining <= 0:
		return

	if not _can_see_player:
		_heard_vulnerable_sound = true
		_vulnerable_sound_position = position
		_vulnerable_sound_timestamp = Time.get_ticks_msec() / 1000.0
		_log("Heard vulnerable sound at %s - potential grenade target" % position)


## Called when an ally dies. Updates witnessed kill count (Trigger 3).
func on_ally_died(ally_position: Vector2, killer_is_player: bool) -> void:
	if not killer_is_player:
		return

	if not enabled or _grenades_remaining <= 0:
		return

	if _can_see_position(ally_position):
		_witnessed_kills_count += 1
		_kill_witness_reset_timer = KILL_WITNESS_WINDOW
		_log("Witnessed ally kill #%d at %s" % [_witnessed_kills_count, ally_position])


# ============================================================================
# World State Update
# ============================================================================

func _update_world_state() -> void:
	_goap_world_state["has_grenades"] = _grenades_remaining > 0
	_goap_world_state["grenades_remaining"] = _grenades_remaining
	_goap_world_state["grenade_cooldown_ready"] = _cooldown_timer <= 0.0

	var t1 := _should_trigger_suppression()
	var t2 := _should_trigger_pursuit()
	var t3 := _should_trigger_witness()
	var t4 := _should_trigger_sound()
	var t5 := _should_trigger_sustained_fire()
	var t6 := _should_trigger_desperation()

	_goap_world_state["trigger_1_suppression_hidden"] = t1
	_goap_world_state["trigger_2_pursuit"] = t2
	_goap_world_state["trigger_3_witness_kills"] = t3
	_goap_world_state["trigger_4_sound_based"] = t4
	_goap_world_state["trigger_5_sustained_fire"] = t5
	_goap_world_state["trigger_6_desperation"] = t6

	var any_trigger := t1 or t2 or t3 or t4 or t5 or t6
	var was_ready: bool = _goap_world_state.get("ready_to_throw_grenade", false)
	_goap_world_state["ready_to_throw_grenade"] = _cooldown_timer <= 0.0 and _grenades_remaining > 0 and any_trigger

	if _goap_world_state["ready_to_throw_grenade"] and not was_ready:
		var triggers: PackedStringArray = []
		if t1: triggers.append("T1:SuppressionHidden")
		if t2: triggers.append("T2:Pursuit")
		if t3: triggers.append("T3:WitnessKills")
		if t4: triggers.append("T4:SoundBased")
		if t5: triggers.append("T5:SustainedFire")
		if t6: triggers.append("T6:Desperation")
		_log("TRIGGER ACTIVE: %s (grenades: %d)" % [", ".join(triggers), _grenades_remaining])


# ============================================================================
# Trigger Condition Checks
# ============================================================================

func _should_trigger_suppression() -> bool:
	if not _was_suppressed_before_hidden:
		return false
	if _can_see_player:
		return false
	return _player_hidden_timer >= HIDDEN_THRESHOLD


func _should_trigger_pursuit() -> bool:
	if not _under_fire:
		return false
	var approach_speed: float = _goap_world_state.get("player_approaching_speed", 0.0)
	return approach_speed >= PURSUIT_SPEED_THRESHOLD


func _should_trigger_witness() -> bool:
	return _witnessed_kills_count >= KILL_THRESHOLD


func _should_trigger_sound() -> bool:
	if not _heard_vulnerable_sound:
		return false

	var current_time := Time.get_ticks_msec() / 1000.0
	var sound_age := current_time - _vulnerable_sound_timestamp
	if sound_age > SOUND_VALIDITY_WINDOW:
		_heard_vulnerable_sound = false
		return false

	return not _can_see_player


func _should_trigger_sustained_fire() -> bool:
	if not _fire_zone_valid:
		return false
	return _fire_zone_total_duration >= SUSTAINED_FIRE_THRESHOLD


func _should_trigger_desperation() -> bool:
	return _current_health <= DESPERATION_HEALTH_THRESHOLD


# ============================================================================
# Target Position Selection
# ============================================================================

func _get_target_position() -> Vector2:
	# Priority order from lowest cost to highest

	# Trigger 6: Desperation
	if _should_trigger_desperation():
		if _player != null:
			return _player.global_position
		if _memory and _memory.has_target():
			return _memory.suspected_position

	# Trigger 4: Sound-based
	if _should_trigger_sound():
		return _vulnerable_sound_position

	# Trigger 2: Pursuit
	if _should_trigger_pursuit():
		if _player != null:
			var direction := (_player.global_position - _parent.global_position).normalized()
			var throw_dist := minf(200.0, _parent.global_position.distance_to(_player.global_position) * 0.5)
			return _parent.global_position + direction * throw_dist

	# Trigger 3: Witness kills
	if _should_trigger_witness():
		if _player != null and _can_see_player:
			return _player.global_position
		if _memory and _memory.has_target():
			return _memory.suspected_position

	# Trigger 5: Sustained fire
	if _should_trigger_sustained_fire():
		return _fire_zone_center

	# Trigger 1: Suppression hidden
	if _should_trigger_suppression():
		if _memory and _memory.has_target():
			return _memory.suspected_position
		return _last_known_player_position

	return Vector2.ZERO


# ============================================================================
# Throw Execution
# ============================================================================

## Check if can throw a grenade right now.
func can_throw() -> bool:
	if not enabled:
		return false
	if _grenades_remaining <= 0:
		return false
	if _cooldown_timer > 0.0:
		return false
	if _is_throwing:
		return false
	if not _is_alive:
		return false
	if _is_stunned or _is_blinded:
		return false
	return _goap_world_state.get("ready_to_throw_grenade", false)


## Attempt to throw a grenade. Returns true if throw was initiated.
func try_throw() -> bool:
	if not can_throw():
		return false

	var target := _get_target_position()
	if target == Vector2.ZERO:
		return false

	var distance := _parent.global_position.distance_to(target)
	if distance < min_throw_distance:
		_log("Target too close (%.0f < %.0f) - skipping throw" % [distance, min_throw_distance])
		return false

	if distance > max_throw_distance:
		var direction := (target - _parent.global_position).normalized()
		target = _parent.global_position + direction * max_throw_distance
		distance = max_throw_distance

	if not _is_throw_path_clear(target):
		_log("Throw path blocked to %s" % target)
		return false

	_execute_throw(target)
	return true


func _is_throw_path_clear(target: Vector2) -> bool:
	var space_state := _parent.get_world_2d().direct_space_state
	if space_state == null:
		return true

	var query := PhysicsRayQueryParameters2D.create(_parent.global_position, target)
	query.collision_mask = 4  # Obstacles layer
	query.exclude = [_parent]

	var result := space_state.intersect_ray(query)

	if result.is_empty():
		return true

	var collision_distance := _parent.global_position.distance_to(result.position)
	var total_distance := _parent.global_position.distance_to(target)

	return collision_distance > total_distance * 0.6


func _execute_throw(target: Vector2) -> void:
	if grenade_scene == null:
		_log("ERROR: No grenade scene configured!")
		return

	_is_throwing = true

	# Add delay before throw
	if throw_delay > 0.0:
		_log("Preparing throw (%.0fms delay)..." % (throw_delay * 1000))
		await get_tree().create_timer(throw_delay).timeout
		# Safety checks after delay
		if not _is_alive or _is_stunned or _is_blinded:
			_log("Throw cancelled - incapacitated during delay")
			_is_throwing = false
			return
		if not is_instance_valid(self) or not is_instance_valid(_parent):
			return

	# Calculate throw direction with inaccuracy
	var base_direction := (target - _parent.global_position).normalized()
	var inaccuracy_angle := randf_range(-inaccuracy, inaccuracy)
	var throw_direction := base_direction.rotated(inaccuracy_angle)

	var distance := _parent.global_position.distance_to(target)

	# Instantiate grenade
	var grenade: Node2D = grenade_scene.instantiate()

	var spawn_offset := 40.0
	grenade.global_position = _parent.global_position + throw_direction * spawn_offset

	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(grenade)
	else:
		_parent.get_parent().add_child(grenade)

	if grenade.has_method("activate_timer"):
		grenade.activate_timer()

	var throw_speed := clampf(distance * 1.5, 200.0, 800.0)

	if grenade.has_method("throw_grenade"):
		grenade.throw_grenade(throw_direction, distance)
	elif grenade is RigidBody2D:
		grenade.freeze = false
		grenade.linear_velocity = throw_direction * throw_speed
		grenade.rotation = throw_direction.angle()

	var trigger_name := _get_active_trigger_name()
	_log("THROWN! Target: %s, Distance: %.0f, Trigger: %s" % [target, distance, trigger_name])
	_log_to_file("Grenade thrown at %s (distance=%.0f, trigger=%s)" % [target, distance, trigger_name])

	_grenades_remaining -= 1
	_cooldown_timer = throw_cooldown
	_is_throwing = false

	_clear_acted_triggers()

	grenade_thrown.emit(grenade, target)


func _get_active_trigger_name() -> String:
	if _should_trigger_desperation():
		return "Trigger6_Desperation"
	elif _should_trigger_sound():
		return "Trigger4_Sound"
	elif _should_trigger_pursuit():
		return "Trigger2_Pursuit"
	elif _should_trigger_witness():
		return "Trigger3_WitnessKills"
	elif _should_trigger_sustained_fire():
		return "Trigger5_SustainedFire"
	elif _should_trigger_suppression():
		return "Trigger1_SuppressionHidden"
	return "Unknown"


func _clear_acted_triggers() -> void:
	_player_hidden_timer = 0.0
	_was_suppressed_before_hidden = false
	_witnessed_kills_count = 0
	_heard_vulnerable_sound = false
	_fire_zone_valid = false
	_fire_zone_total_duration = 0.0


# ============================================================================
# Utility Functions
# ============================================================================

func get_grenades_remaining() -> int:
	return _grenades_remaining


func add_grenades(count: int) -> void:
	_grenades_remaining += count
	_log("Added %d grenades, now have %d" % [count, _grenades_remaining])


func _get_current_map_name() -> String:
	var current_scene := get_tree().current_scene
	if current_scene != null:
		return current_scene.name
	return ""


func _get_zone_radius() -> float:
	var viewport := get_viewport()
	if viewport == null:
		return 200.0

	var viewport_size := viewport.get_visible_rect().size
	var viewport_diagonal := sqrt(viewport_size.x ** 2 + viewport_size.y ** 2)
	return viewport_diagonal / VIEWPORT_ZONE_FRACTION / 2.0


func _can_see_position(pos: Vector2) -> bool:
	if not _parent:
		return false

	var space_state := _parent.get_world_2d().direct_space_state
	if space_state == null:
		return true

	var query := PhysicsRayQueryParameters2D.create(_parent.global_position, pos)
	query.collision_mask = 4  # Obstacles
	query.exclude = [_parent]

	var result := space_state.intersect_ray(query)
	return result.is_empty()


func _log(message: String) -> void:
	if debug_logging:
		print("[GrenadeThrowing] %s" % message)
	_log_to_file("[Grenade] %s" % message)


func _log_to_file(message: String) -> void:
	if _log_to_file_callback.is_valid():
		_log_to_file_callback.call(message)
