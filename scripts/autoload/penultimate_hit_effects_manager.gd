extends Node
## Autoload singleton for managing the "penultimate hit" effect.
##
## When the player is hit and has 1 HP or less remaining:
## - Game speed slows to 0.1 (10x slowdown - very dramatic!)
## - Screen saturation increases 3x (3 times more vivid colors)
## - Screen contrast increases 2x (2 times more contrast)
## - Enemy saturation increases 4x (4 times more vivid colors)
## - Effect lasts for 3 real seconds (independent of time_scale)
##
## This effect creates a dramatic "last chance" moment when the player
## is one hit away from death.

## The slowed down time scale during penultimate hit effect.
const PENULTIMATE_TIME_SCALE: float = 0.1

## Screen saturation multiplier (3x = boost of 2.0, since multiplier = 1.0 + boost).
const SCREEN_SATURATION_BOOST: float = 2.0

## Screen contrast multiplier (2x = boost of 1.0, since multiplier = 1.0 + boost).
const SCREEN_CONTRAST_BOOST: float = 1.0

## Enemy saturation multiplier (4x).
const ENEMY_SATURATION_MULTIPLIER: float = 4.0

## Player saturation multiplier (same as enemies for consistency).
const PLAYER_SATURATION_MULTIPLIER: float = 4.0

## Duration of the effect in real seconds (independent of time_scale).
const EFFECT_DURATION_REAL_SECONDS: float = 3.0

## The CanvasLayer for screen effects.
var _effects_layer: CanvasLayer = null

## The ColorRect with the saturation shader.
var _saturation_rect: ColorRect = null

## Whether the penultimate hit effect is currently active.
var _is_effect_active: bool = false

## Reference to the player for health monitoring.
var _player: Node = null

## Whether we've successfully connected to player signals.
var _connected_to_player: bool = false

## Cached list of enemies with their original modulate colors.
## Key: enemy instance, Value: original modulate Color
var _enemy_original_colors: Dictionary = {}

## Cached player sprites with their original modulate colors.
## Key: sprite instance, Value: original modulate Color
var _player_original_colors: Dictionary = {}

## Timer for tracking effect duration (uses real time, not game time).
var _effect_start_time: float = 0.0

## Tracks the previous scene root to detect scene changes.
var _previous_scene_root: Node = null


func _ready() -> void:
	# Connect to scene tree changes to find player and reset effects on scene reload
	get_tree().tree_changed.connect(_on_tree_changed)

	# Create effects layer (very high layer to render on top of everything)
	_effects_layer = CanvasLayer.new()
	_effects_layer.name = "PenultimateHitEffectsLayer"
	_effects_layer.layer = 101  # Higher than HitEffectsManager's layer 100
	add_child(_effects_layer)

	# Create saturation overlay
	_saturation_rect = ColorRect.new()
	_saturation_rect.name = "PenultimateSaturationOverlay"
	_saturation_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_saturation_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Load and apply the saturation shader
	var shader := load("res://scripts/shaders/saturation.gdshader") as Shader
	if shader:
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("saturation_boost", 0.0)
		material.set_shader_parameter("contrast_boost", 0.0)
		_saturation_rect.material = material
		_log("Saturation shader loaded successfully")
	else:
		push_warning("PenultimateHitEffectsManager: Could not load saturation shader")
		_log("WARNING: Could not load saturation shader!")

	_saturation_rect.visible = false
	_effects_layer.add_child(_saturation_rect)

	_log("PenultimateHitEffectsManager ready - Configuration:")
	_log("  Time scale: %.2f (%.0fx slowdown)" % [PENULTIMATE_TIME_SCALE, 1.0 / PENULTIMATE_TIME_SCALE])
	_log("  Saturation boost: %.1f (%.1fx)" % [SCREEN_SATURATION_BOOST, 1.0 + SCREEN_SATURATION_BOOST])
	_log("  Contrast boost: %.1f (%.1fx)" % [SCREEN_CONTRAST_BOOST, 1.0 + SCREEN_CONTRAST_BOOST])
	_log("  Effect duration: %.1f real seconds" % EFFECT_DURATION_REAL_SECONDS)


func _process(_delta: float) -> void:
	# Check if we need to find the player
	if _player == null:
		_find_player()

	# Check if effect should end based on real time duration
	if _is_effect_active:
		# Use OS.get_ticks_msec() for real time (not affected by time_scale)
		var current_time := Time.get_ticks_msec() / 1000.0
		var elapsed_real_time := current_time - _effect_start_time

		if elapsed_real_time >= EFFECT_DURATION_REAL_SECONDS:
			_log("Effect duration expired after %.2f real seconds" % elapsed_real_time)
			_end_penultimate_effect()


## Log a message with the PenultimateHit prefix.
func _log(message: String) -> void:
	var logger: Node = get_node_or_null("/root/FileLogger")
	if logger and logger.has_method("log_info"):
		logger.log_info("[PenultimateHit] " + message)
	else:
		print("[PenultimateHit] " + message)


## Find and connect to the player.
func _find_player() -> void:
	# Skip if already connected
	if _connected_to_player and is_instance_valid(_player):
		return

	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		# Try finding by class/script path
		var players := get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			_player = players[0]

	if not _player:
		return

	_log("Found player: %s (class: %s)" % [_player.name, _player.get_class()])

	var connected := false

	# Try to connect to GDScript player's health_changed signal (int, int)
	if _player.has_signal("health_changed"):
		if not _player.health_changed.is_connected(_on_player_health_changed):
			_player.health_changed.connect(_on_player_health_changed)
			_log("Connected to player health_changed signal (GDScript)")
			connected = true

	# Try to connect to C# player's Damaged signal (float amount, float currentHealth)
	# This signal is emitted by BaseCharacter when it takes damage, includes current health
	if _player.has_signal("Damaged"):
		if not _player.Damaged.is_connected(_on_player_damaged):
			_player.Damaged.connect(_on_player_damaged)
			_log("Connected to player Damaged signal (C#)")
			connected = true

	if not connected:
		_log("WARNING: Could not connect to any health signal!")
	else:
		_connected_to_player = true

	# Connect to died signal to end effect on death
	if _player.has_signal("died") and not _player.died.is_connected(_on_player_died):
		_player.died.connect(_on_player_died)
		_log("Connected to player died signal (GDScript)")
	elif _player.has_signal("Died") and not _player.Died.is_connected(_on_player_died):
		_player.Died.connect(_on_player_died)
		_log("Connected to player Died signal (C#)")


## Called when player health changes (GDScript player, int values).
func _on_player_health_changed(current: int, maximum: int) -> void:
	_log("Player health changed: %d/%d" % [current, maximum])
	_check_penultimate_state(float(current))


## Called when player takes damage (C# player, from BaseCharacter.Damaged signal).
## Signal signature: Damaged(float amount, float currentHealth)
func _on_player_damaged(amount: float, current_health: float) -> void:
	_log("Player damaged: %.1f damage, current health: %.1f" % [amount, current_health])
	_check_penultimate_state(current_health)


## Check if penultimate hit effect should be triggered or ended.
func _check_penultimate_state(current_health: float) -> void:
	if current_health <= 1.0 and current_health > 0.0:
		# On hard mode, the special "last chance" effect replaces this effect
		# So we skip the regular penultimate hit effect on hard difficulty
		var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
		if difficulty_manager != null and difficulty_manager.is_hard_mode():
			_log("Hard mode active - skipping regular penultimate hit effect (using last chance instead)")
			return

		# Player has 1 HP or less but is still alive - trigger penultimate hit effect
		if not _is_effect_active:
			_log("Triggering penultimate hit effect (HP: %.1f)" % current_health)
			_start_penultimate_effect()
		else:
			# Effect already active, just reset the timer to extend duration
			_effect_start_time = Time.get_ticks_msec() / 1000.0
			_log("Extending penultimate hit effect duration (HP: %.1f)" % current_health)
	# Note: We don't end the effect when health goes above 1 HP anymore
	# The effect will end after the duration expires or on player death


## Called when player dies.
func _on_player_died() -> void:
	_log("Player died - ending penultimate effect")
	# End effect when player dies
	if _is_effect_active:
		_end_penultimate_effect()


## Start the penultimate hit effect.
func _start_penultimate_effect() -> void:
	if _is_effect_active:
		return

	_is_effect_active = true
	_effect_start_time = Time.get_ticks_msec() / 1000.0

	_log("Starting penultimate hit effect:")
	_log("  - Time scale: %.2f" % PENULTIMATE_TIME_SCALE)
	_log("  - Saturation boost: %.2f (%.1fx)" % [SCREEN_SATURATION_BOOST, 1.0 + SCREEN_SATURATION_BOOST])
	_log("  - Contrast boost: %.2f (%.1fx)" % [SCREEN_CONTRAST_BOOST, 1.0 + SCREEN_CONTRAST_BOOST])
	_log("  - Duration: %.1f real seconds" % EFFECT_DURATION_REAL_SECONDS)

	# Slow down time to 0.25
	Engine.time_scale = PENULTIMATE_TIME_SCALE

	# Apply screen saturation (3x) and contrast (2x)
	_saturation_rect.visible = true
	var material := _saturation_rect.material as ShaderMaterial
	if material:
		material.set_shader_parameter("saturation_boost", SCREEN_SATURATION_BOOST)
		material.set_shader_parameter("contrast_boost", SCREEN_CONTRAST_BOOST)
		_log("Applied shader parameters: saturation=%.2f, contrast=%.2f" % [SCREEN_SATURATION_BOOST, SCREEN_CONTRAST_BOOST])
	else:
		_log("WARNING: No shader material found!")

	# Apply enemy saturation (4x)
	_apply_enemy_saturation()

	# Apply player saturation (4x) - makes player more visible
	_apply_player_saturation()


## End the penultimate hit effect.
func _end_penultimate_effect() -> void:
	if not _is_effect_active:
		return

	_is_effect_active = false
	_log("Ending penultimate hit effect")

	# Restore normal time
	Engine.time_scale = 1.0

	# Remove screen saturation and contrast
	_saturation_rect.visible = false
	var material := _saturation_rect.material as ShaderMaterial
	if material:
		material.set_shader_parameter("saturation_boost", 0.0)
		material.set_shader_parameter("contrast_boost", 0.0)

	# Restore enemy colors
	_restore_enemy_colors()

	# Restore player sprite colors
	_restore_player_colors()


## Apply 4x saturation to all enemies.
func _apply_enemy_saturation() -> void:
	_enemy_original_colors.clear()

	var enemies := get_tree().get_nodes_in_group("enemies")
	_log("Applying saturation to %d enemies" % enemies.size())

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		var sprite := enemy.get_node_or_null("Sprite2D") as Sprite2D
		if sprite:
			# Store original color
			_enemy_original_colors[enemy] = sprite.modulate

			# Apply 4x saturation to the sprite's modulate color
			sprite.modulate = _saturate_color(sprite.modulate, ENEMY_SATURATION_MULTIPLIER)


## Restore original colors to all enemies.
func _restore_enemy_colors() -> void:
	for enemy in _enemy_original_colors.keys():
		if not is_instance_valid(enemy):
			continue

		var sprite := enemy.get_node_or_null("Sprite2D") as Sprite2D
		if sprite:
			sprite.modulate = _enemy_original_colors[enemy]

	_enemy_original_colors.clear()


## Apply saturation boost to all player sprites (visibility during effect).
## This makes the entire player more vivid during the penultimate hit effect.
func _apply_player_saturation() -> void:
	if _player == null:
		return

	_player_original_colors.clear()

	# Find all player sprites in PlayerModel
	var player_model := _player.get_node_or_null("PlayerModel") as Node2D
	if player_model == null:
		_log("WARNING: PlayerModel not found on player")
		return

	# Apply saturation to all direct sprite children (Body, Head, LeftArm, RightArm)
	var sprites_saturated: int = 0
	for child in player_model.get_children():
		if child is Sprite2D:
			_player_original_colors[child] = child.modulate
			child.modulate = _saturate_color(child.modulate, PLAYER_SATURATION_MULTIPLIER)
			sprites_saturated += 1

	# Also apply saturation to armband (sibling of RightArm, not child - to avoid inheriting health modulate)
	var armband := player_model.get_node_or_null("Armband") as Sprite2D
	if armband:
		_player_original_colors[armband] = armband.modulate
		armband.modulate = _saturate_color(armband.modulate, PLAYER_SATURATION_MULTIPLIER)
		sprites_saturated += 1

	_log("Applied %.1fx saturation to %d player sprites" % [PLAYER_SATURATION_MULTIPLIER, sprites_saturated])


## Restore original colors to player's sprites.
## After restoring, tells the player to refresh their health visual to ensure
## the correct health-based coloring is applied (not the stale stored colors).
func _restore_player_colors() -> void:
	for sprite in _player_original_colors.keys():
		if is_instance_valid(sprite):
			sprite.modulate = _player_original_colors[sprite]

	if _player_original_colors.size() > 0:
		_log("Restored original colors to %d player sprites" % _player_original_colors.size())

	_player_original_colors.clear()

	# Tell the player to refresh their health visual to apply correct colors
	# This is needed because the stored colors might be stale (captured at a different
	# health level or during a previous effect state)
	if _player != null and is_instance_valid(_player):
		# Try C# player method (RefreshHealthVisual)
		if _player.has_method("RefreshHealthVisual"):
			_player.RefreshHealthVisual()
			_log("Called player RefreshHealthVisual (C#)")
		# Try GDScript player method (refresh_health_visual)
		elif _player.has_method("refresh_health_visual"):
			_player.refresh_health_visual()
			_log("Called player refresh_health_visual (GDScript)")


## Increase saturation of a color by a multiplier.
## Uses the same algorithm as the saturation shader.
func _saturate_color(color: Color, multiplier: float) -> Color:
	# Calculate luminance using standard weights
	var luminance := color.r * 0.299 + color.g * 0.587 + color.b * 0.114

	# Increase saturation by moving away from grayscale
	var saturated_r: float = lerp(luminance, color.r, multiplier)
	var saturated_g: float = lerp(luminance, color.g, multiplier)
	var saturated_b: float = lerp(luminance, color.b, multiplier)

	# Clamp to valid color range
	return Color(
		clampf(saturated_r, 0.0, 1.0),
		clampf(saturated_g, 0.0, 1.0),
		clampf(saturated_b, 0.0, 1.0),
		color.a
	)


## Resets all effects (useful when restarting the scene).
func reset_effects() -> void:
	_log("Resetting all effects (scene change detected)")
	_end_penultimate_effect()
	_player = null
	_connected_to_player = false
	_player_original_colors.clear()


## Called when the scene tree structure changes.
## Used to reset effects when a new scene is loaded.
func _on_tree_changed() -> void:
	var current_scene := get_tree().current_scene
	if current_scene != null and current_scene != _previous_scene_root:
		_previous_scene_root = current_scene
		reset_effects()
