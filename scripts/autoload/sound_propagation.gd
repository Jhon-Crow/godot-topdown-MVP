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
	RELOAD_COMPLETE, ## Weapon reload finished - bolt cycling sound, enemies become cautious
	GRENADE_LANDING, ## Grenade landing on ground - Issue #426: very close range (112px)
	CASING_KICK      ## Issue #693: Shell casing kicked by player walking - same range as reload
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
## Gunshot range uses PM pistol as baseline (800px). All weapon loudness values
## scaled by factor 800/1469 from original values (Issue #1269).
## These define how far a sound can travel before becoming inaudible.
## Note: RELOAD, EMPTY_CLICK, and RELOAD_COMPLETE sounds propagate through walls (no line-of-sight check).
const PROPAGATION_DISTANCES: Dictionary = {
	SoundType.GUNSHOT: 800.0,          ## Issue #1269: PM baseline (800px, all weapons scaled by 800/1469 factor)
	SoundType.EXPLOSION: 2200.0,       ## 1.5x viewport diagonal
	SoundType.FOOTSTEP: 180.0,         ## Very short range
	SoundType.RELOAD: 900.0,           ## Loud mechanical sound - enemies hear through walls
	SoundType.IMPACT: 550.0,           ## Medium range
	SoundType.EMPTY_CLICK: 600.0,      ## Shorter than reload but still audible through walls
	SoundType.RELOAD_COMPLETE: 900.0,  ## Bolt cycling sound - same range as reload start
	SoundType.GRENADE_LANDING: 112.0,  ## Issue #426: 1/4 of half-reload (450/4) - enemies hear grenade very close
	SoundType.CASING_KICK: 900.0       ## Issue #693: Same range as reload - enemies hear casings kicked by player
}

## Reference distance for sound intensity calculations (in pixels).
## At this distance, sound is at "full" intensity (1.0).
const REFERENCE_DISTANCE: float = 50.0

## Minimum intensity threshold below which sound is not propagated.
## This prevents computation for very distant, inaudible sounds.
const MIN_INTENSITY_THRESHOLD: float = 0.01

## Signal emitted whenever a sound is propagated (Issue #1253).
## Used by SoundVisualizer to draw debug circles showing propagation range.
signal sound_emitted(sound_type: SoundType, position: Vector2, source_type: SourceType, propagation_distance: float)

## Registered sound listeners (typically enemies).
## Each listener must have an on_sound_heard(sound_type, position, source_type, source_node) method.
var _listeners: Array = []

## Whether debug logging is enabled.
var _debug_logging: bool = false

## Issue #969: Minimum interval (seconds) between CASING_KICK sound propagations.
## Casings ejected from high-fire-rate weapons (e.g. MiniUzi) immediately enter the
## player's CasingPusher area and trigger receive_kick(), which emits CASING_KICK for
## every enemy on every shot. Throttling prevents flooding the sound propagation system
## with redundant alerts — enemies already react to the GUNSHOT sound from the same shot.
const CASING_KICK_PROPAGATION_COOLDOWN: float = 0.4

## Timestamp of the last CASING_KICK propagation (for throttling).
var _last_casing_kick_time: float = -999.0

## Issue #1145: Minimum interval (seconds) between EMPTY_CLICK sound propagations.
## When the player holds the trigger with an empty magazine, the weapon fires at full rate
## (e.g. Mini UZI ~15/sec) and each pull calls emit_player_empty_click(). With 10 enemies
## listening, this produces 150+ enemy callbacks per second — causing FPS drops to ~26fps.
## Throttling to once per 0.4s (same cooldown as CASING_KICK) eliminates the flooding
## while still alerting enemies that the player's weapon is empty. Enemies only need one
## notification to react; repeated clicks within the same second are redundant.
const EMPTY_CLICK_PROPAGATION_COOLDOWN: float = 0.4

## Timestamp of the last EMPTY_CLICK propagation (for throttling).
var _last_empty_click_time: float = -999.0

## #1528: Per-frame sound emission throttle to prevent cascading callbacks.
## When many enemies fire simultaneously, each gunshot iterates all listeners.
## Cap total emissions per physics frame to spread load across frames.
const SOUND_EMISSIONS_PER_FRAME_MAX: int = 3  ## Max sound emissions processed per physics frame
var _emissions_this_frame: int = 0  ## Counter reset each physics frame
var _last_emission_frame: int = -1  ## Track physics frame for counter reset
var _deferred_sounds: Array = []  ## Sounds queued for next frame(s) when throttle exceeded

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


## #1528: Process deferred sounds from previous frame and reset emission counter.
func _physics_process(_delta: float) -> void:
	_emissions_this_frame = 0
	# Process deferred sounds (up to the per-frame cap)
	while _deferred_sounds.size() > 0 and _emissions_this_frame < SOUND_EMISSIONS_PER_FRAME_MAX:
		var deferred: Dictionary = _deferred_sounds.pop_front()
		_emit_sound_internal(deferred["type"], deferred["pos"], deferred["source_type"],
			deferred["source_node"], deferred["range"])

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
	# #1528: Throttle sound emissions per physics frame to prevent cascading callbacks.
	# When many enemies fire simultaneously (e.g. 5+ in one frame), each emission iterates
	# all listeners producing 100+ callbacks. Defer excess sounds to the next frame.
	_emissions_this_frame += 1
	if _emissions_this_frame > SOUND_EMISSIONS_PER_FRAME_MAX:
		# Defer this sound — will be processed in next frame's _physics_process.
		# Keep deferred queue bounded to prevent memory growth in extreme cases.
		if _deferred_sounds.size() < 10:
			_deferred_sounds.append({
				"type": sound_type, "pos": position, "source_type": source_type,
				"source_node": source_node, "range": custom_range
			})
		return
	_emit_sound_internal(sound_type, position, source_type, source_node, custom_range)


## #1528: Internal sound emission — separated from emit_sound for deferred processing.
func _emit_sound_internal(sound_type: SoundType, position: Vector2, source_type: SourceType,
				source_node: Node2D = null, custom_range: float = -1.0) -> void:
	var propagation_distance: float = custom_range if custom_range > 0 else float(PROPAGATION_DISTANCES.get(sound_type, 1000.0))

	# Notify SoundVisualizer for debug overlay (Issue #1253).
	sound_emitted.emit(sound_type, position, source_type, propagation_distance)

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

	# #1528 v3: Lazy-clean invalid listeners — remove invalids only when found (not filter() rebuild every call).
	# filter() creates a new Array every invocation; with 20 enemies and 5+ sounds/frame this adds up fast.
	var listeners_notified := 0
	var listeners_out_of_range := 0
	var listeners_skipped_self := 0
	var i := _listeners.size() - 1
	while i >= 0:
		var listener: Node2D = _listeners[i]
		if not is_instance_valid(listener):
			_listeners.remove_at(i); i -= 1; continue
		i -= 1
		# Skip if listener is the source (can't hear your own sounds as external)
		if source_node and listener == source_node:
			listeners_skipped_self += 1
			continue
		# Check if listener is within propagation range
		var distance: float = listener.global_position.distance_to(position)
		if distance <= propagation_distance:
			var intensity: float = calculate_intensity(distance)
			# #1528 v3: Avoid has_method() per listener per frame — call on_sound_heard_with_intensity directly.
			# All registered enemies implement this method (checked at registration time via register_listener).
			listener.on_sound_heard_with_intensity(sound_type, position, source_type, source_node, intensity)
			listeners_notified += 1
		else:
			listeners_out_of_range += 1

	_log_to_file("Sound result: notified=%d, out_of_range=%d, self=%d" % [
		listeners_notified, listeners_out_of_range, listeners_skipped_self
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
##
## Issue #1145: Throttled to at most once every EMPTY_CLICK_PROPAGATION_COOLDOWN seconds.
## High-fire-rate weapons (e.g. MiniUzi ~15 shots/sec) spam this call continuously while
## the trigger is held on an empty magazine, flooding all listeners with redundant alerts.
## Enemies need only one notification to update their state — additional clicks are ignored.
func emit_player_empty_click(position: Vector2, source_node: Node2D = null) -> void:
	var current_time := Time.get_ticks_msec() / 1000.0
	if current_time - _last_empty_click_time < EMPTY_CLICK_PROPAGATION_COOLDOWN:
		return  # Throttled: too soon since last EMPTY_CLICK propagation
	_last_empty_click_time = current_time
	emit_sound(SoundType.EMPTY_CLICK, position, SourceType.PLAYER, source_node)


## Convenience method to emit a reload completion sound from the player.
## This sound propagates through walls and signals enemies to become cautious
## because the player is no longer vulnerable (reload finished).
func emit_player_reload_complete(position: Vector2, source_node: Node2D = null) -> void:
	emit_sound(SoundType.RELOAD_COMPLETE, position, SourceType.PLAYER, source_node)


## Convenience method to emit a grenade landing sound (Issue #426).
## This sound has a very short range (112px) - enemies only hear grenades landing very close.
## Enemies within range will hear the grenade land and can react to evade.
func emit_grenade_landing(position: Vector2, source_node: Node2D = null) -> void:
	emit_sound(SoundType.GRENADE_LANDING, position, SourceType.NEUTRAL, source_node)


## Convenience method to emit a casing kick sound (Issue #693).
## When a player walks over shell casings and kicks them, enemies hear the metallic sound.
## This sound has the same range as reload (900px) and propagates through walls.
##
## Issue #969: Throttled to at most once every CASING_KICK_PROPAGATION_COOLDOWN seconds.
## High-fire-rate weapons eject casings that immediately enter the player's CasingPusher
## area, triggering a CASING_KICK propagation for every single shot. Since enemies already
## react to the GUNSHOT sound, this flooding is redundant and causes FPS drops.
func emit_casing_kick(position: Vector2, source_node: Node2D = null) -> void:
	var current_time := Time.get_ticks_msec() / 1000.0
	if current_time - _last_casing_kick_time < CASING_KICK_PROPAGATION_COOLDOWN:
		return  # Throttled: too soon since last CASING_KICK propagation
	_last_casing_kick_time = current_time
	emit_sound(SoundType.CASING_KICK, position, SourceType.NEUTRAL, source_node)


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
