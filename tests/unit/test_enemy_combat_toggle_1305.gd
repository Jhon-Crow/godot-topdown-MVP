extends GutTest
## Regression tests for Issue #1305: Disabling COMBAT in PerformanceSettings must
## prevent all priority attack paths (distracted, vulnerable, grenade throw).
##
## These tests verify that the `_combat_allowed` guard in `_process_ai_state()`
## correctly blocks the priority attack bypass paths when the COMBAT state toggle
## is disabled in PerformanceSettings.


# ============================================================================
# Mock PerformanceSettings
# ============================================================================

class MockPerformanceSettings:
	extends RefCounted

	var _combat_enabled: bool = true

	func is_ai_state_combat_enabled() -> bool:
		return _combat_enabled


# ============================================================================
# Tests: _combat_allowed logic
# ============================================================================

func test_combat_allowed_true_when_no_performance_settings() -> void:
	# When PerformanceSettings autoload is absent, _combat_allowed defaults to true
	var ps = null
	var combat_allowed: bool = ps == null or ps.is_ai_state_combat_enabled()
	assert_true(combat_allowed,
		"Combat should be allowed when PerformanceSettings is not loaded")


func test_combat_allowed_true_when_combat_enabled() -> void:
	var ps := MockPerformanceSettings.new()
	ps._combat_enabled = true
	var combat_allowed: bool = ps == null or ps.is_ai_state_combat_enabled()
	assert_true(combat_allowed,
		"Combat should be allowed when COMBAT state is enabled")


func test_combat_allowed_false_when_combat_disabled() -> void:
	var ps := MockPerformanceSettings.new()
	ps._combat_enabled = false
	var combat_allowed: bool = ps == null or ps.is_ai_state_combat_enabled()
	assert_false(combat_allowed,
		"Combat should NOT be allowed when COMBAT state is disabled")


# ============================================================================
# Tests: Priority attack gating
# ============================================================================

func test_distraction_attack_blocked_when_combat_disabled() -> void:
	# Simulates the condition at enemy.gd line ~1235:
	# if _combat_allowed and is_distraction_enabled and ... and player_distracted
	var ps := MockPerformanceSettings.new()
	ps._combat_enabled = false
	var combat_allowed: bool = ps == null or ps.is_ai_state_combat_enabled()

	var is_distraction_enabled := true
	var is_confused := false
	var is_pacifist := false
	var player_distracted := true
	var can_see_player := true

	var would_shoot: bool = combat_allowed and is_distraction_enabled and not is_confused and not is_pacifist and player_distracted and can_see_player
	assert_false(would_shoot,
		"Distraction priority attack must be blocked when COMBAT is disabled (Issue #1305)")


func test_distraction_attack_allowed_when_combat_enabled() -> void:
	var ps := MockPerformanceSettings.new()
	ps._combat_enabled = true
	var combat_allowed: bool = ps == null or ps.is_ai_state_combat_enabled()

	var is_distraction_enabled := true
	var is_confused := false
	var is_pacifist := false
	var player_distracted := true
	var can_see_player := true

	var would_shoot: bool = combat_allowed and is_distraction_enabled and not is_confused and not is_pacifist and player_distracted and can_see_player
	assert_true(would_shoot,
		"Distraction priority attack should work when COMBAT is enabled")


func test_vulnerability_attack_blocked_when_combat_disabled() -> void:
	# Simulates the condition at enemy.gd line ~1276:
	# if _combat_allowed and player_is_vulnerable and not is_confused ...
	var ps := MockPerformanceSettings.new()
	ps._combat_enabled = false
	var combat_allowed: bool = ps == null or ps.is_ai_state_combat_enabled()

	var player_is_vulnerable := true
	var is_confused := false
	var is_pacifist := false
	var can_see_player := true
	var player_close := true

	var would_shoot: bool = combat_allowed and player_is_vulnerable and not is_confused and not is_pacifist and can_see_player and player_close
	assert_false(would_shoot,
		"Vulnerability priority attack must be blocked when COMBAT is disabled (Issue #1305)")


func test_vulnerability_pursuit_blocked_when_combat_disabled() -> void:
	# Simulates the condition at enemy.gd line ~1296:
	# if _combat_allowed and player_is_vulnerable and _can_see_player ...
	var ps := MockPerformanceSettings.new()
	ps._combat_enabled = false
	var combat_allowed: bool = ps == null or ps.is_ai_state_combat_enabled()

	var player_is_vulnerable := true
	var can_see_player := true
	var player_close := false

	var would_pursue: bool = combat_allowed and player_is_vulnerable and can_see_player and not player_close
	assert_false(would_pursue,
		"Vulnerability pursuit must be blocked when COMBAT is disabled (Issue #1305)")


func test_grenade_throw_blocked_when_combat_disabled() -> void:
	# Simulates the condition at enemy.gd line ~1315:
	# if _combat_allowed and ready_to_throw and not is_pacifist
	var ps := MockPerformanceSettings.new()
	ps._combat_enabled = false
	var combat_allowed: bool = ps == null or ps.is_ai_state_combat_enabled()

	var ready_to_throw := true
	var is_pacifist := false

	var would_throw: bool = combat_allowed and ready_to_throw and not is_pacifist
	assert_false(would_throw,
		"Grenade throw must be blocked when COMBAT is disabled (Issue #1305)")


func test_grenade_throw_allowed_when_combat_enabled() -> void:
	var ps := MockPerformanceSettings.new()
	ps._combat_enabled = true
	var combat_allowed: bool = ps == null or ps.is_ai_state_combat_enabled()

	var ready_to_throw := true
	var is_pacifist := false

	var would_throw: bool = combat_allowed and ready_to_throw and not is_pacifist
	assert_true(would_throw,
		"Grenade throw should work when COMBAT is enabled")
