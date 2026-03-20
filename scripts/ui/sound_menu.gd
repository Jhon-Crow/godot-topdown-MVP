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
