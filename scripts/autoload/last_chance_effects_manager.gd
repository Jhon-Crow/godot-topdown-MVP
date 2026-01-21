extends Node
## LastChanceEffectsManager - Special "last chance" effect for hard difficulty.
##
## This autoload singleton manages the special time-freeze effect that triggers
## on hard difficulty when the player is about to die (1 HP or less) and an
## enemy bullet on a collision course enters their threat sphere.
##
## Effect details (as per issue #167):
## 1. Time completely stops for 6 real seconds
## 2. Player can move at normal speed and shoot during the freeze
## 3. Player-fired bullets stay frozen in place until time unfreezes
## 4. All colors except the player are dimmed
## 5. Blue sepia effect overlay with a ripple effect
## 6. This effect triggers ONLY ONCE per life

## Duration of the time freeze in real seconds.
const FREEZE_DURATION_REAL_SECONDS: float = 6.0

## Blue sepia intensity for the shader (0.0-1.0).
const SEPIA_INTENSITY: float = 0.7

## Brightness reduction for non-player elements (0.0-1.0, where 1.0 is normal).
const BRIGHTNESS: float = 0.6

## Ripple effect strength.
const RIPPLE_STRENGTH: float = 0.008

## Ripple effect frequency.
const RIPPLE_FREQUENCY: float = 25.0

## Ripple effect speed.
const RIPPLE_SPEED: float = 2.0

## The CanvasLayer for screen effects.
var _effects_layer: CanvasLayer = null

## The ColorRect with the last chance shader.
var _effect_rect: ColorRect = null

## Whether the last chance effect is currently active.
var _is_effect_active: bool = false

## Whether the last chance effect has already been used this life.
## Only triggers ONCE.
var _effect_used: bool = false

## Reference to the player for monitoring.
var _player: Node = null

## Reference to the player's ThreatSphere for signal connection.
var _threat_sphere: Area2D = null

## Whether we've successfully connected to player signals.
var _connected_to_player: bool = false

## Timer for tracking effect duration (uses real time, not game time).
var _effect_start_time: float = 0.0

## Tracks the previous scene root to detect scene changes.
var _previous_scene_root: Node = null

## List of bullets frozen by the player during time freeze.
var _frozen_player_bullets: Array = []

## Original process mode of the player (to restore after effect).
var _player_original_process_mode: Node.ProcessMode = Node.PROCESS_MODE_INHERIT


func _ready() -> void:
	# Connect to scene tree changes to find player and reset effects on scene reload
	get_tree().tree_changed.connect(_on_tree_changed)

	# Create effects layer (very high layer to render on top of everything)
	_effects_layer = CanvasLayer.new()
	_effects_layer.name = "LastChanceEffectsLayer"
	_effects_layer.layer = 102  # Higher than other effects layers
	add_child(_effects_layer)

	# Create effect overlay
	_effect_rect = ColorRect.new()
	_effect_rect.name = "LastChanceOverlay"
	_effect_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_effect_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Load and apply the last chance shader
	var shader := load("res://scripts/shaders/last_chance.gdshader") as Shader
	if shader:
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("sepia_intensity", 0.0)
		material.set_shader_parameter("brightness", 1.0)
		material.set_shader_parameter("ripple_strength", 0.0)
		material.set_shader_parameter("ripple_frequency", RIPPLE_FREQUENCY)
		material.set_shader_parameter("ripple_speed", RIPPLE_SPEED)
		material.set_shader_parameter("time_offset", 0.0)
		_effect_rect.material = material
		_log("Last chance shader loaded successfully")
	else:
		push_warning("LastChanceEffectsManager: Could not load last chance shader")
		_log("WARNING: Could not load last chance shader!")

	_effect_rect.visible = false
	_effects_layer.add_child(_effect_rect)

	_log("LastChanceEffectsManager ready - Configuration:")
	_log("  Freeze duration: %.1f real seconds" % FREEZE_DURATION_REAL_SECONDS)
	_log("  Sepia intensity: %.2f" % SEPIA_INTENSITY)
	_log("  Brightness: %.2f" % BRIGHTNESS)


func _process(delta: float) -> void:
	# Check if we need to find the player
	if _player == null or not is_instance_valid(_player):
		_find_player()

	# Update shader time for ripple animation (using real time)
	if _is_effect_active:
		var current_time := Time.get_ticks_msec() / 1000.0
		var elapsed := current_time - _effect_start_time

		# Update ripple time offset in shader
		var material := _effect_rect.material as ShaderMaterial
		if material:
			material.set_shader_parameter("time_offset", elapsed)

		# Check if effect should end based on real time duration
		if elapsed >= FREEZE_DURATION_REAL_SECONDS:
			_log("Effect duration expired after %.2f real seconds" % elapsed)
			_end_last_chance_effect()


## Log a message with the LastChance prefix.
func _log(message: String) -> void:
	var logger: Node = get_node_or_null("/root/FileLogger")
	if logger and logger.has_method("log_info"):
		logger.log_info("[LastChance] " + message)
	else:
		print("[LastChance] " + message)


## Find and connect to the player and their threat sphere.
func _find_player() -> void:
	# Skip if already connected
	if _connected_to_player and is_instance_valid(_player):
		return

	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		return

	_log("Found player: %s" % _player.name)

	# Find threat sphere on player
	_threat_sphere = _player.get_node_or_null("ThreatSphere") as Area2D
	if _threat_sphere == null:
		_log("WARNING: No ThreatSphere found on player - last chance effect won't work")
		return

	# Connect to threat sphere signal
	if _threat_sphere.has_signal("threat_detected"):
		if not _threat_sphere.threat_detected.is_connected(_on_threat_detected):
			_threat_sphere.threat_detected.connect(_on_threat_detected)
			_log("Connected to ThreatSphere threat_detected signal")

	# Connect to player health signals to track when HP is low
	if _player.has_signal("Damaged"):
		if not _player.Damaged.is_connected(_on_player_damaged):
			_player.Damaged.connect(_on_player_damaged)
			_log("Connected to player Damaged signal (C#)")

	if _player.has_signal("health_changed"):
		if not _player.health_changed.is_connected(_on_player_health_changed):
			_player.health_changed.connect(_on_player_health_changed)
			_log("Connected to player health_changed signal (GDScript)")

	# Connect to died signal to reset effect availability on death
	if _player.has_signal("Died"):
		if not _player.Died.is_connected(_on_player_died):
			_player.Died.connect(_on_player_died)
			_log("Connected to player Died signal (C#)")

	if _player.has_signal("died"):
		if not _player.died.is_connected(_on_player_died):
			_player.died.connect(_on_player_died)
			_log("Connected to player died signal (GDScript)")

	_connected_to_player = true


## Called when player health changes (GDScript).
func _on_player_health_changed(_current: int, _maximum: int) -> void:
	# Health tracking is handled by _can_trigger_effect()
	pass


## Called when player takes damage (C#).
func _on_player_damaged(_amount: float, _current_health: float) -> void:
	# Health tracking is handled by _can_trigger_effect()
	pass


## Called when player dies.
func _on_player_died() -> void:
	_log("Player died")
	if _is_effect_active:
		_end_last_chance_effect()
	# Reset effect usage on death so it can trigger again next life
	_effect_used = false


## Called when a threat is detected by the player's threat sphere.
func _on_threat_detected(bullet: Area2D) -> void:
	_log("Threat detected: %s" % bullet.name)

	# Check if we can trigger the effect
	if not _can_trigger_effect():
		_log("Cannot trigger effect - conditions not met")
		return

	_log("Triggering last chance effect!")
	_start_last_chance_effect()


## Checks if the last chance effect can be triggered.
func _can_trigger_effect() -> bool:
	# Effect already used this life?
	if _effect_used:
		_log("Effect already used this life")
		return false

	# Effect already active?
	if _is_effect_active:
		_log("Effect already active")
		return false

	# Only trigger in hard mode
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager == null:
		_log("DifficultyManager not found")
		return false

	if not difficulty_manager.is_hard_mode():
		_log("Not in hard mode - effect disabled")
		return false

	# Check player health (1 HP or less)
	if _player == null:
		_log("Player not found")
		return false

	var current_health := _get_player_health()
	if current_health > 1.0 or current_health <= 0.0:
		_log("Player health is %.1f - effect requires exactly 1 HP or less but alive" % current_health)
		return false

	return true


## Gets the player's current health.
func _get_player_health() -> float:
	if _player == null:
		return 0.0

	# Try C# player (has HealthComponent)
	var health_component: Node = _player.get_node_or_null("HealthComponent")
	if health_component != null:
		if health_component.has_method("get") and health_component.get("CurrentHealth") != null:
			return health_component.get("CurrentHealth")
		if "CurrentHealth" in health_component:
			return health_component.CurrentHealth

	# Try GDScript player
	if _player.has_method("get_health"):
		return _player.get_health()

	# Try health property
	if "health" in _player:
		return _player.health

	# Try current_health property
	if "current_health" in _player:
		return _player.current_health

	return 0.0


## Starts the last chance effect.
func _start_last_chance_effect() -> void:
	if _is_effect_active:
		return

	_is_effect_active = true
	_effect_used = true  # Mark as used (only triggers once)
	_effect_start_time = Time.get_ticks_msec() / 1000.0

	_log("Starting last chance effect:")
	_log("  - Time will be frozen (except player)")
	_log("  - Duration: %.1f real seconds" % FREEZE_DURATION_REAL_SECONDS)
	_log("  - Sepia intensity: %.2f" % SEPIA_INTENSITY)
	_log("  - Brightness: %.2f" % BRIGHTNESS)

	# Freeze time for everything except the player
	_freeze_time()

	# Apply visual effects
	_apply_visual_effects()


## Freezes time for everything except the player.
func _freeze_time() -> void:
	# Store player's original process mode
	if _player != null:
		_player_original_process_mode = _player.process_mode

	# Set engine time scale to 0 (freeze everything)
	Engine.time_scale = 0.0

	# But allow the player to still process
	if _player != null:
		_player.process_mode = Node.PROCESS_MODE_ALWAYS
		_log("Player process_mode set to ALWAYS")

	# Also allow the camera to process
	var camera: Camera2D = _player.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.process_mode = Node.PROCESS_MODE_ALWAYS

	# Allow this manager to process (for timer and ripple animation)
	process_mode = Node.PROCESS_MODE_ALWAYS


## Applies the visual effects (blue sepia + ripple).
func _apply_visual_effects() -> void:
	_effect_rect.visible = true
	var material := _effect_rect.material as ShaderMaterial
	if material:
		material.set_shader_parameter("sepia_intensity", SEPIA_INTENSITY)
		material.set_shader_parameter("brightness", BRIGHTNESS)
		material.set_shader_parameter("ripple_strength", RIPPLE_STRENGTH)
		material.set_shader_parameter("time_offset", 0.0)
		_log("Applied visual effects: sepia=%.2f, brightness=%.2f, ripple=%.4f" % [SEPIA_INTENSITY, BRIGHTNESS, RIPPLE_STRENGTH])


## Ends the last chance effect.
func _end_last_chance_effect() -> void:
	if not _is_effect_active:
		return

	_is_effect_active = false
	_log("Ending last chance effect")

	# Restore normal time
	_unfreeze_time()

	# Remove visual effects
	_remove_visual_effects()


## Unfreezes time and restores normal processing.
func _unfreeze_time() -> void:
	# Restore engine time scale
	Engine.time_scale = 1.0

	# Restore player's original process mode
	if _player != null and is_instance_valid(_player):
		_player.process_mode = _player_original_process_mode
		_log("Player process_mode restored")

		# Restore camera process mode
		var camera: Camera2D = _player.get_node_or_null("Camera2D") as Camera2D
		if camera != null:
			camera.process_mode = Node.PROCESS_MODE_INHERIT

	# Restore this manager's process mode
	process_mode = Node.PROCESS_MODE_INHERIT

	# Unfreeze any player bullets that were fired during the time freeze
	_unfreeze_player_bullets()


## Removes the visual effects.
func _remove_visual_effects() -> void:
	_effect_rect.visible = false
	var material := _effect_rect.material as ShaderMaterial
	if material:
		material.set_shader_parameter("sepia_intensity", 0.0)
		material.set_shader_parameter("brightness", 1.0)
		material.set_shader_parameter("ripple_strength", 0.0)


## Registers a player bullet that was fired during time freeze.
## These bullets should stay frozen until time unfreezes.
func register_frozen_bullet(bullet: Node2D) -> void:
	if not _is_effect_active:
		return

	if bullet not in _frozen_player_bullets:
		_frozen_player_bullets.append(bullet)
		# Freeze the bullet's processing
		bullet.process_mode = Node.PROCESS_MODE_DISABLED
		_log("Registered frozen player bullet: %s" % bullet.name)


## Unfreezes all player bullets that were fired during time freeze.
func _unfreeze_player_bullets() -> void:
	for bullet in _frozen_player_bullets:
		if is_instance_valid(bullet):
			bullet.process_mode = Node.PROCESS_MODE_INHERIT
			_log("Unfroze player bullet: %s" % bullet.name)

	_frozen_player_bullets.clear()


## Resets all effects (useful when restarting the scene).
func reset_effects() -> void:
	_log("Resetting all effects (scene change detected)")
	if _is_effect_active:
		_end_last_chance_effect()
	_player = null
	_threat_sphere = null
	_connected_to_player = false
	_effect_used = false  # Reset on scene change
	_frozen_player_bullets.clear()


## Called when the scene tree structure changes.
## Used to reset effects when a new scene is loaded.
func _on_tree_changed() -> void:
	var current_scene := get_tree().current_scene
	if current_scene != null and current_scene != _previous_scene_root:
		_previous_scene_root = current_scene
		reset_effects()


## Returns whether the last chance effect is currently active.
func is_effect_active() -> bool:
	return _is_effect_active


## Returns whether the last chance effect has been used this life.
func is_effect_used() -> bool:
	return _effect_used
