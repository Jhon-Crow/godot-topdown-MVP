extends CanvasLayer
## Controls menu for remapping game key bindings.
##
## Displays a list of all remappable actions with their current key bindings.
## Allows users to rebind keys by clicking on an action and pressing a new key.
## Includes conflict detection and settings persistence.

## Signal emitted when the back button is pressed.
signal back_pressed

## Reference to the action list container.
@onready var action_list: VBoxContainer = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/ScrollContainer/ActionList
@onready var apply_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/ButtonContainer/ApplyButton
@onready var reset_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/ButtonContainer/ResetButton
@onready var back_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/ButtonContainer/BackButton
@onready var status_label: Label = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/StatusLabel
@onready var conflict_dialog: AcceptDialog = $ConflictDialog

## Currently selected action for rebinding. Empty string means no action selected.
var _rebinding_action: String = ""

## Dictionary mapping action names to their UI button references.
var _action_buttons: Dictionary = {}

## Flag to track if there are unsaved changes.
var _has_changes: bool = false

## Temporary storage for new bindings before applying.
var _pending_bindings: Dictionary = {}


func _ready() -> void:
	# Connect button signals
	apply_button.pressed.connect(_on_apply_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	back_button.pressed.connect(_on_back_pressed)
	conflict_dialog.confirmed.connect(_on_conflict_confirmed)

	# Populate the action list
	_populate_action_list()

	# Update button states
	_update_button_states()

	# Set process mode to allow input while paused
	process_mode = Node.PROCESS_MODE_ALWAYS


func _populate_action_list() -> void:
	# Clear existing children (except template if any)
	for child in action_list.get_children():
		child.queue_free()
	_action_buttons.clear()

	# Create a row for each remappable action
	for action_name in InputSettings.remappable_actions:
		var row := _create_action_row(action_name)
		action_list.add_child(row)


func _create_action_row(action_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = action_name + "_row"

	# Action name label
	var label := Label.new()
	label.text = InputSettings.get_action_display_name(action_name)
	label.custom_minimum_size.x = 150
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	# Key binding button
	var button := Button.new()
	button.name = action_name + "_button"
	button.text = InputSettings.get_action_key_name(action_name)
	button.custom_minimum_size = Vector2(150, 35)
	button.pressed.connect(_on_action_button_pressed.bind(action_name))
	row.add_child(button)

	_action_buttons[action_name] = button

	return row


func _input(event: InputEvent) -> void:
	if _rebinding_action.is_empty():
		return

	# Only handle key and mouse button events
	if not (event is InputEventKey or event is InputEventMouseButton):
		return

	# Ignore key release events
	if event is InputEventKey and not event.pressed:
		return

	# Ignore mouse button release events
	if event is InputEventMouseButton and not event.pressed:
		return

	# Prevent the event from propagating
	get_viewport().set_input_as_handled()

	# Handle escape key to cancel rebinding
	if event is InputEventKey and event.physical_keycode == KEY_ESCAPE:
		_cancel_rebinding()
		return

	# Check for conflicts
	var conflict := InputSettings.check_key_conflict(event, _rebinding_action)
	if not conflict.is_empty():
		_show_conflict_dialog(conflict, event)
		return

	# Apply the new binding
	_apply_pending_binding(_rebinding_action, event)


func _on_action_button_pressed(action_name: String) -> void:
	_start_rebinding(action_name)


func _start_rebinding(action_name: String) -> void:
	_rebinding_action = action_name

	# Update button text to show waiting state
	var button: Button = _action_buttons[action_name]
	button.text = "Press a key..."

	# Update status
	status_label.text = "Press a key for " + InputSettings.get_action_display_name(action_name) + " (Escape to cancel)"


func _cancel_rebinding() -> void:
	if _rebinding_action.is_empty():
		return

	# Restore the button text
	var button: Button = _action_buttons[_rebinding_action]
	if _rebinding_action in _pending_bindings:
		button.text = InputSettings.get_event_name(_pending_bindings[_rebinding_action])
	else:
		button.text = InputSettings.get_action_key_name(_rebinding_action)

	_rebinding_action = ""
	status_label.text = ""


func _apply_pending_binding(action_name: String, event: InputEvent) -> void:
	# Store in pending bindings
	_pending_bindings[action_name] = event

	# Update button text
	var button: Button = _action_buttons[action_name]
	button.text = InputSettings.get_event_name(event)

	# Mark as having unsaved changes
	_has_changes = true
	_update_button_states()

	# Clear rebinding state
	_rebinding_action = ""
	status_label.text = "Changes pending. Click Apply to save."


func _show_conflict_dialog(conflicting_action: String, new_event: InputEvent) -> void:
	var conflict_name := InputSettings.get_action_display_name(conflicting_action)
	var key_name := InputSettings.get_event_name(new_event)

	conflict_dialog.dialog_text = "'" + key_name + "' is already assigned to '" + conflict_name + "'.\n\nDo you want to replace it?"

	# Store the event for when confirmed
	conflict_dialog.set_meta("pending_event", new_event)
	conflict_dialog.set_meta("conflicting_action", conflicting_action)

	conflict_dialog.popup_centered()


func _on_conflict_confirmed() -> void:
	var pending_event: InputEvent = conflict_dialog.get_meta("pending_event")
	var conflicting_action: String = conflict_dialog.get_meta("conflicting_action")

	# Clear the conflicting action's binding
	_pending_bindings[conflicting_action] = null
	var conflict_button: Button = _action_buttons[conflicting_action]
	conflict_button.text = "Not Set"

	# Apply the new binding
	_apply_pending_binding(_rebinding_action, pending_event)


func _on_apply_pressed() -> void:
	# Apply all pending bindings
	for action_name in _pending_bindings:
		var event: InputEvent = _pending_bindings[action_name]
		if event != null:
			InputSettings.set_action_key(action_name, event)
		else:
			# Clear the action
			InputMap.action_erase_events(action_name)

	# Save settings
	InputSettings.save_settings()

	# Clear pending changes
	_pending_bindings.clear()
	_has_changes = false
	_update_button_states()

	status_label.text = "Settings saved!"

	# Clear status after a delay
	await get_tree().create_timer(2.0).timeout
	if status_label.text == "Settings saved!":
		status_label.text = ""


func _on_reset_pressed() -> void:
	# Reset to defaults
	InputSettings.reset_to_defaults()

	# Clear pending changes
	_pending_bindings.clear()
	_has_changes = false

	# Refresh the UI
	_refresh_all_buttons()
	_update_button_states()

	status_label.text = "Controls reset to defaults."


func _on_back_pressed() -> void:
	# If there are unsaved changes, discard them
	if _has_changes:
		_pending_bindings.clear()
		_has_changes = false
		_refresh_all_buttons()

	_rebinding_action = ""
	status_label.text = ""

	back_pressed.emit()


func _refresh_all_buttons() -> void:
	for action_name in _action_buttons:
		var button: Button = _action_buttons[action_name]
		button.text = InputSettings.get_action_key_name(action_name)


func _update_button_states() -> void:
	apply_button.disabled = not _has_changes
