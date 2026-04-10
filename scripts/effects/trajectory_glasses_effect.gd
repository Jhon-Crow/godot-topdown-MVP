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
##
## Rendering approach:
## - Trajectory points are stored in local player coordinates
## - Player's _draw() reads these points and draws them directly
## - This is the same approach used by grenade trajectory visualization
## - Guarantees correct coordinate space and rendering order

## Duration of trajectory glasses effect in seconds.
const EFFECT_DURATION: float = 10.0

## Maximum charges per battle.
const MAX_CHARGES: int = 2

## Maximum number of ricochet bounces to visualize for weapons with unlimited ricochets.
## Keeps the visualization readable without cluttering the screen.
const MAX_RICOCHET_BOUNCES: int = 5

## Laser width for trajectory visualization.
const LASER_WIDTH: float = 2.0

## Color for valid ricochet (can ricochet at this angle).
const VALID_RICOCHET_COLOR: Color = Color(0.0, 1.0, 0.0, 0.8)  # Bright green

## Color for invalid ricochet (angle too steep or weapon cannot ricochet).
const INVALID_RICOCHET_COLOR: Color = Color(1.0, 0.0, 0.0, 0.8)  # Bright red

## Maximum ricochet angle in degrees (same as bullet.gd DEFAULT_MAX_RICOCHET_ANGLE).
const MAX_RICOCHET_ANGLE: float = 90.0

## Continuous blink threshold in seconds — trajectory ray blinks continuously below this value (Issue #1085).
const CONTINUOUS_BLINK_THRESHOLD: float = 4.0

## Single-blink threshold — ray blinks once when remaining time first crosses this value (Issue #1085).
## Equal to 25% of EFFECT_DURATION (10 s × 25% = 2.5 s).
const SINGLE_BLINK_THRESHOLD: float = EFFECT_DURATION * 0.25

## Flash frequency when time is low (Hz).
const WARNING_FLASH_FREQUENCY: float = 3.0

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

## Cached viewport diagonal for max laser length.
var _viewport_diagonal: float = 2203.0

## Audio player for activation sounds.
var _audio_player: AudioStreamPlayer = null

## Warning flash timer for the trajectory ray continuous blink phase (Issue #1085).
var _warning_flash_timer: float = 0.0

## Whether the continuous-blink phase has been logged this activation (Issue #1085).
var _continuous_blink_logged: bool = false

## Whether the single-blink at 25% has already been triggered this activation (Issue #1085).
var _single_blink_triggered: bool = false

## Single-blink phase timer — counts up during the one-shot flash (Issue #1085).
## Negative/zero when the single blink is not in progress.
var _single_blink_timer: float = 0.0

## Whether the trajectory ray should be visible this frame (used for blinking, Issue #1085).
## True when time is not low, or when in the "on" phase of the blink cycle.
var trajectory_ray_visible: bool = true

## Trajectory points in LOCAL player coordinates (for player._draw()).
## Updated every frame when active.
var trajectory_local_points: Array[Vector2] = []

## Color for the valid (green) part of the trajectory.
## Kept for backward compatibility; the drawing code uses trajectory_invalid_start_index.
var trajectory_color: Color = VALID_RICOCHET_COLOR

## Index of the first point that belongs to the invalid (red) terminal segment.
## -1 means all segments are valid (green).
## When set, points[trajectory_invalid_start_index - 1] → points[trajectory_invalid_start_index]
## is drawn red, and no further segments exist.
var trajectory_invalid_start_index: int = -1

## Signal emitted when trajectory glasses is activated.
signal trajectory_activated(charges_remaining: int)

## Signal emitted when trajectory glasses wears off.
signal trajectory_deactivated(charges_remaining: int)

## Signal emitted when charges change.
signal charges_changed(current: int, maximum: int)


func _ready() -> void:
	# Setup audio player
	_setup_audio()

	FileLogger.info("[TrajectoryGlasses] Effect ready, charges: %d/%d" % [charges, MAX_CHARGES])


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

	FileLogger.info("[TrajectoryGlasses] Weapon set: %s" % [
		weapon.name if weapon else "null"
	])


## Attempt to activate the trajectory glasses effect.
## Returns true if activation was successful.
func activate() -> bool:
	if is_active:
		FileLogger.info("[TrajectoryGlasses] Already active, ignoring activation")
		return false  # Already active

	if charges <= 0:
		FileLogger.info("[TrajectoryGlasses] No charges remaining")
		return false

	# Consume a charge
	charges -= 1
	is_active = true
	_effect_timer = EFFECT_DURATION

	# Reset trajectory color to valid (green)
	trajectory_color = VALID_RICOCHET_COLOR

	# Play activation sound
	_play_activation_sound()

	# Hide built-in weapon lasers
	_hide_weapon_lasers()

	FileLogger.info("[TrajectoryGlasses] Activated! Duration: %.1fs, Charges remaining: %d/%d, Player: %s" % [
		EFFECT_DURATION, charges, MAX_CHARGES,
		_player.name if _player else "null"
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
	_warning_flash_timer = 0.0
	_continuous_blink_logged = false
	_single_blink_triggered = false
	_single_blink_timer = 0.0
	trajectory_ray_visible = true

	# Clear trajectory points so player._draw() stops rendering
	trajectory_local_points.clear()

	# Request player redraw to clear visualization
	if _player and is_instance_valid(_player):
		_player.queue_redraw()

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

	# Blink logic (Issue #1085).
	# Timeline (10 s total):
	#   10 s → 4 s  : ray solid (normal phase)
	#    4 s → 0 s  : continuous blinking at WARNING_FLASH_FREQUENCY Hz
	#   At 2.5 s    : single extra blink (ray off for half-period) injected into the
	#                 continuous-blink stream as an additional one-shot flash.
	#
	# Because SINGLE_BLINK_THRESHOLD (2.5 s) < CONTINUOUS_BLINK_THRESHOLD (4 s),
	# the single blink fires while continuous blinking is already active.
	if _effect_timer <= CONTINUOUS_BLINK_THRESHOLD:
		if not _continuous_blink_logged:
			_continuous_blink_logged = true
			FileLogger.info("[TrajectoryGlasses] Continuous blink phase started at %.2fs remaining (threshold=%.2fs, freq=%.1fHz)" % [
				_effect_timer, CONTINUOUS_BLINK_THRESHOLD, WARNING_FLASH_FREQUENCY
			])
		# Trigger the one-shot single blink the first time we cross 25% (Issue #1085).
		if _effect_timer <= SINGLE_BLINK_THRESHOLD and not _single_blink_triggered:
			_single_blink_triggered = true
			_single_blink_timer = 0.0
			FileLogger.info("[TrajectoryGlasses] Single-blink triggered at %.2fs remaining (threshold=%.2fs)" % [
				_effect_timer, SINGLE_BLINK_THRESHOLD
			])

		# During the single-blink window, override with a clean off→on half-period.
		var single_blink_period := 1.0 / WARNING_FLASH_FREQUENCY
		var prev_visible := trajectory_ray_visible
		if _single_blink_triggered and _single_blink_timer < single_blink_period:
			_single_blink_timer += delta
			if _single_blink_timer < single_blink_period * 0.5:
				trajectory_ray_visible = false  # ray off
			else:
				trajectory_ray_visible = true   # ray back on
		else:
			# Continuous blink: toggle at WARNING_FLASH_FREQUENCY Hz.
			_warning_flash_timer += delta
			var flash_period := 1.0 / WARNING_FLASH_FREQUENCY
			trajectory_ray_visible = fmod(_warning_flash_timer, flash_period) < (flash_period * 0.5)
		if trajectory_ray_visible != prev_visible:
			FileLogger.info("[TrajectoryGlasses] Blink state changed: ray_visible=%s at %.2fs remaining" % [
				str(trajectory_ray_visible), _effect_timer
			])
	else:
		# Normal phase: ray always visible, reset timers.
		_warning_flash_timer = 0.0
		_continuous_blink_logged = false
		_single_blink_triggered = false
		_single_blink_timer = 0.0
		trajectory_ray_visible = true

	# Request player redraw so _draw() picks up new trajectory points
	if _player and is_instance_valid(_player):
		_player.queue_redraw()


## Update the trajectory data based on current aim direction.
func _update_trajectory() -> void:
	if _player == null:
		return

	# Clear previous trajectory
	trajectory_local_points.clear()
	trajectory_color = VALID_RICOCHET_COLOR
	trajectory_invalid_start_index = -1

	# Get weapon/aim direction
	var player_pos: Vector2 = _player.global_position
	var aim_direction: Vector2 = _get_aim_direction()

	if aim_direction == Vector2.ZERO:
		return

	# Add bullet spawn offset
	var bullet_offset := 20.0  # Default bullet_spawn_offset from player
	if _player.has_method("get") and "bullet_spawn_offset" in _player:
		bullet_offset = _player.get("bullet_spawn_offset")

	# Start position in world space (from bullet barrel)
	var start_world := player_pos + aim_direction * bullet_offset

	# Calculate ricochet trajectory (returns world coordinates)
	var world_points := _calculate_ricochet_trajectory(start_world, aim_direction)

	# Convert world coordinates to LOCAL player coordinates (for _draw())
	for wp in world_points:
		trajectory_local_points.append(wp - player_pos)


## Get the aim direction from weapon or mouse.
func _get_aim_direction() -> Vector2:
	if _player == null:
		return Vector2.ZERO

	# Try to get aim direction from weapon
	if _weapon and is_instance_valid(_weapon):
		# C# weapons have AimDirection property
		if "AimDirection" in _weapon:
			var aim: Vector2 = _weapon.get("AimDirection")
			if aim != Vector2.ZERO:
				return aim.normalized()
		# GDScript weapons might have aim_direction
		if "aim_direction" in _weapon:
			var aim: Vector2 = _weapon.get("aim_direction")
			if aim != Vector2.ZERO:
				return aim.normalized()

	# Fallback: direction from player to mouse (world coordinates)
	var mouse_pos := _player.get_global_mouse_position()
	var to_mouse := mouse_pos - _player.global_position
	if to_mouse.length_squared() < 0.001:
		return Vector2.RIGHT

	return to_mouse.normalized()


## Get the maximum ricochet angle for the current weapon in degrees.
## Reads from the weapon's CaliberData resource when available.
## Falls back to MAX_RICOCHET_ANGLE (90 degrees) if no caliber data is found.
##
## Implementation note (Issue #935):
## Accessing caliber properties via GDScript .get("Caliber") on a C# Resource?
## property returns a stripped Resource object that loses its GDScript script
## binding — making "as CaliberData" return null and .get("max_ricochet_angle")
## return the GDScript default (90°) instead of the .tres value (70°).
## The fix is to call C# helper methods (GetCaliberMaxRicochetAngle, etc.) that
## read the caliber resource via C#, where the resource is correctly bound.
func _get_weapon_max_ricochet_angle() -> float:
	if _weapon == null or not is_instance_valid(_weapon):
		FileLogger.info("[TrajectoryGlasses] _get_weapon_max_ricochet_angle: no weapon, using default %.1f" % MAX_RICOCHET_ANGLE)
		return MAX_RICOCHET_ANGLE

	# Preferred path: use C# helper methods on BaseWeapon subclasses (Issue #935).
	# These methods read the caliber resource from the C# side where it is correctly
	# bound, avoiding the GDScript interop issue with Resource? properties.
	if _weapon.has_method("GetCaliberCanRicochet") and _weapon.has_method("GetCaliberMaxRicochetAngle"):
		var can_ricochet: bool = _weapon.call("GetCaliberCanRicochet")
		if not can_ricochet:
			FileLogger.info("[TrajectoryGlasses] _get_weapon_max_ricochet_angle: %s cannot ricochet (can_ricochet=false)" % _weapon.name)
			return 0.0
		var angle: float = _weapon.call("GetCaliberMaxRicochetAngle")
		FileLogger.info("[TrajectoryGlasses] _get_weapon_max_ricochet_angle: %s -> max_ricochet_angle=%.1f (via C# helper)" % [_weapon.name, angle])
		return angle

	# Fallback: try to read WeaponData.Caliber.max_ricochet_angle directly (GDScript weapons).
	var weapon_data = null
	if "WeaponData" in _weapon:
		weapon_data = _weapon.get("WeaponData")
	elif "weapon_data" in _weapon:
		weapon_data = _weapon.get("weapon_data")

	if weapon_data == null:
		FileLogger.info("[TrajectoryGlasses] _get_weapon_max_ricochet_angle: no weapon_data on %s, using default %.1f" % [_weapon.name, MAX_RICOCHET_ANGLE])
		return MAX_RICOCHET_ANGLE

	var caliber = null
	if "Caliber" in weapon_data:
		caliber = weapon_data.get("Caliber")
	elif "caliber" in weapon_data:
		caliber = weapon_data.get("caliber")

	if caliber == null:
		FileLogger.info("[TrajectoryGlasses] _get_weapon_max_ricochet_angle: no caliber in weapon_data for %s, using default %.1f" % [_weapon.name, MAX_RICOCHET_ANGLE])
		return MAX_RICOCHET_ANGLE

	var caliber_typed := caliber as CaliberData
	if caliber_typed == null:
		FileLogger.info("[TrajectoryGlasses] _get_weapon_max_ricochet_angle: caliber is not CaliberData for %s, using default %.1f" % [_weapon.name, MAX_RICOCHET_ANGLE])
		return MAX_RICOCHET_ANGLE

	if not caliber_typed.can_ricochet:
		FileLogger.info("[TrajectoryGlasses] _get_weapon_max_ricochet_angle: %s cannot ricochet (can_ricochet=false)" % _weapon.name)
		return 0.0

	var angle := caliber_typed.max_ricochet_angle
	FileLogger.info("[TrajectoryGlasses] _get_weapon_max_ricochet_angle: %s -> max_ricochet_angle=%.1f" % [_weapon.name, angle])
	return angle


## Get the maximum number of ricochets for the current weapon.
## Reads from the weapon's CaliberData resource when available.
## Returns -1 for unlimited, or a non-negative integer to cap bounces.
func _get_weapon_max_ricochets() -> int:
	if _weapon == null or not is_instance_valid(_weapon):
		return -1

	# Preferred path: use C# helper method on BaseWeapon subclasses (Issue #935).
	if _weapon.has_method("GetCaliberMaxRicochets"):
		var max_r: int = _weapon.call("GetCaliberMaxRicochets")
		FileLogger.info("[TrajectoryGlasses] _get_weapon_max_ricochets: %s -> max_ricochets=%d (via C# helper)" % [_weapon.name, max_r])
		return max_r

	# Fallback: try to read WeaponData.Caliber.max_ricochets directly (GDScript weapons).
	var weapon_data = null
	if "WeaponData" in _weapon:
		weapon_data = _weapon.get("WeaponData")
	elif "weapon_data" in _weapon:
		weapon_data = _weapon.get("weapon_data")

	if weapon_data == null:
		return -1

	var caliber = null
	if "Caliber" in weapon_data:
		caliber = weapon_data.get("Caliber")
	elif "caliber" in weapon_data:
		caliber = weapon_data.get("caliber")

	if caliber == null:
		return -1

	var caliber_typed := caliber as CaliberData
	if caliber_typed == null:
		return -1

	var max_r := caliber_typed.max_ricochets
	FileLogger.info("[TrajectoryGlasses] _get_weapon_max_ricochets: %s -> max_ricochets=%d" % [_weapon.name, max_r])
	return max_r


## Calculate the ricochet trajectory as an array of world-coordinate points.
## Uses the same logic as bullet.gd for realistic behavior.
## Respects the weapon's caliber data for ricochet angle limits and max bounce count.
## Sets trajectory_invalid_start_index to the index of the first non-ricochetable
## hit point; the segment ending there is drawn red, and tracing stops.
func _calculate_ricochet_trajectory(start: Vector2, direction: Vector2) -> Array[Vector2]:
	var points: Array[Vector2] = []
	points.append(start)

	var current_pos := start
	var current_dir := direction
	var max_distance := _viewport_diagonal

	# Get weapon-specific ricochet limits
	var weapon_max_angle := _get_weapon_max_ricochet_angle()
	var weapon_max_ricochets := _get_weapon_max_ricochets()

	# Clamp bounce limit: use caliber's max_ricochets if set (>=0), else MAX_RICOCHET_BOUNCES.
	# bounce_limit is the maximum number of WALL HITS allowed.
	# After each valid wall hit we continue to show the next segment.
	# After the last allowed valid wall hit, we add one final segment going forward.
	var bounce_limit := MAX_RICOCHET_BOUNCES
	if weapon_max_ricochets >= 0:
		bounce_limit = weapon_max_ricochets

	FileLogger.info("[TrajectoryGlasses] _calculate_ricochet_trajectory: weapon_max_angle=%.1f, weapon_max_ricochets=%d, bounce_limit=%d" % [
		weapon_max_angle, weapon_max_ricochets, bounce_limit
	])

	var space_state := _player.get_world_2d().direct_space_state
	if space_state == null:
		# No physics world - just draw straight line
		points.append(start + direction * max_distance)
		return points

	var bounces_done := 0
	var final_segment_only := false  # True when we should draw one more open segment then stop
	for _seg in range(bounce_limit + 1):
		# Raycast forward from current position
		var ray_end := current_pos + current_dir * max_distance
		var query := PhysicsRayQueryParameters2D.create(current_pos, ray_end)
		query.collision_mask = 4  # Layer 3 = obstacles/walls

		var result := space_state.intersect_ray(query)

		if result.is_empty():
			# No hit — line extends to max distance (all valid, green)
			points.append(ray_end)
			break

		# Hit a wall
		var hit_pos: Vector2 = result.position
		var hit_normal: Vector2 = result.normal

		# Check if ricochet is valid at this angle before adding the point
		var impact_angle := _calculate_impact_angle(current_dir, hit_normal)
		var is_valid_ricochet := weapon_max_angle > 0.0 and impact_angle < weapon_max_angle

		FileLogger.info("[TrajectoryGlasses] seg %d (bounce %d/%d): impact_angle=%.1f, weapon_max_angle=%.1f, is_valid=%s, final_seg=%s" % [
			_seg, bounces_done, bounce_limit, impact_angle, weapon_max_angle, str(is_valid_ricochet), str(final_segment_only)
		])

		# Add the hit point
		points.append(hit_pos)

		if not is_valid_ricochet or final_segment_only:
			# Either invalid ricochet angle, or we've exhausted the weapon's bounce limit.
			# Mark as terminal red segment and stop.
			trajectory_invalid_start_index = points.size() - 1
			trajectory_color = INVALID_RICOCHET_COLOR
			break

		bounces_done += 1

		# Calculate reflection for next segment
		current_dir = current_dir - 2.0 * current_dir.dot(hit_normal) * hit_normal
		current_dir = current_dir.normalized()

		# Move slightly away from surface to avoid re-hitting same spot
		current_pos = hit_pos + current_dir * 2.0

		if bounces_done >= bounce_limit:
			# Reached the weapon's max bounce limit.
			# Allow one more segment to show the final direction, but if it hits
			# another wall that wall hit becomes the red terminal.
			final_segment_only = true

	return points


## Calculate the grazing/impact angle in degrees.
## Returns 0 for parallel (grazing), 90 for perpendicular (direct hit).
func _calculate_impact_angle(direction: Vector2, surface_normal: Vector2) -> float:
	var dot := absf(direction.normalized().dot(surface_normal.normalized()))
	dot = clampf(dot, 0.0, 1.0)
	return rad_to_deg(asin(dot))


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

	# Determine whether the built-in laser should be re-enabled.
	# In Gunslinger mode the laser is disabled unless the Laser Sight active item is equipped.
	# Restoring it unconditionally would introduce the bug reported in Issue #1754.
	var should_enable_laser: bool = true
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager and difficulty_manager.has_method("should_disable_laser_sight"):
		if difficulty_manager.should_disable_laser_sight():
			# Laser is disabled in this difficulty — check whether the Laser Sight item overrides it.
			var active_item_manager: Node = get_node_or_null("/root/ActiveItemManager")
			var has_laser_item: bool = (
				active_item_manager != null
				and active_item_manager.has_method("should_force_laser_sight")
				and active_item_manager.call("should_force_laser_sight")
			)
			should_enable_laser = has_laser_item
			FileLogger.info("[TrajectoryGlasses] _restore_weapon_lasers: Gunslinger mode — laser_item=%s, should_enable=%s" % [
				str(has_laser_item), str(should_enable_laser)
			])

	# Re-enable laser sight on C# weapons
	if _weapon.has_method("SetLaserSightEnabled"):
		_weapon.call("SetLaserSightEnabled", should_enable_laser)
		FileLogger.info("[TrajectoryGlasses] Restored weapon laser sight (enabled=%s)" % str(should_enable_laser))
	elif _weapon.has_method("set_laser_sight_enabled"):
		_weapon.call("set_laser_sight_enabled", should_enable_laser)
		FileLogger.info("[TrajectoryGlasses] Restored weapon laser sight GDScript (enabled=%s)" % str(should_enable_laser))

	# Restore any Line2D children named "LaserSight"
	var laser := _weapon.get_node_or_null("LaserSight")
	if laser and laser is Line2D:
		laser.visible = should_enable_laser

	# Restore Power Fantasy laser if applicable
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
