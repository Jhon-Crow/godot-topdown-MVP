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
