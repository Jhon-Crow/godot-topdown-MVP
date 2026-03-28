extends GutTest
## Unit tests for factory_level.gd level script.
##
## Tests saturation constants, exit zone configuration, and level initialization
## for the building-style factory map with 13 enemies.


# ============================================================================
# Mock Classes
# ============================================================================


class MockExperimentalSettings:
	## Whether replay viewing is enabled (Issue #807).
	var replay_enabled: bool = false

	func is_replay_enabled() -> bool:
		return replay_enabled


class MockScoreScreenButtons:
	## Simulates the replay button visibility logic from factory_level.gd
	## _add_score_screen_buttons (Issue #1610: guard replay button with
	## experimental_settings check).
	var experimental_settings: MockExperimentalSettings = null
	var replay_button_added: bool = false

	func add_score_screen_buttons() -> void:
		replay_button_added = false
		var replay_enabled: bool = (
			experimental_settings != null
			and experimental_settings.is_replay_enabled()
		)
		if replay_enabled:
			replay_button_added = true


class MockUnhandledInput:
	## Simulates the _unhandled_input W-key logic from factory_level.gd
	## (Issue #1610: guard W key replay trigger with experimental_settings check).
	var experimental_settings: MockExperimentalSettings = null
	var _score_shown: bool = true
	var replay_triggered: bool = false

	func handle_w_key() -> void:
		if not _score_shown:
			return
		if experimental_settings and experimental_settings.is_replay_enabled():
			replay_triggered = true


class MockFactoryLevel:
	## Saturation effect constants (must match factory_level.gd).
	const SATURATION_DURATION: float = 0.15
	const SATURATION_INTENSITY: float = 0.25

	## Level state variables.
	var _initial_enemy_count: int = 0
	var _current_enemy_count: int = 0
	var _level_cleared: bool = false
	var _level_completed: bool = false
	var _game_over_shown: bool = false
	var _score_shown: bool = false
	var _enemies: Array = []

	## Exit zone configuration.
	var exit_zone_position: Vector2 = Vector2(120, 1000)
	var exit_zone_width: float = 60.0
	var exit_zone_height: float = 100.0

	## Track state changes.
	var exit_zone_activated: bool = false

	## Level name for identification.
	var level_name: String = "FactoryLevel"

	## Factory dimensions (~2400x2000 pixels).
	var map_width: int = 2400
	var map_height: int = 2000

	## Default enemy count for factory level.
	var default_enemy_count: int = 13

	## Initialize with default enemies.
	func initialize() -> void:
		_enemies.clear()
		for i in range(default_enemy_count):
			_enemies.append("FactoryEnemy%d" % (i + 1))
		_initial_enemy_count = _enemies.size()
		_current_enemy_count = _initial_enemy_count

	## Called when an enemy dies.
	func on_enemy_died() -> void:
		_current_enemy_count -= 1
		if _current_enemy_count <= 0:
			_level_cleared = true
			exit_zone_activated = true

	## Called when player reaches exit after clearing.
	func on_player_reached_exit() -> void:
		if not _level_cleared or _level_completed:
			return
		_level_completed = true


var level: MockFactoryLevel


func before_each() -> void:
	level = MockFactoryLevel.new()


func after_each() -> void:
	level = null


# ============================================================================
# Saturation Constants Tests
# ============================================================================


func test_saturation_duration() -> void:
	assert_eq(level.SATURATION_DURATION, 0.15,
		"SATURATION_DURATION should be 0.15 seconds")


func test_saturation_intensity() -> void:
	assert_eq(level.SATURATION_INTENSITY, 0.25,
		"SATURATION_INTENSITY should be 0.25")


# ============================================================================
# Exit Zone Tests
# ============================================================================


func test_exit_zone_position() -> void:
	assert_eq(level.exit_zone_position, Vector2(120, 1000),
		"Factory level exit zone should be at (120, 1000)")


func test_exit_zone_dimensions() -> void:
	assert_eq(level.exit_zone_width, 60.0,
		"Exit zone width should be 60.0")
	assert_eq(level.exit_zone_height, 100.0,
		"Exit zone height should be 100.0")


# ============================================================================
# Level Initialization Tests
# ============================================================================


func test_default_enemy_count() -> void:
	assert_eq(level.default_enemy_count, 13,
		"Factory level should have 13 enemies by default")


func test_level_starts_not_cleared() -> void:
	level.initialize()
	assert_false(level._level_cleared,
		"Level should not be cleared at start")


func test_enemy_count_initialized_correctly() -> void:
	level.initialize()
	assert_eq(level._initial_enemy_count, 13,
		"Initial enemy count should be 13")
	assert_eq(level._current_enemy_count, 13,
		"Current enemy count should be 13 at start")


func test_level_cleared_when_all_enemies_dead() -> void:
	level.initialize()
	for i in range(12):
		level.on_enemy_died()
	assert_false(level._level_cleared, "Not cleared with 1 enemy remaining")
	level.on_enemy_died()
	assert_true(level._level_cleared, "Level should be cleared when all 13 enemies dead")
	assert_true(level.exit_zone_activated, "Exit zone should activate on clear")


func test_player_exit_completes_level() -> void:
	level.initialize()
	for i in range(13):
		level.on_enemy_died()
	level.on_player_reached_exit()
	assert_true(level._level_completed,
		"Level should complete when player reaches exit after clearing")


func test_player_exit_blocked_before_clear() -> void:
	level.initialize()
	level.on_player_reached_exit()
	assert_false(level._level_completed,
		"Level should not complete if enemies remain")


func test_map_dimensions() -> void:
	assert_eq(level.map_width, 2400, "Factory map width should be 2400")
	assert_eq(level.map_height, 2000, "Factory map height should be 2000")


# ============================================================================
# Replay Button Visibility Tests (Issue #1610)
# ============================================================================


func test_replay_button_not_added_when_replay_disabled() -> void:
	var screen := MockScoreScreenButtons.new()
	var settings := MockExperimentalSettings.new()
	settings.replay_enabled = false
	screen.experimental_settings = settings
	screen.add_score_screen_buttons()
	assert_false(screen.replay_button_added,
		"Replay button must not appear on score screen when replay is disabled in experimental settings")


func test_replay_button_added_when_replay_enabled() -> void:
	var screen := MockScoreScreenButtons.new()
	var settings := MockExperimentalSettings.new()
	settings.replay_enabled = true
	screen.experimental_settings = settings
	screen.add_score_screen_buttons()
	assert_true(screen.replay_button_added,
		"Replay button should appear on score screen when replay is enabled in experimental settings")


func test_replay_button_not_added_when_no_experimental_settings() -> void:
	var screen := MockScoreScreenButtons.new()
	screen.experimental_settings = null
	screen.add_score_screen_buttons()
	assert_false(screen.replay_button_added,
		"Replay button must not appear when experimental settings node is absent")


func test_w_key_does_not_trigger_replay_when_disabled() -> void:
	var handler := MockUnhandledInput.new()
	var settings := MockExperimentalSettings.new()
	settings.replay_enabled = false
	handler.experimental_settings = settings
	handler.handle_w_key()
	assert_false(handler.replay_triggered,
		"W key must not trigger replay when replay is disabled in experimental settings")


func test_w_key_triggers_replay_when_enabled() -> void:
	var handler := MockUnhandledInput.new()
	var settings := MockExperimentalSettings.new()
	settings.replay_enabled = true
	handler.experimental_settings = settings
	handler.handle_w_key()
	assert_true(handler.replay_triggered,
		"W key should trigger replay when replay is enabled in experimental settings")


func test_w_key_does_not_trigger_replay_when_no_experimental_settings() -> void:
	var handler := MockUnhandledInput.new()
	handler.experimental_settings = null
	handler.handle_w_key()
	assert_false(handler.replay_triggered,
		"W key must not trigger replay when experimental settings node is absent")
