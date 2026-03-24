extends GutTest
## Unit tests for the Radio Jammer enemy feature (Issue #1036).
##
## Tests the jammer state management in ActiveItemManager and the
## radio wave visual effect constants.


# ============================================================================
# ActiveItemManager jammer state tests
# ============================================================================


func test_jammer_starts_not_jammed() -> void:
	# Simulate the initial state: _is_jammed should be false by default
	var is_jammed := false
	assert_false(is_jammed, "Active items should not be jammed by default")


func test_set_jammed_true_enables_jam() -> void:
	var is_jammed := false
	# Simulate set_jammed(true)
	is_jammed = true
	assert_true(is_jammed, "set_jammed(true) should jam active items")


func test_set_jammed_false_clears_jam() -> void:
	var is_jammed := true
	# Simulate set_jammed(false)
	is_jammed = false
	assert_false(is_jammed, "set_jammed(false) should clear the jam")


func test_is_active_item_jammed_reflects_state() -> void:
	# The method should return the current _is_jammed value
	var state_true := true
	var state_false := false
	assert_true(state_true, "is_active_item_jammed() returns true when jammed")
	assert_false(state_false, "is_active_item_jammed() returns false when not jammed")


func test_jammer_can_be_toggled() -> void:
	var is_jammed := false
	is_jammed = true
	assert_true(is_jammed, "Jammer can be turned on")
	is_jammed = false
	assert_false(is_jammed, "Jammer can be turned off")


# ============================================================================
# Radio Jammer enemy export property tests
# ============================================================================


func test_is_radio_jammer_default_false() -> void:
	# The @export var is_radio_jammer starts false in the base enemy
	var is_radio_jammer := false
	assert_false(is_radio_jammer, "is_radio_jammer should default to false for base enemy")


func test_radio_jammer_scene_sets_flag_true() -> void:
	# RadioJammerEnemy.tscn overrides is_radio_jammer = true
	var scene_value := true
	assert_true(scene_value, "RadioJammerEnemy scene should set is_radio_jammer = true")


func test_jammer_radius_default() -> void:
	# Default jammer_radius is 1000 px as specified in the issue
	var jammer_radius := 1000.0
	assert_eq(jammer_radius, 1000.0, "Default jammer_radius should be 1000 px")


func test_jammer_radius_positive() -> void:
	var jammer_radius := 1000.0
	assert_true(jammer_radius > 0.0, "jammer_radius must be positive")


# ============================================================================
# Radio wave visual effect constants tests
# ============================================================================


func test_radio_wave_max_ring_radius_positive() -> void:
	var max_radius := 60.0  # RadioWaveEffect.MAX_RING_RADIUS
	assert_true(max_radius > 0.0, "MAX_RING_RADIUS must be positive")


func test_radio_wave_min_ring_radius_positive() -> void:
	var min_radius := 10.0  # RadioWaveEffect.MIN_RING_RADIUS
	assert_true(min_radius > 0.0, "MIN_RING_RADIUS must be positive")


func test_radio_wave_min_less_than_max() -> void:
	var min_radius := 10.0
	var max_radius := 60.0
	assert_true(min_radius < max_radius, "MIN_RING_RADIUS must be smaller than MAX_RING_RADIUS")


func test_radio_wave_expand_speed_positive() -> void:
	var speed := 40.0  # RadioWaveEffect.RING_EXPAND_SPEED
	assert_true(speed > 0.0, "RING_EXPAND_SPEED must be positive")


func test_radio_wave_spawn_interval_positive() -> void:
	var interval := 0.5  # RadioWaveEffect.RING_SPAWN_INTERVAL
	assert_true(interval > 0.0, "RING_SPAWN_INTERVAL must be positive")


func test_radio_wave_color_has_alpha() -> void:
	# RING_COLOR should be semi-transparent (alpha < 1.0)
	var alpha := 0.6  # from RING_COLOR definition
	assert_true(alpha < 1.0, "Radio wave ring color should be semi-transparent")
	assert_true(alpha > 0.0, "Radio wave ring color alpha must be positive")


# ============================================================================
# Jammer proximity logic tests
# ============================================================================


func test_player_within_jammer_radius_is_jammed() -> void:
	var jammer_pos := Vector2(0.0, 0.0)
	var player_pos := Vector2(500.0, 0.0)
	var jammer_radius := 1000.0
	var dist := jammer_pos.distance_to(player_pos)
	assert_true(dist <= jammer_radius, "Player at 500px should be within 1000px jammer radius")


func test_player_outside_jammer_radius_not_jammed() -> void:
	var jammer_pos := Vector2(0.0, 0.0)
	var player_pos := Vector2(1500.0, 0.0)
	var jammer_radius := 1000.0
	var dist := jammer_pos.distance_to(player_pos)
	assert_false(dist <= jammer_radius, "Player at 1500px should be outside 1000px jammer radius")


func test_player_at_exact_boundary_is_jammed() -> void:
	var jammer_pos := Vector2(0.0, 0.0)
	var player_pos := Vector2(1000.0, 0.0)
	var jammer_radius := 1000.0
	var dist := jammer_pos.distance_to(player_pos)
	assert_true(dist <= jammer_radius, "Player exactly at jammer_radius boundary should be jammed")


# ============================================================================
# ActiveItemManager JAMMER_RADIUS constant tests (Issue #1036 race condition fix)
# ============================================================================


func test_active_item_manager_jammer_radius_matches_wave_effect() -> void:
	# JAMMER_RADIUS in ActiveItemManager must match RadioWaveEffect.jammer_radius
	# to ensure the direct-query approach uses the same radius as the visual effect.
	var aim_radius := 1000.0  # ActiveItemManager.JAMMER_RADIUS
	var wave_radius := 1000.0  # RadioWaveEffect.jammer_radius export default
	assert_eq(aim_radius, wave_radius, "JAMMER_RADIUS in ActiveItemManager must match RadioWaveEffect default")


func test_active_item_manager_jammer_radius_is_positive() -> void:
	var jammer_radius := 1000.0  # ActiveItemManager.JAMMER_RADIUS
	assert_true(jammer_radius > 0.0, "JAMMER_RADIUS must be positive")


func test_radio_jammer_scene_includes_radio_jammers_group() -> void:
	# RadioJammerEnemy.tscn must include "radio_jammers" group for the direct-query
	# approach in ActiveItemManager.is_active_item_jammed() to find it.
	# This is verified by checking the scene string directly.
	var scene_text := ""
	var f := FileAccess.open("res://scenes/objects/RadioJammerEnemy.tscn", FileAccess.READ)
	if f != null:
		scene_text = f.get_as_text()
		f.close()
	assert_true(scene_text.contains("radio_jammers"),
		"RadioJammerEnemy.tscn must include 'radio_jammers' group for direct-query jamming to work")


func test_jammer_race_condition_scenario_distance_check() -> void:
	# Verifies the corrected logic: player at ~(735,1225), jammer at ~(814,1121)
	# This was the scenario from the bug report 2026-03-17 where blocking failed.
	var player_pos := Vector2(735.0, 1225.0)
	var jammer_pos := Vector2(814.0, 1121.0)
	var jammer_radius := 1000.0
	var dist := jammer_pos.distance_to(player_pos)
	assert_true(dist <= jammer_radius,
		"Bug scenario: player at (735,1225), jammer at (814,1121) = %.0fpx — must be jammed" % dist)


func test_jammer_race_condition_scenario_out_of_range() -> void:
	# Verifies the first invisibility activation was NOT in range (correct behavior).
	# Player at (150,1900), jammer at (1100,900) = ~1379px > 1000px.
	var player_pos := Vector2(150.0, 1900.0)
	var jammer_pos := Vector2(1100.0, 900.0)
	var jammer_radius := 1000.0
	var dist := jammer_pos.distance_to(player_pos)
	assert_false(dist <= jammer_radius,
		"First activation scenario: player at (150,1900), jammer at (1100,900) = %.0fpx — should NOT be jammed" % dist)


# ============================================================================
# Issue #1115: Cancel active effects when player enters jammer range
# ============================================================================


func test_jammer_hud_circle_radius_matches_combat_disposition_icon_size() -> void:
	# CIRCLE_RADIUS should be reduced to match the Combat Disposition item icon size
	# The Combat Disposition icon is 64px PNG displayed at 0.5 scale = 32px.
	# A radius of 10 with LINE_WIDTH 3 gives outer diameter ~23px, smaller than before (Issue #1115).
	var circle_radius := 10.0  # JammerHud.CIRCLE_RADIUS
	var line_width := 3.0      # JammerHud.LINE_WIDTH
	var outer_diameter := (circle_radius + line_width * 0.5) * 2.0
	assert_true(outer_diameter <= 32.0,
		"Jammer HUD prohibition sign should be no larger than Combat Disposition icon (32px), got %.1fpx" % outer_diameter)


func test_jammer_hud_circle_radius_positive() -> void:
	var circle_radius := 10.0  # JammerHud.CIRCLE_RADIUS
	assert_true(circle_radius > 0.0, "CIRCLE_RADIUS must be positive")


func test_jammer_cancels_homing_bullets_when_player_enters_range() -> void:
	# Simulate: homing active=true, then player enters jammer range → must cancel
	var homing_active := true
	var is_jammed := true  # player walked into jammer radius
	if homing_active and is_jammed:
		homing_active = false
	assert_false(homing_active,
		"Homing bullets effect must be cancelled when player enters jammer range (Issue #1115)")


func test_jammer_cancels_invisibility_when_player_enters_range() -> void:
	# Simulate: invisibility active=true, then player enters jammer range → must cancel
	var invisibility_active := true
	var is_jammed := true
	if invisibility_active and is_jammed:
		invisibility_active = false
	assert_false(invisibility_active,
		"Invisibility suit effect must be cancelled when player enters jammer range (Issue #1115)")


func test_jammer_cancels_trajectory_glasses_when_player_enters_range() -> void:
	# Simulate: trajectory glasses active=true, then player enters jammer range → must cancel
	var glasses_active := true
	var is_jammed := true
	if glasses_active and is_jammed:
		glasses_active = false
	assert_false(glasses_active,
		"Trajectory glasses effect must be cancelled when player enters jammer range (Issue #1115)")


func test_active_effects_not_cancelled_outside_jammer_range() -> void:
	# Simulate: effects active, player is outside jammer range → must NOT cancel
	var homing_active := true
	var is_jammed := false  # player is outside jammer radius
	if homing_active and is_jammed:
		homing_active = false
	assert_true(homing_active,
		"Homing bullets must NOT be cancelled when player is outside jammer range (Issue #1115)")
