extends GutTest
## Unit tests for PlayerLoudspeakerComponent.
##
## Tests LOUDSPEAKER_HOLD_DURATION constant and equipped state tracking
## for the player loudspeaker active item.


# ============================================================================
# Mock PlayerLoudspeakerComponent for Logic Tests
# ============================================================================


class MockPlayerLoudspeakerComponent:
	const LOUDSPEAKER_HOLD_DURATION: float = 0.6

	var _loudspeaker_equipped: bool = false
	var _loudspeaker_hold_timer: float = 0.0
	var _loudspeaker_hand_sprite_visible: bool = false

	func has_loudspeaker() -> bool:
		return _loudspeaker_equipped

	func equip() -> void:
		_loudspeaker_equipped = true

	func unequip() -> void:
		_loudspeaker_equipped = false

	func start_hold_animation() -> void:
		_loudspeaker_hold_timer = LOUDSPEAKER_HOLD_DURATION
		_loudspeaker_hand_sprite_visible = true

	func update_hold_timer(delta: float) -> void:
		if _loudspeaker_hold_timer > 0.0:
			_loudspeaker_hold_timer -= delta
			if _loudspeaker_hold_timer <= 0.0:
				_loudspeaker_hold_timer = 0.0
				_loudspeaker_hand_sprite_visible = false

	func is_hold_animation_active() -> bool:
		return _loudspeaker_hold_timer > 0.0


var comp: MockPlayerLoudspeakerComponent


func before_each() -> void:
	comp = MockPlayerLoudspeakerComponent.new()


func after_each() -> void:
	comp = null


# ============================================================================
# Constants Tests
# ============================================================================


func test_loudspeaker_hold_duration() -> void:
	assert_eq(MockPlayerLoudspeakerComponent.LOUDSPEAKER_HOLD_DURATION, 0.6,
		"LOUDSPEAKER_HOLD_DURATION should be 0.6 seconds")


# ============================================================================
# Equipped State Tests
# ============================================================================


func test_not_equipped_by_default() -> void:
	assert_false(comp.has_loudspeaker(),
		"Loudspeaker should not be equipped by default")


func test_equip_sets_equipped_true() -> void:
	comp.equip()

	assert_true(comp.has_loudspeaker(),
		"has_loudspeaker should return true after equip")


func test_unequip_sets_equipped_false() -> void:
	comp.equip()
	comp.unequip()

	assert_false(comp.has_loudspeaker(),
		"has_loudspeaker should return false after unequip")


func test_equip_twice_remains_equipped() -> void:
	comp.equip()
	comp.equip()

	assert_true(comp.has_loudspeaker(),
		"Double equip should still be equipped")


# ============================================================================
# Hold Animation Timer Tests
# ============================================================================


func test_hold_timer_zero_by_default() -> void:
	assert_eq(comp._loudspeaker_hold_timer, 0.0,
		"Hold timer should be 0 by default")


func test_hold_animation_not_active_by_default() -> void:
	assert_false(comp.is_hold_animation_active(),
		"Hold animation should not be active by default")


func test_start_hold_sets_timer() -> void:
	comp.start_hold_animation()

	assert_eq(comp._loudspeaker_hold_timer, 0.6,
		"Hold timer should be set to LOUDSPEAKER_HOLD_DURATION")


func test_start_hold_shows_sprite() -> void:
	comp.start_hold_animation()

	assert_true(comp._loudspeaker_hand_sprite_visible,
		"Hand sprite should be visible during hold")


func test_hold_animation_active_after_start() -> void:
	comp.start_hold_animation()

	assert_true(comp.is_hold_animation_active(),
		"Hold animation should be active after start")


func test_hold_timer_decreases_over_time() -> void:
	comp.start_hold_animation()
	comp.update_hold_timer(0.3)

	assert_almost_eq(comp._loudspeaker_hold_timer, 0.3, 0.01,
		"Hold timer should decrease by delta")
	assert_true(comp.is_hold_animation_active(),
		"Hold animation should still be active mid-timer")


func test_hold_timer_completes() -> void:
	comp.start_hold_animation()
	comp.update_hold_timer(0.6)

	assert_eq(comp._loudspeaker_hold_timer, 0.0,
		"Hold timer should reach 0 when duration elapsed")
	assert_false(comp.is_hold_animation_active(),
		"Hold animation should not be active after completion")


func test_hold_sprite_hidden_after_timer() -> void:
	comp.start_hold_animation()
	comp.update_hold_timer(0.7)  # More than duration

	assert_false(comp._loudspeaker_hand_sprite_visible,
		"Hand sprite should be hidden after hold timer expires")


func test_hold_timer_does_not_go_negative() -> void:
	comp.start_hold_animation()
	comp.update_hold_timer(1.0)

	assert_eq(comp._loudspeaker_hold_timer, 0.0,
		"Hold timer should not go negative")


func test_hold_timer_no_update_when_zero() -> void:
	comp.update_hold_timer(0.5)

	assert_eq(comp._loudspeaker_hold_timer, 0.0,
		"Hold timer should stay at 0 when not started")
	assert_false(comp._loudspeaker_hand_sprite_visible,
		"Sprite should remain hidden when timer was never started")
