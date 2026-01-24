class_name EnemyMemory
extends RefCounted
## Memory system for enemy AI that tracks suspected player position with confidence.
##
## This class implements an "enemy memory" system where enemies maintain:
## - A suspected position of the player (Vector2)
## - A confidence level (0.0-1.0) representing certainty about that position
## - Time-based decay of confidence
## - Update logic that respects confidence priority
##
## Information sources and their confidence levels:
## - Direct visual contact: confidence = 1.0
## - Sound (gunshot): confidence = 0.7
## - Sound (reload/empty click): confidence = 0.6
## - Information from other enemies: uses source's confidence * 0.9
##
## The confidence system affects AI behavior:
## - High confidence (>0.8): Move directly to suspected position
## - Medium confidence (0.5-0.8): Move cautiously, check cover along the way
## - Low confidence (<0.5): Return to patrol/guard behavior
##
## Usage:
##   var memory = EnemyMemory.new()
##   memory.update_position(player_pos, 1.0)  # Visual contact
##   memory.decay(delta)  # Call each frame
##   if memory.has_target():
##       var target = memory.suspected_position

## The suspected position of the target (player).
var suspected_position: Vector2 = Vector2.ZERO

## Confidence level (0.0 to 1.0) about the suspected position.
## 1.0 = certain (direct visual), 0.0 = no information.
var confidence: float = 0.0

## Timestamp (in milliseconds) when the position was last updated.
var last_updated: float = 0.0

## Minimum time (ms) before a lower-confidence signal can override current position.
## This prevents immediate overwrites from weaker signals.
const OVERRIDE_COOLDOWN_MS: float = 5000.0

## Default decay rate per second.
## At 0.1, confidence drops from 1.0 to 0.0 in 10 seconds.
const DEFAULT_DECAY_RATE: float = 0.1

## Confidence threshold below which the target is considered "lost".
const LOST_TARGET_THRESHOLD: float = 0.05

## Confidence thresholds for different behavior modes.
const HIGH_CONFIDENCE_THRESHOLD: float = 0.8
const MEDIUM_CONFIDENCE_THRESHOLD: float = 0.5
const LOW_CONFIDENCE_THRESHOLD: float = 0.3


## Update the suspected position with new information.
##
## The update will occur if:
## - The new confidence is >= current confidence (stronger or equal signal), OR
## - The override cooldown has elapsed since last update (5 seconds)
##
## Parameters:
## - pos: The new suspected position
## - new_confidence: Confidence level of the new information (0.0-1.0)
##
## Returns:
## - true if the position was updated, false if the update was rejected
func update_position(pos: Vector2, new_confidence: float) -> bool:
	var current_time := Time.get_ticks_msec()
	var time_since_update := current_time - last_updated

	# Accept update if:
	# 1. New confidence is >= current (stronger signal always wins)
	# 2. OR cooldown has elapsed (allow weaker signals after timeout)
	if new_confidence >= confidence or time_since_update > OVERRIDE_COOLDOWN_MS:
		suspected_position = pos
		confidence = clampf(new_confidence, 0.0, 1.0)
		last_updated = current_time
		return true

	return false


## Apply confidence decay over time.
##
## Should be called every frame to gradually reduce confidence.
## When confidence reaches 0, the enemy loses track of the target.
##
## Parameters:
## - delta: Frame time in seconds
## - decay_rate: Rate of decay per second (default 0.1 = 10 seconds to fully decay)
func decay(delta: float, decay_rate: float = DEFAULT_DECAY_RATE) -> void:
	if confidence > 0.0:
		confidence = maxf(confidence - decay_rate * delta, 0.0)


## Check if the memory has a valid target (confidence above threshold).
func has_target() -> bool:
	return confidence > LOST_TARGET_THRESHOLD


## Check if confidence is high (direct engagement behavior).
func is_high_confidence() -> bool:
	return confidence >= HIGH_CONFIDENCE_THRESHOLD


## Check if confidence is medium (cautious approach behavior).
func is_medium_confidence() -> bool:
	return confidence >= MEDIUM_CONFIDENCE_THRESHOLD and confidence < HIGH_CONFIDENCE_THRESHOLD


## Check if confidence is low (search/patrol behavior).
func is_low_confidence() -> bool:
	return confidence >= LOW_CONFIDENCE_THRESHOLD and confidence < MEDIUM_CONFIDENCE_THRESHOLD


## Get the time (in seconds) since the last position update.
func get_time_since_update() -> float:
	return (Time.get_ticks_msec() - last_updated) / 1000.0


## Reset the memory to initial state (no target).
func reset() -> void:
	suspected_position = Vector2.ZERO
	confidence = 0.0
	last_updated = 0.0


## Create a copy of this memory (for sharing information between enemies).
func duplicate_memory() -> EnemyMemory:
	var copy := EnemyMemory.new()
	copy.suspected_position = suspected_position
	copy.confidence = confidence
	copy.last_updated = last_updated
	return copy


## Merge information from another enemy's memory.
## The received confidence is reduced by a factor to represent information degradation.
##
## Parameters:
## - other: The other enemy's memory to receive information from
## - confidence_factor: Multiplier for confidence (default 0.9)
##
## Returns:
## - true if our memory was updated with the received information
func receive_intel(other: EnemyMemory, confidence_factor: float = 0.9) -> bool:
	if other == null or not other.has_target():
		return false

	# Reduce confidence when sharing info (information degrades through communication)
	var received_confidence := other.confidence * confidence_factor
	return update_position(other.suspected_position, received_confidence)


## Get the behavior mode based on current confidence level.
## Returns a string describing the recommended behavior.
func get_behavior_mode() -> String:
	if is_high_confidence():
		return "direct_pursuit"
	elif is_medium_confidence():
		return "cautious_approach"
	elif is_low_confidence():
		return "search"
	else:
		return "patrol"


## Create string representation for debugging.
func _to_string() -> String:
	if not has_target():
		return "EnemyMemory(no target)"
	return "EnemyMemory(pos=%s, conf=%.2f, mode=%s)" % [
		suspected_position,
		confidence,
		get_behavior_mode()
	]
