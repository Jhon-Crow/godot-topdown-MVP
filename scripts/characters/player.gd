extends CharacterBody2D
## Player character controller for top-down movement and shooting.
##
## Uses physics-based movement with acceleration and friction for smooth control.
## Supports WASD and arrow key input via configured input actions.
## Shoots bullets towards the mouse cursor on left mouse button click.
## Features limited ammunition system with progressive spread.
## Includes health system for taking damage from enemy projectiles.

## Maximum movement speed in pixels per second.
@export var max_speed: float = 300.0

## Acceleration rate - how quickly the player reaches max speed.
@export var acceleration: float = 1200.0

## Friction rate - how quickly the player slows down when not moving.
@export var friction: float = 1000.0

## Bullet scene to instantiate when shooting.
@export var bullet_scene: PackedScene

## Offset from player center for bullet spawn position.
@export var bullet_spawn_offset: float = 20.0

## Maximum ammunition (default 90 bullets = 3 magazines of 30 for Normal mode).
## In Hard mode, this is reduced to 60 bullets (2 magazines).
@export var max_ammo: int = 90

## Maximum health of the player.
@export var max_health: int = 5

## Weapon loudness - determines how far gunshots propagate for enemy detection.
## Set to viewport diagonal (~1469 pixels) for assault rifle by default.
## This affects how far enemies can hear the player's gunshots.
@export var weapon_loudness: float = 1469.0

## Reload mode: simple (press R once) or sequence (R-F-R).
@export_enum("Simple", "Sequence") var reload_mode: int = 1  # Default to Sequence mode

## Time to reload in seconds (only used in Simple mode).
@export var reload_time: float = 1.5

## Color when at full health.
@export var full_health_color: Color = Color(0.2, 0.6, 1.0, 1.0)

## Color when at low health (interpolates based on health percentage).
@export var low_health_color: Color = Color(0.1, 0.2, 0.4, 1.0)

## Color to flash when hit.
@export var hit_flash_color: Color = Color(1.0, 1.0, 1.0, 1.0)

## Duration of hit flash effect in seconds.
@export var hit_flash_duration: float = 0.1

## Screen shake intensity per shot in pixels.
## The actual shake distance per shot is calculated as: intensity / fire_rate * 10
## Lower fire rate = larger shake per shot.
@export var screen_shake_intensity: float = 5.0

## Fire rate in shots per second (used for shake calculation).
## Default is 10.0 to match the assault rifle.
@export var fire_rate: float = 10.0

## Minimum recovery time for screen shake at minimum spread.
@export var screen_shake_min_recovery: float = 0.25

## Maximum recovery time for screen shake at maximum spread (min 50ms).
@export var screen_shake_max_recovery: float = 0.05

## Current ammunition count.
var _current_ammo: int = 90

## Current health of the player.
var _current_health: int = 5

## Whether the player is alive.
var _is_alive: bool = true

## Reference to the player model node containing all sprites.
@onready var _player_model: Node2D = $PlayerModel

## References to individual sprite parts for color changes.
@onready var _body_sprite: Sprite2D = $PlayerModel/Body
@onready var _head_sprite: Sprite2D = $PlayerModel/Head
@onready var _left_arm_sprite: Sprite2D = $PlayerModel/LeftArm
@onready var _right_arm_sprite: Sprite2D = $PlayerModel/RightArm

## Legacy reference for compatibility (points to body sprite).
@onready var _sprite: Sprite2D = $PlayerModel/Body

## Progressive spread system parameters.
## Number of shots before spread starts increasing.
const SPREAD_THRESHOLD: int = 3
## Initial minimal spread in degrees.
const INITIAL_SPREAD: float = 0.5
## Spread increase per shot after threshold (degrees).
const SPREAD_INCREMENT: float = 0.6
## Maximum spread in degrees.
const MAX_SPREAD: float = 4.0
## Time in seconds for spread to reset after stopping fire.
const SPREAD_RESET_TIME: float = 0.25

## Current number of consecutive shots.
var _shot_count: int = 0
## Timer since last shot.
var _shot_timer: float = 0.0

## Reload sequence state (0 = waiting for R, 1 = waiting for F, 2 = waiting for R).
var _reload_sequence_step: int = 0

## Whether the player is currently in reload sequence (for Sequence mode).
var _is_reloading_sequence: bool = false

## Whether the player is currently reloading (for Simple mode).
var _is_reloading_simple: bool = false

## Timer for simple reload progress.
var _reload_timer: float = 0.0

## Signal emitted when ammo changes.
signal ammo_changed(current: int, maximum: int)

## Signal emitted when ammo is depleted.
signal ammo_depleted

## Signal emitted when the player is hit.
signal hit

## Signal emitted when health changes.
signal health_changed(current: int, maximum: int)

## Signal emitted when the player dies.
signal died

## Signal emitted when death animation completes.
signal death_animation_completed

## Signal emitted when reload sequence progresses.
signal reload_sequence_progress(step: int, total: int)

## Signal emitted when reload completes.
signal reload_completed

## Signal emitted when reload starts (first step of sequence or simple reload).
## This signal notifies enemies that the player has begun reloading.
signal reload_started

## Signal emitted when grenade count changes.
signal grenade_changed(current: int, maximum: int)

## Signal emitted when a grenade is thrown.
signal grenade_thrown

## Grenade scene to instantiate when throwing.
@export var grenade_scene: PackedScene

## Maximum number of grenades the player can carry.
@export var max_grenades: int = 3

## Current number of grenades.
var _current_grenades: int = 3

## Whether the player is on the tutorial level (infinite grenades).
var _is_tutorial_level: bool = false

## Whether the player is preparing to throw a grenade (G held down).
var _is_preparing_grenade: bool = false

## Position where the grenade throw drag started.
var _grenade_drag_start: Vector2 = Vector2.ZERO

## Whether the grenade throw drag has started.
var _grenade_drag_active: bool = false

## Whether debug mode is enabled (F7 toggle, shows grenade trajectory).
var _debug_mode_enabled: bool = false


func _ready() -> void:
	FileLogger.info("[Player] Initializing player...")

	# Preload bullet scene if not set in inspector
	if bullet_scene == null:
		bullet_scene = preload("res://scenes/projectiles/Bullet.tscn")
		FileLogger.info("[Player] Bullet scene preloaded")

	# Get grenade scene from GrenadeManager (supports grenade type selection)
	# GrenadeManager handles the currently selected grenade type (Flashbang or Frag)
	if grenade_scene == null:
		var grenade_manager: Node = get_node_or_null("/root/GrenadeManager")
		if grenade_manager and grenade_manager.has_method("get_current_grenade_scene"):
			grenade_scene = grenade_manager.get_current_grenade_scene()
			if grenade_scene:
				FileLogger.info("[Player] Grenade scene loaded from GrenadeManager: %s" % grenade_manager.get_grenade_name(grenade_manager.current_grenade_type))
			else:
				FileLogger.info("[Player] WARNING: GrenadeManager returned null grenade scene")
		else:
			# Fallback to flashbang if GrenadeManager is not available
			var grenade_path := "res://scenes/projectiles/FlashbangGrenade.tscn"
			if ResourceLoader.exists(grenade_path):
				grenade_scene = load(grenade_path)
				FileLogger.info("[Player] Grenade scene loaded from fallback: %s" % grenade_path)
			else:
				FileLogger.info("[Player] WARNING: Grenade scene not found at: %s" % grenade_path)
	else:
		FileLogger.info("[Player] Grenade scene already set in inspector")

	# Get max ammo from DifficultyManager based on current difficulty
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager:
		max_ammo = difficulty_manager.get_max_ammo()
		# Connect to difficulty changes to update ammo limit mid-game
		if not difficulty_manager.difficulty_changed.is_connected(_on_difficulty_changed):
			difficulty_manager.difficulty_changed.connect(_on_difficulty_changed)

	_current_ammo = max_ammo
	_current_health = max_health
	_is_alive = true
	_update_health_visual()

	# Detect if we're on the tutorial level
	# Tutorial level is: scenes/levels/csharp/TestTier.tscn with tutorial_level.gd script
	var current_scene := get_tree().current_scene
	if current_scene != null:
		var scene_path := current_scene.scene_file_path
		# Tutorial level is detected by:
		# 1. Scene path contains "csharp/TestTier" (the tutorial scene)
		# 2. OR scene uses tutorial_level.gd script
		_is_tutorial_level = scene_path.contains("csharp/TestTier")

		# Also check if the scene script is tutorial_level.gd
		var script = current_scene.get_script()
		if script != null:
			var script_path: String = script.resource_path
			if script_path.contains("tutorial_level"):
				_is_tutorial_level = true

	# Initialize grenade count based on level type
	# Tutorial: infinite grenades (max count)
	# Other levels: 1 grenade
	if _is_tutorial_level:
		_current_grenades = max_grenades
		FileLogger.info("[Player.Grenade] Tutorial level detected - infinite grenades enabled")
	else:
		_current_grenades = 1
		FileLogger.info("[Player.Grenade] Normal level - starting with 1 grenade")

	# Store base positions for walking animation
	if _body_sprite:
		_base_body_pos = _body_sprite.position
	if _head_sprite:
		_base_head_pos = _head_sprite.position
	if _left_arm_sprite:
		_base_left_arm_pos = _left_arm_sprite.position
	if _right_arm_sprite:
		_base_right_arm_pos = _right_arm_sprite.position

	# Apply scale to player model for larger appearance
	if _player_model:
		_player_model.scale = Vector2(player_model_scale, player_model_scale)

	# Store weapon mount base position for sling animation
	if _weapon_mount:
		_base_weapon_mount_pos = _weapon_mount.position
		_base_weapon_mount_rot = _weapon_mount.rotation

	# Set z-index for proper layering: head should be above weapon
	# The weapon has z_index = 1, so head should be 2 or higher
	if _head_sprite:
		_head_sprite.z_index = 3  # Head on top (above weapon)
	if _body_sprite:
		_body_sprite.z_index = 1  # Body same level as weapon
	if _left_arm_sprite:
		_left_arm_sprite.z_index = 2  # Arms between body and head
	if _right_arm_sprite:
		_right_arm_sprite.z_index = 2  # Arms between body and head

	# Note: Weapon pose detection is done in _process() after a few frames
	# to ensure level scripts have finished adding weapons to the player.
	# See _weapon_pose_applied and _weapon_detect_frame_count variables.

	# Connect to GameManager's debug mode signal for F7 toggle
	_connect_debug_mode_signal()

	# Initialize death animation component
	_init_death_animation()

	FileLogger.info("[Player] Ready! Ammo: %d/%d, Grenades: %d/%d, Health: %d/%d" % [
		_current_ammo, max_ammo,
		_current_grenades, max_grenades,
		_current_health, max_health
	])


func _physics_process(delta: float) -> void:
	if not _is_alive:
		return

	# Detect weapon pose after waiting a few frames for level scripts to add weapons
	if not _weapon_pose_applied:
		_weapon_detect_frame_count += 1
		if _weapon_detect_frame_count >= WEAPON_DETECT_WAIT_FRAMES:
			_detect_and_apply_weapon_pose()
			_weapon_pose_applied = true

	var input_direction := _get_input_direction()

	if input_direction != Vector2.ZERO:
		# Apply acceleration towards the input direction
		velocity = velocity.move_toward(input_direction * max_speed, acceleration * delta)
	else:
		# Apply friction to slow down
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	move_and_slide()

	# Update player model rotation to face the aim direction (rifle direction)
	_update_player_model_rotation()

	# Update walking animation based on movement (only if not in grenade or reload animation)
	if _grenade_anim_phase == GrenadeAnimPhase.NONE and _reload_anim_phase == ReloadAnimPhase.NONE:
		_update_walk_animation(delta, input_direction)

	# Update grenade animation
	_update_grenade_animation(delta)

	# Update reload animation
	_update_reload_animation(delta)

	# Update spread reset timer
	_shot_timer += delta
	if _shot_timer >= SPREAD_RESET_TIME:
		_shot_count = 0

	# Update simple reload timer and animation phases
	if _is_reloading_simple:
		_reload_timer += delta
		# Progress through animation phases based on reload progress
		# Divide reload_time into thirds for each phase
		var phase_duration := reload_time / 3.0
		if _reload_timer < phase_duration:
			# Phase 1: Grab magazine (already started)
			pass
		elif _reload_timer < phase_duration * 2.0:
			# Phase 2: Insert magazine
			if _reload_anim_phase == ReloadAnimPhase.GRAB_MAGAZINE:
				_start_reload_anim_phase(ReloadAnimPhase.INSERT_MAGAZINE, phase_duration)
		elif _reload_timer < reload_time:
			# Phase 3: Pull bolt
			if _reload_anim_phase == ReloadAnimPhase.INSERT_MAGAZINE:
				_start_reload_anim_phase(ReloadAnimPhase.PULL_BOLT, phase_duration)
		else:
			# Complete reload
			_complete_simple_reload()

	# Handle grenade input first (so it can consume shoot input)
	_handle_grenade_input()

	# Make active grenade follow player if held
	if _active_grenade != null and is_instance_valid(_active_grenade):
		_active_grenade.global_position = global_position

	# Handle shooting input (only if not in grenade preparation state)
	# Grenade steps 2 and 3 use LMB, so don't shoot during those
	var can_shoot := _grenade_state == GrenadeState.IDLE or _grenade_state == GrenadeState.TIMER_STARTED
	if can_shoot and Input.is_action_just_pressed("shoot"):
		_shoot()

	# Handle reload input based on mode
	if reload_mode == 0:  # Simple mode
		_handle_simple_reload_input()
	else:  # Sequence mode
		_handle_sequence_reload_input()


func _get_input_direction() -> Vector2:
	var direction := Vector2.ZERO
	direction.x = Input.get_axis("move_left", "move_right")
	direction.y = Input.get_axis("move_up", "move_down")

	# Normalize to prevent faster diagonal movement
	if direction.length() > 1.0:
		direction = direction.normalized()

	return direction


## Updates the player model rotation to face the aim direction.
## The player model (body, head, arms) rotates to follow the rifle's aim direction.
## This creates the appearance of the player rotating their whole body toward the target.
func _update_player_model_rotation() -> void:
	if not _player_model:
		return

	# Calculate direction to mouse cursor
	var mouse_pos := get_global_mouse_position()
	var to_mouse := mouse_pos - global_position

	if to_mouse.length_squared() < 0.001:
		return  # No valid direction

	var aim_direction := to_mouse.normalized()

	# Calculate target rotation angle
	var target_angle := aim_direction.angle()

	# Handle sprite flipping for left/right aim
	# When aiming left (angle > 90° or < -90°), flip vertically to avoid upside-down appearance
	var aiming_left := absf(target_angle) > PI / 2

	# Apply rotation to the player model using GLOBAL rotation.
	# IMPORTANT: We use global_rotation instead of (local) rotation because the Player
	# CharacterBody2D node may also have its own rotation (e.g., during grenade throws).
	# Using global_rotation ensures the PlayerModel's visual direction is set in world
	# coordinates, independent of any parent rotation.
	#
	# When we flip the model vertically (negative scale.y), we must NEGATE the rotation
	# angle to compensate. This is because a negative Y scale mirrors the coordinate
	# system, which inverts the effect of rotation.
	if aiming_left:
		_player_model.global_rotation = -target_angle
		_player_model.scale = Vector2(player_model_scale, -player_model_scale)
	else:
		_player_model.global_rotation = target_angle
		_player_model.scale = Vector2(player_model_scale, player_model_scale)


## Detects the equipped weapon type and applies appropriate arm positioning.
## Called from _physics_process() after a few frames to ensure level scripts
## have finished adding weapons to the player node.
func _detect_and_apply_weapon_pose() -> void:
	FileLogger.info("[Player] Detecting weapon pose (frame %d)..." % _weapon_detect_frame_count)
	var detected_type := WeaponType.RIFLE  # Default to rifle pose

	# Check for weapon children - weapons are added directly to player by level scripts
	# Check in order of specificity: MiniUzi (SMG), Shotgun, then default to Rifle
	var mini_uzi := get_node_or_null("MiniUzi")
	var shotgun := get_node_or_null("Shotgun")

	if mini_uzi != null:
		detected_type = WeaponType.SMG
		FileLogger.info("[Player] Detected weapon: Mini UZI (SMG pose)")
	elif shotgun != null:
		detected_type = WeaponType.SHOTGUN
		FileLogger.info("[Player] Detected weapon: Shotgun (Shotgun pose)")
	else:
		# Default to rifle (AssaultRifle or no weapon)
		detected_type = WeaponType.RIFLE
		FileLogger.info("[Player] Detected weapon: Rifle (default pose)")

	_current_weapon_type = detected_type
	_apply_weapon_arm_offsets()


## Applies arm position offsets based on current weapon type.
## Modifies base arm positions to create appropriate weapon-holding poses.
func _apply_weapon_arm_offsets() -> void:
	# Reset to original scene positions first
	# Original positions from Player.tscn: LeftArm (24, 6), RightArm (-2, 6)
	var original_left_arm_pos := Vector2(24, 6)
	var original_right_arm_pos := Vector2(-2, 6)

	match _current_weapon_type:
		WeaponType.SMG:
			# SMG pose: Compact two-handed grip
			# Left arm moves back toward body for shorter weapon
			# Right arm moves forward slightly to meet left hand
			_base_left_arm_pos = original_left_arm_pos + SMG_LEFT_ARM_OFFSET
			_base_right_arm_pos = original_right_arm_pos + SMG_RIGHT_ARM_OFFSET
			FileLogger.info("[Player] Applied SMG arm pose: Left=%s, Right=%s" % [
				str(_base_left_arm_pos), str(_base_right_arm_pos)
			])
		WeaponType.SHOTGUN:
			# Shotgun pose: Similar to rifle but slightly tighter
			_base_left_arm_pos = original_left_arm_pos + Vector2(-3, 0)
			_base_right_arm_pos = original_right_arm_pos + Vector2(1, 0)
			FileLogger.info("[Player] Applied Shotgun arm pose: Left=%s, Right=%s" % [
				str(_base_left_arm_pos), str(_base_right_arm_pos)
			])
		WeaponType.RIFLE, _:
			# Rifle pose: Standard extended grip (original positions)
			_base_left_arm_pos = original_left_arm_pos
			_base_right_arm_pos = original_right_arm_pos
			FileLogger.info("[Player] Applied Rifle arm pose: Left=%s, Right=%s" % [
				str(_base_left_arm_pos), str(_base_right_arm_pos)
			])

	# Apply new base positions to sprites immediately
	if _left_arm_sprite:
		_left_arm_sprite.position = _base_left_arm_pos
	if _right_arm_sprite:
		_right_arm_sprite.position = _base_right_arm_pos


## Updates the walking animation based on player movement state.
## Creates a natural bobbing motion for body parts during movement.
## @param delta: Time since last frame.
## @param input_direction: Current movement input direction.
func _update_walk_animation(delta: float, input_direction: Vector2) -> void:
	var is_moving := input_direction != Vector2.ZERO or velocity.length() > 10.0

	if is_moving:
		# Accumulate animation time based on movement speed
		var speed_factor := velocity.length() / max_speed
		_walk_anim_time += delta * walk_anim_speed * speed_factor
		_is_walking = true

		# Calculate animation offsets using sine waves
		# Body bobs up and down (frequency = 2x for double step)
		var body_bob := sin(_walk_anim_time * 2.0) * 1.5 * walk_anim_intensity

		# Head bobs slightly less than body (dampened)
		var head_bob := sin(_walk_anim_time * 2.0) * 0.8 * walk_anim_intensity

		# Arms swing opposite to each other (alternating)
		var arm_swing := sin(_walk_anim_time) * 3.0 * walk_anim_intensity

		# Apply offsets to sprites
		if _body_sprite:
			_body_sprite.position = _base_body_pos + Vector2(0, body_bob)

		if _head_sprite:
			_head_sprite.position = _base_head_pos + Vector2(0, head_bob)

		if _left_arm_sprite:
			# Left arm swings forward/back (y-axis in top-down)
			_left_arm_sprite.position = _base_left_arm_pos + Vector2(arm_swing, 0)

		if _right_arm_sprite:
			# Right arm swings opposite to left arm
			_right_arm_sprite.position = _base_right_arm_pos + Vector2(-arm_swing, 0)
	else:
		# Return to idle pose smoothly
		if _is_walking:
			_is_walking = false
			_walk_anim_time = 0.0

		# Interpolate back to base positions
		var lerp_speed := 10.0 * delta
		if _body_sprite:
			_body_sprite.position = _body_sprite.position.lerp(_base_body_pos, lerp_speed)
		if _head_sprite:
			_head_sprite.position = _head_sprite.position.lerp(_base_head_pos, lerp_speed)
		if _left_arm_sprite:
			_left_arm_sprite.position = _left_arm_sprite.position.lerp(_base_left_arm_pos, lerp_speed)
		if _right_arm_sprite:
			_right_arm_sprite.position = _right_arm_sprite.position.lerp(_base_right_arm_pos, lerp_speed)


## Calculate current spread based on consecutive shots.
func _get_current_spread() -> float:
	if _shot_count <= SPREAD_THRESHOLD:
		return INITIAL_SPREAD
	else:
		var extra_shots := _shot_count - SPREAD_THRESHOLD
		var spread := INITIAL_SPREAD + extra_shots * SPREAD_INCREMENT
		return minf(spread, MAX_SPREAD)


func _shoot() -> void:
	if bullet_scene == null:
		return

	# Check ammo
	if _current_ammo <= 0:
		# Play empty click sound
		var audio_manager: Node = get_node_or_null("/root/AudioManager")
		if audio_manager and audio_manager.has_method("play_empty_click"):
			audio_manager.play_empty_click(global_position)
		ammo_depleted.emit()
		return

	# Calculate direction towards mouse cursor
	var mouse_pos := get_global_mouse_position()
	var shoot_direction := (mouse_pos - global_position).normalized()

	# Apply spread
	var spread := _get_current_spread()
	var spread_radians := deg_to_rad(spread)
	var random_spread := randf_range(-spread_radians, spread_radians)
	shoot_direction = shoot_direction.rotated(random_spread)

	# Create bullet instance
	var bullet := bullet_scene.instantiate()

	# Set bullet position with offset in shoot direction
	bullet.global_position = global_position + shoot_direction * bullet_spawn_offset

	# Set bullet direction
	bullet.direction = shoot_direction

	# Set shooter ID to identify this player as the source
	# This prevents the player from being hit by their own bullets
	bullet.shooter_id = get_instance_id()

	# Set shooter position for distance-based penetration calculation
	# Direct assignment - the bullet script defines this property
	bullet.shooter_position = global_position

	# Add bullet to the scene tree (parent's parent to avoid it being a child of player)
	get_tree().current_scene.add_child(bullet)

	# Play shooting sound
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_m16_shot"):
		audio_manager.play_m16_shot(global_position)

	# Emit gunshot sound for in-game sound propagation (alerts enemies)
	# Uses weapon_loudness to determine propagation range
	var sound_propagation: Node = get_node_or_null("/root/SoundPropagation")
	if sound_propagation and sound_propagation.has_method("emit_sound"):
		# Use emit_sound with custom range for weapon-specific loudness
		sound_propagation.emit_sound(0, global_position, 0, self, weapon_loudness)  # 0 = GUNSHOT, 0 = PLAYER

	# Play shell casing sound with a small delay
	if audio_manager and audio_manager.has_method("play_shell_rifle"):
		_play_delayed_shell_sound()

	# Trigger screen shake
	_trigger_screen_shake(shoot_direction)

	# Update ammo and shot count
	_current_ammo -= 1
	_shot_count += 1
	_shot_timer = 0.0
	ammo_changed.emit(_current_ammo, max_ammo)


## Trigger screen shake based on shooting direction and current spread.
func _trigger_screen_shake(shoot_direction: Vector2) -> void:
	if screen_shake_intensity <= 0.0:
		return

	var screen_shake: Node = get_node_or_null("/root/ScreenShakeManager")
	if not screen_shake:
		return

	# Calculate shake intensity based on fire rate
	# Lower fire rate = larger shake per shot
	var shake_intensity: float
	if fire_rate > 0.0:
		shake_intensity = screen_shake_intensity / fire_rate * 10.0
	else:
		shake_intensity = screen_shake_intensity

	# Calculate spread ratio for recovery time interpolation
	var current_spread := _get_current_spread()
	var spread_ratio := 0.0
	if MAX_SPREAD > INITIAL_SPREAD:
		spread_ratio = clampf((current_spread - INITIAL_SPREAD) / (MAX_SPREAD - INITIAL_SPREAD), 0.0, 1.0)

	# Calculate recovery time based on spread ratio
	# At min spread -> slower recovery (min_recovery)
	# At max spread -> faster recovery (max_recovery)
	var recovery_time := lerpf(screen_shake_min_recovery, screen_shake_max_recovery, spread_ratio)
	# Clamp to minimum 50ms as per specification
	recovery_time = maxf(recovery_time, 0.05)

	# Trigger the shake via ScreenShakeManager
	screen_shake.add_shake(shoot_direction, shake_intensity, recovery_time)


## Play shell casing sound with a delay to simulate the casing hitting the ground.
func _play_delayed_shell_sound() -> void:
	await get_tree().create_timer(0.15).timeout
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_shell_rifle"):
		audio_manager.play_shell_rifle(global_position)


## Get current ammo count.
func get_current_ammo() -> int:
	return _current_ammo


## Get maximum ammo count.
func get_max_ammo() -> int:
	return max_ammo


## Handle simple reload input (just press R once).
## Reload takes reload_time seconds to complete.
## Animation plays all three steps automatically.
func _handle_simple_reload_input() -> void:
	# Don't start reload if already reloading or at max ammo
	if _is_reloading_simple or _current_ammo >= max_ammo:
		return

	if Input.is_action_just_pressed("reload"):
		_is_reloading_simple = true
		_reload_timer = 0.0
		# Start animation: begins with grab magazine
		_start_reload_anim_phase(ReloadAnimPhase.GRAB_MAGAZINE, RELOAD_ANIM_GRAB_DURATION)
		# Play full reload sound for simple mode
		var audio_manager: Node = get_node_or_null("/root/AudioManager")
		if audio_manager and audio_manager.has_method("play_reload_full"):
			audio_manager.play_reload_full(global_position)
		reload_sequence_progress.emit(1, 1)
		# Notify enemies that reload has started
		reload_started.emit()


## Complete the simple reload.
func _complete_simple_reload() -> void:
	_current_ammo = max_ammo
	_is_reloading_simple = false
	_reload_timer = 0.0
	# Transition to return idle animation
	_start_reload_anim_phase(ReloadAnimPhase.RETURN_IDLE, RELOAD_ANIM_RETURN_DURATION)
	ammo_changed.emit(_current_ammo, max_ammo)
	reload_completed.emit()
	# Emit reload completion sound for in-game sound propagation
	# This alerts enemies that player is no longer vulnerable and they should become cautious
	var sound_propagation: Node = get_node_or_null("/root/SoundPropagation")
	if sound_propagation and sound_propagation.has_method("emit_player_reload_complete"):
		sound_propagation.emit_player_reload_complete(global_position, self)


## Handle reload sequence input (R-F-R).
## Player must press R, then F, then R again to complete reload.
## Reload happens instantly once sequence is completed.
## Three animation steps:
## 1. R press: Grab magazine from chest with left hand
## 2. F press: Insert magazine into rifle
## 3. R press: Pull the bolt/charging handle
func _handle_sequence_reload_input() -> void:
	# Don't process reload if already at max ammo
	if _current_ammo >= max_ammo:
		_reload_sequence_step = 0
		_is_reloading_sequence = false
		return

	var audio_manager: Node = get_node_or_null("/root/AudioManager")

	match _reload_sequence_step:
		0:
			# Waiting for first R press
			if Input.is_action_just_pressed("reload"):
				_reload_sequence_step = 1
				_is_reloading_sequence = true
				# Start animation: Step 1 - Grab magazine from chest
				_start_reload_anim_phase(ReloadAnimPhase.GRAB_MAGAZINE, RELOAD_ANIM_GRAB_DURATION)
				# Play magazine out sound
				if audio_manager and audio_manager.has_method("play_reload_mag_out"):
					audio_manager.play_reload_mag_out(global_position)
				reload_sequence_progress.emit(1, 3)
				# Notify enemies that reload has started
				reload_started.emit()
		1:
			# Waiting for F press
			if Input.is_action_just_pressed("reload_step"):
				_reload_sequence_step = 2
				# Start animation: Step 2 - Insert magazine into rifle
				_start_reload_anim_phase(ReloadAnimPhase.INSERT_MAGAZINE, RELOAD_ANIM_INSERT_DURATION)
				# Play magazine in sound
				if audio_manager and audio_manager.has_method("play_reload_mag_in"):
					audio_manager.play_reload_mag_in(global_position)
				reload_sequence_progress.emit(2, 3)
			elif Input.is_action_just_pressed("reload"):
				# R pressed again - restart sequence with mag out sound
				_reload_sequence_step = 1
				# Restart animation from grab phase
				_start_reload_anim_phase(ReloadAnimPhase.GRAB_MAGAZINE, RELOAD_ANIM_GRAB_DURATION)
				if audio_manager and audio_manager.has_method("play_reload_mag_out"):
					audio_manager.play_reload_mag_out(global_position)
				reload_sequence_progress.emit(1, 3)
		2:
			# Waiting for final R press
			if Input.is_action_just_pressed("reload"):
				# Start animation: Step 3 - Pull bolt/charging handle
				_start_reload_anim_phase(ReloadAnimPhase.PULL_BOLT, RELOAD_ANIM_BOLT_DURATION)
				# Play bolt cycling sound and complete reload
				if audio_manager and audio_manager.has_method("play_m16_bolt"):
					audio_manager.play_m16_bolt(global_position)
				_complete_reload()
			elif Input.is_action_just_pressed("reload_step"):
				# Wrong key pressed, reset sequence
				_reload_sequence_step = 1
				# Restart animation from grab phase
				_start_reload_anim_phase(ReloadAnimPhase.GRAB_MAGAZINE, RELOAD_ANIM_GRAB_DURATION)
				if audio_manager and audio_manager.has_method("play_reload_mag_out"):
					audio_manager.play_reload_mag_out(global_position)
				reload_sequence_progress.emit(1, 3)


## Complete the reload - instantly refill ammo.
func _complete_reload() -> void:
	_current_ammo = max_ammo
	_reload_sequence_step = 0
	_is_reloading_sequence = false
	# Bolt pull phase transitions automatically to RETURN_IDLE in _update_reload_animation
	ammo_changed.emit(_current_ammo, max_ammo)
	reload_completed.emit()
	reload_sequence_progress.emit(3, 3)
	# Emit reload completion sound for in-game sound propagation
	# This alerts enemies that player is no longer vulnerable and they should become cautious
	var sound_propagation: Node = get_node_or_null("/root/SoundPropagation")
	if sound_propagation and sound_propagation.has_method("emit_player_reload_complete"):
		sound_propagation.emit_player_reload_complete(global_position, self)


## Check if player is currently reloading (either mode).
func is_reloading() -> bool:
	return _is_reloading_sequence or _is_reloading_simple


## Get current reload sequence step (0-2).
func get_reload_step() -> int:
	return _reload_sequence_step


## Cancel the reload (both modes) and reset.
func cancel_reload() -> void:
	_reload_sequence_step = 0
	_is_reloading_sequence = false
	_is_reloading_simple = false
	_reload_timer = 0.0
	# Return arms to idle if reload animation was active
	if _reload_anim_phase != ReloadAnimPhase.NONE:
		_start_reload_anim_phase(ReloadAnimPhase.RETURN_IDLE, RELOAD_ANIM_RETURN_DURATION)


## Called when hit by a projectile.
func on_hit() -> void:
	# Call extended version with default values
	on_hit_with_info(Vector2.RIGHT, null)


## Called when hit by a projectile with extended hit information.
## @param hit_direction: Direction the bullet was traveling.
## @param caliber_data: Caliber resource for effect scaling.
func on_hit_with_info(hit_direction: Vector2, caliber_data: Resource) -> void:
	if not _is_alive:
		return

	hit.emit()

	# Store hit direction for death animation
	_last_hit_direction = hit_direction

	# Show hit flash effect
	_show_hit_flash()

	# Apply damage
	_current_health -= 1
	health_changed.emit(_current_health, max_health)

	# Register damage with ScoreManager
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager and score_manager.has_method("register_damage_taken"):
		score_manager.register_damage_taken(1)

	# Play appropriate hit sound and spawn visual effects
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	var impact_manager: Node = get_node_or_null("/root/ImpactEffectsManager")

	if _current_health <= 0:
		# Play lethal hit sound
		if audio_manager and audio_manager.has_method("play_hit_lethal"):
			audio_manager.play_hit_lethal(global_position)
		# Spawn blood splatter effect for lethal hit (with decal)
		if impact_manager and impact_manager.has_method("spawn_blood_effect"):
			impact_manager.spawn_blood_effect(global_position, hit_direction, caliber_data, true)
		_on_death()
	else:
		# Play non-lethal hit sound
		if audio_manager and audio_manager.has_method("play_hit_non_lethal"):
			audio_manager.play_hit_non_lethal(global_position)
		# Spawn blood effect for non-lethal hit (smaller, no decal)
		if impact_manager and impact_manager.has_method("spawn_blood_effect"):
			impact_manager.spawn_blood_effect(global_position, hit_direction, caliber_data, false)
		_update_health_visual()


## Shows a brief flash effect when hit.
func _show_hit_flash() -> void:
	if not _player_model:
		return

	_set_all_sprites_modulate(hit_flash_color)

	await get_tree().create_timer(hit_flash_duration).timeout

	# Restore color based on current health (if still alive)
	if _is_alive:
		_update_health_visual()


## Updates the sprite color based on current health percentage.
func _update_health_visual() -> void:
	if not _player_model:
		return

	# Interpolate color based on health percentage
	var health_percent := _get_health_percent()
	var color := full_health_color.lerp(low_health_color, 1.0 - health_percent)
	_set_all_sprites_modulate(color)


## Public method to refresh the health visual.
## Called by effects managers (like LastChanceEffectsManager) after they finish
## modifying player sprite colors, to ensure the player returns to correct
## health-based coloring.
func refresh_health_visual() -> void:
	_update_health_visual()


## Sets the modulate color on all player sprite parts.
## The armband is a separate child sprite that keeps its original color,
## so all body parts including right arm use the same health-based color.
## @param color: The color to apply to all sprites.
func _set_all_sprites_modulate(color: Color) -> void:
	if _body_sprite:
		_body_sprite.modulate = color
	if _head_sprite:
		_head_sprite.modulate = color
	if _left_arm_sprite:
		_left_arm_sprite.modulate = color
	if _right_arm_sprite:
		# Right arm uses the same color as other body parts.
		# The armband is now a separate child sprite (Armband node) that
		# doesn't inherit this modulate, keeping its bright red color visible.
		_right_arm_sprite.modulate = color


## Returns the current health as a percentage (0.0 to 1.0).
func _get_health_percent() -> float:
	if max_health <= 0:
		return 0.0
	return float(_current_health) / float(max_health)


## Called when the player dies.
func _on_death() -> void:
	_is_alive = false
	died.emit()

	# Start death animation with the hit direction
	if _death_animation and _death_animation.has_method("start_death_animation"):
		_death_animation.start_death_animation(_last_hit_direction)
		FileLogger.info("[Player] Death animation started with hit direction: %s" % str(_last_hit_direction))
	else:
		# Fallback to visual feedback if death animation not available
		_set_all_sprites_modulate(Color(0.3, 0.3, 0.3, 0.5))


## Get current health.
func get_current_health() -> int:
	return _current_health


## Get maximum health.
func get_max_health() -> int:
	return max_health


## Check if player is alive.
func is_alive() -> bool:
	return _is_alive


## Initialize the death animation component.
func _init_death_animation() -> void:
	# Create death animation component as a child node
	_death_animation = DeathAnimationComponent.new()
	_death_animation.name = "DeathAnimation"
	add_child(_death_animation)

	# Initialize with sprite references
	_death_animation.initialize(
		_body_sprite,
		_head_sprite,
		_left_arm_sprite,
		_right_arm_sprite,
		_player_model
	)

	# Connect signals
	_death_animation.death_animation_completed.connect(_on_death_animation_completed)
	_death_animation.ragdoll_activated.connect(_on_ragdoll_activated)

	FileLogger.info("[Player] Death animation component initialized")


## Called when death animation completes (body at rest).
func _on_death_animation_completed() -> void:
	FileLogger.info("[Player] Death animation completed")
	death_animation_completed.emit()

	# Apply final darkening effect
	_set_all_sprites_modulate(Color(0.3, 0.3, 0.3, 0.5))


## Called when ragdoll physics activates.
func _on_ragdoll_activated() -> void:
	FileLogger.info("[Player] Ragdoll activated")


## Reset the player state (called on respawn).
## Note: This resets death animation as well.
func reset_player() -> void:
	_is_alive = true
	_current_health = max_health
	_current_ammo = max_ammo

	# Reset death animation
	if _death_animation and _death_animation.has_method("reset"):
		_death_animation.reset()

	_update_health_visual()
	health_changed.emit(_current_health, max_health)
	ammo_changed.emit(_current_ammo, max_ammo)
	FileLogger.info("[Player] Player reset")


## Called when difficulty changes mid-game.
## Updates max ammo based on new difficulty setting.
func _on_difficulty_changed(_new_difficulty: int) -> void:
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager:
		var new_max_ammo := difficulty_manager.get_max_ammo()
		# Only update if the max ammo changed
		if new_max_ammo != max_ammo:
			var old_max_ammo := max_ammo
			max_ammo = new_max_ammo
			# Scale current ammo proportionally, but cap at new max
			if old_max_ammo > 0:
				_current_ammo = mini(_current_ammo, max_ammo)
			else:
				_current_ammo = max_ammo
			ammo_changed.emit(_current_ammo, max_ammo)


# ============================================================================
# Grenade System
# ============================================================================

## Grenade throw state machine (2-step mechanic).
## Step 1: G + RMB drag right = start timer (pin pulled)
## Step 2: Hold G → press+hold RMB → release G = ready to throw (only RMB held)
## Step 3: RMB drag and release = throw
enum GrenadeState {
	IDLE,                 # No grenade action
	TIMER_STARTED,        # Step 1 complete: timer running, G held, waiting for RMB
	WAITING_FOR_G_RELEASE,# Step 2 in progress: G+RMB held, waiting for G release
	AIMING                # Step 2 complete: only RMB held, drag to aim and release to throw
}

# ============================================================================
# Reload Animation System
# ============================================================================

## Animation phases for assault rifle reload sequence.
## Maps to the R-F-R input system for visual feedback.
## Three steps as requested:
## 1. Take magazine with left hand from chest
## 2. Insert magazine into rifle
## 3. Pull the bolt/charging handle
enum ReloadAnimPhase {
	NONE,               # Normal arm positions (weapon held)
	GRAB_MAGAZINE,      # Step 1: Left hand moves to chest to grab new magazine
	INSERT_MAGAZINE,    # Step 2: Left hand brings magazine to weapon, inserts it
	PULL_BOLT,          # Step 3: Character pulls the charging handle
	RETURN_IDLE         # Arms return to normal weapon-holding position
}

## Current reload animation phase.
var _reload_anim_phase: int = ReloadAnimPhase.NONE

## Reload animation phase timer for timed transitions.
var _reload_anim_timer: float = 0.0

## Reload animation phase duration in seconds.
var _reload_anim_duration: float = 0.0

## Target positions for reload arm animations (relative offsets from base positions).
## These are in local PlayerModel space.
## Base positions: LeftArm (24, 6), RightArm (-2, 6)
## For reload, left arm goes to chest (vest/mag pouch area), then to weapon

# Step 1: Grab magazine from chest - left arm moves back toward body
const RELOAD_ARM_LEFT_GRAB := Vector2(-18, -2)        # Left hand at chest/vest mag pouch
const RELOAD_ARM_RIGHT_HOLD := Vector2(0, 0)          # Right hand stays on weapon grip

# Step 2: Insert magazine - left arm moves to weapon magwell
const RELOAD_ARM_LEFT_INSERT := Vector2(8, 2)         # Left hand at weapon magwell (forward)
const RELOAD_ARM_RIGHT_STEADY := Vector2(0, 1)        # Right hand steadies weapon

# Step 3: Pull bolt - both arms involved, right pulls charging handle
const RELOAD_ARM_LEFT_SUPPORT := Vector2(12, 0)       # Left hand holds foregrip
const RELOAD_ARM_RIGHT_BOLT := Vector2(-6, -3)        # Right hand pulls bolt back

## Target rotations for reload arm animations (in degrees).
const RELOAD_ARM_ROT_LEFT_GRAB := -50.0      # Arm rotation when grabbing mag from chest
const RELOAD_ARM_ROT_RIGHT_HOLD := 0.0       # Right arm steady during grab
const RELOAD_ARM_ROT_LEFT_INSERT := -10.0    # Left arm rotation when inserting
const RELOAD_ARM_ROT_RIGHT_STEADY := 5.0     # Slight tilt while steadying
const RELOAD_ARM_ROT_LEFT_SUPPORT := 0.0     # Left arm on foregrip
const RELOAD_ARM_ROT_RIGHT_BOLT := -20.0     # Right arm rotation when pulling bolt

## Animation durations for each reload phase (in seconds).
const RELOAD_ANIM_GRAB_DURATION := 0.25      # Time to grab magazine from chest
const RELOAD_ANIM_INSERT_DURATION := 0.3     # Time to insert magazine
const RELOAD_ANIM_BOLT_DURATION := 0.2       # Time to pull bolt
const RELOAD_ANIM_RETURN_DURATION := 0.2     # Time to return to idle

## Current grenade state.
var _grenade_state: int = GrenadeState.IDLE

## Active grenade instance (created when timer starts).
var _active_grenade: RigidBody2D = null

## Position where the aiming drag started.
var _aim_drag_start: Vector2 = Vector2.ZERO

## Time when the grenade timer was started (for tracking in case grenade explodes in hand).
var _grenade_timer_start_time: float = 0.0

## Player's rotation before throw (to restore after throw animation).
var _player_rotation_before_throw: float = 0.0

## Whether player is in throw rotation animation.
var _is_throw_rotating: bool = false

## Target rotation for throw animation.
var _throw_target_rotation: float = 0.0

## Time remaining for throw rotation to restore.
var _throw_rotation_restore_timer: float = 0.0

## Duration of throw rotation animation in seconds.
const THROW_ROTATION_DURATION: float = 0.15

# ============================================================================
# Walking Animation System
# ============================================================================

## Walking animation speed multiplier - higher = faster leg cycle.
@export var walk_anim_speed: float = 12.0

## Walking animation intensity - higher = more pronounced movement.
@export var walk_anim_intensity: float = 1.0

## Scale multiplier for the player model (body, head, arms).
## Default is 1.3 to make the player slightly larger.
@export var player_model_scale: float = 1.3

## Current walk animation time (accumulator for sine wave).
var _walk_anim_time: float = 0.0

## Last hit direction (used for death animation).
var _last_hit_direction: Vector2 = Vector2.RIGHT

## Death animation component reference.
var _death_animation: Node = null

## Note: DeathAnimationComponent is available via class_name declaration.

## Whether the player is currently walking (for animation state).
var _is_walking: bool = false

## Base positions for body parts (stored on ready for animation offsets).
var _base_body_pos: Vector2 = Vector2.ZERO
var _base_head_pos: Vector2 = Vector2.ZERO
var _base_left_arm_pos: Vector2 = Vector2.ZERO
var _base_right_arm_pos: Vector2 = Vector2.ZERO

# ============================================================================
# Weapon-Specific Arm Positioning System
# ============================================================================

## Weapon types for arm positioning.
## Different weapon types require different arm poses for realistic holding.
enum WeaponType {
	RIFLE,  # Long barrel weapons (M16, AK47) - arms spread apart
	SMG,    # Compact weapons (UZI, MP5) - arms closer together
	SHOTGUN # Medium weapons (pump shotgun) - intermediate pose
}

## Currently detected weapon type.
var _current_weapon_type: int = WeaponType.RIFLE

## Whether weapon pose has been detected and applied.
## Used to trigger detection in first few _process frames after _ready().
var _weapon_pose_applied: bool = false

## Frame counter for delayed weapon pose detection.
## Weapons are added by level scripts AFTER player's _ready() completes.
## We wait a few frames to ensure the weapon is added before detecting.
var _weapon_detect_frame_count: int = 0

## Number of frames to wait before detecting weapon pose.
## This ensures level scripts have finished adding weapons.
const WEAPON_DETECT_WAIT_FRAMES: int = 3

## Arm position offsets for SMG weapons (relative to rifle base positions).
## UZI and similar compact SMGs should have the left arm closer to the body
## for a proper two-handed compact grip.
## Left arm moves back (negative X) to create compact grip.
const SMG_LEFT_ARM_OFFSET := Vector2(-10, 0)
## Right arm moves slightly forward to meet left hand.
const SMG_RIGHT_ARM_OFFSET := Vector2(3, 0)

# ============================================================================
# Grenade Animation System
# ============================================================================

## Animation phases for grenade throwing sequence.
## Maps to the multi-step input system for visual feedback.
enum GrenadeAnimPhase {
	NONE,           # Normal arm positions (walking/idle)
	GRAB_GRENADE,   # Left hand moves to chest to grab grenade
	PULL_PIN,       # Right hand pulls pin (quick snap animation)
	HANDS_APPROACH, # Right hand moves toward left hand
	TRANSFER,       # Grenade transfers to right hand
	WIND_UP,        # Dynamic wind-up based on drag
	THROW,          # Throwing motion
	RETURN_IDLE     # Arms return to normal positions
}

## Current grenade animation phase.
var _grenade_anim_phase: int = GrenadeAnimPhase.NONE

## Animation phase timer for timed transitions.
var _grenade_anim_timer: float = 0.0

## Animation phase duration in seconds.
var _grenade_anim_duration: float = 0.0

## Current wind-up intensity (0.0 = no wind-up, 1.0 = maximum wind-up).
var _wind_up_intensity: float = 0.0

## Previous mouse position for velocity calculation.
var _prev_mouse_pos: Vector2 = Vector2.ZERO

## Whether weapon is in sling position (lowered for grenade handling).
var _weapon_slung: bool = false

## Reference to weapon mount for sling animation.
@onready var _weapon_mount: Node2D = $PlayerModel/WeaponMount

## Base weapon mount position (for sling animation).
var _base_weapon_mount_pos: Vector2 = Vector2.ZERO

## Base weapon mount rotation (for sling animation).
var _base_weapon_mount_rot: float = 0.0

## Target positions for arm animations (relative offsets from base positions).
## These are in local PlayerModel space.
## Base positions: LeftArm (24, 6), RightArm (-2, 6)
## Body position: (-4, 0), so left shoulder area is approximately x=0 to x=5
## To move left arm from x=24 to shoulder (x~5), we need offset of ~-20
## During grenade operations, left arm should be BEHIND the body (toward shoulder)
const ARM_LEFT_CHEST := Vector2(-15, 0)         # Left hand moves back to chest/shoulder area
const ARM_RIGHT_PIN := Vector2(2, -2)           # Right hand slightly up for pin pull
const ARM_LEFT_EXTENDED := Vector2(-10, 2)      # Left hand at chest level with grenade
const ARM_RIGHT_APPROACH := Vector2(4, 0)       # Right hand approaching left
const ARM_LEFT_TRANSFER := Vector2(-12, 3)      # Left hand drops back after transfer
const ARM_RIGHT_HOLD := Vector2(3, 1)           # Right hand holding grenade
const ARM_RIGHT_WIND_MIN := Vector2(4, 3)       # Minimum wind-up position
const ARM_RIGHT_WIND_MAX := Vector2(8, 5)       # Maximum wind-up position
const ARM_RIGHT_THROW := Vector2(-4, -2)        # Throw follow-through
const ARM_LEFT_RELAXED := Vector2(-20, 2)       # Left arm at shoulder/body during wind-up/throw

## Target rotations for arm animations (in degrees).
const ARM_ROT_GRAB := -45.0           # Arm rotation when grabbing at chest
const ARM_ROT_PIN_PULL := -15.0       # Right arm rotation when pulling pin
const ARM_ROT_LEFT_AT_CHEST := -30.0  # Left arm rotation while holding grenade at chest
const ARM_ROT_WIND_MIN := 15.0        # Right arm minimum wind-up rotation
const ARM_ROT_WIND_MAX := 35.0        # Right arm maximum wind-up rotation
const ARM_ROT_THROW := -25.0          # Right arm throw rotation
const ARM_ROT_LEFT_RELAXED := -60.0   # Left arm hangs down at side during wind-up/throw

## Animation durations for each phase (in seconds).
const ANIM_GRAB_DURATION := 0.2
const ANIM_PIN_DURATION := 0.15
const ANIM_APPROACH_DURATION := 0.2
const ANIM_TRANSFER_DURATION := 0.15
const ANIM_THROW_DURATION := 0.2
const ANIM_RETURN_DURATION := 0.3

## Animation lerp speeds.
const ANIM_LERP_SPEED := 15.0         # Position interpolation speed
const ANIM_LERP_SPEED_FAST := 25.0    # Fast interpolation for snappy movements

## Weapon sling position (lowered and rotated for chest carry).
const WEAPON_SLING_OFFSET := Vector2(0, 15)     # Lower weapon
const WEAPON_SLING_ROTATION := 1.2              # Rotate to hang down (radians, ~70 degrees)


## Handle grenade input with 2-step mechanic.
## Step 1: G + RMB drag right = start timer (pull pin)
## Step 2: Hold G → press+hold RMB → release G = ready to throw
## Step 3: RMB drag and release = throw
func _handle_grenade_input() -> void:
	# Handle throw rotation animation
	_handle_throw_rotation_animation(get_physics_process_delta_time())

	# Check for active grenade explosion (explodes in hand after 4 seconds)
	if _active_grenade != null and not is_instance_valid(_active_grenade):
		# Grenade was destroyed (exploded)
		_reset_grenade_state()
		return

	match _grenade_state:
		GrenadeState.IDLE:
			_handle_grenade_idle_state()
		GrenadeState.TIMER_STARTED:
			_handle_grenade_timer_started_state()
		GrenadeState.WAITING_FOR_G_RELEASE:
			_handle_grenade_waiting_for_g_release_state()
		GrenadeState.AIMING:
			_handle_grenade_aiming_state()


## Handle IDLE state: waiting for G + RMB drag right to start timer.
func _handle_grenade_idle_state() -> void:
	# Start grab animation when G is first pressed (check before the is_action_pressed block)
	if Input.is_action_just_pressed("grenade_prepare") and _current_grenades > 0:
		_start_grenade_anim_phase(GrenadeAnimPhase.GRAB_GRENADE, ANIM_GRAB_DURATION)
		FileLogger.info("[Player.Grenade] G pressed - starting grab animation")

	# Check if G key is held and player has grenades
	if Input.is_action_pressed("grenade_prepare") and _current_grenades > 0:
		# Start drag tracking for step 1
		if Input.is_action_just_pressed("grenade_throw"):
			_grenade_drag_start = get_global_mouse_position()
			_grenade_drag_active = true
			FileLogger.info("[Player.Grenade] Step 1 started: G held, RMB pressed at %s" % str(_grenade_drag_start))

		# Check for drag release (complete step 1)
		if _grenade_drag_active and Input.is_action_just_released("grenade_throw"):
			var drag_end := get_global_mouse_position()
			var drag_vector := drag_end - _grenade_drag_start

			# Check if dragged to the right (positive X direction)
			if drag_vector.x > 20.0:  # Minimum drag distance
				_start_grenade_timer()
				# Start pin pull animation
				_start_grenade_anim_phase(GrenadeAnimPhase.PULL_PIN, ANIM_PIN_DURATION)
				FileLogger.info("[Player.Grenade] Step 1 complete: Timer started! Drag right detected (%.1f pixels)" % drag_vector.x)
			else:
				FileLogger.info("[Player.Grenade] Step 1 cancelled: Drag was not to the right (x=%.1f)" % drag_vector.x)
				# Cancel animation if drag was cancelled
				_start_grenade_anim_phase(GrenadeAnimPhase.RETURN_IDLE, ANIM_RETURN_DURATION)

			_grenade_drag_active = false
	else:
		# G released without completing - return to idle
		if _grenade_anim_phase == GrenadeAnimPhase.GRAB_GRENADE:
			_start_grenade_anim_phase(GrenadeAnimPhase.RETURN_IDLE, ANIM_RETURN_DURATION)
		_grenade_drag_active = false


## Handle TIMER_STARTED state: waiting for RMB press while G is held (Step 2 part 1).
func _handle_grenade_timer_started_state() -> void:
	# G must still be held to continue
	if not Input.is_action_pressed("grenade_prepare"):
		# G released - cancel and drop grenade
		FileLogger.info("[Player.Grenade] Cancelled: G released while timer running")
		_start_grenade_anim_phase(GrenadeAnimPhase.RETURN_IDLE, ANIM_RETURN_DURATION)
		_drop_grenade_at_feet()
		return

	# Check for RMB press to enter WaitingForGRelease state
	if Input.is_action_just_pressed("grenade_throw"):
		_grenade_state = GrenadeState.WAITING_FOR_G_RELEASE
		_is_preparing_grenade = true
		# Start hands approach animation
		_start_grenade_anim_phase(GrenadeAnimPhase.HANDS_APPROACH, ANIM_APPROACH_DURATION)
		FileLogger.info("[Player.Grenade] Step 2 part 1: G+RMB held - now release G to ready the throw")


## Handle WAITING_FOR_G_RELEASE state: G+RMB both held, waiting for G release (Step 2 part 2).
func _handle_grenade_waiting_for_g_release_state() -> void:
	# If RMB is released before G, go back to TimerStarted
	if not Input.is_action_pressed("grenade_throw"):
		_grenade_state = GrenadeState.TIMER_STARTED
		_is_preparing_grenade = false
		# Go back to left arm extended position
		_start_grenade_anim_phase(GrenadeAnimPhase.PULL_PIN, ANIM_PIN_DURATION)
		FileLogger.info("[Player.Grenade] RMB released before G - back to waiting for RMB")
		return

	# If G is released while RMB is still held, enter Aiming state
	if not Input.is_action_pressed("grenade_prepare"):
		_grenade_state = GrenadeState.AIMING
		_aim_drag_start = get_global_mouse_position()
		_prev_mouse_pos = _aim_drag_start
		# Start transfer animation, then wind-up
		_start_grenade_anim_phase(GrenadeAnimPhase.TRANSFER, ANIM_TRANSFER_DURATION)
		FileLogger.info("[Player.Grenade] Step 2 complete: G released, RMB held - now aiming, drag and release RMB to throw")


## Handle AIMING state: only RMB held (G released), drag to aim and release to throw.
func _handle_grenade_aiming_state() -> void:
	# In this state, G is already released (that's how we got here)
	# We only care about RMB

	# Update wind-up intensity based on mouse drag during aiming
	_update_wind_up_intensity()

	# Request redraw for debug trajectory visualization
	if _debug_mode_enabled:
		queue_redraw()

	# If transfer animation is done, switch to wind-up
	if _grenade_anim_phase == GrenadeAnimPhase.TRANSFER and _grenade_anim_timer <= 0:
		_grenade_anim_phase = GrenadeAnimPhase.WIND_UP

	# Check for RMB release (complete step 3 - throw!)
	if Input.is_action_just_released("grenade_throw"):
		var drag_end := get_global_mouse_position()
		# Start throw animation
		_start_grenade_anim_phase(GrenadeAnimPhase.THROW, ANIM_THROW_DURATION)
		_throw_grenade(drag_end)
		FileLogger.info("[Player.Grenade] Step 3 complete: Grenade thrown!")


## Start the grenade timer (step 1 complete - pin pulled).
## Creates the grenade instance and starts its 4-second fuse.
func _start_grenade_timer() -> void:
	if _current_grenades <= 0:
		FileLogger.info("[Player.Grenade] Cannot start timer: no grenades")
		return

	if grenade_scene == null:
		FileLogger.info("[Player.Grenade] Cannot start timer: grenade_scene is null")
		return

	# Create grenade instance (held by player)
	_active_grenade = grenade_scene.instantiate()
	if _active_grenade == null:
		FileLogger.info("[Player.Grenade] Failed to instantiate grenade scene")
		return

	# Add grenade to scene first (must be in tree before setting global_position)
	get_tree().current_scene.add_child(_active_grenade)

	# Set position AFTER add_child (global_position only works when node is in the scene tree)
	_active_grenade.global_position = global_position

	# Activate the grenade timer (starts 4s countdown)
	if _active_grenade.has_method("activate_timer"):
		_active_grenade.activate_timer()

	# Update state
	_grenade_state = GrenadeState.TIMER_STARTED
	_grenade_timer_start_time = Time.get_ticks_msec() / 1000.0

	# Decrement grenade count now (pin is pulled) - but not on tutorial level (infinite)
	if not _is_tutorial_level:
		_current_grenades -= 1
	grenade_changed.emit(_current_grenades, max_grenades)

	# Play pin pull sound
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_grenade_prepare"):
		audio_manager.play_grenade_prepare(global_position)

	FileLogger.info("[Player.Grenade] Timer started, grenade created at %s" % str(global_position))


## Drop the grenade at player's feet (when G is released before throwing).
func _drop_grenade_at_feet() -> void:
	if _active_grenade != null and is_instance_valid(_active_grenade):
		# Set position to current player position before unfreezing
		_active_grenade.global_position = global_position
		# Unfreeze the grenade so physics works and it can explode
		_active_grenade.freeze = false
		# Grenade stays where it is (at player's last position)
		# It will explode when timer runs out
		FileLogger.info("[Player.Grenade] Grenade dropped at feet at %s (unfrozen)" % str(_active_grenade.global_position))
	_reset_grenade_state()


## Reset grenade state to idle.
func _reset_grenade_state() -> void:
	_grenade_state = GrenadeState.IDLE
	_is_preparing_grenade = false
	_grenade_drag_active = false
	_grenade_drag_start = Vector2.ZERO
	_aim_drag_start = Vector2.ZERO
	_active_grenade = null
	_wind_up_intensity = 0.0
	# Animation will transition via RETURN_IDLE phase (set by caller if needed)
	FileLogger.info("[Player.Grenade] State reset to IDLE")


## Throw the grenade based on aiming drag direction and distance.
## Includes player rotation animation to prevent grenade hitting player.
## @param drag_end: The position where the mouse drag ended.
func _throw_grenade(drag_end: Vector2) -> void:
	if _active_grenade == null or not is_instance_valid(_active_grenade):
		FileLogger.info("[Player.Grenade] Cannot throw: no active grenade")
		_reset_grenade_state()
		return

	# Calculate throw direction and distance from aiming drag
	var drag_vector := drag_end - _aim_drag_start
	var drag_distance := drag_vector.length()

	# If drag is too short (dropped at feet), use minimum throw
	var min_drag_distance := 10.0
	if drag_distance < min_drag_distance:
		drag_distance = min_drag_distance
		drag_vector = Vector2(1, 0)  # Default direction if no drag

	var throw_direction := drag_vector.normalized()

	# Increase throw sensitivity significantly - multiply drag distance by 9x
	# (3x for sensitivity * 3x for user-requested range increase)
	var sensitivity_multiplier := 9.0
	var adjusted_drag_distance := drag_distance * sensitivity_multiplier

	# Clamp max drag distance to viewport length * 3 (user requested 3x farther)
	var viewport := get_viewport()
	var max_drag_distance := 3840.0  # Default 1280 * 3
	if viewport:
		max_drag_distance = viewport.get_visible_rect().size.x * 3.0
	adjusted_drag_distance = minf(adjusted_drag_distance, max_drag_distance)

	FileLogger.info("[Player.Grenade] Throwing! Direction: %s, Drag: %.1f (adjusted: %.1f)" % [str(throw_direction), drag_distance, adjusted_drag_distance])

	# Rotate player to face throw direction (prevents grenade hitting player when throwing upward)
	_rotate_player_for_throw(throw_direction)

	# IMPORTANT: Set grenade position to player's CURRENT position (not where it was activated)
	# Offset grenade spawn position in throw direction to avoid collision with player
	var spawn_offset := 60.0  # Increased from 30 to 60 pixels in front of player to avoid hitting
	var spawn_position := global_position + throw_direction * spawn_offset
	_active_grenade.global_position = spawn_position

	# Set the throw velocity with adjusted distance
	if _active_grenade.has_method("throw_grenade"):
		_active_grenade.throw_grenade(throw_direction, adjusted_drag_distance)

	# Emit signal
	grenade_thrown.emit()

	# Play throw sound
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_grenade_throw"):
		audio_manager.play_grenade_throw(global_position)

	FileLogger.info("[Player.Grenade] Thrown! Direction: %s, Distance: %.1f" % [str(throw_direction), adjusted_drag_distance])

	# Reset state (grenade is now independent)
	_reset_grenade_state()


## Rotate player to face throw direction (with swing animation).
## Prevents grenade from hitting player when throwing upward.
## @param throw_direction: The direction of the throw.
func _rotate_player_for_throw(throw_direction: Vector2) -> void:
	# Store current rotation to restore later
	_player_rotation_before_throw = rotation

	# Calculate target rotation (face throw direction)
	_throw_target_rotation = throw_direction.angle()

	# Apply rotation immediately
	rotation = _throw_target_rotation

	# Start restore timer
	_is_throw_rotating = true
	_throw_rotation_restore_timer = THROW_ROTATION_DURATION

	FileLogger.info("[Player.Grenade] Player rotated for throw: %.2f -> %.2f" % [_player_rotation_before_throw, _throw_target_rotation])


## Handle throw rotation animation - restore player rotation after throw.
## @param delta: Time since last frame.
func _handle_throw_rotation_animation(delta: float) -> void:
	if not _is_throw_rotating:
		return

	_throw_rotation_restore_timer -= delta
	if _throw_rotation_restore_timer <= 0:
		# Restore original rotation
		rotation = _player_rotation_before_throw
		_is_throw_rotating = false
		FileLogger.info("[Player.Grenade] Player rotation restored to %.2f" % _player_rotation_before_throw)


## Get current grenade count.
func get_current_grenades() -> int:
	return _current_grenades


## Get maximum grenade count.
func get_max_grenades() -> int:
	return max_grenades


## Add grenades to inventory (e.g., from pickup).
func add_grenades(count: int) -> void:
	_current_grenades = mini(_current_grenades + count, max_grenades)
	grenade_changed.emit(_current_grenades, max_grenades)


## Check if player is preparing to throw a grenade.
func is_preparing_grenade() -> bool:
	return _is_preparing_grenade


# ============================================================================
# Grenade Animation Functions
# ============================================================================

## Start a new grenade animation phase.
## @param phase: The GrenadeAnimPhase to transition to.
## @param duration: How long this phase should last (for timed phases).
func _start_grenade_anim_phase(phase: int, duration: float) -> void:
	_grenade_anim_phase = phase
	_grenade_anim_timer = duration
	_grenade_anim_duration = duration

	# Enable weapon sling when handling grenade
	if phase != GrenadeAnimPhase.NONE and phase != GrenadeAnimPhase.RETURN_IDLE:
		_weapon_slung = true
	elif phase == GrenadeAnimPhase.RETURN_IDLE:
		# Will be unset when return animation completes
		pass

	FileLogger.info("[Player.Grenade.Anim] Phase changed to: %s (duration: %.2fs)" % [
		GrenadeAnimPhase.keys()[phase], duration
	])


## Update grenade animation based on current phase.
## Called every frame from _physics_process.
## @param delta: Time since last frame.
func _update_grenade_animation(delta: float) -> void:
	# Early exit if no animation active
	if _grenade_anim_phase == GrenadeAnimPhase.NONE:
		return

	# Update phase timer
	if _grenade_anim_timer > 0:
		_grenade_anim_timer -= delta

	# Calculate animation progress (0.0 to 1.0)
	var progress := 1.0
	if _grenade_anim_duration > 0:
		progress = clampf(1.0 - (_grenade_anim_timer / _grenade_anim_duration), 0.0, 1.0)

	# Calculate target positions based on current phase
	var left_arm_target := _base_left_arm_pos
	var right_arm_target := _base_right_arm_pos
	var left_arm_rot := 0.0
	var right_arm_rot := 0.0
	var lerp_speed := ANIM_LERP_SPEED * delta

	match _grenade_anim_phase:
		GrenadeAnimPhase.GRAB_GRENADE:
			# Left arm moves back to shoulder/chest area (away from weapon) to grab grenade
			# Large negative X offset pulls the arm from weapon front toward body
			left_arm_target = _base_left_arm_pos + ARM_LEFT_CHEST
			left_arm_rot = deg_to_rad(ARM_ROT_GRAB)
			lerp_speed = ANIM_LERP_SPEED_FAST * delta

		GrenadeAnimPhase.PULL_PIN:
			# Left hand holds grenade at chest level, right hand pulls pin
			left_arm_target = _base_left_arm_pos + ARM_LEFT_EXTENDED
			left_arm_rot = deg_to_rad(ARM_ROT_LEFT_AT_CHEST)
			right_arm_target = _base_right_arm_pos + ARM_RIGHT_PIN
			right_arm_rot = deg_to_rad(ARM_ROT_PIN_PULL)
			lerp_speed = ANIM_LERP_SPEED_FAST * delta

		GrenadeAnimPhase.HANDS_APPROACH:
			# Both hands at chest level, preparing for transfer
			left_arm_target = _base_left_arm_pos + ARM_LEFT_EXTENDED
			left_arm_rot = deg_to_rad(ARM_ROT_LEFT_AT_CHEST)
			right_arm_target = _base_right_arm_pos + ARM_RIGHT_APPROACH

		GrenadeAnimPhase.TRANSFER:
			# Left arm drops back toward body, right hand takes grenade
			left_arm_target = _base_left_arm_pos + ARM_LEFT_TRANSFER
			left_arm_rot = deg_to_rad(ARM_ROT_LEFT_RELAXED * 0.5)
			right_arm_target = _base_right_arm_pos + ARM_RIGHT_HOLD
			lerp_speed = ANIM_LERP_SPEED * delta

		GrenadeAnimPhase.WIND_UP:
			# LEFT ARM: Fully retracted to shoulder/body area, hangs at side
			# This is the key position - arm must be clearly NOT on the weapon
			left_arm_target = _base_left_arm_pos + ARM_LEFT_RELAXED
			left_arm_rot = deg_to_rad(ARM_ROT_LEFT_RELAXED)
			# RIGHT ARM: Interpolate between min and max wind-up based on intensity
			var wind_up_offset := ARM_RIGHT_WIND_MIN.lerp(ARM_RIGHT_WIND_MAX, _wind_up_intensity)
			right_arm_target = _base_right_arm_pos + wind_up_offset
			var wind_up_rot := lerpf(ARM_ROT_WIND_MIN, ARM_ROT_WIND_MAX, _wind_up_intensity)
			right_arm_rot = deg_to_rad(wind_up_rot)
			lerp_speed = ANIM_LERP_SPEED_FAST * delta  # Responsive to input

		GrenadeAnimPhase.THROW:
			# Throwing motion - right arm swings forward, left stays at body
			left_arm_target = _base_left_arm_pos + ARM_LEFT_RELAXED
			left_arm_rot = deg_to_rad(ARM_ROT_LEFT_RELAXED)
			right_arm_target = _base_right_arm_pos + ARM_RIGHT_THROW
			right_arm_rot = deg_to_rad(ARM_ROT_THROW)
			lerp_speed = ANIM_LERP_SPEED_FAST * delta

			# When throw animation completes, transition to return
			if _grenade_anim_timer <= 0:
				_start_grenade_anim_phase(GrenadeAnimPhase.RETURN_IDLE, ANIM_RETURN_DURATION)

		GrenadeAnimPhase.RETURN_IDLE:
			# Arms returning to base positions (back to holding weapon)
			left_arm_target = _base_left_arm_pos
			right_arm_target = _base_right_arm_pos
			lerp_speed = ANIM_LERP_SPEED * delta

			# When return animation completes, end animation
			if _grenade_anim_timer <= 0:
				_grenade_anim_phase = GrenadeAnimPhase.NONE
				_weapon_slung = false
				FileLogger.info("[Player.Grenade.Anim] Animation complete, returning to normal")

	# Apply arm positions with smooth interpolation
	if _left_arm_sprite:
		_left_arm_sprite.position = _left_arm_sprite.position.lerp(left_arm_target, lerp_speed)
		_left_arm_sprite.rotation = lerpf(_left_arm_sprite.rotation, left_arm_rot, lerp_speed)

	if _right_arm_sprite:
		_right_arm_sprite.position = _right_arm_sprite.position.lerp(right_arm_target, lerp_speed)
		_right_arm_sprite.rotation = lerpf(_right_arm_sprite.rotation, right_arm_rot, lerp_speed)

	# Update weapon sling animation
	_update_weapon_sling(delta)


## Update weapon sling position (lower weapon when handling grenade).
## @param delta: Time since last frame.
func _update_weapon_sling(delta: float) -> void:
	if not _weapon_mount:
		return

	var target_pos := _base_weapon_mount_pos
	var target_rot := _base_weapon_mount_rot

	if _weapon_slung:
		# Lower weapon to chest/sling position
		target_pos = _base_weapon_mount_pos + WEAPON_SLING_OFFSET
		target_rot = _base_weapon_mount_rot + WEAPON_SLING_ROTATION

	var lerp_speed := ANIM_LERP_SPEED * delta
	_weapon_mount.position = _weapon_mount.position.lerp(target_pos, lerp_speed)
	_weapon_mount.rotation = lerpf(_weapon_mount.rotation, target_rot, lerp_speed)


## Update wind-up intensity based on mouse drag distance during aiming.
func _update_wind_up_intensity() -> void:
	var current_mouse := get_global_mouse_position()

	# Calculate drag distance from aim start
	var drag_vector := current_mouse - _aim_drag_start
	var drag_distance := drag_vector.length()

	# Get viewport for max drag calculation
	var viewport := get_viewport()
	var max_drag := 600.0  # Default max drag distance
	if viewport:
		max_drag = viewport.get_visible_rect().size.x * 0.5

	# Calculate base intensity from distance
	var intensity := clampf(drag_distance / max_drag, 0.0, 1.0)

	# Add velocity component for more responsive feel
	var mouse_delta := current_mouse - _prev_mouse_pos
	var mouse_velocity := mouse_delta.length()
	var velocity_bonus := clampf(mouse_velocity / 50.0, 0.0, 0.2)

	_wind_up_intensity = clampf(intensity + velocity_bonus, 0.0, 1.0)
	_prev_mouse_pos = current_mouse


# ============================================================================
# Reload Animation Functions
# ============================================================================

## Start a new reload animation phase.
## @param phase: The ReloadAnimPhase to transition to.
## @param duration: How long this phase should last.
func _start_reload_anim_phase(phase: int, duration: float) -> void:
	_reload_anim_phase = phase
	_reload_anim_timer = duration
	_reload_anim_duration = duration
	FileLogger.info("[Player.Reload.Anim] Phase changed to: %s (duration: %.2fs)" % [
		ReloadAnimPhase.keys()[phase], duration
	])


## Update reload animation based on current phase.
## Called every frame from _physics_process.
## Implements three steps as requested:
## 1. Left hand grabs magazine from chest
## 2. Left hand inserts magazine into rifle
## 3. Pull the bolt/charging handle
## @param delta: Time since last frame.
func _update_reload_animation(delta: float) -> void:
	# Early exit if no animation active
	if _reload_anim_phase == ReloadAnimPhase.NONE:
		return

	# Update phase timer
	if _reload_anim_timer > 0:
		_reload_anim_timer -= delta

	# Calculate animation progress (0.0 to 1.0)
	var progress := 1.0
	if _reload_anim_duration > 0:
		progress = clampf(1.0 - (_reload_anim_timer / _reload_anim_duration), 0.0, 1.0)

	# Calculate target positions based on current phase
	var left_arm_target := _base_left_arm_pos
	var right_arm_target := _base_right_arm_pos
	var left_arm_rot := 0.0
	var right_arm_rot := 0.0
	var lerp_speed := ANIM_LERP_SPEED * delta

	match _reload_anim_phase:
		ReloadAnimPhase.GRAB_MAGAZINE:
			# Step 1: Left hand moves to chest/vest to grab magazine
			# Left arm moves back toward body (chest area where mag pouches are)
			left_arm_target = _base_left_arm_pos + RELOAD_ARM_LEFT_GRAB
			left_arm_rot = deg_to_rad(RELOAD_ARM_ROT_LEFT_GRAB)
			# Right hand stays on weapon grip, steadying the rifle
			right_arm_target = _base_right_arm_pos + RELOAD_ARM_RIGHT_HOLD
			right_arm_rot = deg_to_rad(RELOAD_ARM_ROT_RIGHT_HOLD)
			lerp_speed = ANIM_LERP_SPEED_FAST * delta

		ReloadAnimPhase.INSERT_MAGAZINE:
			# Step 2: Left hand moves forward to weapon magwell, inserts magazine
			left_arm_target = _base_left_arm_pos + RELOAD_ARM_LEFT_INSERT
			left_arm_rot = deg_to_rad(RELOAD_ARM_ROT_LEFT_INSERT)
			# Right hand steadies the weapon slightly
			right_arm_target = _base_right_arm_pos + RELOAD_ARM_RIGHT_STEADY
			right_arm_rot = deg_to_rad(RELOAD_ARM_ROT_RIGHT_STEADY)
			lerp_speed = ANIM_LERP_SPEED * delta

		ReloadAnimPhase.PULL_BOLT:
			# Step 3: Pull bolt/charging handle
			# Left hand moves to foregrip to support weapon
			left_arm_target = _base_left_arm_pos + RELOAD_ARM_LEFT_SUPPORT
			left_arm_rot = deg_to_rad(RELOAD_ARM_ROT_LEFT_SUPPORT)
			# Right hand pulls charging handle back
			right_arm_target = _base_right_arm_pos + RELOAD_ARM_RIGHT_BOLT
			right_arm_rot = deg_to_rad(RELOAD_ARM_ROT_RIGHT_BOLT)
			lerp_speed = ANIM_LERP_SPEED_FAST * delta

			# When bolt pull animation completes, transition to return idle
			if _reload_anim_timer <= 0:
				_start_reload_anim_phase(ReloadAnimPhase.RETURN_IDLE, RELOAD_ANIM_RETURN_DURATION)

		ReloadAnimPhase.RETURN_IDLE:
			# Arms returning to normal weapon-holding positions
			left_arm_target = _base_left_arm_pos
			right_arm_target = _base_right_arm_pos
			lerp_speed = ANIM_LERP_SPEED * delta

			# When return animation completes, end animation
			if _reload_anim_timer <= 0:
				_reload_anim_phase = ReloadAnimPhase.NONE
				FileLogger.info("[Player.Reload.Anim] Reload animation complete, returning to normal")

	# Apply arm positions with smooth interpolation
	if _left_arm_sprite:
		_left_arm_sprite.position = _left_arm_sprite.position.lerp(left_arm_target, lerp_speed)
		_left_arm_sprite.rotation = lerpf(_left_arm_sprite.rotation, left_arm_rot, lerp_speed)

	if _right_arm_sprite:
		_right_arm_sprite.position = _right_arm_sprite.position.lerp(right_arm_target, lerp_speed)
		_right_arm_sprite.rotation = lerpf(_right_arm_sprite.rotation, right_arm_rot, lerp_speed)


# ============================================================================
# Debug Visualization System
# ============================================================================

## Connect to GameManager's debug mode signal for F7 toggle.
func _connect_debug_mode_signal() -> void:
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager:
		# Connect to debug mode toggle signal
		if game_manager.has_signal("debug_mode_toggled"):
			game_manager.debug_mode_toggled.connect(_on_debug_mode_toggled)
		# Sync with current debug mode state
		if game_manager.has_method("is_debug_mode_enabled"):
			_debug_mode_enabled = game_manager.is_debug_mode_enabled()


## Called when debug mode is toggled via F7 key.
func _on_debug_mode_toggled(enabled: bool) -> void:
	_debug_mode_enabled = enabled
	queue_redraw()


## Draw debug visualization for grenade throw trajectory.
## Shows the throw direction line and predicted landing position during aiming.
func _draw() -> void:
	if not _debug_mode_enabled:
		return

	# Only draw during grenade aiming state
	if _grenade_state != GrenadeState.AIMING:
		return

	# Colors for debug visualization
	var color_trajectory := Color.YELLOW  # Trajectory line
	var color_landing := Color.ORANGE  # Landing position
	var color_radius := Color(1.0, 0.5, 0.0, 0.3)  # Effect radius (semi-transparent orange)

	# Calculate throw parameters based on current drag
	var current_mouse := get_global_mouse_position()
	var drag_vector := current_mouse - _aim_drag_start
	var drag_distance := drag_vector.length()

	# Minimum drag distance for valid throw
	var min_drag_distance := 10.0
	if drag_distance < min_drag_distance:
		drag_distance = min_drag_distance
		drag_vector = Vector2(1, 0)

	var throw_direction := drag_vector.normalized()

	# Apply same sensitivity multiplier as in _throw_grenade
	var sensitivity_multiplier := 9.0
	var adjusted_drag_distance := drag_distance * sensitivity_multiplier

	# Clamp to max drag distance (3x viewport width)
	var viewport := get_viewport()
	var max_drag_distance := 3840.0
	if viewport:
		max_drag_distance = viewport.get_visible_rect().size.x * 3.0
	adjusted_drag_distance = minf(adjusted_drag_distance, max_drag_distance)

	# Calculate throw speed using grenade parameters
	# From grenade_base.gd: drag_to_speed_multiplier = 2.0, max_throw_speed = 2500, min_throw_speed = 100
	var drag_to_speed_multiplier := 2.0
	var max_throw_speed := 2500.0
	var min_throw_speed := 100.0
	var throw_speed := clampf(
		adjusted_drag_distance * drag_to_speed_multiplier,
		min_throw_speed,
		max_throw_speed
	)

	# Calculate landing distance using physics
	# From grenade_base.gd: ground_friction = 150.0
	# The grenade decelerates at ground_friction per second
	# Distance = v^2 / (2 * friction) (kinematic formula for constant deceleration)
	var ground_friction := 150.0
	var landing_distance := (throw_speed * throw_speed) / (2.0 * ground_friction)

	# Spawn offset (same as in _throw_grenade)
	var spawn_offset := 60.0

	# Calculate positions relative to player (for drawing in local coordinates)
	# Note: _draw() uses local coordinates, so we draw relative to Vector2.ZERO (player position)
	var spawn_pos := throw_direction * spawn_offset
	var landing_pos := spawn_pos + throw_direction * landing_distance

	# Draw trajectory line from spawn point to landing
	draw_line(spawn_pos, landing_pos, color_trajectory, 2.0)

	# Draw intermediate points along trajectory for better visualization
	var num_points := 8
	for i in range(1, num_points):
		var t := float(i) / float(num_points)
		var point := spawn_pos + throw_direction * landing_distance * t
		draw_circle(point, 3.0, color_trajectory)

	# Draw landing position marker (cross)
	var cross_size := 12.0
	draw_line(landing_pos + Vector2(-cross_size, 0), landing_pos + Vector2(cross_size, 0), color_landing, 3.0)
	draw_line(landing_pos + Vector2(0, -cross_size), landing_pos + Vector2(0, cross_size), color_landing, 3.0)

	# Draw effect radius at landing position
	# Default grenade effect radius from grenade_base.gd is 200.0 pixels
	var effect_radius := 200.0
	_draw_circle_outline(landing_pos, effect_radius, color_radius, 2.0)

	# Draw small circle at spawn point
	draw_circle(spawn_pos, 5.0, color_trajectory)


## Draw a circle outline (not filled) at the specified position.
## @param center: Center position of the circle.
## @param radius: Radius of the circle.
## @param color: Color of the outline.
## @param width: Line width.
func _draw_circle_outline(center: Vector2, radius: float, color: Color, width: float) -> void:
	var num_segments := 32
	var angle_step := TAU / num_segments
	var prev_point := center + Vector2(radius, 0)

	for i in range(1, num_segments + 1):
		var angle := angle_step * i
		var next_point := center + Vector2(cos(angle), sin(angle)) * radius
		draw_line(prev_point, next_point, color, width)
		prev_point = next_point
