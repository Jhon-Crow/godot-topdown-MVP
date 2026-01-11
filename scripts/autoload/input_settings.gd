extends Node
## Autoload singleton for managing input settings and key bindings.
##
## Handles saving and loading key bindings from a configuration file.
## Provides functionality for remapping controls and resetting to defaults.

## Path to the settings configuration file.
const SETTINGS_PATH := "user://input_settings.cfg"

## Configuration file for storing settings.
var _config := ConfigFile.new()

## List of action names that can be remapped.
var remappable_actions: Array[String] = [
	"move_up",
	"move_down",
	"move_left",
	"move_right",
	"shoot",
	"pause"
]

## Default key bindings stored at startup before any user modifications.
var _default_bindings: Dictionary = {}

## Signal emitted when controls are changed.
signal controls_changed


func _ready() -> void:
	_store_default_bindings()
	_ensure_pause_action_exists()
	load_settings()


## Ensures the pause action exists in InputMap (may not be defined by default).
func _ensure_pause_action_exists() -> void:
	if not InputMap.has_action("pause"):
		InputMap.add_action("pause")
		var event := InputEventKey.new()
		event.physical_keycode = KEY_ESCAPE
		InputMap.action_add_event("pause", event)


## Stores the default bindings from InputMap at startup.
func _store_default_bindings() -> void:
	for action_name in remappable_actions:
		if InputMap.has_action(action_name):
			var events := InputMap.action_get_events(action_name)
			_default_bindings[action_name] = events.duplicate()


## Loads settings from the configuration file.
func load_settings() -> void:
	var err := _config.load(SETTINGS_PATH)
	if err != OK:
		return  # No settings file exists yet, use defaults

	for action_name in remappable_actions:
		if not _config.has_section_key("controls", action_name):
			continue

		var saved_key: int = _config.get_value("controls", action_name, 0)
		if saved_key == 0:
			continue

		# Clear existing events and add the saved one
		_set_action_key(action_name, saved_key)

	controls_changed.emit()


## Saves current settings to the configuration file.
func save_settings() -> void:
	for action_name in remappable_actions:
		var events := InputMap.action_get_events(action_name)
		for event in events:
			if event is InputEventKey:
				var key_event: InputEventKey = event
				var keycode := key_event.physical_keycode
				if keycode == 0:
					keycode = key_event.keycode
				_config.set_value("controls", action_name, keycode)
				break
			elif event is InputEventMouseButton:
				# For mouse buttons, save as negative values to distinguish
				var mouse_event: InputEventMouseButton = event
				_config.set_value("controls", action_name, -mouse_event.button_index)
				break

	var err := _config.save(SETTINGS_PATH)
	if err != OK:
		push_error("Failed to save input settings: " + str(err))


## Sets a new key for an action.
func set_action_key(action_name: String, event: InputEvent) -> void:
	if not action_name in remappable_actions:
		return

	# Remove the old events
	InputMap.action_erase_events(action_name)

	# Add the new event
	InputMap.action_add_event(action_name, event)

	controls_changed.emit()


## Internal method to set action key from physical keycode.
func _set_action_key(action_name: String, keycode: int) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

	InputMap.action_erase_events(action_name)

	if keycode < 0:
		# Negative values indicate mouse buttons
		var mouse_event := InputEventMouseButton.new()
		mouse_event.button_index = -keycode
		mouse_event.pressed = true
		InputMap.action_add_event(action_name, mouse_event)
	else:
		var key_event := InputEventKey.new()
		key_event.physical_keycode = keycode
		InputMap.action_add_event(action_name, key_event)


## Resets all controls to their default values.
func reset_to_defaults() -> void:
	for action_name in remappable_actions:
		if action_name in _default_bindings:
			InputMap.action_erase_events(action_name)
			for event in _default_bindings[action_name]:
				InputMap.action_add_event(action_name, event)

	save_settings()
	controls_changed.emit()


## Gets the display name for an input event.
func get_event_name(event: InputEvent) -> String:
	if event is InputEventKey:
		var key_event: InputEventKey = event
		var keycode := key_event.physical_keycode
		if keycode == 0:
			keycode = key_event.keycode
		return OS.get_keycode_string(keycode)
	elif event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		match mouse_event.button_index:
			MOUSE_BUTTON_LEFT:
				return "Left Mouse"
			MOUSE_BUTTON_RIGHT:
				return "Right Mouse"
			MOUSE_BUTTON_MIDDLE:
				return "Middle Mouse"
			MOUSE_BUTTON_WHEEL_UP:
				return "Mouse Wheel Up"
			MOUSE_BUTTON_WHEEL_DOWN:
				return "Mouse Wheel Down"
			_:
				return "Mouse " + str(mouse_event.button_index)
	return "Unknown"


## Gets the first event assigned to an action.
func get_action_event(action_name: String) -> InputEvent:
	if not InputMap.has_action(action_name):
		return null
	var events := InputMap.action_get_events(action_name)
	if events.size() > 0:
		return events[0]
	return null


## Gets the display name for an action's current binding.
func get_action_key_name(action_name: String) -> String:
	var event := get_action_event(action_name)
	if event:
		return get_event_name(event)
	return "Not Set"


## Gets a human-readable name for an action.
func get_action_display_name(action_name: String) -> String:
	match action_name:
		"move_up":
			return "Move Up"
		"move_down":
			return "Move Down"
		"move_left":
			return "Move Left"
		"move_right":
			return "Move Right"
		"shoot":
			return "Shoot"
		"pause":
			return "Pause"
		_:
			return action_name.capitalize().replace("_", " ")


## Checks if a key is already assigned to another action.
## Returns the action name if conflict exists, empty string otherwise.
func check_key_conflict(event: InputEvent, exclude_action: String = "") -> String:
	for action_name in remappable_actions:
		if action_name == exclude_action:
			continue

		var action_event := get_action_event(action_name)
		if action_event == null:
			continue

		if _events_match(event, action_event):
			return action_name

	return ""


## Checks if two input events match.
func _events_match(event1: InputEvent, event2: InputEvent) -> bool:
	if event1 is InputEventKey and event2 is InputEventKey:
		var key1: InputEventKey = event1
		var key2: InputEventKey = event2
		var keycode1 := key1.physical_keycode if key1.physical_keycode != 0 else key1.keycode
		var keycode2 := key2.physical_keycode if key2.physical_keycode != 0 else key2.keycode
		return keycode1 == keycode2
	elif event1 is InputEventMouseButton and event2 is InputEventMouseButton:
		var mouse1: InputEventMouseButton = event1
		var mouse2: InputEventMouseButton = event2
		return mouse1.button_index == mouse2.button_index
	return false
