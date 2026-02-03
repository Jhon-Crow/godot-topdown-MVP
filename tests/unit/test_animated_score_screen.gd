extends GutTest
## Unit tests for the AnimatedScoreScreen component.
##
## Tests cover:
## - Score data processing
## - Item list building
## - Animation state management
## - Rank color retrieval


## Test score data fixture.
var _test_score_data: Dictionary = {
	"total_score": 5000,
	"rank": "A",
	"kills": 10,
	"total_enemies": 10,
	"kill_points": 1000,
	"combo_points": 2000,
	"max_combo": 5,
	"time_bonus": 1500,
	"completion_time": 45.5,
	"accuracy_bonus": 500,
	"accuracy": 75.0,
	"shots_fired": 20,
	"hits_landed": 15,
	"damage_penalty": 0,
	"damage_taken": 0,
	"special_kill_bonus": 0,
	"ricochet_kills": 0,
	"penetration_kills": 0,
	"aggressiveness": 0.5,
	"special_kills_eligible": false,
	"max_possible_score": 10000
}


func test_animated_score_screen_can_be_instantiated():
	# Given: The animated score screen script
	var AnimatedScoreScreen = load("res://scripts/ui/animated_score_screen.gd")

	# When: We create an instance
	var score_screen = AnimatedScoreScreen.new()

	# Then: It should be valid
	assert_not_null(score_screen, "AnimatedScoreScreen should be instantiable")
	assert_true(score_screen is Control, "AnimatedScoreScreen should extend Control")

	# Cleanup
	score_screen.queue_free()


func test_get_rank_color_returns_correct_colors():
	# Given: The animated score screen class
	var AnimatedScoreScreen = load("res://scripts/ui/animated_score_screen.gd")

	# When/Then: Each rank returns the expected color
	assert_eq(AnimatedScoreScreen.get_rank_color("S"), Color(1.0, 0.84, 0.0, 1.0), "S rank should be gold")
	assert_eq(AnimatedScoreScreen.get_rank_color("A+"), Color(0.0, 1.0, 0.5, 1.0), "A+ rank should be bright green")
	assert_eq(AnimatedScoreScreen.get_rank_color("A"), Color(0.2, 0.8, 0.2, 1.0), "A rank should be green")
	assert_eq(AnimatedScoreScreen.get_rank_color("B"), Color(0.3, 0.7, 1.0, 1.0), "B rank should be blue")
	assert_eq(AnimatedScoreScreen.get_rank_color("C"), Color(1.0, 1.0, 1.0, 1.0), "C rank should be white")
	assert_eq(AnimatedScoreScreen.get_rank_color("D"), Color(1.0, 0.6, 0.2, 1.0), "D rank should be orange")
	assert_eq(AnimatedScoreScreen.get_rank_color("F"), Color(1.0, 0.2, 0.2, 1.0), "F rank should be red")


func test_get_rank_color_returns_white_for_unknown_rank():
	# Given: The animated score screen class
	var AnimatedScoreScreen = load("res://scripts/ui/animated_score_screen.gd")

	# When: We request a color for an unknown rank
	var color = AnimatedScoreScreen.get_rank_color("X")

	# Then: It should return white (default)
	assert_eq(color, Color.WHITE, "Unknown rank should return white")


func test_animated_score_screen_has_required_constants():
	# Given: The animated score screen script
	var AnimatedScoreScreen = load("res://scripts/ui/animated_score_screen.gd")
	var score_screen = AnimatedScoreScreen.new()

	# Then: Required constants should be defined
	assert_true(score_screen.TITLE_FADE_DURATION > 0, "TITLE_FADE_DURATION should be positive")
	assert_true(score_screen.ITEM_REVEAL_DURATION > 0, "ITEM_REVEAL_DURATION should be positive")
	assert_true(score_screen.ITEM_COUNT_DURATION > 0, "ITEM_COUNT_DURATION should be positive")
	assert_true(score_screen.PULSE_FREQUENCY > 0, "PULSE_FREQUENCY should be positive")
	assert_true(score_screen.RANK_FLASH_DURATION > 0, "RANK_FLASH_DURATION should be positive")
	assert_true(score_screen.RANK_SHRINK_DURATION > 0, "RANK_SHRINK_DURATION should be positive")

	# Cleanup
	score_screen.queue_free()


func test_animated_score_screen_has_rank_colors_dictionary():
	# Given: The animated score screen script
	var AnimatedScoreScreen = load("res://scripts/ui/animated_score_screen.gd")
	var score_screen = AnimatedScoreScreen.new()

	# Then: RANK_COLORS dictionary should have all required ranks
	assert_true(score_screen.RANK_COLORS.has("S"), "RANK_COLORS should have S rank")
	assert_true(score_screen.RANK_COLORS.has("A+"), "RANK_COLORS should have A+ rank")
	assert_true(score_screen.RANK_COLORS.has("A"), "RANK_COLORS should have A rank")
	assert_true(score_screen.RANK_COLORS.has("B"), "RANK_COLORS should have B rank")
	assert_true(score_screen.RANK_COLORS.has("C"), "RANK_COLORS should have C rank")
	assert_true(score_screen.RANK_COLORS.has("D"), "RANK_COLORS should have D rank")
	assert_true(score_screen.RANK_COLORS.has("F"), "RANK_COLORS should have F rank")

	# Cleanup
	score_screen.queue_free()


func test_animated_score_screen_has_flash_colors_array():
	# Given: The animated score screen script
	var AnimatedScoreScreen = load("res://scripts/ui/animated_score_screen.gd")
	var score_screen = AnimatedScoreScreen.new()

	# Then: FLASH_COLORS array should have multiple colors for the flashing effect
	assert_true(score_screen.FLASH_COLORS.size() >= 3, "FLASH_COLORS should have at least 3 colors")

	# Each color should have high alpha (visible)
	for color in score_screen.FLASH_COLORS:
		assert_true(color.a >= 0.8, "Flash colors should be mostly opaque")

	# Cleanup
	score_screen.queue_free()


func test_animated_score_screen_emits_animation_complete_signal():
	# Given: The animated score screen script
	var AnimatedScoreScreen = load("res://scripts/ui/animated_score_screen.gd")
	var score_screen = AnimatedScoreScreen.new()

	# Then: It should have the animation_complete signal
	assert_true(score_screen.has_signal("animation_complete"), "Should have animation_complete signal")

	# Cleanup
	score_screen.queue_free()


func test_show_score_creates_required_ui_elements():
	# Given: An animated score screen added to the scene tree
	var AnimatedScoreScreen = load("res://scripts/ui/animated_score_screen.gd")
	var score_screen = AnimatedScoreScreen.new()
	add_child_autofree(score_screen)

	# When: We call show_score
	score_screen.show_score(_test_score_data)

	# Allow a frame for nodes to be created
	await get_tree().process_frame

	# Then: Background and container should be created
	var background = score_screen.get_node_or_null("ScoreBackground")
	var container = score_screen.get_node_or_null("ScoreContainer")

	assert_not_null(background, "ScoreBackground should be created")
	assert_not_null(container, "ScoreContainer should be created")


func test_animated_score_screen_pulse_settings_are_valid():
	# Given: The animated score screen script
	var AnimatedScoreScreen = load("res://scripts/ui/animated_score_screen.gd")
	var score_screen = AnimatedScoreScreen.new()

	# Then: Pulse settings should be sensible
	assert_true(score_screen.PULSE_SCALE_MIN >= 0.8, "Min scale should not be too small")
	assert_true(score_screen.PULSE_SCALE_MIN <= 1.0, "Min scale should not exceed 1.0")
	assert_true(score_screen.PULSE_SCALE_MAX > score_screen.PULSE_SCALE_MIN, "Max scale should be greater than min")
	assert_true(score_screen.PULSE_SCALE_MAX <= 1.5, "Max scale should not be too large")
	assert_true(score_screen.PULSE_COLOR_INTENSITY >= 0.0, "Color intensity should be non-negative")
	assert_true(score_screen.PULSE_COLOR_INTENSITY <= 1.0, "Color intensity should not exceed 1.0")

	# Cleanup
	score_screen.queue_free()


func test_beep_audio_settings_are_sensible():
	# Given: The animated score screen script
	var AnimatedScoreScreen = load("res://scripts/ui/animated_score_screen.gd")
	var score_screen = AnimatedScoreScreen.new()

	# Then: Audio settings should be within reasonable ranges
	assert_true(score_screen.BEEP_BASE_FREQUENCY >= 100.0, "Beep frequency should be audible")
	assert_true(score_screen.BEEP_BASE_FREQUENCY <= 2000.0, "Beep frequency should not be too high")
	assert_true(score_screen.BEEP_DURATION > 0.0, "Beep duration should be positive")
	assert_true(score_screen.BEEP_DURATION <= 0.5, "Beep duration should be short")
	assert_true(score_screen.BEEP_VOLUME <= 0.0, "Beep volume should be in negative dB range")

	# Cleanup
	score_screen.queue_free()


func test_score_screen_handles_missing_score_data_gracefully():
	# Given: An animated score screen added to the scene tree
	var AnimatedScoreScreen = load("res://scripts/ui/animated_score_screen.gd")
	var score_screen = AnimatedScoreScreen.new()
	add_child_autofree(score_screen)

	# When: We call show_score with minimal data (some fields missing)
	var minimal_data: Dictionary = {
		"total_score": 100,
		"rank": "F",
		"kills": 1,
		"total_enemies": 5
	}

	# Then: It should not crash
	score_screen.show_score(minimal_data)

	# Allow a frame for processing
	await get_tree().process_frame

	# Should still create UI elements
	var background = score_screen.get_node_or_null("ScoreBackground")
	assert_not_null(background, "Should handle minimal data without crashing")


func test_score_screen_handles_special_kills_data():
	# Given: An animated score screen added to the scene tree
	var AnimatedScoreScreen = load("res://scripts/ui/animated_score_screen.gd")
	var score_screen = AnimatedScoreScreen.new()
	add_child_autofree(score_screen)

	# When: We call show_score with special kills
	var data_with_special_kills = _test_score_data.duplicate()
	data_with_special_kills["ricochet_kills"] = 3
	data_with_special_kills["penetration_kills"] = 2
	data_with_special_kills["special_kill_bonus"] = 750
	data_with_special_kills["special_kills_eligible"] = true

	# Then: It should not crash
	score_screen.show_score(data_with_special_kills)

	# Allow a frame for processing
	await get_tree().process_frame

	var background = score_screen.get_node_or_null("ScoreBackground")
	assert_not_null(background, "Should handle special kills data without crashing")


func test_score_screen_handles_damage_penalty_data():
	# Given: An animated score screen added to the scene tree
	var AnimatedScoreScreen = load("res://scripts/ui/animated_score_screen.gd")
	var score_screen = AnimatedScoreScreen.new()
	add_child_autofree(score_screen)

	# When: We call show_score with damage penalty
	var data_with_damage = _test_score_data.duplicate()
	data_with_damage["damage_taken"] = 3
	data_with_damage["damage_penalty"] = 600

	# Then: It should not crash
	score_screen.show_score(data_with_damage)

	# Allow a frame for processing
	await get_tree().process_frame

	var background = score_screen.get_node_or_null("ScoreBackground")
	assert_not_null(background, "Should handle damage penalty data without crashing")
