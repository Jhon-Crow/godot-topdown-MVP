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
@onready var wall_hit_particles_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/WallHitParticlesContainer/WallHitParticlesCheckbox
@onready var ai_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/AIContainer/AICheckbox
@onready var ai_idle_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/AIIdleContainer/AIIdleCheckbox
@onready var ai_combat_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/AICombatContainer/AICombatCheckbox
@onready var ai_seeking_cover_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/AISeekingCoverContainer/AISeekingCoverCheckbox
@onready var ai_in_cover_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/AIInCoverContainer/AIInCoverCheckbox
@onready var ai_flanking_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/AIFlankingContainer/AIFlankingCheckbox
@onready var ai_suppressed_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/AISuppressedContainer/AISuppressedCheckbox
@onready var ai_retreating_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/AIRetreatingContainer/AIRetreatingCheckbox
@onready var ai_pursuing_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/AIPursuingContainer/AIPursuingCheckbox
@onready var ai_assault_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/AIAssaultContainer/AIAssaultCheckbox
@onready var ai_searching_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/AISearchingContainer/AISearchingCheckbox
@onready var status_label: Label = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/StatusLabel
@onready var back_button: Button = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/BackButton


func _ready() -> void:
	# Connect checkbox signals
	particles_checkbox.toggled.connect(_on_particles_toggled)
	blood_decals_checkbox.toggled.connect(_on_blood_decals_toggled)
	screen_shake_checkbox.toggled.connect(_on_screen_shake_toggled)
	explosion_lights_checkbox.toggled.connect(_on_explosion_lights_toggled)
	wall_hit_particles_checkbox.toggled.connect(_on_wall_hit_particles_toggled)
	ai_checkbox.toggled.connect(_on_ai_toggled)
	ai_idle_checkbox.toggled.connect(func(e): _on_ai_state_toggled("idle", e))
	ai_combat_checkbox.toggled.connect(func(e): _on_ai_state_toggled("combat", e))
	ai_seeking_cover_checkbox.toggled.connect(func(e): _on_ai_state_toggled("seeking_cover", e))
	ai_in_cover_checkbox.toggled.connect(func(e): _on_ai_state_toggled("in_cover", e))
	ai_flanking_checkbox.toggled.connect(func(e): _on_ai_state_toggled("flanking", e))
	ai_suppressed_checkbox.toggled.connect(func(e): _on_ai_state_toggled("suppressed", e))
	ai_retreating_checkbox.toggled.connect(func(e): _on_ai_state_toggled("retreating", e))
	ai_pursuing_checkbox.toggled.connect(func(e): _on_ai_state_toggled("pursuing", e))
	ai_assault_checkbox.toggled.connect(func(e): _on_ai_state_toggled("assault", e))
	ai_searching_checkbox.toggled.connect(func(e): _on_ai_state_toggled("searching", e))
	back_button.pressed.connect(_on_back_pressed)

	# Update UI from current settings
	_update_ui()

	# Connect to settings changes so UI stays in sync
	var perf_settings: Node = get_node_or_null("/root/PerformanceSettings")
	if perf_settings:
		perf_settings.settings_changed.connect(_update_ui)
	var gameplay_settings: Node = get_node_or_null("/root/GameplaySettings")
	if gameplay_settings and gameplay_settings.has_signal("settings_changed"):
		gameplay_settings.settings_changed.connect(_update_ui)

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
	var gameplay_settings: Node = get_node_or_null("/root/GameplaySettings")
	wall_hit_particles_checkbox.button_pressed = gameplay_settings.is_wall_hit_particles_enabled() if gameplay_settings else true
	ai_checkbox.button_pressed = perf_settings.is_ai_enabled()
	ai_idle_checkbox.button_pressed = perf_settings.is_ai_state_idle_enabled()
	ai_combat_checkbox.button_pressed = perf_settings.is_ai_state_combat_enabled()
	ai_seeking_cover_checkbox.button_pressed = perf_settings.is_ai_state_seeking_cover_enabled()
	ai_in_cover_checkbox.button_pressed = perf_settings.is_ai_state_in_cover_enabled()
	ai_flanking_checkbox.button_pressed = perf_settings.is_ai_state_flanking_enabled()
	ai_suppressed_checkbox.button_pressed = perf_settings.is_ai_state_suppressed_enabled()
	ai_retreating_checkbox.button_pressed = perf_settings.is_ai_state_retreating_enabled()
	ai_pursuing_checkbox.button_pressed = perf_settings.is_ai_state_pursuing_enabled()
	ai_assault_checkbox.button_pressed = perf_settings.is_ai_state_assault_enabled()
	ai_searching_checkbox.button_pressed = perf_settings.is_ai_state_searching_enabled()

	# Show which features are currently disabled
	var disabled_parts: Array[String] = []
	if not perf_settings.is_particles_enabled(): disabled_parts.append("Particles")
	if not perf_settings.is_blood_decals_enabled(): disabled_parts.append("Blood decals")
	if not perf_settings.is_screen_shake_enabled(): disabled_parts.append("Screen shake")
	if not perf_settings.is_explosion_lights_enabled(): disabled_parts.append("Explosion lights")
	var gs: Node = get_node_or_null("/root/GameplaySettings")
	if gs and not gs.is_wall_hit_particles_enabled(): disabled_parts.append("Wall hit particles")
	if not perf_settings.is_ai_enabled(): disabled_parts.append("AI")
	if not perf_settings.is_ai_state_idle_enabled(): disabled_parts.append("AI:IDLE")
	if not perf_settings.is_ai_state_combat_enabled(): disabled_parts.append("AI:COMBAT")
	if not perf_settings.is_ai_state_seeking_cover_enabled(): disabled_parts.append("AI:SEEKING_COVER")
	if not perf_settings.is_ai_state_in_cover_enabled(): disabled_parts.append("AI:IN_COVER")
	if not perf_settings.is_ai_state_flanking_enabled(): disabled_parts.append("AI:FLANKING")
	if not perf_settings.is_ai_state_suppressed_enabled(): disabled_parts.append("AI:SUPPRESSED")
	if not perf_settings.is_ai_state_retreating_enabled(): disabled_parts.append("AI:RETREATING")
	if not perf_settings.is_ai_state_pursuing_enabled(): disabled_parts.append("AI:PURSUING")
	if not perf_settings.is_ai_state_assault_enabled(): disabled_parts.append("AI:ASSAULT")
	if not perf_settings.is_ai_state_searching_enabled(): disabled_parts.append("AI:SEARCHING")

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


func _on_wall_hit_particles_toggled(enabled: bool) -> void:
	var gameplay_settings: Node = get_node_or_null("/root/GameplaySettings")
	if gameplay_settings:
		gameplay_settings.set_wall_hit_particles_enabled(enabled)
	_update_ui()


func _on_ai_toggled(enabled: bool) -> void:
	var perf_settings: Node = get_node_or_null("/root/PerformanceSettings")
	if perf_settings:
		perf_settings.set_ai_enabled(enabled)
	_update_ui()


func _on_ai_state_toggled(state_name: String, enabled: bool) -> void:
	var perf_settings: Node = get_node_or_null("/root/PerformanceSettings")
	if perf_settings == null:
		return
	match state_name:
		"idle": perf_settings.set_ai_state_idle_enabled(enabled)
		"combat": perf_settings.set_ai_state_combat_enabled(enabled)
		"seeking_cover": perf_settings.set_ai_state_seeking_cover_enabled(enabled)
		"in_cover": perf_settings.set_ai_state_in_cover_enabled(enabled)
		"flanking": perf_settings.set_ai_state_flanking_enabled(enabled)
		"suppressed": perf_settings.set_ai_state_suppressed_enabled(enabled)
		"retreating": perf_settings.set_ai_state_retreating_enabled(enabled)
		"pursuing": perf_settings.set_ai_state_pursuing_enabled(enabled)
		"assault": perf_settings.set_ai_state_assault_enabled(enabled)
		"searching": perf_settings.set_ai_state_searching_enabled(enabled)
	_update_ui()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func _on_back_pressed() -> void:
	back_pressed.emit()
