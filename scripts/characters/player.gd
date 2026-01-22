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

## Current aim direction for player model rotation.
var _aim_direction: Vector2 = Vector2.RIGHT

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


func _ready() -> void:
	FileLogger.info("[Player] Initializing player...")

	# Preload bullet scene if not set in inspector
	if bullet_scene == null:
		bullet_scene = preload("res://scenes/projectiles/Bullet.tscn")
		FileLogger.info("[Player] Bullet scene preloaded")

	# Preload grenade scene if not set in inspector
	if grenade_scene == null:
		var grenade_path := "res://scenes/projectiles/FlashbangGrenade.tscn"
		if ResourceLoader.exists(grenade_path):
			grenade_scene = load(grenade_path)
			FileLogger.info("[Player] Grenade scene loaded from: %s" % grenade_path)
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

	FileLogger.info("[Player] Ready! Ammo: %d/%d, Grenades: %d/%d, Health: %d/%d" % [
		_current_ammo, max_ammo,
		_current_grenades, max_grenades,
		_current_health, max_health
	])


func _physics_process(delta: float) -> void:
	if not _is_alive:
		return

	var input_direction := _get_input_direction()

	if input_direction != Vector2.ZERO:
		# Apply acceleration towards the input direction
		velocity = velocity.move_toward(input_direction * max_speed, acceleration * delta)
	else:
		# Apply friction to slow down
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	move_and_slide()

	# Update player model rotation to face aim direction (mouse cursor)
	_update_aim_rotation()

	# Update spread reset timer
	_shot_timer += delta
	if _shot_timer >= SPREAD_RESET_TIME:
		_shot_count = 0

	# Update simple reload timer
	if _is_reloading_simple:
		_reload_timer += delta
		if _reload_timer >= reload_time:
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


## Update player model rotation to face the mouse cursor (aim direction).
## The model rotates to match weapon aim, giving a more realistic top-down appearance.
func _update_aim_rotation() -> void:
	if not _player_model:
		return

	# Get direction to mouse cursor
	var mouse_pos := get_global_mouse_position()
	var to_mouse := mouse_pos - global_position

	if to_mouse.length_squared() > 0.001:
		_aim_direction = to_mouse.normalized()
		# Rotate the player model to face the aim direction
		_player_model.rotation = _aim_direction.angle()


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
func _handle_simple_reload_input() -> void:
	# Don't start reload if already reloading or at max ammo
	if _is_reloading_simple or _current_ammo >= max_ammo:
		return

	if Input.is_action_just_pressed("reload"):
		_is_reloading_simple = true
		_reload_timer = 0.0
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
				# Play magazine in sound
				if audio_manager and audio_manager.has_method("play_reload_mag_in"):
					audio_manager.play_reload_mag_in(global_position)
				reload_sequence_progress.emit(2, 3)
			elif Input.is_action_just_pressed("reload"):
				# R pressed again - restart sequence with mag out sound
				_reload_sequence_step = 1
				if audio_manager and audio_manager.has_method("play_reload_mag_out"):
					audio_manager.play_reload_mag_out(global_position)
				reload_sequence_progress.emit(1, 3)
		2:
			# Waiting for final R press
			if Input.is_action_just_pressed("reload"):
				# Play bolt cycling sound and complete reload
				if audio_manager and audio_manager.has_method("play_m16_bolt"):
					audio_manager.play_m16_bolt(global_position)
				_complete_reload()
			elif Input.is_action_just_pressed("reload_step"):
				# Wrong key pressed, reset sequence
				_reload_sequence_step = 1
				if audio_manager and audio_manager.has_method("play_reload_mag_out"):
					audio_manager.play_reload_mag_out(global_position)
				reload_sequence_progress.emit(1, 3)


## Complete the reload - instantly refill ammo.
func _complete_reload() -> void:
	_current_ammo = max_ammo
	_reload_sequence_step = 0
	_is_reloading_sequence = false
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


## Sets the modulate color on all player sprite parts.
## @param color: The color to apply to all sprites.
func _set_all_sprites_modulate(color: Color) -> void:
	if _body_sprite:
		_body_sprite.modulate = color
	if _head_sprite:
		_head_sprite.modulate = color
	if _left_arm_sprite:
		_left_arm_sprite.modulate = color
	if _right_arm_sprite:
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
	# Visual feedback - make all sprites darker/transparent
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
				FileLogger.info("[Player.Grenade] Step 1 complete: Timer started! Drag right detected (%.1f pixels)" % drag_vector.x)
			else:
				FileLogger.info("[Player.Grenade] Step 1 cancelled: Drag was not to the right (x=%.1f)" % drag_vector.x)

			_grenade_drag_active = false
	else:
		_grenade_drag_active = false


## Handle TIMER_STARTED state: waiting for RMB press while G is held (Step 2 part 1).
func _handle_grenade_timer_started_state() -> void:
	# G must still be held to continue
	if not Input.is_action_pressed("grenade_prepare"):
		# G released - cancel and drop grenade
		FileLogger.info("[Player.Grenade] Cancelled: G released while timer running")
		_drop_grenade_at_feet()
		return

	# Check for RMB press to enter WaitingForGRelease state
	if Input.is_action_just_pressed("grenade_throw"):
		_grenade_state = GrenadeState.WAITING_FOR_G_RELEASE
		_is_preparing_grenade = true
		FileLogger.info("[Player.Grenade] Step 2 part 1: G+RMB held - now release G to ready the throw")


## Handle WAITING_FOR_G_RELEASE state: G+RMB both held, waiting for G release (Step 2 part 2).
func _handle_grenade_waiting_for_g_release_state() -> void:
	# If RMB is released before G, go back to TimerStarted
	if not Input.is_action_pressed("grenade_throw"):
		_grenade_state = GrenadeState.TIMER_STARTED
		_is_preparing_grenade = false
		FileLogger.info("[Player.Grenade] RMB released before G - back to waiting for RMB")
		return

	# If G is released while RMB is still held, enter Aiming state
	if not Input.is_action_pressed("grenade_prepare"):
		_grenade_state = GrenadeState.AIMING
		_aim_drag_start = get_global_mouse_position()
		FileLogger.info("[Player.Grenade] Step 2 complete: G released, RMB held - now aiming, drag and release RMB to throw")


## Handle AIMING state: only RMB held (G released), drag to aim and release to throw.
func _handle_grenade_aiming_state() -> void:
	# In this state, G is already released (that's how we got here)
	# We only care about RMB

	# Check for RMB release (complete step 3 - throw!)
	if Input.is_action_just_released("grenade_throw"):
		var drag_end := get_global_mouse_position()
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
