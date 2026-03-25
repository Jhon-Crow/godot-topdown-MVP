extends CharacterBody2D
## Drone entity spawned by the Drone Operator enemy (Issue #1397, #1417).
##
## Two-phase drone: starts in SEARCHING mode with 360° vision,
## transitions to COMBAT mode when player is detected.
## In combat: red LED, beeping sound, 3× speed kamikaze, drift on turns,
## explodes like RPG on player collision (no wall penetration).
##
## All AI logic is in this file (no separate DroneComponent) to avoid
## GDScript class_name cross-script dependency issues in exported builds.

## Signals matching the standard enemy interface for level tracking.
signal hit
signal died
signal died_with_info(is_ricochet_kill: bool, is_penetration_kill: bool, is_player_kill: bool)

## Drone behavior states.
enum DroneState {
	SEARCHING,  ## Scanning for player with 360° vision
	COMBAT      ## Kamikaze flight toward player
}

## Visual size of the drone body polygon.
const DRONE_BODY_SIZE: float = 10.0

## Rotor arm length from center.
const ROTOR_ARM_LENGTH: float = 12.0

## Rotor radius.
const ROTOR_RADIUS: float = 4.0

## Rotor rotation speed (radians/sec).
const ROTOR_SPEED: float = 20.0

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

## Drift/inertia factor for COMBAT direction.
const DRIFT_FACTOR: float = 0.85

## Beep interval in seconds.
const BEEP_INTERVAL: float = 0.3

## Beep frequency (Hz) for procedural tone.
const BEEP_FREQUENCY: float = 1200.0

## Beep duration per pip (seconds).
const BEEP_DURATION: float = 0.08

## Drone AI state.
var _state: DroneState = DroneState.SEARCHING

## Current HP.
var _hp: int = DRONE_HP

## Whether the drone is alive.
var _is_alive: bool = true

## Whether the drone has exploded.
var _has_exploded: bool = false

## Reference to the player.
var _player: Node2D = null

## Reference to the NavigationAgent2D for pathfinding.
var _nav_agent: NavigationAgent2D = null

## Reference to the operator who spawned this drone.
var _operator: Node2D = null

## Current movement direction (drift/inertia in combat).
var _current_move_direction: Vector2 = Vector2.ZERO

## Beep timer for morse-code-like sound pattern.
var _beep_timer: float = 0.0

## Beep pattern index.
var _beep_pattern_index: int = 0

## Morse-code-like beep pattern values.
var _beep_pattern: Array = [0.08, 0.08, 0.2, 0.08, 0.08, 0.2, 0.08, 0.08]

## AudioStreamPlayer2D for beeping sound.
var _beep_player: AudioStreamPlayer2D = null

## Rotor angle for animation.
var _rotor_angle: float = 0.0

## Stored rotor sprites for animation.
var _rotor_sprites: Array = []

## LED indicator polygon (changes color: green=searching, red=combat).
var _led: Polygon2D = null

## PointLight2D for LED glow in combat mode.
var _led_light: PointLight2D = null


func _ready() -> void:
	add_to_group("enemies")
	FileLogger.info("[Drone] _ready started")
	_find_nav_agent()
	_setup_drone_visual()
	_setup_beep_player()
	_find_player()
	FileLogger.info("[Drone] _ready complete (state=%s, player=%s, nav=%s)" % [
		DroneState.keys()[_state],
		(_player.name if _player else "null"),
		("found" if _nav_agent else "missing")
	])


## Initialize the drone with operator reference (called by DroneOperatorComponent).
func initialize_drone(operator: Node2D) -> void:
	_operator = operator
	FileLogger.info("[Drone] Initialized by operator: %s" % (operator.name if operator else "null"))


## Find the NavigationAgent2D child node.
func _find_nav_agent() -> void:
	_nav_agent = get_node_or_null("NavigationAgent2D") as NavigationAgent2D
	if _nav_agent:
		_nav_agent.path_desired_distance = 8.0
		_nav_agent.target_desired_distance = 8.0
		FileLogger.info("[Drone] NavigationAgent2D found and configured")
	else:
		FileLogger.info("[Drone] WARNING: No NavigationAgent2D, using direct movement")


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
	# Method 1: search by group
	var tree := get_tree()
	if tree == null:
		return
	var players: Array = tree.get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]
		FileLogger.info("[Drone] Player found via group: %s" % _player.name)
		return
	# Method 2: GameManager autoload
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm and gm.get("player") and is_instance_valid(gm.get("player")):
		_player = gm.player
		FileLogger.info("[Drone] Player found via GameManager: %s" % _player.name)
		return
	# Method 3: search by node name
	var root: Node = tree.current_scene
	if root:
		var found: Node = root.find_child("Player", true, false)
		if found:
			_player = found
			FileLogger.info("[Drone] Player found via find_child: %s" % _player.name)
			return
	FileLogger.info("[Drone] WARNING: Player not found, will retry in _physics_process")


## Create the top-down drone visual using Polygon2D shapes.
func _setup_drone_visual() -> void:
	var model: Node2D = $DroneModel
	if model == null:
		return

	# Main body: dark gray square/circle representing the drone chassis
	var body_poly := Polygon2D.new()
	body_poly.polygon = PackedVector2Array([
		Vector2(-DRONE_BODY_SIZE, -DRONE_BODY_SIZE),
		Vector2(DRONE_BODY_SIZE, -DRONE_BODY_SIZE),
		Vector2(DRONE_BODY_SIZE, DRONE_BODY_SIZE),
		Vector2(-DRONE_BODY_SIZE, DRONE_BODY_SIZE),
	])
	body_poly.color = Color(0.2, 0.2, 0.25, 0.9)
	body_poly.z_index = 1
	model.add_child(body_poly)

	# Camera lens on front
	var lens := Polygon2D.new()
	lens.polygon = PackedVector2Array([
		Vector2(DRONE_BODY_SIZE - 2, -3),
		Vector2(DRONE_BODY_SIZE + 3, -3),
		Vector2(DRONE_BODY_SIZE + 3, 3),
		Vector2(DRONE_BODY_SIZE - 2, 3),
	])
	lens.color = Color(0.1, 0.5, 0.9, 0.9)  # Blue camera lens
	lens.z_index = 2
	model.add_child(lens)

	# Four rotor arms + rotor circles (quadcopter layout)
	var arm_positions: Array = [
		Vector2(ROTOR_ARM_LENGTH, ROTOR_ARM_LENGTH),
		Vector2(ROTOR_ARM_LENGTH, -ROTOR_ARM_LENGTH),
		Vector2(-ROTOR_ARM_LENGTH, ROTOR_ARM_LENGTH),
		Vector2(-ROTOR_ARM_LENGTH, -ROTOR_ARM_LENGTH),
	]
	for pos in arm_positions:
		# Arm line
		var arm := Polygon2D.new()
		arm.polygon = PackedVector2Array([
			Vector2(-1, -1) + pos * 0.2,
			Vector2(1, -1) + pos * 0.2,
			Vector2(1, 1) + pos,
			Vector2(-1, 1) + pos,
		])
		arm.color = Color(0.3, 0.3, 0.35, 0.8)
		model.add_child(arm)

		# Rotor disc (semi-transparent circle approximation)
		var rotor := Polygon2D.new()
		var points: PackedVector2Array = PackedVector2Array()
		for i in range(8):
			var angle: float = i * TAU / 8.0
			points.append(pos + Vector2(cos(angle), sin(angle)) * ROTOR_RADIUS)
		rotor.polygon = points
		rotor.color = Color(0.5, 0.5, 0.6, 0.3)  # Semi-transparent rotor disc
		rotor.z_index = 3
		model.add_child(rotor)
		_rotor_sprites.append(rotor)

	# LED indicator light (green = searching, switches to red in combat)
	_led = Polygon2D.new()
	_led.polygon = PackedVector2Array([
		Vector2(-2, -2),
		Vector2(2, -2),
		Vector2(2, 2),
		Vector2(-2, 2),
	])
	_led.color = Color(0.2, 0.8, 0.2, 0.9)  # Green = searching
	_led.z_index = 4
	model.add_child(_led)

	# Prepare PointLight2D for combat mode glow (hidden initially)
	_led_light = PointLight2D.new()
	_led_light.name = "LEDGlow"
	_led_light.color = Color(1.0, 0.1, 0.1, 1.0)  # Red glow
	_led_light.energy = 0.0  # Hidden initially
	_led_light.texture = _create_light_texture()
	_led_light.texture_scale = 0.3
	_led_light.z_index = 5
	model.add_child(_led_light)

	FileLogger.info("[Drone] Visual setup complete (quadcopter style, LED=green/searching)")


## Create a simple radial gradient texture for the LED glow light.
func _create_light_texture() -> ImageTexture:
	var size: int = 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	var radius: float = size / 2.0
	for x in range(size):
		for y in range(size):
			var dist := Vector2(x, y).distance_to(center)
			if dist <= radius:
				var alpha := 1.0 - (dist / radius)
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha * alpha))
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(image)


func _physics_process(delta: float) -> void:
	if not _is_alive:
		return

	# Animate rotors
	_rotor_angle += 20.0 * delta
	var speed_mult: float = 3.0 if _state == DroneState.COMBAT else 1.0
	for rotor in _rotor_sprites:
		if is_instance_valid(rotor):
			rotor.color.a = 0.2 + 0.15 * abs(sin(_rotor_angle * speed_mult))

	# Pulse LED in combat mode
	if _state == DroneState.COMBAT and _led_light:
		_led_light.energy = 2.0 + 1.5 * abs(sin(_rotor_angle * 2.0))
		if _led:
			_led.color.a = 0.7 + 0.3 * abs(sin(_rotor_angle * 2.0))

	# Retry player search if needed
	if _player == null or not is_instance_valid(_player):
		_player = null
		_find_player()
		return

	# Check if player is alive via GameManager
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm and not gm.get("player_alive"):
		velocity = Vector2.ZERO
		move_and_slide()
		return

	match _state:
		DroneState.SEARCHING:
			_update_searching(delta)
		DroneState.COMBAT:
			_update_combat(delta)


## SEARCHING state: scan for player with 360° vision (no FOV limit).
func _update_searching(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return

	# Check if player is invisible
	if _player.has_method("is_invisible") and _player.is_invisible():
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# 360° vision: only need line-of-sight check, no FOV angle restriction
	if _has_line_of_sight_to_player():
		_transition_to_combat()
		return

	# Not detected yet: hover in place
	velocity = Vector2.ZERO
	move_and_slide()


## Check line-of-sight to player (no FOV restriction — 360° vision).
func _has_line_of_sight_to_player() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false

	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.new()
	query.from = global_position
	query.to = _player.global_position
	query.collision_mask = 4  # Only check obstacles (layer 3)
	query.exclude = [get_rid()]

	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return true  # No obstacle — player is visible

	var hit_pos: Vector2 = result["position"]
	var dist_to_hit := global_position.distance_to(hit_pos)
	var dist_to_player := global_position.distance_to(_player.global_position)
	return dist_to_hit >= dist_to_player - 10.0


## Transition from SEARCHING to COMBAT mode.
func _transition_to_combat() -> void:
	_state = DroneState.COMBAT
	_beep_timer = 0.0
	_beep_pattern_index = 0
	# Switch LED to red
	if _led:
		_led.color = Color(1.0, 0.1, 0.05, 0.95)
	if _led_light:
		_led_light.energy = 3.0
	FileLogger.info("[Drone] COMBAT mode activated — kamikaze flight toward player!")


## COMBAT state: fly toward player at 3× speed, drift on turns, explode on collision.
func _update_combat(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		velocity = Vector2.ZERO
		move_and_slide()
		return

	_update_beep(delta)

	var to_player: Vector2 = _player.global_position - global_position
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
		desired_direction = global_position.direction_to(next_path_pos)
	else:
		desired_direction = to_player.normalized()

	# Apply drift/inertia
	if _current_move_direction == Vector2.ZERO:
		_current_move_direction = desired_direction
	else:
		_current_move_direction = (_current_move_direction * DRIFT_FACTOR + desired_direction * (1.0 - DRIFT_FACTOR)).normalized()

	velocity = _current_move_direction * COMBAT_SPEED
	move_and_slide()

	# Check if we collided with the player
	if get_slide_collision_count() > 0:
		for i in range(get_slide_collision_count()):
			var collision := get_slide_collision(i)
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
	if _has_exploded or not _is_alive:
		return
	_has_exploded = true
	_is_alive = false
	_hp = 0

	FileLogger.info("[Drone] EXPLODED at pos=%s (kamikaze)" % str(global_position))

	var explode_pos: Vector2 = global_position

	# Trigger Power Fantasy explosion effect
	var power_fantasy_manager: Node = get_node_or_null("/root/PowerFantasyEffectsManager")
	if power_fantasy_manager and power_fantasy_manager.has_method("on_grenade_exploded"):
		power_fantasy_manager.on_grenade_exploded()

	# Play explosion sound via SoundPropagation
	var sound_propagation: Node = get_node_or_null("/root/SoundPropagation")
	if sound_propagation and sound_propagation.has_method("emit_sound"):
		var viewport := get_viewport()
		var viewport_diagonal := 1469.0
		if viewport:
			var size := viewport.get_visible_rect().size
			viewport_diagonal = sqrt(size.x * size.x + size.y * size.y)
		sound_propagation.emit_sound(1, explode_pos, 1, self, viewport_diagonal * 2.0)

	# Play explosion sound via AudioManager
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_offensive_grenade_explosion"):
		audio_manager.play_offensive_grenade_explosion(explode_pos)

	# Damage entities in explosion radius
	_damage_entities_in_radius(explode_pos)

	# Spawn visual explosion effect
	_spawn_explosion_effect(explode_pos)

	# Scatter casings
	_scatter_casings(explode_pos)

	# Notify operator and emit died signals
	died.emit()
	died_with_info.emit(false, false, false)

	set_physics_process(false)
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.15)
	tween.tween_callback(queue_free)


## Damage entities within explosion radius using line-of-sight checks.
func _damage_entities_in_radius(explode_pos: Vector2) -> void:
	var space_state := get_world_2d().direct_space_state

	var enemies := get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy == self:
			continue
		if enemy is Node2D and _is_in_radius(explode_pos, enemy.global_position):
			if _has_explosion_line_of_sight(space_state, explode_pos, enemy.global_position):
				_apply_explosion_damage(enemy, explode_pos)

	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0 and players[0] is Node2D:
		var player: Node2D = players[0]
		if _is_in_radius(explode_pos, player.global_position) and _has_explosion_line_of_sight(space_state, explode_pos, player.global_position):
			_apply_explosion_damage(player, explode_pos)


func _is_in_radius(center: Vector2, pos: Vector2) -> bool:
	return center.distance_to(pos) <= EXPLOSION_RADIUS


func _has_explosion_line_of_sight(space_state: PhysicsDirectSpaceState2D, from_pos: Vector2, target_pos: Vector2) -> bool:
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
	var impact_manager: Node = get_node_or_null("/root/ImpactEffectsManager")
	if impact_manager and impact_manager.has_method("spawn_explosion_effect"):
		impact_manager.spawn_explosion_effect(explode_pos, EXPLOSION_RADIUS)
	else:
		_create_simple_explosion(explode_pos)


## Fallback simple explosion visual.
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
	get_tree().current_scene.add_child(flash)
	var tween := get_tree().create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 0.3)
	tween.tween_callback(flash.queue_free)


## Scatter casings near explosion point.
func _scatter_casings(explode_pos: Vector2) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var casings := tree.get_nodes_in_group("casings")
	if casings.is_empty():
		return
	var space_state := get_world_2d().direct_space_state
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


## Called when hit by a projectile (basic).
func on_hit() -> void:
	if not _is_alive:
		return
	hit.emit()
	_hp -= 1
	FileLogger.info("[Drone] on_hit: hp=%d/%d" % [_hp, DRONE_HP])
	if _hp <= 0:
		_die(false, false, false)


## Called when hit by a projectile with direction and caliber info.
func on_hit_with_info(_hit_direction: Vector2, _caliber_data: Resource) -> void:
	on_hit()


## Called when hit by a projectile with full bullet info.
func on_hit_with_bullet_info(_hit_direction: Vector2, _caliber_data: Resource, has_ricocheted: bool, has_penetrated: bool, bullet_damage: float = 1.0, is_from_player: bool = false) -> void:
	if not _is_alive:
		return
	hit.emit()
	var dmg: int = maxi(int(round(bullet_damage)), 1)
	_hp -= dmg
	FileLogger.info("[Drone] on_hit_with_bullet_info: dmg=%d, hp=%d/%d" % [dmg, _hp, DRONE_HP])
	if _hp <= 0:
		_die(has_ricocheted, has_penetrated, is_from_player)


## Handle drone death (shot down, not exploded).
func _die(is_ricochet_kill: bool, is_penetration_kill: bool, is_player_kill: bool) -> void:
	_is_alive = false
	died.emit()
	died_with_info.emit(is_ricochet_kill, is_penetration_kill, is_player_kill)
	FileLogger.info("[Drone] Died (ricochet=%s, penetration=%s, player=%s)" % [
		str(is_ricochet_kill), str(is_penetration_kill), str(is_player_kill)
	])
	set_physics_process(false)
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)


## Check if the drone is alive (used by collision system).
func is_alive() -> bool:
	return _is_alive


## Check if the drone is in combat mode (used by operator).
func is_in_combat() -> bool:
	return _state == DroneState.COMBAT
