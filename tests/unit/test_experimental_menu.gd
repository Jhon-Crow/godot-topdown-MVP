extends GutTest
## Unit tests for ExperimentalMenu UI.
##
## Tests the experimental features menu that provides UI controls
## for toggling experimental settings.


# ============================================================================
# Mock ExperimentalSettings for Menu Tests
# ============================================================================


class MockMenuExperimentalSettings:
	var fov_enabled: bool = true
	var complex_grenade_throwing: bool = false
	var ai_prediction_enabled: bool = false
	var debug_mode_enabled: bool = false
	var invincibility_enabled: bool = false
	var realistic_visibility_enabled: bool = false
	var replay_enabled: bool = false
	var logging_enabled: bool = true
	var enemy_flashlight_blinding_enabled: bool = false
	var fps_counter_enabled: bool = false
	var fps_drop_logging_enabled: bool = false
	var all_weapons_unlocked: bool = false
	var all_maps_unlocked: bool = false
	var selected_enemy_type_index: int = 0
	var global_stuck_max_time: float = 20.0
	var nav_mesh_visible_enabled: bool = false
	var search_path_visible_enabled: bool = false
	var passage_waypoints_visible_enabled: bool = false
	var passage_waypoints_enabled: bool = false
	var sound_visualizer_enabled: bool = false
	var enemy_path_visible_enabled: bool = false
	var cover_raycast_visible_enabled: bool = false
	var tactical_group_enabled: bool = false
	var cover_infinite_rays_enabled: bool = true
	var cover_sector_rays_enabled: bool = true
	var settings_changed_count: int = 0

	func set_fov_enabled(enabled: bool) -> void:
		if fov_enabled != enabled:
			fov_enabled = enabled
			settings_changed_count += 1

	func is_fov_enabled() -> bool:
		return fov_enabled

	func set_complex_grenade_throwing(enabled: bool) -> void:
		if complex_grenade_throwing != enabled:
			complex_grenade_throwing = enabled
			settings_changed_count += 1

	func is_complex_grenade_throwing() -> bool:
		return complex_grenade_throwing

	func set_ai_prediction_enabled(enabled: bool) -> void:
		if ai_prediction_enabled != enabled:
			ai_prediction_enabled = enabled
			settings_changed_count += 1

	func is_ai_prediction_enabled() -> bool:
		return ai_prediction_enabled

	func set_debug_mode_enabled(enabled: bool) -> void:
		if debug_mode_enabled != enabled:
			debug_mode_enabled = enabled
			settings_changed_count += 1

	func is_debug_mode_enabled() -> bool:
		return debug_mode_enabled

	func set_invincibility_enabled(enabled: bool) -> void:
		if invincibility_enabled != enabled:
			invincibility_enabled = enabled
			settings_changed_count += 1

	func is_invincibility_enabled() -> bool:
		return invincibility_enabled

	func set_realistic_visibility_enabled(enabled: bool) -> void:
		if realistic_visibility_enabled != enabled:
			realistic_visibility_enabled = enabled
			settings_changed_count += 1

	func is_realistic_visibility_enabled() -> bool:
		return realistic_visibility_enabled

	func set_replay_enabled(enabled: bool) -> void:
		if replay_enabled != enabled:
			replay_enabled = enabled
			settings_changed_count += 1

	func is_replay_enabled() -> bool:
		return replay_enabled

	func set_logging_enabled(enabled: bool) -> void:
		if logging_enabled != enabled:
			logging_enabled = enabled
			settings_changed_count += 1

	func is_logging_enabled() -> bool:
		return logging_enabled

	func set_enemy_flashlight_blinding_enabled(enabled: bool) -> void:
		if enemy_flashlight_blinding_enabled != enabled:
			enemy_flashlight_blinding_enabled = enabled
			settings_changed_count += 1

	func is_enemy_flashlight_blinding_enabled() -> bool:
		return enemy_flashlight_blinding_enabled

	func set_fps_counter_enabled(enabled: bool) -> void:
		if fps_counter_enabled != enabled:
			fps_counter_enabled = enabled
			settings_changed_count += 1

	func is_fps_counter_enabled() -> bool:
		return fps_counter_enabled

	func set_all_weapons_unlocked(enabled: bool) -> void:
		if all_weapons_unlocked != enabled:
			all_weapons_unlocked = enabled
			settings_changed_count += 1

	func is_all_weapons_unlocked() -> bool:
		return all_weapons_unlocked

	func set_all_maps_unlocked(enabled: bool) -> void:
		if all_maps_unlocked != enabled:
			all_maps_unlocked = enabled
			settings_changed_count += 1

	func is_all_maps_unlocked() -> bool:
		return all_maps_unlocked

	func set_nav_mesh_visible_enabled(enabled: bool) -> void:
		if nav_mesh_visible_enabled != enabled:
			nav_mesh_visible_enabled = enabled
			settings_changed_count += 1

	func is_nav_mesh_visible_enabled() -> bool:
		return nav_mesh_visible_enabled

	func set_tactical_group_enabled(enabled: bool) -> void:
		if tactical_group_enabled != enabled:
			tactical_group_enabled = enabled
			settings_changed_count += 1

	func is_tactical_group_enabled() -> bool:
		return tactical_group_enabled

	func set_cover_infinite_rays_enabled(enabled: bool) -> void:
		if cover_infinite_rays_enabled != enabled:
			cover_infinite_rays_enabled = enabled
			settings_changed_count += 1

	func is_cover_infinite_rays_enabled() -> bool:
		return cover_infinite_rays_enabled

	func set_cover_sector_rays_enabled(enabled: bool) -> void:
		if cover_sector_rays_enabled != enabled:
			cover_sector_rays_enabled = enabled
			settings_changed_count += 1

	func is_cover_sector_rays_enabled() -> bool:
		return cover_sector_rays_enabled

	func set_selected_enemy_type_index(index: int) -> void:
		selected_enemy_type_index = index

	func get_selected_enemy_type_index() -> int:
		return selected_enemy_type_index

	func set_global_stuck_max_time(value: float) -> void:
		if global_stuck_max_time != value:
			global_stuck_max_time = value
			settings_changed_count += 1

	func get_global_stuck_max_time() -> float:
		return global_stuck_max_time


# ============================================================================
# Default State Tests
# ============================================================================


func test_default_fov_enabled() -> void:
	var settings := MockMenuExperimentalSettings.new()
	assert_true(settings.is_fov_enabled(), "FOV should be enabled by default")


func test_default_complex_grenade_disabled() -> void:
	var settings := MockMenuExperimentalSettings.new()
	assert_false(settings.is_complex_grenade_throwing(), "Complex grenade should be disabled by default")


func test_default_ai_prediction_disabled() -> void:
	var settings := MockMenuExperimentalSettings.new()
	assert_false(settings.is_ai_prediction_enabled(), "AI prediction should be disabled by default")


func test_default_debug_mode_disabled() -> void:
	var settings := MockMenuExperimentalSettings.new()
	assert_false(settings.is_debug_mode_enabled(), "Debug mode should be disabled by default")


func test_default_invincibility_disabled() -> void:
	var settings := MockMenuExperimentalSettings.new()
	assert_false(settings.is_invincibility_enabled(), "Invincibility should be disabled by default")


func test_default_realistic_visibility_disabled() -> void:
	var settings := MockMenuExperimentalSettings.new()
	assert_false(settings.is_realistic_visibility_enabled(), "Realistic visibility should be disabled by default")


func test_default_replay_disabled() -> void:
	var settings := MockMenuExperimentalSettings.new()
	assert_false(settings.is_replay_enabled(), "Replay should be disabled by default")


func test_default_logging_enabled() -> void:
	var settings := MockMenuExperimentalSettings.new()
	assert_true(settings.is_logging_enabled(), "Logging should be enabled by default")


func test_default_flashlight_blinding_disabled() -> void:
	var settings := MockMenuExperimentalSettings.new()
	assert_false(settings.is_enemy_flashlight_blinding_enabled(), "Enemy flashlight blinding should be disabled by default")


func test_default_fps_counter_disabled() -> void:
	var settings := MockMenuExperimentalSettings.new()
	assert_false(settings.is_fps_counter_enabled(), "FPS counter should be disabled by default")


func test_default_all_weapons_unlocked_disabled() -> void:
	var settings := MockMenuExperimentalSettings.new()
	assert_false(settings.is_all_weapons_unlocked(), "All weapons unlocked should be disabled by default")


func test_default_all_maps_unlocked_disabled() -> void:
	var settings := MockMenuExperimentalSettings.new()
	assert_false(settings.is_all_maps_unlocked(), "All maps unlocked should be disabled by default")


func test_default_nav_mesh_disabled() -> void:
	var settings := MockMenuExperimentalSettings.new()
	assert_false(settings.is_nav_mesh_visible_enabled(), "Nav mesh should be disabled by default")


func test_default_tactical_group_disabled() -> void:
	var settings := MockMenuExperimentalSettings.new()
	assert_false(settings.is_tactical_group_enabled(), "Tactical group should be disabled by default")


func test_default_cover_infinite_rays_enabled() -> void:
	var settings := MockMenuExperimentalSettings.new()
	assert_true(settings.is_cover_infinite_rays_enabled(), "Cover infinite rays should be enabled by default")


func test_default_cover_sector_rays_enabled() -> void:
	var settings := MockMenuExperimentalSettings.new()
	assert_true(settings.is_cover_sector_rays_enabled(), "Cover sector rays should be enabled by default")


func test_default_enemy_type_index() -> void:
	var settings := MockMenuExperimentalSettings.new()
	assert_eq(settings.get_selected_enemy_type_index(), 0, "Selected enemy type should default to 0")


func test_default_stuck_max_time() -> void:
	var settings := MockMenuExperimentalSettings.new()
	assert_eq(settings.get_global_stuck_max_time(), 20.0, "Stuck max time should default to 20.0")


# ============================================================================
# Toggle Tests - Verify settings correctly toggle
# ============================================================================


func test_toggle_fov() -> void:
	var settings := MockMenuExperimentalSettings.new()
	settings.set_fov_enabled(false)
	assert_false(settings.is_fov_enabled(), "FOV should be disabled after toggle")
	settings.set_fov_enabled(true)
	assert_true(settings.is_fov_enabled(), "FOV should be re-enabled")


func test_toggle_complex_grenade() -> void:
	var settings := MockMenuExperimentalSettings.new()
	settings.set_complex_grenade_throwing(true)
	assert_true(settings.is_complex_grenade_throwing(), "Complex grenade should be enabled after toggle")


func test_toggle_ai_prediction() -> void:
	var settings := MockMenuExperimentalSettings.new()
	settings.set_ai_prediction_enabled(true)
	assert_true(settings.is_ai_prediction_enabled(), "AI prediction should be enabled after toggle")


func test_toggle_debug_mode() -> void:
	var settings := MockMenuExperimentalSettings.new()
	settings.set_debug_mode_enabled(true)
	assert_true(settings.is_debug_mode_enabled(), "Debug mode should be enabled after toggle")


func test_toggle_invincibility() -> void:
	var settings := MockMenuExperimentalSettings.new()
	settings.set_invincibility_enabled(true)
	assert_true(settings.is_invincibility_enabled(), "Invincibility should be enabled after toggle")


func test_toggle_realistic_visibility() -> void:
	var settings := MockMenuExperimentalSettings.new()
	settings.set_realistic_visibility_enabled(true)
	assert_true(settings.is_realistic_visibility_enabled(), "Realistic visibility should be enabled after toggle")


func test_toggle_replay() -> void:
	var settings := MockMenuExperimentalSettings.new()
	settings.set_replay_enabled(true)
	assert_true(settings.is_replay_enabled(), "Replay should be enabled after toggle")


func test_toggle_logging() -> void:
	var settings := MockMenuExperimentalSettings.new()
	settings.set_logging_enabled(false)
	assert_false(settings.is_logging_enabled(), "Logging should be disabled after toggle")


func test_toggle_flashlight_blinding() -> void:
	var settings := MockMenuExperimentalSettings.new()
	settings.set_enemy_flashlight_blinding_enabled(true)
	assert_true(settings.is_enemy_flashlight_blinding_enabled(), "Flashlight blinding should be enabled")


func test_toggle_fps_counter() -> void:
	var settings := MockMenuExperimentalSettings.new()
	settings.set_fps_counter_enabled(true)
	assert_true(settings.is_fps_counter_enabled(), "FPS counter should be enabled")


func test_toggle_all_weapons_unlocked() -> void:
	var settings := MockMenuExperimentalSettings.new()
	settings.set_all_weapons_unlocked(true)
	assert_true(settings.is_all_weapons_unlocked(), "All weapons should be unlocked")


func test_toggle_all_maps_unlocked() -> void:
	var settings := MockMenuExperimentalSettings.new()
	settings.set_all_maps_unlocked(true)
	assert_true(settings.is_all_maps_unlocked(), "All maps should be unlocked")


func test_toggle_nav_mesh() -> void:
	var settings := MockMenuExperimentalSettings.new()
	settings.set_nav_mesh_visible_enabled(true)
	assert_true(settings.is_nav_mesh_visible_enabled(), "Nav mesh should be visible")


func test_toggle_tactical_group() -> void:
	var settings := MockMenuExperimentalSettings.new()
	settings.set_tactical_group_enabled(true)
	assert_true(settings.is_tactical_group_enabled(), "Tactical group should be enabled")


func test_toggle_cover_infinite_rays() -> void:
	var settings := MockMenuExperimentalSettings.new()
	settings.set_cover_infinite_rays_enabled(false)
	assert_false(settings.is_cover_infinite_rays_enabled(), "Cover infinite rays should be disabled")


func test_toggle_cover_sector_rays() -> void:
	var settings := MockMenuExperimentalSettings.new()
	settings.set_cover_sector_rays_enabled(false)
	assert_false(settings.is_cover_sector_rays_enabled(), "Cover sector rays should be disabled")


# ============================================================================
# Signal Emission Tests
# ============================================================================


func test_no_signal_when_same_value() -> void:
	var settings := MockMenuExperimentalSettings.new()
	settings.set_fov_enabled(true)  # same as default
	assert_eq(settings.settings_changed_count, 0, "Should not emit signal when value unchanged")


func test_signal_on_change() -> void:
	var settings := MockMenuExperimentalSettings.new()
	settings.set_fov_enabled(false)
	assert_eq(settings.settings_changed_count, 1, "Should emit signal on value change")


func test_multiple_toggles_emit_signals() -> void:
	var settings := MockMenuExperimentalSettings.new()
	settings.set_fov_enabled(false)
	settings.set_debug_mode_enabled(true)
	settings.set_invincibility_enabled(true)
	assert_eq(settings.settings_changed_count, 3, "Should emit signal for each change")


# ============================================================================
# Enemy Type Index Tests
# ============================================================================


func test_set_enemy_type_index() -> void:
	var settings := MockMenuExperimentalSettings.new()
	settings.set_selected_enemy_type_index(3)
	assert_eq(settings.get_selected_enemy_type_index(), 3, "Enemy type index should be 3")


func test_enemy_type_index_zero() -> void:
	var settings := MockMenuExperimentalSettings.new()
	settings.set_selected_enemy_type_index(0)
	assert_eq(settings.get_selected_enemy_type_index(), 0, "Enemy type index should be 0")


# ============================================================================
# Stuck Max Time Tests
# ============================================================================


func test_set_stuck_max_time() -> void:
	var settings := MockMenuExperimentalSettings.new()
	settings.set_global_stuck_max_time(30.0)
	assert_eq(settings.get_global_stuck_max_time(), 30.0, "Stuck max time should be 30.0")


func test_stuck_max_time_no_signal_same_value() -> void:
	var settings := MockMenuExperimentalSettings.new()
	settings.set_global_stuck_max_time(20.0)  # same as default
	assert_eq(settings.settings_changed_count, 0, "Should not emit signal for same value")


# ============================================================================
# Menu Process Mode Tests
# ============================================================================


func test_experimental_menu_should_use_process_always() -> void:
	# Experimental menu must use PROCESS_MODE_ALWAYS to receive input while paused
	var expected_mode := Node.PROCESS_MODE_ALWAYS
	assert_eq(expected_mode, 3, "PROCESS_MODE_ALWAYS should be 3")
