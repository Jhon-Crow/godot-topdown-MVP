extends CanvasLayer
## Gameplay settings menu.
##
## Provides settings that affect gameplay mechanics:
## - Blood amount (количество крови): slider controlling blood decals per hit (Issue #1090)
## - Weapon hints display mode (Issue #809): Always / First time only / Never

## Signal emitted when the back button is pressed.
signal back_pressed

## Reference to UI elements.
@onready var blood_slider: HSlider = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/BloodContainer/BloodSlider
@onready var blood_value_label: Label = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/BloodContainer/BloodValueLabel
@onready var weapon_hints_option: OptionButton = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/WeaponHintsContainer/WeaponHintsOption
@onready var back_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/BackButton


func _ready() -> void:
	# Connect button and slider signals
	blood_slider.value_changed.connect(_on_blood_amount_changed)
	_setup_weapon_hints_option()
	weapon_hints_option.item_selected.connect(_on_weapon_hints_selected)
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


## Setup the weapon hints option button with items.
func _setup_weapon_hints_option() -> void:
	weapon_hints_option.clear()
	weapon_hints_option.add_item("Always", 0)
	weapon_hints_option.add_item("First time only", 1)
	weapon_hints_option.add_item("Never", 2)

	# Select current mode from settings
	var weapon_hints_settings: Node = get_node_or_null("/root/WeaponHintsSettings")
	if weapon_hints_settings:
		var current_mode: int = weapon_hints_settings.get_hint_mode()
		weapon_hints_option.select(current_mode)
	else:
		# Default to "Always" if settings not available
		weapon_hints_option.select(0)


## Called when weapon hints option is changed.
func _on_weapon_hints_selected(index: int) -> void:
	var weapon_hints_settings: Node = get_node_or_null("/root/WeaponHintsSettings")
	if weapon_hints_settings:
		weapon_hints_settings.set_hint_mode(index)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func _on_back_pressed() -> void:
	back_pressed.emit()
