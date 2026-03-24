extends GutTest
## Unit tests for ControlsMenu.
##
## Tests rebinding state management, pending bindings tracking,
## and conflict detection concepts using a mock class.


# ============================================================================
# Mock ControlsMenu for Testing
# ============================================================================


class MockControlsMenu:
	## Currently selected action for rebinding. Empty string means no action selected.
	var _rebinding_action: String = ""

	## Dictionary mapping action names to their UI button references.
	var _action_buttons: Dictionary = {}

	## Flag to track if there are unsaved changes.
	var _has_changes: bool = false

	## Temporary storage for new bindings before applying.
	var _pending_bindings: Dictionary = {}

	## Simulated current bindings (action_name -> key_name).
	var _current_bindings: Dictionary = {
		"move_up": "W",
		"move_down": "S",
		"move_left": "A",
		"move_right": "D",
		"shoot": "Mouse Left",
		"reload": "R",
		"pause": "Escape",
		"interact": "E",
	}

	## Signal tracking.
	var back_pressed_count: int = 0
	var apply_count: int = 0
	var reset_count: int = 0

	## Start rebinding an action.
	func start_rebinding(action_name: String) -> void:
		_rebinding_action = action_name

	## Cancel the current rebinding.
	func cancel_rebinding() -> void:
		_rebinding_action = ""

	## Check if currently in rebinding mode.
	func is_rebinding() -> bool:
		return not _rebinding_action.is_empty()

	## Get the action currently being rebound.
	func get_rebinding_action() -> String:
		return _rebinding_action

	## Apply a pending binding for an action.
	func set_pending_binding(action_name: String, key_name: String) -> void:
		_pending_bindings[action_name] = key_name
		_has_changes = true
		_rebinding_action = ""

	## Check if there are unsaved changes.
	func has_changes() -> bool:
		return _has_changes

	## Get pending bindings dictionary.
	func get_pending_bindings() -> Dictionary:
		return _pending_bindings

	## Check for key conflict: returns the action name that already uses this key.
	func check_conflict(key_name: String, exclude_action: String) -> String:
		# Check current bindings
		for action_name in _current_bindings:
			if action_name == exclude_action:
				continue
			if _current_bindings[action_name] == key_name:
				return action_name
		# Check pending bindings (override current)
		for action_name in _pending_bindings:
			if action_name == exclude_action:
				continue
			if _pending_bindings[action_name] == key_name:
				return action_name
		return ""

	## Apply all pending bindings.
	func apply() -> void:
		for action_name in _pending_bindings:
			_current_bindings[action_name] = _pending_bindings[action_name]
		_pending_bindings.clear()
		_has_changes = false
		apply_count += 1

	## Reset to defaults.
	func reset() -> void:
		_pending_bindings.clear()
		_has_changes = false
		reset_count += 1

	## Press back button.
	func press_back() -> void:
		if _has_changes:
			_pending_bindings.clear()
			_has_changes = false
		_rebinding_action = ""
		back_pressed_count += 1


var menu: MockControlsMenu


func before_each() -> void:
	menu = MockControlsMenu.new()


func after_each() -> void:
	menu = null


# ============================================================================
# Rebinding State Management Tests
# ============================================================================


func test_initial_rebinding_state() -> void:
	assert_false(menu.is_rebinding(),
		"Should not be in rebinding mode initially")


func test_start_rebinding() -> void:
	menu.start_rebinding("move_up")

	assert_true(menu.is_rebinding(),
		"Should be in rebinding mode after start")
	assert_eq(menu.get_rebinding_action(), "move_up",
		"Should track which action is being rebound")


func test_cancel_rebinding() -> void:
	menu.start_rebinding("shoot")
	menu.cancel_rebinding()

	assert_false(menu.is_rebinding(),
		"Should not be in rebinding mode after cancel")
	assert_eq(menu.get_rebinding_action(), "",
		"Rebinding action should be empty after cancel")


func test_rebinding_clears_on_binding_set() -> void:
	menu.start_rebinding("reload")
	menu.set_pending_binding("reload", "T")

	assert_false(menu.is_rebinding(),
		"Should exit rebinding mode after setting a binding")


func test_switch_rebinding_action() -> void:
	menu.start_rebinding("move_up")
	menu.start_rebinding("move_down")

	assert_eq(menu.get_rebinding_action(), "move_down",
		"Should track latest rebinding action")


# ============================================================================
# Pending Bindings Tracking Tests
# ============================================================================


func test_no_pending_changes_initially() -> void:
	assert_false(menu.has_changes(),
		"Should have no pending changes initially")


func test_pending_binding_sets_has_changes() -> void:
	menu.set_pending_binding("move_up", "I")

	assert_true(menu.has_changes(),
		"Should have pending changes after setting a binding")


func test_pending_binding_stored_correctly() -> void:
	menu.set_pending_binding("reload", "T")

	var pending := menu.get_pending_bindings()
	assert_eq(pending["reload"], "T",
		"Pending binding should store the new key")


func test_multiple_pending_bindings() -> void:
	menu.set_pending_binding("move_up", "I")
	menu.set_pending_binding("move_down", "K")
	menu.set_pending_binding("move_left", "J")
	menu.set_pending_binding("move_right", "L")

	var pending := menu.get_pending_bindings()
	assert_eq(pending.size(), 4,
		"Should store all four pending bindings")


func test_overwrite_pending_binding() -> void:
	menu.set_pending_binding("reload", "T")
	menu.set_pending_binding("reload", "Y")

	var pending := menu.get_pending_bindings()
	assert_eq(pending["reload"], "Y",
		"Latest pending binding should overwrite previous")


func test_apply_clears_pending() -> void:
	menu.set_pending_binding("reload", "T")
	menu.apply()

	assert_false(menu.has_changes(),
		"Should have no pending changes after apply")
	assert_eq(menu.get_pending_bindings().size(), 0,
		"Pending bindings should be empty after apply")


func test_apply_updates_current_bindings() -> void:
	menu.set_pending_binding("reload", "T")
	menu.apply()

	# Now setting a conflict check should see the new binding
	var conflict := menu.check_conflict("T", "move_up")
	assert_eq(conflict, "reload",
		"Applied binding should be reflected in current bindings")


func test_apply_increments_count() -> void:
	menu.set_pending_binding("reload", "T")
	menu.apply()

	assert_eq(menu.apply_count, 1,
		"Apply count should increment")


func test_reset_clears_pending() -> void:
	menu.set_pending_binding("reload", "T")
	menu.reset()

	assert_false(menu.has_changes(),
		"Should have no pending changes after reset")
	assert_eq(menu.get_pending_bindings().size(), 0,
		"Pending bindings should be empty after reset")


# ============================================================================
# Conflict Detection Tests
# ============================================================================


func test_no_conflict_for_unused_key() -> void:
	var conflict := menu.check_conflict("Z", "move_up")

	assert_eq(conflict, "",
		"Should not detect conflict for unused key")


func test_conflict_detected_for_existing_binding() -> void:
	var conflict := menu.check_conflict("W", "reload")

	assert_eq(conflict, "move_up",
		"Should detect conflict with move_up (W key)")


func test_no_self_conflict() -> void:
	var conflict := menu.check_conflict("W", "move_up")

	assert_eq(conflict, "",
		"Should not report conflict with the same action")


func test_conflict_with_pending_binding() -> void:
	menu.set_pending_binding("interact", "Z")
	var conflict := menu.check_conflict("Z", "reload")

	assert_eq(conflict, "interact",
		"Should detect conflict with pending bindings")


func test_conflict_detection_all_default_keys() -> void:
	var default_keys := ["W", "S", "A", "D", "Mouse Left", "R", "Escape", "E"]
	for key in default_keys:
		var conflict := menu.check_conflict(key, "__nonexistent__")
		assert_ne(conflict, "",
			"Key '%s' should conflict with an existing action" % key)


# ============================================================================
# Back Button Tests
# ============================================================================


func test_back_discards_pending_changes() -> void:
	menu.set_pending_binding("reload", "T")
	menu.press_back()

	assert_false(menu.has_changes(),
		"Back should discard pending changes")


func test_back_clears_rebinding_state() -> void:
	menu.start_rebinding("shoot")
	menu.press_back()

	assert_false(menu.is_rebinding(),
		"Back should clear rebinding state")


func test_back_increments_count() -> void:
	menu.press_back()
	menu.press_back()

	assert_eq(menu.back_pressed_count, 2,
		"Should track back presses")


# ============================================================================
# Initial Bindings Tests
# ============================================================================


func test_initial_bindings_count() -> void:
	assert_eq(menu._current_bindings.size(), 8,
		"Should have 8 default bindings")


func test_initial_move_up_binding() -> void:
	assert_eq(menu._current_bindings["move_up"], "W",
		"move_up should default to W")


func test_initial_shoot_binding() -> void:
	assert_eq(menu._current_bindings["shoot"], "Mouse Left",
		"shoot should default to Mouse Left")
