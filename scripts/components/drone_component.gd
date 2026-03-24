class_name DroneComponent
extends Node
## Drone entity spawned by the Drone Operator enemy (Issue #1397, #1417).
##
## Two-phase behavior:
## 1. SEARCHING: Patrols/hovers, scanning for the player with 360° vision (unlimited FOV angle).
##    Uses line-of-sight raycast to detect the player through walls.
## 2. COMBAT: Once the player is detected, the drone activates combat mode:
##    - Red LED lights up, beeping/morse-code sound starts.
##    - Speed increases to 3× normal.
##    - Flies directly at the player (kamikaze).
##    - Uses NavigationAgent2D to navigate around obstacles, but drifts on turns due to high speed.
##    - On collision with the player: explodes like an RPG rocket (same power, no wall penetration).

## Health points of the drone.
const DRONE_HP: int = 2

## Movement speed of the drone in SEARCHING mode (px/s).
const SEARCH_SPEED: float = 150.0

## Combat speed multiplier (3× search speed per Issue #1417).
const COMBAT_SPEED_MULTIPLIER: float = 3.0

## Combat movement speed (px/s).
const COMBAT_SPEED: float = SEARCH_SPEED * COMBAT_SPEED_MULTIPLIER

## Hover height offset (visual only, for top-down appearance).
const HOVER_OFFSET: float = -20.0

## Drone detection range (px). 0 = unlimited.
const DETECTION_RANGE: float = 0.0

## Explosion radius (same as RPG rocket: 150 px).
const EXPLOSION_RADIUS: float = 150.0

## Explosion damage (same as RPG rocket: 3 HP).
const EXPLOSION_DAMAGE: int = 3

## Distance at which the drone collides with the player and explodes (px).
const COLLISION_DISTANCE: float = 24.0

## Drift/inertia factor: how much the drone resists changing direction in combat.
## 0.0 = instant turn, 1.0 = no turning at all. Higher = more drift.
const DRIFT_FACTOR: float = 0.85

## Beep interval in seconds (morse-code-like pattern).
const BEEP_INTERVAL: float = 0.3

## Beep frequency (Hz) for procedural tone generation.
const BEEP_FREQUENCY: float = 1200.0

## Beep duration per pip (seconds).
const BEEP_DURATION: float = 0.08

## Drone behavior states.
enum DroneState {
	SEARCHING,  ## Scanning for player with 360° vision
	COMBAT      ## Kamikaze flight toward player
}

## Signal emitted when drone is destroyed.
signal drone_destroyed

## Signal emitted when drone takes damage.
signal drone_hit

## Signal emitted when drone enters combat mode (for visual/audio updates).
signal combat_activated

## Current HP.
var _hp: int = DRONE_HP

## Whether the drone is alive.
var _is_alive: bool = true

## Current behavior state.
var _state: DroneState = DroneState.SEARCHING

## Reference to the drone's CharacterBody2D scene root.
var _drone_body: CharacterBody2D = null

## Reference to the player.
var _player: Node2D = null

## Reference to the operator who spawned this drone.
var _operator: Node2D = null

## Reference to the NavigationAgent2D for pathfinding (combat mode).
var _nav_agent: NavigationAgent2D = null

## Current movement direction (used for drift/inertia in combat).
var _current_move_direction: Vector2 = Vector2.ZERO

## Beep timer for morse-code-like sound pattern.
var _beep_timer: float = 0.0

## Beep pattern index (for morse-code-like variation).
var _beep_pattern_index: int = 0

## Morse-code-like beep pattern: short=0.08s, long=0.2s, pause=silence.
## Repeats: dot-dot-dash-dot (like letter "F" in morse) for "hostile drone" feel.
var _beep_pattern: Array[float] = [0.08, 0.08, 0.2, 0.08, 0.08, 0.2, 0.08, 0.08]

## Whether the drone has exploded (prevents double-explosion).
var _has_exploded: bool = false

## AudioStreamPlayer2D for beeping sound.
var _beep_player: AudioStreamPlayer2D = null

## Logging flag.
var debug_logging: bool = false


func _ready() -> void:
	_drone_body = get_parent() as CharacterBody2D
	_find_player()
	_find_nav_agent()
	_setup_beep_player()


## Initialize the drone with operator reference.
func initialize(operator: Node2D) -> void:
	_operator = operator
	FileLogger.info("[Drone] Initialized by operator: %s" % (operator.name if operator else "null"))


## Find the player in the scene tree.
func _find_player() -> void:
	if _drone_body == null:
		return
	var players: Array = _drone_body.get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]
	else:
		# Fallback: search for Player node
		var root: Node = _drone_body.get_tree().current_scene
		if root:
			_player = root.find_child("Player", true, false)


## Find the NavigationAgent2D child node.
func _find_nav_agent() -> void:
	if _drone_body == null:
		return
	_nav_agent = _drone_body.get_node_or_null("NavigationAgent2D") as NavigationAgent2D
	if _nav_agent:
		_nav_agent.path_desired_distance = 8.0
		_nav_agent.target_desired_distance = 8.0
		FileLogger.info("[Drone] NavigationAgent2D found and configured")
	else:
		FileLogger.info("[Drone] WARNING: No NavigationAgent2D found, using direct movement")


## Set up AudioStreamPlayer2D for beeping sound in combat mode.
func _setup_beep_player() -> void:
	if _drone_body == null:
		return
	_beep_player = AudioStreamPlayer2D.new()
	_beep_player.name = "DroneBeepPlayer"
	_beep_player.max_distance = 800.0
	_beep_player.attenuation = 2.0
	_beep_player.volume_db = -8.0
	_drone_body.add_child(_beep_player)


func _physics_process(delta: float) -> void:
	if not _is_alive or _drone_body == null:
		return

	if _player == null:
		_find_player()
		return

	match _state:
		DroneState.SEARCHING:
			_update_searching(delta)
		DroneState.COMBAT:
			_update_combat(delta)


## SEARCHING state: scan for player with 360° vision (no FOV limit).
func _update_searching(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return

	# Check if player is alive
	if _player.has_method("is_alive") and not _player.is_alive():
		_drone_body.velocity = Vector2.ZERO
		_drone_body.move_and_slide()
		return

	# Check if player is invisible
	if _player.has_method("is_invisible") and _player.is_invisible():
		_drone_body.velocity = Vector2.ZERO
		_drone_body.move_and_slide()
		return

	var to_player: Vector2 = _player.global_position - _drone_body.global_position
	var distance: float = to_player.length()

	# 360° vision: only need line-of-sight check, no FOV angle restriction
	if _has_line_of_sight_to_player():
		# Player detected! Transition to COMBAT.
		_transition_to_combat()
		return

	# Not detected yet: hover/patrol slowly in random direction
	# Simple wandering behavior while searching
	_drone_body.velocity = Vector2.ZERO
	_drone_body.move_and_slide()


## Check line-of-sight to player (no FOV restriction — 360° vision).
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

	# Check if obstacle is between drone and player
	var hit_pos: Vector2 = result["position"]
	var dist_to_hit := _drone_body.global_position.distance_to(hit_pos)
	var dist_to_player := _drone_body.global_position.distance_to(_player.global_position)
	return dist_to_hit >= dist_to_player - 10.0  # 10px tolerance


## Transition from SEARCHING to COMBAT mode.
func _transition_to_combat() -> void:
	_state = DroneState.COMBAT
	_beep_timer = 0.0
	_beep_pattern_index = 0
	combat_activated.emit()
	FileLogger.info("[Drone] COMBAT mode activated — kamikaze flight toward player!")


## COMBAT state: fly toward player at 3× speed, drift on turns, explode on collision.
func _update_combat(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_drone_body.velocity = Vector2.ZERO
		_drone_body.move_and_slide()
		return

	# Update beeping sound
	_update_beep(delta)

	var to_player: Vector2 = _player.global_position - _drone_body.global_position
	var distance: float = to_player.length()

	# Check for collision with player (kamikaze explosion)
	if distance <= COLLISION_DISTANCE:
		_explode()
		return

	# Calculate desired direction using NavigationAgent2D if available
	var desired_direction: Vector2 = Vector2.ZERO
	if _nav_agent and _nav_agent.is_navigation_finished() == false:
		_nav_agent.target_position = _player.global_position
		var next_path_pos: Vector2 = _nav_agent.get_next_path_position()
		desired_direction = (_drone_body.global_position.direction_to(next_path_pos))
	elif _nav_agent:
		_nav_agent.target_position = _player.global_position
		var next_path_pos: Vector2 = _nav_agent.get_next_path_position()
		desired_direction = (_drone_body.global_position.direction_to(next_path_pos))
	else:
		# Fallback: direct direction to player
		desired_direction = to_player.normalized()

	# Apply drift/inertia: the drone resists changing direction due to high speed.
	# At DRIFT_FACTOR=0.85, the drone preserves 85% of its current direction,
	# creating visible "sliding" on turns that looks like momentum.
	if _current_move_direction == Vector2.ZERO:
		_current_move_direction = desired_direction
	else:
		_current_move_direction = (_current_move_direction * DRIFT_FACTOR + desired_direction * (1.0 - DRIFT_FACTOR)).normalized()

	# Apply combat speed (3× search speed)
	_drone_body.velocity = _current_move_direction * COMBAT_SPEED
	_drone_body.move_and_slide()

	# Check if we collided with anything (wall, obstacle) — doesn't explode on walls, only player
	# But if move_and_slide hit something and we're very close to player, still explode
	if _drone_body.get_slide_collision_count() > 0:
		# Check if any collision is with the player
		for i in range(_drone_body.get_slide_collision_count()):
			var collision := _drone_body.get_slide_collision(i)
			var collider := collision.get_collider()
			if collider and collider.is_in_group("player"):
				_explode()
				return


## Update beeping sound in combat mode (morse-code-like pattern).
func _update_beep(delta: float) -> void:
	_beep_timer -= delta
	if _beep_timer <= 0.0:
		# Play next beep in pattern
		var beep_duration: float = _beep_pattern[_beep_pattern_index % _beep_pattern.size()]
		_play_beep_tone(beep_duration)

		# Advance pattern
		_beep_pattern_index += 1

		# Set timer: beep duration + gap
		_beep_timer = beep_duration + BEEP_INTERVAL


## Play a procedural beep tone using AudioStreamGenerator or simple approach.
func _play_beep_tone(duration: float) -> void:
	if _beep_player == null or _drone_body == null:
		return

	# Generate a simple sine wave beep
	var sample_rate: int = 22050
	var num_samples: int = int(duration * sample_rate)
	if num_samples <= 0:
		return

	var audio_stream := AudioStreamWAV.new()
	audio_stream.format = AudioStreamWAV.FORMAT_16_BITS
	audio_stream.mix_rate = sample_rate
	audio_stream.stereo = false

	var data := PackedByteArray()
	data.resize(num_samples * 2)  # 16-bit = 2 bytes per sample

	for i in range(num_samples):
		var t: float = float(i) / sample_rate
		# Sine wave with fade-out envelope
		var envelope: float = 1.0 - (float(i) / num_samples)
		var sample: float = sin(t * BEEP_FREQUENCY * TAU) * envelope * 0.5
		var sample_int: int = clampi(int(sample * 32767.0), -32768, 32767)
		# Store as little-endian 16-bit
		data[i * 2] = sample_int & 0xFF
		data[i * 2 + 1] = (sample_int >> 8) & 0xFF

	audio_stream.data = data
	_beep_player.stream = audio_stream
	_beep_player.play()


## Explode the drone like an RPG rocket (same power, no wall penetration).
func _explode() -> void:
	if _has_exploded or not _is_alive:
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

	# Damage entities in explosion radius (line-of-sight check, NO wall penetration)
	_damage_entities_in_radius(explode_pos)

	# Spawn visual explosion effect
	_spawn_explosion_effect(explode_pos)

	# Scatter casings
	_scatter_casings(explode_pos)

	# Emit destruction signal for operator
	drone_destroyed.emit()

	# Visual death and cleanup
	if _drone_body and is_instance_valid(_drone_body):
		_drone_body.set_physics_process(false)
		# Short delay for explosion visual, then remove
		var tween: Tween = _drone_body.create_tween()
		tween.tween_property(_drone_body, "modulate:a", 0.0, 0.15)
		tween.tween_callback(_drone_body.queue_free)


## Damage entities within explosion radius using line-of-sight checks.
## Does NOT penetrate walls (unlike RPG rocket which carves passages).
func _damage_entities_in_radius(explode_pos: Vector2) -> void:
	var space_state := _drone_body.get_world_2d().direct_space_state

	# Damage enemies
	var enemies := _drone_body.get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy == _drone_body:
			continue  # Don't damage self
		if enemy is Node2D and _is_in_radius(explode_pos, enemy.global_position):
			if _has_explosion_line_of_sight(space_state, explode_pos, enemy.global_position):
				_apply_damage(enemy, explode_pos)

	# Damage player
	var players := _drone_body.get_tree().get_nodes_in_group("player")
	if players.size() > 0 and players[0] is Node2D:
		var player: Node2D = players[0]
		if _is_in_radius(explode_pos, player.global_position) and _has_explosion_line_of_sight(space_state, explode_pos, player.global_position):
			_apply_damage(player, explode_pos)


## Check if a position is within explosion radius.
func _is_in_radius(center: Vector2, pos: Vector2) -> bool:
	return center.distance_to(pos) <= EXPLOSION_RADIUS


## Check line-of-sight for explosion damage (obstacles block damage).
func _has_explosion_line_of_sight(space_state: PhysicsDirectSpaceState2D, from_pos: Vector2, target_pos: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(from_pos, target_pos)
	query.collision_mask = 4  # Only check against obstacles
	return space_state.intersect_ray(query).is_empty()


## Apply explosion damage to an entity.
func _apply_damage(entity: Node2D, explode_pos: Vector2) -> void:
	var hit_direction := (entity.global_position - explode_pos).normalized()
	if entity.has_method("on_hit_with_info"):
		for i in range(EXPLOSION_DAMAGE):
			entity.on_hit_with_info(hit_direction, null)
	elif entity.has_method("on_hit"):
		for i in range(EXPLOSION_DAMAGE):
			entity.on_hit()


## Spawn visual explosion effect (reuses RPG explosion visual system).
func _spawn_explosion_effect(explode_pos: Vector2) -> void:
	var impact_manager: Node = _drone_body.get_node_or_null("/root/ImpactEffectsManager")
	if impact_manager and impact_manager.has_method("spawn_explosion_effect"):
		impact_manager.spawn_explosion_effect(explode_pos, EXPLOSION_RADIUS)
	else:
		_create_simple_explosion(explode_pos)


## Fallback simple explosion visual if ImpactEffectsManager is not available.
func _create_simple_explosion(explode_pos: Vector2) -> void:
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
	_drone_body.get_tree().current_scene.add_child(flash)
	var tween := _drone_body.get_tree().create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 0.3)
	tween.tween_callback(flash.queue_free)


## Scatter casings near explosion point (same as RPG rocket).
func _scatter_casings(explode_pos: Vector2) -> void:
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
		if not _has_explosion_line_of_sight(space_state, explode_pos, casing.global_position):
			continue
		var dir := (casing.global_position - explode_pos).normalized().rotated(randf_range(-0.2, 0.2))
		var impulse_strength := 1500.0 * (1.0 - distance / (EXPLOSION_RADIUS * 1.5))
		if casing.has_method("receive_kick"):
			casing.receive_kick(dir * impulse_strength)


## Apply damage to the drone.
## Returns true if the drone was destroyed by this hit.
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
	FileLogger.info("[Drone] Destroyed (shot down)!")
	drone_destroyed.emit()

	# Visual death: fade out and remove
	if _drone_body:
		var tween: Tween = _drone_body.create_tween()
		tween.tween_property(_drone_body, "modulate:a", 0.0, 0.3)
		tween.tween_callback(_drone_body.queue_free)


## Check if the drone is alive.
func is_alive() -> bool:
	return _is_alive


## Get current HP.
func get_hp() -> int:
	return _hp


## Get current state.
func get_state() -> DroneState:
	return _state


## Check if the drone is in combat mode.
func is_in_combat() -> bool:
	return _state == DroneState.COMBAT
