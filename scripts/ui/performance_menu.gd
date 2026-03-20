extends CanvasLayer
## Performance settings menu (Issue #1186).
##
## Provides toggles for every subsystem that can affect performance,
## making it easy to isolate bottlenecks during profiling.
## All features are enabled by default - disabling does not change
## default gameplay.

## Signal emitted when the back button is pressed.
signal back_pressed

## Reference to UI elements.
@onready var particles_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/ParticlesContainer/ParticlesCheckbox
@onready var blood_decals_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/BloodDecalsContainer/BloodDecalsCheckbox
@onready var screen_shake_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/ScreenShakeContainer/ScreenShakeCheckbox
@onready var explosion_lights_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/ExplosionLightsContainer/ExplosionLightsCheckbox
@onready var ai_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/AIContainer/AICheckbox
@onready var status_label: Label = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/StatusLabel
@onready var back_button: Button = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/BackButton


func _ready() -> void:
	# Connect checkbox signals
	particles_checkbox.toggled.connect(_on_particles_toggled)
	blood_decals_checkbox.toggled.connect(_on_blood_decals_toggled)
	screen_shake_checkbox.toggled.connect(_on_screen_shake_toggled)
	explosion_lights_checkbox.toggled.connect(_on_explosion_lights_toggled)
	ai_checkbox.toggled.connect(_on_ai_toggled)
	back_button.pressed.connect(_on_back_pressed)

	# Update UI from current settings
	_update_ui()

	# Connect to settings changes so UI stays in sync
	var perf_settings: Node = get_node_or_null("/root/PerformanceSettings")
	if perf_settings:
		perf_settings.settings_changed.connect(_update_ui)

	# Allow input while paused
	process_mode = Node.PROCESS_MODE_ALWAYS


func _update_ui() -> void:
	var perf_settings: Node = get_node_or_null("/root/PerformanceSettings")
	if perf_settings == null:
		status_label.text = "Error: PerformanceSettings not found"
		return

	particles_checkbox.button_pressed = perf_settings.is_particles_enabled()
	blood_decals_checkbox.button_pressed = perf_settings.is_blood_decals_enabled()
	screen_shake_checkbox.button_pressed = perf_settings.is_screen_shake_enabled()
	explosion_lights_checkbox.button_pressed = perf_settings.is_explosion_lights_enabled()
	ai_checkbox.button_pressed = perf_settings.is_ai_enabled()

	# Show which features are currently disabled
	var disabled_parts: Array[String] = []
	if not perf_settings.is_particles_enabled():
		disabled_parts.append("Particles")
	if not perf_settings.is_blood_decals_enabled():
		disabled_parts.append("Blood decals")
	if not perf_settings.is_screen_shake_enabled():
		disabled_parts.append("Screen shake")
	if not perf_settings.is_explosion_lights_enabled():
		disabled_parts.append("Explosion lights")
	if not perf_settings.is_ai_enabled():
		disabled_parts.append("AI")

	if disabled_parts.is_empty():
		status_label.text = "All performance features enabled"
	else:
		status_label.text = "Disabled: " + ", ".join(disabled_parts)


func _on_particles_toggled(enabled: bool) -> void:
	var perf_settings: Node = get_node_or_null("/root/PerformanceSettings")
	if perf_settings:
		perf_settings.set_particles_enabled(enabled)
	_update_ui()


func _on_blood_decals_toggled(enabled: bool) -> void:
	var perf_settings: Node = get_node_or_null("/root/PerformanceSettings")
	if perf_settings:
		perf_settings.set_blood_decals_enabled(enabled)
	_update_ui()


func _on_screen_shake_toggled(enabled: bool) -> void:
	var perf_settings: Node = get_node_or_null("/root/PerformanceSettings")
	if perf_settings:
		perf_settings.set_screen_shake_enabled(enabled)
	_update_ui()


func _on_explosion_lights_toggled(enabled: bool) -> void:
	var perf_settings: Node = get_node_or_null("/root/PerformanceSettings")
	if perf_settings:
		perf_settings.set_explosion_lights_enabled(enabled)
	_update_ui()


func _on_ai_toggled(enabled: bool) -> void:
	var perf_settings: Node = get_node_or_null("/root/PerformanceSettings")
	if perf_settings:
		perf_settings.set_ai_enabled(enabled)
	_update_ui()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func _on_back_pressed() -> void:
	back_pressed.emit()
