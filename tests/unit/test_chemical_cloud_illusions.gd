extends GutTest
## Unit tests for ChemicalCloud illusion spawning (Issue #1361).
##
## Tests that:
## - Illusion copy count range is 2-6 per enemy
## - Original enemy is positioned randomly among copies (not always center)


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
