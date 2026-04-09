extends CanvasLayer
## Optimization settings menu (Issue #1145, #1487).
##
## Provides settings that control performance vs. visual quality trade-offs:
## - Dust particle quality: Full / Half / Off

## Signal emitted when the back button is pressed.
signal back_pressed

## Reference to UI elements.
@onready var dust_quality_option: OptionButton = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/DustQualityContainer/DustQualityOption
@onready var back_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/BackButton


func _ready() -> void:
	# Setup tooltips and label behaviour for settings rows (Issue #1200)
	_setup_row_hover($MenuContainer/PanelContainer/MarginContainer/VBoxContainer/DustQualityContainer,
			"Dust Particles")

	# Populate dust quality option button
	_setup_dust_quality_option()

	# Connect button signals
	dust_quality_option.item_selected.connect(_on_dust_quality_selected)
	back_button.pressed.connect(_on_back_pressed)

	# Update UI from current settings
	_update_ui()

	# Connect to settings changes (in case settings change from elsewhere)
	var gameplay_settings: Node = get_node_or_null("/root/GameplaySettings")
	if gameplay_settings:
		gameplay_settings.settings_changed.connect(_update_ui)

	# Set process mode to allow input while paused
	process_mode = Node.PROCESS_MODE_ALWAYS


## Populate the dust quality OptionButton with items (Issue #1487).
func _setup_dust_quality_option() -> void:
	var gs: Node = get_node_or_null("/root/GameplaySettings")
	dust_quality_option.clear()
	dust_quality_option.add_item("Full", gs.DUST_QUALITY_FULL if gs else 0)
	dust_quality_option.add_item("Half", gs.DUST_QUALITY_HALF if gs else 1)
	dust_quality_option.add_item("Off", gs.DUST_QUALITY_OFF if gs else 2)


func _update_ui() -> void:
	var gameplay_settings: Node = get_node_or_null("/root/GameplaySettings")
	if gameplay_settings == null:
		return

	# Block signals while updating to avoid feedback loops
	dust_quality_option.set_block_signals(true)
	dust_quality_option.select(gameplay_settings.get_dust_quality())
	dust_quality_option.set_block_signals(false)


func _on_dust_quality_selected(index: int) -> void:
	var gameplay_settings: Node = get_node_or_null("/root/GameplaySettings")
	if gameplay_settings:
		gameplay_settings.set_dust_quality(index)
	_update_ui()


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
