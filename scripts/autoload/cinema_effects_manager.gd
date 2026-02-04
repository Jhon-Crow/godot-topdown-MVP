extends Node
## Autoload singleton for managing cinema film effects.
##
## Provides a screen-wide film effect that simulates a vintage/cinematic look including:
## - Film grain (without ripple/wave artifacts)
## - Warm/sunny color tint
## - Vignette effect
## - Rare film defects (scratches, dust, flicker)
##
## The effect can be enabled/disabled and parameters can be adjusted at runtime.
##
## ARCHITECTURE (v5.3):
## This manager uses an OVERLAY-BASED approach that does NOT use hint_screen_texture.
## This avoids known bugs in Godot's gl_compatibility renderer that cause white screens.
## Instead of sampling the screen and modifying it, we create transparent overlays
## that blend on top of the rendered scene using standard alpha blending.
##
## v5.0 ADDITIONS:
## - Micro scratches (small 2px scratches) for more authentic film look
## - Death effects: cigarette burn + end of reel countdown triggered on player death
##
## v5.1 FIXES (Issue #431):
## - Fixed player death signal connection (now supports C# 'Died' signal naming)
## - Changed micro scratches to small dots/specks like real film dust particles
## - Moved end of reel effect to top-left corner as requested
## - Increased grain intensity from 0.07 to 0.10
## - Reduced micro speck probability for rare appearance
##
## v5.2 FIXES (Issue #431 feedback):
## - Moved end of reel (white circle) to TOP-RIGHT corner
## - Added expanding death spots that grow and multiply over time
## - Made white specks/motes much more visible (larger size, higher intensity)
## - Increased grain intensity further to 0.15
##
## v5.3 FIXES (Issue #440):
## - Simplified end of reel effect to a clean ~80x80 pixel white circle ring
## - Changed from complex countdown markers to simple ring outline
## - Circle now blinks exactly 2 times then stays visible
## - Updated: Made circle 2x smaller per feedback (was ~160x160, now ~80x80)

# ============================================================================
# DEFAULT VALUES
# ============================================================================

## Default grain intensity (0.0 = no grain, 0.5 = maximum)
## Issue #431 feedback: Increased from 0.10 to 0.15 for even more visible grain
const DEFAULT_GRAIN_INTENSITY: float = 0.15

## Default warm color tint (slightly warm/golden)
const DEFAULT_WARM_COLOR: Color = Color(1.0, 0.95, 0.85)

## Default warm tint intensity (0.0 = no tint, 1.0 = full tint)
const DEFAULT_WARM_INTENSITY: float = 0.12

## Default sunny effect intensity
const DEFAULT_SUNNY_INTENSITY: float = 0.08

## Default vignette intensity
const DEFAULT_VIGNETTE_INTENSITY: float = 0.25

## Default vignette softness
const DEFAULT_VIGNETTE_SOFTNESS: float = 0.45

## Default film defect probability (1.5% chance)
const DEFAULT_DEFECT_PROBABILITY: float = 0.015

## Default scratch intensity
const DEFAULT_SCRATCH_INTENSITY: float = 0.6

## Default dust intensity
const DEFAULT_DUST_INTENSITY: float = 0.5

## Default flicker intensity
const DEFAULT_FLICKER_INTENSITY: float = 0.03

## Default micro scratch (now micro specks/dots) intensity
## Issue #431 feedback: Increased from 0.35 to 0.7 for visibility
const DEFAULT_MICRO_SCRATCH_INTENSITY: float = 0.7

## Default micro scratch (now micro specks/dots) probability
## Issue #431 feedback: Increased from 0.015 to 0.04 for more frequent appearance
const DEFAULT_MICRO_SCRATCH_PROBABILITY: float = 0.04

## Default cigarette burn size
const DEFAULT_CIGARETTE_BURN_SIZE: float = 0.15

## Default end of reel duration (seconds)
const DEFAULT_END_OF_REEL_DURATION: float = 3.0

## The CanvasLayer for cinema effects.
var _effects_layer: CanvasLayer = null

## The ColorRect with the cinema shader.
var _cinema_rect: ColorRect = null

## Whether the effect is currently active.
var _is_active: bool = true

## Cached shader material reference.
var _material: ShaderMaterial = null


## Number of frames to wait before enabling the effect.
## This ensures the scene has fully rendered before applying the shader.
## With v4.0 overlay approach, this is less critical but still provides
## smooth transitions.
const ACTIVATION_DELAY_FRAMES: int = 1

## Counter for delayed activation.
var _activation_frame_counter: int = 0

## Whether we're waiting to activate the effect.
var _waiting_for_activation: bool = false

## Whether death effects are currently playing.
var _death_effects_active: bool = false

## Time tracker for end of reel animation.
var _end_of_reel_timer: float = 0.0

## Duration for end of reel effect.
var _end_of_reel_duration: float = DEFAULT_END_OF_REEL_DURATION

## Time tracker for death spots animation (Issue #431).
var _death_spots_timer: float = 0.0

## Reference to the current player node (for death signal connection).
var _player_ref: Node = null


func _ready() -> void:
	_log("CinemaEffectsManager initializing (v5.3 - overlay approach with simplified death circle)...")

	# Connect to scene tree changes to handle scene reloads
	get_tree().tree_changed.connect(_on_tree_changed)

	# Create effects layer (high layer to render on top of everything)
	_effects_layer = CanvasLayer.new()
	_effects_layer.name = "CinemaEffectsLayer"
	_effects_layer.layer = 99  # Below hit effects (100) but above UI
	add_child(_effects_layer)
	_log("Created effects layer at layer 99")

	# Create full-screen overlay
	_cinema_rect = ColorRect.new()
	_cinema_rect.name = "CinemaOverlay"
	_cinema_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cinema_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Set base color to transparent - the shader will produce the overlay
	_cinema_rect.color = Color(1.0, 1.0, 1.0, 1.0)  # White base, shader controls actual output

	# Load and apply the cinema shader
	var shader := load("res://scripts/shaders/cinema_film.gdshader") as Shader
	if shader:
		_material = ShaderMaterial.new()
		_material.shader = shader
		_set_default_parameters()
		_cinema_rect.material = _material
		_log("Cinema shader loaded successfully (v5.0 - no screen_texture)")
	else:
		push_warning("CinemaEffectsManager: Could not load cinema_film shader")
		_log("WARNING: Could not load cinema_film shader!")

	# Start with overlay hidden for smooth initialization
	_cinema_rect.visible = false
	_effects_layer.add_child(_cinema_rect)

	# Perform shader warmup to prevent first-frame stutter (Issue #343 pattern)
	_warmup_shader()

	_log("Cinema film effect initialized (v5.3) - Configuration:")
	_log("  Approach: Overlay-based (no screen_texture)")
	_log("  Grain intensity: %.2f" % DEFAULT_GRAIN_INTENSITY)
	_log("  Warm tint: %.2f intensity" % DEFAULT_WARM_INTENSITY)
	_log("  Sunny effect: %.2f intensity" % DEFAULT_SUNNY_INTENSITY)
	_log("  Vignette: %.2f intensity" % DEFAULT_VIGNETTE_INTENSITY)
	_log("  Film defects: %.1f%% probability" % (DEFAULT_DEFECT_PROBABILITY * 100.0))
	_log("  White specks: %.2f intensity, %.1f%% probability" % [DEFAULT_MICRO_SCRATCH_INTENSITY, DEFAULT_MICRO_SCRATCH_PROBABILITY * 100.0])
	_log("  Death effects: cigarette burn + expanding spots + end of reel circle (160px, blinks 2x)")

	# Start delayed activation - minimal delay needed since we don't use screen_texture
	_waiting_for_activation = true
	_activation_frame_counter = 0
	_log("Enabling effect after %d frame(s)..." % ACTIVATION_DELAY_FRAMES)

	# Connect to player death when player becomes available
	call_deferred("_connect_to_player_death")


## Log a message with the CinemaEffects prefix.
func _log(message: String) -> void:
	var logger: Node = get_node_or_null("/root/FileLogger")
	if logger and logger.has_method("log_info"):
		logger.log_info("[CinemaEffects] " + message)
	else:
		print("[CinemaEffects] " + message)


## Process function for delayed activation and death effects animation.
func _process(delta: float) -> void:
	# Handle delayed activation to ensure scene has rendered before enabling effect
	if _waiting_for_activation:
		_activation_frame_counter += 1
		if _activation_frame_counter >= ACTIVATION_DELAY_FRAMES:
			_waiting_for_activation = false
			if _is_active:
				_cinema_rect.visible = true
				_log("Cinema effect now enabled (after %d frames delay)" % ACTIVATION_DELAY_FRAMES)

	# Handle death effects animation (end of reel countdown + expanding spots)
	if _death_effects_active and _material:
		_end_of_reel_timer += delta
		_death_spots_timer += delta
		_material.set_shader_parameter("end_of_reel_time", _end_of_reel_timer)
		_material.set_shader_parameter("death_spots_time", _death_spots_timer)

		# Animate cigarette burn intensity (fade in over 0.5 seconds)
		var burn_intensity: float = clampf(_end_of_reel_timer / 0.5, 0.0, 1.0)
		_material.set_shader_parameter("cigarette_burn_intensity", burn_intensity)

		# Animate end of reel intensity (fade in over 0.3 seconds)
		var reel_intensity: float = clampf(_end_of_reel_timer / 0.3, 0.0, 1.0)
		_material.set_shader_parameter("end_of_reel_intensity", reel_intensity)

		# Animate death spots intensity (fade in over 0.5 seconds, stays at full)
		var spots_intensity: float = clampf(_death_spots_timer / 0.5, 0.0, 1.0)
		_material.set_shader_parameter("death_spots_intensity", spots_intensity)


## Sets all shader parameters to default values.
func _set_default_parameters() -> void:
	if _material:
		# Grain parameters
		_material.set_shader_parameter("grain_intensity", DEFAULT_GRAIN_INTENSITY)
		_material.set_shader_parameter("grain_enabled", true)

		# Warm color parameters
		_material.set_shader_parameter("warm_color", DEFAULT_WARM_COLOR)
		_material.set_shader_parameter("warm_intensity", DEFAULT_WARM_INTENSITY)
		_material.set_shader_parameter("warm_enabled", true)

		# Sunny/bright effect parameters (v4.0: no highlight_boost - overlay approach)
		_material.set_shader_parameter("sunny_intensity", DEFAULT_SUNNY_INTENSITY)
		_material.set_shader_parameter("sunny_enabled", true)

		# Vignette parameters
		_material.set_shader_parameter("vignette_intensity", DEFAULT_VIGNETTE_INTENSITY)
		_material.set_shader_parameter("vignette_softness", DEFAULT_VIGNETTE_SOFTNESS)
		_material.set_shader_parameter("vignette_enabled", true)

		# Film defect parameters
		_material.set_shader_parameter("defects_enabled", true)
		_material.set_shader_parameter("defect_probability", DEFAULT_DEFECT_PROBABILITY)
		_material.set_shader_parameter("scratch_intensity", DEFAULT_SCRATCH_INTENSITY)
		_material.set_shader_parameter("dust_intensity", DEFAULT_DUST_INTENSITY)
		_material.set_shader_parameter("flicker_intensity", DEFAULT_FLICKER_INTENSITY)

		# Micro scratches parameters (small 2px scratches)
		_material.set_shader_parameter("micro_scratches_enabled", true)
		_material.set_shader_parameter("micro_scratch_intensity", DEFAULT_MICRO_SCRATCH_INTENSITY)
		_material.set_shader_parameter("micro_scratch_probability", DEFAULT_MICRO_SCRATCH_PROBABILITY)

		# Death effects (disabled by default, activated on player death)
		_material.set_shader_parameter("cigarette_burn_enabled", false)
		_material.set_shader_parameter("cigarette_burn_intensity", 0.0)
		_material.set_shader_parameter("cigarette_burn_position", Vector2(0.5, 0.5))
		_material.set_shader_parameter("cigarette_burn_size", DEFAULT_CIGARETTE_BURN_SIZE)
		_material.set_shader_parameter("end_of_reel_enabled", false)
		_material.set_shader_parameter("end_of_reel_intensity", 0.0)
		_material.set_shader_parameter("end_of_reel_time", 0.0)
		# Death spots (Issue #431 - expanding spots that multiply)
		_material.set_shader_parameter("death_spots_enabled", false)
		_material.set_shader_parameter("death_spots_intensity", 0.0)
		_material.set_shader_parameter("death_spots_time", 0.0)


## Enables or disables the entire cinema effect.
func set_enabled(enabled: bool) -> void:
	_is_active = enabled
	if enabled:
		# Use delayed activation when enabling to prevent white screen
		_start_delayed_activation()
	else:
		# Disable immediately
		_cinema_rect.visible = false
		_waiting_for_activation = false


## Returns whether the effect is currently enabled.
func is_enabled() -> bool:
	return _is_active


## Sets the film grain intensity.
## @param intensity: Value from 0.0 (no grain) to 0.5 (maximum grain)
func set_grain_intensity(intensity: float) -> void:
	if _material:
		_material.set_shader_parameter("grain_intensity", clamp(intensity, 0.0, 0.5))


## Gets the current grain intensity.
func get_grain_intensity() -> float:
	if _material:
		return _material.get_shader_parameter("grain_intensity")
	return DEFAULT_GRAIN_INTENSITY


## Enables or disables just the grain effect.
func set_grain_enabled(enabled: bool) -> void:
	if _material:
		_material.set_shader_parameter("grain_enabled", enabled)


## Sets the warm color tint.
## @param color: The target warm color (default is a subtle warm/sepia)
func set_warm_color(color: Color) -> void:
	if _material:
		_material.set_shader_parameter("warm_color", color)


## Sets the warm tint intensity.
## @param intensity: Value from 0.0 (no tint) to 1.0 (full tint)
func set_warm_intensity(intensity: float) -> void:
	if _material:
		_material.set_shader_parameter("warm_intensity", clamp(intensity, 0.0, 1.0))


## Gets the current warm intensity.
func get_warm_intensity() -> float:
	if _material:
		return _material.get_shader_parameter("warm_intensity")
	return DEFAULT_WARM_INTENSITY


## Enables or disables just the warm tint effect.
func set_warm_enabled(enabled: bool) -> void:
	if _material:
		_material.set_shader_parameter("warm_enabled", enabled)


# ============================================================================
# SUNNY EFFECT CONTROLS
# ============================================================================

## Sets the sunny/golden highlight effect intensity.
## @param intensity: Value from 0.0 (no sunny effect) to 0.5 (maximum)
func set_sunny_intensity(intensity: float) -> void:
	if _material:
		_material.set_shader_parameter("sunny_intensity", clamp(intensity, 0.0, 0.5))


## Gets the current sunny effect intensity.
func get_sunny_intensity() -> float:
	if _material:
		return _material.get_shader_parameter("sunny_intensity")
	return DEFAULT_SUNNY_INTENSITY


## Enables or disables the sunny/golden highlight effect.
func set_sunny_enabled(enabled: bool) -> void:
	if _material:
		_material.set_shader_parameter("sunny_enabled", enabled)


# ============================================================================
# VIGNETTE CONTROLS
# ============================================================================

## Sets the vignette (edge darkening) intensity.
## @param intensity: Value from 0.0 (no vignette) to 1.0 (strong vignette)
func set_vignette_intensity(intensity: float) -> void:
	if _material:
		_material.set_shader_parameter("vignette_intensity", clamp(intensity, 0.0, 1.0))


## Gets the current vignette intensity.
func get_vignette_intensity() -> float:
	if _material:
		return _material.get_shader_parameter("vignette_intensity")
	return DEFAULT_VIGNETTE_INTENSITY


## Sets the vignette softness (how gradual the edge darkening is).
## @param softness: Value from 0.0 (sharp edges) to 1.0 (soft gradient)
func set_vignette_softness(softness: float) -> void:
	if _material:
		_material.set_shader_parameter("vignette_softness", clamp(softness, 0.0, 1.0))


## Enables or disables the vignette effect.
func set_vignette_enabled(enabled: bool) -> void:
	if _material:
		_material.set_shader_parameter("vignette_enabled", enabled)


# ============================================================================
# FILM DEFECTS CONTROLS (scratches, dust, flicker)
# ============================================================================

## Enables or disables all film defect effects (scratches, dust, flicker).
func set_defects_enabled(enabled: bool) -> void:
	if _material:
		_material.set_shader_parameter("defects_enabled", enabled)


## Returns whether film defects are enabled.
func is_defects_enabled() -> bool:
	if _material:
		return _material.get_shader_parameter("defects_enabled")
	return true


## Sets the probability of film defects appearing.
## @param probability: Value from 0.0 (never) to 0.1 (10% chance per frame)
func set_defect_probability(probability: float) -> void:
	if _material:
		_material.set_shader_parameter("defect_probability", clamp(probability, 0.0, 0.1))


## Gets the current defect probability.
func get_defect_probability() -> float:
	if _material:
		return _material.get_shader_parameter("defect_probability")
	return DEFAULT_DEFECT_PROBABILITY


## Sets the intensity of vertical scratch lines.
## @param intensity: Value from 0.0 (invisible) to 1.0 (fully visible)
func set_scratch_intensity(intensity: float) -> void:
	if _material:
		_material.set_shader_parameter("scratch_intensity", clamp(intensity, 0.0, 1.0))


## Sets the intensity of dust particles.
## @param intensity: Value from 0.0 (no dust) to 1.0 (dark dust)
func set_dust_intensity(intensity: float) -> void:
	if _material:
		_material.set_shader_parameter("dust_intensity", clamp(intensity, 0.0, 1.0))


## Sets the intensity of projector flicker effect.
## @param intensity: Value from 0.0 (no flicker) to 0.3 (strong flicker)
func set_flicker_intensity(intensity: float) -> void:
	if _material:
		_material.set_shader_parameter("flicker_intensity", clamp(intensity, 0.0, 0.3))


# ============================================================================
# MICRO SCRATCHES CONTROLS (small 2px scratches)
# ============================================================================

## Enables or disables micro scratches effect.
func set_micro_scratches_enabled(enabled: bool) -> void:
	if _material:
		_material.set_shader_parameter("micro_scratches_enabled", enabled)


## Returns whether micro scratches are enabled.
func is_micro_scratches_enabled() -> bool:
	if _material:
		return _material.get_shader_parameter("micro_scratches_enabled")
	return true


## Sets the micro scratch intensity.
## @param intensity: Value from 0.0 (invisible) to 1.0 (fully visible)
func set_micro_scratch_intensity(intensity: float) -> void:
	if _material:
		_material.set_shader_parameter("micro_scratch_intensity", clamp(intensity, 0.0, 1.0))


## Gets the current micro scratch intensity.
func get_micro_scratch_intensity() -> float:
	if _material:
		return _material.get_shader_parameter("micro_scratch_intensity")
	return DEFAULT_MICRO_SCRATCH_INTENSITY


## Sets the probability of micro scratches appearing.
## @param probability: Value from 0.0 (never) to 0.2 (20% chance)
func set_micro_scratch_probability(probability: float) -> void:
	if _material:
		_material.set_shader_parameter("micro_scratch_probability", clamp(probability, 0.0, 0.2))


# ============================================================================
# DEATH EFFECTS CONTROLS (cigarette burn + end of reel)
# ============================================================================

## Triggers the death effects (cigarette burn + expanding spots + end of reel).
## Call this when the player dies to show the cinematic death sequence.
func trigger_death_effects() -> void:
	if not _material:
		return

	_log("Death effects triggered - starting cigarette burn, expanding spots, and end of reel (top-right)")
	_death_effects_active = true
	_end_of_reel_timer = 0.0
	_death_spots_timer = 0.0

	# Generate random position for cigarette burn (biased toward center-ish area)
	var burn_x := 0.3 + randf() * 0.4  # 0.3 to 0.7
	var burn_y := 0.3 + randf() * 0.4  # 0.3 to 0.7
	_material.set_shader_parameter("cigarette_burn_position", Vector2(burn_x, burn_y))

	# Enable all death effects
	_material.set_shader_parameter("cigarette_burn_enabled", true)
	_material.set_shader_parameter("end_of_reel_enabled", true)
	_material.set_shader_parameter("death_spots_enabled", true)

	# Start with zero intensity (will animate in _process)
	_material.set_shader_parameter("cigarette_burn_intensity", 0.0)
	_material.set_shader_parameter("end_of_reel_intensity", 0.0)
	_material.set_shader_parameter("death_spots_intensity", 0.0)


## Stops and resets the death effects.
## Call this when the player respawns.
func reset_death_effects() -> void:
	if not _material:
		return

	_log("Death effects reset")
	_death_effects_active = false
	_end_of_reel_timer = 0.0
	_death_spots_timer = 0.0

	# Disable all death effects
	_material.set_shader_parameter("cigarette_burn_enabled", false)
	_material.set_shader_parameter("cigarette_burn_intensity", 0.0)
	_material.set_shader_parameter("end_of_reel_enabled", false)
	_material.set_shader_parameter("end_of_reel_intensity", 0.0)
	_material.set_shader_parameter("end_of_reel_time", 0.0)
	_material.set_shader_parameter("death_spots_enabled", false)
	_material.set_shader_parameter("death_spots_intensity", 0.0)
	_material.set_shader_parameter("death_spots_time", 0.0)


## Returns whether death effects are currently active.
func is_death_effects_active() -> bool:
	return _death_effects_active


## Sets the size of the cigarette burn.
## @param size: Value from 0.0 to 0.5 (fraction of screen)
func set_cigarette_burn_size(size: float) -> void:
	if _material:
		_material.set_shader_parameter("cigarette_burn_size", clamp(size, 0.0, 0.5))


## Sets the duration of the end of reel countdown.
## @param duration: Time in seconds
func set_end_of_reel_duration(duration: float) -> void:
	_end_of_reel_duration = max(0.1, duration)


# ============================================================================
# PLAYER DEATH CONNECTION
# ============================================================================

## Connects to the player's death signal to trigger death effects automatically.
func _connect_to_player_death() -> void:
	# Try to find the player node
	var player := _find_player_node()
	if player:
		_connect_player_signals(player)
	else:
		# If player not found yet, try again when scene changes
		_log("Player not found yet, will connect when scene changes")


## Finds the player node in the scene tree.
func _find_player_node() -> Node:
	# Try common paths for player
	var possible_paths := [
		"/root/MainScene/Player",
		"/root/Game/Player",
		"/root/World/Player",
	]

	for path in possible_paths:
		var node := get_node_or_null(path)
		if node:
			return node

	# Try to find by group
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0]

	# Try to find by class name pattern
	var root := get_tree().current_scene
	if root:
		return _find_node_by_name_pattern(root, "player")

	return null


## Recursively searches for a node whose name contains the pattern.
func _find_node_by_name_pattern(node: Node, pattern: String) -> Node:
	if node.name.to_lower().contains(pattern):
		return node
	for child in node.get_children():
		var found := _find_node_by_name_pattern(child, pattern)
		if found:
			return found
	return null


## Connects to the player's signals.
func _connect_player_signals(player: Node) -> void:
	if player == _player_ref:
		return  # Already connected

	# Disconnect from old player if any
	if _player_ref and is_instance_valid(_player_ref):
		# Try both "Died" (C# convention) and "died" (GDScript convention)
		if _player_ref.has_signal("Died") and _player_ref.is_connected("Died", _on_player_died):
			_player_ref.disconnect("Died", _on_player_died)
		elif _player_ref.has_signal("died") and _player_ref.is_connected("died", _on_player_died):
			_player_ref.disconnect("died", _on_player_died)

	_player_ref = player
	_log("Found player node: %s" % player.name)

	# Connect to death signal - try both C# ("Died") and GDScript ("died") conventions
	if player.has_signal("Died"):
		if not player.is_connected("Died", _on_player_died):
			player.connect("Died", _on_player_died)
			_log("Connected to player 'Died' signal (C# naming)")
	elif player.has_signal("died"):
		if not player.is_connected("died", _on_player_died):
			player.connect("died", _on_player_died)
			_log("Connected to player 'died' signal (GDScript naming)")
	else:
		_log("WARNING: Player node does not have 'Died' or 'died' signal")


## Called when the player dies.
func _on_player_died() -> void:
	_log("Player died - triggering death effects")
	trigger_death_effects()


## Resets all parameters to defaults.
func reset_to_defaults() -> void:
	_set_default_parameters()
	_is_active = true
	# Trigger delayed activation instead of immediate enable
	_start_delayed_activation()


## Tracks the previous scene root to detect scene changes.
var _previous_scene_root: Node = null


## Called when the scene tree structure changes.
## Used to ensure effect persists across scene loads.
func _on_tree_changed() -> void:
	var current_scene := get_tree().current_scene
	if current_scene != null and current_scene != _previous_scene_root:
		_previous_scene_root = current_scene
		_log("Scene changed to: %s" % current_scene.name)
		# Re-trigger delayed activation on scene changes
		# This ensures the new scene has rendered before enabling the effect
		if _is_active:
			_start_delayed_activation()
		# Try to connect to the new player
		call_deferred("_connect_to_player_death")
		# Reset death effects on scene change (player respawn)
		if _death_effects_active:
			reset_death_effects()


## Starts the delayed activation process.
## Hides the overlay and waits for the scene to render before showing it.
func _start_delayed_activation() -> void:
	_cinema_rect.visible = false
	_waiting_for_activation = true
	_activation_frame_counter = 0


## Performs warmup to pre-compile the cinema shader.
## This prevents a shader compilation stutter on first frame (Issue #343 pattern).
func _warmup_shader() -> void:
	if _cinema_rect == null or _cinema_rect.material == null:
		return

	_log("Starting cinema shader warmup (Issue #343 fix)...")
	var start_time := Time.get_ticks_msec()

	# Ensure shader is visible briefly to trigger compilation
	_cinema_rect.visible = true

	# Wait one frame to ensure GPU processes and compiles the shader
	await get_tree().process_frame

	# CRITICAL: Hide the overlay after warmup
	# It will be re-enabled by delayed activation
	_cinema_rect.visible = false

	var elapsed := Time.get_ticks_msec() - start_time
	_log("Cinema shader warmup complete in %d ms" % elapsed)
