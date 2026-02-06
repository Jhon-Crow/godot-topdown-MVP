extends GutTest
## Unit tests for AdvancedTargetingComponent.
##
## Tests the ricochet and wallbang targeting functionality including
## geometry calculations, probability curves, and targeting decisions.
## Issue #349: Enemy mechanics understanding


# ============================================================================
# Mock AdvancedTargetingComponent for Logic Tests
# ============================================================================


class MockAdvancedTargetingComponent:
	## Enable/disable wallbang shots
	var enable_wallbang_shots: bool = true

	## Enable/disable ricochet shots
	var enable_ricochet_shots: bool = true

	## Enable/disable double ricochet shots
	var enable_double_ricochet: bool = true

	## Minimum ricochet probability threshold
	var ricochet_min_probability_threshold: float = 0.5

	## Minimum double ricochet probability threshold
	var double_ricochet_min_probability_threshold: float = 0.25

	## Maximum ricochet search radius
	var ricochet_search_radius: float = 500.0

	## Maximum total ricochet path distance
	var ricochet_max_total_distance: float = 800.0

	## Maximum penetration distance for wallbang
	var max_penetration_distance: float = 48.0

	## Post-penetration damage multiplier
	var post_penetration_damage_multiplier: float = 0.9

	## Wallbang minimum damage threshold
	var wallbang_min_damage_threshold: float = 0.3


	## Calculate the bullet impact angle (grazing angle).
	## @return: Angle in radians (0 = grazing, PI/2 = perpendicular).
	func calculate_bullet_impact_angle(direction: Vector2, surface_normal: Vector2) -> float:
		var dot := absf(direction.normalized().dot(surface_normal.normalized()))
		dot = clampf(dot, 0.0, 1.0)
		return asin(dot)


	## Calculate ricochet probability based on impact angle.
	## Uses the same curve as bullet.gd for consistency.
	func calculate_ricochet_probability_for_angle(impact_angle_rad: float) -> float:
		var impact_angle_deg := rad_to_deg(impact_angle_rad)
		var max_angle := 90.0

		if impact_angle_deg > max_angle:
			return 0.0

		# Match bullet.gd probability curve:
		# probability = base * (0.9 * (1 - (angle/90)^2.17) + 0.1)
		var normalized_angle := impact_angle_deg / 90.0
		var power_factor := pow(normalized_angle, 2.17)
		var angle_factor := (1.0 - power_factor) * 0.9 + 0.1

		return angle_factor


	## Calculate line segment intersection.
	## @return: Dictionary with valid: bool and point: Vector2.
	func line_segment_intersection(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2) -> Dictionary:
		var d1 := p2 - p1
		var d2 := p4 - p3
		var d3 := p1 - p3

		var cross := d1.x * d2.y - d1.y * d2.x

		if abs(cross) < 0.0001:
			return {"valid": false}  # Lines are parallel

		var t := (d3.x * d2.y - d3.y * d2.x) / cross
		var u := (d3.x * d1.y - d3.y * d1.x) / cross

		# Check if intersection is within both segments
		if t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0:
			return {
				"valid": true,
				"point": p1 + t * d1
			}

		return {"valid": false}


	## Reflect a point across a line defined by start and direction.
	func reflect_point_across_line(point: Vector2, line_start: Vector2, line_normal: Vector2) -> Vector2:
		var to_point := point - line_start
		var dist_to_line := to_point.dot(line_normal)
		return point - 2.0 * dist_to_line * line_normal


	## Check if a reflected ray passes near the target position.
	func reflected_path_reaches_target(start: Vector2, direction: Vector2, target: Vector2, tolerance: float = 50.0) -> bool:
		var to_target := target - start
		var projected := to_target.project(direction)

		# Target must be in the direction of reflection (not behind)
		if projected.dot(direction) < 0:
			return false

		# Check perpendicular distance to target
		var perp_dist := (to_target - projected).length()

		return perp_dist < tolerance


	## Calculate estimated wall thickness based on penetration steps.
	func calculate_wallbang_damage(wall_thickness: float) -> float:
		var penetration_steps := ceil(wall_thickness / 24.0)
		return pow(post_penetration_damage_multiplier, penetration_steps)


# ============================================================================
# Tests
# ============================================================================


var _component: MockAdvancedTargetingComponent


func before_each() -> void:
	_component = MockAdvancedTargetingComponent.new()


func after_each() -> void:
	_component = null


# ============================================================================
# Ricochet Probability Tests
# ============================================================================


func test_ricochet_probability_grazing_angle() -> void:
	# Grazing angle (0°) should have very high probability (~100%)
	var prob := _component.calculate_ricochet_probability_for_angle(0.0)
	assert_gt(prob, 0.95, "Grazing angle (0°) should have >95% probability")


func test_ricochet_probability_shallow_angle() -> void:
	# Shallow angle (15°) should have high probability (~98%)
	var angle_rad := deg_to_rad(15.0)
	var prob := _component.calculate_ricochet_probability_for_angle(angle_rad)
	assert_gt(prob, 0.90, "Shallow angle (15°) should have >90% probability")


func test_ricochet_probability_moderate_angle() -> void:
	# Moderate angle (45°) should have good probability (~80%)
	var angle_rad := deg_to_rad(45.0)
	var prob := _component.calculate_ricochet_probability_for_angle(angle_rad)
	assert_almost_eq(prob, 0.80, 0.15, "Moderate angle (45°) should have ~80% probability")


func test_ricochet_probability_steep_angle() -> void:
	# Steep angle (70°) should have lower probability
	var angle_rad := deg_to_rad(70.0)
	var prob := _component.calculate_ricochet_probability_for_angle(angle_rad)
	assert_lt(prob, 0.50, "Steep angle (70°) should have <50% probability")


func test_ricochet_probability_perpendicular_angle() -> void:
	# Perpendicular angle (90°) should have minimal probability (~10%)
	var angle_rad := deg_to_rad(90.0)
	var prob := _component.calculate_ricochet_probability_for_angle(angle_rad)
	assert_almost_eq(prob, 0.10, 0.05, "Perpendicular angle (90°) should have ~10% probability")


func test_ricochet_probability_beyond_max_angle() -> void:
	# Angle beyond 90° should have 0% probability
	var angle_rad := deg_to_rad(100.0)
	var prob := _component.calculate_ricochet_probability_for_angle(angle_rad)
	assert_eq(prob, 0.0, "Angle beyond 90° should have 0% probability")


# ============================================================================
# Impact Angle Calculation Tests
# ============================================================================


func test_impact_angle_grazing_shot() -> void:
	# Bullet parallel to wall (grazing shot)
	var direction := Vector2(1, 0)  # Moving right
	var surface_normal := Vector2(0, 1)  # Wall facing up
	var angle := _component.calculate_bullet_impact_angle(direction, surface_normal)
	assert_almost_eq(rad_to_deg(angle), 0.0, 1.0, "Grazing shot should have ~0° impact angle")


func test_impact_angle_perpendicular_shot() -> void:
	# Bullet perpendicular to wall (direct hit)
	var direction := Vector2(0, -1)  # Moving up
	var surface_normal := Vector2(0, 1)  # Wall facing up
	var angle := _component.calculate_bullet_impact_angle(direction, surface_normal)
	assert_almost_eq(rad_to_deg(angle), 90.0, 1.0, "Perpendicular shot should have ~90° impact angle")


func test_impact_angle_45_degree_shot() -> void:
	# Bullet at 45° to wall
	var direction := Vector2(1, -1).normalized()  # Moving right-up
	var surface_normal := Vector2(0, 1)  # Wall facing up
	var angle := _component.calculate_bullet_impact_angle(direction, surface_normal)
	assert_almost_eq(rad_to_deg(angle), 45.0, 2.0, "45° shot should have ~45° impact angle")


# ============================================================================
# Line Segment Intersection Tests
# ============================================================================


func test_intersection_crossing_lines() -> void:
	# Two crossing line segments
	var result := _component.line_segment_intersection(
		Vector2(0, 0), Vector2(10, 10),  # Diagonal line
		Vector2(0, 10), Vector2(10, 0)   # Opposite diagonal
	)
	assert_true(result.valid, "Crossing lines should have valid intersection")
	assert_almost_eq(result.point.x, 5.0, 0.1, "Intersection X should be ~5")
	assert_almost_eq(result.point.y, 5.0, 0.1, "Intersection Y should be ~5")


func test_intersection_parallel_lines() -> void:
	# Two parallel line segments (no intersection)
	var result := _component.line_segment_intersection(
		Vector2(0, 0), Vector2(10, 0),  # Horizontal line at y=0
		Vector2(0, 5), Vector2(10, 5)   # Horizontal line at y=5
	)
	assert_false(result.valid, "Parallel lines should not have intersection")


func test_intersection_non_crossing_segments() -> void:
	# Lines that would cross if extended, but segments don't
	var result := _component.line_segment_intersection(
		Vector2(0, 0), Vector2(2, 2),   # Short diagonal
		Vector2(5, 0), Vector2(5, 10)   # Vertical line far right
	)
	assert_false(result.valid, "Non-crossing segments should not have intersection")


func test_intersection_t_junction() -> void:
	# One segment ends at the middle of another
	var result := _component.line_segment_intersection(
		Vector2(0, 5), Vector2(10, 5),  # Horizontal line
		Vector2(5, 0), Vector2(5, 5)    # Vertical line meeting at (5, 5)
	)
	assert_true(result.valid, "T-junction should have valid intersection")
	assert_almost_eq(result.point.x, 5.0, 0.1, "Intersection X should be ~5")
	assert_almost_eq(result.point.y, 5.0, 0.1, "Intersection Y should be ~5")


# ============================================================================
# Mirror Point Tests
# ============================================================================


func test_reflect_point_horizontal_wall() -> void:
	# Reflect point across horizontal wall
	var point := Vector2(50, 100)
	var wall_start := Vector2(0, 50)  # Wall at y=50
	var wall_normal := Vector2(0, 1)  # Wall facing up

	var mirror := _component.reflect_point_across_line(point, wall_start, wall_normal)

	assert_almost_eq(mirror.x, 50.0, 0.1, "Mirror X should stay same")
	assert_almost_eq(mirror.y, 0.0, 0.1, "Mirror Y should be reflected (100->0)")


func test_reflect_point_vertical_wall() -> void:
	# Reflect point across vertical wall
	var point := Vector2(100, 50)
	var wall_start := Vector2(50, 0)  # Wall at x=50
	var wall_normal := Vector2(1, 0)  # Wall facing right

	var mirror := _component.reflect_point_across_line(point, wall_start, wall_normal)

	assert_almost_eq(mirror.x, 0.0, 0.1, "Mirror X should be reflected (100->0)")
	assert_almost_eq(mirror.y, 50.0, 0.1, "Mirror Y should stay same")


# ============================================================================
# Reflected Path Tests
# ============================================================================


func test_reflected_path_hits_target() -> void:
	# Ray directed straight at target
	var start := Vector2(0, 0)
	var direction := Vector2(1, 0).normalized()  # Going right
	var target := Vector2(100, 0)  # Directly ahead

	var result := _component.reflected_path_reaches_target(start, direction, target)
	assert_true(result, "Ray pointing at target should reach it")


func test_reflected_path_misses_target() -> void:
	# Ray directed away from target
	var start := Vector2(0, 0)
	var direction := Vector2(-1, 0).normalized()  # Going left
	var target := Vector2(100, 0)  # Target is to the right

	var result := _component.reflected_path_reaches_target(start, direction, target)
	assert_false(result, "Ray pointing away from target should not reach it")


func test_reflected_path_near_miss() -> void:
	# Ray that passes near target but not within tolerance
	var start := Vector2(0, 0)
	var direction := Vector2(1, 0).normalized()  # Going right
	var target := Vector2(100, 100)  # 100 units above the ray path

	var result := _component.reflected_path_reaches_target(start, direction, target, 50.0)
	assert_false(result, "Ray passing >50 units from target should miss")


func test_reflected_path_close_pass() -> void:
	# Ray that passes close to target within tolerance
	var start := Vector2(0, 0)
	var direction := Vector2(1, 0).normalized()  # Going right
	var target := Vector2(100, 30)  # 30 units above the ray path

	var result := _component.reflected_path_reaches_target(start, direction, target, 50.0)
	assert_true(result, "Ray passing within 50 units of target should hit")


# ============================================================================
# Wallbang Damage Calculation Tests
# ============================================================================


func test_wallbang_damage_thin_wall() -> void:
	# Very thin wall (5 pixels) = 1 penetration step
	var damage := _component.calculate_wallbang_damage(5.0)
	assert_almost_eq(damage, 0.9, 0.01, "Thin wall should have 90% damage")


func test_wallbang_damage_standard_wall() -> void:
	# Standard wall (24 pixels) = 1 penetration step
	var damage := _component.calculate_wallbang_damage(24.0)
	assert_almost_eq(damage, 0.9, 0.01, "Standard wall should have 90% damage")


func test_wallbang_damage_thick_wall() -> void:
	# Thick wall (48 pixels) = 2 penetration steps
	var damage := _component.calculate_wallbang_damage(48.0)
	assert_almost_eq(damage, 0.81, 0.01, "Thick wall should have 81% damage (0.9^2)")


func test_wallbang_damage_very_thick_wall() -> void:
	# Very thick wall (72 pixels) = 3 penetration steps
	var damage := _component.calculate_wallbang_damage(72.0)
	assert_almost_eq(damage, 0.729, 0.01, "Very thick wall should have 72.9% damage (0.9^3)")


func test_wallbang_below_threshold() -> void:
	# Wall so thick that damage would be below threshold
	var damage := _component.calculate_wallbang_damage(200.0)  # Many steps
	assert_lt(damage, _component.wallbang_min_damage_threshold,
		"Very thick wall should result in damage below threshold")


# ============================================================================
# Configuration Tests
# ============================================================================


func test_default_configuration() -> void:
	assert_true(_component.enable_wallbang_shots, "Wallbang should be enabled by default")
	assert_true(_component.enable_ricochet_shots, "Ricochet should be enabled by default")
	assert_true(_component.enable_double_ricochet, "Double ricochet should be enabled by default")


func test_probability_thresholds() -> void:
	assert_eq(_component.ricochet_min_probability_threshold, 0.5,
		"Ricochet min probability should be 0.5")
	assert_eq(_component.double_ricochet_min_probability_threshold, 0.25,
		"Double ricochet min probability should be 0.25")


func test_distance_limits() -> void:
	assert_eq(_component.ricochet_search_radius, 500.0,
		"Ricochet search radius should be 500")
	assert_eq(_component.ricochet_max_total_distance, 800.0,
		"Max ricochet path distance should be 800")


func test_penetration_settings() -> void:
	assert_eq(_component.max_penetration_distance, 48.0,
		"Max penetration distance should be 48")
	assert_eq(_component.post_penetration_damage_multiplier, 0.9,
		"Post-penetration damage multiplier should be 0.9")


# ============================================================================
# Snap-Shooting / Suspected Target Tests (Issue #349)
# ============================================================================


## Mock for testing suspected target probability scaling
class MockSuspectedTargeting:
	var suspected_confidence: float = 0.0
	var base_ricochet_probability: float = 0.8
	var base_wallbang_probability: float = 1.0

	## Scale ricochet probability by confidence (as in AdvancedTargetingComponent)
	func get_suspected_ricochet_probability() -> float:
		return base_ricochet_probability * suspected_confidence

	## Scale wallbang probability by confidence (as in AdvancedTargetingComponent)
	func get_suspected_wallbang_probability() -> float:
		return base_wallbang_probability * suspected_confidence


func test_suspected_probability_high_confidence() -> void:
	var mock := MockSuspectedTargeting.new()
	mock.suspected_confidence = 0.9  # High confidence (e.g., just saw player)
	var prob := mock.get_suspected_ricochet_probability()
	assert_almost_eq(prob, 0.72, 0.01, "High confidence (0.9) * 0.8 prob = 0.72")


func test_suspected_probability_medium_confidence() -> void:
	var mock := MockSuspectedTargeting.new()
	mock.suspected_confidence = 0.5  # Medium confidence (e.g., heard gunshot)
	var prob := mock.get_suspected_ricochet_probability()
	assert_almost_eq(prob, 0.40, 0.01, "Medium confidence (0.5) * 0.8 prob = 0.40")


func test_suspected_probability_low_confidence() -> void:
	var mock := MockSuspectedTargeting.new()
	mock.suspected_confidence = 0.3  # Low confidence (e.g., old memory)
	var prob := mock.get_suspected_ricochet_probability()
	assert_almost_eq(prob, 0.24, 0.01, "Low confidence (0.3) * 0.8 prob = 0.24")


func test_suspected_probability_zero_confidence() -> void:
	var mock := MockSuspectedTargeting.new()
	mock.suspected_confidence = 0.0  # No confidence
	var prob := mock.get_suspected_ricochet_probability()
	assert_eq(prob, 0.0, "Zero confidence should give zero probability")


func test_suspected_wallbang_probability_medium_confidence() -> void:
	var mock := MockSuspectedTargeting.new()
	mock.suspected_confidence = 0.6  # Medium confidence from sound
	var prob := mock.get_suspected_wallbang_probability()
	assert_almost_eq(prob, 0.6, 0.01, "Medium confidence wallbang prob should be 0.6")
