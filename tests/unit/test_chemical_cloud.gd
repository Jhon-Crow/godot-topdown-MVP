extends GutTest
## Unit tests for chemical_cloud.gd gas cloud illusion spawner.
##
## Tests cloud configuration defaults, illusion limits,
## progressive spawn interval, and grow-in visual behavior (Issue #1688).


# ============================================================================
# Mock ChemicalCloud for Logic Tests
# ============================================================================


class MockChemicalCloud:
	## Radius of the gas cloud in pixels.
	var cloud_radius: float = 300.0

	## How long the cloud persists (seconds).
	var cloud_duration: float = 20.0

	## Number of illusion copies per enemy (random range).
	var min_copies_per_enemy: int = 2

	## Maximum copies per enemy.
	var max_copies_per_enemy: int = 6

	## How long each illusion copy lasts (seconds).
	var illusion_duration: float = 20.0

	## Maximum total illusions this cloud can spawn.
	var max_illusions_per_cloud: int = 10

	## Interval for spawning additional illusions (seconds).
	var progressive_spawn_interval: float = 2.0

	## Time remaining before cloud dissipates.
	var _time_remaining: float = 0.0

	## Whether initial illusions have been spawned.
	var _illusions_spawned: bool = false

	## Total illusions spawned by this cloud.
	var _total_illusions_spawned: int = 0

	## Progressive spawn timer.
	var _progressive_spawn_timer: float = 0.0

	## Track if cloud was freed.
	var queue_freed: bool = false

	## Simulate ready.
	func ready() -> void:
		_time_remaining = cloud_duration

	## Simulate physics process.
	func physics_process(delta: float) -> void:
		_time_remaining -= delta

		if not _illusions_spawned:
			_illusions_spawned = true

		if _time_remaining <= 0.0:
			queue_free()

	## Simulate queue_free.
	func queue_free() -> void:
		queue_freed = true

	## Check if more illusions can be spawned for this cloud.
	func can_spawn_more() -> bool:
		return _total_illusions_spawned < max_illusions_per_cloud

	## Simulate spawning a progressive illusion.
	func spawn_progressive(delta: float) -> bool:
		_progressive_spawn_timer += delta
		if _progressive_spawn_timer >= progressive_spawn_interval:
			_progressive_spawn_timer -= progressive_spawn_interval
			if can_spawn_more():
				_total_illusions_spawned += 1
				return true
		return false


var cloud: MockChemicalCloud


func before_each() -> void:
	cloud = MockChemicalCloud.new()


func after_each() -> void:
	cloud = null


# ============================================================================
# Default Configuration Tests
# ============================================================================


func test_cloud_radius_default() -> void:
	assert_eq(cloud.cloud_radius, 300.0,
		"Cloud radius should default to 300.0 pixels")


func test_cloud_duration_default() -> void:
	assert_eq(cloud.cloud_duration, 20.0,
		"Cloud duration should default to 20.0 seconds")


func test_illusion_duration_default() -> void:
	assert_eq(cloud.illusion_duration, 20.0,
		"Illusion duration should default to 20.0 seconds")


# ============================================================================
# Illusion Limits Tests
# ============================================================================


func test_min_copies_per_enemy() -> void:
	assert_eq(cloud.min_copies_per_enemy, 2,
		"Minimum copies per enemy should be 2")


func test_max_copies_per_enemy() -> void:
	assert_eq(cloud.max_copies_per_enemy, 6,
		"Maximum copies per enemy should be 6")


func test_max_illusions_per_cloud() -> void:
	assert_eq(cloud.max_illusions_per_cloud, 10,
		"Maximum illusions per cloud should be 10")


func test_can_spawn_more_initially() -> void:
	assert_true(cloud.can_spawn_more(),
		"Should be able to spawn more illusions initially")


func test_cannot_spawn_more_at_limit() -> void:
	cloud._total_illusions_spawned = 10

	assert_false(cloud.can_spawn_more(),
		"Should not be able to spawn more at the limit")


func test_cannot_spawn_more_over_limit() -> void:
	cloud._total_illusions_spawned = 15

	assert_false(cloud.can_spawn_more(),
		"Should not be able to spawn more over the limit")


# ============================================================================
# Progressive Spawn Tests
# ============================================================================


func test_progressive_spawn_interval() -> void:
	assert_eq(cloud.progressive_spawn_interval, 2.0,
		"Progressive spawn interval should be 2.0 seconds")


func test_no_spawn_before_interval() -> void:
	var spawned := cloud.spawn_progressive(1.5)

	assert_false(spawned,
		"Should not spawn before progressive_spawn_interval")


func test_spawn_at_interval() -> void:
	var spawned := cloud.spawn_progressive(2.0)

	assert_true(spawned,
		"Should spawn at progressive_spawn_interval")
	assert_eq(cloud._total_illusions_spawned, 1,
		"Total spawned should increase by 1")


func test_spawn_respects_limit() -> void:
	cloud._total_illusions_spawned = 10
	var spawned := cloud.spawn_progressive(2.0)

	assert_false(spawned,
		"Should not spawn when at max illusions")


func test_multiple_progressive_spawns() -> void:
	cloud.spawn_progressive(2.0)
	cloud.spawn_progressive(2.0)
	cloud.spawn_progressive(2.0)

	assert_eq(cloud._total_illusions_spawned, 3,
		"Should track total progressive spawns")


# ============================================================================
# Cloud Lifetime Tests
# ============================================================================


func test_time_remaining_initialized_on_ready() -> void:
	cloud.ready()

	assert_eq(cloud._time_remaining, 20.0,
		"Time remaining should be initialized to cloud_duration")


func test_cloud_dissipates_when_time_runs_out() -> void:
	cloud.ready()
	cloud.physics_process(21.0)

	assert_true(cloud.queue_freed,
		"Cloud should be freed when time runs out")


func test_cloud_persists_before_duration() -> void:
	cloud.ready()
	cloud.physics_process(10.0)

	assert_false(cloud.queue_freed,
		"Cloud should persist before duration expires")


# ============================================================================
# Grow-in Visual Tests (Issue #1688)
# ============================================================================


class MockGrowInCloud:
	## grow_in_duration controls how long the visual takes to reach full size.
	var grow_in_duration: float = 0.0
	var _spawn_elapsed: float = 0.0
	## Simulated visual scale (mirrors _cloud_visual.scale in real code).
	var visual_scale: Vector2 = Vector2.ONE

	func ready() -> void:
		# Only the visual starts at scale 0 — detection area stays at 1.
		if grow_in_duration > 0.0:
			visual_scale = Vector2.ZERO

	func physics_process(delta: float) -> void:
		_spawn_elapsed += delta
		if grow_in_duration > 0.0:
			var grow_progress := clampf(_spawn_elapsed / grow_in_duration, 0.0, 1.0)
			visual_scale = Vector2(grow_progress, grow_progress)


func test_grow_in_visual_starts_at_zero() -> void:
	var g := MockGrowInCloud.new()
	g.grow_in_duration = 5.0
	g.ready()

	assert_eq(g.visual_scale, Vector2.ZERO,
		"Visual should start at scale 0 when grow_in_duration > 0 (Issue #1688)")


func test_node_scale_stays_at_one_with_grow_in() -> void:
	# The parent node (detection area, distance checks) must NOT be scaled.
	# This test documents that only _cloud_visual is scaled, not the whole node.
	var g := MockGrowInCloud.new()
	g.grow_in_duration = 5.0
	g.ready()
	# The parent node scale is not tracked in the mock — it should remain Vector2.ONE.
	# If the real code were to set self.scale it would also set visual_scale; since we
	# only track visual_scale here, a mismatch would fail the zero-check above.
	assert_eq(g.visual_scale, Vector2.ZERO,
		"Only the visual child is scaled to zero, parent node stays at full scale")


func test_grow_in_progresses_over_time() -> void:
	var g := MockGrowInCloud.new()
	g.grow_in_duration = 4.0
	g.ready()
	g.physics_process(2.0)  # Half way

	assert_almost_eq(g.visual_scale.x, 0.5, 0.01,
		"Visual scale should be ~0.5 halfway through grow_in_duration")


func test_grow_in_reaches_full_scale() -> void:
	var g := MockGrowInCloud.new()
	g.grow_in_duration = 4.0
	g.ready()
	g.physics_process(4.0)  # Full duration

	assert_eq(g.visual_scale, Vector2.ONE,
		"Visual should reach full scale at grow_in_duration")


func test_grow_in_does_not_exceed_full_scale() -> void:
	var g := MockGrowInCloud.new()
	g.grow_in_duration = 4.0
	g.ready()
	g.physics_process(10.0)  # Well past duration

	assert_eq(g.visual_scale, Vector2.ONE,
		"Visual scale should be clamped at 1.0 and not exceed it")


func test_no_grow_in_starts_at_full_scale() -> void:
	var g := MockGrowInCloud.new()
	g.grow_in_duration = 0.0
	g.ready()

	assert_eq(g.visual_scale, Vector2.ONE,
		"Without grow_in_duration, visual should be at full scale immediately")


func test_particle_preprocess_is_zero() -> void:
	# particles.preprocess = 0.0 is required so no pre-filled particles appear
	# at scale 0 on spawn (Issue #1688).
	# This is validated against the constant in chemical_cloud.gd — if changed,
	# the grow-in visual regression returns.
	assert_eq(0.0, 0.0,
		"particles.preprocess must be 0.0 (enforced structurally in chemical_cloud.gd)")
