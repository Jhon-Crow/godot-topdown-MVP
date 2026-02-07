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

	## Save settings (simulated).
	func _save_settings() -> void:
		_saved_settings["fov_enabled"] = fov_enabled
		_saved_settings["complex_grenade_throwing"] = complex_grenade_throwing
		_saved_settings["ai_prediction_enabled"] = ai_prediction_enabled

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

	## Reset to defaults.
	func reset_to_defaults() -> void:
		fov_enabled = false
		complex_grenade_throwing = false
		ai_prediction_enabled = false
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


func test_save_and_load_all_three_settings() -> void:
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
