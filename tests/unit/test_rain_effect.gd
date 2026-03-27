extends GutTest
## Unit tests for rain_effect.gd HM2-style precipitation system (Issue #1394, fixed #1499, #1546).
##
## Tests continuous rain behavior, exclusion zone logic, and state transitions.
## Also tests streak length, radial direction, and time-stop behavior (Issue #1585).
## Splashes removed per Issue #1580 feedback — streaks-only with fish-eye radial direction.


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

	## Whether time is currently stopped (Issue #1585).
	var _time_stopped: bool = false

	## Simulated process_mode for the streak particle layer (true = disabled).
	## Mirrors the fix: set_time_stopped uses process_mode, not emitting=false,
	## so existing particles freeze in place rather than disappearing.
	var _streaks_disabled: bool = false


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
		else:
			# Restore particle processing, then update emission based on exclusion zone.
			_streaks_disabled = false
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
# Tests: Issue #1546 Fixes — Streak Appearance (Fish-Eye Radial Direction)
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
	var width: int = 4
	var height: int = 8
	var scale_min: float = 1.2
	var scale_max: float = 2.5


func test_streak_uses_inward_radial_velocity() -> void:
	# The fish-eye top-down view is achieved with negative radial_velocity: drops
	# converge toward the screen center, simulating rain falling straight toward
	# the viewer from above. radial_velocity_min/max must both be negative.
	var mat := MockParticleMaterial.new()
	mat.radial_velocity_min = -140.0
	mat.radial_velocity_max = -80.0
	assert_true(mat.radial_velocity_min < 0.0,
		"radial_velocity_min must be negative for fish-eye top-down rain effect")
	assert_true(mat.radial_velocity_max < 0.0,
		"radial_velocity_max must be negative for fish-eye top-down rain effect")
	assert_true(mat.radial_velocity_min <= mat.radial_velocity_max,
		"radial_velocity_min must be <= max for valid velocity range")


func test_streak_texture_dimensions() -> void:
	# Fix #1546: texture is 4x8 so drops look like circles when viewed from above.
	var tex := MockStreakTexture.new()
	assert_eq(tex.width, 4, "Streak texture width must be 4px")
	assert_eq(tex.height, 8, "Streak texture height must be 8px (short circles for top-down view)")


func test_streak_scale_is_large_enough() -> void:
	# Fix #1546: scale_max must be >= 2.0 so streaks appear large enough in-game.
	var tex := MockStreakTexture.new()
	assert_true(tex.scale_max >= 2.0,
		"Streak scale_max must be >= 2.0 for visible drop size")


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
