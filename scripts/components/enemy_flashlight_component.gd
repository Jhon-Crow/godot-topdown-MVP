class_name EnemyFlashlightComponent
extends Node
## Component for enemy flashlight behavior in night mode (Issue #824).
##
## In night mode, enemies shine their flashlight at the player's position
## 300-500ms before shooting or throwing a grenade (Issue #825: increased from 50-100ms
## to give the player a visible warning and reaction time). If the player is caught
## in the flashlight beam, they receive a stun effect similar to how the
## player's flashlight affects enemies.
##
## The flashlight beam has the same properties as the player's flashlight:
## - 18-degree cone (9 degrees half-angle)
## - 600 pixel range
## - Respects walls (shadow_enabled = true)
## - 2 second blindness duration with 20 second cooldown

## Duration for flashlight to be on before attack (300-500ms).
## This gives the player enough time to see the flashlight warning and react.
## Previously was 50-100ms which was imperceptible (Issue #825 fix).
const PRE_ATTACK_FLASH_DURATION_MIN: float = 0.3
const PRE_ATTACK_FLASH_DURATION_MAX: float = 0.5

## Flashlight beam half-angle in degrees (matches player flashlight).
const BEAM_HALF_ANGLE_DEG: float = 9.0

## Maximum range for the flashlight beam (matches player flashlight).
const BEAM_RANGE: float = 600.0

## Duration of the blindness effect on the player (seconds).
const BLINDNESS_DURATION: float = 2.0

## Cooldown in seconds before the player can be blinded again by this enemy.
const BLINDNESS_COOLDOWN: float = 20.0

## Collision mask for obstacles (layer 3) used in line-of-sight checks.
const OBSTACLE_COLLISION_MASK: int = 4

## Reference to the parent enemy node.
var _enemy: CharacterBody2D = null

## Reference to the enemy's model node (for flashlight positioning).
var _enemy_model: Node2D = null

## Reference to the flashlight effect scene instance.
var _flashlight_node: Node2D = null

## Reference to the PointLight2D child of the flashlight node.
var _point_light: PointLight2D = null

## Whether the flashlight is currently on.
var _is_on: bool = false

## Timer for how long the flashlight has been on.
var _flash_timer: float = 0.0

## Target duration for the current flash.
var _flash_target_duration: float = 0.0

## Whether the component is currently executing a pre-attack flash.
var _is_flashing_for_attack: bool = false

## Callback to execute after flash completes.
var _flash_callback: Callable = Callable()

## Whether the player has been blinded by this enemy recently (cooldown tracking).
var _player_blinded_time: int = 0

## Whether debug logging is enabled.
var debug_logging: bool = false

## Scene path for the enemy flashlight effect.
const FLASHLIGHT_SCENE_PATH: String = "res://scenes/effects/EnemyFlashlightEffect.tscn"


func _ready() -> void:
	_enemy = get_parent() as CharacterBody2D
	if _enemy == null:
		_log_debug("ERROR: Parent is not a CharacterBody2D")
		return

	_enemy_model = _enemy.get_node_or_null("EnemyModel")
	if _enemy_model == null:
		_log_debug("ERROR: Could not find EnemyModel node")
		return

	_setup_flashlight()


## Setup the flashlight effect node.
func _setup_flashlight() -> void:
	if not _is_night_mode_active():
		_log_debug("Night mode not active, flashlight not initialized")
		return

	# Load and instantiate the flashlight effect scene
	if not ResourceLoader.exists(FLASHLIGHT_SCENE_PATH):
		_log_debug("WARNING: Flashlight scene not found: %s" % FLASHLIGHT_SCENE_PATH)
		return

	var flashlight_scene: PackedScene = load(FLASHLIGHT_SCENE_PATH)
	if flashlight_scene == null:
		_log_debug("WARNING: Failed to load flashlight scene")
		return

	_flashlight_node = flashlight_scene.instantiate()
	_flashlight_node.name = "EnemyFlashlightEffect"

	# Add as child of EnemyModel so it rotates with the enemy's facing direction
	if _enemy_model:
		_enemy_model.add_child(_flashlight_node)
		# Position at the weapon barrel (forward from center)
		var bullet_spawn_offset: float = _enemy.get("bullet_spawn_offset") if _enemy.get("bullet_spawn_offset") != null else 30.0
		_flashlight_node.position = Vector2(bullet_spawn_offset, 0)

		# Get reference to the PointLight2D
		_point_light = _flashlight_node.get_node_or_null("PointLight2D")
		if _point_light:
			_point_light.visible = false
			_point_light.energy = 0.0

		_log_debug("Flashlight setup complete at offset (%d, 0)" % int(bullet_spawn_offset))
	else:
		_log_debug("WARNING: _enemy_model is null, flashlight not attached")
		_flashlight_node.queue_free()
		_flashlight_node = null


func _physics_process(delta: float) -> void:
	if not _is_flashing_for_attack:
		return

	_flash_timer += delta

	# Check if we should blind the player while the flashlight is on
	if _is_on:
		_check_player_in_beam()

	# Check if flash duration has completed
	if _flash_timer >= _flash_target_duration:
		_complete_flash()


## Check if night mode (realistic visibility) is currently active.
func _is_night_mode_active() -> bool:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings and experimental_settings.has_method("is_realistic_visibility_enabled"):
		return experimental_settings.is_realistic_visibility_enabled()
	return false


## Start the pre-attack flashlight sequence.
## The flashlight will turn on for 300-500ms (visible warning for player), check if player
## is in beam, and then execute the callback (shoot or throw grenade).
## @param target_position: Position to aim the flashlight at (player's position).
## @param callback: Callable to execute after the flash completes.
func start_pre_attack_flash(target_position: Vector2, callback: Callable) -> void:
	if not _is_night_mode_active():
		# Night mode not active, execute callback immediately
		if callback.is_valid():
			callback.call()
		return

	if _flashlight_node == null or _point_light == null:
		# Flashlight not initialized, try to set it up
		_setup_flashlight()
		if _flashlight_node == null or _point_light == null:
			# Still not available, execute callback immediately
			if callback.is_valid():
				callback.call()
			return

	if _is_flashing_for_attack:
		# Already flashing, don't interrupt
		_log_debug("Already flashing, skipping new flash request")
		return

	# Start the flash sequence
	_is_flashing_for_attack = true
	_flash_timer = 0.0
	_flash_target_duration = randf_range(PRE_ATTACK_FLASH_DURATION_MIN, PRE_ATTACK_FLASH_DURATION_MAX)
	_flash_callback = callback

	_turn_on()
	_log_debug("Pre-attack flash started, duration: %.3fs" % _flash_target_duration)


## Complete the flash sequence and execute the callback.
func _complete_flash() -> void:
	_turn_off()
	_is_flashing_for_attack = false

	_log_debug("Pre-attack flash completed")

	# Execute the callback (shoot or throw grenade)
	if _flash_callback.is_valid():
		_flash_callback.call()
	_flash_callback = Callable()


## Turn the flashlight on.
func _turn_on() -> void:
	if _is_on:
		return
	_is_on = true
	if _point_light:
		_point_light.visible = true
		_point_light.energy = 8.0  # Same energy as player flashlight
	_log_debug("Flashlight turned on")


## Turn the flashlight off.
func _turn_off() -> void:
	if not _is_on:
		return
	_is_on = false
	if _point_light:
		_point_light.visible = false
		_point_light.energy = 0.0
	_log_debug("Flashlight turned off")


## Check if the player is currently on.
func is_on() -> bool:
	return _is_on


## Check if enemy flashlight blinding is enabled in experimental settings (Issue #903).
func _is_enemy_flashlight_blinding_enabled() -> bool:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings and experimental_settings.has_method("is_enemy_flashlight_blinding_enabled"):
		return experimental_settings.is_enemy_flashlight_blinding_enabled()
	return false


## Check if the player is in the flashlight beam and apply stun if so.
func _check_player_in_beam() -> void:
	# Do not blind player if the experimental setting is disabled (Issue #903).
	if not _is_enemy_flashlight_blinding_enabled():
		return

	var player := _find_player()
	if player == null:
		return

	# Check cooldown
	var current_time: int = Time.get_ticks_msec()
	if _player_blinded_time > 0:
		var elapsed_sec: float = float(current_time - _player_blinded_time) / 1000.0
		if elapsed_sec < BLINDNESS_COOLDOWN:
			return

	if _is_player_in_beam(player):
		_blind_player(player)


## Check if the player is within the flashlight beam cone and has line of sight.
func _is_player_in_beam(player: Node2D) -> bool:
	if _flashlight_node == null:
		return false

	var beam_origin := _flashlight_node.global_position
	var beam_direction := Vector2.RIGHT.rotated(_flashlight_node.global_rotation)
	var to_player := player.global_position - beam_origin
	var distance := to_player.length()

	# Check range
	if distance > BEAM_RANGE or distance < 1.0:
		return false

	# Check angle: player must be within the beam half-angle
	var angle_to_player: float = abs(beam_direction.angle_to(to_player))
	if angle_to_player > deg_to_rad(BEAM_HALF_ANGLE_DEG):
		return false

	# Check line of sight (walls block the beam)
	return _has_line_of_sight_to(player)


## Check line of sight from flashlight to player (walls block).
func _has_line_of_sight_to(target: Node2D) -> bool:
	if _flashlight_node == null:
		return false

	var space_state := _flashlight_node.get_world_2d().direct_space_state

	# Check from flashlight position to player
	var query := PhysicsRayQueryParameters2D.create(
		_flashlight_node.global_position,
		target.global_position
	)
	query.collision_mask = OBSTACLE_COLLISION_MASK
	var result := space_state.intersect_ray(query)

	return result.is_empty()


## Apply blindness/stun effect to the player.
func _blind_player(player: Node2D) -> void:
	_player_blinded_time = Time.get_ticks_msec()

	var distance := _flashlight_node.global_position.distance_to(player.global_position)
	_log_debug("Beam hit player at distance %.0f, applying stun effect for %.1fs" % [distance, BLINDNESS_DURATION])

	# Apply the flashbang effect to the player via FlashbangPlayerEffectsManager
	# This creates the same visual effect as a stun grenade
	var effects_manager: Node = get_node_or_null("/root/FlashbangPlayerEffectsManager")
	if effects_manager and effects_manager.has_method("apply_flashbang_effect"):
		# Use flashlight position as "grenade position" and calculate intensity based on distance
		# Using BEAM_RANGE as the effect radius for intensity calculation
		effects_manager.apply_flashbang_effect(
			_flashlight_node.global_position,
			player.global_position,
			BEAM_RANGE
		)
		_log_debug("Applied flashbang effect to player via FlashbangPlayerEffectsManager")


## Find the player node.
func _find_player() -> Node2D:
	# Try to get player from the enemies group context
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0] as Node2D

	# Try common paths
	var scene := get_tree().current_scene
	if scene:
		var player := scene.get_node_or_null("Player")
		if player:
			return player as Node2D

	return null


## Log debug message if debug logging is enabled.
func _log_debug(message: String) -> void:
	if not debug_logging:
		return

	var enemy_name: String = str(_enemy.name) if _enemy else "Unknown"
	var log_msg := "[EnemyFlashlight:%s] %s" % [enemy_name, message]

	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info(log_msg)
	else:
		print(log_msg)
