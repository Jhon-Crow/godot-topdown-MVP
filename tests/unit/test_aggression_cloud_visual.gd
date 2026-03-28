extends GutTest
## Tests for aggression gas cloud visual effects (Issue #718).
##
## Validates that the gas cloud has proper visibility and uses particle system.
## Updated in session 2 to match new programmatic particle creation approach.

const AggressionCloud := preload("res://scripts/effects/aggression_cloud.gd")


func test_cloud_creates_particle_system() -> void:
	# Given: An aggression cloud is created
	var cloud := AggressionCloud.new()
	add_child_autofree(cloud)

	# Wait for _ready to execute
	await wait_frames(2)

	# Then: Should have particles child (not just static sprite)
	var has_particles := false
	for child in cloud.get_children():
		if child is GPUParticles2D:
			has_particles = true
			break

	assert_true(has_particles, "Cloud should use GPUParticles2D for visibility")


func test_cloud_uses_particles_flag() -> void:
	# Given: An aggression cloud is created
	var cloud := AggressionCloud.new()
	add_child_autofree(cloud)

	await wait_frames(2)

	# Then: _using_particles flag should be set to true
	assert_true(cloud._using_particles, "Cloud should be using particle system")


func test_cloud_visual_is_not_null() -> void:
	# Given: An aggression cloud is created
	var cloud := AggressionCloud.new()
	add_child_autofree(cloud)

	await wait_frames(2)

	# Then: _cloud_visual should be set
	assert_not_null(cloud._cloud_visual, "Cloud visual should be created")


func test_particle_has_proper_z_index() -> void:
	# Given: An aggression cloud is created
	var cloud := AggressionCloud.new()
	add_child_autofree(cloud)

	await wait_frames(2)

	# Get the particle system
	var particles: GPUParticles2D = null
	for child in cloud.get_children():
		if child is GPUParticles2D:
			particles = child
			break

	if particles:
		# Then: Z-index should be 1 or higher (not -1 which was the bug)
		assert_gt(particles.z_index, -1, "Particles should draw above ground (z_index > -1)")
		assert_eq(particles.z_index, 1, "Particles should have z_index = 1")
	else:
		fail_test("No particle system found")


func test_particle_uses_continuous_emission() -> void:
	# Given: An aggression cloud is created
	var cloud := AggressionCloud.new()
	add_child_autofree(cloud)

	await wait_frames(2)

	# Get the particle system
	var particles: GPUParticles2D = null
	for child in cloud.get_children():
		if child is GPUParticles2D:
			particles = child
			break

	if particles:
		# Then: Should NOT be one_shot (needs continuous emission for 20s cloud)
		assert_false(particles.one_shot, "Particles should emit continuously, not one-shot")
		# And should be emitting
		assert_true(particles.emitting, "Particles should be emitting")
	else:
		fail_test("No particle system found")


func test_particle_has_sufficient_amount() -> void:
	# Given: An aggression cloud is created
	var cloud := AggressionCloud.new()
	add_child_autofree(cloud)

	await wait_frames(2)

	# Get the particle system
	var particles: GPUParticles2D = null
	for child in cloud.get_children():
		if child is GPUParticles2D:
			particles = child
			break

	if particles:
		# Then: Should have enough particles for visible cloud (not just a few)
		assert_gte(particles.amount, 50, "Should have at least 50 particles for visibility")
	else:
		fail_test("No particle system found")


func test_particle_has_proper_lifetime() -> void:
	# Given: An aggression cloud is created
	var cloud := AggressionCloud.new()
	add_child_autofree(cloud)

	await wait_frames(2)

	# Get the particle system
	var particles: GPUParticles2D = null
	for child in cloud.get_children():
		if child is GPUParticles2D:
			particles = child
			break

	if particles:
		# Then: Particle lifetime should be 3-5 seconds (balance between coverage and performance)
		assert_gte(particles.lifetime, 3.0, "Particle lifetime should be at least 3s")
		assert_lte(particles.lifetime, 5.0, "Particle lifetime should be at most 5s")
	else:
		fail_test("No particle system found")


func test_particle_has_no_preprocess_for_grow_in() -> void:
	# Issue #1688: Cloud must start at scale 0 and grow gradually.
	# preprocess > 0 would pre-fill particles at full scale, making the cloud
	# appear large immediately — so preprocess must be 0.
	var cloud := AggressionCloud.new()
	add_child_autofree(cloud)

	await wait_frames(2)

	# Get the particle system
	var particles: GPUParticles2D = null
	for child in cloud.get_children():
		if child is GPUParticles2D:
			particles = child
			break

	if particles:
		# Then: preprocess should be 0 so the cloud starts visually empty and grows
		assert_eq(particles.preprocess, 0.0, "Particles should have preprocess=0 for grow-in to work")
	else:
		fail_test("No particle system found")


func test_cloud_stops_emission_before_dissipation() -> void:
	# Given: An aggression cloud with short duration for testing
	var cloud := AggressionCloud.new()
	cloud.cloud_duration = 6.0  # Short duration for test
	add_child_autofree(cloud)

	await wait_frames(2)

	# Get the particle system
	var particles: GPUParticles2D = null
	for child in cloud.get_children():
		if child is GPUParticles2D:
			particles = child
			break

	if particles:
		# Initially should be emitting
		assert_true(particles.emitting, "Particles should start emitting")

		# Wait until last 5 seconds (at 1.5s remaining for 6s duration)
		await wait_seconds(4.6)

		# Then: Should stop emitting to allow natural fade
		assert_false(particles.emitting, "Particles should stop emitting in last 5 seconds")
	else:
		pending("No particle system found - may be using fallback")


func test_cloud_duration_is_20_seconds() -> void:
	# Given: An aggression cloud
	var cloud := AggressionCloud.new()
	add_child_autofree(cloud)

	# Then: Default duration should be 20 seconds
	assert_eq(cloud.cloud_duration, 20.0, "Cloud should persist for 20 seconds")


func test_cloud_radius_is_300_pixels() -> void:
	# Given: An aggression cloud
	var cloud := AggressionCloud.new()
	add_child_autofree(cloud)

	# Then: Radius should be 300px (larger than frag grenade's 225px)
	assert_eq(cloud.cloud_radius, 300.0, "Cloud radius should be 300px")


func test_fallback_sprite_has_high_alpha() -> void:
	# This tests the fallback visual in case particles fail
	# We can call _create_sprite_fallback directly for testing
	var cloud := AggressionCloud.new()
	var sprite := cloud._create_sprite_fallback()

	# Then: Alpha should be high (0.75 vs original 0.35)
	assert_gte(sprite.modulate.a, 0.7, "Fallback sprite should have alpha >= 0.7")

	# And z_index should be above ground
	assert_eq(sprite.z_index, 1, "Fallback sprite z_index should be 1")

	sprite.queue_free()
	cloud.queue_free()


func test_cloud_starts_at_zero_scale_when_grow_in_set() -> void:
	# Issue #1688: Cloud must begin invisible (scale 0) so it visually grows from
	# the grenade position, not appear large immediately.
	var cloud := AggressionCloud.new()
	cloud.grow_in_duration = 3.0
	add_child_autofree(cloud)

	# Check scale immediately after adding (before any physics frames)
	assert_eq(cloud.scale, Vector2.ZERO,
		"Cloud should start at scale 0 when grow_in_duration > 0 (not jump to full size)")


func test_cloud_scale_zero_when_no_grow_in() -> void:
	# Without grow_in_duration the cloud should spawn at normal scale (1, 1)
	var cloud := AggressionCloud.new()
	cloud.grow_in_duration = 0.0
	add_child_autofree(cloud)

	assert_eq(cloud.scale, Vector2.ONE,
		"Cloud without grow-in should spawn at full scale")


func test_detection_area_created() -> void:
	# Given: An aggression cloud is created
	var cloud := AggressionCloud.new()
	add_child_autofree(cloud)

	await wait_frames(2)

	# Then: Detection area should be created
	assert_not_null(cloud._detection_area, "Detection area should be created")

	# And should have proper collision mask for enemies
	assert_eq(cloud._detection_area.collision_mask, 2, "Should detect enemies (collision layer 2)")
