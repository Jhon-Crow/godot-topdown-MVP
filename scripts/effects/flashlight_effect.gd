extends Node2D
## Tactical flashlight effect attached to the player's weapon.
##
## Creates a directional beam of bright white light from the weapon barrel.
## Uses PointLight2D with shadow_enabled = true so light doesn't pass through walls.
## The light is toggled on/off by holding the Space key (flashlight_toggle action).
##
## The flashlight is positioned at the weapon barrel offset and rotates
## with the player model to always point in the aiming direction.
##
## When the flashlight beam hits an enemy directly, the enemy is blinded
## for 2 seconds. Each enemy has a 20-second cooldown before it can be blinded again.

## Light energy (brightness) when the flashlight is on.
## Bright white light — same level as flashbang (8.0) for clear visibility.
const LIGHT_ENERGY: float = 8.0

## Texture scale for the 6-degree cone beam range.
## Higher values make the narrow beam reach further.
const LIGHT_TEXTURE_SCALE: float = 6.0

## Flashlight beam half-angle in degrees.
## 18 degrees total beam = 9 degrees each side from center.
## The actual cone shape is pre-baked in the texture (flashlight_cone_18deg.png).
const BEAM_HALF_ANGLE_DEG: float = 9.0

## Maximum range (in pixels) for the flashlight beam to blind enemies.
## Based on texture size (2048) scaled by texture_scale (6.0) / 2.
## Capped at a practical gameplay distance.
const BEAM_RANGE: float = 600.0

## Duration of the blindness effect in seconds.
const BLINDNESS_DURATION: float = 2.0

## Cooldown in seconds before the same enemy can be blinded again.
const BLINDNESS_COOLDOWN: float = 20.0

## Path to the flashlight toggle sound file.
const FLASHLIGHT_SOUND_PATH: String = "res://assets/audio/звук включения и выключения фанарика.mp3"

## Collision mask for obstacles (layer 3) used in line-of-sight checks.
const OBSTACLE_COLLISION_MASK: int = 4

## Safety margin (pixels) to pull the light back from a wall hit point.
## Prevents the light from sitting exactly on the occluder edge.
const WALL_SAFETY_MARGIN: float = 2.0

## Reference to the PointLight2D child node.
var _point_light: PointLight2D = null

## Whether the flashlight is currently active (on).
var _is_on: bool = false

## AudioStreamPlayer for flashlight toggle sound.
var _audio_player: AudioStreamPlayer = null

## Tracks when each enemy was last blinded (instance_id -> timestamp in msec).
## Used to enforce the per-enemy cooldown period.
var _blinded_enemies: Dictionary = {}


func _ready() -> void:
	_point_light = get_node_or_null("PointLight2D")
	if _point_light == null:
		FileLogger.info("[FlashlightEffect] WARNING: PointLight2D child not found")
	else:
		FileLogger.info("[FlashlightEffect] PointLight2D found, energy=%.1f, shadow=%s" % [_point_light.energy, str(_point_light.shadow_enabled)])
	# Start with light off
	_set_light_visible(false)
	# Load toggle sound
	_setup_audio()


## Set up the audio player for flashlight toggle sound.
func _setup_audio() -> void:
	if ResourceLoader.exists(FLASHLIGHT_SOUND_PATH):
		var stream = load(FLASHLIGHT_SOUND_PATH)
		if stream:
			_audio_player = AudioStreamPlayer.new()
			_audio_player.stream = stream
			_audio_player.volume_db = 0.0
			add_child(_audio_player)
			FileLogger.info("[FlashlightEffect] Flashlight sound loaded")
	else:
		FileLogger.info("[FlashlightEffect] Flashlight sound not found: %s" % FLASHLIGHT_SOUND_PATH)


## Play the flashlight toggle sound.
func _play_toggle_sound() -> void:
	if _audio_player and is_instance_valid(_audio_player):
		_audio_player.play()


## Turn the flashlight on.
func turn_on() -> void:
	if _is_on:
		return
	_is_on = true
	_set_light_visible(true)
	_play_toggle_sound()


## Turn the flashlight off.
func turn_off() -> void:
	if not _is_on:
		return
	_is_on = false
	_set_light_visible(false)
	_play_toggle_sound()


## Check if the flashlight is currently on.
func is_on() -> bool:
	return _is_on


## Set the light visibility and energy.
func _set_light_visible(visible_state: bool) -> void:
	if _point_light:
		_point_light.visible = visible_state
		_point_light.energy = LIGHT_ENERGY if visible_state else 0.0


## Prevent the PointLight2D from penetrating walls when the player stands
## close to a wall. Raycasts from the player's center toward the flashlight's
## default position; if a wall is in the way, the light is pulled back.
func _clamp_light_to_walls() -> void:
	if _point_light == null:
		return
	# The hierarchy is: Player (CharacterBody2D) -> PlayerModel -> FlashlightEffect -> PointLight2D
	# get_parent() is PlayerModel, get_parent().get_parent() is the Player node.
	var player_model := get_parent()
	if player_model == null:
		return
	var player := player_model.get_parent()
	if player == null:
		return

	var player_center: Vector2 = player.global_position
	var intended_pos: Vector2 = global_position  # FlashlightEffect's default global pos (at barrel offset)
	var to_light: Vector2 = intended_pos - player_center
	var dist: float = to_light.length()

	if dist < 1.0:
		# Light is at player center, nothing to clamp
		_point_light.position = Vector2.ZERO
		return

	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(player_center, intended_pos)
	query.collision_mask = OBSTACLE_COLLISION_MASK
	var result := space_state.intersect_ray(query)

	if result.is_empty():
		# No wall between player and flashlight position — use default
		_point_light.position = Vector2.ZERO
	else:
		# Wall hit: pull the light back to just before the wall
		var hit_pos: Vector2 = result["position"]
		var direction: Vector2 = to_light.normalized()
		var safe_pos: Vector2 = hit_pos - direction * WALL_SAFETY_MARGIN
		# Convert to local coordinates of FlashlightEffect node
		_point_light.global_position = safe_pos


func _physics_process(_delta: float) -> void:
	_clamp_light_to_walls()
	if not _is_on:
		return
	_check_enemies_in_beam()


## Check all enemies and blind those caught in the flashlight beam.
## Each enemy can only be blinded once per cooldown period (20 seconds).
func _check_enemies_in_beam() -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	var current_time: int = Time.get_ticks_msec()
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue

		var enemy_id: int = enemy.get_instance_id()
		if _blinded_enemies.has(enemy_id):
			var last_blinded: int = int(_blinded_enemies[enemy_id])
			var elapsed_sec: float = float(current_time - last_blinded) / 1000.0
			if elapsed_sec < BLINDNESS_COOLDOWN:
				continue

		if _is_enemy_in_beam(enemy):
			_blind_enemy(enemy)


## Check if an enemy is within the flashlight beam cone and has line of sight.
func _is_enemy_in_beam(enemy: Node2D) -> bool:
	var beam_origin := global_position
	var beam_direction := Vector2.RIGHT.rotated(global_rotation)
	var to_enemy := enemy.global_position - beam_origin
	var distance := to_enemy.length()

	# Check range
	if distance > BEAM_RANGE or distance < 1.0:
		return false

	# Check angle: enemy must be within the beam half-angle
	var angle_to_enemy := abs(beam_direction.angle_to(to_enemy))
	if angle_to_enemy > deg_to_rad(BEAM_HALF_ANGLE_DEG):
		return false

	# Check line of sight (walls block the beam)
	return _has_line_of_sight_to(enemy)


## Check line of sight from flashlight to target (walls block).
func _has_line_of_sight_to(target: Node2D) -> bool:
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		global_position,
		target.global_position
	)
	query.collision_mask = OBSTACLE_COLLISION_MASK
	query.exclude = [self]
	var result := space_state.intersect_ray(query)
	return result.is_empty()


## Apply blindness effect to an enemy via StatusEffectsManager.
func _blind_enemy(enemy: Node2D) -> void:
	var enemy_id := enemy.get_instance_id()
	_blinded_enemies[enemy_id] = Time.get_ticks_msec()

	FileLogger.info("[FlashlightEffect] Beam hit %s at distance %.0f, applying blindness for %.1fs" % [enemy.name, global_position.distance_to(enemy.global_position), BLINDNESS_DURATION])

	var status_manager: Node = get_node_or_null("/root/StatusEffectsManager")
	if status_manager and status_manager.has_method("apply_blindness"):
		status_manager.apply_blindness(enemy, BLINDNESS_DURATION)
	elif enemy.has_method("set_blinded"):
		enemy.set_blinded(true)
