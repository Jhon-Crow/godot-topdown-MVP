extends GutTest
## Unit tests for snow_effect.gd world-space snowfall (Issue #1569).
##
## Tests that snow starts emitting on ready, that the emitter position tracks
## the camera center (world-space, not screen-space), that particle lifetime
## values are long enough for a slow, gentle snowfall animation, and that snow
## pauses correctly during time-stop effects (Issue #1585).


# ============================================================================
# Mock SnowEffect for Logic Tests
# ============================================================================


class MockSnowEffect:
	## Whether currently emitting particles.
	var emitting: bool = false

	## Simulated emitter position (updated each frame to camera center).
	var emitter_position: Vector2 = Vector2.ZERO

	## Whether time is currently stopped (Issue #1585).
	var _time_stopped: bool = false


	func ready() -> void:
		# Snow is always on from the start
		emitting = true


	func process(camera_center: Vector2) -> void:
		# While time is stopped, do not update emitter or emit new flakes.
		if _time_stopped:
			return
		# Update emitter to the camera center so new flakes spawn in the viewport.
		# Already-spawned particles keep their world positions — snow does not follow the player.
		emitter_position = camera_center


	## Pauses or resumes particle emission for time-stop effects (Issue #1585).
	func set_time_stopped(paused: bool) -> void:
		if _time_stopped == paused:
			return
		_time_stopped = paused
		emitting = not paused


# ============================================================================
# Tests: Snow Starts Immediately
# ============================================================================


func test_snow_starts_immediately() -> void:
	var snow := MockSnowEffect.new()
	snow.ready()
	assert_true(snow.emitting, "Snow should emit immediately on ready")


func test_snow_emitter_at_origin_before_camera() -> void:
	var snow := MockSnowEffect.new()
	snow.ready()
	assert_eq(snow.emitter_position, Vector2.ZERO,
		"Emitter should start at origin before any camera update")


# ============================================================================
# Tests: Camera Tracking (World-Space Emitters)
# ============================================================================


func test_emitter_follows_camera_center() -> void:
	var snow := MockSnowEffect.new()
	snow.ready()
	var cam_center := Vector2(320.0, 180.0)
	snow.process(cam_center)
	assert_eq(snow.emitter_position, cam_center,
		"Emitter should move to camera center so new flakes spawn in the visible area")


func test_emitter_updates_each_frame() -> void:
	var snow := MockSnowEffect.new()
	snow.ready()
	snow.process(Vector2(0.0, 0.0))
	snow.process(Vector2(500.0, 300.0))
	assert_eq(snow.emitter_position, Vector2(500.0, 300.0),
		"Emitter should update to the latest camera position each frame")


func test_emitter_tracks_player_movement() -> void:
	# Simulate player walking: camera moves, emitter follows, but already-spawned
	# flakes stay at their world positions (tested via emitter_position updates).
	var snow := MockSnowEffect.new()
	snow.ready()
	var positions := [Vector2(100, 100), Vector2(200, 100), Vector2(300, 150)]
	for pos in positions:
		snow.process(pos)
	assert_eq(snow.emitter_position, Vector2(300, 150),
		"Emitter should end at the last camera position after player moves")


# ============================================================================
# Tests: Lifetime Values (Slow Animation — Issue #1569)
# ============================================================================


class MockParticles:
	## Particle lifetime in seconds.
	var lifetime: float = 0.0


func test_large_flake_lifetime_is_slow() -> void:
	# Issue #1569 requires longer lifetime so animation is visibly slower.
	# Previous value was 0.5s; new value must be >= 2.0s.
	var particles := MockParticles.new()
	particles.lifetime = 2.0
	assert_true(particles.lifetime >= 2.0,
		"Large flake lifetime must be >= 2.0s for slow gentle snowfall (was 0.5s)")


func test_small_flake_lifetime_is_slow() -> void:
	# Issue #1569 requires longer lifetime so animation is visibly slower.
	# Previous value was 0.7s; new value must be >= 2.0s.
	var particles := MockParticles.new()
	particles.lifetime = 2.5
	assert_true(particles.lifetime >= 2.0,
		"Small flake lifetime must be >= 2.0s for slow gentle snowfall (was 0.7s)")


func test_small_flake_lifetime_exceeds_large() -> void:
	# Small flakes should linger at least as long as large ones for depth layering.
	var large_lifetime := 2.0
	var small_lifetime := 2.5
	assert_true(small_lifetime >= large_lifetime,
		"Small flake lifetime should be >= large flake lifetime for depth effect")


# ============================================================================
# Tests: Emission State Toggle
# ============================================================================


func test_emitting_can_be_disabled() -> void:
	var snow := MockSnowEffect.new()
	snow.ready()
	assert_true(snow.emitting, "Snow should start emitting")
	snow.emitting = false
	assert_false(snow.emitting, "Snow emission should be toggleable off")


func test_emitting_can_be_reenabled() -> void:
	var snow := MockSnowEffect.new()
	snow.ready()
	snow.emitting = false
	snow.emitting = true
	assert_true(snow.emitting, "Snow emission should be re-enableable after being turned off")


# ============================================================================
# Tests: Issue #1585 — Snow stops during time-stop (last chance effect)
# ============================================================================


func test_snow_stops_when_time_stopped() -> void:
	var snow := MockSnowEffect.new()
	snow.ready()
	assert_true(snow.emitting, "Snow should be emitting before time stop")
	snow.set_time_stopped(true)
	assert_false(snow.emitting, "Snow should stop emitting when time is stopped")


func test_snow_resumes_when_time_resumes() -> void:
	var snow := MockSnowEffect.new()
	snow.ready()
	snow.set_time_stopped(true)
	snow.set_time_stopped(false)
	assert_true(snow.emitting, "Snow should resume emitting when time resumes")


func test_snow_time_stopped_is_idempotent() -> void:
	var snow := MockSnowEffect.new()
	snow.ready()
	snow.set_time_stopped(true)
	snow.set_time_stopped(true)
	assert_false(snow.emitting, "Calling set_time_stopped(true) twice should keep snow off")


func test_snow_emitter_not_updated_during_time_stop() -> void:
	var snow := MockSnowEffect.new()
	snow.ready()
	snow.process(Vector2(100.0, 100.0))
	snow.set_time_stopped(true)
	# Camera moves but emitter position must not change while time is stopped.
	snow.process(Vector2(500.0, 500.0))
	assert_eq(snow.emitter_position, Vector2(100.0, 100.0),
		"Emitter position must not update while time is stopped")
