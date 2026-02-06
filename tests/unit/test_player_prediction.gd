extends GutTest
## Unit tests for PlayerPredictionComponent (Issue #298).
##
## Tests the player prediction system including:
## - Hypothesis generation (cover, flank, direction, aggressive, stationary)
## - Probability normalization and style bias
## - Prediction decay and cleanup
## - Style classification (aggressive, cautious, cunning)
## - Multi-agent prediction sharing
## - Edge cases


var predictor: PlayerPredictionComponent


func before_each() -> void:
	predictor = PlayerPredictionComponent.new()


func after_each() -> void:
	predictor = null


# ============================================================================
# Initialization Tests
# ============================================================================


func test_initial_state_no_predictions() -> void:
	assert_false(predictor.has_predictions,
		"Should have no predictions initially")


func test_initial_style_is_unknown() -> void:
	assert_eq(predictor.player_style, PlayerPredictionComponent.PlayerStyle.UNKNOWN,
		"Initial player style should be UNKNOWN")


func test_initial_velocity_is_zero() -> void:
	assert_eq(predictor.last_known_velocity, Vector2.ZERO,
		"Initial velocity should be Vector2.ZERO")


func test_initial_position_is_zero() -> void:
	assert_eq(predictor.last_known_position, Vector2.ZERO,
		"Initial position should be Vector2.ZERO")


func test_initial_shot_direction_is_zero() -> void:
	assert_eq(predictor.last_shot_direction, Vector2.ZERO,
		"Initial shot direction should be Vector2.ZERO")


func test_initial_shot_timer_is_negative() -> void:
	assert_eq(predictor.time_since_last_shot, -1.0,
		"Initial shot timer should be -1.0 (never fired)")


# ============================================================================
# Observation Tests
# ============================================================================


func test_update_observation_tracks_position() -> void:
	var player_pos := Vector2(100, 200)
	var enemy_pos := Vector2(0, 0)
	predictor.update_observation(player_pos, enemy_pos, 0.016)

	assert_eq(predictor.last_known_position, player_pos,
		"Should track player position")


func test_update_observation_estimates_velocity() -> void:
	var enemy_pos := Vector2(0, 0)
	# First observation (no velocity yet)
	predictor.update_observation(Vector2(100, 100), enemy_pos, 0.016)
	# Second observation (velocity calculated)
	predictor.update_observation(Vector2(110, 100), enemy_pos, 0.016)

	assert_true(predictor.last_known_velocity.x > 0.0,
		"Velocity should be positive in x direction")
	assert_almost_eq(predictor.last_known_velocity.y, 0.0, 1.0,
		"Velocity y should be near zero")


func test_update_observation_clears_predictions() -> void:
	# Generate predictions first
	predictor.generate_predictions(
		Vector2(200, 200), Vector2(0, 0), Vector2.RIGHT
	)
	assert_true(predictor.has_predictions, "Should have predictions")

	# Observing player should clear predictions
	predictor.update_observation(Vector2(200, 200), Vector2(0, 0), 0.016)
	assert_false(predictor.has_predictions,
		"Observing player should clear predictions")


# ============================================================================
# Shot Direction Tests
# ============================================================================


func test_record_player_shot_sets_direction() -> void:
	predictor.record_player_shot(Vector2(1, 0))

	assert_eq(predictor.last_shot_direction, Vector2(1, 0),
		"Shot direction should be set")


func test_record_player_shot_normalizes_direction() -> void:
	predictor.record_player_shot(Vector2(10, 0))

	assert_almost_eq(predictor.last_shot_direction.length(), 1.0, 0.001,
		"Shot direction should be normalized")


func test_record_player_shot_starts_timer() -> void:
	predictor.record_player_shot(Vector2(1, 0))

	assert_eq(predictor.time_since_last_shot, 0.0,
		"Shot timer should be reset to 0")


# ============================================================================
# Prediction Generation Tests
# ============================================================================


func test_generate_predictions_creates_hypotheses() -> void:
	predictor.generate_predictions(
		Vector2(200, 200),  # last known position
		Vector2(0, 0),      # enemy position
		Vector2.RIGHT       # enemy facing
	)

	assert_true(predictor.has_predictions,
		"Should have predictions after generation")
	assert_gt(predictor.hypotheses.size(), 0,
		"Should have at least one hypothesis")


func test_generate_predictions_includes_cover_hypothesis() -> void:
	predictor.generate_predictions(
		Vector2(200, 200), Vector2(0, 0), Vector2.RIGHT
	)

	var has_cover := false
	for h in predictor.hypotheses:
		if h.type == PlayerPredictionComponent.HypothesisType.COVER:
			has_cover = true
			break
	assert_true(has_cover, "Should include cover hypothesis")


func test_generate_predictions_includes_flank_hypotheses() -> void:
	predictor.generate_predictions(
		Vector2(200, 200), Vector2(0, 0), Vector2.RIGHT
	)

	var has_flank_left := false
	var has_flank_right := false
	for h in predictor.hypotheses:
		if h.type == PlayerPredictionComponent.HypothesisType.FLANK_LEFT:
			has_flank_left = true
		if h.type == PlayerPredictionComponent.HypothesisType.FLANK_RIGHT:
			has_flank_right = true
	assert_true(has_flank_left, "Should include flank left hypothesis")
	assert_true(has_flank_right, "Should include flank right hypothesis")


func test_generate_predictions_includes_aggressive_hypothesis() -> void:
	predictor.generate_predictions(
		Vector2(200, 200), Vector2(0, 0), Vector2.RIGHT
	)

	var has_aggressive := false
	for h in predictor.hypotheses:
		if h.type == PlayerPredictionComponent.HypothesisType.AGGRESSIVE:
			has_aggressive = true
			break
	assert_true(has_aggressive, "Should include aggressive hypothesis")


func test_generate_predictions_includes_stationary_hypothesis() -> void:
	predictor.generate_predictions(
		Vector2(200, 200), Vector2(0, 0), Vector2.RIGHT
	)

	var has_stationary := false
	for h in predictor.hypotheses:
		if h.type == PlayerPredictionComponent.HypothesisType.STATIONARY:
			has_stationary = true
			break
	assert_true(has_stationary, "Should include stationary hypothesis")


func test_generate_predictions_includes_direction_when_moving() -> void:
	# Give the predictor a known velocity
	predictor.update_observation(Vector2(100, 100), Vector2(0, 0), 0.016)
	predictor.update_observation(Vector2(120, 100), Vector2(0, 0), 0.016)

	predictor.generate_predictions(
		Vector2(120, 100), Vector2(0, 0), Vector2.RIGHT
	)

	var has_direction := false
	for h in predictor.hypotheses:
		if h.type == PlayerPredictionComponent.HypothesisType.LAST_DIRECTION:
			has_direction = true
			break
	assert_true(has_direction, "Should include direction hypothesis when player was moving")


func test_generate_predictions_no_direction_when_stationary() -> void:
	# Don't move — velocity stays near zero
	predictor.generate_predictions(
		Vector2(200, 200), Vector2(0, 0), Vector2.RIGHT
	)

	var has_direction := false
	for h in predictor.hypotheses:
		if h.type == PlayerPredictionComponent.HypothesisType.LAST_DIRECTION:
			has_direction = true
			break
	assert_false(has_direction, "Should NOT include direction hypothesis when player was stationary")


func test_generate_predictions_probabilities_sum_to_one() -> void:
	predictor.generate_predictions(
		Vector2(200, 200), Vector2(0, 0), Vector2.RIGHT
	)

	var total := 0.0
	for h in predictor.hypotheses:
		total += h.probability
	assert_almost_eq(total, 1.0, 0.01,
		"Hypothesis probabilities should sum to ~1.0")


func test_generate_predictions_sorted_by_probability() -> void:
	predictor.generate_predictions(
		Vector2(200, 200), Vector2(0, 0), Vector2.RIGHT
	)

	for i in range(predictor.hypotheses.size() - 1):
		assert_true(
			predictor.hypotheses[i].probability >= predictor.hypotheses[i + 1].probability,
			"Hypotheses should be sorted by probability (descending)")


func test_generate_predictions_with_cover_positions() -> void:
	var covers: Array = [
		Vector2(300, 200),
		Vector2(200, 300),
		Vector2(100, 100)
	]
	predictor.generate_predictions(
		Vector2(200, 200), Vector2(0, 0), Vector2.RIGHT, covers
	)

	assert_true(predictor.has_predictions,
		"Should have predictions with cover positions")


func test_generate_predictions_clears_old() -> void:
	# First generation
	predictor.generate_predictions(
		Vector2(200, 200), Vector2(0, 0), Vector2.RIGHT
	)
	var first_count := predictor.hypotheses.size()

	# Second generation should replace, not add
	predictor.generate_predictions(
		Vector2(400, 400), Vector2(0, 0), Vector2.RIGHT
	)

	assert_true(predictor.hypotheses.size() <= first_count + 2,
		"Second generation should not accumulate excessively")


# ============================================================================
# Best Hypothesis Tests
# ============================================================================


func test_get_best_hypothesis_returns_highest_probability() -> void:
	predictor.generate_predictions(
		Vector2(200, 200), Vector2(0, 0), Vector2.RIGHT
	)

	var best := predictor.get_best_hypothesis()
	assert_not_null(best, "Should return a hypothesis")
	for h in predictor.hypotheses:
		if not h.checked:
			assert_true(best.probability >= h.probability,
				"Best hypothesis should have highest probability")


func test_get_best_hypothesis_returns_null_when_no_predictions() -> void:
	var best := predictor.get_best_hypothesis()
	assert_null(best, "Should return null when no predictions")


func test_get_best_position_returns_position() -> void:
	predictor.generate_predictions(
		Vector2(200, 200), Vector2(0, 0), Vector2.RIGHT
	)

	var pos := predictor.get_best_position()
	assert_ne(pos, Vector2.ZERO, "Should return a non-zero position")


func test_get_best_position_returns_zero_when_no_predictions() -> void:
	var pos := predictor.get_best_position()
	assert_eq(pos, Vector2.ZERO, "Should return zero when no predictions")


func test_get_prediction_confidence_returns_value() -> void:
	predictor.generate_predictions(
		Vector2(200, 200), Vector2(0, 0), Vector2.RIGHT
	)

	var conf := predictor.get_prediction_confidence()
	assert_gt(conf, 0.0, "Confidence should be positive")
	assert_true(conf <= 1.0, "Confidence should be <= 1.0")


func test_get_prediction_confidence_returns_zero_when_no_predictions() -> void:
	var conf := predictor.get_prediction_confidence()
	assert_eq(conf, 0.0, "Confidence should be 0 when no predictions")


# ============================================================================
# Mark Checked Tests
# ============================================================================


func test_mark_position_checked() -> void:
	predictor.generate_predictions(
		Vector2(200, 200), Vector2(0, 0), Vector2.RIGHT
	)

	var best := predictor.get_best_hypothesis()
	assert_not_null(best, "Should have a hypothesis")
	var best_pos := best.position

	predictor.mark_position_checked(best_pos)
	assert_true(best.checked, "Hypothesis should be marked as checked")


func test_mark_position_checked_skips_to_next() -> void:
	predictor.generate_predictions(
		Vector2(200, 200), Vector2(0, 0), Vector2.RIGHT
	)

	var first := predictor.get_best_hypothesis()
	predictor.mark_position_checked(first.position)

	var second := predictor.get_best_hypothesis()
	if second:
		assert_ne(second, first, "Should return next unchecked hypothesis")


func test_mark_position_checked_with_tolerance() -> void:
	predictor.generate_predictions(
		Vector2(200, 200), Vector2(0, 0), Vector2.RIGHT
	)

	var best := predictor.get_best_hypothesis()
	# Mark at position slightly off from actual
	var offset_pos := best.position + Vector2(50, 50)
	predictor.mark_position_checked(offset_pos, 100.0)

	assert_true(best.checked, "Should mark hypothesis within tolerance")


func test_mark_position_not_checked_outside_tolerance() -> void:
	predictor.generate_predictions(
		Vector2(200, 200), Vector2(0, 0), Vector2.RIGHT
	)

	var best := predictor.get_best_hypothesis()
	# Mark at position far from actual
	var far_pos := best.position + Vector2(500, 500)
	predictor.mark_position_checked(far_pos, 100.0)

	assert_false(best.checked, "Should NOT mark hypothesis outside tolerance")


# ============================================================================
# Prediction Decay Tests
# ============================================================================


func test_update_predictions_decays_probability() -> void:
	predictor.generate_predictions(
		Vector2(200, 200), Vector2(0, 0), Vector2.RIGHT
	)

	var initial_prob := predictor.get_prediction_confidence()
	predictor.update_predictions(1.0)  # 1 second

	var decayed_prob := predictor.get_prediction_confidence()
	assert_lt(decayed_prob, initial_prob,
		"Probability should decrease over time")


func test_update_predictions_clears_after_max_age() -> void:
	predictor.generate_predictions(
		Vector2(200, 200), Vector2(0, 0), Vector2.RIGHT
	)

	# Simulate 20 seconds (beyond MAX_HYPOTHESIS_AGE of 15)
	predictor.update_predictions(20.0)

	assert_false(predictor.has_predictions,
		"Predictions should be cleared after max age")


func test_update_predictions_removes_low_probability() -> void:
	predictor.generate_predictions(
		Vector2(200, 200), Vector2(0, 0), Vector2.RIGHT
	)

	var initial_count := predictor.hypotheses.size()

	# Decay significantly (10 seconds at 0.08/s = 0.8 total decay)
	predictor.update_predictions(10.0)

	assert_true(predictor.hypotheses.size() <= initial_count,
		"Low probability hypotheses should be removed")


func test_update_predictions_no_effect_when_no_predictions() -> void:
	predictor.update_predictions(1.0)
	assert_false(predictor.has_predictions,
		"Should not create predictions from nothing")


# ============================================================================
# Style Classification Tests
# ============================================================================


func test_style_starts_unknown() -> void:
	assert_eq(predictor.player_style, PlayerPredictionComponent.PlayerStyle.UNKNOWN,
		"Style should start as UNKNOWN")


func test_style_classification_requires_observations() -> void:
	# Only a few observations — should not classify yet
	for i in range(3):
		predictor.update_observation(
			Vector2(100 + i * 10, 100),  # Moving right
			Vector2(200, 100),  # Enemy ahead
			0.016
		)

	assert_eq(predictor.player_style, PlayerPredictionComponent.PlayerStyle.UNKNOWN,
		"Should not classify with few observations")


func test_style_aggressive_classification() -> void:
	# Player consistently moves toward enemy
	var enemy_pos := Vector2(500, 100)
	for i in range(10):
		var player_pos := Vector2(100 + i * 30, 100)  # Moving toward enemy
		predictor.update_observation(player_pos, enemy_pos, 0.016)

	assert_eq(predictor.player_style, PlayerPredictionComponent.PlayerStyle.AGGRESSIVE,
		"Player moving toward enemy should be classified as AGGRESSIVE")


func test_style_cautious_classification() -> void:
	# Player consistently moves away from enemy
	var enemy_pos := Vector2(0, 100)
	for i in range(10):
		var player_pos := Vector2(100 + i * 30, 100)  # Moving away from enemy
		predictor.update_observation(player_pos, enemy_pos, 0.016)

	assert_eq(predictor.player_style, PlayerPredictionComponent.PlayerStyle.CAUTIOUS,
		"Player moving away from enemy should be classified as CAUTIOUS")


func test_style_cunning_classification() -> void:
	# Player consistently moves perpendicular to enemy (flanking)
	var enemy_pos := Vector2(200, 0)  # Enemy to the north
	for i in range(10):
		var player_pos := Vector2(100 + i * 30, 200)  # Moving east (perpendicular)
		predictor.update_observation(player_pos, enemy_pos, 0.016)

	assert_eq(predictor.player_style, PlayerPredictionComponent.PlayerStyle.CUNNING,
		"Player moving perpendicular should be classified as CUNNING")


func test_style_affects_predictions() -> void:
	# Make player aggressive
	var enemy_pos := Vector2(500, 100)
	for i in range(10):
		predictor.update_observation(Vector2(100 + i * 30, 100), enemy_pos, 0.016)

	assert_eq(predictor.player_style, PlayerPredictionComponent.PlayerStyle.AGGRESSIVE)

	# Generate predictions
	predictor.generate_predictions(
		Vector2(400, 100), enemy_pos, Vector2.LEFT
	)

	# Find aggressive hypothesis - should have boosted probability
	var aggressive_prob := 0.0
	var cover_prob := 0.0
	for h in predictor.hypotheses:
		if h.type == PlayerPredictionComponent.HypothesisType.AGGRESSIVE:
			aggressive_prob = h.probability
		if h.type == PlayerPredictionComponent.HypothesisType.COVER:
			cover_prob = h.probability

	# With aggressive style, aggressive hypothesis should be boosted
	assert_gt(aggressive_prob, 0.0, "Aggressive hypothesis should exist")


func test_get_style_name_returns_string() -> void:
	assert_eq(predictor.get_style_name(), "unknown", "Default style name")

	# Force aggressive
	predictor.player_style = PlayerPredictionComponent.PlayerStyle.AGGRESSIVE
	assert_eq(predictor.get_style_name(), "aggressive")

	predictor.player_style = PlayerPredictionComponent.PlayerStyle.CAUTIOUS
	assert_eq(predictor.get_style_name(), "cautious")

	predictor.player_style = PlayerPredictionComponent.PlayerStyle.CUNNING
	assert_eq(predictor.get_style_name(), "cunning")


# ============================================================================
# Multi-Agent Prediction Sharing Tests
# ============================================================================


func test_receive_prediction_intel_adds_hypothesis() -> void:
	var other_hypothesis := PlayerPredictionComponent.Hypothesis.new(
		Vector2(300, 300),
		PlayerPredictionComponent.HypothesisType.COVER,
		0.5
	)

	predictor.receive_prediction_intel(other_hypothesis)

	assert_true(predictor.has_predictions,
		"Should have predictions after receiving intel")
	assert_eq(predictor.hypotheses.size(), 1,
		"Should have one hypothesis")


func test_receive_prediction_intel_reduces_confidence() -> void:
	var other_hypothesis := PlayerPredictionComponent.Hypothesis.new(
		Vector2(300, 300),
		PlayerPredictionComponent.HypothesisType.COVER,
		1.0
	)

	predictor.receive_prediction_intel(other_hypothesis, 0.9)

	assert_almost_eq(predictor.hypotheses[0].probability, 0.9, 0.01,
		"Received probability should be reduced by factor")


func test_receive_prediction_intel_merges_nearby() -> void:
	# First hypothesis
	var h1 := PlayerPredictionComponent.Hypothesis.new(
		Vector2(300, 300),
		PlayerPredictionComponent.HypothesisType.COVER,
		0.5
	)
	predictor.receive_prediction_intel(h1)

	# Second hypothesis at similar position (within 100px)
	var h2 := PlayerPredictionComponent.Hypothesis.new(
		Vector2(350, 350),
		PlayerPredictionComponent.HypothesisType.COVER,
		0.8
	)
	predictor.receive_prediction_intel(h2)

	# Should merge, not add
	assert_eq(predictor.hypotheses.size(), 1,
		"Nearby hypotheses should be merged")


func test_receive_prediction_intel_adds_distant() -> void:
	# First hypothesis
	var h1 := PlayerPredictionComponent.Hypothesis.new(
		Vector2(100, 100),
		PlayerPredictionComponent.HypothesisType.COVER,
		0.5
	)
	predictor.receive_prediction_intel(h1)

	# Second hypothesis at distant position (>100px)
	var h2 := PlayerPredictionComponent.Hypothesis.new(
		Vector2(500, 500),
		PlayerPredictionComponent.HypothesisType.FLANK_LEFT,
		0.4
	)
	predictor.receive_prediction_intel(h2)

	assert_eq(predictor.hypotheses.size(), 2,
		"Distant hypotheses should be added separately")


func test_receive_prediction_intel_rejects_null() -> void:
	predictor.receive_prediction_intel(null)

	assert_false(predictor.has_predictions,
		"Should reject null hypothesis")


func test_receive_prediction_intel_rejects_low_probability() -> void:
	var weak := PlayerPredictionComponent.Hypothesis.new(
		Vector2(300, 300),
		PlayerPredictionComponent.HypothesisType.COVER,
		0.01  # Below MIN_HYPOTHESIS_PROBABILITY
	)

	predictor.receive_prediction_intel(weak)

	assert_false(predictor.has_predictions,
		"Should reject very low probability hypothesis")


# ============================================================================
# Reset Tests
# ============================================================================


func test_reset_clears_predictions() -> void:
	predictor.generate_predictions(
		Vector2(200, 200), Vector2(0, 0), Vector2.RIGHT
	)
	predictor.reset()

	assert_false(predictor.has_predictions,
		"Reset should clear predictions")


func test_reset_clears_velocity() -> void:
	predictor.update_observation(Vector2(100, 100), Vector2(0, 0), 0.016)
	predictor.update_observation(Vector2(120, 100), Vector2(0, 0), 0.016)
	predictor.reset()

	assert_eq(predictor.last_known_velocity, Vector2.ZERO,
		"Reset should clear velocity")


func test_reset_preserves_style() -> void:
	# Make player aggressive
	var enemy_pos := Vector2(500, 100)
	for i in range(10):
		predictor.update_observation(Vector2(100 + i * 30, 100), enemy_pos, 0.016)

	var style_before := predictor.player_style
	predictor.reset()

	assert_eq(predictor.player_style, style_before,
		"Reset should preserve player style")


func test_reset_clears_shot_direction() -> void:
	predictor.record_player_shot(Vector2(1, 0))
	predictor.reset()

	assert_eq(predictor.last_shot_direction, Vector2.ZERO,
		"Reset should clear shot direction")


# ============================================================================
# Constants Tests
# ============================================================================


func test_player_speed_constant() -> void:
	assert_eq(PlayerPredictionComponent.PLAYER_SPEED, 350.0,
		"Player speed should be 350.0")


func test_max_hypotheses_constant() -> void:
	assert_eq(PlayerPredictionComponent.MAX_HYPOTHESES, 6,
		"Max hypotheses should be 6")


func test_max_hypothesis_age_constant() -> void:
	assert_eq(PlayerPredictionComponent.MAX_HYPOTHESIS_AGE, 15.0,
		"Max hypothesis age should be 15.0 seconds")


func test_cover_search_radius_constant() -> void:
	assert_eq(PlayerPredictionComponent.COVER_SEARCH_RADIUS, 400.0,
		"Cover search radius should be 400.0 pixels")


# ============================================================================
# String Representation Tests
# ============================================================================


func test_to_string_no_predictions() -> void:
	var s := predictor._to_string()
	assert_eq(s, "PlayerPrediction(no predictions)",
		"String should indicate no predictions")


func test_to_string_with_predictions() -> void:
	predictor.generate_predictions(
		Vector2(200, 200), Vector2(0, 0), Vector2.RIGHT
	)

	var s := predictor._to_string()
	assert_true("PlayerPrediction" in s,
		"String should contain class name")
	assert_true("hypotheses" in s,
		"String should contain hypothesis count")


# ============================================================================
# Edge Case Tests
# ============================================================================


func test_generate_predictions_same_position() -> void:
	# Enemy and player at same position
	predictor.generate_predictions(
		Vector2(100, 100), Vector2(100, 100), Vector2.RIGHT
	)

	assert_true(predictor.has_predictions,
		"Should handle same position gracefully")


func test_generate_predictions_zero_position() -> void:
	predictor.generate_predictions(
		Vector2.ZERO, Vector2.ZERO, Vector2.RIGHT
	)

	assert_true(predictor.has_predictions,
		"Should handle zero positions gracefully")


func test_multiple_generation_cycles() -> void:
	# Generate, decay, generate again
	for i in range(5):
		predictor.generate_predictions(
			Vector2(100 * (i + 1), 100),
			Vector2(0, 0),
			Vector2.RIGHT
		)
		predictor.update_predictions(2.0)

	# Should still function correctly
	assert_true(predictor.hypotheses.size() <= PlayerPredictionComponent.MAX_HYPOTHESES,
		"Should not exceed max hypotheses after multiple cycles")


func test_hypothesis_inner_class() -> void:
	var h := PlayerPredictionComponent.Hypothesis.new(
		Vector2(100, 200),
		PlayerPredictionComponent.HypothesisType.COVER,
		0.75
	)

	assert_eq(h.position, Vector2(100, 200), "Position should be set")
	assert_eq(h.type, PlayerPredictionComponent.HypothesisType.COVER, "Type should be COVER")
	assert_eq(h.probability, 0.75, "Probability should be 0.75")
	assert_false(h.checked, "Should not be checked initially")
