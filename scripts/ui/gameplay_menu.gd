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
@onready var aim_assist_toggle: CheckButton = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/AimAssistContainer/AimAssistToggle
@onready var back_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/BackButton


func _ready() -> void:
	# Setup tooltips and label behaviour for settings rows (Issue #1200)
	_setup_row_hover($MenuContainer/PanelContainer/MarginContainer/VBoxContainer/BloodContainer,
			tr("BLOOD_AMOUNT"))
	_setup_row_hover($MenuContainer/PanelContainer/MarginContainer/VBoxContainer/WeaponHintsContainer,
			tr("WEAPON_HINTS"))
	_setup_row_hover($MenuContainer/PanelContainer/MarginContainer/VBoxContainer/AimAssistContainer,
			tr("REVOLVER_AIM_ASSIST"))

	# Connect button and slider signals
	blood_slider.value_changed.connect(_on_blood_amount_changed)
	_setup_weapon_hints_option()
	weapon_hints_option.item_selected.connect(_on_weapon_hints_selected)
	aim_assist_toggle.toggled.connect(_on_aim_assist_toggled)
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

	# Aim assist toggle (Issue #1332)
	aim_assist_toggle.set_block_signals(true)
	aim_assist_toggle.button_pressed = gameplay_settings.is_revolver_aim_assist_enabled()
	aim_assist_toggle.set_block_signals(false)


func _on_blood_amount_changed(value: float) -> void:
	var gameplay_settings: Node = get_node_or_null("/root/GameplaySettings")
	if gameplay_settings:
		gameplay_settings.set_blood_amount(value / 100.0)
	blood_value_label.text = "%d%%" % int(value)


## Setup the weapon hints option button with items.
func _setup_weapon_hints_option() -> void:
	weapon_hints_option.clear()
	weapon_hints_option.add_item(tr("WEAPON_HINTS_ALWAYS"), 0)
	weapon_hints_option.add_item(tr("WEAPON_HINTS_FIRST_TIME"), 1)
	weapon_hints_option.add_item(tr("WEAPON_HINTS_NEVER"), 2)

	# Select current mode from settings
	var weapon_hints_settings: Node = get_node_or_null("/root/WeaponHintsSettings")
	if weapon_hints_settings:
		var current_mode: int = weapon_hints_settings.get_hint_mode()
		weapon_hints_option.select(current_mode)
	else:
		# Default to "Always" if settings not available
		weapon_hints_option.select(0)


## Called when the revolver aim assist toggle is changed (Issue #1332).
func _on_aim_assist_toggled(enabled: bool) -> void:
	var gameplay_settings: Node = get_node_or_null("/root/GameplaySettings")
	if gameplay_settings:
		gameplay_settings.set_revolver_aim_assist_enabled(enabled)


## Called when weapon hints option is changed.
func _on_weapon_hints_selected(index: int) -> void:
	var weapon_hints_settings: Node = get_node_or_null("/root/WeaponHintsSettings")
	if weapon_hints_settings:
		weapon_hints_settings.set_hint_mode(index)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func _on_back_pressed() -> void:
	back_pressed.emit()


## Semi-transparent background colour drawn over a settings row on hover (Issue #1200).
const ROW_HOVER_BG: Color = Color(1.0, 1.0, 1.0, 0.08)

## Tracks which Control nodes currently have a hover background drawn on them.
var _row_hover_bg: Dictionary = {}


## Draw the hover background rect for a registered row node.
func _draw_row_bg(node: Control) -> void:
	if _row_hover_bg.get(node, false):
		node.draw_rect(Rect2(Vector2.ZERO, node.size), ROW_HOVER_BG)


## Setup tooltip, hover highlight, and label behaviour for a settings row (Issue #1200).
## @param container   The HBoxContainer that holds the label + interactive control.
## @param tooltip     Short name shown in the tooltip and applied to all child nodes.
## @param description Optional sibling Label with the long description text.
##                    When provided it receives the same tooltip, hover highlight,
##                    and click-forwarding as the main container.
func _setup_row_hover(container: Control, tooltip: String,
		description: Control = null) -> void:
	container.tooltip_text = tooltip
	container.mouse_filter = Control.MOUSE_FILTER_STOP
	for child in container.get_children():
		if child is Control:
			child.tooltip_text = tooltip
	_row_hover_bg[container] = false
	container.draw.connect(_draw_row_bg.bind(container))
	container.mouse_entered.connect(_on_row_hovered.bind(container, description, true))
	container.mouse_exited.connect(_on_row_hovered.bind(container, description, false))
	container.gui_input.connect(_on_row_gui_input.bind(container))
	if description != null:
		description.tooltip_text = tooltip
		description.mouse_filter = Control.MOUSE_FILTER_STOP
		_row_hover_bg[description] = false
		description.draw.connect(_draw_row_bg.bind(description))
		description.mouse_entered.connect(_on_row_hovered.bind(container, description, true))
		description.mouse_exited.connect(_on_row_hovered.bind(container, description, false))
		description.gui_input.connect(_on_row_gui_input.bind(container))


## Apply or remove hover background on the row container and its description label.
func _on_row_hovered(container: Control, description: Control,
		hovered: bool) -> void:
	_row_hover_bg[container] = hovered
	container.queue_redraw()
	if description != null:
		_row_hover_bg[description] = hovered
		description.queue_redraw()


## Forward a left-click on the row container to the first interactive control inside.
func _on_row_gui_input(event: InputEvent, container: Control) -> void:
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		for child in container.get_children():
			if child is CheckButton:
				# Setting button_pressed automatically emits toggled signal.
				child.button_pressed = not child.button_pressed
				container.accept_event()
				return
			if child is Button:
				child.pressed.emit()
				container.accept_event()
				return
			if child is OptionButton:
				child.show_popup()
				container.accept_event()
				return
