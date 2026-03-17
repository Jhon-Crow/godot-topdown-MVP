extends CanvasLayer
## Gameplay settings menu (Issue #1090).
##
## Allows the player to adjust gameplay visual preferences:
## - Blood amount (количество крови): slider controlling blood decals per hit

## Signal emitted when the back button is pressed.
signal back_pressed

## Reference to UI elements.
@onready var blood_slider: HSlider = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/BloodContainer/BloodSlider
@onready var blood_value_label: Label = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/BloodContainer/BloodValueLabel
@onready var back_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/BackButton


func _ready() -> void:
	# Connect button and slider signals
	blood_slider.value_changed.connect(_on_blood_amount_changed)
	back_button.pressed.connect(_on_back_pressed)

	# Update slider from current settings
	_update_ui()

	# Connect to settings changes (in case settings change from elsewhere)
	var gameplay_settings: Node = get_node_or_null("/root/GameplaySettings")
	if gameplay_settings:
		gameplay_settings.settings_changed.connect(_update_ui)

	# Set process mode to allow input while paused
	process_mode = Node.PROCESS_MODE_ALWAYS


func _update_ui() -> void:
	var gameplay_settings: Node = get_node_or_null("/root/GameplaySettings")
	if gameplay_settings == null:
		return

	# Block signals while updating to avoid feedback loops
	blood_slider.set_block_signals(true)
	blood_slider.value = gameplay_settings.get_blood_amount() * 100.0
	blood_slider.set_block_signals(false)
	blood_value_label.text = "%d%%" % int(gameplay_settings.get_blood_amount() * 100.0)


func _on_blood_amount_changed(value: float) -> void:
	var gameplay_settings: Node = get_node_or_null("/root/GameplaySettings")
	if gameplay_settings:
		gameplay_settings.set_blood_amount(value / 100.0)
	blood_value_label.text = "%d%%" % int(value)


func _on_back_pressed() -> void:
	back_pressed.emit()
