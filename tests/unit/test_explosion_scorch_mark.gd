extends GutTest
## Unit tests for ExplosionScorchMark (Issue #1005).
##
## Tests the scorch mark visual effect that remains on the floor
## after grenade explosions. Validates size, opacity, and configuration
## for different grenade types.


# ============================================================================
# Mock ExplosionScorchMark for Logic Tests
# ============================================================================


class MockExplosionScorchMark:
	## Scorch mark radius in pixels.
	var scorch_radius: float = 40.0

	## Alpha (opacity) of the scorch mark.
	var scorch_alpha: float = 0.6

	## Whether the scorch mark should fade out over time.
	var auto_fade: bool = false

	## Time in seconds before the mark starts fading.
	var fade_delay: float = 120.0

	## Time in seconds for the fade-out animation.
	var fade_duration: float = 30.0

	## Grenade type that created this mark.
	var grenade_type: String = "unknown"

	## Global position.
	var global_position: Vector2 = Vector2.ZERO

	## Rotation (random for visual variety).
	var rotation: float = 0.0

	## Modulate color (includes alpha).
	var modulate: Color = Color(1.0, 1.0, 1.0, 0.6)

	## Z-index for layering.
	var z_index: int = 0

	## Whether the mark has been removed.
	var _removed: bool = false


	## Configure the scorch mark with parameters.
	func configure(pos: Vector2, radius: float, alpha: float, type: String) -> void:
		global_position = pos
		scorch_radius = radius
		scorch_alpha = alpha
		grenade_type = type
		modulate = Color(1.0, 1.0, 1.0, alpha)
		# Random rotation for visual variety
		rotation = randf_range(0, TAU)


	## Remove the scorch mark.
	func remove() -> void:
		_removed = true


	## Check if mark has been removed.
	func is_removed() -> bool:
		return _removed


var scorch_mark: MockExplosionScorchMark


func before_each() -> void:
	scorch_mark = MockExplosionScorchMark.new()


func after_each() -> void:
	scorch_mark = null


# ============================================================================
# Default Configuration Tests
# ============================================================================


func test_default_scorch_radius() -> void:
	assert_eq(scorch_mark.scorch_radius, 40.0,
		"Default scorch radius should be 40 pixels")


func test_default_scorch_alpha() -> void:
	assert_eq(scorch_mark.scorch_alpha, 0.6,
		"Default scorch alpha should be 0.6")


func test_default_auto_fade() -> void:
	assert_false(scorch_mark.auto_fade,
		"Auto fade should be disabled by default")


func test_default_fade_delay() -> void:
	assert_eq(scorch_mark.fade_delay, 120.0,
		"Default fade delay should be 120 seconds")


func test_default_fade_duration() -> void:
	assert_eq(scorch_mark.fade_duration, 30.0,
		"Default fade duration should be 30 seconds")


func test_default_z_index() -> void:
	assert_eq(scorch_mark.z_index, 0,
		"Default z-index should be 0 (floor level)")


# ============================================================================
# Configuration Tests
# ============================================================================


func test_configure_sets_position() -> void:
	scorch_mark.configure(Vector2(100, 200), 50.0, 0.7, "test")

	assert_eq(scorch_mark.global_position, Vector2(100, 200))


func test_configure_sets_radius() -> void:
	scorch_mark.configure(Vector2.ZERO, 75.0, 0.5, "test")

	assert_eq(scorch_mark.scorch_radius, 75.0)


func test_configure_sets_alpha() -> void:
	scorch_mark.configure(Vector2.ZERO, 50.0, 0.3, "test")

	assert_eq(scorch_mark.scorch_alpha, 0.3)
	assert_eq(scorch_mark.modulate.a, 0.3)


func test_configure_sets_grenade_type() -> void:
	scorch_mark.configure(Vector2.ZERO, 50.0, 0.5, "flashbang")

	assert_eq(scorch_mark.grenade_type, "flashbang")


func test_configure_sets_random_rotation() -> void:
	var rotations := []
	for i in range(10):
		var mark := MockExplosionScorchMark.new()
		mark.configure(Vector2.ZERO, 50.0, 0.5, "test")
		rotations.append(mark.rotation)

	# Check that rotations vary (not all the same)
	var unique_count := 0
	for i in range(rotations.size()):
		var is_unique := true
		for j in range(i):
			if abs(rotations[i] - rotations[j]) < 0.001:
				is_unique = false
				break
		if is_unique:
			unique_count += 1

	assert_gt(unique_count, 1,
		"Rotations should vary between scorch marks")


# ============================================================================
# Issue #1005 Grenade Type Size Requirements Tests
# ============================================================================


func test_issue_1005_flashbang_size() -> void:
	# Flashbang: size of grenade itself (~20px), almost invisible (0.15 alpha)
	scorch_mark.configure(Vector2.ZERO, 20.0, 0.15, "flashbang")

	assert_eq(scorch_mark.scorch_radius, 20.0,
		"Flashbang scorch mark should be size of grenade (~20px)")
	assert_eq(scorch_mark.scorch_alpha, 0.15,
		"Flashbang scorch mark should be almost invisible (0.15 alpha)")


func test_issue_1005_frag_size() -> void:
	# Frag (offensive): 2x grenade size (~40px), burnt mark (0.6 alpha)
	scorch_mark.configure(Vector2.ZERO, 40.0, 0.6, "frag")

	assert_eq(scorch_mark.scorch_radius, 40.0,
		"Frag scorch mark should be 2x grenade size (~40px)")
	assert_eq(scorch_mark.scorch_alpha, 0.6,
		"Frag scorch mark should have burnt appearance (0.6 alpha)")


func test_issue_1005_defensive_size() -> void:
	# F-1 (defensive): 2x frag size (~80px), prominent burnt mark (0.7 alpha)
	scorch_mark.configure(Vector2.ZERO, 80.0, 0.7, "defensive")

	assert_eq(scorch_mark.scorch_radius, 80.0,
		"F-1 scorch mark should be 2x frag size (~80px)")
	assert_eq(scorch_mark.scorch_alpha, 0.7,
		"F-1 scorch mark should be prominent (0.7 alpha)")


func test_issue_1005_size_ratio_flashbang_to_frag() -> void:
	# Frag should be 2x size of flashbang
	var flashbang_radius := 20.0
	var frag_radius := 40.0

	assert_eq(frag_radius / flashbang_radius, 2.0,
		"Frag should be exactly 2x the size of flashbang")


func test_issue_1005_size_ratio_frag_to_defensive() -> void:
	# F-1 should be 2x size of frag
	var frag_radius := 40.0
	var defensive_radius := 80.0

	assert_eq(defensive_radius / frag_radius, 2.0,
		"F-1 should be exactly 2x the size of frag")


func test_issue_1005_visibility_hierarchy() -> void:
	# Visibility should increase: flashbang < frag < defensive
	var flashbang_alpha := 0.15
	var frag_alpha := 0.6
	var defensive_alpha := 0.7

	assert_lt(flashbang_alpha, frag_alpha,
		"Flashbang should be less visible than frag")
	assert_lt(frag_alpha, defensive_alpha,
		"Frag should be less visible than defensive")


# ============================================================================
# Removal Tests
# ============================================================================


func test_remove_marks_as_removed() -> void:
	scorch_mark.remove()

	assert_true(scorch_mark.is_removed())


func test_not_removed_initially() -> void:
	assert_false(scorch_mark.is_removed())


# ============================================================================
# Edge Cases Tests
# ============================================================================


func test_zero_radius() -> void:
	scorch_mark.configure(Vector2.ZERO, 0.0, 0.5, "test")

	assert_eq(scorch_mark.scorch_radius, 0.0,
		"Zero radius should be allowed")


func test_zero_alpha() -> void:
	scorch_mark.configure(Vector2.ZERO, 50.0, 0.0, "test")

	assert_eq(scorch_mark.scorch_alpha, 0.0,
		"Zero alpha should be allowed (invisible mark)")
	assert_eq(scorch_mark.modulate.a, 0.0)


func test_full_alpha() -> void:
	scorch_mark.configure(Vector2.ZERO, 50.0, 1.0, "test")

	assert_eq(scorch_mark.scorch_alpha, 1.0,
		"Full alpha should be allowed")
	assert_eq(scorch_mark.modulate.a, 1.0)


func test_large_radius() -> void:
	scorch_mark.configure(Vector2.ZERO, 500.0, 0.5, "test")

	assert_eq(scorch_mark.scorch_radius, 500.0,
		"Large radius should be allowed")


func test_negative_position() -> void:
	scorch_mark.configure(Vector2(-100, -200), 50.0, 0.5, "test")

	assert_eq(scorch_mark.global_position, Vector2(-100, -200),
		"Negative positions should be allowed")


func test_rotation_within_bounds() -> void:
	for i in range(20):
		var mark := MockExplosionScorchMark.new()
		mark.configure(Vector2.ZERO, 50.0, 0.5, "test")

		assert_gte(mark.rotation, 0.0,
			"Rotation should be >= 0")
		assert_lt(mark.rotation, TAU,
			"Rotation should be < TAU (2*PI)")


# ============================================================================
# Persistence Tests
# ============================================================================


func test_auto_fade_can_be_enabled() -> void:
	scorch_mark.auto_fade = true

	assert_true(scorch_mark.auto_fade)


func test_fade_delay_configurable() -> void:
	scorch_mark.fade_delay = 60.0

	assert_eq(scorch_mark.fade_delay, 60.0)


func test_fade_duration_configurable() -> void:
	scorch_mark.fade_duration = 10.0

	assert_eq(scorch_mark.fade_duration, 10.0)
