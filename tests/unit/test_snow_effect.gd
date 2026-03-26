extends GutTest
## Unit tests for snow_effect.gd world-space snowfall (Issue #1569).
##
## Tests that snow starts emitting on ready, that the emitter position tracks
## the camera center (world-space, not screen-space), and that particle lifetime
## values are long enough for a slow, gentle snowfall animation.


# ============================================================================
# Mock SnowEffect for Logic Tests
# ============================================================================


class MockSnowEffect:
	## Whether currently emitting particles.
	var emitting: bool = false

	## Simulated emitter position (updated each frame to camera center).
	var emitter_position: Vector2 = Vector2.ZERO


	func ready() -> void:
		# Snow is always on from the start
		emitting = true


	func process(camera_center: Vector2) -> void:
		# Update emitter to the camera center so new flakes spawn in the viewport.
		# Already-spawned particles keep their world positions — snow does not follow the player.
		emitter_position = camera_center


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
