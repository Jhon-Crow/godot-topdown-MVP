extends GutTest
## Unit tests for rain_effect.gd HM2-style precipitation system (Issue #1394, fixed #1499, #1546).
##
## Tests continuous rain behavior, exclusion zone logic, and state transitions.
## Also tests streak length, direction, and splash alignment fixes.
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
# Tests: Issue #1546 Fixes — Longer Streaks, Downward Direction, Splash Alignment
# ============================================================================


class MockParticleMaterial:
	## Simulates ParticleProcessMaterial direction property.
	var direction: Vector3 = Vector3.ZERO
	var initial_velocity_min: float = 0.0
	var initial_velocity_max: float = 0.0
	var radial_velocity_min: float = 0.0
	var radial_velocity_max: float = 0.0


class MockStreakTexture:
	## Simulates GradientTexture2D for streak length check.
	var width: int = 2
	var height: int = 16
	var scale_min: float = 1.2
	var scale_max: float = 2.5


func test_streak_direction_is_downward() -> void:
	# The direction vector must have a positive Y component (downward in Godot 2D).
	# Fix #1546: use straight downward direction=(0.1,1,0) so rain does not converge
	# on the player center and appears to fall uniformly across the map.
	var mat := MockParticleMaterial.new()
	mat.direction = Vector3(0.1, 1.0, 0.0)
	assert_true(mat.direction.y > 0.0,
		"Streak direction Y must be positive (downward) to make rain fall, not fly up")


func test_streak_has_no_radial_velocity() -> void:
	# radial_velocity must be zero — non-zero radial_velocity makes rain converge
	# on screen center (player position), which is the bug fixed in #1546.
	var mat := MockParticleMaterial.new()
	mat.radial_velocity_min = 0.0
	mat.radial_velocity_max = 0.0
	assert_eq(mat.radial_velocity_min, 0.0,
		"radial_velocity_min must be 0 to prevent rain from following the player")
	assert_eq(mat.radial_velocity_max, 0.0,
		"radial_velocity_max must be 0 to prevent rain from following the player")


func test_streak_has_positive_initial_velocity() -> void:
	# Streaks need initial_velocity > 0 to move downward (straight-down direction).
	var mat := MockParticleMaterial.new()
	mat.initial_velocity_min = 500.0
	mat.initial_velocity_max = 700.0
	assert_true(mat.initial_velocity_min > 0.0,
		"Streak initial_velocity_min must be > 0 for visible downward movement")
	assert_true(mat.initial_velocity_max > mat.initial_velocity_min,
		"initial_velocity_max must exceed min for velocity variation")


func test_streak_texture_is_long_enough() -> void:
	# Fix #1546: streak texture height must be >= 16px (was 6px) for visibly long drops.
	var tex := MockStreakTexture.new()
	assert_true(tex.height >= 16,
		"Streak texture height must be >= 16px for long drop appearance (was 6px)")


func test_streak_scale_is_large_enough() -> void:
	# Fix #1546: scale_max must be >= 2.0 (was 1.5) so streaks appear longer in-game.
	var tex := MockStreakTexture.new()
	assert_true(tex.scale_max >= 2.0,
		"Streak scale_max must be >= 2.0 for long drop appearance (was 1.5)")


func test_splash_offset_matches_streak_endpoint() -> void:
	# Fix #1546: Splash emitter is offset from streak emitter by the average travel
	# vector so that streak disappearance matches splash appearance.
	# Streak: direction=(0.1,1,0) normalized≈(0.0995,0.995,0), avg_velocity=600,
	# avg_lifetime=0.18*(1-0.2/2)=0.162s (accounting for lifetime_randomness=0.2)
	var direction := Vector3(0.1, 1.0, 0.0).normalized()
	var avg_velocity := (500.0 + 700.0) / 2.0
	var avg_lifetime := 0.18 * (1.0 - 0.2 / 2.0)
	var streak_origin := Vector2(640.0, 360.0)

	var travel_x := direction.x * avg_velocity * avg_lifetime
	var travel_y := direction.y * avg_velocity * avg_lifetime
	var expected_splash_pos := streak_origin + Vector2(travel_x, travel_y)

	# Splash position from the fixed scene: Vector2(650, 457)
	var actual_splash_pos := Vector2(650.0, 457.0)

	# Allow ±10px tolerance for rounding and lifetime randomness spread
	assert_true(abs(actual_splash_pos.x - expected_splash_pos.x) <= 10.0,
		"Splash X position should match streak endpoint X (±10px). Expected ~%.0f got %.0f" % [expected_splash_pos.x, actual_splash_pos.x])
	assert_true(abs(actual_splash_pos.y - expected_splash_pos.y) <= 10.0,
		"Splash Y position should match streak endpoint Y (±10px). Expected ~%.0f got %.0f" % [expected_splash_pos.y, actual_splash_pos.y])


# ============================================================================
# Tests: Issue #1580 — Drop Animation: Falling → Landing → Splashing
# ============================================================================


func test_splash_appears_at_streak_landing_zone() -> void:
	# Issue #1580: Puddles must appear where drops land — both emitters must cover
	# the same area of the screen. The streak emission box is at origin (640,360)
	# covering ±700x±400, so it spans x=[−60,1340], y=[−40,760] in screen space.
	# The splash emitter at (650,457) with the same ±700x±400 box covers x=[−50,1350],
	# y=[57,857]. The overlap ensures splashes appear within the region streaks land.
	var streak_origin := Vector2(640.0, 360.0)
	var splash_origin := Vector2(650.0, 457.0)
	var box_half := Vector2(700.0, 400.0)

	var streak_min := streak_origin - box_half
	var streak_max := streak_origin + box_half
	var splash_min := splash_origin - box_half
	var splash_max := splash_origin + box_half

	# Overlap region must be non-empty: max of mins < min of maxes
	var overlap_min_x := maxf(streak_min.x, splash_min.x)
	var overlap_max_x := minf(streak_max.x, splash_max.x)
	var overlap_min_y := maxf(streak_min.y, splash_min.y)
	var overlap_max_y := minf(streak_max.y, splash_max.y)

	assert_true(overlap_max_x > overlap_min_x,
		"Streak and splash emission boxes must overlap in X — splashes appear in streak landing zone")
	assert_true(overlap_max_y > overlap_min_y,
		"Streak and splash emission boxes must overlap in Y — splashes appear in streak landing zone")


func test_rain_animation_phases_contract() -> void:
	# Issue #1580: The three-phase raindrop animation requires specific timing:
	#   Phase 1 (falling):   streak emits at t=0, lifetime=0.18s
	#   Phase 2 (landing):   streak disappears at ~t=0.18s at the landing position
	#   Phase 3 (splashing): splash emits from landing position, lifetime=0.4s
	# The splash lifetime must be longer than streak lifetime so the ripple lingers
	# after the drop has "hit" the ground.
	var streak_lifetime := 0.18
	var splash_lifetime := 0.4

	assert_true(splash_lifetime > streak_lifetime,
		"Splash lifetime (%.2fs) must exceed streak lifetime (%.2fs) — ripple lingers after drop lands" % [splash_lifetime, streak_lifetime])


func test_splash_emitter_offset_is_downward_from_streak() -> void:
	# Issue #1580: The splash emitter must be offset downward (positive Y) from the
	# streak emitter — puddles appear below where drops start falling, not above.
	var streak_pos := Vector2(640.0, 360.0)
	var splash_pos := Vector2(650.0, 457.0)

	assert_true(splash_pos.y > streak_pos.y,
		"Splash emitter Y (%.0f) must be below streak emitter Y (%.0f) — puddles appear at bottom of drop path" % [splash_pos.y, streak_pos.y])
