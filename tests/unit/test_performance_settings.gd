extends GutTest
## Unit tests for PerformanceSettings autoload.
##
## Tests the performance toggles, setter/getter pairs, signal emission,
## and AI state filtering logic.


# ============================================================================
# Mock PerformanceSettings
# ============================================================================


class MockPerformanceSettings:
	## Signal emitted when any performance setting changes.
	signal settings_changed

	## Performance toggle defaults (all enabled).
	var particles_enabled: bool = true
	var blood_decals_enabled: bool = true
	var screen_shake_enabled: bool = true
	var explosion_lights_enabled: bool = true
	var ai_enabled: bool = true

	## Per-state AI toggles (all enabled by default).
	var ai_state_idle_enabled: bool = true
	var ai_state_combat_enabled: bool = true
	var ai_state_seeking_cover_enabled: bool = true
	var ai_state_in_cover_enabled: bool = true
	var ai_state_flanking_enabled: bool = true
	var ai_state_suppressed_enabled: bool = true
	var ai_state_retreating_enabled: bool = true
	var ai_state_pursuing_enabled: bool = true
	var ai_state_assault_enabled: bool = true
	var ai_state_searching_enabled: bool = true

	func set_particles_enabled(enabled: bool) -> void:
		if particles_enabled != enabled:
			particles_enabled = enabled
			settings_changed.emit()

	func is_particles_enabled() -> bool:
		return particles_enabled

	func set_blood_decals_enabled(enabled: bool) -> void:
		if blood_decals_enabled != enabled:
			blood_decals_enabled = enabled
			settings_changed.emit()

	func is_blood_decals_enabled() -> bool:
		return blood_decals_enabled

	func set_screen_shake_enabled(enabled: bool) -> void:
		if screen_shake_enabled != enabled:
			screen_shake_enabled = enabled
			settings_changed.emit()

	func is_screen_shake_enabled() -> bool:
		return screen_shake_enabled

	func set_explosion_lights_enabled(enabled: bool) -> void:
		if explosion_lights_enabled != enabled:
			explosion_lights_enabled = enabled
			settings_changed.emit()

	func is_explosion_lights_enabled() -> bool:
		return explosion_lights_enabled

	func set_ai_enabled(enabled: bool) -> void:
		if ai_enabled != enabled:
			ai_enabled = enabled
			settings_changed.emit()

	func is_ai_enabled() -> bool:
		return ai_enabled

	## Filter AI state - redirects disabled states.
	## IDLE disabled -> SEARCHING (keeps enemies busy); other states disabled -> IDLE.
	func filter_ai_state(state: int) -> int:
		match state:
			0: if not ai_state_idle_enabled: return 9          # IDLE -> SEARCHING
			1: if not ai_state_combat_enabled: return 0        # COMBAT -> IDLE
			2: if not ai_state_seeking_cover_enabled: return 0 # SEEKING_COVER -> IDLE
			3: if not ai_state_in_cover_enabled: return 0      # IN_COVER -> IDLE
			4: if not ai_state_flanking_enabled: return 0      # FLANKING -> IDLE
			5: if not ai_state_suppressed_enabled: return 0    # SUPPRESSED -> IDLE
			6: if not ai_state_retreating_enabled: return 0    # RETREATING -> IDLE
			7: if not ai_state_pursuing_enabled: return 0      # PURSUING -> IDLE
			8: if not ai_state_assault_enabled: return 0       # ASSAULT -> IDLE
			9: if not ai_state_searching_enabled: return 0     # SEARCHING -> IDLE
		return state


var settings: MockPerformanceSettings


func before_each() -> void:
	settings = MockPerformanceSettings.new()


func after_each() -> void:
	settings = null


# ============================================================================
# Default Value Tests
# ============================================================================


func test_default_particles_enabled() -> void:
	assert_true(settings.is_particles_enabled(),
		"Particles should be enabled by default")


func test_default_blood_decals_enabled() -> void:
	assert_true(settings.is_blood_decals_enabled(),
		"Blood decals should be enabled by default")


func test_default_screen_shake_enabled() -> void:
	assert_true(settings.is_screen_shake_enabled(),
		"Screen shake should be enabled by default")


func test_default_explosion_lights_enabled() -> void:
	assert_true(settings.is_explosion_lights_enabled(),
		"Explosion lights should be enabled by default")


func test_default_ai_enabled() -> void:
	assert_true(settings.is_ai_enabled(),
		"AI should be enabled by default")


func test_default_ai_state_toggles_all_enabled() -> void:
	assert_true(settings.ai_state_idle_enabled, "IDLE state should be enabled by default")
	assert_true(settings.ai_state_combat_enabled, "COMBAT state should be enabled by default")
	assert_true(settings.ai_state_seeking_cover_enabled, "SEEKING_COVER state should be enabled by default")
	assert_true(settings.ai_state_in_cover_enabled, "IN_COVER state should be enabled by default")
	assert_true(settings.ai_state_flanking_enabled, "FLANKING state should be enabled by default")
	assert_true(settings.ai_state_suppressed_enabled, "SUPPRESSED state should be enabled by default")
	assert_true(settings.ai_state_retreating_enabled, "RETREATING state should be enabled by default")
	assert_true(settings.ai_state_pursuing_enabled, "PURSUING state should be enabled by default")
	assert_true(settings.ai_state_assault_enabled, "ASSAULT state should be enabled by default")
	assert_true(settings.ai_state_searching_enabled, "SEARCHING state should be enabled by default")


# ============================================================================
# Setter/Getter Tests
# ============================================================================


func test_set_particles_disabled() -> void:
	settings.set_particles_enabled(false)
	assert_false(settings.is_particles_enabled(), "Particles should be disabled after setter")


func test_set_blood_decals_disabled() -> void:
	settings.set_blood_decals_enabled(false)
	assert_false(settings.is_blood_decals_enabled(), "Blood decals should be disabled after setter")


func test_set_screen_shake_disabled() -> void:
	settings.set_screen_shake_enabled(false)
	assert_false(settings.is_screen_shake_enabled(), "Screen shake should be disabled after setter")


func test_set_explosion_lights_disabled() -> void:
	settings.set_explosion_lights_enabled(false)
	assert_false(settings.is_explosion_lights_enabled(), "Explosion lights should be disabled after setter")


func test_set_ai_disabled() -> void:
	settings.set_ai_enabled(false)
	assert_false(settings.is_ai_enabled(), "AI should be disabled after setter")


func test_re_enable_particles() -> void:
	settings.set_particles_enabled(false)
	settings.set_particles_enabled(true)
	assert_true(settings.is_particles_enabled(), "Particles should be re-enabled")


# ============================================================================
# Signal Emission Tests
# ============================================================================


func test_signal_emitted_on_particles_change() -> void:
	var signal_count := 0
	settings.settings_changed.connect(func(): signal_count += 1)

	settings.set_particles_enabled(false)

	assert_eq(signal_count, 1, "Signal should be emitted when particles setting changes")


func test_signal_emitted_on_blood_decals_change() -> void:
	var signal_count := 0
	settings.settings_changed.connect(func(): signal_count += 1)

	settings.set_blood_decals_enabled(false)

	assert_eq(signal_count, 1, "Signal should be emitted when blood decals setting changes")


func test_signal_emitted_on_ai_change() -> void:
	var signal_count := 0
	settings.settings_changed.connect(func(): signal_count += 1)

	settings.set_ai_enabled(false)

	assert_eq(signal_count, 1, "Signal should be emitted when AI setting changes")


func test_no_signal_when_same_value_particles() -> void:
	var signal_count := 0
	settings.settings_changed.connect(func(): signal_count += 1)

	settings.set_particles_enabled(true)  # same as default

	assert_eq(signal_count, 0,
		"Signal should not be emitted when setting same value")


func test_no_signal_when_same_value_ai() -> void:
	var signal_count := 0
	settings.settings_changed.connect(func(): signal_count += 1)

	settings.set_ai_enabled(true)  # same as default

	assert_eq(signal_count, 0,
		"Signal should not be emitted when setting same AI value")


func test_multiple_changes_emit_multiple_signals() -> void:
	var signal_count := 0
	settings.settings_changed.connect(func(): signal_count += 1)

	settings.set_particles_enabled(false)
	settings.set_blood_decals_enabled(false)
	settings.set_screen_shake_enabled(false)

	assert_eq(signal_count, 3,
		"Each setting change should emit one signal")


# ============================================================================
# filter_ai_state() Tests
# ============================================================================


func test_filter_ai_state_all_enabled_returns_same() -> void:
	for state in range(10):
		assert_eq(settings.filter_ai_state(state), state,
			"filter_ai_state(%d) should return %d when all enabled" % [state, state])


func test_filter_idle_disabled_redirects_to_searching() -> void:
	settings.ai_state_idle_enabled = false

	assert_eq(settings.filter_ai_state(0), 9,
		"Disabled IDLE (0) should redirect to SEARCHING (9)")


func test_filter_combat_disabled_redirects_to_idle() -> void:
	settings.ai_state_combat_enabled = false

	assert_eq(settings.filter_ai_state(1), 0,
		"Disabled COMBAT (1) should redirect to IDLE (0)")


func test_filter_seeking_cover_disabled_redirects_to_idle() -> void:
	settings.ai_state_seeking_cover_enabled = false

	assert_eq(settings.filter_ai_state(2), 0,
		"Disabled SEEKING_COVER (2) should redirect to IDLE (0)")


func test_filter_in_cover_disabled_redirects_to_idle() -> void:
	settings.ai_state_in_cover_enabled = false

	assert_eq(settings.filter_ai_state(3), 0,
		"Disabled IN_COVER (3) should redirect to IDLE (0)")


func test_filter_flanking_disabled_redirects_to_idle() -> void:
	settings.ai_state_flanking_enabled = false

	assert_eq(settings.filter_ai_state(4), 0,
		"Disabled FLANKING (4) should redirect to IDLE (0)")


func test_filter_suppressed_disabled_redirects_to_idle() -> void:
	settings.ai_state_suppressed_enabled = false

	assert_eq(settings.filter_ai_state(5), 0,
		"Disabled SUPPRESSED (5) should redirect to IDLE (0)")


func test_filter_retreating_disabled_redirects_to_idle() -> void:
	settings.ai_state_retreating_enabled = false

	assert_eq(settings.filter_ai_state(6), 0,
		"Disabled RETREATING (6) should redirect to IDLE (0)")


func test_filter_pursuing_disabled_redirects_to_idle() -> void:
	settings.ai_state_pursuing_enabled = false

	assert_eq(settings.filter_ai_state(7), 0,
		"Disabled PURSUING (7) should redirect to IDLE (0)")


func test_filter_assault_disabled_redirects_to_idle() -> void:
	settings.ai_state_assault_enabled = false

	assert_eq(settings.filter_ai_state(8), 0,
		"Disabled ASSAULT (8) should redirect to IDLE (0)")


func test_filter_searching_disabled_redirects_to_idle() -> void:
	settings.ai_state_searching_enabled = false

	assert_eq(settings.filter_ai_state(9), 0,
		"Disabled SEARCHING (9) should redirect to IDLE (0)")


func test_filter_unknown_state_returns_same() -> void:
	assert_eq(settings.filter_ai_state(99), 99,
		"Unknown state should pass through unchanged")
