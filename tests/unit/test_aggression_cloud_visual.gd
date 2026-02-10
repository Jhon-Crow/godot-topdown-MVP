extends GutTest
## Tests for aggression gas cloud visual effects (Issue #718).
##
## Validates that the gas cloud has proper visibility and uses particle system.

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


func test_particle_effect_scene_exists() -> void:
	# Given: The particle effect scene path
	var scene_path := "res://scenes/effects/AggressionCloudEffect.tscn"

	# Then: Scene file should exist and be loadable
	assert_file_exists(scene_path)

	var scene := load(scene_path)
	assert_not_null(scene, "AggressionCloudEffect scene should load")

	var instance := scene.instantiate()
	assert_not_null(instance, "Scene should instantiate")
	assert_true(instance is GPUParticles2D, "Root node should be GPUParticles2D")
	instance.queue_free()


func test_particle_has_proper_z_index() -> void:
	# Given: The particle effect scene
	var scene := load("res://scenes/effects/AggressionCloudEffect.tscn")
	var particles := scene.instantiate() as GPUParticles2D
	add_child_autofree(particles)

	# Then: Z-index should be 1 or higher (not -1 which was the bug)
	assert_gt(particles.z_index, -1, "Particles should draw above ground (z_index > -1)")
	assert_eq(particles.z_index, 1, "Particles should have z_index = 1")


func test_particle_uses_continuous_emission() -> void:
	# Given: The particle effect scene
	var scene := load("res://scenes/effects/AggressionCloudEffect.tscn")
	var particles := scene.instantiate() as GPUParticles2D
	add_child_autofree(particles)

	# Then: Should NOT be one_shot (needs continuous emission for 20s cloud)
	# Note: Scene has emitting=false by default, cloud enables it
	assert_false(particles.one_shot, "Particles should emit continuously, not one-shot")


func test_particle_has_sufficient_amount() -> void:
	# Given: The particle effect scene
	var scene := load("res://scenes/effects/AggressionCloudEffect.tscn")
	var particles := scene.instantiate() as GPUParticles2D
	add_child_autofree(particles)

	# Then: Should have enough particles for visible cloud (not just a few)
	assert_gte(particles.amount, 50, "Should have at least 50 particles for visibility")


func test_particle_has_proper_lifetime() -> void:
	# Given: The particle effect scene
	var scene := load("res://scenes/effects/AggressionCloudEffect.tscn")
	var particles := scene.instantiate() as GPUParticles2D
	add_child_autofree(particles)

	# Then: Particle lifetime should be 4-6 seconds (balance between coverage and performance)
	assert_gte(particles.lifetime, 4.0, "Particle lifetime should be at least 4s")
	assert_lte(particles.lifetime, 6.0, "Particle lifetime should be at most 6s")


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
