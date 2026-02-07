class_name PlayerPredictionComponent
extends RefCounted
## Predicts player movement when line of sight is lost (Issue #298).
##
## Generates probability-weighted hypotheses about where the player might be,
## based on:
## - Retreat paths to nearby cover
## - Flanking routes around the enemy
## - Last known velocity/direction (with momentum averaging)
## - Shot direction memory and post-shot repositioning
## - Time-distance expansion (max travel radius)
## - Player behavioral style (aggressive/cautious/cunning)
##
## Integrates with EnemyMemory and the GOAP planner to enable smarter
## investigation behavior when player disappears from view.
##
## Usage:
##   var predictor = PlayerPredictionComponent.new()
##   predictor.update_observation(player_pos, player_vel, delta)
##   predictor.on_player_lost(last_pos, enemy_pos, enemy_facing)
##   var best = predictor.get_best_hypothesis()

## Hypothesis types for predicted player positions.
enum HypothesisType {
	COVER,            ## Player retreated to nearby cover
	FLANK_LEFT,       ## Player flanking from the left
	FLANK_RIGHT,      ## Player flanking from the right
	LAST_DIRECTION,   ## Player continued moving in last known direction
	AGGRESSIVE,       ## Player is rushing toward the enemy
	STATIONARY,       ## Player stayed near last known position
	SHOT_REPOSITION   ## Player repositioning after firing
}

## A single prediction hypothesis about where the player might be.
class Hypothesis:
	var position: Vector2 = Vector2.ZERO
	var type: HypothesisType = HypothesisType.COVER
	var probability: float = 0.0
	var checked: bool = false  ## Whether this hypothesis has been investigated

	func _init(pos: Vector2 = Vector2.ZERO, h_type: HypothesisType = HypothesisType.COVER, prob: float = 0.0) -> void:
		position = pos
		type = h_type
		probability = prob

## Player behavioral style classification.
enum PlayerStyle {
	UNKNOWN,    ## Not enough data
	AGGRESSIVE, ## Player tends to push forward
	CAUTIOUS,   ## Player tends to use cover and retreat
	CUNNING     ## Player tends to flank and reposition
}

# ============================================================================
# Configuration
# ============================================================================

## Assumed player speed for distance calculations (px/s).
const PLAYER_SPEED: float = 350.0

## Maximum number of hypotheses to maintain.
const MAX_HYPOTHESES: int = 10

## Minimum probability for a hypothesis to be considered valid.
const MIN_HYPOTHESIS_PROBABILITY: float = 0.03

## How quickly hypotheses decay per second (probability reduction).
const HYPOTHESIS_DECAY_RATE: float = 0.05

## Maximum time (seconds) to keep hypotheses alive before clearing them.
const MAX_HYPOTHESIS_AGE: float = 20.0

## Distance to check for cover positions around last known position (px).
const COVER_SEARCH_RADIUS: float = 600.0

## Flank angle from the enemy-to-player line (radians). ~60 degrees.
const FLANK_ANGLE: float = PI / 3.0

## Secondary flank angle for wider coverage (~45 degrees).
const FLANK_ANGLE_WIDE: float = PI / 4.0

## Distance for flank hypotheses from last known position (px).
const FLANK_DISTANCE: float = 300.0

## Weight for cover hypotheses (higher = more likely to predict cover retreat).
const COVER_WEIGHT: float = 1.6

## Weight for flank hypotheses.
const FLANK_WEIGHT: float = 1.1

## Weight for last-direction hypotheses.
const DIRECTION_WEIGHT: float = 1.0

## Weight for aggressive (rush toward enemy) hypotheses.
const AGGRESSIVE_WEIGHT: float = 0.9

## Weight for stationary hypotheses.
const STATIONARY_WEIGHT: float = 0.6

## Weight for shot-reposition hypotheses.
const SHOT_REPOSITION_WEIGHT: float = 1.3

## Number of observations before style classification begins.
const STYLE_OBSERVATION_THRESHOLD: int = 3

## Minimum flank count ratio to classify as cunning.
const CUNNING_FLANK_RATIO: float = 0.25

## Minimum aggression count ratio to classify as aggressive.
const AGGRESSIVE_RATIO: float = 0.35

## Number of velocity samples to average for momentum tracking.
const VELOCITY_SAMPLE_COUNT: int = 5

## Time window (seconds) after a shot to generate repositioning prediction.
const SHOT_REPOSITION_WINDOW: float = 3.0

# ============================================================================
# State
# ============================================================================

## Current hypotheses about player position.
var hypotheses: Array = []  # Array of Hypothesis

## Time since hypotheses were generated (seconds).
var hypothesis_age: float = 0.0

## Whether we currently have active predictions.
var has_predictions: bool = false

## The last known player velocity when they were visible.
var last_known_velocity: Vector2 = Vector2.ZERO

## Smoothed (momentum-averaged) player velocity.
var momentum_velocity: Vector2 = Vector2.ZERO

## The last known player position when they were visible.
var last_known_position: Vector2 = Vector2.ZERO

## Direction the player last fired a shot (normalized).
var last_shot_direction: Vector2 = Vector2.ZERO

## Time since the player last fired (seconds). -1 if never fired.
var time_since_last_shot: float = -1.0

## Classified player behavioral style.
var player_style: PlayerStyle = PlayerStyle.UNKNOWN

## Counters for style classification.
var _style_observations: int = 0
var _aggressive_count: int = 0  ## Times player moved toward enemy
var _cautious_count: int = 0    ## Times player retreated to cover
var _cunning_count: int = 0     ## Times player flanked

## Previous player position for velocity estimation.
var _prev_player_position: Vector2 = Vector2.ZERO
var _has_prev_position: bool = false

## Velocity history ring buffer for momentum averaging.
var _velocity_samples: Array = []  # Array of Vector2

## Enable debug logging (off by default, toggleable).
var debug_logging: bool = false

# ============================================================================
# Public Methods
# ============================================================================


## Update observation of the player while they are visible.
## Call this every frame when the enemy can see the player.
## Tracks velocity with momentum averaging and updates style classification.
func update_observation(player_pos: Vector2, enemy_pos: Vector2, delta: float) -> void:
	# Estimate velocity from position change
	if _has_prev_position and delta > 0.0:
		last_known_velocity = (player_pos - _prev_player_position) / delta
		# Add to momentum buffer
		_velocity_samples.append(last_known_velocity)
		if _velocity_samples.size() > VELOCITY_SAMPLE_COUNT:
			_velocity_samples.pop_front()
		# Compute momentum average
		var sum := Vector2.ZERO
		for v in _velocity_samples:
			sum += v
		momentum_velocity = sum / _velocity_samples.size()
	_prev_player_position = player_pos
	_has_prev_position = true
	last_known_position = player_pos

	# Update shot timer
	if time_since_last_shot >= 0.0:
		time_since_last_shot += delta

	# Classify behavior based on movement relative to enemy
	_classify_observation(player_pos, enemy_pos)

	# Clear old predictions when we can see the player
	if has_predictions:
		_clear_hypotheses()


## Record that the player fired a shot in the given direction.
## Used to predict post-shot repositioning.
func record_player_shot(direction: Vector2) -> void:
	last_shot_direction = direction.normalized()
	time_since_last_shot = 0.0


## Generate predictions when the player is lost from sight.
## Call this once when the enemy loses visual contact with the player.
##
## Parameters:
## - last_pos: Last known player position
## - enemy_pos: Current enemy position
## - enemy_facing: Direction the enemy is facing (normalized)
## - cover_positions: Array of Vector2 cover positions nearby (from cover component)
func generate_predictions(last_pos: Vector2, enemy_pos: Vector2, enemy_facing: Vector2, cover_positions: Array = []) -> void:
	_clear_hypotheses()
	hypothesis_age = 0.0

	var direction_from_enemy := (last_pos - enemy_pos).normalized()

	# 1. Cover retreat hypotheses (strongest)
	_generate_cover_hypotheses(last_pos, enemy_pos, cover_positions)

	# 2. Flank hypotheses (left and right)
	_generate_flank_hypotheses(last_pos, enemy_pos, direction_from_enemy)

	# 3. Last direction hypothesis (velocity extrapolation with momentum)
	_generate_direction_hypothesis(last_pos)

	# 4. Aggressive hypothesis (player rushing toward enemy)
	_generate_aggressive_hypothesis(last_pos, enemy_pos)

	# 5. Stationary hypothesis (player stayed put)
	_generate_stationary_hypothesis(last_pos)

	# 6. Shot-reposition hypothesis (post-shot movement)
	_generate_shot_reposition_hypothesis(last_pos, enemy_pos)

	# Normalize probabilities
	_normalize_probabilities()

	# Apply style bias (stronger multipliers for classified styles)
	_apply_style_bias()

	# Sort by probability (highest first)
	_sort_hypotheses()

	has_predictions = hypotheses.size() > 0

	if debug_logging and has_predictions:
		_log_hypotheses("Generated predictions")


## Update predictions over time. Call every frame when predictions are active.
## Expands hypothesis positions based on time passed and decays probabilities.
func update_predictions(delta: float) -> void:
	if not has_predictions:
		return

	hypothesis_age += delta

	# Decay probabilities over time (slower decay = predictions last longer)
	for h in hypotheses:
		if not h.checked:
			h.probability = maxf(h.probability - HYPOTHESIS_DECAY_RATE * delta, 0.0)

	# Expand positions based on time (player could have moved further)
	for h in hypotheses:
		if not h.checked:
			# Shift hypothesis in its predicted direction at 40% potential speed
			var shift_dir := (h.position - last_known_position).normalized()
			if shift_dir.length_squared() > 0.01:
				var expansion := PLAYER_SPEED * delta * 0.4
				h.position += shift_dir * expansion

	# Remove dead hypotheses
	hypotheses = hypotheses.filter(func(h: Hypothesis) -> bool: return h.probability > MIN_HYPOTHESIS_PROBABILITY)

	# Check if predictions are still relevant
	if hypotheses.is_empty() or hypothesis_age > MAX_HYPOTHESIS_AGE:
		_clear_hypotheses()


## Get the best (highest probability) unchecked hypothesis.
## Returns null if no valid hypotheses remain.
func get_best_hypothesis() -> Hypothesis:
	for h in hypotheses:
		if not h.checked:
			return h
	return null


## Get the best hypothesis position, or Vector2.ZERO if none available.
func get_best_position() -> Vector2:
	var best := get_best_hypothesis()
	return best.position if best else Vector2.ZERO


## Get the confidence of the best hypothesis (0-1).
func get_prediction_confidence() -> float:
	var best := get_best_hypothesis()
	return best.probability if best else 0.0


## Mark a hypothesis as checked (investigated) when enemy reaches that position.
## The hypothesis with the position closest to the given position is marked.
func mark_position_checked(pos: Vector2, tolerance: float = 100.0) -> void:
	var closest_dist := INF
	var closest_h: Hypothesis = null
	for h in hypotheses:
		if h.checked:
			continue
		var dist := h.position.distance_to(pos)
		if dist < closest_dist and dist < tolerance:
			closest_dist = dist
			closest_h = h
	if closest_h:
		closest_h.checked = true
		if debug_logging:
			print("[Prediction] Marked hypothesis %s as checked (type=%s)" % [closest_h.position, HypothesisType.keys()[closest_h.type]])


## Receive a prediction from an allied enemy and merge it into our hypotheses.
## Reduces probability by a factor (information degrades through sharing).
func receive_prediction_intel(other_hypothesis: Hypothesis, confidence_factor: float = 0.9) -> void:
	if other_hypothesis == null or other_hypothesis.probability < MIN_HYPOTHESIS_PROBABILITY:
		return

	# Check if we already have a similar hypothesis (same area)
	for h in hypotheses:
		if h.position.distance_to(other_hypothesis.position) < 100.0:
			# Merge: take higher probability
			h.probability = maxf(h.probability, other_hypothesis.probability * confidence_factor)
			return

	# Add as new hypothesis if we have room
	if hypotheses.size() < MAX_HYPOTHESES:
		var new_h := Hypothesis.new(
			other_hypothesis.position,
			other_hypothesis.type,
			other_hypothesis.probability * confidence_factor
		)
		hypotheses.append(new_h)
		_sort_hypotheses()
		has_predictions = true


## Process prediction during pursuing state. Returns the next target position
## to move toward, or Vector2.ZERO if no prediction targets remain.
## Automatically marks reached positions as checked and advances to next hypothesis.
func get_pursuit_target(current_pos: Vector2, reach_tolerance: float = 100.0) -> Vector2:
	if not has_predictions:
		return Vector2.ZERO
	var best := get_best_hypothesis()
	if best == null:
		return Vector2.ZERO
	if current_pos.distance_to(best.position) < reach_tolerance:
		mark_position_checked(best.position)
		var next := get_best_hypothesis()
		return next.position if next else Vector2.ZERO
	return best.position


## Get a string describing the current player style.
func get_style_name() -> String:
	match player_style:
		PlayerStyle.AGGRESSIVE: return "aggressive"
		PlayerStyle.CAUTIOUS: return "cautious"
		PlayerStyle.CUNNING: return "cunning"
		_: return "unknown"


## Get a short debug label string for the prediction state. Returns "" if no predictions.
func get_debug_text() -> String:
	var best := get_best_hypothesis()
	if best == null: return ""
	return "\n{P:%s %.0f%%}" % [HypothesisType.keys()[best.type].substr(0, 5), best.probability * 100]


## Process the frame update for memory integration. Call every frame.
## Handles observation tracking, sight-loss prediction generation, and decay.
## Parameters:
##   can_see: whether enemy can see player this frame
##   was_visible: whether enemy could see player last frame
##   player_pos: player position (only used when can_see)
##   enemy_pos: enemy position
##   enemy_facing: enemy model facing direction
##   delta: frame time
##   memory: EnemyMemory to update velocity on
func process_frame(can_see: bool, was_visible: bool, player_pos: Vector2, enemy_pos: Vector2, enemy_facing: Vector2, delta: float, memory: EnemyMemory = null) -> void:
	if can_see:
		update_observation(player_pos, enemy_pos, delta)
		if memory: memory.update_velocity(last_known_velocity)
	if was_visible and not can_see:
		generate_predictions(player_pos, enemy_pos, enemy_facing)
	if has_predictions:
		update_predictions(delta)


## Reset all prediction state.
func reset() -> void:
	_clear_hypotheses()
	last_known_velocity = Vector2.ZERO
	momentum_velocity = Vector2.ZERO
	last_known_position = Vector2.ZERO
	last_shot_direction = Vector2.ZERO
	time_since_last_shot = -1.0
	_prev_player_position = Vector2.ZERO
	_has_prev_position = false
	_velocity_samples.clear()
	# Note: player_style and counters are NOT reset — they persist across encounters


## Create a string representation for debugging.
func _to_string() -> String:
	if not has_predictions:
		return "PlayerPrediction(no predictions)"
	var best := get_best_hypothesis()
	if best:
		return "PlayerPrediction(hypotheses=%d, best=%s@%.0f%%, style=%s)" % [
			hypotheses.size(),
			HypothesisType.keys()[best.type],
			best.probability * 100.0,
			get_style_name()
		]
	return "PlayerPrediction(hypotheses=%d, all checked)" % hypotheses.size()


# ============================================================================
# Private Methods — Hypothesis Generation
# ============================================================================


## Generate cover retreat hypotheses from nearby cover positions.
func _generate_cover_hypotheses(last_pos: Vector2, enemy_pos: Vector2, cover_positions: Array) -> void:
	var retreat_dir := (last_pos - enemy_pos).normalized()

	if cover_positions.is_empty():
		# No cover data provided — generate cover hypotheses behind player
		var cover_pos := last_pos + retreat_dir * 200.0
		hypotheses.append(Hypothesis.new(cover_pos, HypothesisType.COVER, COVER_WEIGHT))
		# Also add a lateral cover position
		var lateral := retreat_dir.rotated(PI / 4.0) * 150.0
		hypotheses.append(Hypothesis.new(last_pos + lateral, HypothesisType.COVER, COVER_WEIGHT * 0.7))
		return

	# Evaluate each cover position
	var best_covers: Array = []  # [{pos, score}]
	for cover_pos in cover_positions:
		if not (cover_pos is Vector2):
			continue
		var dist := last_pos.distance_to(cover_pos)
		if dist > COVER_SEARCH_RADIUS or dist < 30.0:
			continue

		# Score: prefer covers in the retreat direction and closer to last position
		var to_cover := (cover_pos - last_pos).normalized()
		var retreat_alignment := retreat_dir.dot(to_cover)  # Higher = more in retreat dir
		var score := COVER_WEIGHT * (1.0 + retreat_alignment * 0.6) - dist * 0.001

		# Bonus if player was moving toward this cover (use momentum velocity)
		var vel := momentum_velocity if momentum_velocity.length_squared() > 100.0 else last_known_velocity
		if vel.length_squared() > 100.0:
			var vel_alignment := vel.normalized().dot(to_cover)
			score += vel_alignment * 0.5

		# Bonus for covers that break line of sight to enemy
		var enemy_to_cover := (cover_pos - enemy_pos).normalized()
		var perpendicular := absf(retreat_dir.dot(enemy_to_cover))
		score += (1.0 - perpendicular) * 0.3

		best_covers.append({"pos": cover_pos, "score": score})

	# Sort by score and take top 3
	best_covers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	var count := mini(best_covers.size(), 3)
	for i in range(count):
		hypotheses.append(Hypothesis.new(
			best_covers[i]["pos"],
			HypothesisType.COVER,
			best_covers[i]["score"]
		))


## Generate flank hypotheses (left and right of enemy).
func _generate_flank_hypotheses(last_pos: Vector2, enemy_pos: Vector2, dir_from_enemy: Vector2) -> void:
	# Primary flanks: rotate direction 60° from enemy-to-player line
	var left_dir := dir_from_enemy.rotated(-FLANK_ANGLE)
	var left_pos := last_pos + left_dir * FLANK_DISTANCE
	hypotheses.append(Hypothesis.new(left_pos, HypothesisType.FLANK_LEFT, FLANK_WEIGHT))

	var right_dir := dir_from_enemy.rotated(FLANK_ANGLE)
	var right_pos := last_pos + right_dir * FLANK_DISTANCE
	hypotheses.append(Hypothesis.new(right_pos, HypothesisType.FLANK_RIGHT, FLANK_WEIGHT))

	# If player had momentum, bias the flank direction toward momentum
	if momentum_velocity.length_squared() > 2500.0:
		var vel_dir := momentum_velocity.normalized()
		var vel_cross := vel_dir.x * dir_from_enemy.y - vel_dir.y * dir_from_enemy.x
		if vel_cross > 0.3:
			# Player was moving to the right — boost right flank
			hypotheses[-1].probability *= 1.4
		elif vel_cross < -0.3:
			# Player was moving to the left — boost left flank
			hypotheses[-2].probability *= 1.4


## Generate hypothesis based on last known velocity (momentum extrapolation).
func _generate_direction_hypothesis(last_pos: Vector2) -> void:
	# Use momentum velocity for smoother predictions
	var vel := momentum_velocity if momentum_velocity.length_squared() > 100.0 else last_known_velocity
	if vel.length_squared() < 100.0:
		# Player was barely moving — skip direction hypothesis
		return

	# Extrapolate 1.5 seconds of movement
	var predicted_pos := last_pos + vel.normalized() * PLAYER_SPEED * 1.5
	hypotheses.append(Hypothesis.new(predicted_pos, HypothesisType.LAST_DIRECTION, DIRECTION_WEIGHT))


## Generate hypothesis for aggressive player (rushing toward enemy).
func _generate_aggressive_hypothesis(last_pos: Vector2, enemy_pos: Vector2) -> void:
	var to_enemy := (enemy_pos - last_pos).normalized()
	# Predict player closing half the distance in 1 second
	var rush_pos := last_pos + to_enemy * PLAYER_SPEED * 0.7
	hypotheses.append(Hypothesis.new(rush_pos, HypothesisType.AGGRESSIVE, AGGRESSIVE_WEIGHT))


## Generate hypothesis that player stayed near last known position.
func _generate_stationary_hypothesis(last_pos: Vector2) -> void:
	hypotheses.append(Hypothesis.new(last_pos, HypothesisType.STATIONARY, STATIONARY_WEIGHT))


## Generate hypothesis for post-shot repositioning.
## Players often move to a new position after firing to avoid return fire.
func _generate_shot_reposition_hypothesis(last_pos: Vector2, enemy_pos: Vector2) -> void:
	# Only generate if the player fired recently
	if time_since_last_shot < 0.0 or time_since_last_shot > SHOT_REPOSITION_WINDOW:
		return
	if last_shot_direction.length_squared() < 0.01:
		return

	# Predict player moves perpendicular to shot direction (most common repositioning)
	var perp_left := last_shot_direction.rotated(-PI / 2.0)
	var reposition_pos := last_pos + perp_left * PLAYER_SPEED * 0.8

	# Recency bonus: more recent shots = higher probability
	var recency := 1.0 - (time_since_last_shot / SHOT_REPOSITION_WINDOW)
	var weight := SHOT_REPOSITION_WEIGHT * recency

	hypotheses.append(Hypothesis.new(reposition_pos, HypothesisType.SHOT_REPOSITION, weight))


# ============================================================================
# Private Methods — Style Classification
# ============================================================================


## Classify a single observation based on player's movement relative to enemy.
func _classify_observation(player_pos: Vector2, enemy_pos: Vector2) -> void:
	if not _has_prev_position:
		return

	_style_observations += 1

	var move_dir := (player_pos - _prev_player_position).normalized()
	var to_enemy := (enemy_pos - player_pos).normalized()

	if move_dir.length_squared() < 0.01:
		return  # Player didn't move

	var dot_toward_enemy := move_dir.dot(to_enemy)

	if dot_toward_enemy > 0.5:
		_aggressive_count += 1
	elif dot_toward_enemy < -0.3:
		_cautious_count += 1

	# Check for perpendicular movement (flanking)
	var cross := abs(move_dir.x * to_enemy.y - move_dir.y * to_enemy.x)
	if cross > 0.7:
		_cunning_count += 1

	# Update style classification when enough data (faster threshold)
	if _style_observations >= STYLE_OBSERVATION_THRESHOLD:
		_update_style_classification()


## Update the player style classification based on accumulated observations.
func _update_style_classification() -> void:
	if _style_observations == 0:
		return

	var total := float(_style_observations)
	var aggressive_ratio := float(_aggressive_count) / total
	var cunning_ratio := float(_cunning_count) / total
	var cautious_ratio := float(_cautious_count) / total

	# Classify based on dominant behavior
	if cunning_ratio >= CUNNING_FLANK_RATIO and cunning_ratio >= aggressive_ratio:
		player_style = PlayerStyle.CUNNING
	elif aggressive_ratio >= AGGRESSIVE_RATIO:
		player_style = PlayerStyle.AGGRESSIVE
	elif cautious_ratio > aggressive_ratio:
		player_style = PlayerStyle.CAUTIOUS
	else:
		player_style = PlayerStyle.UNKNOWN


# ============================================================================
# Private Methods — Probability Management
# ============================================================================


## Apply bias based on player style. Uses strong 2x multipliers for dramatic effect.
func _apply_style_bias() -> void:
	if player_style == PlayerStyle.UNKNOWN:
		return

	for h in hypotheses:
		match player_style:
			PlayerStyle.AGGRESSIVE:
				if h.type == HypothesisType.AGGRESSIVE:
					h.probability *= 2.0
				elif h.type == HypothesisType.COVER:
					h.probability *= 0.5
				elif h.type == HypothesisType.STATIONARY:
					h.probability *= 0.6
			PlayerStyle.CAUTIOUS:
				if h.type == HypothesisType.COVER:
					h.probability *= 2.0
				elif h.type == HypothesisType.AGGRESSIVE:
					h.probability *= 0.3
				elif h.type == HypothesisType.SHOT_REPOSITION:
					h.probability *= 1.5
			PlayerStyle.CUNNING:
				if h.type in [HypothesisType.FLANK_LEFT, HypothesisType.FLANK_RIGHT]:
					h.probability *= 2.0
				elif h.type == HypothesisType.SHOT_REPOSITION:
					h.probability *= 1.5
				elif h.type == HypothesisType.STATIONARY:
					h.probability *= 0.3

	# Re-normalize after bias
	_normalize_probabilities()
	_sort_hypotheses()


## Normalize hypothesis probabilities to sum to 1.0.
func _normalize_probabilities() -> void:
	var total := 0.0
	for h in hypotheses:
		total += h.probability
	if total > 0.0:
		for h in hypotheses:
			h.probability /= total


## Sort hypotheses by probability (highest first).
func _sort_hypotheses() -> void:
	hypotheses.sort_custom(func(a: Hypothesis, b: Hypothesis) -> bool:
		return a.probability > b.probability
	)


## Clear all hypotheses.
func _clear_hypotheses() -> void:
	hypotheses.clear()
	has_predictions = false
	hypothesis_age = 0.0


## Debug log hypotheses.
func _log_hypotheses(context: String) -> void:
	print("[Prediction] %s: %d hypotheses (style=%s)" % [context, hypotheses.size(), get_style_name()])
	for h in hypotheses:
		print("  - %s: pos=%s, prob=%.0f%%, checked=%s" % [
			HypothesisType.keys()[h.type],
			h.position,
			h.probability * 100.0,
			h.checked
		])
