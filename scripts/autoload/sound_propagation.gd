extends Node
## Autoload singleton for managing in-game sound propagation.
##
## This system handles the propagation of sounds that affect gameplay behavior,
## such as gunshots alerting enemies. It is separate from the AudioManager
## which handles actual audio playback.
##
## The system is designed to be extensible:
## - Add new sound types to the SoundType enum
## - Define propagation distances for each sound type
## - Listeners (enemies) register themselves to receive sound events
## - Sound sources can specify custom loudness (range) for their weapons
##
## Usage:
## - Call emit_sound() when a sound-producing action occurs (shooting, explosions, etc.)
## - Listeners call register_listener() to receive sound notifications
## - Listeners implement on_sound_heard(sound_type, position, source) to react
## - Use custom_range parameter to specify weapon-specific loudness

## Types of sounds that can propagate through the game world.
## Each type has different propagation characteristics.
enum SoundType {
	GUNSHOT,         ## Gunfire from weapons - loud, propagates far
	EXPLOSION,       ## Explosions - very loud, propagates very far
	FOOTSTEP,        ## Footsteps - quiet, short range (for future use)
	RELOAD,          ## Weapon reload - loud mechanical sound, propagates far (through walls)
	IMPACT,          ## Bullet impacts - medium range (for future use)
	EMPTY_CLICK,     ## Empty weapon click - audible but shorter range than reload
	RELOAD_COMPLETE  ## Weapon reload finished - bolt cycling sound, enemies become cautious
}

## Source types for sounds - used to determine if listener should react.
enum SourceType {
	PLAYER,   ## Sound came from the player
	ENEMY,    ## Sound came from an enemy
	NEUTRAL   ## Sound came from environment or unknown source
}

## Viewport dimensions for reference (from project settings).
## Used to calculate viewport-relative propagation distances.
const VIEWPORT_WIDTH: float = 1280.0
const VIEWPORT_HEIGHT: float = 720.0
const VIEWPORT_DIAGONAL: float = 1468.6  # sqrt(1280^2 + 720^2) ≈ 1468.6 pixels

## Propagation distances for each sound type (in pixels).
## Gunshot range is approximately viewport diagonal for realistic gameplay.
## These define how far a sound can travel before becoming inaudible.
## Note: RELOAD, EMPTY_CLICK, and RELOAD_COMPLETE sounds propagate through walls (no line-of-sight check).
const PROPAGATION_DISTANCES: Dictionary = {
	SoundType.GUNSHOT: 1468.6,         ## Approximately viewport diagonal
	SoundType.EXPLOSION: 2200.0,       ## 1.5x viewport diagonal
	SoundType.FOOTSTEP: 180.0,         ## Very short range
	SoundType.RELOAD: 900.0,           ## Loud mechanical sound - enemies hear through walls
	SoundType.IMPACT: 550.0,           ## Medium range
	SoundType.EMPTY_CLICK: 600.0,      ## Shorter than reload but still audible through walls
	SoundType.RELOAD_COMPLETE: 900.0   ## Bolt cycling sound - same range as reload start
}

## Reference distance for sound intensity calculations (in pixels).
## At this distance, sound is at "full" intensity (1.0).
const REFERENCE_DISTANCE: float = 50.0

## Minimum intensity threshold below which sound is not propagated.
## This prevents computation for very distant, inaudible sounds.
const MIN_INTENSITY_THRESHOLD: float = 0.01

## Registered sound listeners (typically enemies).
## Each listener must have an on_sound_heard(sound_type, position, source_type, source_node) method.
var _listeners: Array = []

## Whether debug logging is enabled.
var _debug_logging: bool = false

## Reference to FileLogger for persistent logging.
var _file_logger: Node = null


func _ready() -> void:
	# Get FileLogger reference for persistent logging
	_file_logger = get_node_or_null("/root/FileLogger")
	if _file_logger:
		_log_to_file("SoundPropagation autoload initialized")

	# Try to sync with GameManager debug mode
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("is_debug_mode_enabled"):
		_debug_logging = game_manager.is_debug_mode_enabled()
		if game_manager.has_signal("debug_mode_toggled"):
			game_manager.debug_mode_toggled.connect(_on_debug_mode_toggled)


## Called when debug mode is toggled via GameManager.
func _on_debug_mode_toggled(enabled: bool) -> void:
	_debug_logging = enabled


## Register a listener to receive sound events.
## The listener must implement on_sound_heard(sound_type: SoundType, position: Vector2,
##                                            source_type: SourceType, source_node: Node2D) -> void
func register_listener(listener: Node2D) -> void:
	if listener and not _listeners.has(listener):
		_listeners.append(listener)
		_log_debug("Registered sound listener: %s" % listener.name)
		_log_to_file("Registered listener: %s (total: %d)" % [listener.name, _listeners.size()])


## Unregister a listener from receiving sound events.
func unregister_listener(listener: Node2D) -> void:
	var idx := _listeners.find(listener)
	if idx >= 0:
		_listeners.remove_at(idx)
		_log_debug("Unregistered sound listener: %s" % listener.name)
		_log_to_file("Unregistered listener: %s (remaining: %d)" % [listener.name, _listeners.size()])


## Emit a sound at a given position.
## All registered listeners within range will be notified.
## Uses physically-based inverse square law for intensity calculation.
##
## Parameters:
## - sound_type: The type of sound being emitted
## - position: World position where the sound originates
## - source_type: Whether the sound comes from player, enemy, or neutral source
## - source_node: The node that produced the sound (optional, can be null)
## - custom_range: Override the default propagation distance (optional, -1 uses default)
func emit_sound(sound_type: SoundType, position: Vector2, source_type: SourceType,
				source_node: Node2D = null, custom_range: float = -1.0) -> void:
	var propagation_distance: float = custom_range if custom_range > 0 else float(PROPAGATION_DISTANCES.get(sound_type, 1000.0))

	var source_name: String = source_node.name if source_node else "null"
	_log_debug("Sound emitted: type=%s, pos=%s, source=%s, range=%.0f" % [
		SoundType.keys()[sound_type],
		position,
		SourceType.keys()[source_type],
		propagation_distance
	])
	_log_to_file("Sound emitted: type=%s, pos=%s, source=%s (%s), range=%.0f, listeners=%d" % [
		SoundType.keys()[sound_type],
		position,
		SourceType.keys()[source_type],
		source_name,
		propagation_distance,
		_listeners.size()
	])

	# Clean up invalid listeners (destroyed nodes)
	var prev_count := _listeners.size()
	_listeners = _listeners.filter(func(l): return is_instance_valid(l))
	if _listeners.size() < prev_count:
		_log_to_file("Cleaned up %d invalid listeners" % (prev_count - _listeners.size()))

	# Notify all listeners within range
	var listeners_notified := 0
	var listeners_out_of_range := 0
	var listeners_skipped_self := 0
	var listeners_below_threshold := 0

	for listener: Node2D in _listeners:
		if not is_instance_valid(listener):
			continue

		# Skip if listener is the source (can't hear your own sounds as external)
		if source_node and listener == source_node:
			listeners_skipped_self += 1
			continue

		# Check if listener is within propagation range
		var distance: float = listener.global_position.distance_to(position)
		if distance <= propagation_distance:
			# Calculate sound intensity using inverse square law
			# Intensity = 1.0 at reference distance, falls off with 1/r²
			var intensity: float = calculate_intensity(distance)

			# Only notify if intensity is above threshold
			if intensity >= MIN_INTENSITY_THRESHOLD:
				# Notify the listener with intensity information
				if listener.has_method("on_sound_heard_with_intensity"):
					listener.on_sound_heard_with_intensity(sound_type, position, source_type, source_node, intensity)
					listeners_notified += 1
				elif listener.has_method("on_sound_heard"):
					listener.on_sound_heard(sound_type, position, source_type, source_node)
					listeners_notified += 1
			else:
				listeners_below_threshold += 1
		else:
			listeners_out_of_range += 1

	_log_to_file("Sound result: notified=%d, out_of_range=%d, self=%d, below_threshold=%d" % [
		listeners_notified, listeners_out_of_range, listeners_skipped_self, listeners_below_threshold
	])

	if listeners_notified > 0:
		_log_debug("Sound notified %d listeners" % listeners_notified)


## Calculate sound intensity at a given distance using inverse square law.
## Uses physically-inspired attenuation: intensity = (reference_distance / distance)²
##
## Parameters:
## - distance: Distance from sound source in pixels
##
## Returns:
## - Intensity value from 0.0 to 1.0 (clamped)
func calculate_intensity(distance: float) -> float:
	# At or closer than reference distance, full intensity
	if distance <= REFERENCE_DISTANCE:
		return 1.0

	# Inverse square law: I = I₀ * (r₀/r)²
	# Where I₀ = 1.0 at reference distance r₀
	var intensity := pow(REFERENCE_DISTANCE / distance, 2.0)

	return clampf(intensity, 0.0, 1.0)


## Calculate sound intensity with atmospheric absorption for more realism.
## Includes both inverse square law and high-frequency absorption.
##
## Parameters:
## - distance: Distance from sound source in pixels
## - absorption_coefficient: How quickly high frequencies are absorbed (default 0.001)
##
## Returns:
## - Intensity value from 0.0 to 1.0 (clamped)
func calculate_intensity_with_absorption(distance: float, absorption_coefficient: float = 0.001) -> float:
	# Start with inverse square law intensity
	var base_intensity := calculate_intensity(distance)

	# Apply exponential atmospheric absorption
	# This simulates high-frequency content being absorbed over distance
	var absorption_factor := exp(-absorption_coefficient * distance)

	return clampf(base_intensity * absorption_factor, 0.0, 1.0)


## Convenience method to emit a gunshot sound from the player.
func emit_player_gunshot(position: Vector2, source_node: Node2D = null) -> void:
	emit_sound(SoundType.GUNSHOT, position, SourceType.PLAYER, source_node)


## Convenience method to emit a gunshot sound from an enemy.
func emit_enemy_gunshot(position: Vector2, source_node: Node2D = null) -> void:
	emit_sound(SoundType.GUNSHOT, position, SourceType.ENEMY, source_node)


## Convenience method to emit a reload sound from the player.
## This sound propagates through walls and alerts enemies even behind cover.
func emit_player_reload(position: Vector2, source_node: Node2D = null) -> void:
	emit_sound(SoundType.RELOAD, position, SourceType.PLAYER, source_node)


## Convenience method to emit an empty click sound from the player.
## This sound propagates through walls but at shorter range than reload.
func emit_player_empty_click(position: Vector2, source_node: Node2D = null) -> void:
	emit_sound(SoundType.EMPTY_CLICK, position, SourceType.PLAYER, source_node)


## Convenience method to emit a reload completion sound from the player.
## This sound propagates through walls and signals enemies to become cautious
## because the player is no longer vulnerable (reload finished).
func emit_player_reload_complete(position: Vector2, source_node: Node2D = null) -> void:
	emit_sound(SoundType.RELOAD_COMPLETE, position, SourceType.PLAYER, source_node)


## Get the propagation distance for a sound type.
func get_propagation_distance(sound_type: SoundType) -> float:
	return PROPAGATION_DISTANCES.get(sound_type, 1000.0)


## Get the number of registered listeners.
func get_listener_count() -> int:
	_listeners = _listeners.filter(func(l): return is_instance_valid(l))
	return _listeners.size()


## Log a debug message if debug logging is enabled.
func _log_debug(message: String) -> void:
	if _debug_logging:
		print("[SoundPropagation] " + message)


## Log a message to the file logger for persistent debugging.
func _log_to_file(message: String) -> void:
	if _file_logger and _file_logger.has_method("log_info"):
		_file_logger.log_info("[SoundPropagation] " + message)
