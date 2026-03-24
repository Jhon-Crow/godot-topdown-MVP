class_name DroneComponent
extends Node
## Drone combat AI component (Issue #1397, #1417).
##
## Two-phase behavior:
## 1. SEARCHING: Hovers/patrols, scanning for the player with 360° vision
##    and unlimited range. LED is green. Uses line-of-sight raycasting.
## 2. COMBAT: After detecting the player, LED turns red, beeping starts,
##    drone accelerates to 3x speed and flies at the player to ram them.
##    Uses NavigationAgent2D for obstacle avoidance with momentum-based
##    drift on turns. On collision with the player, explodes like an RPG
##    rocket (150px radius, 3 damage) but does NOT penetrate walls.

## Drone AI states.
enum DroneState {
	SEARCHING,  ## Scanning for player with 360° vision
	COMBAT      ## Locked on, charging at player at 3x speed
}

## Health points of the drone.
const DRONE_HP: int = 2

## Movement speed of the drone in SEARCHING mode (px/s).
const DRONE_SPEED: float = 150.0

## Speed multiplier in COMBAT mode (3x per issue #1417).
const COMBAT_SPEED_MULTIPLIER: float = 3.0

## Combat speed = DRONE_SPEED * COMBAT_SPEED_MULTIPLIER.
const COMBAT_SPEED: float = DRONE_SPEED * COMBAT_SPEED_MULTIPLIER

## Hover height offset (visual only, for top-down appearance).
const HOVER_OFFSET: float = -20.0

## Drone detection range (px). 0 = unlimited (line-of-sight only).
const DETECTION_RANGE: float = 0.0

## Detection confirmation delay (seconds) before entering COMBAT.
const DETECTION_DELAY: float = 0.3

## Drift turn factor — how quickly the drone's velocity catches up to desired
## direction in COMBAT. Lower = more drift. Range: 0.0 (no turning) to 1.0 (instant).
const DRIFT_TURN_FACTOR: float = 0.03

## Explosion radius (same as RPG rocket, Issue #583).
const EXPLOSION_RADIUS: float = 150.0

## Explosion damage (same as RPG rocket).
const EXPLOSION_DAMAGE: int = 3

## Collision distance to trigger explosion in COMBAT mode (px).
const COLLISION_DISTANCE: float = 30.0

## Beep frequency in Hz for COMBAT mode.
const BEEP_FREQUENCY: float = 880.0

## Beep duration (seconds).
const BEEP_DURATION: float = 0.06

## Interval between beeps in COMBAT mode (morse-code feel).
const BEEP_INTERVAL_SHORT: float = 0.15

## Longer interval between beep groups.
const BEEP_INTERVAL_LONG: float = 0.5

## Number of short beeps before a long pause.
const BEEPS_PER_GROUP: int = 3

## Searching patrol radius around spawn point (px).
const SEARCH_PATROL_RADIUS: float = 80.0

## Searching patrol speed multiplier (slower than base speed).
const SEARCH_PATROL_SPEED: float = 0.5

## Navigation path recalculation interval (seconds).
const NAV_UPDATE_INTERVAL: float = 0.2

## Signal emitted when drone is destroyed.
signal drone_destroyed

## Signal emitted when drone takes damage.
signal drone_hit

## Signal emitted when drone enters COMBAT mode (for LED/sound changes).
signal combat_entered

## Signal emitted when drone explodes on contact.
signal drone_exploded

## Current HP.
var _hp: int = DRONE_HP

## Whether the drone is alive.
var _is_alive: bool = true

## Current AI state.
var _state: DroneState = DroneState.SEARCHING

## Reference to the drone's CharacterBody2D scene root.
var _drone_body: CharacterBody2D = null

## Reference to the player.
var _player: Node2D = null

## Reference to the operator who spawned this drone.
var _operator: Node2D = null

## Detection timer — accumulates while player is in line-of-sight.
var _detection_timer: float = 0.0

## Whether detection has been confirmed.
var _detection_confirmed: bool = false

## Spawn/home position for patrol movement.
var _home_position: Vector2 = Vector2.ZERO

## Current patrol angle around home position.
var _patrol_angle: float = 0.0

## NavigationAgent2D reference for pathfinding.
var _nav_agent: NavigationAgent2D = null

## RayCast2D reference for line-of-sight checks.
var _raycast: RayCast2D = null

## Current actual velocity direction (for drift effect).
var _actual_direction: Vector2 = Vector2.ZERO

## Beep timer for combat sound.
var _beep_timer: float = 0.0

## Current beep count within group.
var _beep_count: int = 0

## AudioStreamPlayer for beeping.
var _audio_player: AudioStreamPlayer = null

## Navigation path update timer.
var _nav_timer: float = 0.0

## Whether the drone has exploded.
var _has_exploded: bool = false

## Logging flag.
var debug_logging: bool = false


func _ready() -> void:
	FileLogger.info("[Drone] DroneComponent _ready started")
	_drone_body = get_parent() as CharacterBody2D
	if _drone_body:
		_nav_agent = _drone_body.get_node_or_null("NavigationAgent2D") as NavigationAgent2D
		_raycast = _drone_body.get_node_or_null("RayCast2D") as RayCast2D
		# Setup audio player for beeping (defer to avoid add_child during _ready issues)
		call_deferred("_setup_audio_player")
		FileLogger.info("[Drone] _ready: body=%s, nav=%s, ray=%s, pos=%s" % [
			str(_drone_body != null), str(_nav_agent != null), str(_raycast != null),
			str(_drone_body.global_position)])
	else:
		FileLogger.info("[Drone] _ready: ERROR - no CharacterBody2D parent!")
	if _nav_agent:
		_nav_agent.path_desired_distance = 20.0
		_nav_agent.target_desired_distance = 20.0
	# Defer player search and home position to ensure scene tree is fully ready
	call_deferred("_deferred_init")


## Deferred audio player setup — avoids add_child during _ready.
func _setup_audio_player() -> void:
	if _drone_body == null or not is_instance_valid(_drone_body):
		return
	_audio_player = AudioStreamPlayer.new()
	_audio_player.name = "DroneBeepPlayer"
	_audio_player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	_drone_body.add_child(_audio_player)


## Deferred initialization — runs after the scene tree is fully ready.
func _deferred_init() -> void:
	if _drone_body and is_instance_valid(_drone_body):
		_home_position = _drone_body.global_position
		FileLogger.info("[Drone] Deferred init: home_position=%s" % str(_home_position))
	_find_player()
	if _player:
		FileLogger.info("[Drone] Player found: %s at %s" % [_player.name, str(_player.global_position)])
	else:
		FileLogger.info("[Drone] WARNING: Player not found in scene tree!")


## Initialize the drone with operator reference.
func initialize(operator: Node2D) -> void:
	_operator = operator
	# Try to get player reference from operator's enemy AI
	if _player == null and operator and operator.get("_player") != null:
		_player = operator.get("_player")
	FileLogger.info("[Drone] Initialized by operator: %s, player found: %s" % [
		operator.name if operator else "null",
		str(_player != null)])


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


## Periodic log timer to avoid spamming.
var _log_timer: float = 0.0

func _physics_process(delta: float) -> void:
	if not _is_alive or _drone_body == null or _has_exploded:
		return

	if _player == null:
		_find_player()
		if _player == null:
			_log_timer += delta
			if _log_timer >= 2.0:
				_log_timer = 0.0
				FileLogger.info("[Drone] Still searching for player node...")
			return

	match _state:
		DroneState.SEARCHING:
			_process_searching(delta)
		DroneState.COMBAT:
			_process_combat(delta)


## SEARCHING state: patrol near home position, scan for player with 360° vision.
func _process_searching(delta: float) -> void:
	# Check player visibility (360° FOV, unlimited range, line-of-sight only)
	var can_see_player := _check_player_visibility()

	if can_see_player:
		_detection_timer += delta
		if _detection_timer >= DETECTION_DELAY:
			_transition_to_combat()
			return
	else:
		if _detection_timer > 0.0:
			FileLogger.info("[Drone] Lost sight of player (detection timer was %.2f)" % _detection_timer)
		_detection_timer = 0.0

	# Patrol: circle around home position
	_patrol_angle += delta * 0.5  # Slow rotation
	var patrol_target := _home_position + Vector2(
		cos(_patrol_angle) * SEARCH_PATROL_RADIUS,
		sin(_patrol_angle) * SEARCH_PATROL_RADIUS
	)

	var direction := (patrol_target - _drone_body.global_position)
	var distance := direction.length()

	if distance > 5.0:
		direction = direction.normalized()
		_drone_body.velocity = direction * DRONE_SPEED * SEARCH_PATROL_SPEED
		_actual_direction = direction
	else:
		_drone_body.velocity = Vector2.ZERO

	_drone_body.move_and_slide()


## Check if the player is visible using line-of-sight raycast.
## 360° FOV (no angle restriction), unlimited range.
func _check_player_visibility() -> bool:
	if _player == null or not is_instance_valid(_player) or _drone_body == null:
		return false

	# Check if player is invisible
	if _player.has_method("is_invisible") and _player.is_invisible():
		return false

	# Check if player is alive
	if _player.has_method("is_alive") and not _player.is_alive():
		return false

	# Line-of-sight check using raycast
	if _raycast:
		_raycast.target_position = _raycast.to_local(_player.global_position)
		_raycast.force_raycast_update()

		if not _raycast.is_colliding():
			return true  # Clear line of sight

		# Check if the collider is the player or child of player
		var collider := _raycast.get_collider()
		if collider == _player:
			return true
		if collider:
			var parent: Node = collider.get_parent()
			while parent:
				if parent == _player:
					return true
				parent = parent.get_parent()
		return false
	else:
		# Fallback without raycast: use physics space query
		var space_state := _drone_body.get_world_2d().direct_space_state
		var query := PhysicsRayQueryParameters2D.create(
			_drone_body.global_position,
			_player.global_position
		)
		query.collision_mask = 4  # Obstacles only
		query.exclude = [_drone_body]
		return space_state.intersect_ray(query).is_empty()


## Transition from SEARCHING to COMBAT.
func _transition_to_combat() -> void:
	_state = DroneState.COMBAT
	_detection_confirmed = true
	_beep_timer = 0.0
	_beep_count = 0
	_actual_direction = (_player.global_position - _drone_body.global_position).normalized()
	# Initialize navigation target immediately
	if _nav_agent:
		_nav_agent.target_position = _player.global_position
	combat_entered.emit()
	FileLogger.info("[Drone] COMBAT mode activated! Target: player at %s" % str(_player.global_position))


## COMBAT state: charge at player at 3x speed with drift on turns.
func _process_combat(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return

	# Play beeping sound
	_update_beeping(delta)

	# Check for collision with player
	var distance_to_player := _drone_body.global_position.distance_to(_player.global_position)
	if distance_to_player <= COLLISION_DISTANCE:
		_explode()
		return

	# Calculate desired direction toward player
	var desired_direction: Vector2

	# Update navigation target periodically
	_nav_timer += delta
	if _nav_timer >= NAV_UPDATE_INTERVAL:
		_nav_timer = 0.0
		if _nav_agent:
			_nav_agent.target_position = _player.global_position

	# Use NavigationAgent2D for pathfinding if available and has a valid path
	if _nav_agent:
		var next_pos := _nav_agent.get_next_path_position()
		var nav_dir := _drone_body.global_position.direction_to(next_pos)
		# Only use nav path if it gives a meaningful direction
		if nav_dir.length() > 0.01:
			desired_direction = nav_dir
		else:
			desired_direction = (_player.global_position - _drone_body.global_position).normalized()
	else:
		# Direct path to player (no navigation)
		desired_direction = (_player.global_position - _drone_body.global_position).normalized()

	# Apply drift: actual direction slowly catches up to desired direction
	# This creates the "sliding on turns" effect at high speed
	if _actual_direction == Vector2.ZERO:
		_actual_direction = desired_direction
	else:
		_actual_direction = _actual_direction.lerp(desired_direction, DRIFT_TURN_FACTOR).normalized()

	# Apply velocity with combat speed
	_drone_body.velocity = _actual_direction * COMBAT_SPEED

	# Rotate drone body to face movement direction
	if _drone_body.has_node("DroneModel"):
		var model := _drone_body.get_node("DroneModel") as Node2D
		if model:
			model.rotation = _actual_direction.angle()

	_drone_body.move_and_slide()


## Update beeping sound in COMBAT mode (morse-code-like pattern).
func _update_beeping(delta: float) -> void:
	_beep_timer -= delta
	if _beep_timer <= 0.0:
		_play_beep()
		_beep_count += 1
		if _beep_count >= BEEPS_PER_GROUP:
			_beep_count = 0
			_beep_timer = BEEP_INTERVAL_LONG
		else:
			_beep_timer = BEEP_INTERVAL_SHORT


## Play a single beep using AudioStreamGenerator.
func _play_beep() -> void:
	if _audio_player == null:
		return

	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 44100.0
	generator.buffer_length = 0.1

	_audio_player.stream = generator
	_audio_player.volume_db = -12.0
	_audio_player.play()

	var playback: AudioStreamGeneratorPlayback = _audio_player.get_stream_playback()

	var sample_rate: float = 44100.0
	var num_samples: int = int(BEEP_DURATION * sample_rate)

	for i in range(num_samples):
		var t: float = float(i) / sample_rate
		var envelope: float = 1.0 - (float(i) / float(num_samples))
		envelope = envelope * envelope
		var sample: float = sin(2.0 * PI * BEEP_FREQUENCY * t) * envelope * 0.3
		playback.push_frame(Vector2(sample, sample))


## Explode the drone (RPG-strength, no wall penetration).
func _explode() -> void:
	if _has_exploded or not _is_alive:
		return
	_has_exploded = true
	_is_alive = false
	_hp = 0

	FileLogger.info("[Drone] EXPLODED at %s (RPG-strength, radius=%.0f, damage=%d)" % [
		str(_drone_body.global_position), EXPLOSION_RADIUS, EXPLOSION_DAMAGE
	])

	drone_exploded.emit()
	drone_destroyed.emit()

	# Trigger Power Fantasy rocket explosion effect
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
		sound_propagation.emit_sound(1, _drone_body.global_position, 1, _drone_body, viewport_diagonal * 2.0)

	# Play explosion sound via AudioManager
	var audio_manager: Node = _drone_body.get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_offensive_grenade_explosion"):
		audio_manager.play_offensive_grenade_explosion(_drone_body.global_position)

	# Damage entities in explosion radius (with line-of-sight, NO wall penetration)
	_damage_entities_in_radius()

	# Spawn visual explosion effect
	_spawn_explosion_effect()

	# Scatter nearby casings
	_scatter_casings()

	# Stop beeping
	if _audio_player and _audio_player.playing:
		_audio_player.stop()

	# Destroy drone after short delay for effects
	if _drone_body and is_instance_valid(_drone_body):
		var tween: Tween = _drone_body.create_tween()
		tween.tween_property(_drone_body, "modulate:a", 0.0, 0.15)
		tween.tween_callback(_drone_body.queue_free)


## Damage all entities within explosion radius (line-of-sight blocked by walls).
func _damage_entities_in_radius() -> void:
	if _drone_body == null:
		return
	var space_state := _drone_body.get_world_2d().direct_space_state
	var explosion_pos := _drone_body.global_position

	# Damage enemies
	var enemies := _drone_body.get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy == _drone_body:
			continue  # Don't damage self
		if enemy is Node2D and _is_in_radius(enemy.global_position, explosion_pos):
			if _has_line_of_sight(space_state, explosion_pos, enemy.global_position):
				_apply_damage(enemy, explosion_pos)

	# Damage player
	var players := _drone_body.get_tree().get_nodes_in_group("player")
	if players.size() > 0 and players[0] is Node2D:
		var player: Node2D = players[0]
		if _is_in_radius(player.global_position, explosion_pos):
			if _has_line_of_sight(space_state, explosion_pos, player.global_position):
				_apply_damage(player, explosion_pos)


## Check if position is within explosion radius.
func _is_in_radius(pos: Vector2, center: Vector2) -> bool:
	return center.distance_to(pos) <= EXPLOSION_RADIUS


## Check line-of-sight from explosion center to target (obstacles block damage).
func _has_line_of_sight(space_state: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collision_mask = 4  # Obstacles only
	if _drone_body:
		query.exclude = [_drone_body]
	return space_state.intersect_ray(query).is_empty()


## Apply explosion damage to an entity.
func _apply_damage(entity: Node2D, explosion_pos: Vector2) -> void:
	var hit_direction := (entity.global_position - explosion_pos).normalized()
	if entity.has_method("on_hit_with_info"):
		for i in range(EXPLOSION_DAMAGE):
			entity.on_hit_with_info(hit_direction, null)
	elif entity.has_method("on_hit"):
		for i in range(EXPLOSION_DAMAGE):
			entity.on_hit()


## Spawn visual explosion effect.
func _spawn_explosion_effect() -> void:
	if _drone_body == null:
		return
	var impact_manager: Node = _drone_body.get_node_or_null("/root/ImpactEffectsManager")
	if impact_manager and impact_manager.has_method("spawn_explosion_effect"):
		impact_manager.spawn_explosion_effect(_drone_body.global_position, EXPLOSION_RADIUS)
	else:
		_create_simple_explosion()


## Fallback simple explosion visual.
func _create_simple_explosion() -> void:
	if _drone_body == null:
		return
	var flash := Sprite2D.new()
	flash.texture = _create_explosion_texture(int(EXPLOSION_RADIUS))
	flash.global_position = _drone_body.global_position
	flash.modulate = Color(1.0, 0.5, 0.1, 0.9)
	flash.z_index = 100
	_drone_body.get_tree().current_scene.add_child(flash)
	var tween := _drone_body.get_tree().create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 0.3)
	tween.tween_callback(flash.queue_free)


## Create a procedural radial gradient texture for explosion.
func _create_explosion_texture(radius: int) -> ImageTexture:
	var size := radius * 2
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(radius, radius)
	for x in range(size):
		for y in range(size):
			var pos := Vector2(x, y)
			var distance := pos.distance_to(center)
			if distance <= radius:
				var alpha := 1.0 - (distance / radius)
				image.set_pixel(x, y, Color(1.0, 0.5, 0.1, alpha))
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(image)


## Scatter nearby casings from explosion force.
func _scatter_casings() -> void:
	if _drone_body == null:
		return
	var casings := _drone_body.get_tree().get_nodes_in_group("casings")
	if casings.is_empty():
		return
	var space_state := _drone_body.get_world_2d().direct_space_state
	var explosion_pos := _drone_body.global_position
	for casing in casings:
		if not is_instance_valid(casing) or not casing is RigidBody2D:
			continue
		var distance := explosion_pos.distance_to(casing.global_position)
		if distance > EXPLOSION_RADIUS * 1.5:
			continue
		if not _has_line_of_sight(space_state, explosion_pos, casing.global_position):
			continue
		var dir := (casing.global_position - explosion_pos).normalized().rotated(randf_range(-0.2, 0.2))
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


## Destroy the drone (non-explosion death, e.g. shot down).
func _die() -> void:
	_is_alive = false
	_hp = 0
	FileLogger.info("[Drone] Destroyed (shot down)!")
	drone_destroyed.emit()

	# Stop beeping
	if _audio_player and _audio_player.playing:
		_audio_player.stop()

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


## Check if drone is in combat mode.
func is_in_combat() -> bool:
	return _state == DroneState.COMBAT
