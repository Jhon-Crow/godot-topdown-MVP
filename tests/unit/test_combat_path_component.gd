extends GutTest
## Unit tests for CombatPathComponent.
##
## Tests waypoint collection, FALLBACK_MAX_DIST, MAX_TRAVEL_DIST constants,
## and attacking/retreat waypoint selection logic.


# ============================================================================
# Mock CombatPathComponent for Logic Tests
# ============================================================================


class MockCombatPathComponent:
	const FALLBACK_MAX_DIST: float = 350.0
	const FALLBACK_TARGET_DISTANCE: float = 120.0
	const MAX_TRAVEL_DIST: float = 400.0

	var _attacking_waypoints: Array[Vector2] = []
	var _retreat_waypoints: Array[Vector2] = []
	var has_paths: bool = false

	func set_attacking_waypoints(waypoints: Array[Vector2]) -> void:
		_attacking_waypoints = waypoints
		has_paths = _attacking_waypoints.size() > 0 or _retreat_waypoints.size() > 0

	func set_retreat_waypoints(waypoints: Array[Vector2]) -> void:
		_retreat_waypoints = waypoints
		has_paths = _attacking_waypoints.size() > 0 or _retreat_waypoints.size() > 0

	func get_nearest_attacking_waypoint(from_pos: Vector2, toward_pos: Vector2) -> Vector2:
		if _attacking_waypoints.is_empty():
			return Vector2.ZERO

		var my_dist_to_target := from_pos.distance_to(toward_pos)
		var best := Vector2.ZERO
		var best_score := -INF
		var nearest_fallback := Vector2.ZERO
		var nearest_fallback_dist := INF

		for wp in _attacking_waypoints:
			var dist_from_me := from_pos.distance_to(wp)
			var wp_dist_to_target := wp.distance_to(toward_pos)
			if dist_from_me < 20.0:
				continue
			var fallback_makes_sense := wp_dist_to_target < my_dist_to_target or my_dist_to_target <= FALLBACK_TARGET_DISTANCE
			if fallback_makes_sense and dist_from_me < nearest_fallback_dist and dist_from_me <= FALLBACK_MAX_DIST:
				nearest_fallback_dist = dist_from_me
				nearest_fallback = wp
			if dist_from_me > MAX_TRAVEL_DIST:
				continue
			if wp_dist_to_target >= my_dist_to_target:
				continue
			var progress := my_dist_to_target - wp_dist_to_target
			var score := progress - dist_from_me * 0.5
			if score > best_score:
				best_score = score
				best = wp

		if best == Vector2.ZERO:
			return nearest_fallback
		return best

	func get_nearest_retreat_waypoint(from_pos: Vector2, away_from_pos: Vector2) -> Vector2:
		if _retreat_waypoints.is_empty():
			return Vector2.ZERO

		var my_dist_from_threat := from_pos.distance_to(away_from_pos)
		var best := Vector2.ZERO
		var best_score := -INF

		for wp in _retreat_waypoints:
			var wp_dist_from_threat := wp.distance_to(away_from_pos)
			if wp_dist_from_threat <= my_dist_from_threat:
				continue
			var dist_from_me := from_pos.distance_to(wp)
			if dist_from_me < 20.0:
				continue
			var safety_gain := wp_dist_from_threat - my_dist_from_threat
			var score := safety_gain - dist_from_me * 0.3
			if score > best_score:
				best_score = score
				best = wp

		return best


var comp: MockCombatPathComponent


func before_each() -> void:
	comp = MockCombatPathComponent.new()


func after_each() -> void:
	comp = null


# ============================================================================
# Constants Tests
# ============================================================================


func test_fallback_max_dist_value() -> void:
	assert_eq(MockCombatPathComponent.FALLBACK_MAX_DIST, 350.0,
		"FALLBACK_MAX_DIST should be 350.0")


func test_fallback_target_distance_value() -> void:
	assert_eq(MockCombatPathComponent.FALLBACK_TARGET_DISTANCE, 120.0,
		"FALLBACK_TARGET_DISTANCE should be 120.0")


func test_max_travel_dist_value() -> void:
	assert_eq(MockCombatPathComponent.MAX_TRAVEL_DIST, 400.0,
		"MAX_TRAVEL_DIST should be 400.0")


# ============================================================================
# Waypoint Collection Tests
# ============================================================================


func test_has_paths_false_by_default() -> void:
	assert_false(comp.has_paths,
		"has_paths should be false with no waypoints")


func test_has_paths_true_with_attacking_waypoints() -> void:
	comp.set_attacking_waypoints([Vector2(100, 100)])

	assert_true(comp.has_paths,
		"has_paths should be true with attacking waypoints")


func test_has_paths_true_with_retreat_waypoints() -> void:
	comp.set_retreat_waypoints([Vector2(100, 100)])

	assert_true(comp.has_paths,
		"has_paths should be true with retreat waypoints")


func test_has_paths_true_with_both() -> void:
	comp.set_attacking_waypoints([Vector2(100, 100)])
	comp.set_retreat_waypoints([Vector2(200, 200)])

	assert_true(comp.has_paths)


# ============================================================================
# Attacking Waypoint Tests
# ============================================================================


func test_attacking_returns_zero_when_empty() -> void:
	var result := comp.get_nearest_attacking_waypoint(Vector2(0, 0), Vector2(500, 0))

	assert_eq(result, Vector2.ZERO,
		"Should return Vector2.ZERO when no attacking waypoints")


func test_attacking_selects_waypoint_closer_to_target() -> void:
	comp.set_attacking_waypoints([
		Vector2(250, 0),  # Closer to target (500,0) — progress waypoint
		Vector2(-100, 0),  # Further from target — no progress
	])

	var result := comp.get_nearest_attacking_waypoint(Vector2(0, 0), Vector2(500, 0))

	assert_eq(result, Vector2(250, 0),
		"Should select waypoint that makes progress toward target")


func test_attacking_skips_waypoints_too_close() -> void:
	comp.set_attacking_waypoints([
		Vector2(10, 0),  # Within 20px — skipped
	])

	var result := comp.get_nearest_attacking_waypoint(Vector2(0, 0), Vector2(500, 0))

	# Should fall back since the only waypoint is too close
	assert_eq(result, Vector2.ZERO,
		"Should skip waypoints within 20px of enemy")


func test_attacking_skips_waypoints_beyond_max_travel_dist() -> void:
	comp.set_attacking_waypoints([
		Vector2(450, 0),  # Beyond MAX_TRAVEL_DIST (400) from enemy at origin
	])

	var result := comp.get_nearest_attacking_waypoint(Vector2(0, 0), Vector2(500, 0))

	# The waypoint is 450px away (> MAX_TRAVEL_DIST=400), so it's skipped for scoring.
	# But it's also > FALLBACK_MAX_DIST=350, so no fallback either.
	assert_eq(result, Vector2.ZERO,
		"Should skip waypoints beyond MAX_TRAVEL_DIST for progress scoring")


func test_attacking_uses_fallback_when_no_progress_waypoint() -> void:
	# Enemy is already very close to target — no waypoint makes progress
	comp.set_attacking_waypoints([
		Vector2(100, 50),  # Within FALLBACK_MAX_DIST
	])

	var enemy_pos := Vector2(100, 0)
	var target_pos := Vector2(100, 10)  # Very close

	var result := comp.get_nearest_attacking_waypoint(enemy_pos, target_pos)

	assert_eq(result, Vector2(100, 50),
		"Should use fallback waypoint when no progress waypoint exists")


func test_attacking_rejects_fallback_that_moves_away_from_far_target() -> void:
	comp.set_attacking_waypoints([
		Vector2(-100, 0),  # Local fallback, but farther from the target
	])

	var result := comp.get_nearest_attacking_waypoint(Vector2(0, 0), Vector2(500, 0))

	assert_eq(result, Vector2.ZERO,
		"PURSUING must not use a local fallback waypoint that moves farther from a distant player")


func test_attacking_fallback_respects_max_dist() -> void:
	comp.set_attacking_waypoints([
		Vector2(400, 0),  # Beyond FALLBACK_MAX_DIST=350 from origin
	])

	var enemy_pos := Vector2(0, 0)
	var target_pos := Vector2(0, 10)

	var result := comp.get_nearest_attacking_waypoint(enemy_pos, target_pos)

	assert_eq(result, Vector2.ZERO,
		"Fallback should not use waypoints beyond FALLBACK_MAX_DIST")


func test_attacking_prefers_higher_score() -> void:
	comp.set_attacking_waypoints([
		Vector2(100, 0),  # 100px progress, 100px travel, score=100-50=50
		Vector2(200, 0),  # 200px progress, 200px travel, score=200-100=100
	])

	var result := comp.get_nearest_attacking_waypoint(Vector2(0, 0), Vector2(500, 0))

	assert_eq(result, Vector2(200, 0),
		"Should prefer waypoint with higher score (progress - 0.5*travel)")


# ============================================================================
# Retreat Waypoint Tests
# ============================================================================


func test_retreat_returns_zero_when_empty() -> void:
	var result := comp.get_nearest_retreat_waypoint(Vector2(100, 0), Vector2(0, 0))

	assert_eq(result, Vector2.ZERO,
		"Should return Vector2.ZERO when no retreat waypoints")


func test_retreat_selects_waypoint_further_from_threat() -> void:
	comp.set_retreat_waypoints([
		Vector2(300, 0),  # Further from threat at origin
		Vector2(50, 0),   # Closer to threat — won't add safety
	])

	var result := comp.get_nearest_retreat_waypoint(Vector2(100, 0), Vector2(0, 0))

	assert_eq(result, Vector2(300, 0),
		"Should select waypoint that increases distance from threat")


func test_retreat_skips_waypoints_closer_to_threat() -> void:
	comp.set_retreat_waypoints([
		Vector2(50, 0),  # Closer to threat at origin than enemy at (100,0)
	])

	var result := comp.get_nearest_retreat_waypoint(Vector2(100, 0), Vector2(0, 0))

	assert_eq(result, Vector2.ZERO,
		"Should skip waypoints that don't increase distance from threat")


func test_retreat_skips_waypoints_too_close_to_enemy() -> void:
	comp.set_retreat_waypoints([
		Vector2(105, 0),  # Within 20px of enemy at (100,0)
	])

	var result := comp.get_nearest_retreat_waypoint(Vector2(100, 0), Vector2(0, 0))

	assert_eq(result, Vector2.ZERO,
		"Should skip waypoints within 20px of enemy position")


func test_retreat_prefers_safety_gain_over_travel_cost() -> void:
	comp.set_retreat_waypoints([
		Vector2(250, 0),  # 150px safety gain, 150px travel, score=150-45=105
		Vector2(400, 0),  # 300px safety gain, 300px travel, score=300-90=210
	])

	var result := comp.get_nearest_retreat_waypoint(Vector2(100, 0), Vector2(0, 0))

	assert_eq(result, Vector2(400, 0),
		"Should prefer waypoint with higher safety gain score")
