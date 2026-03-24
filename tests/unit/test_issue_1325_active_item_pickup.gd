extends GutTest
## Unit tests for Issue #1325 — active item can be used immediately after pickup in roguelike mode.
##
## The bug: ActiveItemManager.set_active_item(type, false) is called on pickup (no scene restart).
## The signal active_item_changed fires, but the Player's _init_* methods were never called again,
## so equipped flags remained false and the item could not be activated.
##
## The fix: Player now connects to active_item_changed in _ready() and calls the appropriate
## _init_* function when the signal fires, making the item immediately usable.


# ============================================================================
# MockActiveItemManager — lightweight substitute for the autoload singleton
# ============================================================================

class MockActiveItemManager extends Node:
	signal active_item_changed(new_type: int)

	var current_active_item: int = 0  # NONE

	## Simulate set_active_item(type, false) — no scene restart.
	func set_active_item(type: int, restart_level: bool = true) -> void:
		current_active_item = type
		active_item_changed.emit(type)

	func has_homing_bullets() -> bool:
		return current_active_item == 2
	func has_flashlight() -> bool:
		return current_active_item == 1
	func has_bff_pendant() -> bool:
		return current_active_item == 4
	func has_invisibility_suit() -> bool:
		return current_active_item == 5
	func has_breaker_bullets() -> bool:
		return current_active_item == 6
	func has_force_field() -> bool:
		return current_active_item == 7
	func has_trajectory_glasses() -> bool:
		return current_active_item == 8
	func has_loudspeaker() -> bool:
		return current_active_item == 11
	func has_breaching_charges() -> bool:
		return current_active_item == 12
	func has_armored_skin() -> bool:
		return current_active_item == 13
	func has_drilling_bullets() -> bool:
		return current_active_item == 15
	func has_recoil_compensator() -> bool:
		return current_active_item == 16
	func has_experimental_sample() -> bool:
		return current_active_item == 18
	func has_fine_motor_skills() -> bool:
		return current_active_item == 19
	func is_active_item_jammed() -> bool:
		return false
	func is_active_item_jammed_verbose() -> bool:
		return false


# ============================================================================
# MockPlayer — simulates the relevant parts of player.gd
# ============================================================================

class MockPlayer:
	## Replicates the equipped-flag pattern from player.gd.
	var _homing_equipped: bool = false
	var _homing_active: bool = false
	var _homing_timer: float = 0.0
	var _flashlight_equipped: bool = false
	var _bff_pendant_equipped: bool = false
	var _invisibility_suit_equipped: bool = false
	var _breaker_bullets_active: bool = false
	var _force_field_equipped: bool = false
	var _trajectory_glasses_equipped: bool = false
	var _loudspeaker_equipped: bool = false
	var _breaching_charges_equipped: bool = false
	var _armored_skin_active: bool = false
	var _recoil_compensator_equipped: bool = false
	var _experimental_sample_equipped: bool = false
	var _fine_motor_skills_equipped: bool = false

	var active_item_manager: MockActiveItemManager = null

	func _init(manager: MockActiveItemManager) -> void:
		active_item_manager = manager

	## Simulate _ready(): connect to signal
	func connect_signal() -> void:
		active_item_manager.active_item_changed.connect(_on_active_item_picked_up)

	## De-equip all items (mirrors _deequip_all_active_items in player.gd)
	func _deequip_all_active_items() -> void:
		_flashlight_equipped = false
		_homing_equipped = false
		_homing_active = false
		_homing_timer = 0.0
		_bff_pendant_equipped = false
		_invisibility_suit_equipped = false
		_breaker_bullets_active = false
		_force_field_equipped = false
		_trajectory_glasses_equipped = false
		_loudspeaker_equipped = false
		_breaching_charges_equipped = false
		_armored_skin_active = false
		_recoil_compensator_equipped = false
		_experimental_sample_equipped = false
		_fine_motor_skills_equipped = false

	## Mirrors _on_active_item_picked_up in player.gd
	func _on_active_item_picked_up(item_type: int) -> void:
		_deequip_all_active_items()
		match item_type:
			1:  _init_flashlight()
			2:  _init_homing_bullets()
			4:  _init_bff_pendant()
			5:  _init_invisibility_suit()
			6:  _init_breaker_bullets()
			7:  _init_force_field()
			8:  _init_trajectory_glasses()
			11: _init_loudspeaker()
			12: _init_breaching_charges()
			13: _init_armored_skin()
			16: _init_recoil_compensator()
			18: _init_experimental_sample()
			19: _init_fine_motor_skills()

	## Minimal init stubs that mirror the real guard + flag-set pattern.
	func _init_flashlight() -> void:
		if not active_item_manager.has_flashlight():
			return
		_flashlight_equipped = true

	func _init_homing_bullets() -> void:
		if not active_item_manager.has_homing_bullets():
			return
		_homing_equipped = true
		_homing_active = false
		_homing_timer = 0.0

	func _init_bff_pendant() -> void:
		if not active_item_manager.has_bff_pendant():
			return
		_bff_pendant_equipped = true

	func _init_invisibility_suit() -> void:
		if not active_item_manager.has_invisibility_suit():
			return
		_invisibility_suit_equipped = true

	func _init_breaker_bullets() -> void:
		if not active_item_manager.has_breaker_bullets():
			return
		_breaker_bullets_active = true

	func _init_force_field() -> void:
		if not active_item_manager.has_force_field():
			return
		_force_field_equipped = true

	func _init_trajectory_glasses() -> void:
		if not active_item_manager.has_trajectory_glasses():
			return
		_trajectory_glasses_equipped = true

	func _init_loudspeaker() -> void:
		if not active_item_manager.has_loudspeaker():
			return
		_loudspeaker_equipped = true

	func _init_breaching_charges() -> void:
		if not active_item_manager.has_breaching_charges():
			return
		_breaching_charges_equipped = true

	func _init_armored_skin() -> void:
		if not active_item_manager.has_armored_skin():
			return
		_armored_skin_active = true

	func _init_recoil_compensator() -> void:
		if not active_item_manager.has_recoil_compensator():
			return
		_recoil_compensator_equipped = true

	func _init_experimental_sample() -> void:
		if not active_item_manager.has_experimental_sample():
			return
		_experimental_sample_equipped = true

	func _init_fine_motor_skills() -> void:
		if not active_item_manager.has_fine_motor_skills():
			return
		_fine_motor_skills_equipped = true


# ============================================================================
# Test cases
# ============================================================================

var _manager: MockActiveItemManager
var _player: MockPlayer


func before_each() -> void:
	_manager = MockActiveItemManager.new()
	_player = MockPlayer.new(_manager)
	_player.connect_signal()


# --- Core bug regression: item equipped after pickup ---

func test_homing_bullets_equipped_after_pickup() -> void:
	## Before the fix: _homing_equipped stayed false after pickup in roguelike mode.
	## After the fix: active_item_changed signal triggers _init_homing_bullets().
	assert_false(_player._homing_equipped,
		"Homing bullets should NOT be equipped before pickup")
	_manager.set_active_item(2, false)  # 2 = HOMING_BULLETS, no restart
	assert_true(_player._homing_equipped,
		"Homing bullets should be equipped immediately after pickup (Issue #1325)")


func test_flashlight_equipped_after_pickup() -> void:
	assert_false(_player._flashlight_equipped,
		"Flashlight should NOT be equipped before pickup")
	_manager.set_active_item(1, false)
	assert_true(_player._flashlight_equipped,
		"Flashlight should be equipped immediately after pickup (Issue #1325)")


func test_force_field_equipped_after_pickup() -> void:
	assert_false(_player._force_field_equipped,
		"Force field should NOT be equipped before pickup")
	_manager.set_active_item(7, false)
	assert_true(_player._force_field_equipped,
		"Force field should be equipped immediately after pickup (Issue #1325)")


func test_invisibility_suit_equipped_after_pickup() -> void:
	assert_false(_player._invisibility_suit_equipped,
		"Invisibility suit should NOT be equipped before pickup")
	_manager.set_active_item(5, false)
	assert_true(_player._invisibility_suit_equipped,
		"Invisibility suit should be equipped immediately after pickup (Issue #1325)")


func test_trajectory_glasses_equipped_after_pickup() -> void:
	assert_false(_player._trajectory_glasses_equipped,
		"Trajectory glasses should NOT be equipped before pickup")
	_manager.set_active_item(8, false)
	assert_true(_player._trajectory_glasses_equipped,
		"Trajectory glasses should be equipped immediately after pickup (Issue #1325)")


func test_recoil_compensator_equipped_after_pickup() -> void:
	assert_false(_player._recoil_compensator_equipped,
		"Recoil compensator should NOT be equipped before pickup")
	_manager.set_active_item(16, false)
	assert_true(_player._recoil_compensator_equipped,
		"Recoil compensator should be equipped immediately after pickup (Issue #1325)")


func test_loudspeaker_equipped_after_pickup() -> void:
	assert_false(_player._loudspeaker_equipped,
		"Loudspeaker should NOT be equipped before pickup")
	_manager.set_active_item(11, false)
	assert_true(_player._loudspeaker_equipped,
		"Loudspeaker should be equipped immediately after pickup (Issue #1325)")


func test_experimental_sample_equipped_after_pickup() -> void:
	assert_false(_player._experimental_sample_equipped,
		"Experimental sample should NOT be equipped before pickup")
	_manager.set_active_item(18, false)
	assert_true(_player._experimental_sample_equipped,
		"Experimental sample should be equipped immediately after pickup (Issue #1325)")


func test_fine_motor_skills_equipped_after_pickup() -> void:
	assert_false(_player._fine_motor_skills_equipped,
		"Fine motor skills should NOT be equipped before pickup")
	_manager.set_active_item(19, false)
	assert_true(_player._fine_motor_skills_equipped,
		"Fine motor skills should be equipped immediately after pickup (Issue #1325)")


# --- Passive items ---

func test_breaker_bullets_active_after_pickup() -> void:
	assert_false(_player._breaker_bullets_active,
		"Breaker bullets should NOT be active before pickup")
	_manager.set_active_item(6, false)
	assert_true(_player._breaker_bullets_active,
		"Breaker bullets (passive) should be active immediately after pickup (Issue #1325)")


func test_armored_skin_active_after_pickup() -> void:
	assert_false(_player._armored_skin_active,
		"Armored skin should NOT be active before pickup")
	_manager.set_active_item(13, false)
	assert_true(_player._armored_skin_active,
		"Armored skin (passive) should be active immediately after pickup (Issue #1325)")


# --- Dual-equip prevention: old item de-equipped on swap ---

func test_old_item_deequipped_when_new_item_picked_up() -> void:
	## Player picks up flashlight first, then swaps to homing bullets.
	## After the fix: flashlight is de-equipped when homing bullets are picked up.
	_manager.set_active_item(1, false)  # Pick up flashlight
	assert_true(_player._flashlight_equipped, "Flashlight should be equipped after first pickup")
	_manager.set_active_item(2, false)  # Swap to homing bullets
	assert_false(_player._flashlight_equipped,
		"Flashlight should be de-equipped when homing bullets are picked up (Issue #1325)")
	assert_true(_player._homing_equipped,
		"Homing bullets should be equipped after swap (Issue #1325)")


func test_swapping_back_to_old_item_works() -> void:
	## Player picks up A, then B, then A again via pedestal swap.
	_manager.set_active_item(7, false)  # Force field
	assert_true(_player._force_field_equipped)
	_manager.set_active_item(2, false)  # Swap to homing bullets
	assert_false(_player._force_field_equipped,
		"Force field should be de-equipped after swap")
	assert_true(_player._homing_equipped)
	_manager.set_active_item(7, false)  # Swap back to force field
	assert_true(_player._force_field_equipped,
		"Force field should be re-equipped on second pickup (Issue #1325)")
	assert_false(_player._homing_equipped,
		"Homing bullets should be de-equipped on swap back")


func test_none_item_does_not_equip_anything() -> void:
	## Setting active item to NONE (0) should not equip anything.
	_manager.set_active_item(0, false)
	assert_false(_player._flashlight_equipped)
	assert_false(_player._homing_equipped)
	assert_false(_player._force_field_equipped)


func test_active_item_changed_without_restart_sets_equipped_flag() -> void:
	## Verify the fix works specifically for the no-restart path (roguelike pickup).
	## Before fix: equipped flag stayed false because no _init_* was called.
	## After fix: signal handler runs _init_* and sets the flag.
	_manager.set_active_item(8, false)  # Trajectory glasses, no restart
	assert_true(_player._trajectory_glasses_equipped,
		"Trajectory glasses equipped flag must be true immediately after roguelike pickup")
