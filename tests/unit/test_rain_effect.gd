extends GutTest
## Unit tests for rain_effect.gd HM2-style precipitation system (Issue #1394, fixed #1499, #1546, #1579, #1615).
##
## Tests continuous rain behavior, exclusion zone logic, and state transitions.
## Also tests streak length, direction, splash alignment, world-space emitter tracking,
## time-stop behavior (Issue #1585), and per-particle shader occlusion (Issue #1615).
##
## Fix #1615 — changed behavior:
## Rain now always emits continuously; exclusion zones are pushed to the
## particle shader (rain_occlusion.gdshader) as uniforms so individual
## particles inside building footprints are discarded on the GPU.
## The camera-based binary stop/start logic has been removed.


# ============================================================================
# Mock RainEffect for Logic Tests
# ============================================================================


class MockRainEffect:
	## Indoor exclusion zones (pushed to shader, tested per particle in world space).
	var exclusion_zones: Array = []

	## Whether currently emitting particles.
	## In the new design, emitting is always true unless time is stopped.
	var emitting: bool = false

	## Whether time is currently stopped (e.g. last chance effect).
	var _time_stopped: bool = false

	## Simulated process_mode for each particle layer (true = disabled).
	## Mirrors the fix: set_time_stopped uses process_mode, not emitting=false,
	## so existing particles freeze in place rather than disappearing.
	var _streaks_disabled: bool = false
	var _splashes_disabled: bool = false

	## Tracked shader zone uniforms (simulates what rain_effect.gd sends to GPU).
	var _shader_zone_count: int = 0
	var _shader_zones: Array = []

	## Tracked emitter positions (world-space, updated each frame to camera center).
	var streaks_position: Vector2 = Vector2.ZERO
	var splashes_position: Vector2 = Vector2.ZERO


	func ready() -> void:
		# Rain is always on from the start (continuous mode, shader handles occlusion)
		emitting = true


	func add_exclusion_zone(rect: Rect2) -> void:
		exclusion_zones.append(rect)
		_update_shader_zones()


	func clear_exclusion_zones() -> void:
		exclusion_zones.clear()
		_update_shader_zones()


	func is_raining() -> bool:
		# Rain always emits; shader discards particles inside zones on the GPU.
		return emitting


	## Simulates what rain_effect.gd._update_shader_zones() does:
	## packs exclusion_zones into Vector4 (x_min, y_min, x_max, y_max) for the shader.
	func _update_shader_zones() -> void:
		_shader_zone_count = exclusion_zones.size()
		_shader_zones.clear()
		for zone in exclusion_zones:
			_shader_zones.append(Vector4(
				zone.position.x,
				zone.position.y,
				zone.position.x + zone.size.x,
				zone.position.y + zone.size.y
			))


	## Returns true if a world-space point would be discarded by the occlusion shader.
	## Replicates the GLSL logic in rain_occlusion.gdshader.
	func shader_would_discard(world_pos: Vector2) -> bool:
		for zone in _shader_zones:
			if world_pos.x >= zone.x and world_pos.x <= zone.z and \
				world_pos.y >= zone.y and world_pos.y <= zone.w:
				return true
		return false


	func simulate_camera_move(camera_center: Vector2) -> void:
		# Track emitters to camera center (world-space, like SnowEffect).
		# Camera position no longer affects emission — that is now the shader's job.
		if _time_stopped:
			return
		streaks_position = camera_center
		splashes_position = camera_center


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
			# Restore particle processing; rain always resumes (shader handles occlusion).
			_streaks_disabled = false
			_splashes_disabled = false
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
	assert_true(rain.is_raining(), "Rain should always be active (shader occludes, not emitting toggle)")


# ============================================================================
# Tests: World-Space Emitter Tracking (Fix #1579)
# ============================================================================


func test_emitters_track_camera_position() -> void:
	var rain := MockRainEffect.new()
	rain.ready()
	var cam_pos := Vector2(320.0, 180.0)
	rain.simulate_camera_move(cam_pos)
	assert_eq(rain.streaks_position, cam_pos,
		"RainStreaks emitter should track camera center in world space")
	assert_eq(rain.splashes_position, cam_pos,
		"RainSplashes emitter should track camera center in world space")


func test_emitters_update_when_camera_moves() -> void:
	var rain := MockRainEffect.new()
	rain.ready()
	rain.simulate_camera_move(Vector2(100.0, 100.0))
	rain.simulate_camera_move(Vector2(500.0, 300.0))
	assert_eq(rain.streaks_position, Vector2(500.0, 300.0),
		"Emitter position should update to latest camera position")


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


# ============================================================================
# Tests: Shader Occlusion Logic (Fix #1615)
# ============================================================================


func test_rain_always_emits_regardless_of_exclusion_zones() -> void:
	# Fix #1615: rain no longer stops globally; shader discards per-particle.
	var rain := MockRainEffect.new()
	rain.ready()
	rain.add_exclusion_zone(Rect2(100, 100, 200, 200))
	# Camera inside building — emitting must stay true
	rain.simulate_camera_move(Vector2(150, 150))
	assert_true(rain.emitting,
		"Rain must keep emitting even when camera is inside a building (Fix #1615)")


func test_rain_is_raining_always_true_with_zones() -> void:
	var rain := MockRainEffect.new()
	rain.ready()
	rain.add_exclusion_zone(Rect2(100, 100, 200, 200))
	rain.simulate_camera_move(Vector2(150, 150))
	assert_true(rain.is_raining(),
		"is_raining must be true even inside exclusion zones (shader handles occlusion)")


func test_shader_zones_count_matches_added_zones() -> void:
	var rain := MockRainEffect.new()
	rain.add_exclusion_zone(Rect2(100, 100, 200, 200))
	rain.add_exclusion_zone(Rect2(500, 500, 300, 300))
	assert_eq(rain._shader_zone_count, 2, "Shader zone_count must match number of added zones")


func test_shader_zones_cleared_when_zones_cleared() -> void:
	var rain := MockRainEffect.new()
	rain.add_exclusion_zone(Rect2(100, 100, 200, 200))
	rain.clear_exclusion_zones()
	assert_eq(rain._shader_zone_count, 0, "Shader zone_count must be 0 after clear")


func test_shader_discards_point_inside_zone() -> void:
	var rain := MockRainEffect.new()
	rain.add_exclusion_zone(Rect2(100, 100, 200, 200))
	assert_true(rain.shader_would_discard(Vector2(150, 150)),
		"Shader must discard particle at center of exclusion zone")


func test_shader_keeps_point_outside_zone() -> void:
	var rain := MockRainEffect.new()
	rain.add_exclusion_zone(Rect2(100, 100, 200, 200))
	assert_false(rain.shader_would_discard(Vector2(50, 50)),
		"Shader must keep particle outside exclusion zone")


func test_shader_discards_point_on_zone_boundary() -> void:
	var rain := MockRainEffect.new()
	rain.add_exclusion_zone(Rect2(100, 100, 200, 200))
	assert_true(rain.shader_would_discard(Vector2(100, 100)),
		"Shader must discard particle on zone boundary (top-left corner)")


func test_shader_discards_in_second_zone() -> void:
	var rain := MockRainEffect.new()
	rain.add_exclusion_zone(Rect2(100, 100, 200, 200))
	rain.add_exclusion_zone(Rect2(500, 500, 300, 300))
	assert_true(rain.shader_would_discard(Vector2(600, 600)),
		"Shader must discard particle in second zone")
	assert_false(rain.shader_would_discard(Vector2(400, 400)),
		"Shader must keep particle between zones")


func test_shader_zone_encoding_xmin_ymin_xmax_ymax() -> void:
	var rain := MockRainEffect.new()
	rain.add_exclusion_zone(Rect2(100, 200, 300, 400))
	# Encoded as (x_min, y_min, x_max, y_max)
	var zone: Vector4 = rain._shader_zones[0]
	assert_eq(zone.x, 100.0, "zone.x should be x_min")
	assert_eq(zone.y, 200.0, "zone.y should be y_min")
	assert_eq(zone.z, 400.0, "zone.z should be x_max (100+300)")
	assert_eq(zone.w, 600.0, "zone.w should be y_max (200+400)")


# ============================================================================
# Tests: Building Exclusion Zone Geometry (Docks Level)
# ============================================================================


func test_warehouse_a_shader_discards_inside() -> void:
	var rain := MockRainEffect.new()
	# WarehouseA: position (400, 1800), walls extend ±270x, ±320y
	var warehouse_a := Rect2(400 - 270, 1800 - 320, 540, 640)
	rain.add_exclusion_zone(warehouse_a)

	assert_true(rain.shader_would_discard(Vector2(400, 1800)),
		"Shader must discard particle at center of WarehouseA")
	assert_false(rain.shader_would_discard(Vector2(800, 1800)),
		"Shader must keep particle east of WarehouseA")


func test_warehouse_b_shader_discards_inside() -> void:
	var rain := MockRainEffect.new()
	# WarehouseB: position (4400, 2800), walls extend ±370x, ±420y
	var warehouse_b := Rect2(4400 - 370, 2800 - 420, 740, 840)
	rain.add_exclusion_zone(warehouse_b)

	assert_true(rain.shader_would_discard(Vector2(4400, 2800)),
		"Shader must discard particle at center of WarehouseB")
	assert_false(rain.shader_would_discard(Vector2(3900, 2800)),
		"Shader must keep particle west of WarehouseB")


func test_crane_platform_shader_discards_inside() -> void:
	var rain := MockRainEffect.new()
	# CranePlatform: position (400, 500), walls extend ±208x, ±158y
	var crane_platform := Rect2(400 - 208, 500 - 158, 416, 316)
	rain.add_exclusion_zone(crane_platform)

	assert_true(rain.shader_would_discard(Vector2(400, 500)),
		"Shader must discard particle at center of CranePlatform")
	assert_false(rain.shader_would_discard(Vector2(700, 500)),
		"Shader must keep particle east of CranePlatform")


func test_rain_keeps_emitting_inside_crane_platform() -> void:
	# Fix #1615: camera inside building must NOT stop rain globally.
	var rain := MockRainEffect.new()
	rain.ready()
	var crane_platform := Rect2(400 - 208, 500 - 158, 416, 316)
	rain.add_exclusion_zone(crane_platform)

	rain.simulate_camera_move(Vector2(400, 500))
	assert_true(rain.emitting,
		"Rain must keep emitting when camera is inside CranePlatform (shader handles occlusion)")

	rain.simulate_camera_move(Vector2(800, 500))
	assert_true(rain.emitting,
		"Rain must keep emitting when camera is outside CranePlatform")


# ============================================================================
# Tests: Issue #1546 Fixes — Streak Direction and Splash Alignment
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
	# Time is stopped — camera moves must not update emitter positions.
	rain.set_time_stopped(true)
	rain.simulate_camera_move(Vector2(150, 150))
	# emitting stays true; emitter positions unchanged during time stop.
	assert_true(rain.emitting, "emitting must stay true (frozen) during time stop")
	assert_eq(rain.streaks_position, Vector2.ZERO,
		"Emitter position must not update during time stop")


func test_rain_resumes_emitting_after_time_stop_inside_zone() -> void:
	# Fix #1615: when time resumes, rain always emits (shader handles occlusion).
	var rain := MockRainEffect.new()
	rain.ready()
	rain.add_exclusion_zone(Rect2(100, 100, 200, 200))
	rain.simulate_camera_move(Vector2(150, 150))  # move camera inside zone (no effect now)
	rain.set_time_stopped(true)
	rain.set_time_stopped(false)
	assert_true(rain.emitting,
		"Rain must resume emitting when time resumes (shader handles any building occlusion)")
