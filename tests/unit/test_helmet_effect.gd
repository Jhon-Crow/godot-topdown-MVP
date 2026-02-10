extends GutTest
## Unit tests for AI Helmet effect (Issue #671).
##
## Tests the helmet prediction system including activation, charges,
## duration timer, ghost position calculation, and deactivation.


# ============================================================================
# Mock Classes for Testing
# ============================================================================


class MockHelmetEffect:
	## Duration of the prediction effect in seconds.
	const EFFECT_DURATION: float = 10.0

	## Number of charges available per battle.
	const MAX_CHARGES: int = 2

	## Time ahead to predict enemy positions (seconds).
	const PREDICTION_TIME: float = 1.0

	## Ghost outline color (bright red, higher alpha for visibility).
	const GHOST_COLOR: Color = Color(1.0, 0.1, 0.1, 0.8)

	## Ghost outline radius (larger for visibility ~32px).
	const GHOST_RADIUS: float = 32.0

	## Ghost circle line width.
	const GHOST_LINE_WIDTH: float = 4.0

	## Ghost fill color (semi-transparent red).
	const GHOST_FILL_COLOR: Color = Color(1.0, 0.1, 0.1, 0.25)

	## Remaining charges.
	var _charges: int = MAX_CHARGES

	## Whether the effect is currently active.
	var _is_active: bool = false

	## Time remaining for current activation.
	var _remaining_time: float = 0.0

	## Cached ghost data.
	var _ghost_data: Array = []

	## Signal tracking.
	var activation_count: int = 0
	var deactivation_count: int = 0
	var last_charges_emitted: int = -1

	## Activate the helmet prediction effect.
	func activate() -> bool:
		if _is_active:
			return false

		if _charges <= 0:
			return false

		_charges -= 1
		_is_active = true
		_remaining_time = EFFECT_DURATION
		activation_count += 1
		last_charges_emitted = _charges
		return true

	## Deactivate the helmet prediction effect.
	func deactivate() -> void:
		if not _is_active:
			return
		_is_active = false
		_remaining_time = 0.0
		_ghost_data.clear()
		deactivation_count += 1

	## Check if effect is active.
	func is_active() -> bool:
		return _is_active

	## Get remaining charges.
	func get_charges() -> int:
		return _charges

	## Get remaining effect time.
	func get_remaining_time() -> float:
		return _remaining_time

	## Simulate a physics frame update.
	func simulate_physics(delta: float) -> void:
		if not _is_active:
			return

		_remaining_time -= delta
		if _remaining_time <= 0.0:
			deactivate()
			return

	## Calculate predicted position for an enemy.
	func predict_position(current_pos: Vector2, velocity: Vector2) -> Vector2:
		return current_pos + velocity * PREDICTION_TIME


class MockEnemy:
	## Enemy position.
	var global_position: Vector2 = Vector2.ZERO

	## Enemy velocity (CharacterBody2D property).
	var velocity: Vector2 = Vector2.ZERO

	## Whether the enemy is alive.
	var _is_alive: bool = true

	func is_alive() -> bool:
		return _is_alive


class MockActiveItemManagerWithHelmet:
	## Active item types.
	const ActiveItemType := {
		NONE = 0,
		FLASHLIGHT = 1,
		AI_HELMET = 2
	}

	## Currently selected active item type.
	var current_active_item: int = ActiveItemType.NONE

	## Active item data.
	const ACTIVE_ITEM_DATA: Dictionary = {
		0: {
			"name": "None",
			"icon_path": "",
			"description": "No active item equipped."
		},
		1: {
			"name": "Flashlight",
			"icon_path": "res://assets/sprites/weapons/flashlight_icon.png",
			"description": "Tactical flashlight — hold Space to illuminate in weapon direction. Bright white light, turns off when released."
		},
		2: {
			"name": "AI Helmet",
			"icon_path": "res://assets/sprites/weapons/ai_helmet_icon.png",
			"description": "AI-powered helmet — press Space to predict enemy positions 1 second ahead. Red ghost outlines appear for 10 seconds. 2 charges per battle."
		}
	}

	## Signal tracking.
	var type_changed_count: int = 0
	var last_restart_called: bool = false

	func set_active_item(type: int, restart_level: bool = true) -> void:
		if type == current_active_item:
			return
		if type not in ACTIVE_ITEM_DATA:
			return
		current_active_item = type
		type_changed_count += 1
		if restart_level:
			last_restart_called = true

	func get_active_item_data(type: int) -> Dictionary:
		if type in ACTIVE_ITEM_DATA:
			return ACTIVE_ITEM_DATA[type]
		return {}

	func get_all_active_item_types() -> Array:
		return ACTIVE_ITEM_DATA.keys()

	func get_active_item_name(type: int) -> String:
		if type in ACTIVE_ITEM_DATA:
			return ACTIVE_ITEM_DATA[type]["name"]
		return "Unknown"

	func get_active_item_description(type: int) -> String:
		if type in ACTIVE_ITEM_DATA:
			return ACTIVE_ITEM_DATA[type]["description"]
		return ""

	func get_active_item_icon_path(type: int) -> String:
		if type in ACTIVE_ITEM_DATA:
			return ACTIVE_ITEM_DATA[type]["icon_path"]
		return ""

	func is_selected(type: int) -> bool:
		return type == current_active_item

	func has_flashlight() -> bool:
		return current_active_item == ActiveItemType.FLASHLIGHT

	func has_ai_helmet() -> bool:
		return current_active_item == ActiveItemType.AI_HELMET


var helmet: MockHelmetEffect
var manager: MockActiveItemManagerWithHelmet


func before_each() -> void:
	helmet = MockHelmetEffect.new()
	manager = MockActiveItemManagerWithHelmet.new()


func after_each() -> void:
	helmet = null
	manager = null


# ============================================================================
# Constants Tests
# ============================================================================


func test_effect_duration_is_10_seconds() -> void:
	assert_eq(helmet.EFFECT_DURATION, 10.0,
		"Effect duration should be 10 seconds")


func test_max_charges_is_2() -> void:
	assert_eq(helmet.MAX_CHARGES, 2,
		"Maximum charges should be 2 per battle")


func test_prediction_time_is_1_second() -> void:
	assert_eq(helmet.PREDICTION_TIME, 1.0,
		"Prediction time should be 1 second ahead")


func test_ghost_color_is_red() -> void:
	assert_gt(helmet.GHOST_COLOR.r, 0.8,
		"Ghost color should have high red channel")
	assert_lt(helmet.GHOST_COLOR.g, 0.3,
		"Ghost color should have low green channel")
	assert_lt(helmet.GHOST_COLOR.b, 0.3,
		"Ghost color should have low blue channel")


func test_ghost_color_is_semi_transparent() -> void:
	assert_gt(helmet.GHOST_COLOR.a, 0.0,
		"Ghost color alpha should be greater than 0")
	assert_lt(helmet.GHOST_COLOR.a, 1.0,
		"Ghost color alpha should be less than 1 (semi-transparent)")


func test_ghost_radius_is_visible() -> void:
	assert_eq(helmet.GHOST_RADIUS, 32.0,
		"Ghost radius should be 32px for visibility")


# ============================================================================
# Initial State Tests
# ============================================================================


func test_starts_inactive() -> void:
	assert_false(helmet.is_active(),
		"Helmet should start inactive")


func test_starts_with_max_charges() -> void:
	assert_eq(helmet.get_charges(), 2,
		"Helmet should start with 2 charges")


func test_starts_with_zero_remaining_time() -> void:
	assert_eq(helmet.get_remaining_time(), 0.0,
		"Remaining time should be 0 when inactive")


func test_starts_with_empty_ghost_data() -> void:
	assert_true(helmet._ghost_data.is_empty(),
		"Ghost data should be empty initially")


# ============================================================================
# Activation Tests
# ============================================================================


func test_activate_succeeds_with_charges() -> void:
	var result := helmet.activate()
	assert_true(result, "Activation should succeed with charges")


func test_activate_sets_active() -> void:
	helmet.activate()
	assert_true(helmet.is_active(),
		"Helmet should be active after activation")


func test_activate_sets_remaining_time() -> void:
	helmet.activate()
	assert_eq(helmet.get_remaining_time(), 10.0,
		"Remaining time should be set to EFFECT_DURATION")


func test_activate_decrements_charges() -> void:
	helmet.activate()
	assert_eq(helmet.get_charges(), 1,
		"Charges should decrease by 1 after activation")


func test_activate_emits_signal() -> void:
	helmet.activate()
	assert_eq(helmet.activation_count, 1,
		"Activation count should be 1")
	assert_eq(helmet.last_charges_emitted, 1,
		"Signal should emit remaining charges count (1)")


func test_activate_fails_when_already_active() -> void:
	helmet.activate()
	var result := helmet.activate()
	assert_false(result,
		"Second activation should fail while active")
	assert_eq(helmet.get_charges(), 1,
		"Charges should not decrease on failed activation")


func test_activate_fails_with_no_charges() -> void:
	helmet.activate()  # Use charge 1
	helmet.deactivate()
	helmet.activate()  # Use charge 2
	helmet.deactivate()

	var result := helmet.activate()
	assert_false(result,
		"Activation should fail with 0 charges")
	assert_eq(helmet.get_charges(), 0,
		"Charges should remain at 0")


func test_two_activations_use_both_charges() -> void:
	helmet.activate()
	assert_eq(helmet.get_charges(), 1, "1 charge after first activation")

	helmet.deactivate()
	helmet.activate()
	assert_eq(helmet.get_charges(), 0, "0 charges after second activation")


# ============================================================================
# Deactivation Tests
# ============================================================================


func test_deactivate_sets_inactive() -> void:
	helmet.activate()
	helmet.deactivate()
	assert_false(helmet.is_active(),
		"Helmet should be inactive after deactivation")


func test_deactivate_resets_remaining_time() -> void:
	helmet.activate()
	helmet.deactivate()
	assert_eq(helmet.get_remaining_time(), 0.0,
		"Remaining time should be 0 after deactivation")


func test_deactivate_clears_ghost_data() -> void:
	helmet.activate()
	helmet._ghost_data.append({"position": Vector2.ZERO})
	helmet.deactivate()
	assert_true(helmet._ghost_data.is_empty(),
		"Ghost data should be cleared on deactivation")


func test_deactivate_emits_signal() -> void:
	helmet.activate()
	helmet.deactivate()
	assert_eq(helmet.deactivation_count, 1,
		"Deactivation count should be 1")


func test_deactivate_when_inactive_does_nothing() -> void:
	helmet.deactivate()
	assert_eq(helmet.deactivation_count, 0,
		"Deactivating while inactive should not emit signal")


# ============================================================================
# Timer / Physics Simulation Tests
# ============================================================================


func test_timer_decreases_over_time() -> void:
	helmet.activate()
	helmet.simulate_physics(1.0)
	assert_almost_eq(helmet.get_remaining_time(), 9.0, 0.01,
		"Remaining time should decrease by delta")


func test_timer_expires_and_deactivates() -> void:
	helmet.activate()
	helmet.simulate_physics(10.0)  # Full duration
	assert_false(helmet.is_active(),
		"Helmet should deactivate when timer expires")


func test_timer_expires_emits_deactivation() -> void:
	helmet.activate()
	helmet.simulate_physics(10.0)
	assert_eq(helmet.deactivation_count, 1,
		"Timer expiry should trigger deactivation signal")


func test_timer_does_not_go_negative() -> void:
	helmet.activate()
	helmet.simulate_physics(15.0)  # More than duration
	assert_eq(helmet.get_remaining_time(), 0.0,
		"Remaining time should not go below 0")


func test_multiple_small_deltas() -> void:
	helmet.activate()
	for i in range(100):
		helmet.simulate_physics(0.1)  # 100 * 0.1 = 10.0 seconds
	assert_false(helmet.is_active(),
		"Helmet should deactivate after cumulative time exceeds duration")


func test_physics_does_nothing_when_inactive() -> void:
	helmet.simulate_physics(1.0)
	assert_false(helmet.is_active(),
		"Inactive helmet should remain inactive")
	assert_eq(helmet.get_remaining_time(), 0.0,
		"Remaining time should stay 0 when inactive")


# ============================================================================
# Position Prediction Tests
# ============================================================================


func test_predict_stationary_enemy() -> void:
	var pos := Vector2(100, 200)
	var vel := Vector2.ZERO
	var predicted := helmet.predict_position(pos, vel)
	assert_eq(predicted, Vector2(100, 200),
		"Stationary enemy should predict to same position")


func test_predict_moving_enemy_right() -> void:
	var pos := Vector2(100, 200)
	var vel := Vector2(200, 0)  # Moving right at 200 px/s
	var predicted := helmet.predict_position(pos, vel)
	assert_eq(predicted, Vector2(300, 200),
		"Enemy moving right at 200px/s should predict 200px ahead")


func test_predict_moving_enemy_diagonal() -> void:
	var pos := Vector2(0, 0)
	var vel := Vector2(100, 100)
	var predicted := helmet.predict_position(pos, vel)
	assert_eq(predicted, Vector2(100, 100),
		"Diagonal movement should predict correctly")


func test_predict_moving_enemy_fast() -> void:
	var pos := Vector2(50, 50)
	var vel := Vector2(320, 0)  # combat_move_speed
	var predicted := helmet.predict_position(pos, vel)
	assert_eq(predicted, Vector2(370, 50),
		"Fast-moving enemy should predict 320px ahead")


func test_predict_negative_velocity() -> void:
	var pos := Vector2(200, 200)
	var vel := Vector2(-150, -100)
	var predicted := helmet.predict_position(pos, vel)
	assert_eq(predicted, Vector2(50, 100),
		"Negative velocity should predict backwards")


# ============================================================================
# ActiveItemManager Integration Tests (AI Helmet)
# ============================================================================


func test_ai_helmet_type_value() -> void:
	assert_eq(manager.ActiveItemType.AI_HELMET, 2,
		"AI_HELMET should be type 2")


func test_ai_helmet_data_exists() -> void:
	var data := manager.get_active_item_data(2)
	assert_false(data.is_empty(),
		"AI_HELMET data should exist")


func test_ai_helmet_name() -> void:
	assert_eq(manager.get_active_item_name(2), "AI Helmet",
		"AI Helmet should have correct name")


func test_ai_helmet_description_mentions_space() -> void:
	var desc := manager.get_active_item_description(2)
	assert_true(desc.contains("Space"),
		"AI Helmet description should mention Space key")


func test_ai_helmet_description_mentions_predict() -> void:
	var desc := manager.get_active_item_description(2)
	assert_true(desc.contains("predict"),
		"AI Helmet description should mention prediction")


func test_ai_helmet_description_mentions_10_seconds() -> void:
	var desc := manager.get_active_item_description(2)
	assert_true(desc.contains("10 seconds"),
		"AI Helmet description should mention 10 seconds duration")


func test_ai_helmet_description_mentions_2_charges() -> void:
	var desc := manager.get_active_item_description(2)
	assert_true(desc.contains("2 charges"),
		"AI Helmet description should mention 2 charges")


func test_ai_helmet_icon_path() -> void:
	var path := manager.get_active_item_icon_path(2)
	assert_true(path.contains("ai_helmet"),
		"AI Helmet icon path should contain 'ai_helmet'")


func test_has_ai_helmet_when_selected() -> void:
	manager.set_active_item(2)
	assert_true(manager.has_ai_helmet(),
		"has_ai_helmet should return true when AI helmet selected")


func test_no_ai_helmet_by_default() -> void:
	assert_false(manager.has_ai_helmet(),
		"has_ai_helmet should return false by default")


func test_no_ai_helmet_when_flashlight_selected() -> void:
	manager.set_active_item(1)
	assert_false(manager.has_ai_helmet(),
		"has_ai_helmet should return false when flashlight selected")


func test_no_flashlight_when_ai_helmet_selected() -> void:
	manager.set_active_item(2)
	assert_false(manager.has_flashlight(),
		"has_flashlight should return false when AI helmet selected")


func test_all_active_item_types_includes_helmet() -> void:
	var types := manager.get_all_active_item_types()
	assert_eq(types.size(), 3,
		"Should return 3 active item types (NONE, FLASHLIGHT, AI_HELMET)")
	assert_true(2 in types,
		"Types should include AI_HELMET (2)")


func test_switch_between_items() -> void:
	manager.set_active_item(2)  # AI Helmet
	assert_true(manager.has_ai_helmet())

	manager.set_active_item(1)  # Flashlight
	assert_true(manager.has_flashlight())
	assert_false(manager.has_ai_helmet())

	manager.set_active_item(0)  # None
	assert_false(manager.has_flashlight())
	assert_false(manager.has_ai_helmet())


# ============================================================================
# Charge System Edge Cases
# ============================================================================


func test_activate_after_first_expires() -> void:
	helmet.activate()
	helmet.simulate_physics(10.0)  # Let it expire
	assert_false(helmet.is_active(), "Should be inactive after expiry")
	assert_eq(helmet.get_charges(), 1, "Should have 1 charge left")

	var result := helmet.activate()
	assert_true(result, "Second activation should succeed")
	assert_true(helmet.is_active(), "Should be active again")
	assert_eq(helmet.get_charges(), 0, "Should have 0 charges")


func test_no_charge_consumed_on_failed_activation() -> void:
	helmet.activate()
	var initial_charges := helmet.get_charges()

	helmet.activate()  # Should fail (already active)
	assert_eq(helmet.get_charges(), initial_charges,
		"Failed activation should not consume a charge")


func test_manual_deactivate_preserves_charges() -> void:
	helmet.activate()
	helmet.deactivate()
	assert_eq(helmet.get_charges(), 1,
		"Manual deactivation should preserve remaining charges")


# ============================================================================
# Enemy Mock Tests (for prediction verification)
# ============================================================================


func test_mock_enemy_default_position() -> void:
	var enemy := MockEnemy.new()
	assert_eq(enemy.global_position, Vector2.ZERO,
		"Default enemy position should be zero")


func test_mock_enemy_default_velocity() -> void:
	var enemy := MockEnemy.new()
	assert_eq(enemy.velocity, Vector2.ZERO,
		"Default enemy velocity should be zero")


func test_mock_enemy_alive_by_default() -> void:
	var enemy := MockEnemy.new()
	assert_true(enemy.is_alive(),
		"Enemy should be alive by default")


func test_mock_enemy_dead_skipped() -> void:
	var enemy := MockEnemy.new()
	enemy._is_alive = false
	assert_false(enemy.is_alive(),
		"Dead enemy should not be alive")


func test_predict_with_mock_enemy() -> void:
	var enemy := MockEnemy.new()
	enemy.global_position = Vector2(100, 100)
	enemy.velocity = Vector2(220, 0)

	var predicted := helmet.predict_position(enemy.global_position, enemy.velocity)
	assert_eq(predicted, Vector2(320, 100),
		"Prediction should use enemy position + velocity * 1.0s")
