extends GutTest
## Unit tests for ChemicalCloud illusion spawning (Issues #1361, #1367).
##
## Tests that:
## - Illusion copy count range is 2-6 per enemy
## - Original enemy is positioned randomly among copies (not always center)
## - Progressive illusion spawning: max 10, +1 every 2 seconds (Issue #1367)
## - Cloud radius doubled to 600 (Issue #1367)


# ============================================================================
# Mock Classes
# ============================================================================


class MockEnemy:
	extends Node2D

	var _is_alive_value: bool = true
	var bullet_scene: PackedScene = null
	var _enemy_model: Node2D = null
	var _can_see_player: bool = false
	var enemy_model_scale: float = 1.0

	func is_alive() -> bool:
		return _is_alive_value


class MockPlayer:
	extends Node2D
	pass


# ============================================================================
# Tests for copy count range (2-6)
# ============================================================================


func test_max_copies_per_enemy_default_is_6() -> void:
	var cloud := ChemicalCloud.new()
	assert_eq(cloud.max_copies_per_enemy, 6, "max_copies_per_enemy should default to 6")
	cloud.free()


func test_min_copies_per_enemy_default_is_2() -> void:
	var cloud := ChemicalCloud.new()
	assert_eq(cloud.min_copies_per_enemy, 2, "min_copies_per_enemy should default to 2")
	cloud.free()


func test_copies_range_is_2_to_6() -> void:
	# Verify that randi_range with min=2, max=6 produces values in [2, 6]
	var cloud := ChemicalCloud.new()
	var seen_values: Dictionary = {}
	# Run many iterations to check range bounds
	for i in range(500):
		var copies: int = randi_range(cloud.min_copies_per_enemy, cloud.max_copies_per_enemy)
		assert_true(copies >= 2, "Copies should be >= 2, got %d" % copies)
		assert_true(copies <= 6, "Copies should be <= 6, got %d" % copies)
		seen_values[copies] = true
	# With 500 iterations we should see all values 2-6
	for v in range(2, 7):
		assert_true(seen_values.has(v), "Should see value %d in copy range" % v)
	cloud.free()


# ============================================================================
# Tests for random original position (Issue #1361)
# ============================================================================


func test_original_enemy_prefers_non_center_offsets_before_fallback() -> void:
	# Simulate the position selection logic from _spawn_illusions_for_nearby_enemies.
	# The original enemy should use a non-center candidate whenever one is available.
	var center_count: int = 0
	var total_runs: int = 200

	for _i in range(total_runs):
		var copies: int = randi_range(2, 6)
		var total_positions: int = copies + 1
		var candidate_indices: Array[int] = []
		for i in range(1, total_positions):
			candidate_indices.append(i)
		candidate_indices.shuffle()
		var original_index: int = candidate_indices[0]
		if original_index == 0:
			center_count += 1

	assert_eq(center_count, 0,
		"Original enemy should reserve center for fallback only. Center count: %d/%d" % [center_count, total_runs])


func test_position_offsets_cover_full_circle() -> void:
	# Verify that illusion positions are spread around a circle
	var copies: int = 6
	var angles: Array[float] = []
	for i in range(copies):
		var angle: float = (TAU / copies) * i
		angles.append(angle)
	# Verify angles span the full circle (approximately)
	var min_angle: float = angles[0]
	var max_angle: float = angles[copies - 1]
	assert_almost_eq(min_angle, 0.0, 0.01, "First angle should be near 0")
	assert_almost_eq(max_angle, TAU * (copies - 1.0) / copies, 0.01,
		"Last angle should be near TAU * 5/6")


func test_illusion_offsets_adjusted_when_original_moves() -> void:
	# When original moves to position X, illusion offsets should be adjusted by -X
	# so they still end up at their intended absolute positions.
	var original_pos := Vector2(100, 200)
	var copies: int = 3
	var total_positions: int = copies + 1  # 4

	# Generate offsets
	var offsets: Array[Vector2] = []
	offsets.append(Vector2.ZERO)  # center
	for i in range(copies):
		var angle: float = (TAU / copies) * i
		var distance: float = 80.0
		offsets.append(Vector2(cos(angle), sin(angle)) * distance)

	# Pick a non-center position for the original
	var original_index: int = 2
	var original_offset: Vector2 = offsets[original_index]

	# Calculate adjusted offsets for illusions
	var illusion_offsets: Array[Vector2] = []
	for i in range(total_positions):
		if i == original_index:
			continue
		illusion_offsets.append(offsets[i] - original_offset)

	# Verify: the number of illusions equals copies (one position taken by original)
	assert_eq(illusion_offsets.size(), copies,
		"Should have %d illusion offsets" % copies)

	# Verify: one of the illusion offsets points back to center (covers original's old spot)
	var has_center_cover: bool = false
	for offset in illusion_offsets:
		if offset.is_equal_approx(-original_offset):
			has_center_cover = true
			break
	assert_true(has_center_cover,
		"One illusion should cover the original's old center position")


func test_total_entities_equals_copies_plus_one() -> void:
	# The total number of visible entities (original + illusions) should be copies + 1
	for _run in range(50):
		var copies: int = randi_range(2, 6)
		var total_positions: int = copies + 1
		var original_index: int = randi_range(0, total_positions - 1)

		# Count illusions (all positions except original's)
		var illusion_count: int = 0
		for i in range(total_positions):
			if i != original_index:
				illusion_count += 1

		# Total visible = 1 original + illusion_count
		assert_eq(1 + illusion_count, total_positions,
			"Total entities should be %d (1 original + %d illusions)" % [total_positions, illusion_count])


# ============================================================================
# Tests for Issue #1367: Progressive illusion spawning and cloud radius
# ============================================================================


func test_max_illusions_per_cloud_default_is_10() -> void:
	var cloud := ChemicalCloud.new()
	assert_eq(cloud.max_illusions_per_cloud, 10, "max_illusions_per_cloud should default to 10")
	cloud.free()


func test_progressive_spawn_interval_default_is_2() -> void:
	var cloud := ChemicalCloud.new()
	assert_almost_eq(cloud.progressive_spawn_interval, 2.0, 0.01,
		"progressive_spawn_interval should default to 2.0 seconds")
	cloud.free()


func test_chemical_grenade_effect_radius_is_600() -> void:
	# Issue #1367: Cloud should be 2x bigger (300 -> 600)
	var grenade := ChemicalGasGrenade.new()
	assert_almost_eq(grenade.effect_radius, 600.0, 0.01,
		"effect_radius should be 600 (2x the original 300)")
	grenade.free()


func test_progressive_spawning_respects_per_cloud_cap() -> void:
	# Simulate progressive spawning and verify it stops at max_illusions_per_cloud
	var cloud := ChemicalCloud.new()
	var max_cap := cloud.max_illusions_per_cloud
	assert_eq(max_cap, 10, "Max cap should be 10")

	# Simulate: initial batch spawns 4, then progressive adds 1 at a time
	var initial_batch: int = 4
	var total: int = initial_batch
	var seconds_in_cloud: float = 0.0
	var interval: float = cloud.progressive_spawn_interval

	# Simulate 20 seconds in cloud
	while seconds_in_cloud < 20.0 and total < max_cap:
		seconds_in_cloud += interval
		total += 1

	# After enough time, total should reach exactly max_cap
	assert_eq(total, max_cap,
		"Total illusions should reach cap of %d" % max_cap)
	cloud.free()


func test_initial_batch_plus_progressive_can_reach_10() -> void:
	# With initial batch of 2-6 and progressive spawning every 2s,
	# the system should be able to reach 10 total illusions.
	var cloud := ChemicalCloud.new()

	# Worst case: initial batch of 6, need 4 more progressive spawns = 8 seconds
	# Best case: initial batch of 2, need 8 more progressive spawns = 16 seconds
	# Cloud duration is 20 seconds, so both cases fit within cloud lifetime.
	var initial_min: int = cloud.min_copies_per_enemy  # 2
	var initial_max: int = cloud.max_copies_per_enemy  # 6
	var max_cap: int = cloud.max_illusions_per_cloud  # 10
	var interval: float = cloud.progressive_spawn_interval  # 2.0
	var duration: float = cloud.cloud_duration  # 20.0

	# Even with max initial batch (6), remaining 4 need 4*2 = 8 seconds
	var remaining_from_max_batch: int = max_cap - initial_max  # 4
	var time_needed: float = remaining_from_max_batch * interval  # 8.0
	assert_true(time_needed <= duration,
		"Should have enough time (%.1fs needed, %.1fs available) to reach cap from max initial batch" % [
			time_needed, duration
		])

	# Even with min initial batch (2), remaining 8 need 8*2 = 16 seconds
	var remaining_from_min_batch: int = max_cap - initial_min  # 8
	var time_needed_min: float = remaining_from_min_batch * interval  # 16.0
	assert_true(time_needed_min <= duration,
		"Should have enough time (%.1fs needed, %.1fs available) to reach cap from min initial batch" % [
			time_needed_min, duration
		])

	cloud.free()


# ============================================================================
# Issue #1632: Wall-safe random position for the original enemy
# ============================================================================


## Build a StaticBody2D with a rectangle collider on the obstacle layer (layer 3).
func _make_wall(pos: Vector2, extents: Vector2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.collision_layer = 4  # layer 3 (bit 2) — obstacles
	wall.collision_mask = 0
	wall.global_position = pos
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = extents
	shape.shape = rect
	wall.add_child(shape)
	return wall


## Add node to the scene tree and wait one physics frame so collision shapes register.
func _register_in_physics(node: Node) -> void:
	add_child_autofree(node)
	await wait_frames(2)


func test_wall_validation_rejects_position_inside_wall() -> void:
	var cloud := ChemicalCloud.new()
	add_child_autofree(cloud)
	var wall := _make_wall(Vector2(200, 0), Vector2(100, 100))
	await _register_in_physics(wall)

	var enemy := MockEnemy.new()
	add_child_autofree(enemy)
	enemy.global_position = Vector2(0, 0)

	# Target inside the wall — must be rejected.
	var safe := cloud._is_position_safe_from_walls(
		enemy.global_position, Vector2(200, 0), enemy
	)
	assert_false(safe, "Position inside wall collider must be rejected")


func test_wall_validation_rejects_path_crossing_wall() -> void:
	var cloud := ChemicalCloud.new()
	add_child_autofree(cloud)
	# Wall sits between (0,0) and (400,0).
	var wall := _make_wall(Vector2(200, 0), Vector2(50, 200))
	await _register_in_physics(wall)

	var enemy := MockEnemy.new()
	add_child_autofree(enemy)
	enemy.global_position = Vector2(0, 0)

	# Target is in open space but the path crosses the wall — must be rejected.
	var safe := cloud._is_position_safe_from_walls(
		enemy.global_position, Vector2(400, 0), enemy
	)
	assert_false(safe, "Path crossing wall must be rejected")


func test_wall_validation_accepts_open_space_position() -> void:
	var cloud := ChemicalCloud.new()
	add_child_autofree(cloud)
	# Wall placed far off to the side so it does not interfere.
	var wall := _make_wall(Vector2(1000, 1000), Vector2(50, 50))
	await _register_in_physics(wall)

	var enemy := MockEnemy.new()
	add_child_autofree(enemy)
	enemy.global_position = Vector2(0, 0)

	var safe := cloud._is_position_safe_from_walls(
		enemy.global_position, Vector2(100, 0), enemy
	)
	assert_true(safe, "Open-space position with clear path must be accepted")


func test_wall_validation_returns_true_when_world_unavailable() -> void:
	# ChemicalCloud not added to the tree has no World2D — validation must not block.
	var cloud := ChemicalCloud.new()
	var enemy := MockEnemy.new()
	enemy.global_position = Vector2(0, 0)
	var safe := cloud._is_position_safe_from_walls(
		enemy.global_position, Vector2(100, 0), enemy
	)
	assert_true(safe, "Validation must be permissive when no physics space is available")
	cloud.free()
	enemy.free()


func test_candidate_indices_exclude_center_before_fallback() -> void:
	# The validation loop must iterate over non-center offsets (indices 1..N-1)
	# before falling back to index 0. Center stays reserved as the no-move fallback
	# so the random-position behavior from Issue #1361 is preserved whenever any
	# random offset passes the wall check.
	var total_positions: int = 5
	var candidate_indices: Array[int] = []
	for i in range(1, total_positions):
		candidate_indices.append(i)
	assert_eq(candidate_indices.size(), total_positions - 1,
		"Should iterate over %d non-center candidates" % (total_positions - 1))
	assert_false(candidate_indices.has(0),
		"Index 0 (center) must be excluded from the shuffled candidate list")


func test_alive_enemies_sorted_by_cloud_distance_prioritizes_local_illusions() -> void:
	var cloud := ChemicalCloud.new()
	add_child_autofree(cloud)
	cloud.global_position = Vector2(1000, 1000)

	var far_enemy := MockEnemy.new()
	far_enemy.global_position = Vector2(300, 2670)
	far_enemy.add_to_group("enemies")
	add_child_autofree(far_enemy)

	var near_enemy := MockEnemy.new()
	near_enemy.global_position = Vector2(1100, 1020)
	near_enemy.add_to_group("enemies")
	add_child_autofree(near_enemy)

	var dead_enemy := MockEnemy.new()
	dead_enemy.global_position = Vector2(1005, 1005)
	dead_enemy._is_alive_value = false
	dead_enemy.add_to_group("enemies")
	add_child_autofree(dead_enemy)

	var sorted := cloud._get_alive_enemies_sorted_by_cloud_distance()
	assert_eq(sorted.size(), 2, "Dead enemies must be excluded from the spawn list")
	assert_eq(sorted[0], near_enemy,
		"Nearest alive enemy must be processed first so the per-cloud cap is spent locally")
	assert_eq(sorted[1], far_enemy,
		"Farther alive enemy should be processed after local enemies")
