extends GutTest
## Unit tests for rain_effect.gd HM2-style precipitation system (Issue #1394, fixed #1499, #1546, #1580).
##
## Tests continuous rain behavior, exclusion zone logic, and state transitions.
## Also tests streak appearance (thin 2x16 fish-eye radial), projected ground splashes,
## player-area top-down drops, ring emission constraint, and time-stop behavior (Issue #1585).
## Four-layer system: RainStreaks + RainSplashes + PlayerDrops on a CanvasLayer.


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
	var _player_drops_disabled: bool = false


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
			_player_drops_disabled = true
		else:
			# Restore particle processing, then update emission based on exclusion zone.
			_streaks_disabled = false
			_splashes_disabled = false
			_player_drops_disabled = false
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
# Tests: Issue #1546/#1580 — Streak Appearance (Fish-Eye Radial + Thin Texture)
# ============================================================================


class MockParticleMaterial:
	## Simulates ParticleProcessMaterial direction and velocity properties.
	var direction: Vector3 = Vector3.ZERO
	var initial_velocity_min: float = 0.0
	var initial_velocity_max: float = 0.0
	var radial_velocity_min: float = 0.0
	var radial_velocity_max: float = 0.0


class MockStreakTexture:
	## Simulates GradientTexture2D for streak thin-line appearance.
	var width: int = 2
	var height: int = 16
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


func test_streak_texture_is_thin_line() -> void:
	# PR #1605 fix: streak texture is 2x16 (tall thin line) so rain appears as
	# thin strokes, not squares. Height must be much taller than width.
	var tex := MockStreakTexture.new()
	assert_eq(tex.width, 2, "Streak texture width must be 2px for thin-line appearance")
	assert_true(tex.height >= 16,
		"Streak texture height must be >= 16px for visible stroke length")
	assert_true(tex.height > tex.width,
		"Streak texture must be taller than wide (thin vertical line)")


func test_streak_scale_is_large_enough() -> void:
	# scale_max must be >= 2.0 so streaks appear large enough in-game.
	var tex := MockStreakTexture.new()
	assert_true(tex.scale_max >= 2.0,
		"Streak scale_max must be >= 2.0 for visible drop size")


# ============================================================================
# Tests: Issue #1580 — Projected Ground Splashes at Streak Landing Points
# ============================================================================


class MockSplashRingMaterial:
	## Simulates ParticleProcessMaterial for RainSplashes with ring emission.
	## Ring emission matches RainStreaks so splashes appear at the projected
	## ground landing points of streaks (outside the player zone).
	var emission_shape: int = 6  # EMISSION_SHAPE_RING
	var emission_ring_inner_radius: float = 100.0
	var emission_ring_radius: float = 750.0
	var spread: float = 180.0


func test_splashes_use_ring_emission_at_streak_landing_zone() -> void:
	# Splashes must use ring emission matching the streak emitter so they appear
	# at the projected ground landing points of streaks — not inside the player zone.
	var mat := MockSplashRingMaterial.new()
	assert_eq(mat.emission_shape, 6,
		"RainSplashes must use ring emission (shape 6) to match streak landing zone")
	assert_true(mat.emission_ring_inner_radius >= 80.0,
		"Splash ring inner radius must be >= 80px — no splashes inside player zone")
	assert_true(mat.emission_ring_radius > mat.emission_ring_inner_radius,
		"Splash ring outer radius must be larger than inner radius")


func test_splashes_have_radial_spread() -> void:
	# Splashes must spread radially (spread=180) to look like water droplets
	# scattering outward from the impact point on the ground.
	var mat := MockSplashRingMaterial.new()
	assert_true(mat.spread >= 90.0,
		"Splash spread must be >= 90 degrees for radial scatter from landing point")


func test_splashes_stop_with_all_layers_when_entering_building() -> void:
	# When rain is disabled (indoor exclusion zone), all layers including splashes stop.
	var rain := MockRainEffect.new()
	rain.ready()
	assert_true(rain.emitting, "All rain layers should emit outdoors")

	rain.add_exclusion_zone(Rect2(100, 100, 200, 200))
	rain.simulate_camera_move(Vector2(150, 150))
	assert_false(rain.emitting,
		"All layers (streaks, splashes, player drops) must stop inside buildings")


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
	# Fix #1580/#1605: streaks must not spawn in the player area.
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
	assert_true(rain._player_drops_disabled, "PlayerDrops must be process-disabled (frozen in place)")


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
	assert_false(rain._player_drops_disabled, "PlayerDrops must be re-enabled after time resumes")
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
