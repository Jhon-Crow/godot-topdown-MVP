class_name MacheteComponent
extends Node
## Machete melee combat component (Issue #579).
##
## Handles melee-specific behaviors for machete-wielding enemies:
## - Sneaking approach via cover-to-cover movement
## - Backstab/flank attack preference (attack from behind)
## - Bullet dodging in attack state (lateral dodge instead of hiding)
## - Melee attack with area damage (no projectiles)

## Melee attack range in pixels.
@export var melee_range: float = 80.0

## Melee attack damage.
@export var melee_damage: int = 2

## Melee attack cooldown in seconds.
@export var melee_cooldown: float = 1.5

## Dodge speed in pixels per second.
@export var dodge_speed: float = 400.0

## Dodge distance in pixels.
@export var dodge_distance: float = 120.0

## Dodge cooldown in seconds.
@export var dodge_cooldown: float = 1.2

## Speed multiplier when sneaking (fraction of normal speed).
@export var sneak_speed_multiplier: float = 0.6

## Enable debug logging.
@export var debug_logging: bool = false

## Emitted when a melee attack hits the player.
signal melee_hit(target: Node2D, damage: int)

## Emitted when a dodge is performed.
signal dodge_performed(direction: Vector2)

## Timer since last melee attack.
var _melee_timer: float = 0.0

## Timer since last dodge.
var _dodge_timer: float = 0.0

## Whether currently performing a dodge.
var _is_dodging: bool = false

## Dodge target position.
var _dodge_target: Vector2 = Vector2.ZERO

## Dodge start position.
var _dodge_start: Vector2 = Vector2.ZERO

## Dodge progress (0.0 to 1.0).
var _dodge_progress: float = 0.0

## Parent enemy reference.
var _parent: CharacterBody2D = null


func _ready() -> void:
	_parent = get_parent() as CharacterBody2D
	_melee_timer = melee_cooldown  # Ready to attack immediately


## Update timers. Called from enemy _physics_process.
func update(delta: float) -> void:
	_melee_timer += delta
	_dodge_timer += delta

	if _is_dodging:
		_process_dodge(delta)


## Check if melee attack cooldown is ready (ignores range/dodge).
func is_attack_ready() -> bool:
	return _melee_timer >= melee_cooldown and not _is_dodging


## Check if melee attack can be performed (in range and off cooldown).
func can_melee_attack(target: Node2D) -> bool:
	if target == null or _parent == null:
		return false
	if _melee_timer < melee_cooldown:
		return false
	if _is_dodging:
		return false
	var distance := _parent.global_position.distance_to(target.global_position)
	return distance <= melee_range


## Perform a melee attack on the target. Returns true if attack was executed.
func perform_melee_attack(target: Node2D) -> bool:
	if not can_melee_attack(target):
		return false

	_melee_timer = 0.0

	# Deal damage to player
	if target.has_method("take_damage"):
		target.take_damage(melee_damage)
	elif target.has_method("TakeDamage"):
		target.TakeDamage(melee_damage)

	# Play melee sound
	var audio: Node = _parent.get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play_hit_non_lethal"):
		audio.play_hit_non_lethal(_parent.global_position)

	# Emit sound propagation (melee swing is quieter)
	var sp: Node = _parent.get_node_or_null("/root/SoundPropagation")
	if sp and sp.has_method("emit_sound"):
		sp.emit_sound(0, _parent.global_position, 1, _parent, 200.0)

	melee_hit.emit(target, melee_damage)
	_log("Melee attack hit %s for %d damage" % [target.name, melee_damage])
	return true


## Check if player is being attacked from behind (backstab opportunity).
## Returns true if player is facing away from this enemy (angle > 90 degrees).
func is_backstab_opportunity(player: Node2D) -> bool:
	if player == null or _parent == null:
		return false

	# Get player's facing direction
	var player_facing := Vector2.RIGHT.rotated(player.rotation)

	# Direction from player to this enemy
	var player_to_enemy := (_parent.global_position - player.global_position).normalized()

	# If dot product is negative, enemy is behind player
	var dot := player_facing.dot(player_to_enemy)
	return dot < 0.0


## Check if player is currently under fire from other enemies.
## Returns true if any other enemy is in COMBAT state and can see the player.
func is_player_under_fire(player: Node2D) -> bool:
	if player == null or _parent == null:
		return false

	var enemies := _parent.get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy == _parent:
			continue
		if not is_instance_valid(enemy):
			continue
		# Check if this other enemy is actively engaging the player
		var state = enemy.get("_current_state")
		var can_see = enemy.get("_can_see_player")
		if state == null or can_see == null:
			continue
		# COMBAT=1 and RETREATING=6 in enemy AIState enum (shooting states)
		if can_see and (state == 1 or state == 6):
			return true
	return false


## Calculate the best approach position behind the player.
## Returns a position behind the player relative to their facing direction.
func get_backstab_approach_position(player: Node2D, approach_distance: float = 150.0) -> Vector2:
	if player == null:
		return Vector2.ZERO

	# Get player's facing direction
	var player_facing := Vector2.RIGHT.rotated(player.rotation)

	# Position behind the player
	var behind_pos := player.global_position - player_facing * approach_distance

	return behind_pos


## Try to dodge a bullet threat. Returns true if dodge was initiated.
## Dodges perpendicular to the bullet direction.
func try_dodge(bullet_direction: Vector2) -> bool:
	if _parent == null:
		return false
	if _is_dodging:
		return false
	if _dodge_timer < dodge_cooldown:
		return false

	_dodge_timer = 0.0
	_is_dodging = true
	_dodge_start = _parent.global_position
	_dodge_progress = 0.0

	# Calculate perpendicular dodge direction (choose the side away from bullet)
	var perp_right := Vector2(-bullet_direction.y, bullet_direction.x)
	var perp_left := Vector2(bullet_direction.y, -bullet_direction.x)

	# Choose dodge side: prefer the one closer to valid navigation mesh
	var right_pos := _parent.global_position + perp_right * dodge_distance
	var left_pos := _parent.global_position + perp_left * dodge_distance

	var nav_agent: NavigationAgent2D = _parent.get_node_or_null("NavigationAgent2D")
	if nav_agent:
		var right_nearest := NavigationServer2D.map_get_closest_point(nav_agent.get_navigation_map(), right_pos)
		var left_nearest := NavigationServer2D.map_get_closest_point(nav_agent.get_navigation_map(), left_pos)
		var right_dist := right_pos.distance_squared_to(right_nearest)
		var left_dist := left_pos.distance_squared_to(left_nearest)
		_dodge_target = left_pos if left_dist < right_dist else right_pos
	else:
		# No navigation: pick a random side
		_dodge_target = left_pos if randf() > 0.5 else right_pos

	dodge_performed.emit((_dodge_target - _parent.global_position).normalized())
	_log("Dodge initiated: direction=%s, target=%s" % [(_dodge_target - _parent.global_position).normalized(), _dodge_target])
	return true


## Check if currently dodging.
func is_dodging() -> bool:
	return _is_dodging


## Get the current dodge velocity. Returns Vector2.ZERO if not dodging.
func get_dodge_velocity() -> Vector2:
	if not _is_dodging or _parent == null:
		return Vector2.ZERO

	var dodge_dir := (_dodge_target - _dodge_start).normalized()
	return dodge_dir * dodge_speed


## Process dodge movement. Called from update().
func _process_dodge(delta: float) -> void:
	if not _is_dodging or _parent == null:
		_is_dodging = false
		return

	var total_dodge_time := dodge_distance / dodge_speed
	_dodge_progress += delta / total_dodge_time

	if _dodge_progress >= 1.0:
		_is_dodging = false
		_dodge_progress = 0.0
		_log("Dodge complete")


## Get sneak movement speed (reduced for stealth approach).
func get_sneak_speed(base_speed: float) -> float:
	return base_speed * sneak_speed_multiplier


## Check if in melee range of target.
func is_in_melee_range(target: Node2D) -> bool:
	if target == null or _parent == null:
		return false
	return _parent.global_position.distance_to(target.global_position) <= melee_range


## Configure from weapon config dictionary.
func configure_from_weapon_config(config: Dictionary) -> void:
	melee_range = config.get("melee_range", 80.0)
	melee_damage = config.get("melee_damage", 2)
	dodge_speed = config.get("dodge_speed", 400.0)
	dodge_distance = config.get("dodge_distance", 120.0)
	sneak_speed_multiplier = config.get("sneak_speed_multiplier", 0.6)


## Log a debug message.
func _log(message: String) -> void:
	if not debug_logging:
		return
	var logger: Node = get_node_or_null("/root/FileLogger")
	if logger and logger.has_method("log_info"):
		logger.log_info("[MacheteComponent] " + message)
	else:
		print("[MacheteComponent] " + message)
