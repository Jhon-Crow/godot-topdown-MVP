extends CanvasLayer
## Experimental features menu.
##
## Allows the player to enable/disable experimental game features.
## All experimental features are disabled by default.

## Signal emitted when the back button is pressed.
signal back_pressed

## Reference to UI elements.
@onready var fov_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/FOVContainer/FOVCheckbox
@onready var back_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/BackButton
@onready var status_label: Label = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/StatusLabel


func _ready() -> void:
	# Connect button signals
	fov_checkbox.toggled.connect(_on_fov_toggled)
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

	# Update checkbox state (inverted: checked = FOV disabled)
	fov_checkbox.button_pressed = not experimental_settings.is_fov_enabled()

	# Update status label
	if experimental_settings.is_fov_enabled():
		status_label.text = "FOV enabled: Enemies see in 100 degree cone"
	else:
		status_label.text = "FOV disabled: Enemies have 360 degree vision"


func _on_fov_toggled(disabled: bool) -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		# Inverted: checkbox checked = FOV disabled
		experimental_settings.set_fov_enabled(not disabled)
	_update_ui()


func _on_back_pressed() -> void:
	back_pressed.emit()


func _on_settings_changed() -> void:
	_update_ui()
