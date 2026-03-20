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


## Setup tooltip and label behaviour for a settings row container (Issue #1200).
## Sets a short name tooltip on the container and all its children so it appears
## when hovering anywhere over the row. Also makes the container act as a label:
## clicking anywhere on the row triggers the first interactive control inside
## (CheckButton, Button, or OptionButton).
func _setup_row_hover(container: Control, tooltip: String) -> void:
	container.tooltip_text = tooltip
	container.mouse_filter = Control.MOUSE_FILTER_STOP
	for child in container.get_children():
		if child is Control:
			child.tooltip_text = tooltip
	container.gui_input.connect(_on_row_gui_input.bind(container))


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
