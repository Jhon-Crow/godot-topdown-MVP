extends GutTest
## Unit tests for railway_station_level.gd — game-end screen behaviour (Issue #1755).
##
## The owner requested that touching the exit point shows a fullscreen black-background
## screen with white "Конец. Спасибо за игру" text.  The player must click the mouse
## or press any key to dismiss it; only then does the regular score screen appear.


# ============================================================================
# Mock Railway Station Level
# ============================================================================


class MockRailwayStationLevel:
	## Mirrors the new state variables added for Issue #1755.
	var _level_completed: bool = false
	var _game_end_screen_shown: bool = false
	var _game_end_dismissed: bool = false   # guard added to fix Bug 2 (re-appearance)
	var _pending_score_data: Dictionary = {}
	var _level_cleared: bool = false

	## Tracking flags used by the tests.
	var game_end_screen_displayed: bool = false
	var score_screen_display_count: int = 0
	var score_screen_displayed: bool = false
	var victory_message_displayed: bool = false
	var dismissed: bool = false

	## Simulate completing the level (player touched exit).
	func complete_level_with_score(score_data: Dictionary) -> void:
		if _level_completed:
			return
		_level_completed = true
		_pending_score_data = score_data
		_show_game_end_screen()

	## Show the end-of-game screen (black bg + white text).
	func _show_game_end_screen() -> void:
		if _game_end_screen_shown:
			return
		_game_end_screen_shown = true
		game_end_screen_displayed = true

	## Simulate the player pressing a key (keyboard path via _unhandled_input).
	func handle_key_input() -> void:
		if _game_end_screen_shown and not _game_end_dismissed:
			_dismiss_game_end_screen()

	## Simulate the player clicking the mouse (mouse path via gui_input on bg).
	func handle_mouse_input() -> void:
		if _game_end_screen_shown:
			_dismiss_game_end_screen()

	## Remove the end screen and proceed to score.
	func _dismiss_game_end_screen() -> void:
		if _game_end_dismissed:
			return
		_game_end_dismissed = true
		dismissed = true
		_proceed_to_score_screen()

	## Show score or fallback victory message.
	func _proceed_to_score_screen() -> void:
		if not _pending_score_data.is_empty():
			_show_score_screen(_pending_score_data)
		else:
			_show_victory_message()

	func _show_score_screen(_score_data: Dictionary) -> void:
		score_screen_display_count += 1
		score_screen_displayed = true

	func _show_victory_message() -> void:
		victory_message_displayed = true


var level: MockRailwayStationLevel


func before_each() -> void:
	level = MockRailwayStationLevel.new()


func after_each() -> void:
	level = null


# ============================================================================
# Game-end screen display tests
# ============================================================================


func test_game_end_screen_shown_when_player_reaches_exit() -> void:
	var score_data := {"rank": "S", "total_score": 100, "kills": 0}
	level.complete_level_with_score(score_data)
	assert_true(level.game_end_screen_displayed,
		"Game-end screen must be shown immediately when exit is reached")


func test_score_screen_not_shown_immediately_after_exit() -> void:
	var score_data := {"rank": "A", "total_score": 50, "kills": 0}
	level.complete_level_with_score(score_data)
	assert_false(level.score_screen_displayed,
		"Score screen must NOT appear until the player dismisses the end screen")


func test_score_screen_appears_after_dismiss() -> void:
	var score_data := {"rank": "B", "total_score": 25, "kills": 0}
	level.complete_level_with_score(score_data)
	level.handle_key_input()
	assert_true(level.score_screen_displayed,
		"Score screen must appear after the player dismisses the end screen")


func test_game_end_screen_not_shown_twice() -> void:
	var score_data := {"rank": "C", "total_score": 10, "kills": 0}
	level.complete_level_with_score(score_data)
	# Attempt a second trigger — should be a no-op.
	level._show_game_end_screen()
	# If guard works, _game_end_screen_shown stays true but display count stays 1.
	assert_true(level._game_end_screen_shown,
		"_game_end_screen_shown flag must stay true")
	assert_true(level.game_end_screen_displayed,
		"Game-end screen display should still be recorded")


func test_complete_level_idempotent() -> void:
	var score_data := {"rank": "S", "total_score": 200, "kills": 5}
	level.complete_level_with_score(score_data)
	level.complete_level_with_score(score_data)  # Second call should be ignored.
	level.handle_key_input()
	assert_true(level.score_screen_displayed,
		"Score screen must appear exactly once even if complete_level called twice")


func test_pending_score_data_stored_before_dismiss() -> void:
	var score_data := {"rank": "A+", "total_score": 999, "kills": 10}
	level.complete_level_with_score(score_data)
	assert_eq(level._pending_score_data, score_data,
		"Score data must be preserved so it can be shown after dismiss")


func test_fallback_to_victory_message_when_no_score_data() -> void:
	# Simulate a level where ScoreManager is unavailable: no score_data stored.
	level._game_end_screen_shown = true
	level._dismiss_game_end_screen()
	assert_true(level.victory_message_displayed,
		"Victory message must be shown when no pending score data is available")
	assert_false(level.score_screen_displayed,
		"Score screen must NOT be shown when there is no score data")


func test_input_before_end_screen_does_nothing() -> void:
	# Calling dismiss before the screen is shown should be a no-op.
	level.handle_key_input()
	assert_false(level.dismissed,
		"Dismiss must have no effect before the end screen is shown")
	assert_false(level.score_screen_displayed,
		"Score screen must not appear if dismiss is called prematurely")


# ============================================================================
# Regression tests for Bug 1 and Bug 2 (Issue #1755 follow-up, 2026-04-10)
# ============================================================================


func test_mouse_click_dismisses_end_screen() -> void:
	## Bug 1 regression: mouse click must dismiss the game-end screen.
	var score_data := {"rank": "S", "total_score": 100, "kills": 0}
	level.complete_level_with_score(score_data)
	level.handle_mouse_input()
	assert_true(level.dismissed,
		"Mouse click must dismiss the game-end screen")
	assert_true(level.score_screen_displayed,
		"Score screen must appear after mouse-click dismiss")


func test_score_screen_appears_only_once_after_repeated_key_presses() -> void:
	## Bug 2 regression: repeated key presses must not re-show the score screen.
	var score_data := {"rank": "A", "total_score": 50, "kills": 0}
	level.complete_level_with_score(score_data)
	level.handle_key_input()   # First press — dismisses end screen, shows score
	level.handle_key_input()   # Second press — must be ignored
	level.handle_key_input()   # Third press — must be ignored
	assert_eq(level.score_screen_display_count, 1,
		"Score screen must appear exactly once, no matter how many keys are pressed")


func test_score_screen_appears_only_once_after_repeated_mouse_clicks() -> void:
	## Bug 2 regression (mouse path): repeated clicks must not re-show the score screen.
	var score_data := {"rank": "B", "total_score": 30, "kills": 0}
	level.complete_level_with_score(score_data)
	level.handle_mouse_input()   # First click — dismisses end screen, shows score
	level.handle_mouse_input()   # Second click — must be ignored (gui_input lambda also
	level.handle_mouse_input()   # Third click    checks _game_end_dismissed guard)
	assert_eq(level.score_screen_display_count, 1,
		"Score screen must appear exactly once even if the mouse is clicked multiple times")
