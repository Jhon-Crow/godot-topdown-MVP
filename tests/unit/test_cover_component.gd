extends GutTest
## Unit tests for CoverComponent.
##
## Tests the cover detection and evaluation functionality including
## cover position finding, quality evaluation, pursuit cover, and
## protection checks.


# ============================================================================
# Mock CoverComponent for Logic Tests
# ============================================================================


class MockCoverComponent:
	## Number of raycasts for cover detection.
	var cover_check_count: int = 16

	## Distance to check for cover.
	var cover_check_distance: float = 300.0

	## Minimum distance from current position for valid cover.
	var min_cover_distance: float = 50.0

	## Minimum distance progress required for pursuit cover (fraction).
	var pursuit_min_progress_fraction: float = 0.10

	## Penalty for cover on same obstacle.
	var same_obstacle_penalty: float = 4.0

	## Parent position (simulated).
	var _parent_position: Vector2 = Vector2.ZERO

	## Current cover position.
	var _cover_position: Vector2 = Vector2.ZERO

	## Whether we have valid cover.
	var _has_valid_cover: bool = false

	## The obstacle of current cover (for penalty calculation).
	var _current_cover_obstacle: Object = null

	## Target (usually the player) to hide from.
	var _threat_position: Vector2 = Vector2.ZERO

	## Mock cover spots for testing.
	var _available_cover_spots: Array = []

	## Set parent position.
	func set_parent_position(pos: Vector2) -> void:
		_parent_position = pos

	## Set the threat position to hide from.
	func set_threat_position(pos: Vector2) -> void:
		_threat_position = pos

	## Add a mock cover spot for testing.
	func add_cover_spot(position: Vector2, obstacle: Object = null,
						is_protected: bool = true) -> void:
		_available_cover_spots.append({
			"position": position,
			"obstacle": obstacle,
			"is_protected": is_protected
		})

	## Clear mock cover spots.
	func clear_cover_spots() -> void:
		_available_cover_spots.clear()

	## Find the best cover position.
	func find_cover() -> void:
		var best_cover: Vector2 = Vector2.ZERO
		var best_score: float = -INF
		var best_obstacle: Object = null

		for spot in _available_cover_spots:
			var cover_pos: Vector2 = spot["position"]
			var obstacle: Object = spot["obstacle"]

			var score := _evaluate_cover(cover_pos, obstacle, spot["is_protected"])

			if score > best_score:
				best_score = score
				best_cover = cover_pos
				best_obstacle = obstacle

		if best_score > 0.0:
			_cover_position = best_cover
			_has_valid_cover = true
			_current_cover_obstacle = best_obstacle
		else:
			_has_valid_cover = false

	## Find cover that moves closer to a target position.
	func find_pursuit_cover(target_pos: Vector2) -> Vector2:
		var current_distance := _parent_position.distance_to(target_pos)
		var best_cover: Vector2 = Vector2.ZERO
		var best_score: float = -INF
		var best_obstacle: Object = null

		for spot in _available_cover_spots:
			var cover_pos: Vector2 = spot["position"]
			var obstacle: Object = spot["obstacle"]

			# Check distance progress
			var new_distance := cover_pos.distance_to(target_pos)
			var progress := current_distance - new_distance
			var progress_fraction := 0.0
			if current_distance > 0:
				progress_fraction = progress / current_distance

			if progress_fraction < pursuit_min_progress_fraction:
				continue

			var score := _evaluate_pursuit_cover(cover_pos, obstacle, target_pos,
				spot["is_protected"])

			if score > best_score:
				best_score = score
				best_cover = cover_pos
				best_obstacle = obstacle

		if best_score > 0.0:
			_current_cover_obstacle = best_obstacle
			return best_cover

		return Vector2.ZERO

	## Evaluate cover quality for defensive purposes.
	func _evaluate_cover(cover_pos: Vector2, obstacle: Object,
						is_protected: bool) -> float:
		var score := 0.0

		# Distance from current position (prefer closer cover)
		var distance := _parent_position.distance_to(cover_pos)
		if distance < min_cover_distance:
			return -INF  # Too close

		score -= distance * 0.01  # Small penalty for distance

		# Check if cover blocks line of sight to threat
		if is_protected:
			score += 100.0  # Major bonus for actual cover

		# Penalty for same obstacle as current cover
		if obstacle == _current_cover_obstacle and obstacle != null:
			score -= same_obstacle_penalty

		return score

	## Evaluate cover for pursuit (moving toward target).
	func _evaluate_pursuit_cover(cover_pos: Vector2, obstacle: Object,
								target_pos: Vector2, is_protected: bool) -> float:
		var score := 0.0

		# Distance to target (prefer cover closer to target)
		var distance_to_target := cover_pos.distance_to(target_pos)
		score -= distance_to_target * 0.1

		# Check if provides cover from threat
		if is_protected:
			score += 50.0

		# Penalty for same obstacle
		if obstacle == _current_cover_obstacle and obstacle != null:
			score -= same_obstacle_penalty

		return score

	## Check if currently in valid cover.
	func is_in_cover(tolerance: float = 30.0) -> bool:
		if not _has_valid_cover:
			return false

		return _parent_position.distance_to(_cover_position) <= tolerance

	## Get current cover position.
	func get_cover_position() -> Vector2:
		return _cover_position

	## Check if has valid cover.
	func has_valid_cover() -> bool:
		return _has_valid_cover

	## Clear current cover.
	func clear_cover() -> void:
		_has_valid_cover = false
		_cover_position = Vector2.ZERO
		_current_cover_obstacle = null


var cover: MockCoverComponent


func before_each() -> void:
	cover = MockCoverComponent.new()


func after_each() -> void:
	cover = null


# ============================================================================
# Default Configuration Tests
# ============================================================================


func test_default_cover_check_count() -> void:
	assert_eq(cover.cover_check_count, 16,
		"Default cover check count should be 16")


func test_default_cover_check_distance() -> void:
	assert_eq(cover.cover_check_distance, 300.0,
		"Default cover check distance should be 300")


func test_default_min_cover_distance() -> void:
	assert_eq(cover.min_cover_distance, 50.0,
		"Default minimum cover distance should be 50")


func test_default_pursuit_min_progress_fraction() -> void:
	assert_eq(cover.pursuit_min_progress_fraction, 0.10,
		"Default pursuit min progress fraction should be 0.10")


func test_default_same_obstacle_penalty() -> void:
	assert_eq(cover.same_obstacle_penalty, 4.0,
		"Default same obstacle penalty should be 4.0")


# ============================================================================
# Initial State Tests
# ============================================================================


func test_no_valid_cover_initially() -> void:
	assert_false(cover.has_valid_cover(),
		"Should not have valid cover initially")


func test_cover_position_zero_initially() -> void:
	assert_eq(cover.get_cover_position(), Vector2.ZERO,
		"Cover position should be zero initially")


func test_not_in_cover_initially() -> void:
	assert_false(cover.is_in_cover(),
		"Should not be in cover initially")


# ============================================================================
# Find Cover Tests
# ============================================================================


func test_find_cover_with_valid_spot() -> void:
	cover.set_parent_position(Vector2.ZERO)
	cover.add_cover_spot(Vector2(100, 0), null, true)
	cover.find_cover()

	assert_true(cover.has_valid_cover())


func test_find_cover_sets_position() -> void:
	cover.set_parent_position(Vector2.ZERO)
	cover.add_cover_spot(Vector2(100, 0), null, true)
	cover.find_cover()

	assert_eq(cover.get_cover_position(), Vector2(100, 0))


func test_find_cover_no_spots_available() -> void:
	cover.set_parent_position(Vector2.ZERO)
	cover.find_cover()

	assert_false(cover.has_valid_cover())


func test_find_cover_rejects_too_close_spots() -> void:
	cover.set_parent_position(Vector2.ZERO)
	cover.add_cover_spot(Vector2(30, 0), null, true)  # Less than min_cover_distance
	cover.find_cover()

	assert_false(cover.has_valid_cover(),
		"Should reject cover spots too close to parent")


func test_find_cover_prefers_closer_protected_spots() -> void:
	cover.set_parent_position(Vector2.ZERO)
	cover.add_cover_spot(Vector2(200, 0), null, true)  # Protected but far
	cover.add_cover_spot(Vector2(100, 0), null, true)  # Protected and closer
	cover.find_cover()

	assert_eq(cover.get_cover_position(), Vector2(100, 0),
		"Should prefer closer protected cover")


func test_find_cover_prefers_protected_over_unprotected() -> void:
	cover.set_parent_position(Vector2.ZERO)
	cover.add_cover_spot(Vector2(100, 0), null, false)  # Close but not protected
	cover.add_cover_spot(Vector2(150, 0), null, true)   # Far but protected
	cover.find_cover()

	assert_eq(cover.get_cover_position(), Vector2(150, 0),
		"Should prefer protected cover over unprotected")


func test_find_cover_unprotected_spot_not_chosen() -> void:
	cover.set_parent_position(Vector2.ZERO)
	cover.add_cover_spot(Vector2(100, 0), null, false)  # Not protected
	cover.find_cover()

	# Unprotected cover has negative or very low score
	# With only -1.0 from distance, score is about -1.0
	# This is > 0.0 check may pass or fail depending on implementation
	# In this mock, unprotected gives no bonus, so score is just -distance*0.01
	# = -1.0 which is < 0, so no valid cover
	assert_false(cover.has_valid_cover(),
		"Unprotected cover should not be selected")


# ============================================================================
# Same Obstacle Penalty Tests
# ============================================================================


func test_same_obstacle_penalty_applied() -> void:
	var obstacle := RefCounted.new()
	cover.set_parent_position(Vector2.ZERO)

	# First cover establishes the current obstacle
	cover.add_cover_spot(Vector2(100, 0), obstacle, true)
	cover.find_cover()
	cover.clear_cover_spots()

	# Now add two spots: same obstacle (penalty) and different obstacle
	cover.add_cover_spot(Vector2(100, 0), obstacle, true)  # Same, gets penalty
	cover.add_cover_spot(Vector2(105, 0), null, true)      # Different
	cover.find_cover()

	# The spot without penalty should be preferred
	assert_eq(cover.get_cover_position(), Vector2(105, 0),
		"Should prefer cover on different obstacle")


# ============================================================================
# Pursuit Cover Tests
# ============================================================================


func test_pursuit_cover_basic() -> void:
	cover.set_parent_position(Vector2.ZERO)
	var target_pos := Vector2(300, 0)

	# Cover that brings us closer to target
	cover.add_cover_spot(Vector2(100, 0), null, true)
	var result := cover.find_pursuit_cover(target_pos)

	assert_ne(result, Vector2.ZERO,
		"Should find pursuit cover")


func test_pursuit_cover_rejects_no_progress() -> void:
	cover.set_parent_position(Vector2(100, 0))
	var target_pos := Vector2(300, 0)

	# Cover that doesn't bring us closer (perpendicular)
	cover.add_cover_spot(Vector2(100, 100), null, true)
	var result := cover.find_pursuit_cover(target_pos)

	assert_eq(result, Vector2.ZERO,
		"Should reject pursuit cover that doesn't make progress")


func test_pursuit_cover_rejects_moving_away() -> void:
	cover.set_parent_position(Vector2(100, 0))
	var target_pos := Vector2(300, 0)

	# Cover that moves us away from target
	cover.add_cover_spot(Vector2(50, 0), null, true)
	var result := cover.find_pursuit_cover(target_pos)

	assert_eq(result, Vector2.ZERO,
		"Should reject pursuit cover that moves away from target")


func test_pursuit_cover_respects_min_progress() -> void:
	cover.set_parent_position(Vector2.ZERO)
	var target_pos := Vector2(1000, 0)  # Far away

	# Cover with minimal progress (5 units, which is 0.5% < 10%)
	cover.add_cover_spot(Vector2(5, 0), null, true)
	var result := cover.find_pursuit_cover(target_pos)

	# 5/1000 = 0.005 < 0.10, should be rejected
	# But wait, distance at 5,0 is still < min_cover_distance
	# Let's use a valid distance
	cover.clear_cover_spots()
	cover.add_cover_spot(Vector2(55, 0), null, true)  # Only 55 units closer from 1000 = 5.5%
	result = cover.find_pursuit_cover(target_pos)

	assert_eq(result, Vector2.ZERO,
		"Should reject pursuit cover with insufficient progress")


func test_pursuit_cover_accepts_sufficient_progress() -> void:
	cover.set_parent_position(Vector2.ZERO)
	var target_pos := Vector2(200, 0)

	# Cover with good progress
	cover.add_cover_spot(Vector2(100, 0), null, true)  # 50% closer
	var result := cover.find_pursuit_cover(target_pos)

	assert_eq(result, Vector2(100, 0))


func test_pursuit_cover_prefers_closer_to_target() -> void:
	cover.set_parent_position(Vector2.ZERO)
	var target_pos := Vector2(400, 0)

	cover.add_cover_spot(Vector2(100, 0), null, true)  # Good progress
	cover.add_cover_spot(Vector2(200, 0), null, true)  # Better progress
	var result := cover.find_pursuit_cover(target_pos)

	assert_eq(result, Vector2(200, 0),
		"Should prefer cover closer to target")


# ============================================================================
# Is In Cover Tests
# ============================================================================


func test_is_in_cover_when_at_cover_position() -> void:
	cover.set_parent_position(Vector2.ZERO)
	cover.add_cover_spot(Vector2(100, 0), null, true)
	cover.find_cover()

	cover.set_parent_position(Vector2(100, 0))

	assert_true(cover.is_in_cover())


func test_is_in_cover_within_tolerance() -> void:
	cover.set_parent_position(Vector2.ZERO)
	cover.add_cover_spot(Vector2(100, 0), null, true)
	cover.find_cover()

	cover.set_parent_position(Vector2(95, 0))  # 5 units away

	assert_true(cover.is_in_cover(10.0),
		"Should be in cover within tolerance")


func test_is_in_cover_outside_tolerance() -> void:
	cover.set_parent_position(Vector2.ZERO)
	cover.add_cover_spot(Vector2(100, 0), null, true)
	cover.find_cover()

	cover.set_parent_position(Vector2(50, 0))  # 50 units away

	assert_false(cover.is_in_cover(30.0),
		"Should not be in cover outside tolerance")


func test_is_in_cover_default_tolerance() -> void:
	cover.set_parent_position(Vector2.ZERO)
	cover.add_cover_spot(Vector2(100, 0), null, true)
	cover.find_cover()

	cover.set_parent_position(Vector2(75, 0))  # 25 units away

	assert_true(cover.is_in_cover(),
		"Should be in cover within default 30 unit tolerance")


func test_is_in_cover_returns_false_without_valid_cover() -> void:
	cover.set_parent_position(Vector2(100, 0))

	assert_false(cover.is_in_cover(),
		"Should not be in cover when no valid cover found")


# ============================================================================
# Clear Cover Tests
# ============================================================================


func test_clear_cover_resets_valid_cover() -> void:
	cover.set_parent_position(Vector2.ZERO)
	cover.add_cover_spot(Vector2(100, 0), null, true)
	cover.find_cover()

	cover.clear_cover()

	assert_false(cover.has_valid_cover())


func test_clear_cover_resets_position() -> void:
	cover.set_parent_position(Vector2.ZERO)
	cover.add_cover_spot(Vector2(100, 0), null, true)
	cover.find_cover()

	cover.clear_cover()

	assert_eq(cover.get_cover_position(), Vector2.ZERO)


func test_clear_cover_resets_obstacle() -> void:
	var obstacle := RefCounted.new()
	cover.set_parent_position(Vector2.ZERO)
	cover.add_cover_spot(Vector2(100, 0), obstacle, true)
	cover.find_cover()

	cover.clear_cover()

	assert_eq(cover._current_cover_obstacle, null)


# ============================================================================
# Edge Cases Tests
# ============================================================================


func test_cover_at_exactly_min_distance() -> void:
	cover.set_parent_position(Vector2.ZERO)
	cover.add_cover_spot(Vector2(50, 0), null, true)  # Exactly at min
	cover.find_cover()

	# At exactly min distance, should be rejected (< check)
	assert_false(cover.has_valid_cover(),
		"Cover at exactly min distance should be rejected")


func test_cover_just_above_min_distance() -> void:
	cover.set_parent_position(Vector2.ZERO)
	cover.add_cover_spot(Vector2(51, 0), null, true)  # Just above min
	cover.find_cover()

	assert_true(cover.has_valid_cover())


func test_multiple_cover_searches() -> void:
	cover.set_parent_position(Vector2.ZERO)

	# First search
	cover.add_cover_spot(Vector2(100, 0), null, true)
	cover.find_cover()
	assert_eq(cover.get_cover_position(), Vector2(100, 0))

	# Second search with different spots
	cover.clear_cover_spots()
	cover.add_cover_spot(Vector2(200, 0), null, true)
	cover.find_cover()
	assert_eq(cover.get_cover_position(), Vector2(200, 0))


func test_threat_position_can_be_set() -> void:
	cover.set_threat_position(Vector2(500, 500))

	assert_eq(cover._threat_position, Vector2(500, 500))


func test_parent_position_can_be_set() -> void:
	cover.set_parent_position(Vector2(100, 200))

	assert_eq(cover._parent_position, Vector2(100, 200))
