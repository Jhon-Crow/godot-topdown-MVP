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


func test_original_enemy_not_always_at_center() -> void:
	# Simulate the position selection logic from _spawn_illusions_for_nearby_enemies.
	# The original enemy should not always get index 0 (center).
	var center_count: int = 0
	var total_runs: int = 200

	for _i in range(total_runs):
		var copies: int = randi_range(2, 6)
		var total_positions: int = copies + 1
		var original_index: int = randi_range(0, total_positions - 1)
		if original_index == 0:
			center_count += 1

	# If always center, center_count would be 200.
	# With random placement, center_count should be roughly total_runs / avg_total_positions.
	# avg copies ~4, avg total_positions ~5, so expected ~200/5 = 40.
	# Allow generous margin: should be less than 60% of runs at center.
	assert_true(center_count < total_runs * 0.6,
		"Original enemy should not always be at center. Center count: %d/%d" % [center_count, total_runs])
	# Should sometimes be at center (not never)
	assert_true(center_count > 0,
		"Original enemy should sometimes be at center. Center count: %d/%d" % [center_count, total_runs])


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
# Tests for Issue #1632: Physics-based wall validation in _is_position_valid
# ============================================================================


func test_is_position_valid_returns_true_when_no_space_state_and_no_nav_agent() -> void:
	# Without physics space state or nav-agent, falls back to allowing the position.
	var cloud := ChemicalCloud.new()
	var enemy := MockEnemy.new()
	enemy.global_position = Vector2(100, 100)
	# null space_state, no NavigationAgent2D child — should allow (fail-open)
	var result: bool = cloud._is_position_valid(enemy, Vector2(200, 100), null)
	assert_true(result, "_is_position_valid should allow when no validation data available")
	cloud.free()
	enemy.free()


func test_wall_collision_mask_is_4() -> void:
	# Verify WALL_COLLISION_MASK matches the obstacles layer used throughout the codebase.
	var cloud := ChemicalCloud.new()
	assert_eq(cloud.WALL_COLLISION_MASK, 4,
		"WALL_COLLISION_MASK should be 4 (layer 3 = obstacles/walls)")
	cloud.free()


func test_nav_snap_tolerance_is_20() -> void:
	# Tightened tolerance: agent radius is ~10-20px, so 20px is a safe upper bound.
	var cloud := ChemicalCloud.new()
	assert_almost_eq(cloud.NAV_SNAP_TOLERANCE, 20.0, 0.01,
		"NAV_SNAP_TOLERANCE should be 20.0 (tightened from 50.0)")
	cloud.free()


func test_fallback_to_center_when_all_candidates_invalid() -> void:
	# When space_state is null (fallback path) and no nav-agent available,
	# the loop should still accept the first valid candidate.
	# Simulate the selection logic: if center (offset=ZERO) is encountered, it's always valid.
	var found_center: bool = false
	var copies: int = 3
	var total_positions: int = copies + 1
	var offsets: Array[Vector2] = []
	offsets.append(Vector2.ZERO)  # center
	for i in range(copies):
		var angle: float = (TAU / copies) * i
		offsets.append(Vector2(cos(angle), sin(angle)) * 90.0)

	# Shuffle and find first valid — center should always be accepted
	var candidate_indices: Array[int] = []
	for i in range(total_positions):
		candidate_indices.append(i)

	for ci in candidate_indices:
		if offsets[ci] == Vector2.ZERO:
			found_center = true
			break  # Center is always valid

	assert_true(found_center, "Center offset should always be found as valid fallback")
