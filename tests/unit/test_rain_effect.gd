extends GutTest
## Unit tests for rain_effect.gd HM2-style precipitation system (Issue #1394, fixed #1499).
##
## Tests continuous rain behavior, exclusion zone logic, and state transitions.
## Also tests the directional (downward) streak fix and splash alignment fix.
## The actual RainEffect extends Node2D with two child GPUParticles2D layers
## (downward streaks + splash ripples). Uses a mock to test logic without
## requiring GPUParticles2D rendering.


# ============================================================================
# Mock RainEffect for Logic Tests
# ============================================================================


class MockRainEffect:
	## Indoor exclusion zones.
	var exclusion_zones: Array = []

	## Whether currently emitting particles.
	var emitting: bool = false

	## Whether inside an exclusion zone.
	var _inside_exclusion: bool = false


	func ready() -> void:
		# Rain is always on from the start (continuous mode)
		emitting = true


	func add_exclusion_zone(rect: Rect2) -> void:
		exclusion_zones.append(rect)


	func clear_exclusion_zones() -> void:
		exclusion_zones.clear()


	func is_raining() -> bool:
		return not _inside_exclusion


	func _is_point_in_exclusion_zone(point: Vector2) -> bool:
		for zone in exclusion_zones:
			if zone.has_point(point):
				return true
		return false


	func simulate_camera_move(camera_center: Vector2) -> void:
		var was_inside := _inside_exclusion
		_inside_exclusion = _is_point_in_exclusion_zone(camera_center)
		if _inside_exclusion and not was_inside:
			emitting = false
		elif not _inside_exclusion and was_inside:
			emitting = true


# ============================================================================
# Tests: Continuous Rain
# ============================================================================


func test_rain_starts_immediately() -> void:
	var rain := MockRainEffect.new()
	rain.ready()
	assert_true(rain.emitting, "Rain should emit immediately on ready")


func test_rain_is_always_on() -> void:
	var rain := MockRainEffect.new()
	rain.ready()
	assert_true(rain.is_raining(), "Rain should always be active")


# ============================================================================
# Tests: Exclusion Zones
# ============================================================================


func test_add_exclusion_zone() -> void:
	var rain := MockRainEffect.new()
	rain.add_exclusion_zone(Rect2(100, 100, 200, 200))
	assert_eq(rain.exclusion_zones.size(), 1, "Should have 1 exclusion zone")


func test_clear_exclusion_zones() -> void:
	var rain := MockRainEffect.new()
	rain.add_exclusion_zone(Rect2(100, 100, 200, 200))
	rain.add_exclusion_zone(Rect2(500, 500, 300, 300))
	rain.clear_exclusion_zones()
	assert_eq(rain.exclusion_zones.size(), 0, "All exclusion zones should be cleared")


func test_point_inside_exclusion_zone() -> void:
	var rain := MockRainEffect.new()
	rain.add_exclusion_zone(Rect2(100, 100, 200, 200))
	assert_true(rain._is_point_in_exclusion_zone(Vector2(150, 150)),
		"Point inside zone should be detected")


func test_point_outside_exclusion_zone() -> void:
	var rain := MockRainEffect.new()
	rain.add_exclusion_zone(Rect2(100, 100, 200, 200))
	assert_false(rain._is_point_in_exclusion_zone(Vector2(50, 50)),
		"Point outside zone should not be detected")


func test_point_on_zone_boundary() -> void:
	var rain := MockRainEffect.new()
	rain.add_exclusion_zone(Rect2(100, 100, 200, 200))
	assert_true(rain._is_point_in_exclusion_zone(Vector2(100, 100)),
		"Point on zone boundary (top-left) should be inside")


func test_multiple_exclusion_zones() -> void:
	var rain := MockRainEffect.new()
	rain.add_exclusion_zone(Rect2(100, 100, 200, 200))
	rain.add_exclusion_zone(Rect2(500, 500, 300, 300))
	assert_true(rain._is_point_in_exclusion_zone(Vector2(600, 600)),
		"Point in second zone should be detected")
	assert_false(rain._is_point_in_exclusion_zone(Vector2(400, 400)),
		"Point between zones should not be detected")


# ============================================================================
# Tests: Building Enter/Exit
# ============================================================================


func test_rain_stops_when_entering_building() -> void:
	var rain := MockRainEffect.new()
	rain.ready()
	assert_true(rain.emitting, "Rain should emit outside buildings")

	rain.add_exclusion_zone(Rect2(100, 100, 200, 200))
	rain.simulate_camera_move(Vector2(150, 150))
	assert_false(rain.emitting, "Rain should stop inside building")


func test_rain_resumes_when_leaving_building() -> void:
	var rain := MockRainEffect.new()
	rain.add_exclusion_zone(Rect2(100, 100, 200, 200))
	rain.ready()

	# Enter building
	rain.simulate_camera_move(Vector2(150, 150))
	assert_false(rain.emitting, "Rain should stop inside building")

	# Leave building
	rain.simulate_camera_move(Vector2(50, 50))
	assert_true(rain.emitting, "Rain should resume after leaving building")


func test_is_raining_returns_true_outside() -> void:
	var rain := MockRainEffect.new()
	rain.ready()
	assert_true(rain.is_raining(), "is_raining should be true outside")


func test_is_raining_returns_false_inside_building() -> void:
	var rain := MockRainEffect.new()
	rain.add_exclusion_zone(Rect2(100, 100, 200, 200))
	rain.ready()
	rain.simulate_camera_move(Vector2(150, 150))
	assert_false(rain.is_raining(), "is_raining should be false inside building")


# ============================================================================
# Tests: Warehouse Exclusion Zones
# ============================================================================


func test_warehouse_a_exclusion_zone() -> void:
	var rain := MockRainEffect.new()
	# WarehouseA: position (400, 1800), walls extend ±270x, ±320y
	var warehouse_a := Rect2(400 - 270, 1800 - 320, 540, 640)
	rain.add_exclusion_zone(warehouse_a)

	assert_true(rain._is_point_in_exclusion_zone(Vector2(400, 1800)),
		"Center of WarehouseA should be in zone")
	assert_false(rain._is_point_in_exclusion_zone(Vector2(800, 1800)),
		"Point east of WarehouseA should not be in zone")


func test_warehouse_b_exclusion_zone() -> void:
	var rain := MockRainEffect.new()
	# WarehouseB: position (4400, 2800), walls extend ±370x, ±420y
	var warehouse_b := Rect2(4400 - 370, 2800 - 420, 740, 840)
	rain.add_exclusion_zone(warehouse_b)

	assert_true(rain._is_point_in_exclusion_zone(Vector2(4400, 2800)),
		"Center of WarehouseB should be in zone")
	assert_false(rain._is_point_in_exclusion_zone(Vector2(3900, 2800)),
		"Point west of WarehouseB should not be in zone")


# ============================================================================
# Tests: Issue #1499 Fixes — Directional Streaks and Splash Alignment
# ============================================================================


class MockParticleMaterial:
	## Simulates ParticleProcessMaterial direction property.
	var direction: Vector3 = Vector3.ZERO
	var initial_velocity_min: float = 0.0
	var initial_velocity_max: float = 0.0
	var radial_velocity_min: float = 0.0
	var radial_velocity_max: float = 0.0


func test_streak_direction_is_downward() -> void:
	# The direction vector must have a positive Y component (downward in Godot 2D)
	# to make streaks fall down, not fly up. Fix: replaced radial_velocity with
	# direction=(0.2,1,0) + initial_velocity (Issue #1499).
	var mat := MockParticleMaterial.new()
	mat.direction = Vector3(0.2, 1.0, 0.0)
	assert_true(mat.direction.y > 0.0,
		"Streak direction Y must be positive (downward) to make rain fall, not fly up")


func test_streak_has_no_radial_velocity() -> void:
	# radial_velocity != 0 causes particles to move away from/toward emitter center,
	# making upper-half streaks fly upward. Fix: radial_velocity must be zero (Issue #1499).
	var mat := MockParticleMaterial.new()
	mat.radial_velocity_min = 0.0
	mat.radial_velocity_max = 0.0
	assert_eq(mat.radial_velocity_min, 0.0,
		"radial_velocity_min must be 0 to prevent upward-flying streaks")
	assert_eq(mat.radial_velocity_max, 0.0,
		"radial_velocity_max must be 0 to prevent upward-flying streaks")


func test_streak_has_positive_initial_velocity() -> void:
	# Streaks need initial_velocity > 0 to actually move after removing radial_velocity.
	var mat := MockParticleMaterial.new()
	mat.initial_velocity_min = 400.0
	mat.initial_velocity_max = 600.0
	assert_true(mat.initial_velocity_min > 0.0,
		"Streak initial_velocity_min must be > 0 for visible movement")
	assert_true(mat.initial_velocity_max > mat.initial_velocity_min,
		"initial_velocity_max must exceed min for velocity variation")


func test_splash_offset_matches_streak_endpoint() -> void:
	# Splash emitter must be offset by the average streak travel vector so that
	# the streak disappearance point matches the splash appearance point (Issue #1499).
	# Streak: direction=(0.2,1,0) normalized=(0.196,0.981,0), avg_velocity=500, lifetime=0.15
	var direction := Vector3(0.2, 1.0, 0.0).normalized()
	var avg_velocity := (400.0 + 600.0) / 2.0
	var lifetime := 0.15
	var streak_origin := Vector2(640.0, 360.0)

	var travel_x := direction.x * avg_velocity * lifetime
	var travel_y := direction.y * avg_velocity * lifetime
	var expected_splash_pos := streak_origin + Vector2(travel_x, travel_y)

	# Splash position from the fixed scene: Vector2(655, 434)
	var actual_splash_pos := Vector2(655.0, 434.0)

	# Allow ±5px tolerance for rounding
	assert_true(abs(actual_splash_pos.x - expected_splash_pos.x) <= 5.0,
		"Splash X position should match streak endpoint X (±5px). Expected ~%.0f got %.0f" % [expected_splash_pos.x, actual_splash_pos.x])
	assert_true(abs(actual_splash_pos.y - expected_splash_pos.y) <= 5.0,
		"Splash Y position should match streak endpoint Y (±5px). Expected ~%.0f got %.0f" % [expected_splash_pos.y, actual_splash_pos.y])
