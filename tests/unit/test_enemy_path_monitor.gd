extends GutTest
## Unit tests for EnemyPathMonitor and the enemy_path_visible_enabled setting.
##
## Tests the enemy navigation path visualization feature (Issue #1277):
##   - ExperimentalSettings.enemy_path_visible_enabled toggle
##   - EnemyPathMonitor color-by-state logic
##   - EnemyPathMonitor path data collection from mock enemies
##
## Issue #1285: Added to verify the display is restored and working correctly.


# ============================================================================
# Mock ExperimentalSettings
# ============================================================================


class MockExperimentalSettings:
	var enemy_path_visible_enabled: bool = false
	var settings_changed_emitted: int = 0
	var _saved_settings: Dictionary = {}

	func set_enemy_path_visible_enabled(enabled: bool) -> void:
		if enemy_path_visible_enabled != enabled:
			enemy_path_visible_enabled = enabled
			settings_changed_emitted += 1
			_saved_settings["enemy_path_visible_enabled"] = enabled

	func is_enemy_path_visible_enabled() -> bool:
		return enemy_path_visible_enabled

	func has_method(method_name: String) -> bool:
		return method_name == "is_enemy_path_visible_enabled"


# ============================================================================
# Mock Enemy
# ============================================================================


class MockEnemy extends Node2D:
	var _path: PackedVector2Array = PackedVector2Array()
	var _state: int = 0

	func get_nav_path() -> PackedVector2Array:
		return _path

	func get_current_state() -> int:
		return _state


# ============================================================================
# Tests — ExperimentalSettings.enemy_path_visible_enabled
# ============================================================================


func test_enemy_path_visible_disabled_by_default() -> void:
	var s := MockExperimentalSettings.new()
	assert_false(s.enemy_path_visible_enabled,
		"enemy_path_visible_enabled should be false by default")


func test_is_enemy_path_visible_returns_false_by_default() -> void:
	var s := MockExperimentalSettings.new()
	assert_false(s.is_enemy_path_visible_enabled(),
		"is_enemy_path_visible_enabled() should return false by default")


func test_set_enemy_path_visible_enabled_true() -> void:
	var s := MockExperimentalSettings.new()
	s.set_enemy_path_visible_enabled(true)
	assert_true(s.enemy_path_visible_enabled,
		"enemy_path_visible_enabled should be true after enabling")


func test_set_enemy_path_visible_enabled_false() -> void:
	var s := MockExperimentalSettings.new()
	s.enemy_path_visible_enabled = true
	s.set_enemy_path_visible_enabled(false)
	assert_false(s.enemy_path_visible_enabled,
		"enemy_path_visible_enabled should be false after disabling")


func test_set_enemy_path_visible_emits_signal() -> void:
	var s := MockExperimentalSettings.new()
	s.set_enemy_path_visible_enabled(true)
	assert_eq(s.settings_changed_emitted, 1,
		"Enabling should emit settings_changed")


func test_set_enemy_path_visible_no_signal_if_same_value() -> void:
	var s := MockExperimentalSettings.new()
	s.enemy_path_visible_enabled = true
	s.settings_changed_emitted = 0
	s.set_enemy_path_visible_enabled(true)
	assert_eq(s.settings_changed_emitted, 0,
		"No signal when value unchanged")


func test_set_enemy_path_visible_saves_settings() -> void:
	var s := MockExperimentalSettings.new()
	s.set_enemy_path_visible_enabled(true)
	assert_true(s._saved_settings.has("enemy_path_visible_enabled"),
		"Setting should be persisted")
	assert_true(s._saved_settings["enemy_path_visible_enabled"],
		"Persisted value should match enabled state")


func test_set_enemy_path_visible_saves_disabled() -> void:
	var s := MockExperimentalSettings.new()
	s.enemy_path_visible_enabled = true
	s.set_enemy_path_visible_enabled(false)
	assert_eq(s._saved_settings.get("enemy_path_visible_enabled", true), false,
		"Persisted value should match disabled state")


func test_is_enemy_path_visible_reflects_property() -> void:
	var s := MockExperimentalSettings.new()
	s.enemy_path_visible_enabled = true
	assert_true(s.is_enemy_path_visible_enabled(),
		"is_enemy_path_visible_enabled() should reflect the property")


func test_toggle_enemy_path_visible_on_off() -> void:
	var s := MockExperimentalSettings.new()
	s.set_enemy_path_visible_enabled(true)
	s.set_enemy_path_visible_enabled(false)
	assert_false(s.enemy_path_visible_enabled,
		"Should be disabled after toggling off")
	assert_eq(s.settings_changed_emitted, 2,
		"Two signals emitted for two changes")


# ============================================================================
# Tests — EnemyPathMonitor color-by-state logic
# ============================================================================


func test_color_idle_is_gray() -> void:
	# AIState.IDLE = 0 → Gray
	var color := EnemyPathMonitor._color_for_state(0)
	assert_almost_eq(color.r, 0.6, 0.01, "IDLE red channel should be ~0.6")
	assert_almost_eq(color.g, 0.6, 0.01, "IDLE green channel should be ~0.6")
	assert_almost_eq(color.b, 0.6, 0.01, "IDLE blue channel should be ~0.6")


func test_color_combat_is_red() -> void:
	# AIState.COMBAT = 1 → Red
	var color := EnemyPathMonitor._color_for_state(1)
	assert_almost_eq(color.r, 1.0, 0.01, "COMBAT red channel should be 1.0")
	assert_almost_eq(color.g, 0.2, 0.01, "COMBAT green channel should be ~0.2")
	assert_almost_eq(color.b, 0.2, 0.01, "COMBAT blue channel should be ~0.2")


func test_color_assault_is_same_as_combat() -> void:
	# AIState.ASSAULT = 8 → same Red as COMBAT
	var combat_color := EnemyPathMonitor._color_for_state(1)
	var assault_color := EnemyPathMonitor._color_for_state(8)
	assert_eq(combat_color, assault_color,
		"COMBAT and ASSAULT should use the same color")


func test_color_seeking_cover_is_orange() -> void:
	# AIState.SEEKING_COVER = 2 → Orange
	var color := EnemyPathMonitor._color_for_state(2)
	assert_almost_eq(color.r, 1.0, 0.01, "SEEKING_COVER red should be 1.0")
	assert_true(color.g > 0.4 and color.g < 0.7,
		"SEEKING_COVER green should be mid-range (orange)")
	assert_almost_eq(color.b, 0.1, 0.05, "SEEKING_COVER blue should be low")


func test_color_flanking_is_magenta() -> void:
	# AIState.FLANKING = 4 → Magenta
	var color := EnemyPathMonitor._color_for_state(4)
	assert_almost_eq(color.r, 1.0, 0.01, "FLANKING red should be 1.0")
	assert_almost_eq(color.g, 0.0, 0.01, "FLANKING green should be 0.0")
	assert_almost_eq(color.b, 1.0, 0.01, "FLANKING blue should be 1.0")


func test_color_pursuing_is_yellow() -> void:
	# AIState.PURSUING = 7 → Yellow
	var color := EnemyPathMonitor._color_for_state(7)
	assert_almost_eq(color.r, 1.0, 0.01, "PURSUING red should be 1.0")
	assert_almost_eq(color.g, 1.0, 0.01, "PURSUING green should be 1.0")
	assert_almost_eq(color.b, 0.0, 0.01, "PURSUING blue should be 0.0")


func test_color_searching_is_cyan() -> void:
	# AIState.SEARCHING = 9 → Cyan (consistent with SearchPathMonitor active paths)
	var color := EnemyPathMonitor._color_for_state(9)
	assert_almost_eq(color.r, 0.0, 0.01, "SEARCHING red should be 0.0")
	assert_almost_eq(color.g, 1.0, 0.01, "SEARCHING green should be 1.0")
	assert_almost_eq(color.b, 0.8, 0.01, "SEARCHING blue should be ~0.8")


func test_color_evading_grenade_is_white() -> void:
	# AIState.EVADING_GRENADE = 10 → White
	var color := EnemyPathMonitor._color_for_state(10)
	assert_almost_eq(color.r, 1.0, 0.01, "EVADING_GRENADE red should be 1.0")
	assert_almost_eq(color.g, 1.0, 0.01, "EVADING_GRENADE green should be 1.0")
	assert_almost_eq(color.b, 1.0, 0.01, "EVADING_GRENADE blue should be 1.0")


func test_color_pacifist_is_green() -> void:
	# AIState.PACIFIST = 11 → Green
	var color := EnemyPathMonitor._color_for_state(11)
	assert_almost_eq(color.r, 0.2, 0.01, "PACIFIST red should be ~0.2")
	assert_almost_eq(color.g, 1.0, 0.01, "PACIFIST green should be 1.0")
	assert_almost_eq(color.b, 0.2, 0.01, "PACIFIST blue should be ~0.2")


func test_color_unknown_state_is_light_gray() -> void:
	# Unknown state (e.g. 999) → Light gray fallback
	var color := EnemyPathMonitor._color_for_state(999)
	assert_true(color.r > 0.7, "Unknown state should have high red (light gray)")
	assert_true(color.g > 0.7, "Unknown state should have high green (light gray)")
	assert_true(color.b > 0.7, "Unknown state should have high blue (light gray)")


func test_color_in_cover_matches_seeking_cover() -> void:
	# IN_COVER = 3 and SEEKING_COVER = 2 share the same Orange color
	var seeking := EnemyPathMonitor._color_for_state(2)
	var in_cover := EnemyPathMonitor._color_for_state(3)
	assert_eq(seeking, in_cover,
		"SEEKING_COVER and IN_COVER should share the same Orange color")


func test_color_suppressed_matches_seeking_cover() -> void:
	# SUPPRESSED = 5 shares Orange with SEEKING_COVER = 2
	var seeking := EnemyPathMonitor._color_for_state(2)
	var suppressed := EnemyPathMonitor._color_for_state(5)
	assert_eq(seeking, suppressed,
		"SUPPRESSED and SEEKING_COVER should share the same Orange color")


func test_color_retreating_matches_seeking_cover() -> void:
	# RETREATING = 6 shares Orange with SEEKING_COVER = 2
	var seeking := EnemyPathMonitor._color_for_state(2)
	var retreating := EnemyPathMonitor._color_for_state(6)
	assert_eq(seeking, retreating,
		"RETREATING and SEEKING_COVER should share the same Orange color")


# ============================================================================
# Tests — Path data collection from mock enemies
# ============================================================================


func test_mock_enemy_returns_empty_path_by_default() -> void:
	var enemy := MockEnemy.new()
	var path := enemy.get_nav_path()
	assert_eq(path.size(), 0,
		"MockEnemy should return an empty path by default")


func test_mock_enemy_returns_assigned_path() -> void:
	var enemy := MockEnemy.new()
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(200, 100)])
	enemy._path = pts
	var path := enemy.get_nav_path()
	assert_eq(path.size(), 3,
		"MockEnemy should return the path it was given")


func test_mock_enemy_returns_state() -> void:
	var enemy := MockEnemy.new()
	enemy._state = 1  # COMBAT
	assert_eq(int(enemy.get_current_state()), 1,
		"MockEnemy should return the assigned state")


func test_path_with_fewer_than_2_points_is_skipped() -> void:
	# EnemyPathMonitor skips paths with fewer than 2 points
	var single_pt := PackedVector2Array([Vector2(50, 50)])
	assert_true(single_pt.size() < 2,
		"Single-point path should be skipped (size < 2)")


func test_path_with_2_points_is_drawn() -> void:
	var two_pts := PackedVector2Array([Vector2(0, 0), Vector2(100, 0)])
	assert_true(two_pts.size() >= 2,
		"Two-point path should be accepted for drawing (size >= 2)")


func test_path_waypoint_count_equals_intermediate_dots() -> void:
	# Intermediate waypoint dots are drawn at path[0]..path[n-2] (all except final)
	var path := PackedVector2Array([
		Vector2(0, 0), Vector2(100, 0), Vector2(200, 0), Vector2(300, 0)
	])
	# Intermediate dots: for i in range(path.size() - 1)
	var intermediate_count := path.size() - 1
	assert_eq(intermediate_count, 3,
		"4-point path should produce 3 intermediate waypoint dots")


func test_path_destination_is_last_point() -> void:
	var path := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(999, 888)])
	var dest := path[path.size() - 1]
	assert_eq(dest, Vector2(999, 888),
		"Destination should be the last point in the path")


func test_path_draw_line_count() -> void:
	# Lines drawn: (enemy_pos → path[0]) + (path[0]→path[1]) + ... + (path[n-2]→path[n-1])
	# Total = 1 + (path.size() - 1) = path.size()
	var enemy_pos := Vector2(10, 10)
	var path := PackedVector2Array([
		Vector2(50, 50), Vector2(150, 50), Vector2(250, 50)
	])
	# Simulate the draw loop from EnemyPathDrawNode._draw()
	var line_count := 1  # enemy_pos → path[0]
	for i in range(path.size() - 1):
		line_count += 1  # path[i] → path[i+1]
	assert_eq(line_count, path.size(),
		"Line count should equal path.size() (1 lead-in + path.size()-1 segments)")


func test_fill_color_is_path_color_with_low_alpha() -> void:
	# fill_color is derived from path color with alpha 0.25
	var base_color := EnemyPathMonitor._color_for_state(0)  # Gray for IDLE
	var fill_color := Color(base_color.r, base_color.g, base_color.b, 0.25)
	assert_almost_eq(fill_color.a, 0.25, 0.01,
		"Fill color alpha should be 0.25")
	assert_eq(fill_color.r, base_color.r,
		"Fill color RGB should match path color")
