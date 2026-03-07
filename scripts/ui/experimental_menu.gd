extends CanvasLayer
## Experimental features menu.
##
## Allows the player to enable/disable experimental game features.
## All experimental features are disabled by default.
## Note: Night Mode (realistic visibility) has been moved to the Difficulty menu.

## Signal emitted when the back button is pressed.
signal back_pressed

## Reference to UI elements.
@onready var fov_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/FOVContainer/FOVCheckbox
@onready var complex_grenade_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/ComplexGrenadeContainer/ComplexGrenadeCheckbox
@onready var ai_prediction_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/AIPredictionContainer/AIPredictionCheckbox
@onready var debug_mode_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/DebugModeContainer/DebugModeCheckbox
@onready var invincibility_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/InvincibilityContainer/InvincibilityCheckbox
@onready var replay_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/ReplayContainer/ReplayCheckbox
@onready var logging_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/LoggingContainer/LoggingCheckbox
@onready var enemy_flashlight_blinding_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/EnemyFlashlightBlindingContainer/EnemyFlashlightBlindingCheckbox
@onready var fps_counter_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/FpsCounterContainer/FpsCounterCheckbox
@onready var fps_drop_logging_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/FpsDropLoggingContainer/FpsDropLoggingCheckbox
@onready var all_weapons_unlocked_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/AllWeaponsUnlockedContainer/AllWeaponsUnlockedCheckbox
@onready var ricochet_points_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/RicochetPointsContainer/RicochetPointsCheckbox
@onready var delete_saves_button: Button = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/DeleteSavesContainer/DeleteSavesButton
@onready var back_button: Button = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/BackButton
@onready var status_label: Label = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/StatusLabel


func _ready() -> void:
	# Connect button signals
	fov_checkbox.toggled.connect(_on_fov_toggled)
	complex_grenade_checkbox.toggled.connect(_on_complex_grenade_toggled)
	ai_prediction_checkbox.toggled.connect(_on_ai_prediction_toggled)
	debug_mode_checkbox.toggled.connect(_on_debug_mode_toggled)
	invincibility_checkbox.toggled.connect(_on_invincibility_toggled)
	replay_checkbox.toggled.connect(_on_replay_toggled)
	logging_checkbox.toggled.connect(_on_logging_toggled)
	enemy_flashlight_blinding_checkbox.toggled.connect(_on_enemy_flashlight_blinding_toggled)
	fps_counter_checkbox.toggled.connect(_on_fps_counter_toggled)
	fps_drop_logging_checkbox.toggled.connect(_on_fps_drop_logging_toggled)
	all_weapons_unlocked_checkbox.toggled.connect(_on_all_weapons_unlocked_toggled)
	ricochet_points_checkbox.toggled.connect(_on_ricochet_points_toggled)
	delete_saves_button.pressed.connect(_on_delete_saves_pressed)
	back_button.pressed.connect(_on_back_pressed)

	# Update UI based on current settings
	_update_ui()

	# Connect to settings changes
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		experimental_settings.settings_changed.connect(_on_settings_changed)

	# Set process mode to allow input while paused
	process_mode = Node.PROCESS_MODE_ALWAYS


func _update_ui() -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings == null:
		status_label.text = "Error: ExperimentalSettings not found"
		return

	# Update checkbox state (inverted: checked = FOV disabled)
	fov_checkbox.button_pressed = not experimental_settings.is_fov_enabled()
	complex_grenade_checkbox.button_pressed = experimental_settings.is_complex_grenade_throwing()
	ai_prediction_checkbox.button_pressed = experimental_settings.is_ai_prediction_enabled()
	debug_mode_checkbox.button_pressed = experimental_settings.is_debug_mode_enabled()
	invincibility_checkbox.button_pressed = experimental_settings.is_invincibility_enabled()
	replay_checkbox.button_pressed = experimental_settings.is_replay_enabled()
	logging_checkbox.button_pressed = experimental_settings.is_logging_enabled()
	enemy_flashlight_blinding_checkbox.button_pressed = experimental_settings.is_enemy_flashlight_blinding_enabled()
	fps_counter_checkbox.button_pressed = experimental_settings.is_fps_counter_enabled()
	fps_drop_logging_checkbox.button_pressed = experimental_settings.is_fps_drop_logging_enabled()
	all_weapons_unlocked_checkbox.button_pressed = experimental_settings.is_all_weapons_unlocked()
	ricochet_points_checkbox.button_pressed = experimental_settings.is_ricochet_points_enabled()

	# Update status label - show status of all settings
	var status_parts: Array[String] = []
	if experimental_settings.is_fov_enabled():
		status_parts.append("FOV: 100° cone")
	if experimental_settings.is_complex_grenade_throwing():
		status_parts.append("Grenades: complex throwing")
	if experimental_settings.is_ai_prediction_enabled():
		status_parts.append("AI: player prediction")
	if experimental_settings.is_debug_mode_enabled():
		status_parts.append("Debug mode")
	if experimental_settings.is_invincibility_enabled():
		status_parts.append("Invincibility")
	if experimental_settings.is_replay_enabled():
		status_parts.append("Replay viewing")
	if experimental_settings.is_logging_enabled():
		status_parts.append("Log recording")
	if experimental_settings.is_enemy_flashlight_blinding_enabled():
		status_parts.append("Enemy flashlight blinding")
	if experimental_settings.is_fps_counter_enabled():
		status_parts.append("FPS counter")
	if experimental_settings.is_fps_drop_logging_enabled():
		status_parts.append("FPS drop logging")
	if experimental_settings.is_all_weapons_unlocked():
		status_parts.append("All weapons unlocked")
	if experimental_settings.is_ricochet_points_enabled():
		status_parts.append("Ricochet points (+20%)")

	if status_parts.is_empty():
		status_label.text = "All experimental features disabled"
	else:
		status_label.text = "Enabled: " + ", ".join(status_parts)


func _on_fov_toggled(disabled: bool) -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		# Inverted: checkbox checked = FOV disabled
		experimental_settings.set_fov_enabled(not disabled)
	_update_ui()


func _on_complex_grenade_toggled(enabled: bool) -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		experimental_settings.set_complex_grenade_throwing(enabled)
	_update_ui()


func _on_ai_prediction_toggled(enabled: bool) -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		experimental_settings.set_ai_prediction_enabled(enabled)
	_update_ui()


func _on_debug_mode_toggled(enabled: bool) -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		experimental_settings.set_debug_mode_enabled(enabled)
	# Also sync to GameManager for runtime signal emission
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("is_debug_mode_enabled"):
		if game_manager.debug_mode_enabled != enabled:
			game_manager.debug_mode_enabled = enabled
			game_manager.debug_mode_toggled.emit(enabled)
	_update_ui()


func _on_invincibility_toggled(enabled: bool) -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		experimental_settings.set_invincibility_enabled(enabled)
	# Also sync to GameManager for runtime signal emission
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("is_invincibility_enabled"):
		if game_manager.invincibility_enabled != enabled:
			game_manager.invincibility_enabled = enabled
			game_manager.invincibility_toggled.emit(enabled)
	_update_ui()


func _on_replay_toggled(enabled: bool) -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		experimental_settings.set_replay_enabled(enabled)
	_update_ui()


func _on_logging_toggled(enabled: bool) -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		experimental_settings.set_logging_enabled(enabled)
	_update_ui()


func _on_enemy_flashlight_blinding_toggled(enabled: bool) -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		experimental_settings.set_enemy_flashlight_blinding_enabled(enabled)
	_update_ui()


func _on_fps_counter_toggled(enabled: bool) -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		experimental_settings.set_fps_counter_enabled(enabled)
	_update_ui()


func _on_fps_drop_logging_toggled(enabled: bool) -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		experimental_settings.set_fps_drop_logging_enabled(enabled)
	_update_ui()


func _on_all_weapons_unlocked_toggled(enabled: bool) -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		experimental_settings.set_all_weapons_unlocked(enabled)
	_update_ui()


func _on_ricochet_points_toggled(enabled: bool) -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		experimental_settings.set_ricochet_points_enabled(enabled)
	_update_ui()


func _on_delete_saves_pressed() -> void:
	var persist_manager: Node = get_node_or_null("/root/PersistManager")
	if persist_manager and persist_manager.has_method("clear_all_saves"):
		persist_manager.clear_all_saves()
	status_label.text = "Saves deleted. Game reset to first-launch state."


func _on_back_pressed() -> void:
	back_pressed.emit()


func _on_settings_changed() -> void:
	_update_ui()
