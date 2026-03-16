extends CanvasLayer
## Gameplay settings menu.
##
## Provides settings that affect gameplay mechanics, such as weapon hints display mode.
## Issue #809: добавь обучение новому оружию (add weapon training).

## Signal emitted when the back button is pressed.
signal back_pressed

## Reference to UI elements.
@onready var weapon_hints_option: OptionButton = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/WeaponHintsContainer/WeaponHintsOption
@onready var back_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/BackButton


func _ready() -> void:
	_setup_weapon_hints_option()
	weapon_hints_option.item_selected.connect(_on_weapon_hints_selected)
	back_button.pressed.connect(_on_back_pressed)

	# Set process mode to allow input while paused
	process_mode = Node.PROCESS_MODE_ALWAYS


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
		# Default to "First time only" if settings not available
		weapon_hints_option.select(1)


## Called when weapon hints option is changed.
func _on_weapon_hints_selected(index: int) -> void:
	var weapon_hints_settings: Node = get_node_or_null("/root/WeaponHintsSettings")
	if weapon_hints_settings:
		weapon_hints_settings.set_hint_mode(index)


func _on_back_pressed() -> void:
	back_pressed.emit()
