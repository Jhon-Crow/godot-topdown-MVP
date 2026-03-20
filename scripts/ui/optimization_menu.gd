extends CanvasLayer
## Optimization settings menu (Issue #1145).
##
## Provides settings that control performance vs. visual quality trade-offs:
## - Wall hit particles: toggle dust effect when bullets hit walls

## Signal emitted when the back button is pressed.
signal back_pressed

## Reference to UI elements.
@onready var wall_hit_particles_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/WallHitParticlesContainer/WallHitParticlesCheckbox
@onready var back_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/BackButton


func _ready() -> void:
	# Setup tooltips and label behaviour for settings rows (Issue #1200)
	_setup_row_hover($MenuContainer/PanelContainer/MarginContainer/VBoxContainer/WallHitParticlesContainer,
			"Wall Hit Particles")

	# Connect button signals
	wall_hit_particles_checkbox.toggled.connect(_on_wall_hit_particles_toggled)
	back_button.pressed.connect(_on_back_pressed)

	# Update UI from current settings
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
	wall_hit_particles_checkbox.set_block_signals(true)
	wall_hit_particles_checkbox.button_pressed = gameplay_settings.is_wall_hit_particles_enabled()
	wall_hit_particles_checkbox.set_block_signals(false)


func _on_wall_hit_particles_toggled(enabled: bool) -> void:
	var gameplay_settings: Node = get_node_or_null("/root/GameplaySettings")
	if gameplay_settings:
		gameplay_settings.set_wall_hit_particles_enabled(enabled)
	_update_ui()


func _on_back_pressed() -> void:
	back_pressed.emit()


## Hover highlight colour applied to a settings row when the cursor is over it.
## Matches the brightness boost used by Button's hover state in the neon theme.
const ROW_HOVER_MODULATE: Color = Color(1.35, 1.35, 1.35, 1.0)

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
	container.mouse_entered.connect(_on_row_hovered.bind(container, description, true))
	container.mouse_exited.connect(_on_row_hovered.bind(container, description, false))
	container.gui_input.connect(_on_row_gui_input.bind(container))
	if description != null:
		description.tooltip_text = tooltip
		description.mouse_filter = Control.MOUSE_FILTER_STOP
		description.mouse_entered.connect(_on_row_hovered.bind(container, description, true))
		description.mouse_exited.connect(_on_row_hovered.bind(container, description, false))
		description.gui_input.connect(_on_row_gui_input.bind(container))


## Apply or remove hover highlight on the row container and its description label.
func _on_row_hovered(container: Control, description: Control,
		hovered: bool) -> void:
	var tint: Color = ROW_HOVER_MODULATE if hovered else Color.WHITE
	container.self_modulate = tint
	if description != null:
		description.self_modulate = tint


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
