extends CanvasLayer
## Sound settings menu (Issue #839).
##
## Allows the player to adjust:
## - Effects volume (громкость эффектов): all sound effects
## - Music volume (громкость музыки): background music

## Signal emitted when the back button is pressed.
signal back_pressed

## Reference to UI elements.
@onready var effects_slider: HSlider = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/EffectsContainer/EffectsSlider
@onready var effects_value_label: Label = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/EffectsContainer/EffectsValueLabel
@onready var music_slider: HSlider = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/MusicContainer/MusicSlider
@onready var music_value_label: Label = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/MusicContainer/MusicValueLabel
@onready var back_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/BackButton


func _ready() -> void:
	# Setup tooltips and label behaviour for settings rows (Issue #1200)
	_setup_row_hover($MenuContainer/PanelContainer/MarginContainer/VBoxContainer/EffectsContainer,
			"Effects Volume")
	_setup_row_hover($MenuContainer/PanelContainer/MarginContainer/VBoxContainer/MusicContainer,
			"Music Volume")

	# Connect button and slider signals
	effects_slider.value_changed.connect(_on_effects_volume_changed)
	music_slider.value_changed.connect(_on_music_volume_changed)
	back_button.pressed.connect(_on_back_pressed)

	# Update sliders from current settings
	_update_ui()

	# Connect to settings changes (in case settings change from elsewhere)
	var sound_settings: Node = get_node_or_null("/root/SoundSettings")
	if sound_settings:
		sound_settings.settings_changed.connect(_update_ui)

	# Set process mode to allow input while paused
	process_mode = Node.PROCESS_MODE_ALWAYS


func _update_ui() -> void:
	var sound_settings: Node = get_node_or_null("/root/SoundSettings")
	if sound_settings == null:
		return

	# Block signals while updating to avoid feedback loops
	effects_slider.set_block_signals(true)
	effects_slider.value = sound_settings.get_effects_volume() * 100.0
	effects_slider.set_block_signals(false)
	effects_value_label.text = "%d%%" % int(sound_settings.get_effects_volume() * 100.0)

	music_slider.set_block_signals(true)
	music_slider.value = sound_settings.get_music_volume() * 100.0
	music_slider.set_block_signals(false)
	music_value_label.text = "%d%%" % int(sound_settings.get_music_volume() * 100.0)


func _on_effects_volume_changed(value: float) -> void:
	var sound_settings: Node = get_node_or_null("/root/SoundSettings")
	if sound_settings:
		sound_settings.set_effects_volume(value / 100.0)
	effects_value_label.text = "%d%%" % int(value)


func _on_music_volume_changed(value: float) -> void:
	var sound_settings: Node = get_node_or_null("/root/SoundSettings")
	if sound_settings:
		sound_settings.set_music_volume(value / 100.0)
	music_value_label.text = "%d%%" % int(value)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


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
