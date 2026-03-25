class_name DroneComponent
extends Node
## Drone AI and behavior component (Issue #1397, #1417).
##
## Two-phase behavior:
## 1. SEARCHING: Hovers in place, scanning for player with 360° vision (no FOV limit).
##    Uses line-of-sight raycast — if player is visible, transitions to COMBAT.
## 2. COMBAT: Red LED, morse-code beeping, 3× speed kamikaze flight.
##    Uses NavigationAgent2D to maneuver around obstacles, but drifts on turns.
##    On collision with player: explodes like RPG rocket (no wall penetration).
##
## This component is a child node of the Drone scene (CharacterBody2D).
## The parent drone.gd handles visuals and hit forwarding.

## Emitted when the drone is destroyed (shot down or exploded).
signal drone_destroyed

## Emitted when the drone takes damage.
signal drone_hit

## Emitted when combat mode activates (for visual updates in drone.gd).
signal combat_activated

## Drone behavior states.
enum DroneState {
	SEARCHING,  ## Scanning for player with 360° vision
	COMBAT      ## Kamikaze flight toward player
}

## Health points of the drone.
const DRONE_HP: int = 2

## Movement speed in SEARCHING mode (px/s).
const SEARCH_SPEED: float = 150.0

## Combat speed multiplier (3× search speed per Issue #1417).
const COMBAT_SPEED_MULTIPLIER: float = 3.0

## Combat movement speed (px/s).
const COMBAT_SPEED: float = SEARCH_SPEED * COMBAT_SPEED_MULTIPLIER

## Distance at which the drone collides with the player and explodes (px).
const COLLISION_DISTANCE: float = 24.0

## Explosion radius (same as RPG rocket: 150 px).
const EXPLOSION_RADIUS: float = 150.0

## Explosion damage (same as RPG rocket: 3 HP).
const EXPLOSION_DAMAGE: int = 3

## Drift/inertia factor for COMBAT direction changes.
const DRIFT_FACTOR: float = 0.85

## Beep interval in seconds.
const BEEP_INTERVAL: float = 0.3

## Beep frequency (Hz) for procedural tone.
const BEEP_FREQUENCY: float = 1200.0

## Beep duration per pip (seconds).
const BEEP_DURATION: float = 0.08

## Current drone state.
var _state: int = DroneState.SEARCHING

## Current HP.
var _hp: int = DRONE_HP

## Whether the drone is alive.
var _is_alive: bool = true

## Whether the drone has exploded.
var _has_exploded: bool = false

## Reference to the parent CharacterBody2D (the Drone scene root).
var _drone_body: CharacterBody2D = null

## Reference to the player.
var _player: Node2D = null

## Reference to the operator who spawned this drone.
var _operator: Node2D = null

## NavigationAgent2D for pathfinding around obstacles.
var _nav_agent: NavigationAgent2D = null

## Current movement direction (drift/inertia in combat).
var _current_move_direction: Vector2 = Vector2.ZERO

## Beep timer for morse-code-like sound pattern.
var _beep_timer: float = 0.0

## Beep pattern index.
var _beep_pattern_index: int = 0

## Morse-code-like beep pattern durations.
var _beep_pattern: Array = [0.08, 0.08, 0.2, 0.08, 0.08, 0.2, 0.08, 0.08]

## AudioStreamPlayer2D for beeping sound.
var _beep_player: AudioStreamPlayer2D = null


func _ready() -> void:
	_drone_body = get_parent() as CharacterBody2D
	if _drone_body == null:
		FileLogger.info("[Drone] WARNING: DroneComponent parent is not CharacterBody2D")
		return
	_find_nav_agent()
	_setup_beep_player()
	_find_player()
	FileLogger.info("[Drone] DroneComponent _ready complete (state=SEARCHING, player=%s, nav=%s)" % [
		(_player.name if _player else "null"),
		("found" if _nav_agent else "missing")
	])


## Initialize the drone with operator reference (called by DroneOperatorComponent).
func initialize(operator: Node2D) -> void:
	_operator = operator
	FileLogger.info("[Drone] Initialized by operator: %s" % (operator.name if operator else "null"))


## Find the NavigationAgent2D sibling node.
func _find_nav_agent() -> void:
	if _drone_body == null:
		return
	_nav_agent = _drone_body.get_node_or_null("NavigationAgent2D") as NavigationAgent2D
	if _nav_agent:
		_nav_agent.path_desired_distance = 8.0
		_nav_agent.target_desired_distance = 8.0


## Set up AudioStreamPlayer2D for beeping sound in combat mode.
func _setup_beep_player() -> void:
	_beep_player = AudioStreamPlayer2D.new()
	_beep_player.name = "DroneBeepPlayer"
	_beep_player.max_distance = 800.0
	_beep_player.attenuation = 2.0
	_beep_player.volume_db = -8.0
	add_child(_beep_player)


## Find the player in the scene tree using multiple fallback methods.
func _find_player() -> void:
	if _drone_body == null:
		return
	var tree := _drone_body.get_tree()
	if tree == null:
		return
	# Method 1: search by group
	var players: Array = tree.get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]
		return
	# Method 2: GameManager autoload
	var gm: Node = _drone_body.get_node_or_null("/root/GameManager")
	if gm and gm.get("player") and is_instance_valid(gm.get("player")):
		_player = gm.player
		return
	# Method 3: search by node name
	var root: Node = tree.current_scene
	if root:
		var found: Node = root.find_child("Player", true, false)
		if found:
			_player = found


func _physics_process(delta: float) -> void:
	if not _is_alive or _drone_body == null:
		return

	# Retry player search if needed
	if _player == null or not is_instance_valid(_player):
		_player = null
		_find_player()
		return

	# Check if player is alive via GameManager
	var gm: Node = _drone_body.get_node_or_null("/root/GameManager")
	if gm and not gm.get("player_alive"):
		_drone_body.velocity = Vector2.ZERO
		_drone_body.move_and_slide()
		return

	if _state == DroneState.SEARCHING:
		_update_searching(delta)
	elif _state == DroneState.COMBAT:
		_update_combat(delta)


## SEARCHING state: scan for player with 360° vision (no FOV limit).
func _update_searching(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return

	# Check if player is invisible
	if _player.has_method("is_invisible") and _player.is_invisible():
		_drone_body.velocity = Vector2.ZERO
		_drone_body.move_and_slide()
		return

	# 360° vision: only need line-of-sight check, no FOV restriction
	if _has_line_of_sight_to_player():
		_transition_to_combat()
		return

	# Not detected yet: hover in place
	_drone_body.velocity = Vector2.ZERO
	_drone_body.move_and_slide()


## Check line-of-sight to player (360° vision, no FOV restriction).
func _has_line_of_sight_to_player() -> bool:
	if _player == null or not is_instance_valid(_player) or _drone_body == null:
		return false

	var space_state := _drone_body.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.new()
	query.from = _drone_body.global_position
	query.to = _player.global_position
	query.collision_mask = 4  # Only check obstacles (layer 3)
	query.exclude = [_drone_body.get_rid()]

	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return true  # No obstacle — player is visible

	var hit_pos: Vector2 = result["position"]
	var dist_to_hit := _drone_body.global_position.distance_to(hit_pos)
	var dist_to_player := _drone_body.global_position.distance_to(_player.global_position)
	return dist_to_hit >= dist_to_player - 10.0


## Transition from SEARCHING to COMBAT mode.
func _transition_to_combat() -> void:
	_state = DroneState.COMBAT
	_beep_timer = 0.0
	_beep_pattern_index = 0
	combat_activated.emit()
	FileLogger.info("[Drone] COMBAT mode activated — kamikaze flight toward player!")


## COMBAT state: fly toward player at 3× speed, drift on turns, explode on collision.
func _update_combat(delta: float) -> void:
	if _player == null or not is_instance_valid(_player) or _drone_body == null:
		_drone_body.velocity = Vector2.ZERO
		_drone_body.move_and_slide()
		return

	_update_beep(delta)

	var to_player: Vector2 = _player.global_position - _drone_body.global_position
	var distance: float = to_player.length()

	# Check for collision with player (kamikaze explosion)
	if distance <= COLLISION_DISTANCE:
		_explode()
		return

	# Calculate desired direction using NavigationAgent2D if available
	var desired_direction: Vector2 = Vector2.ZERO
	if _nav_agent:
		_nav_agent.target_position = _player.global_position
		var next_path_pos: Vector2 = _nav_agent.get_next_path_position()
		desired_direction = _drone_body.global_position.direction_to(next_path_pos)
	else:
		desired_direction = to_player.normalized()

	# Apply drift/inertia
	if _current_move_direction == Vector2.ZERO:
		_current_move_direction = desired_direction
	else:
		_current_move_direction = (_current_move_direction * DRIFT_FACTOR + desired_direction * (1.0 - DRIFT_FACTOR)).normalized()

	_drone_body.velocity = _current_move_direction * COMBAT_SPEED
	_drone_body.move_and_slide()

	# Check if we collided with the player via physics
	if _drone_body.get_slide_collision_count() > 0:
		for i in range(_drone_body.get_slide_collision_count()):
			var collision := _drone_body.get_slide_collision(i)
			var collider := collision.get_collider()
			if collider and collider.is_in_group("player"):
				_explode()
				return


## Update beeping sound in combat mode.
func _update_beep(delta: float) -> void:
	_beep_timer -= delta
	if _beep_timer <= 0.0:
		var beep_duration: float = _beep_pattern[_beep_pattern_index % _beep_pattern.size()]
		_play_beep_tone(beep_duration)
		_beep_pattern_index += 1
		_beep_timer = beep_duration + BEEP_INTERVAL


## Play a procedural beep tone.
func _play_beep_tone(duration: float) -> void:
	if _beep_player == null:
		return

	var sample_rate: int = 22050
	var num_samples: int = int(duration * sample_rate)
	if num_samples <= 0:
		return

	var audio_stream := AudioStreamWAV.new()
	audio_stream.format = AudioStreamWAV.FORMAT_16_BITS
	audio_stream.mix_rate = sample_rate
	audio_stream.stereo = false

	var data := PackedByteArray()
	data.resize(num_samples * 2)

	for i in range(num_samples):
		var t: float = float(i) / sample_rate
		var envelope: float = 1.0 - (float(i) / num_samples)
		var sample: float = sin(t * BEEP_FREQUENCY * TAU) * envelope * 0.5
		var sample_int: int = clampi(int(sample * 32767.0), -32768, 32767)
		data[i * 2] = sample_int & 0xFF
		data[i * 2 + 1] = (sample_int >> 8) & 0xFF

	audio_stream.data = data
	_beep_player.stream = audio_stream
	_beep_player.play()


## Explode the drone like an RPG rocket (same power, no wall penetration).
func _explode() -> void:
	if _has_exploded or not _is_alive or _drone_body == null:
		return
	_has_exploded = true
	_is_alive = false
	_hp = 0

	FileLogger.info("[Drone] EXPLODED at pos=%s (kamikaze)" % str(_drone_body.global_position))

	var explode_pos: Vector2 = _drone_body.global_position

	# Trigger Power Fantasy explosion effect
	var power_fantasy_manager: Node = _drone_body.get_node_or_null("/root/PowerFantasyEffectsManager")
	if power_fantasy_manager and power_fantasy_manager.has_method("on_grenade_exploded"):
		power_fantasy_manager.on_grenade_exploded()

	# Play explosion sound via SoundPropagation
	var sound_propagation: Node = _drone_body.get_node_or_null("/root/SoundPropagation")
	if sound_propagation and sound_propagation.has_method("emit_sound"):
		var viewport := _drone_body.get_viewport()
		var viewport_diagonal := 1469.0
		if viewport:
			var size := viewport.get_visible_rect().size
			viewport_diagonal = sqrt(size.x * size.x + size.y * size.y)
		sound_propagation.emit_sound(1, explode_pos, 1, _drone_body, viewport_diagonal * 2.0)

	# Play explosion sound via AudioManager
	var audio_manager: Node = _drone_body.get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_offensive_grenade_explosion"):
		audio_manager.play_offensive_grenade_explosion(explode_pos)

	# Damage entities in explosion radius
	_damage_entities_in_radius(explode_pos)

	# Spawn visual explosion effect
	_spawn_explosion_effect(explode_pos)

	# Scatter casings
	_scatter_casings(explode_pos)

	# Notify parent drone.gd to emit died signals and clean up
	drone_destroyed.emit()


## Damage entities within explosion radius using line-of-sight checks.
func _damage_entities_in_radius(explode_pos: Vector2) -> void:
	if _drone_body == null:
		return
	var space_state := _drone_body.get_world_2d().direct_space_state
	var tree := _drone_body.get_tree()
	if tree == null:
		return

	var enemies := tree.get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy == _drone_body:
			continue
		if enemy is Node2D and explode_pos.distance_to(enemy.global_position) <= EXPLOSION_RADIUS:
			if _has_explosion_los(space_state, explode_pos, enemy.global_position):
				_apply_explosion_damage(enemy, explode_pos)

	var players := tree.get_nodes_in_group("player")
	if players.size() > 0 and players[0] is Node2D:
		var player: Node2D = players[0]
		if explode_pos.distance_to(player.global_position) <= EXPLOSION_RADIUS:
			if _has_explosion_los(space_state, explode_pos, player.global_position):
				_apply_explosion_damage(player, explode_pos)


func _has_explosion_los(space_state: PhysicsDirectSpaceState2D, from_pos: Vector2, target_pos: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(from_pos, target_pos)
	query.collision_mask = 4
	return space_state.intersect_ray(query).is_empty()


func _apply_explosion_damage(entity: Node2D, explode_pos: Vector2) -> void:
	var hit_direction := (entity.global_position - explode_pos).normalized()
	if entity.has_method("on_hit_with_info"):
		for i in range(EXPLOSION_DAMAGE):
			entity.on_hit_with_info(hit_direction, null)
	elif entity.has_method("on_hit"):
		for i in range(EXPLOSION_DAMAGE):
			entity.on_hit()


## Spawn visual explosion effect.
func _spawn_explosion_effect(explode_pos: Vector2) -> void:
	if _drone_body == null:
		return
	var impact_manager: Node = _drone_body.get_node_or_null("/root/ImpactEffectsManager")
	if impact_manager and impact_manager.has_method("spawn_explosion_effect"):
		impact_manager.spawn_explosion_effect(explode_pos, EXPLOSION_RADIUS)
	else:
		_create_simple_explosion(explode_pos)


## Fallback simple explosion visual.
func _create_simple_explosion(explode_pos: Vector2) -> void:
	if _drone_body == null:
		return
	var flash := Sprite2D.new()
	var radius_int := int(EXPLOSION_RADIUS)
	var size := radius_int * 2
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(radius_int, radius_int)
	for x in range(size):
		for y in range(size):
			var pos := Vector2(x, y)
			var distance := pos.distance_to(center)
			if distance <= radius_int:
				var alpha := 1.0 - (distance / radius_int)
				image.set_pixel(x, y, Color(1.0, 0.5, 0.1, alpha))
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	flash.texture = ImageTexture.create_from_image(image)
	flash.global_position = explode_pos
	flash.modulate = Color(1.0, 0.5, 0.1, 0.9)
	flash.z_index = 100
	var tree := _drone_body.get_tree()
	if tree and tree.current_scene:
		tree.current_scene.add_child(flash)
		var tween := tree.create_tween()
		tween.tween_property(flash, "modulate:a", 0.0, 0.3)
		tween.tween_callback(flash.queue_free)


## Scatter casings near explosion point.
func _scatter_casings(explode_pos: Vector2) -> void:
	if _drone_body == null:
		return
	var tree := _drone_body.get_tree()
	if tree == null:
		return
	var casings := tree.get_nodes_in_group("casings")
	if casings.is_empty():
		return
	var space_state := _drone_body.get_world_2d().direct_space_state
	for casing in casings:
		if not is_instance_valid(casing) or not casing is RigidBody2D:
			continue
		var distance := explode_pos.distance_to(casing.global_position)
		if distance > EXPLOSION_RADIUS * 1.5:
			continue
		if not _has_explosion_los(space_state, explode_pos, casing.global_position):
			continue
		var dir := (casing.global_position - explode_pos).normalized().rotated(randf_range(-0.2, 0.2))
		var impulse_strength := 1500.0 * (1.0 - distance / (EXPLOSION_RADIUS * 1.5))
		if casing.has_method("receive_kick"):
			casing.receive_kick(dir * impulse_strength)


## Apply damage to the drone. Returns true if destroyed by this hit.
func take_damage(amount: int = 1) -> bool:
	if not _is_alive:
		return false
	_hp -= amount
	drone_hit.emit()
	FileLogger.info("[Drone] Took %d damage (hp=%d/%d)" % [amount, _hp, DRONE_HP])
	if _hp <= 0:
		_die()
		return true
	return false


## Destroy the drone (shot down, not exploded).
func _die() -> void:
	_is_alive = false
	_hp = 0
	FileLogger.info("[Drone] Destroyed!")
	drone_destroyed.emit()


## Check if the drone is alive.
func is_alive() -> bool:
	return _is_alive


## Check if the drone is in combat mode.
func is_in_combat() -> bool:
	return _state == DroneState.COMBAT


## Get current state.
func get_state() -> int:
	return _state
