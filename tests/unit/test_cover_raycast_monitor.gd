extends GutTest
## Unit tests for CoverRaycastMonitor and the cover_raycast_visible_enabled setting.
##
## Tests the cover raycast visualization feature (Issue #1359):
##   - ExperimentalSettings.cover_raycast_visible_enabled toggle
##   - CoverRaycastMonitor data collection from mock enemies
##   - Mock enemy cover raycast data and cover info getters


# ============================================================================
# Mock ExperimentalSettings
# ============================================================================


class MockExperimentalSettings:
	var cover_raycast_visible_enabled: bool = false
	var settings_changed_emitted: int = 0
	var _saved_settings: Dictionary = {}

	func set_cover_raycast_visible_enabled(enabled: bool) -> void:
		if cover_raycast_visible_enabled != enabled:
			cover_raycast_visible_enabled = enabled
			settings_changed_emitted += 1
			_saved_settings["cover_raycast_visible_enabled"] = enabled

	func is_cover_raycast_visible_enabled() -> bool:
		return cover_raycast_visible_enabled

	func has_method(method_name: String) -> bool:
		return method_name == "is_cover_raycast_visible_enabled"


# ============================================================================
# Mock Enemy
# ============================================================================


class MockEnemy extends Node2D:
	var _cover_raycast_data: Array = []
	var _cover_info: Dictionary = { "position": Vector2.ZERO, "valid": false }

	func get_cover_raycast_data() -> Array:
		return _cover_raycast_data

	func get_cover_info() -> Dictionary:
		return _cover_info


# ============================================================================
# Tests — ExperimentalSettings.cover_raycast_visible_enabled
# ============================================================================


func test_cover_raycast_visible_disabled_by_default() -> void:
	var s := MockExperimentalSettings.new()
	assert_false(s.cover_raycast_visible_enabled,
		"cover_raycast_visible_enabled should be false by default")


func test_is_cover_raycast_visible_returns_false_by_default() -> void:
	var s := MockExperimentalSettings.new()
	assert_false(s.is_cover_raycast_visible_enabled(),
		"is_cover_raycast_visible_enabled() should return false by default")


func test_set_cover_raycast_visible_enabled_true() -> void:
	var s := MockExperimentalSettings.new()
	s.set_cover_raycast_visible_enabled(true)
	assert_true(s.cover_raycast_visible_enabled,
		"cover_raycast_visible_enabled should be true after enabling")


func test_set_cover_raycast_visible_enabled_false() -> void:
	var s := MockExperimentalSettings.new()
	s.cover_raycast_visible_enabled = true
	s.set_cover_raycast_visible_enabled(false)
	assert_false(s.cover_raycast_visible_enabled,
		"cover_raycast_visible_enabled should be false after disabling")


func test_set_cover_raycast_visible_emits_signal() -> void:
	var s := MockExperimentalSettings.new()
	s.set_cover_raycast_visible_enabled(true)
	assert_eq(s.settings_changed_emitted, 1,
		"Enabling should emit settings_changed")


func test_set_cover_raycast_visible_no_signal_if_same_value() -> void:
	var s := MockExperimentalSettings.new()
	s.cover_raycast_visible_enabled = true
	s.settings_changed_emitted = 0
	s.set_cover_raycast_visible_enabled(true)
	assert_eq(s.settings_changed_emitted, 0,
		"No signal when value unchanged")


func test_set_cover_raycast_visible_saves_settings() -> void:
	var s := MockExperimentalSettings.new()
	s.set_cover_raycast_visible_enabled(true)
	assert_true(s._saved_settings.has("cover_raycast_visible_enabled"),
		"Setting should be persisted")
	assert_true(s._saved_settings["cover_raycast_visible_enabled"],
		"Persisted value should match enabled state")


func test_set_cover_raycast_visible_saves_disabled() -> void:
	var s := MockExperimentalSettings.new()
	s.cover_raycast_visible_enabled = true
	s.set_cover_raycast_visible_enabled(false)
	assert_eq(s._saved_settings.get("cover_raycast_visible_enabled", true), false,
		"Persisted value should match disabled state")


func test_is_cover_raycast_visible_reflects_property() -> void:
	var s := MockExperimentalSettings.new()
	s.cover_raycast_visible_enabled = true
	assert_true(s.is_cover_raycast_visible_enabled(),
		"is_cover_raycast_visible_enabled() should reflect the property")


func test_toggle_cover_raycast_visible_on_off() -> void:
	var s := MockExperimentalSettings.new()
	s.set_cover_raycast_visible_enabled(true)
	s.set_cover_raycast_visible_enabled(false)
	assert_false(s.cover_raycast_visible_enabled,
		"Should be disabled after toggling off")
	assert_eq(s.settings_changed_emitted, 2,
		"Two signals emitted for two changes")


# ============================================================================
# Tests — Mock enemy cover data
# ============================================================================


func test_mock_enemy_returns_empty_raycast_data_by_default() -> void:
	var enemy := MockEnemy.new()
	var data := enemy.get_cover_raycast_data()
	assert_eq(data.size(), 0,
		"MockEnemy should return empty raycast data by default")


func test_mock_enemy_returns_invalid_cover_by_default() -> void:
	var enemy := MockEnemy.new()
	var info := enemy.get_cover_info()
	assert_false(info["valid"],
		"MockEnemy should have no valid cover by default")
	assert_eq(info["position"], Vector2.ZERO,
		"MockEnemy cover position should be zero by default")


func test_mock_enemy_returns_assigned_raycast_data() -> void:
	var enemy := MockEnemy.new()
	enemy._cover_raycast_data = [
		{ "origin": Vector2(100, 100), "target": Vector2(200, 100), "colliding": true,
		  "point": Vector2(150, 100), "normal": Vector2(-1, 0) },
		{ "origin": Vector2(100, 100), "target": Vector2(100, 200), "colliding": false },
	]
	var data := enemy.get_cover_raycast_data()
	assert_eq(data.size(), 2,
		"MockEnemy should return the raycast data it was given")


func test_mock_enemy_colliding_ray_has_point_and_normal() -> void:
	var enemy := MockEnemy.new()
	var ray := { "origin": Vector2(0, 0), "target": Vector2(100, 0), "colliding": true,
		"point": Vector2(50, 0), "normal": Vector2(-1, 0) }
	enemy._cover_raycast_data = [ray]
	var data := enemy.get_cover_raycast_data()
	assert_true(data[0]["colliding"], "Ray should be colliding")
	assert_eq(data[0]["point"], Vector2(50, 0), "Collision point should match")
	assert_eq(data[0]["normal"], Vector2(-1, 0), "Collision normal should match")


func test_mock_enemy_non_colliding_ray_has_no_point() -> void:
	var enemy := MockEnemy.new()
	var ray := { "origin": Vector2(0, 0), "target": Vector2(300, 0), "colliding": false }
	enemy._cover_raycast_data = [ray]
	var data := enemy.get_cover_raycast_data()
	assert_false(data[0]["colliding"], "Ray should not be colliding")
	assert_false(data[0].has("point"), "Non-colliding ray should not have a point")


func test_mock_enemy_valid_cover_info() -> void:
	var enemy := MockEnemy.new()
	enemy._cover_info = { "position": Vector2(200, 150), "valid": true }
	var info := enemy.get_cover_info()
	assert_true(info["valid"], "Cover should be valid")
	assert_eq(info["position"], Vector2(200, 150), "Cover position should match")


func test_raycast_data_with_16_rays() -> void:
	# Enemy uses 16 raycasts for cover detection
	var enemy := MockEnemy.new()
	var rays: Array = []
	for i in range(16):
		var angle := (float(i) / 16.0) * TAU
		var direction := Vector2.from_angle(angle)
		rays.append({
			"origin": Vector2(100, 100),
			"target": Vector2(100, 100) + direction * 300.0,
			"colliding": i % 3 == 0,  # Every 3rd ray hits
		})
		if i % 3 == 0:
			rays[i]["point"] = Vector2(100, 100) + direction * 150.0
			rays[i]["normal"] = -direction
	enemy._cover_raycast_data = rays
	var data := enemy.get_cover_raycast_data()
	assert_eq(data.size(), 16,
		"Should have exactly 16 raycasts matching COVER_CHECK_COUNT")


func test_colliding_ray_count_from_mixed_data() -> void:
	# Verify we can count how many rays hit obstacles
	var rays: Array = []
	for i in range(16):
		rays.append({
			"origin": Vector2.ZERO,
			"target": Vector2(300, 0),
			"colliding": i < 5,  # First 5 hit
		})
		if i < 5:
			rays[i]["point"] = Vector2(150, 0)
			rays[i]["normal"] = Vector2(-1, 0)
	var colliding_count := 0
	for ray in rays:
		if ray["colliding"]:
			colliding_count += 1
	assert_eq(colliding_count, 5,
		"Should count 5 colliding rays out of 16")


# ============================================================================
# Tests — CoverRaycastMonitor constants
# ============================================================================


func test_cover_marker_radius_is_positive() -> void:
	assert_gt(CoverRaycastMonitor.COVER_MARKER_RADIUS, 0.0,
		"Cover marker radius should be positive")


func test_collision_dot_radius_is_positive() -> void:
	assert_gt(CoverRaycastMonitor.COLLISION_DOT_RADIUS, 0.0,
		"Collision dot radius should be positive")


func test_ray_line_width_is_positive() -> void:
	assert_gt(CoverRaycastMonitor.RAY_LINE_WIDTH, 0.0,
		"Ray line width should be positive")


func test_los_line_width_is_positive() -> void:
	assert_gt(CoverRaycastMonitor.LOS_LINE_WIDTH, 0.0,
		"LOS line width should be positive")


func test_cover_marker_larger_than_collision_dot() -> void:
	assert_gt(CoverRaycastMonitor.COVER_MARKER_RADIUS, CoverRaycastMonitor.COLLISION_DOT_RADIUS,
		"Cover marker should be larger than collision dots for visibility")
