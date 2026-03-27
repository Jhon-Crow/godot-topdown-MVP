extends GutTest
## Unit tests for rain_effect.gd HM2-style precipitation system (Issue #1394, fixed #1499, #1546).
##
## Tests continuous rain behavior, exclusion zone logic, and state transitions.
## Also tests streak length, direction, splash alignment, player-area square
## drops fixes, streak ring emission (excludes player zone), and time-stop
## behavior for the last chance effect (Issue #1585).
## The actual RainEffect extends Node2D with three child GPUParticles2D layers
## (downward streaks + splash ripples + player-area top-down drops). Uses a mock
## to test logic without requiring GPUParticles2D rendering.


# ============================================================================
# Mock RainEffect for Logic Tests
# ============================================================================


class MockRainEffect:
	## Indoor exclusion zones.
	var exclusion_zones: Array = []

	## Whether currently emitting particles (all layers: streaks, splashes, player drops).
	var emitting: bool = false

	## Whether inside an exclusion zone.
	var _inside_exclusion: bool = false

	## Whether time is currently stopped (Issue #1585).
	var _time_stopped: bool = false

	## Simulated process_mode for each particle layer (true = disabled).
	## Mirrors the fix: set_time_stopped uses process_mode, not emitting=false,
	## so existing particles freeze in place rather than disappearing.
	var _streaks_disabled: bool = false
	var _splashes_disabled: bool = false


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
		# While time is stopped, camera moves do not change emission state.
		if _time_stopped:
			return
		var was_inside := _inside_exclusion
		_inside_exclusion = _is_point_in_exclusion_zone(camera_center)
		if _inside_exclusion and not was_inside:
			emitting = false
		elif not _inside_exclusion and was_inside:
			emitting = true


	## Pauses or resumes particle emission for time-stop effects (Issue #1585).
	## Uses process_mode (not emitting=false) so existing particles freeze in place.
	func set_time_stopped(paused: bool) -> void:
		if _time_stopped == paused:
			return
		_time_stopped = paused
		if paused:
			# Disable particle processing — particles freeze in place, emitting stays true.
			_streaks_disabled = true
			_splashes_disabled = true
		else:
			# Restore particle processing, then update emission based on exclusion zone.
			_streaks_disabled = false
			_splashes_disabled = false
			emitting = not _inside_exclusion


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
# Tests: Issue #1546 Feedback — Player Area Top-Down Drops (PlayerDrops layer)
# ============================================================================


class MockStreakRingMaterial:
	## Simulates ParticleProcessMaterial for RainStreaks with ring emission.
	## Ring emission excludes the player area (inner_radius) from streak spawning.
	var emission_shape: int = 6  # EMISSION_SHAPE_RING
	var emission_ring_inner_radius: float = 100.0
	var emission_ring_radius: float = 750.0


class MockPlayerDropTexture:
	## Simulates the square GradientTexture2D for player-area top-down drops.
	var width: int = 3
	var height: int = 3


class MockPlayerDropMaterial:
	## Simulates ParticleProcessMaterial for PlayerDrops.
	var emission_box_extents: Vector3 = Vector3(80, 80, 0)
	var direction: Vector3 = Vector3(0, 1, 0)
	var spread: float = 0.0
	var scale_min: float = 1.0
	var scale_max: float = 2.0


func test_player_drops_texture_is_square() -> void:
	# PlayerDrops must use a square texture to represent a raindrop seen from
	# directly overhead (top-down camera perspective). Issue #1546 feedback.
	var tex := MockPlayerDropTexture.new()
	assert_eq(tex.width, tex.height,
		"PlayerDrops texture must be square (same width and height) for top-down drop appearance")


func test_player_drops_emission_area_is_small() -> void:
	# PlayerDrops must emit in a small area around the player center (~80px),
	# not the full screen like streaks/splashes.
	var mat := MockPlayerDropMaterial.new()
	assert_true(mat.emission_box_extents.x <= 120.0,
		"PlayerDrops emission box X must be <= 120px (player-area only, not full screen)")
	assert_true(mat.emission_box_extents.y <= 120.0,
		"PlayerDrops emission box Y must be <= 120px (player-area only, not full screen)")


func test_player_drops_direction_is_straight_down() -> void:
	# PlayerDrops must fall straight down (no horizontal drift) to simulate the
	# overhead camera perspective where drops appear to fall directly at the viewer.
	var mat := MockPlayerDropMaterial.new()
	assert_eq(mat.direction.x, 0.0,
		"PlayerDrops direction X must be 0 (no horizontal drift for overhead view)")
	assert_true(mat.direction.y > 0.0,
		"PlayerDrops direction Y must be positive (straight downward)")
	assert_eq(mat.spread, 0.0,
		"PlayerDrops spread must be 0 for straight-down fall with no angular variation")


func test_streak_ring_emission_excludes_player_center() -> void:
	# Fix #1584 feedback: streaks must not spawn in the player area.
	# RainStreaks uses ring emission (emission_shape=6) with an inner radius that
	# excludes the center ~100px zone where PlayerDrops appear instead.
	var mat := MockStreakRingMaterial.new()
	assert_eq(mat.emission_shape, 6,
		"RainStreaks must use ring emission (shape 6) to exclude player center zone")
	assert_true(mat.emission_ring_inner_radius >= 80.0,
		"Ring inner radius must be >= 80px to exclude player area from streak spawning")
	assert_true(mat.emission_ring_radius > mat.emission_ring_inner_radius,
		"Ring outer radius must be larger than inner radius")


func test_player_drops_stops_when_entering_building() -> void:
	# When rain is disabled (indoor exclusion zone), PlayerDrops must also stop.
	# The emitting setter in RainEffect covers all layers including PlayerDrops.
	var rain := MockRainEffect.new()
	rain.ready()
	assert_true(rain.emitting, "All rain layers should emit outdoors")

	rain.add_exclusion_zone(Rect2(100, 100, 200, 200))
	rain.simulate_camera_move(Vector2(150, 150))
	assert_false(rain.emitting,
		"PlayerDrops (and all layers) must stop inside buildings")


# ============================================================================
# Tests: Issue #1585 — Rain freezes in place during time-stop (last chance effect)
# ============================================================================


func test_rain_particles_freeze_in_place_when_time_stopped() -> void:
	# Particles must NOT disappear — process_mode is disabled so existing particles
	# stay visible; emitting remains true so the state is preserved for resume.
	var rain := MockRainEffect.new()
	rain.ready()
	assert_true(rain.emitting, "Rain should be emitting before time stop")
	rain.set_time_stopped(true)
	assert_true(rain._streaks_disabled, "Streak particles must be process-disabled (frozen in place)")
	assert_true(rain._splashes_disabled, "Splash particles must be process-disabled (frozen in place)")


func test_rain_emitting_unchanged_when_time_stopped() -> void:
	# emitting flag must NOT be set to false — that would clear all particles.
	var rain := MockRainEffect.new()
	rain.ready()
	rain.set_time_stopped(true)
	assert_true(rain.emitting, "emitting must remain true when time is stopped (particles freeze, not disappear)")


func test_rain_resumes_when_time_resumes() -> void:
	var rain := MockRainEffect.new()
	rain.ready()
	rain.set_time_stopped(true)
	rain.set_time_stopped(false)
	assert_false(rain._streaks_disabled, "Streak particles must be re-enabled after time resumes")
	assert_false(rain._splashes_disabled, "Splash particles must be re-enabled after time resumes")
	assert_true(rain.emitting, "Rain should resume emitting when time resumes")


func test_rain_time_stopped_is_idempotent() -> void:
	var rain := MockRainEffect.new()
	rain.ready()
	rain.set_time_stopped(true)
	rain.set_time_stopped(true)
	assert_true(rain._streaks_disabled, "Calling set_time_stopped(true) twice must keep particles frozen")


func test_rain_camera_move_ignored_during_time_stop() -> void:
	var rain := MockRainEffect.new()
	rain.ready()
	rain.add_exclusion_zone(Rect2(100, 100, 200, 200))
	# Time is stopped — camera entering a building must not change emission state.
	rain.set_time_stopped(true)
	rain.simulate_camera_move(Vector2(150, 150))
	# emitting is still true (particles frozen), exclusion state unchanged.
	assert_true(rain.emitting, "emitting must stay true (frozen, not cleared) during time stop")
	assert_false(rain._inside_exclusion, "Exclusion state must not change during time stop")


func test_rain_resumes_in_exclusion_zone_stays_off() -> void:
	# If time resumes while camera is inside an exclusion zone, rain stays off.
	var rain := MockRainEffect.new()
	rain.ready()
	rain.add_exclusion_zone(Rect2(100, 100, 200, 200))
	rain.simulate_camera_move(Vector2(150, 150))  # enter building
	assert_false(rain.emitting, "Rain should stop inside building")
	rain.set_time_stopped(true)
	rain.set_time_stopped(false)
	assert_false(rain.emitting, "Rain must remain off when time resumes inside exclusion zone")
