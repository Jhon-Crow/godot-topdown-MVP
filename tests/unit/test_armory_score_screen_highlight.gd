extends GutTest
## Regression tests for Issue #1690 — Armory button gold highlight not removed
## after pressing Apply on the armory opened from the score screen.
##
## Bug: sewer_level.gd, factory_level.gd, and labyrinth2_level.gd connected only
## back_pressed in _on_armory_button_pressed, missing the apply_pressed_from_score_screen
## connection. This meant the gold highlight on the ArmoryButton was never cleared
## when the user pressed Apply (instead of Back) to close the armory, even after
## all available items had been unlocked.
##
## Fix: add apply_pressed_from_score_screen.connect with the same removal logic
## that back_pressed already had in those three level scripts.


# ============================================================================
# Mock UnlockManager
# ============================================================================


class MockUnlockManager:
	## Whether any available unlock remains.
	var _has_any_available: bool

	func _init(has_available: bool) -> void:
		_has_any_available = has_available

	func has_method(method_name: String) -> bool:
		return method_name == "has_any_available_unlock"

	func has_any_available_unlock() -> bool:
		return _has_any_available


# ============================================================================
# MockArmoryButtonLevel
## Simulates the _on_armory_button_pressed signal-connection logic from level
## scripts, in both the buggy (pre-fix) and fixed forms.
# ============================================================================


class MockArmoryButtonLevel:
	## Signals emitted by the mock armory menu (mirrors ArmoryMenu signals).
	signal back_pressed
	signal apply_pressed_from_score_screen

	## Tracks whether _remove_armory_button_gold_style() was called.
	var armory_gold_style_removed: bool = false

	## Optional mock unlock manager (null simulates absent /root/UnlockManager).
	var unlock_manager: MockUnlockManager = null

	## Mirrors _remove_armory_button_gold_style() from level scripts.
	func _remove_armory_button_gold_style() -> void:
		armory_gold_style_removed = true

	## Fixed version: connects both back_pressed AND apply_pressed_from_score_screen.
	func setup_connections() -> void:
		back_pressed.connect(func():
			var um = unlock_manager
			if um == null or not um.has_method("has_any_available_unlock") or not um.has_any_available_unlock():
				_remove_armory_button_gold_style()
		)
		armory_menu_apply_connect()

	## Connects only apply_pressed_from_score_screen (the new fix block).
	func armory_menu_apply_connect() -> void:
		apply_pressed_from_score_screen.connect(func():
			# Issue #1690: Remove gold highlight from armory button if all available items have been opened
			var um = unlock_manager
			if um == null or not um.has_method("has_any_available_unlock") or not um.has_any_available_unlock():
				_remove_armory_button_gold_style()
		)

	## Buggy version (pre-fix): connects only back_pressed, not apply_pressed_from_score_screen.
	func setup_connections_buggy() -> void:
		back_pressed.connect(func():
			var um = unlock_manager
			if um == null or not um.has_method("has_any_available_unlock") or not um.has_any_available_unlock():
				_remove_armory_button_gold_style()
		)


# ============================================================================
# Tests — Bug reproduction
# ============================================================================


func test_buggy_apply_does_not_remove_gold_when_no_unlocks_remain() -> void:
	# Demonstrates the pre-fix bug: with only back_pressed connected, emitting
	# apply_pressed_from_score_screen does NOT remove the gold style, even when
	# no unlockable items remain.
	var level := MockArmoryButtonLevel.new()
	level.unlock_manager = MockUnlockManager.new(false)
	level.setup_connections_buggy()
	level.apply_pressed_from_score_screen.emit()
	assert_false(
		level.armory_gold_style_removed,
		"Pre-fix: apply_pressed_from_score_screen must NOT remove gold style when only back_pressed is connected"
	)


# ============================================================================
# Tests — Fix verification
# ============================================================================


func test_fixed_apply_removes_gold_when_no_unlocks_remain() -> void:
	# Issue #1690: after the fix, apply_pressed_from_score_screen removes the
	# gold highlight when the UnlockManager reports no available unlocks.
	var level := MockArmoryButtonLevel.new()
	level.unlock_manager = MockUnlockManager.new(false)
	level.setup_connections()
	level.apply_pressed_from_score_screen.emit()
	assert_true(
		level.armory_gold_style_removed,
		"Fix: apply_pressed_from_score_screen must remove gold style when no unlocks remain"
	)


func test_fixed_apply_does_not_remove_gold_when_unlocks_remain() -> void:
	# When items are still available to unlock, the gold highlight must stay.
	var level := MockArmoryButtonLevel.new()
	level.unlock_manager = MockUnlockManager.new(true)
	level.setup_connections()
	level.apply_pressed_from_score_screen.emit()
	assert_false(
		level.armory_gold_style_removed,
		"Gold style must NOT be removed when there are still available unlocks"
	)


func test_fixed_apply_removes_gold_when_unlock_manager_absent() -> void:
	# Absent UnlockManager (null) is treated as "no unlocks" — gold must be removed.
	var level := MockArmoryButtonLevel.new()
	level.unlock_manager = null
	level.setup_connections()
	level.apply_pressed_from_score_screen.emit()
	assert_true(
		level.armory_gold_style_removed,
		"Gold style must be removed when UnlockManager is absent (null)"
	)


func test_back_pressed_still_removes_gold_after_fix() -> void:
	# Regression: the existing back_pressed connection must still work after the fix.
	var level := MockArmoryButtonLevel.new()
	level.unlock_manager = MockUnlockManager.new(false)
	level.setup_connections()
	level.back_pressed.emit()
	assert_true(
		level.armory_gold_style_removed,
		"back_pressed must still remove gold style after the fix is applied"
	)


func test_back_pressed_does_not_remove_gold_when_unlocks_remain() -> void:
	# back_pressed should also respect the unlock state and NOT remove gold
	# if items are still available.
	var level := MockArmoryButtonLevel.new()
	level.unlock_manager = MockUnlockManager.new(true)
	level.setup_connections()
	level.back_pressed.emit()
	assert_false(
		level.armory_gold_style_removed,
		"back_pressed must NOT remove gold style when there are still available unlocks"
	)


# ============================================================================
# Tests — Source file verification (regression guards for the 3 fixed levels)
# ============================================================================


func test_sewer_level_connects_apply_pressed_from_score_screen() -> void:
	var source := FileAccess.open("res://scripts/levels/sewer_level.gd", FileAccess.READ)
	assert_not_null(source, "sewer_level.gd must be readable")
	var content := source.get_as_text()
	source.close()
	assert_true(
		"apply_pressed_from_score_screen.connect" in content,
		"sewer_level.gd must connect apply_pressed_from_score_screen (Issue #1690)"
	)


func test_factory_level_connects_apply_pressed_from_score_screen() -> void:
	var source := FileAccess.open("res://scripts/levels/factory_level.gd", FileAccess.READ)
	assert_not_null(source, "factory_level.gd must be readable")
	var content := source.get_as_text()
	source.close()
	assert_true(
		"apply_pressed_from_score_screen.connect" in content,
		"factory_level.gd must connect apply_pressed_from_score_screen (Issue #1690)"
	)


func test_labyrinth2_level_connects_apply_pressed_from_score_screen() -> void:
	var source := FileAccess.open("res://scripts/levels/labyrinth2_level.gd", FileAccess.READ)
	assert_not_null(source, "labyrinth2_level.gd must be readable")
	var content := source.get_as_text()
	source.close()
	assert_true(
		"apply_pressed_from_score_screen.connect" in content,
		"labyrinth2_level.gd must connect apply_pressed_from_score_screen (Issue #1690)"
	)
