extends Node
## Trajectory glasses effect controller (Issue #744).
##
## Shows ricochet trajectories for player's bullets when activated.
## Displays a laser-like visualization showing where bullets will ricochet.
## Green laser indicates valid ricochet angle, red indicates impossible ricochet.
##
## Gameplay rules:
## - 2 charges per battle (resets on level restart)
## - Each activation lasts 10 seconds
## - Shows unlimited ricochet bounces (until laser exits viewport)
## - Replaces built-in laser sights when active (silenced pistol, M16, power fantasy)
## - Uses existing ricochet calculation code from bullet.gd

## Duration of trajectory glasses effect in seconds.
const EFFECT_DURATION: float = 10.0

## Maximum charges per battle.
const MAX_CHARGES: int = 2

## Maximum number of ricochet bounces to visualize.
const MAX_RICOCHET_BOUNCES: int = 50

## Laser width for trajectory visualization.
const LASER_WIDTH: float = 2.0

## Color for valid ricochet (can ricochet at this angle).
const VALID_RICOCHET_COLOR: Color = Color(0.0, 1.0, 0.0, 0.6)  # Green

## Color for invalid ricochet (angle too steep).
const INVALID_RICOCHET_COLOR: Color = Color(1.0, 0.0, 0.0, 0.6)  # Red

## Maximum ricochet angle in degrees (same as bullet.gd default).
const MAX_RICOCHET_ANGLE: float = 90.0

## Activation sound path.
const ACTIVATION_SOUND_PATH: String = "res://assets/audio/trajectory_glasses_activate.wav"

## Deactivation sound path.
const DEACTIVATION_SOUND_PATH: String = "res://assets/audio/trajectory_glasses_deactivate.wav"

## Current number of charges remaining.
var charges: int = MAX_CHARGES

## Whether the trajectory glasses effect is currently active.
var is_active: bool = false

## Timer tracking remaining effect duration.
var _effect_timer: float = 0.0

## Reference to the player node.
var _player: Node2D = null

## Reference to the weapon (for aim direction).
var _weapon: Node2D = null

## Line2D node for trajectory visualization.
var _trajectory_line: Line2D = null

## Glow Line2D for wider aura effect.
var _trajectory_glow: Line2D = null

## Cached viewport diagonal for max laser length.
var _viewport_diagonal: float = 2203.0

## Cached caliber data from player's weapon (for ricochet settings).
var _caliber_data: Resource = null

## Audio player for activation sounds.
var _audio_player: AudioStreamPlayer = null

## Signal emitted when trajectory glasses is activated.
signal trajectory_activated(charges_remaining: int)

## Signal emitted when trajectory glasses wears off.
signal trajectory_deactivated(charges_remaining: int)

## Signal emitted when charges change.
signal charges_changed(current: int, maximum: int)


func _ready() -> void:
	# Create the trajectory line visualizer
	_create_trajectory_line()

	# Setup audio player
	_setup_audio()

	FileLogger.info("[TrajectoryGlasses] Effect ready, charges: %d/%d" % [charges, MAX_CHARGES])


func _create_trajectory_line() -> void:
	# Main trajectory line
	_trajectory_line = Line2D.new()
	_trajectory_line.name = "TrajectoryLine"
	_trajectory_line.width = LASER_WIDTH
	_trajectory_line.default_color = VALID_RICOCHET_COLOR
	_trajectory_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_trajectory_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_trajectory_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_trajectory_line.visible = false
	_trajectory_line.z_index = 100  # On top of everything
	_trajectory_line.top_level = true  # Use global coordinates
	add_child(_trajectory_line)

	# Glow effect (wider, more transparent)
	_trajectory_glow = Line2D.new()
	_trajectory_glow.name = "TrajectoryGlow"
	_trajectory_glow.width = LASER_WIDTH * 4
	_trajectory_glow.default_color = Color(VALID_RICOCHET_COLOR.r, VALID_RICOCHET_COLOR.g, VALID_RICOCHET_COLOR.b, 0.2)
	_trajectory_glow.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_trajectory_glow.end_cap_mode = Line2D.LINE_CAP_ROUND
	_trajectory_glow.joint_mode = Line2D.LINE_JOINT_ROUND
	_trajectory_glow.visible = false
	_trajectory_glow.z_index = 99
	_trajectory_glow.top_level = true
	add_child(_trajectory_glow)


func _setup_audio() -> void:
	_audio_player = AudioStreamPlayer.new()
	_audio_player.name = "TrajectoryGlassesAudio"
	_audio_player.bus = "SFX"
	add_child(_audio_player)


## Initialize with a reference to the player node.
## Must be called after the player model is ready.
func initialize(player: Node2D) -> void:
	_player = player

	# Calculate viewport diagonal for max trajectory length
	var viewport := player.get_viewport()
	if viewport:
		var size := viewport.get_visible_rect().size
		_viewport_diagonal = sqrt(size.x * size.x + size.y * size.y)

	FileLogger.info("[TrajectoryGlasses] Initialized with player: %s, viewport diagonal: %.0f" % [
		player.name, _viewport_diagonal
	])


## Set the weapon reference for aim direction.
func set_weapon(weapon: Node2D) -> void:
	_weapon = weapon

	# Try to get caliber data from weapon
	if weapon and weapon.has_method("get") and "caliber_data" in weapon:
		_caliber_data = weapon.get("caliber_data")
	elif weapon and weapon.has_method("get") and "CaliberData" in weapon:
		_caliber_data = weapon.get("CaliberData")

	FileLogger.info("[TrajectoryGlasses] Weapon set: %s, caliber: %s" % [
		weapon.name if weapon else "null",
		_caliber_data.resource_path if _caliber_data else "default"
	])


## Attempt to activate the trajectory glasses effect.
## Returns true if activation was successful.
func activate() -> bool:
	if is_active:
		return false  # Already active

	if charges <= 0:
		FileLogger.info("[TrajectoryGlasses] No charges remaining")
		return false

	# Consume a charge
	charges -= 1
	is_active = true
	_effect_timer = EFFECT_DURATION

	# Show trajectory visualization
	_trajectory_line.visible = true
	_trajectory_glow.visible = true

	# Play activation sound
	_play_activation_sound()

	# Hide built-in weapon lasers
	_hide_weapon_lasers()

	FileLogger.info("[TrajectoryGlasses] Activated! Duration: %.1fs, Charges remaining: %d/%d" % [
		EFFECT_DURATION, charges, MAX_CHARGES
	])

	trajectory_activated.emit(charges)
	charges_changed.emit(charges, MAX_CHARGES)
	return true


## Deactivate the trajectory glasses effect.
func deactivate() -> void:
	if not is_active:
		return

	is_active = false
	_effect_timer = 0.0

	# Hide trajectory visualization
	_trajectory_line.visible = false
	_trajectory_glow.visible = false
	_trajectory_line.clear_points()
	_trajectory_glow.clear_points()

	# Play deactivation sound
	_play_deactivation_sound()

	# Restore built-in weapon lasers
	_restore_weapon_lasers()

	FileLogger.info("[TrajectoryGlasses] Deactivated! Charges remaining: %d/%d" % [
		charges, MAX_CHARGES
	])

	trajectory_deactivated.emit(charges)


func _process(delta: float) -> void:
	if not is_active:
		return

	# Count down effect timer
	_effect_timer -= delta
	if _effect_timer <= 0.0:
		deactivate()
		return

	# Update trajectory visualization every frame
	_update_trajectory()


## Update the trajectory visualization based on current aim direction.
func _update_trajectory() -> void:
	if _player == null:
		return

	_trajectory_line.clear_points()
	_trajectory_glow.clear_points()

	# Get weapon/aim direction
	var start_pos: Vector2 = _player.global_position
	var aim_direction: Vector2 = _get_aim_direction()

	if aim_direction == Vector2.ZERO:
		return

	# Add bullet spawn offset
	var bullet_offset := 20.0  # Default bullet_spawn_offset from player
	if _player.has_method("get") and "bullet_spawn_offset" in _player:
		bullet_offset = _player.get("bullet_spawn_offset")

	start_pos += aim_direction * bullet_offset

	# Calculate ricochet trajectory
	var trajectory_points := _calculate_ricochet_trajectory(start_pos, aim_direction)

	# Add points to line
	for point in trajectory_points:
		_trajectory_line.add_point(point)
		_trajectory_glow.add_point(point)


## Get the aim direction from weapon or mouse.
func _get_aim_direction() -> Vector2:
	if _player == null:
		return Vector2.ZERO

	# Try to get aim direction from weapon
	if _weapon:
		# C# weapons have AimDirection property
		if _weapon.has_method("get") and "AimDirection" in _weapon:
			var aim: Vector2 = _weapon.get("AimDirection")
			if aim != Vector2.ZERO:
				return aim.normalized()
		# GDScript weapons might have aim_direction
		if _weapon.has_method("get") and "aim_direction" in _weapon:
			var aim: Vector2 = _weapon.get("aim_direction")
			if aim != Vector2.ZERO:
				return aim.normalized()

	# Fallback: direction from player to mouse
	var viewport := _player.get_viewport()
	if viewport == null:
		return Vector2.RIGHT

	var mouse_pos := viewport.get_mouse_position()
	var camera := viewport.get_camera_2d()
	if camera:
		# Convert screen position to world position
		mouse_pos = camera.get_global_mouse_position()

	var to_mouse := mouse_pos - _player.global_position
	if to_mouse.length_squared() < 0.001:
		return Vector2.RIGHT

	return to_mouse.normalized()


## Calculate the ricochet trajectory as an array of points.
## Uses the same logic as bullet.gd for realistic behavior.
func _calculate_ricochet_trajectory(start: Vector2, direction: Vector2) -> Array[Vector2]:
	var points: Array[Vector2] = []
	points.append(start)

	var current_pos := start
	var current_dir := direction
	var max_distance := _viewport_diagonal

	var space_state := _player.get_world_2d().direct_space_state
	if space_state == null:
		# No physics - just draw straight line
		points.append(start + direction * max_distance)
		return points

	for bounce in range(MAX_RICOCHET_BOUNCES):
		# Raycast forward
		var ray_end := current_pos + current_dir * max_distance
		var query := PhysicsRayQueryParameters2D.create(current_pos, ray_end)
		query.collision_mask = 4  # Layer 3 = obstacles/walls

		var result := space_state.intersect_ray(query)

		if result.is_empty():
			# No hit - line extends to max distance
			points.append(ray_end)
			break

		# Hit a wall
		var hit_pos: Vector2 = result.position
		var hit_normal: Vector2 = result.normal

		# Add hit point
		points.append(hit_pos)

		# Check if ricochet is valid at this angle
		var impact_angle := _calculate_impact_angle(current_dir, hit_normal)
		var is_valid_ricochet := impact_angle <= MAX_RICOCHET_ANGLE

		# Update laser color based on ricochet validity
		if not is_valid_ricochet:
			# Invalid ricochet angle - show red from this point
			_set_trajectory_colors(INVALID_RICOCHET_COLOR)
			break

		# Calculate reflection for next bounce
		current_dir = current_dir - 2.0 * current_dir.dot(hit_normal) * hit_normal
		current_dir = current_dir.normalized()

		# Move slightly away from surface to avoid re-hitting same spot
		current_pos = hit_pos + current_dir * 2.0

	return points


## Calculate the grazing/impact angle in degrees.
## Returns 0 for parallel (grazing), 90 for perpendicular (direct hit).
func _calculate_impact_angle(direction: Vector2, surface_normal: Vector2) -> float:
	var dot := absf(direction.normalized().dot(surface_normal.normalized()))
	dot = clampf(dot, 0.0, 1.0)
	return rad_to_deg(asin(dot))


## Set the trajectory line colors.
func _set_trajectory_colors(color: Color) -> void:
	_trajectory_line.default_color = color
	_trajectory_glow.default_color = Color(color.r, color.g, color.b, 0.2)


## Play the activation sound.
func _play_activation_sound() -> void:
	if _audio_player == null:
		return

	if ResourceLoader.exists(ACTIVATION_SOUND_PATH):
		_audio_player.stream = load(ACTIVATION_SOUND_PATH)
		_audio_player.play()
	else:
		# Fallback: use a generic activation sound
		var audio_manager: Node = get_node_or_null("/root/AudioManager")
		if audio_manager and audio_manager.has_method("play_ui_click"):
			audio_manager.play_ui_click()


## Play the deactivation sound.
func _play_deactivation_sound() -> void:
	if _audio_player == null:
		return

	if ResourceLoader.exists(DEACTIVATION_SOUND_PATH):
		_audio_player.stream = load(DEACTIVATION_SOUND_PATH)
		_audio_player.play()


## Hide weapon's built-in laser sights when trajectory glasses are active.
func _hide_weapon_lasers() -> void:
	if _weapon == null:
		return

	# Try to disable laser sight on C# weapons (AssaultRifle, SilencedPistol)
	if _weapon.has_method("SetLaserSightEnabled"):
		_weapon.call("SetLaserSightEnabled", false)
		FileLogger.info("[TrajectoryGlasses] Disabled weapon laser sight")
	elif _weapon.has_method("set_laser_sight_enabled"):
		_weapon.call("set_laser_sight_enabled", false)
		FileLogger.info("[TrajectoryGlasses] Disabled weapon laser sight (GDScript)")

	# Also hide any Line2D children named "LaserSight"
	var laser := _weapon.get_node_or_null("LaserSight")
	if laser and laser is Line2D:
		laser.visible = false

	# Hide Power Fantasy laser if present
	var pf_laser := _weapon.get_node_or_null("PowerFantasyLaser")
	if pf_laser and pf_laser is Line2D:
		pf_laser.visible = false


## Restore weapon's built-in laser sights when trajectory glasses deactivate.
func _restore_weapon_lasers() -> void:
	if _weapon == null:
		return

	# Re-enable laser sight on C# weapons
	if _weapon.has_method("SetLaserSightEnabled"):
		# Check if weapon should have laser enabled by default
		var has_laser: bool = true
		if _weapon.has_method("get") and "LaserSightEnabled" in _weapon:
			# We disabled it, so we should restore it to true
			has_laser = true
		_weapon.call("SetLaserSightEnabled", has_laser)
		FileLogger.info("[TrajectoryGlasses] Restored weapon laser sight")
	elif _weapon.has_method("set_laser_sight_enabled"):
		_weapon.call("set_laser_sight_enabled", true)
		FileLogger.info("[TrajectoryGlasses] Restored weapon laser sight (GDScript)")

	# Restore any Line2D children named "LaserSight"
	var laser := _weapon.get_node_or_null("LaserSight")
	if laser and laser is Line2D:
		laser.visible = true

	# Restore Power Fantasy laser if applicable
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager and difficulty_manager.has_method("should_force_blue_laser_sight"):
		if difficulty_manager.should_force_blue_laser_sight():
			var pf_laser := _weapon.get_node_or_null("PowerFantasyLaser")
			if pf_laser and pf_laser is Line2D:
				pf_laser.visible = true


## Get the remaining effect time in seconds.
func get_remaining_time() -> float:
	return _effect_timer if is_active else 0.0


## Get the current number of charges.
func get_charges() -> int:
	return charges
