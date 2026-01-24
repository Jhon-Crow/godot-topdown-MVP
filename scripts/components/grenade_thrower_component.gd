class_name GrenadeThrowerComponent
extends Node
## Grenade throwing behavior component for enemies.
##
## Handles all grenade throwing logic including trigger conditions,
## throw execution, and post-throw behavior. Works with GrenadeInventory
## for grenade tracking.

## Grenade types matching GrenadeInventory.
enum GrenadeType {
	OFFENSIVE = 0,  ## Frag/offensive grenade - high damage
	FLASHBANG = 1   ## Flashbang - blinds and stuns
}

## Signal emitted when grenade throw is requested (for state transition).
signal throw_requested(target_position: Vector2, grenade_type: int)

## Signal emitted when grenade throw is complete.
signal throw_completed

## Signal emitted when an ally death is witnessed.
signal ally_death_witnessed(death_count: int)

## Signal emitted when allies should be notified about incoming grenade.
## Parameters: target_position (where grenade will land), blast_radius (danger zone size)
signal notify_allies_of_grenade(target_position: Vector2, blast_radius: float)

## Signal emitted when grenade explodes (for coordinated assault trigger).
signal grenade_exploded(explosion_position: Vector2)

## Enable/disable grenade throwing behavior.
@export var enabled: bool = false

## Number of offensive (frag) grenades this enemy carries.
@export var offensive_grenades: int = 0

## Number of flashbang grenades this enemy carries.
@export var flashbang_grenades: int = 0

## Maximum grenade throw range in pixels.
@export var throw_range: float = 400.0

## Grenade throw accuracy deviation in degrees (±5° per issue #273 requirement).
@export var throw_deviation: float = 5.0

## Minimum safe distance from grenade explosion (blast radius + safety margin).
## Enemy will not throw if they would be within this distance of the target.
@export var min_safe_distance: float = 250.0

## Offset distance from enemy to spawn grenade (to avoid immediate collision).
@export var grenade_spawn_offset: float = 50.0

## Blast radius for frag grenades (used for ally notification).
@export var frag_blast_radius: float = 225.0

## Blast radius for flashbangs (used for ally notification).
@export var flashbang_blast_radius: float = 400.0

## Frag grenade scene to instantiate when throwing.
@export var frag_grenade_scene: PackedScene

## Flashbang grenade scene to instantiate when throwing.
@export var flashbang_grenade_scene: PackedScene

## Duration for grenade preparation phase (seconds).
const PREP_DURATION: float = 0.5

## Duration of cooldown between grenade throws (seconds).
const COOLDOWN_DURATION: float = 10.0

## Duration player must be hidden after suppression to trigger grenade (6 seconds per issue).
const PLAYER_HIDDEN_TRIGGER_DURATION: float = 6.0

## Duration of continuous gunfire to trigger grenade (10 seconds per issue).
const CONTINUOUS_GUNFIRE_TRIGGER_DURATION: float = 10.0

## Whether the enemy is currently in the process of throwing a grenade.
var _is_throwing: bool = false

## Timer for grenade throw preparation (time to get into position and aim).
var _prep_timer: float = 0.0

## Target position for the grenade throw.
var _target_position: Vector2 = Vector2.ZERO

## Type of grenade being thrown (0=offensive/frag, 1=flashbang).
var _type_to_throw: int = 0

## Cooldown timer after throwing a grenade.
var _cooldown_timer: float = 0.0

## Timer tracking how long the player has been hidden after suppression.
var _player_hidden_timer: float = 0.0

## Timer tracking continuous gunfire in a zone.
var _continuous_gunfire_timer: float = 0.0

## Count of ally deaths witnessed by this enemy.
var _witnessed_ally_deaths: int = 0

## Reference to the log function from parent.
var _log_func: Callable

## Last grenade target position (for post-explosion assault through same passage).
var _last_throw_target: Vector2 = Vector2.ZERO

## Whether we're waiting for a grenade to explode (for coordinated assault).
var _awaiting_explosion: bool = false

## Timer for grenade explosion (frag grenades are impact-triggered, flashbangs have 4s fuse).
var _explosion_timer: float = 0.0

## Whether the grenade was offensive (impacts post-throw behavior).
var _last_grenade_was_offensive: bool = true


## Initialize the component.
func initialize(log_function: Callable = Callable()) -> void:
	_log_func = log_function
	_reset_state()


## Reset all throwing state.
func _reset_state() -> void:
	_is_throwing = false
	_prep_timer = 0.0
	_cooldown_timer = 0.0


## Log a message (using parent's log function if available).
func _log(message: String) -> void:
	if _log_func.is_valid():
		_log_func.call(message)


## Update cooldown timer. Call from _physics_process.
func update_cooldown(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta
		if _cooldown_timer <= 0.0:
			_cooldown_timer = 0.0

	# Update explosion timer if awaiting explosion
	if _awaiting_explosion and _explosion_timer > 0.0:
		_explosion_timer -= delta
		if _explosion_timer <= 0.0:
			_awaiting_explosion = false
			grenade_exploded.emit(_last_throw_target)
			_log("Grenade exploded at %s - triggering assault" % _last_throw_target)


## Update player hidden timer. Call when player visibility changes.
func update_player_hidden_timer(delta: float, player_visible: bool, was_suppression_active: bool) -> void:
	if not enabled:
		return

	if not player_visible and was_suppression_active:
		_player_hidden_timer += delta
	else:
		_player_hidden_timer = 0.0


## Update continuous gunfire timer. Call when gunfire is detected.
func update_gunfire_timer(delta: float, gunfire_detected: bool) -> void:
	if gunfire_detected:
		_continuous_gunfire_timer += delta
	else:
		_continuous_gunfire_timer = 0.0


## Register an ally death. Call when an ally enemy dies.
func register_ally_death() -> void:
	_witnessed_ally_deaths += 1
	ally_death_witnessed.emit(_witnessed_ally_deaths)


## Check if grenades are available.
func has_grenades() -> bool:
	return offensive_grenades > 0 or flashbang_grenades > 0


## Check if throwing at target_pos would put the thrower in the blast radius.
## Returns true if it's SAFE to throw (thrower is outside blast radius).
func is_safe_throw_distance(throw_origin: Vector2, target_pos: Vector2) -> bool:
	var distance_to_target := throw_origin.distance_to(target_pos)
	return distance_to_target >= min_safe_distance


## Check if there's a wall blocking the throw path from origin to target.
## Returns true if the path is CLEAR (no wall blocking), false if blocked.
## This prevents enemies from throwing grenades at walls point-blank.
func is_throw_path_clear(throw_origin: Vector2, target_pos: Vector2) -> bool:
	var parent_node: Node = get_parent()
	if parent_node == null:
		return true  # Fail-open if no parent

	var world_2d: World2D = parent_node.get_world_2d()
	if world_2d == null:
		return true
	var space_state: PhysicsDirectSpaceState2D = world_2d.direct_space_state
	if space_state == null:
		return true

	# Calculate the grenade spawn position (offset from throw origin)
	var direction_to_target := (target_pos - throw_origin).normalized()
	var spawn_pos := throw_origin + direction_to_target * grenade_spawn_offset

	# First check: Is there a wall between enemy and spawn position?
	var spawn_check := PhysicsRayQueryParameters2D.new()
	spawn_check.from = throw_origin
	spawn_check.to = spawn_pos
	spawn_check.collision_mask = 4  # Obstacles (layer 3)
	spawn_check.exclude = [parent_node.get_rid()] if parent_node.has_method("get_rid") else []

	var spawn_result: Dictionary = space_state.intersect_ray(spawn_check)
	if not spawn_result.is_empty():
		_log("Grenade throw blocked: wall between enemy and spawn position")
		return false

	# Second check: Is there a wall between spawn position and target?
	var target_check := PhysicsRayQueryParameters2D.new()
	target_check.from = spawn_pos
	target_check.to = target_pos
	target_check.collision_mask = 4  # Obstacles (layer 3)

	var target_result: Dictionary = space_state.intersect_ray(target_check)
	if not target_result.is_empty():
		# Check if the wall is very close (point-blank situation)
		var hit_position: Vector2 = target_result["position"]
		var distance_to_wall := spawn_pos.distance_to(hit_position)
		var distance_to_target := spawn_pos.distance_to(target_pos)

		# If wall is less than 50 pixels away, it's point-blank - don't throw
		if distance_to_wall < 50.0:
			_log("Grenade throw blocked: wall point-blank (%.1f pixels away)" % distance_to_wall)
			return false

		# If wall blocks more than 80% of the path, don't throw
		if distance_to_wall < distance_to_target * 0.2:
			_log("Grenade throw blocked: wall blocking throw path (%.1f%% of distance)" % [(distance_to_wall / distance_to_target) * 100])
			return false

	return true


## Get the blast radius for the currently selected grenade type.
func get_current_blast_radius() -> float:
	if _type_to_throw == GrenadeType.OFFENSIVE:
		return frag_blast_radius
	else:
		return flashbang_blast_radius


## Check if a grenade throw should be triggered.
## Parameters:
## - current_health: The enemy's current health
## - can_see_player: Whether the enemy can currently see the player
## - is_suppressed: Whether the enemy is in suppressed state
## - distance_to_player: Distance to the player
## - throw_origin: (Optional) Thrower's position for safety check
## - target_pos: (Optional) Target position for safety check
func should_throw(current_health: int, can_see_player: bool, is_suppressed: bool, distance_to_player: float, throw_origin: Vector2 = Vector2.ZERO, target_pos: Vector2 = Vector2.ZERO) -> bool:
	# Must have grenades enabled and available
	if not enabled:
		return false

	if not has_grenades():
		return false

	# Must not be on cooldown
	if _cooldown_timer > 0.0:
		return false

	# Must not already be throwing
	if _is_throwing:
		return false

	# Check distance (must be within throw range)
	if distance_to_player > throw_range:
		return false

	# Safety check: don't throw if thrower would be in blast radius
	# Skip this check if positions aren't provided (backwards compatibility)
	if throw_origin != Vector2.ZERO and target_pos != Vector2.ZERO:
		if not is_safe_throw_distance(throw_origin, target_pos):
			_log("Grenade throw blocked: too close to target (would be in blast radius)")
			return false

	# Trigger conditions from issue #273:

	# 1. Player suppressed enemies then hid for 6+ seconds
	if _player_hidden_timer >= PLAYER_HIDDEN_TRIGGER_DURATION:
		_log("Grenade trigger: player hidden for %.1fs after suppression" % _player_hidden_timer)
		return true

	# 2. Player is chasing a suppressed thrower (enemy is suppressed and player approaching)
	if is_suppressed and can_see_player:
		_log("Grenade trigger: suppressed and player visible (being chased)")
		return true

	# 3. Thrower witnessed player kill 2+ enemies
	if _witnessed_ally_deaths >= 2:
		_log("Grenade trigger: witnessed %d ally deaths" % _witnessed_ally_deaths)
		return true

	# 4. Thrower heard reload/empty magazine sound but can't see player
	# (Handled externally via on_reload_sound_heard)

	# 5. Continuous gunfire for 10 seconds in zone
	if _continuous_gunfire_timer >= CONTINUOUS_GUNFIRE_TRIGGER_DURATION:
		_log("Grenade trigger: continuous gunfire for %.1fs" % _continuous_gunfire_timer)
		return true

	# 6. Thrower has 1 HP or less (critical health desperation throw)
	if current_health <= 1:
		_log("Grenade trigger: critical health (%d HP)" % current_health)
		return true

	return false


## Get the best grenade type for the current tactical situation.
## Returns GrenadeType.OFFENSIVE (0) for frag, GrenadeType.FLASHBANG (1) for flashbang.
func get_best_grenade_type() -> int:
	# Prefer offensive grenade when player is in cover or at distance
	if offensive_grenades > 0:
		return GrenadeType.OFFENSIVE

	# Fallback to flashbang if no frag grenades
	if flashbang_grenades > 0:
		return GrenadeType.FLASHBANG

	return GrenadeType.OFFENSIVE  # Default


## Begin throwing a grenade at the target position.
func begin_throw(target_pos: Vector2, grenade_type: int) -> void:
	_target_position = target_pos
	_type_to_throw = grenade_type
	_prep_timer = 0.0
	_is_throwing = true
	_last_grenade_was_offensive = (grenade_type == GrenadeType.OFFENSIVE)

	var type_name: String = "frag" if grenade_type == GrenadeType.OFFENSIVE else "flashbang"
	_log("Preparing to throw %s grenade at %s" % [type_name, target_pos])

	# Notify allies in the blast zone / throw line to evacuate (per issue #295)
	var blast_radius := get_current_blast_radius()
	notify_allies_of_grenade.emit(target_pos, blast_radius)
	_log("Notifying allies: blast zone at %s, radius %.0f" % [target_pos, blast_radius])


## Update throw preparation. Returns true when throw should execute.
func update_throw_prep(delta: float) -> bool:
	if not _is_throwing:
		return false

	_prep_timer += delta

	if _prep_timer >= PREP_DURATION:
		return true

	return false


## Execute the actual grenade throw.
## Returns the grenade instance if successful, null otherwise.
func execute_throw(throw_origin: Vector2) -> RigidBody2D:
	var grenade_scene: PackedScene = null

	if _type_to_throw == GrenadeType.OFFENSIVE:
		# Offensive/frag grenade
		if offensive_grenades <= 0:
			_log("Cannot throw frag grenade - none left")
			return null
		offensive_grenades -= 1

		if frag_grenade_scene:
			grenade_scene = frag_grenade_scene
		else:
			grenade_scene = preload("res://scenes/projectiles/FragGrenade.tscn")
	else:
		# Flashbang grenade
		if flashbang_grenades <= 0:
			_log("Cannot throw flashbang - none left")
			return null
		flashbang_grenades -= 1

		if flashbang_grenade_scene:
			grenade_scene = flashbang_grenade_scene
		else:
			grenade_scene = preload("res://scenes/projectiles/FlashbangGrenade.tscn")

	if grenade_scene == null:
		_log("ERROR: No grenade scene available")
		return null

	# Instantiate the grenade
	var grenade: RigidBody2D = grenade_scene.instantiate()
	if grenade == null:
		_log("ERROR: Failed to instantiate grenade")
		return null

	# Apply throw deviation (±5° per issue requirement)
	var direction_to_target := (_target_position - throw_origin).normalized()
	var deviation_radians := deg_to_rad(randf_range(-throw_deviation, throw_deviation))
	var deviated_direction := direction_to_target.rotated(deviation_radians)

	# Calculate throw distance (clamped to throw range)
	var distance_to_target := throw_origin.distance_to(_target_position)
	var actual_distance := minf(distance_to_target, throw_range)

	# Position grenade at throw origin with larger offset to avoid collision with thrower
	# This prevents the grenade from immediately colliding with the enemy who threw it
	grenade.global_position = throw_origin + deviated_direction * grenade_spawn_offset

	# Store throw data for deferred execution (after grenade is added to scene)
	# NOTE: Using actual_distance directly (not * 0.5) for proper throw strength
	# The legacy throw_grenade() uses drag_distance * drag_to_speed_multiplier (2.0)
	# So for a 400px target, we need 200 drag_distance to get 400 speed
	# Adjusted formula: actual_distance / drag_to_speed_multiplier = actual_distance / 2.0
	# But this was causing weak throws. The real issue is the speed calculation.
	# For proper throw: use actual_distance as-is, the grenade physics will handle it.
	grenade.set_meta("throw_direction", deviated_direction)
	grenade.set_meta("throw_distance", actual_distance)

	# Store thrower reference so grenade can exclude thrower from initial collision
	# This prevents the grenade from triggering on the enemy who threw it
	grenade.set_meta("thrower_id", get_parent().get_instance_id() if get_parent() else 0)

	var type_name: String = "frag" if _type_to_throw == GrenadeType.OFFENSIVE else "flashbang"
	_log("Threw %s grenade: target=%s, deviation=%.1f°, distance=%.0f" % [
		type_name,
		_target_position,
		rad_to_deg(deviation_radians),
		actual_distance
	])

	# Store last throw position for post-explosion assault (per issue #295)
	_last_throw_target = _target_position
	_awaiting_explosion = true

	# For flashbangs, set explosion timer (4 seconds fuse)
	# Frag grenades are impact-triggered, so we estimate ~1 second flight time
	if _type_to_throw == GrenadeType.OFFENSIVE:
		_explosion_timer = 1.0  # Estimated impact time for frag
	else:
		_explosion_timer = 4.0  # Flashbang fuse timer

	# Complete the throw
	_finish_throw()

	return grenade


## Activate the grenade after it's been added to the scene tree.
static func activate_thrown_grenade(grenade: RigidBody2D) -> void:
	if not grenade:
		return
	var direction: Vector2 = grenade.get_meta("throw_direction", Vector2.RIGHT)
	var drag_distance: float = grenade.get_meta("throw_distance", 100.0)
	if grenade.has_method("throw_grenade"):
		grenade.throw_grenade(direction, drag_distance)
		if grenade.has_method("activate_timer"):
			grenade.activate_timer()


## Finish throwing and start cooldown.
func _finish_throw() -> void:
	_cooldown_timer = COOLDOWN_DURATION
	_is_throwing = false
	throw_completed.emit()


## Cancel the current throw.
func cancel_throw() -> void:
	_is_throwing = false
	_prep_timer = 0.0


## Check if currently throwing.
func is_throwing() -> bool:
	return _is_throwing


## Check if on cooldown.
func is_on_cooldown() -> bool:
	return _cooldown_timer > 0.0


## Get the target position for current throw.
func get_target_position() -> Vector2:
	return _target_position


## Reset all state (for respawn).
func reset() -> void:
	_reset_state()
	_player_hidden_timer = 0.0
	_continuous_gunfire_timer = 0.0
	_witnessed_ally_deaths = 0
	_last_throw_target = Vector2.ZERO
	_awaiting_explosion = false
	_explosion_timer = 0.0


## Get the last throw target position (for post-explosion assault).
func get_last_throw_target() -> Vector2:
	return _last_throw_target


## Check if we're awaiting a grenade explosion.
func is_awaiting_explosion() -> bool:
	return _awaiting_explosion


## Check if the last grenade was offensive (affects post-throw cover behavior).
func was_last_grenade_offensive() -> bool:
	return _last_grenade_was_offensive


## Mark explosion as completed (called by enemy when processing assault).
func mark_explosion_complete() -> void:
	_awaiting_explosion = false
