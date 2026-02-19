extends EnemyGrenadeComponent
## Grenadier-specific grenade component (Issue #604).
## Manages a bag of 8 grenades with different types and priority ordering.
##
## Grenadier grenade loadout:
## - All difficulties: 3 flashbangs + 5 offensive (frag)
## - Hard difficulty: 1 defensive + 7 offensive (frag)
##
## Grenade usage priority (least dangerous first):
## 1. Flashbangs (non-lethal, stun only)
## 2. Offensive/frag grenades (small radius: 225px)
## 3. Defensive grenades (large radius: 700px)
##
## The grenadier throws a grenade into each passage before entering,
## and nearby allies wait for the explosion before proceeding.
class_name GrenadierGrenadeComponent

## Signal emitted when a grenade is about to be thrown (allies should wait).
signal grenade_incoming(grenade_position: Vector2, effect_radius: float, fuse_time: float)

## Signal emitted when the grenade has exploded (allies can proceed).
signal grenade_exploded_safe

## Grenade types in priority order (least dangerous first).
enum GrenadeType { FLASHBANG, OFFENSIVE, DEFENSIVE }

## Preloaded grenade scenes.
var _flashbang_scene: PackedScene = null
var _offensive_scene: PackedScene = null
var _defensive_scene: PackedScene = null

## Grenade bag: ordered list of grenade types remaining.
## Grenades are used from the front of the array (index 0 = next to throw).
var _grenade_bag: Array[int] = []

## Whether this grenadier is currently blocking a passage with a grenade.
var _blocking_passage: bool = false

## The grenade currently in flight (for tracking explosion).
var _active_grenade: Node = null

## Cooldown between passage-clearing grenade throws (shorter than combat cooldown).
var passage_throw_cooldown: float = 2.0

## Whether the grenadier has detected a passage ahead.
var _passage_detected: bool = false

## Position of the detected passage entrance.
var _passage_position: Vector2 = Vector2.ZERO

## Trigger 8 (Issue #657): Direct sight timer - grenadier sees player at safe distance.
var _direct_sight_timer: float = 0.0
## Trigger 8: Delay before throwing on direct sight (seconds).
const DIRECT_SIGHT_DELAY := 0.5
## Trigger 8: Whether grenadier currently has line of sight to player at throwable distance.
var _player_in_throw_range: bool = false

## Trigger 9 (Issue #657): Low suspicion timer - throw on slightest suspicion.
var _low_suspicion_timer: float = 0.0
## Trigger 9: Delay before throwing on low suspicion (seconds). Shorter than T7's 3.0s.
const LOW_SUSPICION_DELAY := 1.0


func _ready() -> void:
	_logger = get_node_or_null("/root/FileLogger")
	_enemy = get_parent() as CharacterBody2D


## Override _reset_triggers to also clear grenadier-specific triggers (Issue #657).
func _reset_triggers() -> void:
	super._reset_triggers()
	_direct_sight_timer = 0.0
	_player_in_throw_range = false
	_low_suspicion_timer = 0.0


## Override update to track grenadier-specific triggers T8 and T9 (Issue #657).
func update(delta: float, can_see: bool, under_fire: bool, player: Node2D, health: int, memory = null) -> void:
	super.update(delta, can_see, under_fire, player, health, memory)
	if not enabled or grenades_remaining <= 0:
		return
	# T8: Direct sight - player visible at safe throwing distance
	if can_see and player and _enemy:
		var dist := _enemy.global_position.distance_to(player.global_position)
		var next_scene := _get_next_grenade_scene()
		var blast_radius := _get_blast_radius_for_scene(next_scene) if next_scene else 225.0
		var min_safe := blast_radius + safety_margin
		if dist >= min_safe and dist <= max_throw_distance:
			_player_in_throw_range = true
			_direct_sight_timer += delta
		else:
			_player_in_throw_range = false
			_direct_sight_timer = 0.0
	else:
		_player_in_throw_range = false
		_direct_sight_timer = 0.0
	# T9: Low suspicion - any confidence level while player hidden (Issue #657)
	if memory != null and memory.has_target() and not can_see:
		_low_suspicion_timer += delta
	else:
		_low_suspicion_timer = 0.0


## Trigger 8: Grenadier sees player at safe throwing distance (Issue #657).
func _t8() -> bool:
	return _player_in_throw_range and _direct_sight_timer >= DIRECT_SIGHT_DELAY


## Trigger 9: Grenadier has any suspicion about player position (Issue #657).
func _t9() -> bool:
	return _low_suspicion_timer >= LOW_SUSPICION_DELAY


## Override is_ready to include grenadier-specific triggers T8 and T9 (Issue #657).
func is_ready(can_see: bool, under_fire: bool, health: int) -> bool:
	if not enabled or grenades_remaining <= 0 or _cooldown > 0.0 or _is_throwing:
		return false
	if _grenade_bag.is_empty():
		return false
	return _t1() or _t2(under_fire) or _t3() or _t4(can_see) or _t5() or _t6(health) or _t7() or _t8() or _t9()


## Override get_target to handle grenadier-specific triggers T8 and T9 (Issue #657).
func get_target(can_see: bool, under_fire: bool, health: int, player: Node2D,
				last_known: Vector2, memory_pos: Vector2) -> Vector2:
	# T6 desperation: highest priority
	if _t6(health):
		return player.global_position if player else memory_pos
	# T8 direct sight: throw at player (Issue #657)
	if _t8() and player:
		return player.global_position
	# T7 suspicion-based (original)
	if _t7():
		return memory_pos if memory_pos != Vector2.ZERO else last_known
	# T9 low suspicion: throw at suspected position (Issue #657)
	if _t9():
		return memory_pos if memory_pos != Vector2.ZERO else last_known
	# Fall through to base triggers
	if _t4(can_see):
		return _sound_pos
	if _t2(under_fire) and player and _enemy:
		var dir := (player.global_position - _enemy.global_position).normalized()
		var d := minf(200.0, _enemy.global_position.distance_to(player.global_position) * 0.5)
		return _enemy.global_position + dir * d
	if _t3():
		return player.global_position if player and can_see else memory_pos
	if _t5():
		return _fire_zone
	if _t1():
		return memory_pos if memory_pos != Vector2.ZERO else last_known
	return Vector2.ZERO


## Initialize the grenadier's grenade bag based on difficulty.
func initialize() -> void:
	_cooldown = 0.0
	_is_throwing = false
	_reset_triggers()

	# Load grenade scenes
	_flashbang_scene = load("res://scenes/projectiles/FlashbangGrenade.tscn")
	_offensive_scene = load("res://scenes/projectiles/FragGrenade.tscn")
	_defensive_scene = load("res://scenes/projectiles/DefensiveGrenade.tscn")

	# Build grenade bag based on difficulty
	_build_grenade_bag()

	grenades_remaining = _grenade_bag.size()
	# Set grenade_scene to the first type for compatibility with parent methods
	grenade_scene = _get_next_grenade_scene()
	_log("Grenadier initialized: %d grenades in bag" % grenades_remaining)


## Build the grenade bag based on current difficulty.
## The bag is ordered by priority: flashbangs first, then offensive, then defensive.
func _build_grenade_bag() -> void:
	_grenade_bag.clear()

	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	var is_hard := false
	if difficulty_manager and difficulty_manager.has_method("is_hard_mode"):
		is_hard = difficulty_manager.is_hard_mode()

	if is_hard:
		# Hard difficulty: 1 defensive + 7 offensive (no flashbangs)
		# Priority order: offensive first (small radius), defensive last (large radius)
		for i in range(7):
			_grenade_bag.append(GrenadeType.OFFENSIVE)
		_grenade_bag.append(GrenadeType.DEFENSIVE)
	else:
		# All other difficulties: 3 flashbangs + 5 offensive
		# Priority order: flashbangs first (non-lethal), then offensive
		for i in range(3):
			_grenade_bag.append(GrenadeType.FLASHBANG)
		for i in range(5):
			_grenade_bag.append(GrenadeType.OFFENSIVE)

	_log("Grenade bag built (%s): %s" % [
		"hard" if is_hard else "normal",
		_bag_to_string()
	])


## Get a human-readable string of the grenade bag contents.
func _bag_to_string() -> String:
	var names: Array[String] = []
	for g in _grenade_bag:
		match g:
			GrenadeType.FLASHBANG: names.append("Flashbang")
			GrenadeType.OFFENSIVE: names.append("Offensive")
			GrenadeType.DEFENSIVE: names.append("Defensive")
	return "[%s]" % ", ".join(names)


## Get the next grenade scene from the bag (does not consume it).
func _get_next_grenade_scene() -> PackedScene:
	if _grenade_bag.is_empty():
		return null
	match _grenade_bag[0]:
		GrenadeType.FLASHBANG: return _flashbang_scene
		GrenadeType.OFFENSIVE: return _offensive_scene
		GrenadeType.DEFENSIVE: return _defensive_scene
	return _offensive_scene


## Get the next grenade type name for logging.
func _get_next_grenade_type_name() -> String:
	if _grenade_bag.is_empty():
		return "none"
	match _grenade_bag[0]:
		GrenadeType.FLASHBANG: return "Flashbang"
		GrenadeType.OFFENSIVE: return "Offensive"
		GrenadeType.DEFENSIVE: return "Defensive"
	return "Unknown"


## Consume the next grenade from the bag.
func _consume_grenade() -> void:
	if not _grenade_bag.is_empty():
		var consumed := _grenade_bag[0]
		_grenade_bag.remove_at(0)
		grenades_remaining = _grenade_bag.size()
		_log("Consumed grenade (type=%d), %d remaining: %s" % [consumed, grenades_remaining, _bag_to_string()])


## Override try_throw to use the grenade bag system.
func try_throw(target: Vector2, is_alive: bool, is_stunned: bool, is_blinded: bool) -> bool:
	if not enabled or grenades_remaining <= 0 or _cooldown > 0.0 or _is_throwing:
		return false
	if not is_alive or is_stunned or is_blinded or target == Vector2.ZERO or _enemy == null:
		return false
	if _grenade_bag.is_empty():
		return false

	var dist := _enemy.global_position.distance_to(target)

	# Get blast radius for the next grenade type
	var next_scene := _get_next_grenade_scene()
	if next_scene == null:
		return false

	var blast_radius := _get_blast_radius_for_scene(next_scene)
	var min_safe_distance := blast_radius + safety_margin

	if dist < min_safe_distance:
		_log("Unsafe throw distance (%.0f < %.0f safe, blast=%.0f) for %s - skipping" %
			[dist, min_safe_distance, blast_radius, _get_next_grenade_type_name()])
		return false

	if dist < min_throw_distance:
		_log("Target too close (%.0f < %.0f) for %s - skipping" %
			[dist, min_throw_distance, _get_next_grenade_type_name()])
		return false

	if dist > max_throw_distance:
		target = _enemy.global_position + (target - _enemy.global_position).normalized() * max_throw_distance

	if not _path_clear(target):
		_log("Throw path blocked for %s to %s" % [_get_next_grenade_type_name(), target])
		return false

	# Issue #712: Check if target is visible to enemy (not throwing into unseen area)
	if require_target_visibility and not _is_target_visible(target):
		_log("Target not visible for %s at %s - skipping throw" % [_get_next_grenade_type_name(), target])
		return false

	_execute_grenadier_throw(target, is_alive, is_stunned, is_blinded)
	return true


## Execute a throw using the grenade bag system. cooldown_override overrides throw_cooldown if > 0.
func _execute_grenadier_throw(target: Vector2, is_alive: bool, is_stunned: bool, is_blinded: bool, cooldown_override: float = 0.0) -> void:
	var next_scene := _get_next_grenade_scene()
	if next_scene == null:
		return
	_is_throwing = true

	# Get effect radius for ally warning
	var blast_radius := _get_blast_radius_for_scene(next_scene)
	var grenade_type_name := _get_next_grenade_type_name()

	# Determine fuse time (flashbang/defensive use timer, frag is impact)
	var fuse := 4.0
	if _grenade_bag[0] == GrenadeType.OFFENSIVE:
		fuse = 1.0  # Frag grenades explode on impact, short effective time

	# Issue #712: Signal enemy to face throw direction before throwing
	var throw_dir := (target - _enemy.global_position).normalized()
	face_throw_direction.emit(throw_dir)
	_log("Grenadier facing throw direction: %s (waiting %.1fs)" % [throw_dir, face_direction_delay])

	# Wait for enemy to rotate toward target
	if face_direction_delay > 0.0:
		await get_tree().create_timer(face_direction_delay).timeout

	# Signal allies to wait
	grenade_incoming.emit(target, blast_radius, fuse)
	_blocking_passage = true

	if throw_delay > 0.0:
		await get_tree().create_timer(throw_delay).timeout

	if not is_alive or is_stunned or is_blinded or not is_instance_valid(self) or not is_instance_valid(_enemy):
		_is_throwing = false
		_blocking_passage = false
		return

	var dir := (target - _enemy.global_position).normalized().rotated(randf_range(-inaccuracy, inaccuracy))
	var grenade: Node2D = next_scene.instantiate()
	grenade.global_position = _enemy.global_position + dir * 40.0

	# Issue #692: Set thrower_id on the grenade so it won't damage the throwing enemy
	if grenade.get("thrower_id") != null:
		grenade.thrower_id = _enemy.get_instance_id()

	var parent := get_tree().current_scene
	(parent if parent else _enemy.get_parent()).add_child(grenade)

	# Attach C# GrenadeTimer component for reliable explosion handling
	var grenade_timer_type := "Frag"
	match _grenade_bag[0]:
		GrenadeType.FLASHBANG: grenade_timer_type = "Flashbang"
		GrenadeType.DEFENSIVE: grenade_timer_type = "Frag"  # Similar timer behavior
		GrenadeType.OFFENSIVE: grenade_timer_type = "Frag"
	_attach_grenade_timer(grenade as RigidBody2D, grenade_timer_type)

	# Activate timer for timer-based grenades
	if grenade.has_method("activate_timer"):
		grenade.activate_timer()
	_activate_grenade_timer(grenade as RigidBody2D)

	# Throw the grenade
	var dist := _enemy.global_position.distance_to(target)
	if grenade.has_method("throw_grenade"):
		grenade.throw_grenade(dir, dist)
	elif grenade is RigidBody2D:
		grenade.freeze = false
		grenade.linear_velocity = dir * clampf(dist * 1.5, 200.0, 800.0)
		grenade.rotation = dir.angle()

	# Mark C# timer as thrown
	_mark_grenade_thrown(grenade as RigidBody2D)

	# Issue #692: Set thrower on C# GrenadeTimer for self-damage prevention
	_set_grenade_thrower(grenade as RigidBody2D, _enemy.get_instance_id())

	# Track active grenade for explosion detection
	_active_grenade = grenade
	if grenade.has_signal("exploded"):
		grenade.exploded.connect(_on_active_grenade_exploded)

	# Consume from bag
	_consume_grenade()

	_cooldown = cooldown_override if cooldown_override > 0.0 else throw_cooldown
	_is_throwing = false
	_reset_triggers()
	grenade_thrown.emit(grenade, target)
	_log("Grenadier threw %s! Target: %s, Distance: %.0f, %d remaining, cooldown=%.1fs" % [
		grenade_type_name, str(target), dist, grenades_remaining, _cooldown
	])

	# Set a safety timer to clear blocking state if grenade signal is missed
	_start_blocking_timeout(fuse + 2.0)


## Called when the active grenade explodes.
func _on_active_grenade_exploded(_position: Vector2, _grenade: GrenadeBase) -> void:
	_blocking_passage = false
	_active_grenade = null
	grenade_exploded_safe.emit()
	_log("Grenadier's grenade exploded - passage clear")


## Safety timeout to clear blocking state if grenade explosion signal is missed.
func _start_blocking_timeout(timeout: float) -> void:
	await get_tree().create_timer(timeout).timeout
	if _blocking_passage:
		_blocking_passage = false
		_active_grenade = null
		grenade_exploded_safe.emit()
		_log("Grenadier blocking timeout - forcing passage clear")


## Get blast radius for a specific grenade scene.
func _get_blast_radius_for_scene(scene: PackedScene) -> float:
	if scene == null:
		return 225.0

	var temp_grenade = scene.instantiate()
	if temp_grenade == null:
		return 225.0

	var radius := 225.0
	if temp_grenade.get("effect_radius") != null:
		radius = temp_grenade.effect_radius

	temp_grenade.queue_free()
	return radius


## Check if the grenadier is currently blocking a passage (allies should wait).
func is_blocking_passage() -> bool:
	return _blocking_passage


## Check if grenadier has grenades remaining in the bag.
func has_grenades() -> bool:
	return not _grenade_bag.is_empty()


## Get the number of grenades remaining in the bag.
func get_bag_size() -> int:
	return _grenade_bag.size()


## Proactive passage throw (Issue #604): Throw a grenade before entering a passage/corridor.
## Called from enemy.gd during PURSUING state when moving toward a waypoint.
## Returns true if a grenade was thrown.
func try_passage_throw(enemy_pos: Vector2, next_waypoint: Vector2, space_state: PhysicsDirectSpaceState2D,
		is_alive: bool, is_stunned: bool, is_blinded: bool) -> bool:
	if not enabled or _grenade_bag.is_empty() or _is_throwing or _blocking_passage:
		return false
	if not is_alive or is_stunned or is_blinded or _enemy == null:
		return false
	# Use passage cooldown (shorter than combat cooldown) for proactive throws
	if _cooldown > 0.0:
		return false

	var dir_to_waypoint := (next_waypoint - enemy_pos).normalized()
	var dist_to_waypoint := enemy_pos.distance_to(next_waypoint)

	# Only check when waypoint is at a reasonable distance (not too close, not too far)
	if dist_to_waypoint < 80.0 or dist_to_waypoint > 500.0:
		return false

	# Raycast from enemy to next waypoint to detect walls/obstacles in the path
	var query := PhysicsRayQueryParameters2D.create(enemy_pos, next_waypoint)
	query.collision_mask = 0b100  # Layer 3: obstacles/walls
	query.exclude = [_enemy]
	var result := space_state.intersect_ray(query)

	if result.is_empty():
		return false  # No wall ahead, no need to throw

	var wall_pos: Vector2 = result.position
	var wall_dist := enemy_pos.distance_to(wall_pos)

	# Wall must be close enough that we're about to enter the passage (within 200px)
	if wall_dist > 200.0 or wall_dist < 40.0:
		return false

	# Calculate throw target: beyond the wall, into the passage/room on the other side
	# Throw to a point 150-300px past the wall along movement direction
	var throw_distance := clampf(dist_to_waypoint, 275.0, max_throw_distance)
	var throw_target := enemy_pos + dir_to_waypoint * throw_distance

	# Verify throw target is far enough for safety
	var target_dist := enemy_pos.distance_to(throw_target)
	var next_scene := _get_next_grenade_scene()
	if next_scene == null:
		return false
	var blast_radius := _get_blast_radius_for_scene(next_scene)
	if target_dist < blast_radius + safety_margin:
		return false

	# Check throw path isn't completely blocked (grenade should arc over low cover)
	if not _path_clear(throw_target):
		# Try throwing slightly to the sides
		var perp := Vector2(-dir_to_waypoint.y, dir_to_waypoint.x)
		var alt_target := throw_target + perp * 80.0
		if _path_clear(alt_target) and enemy_pos.distance_to(alt_target) >= blast_radius + safety_margin:
			throw_target = alt_target
		else:
			alt_target = throw_target - perp * 80.0
			if _path_clear(alt_target) and enemy_pos.distance_to(alt_target) >= blast_radius + safety_margin:
				throw_target = alt_target
			else:
				return false

	_log("Passage throw: wall at %.0fpx, throwing %s to %s (dist=%.0f)" % [
		wall_dist, _get_next_grenade_type_name(), str(throw_target), target_dist])

	_execute_grenadier_throw(throw_target, is_alive, is_stunned, is_blinded, passage_throw_cooldown)
	return true
