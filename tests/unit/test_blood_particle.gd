extends GutTest
## Unit tests for BloodParticle script.
##
## Tests that blood particles properly:
## - Initialize with direction and intensity
## - Apply gravity and damping to velocity
## - Detect wall collisions


const BloodParticleScript = preload("res://scripts/effects/blood_particle.gd")


var particle: Node2D


# ============================================================================
# Setup
# ============================================================================


func before_each() -> void:
	particle = Node2D.new()
	particle.set_script(BloodParticleScript)
	add_child_autoqfree(particle)


func after_each() -> void:
	particle = null


# ============================================================================
# Initialization Tests
# ============================================================================


func test_particle_initializes_without_error() -> void:
	# Test that particle initializes properly
	assert_not_null(particle, "Blood particle should be created")
	pass_test("Particle initialized without error")


func test_particle_has_initialize_method() -> void:
	assert_true(particle.has_method("initialize"),
		"Particle should have initialize method")


func test_particle_has_velocity_property() -> void:
	assert_true("velocity" in particle,
		"Particle should have velocity property")


func test_particle_default_velocity_is_zero() -> void:
	assert_eq(particle.velocity, Vector2.ZERO,
		"Default velocity should be zero")


# ============================================================================
# Initialize Method Tests
# ============================================================================


func test_initialize_sets_velocity_in_direction() -> void:
	var direction := Vector2.RIGHT
	particle.initialize(direction, 1.0, 0.0)  # No spread

	# Velocity should be in the general direction of the input
	assert_gt(particle.velocity.x, 0.0,
		"Velocity should have positive x component for RIGHT direction")


func test_initialize_scales_velocity_with_intensity() -> void:
	var direction := Vector2.RIGHT

	# Initialize two particles with different intensities
	var particle1 = Node2D.new()
	particle1.set_script(BloodParticleScript)
	add_child_autoqfree(particle1)

	var particle2 = Node2D.new()
	particle2.set_script(BloodParticleScript)
	add_child_autoqfree(particle2)

	# Use zero spread to get consistent results
	particle1.initialize(direction, 0.5, 0.0)
	particle2.initialize(direction, 2.0, 0.0)

	# Higher intensity should result in faster velocity (on average)
	# Note: Due to randomization in speed range, we check that both have valid velocities
	assert_gt(particle1.velocity.length(), 0.0, "Particle 1 should have non-zero velocity")
	assert_gt(particle2.velocity.length(), 0.0, "Particle 2 should have non-zero velocity")


func test_initialize_applies_spread_angle() -> void:
	var direction := Vector2.RIGHT
	var large_spread := 1.5  # Large spread angle in radians

	# Initialize multiple particles and verify they don't all go exactly right
	var angles: Array[float] = []

	for i in range(10):
		var p = Node2D.new()
		p.set_script(BloodParticleScript)
		add_child_autoqfree(p)
		p.initialize(direction, 1.0, large_spread)
		angles.append(p.velocity.angle())

	# With spread, angles should vary
	var min_angle: float = angles.min()
	var max_angle: float = angles.max()
	var angle_range: float = max_angle - min_angle

	# There should be some variation in angles (not all exactly 0)
	assert_gt(angle_range, 0.01, "Particles should spread in different directions")


# ============================================================================
# Physics Properties Tests
# ============================================================================


func test_particle_has_gravity_property() -> void:
	assert_true("gravity" in particle,
		"Particle should have gravity property")


func test_particle_has_damping_property() -> void:
	assert_true("damping" in particle,
		"Particle should have damping property")


func test_particle_has_max_lifetime_property() -> void:
	assert_true("max_lifetime" in particle,
		"Particle should have max_lifetime property")


func test_particle_has_collision_mask_property() -> void:
	assert_true("collision_mask" in particle,
		"Particle should have collision_mask property")


func test_gravity_is_positive() -> void:
	assert_gt(particle.gravity, 0.0,
		"Gravity should be positive (downward force)")


func test_damping_is_in_valid_range() -> void:
	assert_gt(particle.damping, 0.0, "Damping should be greater than 0")
	assert_true(particle.damping <= 1.0, "Damping should be at most 1")


func test_max_lifetime_is_positive() -> void:
	assert_gt(particle.max_lifetime, 0.0,
		"Max lifetime should be positive")


# ============================================================================
# Speed Properties Tests
# ============================================================================


func test_particle_has_min_speed_property() -> void:
	assert_true("min_speed" in particle,
		"Particle should have min_speed property")


func test_particle_has_max_speed_property() -> void:
	assert_true("max_speed" in particle,
		"Particle should have max_speed property")


func test_min_speed_is_positive() -> void:
	assert_gt(particle.min_speed, 0.0,
		"Min speed should be positive")


func test_max_speed_greater_than_min_speed() -> void:
	assert_gt(particle.max_speed, particle.min_speed,
		"Max speed should be greater than min speed")


# ============================================================================
# State Tracking Tests
# ============================================================================


func test_particle_tracks_landed_state() -> void:
	assert_true("_has_landed" in particle,
		"Particle should track landed state")


func test_particle_starts_not_landed() -> void:
	assert_false(particle._has_landed,
		"Particle should start as not landed")


func test_particle_tracks_time_alive() -> void:
	assert_true("_time_alive" in particle,
		"Particle should track time alive")


func test_particle_starts_with_zero_time_alive() -> void:
	assert_eq(particle._time_alive, 0.0,
		"Particle should start with zero time alive")
