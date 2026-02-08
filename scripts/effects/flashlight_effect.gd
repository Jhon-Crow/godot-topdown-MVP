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
##
## Light scattering (Issue #644): A secondary PointLight2D with a radial gradient
## is placed at the beam's impact point (wall hit or max range). This simulates
## the ambient glow created when a flashlight beam hits a surface in reality.

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

## Energy (brightness) for the scatter light at the beam impact point (Issue #644).
## Much lower than the main beam (8.0) for a subtle ambient glow effect.
const SCATTER_LIGHT_ENERGY: float = 0.4

## Texture scale for the scatter light radial gradient.
## Controls the radius of the ambient glow at the beam impact point.
const SCATTER_LIGHT_TEXTURE_SCALE: float = 3.0

## Color of the scatter light — warm white matching the main beam tint.
const SCATTER_LIGHT_COLOR: Color = Color(1.0, 1.0, 0.92, 1.0)

## Offset (in pixels) to pull the scatter light back from wall surfaces.
## Prevents the PointLight2D from sitting exactly on a LightOccluder2D boundary,
## which causes light to leak through in Godot's 2D shadow system.
const SCATTER_WALL_PULLBACK: float = 8.0

## Distance threshold (in pixels) for beam-direction wall clamping (Issue #640).
## If the beam hits a wall within this distance from the barrel, the flashlight
## is considered wall-clamped — enemies cannot detect or be blinded through the wall.
## This catches the case where the player stands flush against a wall and the barrel
## is on the player's side but the beam immediately enters the wall body.
const BEAM_WALL_CLAMP_DISTANCE: float = 30.0

## Reference to the PointLight2D child node.
var _point_light: PointLight2D = null

## Reference to the scatter light PointLight2D (Issue #644).
## Positioned at the beam's impact point to simulate light scattering.
var _scatter_light: PointLight2D = null

## Whether the flashlight is currently active (on).
var _is_on: bool = false

## Whether the main beam light is currently wall-clamped (Issue #640).
## Used by _update_scatter_light_position() to suppress the scatter glow
## when the player stands flush against a wall.
var _is_wall_clamped: bool = false

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
	# Setup scatter light at beam impact point (Issue #644)
	_setup_scatter_light()
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


## Setup the scatter light PointLight2D (Issue #644).
## Creates a radial glow light that will be positioned at the beam's impact point.
## Uses shadow_enabled = true so the scatter light respects walls.
func _setup_scatter_light() -> void:
	_scatter_light = PointLight2D.new()
	_scatter_light.name = "ScatterLight"
	_scatter_light.color = SCATTER_LIGHT_COLOR
	_scatter_light.energy = SCATTER_LIGHT_ENERGY
	_scatter_light.shadow_enabled = true
	_scatter_light.shadow_filter = PointLight2D.SHADOW_FILTER_PCF5
	_scatter_light.shadow_filter_smooth = 4.0
	_scatter_light.shadow_color = Color(0, 0, 0, 0.8)
	_scatter_light.texture = _create_scatter_light_texture()
	_scatter_light.texture_scale = SCATTER_LIGHT_TEXTURE_SCALE
	_scatter_light.visible = false
	add_child(_scatter_light)
	FileLogger.info("[FlashlightEffect] Scatter light created (Issue #644)")


## Create a radial gradient texture for the scatter light (Issue #644).
## Uses an early-fadeout design matching the codebase pattern from window lights.
## The gradient reaches zero at 55% radius, leaving 45% buffer for invisible edges.
func _create_scatter_light_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	# Bright center core
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	# Smooth falloff
	gradient.add_point(0.1, Color(0.8, 0.8, 0.8, 1.0))
	gradient.add_point(0.2, Color(0.55, 0.55, 0.55, 1.0))
	gradient.add_point(0.3, Color(0.3, 0.3, 0.3, 1.0))
	gradient.add_point(0.4, Color(0.12, 0.12, 0.12, 1.0))
	# Fade to zero by 55% — remaining 45% is pure black buffer
	gradient.add_point(0.5, Color(0.03, 0.03, 0.03, 1.0))
	gradient.add_point(0.55, Color(0.0, 0.0, 0.0, 1.0))
	gradient.set_color(1, Color(0.0, 0.0, 0.0, 1.0))

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 512
	texture.height = 512
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	return texture


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


## Check if the flashlight beam is currently wall-clamped (Issue #640).
## When true, the beam is blocked by a wall between the player and the barrel.
## Used by enemy AI to avoid detecting/being blinded by a beam that cannot reach them.
func is_wall_clamped() -> bool:
	return _is_wall_clamped


## Set the light visibility and energy.
func _set_light_visible(visible_state: bool) -> void:
	if _point_light:
		_point_light.visible = visible_state
		_point_light.energy = LIGHT_ENERGY if visible_state else 0.0
	if _scatter_light:
		# When wall-clamped, scatter light stays hidden (Issue #640).
		var scatter_visible: bool = visible_state and not _is_wall_clamped
		_scatter_light.visible = scatter_visible
		_scatter_light.energy = SCATTER_LIGHT_ENERGY if visible_state else 0.0


## Prevent the PointLight2D from penetrating walls when the player stands
## close to a wall (Issue #640). Three measures are applied simultaneously:
##
## 1. Move the PointLight2D back to the player center — keeps the wall's
##    LightOccluder2D between the light source and the wall geometry.
## 2. Reduce texture_scale so the beam's visual reach only extends to the
##    wall surface — prevents the cone from illuminating the wall body
##    through PCF shadow filter penumbra bleed.
## 3. Switch to SHADOW_FILTER_NONE for crisp shadow edges — eliminates
##    the soft penumbra that bleeds light around LightOccluder2D boundaries.
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
		_is_wall_clamped = false
		_restore_light_defaults()
		return

	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(player_center, intended_pos)
	query.collision_mask = OBSTACLE_COLLISION_MASK
	# Issue #640: Enable hit_from_inside so the ray detects walls even if player_center
	# is at the edge of a wall body (possible with CharacterBody2D collision margins).
	query.hit_from_inside = true
	var result := space_state.intersect_ray(query)

	if result.is_empty():
		# No wall between player and barrel — check beam direction.
		# The player may be flush against a wall with the barrel on their side,
		# but the beam direction goes into/through the wall.
		var beam_direction := Vector2.RIGHT.rotated(global_rotation)
		var beam_check_end := intended_pos + beam_direction * BEAM_WALL_CLAMP_DISTANCE
		var beam_query := PhysicsRayQueryParameters2D.create(intended_pos, beam_check_end)
		beam_query.collision_mask = OBSTACLE_COLLISION_MASK
		# Issue #640: Enable hit_from_inside so we detect the wall even if the barrel
		# is already inside the wall body (common at wall boundaries due to floating-point).
		beam_query.hit_from_inside = true
		var beam_result := space_state.intersect_ray(beam_query)

		if beam_result.is_empty():
			# No wall in beam direction either — use default
			_point_light.position = Vector2.ZERO
			_is_wall_clamped = false
			_restore_light_defaults()
		else:
			# Wall found immediately in beam direction — clamp the beam.
			_is_wall_clamped = true
			# Move light source to player center so the wall's LightOccluder2D blocks it.
			_point_light.global_position = player_center
			# Reduce texture_scale to reach only the wall surface.
			var wall_dist: float = (beam_result.position - player_center).length()
			var cone_texture_size: float = 2048.0
			var clamped_scale: float = maxf(wall_dist * 2.0 / cone_texture_size, 0.1)
			_point_light.texture_scale = minf(clamped_scale, LIGHT_TEXTURE_SCALE)
			_point_light.shadow_filter = PointLight2D.SHADOW_FILTER_NONE
	else:
		# Wall hit: move the light source back to the player center.
		_point_light.global_position = player_center
		_is_wall_clamped = true

		# Calculate distance from player center to wall hit point.
		var wall_dist: float = (result.position - player_center).length()

		# Reduce texture_scale so the beam only reaches the wall surface.
		# The cone texture is 2048px wide; effective reach = texture_size * scale / 2.
		# We want: effective_reach = wall_dist, so: scale = wall_dist * 2 / texture_size.
		# Clamp to a minimum to avoid visual artifacts from extremely small scales.
		var cone_texture_size: float = 2048.0
		var clamped_scale: float = maxf(wall_dist * 2.0 / cone_texture_size, 0.1)
		_point_light.texture_scale = minf(clamped_scale, LIGHT_TEXTURE_SCALE)

		# Use sharp shadows near walls to prevent PCF penumbra bleed.
		_point_light.shadow_filter = PointLight2D.SHADOW_FILTER_NONE


## Restore PointLight2D to default settings when not wall-clamped.
func _restore_light_defaults() -> void:
	if _point_light == null:
		return
	_point_light.texture_scale = LIGHT_TEXTURE_SCALE
	_point_light.shadow_filter = PointLight2D.SHADOW_FILTER_PCF5


func _physics_process(_delta: float) -> void:
	_clamp_light_to_walls()
	if not _is_on:
		return
	_update_scatter_light_position()
	# Issue #640: When wall-clamped, the beam is blocked by a wall — skip blindness checks.
	# The flashlight barrel is past the wall, so the LOS raycast from barrel to enemy
	# would not detect the wall, causing enemies to be blinded through walls.
	if not _is_wall_clamped:
		_check_enemies_in_beam()


## Update the scatter light position to the beam's impact point (Issue #644).
## Casts a ray along the beam direction and places the scatter light where
## the beam hits a wall or at the maximum beam range if no wall is hit.
##
## Issue #640 fix: When the main beam is wall-clamped (player flush against wall),
## the scatter light is hidden to prevent residual glow from leaking through.
## When a wall hit is detected at normal range, the scatter light is pulled back
## from the wall surface to avoid sitting on the LightOccluder2D boundary.
func _update_scatter_light_position() -> void:
	if _scatter_light == null:
		return

	# If the main beam is wall-clamped, hide the scatter light entirely.
	# When the player is flush against a wall, there's no meaningful surface
	# for the beam to scatter from — the beam is blocked before it reaches.
	if _is_wall_clamped:
		_scatter_light.visible = false
		return

	var beam_origin := global_position
	var beam_direction := Vector2.RIGHT.rotated(global_rotation)
	var beam_end := beam_origin + beam_direction * BEAM_RANGE

	# Raycast to find where the beam hits a wall
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(beam_origin, beam_end)
	query.collision_mask = OBSTACLE_COLLISION_MASK
	query.exclude = [self]
	var result := space_state.intersect_ray(query)

	if not result.is_empty():
		# Beam hits a wall — pull the scatter light back from the wall surface
		# toward the player. This prevents the PointLight2D from sitting exactly
		# on the LightOccluder2D boundary, where Godot's shadow system cannot
		# reliably block it (known engine limitation, GitHub #79783).
		var wall_pos: Vector2 = result.position
		var pullback_dir: Vector2 = -beam_direction
		var scatter_pos: Vector2 = wall_pos + pullback_dir * SCATTER_WALL_PULLBACK
		_scatter_light.global_position = scatter_pos
		_scatter_light.visible = _is_on
	else:
		# No wall hit — place scatter light at max beam range
		_scatter_light.global_position = beam_end
		_scatter_light.visible = _is_on


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
## Issue #640: Uses two rays — one from the barrel and one from the player center.
## The barrel may be inside a wall body, so its ray might not detect the wall.
## The player center is always outside walls (CharacterBody2D physics guarantee).
func _has_line_of_sight_to(target: Node2D) -> bool:
	var space_state := get_world_2d().direct_space_state

	# Check from barrel position
	var query := PhysicsRayQueryParameters2D.create(
		global_position,
		target.global_position
	)
	query.collision_mask = OBSTACLE_COLLISION_MASK
	query.exclude = [self]
	var result := space_state.intersect_ray(query)
	if not result.is_empty():
		return false

	# Issue #640: Secondary check from player center to catch edge cases
	# where the barrel is at/inside a wall boundary.
	var player_model := get_parent()
	if player_model != null:
		var player := player_model.get_parent()
		if player != null:
			var center_query := PhysicsRayQueryParameters2D.create(
				player.global_position,
				target.global_position
			)
			center_query.collision_mask = OBSTACLE_COLLISION_MASK
			var center_result := space_state.intersect_ray(center_query)
			if not center_result.is_empty():
				return false

	return true


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
