extends GutTest
## Unit tests for Level script helper functions.
##
## Tests the ammo display formatting, color coding logic, and magazine display
## used in level scripts (TestTier, BuildingLevel, TutorialLevel).


# ============================================================================
# Mock Level Helper for Testing
# ============================================================================


class MockLevelHelper:
	## Saturation effect constants
	const SATURATION_DURATION: float = 0.15
	const SATURATION_INTENSITY: float = 0.25

	## Ammo color thresholds
	const LOW_AMMO_THRESHOLD: int = 5
	const MEDIUM_AMMO_THRESHOLD: int = 10

	## Colors
	const COLOR_RED := Color(1.0, 0.2, 0.2, 1.0)
	const COLOR_YELLOW := Color(1.0, 1.0, 0.2, 1.0)
	const COLOR_WHITE := Color(1.0, 1.0, 1.0, 1.0)
	const COLOR_DEATH := Color(1.0, 0.15, 0.15, 1.0)
	const COLOR_VICTORY := Color(0.2, 1.0, 0.3, 1.0)


	## Get the ammo color based on current ammo count.
	func get_ammo_color(current: int) -> Color:
		if current <= LOW_AMMO_THRESHOLD:
			return COLOR_RED
		elif current <= MEDIUM_AMMO_THRESHOLD:
			return COLOR_YELLOW
		else:
			return COLOR_WHITE


	## Format the ammo label text (simple format).
	func format_ammo_simple(current: int, maximum: int) -> String:
		return "AMMO: %d/%d" % [current, maximum]


	## Format the ammo label text (magazine format for C# player).
	func format_ammo_magazine(current_mag: int, reserve: int) -> String:
		return "AMMO: %d/%d" % [current_mag, reserve]


	## Format the magazines label showing magazine ammo counts.
	## Shows format: MAGS: [30] | 7 | + x5 where [30] is current magazine,
	## 7 is a partial spare, and + x5 abbreviates full spare magazines.
	## Empty spares are hidden; partial spares shown individually; full spares abbreviated.
	func format_magazines_label(magazine_ammo_counts: Array, magazine_max_counts: Array = []) -> String:
		if magazine_ammo_counts.is_empty():
			return "MAGS: -"

		var parts: Array[String] = []
		# Current magazine always shown in brackets
		parts.append("[%d]" % magazine_ammo_counts[0])

		# Spare magazines: skip empty, show partial individually, abbreviate full as + xN
		var full_spare_count: int = 0
		for i in range(1, magazine_ammo_counts.size()):
			var ammo: int = magazine_ammo_counts[i]
			if ammo <= 0:
				continue
			var cap: int = magazine_max_counts[i] if i < magazine_max_counts.size() else 0
			if cap > 0 and ammo >= cap:
				full_spare_count += 1
			else:
				parts.append("%d" % ammo)

		if full_spare_count > 0:
			parts.append("+ x%d" % full_spare_count)

		return "MAGS: " + " | ".join(parts)


	## Format the enemy count label.
	func format_enemy_count(count: int) -> String:
		return "Enemies: %d" % count


	## Calculate saturation flash in/out values.
	func get_saturation_flash_in_time() -> float:
		return SATURATION_DURATION * 0.3


	func get_saturation_flash_out_time() -> float:
		return SATURATION_DURATION * 0.7


	## Check if game over should be shown.
	func should_show_game_over(current_ammo: int, reserve_ammo: int, enemy_count: int, game_over_shown: bool) -> bool:
		if game_over_shown:
			return false
		if enemy_count <= 0:
			return false
		return current_ammo <= 0 and reserve_ammo <= 0


	## Check if victory should be shown.
	func should_show_victory(enemy_count: int) -> bool:
		return enemy_count <= 0


var helper: MockLevelHelper


func before_each() -> void:
	helper = MockLevelHelper.new()


func after_each() -> void:
	helper = null


# ============================================================================
# Ammo Color Tests
# ============================================================================


func test_ammo_color_red_at_5() -> void:
	var color := helper.get_ammo_color(5)
	assert_eq(color, MockLevelHelper.COLOR_RED, "Should be red at 5 ammo")


func test_ammo_color_red_at_1() -> void:
	var color := helper.get_ammo_color(1)
	assert_eq(color, MockLevelHelper.COLOR_RED, "Should be red at 1 ammo")


func test_ammo_color_red_at_0() -> void:
	var color := helper.get_ammo_color(0)
	assert_eq(color, MockLevelHelper.COLOR_RED, "Should be red at 0 ammo")


func test_ammo_color_yellow_at_6() -> void:
	var color := helper.get_ammo_color(6)
	assert_eq(color, MockLevelHelper.COLOR_YELLOW, "Should be yellow at 6 ammo")


func test_ammo_color_yellow_at_10() -> void:
	var color := helper.get_ammo_color(10)
	assert_eq(color, MockLevelHelper.COLOR_YELLOW, "Should be yellow at 10 ammo")


func test_ammo_color_white_at_11() -> void:
	var color := helper.get_ammo_color(11)
	assert_eq(color, MockLevelHelper.COLOR_WHITE, "Should be white at 11 ammo")


func test_ammo_color_white_at_30() -> void:
	var color := helper.get_ammo_color(30)
	assert_eq(color, MockLevelHelper.COLOR_WHITE, "Should be white at 30 ammo")


# ============================================================================
# Ammo Format Tests
# ============================================================================


func test_format_ammo_simple() -> void:
	var result := helper.format_ammo_simple(30, 90)
	assert_eq(result, "AMMO: 30/90", "Simple ammo format should be correct")


func test_format_ammo_simple_zero() -> void:
	var result := helper.format_ammo_simple(0, 90)
	assert_eq(result, "AMMO: 0/90", "Should handle zero ammo")


func test_format_ammo_magazine() -> void:
	var result := helper.format_ammo_magazine(30, 60)
	assert_eq(result, "AMMO: 30/60", "Magazine ammo format should be correct")


func test_format_ammo_magazine_empty_current() -> void:
	var result := helper.format_ammo_magazine(0, 60)
	assert_eq(result, "AMMO: 0/60", "Should handle empty magazine")


func test_format_ammo_magazine_empty_reserve() -> void:
	var result := helper.format_ammo_magazine(15, 0)
	assert_eq(result, "AMMO: 15/0", "Should handle no reserve")


# ============================================================================
# Magazines Label Format Tests
# ============================================================================


func test_format_magazines_empty_array() -> void:
	var result := helper.format_magazines_label([])
	assert_eq(result, "MAGS: -", "Empty array should show dash")


func test_format_magazines_single() -> void:
	var result := helper.format_magazines_label([30])
	assert_eq(result, "MAGS: [30]", "Single magazine should be in brackets")


func test_format_magazines_partial_spares_shown_individually() -> void:
	# Partial spares (ammo < capacity) are shown individually
	var result := helper.format_magazines_label([30, 25, 10], [30, 30, 30])
	assert_eq(result, "MAGS: [30] | 25 | 10", "Partial spare magazines shown individually")


func test_format_magazines_with_zeros() -> void:
	# Zero in current magazine is shown; zero in spares are hidden
	var result := helper.format_magazines_label([0, 30, 30], [30, 30, 30])
	assert_eq(result, "MAGS: [0] | + x2", "Zero current shown; full spares abbreviated")


func test_format_magazines_empty_spare_hidden() -> void:
	# Empty spare (0 ammo) is hidden; partial (25) shown individually
	var result := helper.format_magazines_label([30, 0, 0, 25], [30, 30, 30, 30])
	assert_eq(result, "MAGS: [30] | 25", "Empty spare magazines should be hidden")


func test_format_magazines_all_spare_empty() -> void:
	var result := helper.format_magazines_label([30, 0, 0, 0], [30, 30, 30, 30])
	assert_eq(result, "MAGS: [30]", "All-empty spares should show only current magazine")


func test_format_magazines_full_spares_abbreviated() -> void:
	# 6 full spares all abbreviated as + x6
	var result := helper.format_magazines_label([30, 30, 30, 30, 30, 30, 30], [30, 30, 30, 30, 30, 30, 30])
	assert_eq(result, "MAGS: [30] | + x6", "Full spare magazines should be abbreviated as + xN")


func test_format_magazines_7_full_spare() -> void:
	# 7 full spares → + x7
	var result := helper.format_magazines_label([30, 30, 30, 30, 30, 30, 30, 30], [30, 30, 30, 30, 30, 30, 30, 30])
	assert_eq(result, "MAGS: [30] | + x7", "7 full spare magazines should show + x7")


func test_format_magazines_partial_and_full_mixed() -> void:
	# 1 partial spare (25) shown individually, 8 full spares abbreviated
	var result := helper.format_magazines_label([30, 30, 30, 30, 30, 30, 30, 30, 30, 25], [30, 30, 30, 30, 30, 30, 30, 30, 30, 30])
	assert_eq(result, "MAGS: [30] | 25 | + x8", "Partial shown individually, full spares abbreviated")


func test_format_magazines_empty_skipped_full_abbreviated() -> void:
	# 9 full spares (non-empty), 2 empty (hidden) -> + x9
	var result := helper.format_magazines_label([30, 30, 30, 30, 30, 30, 30, 0, 30, 30, 30], [30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30])
	assert_eq(result, "MAGS: [30] | + x9", "Empty spares hidden, non-empty full spares abbreviated")


func test_format_magazines_no_capacity_info_treats_as_partial() -> void:
	# When no max_counts provided (empty array), all non-empty spares shown individually
	var result := helper.format_magazines_label([30, 25, 10])
	assert_eq(result, "MAGS: [30] | 25 | 10", "Without capacity info, all non-empty spares shown individually")


# ============================================================================
# Enemy Count Format Tests
# ============================================================================


func test_format_enemy_count() -> void:
	var result := helper.format_enemy_count(10)
	assert_eq(result, "Enemies: 10", "Enemy count format should be correct")


func test_format_enemy_count_zero() -> void:
	var result := helper.format_enemy_count(0)
	assert_eq(result, "Enemies: 0", "Should handle zero enemies")


# ============================================================================
# Saturation Effect Tests
# ============================================================================


func test_saturation_duration_constant() -> void:
	assert_eq(MockLevelHelper.SATURATION_DURATION, 0.15, "Saturation duration should be 0.15s")


func test_saturation_intensity_constant() -> void:
	assert_eq(MockLevelHelper.SATURATION_INTENSITY, 0.25, "Saturation intensity should be 0.25")


func test_saturation_flash_in_time() -> void:
	var expected := 0.15 * 0.3
	assert_almost_eq(helper.get_saturation_flash_in_time(), expected, 0.001,
		"Flash in should be 30% of duration")


func test_saturation_flash_out_time() -> void:
	var expected := 0.15 * 0.7
	assert_almost_eq(helper.get_saturation_flash_out_time(), expected, 0.001,
		"Flash out should be 70% of duration")


# ============================================================================
# Game Over Condition Tests
# ============================================================================


func test_should_show_game_over_no_ammo_with_enemies() -> void:
	assert_true(helper.should_show_game_over(0, 0, 5, false),
		"Should show game over with no ammo and enemies remaining")


func test_should_not_show_game_over_with_ammo() -> void:
	assert_false(helper.should_show_game_over(10, 0, 5, false),
		"Should not show game over with current ammo")


func test_should_not_show_game_over_with_reserve() -> void:
	assert_false(helper.should_show_game_over(0, 30, 5, false),
		"Should not show game over with reserve ammo")


func test_should_not_show_game_over_no_enemies() -> void:
	assert_false(helper.should_show_game_over(0, 0, 0, false),
		"Should not show game over with no enemies (victory instead)")


func test_should_not_show_game_over_already_shown() -> void:
	assert_false(helper.should_show_game_over(0, 0, 5, true),
		"Should not show game over if already shown")


# ============================================================================
# Victory Condition Tests
# ============================================================================


func test_should_show_victory_no_enemies() -> void:
	assert_true(helper.should_show_victory(0), "Should show victory with no enemies")


func test_should_not_show_victory_with_enemies() -> void:
	assert_false(helper.should_show_victory(5), "Should not show victory with enemies remaining")


# ============================================================================
# Color Constants Tests
# ============================================================================


func test_death_color_is_red() -> void:
	assert_true(MockLevelHelper.COLOR_DEATH.r > MockLevelHelper.COLOR_DEATH.g,
		"Death color should be primarily red")


func test_victory_color_is_green() -> void:
	assert_true(MockLevelHelper.COLOR_VICTORY.g > MockLevelHelper.COLOR_VICTORY.r,
		"Victory color should be primarily green")
