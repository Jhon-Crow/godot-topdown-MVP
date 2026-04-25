extends GutTest
## Unit tests for ExperimentalSettings.
##
## Tests the experimental features manager that handles FOV toggle
## and settings persistence.


# ============================================================================
# Mock ExperimentalSettings for Logic Tests
# ============================================================================


class MockExperimentalSettings:
	## Whether FOV (Field of View) limitation for enemies is enabled.
	var fov_enabled: bool = false


	## Whether complex grenade throwing is enabled.
	var complex_grenade_throwing: bool = false

	## Whether AI player prediction is enabled (Issue #298).
	var ai_prediction_enabled: bool = false

	## Whether debug mode is enabled (shows debug labels on enemies).
	var debug_mode_enabled: bool = false

	## Whether invincibility mode is enabled (player takes no damage).
	var invincibility_enabled: bool = false

	## Whether realistic visibility mode is enabled (Issue #540).
	var realistic_visibility_enabled: bool = false

	## Whether log recording is enabled (Issue #848).
	var logging_enabled: bool = false

	## Whether enemy flashlight blinding is enabled (Issue #903).
	var enemy_flashlight_blinding_enabled: bool = false

	## Whether replay viewing is enabled (Issue #807).
	var replay_enabled: bool = false

	## Whether all weapons are unlocked (Issue #882).
	var all_weapons_unlocked: bool = false

	## Whether all maps are unlocked (Issue #1075).
	var all_maps_unlocked: bool = false

	## Whether roguelike is unlocked via experimental toggle (Issue #1618).
	var roguelike_unlocked: bool = false

	## Whether search path waypoints overlay is visible (Issue #1251).
	var search_path_visible_enabled: bool = false

	## Signal tracking
	var settings_changed_emitted: int = 0

	## Settings storage (simulates file)
	var _saved_settings: Dictionary = {}

	## Set FOV enabled/disabled.
	func set_fov_enabled(enabled: bool) -> void:
		if fov_enabled != enabled:
			fov_enabled = enabled
			settings_changed_emitted += 1
			_save_settings()

	## Check if FOV limitation is enabled.
	func is_fov_enabled() -> bool:
		return fov_enabled

	## Set complex grenade throwing enabled/disabled.
	func set_complex_grenade_throwing(enabled: bool) -> void:
		if complex_grenade_throwing != enabled:
			complex_grenade_throwing = enabled
			settings_changed_emitted += 1
			_save_settings()

	## Check if complex grenade throwing is enabled.
	func is_complex_grenade_throwing() -> bool:
		return complex_grenade_throwing

	## Set AI prediction enabled/disabled (Issue #298).
	func set_ai_prediction_enabled(enabled: bool) -> void:
		if ai_prediction_enabled != enabled:
			ai_prediction_enabled = enabled
			settings_changed_emitted += 1
			_save_settings()

	## Check if AI prediction is enabled (Issue #298).
	func is_ai_prediction_enabled() -> bool:
		return ai_prediction_enabled

	## Set debug mode enabled/disabled.
	func set_debug_mode_enabled(enabled: bool) -> void:
		if debug_mode_enabled != enabled:
			debug_mode_enabled = enabled
			settings_changed_emitted += 1
			_save_settings()

	## Check if debug mode is enabled.
	func is_debug_mode_enabled() -> bool:
		return debug_mode_enabled

	## Set invincibility mode enabled/disabled.
	func set_invincibility_enabled(enabled: bool) -> void:
		if invincibility_enabled != enabled:
			invincibility_enabled = enabled
			settings_changed_emitted += 1
			_save_settings()

	## Check if invincibility mode is enabled.
	func is_invincibility_enabled() -> bool:
		return invincibility_enabled

	## Set realistic visibility enabled/disabled (Issue #540).
	func set_realistic_visibility_enabled(enabled: bool) -> void:
		if realistic_visibility_enabled != enabled:
			realistic_visibility_enabled = enabled
			settings_changed_emitted += 1
			_save_settings()

	## Check if realistic visibility is enabled (Issue #540).
	func is_realistic_visibility_enabled() -> bool:
		return realistic_visibility_enabled

	## Set replay viewing enabled/disabled (Issue #807).
	func set_replay_enabled(enabled: bool) -> void:
		if replay_enabled != enabled:
			replay_enabled = enabled
			settings_changed_emitted += 1
			_save_settings()

	## Check if replay viewing is enabled (Issue #807).
	func is_replay_enabled() -> bool:
		return replay_enabled

	## Set log recording enabled/disabled (Issue #848).
	func set_logging_enabled(enabled: bool) -> void:
		if logging_enabled != enabled:
			logging_enabled = enabled
			settings_changed_emitted += 1
			_save_settings()

	## Check if log recording is enabled (Issue #848).
	func is_logging_enabled() -> bool:
		return logging_enabled

	## Set enemy flashlight blinding enabled/disabled (Issue #903).
	func set_enemy_flashlight_blinding_enabled(enabled: bool) -> void:
		if enemy_flashlight_blinding_enabled != enabled:
			enemy_flashlight_blinding_enabled = enabled
			settings_changed_emitted += 1
			_save_settings()

	## Check if enemy flashlight blinding is enabled (Issue #903).
	func is_enemy_flashlight_blinding_enabled() -> bool:
		return enemy_flashlight_blinding_enabled

	## Set all weapons unlocked enabled/disabled (Issue #882).
	func set_all_weapons_unlocked(enabled: bool) -> void:
		if all_weapons_unlocked != enabled:
			all_weapons_unlocked = enabled
			settings_changed_emitted += 1
			_save_settings()

	## Check if all weapons unlocked is enabled (Issue #882).
	func is_all_weapons_unlocked() -> bool:
		return all_weapons_unlocked

	## Set all maps unlocked enabled/disabled (Issue #1075).
	func set_all_maps_unlocked(enabled: bool) -> void:
		if all_maps_unlocked != enabled:
			all_maps_unlocked = enabled
			settings_changed_emitted += 1
			_save_settings()

	## Check if all maps unlocked is enabled (Issue #1075).
	func is_all_maps_unlocked() -> bool:
		return all_maps_unlocked

	## Set roguelike unlocked via experimental toggle (Issue #1618).
	func set_roguelike_unlocked(enabled: bool) -> void:
		if roguelike_unlocked != enabled:
			roguelike_unlocked = enabled
			settings_changed_emitted += 1
			_save_settings()

	## Check if roguelike is unlocked via experimental toggle (Issue #1618).
	func is_roguelike_unlocked() -> bool:
		return roguelike_unlocked

	## Set search path waypoints overlay visibility (Issue #1251).
	func set_search_path_visible_enabled(enabled: bool) -> void:
		if search_path_visible_enabled != enabled:
			search_path_visible_enabled = enabled
			settings_changed_emitted += 1
			_save_settings()

	## Check if search path waypoints overlay is visible (Issue #1251).
	func is_search_path_visible_enabled() -> bool:
		return search_path_visible_enabled

	## Save settings (simulated).
	func _save_settings() -> void:
		_saved_settings["fov_enabled"] = fov_enabled
		_saved_settings["complex_grenade_throwing"] = complex_grenade_throwing
		_saved_settings["ai_prediction_enabled"] = ai_prediction_enabled
		_saved_settings["debug_mode_enabled"] = debug_mode_enabled
		_saved_settings["invincibility_enabled"] = invincibility_enabled
		_saved_settings["realistic_visibility_enabled"] = realistic_visibility_enabled
		_saved_settings["replay_enabled"] = replay_enabled
		_saved_settings["logging_enabled"] = logging_enabled
		_saved_settings["enemy_flashlight_blinding_enabled"] = enemy_flashlight_blinding_enabled
		_saved_settings["all_weapons_unlocked"] = all_weapons_unlocked
		_saved_settings["all_maps_unlocked"] = all_maps_unlocked
		_saved_settings["roguelike_unlocked"] = roguelike_unlocked
		_saved_settings["search_path_visible_enabled"] = search_path_visible_enabled

	## Load settings (simulated).
	func _load_settings() -> void:
		if _saved_settings.has("fov_enabled"):
			fov_enabled = _saved_settings["fov_enabled"]
		else:
			fov_enabled = false
		if _saved_settings.has("complex_grenade_throwing"):
			complex_grenade_throwing = _saved_settings["complex_grenade_throwing"]
		else:
			complex_grenade_throwing = false
		if _saved_settings.has("ai_prediction_enabled"):
			ai_prediction_enabled = _saved_settings["ai_prediction_enabled"]
		else:
			ai_prediction_enabled = false
		if _saved_settings.has("debug_mode_enabled"):
			debug_mode_enabled = _saved_settings["debug_mode_enabled"]
		else:
			debug_mode_enabled = false
		if _saved_settings.has("invincibility_enabled"):
			invincibility_enabled = _saved_settings["invincibility_enabled"]
		else:
			invincibility_enabled = false
		if _saved_settings.has("realistic_visibility_enabled"):
			realistic_visibility_enabled = _saved_settings["realistic_visibility_enabled"]
		else:
			realistic_visibility_enabled = false
		if _saved_settings.has("replay_enabled"):
			replay_enabled = _saved_settings["replay_enabled"]
		else:
			replay_enabled = false
		if _saved_settings.has("logging_enabled"):
			logging_enabled = _saved_settings["logging_enabled"]
		else:
			logging_enabled = false
		if _saved_settings.has("enemy_flashlight_blinding_enabled"):
			enemy_flashlight_blinding_enabled = _saved_settings["enemy_flashlight_blinding_enabled"]
		else:
			enemy_flashlight_blinding_enabled = false
		if _saved_settings.has("all_weapons_unlocked"):
			all_weapons_unlocked = _saved_settings["all_weapons_unlocked"]
		else:
			all_weapons_unlocked = false
		if _saved_settings.has("all_maps_unlocked"):
			all_maps_unlocked = _saved_settings["all_maps_unlocked"]
		else:
			all_maps_unlocked = false
		if _saved_settings.has("roguelike_unlocked"):
			roguelike_unlocked = _saved_settings["roguelike_unlocked"]
		else:
			roguelike_unlocked = false
		if _saved_settings.has("search_path_visible_enabled"):
			search_path_visible_enabled = _saved_settings["search_path_visible_enabled"]
		else:
			search_path_visible_enabled = false

	## Reset to defaults.
	func reset_to_defaults() -> void:
		fov_enabled = false
		complex_grenade_throwing = false
		ai_prediction_enabled = false
		debug_mode_enabled = false
		invincibility_enabled = false
		realistic_visibility_enabled = false
		replay_enabled = false
		logging_enabled = false
		enemy_flashlight_blinding_enabled = false
		all_weapons_unlocked = false
		all_maps_unlocked = false
		roguelike_unlocked = false
		search_path_visible_enabled = false
		settings_changed_emitted += 1
		_saved_settings.clear()


var settings: MockExperimentalSettings


func before_each() -> void:
	settings = MockExperimentalSettings.new()


func after_each() -> void:
	settings = null


# ============================================================================
# Initialization Tests
# ============================================================================


func test_default_fov_disabled() -> void:
	assert_false(settings.fov_enabled,
		"FOV should be disabled by default")


func test_is_fov_enabled_returns_false_by_default() -> void:
	assert_false(settings.is_fov_enabled(),
		"is_fov_enabled should return false by default")


func test_no_signals_emitted_on_init() -> void:
	assert_eq(settings.settings_changed_emitted, 0,
		"No signals should be emitted on initialization")


# ============================================================================
# Set FOV Enabled Tests
# ============================================================================


func test_set_fov_enabled_true() -> void:
	settings.set_fov_enabled(true)

	assert_true(settings.fov_enabled,
		"FOV should be enabled after set_fov_enabled(true)")


func test_set_fov_enabled_false() -> void:
	settings.fov_enabled = true
	settings.set_fov_enabled(false)

	assert_false(settings.fov_enabled,
		"FOV should be disabled after set_fov_enabled(false)")


func test_set_fov_enabled_emits_signal() -> void:
	settings.set_fov_enabled(true)

	assert_eq(settings.settings_changed_emitted, 1,
		"Should emit settings_changed signal")


func test_set_fov_enabled_no_signal_if_same_value() -> void:
	settings.fov_enabled = true
	settings.settings_changed_emitted = 0

	settings.set_fov_enabled(true)  # Same value

	assert_eq(settings.settings_changed_emitted, 0,
		"Should not emit signal if value unchanged")


func test_set_fov_enabled_saves_settings() -> void:
	settings.set_fov_enabled(true)

	assert_true(settings._saved_settings.has("fov_enabled"),
		"Settings should be saved")
	assert_true(settings._saved_settings["fov_enabled"],
		"Saved value should match")


# ============================================================================
# Is FOV Enabled Tests
# ============================================================================


func test_is_fov_enabled_after_enable() -> void:
	settings.set_fov_enabled(true)

	assert_true(settings.is_fov_enabled(),
		"is_fov_enabled should return true after enabling")


func test_is_fov_enabled_after_disable() -> void:
	settings.set_fov_enabled(true)
	settings.set_fov_enabled(false)

	assert_false(settings.is_fov_enabled(),
		"is_fov_enabled should return false after disabling")


func test_is_fov_enabled_reflects_property() -> void:
	settings.fov_enabled = true

	assert_true(settings.is_fov_enabled(),
		"is_fov_enabled should reflect fov_enabled property")


# ============================================================================
# Load Settings Tests
# ============================================================================


func test_load_settings_restores_fov_enabled() -> void:
	settings._saved_settings["fov_enabled"] = true
	settings._load_settings()

	assert_true(settings.fov_enabled,
		"Load should restore saved FOV setting")


func test_load_settings_defaults_when_empty() -> void:
	settings.fov_enabled = true
	settings._saved_settings.clear()
	settings._load_settings()

	assert_false(settings.fov_enabled,
		"Load should default to false when no saved settings")


func test_load_settings_preserves_disabled_state() -> void:
	settings._saved_settings["fov_enabled"] = false
	settings._load_settings()

	assert_false(settings.fov_enabled,
		"Load should preserve disabled state")


# ============================================================================
# Save Settings Tests
# ============================================================================


func test_save_settings_stores_enabled() -> void:
	settings.fov_enabled = true
	settings._save_settings()

	assert_eq(settings._saved_settings["fov_enabled"], true,
		"Save should store enabled state")


func test_save_settings_stores_disabled() -> void:
	settings.fov_enabled = false
	settings._save_settings()

	assert_eq(settings._saved_settings["fov_enabled"], false,
		"Save should store disabled state")


func test_save_and_load_roundtrip() -> void:
	settings.set_fov_enabled(true)
	settings.fov_enabled = false  # Change without saving
	settings._load_settings()

	assert_true(settings.fov_enabled,
		"Load should restore last saved state")


# ============================================================================
# Reset Tests
# ============================================================================


func test_reset_to_defaults() -> void:
	settings.fov_enabled = true
	settings.reset_to_defaults()

	assert_false(settings.fov_enabled,
		"Reset should disable FOV")


func test_reset_clears_saved_settings() -> void:
	settings.set_fov_enabled(true)
	settings.reset_to_defaults()

	assert_eq(settings._saved_settings.size(), 0,
		"Reset should clear saved settings")


func test_reset_emits_signal() -> void:
	settings.set_fov_enabled(true)
	settings.settings_changed_emitted = 0
	settings.reset_to_defaults()

	assert_eq(settings.settings_changed_emitted, 1,
		"Reset should emit settings_changed signal")


# ============================================================================
# Toggle Pattern Tests
# ============================================================================


func test_toggle_on_off() -> void:
	settings.set_fov_enabled(true)
	settings.set_fov_enabled(false)

	assert_false(settings.fov_enabled,
		"Toggle off should disable FOV")
	assert_eq(settings.settings_changed_emitted, 2,
		"Two signals should be emitted for on->off")


func test_toggle_off_on() -> void:
	settings.set_fov_enabled(false)  # Already false, no signal
	settings.set_fov_enabled(true)

	assert_true(settings.fov_enabled,
		"Toggle on should enable FOV")


func test_rapid_toggle() -> void:
	for i in range(10):
		settings.set_fov_enabled(true)
		settings.set_fov_enabled(false)

	assert_false(settings.fov_enabled,
		"Should end disabled after even number of toggles")
	assert_eq(settings.settings_changed_emitted, 20,
		"Should emit signal for each change")


# ============================================================================
# Edge Case Tests
# ============================================================================


func test_set_same_value_multiple_times() -> void:
	settings.set_fov_enabled(true)
	settings.set_fov_enabled(true)
	settings.set_fov_enabled(true)

	assert_eq(settings.settings_changed_emitted, 1,
		"Should only emit once for same value")


func test_direct_property_access() -> void:
	settings.fov_enabled = true

	assert_true(settings.is_fov_enabled(),
		"Direct property access should work")
	assert_eq(settings.settings_changed_emitted, 0,
		"Direct access should not emit signal")


func test_settings_persist_across_calls() -> void:
	settings.set_fov_enabled(true)
	var first_check := settings.is_fov_enabled()

	settings.set_fov_enabled(true)  # No change
	var second_check := settings.is_fov_enabled()

	assert_eq(first_check, second_check,
		"Setting should persist")


# ============================================================================
# Integration-like Tests
# ============================================================================


func test_typical_usage_flow() -> void:
	# 1. Initial state - disabled
	assert_false(settings.is_fov_enabled(), "Should start disabled")

	# 2. User enables FOV
	settings.set_fov_enabled(true)
	assert_true(settings.is_fov_enabled(), "Should be enabled")
	assert_eq(settings.settings_changed_emitted, 1, "One signal")

	# 3. Settings saved (happens automatically)
	assert_true(settings._saved_settings["fov_enabled"], "Settings saved")

	# 4. Simulate app restart - load settings
	settings.fov_enabled = false  # Pretend we lost state
	settings._load_settings()
	assert_true(settings.is_fov_enabled(), "Should restore enabled state")

	# 5. User disables FOV
	settings.set_fov_enabled(false)
	assert_false(settings.is_fov_enabled(), "Should be disabled")
	assert_eq(settings.settings_changed_emitted, 2, "Two signals total")


func test_settings_survive_reload() -> void:
	# Enable and save
	settings.set_fov_enabled(true)

	# Create new instance (simulating restart)
	var new_settings := MockExperimentalSettings.new()
	new_settings._saved_settings = settings._saved_settings  # Share storage
	new_settings._load_settings()

	assert_true(new_settings.is_fov_enabled(),
		"Settings should survive reload")


func test_multiple_settings_instances() -> void:
	# This tests that saved settings can be shared
	var settings2 := MockExperimentalSettings.new()

	settings.set_fov_enabled(true)
	settings2._saved_settings = settings._saved_settings
	settings2._load_settings()

	assert_true(settings2.is_fov_enabled(),
		"Second instance should load shared settings")


# ============================================================================
# Complex Grenade Throwing Tests (Issue #398)
# ============================================================================


func test_default_complex_grenade_throwing_disabled() -> void:
	assert_false(settings.complex_grenade_throwing,
		"Complex grenade throwing should be disabled by default")


func test_is_complex_grenade_throwing_returns_false_by_default() -> void:
	assert_false(settings.is_complex_grenade_throwing(),
		"is_complex_grenade_throwing should return false by default")


func test_set_complex_grenade_throwing_true() -> void:
	settings.set_complex_grenade_throwing(true)

	assert_true(settings.complex_grenade_throwing,
		"Complex grenade throwing should be enabled after set_complex_grenade_throwing(true)")


func test_set_complex_grenade_throwing_false() -> void:
	settings.complex_grenade_throwing = true
	settings.set_complex_grenade_throwing(false)

	assert_false(settings.complex_grenade_throwing,
		"Complex grenade throwing should be disabled after set_complex_grenade_throwing(false)")


func test_set_complex_grenade_throwing_emits_signal() -> void:
	settings.set_complex_grenade_throwing(true)

	assert_eq(settings.settings_changed_emitted, 1,
		"Should emit settings_changed signal when changing complex grenade throwing")


func test_set_complex_grenade_throwing_no_signal_if_same_value() -> void:
	settings.complex_grenade_throwing = true
	settings.settings_changed_emitted = 0

	settings.set_complex_grenade_throwing(true)  # Same value

	assert_eq(settings.settings_changed_emitted, 0,
		"Should not emit signal if complex grenade throwing value unchanged")


func test_set_complex_grenade_throwing_saves_settings() -> void:
	settings.set_complex_grenade_throwing(true)

	assert_true(settings._saved_settings.has("complex_grenade_throwing"),
		"Settings should contain complex_grenade_throwing")
	assert_true(settings._saved_settings["complex_grenade_throwing"],
		"Saved value should match")


func test_load_settings_restores_complex_grenade_throwing() -> void:
	settings._saved_settings["complex_grenade_throwing"] = true
	settings._load_settings()

	assert_true(settings.complex_grenade_throwing,
		"Load should restore saved complex grenade throwing setting")


func test_load_settings_complex_grenade_defaults_when_empty() -> void:
	settings.complex_grenade_throwing = true
	settings._saved_settings.clear()
	settings._load_settings()

	assert_false(settings.complex_grenade_throwing,
		"Load should default complex grenade throwing to false when no saved settings")


func test_reset_clears_complex_grenade_throwing() -> void:
	settings.complex_grenade_throwing = true
	settings.reset_to_defaults()

	assert_false(settings.complex_grenade_throwing,
		"Reset should disable complex grenade throwing")


func test_both_settings_independent() -> void:
	# Enable FOV but not complex grenade
	settings.set_fov_enabled(true)
	assert_true(settings.is_fov_enabled(), "FOV should be enabled")
	assert_false(settings.is_complex_grenade_throwing(), "Complex grenade should still be disabled")

	# Enable complex grenade too
	settings.set_complex_grenade_throwing(true)
	assert_true(settings.is_fov_enabled(), "FOV should still be enabled")
	assert_true(settings.is_complex_grenade_throwing(), "Complex grenade should now be enabled")

	# Disable FOV only
	settings.set_fov_enabled(false)
	assert_false(settings.is_fov_enabled(), "FOV should be disabled")
	assert_true(settings.is_complex_grenade_throwing(), "Complex grenade should still be enabled")


func test_save_and_load_both_settings() -> void:
	settings.set_fov_enabled(true)
	settings.set_complex_grenade_throwing(true)

	# Reset in-memory state
	settings.fov_enabled = false
	settings.complex_grenade_throwing = false

	# Load from saved
	settings._load_settings()

	assert_true(settings.is_fov_enabled(), "FOV should be restored")
	assert_true(settings.is_complex_grenade_throwing(), "Complex grenade should be restored")


# ============================================================================
# AI Prediction Setting Tests (Issue #298)
# ============================================================================


func test_default_ai_prediction_disabled() -> void:
	assert_false(settings.ai_prediction_enabled,
		"AI prediction should be disabled by default")


func test_is_ai_prediction_enabled_returns_false_by_default() -> void:
	assert_false(settings.is_ai_prediction_enabled(),
		"is_ai_prediction_enabled should return false by default")


func test_set_ai_prediction_enabled_true() -> void:
	settings.set_ai_prediction_enabled(true)
	assert_true(settings.ai_prediction_enabled,
		"AI prediction should be enabled after set_ai_prediction_enabled(true)")


func test_set_ai_prediction_enabled_false() -> void:
	settings.ai_prediction_enabled = true
	settings.set_ai_prediction_enabled(false)
	assert_false(settings.ai_prediction_enabled,
		"AI prediction should be disabled after set_ai_prediction_enabled(false)")


func test_set_ai_prediction_enabled_emits_signal() -> void:
	settings.set_ai_prediction_enabled(true)
	assert_eq(settings.settings_changed_emitted, 1,
		"Should emit settings_changed signal when toggling AI prediction")


func test_set_ai_prediction_no_signal_if_same() -> void:
	settings.ai_prediction_enabled = true
	settings.settings_changed_emitted = 0
	settings.set_ai_prediction_enabled(true)  # Same value
	assert_eq(settings.settings_changed_emitted, 0,
		"Should not emit signal if AI prediction value unchanged")


func test_set_ai_prediction_saves_settings() -> void:
	settings.set_ai_prediction_enabled(true)
	assert_true(settings._saved_settings.has("ai_prediction_enabled"),
		"AI prediction setting should be saved")
	assert_true(settings._saved_settings["ai_prediction_enabled"],
		"Saved AI prediction value should match")


func test_load_ai_prediction_setting() -> void:
	settings._saved_settings["ai_prediction_enabled"] = true
	settings._load_settings()
	assert_true(settings.ai_prediction_enabled,
		"Load should restore saved AI prediction setting")


func test_load_ai_prediction_defaults_when_empty() -> void:
	settings.ai_prediction_enabled = true
	settings._saved_settings.clear()
	settings._load_settings()
	assert_false(settings.ai_prediction_enabled,
		"Load should default AI prediction to false when no saved settings")


func test_ai_prediction_independent_of_other_settings() -> void:
	settings.set_ai_prediction_enabled(true)
	assert_true(settings.is_ai_prediction_enabled(), "AI prediction should be enabled")
	assert_false(settings.is_fov_enabled(), "FOV should still be disabled")
	assert_false(settings.is_complex_grenade_throwing(), "Grenades should still be disabled")


func test_save_and_load_fov_grenade_prediction() -> void:
	settings.set_fov_enabled(true)
	settings.set_complex_grenade_throwing(true)
	settings.set_ai_prediction_enabled(true)

	# Reset in-memory state
	settings.fov_enabled = false
	settings.complex_grenade_throwing = false
	settings.ai_prediction_enabled = false

	# Load from saved
	settings._load_settings()

	assert_true(settings.is_fov_enabled(), "FOV should be restored")
	assert_true(settings.is_complex_grenade_throwing(), "Complex grenade should be restored")
	assert_true(settings.is_ai_prediction_enabled(), "AI prediction should be restored")


func test_reset_clears_ai_prediction() -> void:
	settings.set_ai_prediction_enabled(true)
	settings.reset_to_defaults()
	assert_false(settings.ai_prediction_enabled,
		"Reset should disable AI prediction")


# ============================================================================
# Realistic Visibility Setting Tests (Issue #540)
# ============================================================================


func test_default_realistic_visibility_disabled() -> void:
	assert_false(settings.realistic_visibility_enabled,
		"Realistic visibility should be disabled by default")


func test_is_realistic_visibility_enabled_returns_false_by_default() -> void:
	assert_false(settings.is_realistic_visibility_enabled(),
		"is_realistic_visibility_enabled should return false by default")


func test_set_realistic_visibility_enabled_true() -> void:
	settings.set_realistic_visibility_enabled(true)
	assert_true(settings.realistic_visibility_enabled,
		"Realistic visibility should be enabled after set_realistic_visibility_enabled(true)")


func test_set_realistic_visibility_enabled_false() -> void:
	settings.realistic_visibility_enabled = true
	settings.set_realistic_visibility_enabled(false)
	assert_false(settings.realistic_visibility_enabled,
		"Realistic visibility should be disabled after set_realistic_visibility_enabled(false)")


func test_set_realistic_visibility_emits_signal() -> void:
	settings.set_realistic_visibility_enabled(true)
	assert_eq(settings.settings_changed_emitted, 1,
		"Should emit settings_changed signal when toggling realistic visibility")


func test_set_realistic_visibility_no_signal_if_same() -> void:
	settings.realistic_visibility_enabled = true
	settings.settings_changed_emitted = 0
	settings.set_realistic_visibility_enabled(true)  # Same value
	assert_eq(settings.settings_changed_emitted, 0,
		"Should not emit signal if realistic visibility value unchanged")


func test_set_realistic_visibility_saves_settings() -> void:
	settings.set_realistic_visibility_enabled(true)
	assert_true(settings._saved_settings.has("realistic_visibility_enabled"),
		"Realistic visibility setting should be saved")
	assert_true(settings._saved_settings["realistic_visibility_enabled"],
		"Saved realistic visibility value should match")


func test_load_realistic_visibility_setting() -> void:
	settings._saved_settings["realistic_visibility_enabled"] = true
	settings._load_settings()
	assert_true(settings.realistic_visibility_enabled,
		"Load should restore saved realistic visibility setting")


func test_load_realistic_visibility_defaults_when_empty() -> void:
	settings.realistic_visibility_enabled = true
	settings._saved_settings.clear()
	settings._load_settings()
	assert_false(settings.realistic_visibility_enabled,
		"Load should default realistic visibility to false when no saved settings")


func test_realistic_visibility_independent_of_other_settings() -> void:
	settings.set_realistic_visibility_enabled(true)
	assert_true(settings.is_realistic_visibility_enabled(), "Realistic visibility should be enabled")
	assert_false(settings.is_fov_enabled(), "FOV should still be disabled")
	assert_false(settings.is_complex_grenade_throwing(), "Grenades should still be disabled")
	assert_false(settings.is_ai_prediction_enabled(), "AI prediction should still be disabled")


func test_save_and_load_all_settings() -> void:
	settings.set_fov_enabled(true)
	settings.set_complex_grenade_throwing(true)
	settings.set_ai_prediction_enabled(true)
	settings.set_debug_mode_enabled(true)
	settings.set_invincibility_enabled(true)
	settings.set_realistic_visibility_enabled(true)
	settings.set_logging_enabled(true)
	settings.set_enemy_flashlight_blinding_enabled(true)

	# Reset in-memory state
	settings.fov_enabled = false
	settings.complex_grenade_throwing = false
	settings.ai_prediction_enabled = false
	settings.debug_mode_enabled = false
	settings.invincibility_enabled = false
	settings.realistic_visibility_enabled = false
	settings.logging_enabled = true
	settings.enemy_flashlight_blinding_enabled = false

	# Load from saved
	settings._load_settings()

	assert_true(settings.is_fov_enabled(), "FOV should be restored")
	assert_true(settings.is_complex_grenade_throwing(), "Complex grenade should be restored")
	assert_true(settings.is_ai_prediction_enabled(), "AI prediction should be restored")
	assert_true(settings.is_debug_mode_enabled(), "Debug mode should be restored")
	assert_true(settings.is_invincibility_enabled(), "Invincibility should be restored")
	assert_true(settings.is_realistic_visibility_enabled(), "Realistic visibility should be restored")
	assert_true(settings.is_logging_enabled(), "Logging should be restored as enabled")
	assert_true(settings.is_enemy_flashlight_blinding_enabled(), "Enemy flashlight blinding should be restored")


func test_reset_clears_realistic_visibility() -> void:
	settings.set_realistic_visibility_enabled(true)
	settings.reset_to_defaults()
	assert_false(settings.realistic_visibility_enabled,
		"Reset should disable realistic visibility")


# ============================================================================
# Log Recording Setting Tests (Issue #848)
# ============================================================================


func test_default_logging_disabled() -> void:
	assert_false(settings.logging_enabled,
		"Log recording should be disabled by default")


func test_is_logging_enabled_returns_false_by_default() -> void:
	assert_false(settings.is_logging_enabled(),
		"is_logging_enabled should return false by default")


func test_set_logging_enabled_false() -> void:
	settings.set_logging_enabled(false)

	assert_false(settings.logging_enabled,
		"Log recording should be disabled after set_logging_enabled(false)")


func test_set_logging_enabled_true() -> void:
	settings.logging_enabled = false
	settings.set_logging_enabled(true)

	assert_true(settings.logging_enabled,
		"Log recording should be enabled after set_logging_enabled(true)")


func test_set_logging_enabled_emits_signal() -> void:
	settings.set_logging_enabled(true)

	assert_eq(settings.settings_changed_emitted, 1,
		"Should emit settings_changed signal when enabling log recording")


func test_set_logging_enabled_no_signal_if_same_value() -> void:
	settings.settings_changed_emitted = 0

	settings.set_logging_enabled(false)  # Same value (default is false)

	assert_eq(settings.settings_changed_emitted, 0,
		"Should not emit signal if logging_enabled value unchanged")


func test_set_logging_enabled_saves_settings() -> void:
	settings.set_logging_enabled(true)

	assert_true(settings._saved_settings.has("logging_enabled"),
		"Settings should contain logging_enabled")
	assert_true(settings._saved_settings["logging_enabled"],
		"Saved value should match enabled state")


func test_load_settings_restores_logging_disabled() -> void:
	settings._saved_settings["logging_enabled"] = false
	settings._load_settings()

	assert_false(settings.logging_enabled,
		"Load should restore saved logging disabled setting")


func test_load_settings_restores_logging_enabled() -> void:
	settings._saved_settings["logging_enabled"] = true
	settings._load_settings()

	assert_true(settings.logging_enabled,
		"Load should restore saved logging enabled setting")


func test_load_settings_logging_defaults_to_false_when_empty() -> void:
	settings.logging_enabled = true
	settings._saved_settings.clear()
	settings._load_settings()

	assert_false(settings.logging_enabled,
		"Load should default logging to false when no saved settings")


func test_reset_restores_logging_disabled() -> void:
	settings.set_logging_enabled(true)
	settings.reset_to_defaults()

	assert_false(settings.logging_enabled,
		"Reset should disable log recording")


func test_logging_independent_of_other_settings() -> void:
	settings.set_logging_enabled(true)
	assert_true(settings.is_logging_enabled(), "Logging should be enabled")
	assert_false(settings.is_fov_enabled(), "FOV should still be disabled")
	assert_false(settings.is_complex_grenade_throwing(), "Grenades should still be disabled")
	assert_false(settings.is_ai_prediction_enabled(), "AI prediction should still be disabled")
	assert_false(settings.is_debug_mode_enabled(), "Debug mode should still be disabled")
	assert_false(settings.is_invincibility_enabled(), "Invincibility should still be disabled")
	assert_false(settings.is_realistic_visibility_enabled(), "Realistic visibility should still be disabled")


func test_save_and_load_logging_enabled() -> void:
	settings.set_logging_enabled(true)

	# Reset in-memory state
	settings.logging_enabled = false

	# Load from saved
	settings._load_settings()

	assert_true(settings.is_logging_enabled(), "Logging enabled state should survive reload")


func test_logging_toggle_on_off() -> void:
	settings.set_logging_enabled(true)
	settings.set_logging_enabled(false)

	assert_false(settings.logging_enabled,
		"Toggle back off should disable logging")
	assert_eq(settings.settings_changed_emitted, 2,
		"Two signals should be emitted for off->on->off")


# ============================================================================
# Enemy Flashlight Blinding Setting Tests (Issue #903)
# ============================================================================


func test_default_enemy_flashlight_blinding_disabled() -> void:
	assert_false(settings.enemy_flashlight_blinding_enabled,
		"Enemy flashlight blinding should be disabled by default")


func test_is_enemy_flashlight_blinding_enabled_returns_false_by_default() -> void:
	assert_false(settings.is_enemy_flashlight_blinding_enabled(),
		"is_enemy_flashlight_blinding_enabled should return false by default")


func test_set_enemy_flashlight_blinding_enabled_true() -> void:
	settings.set_enemy_flashlight_blinding_enabled(true)

	assert_true(settings.enemy_flashlight_blinding_enabled,
		"Enemy flashlight blinding should be enabled after set_enemy_flashlight_blinding_enabled(true)")


func test_set_enemy_flashlight_blinding_enabled_false() -> void:
	settings.enemy_flashlight_blinding_enabled = true
	settings.set_enemy_flashlight_blinding_enabled(false)

	assert_false(settings.enemy_flashlight_blinding_enabled,
		"Enemy flashlight blinding should be disabled after set_enemy_flashlight_blinding_enabled(false)")


func test_set_enemy_flashlight_blinding_emits_signal() -> void:
	settings.set_enemy_flashlight_blinding_enabled(true)

	assert_eq(settings.settings_changed_emitted, 1,
		"Should emit settings_changed signal when enabling enemy flashlight blinding")


func test_set_enemy_flashlight_blinding_no_signal_if_same_value() -> void:
	settings.enemy_flashlight_blinding_enabled = false
	settings.settings_changed_emitted = 0

	settings.set_enemy_flashlight_blinding_enabled(false)  # Same value

	assert_eq(settings.settings_changed_emitted, 0,
		"Should not emit signal if enemy flashlight blinding value unchanged")


func test_set_enemy_flashlight_blinding_saves_settings() -> void:
	settings.set_enemy_flashlight_blinding_enabled(true)

	assert_true(settings._saved_settings.has("enemy_flashlight_blinding_enabled"),
		"Settings should contain enemy_flashlight_blinding_enabled")
	assert_true(settings._saved_settings["enemy_flashlight_blinding_enabled"],
		"Saved value should match enabled state")


func test_load_settings_restores_enemy_flashlight_blinding() -> void:
	settings._saved_settings["enemy_flashlight_blinding_enabled"] = true
	settings._load_settings()

	assert_true(settings.enemy_flashlight_blinding_enabled,
		"Load should restore saved enemy flashlight blinding setting")


func test_load_settings_enemy_flashlight_blinding_defaults_to_false() -> void:
	settings.enemy_flashlight_blinding_enabled = true
	settings._saved_settings.clear()
	settings._load_settings()

	assert_false(settings.enemy_flashlight_blinding_enabled,
		"Load should default enemy flashlight blinding to false when no saved settings")


func test_reset_clears_enemy_flashlight_blinding() -> void:
	settings.set_enemy_flashlight_blinding_enabled(true)
	settings.reset_to_defaults()

	assert_false(settings.enemy_flashlight_blinding_enabled,
		"Reset should disable enemy flashlight blinding")


func test_enemy_flashlight_blinding_independent_of_other_settings() -> void:
	settings.set_enemy_flashlight_blinding_enabled(true)
	assert_true(settings.is_enemy_flashlight_blinding_enabled(), "Enemy flashlight blinding should be enabled")
	assert_false(settings.is_fov_enabled(), "FOV should still be disabled (default)")
	assert_false(settings.is_complex_grenade_throwing(), "Grenades should still be disabled")
	assert_false(settings.is_ai_prediction_enabled(), "AI prediction should still be disabled")
	assert_false(settings.is_debug_mode_enabled(), "Debug mode should still be disabled")
	assert_false(settings.is_invincibility_enabled(), "Invincibility should still be disabled")
	assert_false(settings.is_realistic_visibility_enabled(), "Realistic visibility should still be disabled")


func test_save_and_load_enemy_flashlight_blinding_enabled() -> void:
	settings.set_enemy_flashlight_blinding_enabled(true)

	# Reset in-memory state
	settings.enemy_flashlight_blinding_enabled = false

	# Load from saved
	settings._load_settings()

	assert_true(settings.is_enemy_flashlight_blinding_enabled(),
		"Enemy flashlight blinding enabled state should survive reload")


# ============================================================================
# All Weapons Unlocked Setting Tests (Issue #882)
# ============================================================================


func test_default_all_weapons_unlocked_disabled() -> void:
	assert_false(settings.all_weapons_unlocked,
		"All weapons unlocked should be disabled by default")


func test_is_all_weapons_unlocked_returns_false_by_default() -> void:
	assert_false(settings.is_all_weapons_unlocked(),
		"is_all_weapons_unlocked should return false by default")


func test_set_all_weapons_unlocked_true() -> void:
	settings.set_all_weapons_unlocked(true)

	assert_true(settings.all_weapons_unlocked,
		"All weapons unlocked should be enabled after set_all_weapons_unlocked(true)")


func test_set_all_weapons_unlocked_false() -> void:
	settings.all_weapons_unlocked = true
	settings.set_all_weapons_unlocked(false)

	assert_false(settings.all_weapons_unlocked,
		"All weapons unlocked should be disabled after set_all_weapons_unlocked(false)")


func test_set_all_weapons_unlocked_emits_signal() -> void:
	settings.set_all_weapons_unlocked(true)

	assert_eq(settings.settings_changed_emitted, 1,
		"Should emit settings_changed signal when enabling all weapons unlocked")


func test_set_all_weapons_unlocked_no_signal_if_same_value() -> void:
	settings.all_weapons_unlocked = false
	settings.settings_changed_emitted = 0

	settings.set_all_weapons_unlocked(false)  # Same value

	assert_eq(settings.settings_changed_emitted, 0,
		"Should not emit signal if all weapons unlocked value unchanged")


func test_set_all_weapons_unlocked_saves_settings() -> void:
	settings.set_all_weapons_unlocked(true)

	assert_true(settings._saved_settings.has("all_weapons_unlocked"),
		"Settings should contain all_weapons_unlocked")
	assert_true(settings._saved_settings["all_weapons_unlocked"],
		"Saved value should match enabled state")


func test_load_settings_restores_all_weapons_unlocked() -> void:
	settings._saved_settings["all_weapons_unlocked"] = true
	settings._load_settings()

	assert_true(settings.all_weapons_unlocked,
		"Load should restore saved all weapons unlocked setting")


func test_load_settings_all_weapons_unlocked_defaults_to_false() -> void:
	settings.all_weapons_unlocked = true
	settings._saved_settings.clear()
	settings._load_settings()

	assert_false(settings.all_weapons_unlocked,
		"Load should default all weapons unlocked to false when no saved settings")


func test_reset_clears_all_weapons_unlocked() -> void:
	settings.set_all_weapons_unlocked(true)
	settings.reset_to_defaults()

	assert_false(settings.all_weapons_unlocked,
		"Reset should disable all weapons unlocked")


func test_all_weapons_unlocked_independent_of_other_settings() -> void:
	settings.set_all_weapons_unlocked(true)
	assert_true(settings.is_all_weapons_unlocked(), "All weapons unlocked should be enabled")
	assert_false(settings.is_fov_enabled(), "FOV should still be disabled (default)")
	assert_false(settings.is_complex_grenade_throwing(), "Grenades should still be disabled")
	assert_false(settings.is_ai_prediction_enabled(), "AI prediction should still be disabled")
	assert_false(settings.is_debug_mode_enabled(), "Debug mode should still be disabled")
	assert_false(settings.is_invincibility_enabled(), "Invincibility should still be disabled")
	assert_false(settings.is_realistic_visibility_enabled(), "Realistic visibility should still be disabled")
	assert_false(settings.is_enemy_flashlight_blinding_enabled(), "Enemy flashlight blinding should still be disabled")


func test_save_and_load_all_weapons_unlocked_enabled() -> void:
	settings.set_all_weapons_unlocked(true)

	# Reset in-memory state
	settings.all_weapons_unlocked = false

	# Load from saved
	settings._load_settings()

	assert_true(settings.is_all_weapons_unlocked(),
		"All weapons unlocked enabled state should survive reload")


# ============================================================================
# Replay Viewing Setting Tests (Issue #807, Issue #1051)
# ============================================================================


func test_default_replay_enabled_disabled() -> void:
	assert_false(settings.replay_enabled,
		"Replay viewing should be disabled by default")


func test_is_replay_enabled_returns_false_by_default() -> void:
	assert_false(settings.is_replay_enabled(),
		"is_replay_enabled should return false by default")


func test_set_replay_enabled_true() -> void:
	settings.set_replay_enabled(true)

	assert_true(settings.replay_enabled,
		"Replay viewing should be enabled after set_replay_enabled(true)")


func test_set_replay_enabled_false() -> void:
	settings.replay_enabled = true
	settings.set_replay_enabled(false)

	assert_false(settings.replay_enabled,
		"Replay viewing should be disabled after set_replay_enabled(false)")


func test_set_replay_enabled_emits_signal() -> void:
	settings.set_replay_enabled(true)

	assert_eq(settings.settings_changed_emitted, 1,
		"Should emit settings_changed signal when enabling replay viewing")


func test_set_replay_enabled_no_signal_if_same_value() -> void:
	settings.replay_enabled = false
	settings.settings_changed_emitted = 0

	settings.set_replay_enabled(false)  # Same value

	assert_eq(settings.settings_changed_emitted, 0,
		"Should not emit signal if replay_enabled value unchanged")


func test_set_replay_enabled_saves_settings() -> void:
	settings.set_replay_enabled(true)

	assert_true(settings._saved_settings.has("replay_enabled"),
		"Settings should contain replay_enabled")
	assert_true(settings._saved_settings["replay_enabled"],
		"Saved value should match enabled state")


func test_load_settings_restores_replay_enabled() -> void:
	settings._saved_settings["replay_enabled"] = true
	settings._load_settings()

	assert_true(settings.replay_enabled,
		"Load should restore saved replay viewing setting")


func test_load_settings_replay_defaults_to_false_when_empty() -> void:
	settings.replay_enabled = true
	settings._saved_settings.clear()
	settings._load_settings()

	assert_false(settings.replay_enabled,
		"Load should default replay viewing to false when no saved settings")


func test_reset_clears_replay_enabled() -> void:
	settings.set_replay_enabled(true)
	settings.reset_to_defaults()

	assert_false(settings.replay_enabled,
		"Reset should disable replay viewing")


func test_replay_enabled_independent_of_other_settings() -> void:
	settings.set_replay_enabled(true)
	assert_true(settings.is_replay_enabled(), "Replay viewing should be enabled")
	assert_false(settings.is_fov_enabled(), "FOV should still be disabled (default)")
	assert_false(settings.is_complex_grenade_throwing(), "Grenades should still be disabled")
	assert_false(settings.is_ai_prediction_enabled(), "AI prediction should still be disabled")


func test_save_and_load_replay_enabled() -> void:
	settings.set_replay_enabled(true)

	# Reset in-memory state
	settings.replay_enabled = false

	# Load from saved
	settings._load_settings()

	assert_true(settings.is_replay_enabled(),
		"Replay enabled state should survive reload")


# ============================================================================
# Replay Button Visibility Logic Tests (Issue #1051)
# ============================================================================
# These tests verify the logic used by level scripts to decide whether to show
# the Watch Replay button on the score screen. The button should only appear
# when ExperimentalSettings.is_replay_enabled() returns true.


## Helper that simulates the replay button visibility check used in level scripts.
## Returns true if the replay button should be shown, false otherwise.
## Mirrors: experimental_settings != null and experimental_settings.has_method("is_replay_enabled") and experimental_settings.is_replay_enabled()
func _should_show_replay_button(experimental_settings) -> bool:
	if experimental_settings == null:
		return false
	if not experimental_settings.has_method("is_replay_enabled"):
		return false
	return experimental_settings.is_replay_enabled()


func test_replay_button_hidden_when_replay_disabled() -> void:
	# Default state: replay_enabled = false
	var should_show: bool = _should_show_replay_button(settings)

	assert_false(should_show,
		"Replay button should NOT be shown when replay viewing is disabled (Issue #1051)")


func test_replay_button_shown_when_replay_enabled() -> void:
	settings.set_replay_enabled(true)
	var should_show: bool = _should_show_replay_button(settings)

	assert_true(should_show,
		"Replay button should be shown when replay viewing is enabled")


func test_replay_button_hidden_when_experimental_settings_null() -> void:
	var should_show: bool = _should_show_replay_button(null)

	assert_false(should_show,
		"Replay button should NOT be shown when ExperimentalSettings node is null")


func test_replay_button_hidden_after_disabling_replay() -> void:
	settings.set_replay_enabled(true)
	assert_true(_should_show_replay_button(settings),
		"Replay button should be shown when enabled")

	settings.set_replay_enabled(false)
	assert_false(_should_show_replay_button(settings),
		"Replay button should NOT be shown after disabling replay viewing")


func test_polygon_level_replay_button_hidden_by_default() -> void:
	# Simulates the Polygon (TestTier) level score screen with default settings
	# Issue #1051: replay button was appearing on Polygon even with replay disabled
	var experimental_settings_mock := MockExperimentalSettings.new()
	# Default: replay_enabled = false (as in ExperimentalSettings)
	var should_show: bool = _should_show_replay_button(experimental_settings_mock)

	assert_false(should_show,
		"Polygon level: replay button should NOT appear on score screen by default (Issue #1051)")


func test_city_level_replay_button_hidden_by_default() -> void:
	# Simulates city_level score screen with default settings (Issue #1051)
	var experimental_settings_mock := MockExperimentalSettings.new()
	var should_show: bool = _should_show_replay_button(experimental_settings_mock)

	assert_false(should_show,
		"City level: replay button should NOT appear on score screen by default (Issue #1051)")


func test_docks_level_replay_button_hidden_by_default() -> void:
	# Simulates docks_level score screen with default settings (Issue #1051)
	var experimental_settings_mock := MockExperimentalSettings.new()
	var should_show: bool = _should_show_replay_button(experimental_settings_mock)

	assert_false(should_show,
		"Docks level: replay button should NOT appear on score screen by default (Issue #1051)")


# ============================================================================
# All Maps Unlocked Setting Tests (Issue #1075)
# ============================================================================


func test_default_all_maps_unlocked_disabled() -> void:
	assert_false(settings.all_maps_unlocked,
		"All maps unlocked should be disabled by default")


func test_is_all_maps_unlocked_returns_false_by_default() -> void:
	assert_false(settings.is_all_maps_unlocked(),
		"is_all_maps_unlocked should return false by default")


func test_set_all_maps_unlocked_true() -> void:
	settings.set_all_maps_unlocked(true)

	assert_true(settings.all_maps_unlocked,
		"All maps unlocked should be enabled after set_all_maps_unlocked(true)")


func test_set_all_maps_unlocked_false() -> void:
	settings.all_maps_unlocked = true
	settings.set_all_maps_unlocked(false)

	assert_false(settings.all_maps_unlocked,
		"All maps unlocked should be disabled after set_all_maps_unlocked(false)")


func test_set_all_maps_unlocked_emits_signal() -> void:
	settings.set_all_maps_unlocked(true)

	assert_eq(settings.settings_changed_emitted, 1,
		"Should emit settings_changed signal when enabling all maps unlocked")


func test_set_all_maps_unlocked_no_signal_if_same_value() -> void:
	settings.all_maps_unlocked = false
	settings.settings_changed_emitted = 0

	settings.set_all_maps_unlocked(false)  # Same value

	assert_eq(settings.settings_changed_emitted, 0,
		"Should not emit signal if all maps unlocked value unchanged")


func test_set_all_maps_unlocked_saves_settings() -> void:
	settings.set_all_maps_unlocked(true)

	assert_true(settings._saved_settings.has("all_maps_unlocked"),
		"Settings should contain all_maps_unlocked")
	assert_true(settings._saved_settings["all_maps_unlocked"],
		"Saved value should match enabled state")


func test_load_settings_restores_all_maps_unlocked() -> void:
	settings._saved_settings["all_maps_unlocked"] = true
	settings._load_settings()

	assert_true(settings.all_maps_unlocked,
		"Load should restore saved all maps unlocked setting")


func test_load_settings_all_maps_unlocked_defaults_to_false() -> void:
	settings.all_maps_unlocked = true
	settings._saved_settings.clear()
	settings._load_settings()

	assert_false(settings.all_maps_unlocked,
		"Load should default all maps unlocked to false when no saved settings")


func test_reset_clears_all_maps_unlocked() -> void:
	settings.set_all_maps_unlocked(true)
	settings.reset_to_defaults()

	assert_false(settings.all_maps_unlocked,
		"Reset should disable all maps unlocked")


func test_all_maps_unlocked_independent_of_all_weapons_unlocked() -> void:
	settings.set_all_maps_unlocked(true)
	assert_true(settings.is_all_maps_unlocked(), "All maps unlocked should be enabled")
	assert_false(settings.is_all_weapons_unlocked(), "All weapons unlocked should still be disabled")


func test_save_and_load_all_maps_unlocked_enabled() -> void:
	settings.set_all_maps_unlocked(true)

	# Reset in-memory state
	settings.all_maps_unlocked = false

	# Load from saved
	settings._load_settings()

	assert_true(settings.is_all_maps_unlocked(),
		"All maps unlocked enabled state should survive reload")


# ============================================================================
# Roguelike Unlocked Tests (Issue #1618)
# ============================================================================


func test_default_roguelike_unlocked_is_false() -> void:
	assert_false(settings.roguelike_unlocked,
		"Roguelike unlocked should be false by default")


func test_is_roguelike_unlocked_returns_false_by_default() -> void:
	assert_false(settings.is_roguelike_unlocked(),
		"is_roguelike_unlocked should return false by default")


func test_set_roguelike_unlocked_true() -> void:
	settings.set_roguelike_unlocked(true)

	assert_true(settings.roguelike_unlocked,
		"Roguelike unlocked should be true after set_roguelike_unlocked(true)")


func test_set_roguelike_unlocked_false() -> void:
	settings.roguelike_unlocked = true
	settings.set_roguelike_unlocked(false)

	assert_false(settings.roguelike_unlocked,
		"Roguelike unlocked should be false after set_roguelike_unlocked(false)")


func test_set_roguelike_unlocked_emits_signal() -> void:
	settings.set_roguelike_unlocked(true)

	assert_eq(settings.settings_changed_emitted, 1,
		"Should emit settings_changed signal when roguelike_unlocked changes")


func test_set_roguelike_unlocked_no_signal_if_same_value() -> void:
	settings.set_roguelike_unlocked(false)

	assert_eq(settings.settings_changed_emitted, 0,
		"Should not emit signal when value does not change")


func test_set_roguelike_unlocked_saves_settings() -> void:
	settings.set_roguelike_unlocked(true)

	assert_true(settings._saved_settings.has("roguelike_unlocked"),
		"Settings should contain roguelike_unlocked key after save")
	assert_true(settings._saved_settings["roguelike_unlocked"],
		"Saved roguelike_unlocked should be true")


func test_load_settings_restores_roguelike_unlocked() -> void:
	settings._saved_settings["roguelike_unlocked"] = true

	settings._load_settings()

	assert_true(settings.roguelike_unlocked,
		"Roguelike unlocked should be restored from saved settings")


func test_load_settings_roguelike_unlocked_defaults_to_false() -> void:
	settings.roguelike_unlocked = true

	settings._load_settings()

	assert_false(settings.roguelike_unlocked,
		"Roguelike unlocked should default to false when not in saved settings")


func test_reset_clears_roguelike_unlocked() -> void:
	settings.set_roguelike_unlocked(true)
	settings.reset_to_defaults()

	assert_false(settings.roguelike_unlocked,
		"Reset should set roguelike_unlocked back to false")


func test_roguelike_unlocked_independent_of_all_maps_unlocked() -> void:
	settings.set_roguelike_unlocked(true)
	assert_true(settings.is_roguelike_unlocked(), "Roguelike unlocked should be enabled")
	assert_false(settings.is_all_maps_unlocked(), "All maps unlocked should still be disabled")


func test_save_and_load_roguelike_unlocked_enabled() -> void:
	settings.set_roguelike_unlocked(true)

	# Reset in-memory state
	settings.roguelike_unlocked = false

	# Load from saved
	settings._load_settings()

	assert_true(settings.is_roguelike_unlocked(),
		"Roguelike unlocked enabled state should survive reload")
