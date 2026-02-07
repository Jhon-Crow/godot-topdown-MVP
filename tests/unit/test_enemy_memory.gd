extends GutTest
## Unit tests for EnemyMemory.
##
## Tests the enemy memory system that tracks player position with confidence.
## Covers position updates, confidence decay, behavior modes, and intel sharing.


var memory: EnemyMemory


func before_each() -> void:
	memory = EnemyMemory.new()


func after_each() -> void:
	memory = null


# ============================================================================
# Initialization Tests
# ============================================================================


func test_initial_suspected_position_is_zero() -> void:
	assert_eq(memory.suspected_position, Vector2.ZERO,
		"Initial suspected position should be Vector2.ZERO")


func test_initial_confidence_is_zero() -> void:
	assert_eq(memory.confidence, 0.0,
		"Initial confidence should be 0.0")


func test_initial_last_updated_is_zero() -> void:
	assert_eq(memory.last_updated, 0.0,
		"Initial last_updated should be 0.0")


func test_default_decay_rate_constant() -> void:
	assert_eq(EnemyMemory.DEFAULT_DECAY_RATE, 0.1,
		"Default decay rate should be 0.1")


func test_lost_target_threshold_constant() -> void:
	assert_eq(EnemyMemory.LOST_TARGET_THRESHOLD, 0.05,
		"Lost target threshold should be 0.05")


func test_high_confidence_threshold_constant() -> void:
	assert_eq(EnemyMemory.HIGH_CONFIDENCE_THRESHOLD, 0.8,
		"High confidence threshold should be 0.8")


func test_medium_confidence_threshold_constant() -> void:
	assert_eq(EnemyMemory.MEDIUM_CONFIDENCE_THRESHOLD, 0.5,
		"Medium confidence threshold should be 0.5")


func test_low_confidence_threshold_constant() -> void:
	assert_eq(EnemyMemory.LOW_CONFIDENCE_THRESHOLD, 0.3,
		"Low confidence threshold should be 0.3")


# ============================================================================
# Update Position Tests
# ============================================================================


func test_update_position_sets_position() -> void:
	var pos := Vector2(100, 200)
	memory.update_position(pos, 1.0)

	assert_eq(memory.suspected_position, pos,
		"Position should be updated")


func test_update_position_sets_confidence() -> void:
	memory.update_position(Vector2(100, 200), 0.7)

	assert_eq(memory.confidence, 0.7,
		"Confidence should be updated to 0.7")


func test_update_position_clamps_confidence_max() -> void:
	memory.update_position(Vector2(100, 200), 1.5)

	assert_eq(memory.confidence, 1.0,
		"Confidence should be clamped to 1.0")


func test_update_position_clamps_confidence_min() -> void:
	memory.update_position(Vector2(100, 200), -0.5)

	assert_eq(memory.confidence, 0.0,
		"Confidence should be clamped to 0.0")


func test_update_position_sets_last_updated() -> void:
	memory.update_position(Vector2(100, 200), 1.0)

	assert_true(memory.last_updated > 0,
		"last_updated should be set to current time")


func test_update_position_returns_true_on_success() -> void:
	var result := memory.update_position(Vector2(100, 200), 1.0)

	assert_true(result,
		"Should return true when update succeeds")


func test_update_position_higher_confidence_overwrites() -> void:
	memory.update_position(Vector2(100, 100), 0.5)
	memory.update_position(Vector2(200, 200), 0.8)

	assert_eq(memory.suspected_position, Vector2(200, 200),
		"Higher confidence should overwrite position")
	assert_eq(memory.confidence, 0.8,
		"Higher confidence should update confidence")


func test_update_position_equal_confidence_overwrites() -> void:
	memory.update_position(Vector2(100, 100), 0.5)
	memory.update_position(Vector2(200, 200), 0.5)

	assert_eq(memory.suspected_position, Vector2(200, 200),
		"Equal confidence should overwrite position")


func test_update_position_lower_confidence_rejected() -> void:
	memory.update_position(Vector2(100, 100), 0.8)
	var result := memory.update_position(Vector2(200, 200), 0.5)

	assert_false(result,
		"Lower confidence update should be rejected")
	assert_eq(memory.suspected_position, Vector2(100, 100),
		"Position should not change on rejected update")
	assert_eq(memory.confidence, 0.8,
		"Confidence should not change on rejected update")


# ============================================================================
# Decay Tests
# ============================================================================


func test_decay_reduces_confidence() -> void:
	memory.update_position(Vector2(100, 200), 1.0)
	memory.decay(1.0)  # 1 second of decay

	assert_almost_eq(memory.confidence, 0.9, 0.001,
		"Confidence should decrease by decay_rate * delta")


func test_decay_does_not_go_below_zero() -> void:
	memory.update_position(Vector2(100, 200), 0.05)
	memory.decay(10.0)  # Large decay to go below 0

	assert_eq(memory.confidence, 0.0,
		"Confidence should not go below 0")


func test_decay_with_custom_rate() -> void:
	memory.update_position(Vector2(100, 200), 1.0)
	memory.decay(1.0, 0.2)  # Custom decay rate of 0.2

	assert_almost_eq(memory.confidence, 0.8, 0.001,
		"Confidence should decrease by custom rate")


func test_decay_does_nothing_at_zero() -> void:
	memory.confidence = 0.0
	memory.decay(1.0)

	assert_eq(memory.confidence, 0.0,
		"Decay should not affect zero confidence")


func test_decay_multiple_frames() -> void:
	memory.update_position(Vector2(100, 200), 1.0)

	# Simulate 5 seconds at 60fps
	for i in range(300):
		memory.decay(1.0 / 60.0)

	assert_almost_eq(memory.confidence, 0.5, 0.01,
		"5 seconds of decay should reduce confidence by 0.5")


# ============================================================================
# Has Target Tests
# ============================================================================


func test_has_target_false_at_zero_confidence() -> void:
	assert_false(memory.has_target(),
		"Should not have target at zero confidence")


func test_has_target_false_below_threshold() -> void:
	memory.confidence = 0.04

	assert_false(memory.has_target(),
		"Should not have target below threshold")


func test_has_target_true_at_threshold() -> void:
	memory.confidence = 0.06

	assert_true(memory.has_target(),
		"Should have target above threshold")


func test_has_target_true_at_full_confidence() -> void:
	memory.update_position(Vector2(100, 200), 1.0)

	assert_true(memory.has_target(),
		"Should have target at full confidence")


# ============================================================================
# Confidence Level Tests
# ============================================================================


func test_is_high_confidence_true_at_threshold() -> void:
	memory.confidence = 0.8

	assert_true(memory.is_high_confidence(),
		"Should be high confidence at 0.8")


func test_is_high_confidence_true_above_threshold() -> void:
	memory.confidence = 1.0

	assert_true(memory.is_high_confidence(),
		"Should be high confidence at 1.0")


func test_is_high_confidence_false_below_threshold() -> void:
	memory.confidence = 0.79

	assert_false(memory.is_high_confidence(),
		"Should not be high confidence below 0.8")


func test_is_medium_confidence_true_at_range() -> void:
	memory.confidence = 0.6

	assert_true(memory.is_medium_confidence(),
		"Should be medium confidence at 0.6")


func test_is_medium_confidence_true_at_lower_bound() -> void:
	memory.confidence = 0.5

	assert_true(memory.is_medium_confidence(),
		"Should be medium confidence at 0.5")


func test_is_medium_confidence_false_at_high() -> void:
	memory.confidence = 0.8

	assert_false(memory.is_medium_confidence(),
		"Should not be medium confidence at high threshold")


func test_is_medium_confidence_false_below_range() -> void:
	memory.confidence = 0.4

	assert_false(memory.is_medium_confidence(),
		"Should not be medium confidence below 0.5")


func test_is_low_confidence_true_at_range() -> void:
	memory.confidence = 0.4

	assert_true(memory.is_low_confidence(),
		"Should be low confidence at 0.4")


func test_is_low_confidence_true_at_lower_bound() -> void:
	memory.confidence = 0.3

	assert_true(memory.is_low_confidence(),
		"Should be low confidence at 0.3")


func test_is_low_confidence_false_above_range() -> void:
	memory.confidence = 0.5

	assert_false(memory.is_low_confidence(),
		"Should not be low confidence at 0.5")


func test_is_low_confidence_false_below_range() -> void:
	memory.confidence = 0.2

	assert_false(memory.is_low_confidence(),
		"Should not be low confidence below 0.3")


# ============================================================================
# Behavior Mode Tests
# ============================================================================


func test_behavior_mode_direct_pursuit_at_high_confidence() -> void:
	memory.confidence = 0.9

	assert_eq(memory.get_behavior_mode(), "direct_pursuit",
		"High confidence should trigger direct pursuit")


func test_behavior_mode_cautious_approach_at_medium_confidence() -> void:
	memory.confidence = 0.6

	assert_eq(memory.get_behavior_mode(), "cautious_approach",
		"Medium confidence should trigger cautious approach")


func test_behavior_mode_search_at_low_confidence() -> void:
	memory.confidence = 0.35

	assert_eq(memory.get_behavior_mode(), "search",
		"Low confidence should trigger search")


func test_behavior_mode_patrol_at_very_low_confidence() -> void:
	memory.confidence = 0.1

	assert_eq(memory.get_behavior_mode(), "patrol",
		"Very low confidence should trigger patrol")


func test_behavior_mode_patrol_at_zero_confidence() -> void:
	memory.confidence = 0.0

	assert_eq(memory.get_behavior_mode(), "patrol",
		"Zero confidence should trigger patrol")


# ============================================================================
# Reset Tests
# ============================================================================


func test_reset_clears_position() -> void:
	memory.update_position(Vector2(100, 200), 1.0)
	memory.reset()

	assert_eq(memory.suspected_position, Vector2.ZERO,
		"Position should be reset to zero")


func test_reset_clears_confidence() -> void:
	memory.update_position(Vector2(100, 200), 1.0)
	memory.reset()

	assert_eq(memory.confidence, 0.0,
		"Confidence should be reset to zero")


func test_reset_clears_last_updated() -> void:
	memory.update_position(Vector2(100, 200), 1.0)
	memory.reset()

	assert_eq(memory.last_updated, 0.0,
		"last_updated should be reset to zero")


# ============================================================================
# Duplicate Memory Tests
# ============================================================================


func test_duplicate_memory_copies_position() -> void:
	memory.update_position(Vector2(100, 200), 0.8)
	var copy := memory.duplicate_memory()

	assert_eq(copy.suspected_position, Vector2(100, 200),
		"Copied memory should have same position")


func test_duplicate_memory_copies_confidence() -> void:
	memory.update_position(Vector2(100, 200), 0.8)
	var copy := memory.duplicate_memory()

	assert_eq(copy.confidence, 0.8,
		"Copied memory should have same confidence")


func test_duplicate_memory_is_independent() -> void:
	memory.update_position(Vector2(100, 200), 0.8)
	var copy := memory.duplicate_memory()

	memory.update_position(Vector2(300, 400), 1.0)

	assert_eq(copy.suspected_position, Vector2(100, 200),
		"Copy should be independent of original")
	assert_eq(copy.confidence, 0.8,
		"Copy confidence should be independent")


# ============================================================================
# Receive Intel Tests
# ============================================================================


func test_receive_intel_updates_from_other() -> void:
	var other := EnemyMemory.new()
	other.update_position(Vector2(100, 200), 1.0)

	var result := memory.receive_intel(other)

	assert_true(result,
		"Should successfully receive intel")
	assert_eq(memory.suspected_position, Vector2(100, 200),
		"Position should be updated from other")


func test_receive_intel_reduces_confidence() -> void:
	var other := EnemyMemory.new()
	other.update_position(Vector2(100, 200), 1.0)

	memory.receive_intel(other)

	assert_almost_eq(memory.confidence, 0.9, 0.001,
		"Received confidence should be 90% of source")


func test_receive_intel_with_custom_factor() -> void:
	var other := EnemyMemory.new()
	other.update_position(Vector2(100, 200), 1.0)

	memory.receive_intel(other, 0.5)

	assert_almost_eq(memory.confidence, 0.5, 0.001,
		"Received confidence should use custom factor")


func test_receive_intel_returns_false_for_null() -> void:
	var result := memory.receive_intel(null)

	assert_false(result,
		"Should return false for null other")


func test_receive_intel_returns_false_for_no_target() -> void:
	var other := EnemyMemory.new()  # No target set

	var result := memory.receive_intel(other)

	assert_false(result,
		"Should return false when other has no target")


func test_receive_intel_rejected_if_lower_confidence() -> void:
	memory.update_position(Vector2(50, 50), 0.95)
	var other := EnemyMemory.new()
	other.update_position(Vector2(100, 200), 1.0)  # Will be 0.9 after factor

	var result := memory.receive_intel(other)

	assert_false(result,
		"Should reject if received confidence is lower")
	assert_eq(memory.suspected_position, Vector2(50, 50),
		"Position should remain unchanged")


# ============================================================================
# Time Since Update Tests
# ============================================================================


func test_get_time_since_update_returns_seconds() -> void:
	memory.update_position(Vector2(100, 200), 1.0)
	# Note: This is a timing-sensitive test
	var time := memory.get_time_since_update()

	assert_true(time >= 0.0,
		"Time since update should be non-negative")
	assert_true(time < 1.0,
		"Time since update should be less than 1 second immediately after")


# ============================================================================
# String Representation Tests
# ============================================================================


func test_to_string_no_target() -> void:
	var str_repr := memory._to_string()

	assert_eq(str_repr, "EnemyMemory(no target)",
		"String should indicate no target")


func test_to_string_with_target() -> void:
	memory.suspected_position = Vector2(100, 200)
	memory.confidence = 0.9

	var str_repr := memory._to_string()

	assert_true("EnemyMemory" in str_repr,
		"String should contain class name")
	assert_true("100" in str_repr and "200" in str_repr,
		"String should contain position")
	assert_true("0.90" in str_repr,
		"String should contain confidence")
	assert_true("direct_pursuit" in str_repr,
		"String should contain behavior mode")


# ============================================================================
# Velocity Tracking Tests (Issue #298)
# ============================================================================


func test_initial_velocity_is_zero() -> void:
	assert_eq(memory.last_known_velocity, Vector2.ZERO,
		"Initial velocity should be Vector2.ZERO")


func test_update_velocity_sets_velocity() -> void:
	memory.update_velocity(Vector2(100, 50))

	assert_eq(memory.last_known_velocity, Vector2(100, 50),
		"Velocity should be updated")


func test_update_velocity_with_zero() -> void:
	memory.update_velocity(Vector2(100, 50))
	memory.update_velocity(Vector2.ZERO)

	assert_eq(memory.last_known_velocity, Vector2.ZERO,
		"Velocity should be updatable to zero")


func test_update_velocity_negative() -> void:
	memory.update_velocity(Vector2(-200, -150))

	assert_eq(memory.last_known_velocity, Vector2(-200, -150),
		"Should handle negative velocity")


func test_reset_clears_velocity() -> void:
	memory.update_velocity(Vector2(100, 50))
	memory.reset()

	assert_eq(memory.last_known_velocity, Vector2.ZERO,
		"Reset should clear velocity")


func test_duplicate_memory_copies_velocity() -> void:
	memory.update_velocity(Vector2(100, 50))
	var copy := memory.duplicate_memory()

	assert_eq(copy.last_known_velocity, Vector2(100, 50),
		"Duplicated memory should copy velocity")


func test_duplicate_memory_velocity_is_independent() -> void:
	memory.update_velocity(Vector2(100, 50))
	var copy := memory.duplicate_memory()

	memory.update_velocity(Vector2(999, 999))

	assert_eq(copy.last_known_velocity, Vector2(100, 50),
		"Copy velocity should be independent of original")


# ============================================================================
# Shot Direction Tracking Tests (Issue #298)
# ============================================================================


func test_initial_shot_direction_is_zero() -> void:
	assert_eq(memory.last_shot_direction, Vector2.ZERO,
		"Initial shot direction should be Vector2.ZERO")


func test_initial_has_shot_direction_is_false() -> void:
	assert_false(memory.has_shot_direction,
		"Initial has_shot_direction should be false")


func test_update_shot_direction_sets_direction() -> void:
	memory.update_shot_direction(Vector2(1, 0))

	assert_eq(memory.last_shot_direction, Vector2(1, 0),
		"Shot direction should be set")
	assert_true(memory.has_shot_direction,
		"has_shot_direction should be true")


func test_update_shot_direction_normalizes() -> void:
	memory.update_shot_direction(Vector2(10, 0))

	assert_almost_eq(memory.last_shot_direction.length(), 1.0, 0.001,
		"Shot direction should be normalized")


func test_update_shot_direction_diagonal() -> void:
	memory.update_shot_direction(Vector2(5, 5))

	assert_almost_eq(memory.last_shot_direction.length(), 1.0, 0.001,
		"Diagonal shot direction should be normalized")
	assert_true(memory.has_shot_direction,
		"has_shot_direction should be true for diagonal")


func test_update_shot_direction_rejects_zero() -> void:
	memory.update_shot_direction(Vector2.ZERO)

	assert_false(memory.has_shot_direction,
		"Zero direction should not set has_shot_direction")


func test_update_shot_direction_rejects_near_zero() -> void:
	memory.update_shot_direction(Vector2(0.01, 0.01))

	# length_squared of (0.01, 0.01) = 0.0002 which is < 0.01
	assert_false(memory.has_shot_direction,
		"Near-zero direction should not set has_shot_direction")


func test_reset_clears_shot_direction() -> void:
	memory.update_shot_direction(Vector2(1, 0))
	memory.reset()

	assert_eq(memory.last_shot_direction, Vector2.ZERO,
		"Reset should clear shot direction")
	assert_false(memory.has_shot_direction,
		"Reset should clear has_shot_direction")


func test_duplicate_memory_copies_shot_direction() -> void:
	memory.update_shot_direction(Vector2(0, 1))
	var copy := memory.duplicate_memory()

	assert_eq(copy.last_shot_direction, memory.last_shot_direction,
		"Duplicated memory should copy shot direction")
	assert_eq(copy.has_shot_direction, true,
		"Duplicated memory should copy has_shot_direction")


func test_duplicate_memory_shot_direction_is_independent() -> void:
	memory.update_shot_direction(Vector2(1, 0))
	var copy := memory.duplicate_memory()

	memory.update_shot_direction(Vector2(0, 1))

	assert_eq(copy.last_shot_direction.x, 1.0,
		"Copy shot direction should be independent of original")


func test_to_string_includes_velocity() -> void:
	memory.suspected_position = Vector2(100, 200)
	memory.confidence = 0.9
	memory.update_velocity(Vector2(350, 0))

	var str_repr := memory._to_string()

	assert_true("vel=" in str_repr,
		"String should contain velocity info")
