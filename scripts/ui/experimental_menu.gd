extends CanvasLayer
## Experimental features menu.
##
## Allows the player to enable/disable experimental game features.
## All experimental features are disabled by default.

## Signal emitted when the back button is pressed.
signal back_pressed

## Reference to UI elements.
@onready var fov_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/FOVContainer/FOVCheckbox
@onready var complex_grenade_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/ComplexGrenadeContainer/ComplexGrenadeCheckbox
@onready var back_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/BackButton
@onready var status_label: Label = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/StatusLabel


func _ready() -> void:
	# Connect button signals
	fov_checkbox.toggled.connect(_on_fov_toggled)
	complex_grenade_checkbox.toggled.connect(_on_complex_grenade_toggled)
	back_button.pressed.connect(_on_back_pressed)

	# Update UI based on current settings
	_update_ui()

	# Connect to settings changes
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		experimental_settings.settings_changed.connect(_on_settings_changed)

	# Set process mode to allow input while paused
	process_mode = Node.PROCESS_MODE_ALWAYS


func _update_ui() -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings == null:
		status_label.text = "Error: ExperimentalSettings not found"
		return

	# Update checkbox states
	fov_checkbox.button_pressed = experimental_settings.is_fov_enabled()
	complex_grenade_checkbox.button_pressed = experimental_settings.is_complex_grenade_throwing()

	# Update status label - show status of both settings
	var status_parts: Array[String] = []
	if experimental_settings.is_fov_enabled():
		status_parts.append("FOV: 100° cone")
	if experimental_settings.is_complex_grenade_throwing():
		status_parts.append("Grenades: complex throwing")

	if status_parts.is_empty():
		status_label.text = "All experimental features disabled"
	else:
		status_label.text = "Enabled: " + ", ".join(status_parts)


func _on_fov_toggled(enabled: bool) -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		experimental_settings.set_fov_enabled(enabled)
	_update_ui()


func _on_complex_grenade_toggled(enabled: bool) -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		experimental_settings.set_complex_grenade_throwing(enabled)
	_update_ui()


func _on_back_pressed() -> void:
	back_pressed.emit()


func _on_settings_changed() -> void:
	_update_ui()
