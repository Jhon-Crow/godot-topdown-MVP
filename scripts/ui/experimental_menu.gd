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
@onready var all_maps_unlocked_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/AllMapsUnlockedContainer/AllMapsUnlockedCheckbox
@onready var global_stuck_max_time_slider: HSlider = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/GlobalStuckMaxTimeContainer/GlobalStuckMaxTimeSlider
@onready var global_stuck_max_time_value_label: Label = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/GlobalStuckMaxTimeContainer/GlobalStuckMaxTimeValueLabel
@onready var nav_mesh_visible_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/NavMeshVisibleContainer/NavMeshVisibleCheckbox
@onready var search_path_visible_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/SearchPathVisibleContainer/SearchPathVisibleCheckbox
@onready var waypoint_visible_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/WaypointVisibleContainer/WaypointVisibleCheckbox
@onready var passage_waypoints_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/PassageWaypointsContainer/PassageWaypointsCheckbox
@onready var sound_visualizer_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/SoundVisualizerContainer/SoundVisualizerCheckbox
@onready var enemy_path_visible_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/EnemyPathVisibleContainer/EnemyPathVisibleCheckbox
@onready var cover_raycast_visible_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/CoverRaycastVisibleContainer/CoverRaycastVisibleCheckbox
@onready var cover_infinite_rays_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/CoverInfiniteRaysContainer/CoverInfiniteRaysCheckbox
@onready var cover_sector_rays_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/CoverSectorRaysContainer/CoverSectorRaysCheckbox
@onready var tactical_group_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/TacticalGroupContainer/TacticalGroupCheckbox
@onready var delete_saves_button: Button = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/DeleteSavesContainer/DeleteSavesButton
@onready var unlock_table_button: Button = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/UnlockTableContainer/UnlockTableButton
@onready var enemies_table_button: Button = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/EnemiesTableContainer/EnemiesTableButton
@onready var enemy_type_option: OptionButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/EnemySpawnerContainer/EnemyTypeOption
@onready var spawn_enemy_button: Button = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/SpawnEnemyButton
@onready var spawn_status_label: Label = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/SpawnStatusLabel
@onready var back_button: Button = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/BackButton
@onready var status_label: Label = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/StatusLabel

## NavBar references.
@onready var scroll_container: ScrollContainer = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer
@onready var nav_visualisation_button: Button = $MenuContainer/NavBar/NavVBox/NavVisualisationButton
@onready var nav_ai_button: Button = $MenuContainer/NavBar/NavVBox/NavAIButton
@onready var nav_cheats_button: Button = $MenuContainer/NavBar/NavVBox/NavCheatsButton
@onready var nav_perf_button: Button = $MenuContainer/NavBar/NavVBox/NavPerfButton
@onready var nav_debug_button: Button = $MenuContainer/NavBar/NavVBox/NavDebugButton
@onready var nav_utilities_button: Button = $MenuContainer/NavBar/NavVBox/NavUtilitiesButton

## Reference to the unlock table menu scene.
var unlock_table_menu_scene: PackedScene = preload("res://scenes/ui/UnlockTableMenu.tscn")

## The instantiated unlock table menu.
var unlock_table_menu: CanvasLayer = null

## Reference to the enemies table menu scene.
var enemies_table_menu_scene: PackedScene = preload("res://scenes/ui/EnemiesTableMenu.tscn")

## The instantiated enemies table menu.
var enemies_table_menu: CanvasLayer = null


func _ready() -> void:
	# Setup tooltips, hover highlight, and label behaviour for settings rows (Issue #1200)
	var _vbox: Node = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer
	_setup_row_hover(_vbox.get_node("FOVContainer"),
			"Disable FOV Limitation",
			_vbox.get_node("FOVDescription"))
	_setup_row_hover(_vbox.get_node("ComplexGrenadeContainer"),
			"Complex Grenade Throwing",
			_vbox.get_node("ComplexGrenadeDescription"))
	_setup_row_hover(_vbox.get_node("AIPredictionContainer"),
			"AI Player Prediction",
			_vbox.get_node("AIPredictionDescription"))
	_setup_row_hover(_vbox.get_node("DebugModeContainer"),
			"Debug Mode")
	_setup_row_hover(_vbox.get_node("InvincibilityContainer"),
			"Invincibility")
	_setup_row_hover(_vbox.get_node("ReplayContainer"),
			"Enable Replay Viewing",
			_vbox.get_node("ReplayDescription"))
	_setup_row_hover(_vbox.get_node("LoggingContainer"),
			"Enable Log Recording",
			_vbox.get_node("LoggingDescription"))
	_setup_row_hover(_vbox.get_node("EnemyFlashlightBlindingContainer"),
			"Enemy Flashlight Blinding",
			_vbox.get_node("EnemyFlashlightBlindingDescription"))
	_setup_row_hover(_vbox.get_node("FpsCounterContainer"),
			"Show FPS Counter",
			_vbox.get_node("FpsCounterDescription"))
	_setup_row_hover(_vbox.get_node("FpsDropLoggingContainer"),
			"Log FPS Drops",
			_vbox.get_node("FpsDropLoggingDescription"))
	_setup_row_hover(_vbox.get_node("AllWeaponsUnlockedContainer"),
			"Unlock All Weapons",
			_vbox.get_node("AllWeaponsUnlockedDescription"))
	_setup_row_hover(_vbox.get_node("AllMapsUnlockedContainer"),
			"Unlock All Maps",
			_vbox.get_node("AllMapsUnlockedDescription"))
	_setup_row_hover(_vbox.get_node("GlobalStuckMaxTimeContainer"),
			"Global Stuck Max Time",
			_vbox.get_node("GlobalStuckMaxTimeDescription"))
	_setup_row_hover(_vbox.get_node("NavMeshVisibleContainer"),
			"Show Nav Mesh",
			_vbox.get_node("NavMeshVisibleDescription"))
	_setup_row_hover(_vbox.get_node("SearchPathVisibleContainer"),
			"Show Search Paths",
			_vbox.get_node("SearchPathVisibleDescription"))
	_setup_row_hover(_vbox.get_node("WaypointVisibleContainer"),
			"Show Waypoints",
			_vbox.get_node("WaypointVisibleDescription"))
	_setup_row_hover(_vbox.get_node("PassageWaypointsContainer"),
			"Use Passage Waypoints",
			_vbox.get_node("PassageWaypointsDescription"))
	_setup_row_hover(_vbox.get_node("SoundVisualizerContainer"),
			"Show Sound Propagation",
			_vbox.get_node("SoundVisualizerDescription"))
	_setup_row_hover(_vbox.get_node("EnemyPathVisibleContainer"),
			"Show Enemy Nav Paths",
			_vbox.get_node("EnemyPathVisibleDescription"))
	_setup_row_hover(_vbox.get_node("CoverRaycastVisibleContainer"),
			"Show Cover Raycasts",
			_vbox.get_node("CoverRaycastVisibleDescription"))
	_setup_row_hover(_vbox.get_node("CoverInfiniteRaysContainer"),
			"Cover Infinite Rays",
			_vbox.get_node("CoverInfiniteRaysDescription"))
	_setup_row_hover(_vbox.get_node("CoverSectorRaysContainer"),
			"Cover Sector Rays",
			_vbox.get_node("CoverSectorRaysDescription"))
	_setup_row_hover(_vbox.get_node("TacticalGroupContainer"),
			"Tactical Group Movement",
			_vbox.get_node("TacticalGroupDescription"))
	_setup_row_hover(_vbox.get_node("DeleteSavesContainer"),
			"Delete Saves",
			_vbox.get_node("DeleteSavesDescription"))
	_setup_row_hover(_vbox.get_node("UnlockTableContainer"),
			"View Unlock Table",
			_vbox.get_node("UnlockTableDescription"))
	_setup_row_hover(_vbox.get_node("EnemiesTableContainer"),
			"View Enemies Table",
			_vbox.get_node("EnemiesTableDescription"))
	_setup_row_hover(_vbox.get_node("EnemySpawnerContainer"),
			"Enemy Spawner")

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
	all_maps_unlocked_checkbox.toggled.connect(_on_all_maps_unlocked_toggled)
	global_stuck_max_time_slider.value_changed.connect(_on_global_stuck_max_time_changed)
	nav_mesh_visible_checkbox.toggled.connect(_on_nav_mesh_visible_toggled)
	search_path_visible_checkbox.toggled.connect(_on_search_path_visible_toggled)
	waypoint_visible_checkbox.toggled.connect(_on_waypoint_visible_toggled)
	passage_waypoints_checkbox.toggled.connect(_on_passage_waypoints_toggled)
	sound_visualizer_checkbox.toggled.connect(_on_sound_visualizer_toggled)
	enemy_path_visible_checkbox.toggled.connect(_on_enemy_path_visible_toggled)
	cover_raycast_visible_checkbox.toggled.connect(_on_cover_raycast_visible_toggled)
	cover_infinite_rays_checkbox.toggled.connect(_on_cover_infinite_rays_toggled)
	cover_sector_rays_checkbox.toggled.connect(_on_cover_sector_rays_toggled)
	tactical_group_checkbox.toggled.connect(_on_tactical_group_toggled)
	delete_saves_button.pressed.connect(_on_delete_saves_pressed)
	unlock_table_button.pressed.connect(_on_unlock_table_pressed)
	enemies_table_button.pressed.connect(_on_enemies_table_pressed)
	_setup_enemy_spawner()
	enemy_type_option.item_selected.connect(_on_enemy_type_selected)
	spawn_enemy_button.pressed.connect(_on_spawn_enemy_pressed)
	back_button.pressed.connect(_on_back_pressed)

	# Connect navbar buttons
	nav_visualisation_button.pressed.connect(_on_nav_visualisation_pressed)
	nav_ai_button.pressed.connect(_on_nav_ai_pressed)
	nav_cheats_button.pressed.connect(_on_nav_cheats_pressed)
	nav_perf_button.pressed.connect(_on_nav_perf_pressed)
	nav_debug_button.pressed.connect(_on_nav_debug_pressed)
	nav_utilities_button.pressed.connect(_on_nav_utilities_pressed)

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
	all_maps_unlocked_checkbox.button_pressed = experimental_settings.is_all_maps_unlocked()
	nav_mesh_visible_checkbox.button_pressed = experimental_settings.is_nav_mesh_visible_enabled()
	search_path_visible_checkbox.button_pressed = experimental_settings.is_search_path_visible_enabled()
	waypoint_visible_checkbox.button_pressed = experimental_settings.is_passage_waypoints_visible_enabled()
	passage_waypoints_checkbox.button_pressed = experimental_settings.has_method("is_passage_waypoints_enabled") and experimental_settings.is_passage_waypoints_enabled()
	sound_visualizer_checkbox.button_pressed = experimental_settings.is_sound_visualizer_enabled()
	enemy_path_visible_checkbox.button_pressed = experimental_settings.is_enemy_path_visible_enabled()
	cover_raycast_visible_checkbox.button_pressed = experimental_settings.has_method("is_cover_raycast_visible_enabled") and experimental_settings.is_cover_raycast_visible_enabled()
	cover_infinite_rays_checkbox.button_pressed = experimental_settings.has_method("is_cover_infinite_rays_enabled") and experimental_settings.is_cover_infinite_rays_enabled()
	cover_sector_rays_checkbox.button_pressed = experimental_settings.has_method("is_cover_sector_rays_enabled") and experimental_settings.is_cover_sector_rays_enabled()
	tactical_group_checkbox.button_pressed = experimental_settings.has_method("is_tactical_group_enabled") and experimental_settings.is_tactical_group_enabled()

	# Update global stuck max time slider
	var stuck_time: float = experimental_settings.get_global_stuck_max_time()
	global_stuck_max_time_slider.set_block_signals(true)
	global_stuck_max_time_slider.value = stuck_time
	global_stuck_max_time_slider.set_block_signals(false)
	global_stuck_max_time_value_label.text = "%ds" % int(stuck_time)

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
	if experimental_settings.is_all_maps_unlocked():
		status_parts.append("All maps unlocked")
	if experimental_settings.is_nav_mesh_visible_enabled():
		status_parts.append("Nav mesh visible")
	if experimental_settings.is_search_path_visible_enabled():
		status_parts.append("Search paths visible")
	if experimental_settings.is_passage_waypoints_visible_enabled():
		status_parts.append("Waypoints visible")
	if experimental_settings.has_method("is_passage_waypoints_enabled") and not experimental_settings.is_passage_waypoints_enabled():
		status_parts.append("Passage waypoints disabled")
	if experimental_settings.is_sound_visualizer_enabled():
		status_parts.append("Sound visualizer")
	if experimental_settings.is_enemy_path_visible_enabled():
		status_parts.append("Enemy nav paths")
	if experimental_settings.has_method("is_cover_raycast_visible_enabled") and experimental_settings.is_cover_raycast_visible_enabled():
		status_parts.append("Cover raycasts visible")
	if experimental_settings.has_method("is_cover_infinite_rays_enabled") and experimental_settings.is_cover_infinite_rays_enabled():
		status_parts.append("Cover infinite rays")
	if experimental_settings.has_method("is_cover_sector_rays_enabled") and experimental_settings.is_cover_sector_rays_enabled():
		status_parts.append("Cover sector rays")
	if experimental_settings.has_method("is_tactical_group_enabled") and experimental_settings.is_tactical_group_enabled():
		status_parts.append("Tactical group movement")

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


func _on_all_maps_unlocked_toggled(enabled: bool) -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		experimental_settings.set_all_maps_unlocked(enabled)
	_update_ui()


func _on_global_stuck_max_time_changed(value: float) -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		experimental_settings.set_global_stuck_max_time(value)
	global_stuck_max_time_value_label.text = "%ds" % int(value)


func _on_nav_mesh_visible_toggled(enabled: bool) -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		experimental_settings.set_nav_mesh_visible_enabled(enabled)
	_update_ui()


func _on_search_path_visible_toggled(enabled: bool) -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		experimental_settings.set_search_path_visible_enabled(enabled)
	_update_ui()


func _on_waypoint_visible_toggled(enabled: bool) -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		experimental_settings.set_passage_waypoints_visible_enabled(enabled)
	_update_ui()


func _on_passage_waypoints_toggled(enabled: bool) -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings and experimental_settings.has_method("set_passage_waypoints_enabled"):
		experimental_settings.set_passage_waypoints_enabled(enabled)
	_update_ui()


func _on_sound_visualizer_toggled(enabled: bool) -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		experimental_settings.set_sound_visualizer_enabled(enabled)
	_update_ui()


func _on_enemy_path_visible_toggled(enabled: bool) -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		experimental_settings.set_enemy_path_visible_enabled(enabled)
	_update_ui()


func _on_cover_raycast_visible_toggled(enabled: bool) -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		experimental_settings.set_cover_raycast_visible_enabled(enabled)
	_update_ui()


func _on_cover_infinite_rays_toggled(enabled: bool) -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		experimental_settings.set_cover_infinite_rays_enabled(enabled)
	_update_ui()


func _on_cover_sector_rays_toggled(enabled: bool) -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		experimental_settings.set_cover_sector_rays_enabled(enabled)
	_update_ui()


func _on_tactical_group_toggled(enabled: bool) -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		experimental_settings.set_tactical_group_enabled(enabled)
	_update_ui()


func _on_delete_saves_pressed() -> void:
	var persist_manager: Node = get_node_or_null("/root/PersistManager")
	if persist_manager and persist_manager.has_method("clear_all_saves"):
		persist_manager.clear_all_saves()
	status_label.text = "Saves deleted. Game reset to first-launch state."


func _on_unlock_table_pressed() -> void:
	# Instantiate unlock table menu on first use.
	# IMPORTANT: Add to /root to avoid nested CanvasLayer visibility issues in Godot 4.
	# When a CanvasLayer is instanced as a child of another CanvasLayer,
	# visibility does not work correctly. See: https://github.com/godotengine/godot/issues/84912
	_log("Unlock table button pressed")
	if unlock_table_menu == null:
		_log("Creating new unlock table menu instance")
		unlock_table_menu = unlock_table_menu_scene.instantiate()
		unlock_table_menu.back_pressed.connect(_on_unlock_table_back_pressed)
		# Add to root node to avoid any CanvasLayer nesting issues
		get_tree().root.add_child(unlock_table_menu)
		_log("Unlock table menu added to /root, calling show()")
		# Explicitly show after adding to tree
		unlock_table_menu.show()
	else:
		_log("Showing existing unlock table menu")
		# Refresh and show existing instance
		if unlock_table_menu.has_method("refresh"):
			unlock_table_menu.refresh()
		unlock_table_menu.show()


func _on_unlock_table_back_pressed() -> void:
	_log("Unlock table back button pressed")
	if unlock_table_menu:
		unlock_table_menu.hide()


func _on_enemies_table_pressed() -> void:
	# Instantiate enemies table menu on first use.
	# IMPORTANT: Add to /root to avoid nested CanvasLayer visibility issues in Godot 4.
	# When a CanvasLayer is instanced as a child of another CanvasLayer,
	# visibility does not work correctly. See: https://github.com/godotengine/godot/issues/84912
	_log("Enemies table button pressed")
	if enemies_table_menu == null:
		_log("Creating new enemies table menu instance")
		enemies_table_menu = enemies_table_menu_scene.instantiate()
		enemies_table_menu.back_pressed.connect(_on_enemies_table_back_pressed)
		# Add to root node to avoid any CanvasLayer nesting issues
		get_tree().root.add_child(enemies_table_menu)
		_log("Enemies table menu added to /root, calling show()")
		# Explicitly show after adding to tree
		enemies_table_menu.show()
	else:
		_log("Showing existing enemies table menu")
		# Refresh and show existing instance
		if enemies_table_menu.has_method("refresh"):
			enemies_table_menu.refresh()
		enemies_table_menu.show()


func _on_enemies_table_back_pressed() -> void:
	_log("Enemies table back button pressed")
	if enemies_table_menu:
		enemies_table_menu.hide()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		# If a sub-window (unlock table or enemies table) is open, let it handle ESC.
		var sub_open: bool = (unlock_table_menu != null and unlock_table_menu.visible) \
				or (enemies_table_menu != null and enemies_table_menu.visible)
		if not sub_open:
			_on_back_pressed()
			get_viewport().set_input_as_handled()


func _on_back_pressed() -> void:
	back_pressed.emit()


func _on_settings_changed() -> void:
	_update_ui()


## Enemy spawner: populate enemy type dropdown.
## Each entry stores weapon_type int as metadata (0=RIFLE, 1=SHOTGUN, 2=UZI, 3=MACHETE, 4=RPG, 5=PM, 6=MACHINE_GUN, 7=SNIPER_RIFLE, 8=REVOLVER).
## Special flags: is_teleporter, has_armored_skin, has_force_field, is_grenadier, start_invisible, has_swat_shield, is_gas_mask.
## Restores the previously selected enemy type from ExperimentalSettings (Issue #1112).
func _setup_enemy_spawner() -> void:
	enemy_type_option.clear()
	var types: Array[Dictionary] = [
		{"name": "Rifle (M16)", "weapon_type": 0, "behavior": 1},
		{"name": "Shotgun", "weapon_type": 1, "behavior": 1},
		{"name": "UZI (SMG)", "weapon_type": 2, "behavior": 1},
		{"name": "Machete (melee)", "weapon_type": 3, "behavior": 1},
		{"name": "RPG + PM pistol", "weapon_type": 4, "behavior": 1},
		{"name": "PM (Makarov pistol)", "weapon_type": 5, "behavior": 1},
		{"name": "Machine Gunner (PKM)", "weapon_type": 6, "behavior": 1},
		{"name": "Sniper (ASVK)", "weapon_type": 7, "behavior": 1},
		{"name": "Patrol Rifle", "weapon_type": 0, "behavior": 0},
		{"name": "SWAT Shieldbearer", "weapon_type": 8, "behavior": 1, "has_swat_shield": true, "scene": "res://scenes/objects/EnemySwatShield.tscn"},  # Issue #1242
		{"name": "Teleporter (Rifle)", "weapon_type": 0, "behavior": 1, "is_teleporter": true},
		{"name": "Armored Skin (Rifle)", "weapon_type": 0, "behavior": 1, "has_armored_skin": true},
		{"name": "Force Field (Rifle)", "weapon_type": 0, "behavior": 1, "has_force_field": true},
		{"name": "Grenadier (Rifle)", "weapon_type": 0, "behavior": 1, "is_grenadier": true},
		{"name": "Invisible (Rifle)", "weapon_type": 0, "behavior": 1, "start_invisible": true},
		{"name": "Gas Mask Enemy", "weapon_type": 0, "behavior": 1, "is_gas_mask": true},
		{"name": "Drone Operator", "weapon_type": 0, "behavior": 1, "is_drone_operator": true, "scene": "res://scenes/objects/EnemyDroneOperator.tscn"},  # Issue #1397
	]
	for t in types:
		enemy_type_option.add_item(t["name"])
		enemy_type_option.set_item_metadata(enemy_type_option.item_count - 1, t)
	# Restore persisted selection.
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings and experimental_settings.has_method("get_selected_enemy_type_index"):
		var saved_idx: int = experimental_settings.get_selected_enemy_type_index()
		if saved_idx >= 0 and saved_idx < enemy_type_option.item_count:
			enemy_type_option.select(saved_idx)


## Spawn the selected enemy type near the player on the current map.
func _on_spawn_enemy_pressed() -> void:
	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		spawn_status_label.text = "Error: No active scene."
		return

	# Find player position for spawn offset.
	var player: Node = get_node_or_null("/root/Player")
	if player == null:
		player = current_scene.find_child("Player", true, false)
	var spawn_pos: Vector2 = Vector2(400.0, 400.0)
	if player and player.get("global_position") != null:
		spawn_pos = player.global_position + Vector2(200.0, 0.0)

	# Instantiate and configure.
	var idx: int = enemy_type_option.selected
	var meta: Dictionary = enemy_type_option.get_item_metadata(idx) if idx >= 0 else {"weapon_type": 0, "behavior": 1}

	# Use scene override if provided (e.g. EnemySwatShield.tscn for the shieldbearer).
	var scene_path: String = meta.get("scene", "res://scenes/objects/Enemy.tscn")
	if not ResourceLoader.exists(scene_path):
		scene_path = "res://scenes/objects/Enemy.tscn"
	var scene: PackedScene = load(scene_path)
	if scene == null:
		spawn_status_label.text = "Error: Scene not found: %s" % scene_path
		return

	var enemy: Node = scene.instantiate()
	enemy.global_position = spawn_pos
	if enemy.get("weapon_type") != null:
		enemy.set("weapon_type", meta.get("weapon_type", 0))
	if enemy.get("behavior_mode") != null:
		enemy.set("behavior_mode", meta.get("behavior", 1))
	if enemy.get("destroy_on_death") != null:
		enemy.set("destroy_on_death", true)
	if meta.has("has_swat_shield") and enemy.get("has_swat_shield") != null:
		enemy.set("has_swat_shield", meta.get("has_swat_shield", false))
	# Apply special enemy flags if present in metadata.
	if meta.get("is_teleporter", false) and enemy.get("is_teleporter") != null:
		enemy.set("is_teleporter", true)
	if meta.get("has_armored_skin", false) and enemy.get("has_armored_skin") != null:
		enemy.set("has_armored_skin", true)
	if meta.get("has_force_field", false) and enemy.get("has_force_field") != null:
		enemy.set("has_force_field", true)
	if meta.get("is_grenadier", false) and enemy.get("is_grenadier") != null:
		enemy.set("is_grenadier", true)
	if meta.get("start_invisible", false) and enemy.get("start_invisible") != null:
		enemy.set("start_invisible", true)
	if meta.get("is_gas_mask", false) and enemy.get("is_gas_mask") != null:
		enemy.set("is_gas_mask", true)
	if meta.get("is_drone_operator", false) and enemy.get("is_drone_operator") != null:
		enemy.set("is_drone_operator", true)

	# Add to Environment/Enemies node if it exists, otherwise directly to scene.
	var enemies_node: Node = current_scene.find_child("Enemies", true, false)
	if enemies_node:
		enemies_node.add_child(enemy)
	else:
		current_scene.add_child(enemy)

	var type_name: String = enemy_type_option.get_item_text(idx) if idx >= 0 else "Unknown"
	spawn_status_label.text = "Spawned: %s at (%d, %d)" % [type_name, int(spawn_pos.x), int(spawn_pos.y)]
	_log("Enemy spawner: spawned '%s' at %s" % [type_name, str(spawn_pos)])


## Persist the selected enemy type index when the dropdown selection changes (Issue #1112).
func _on_enemy_type_selected(index: int) -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings and experimental_settings.has_method("set_selected_enemy_type_index"):
		experimental_settings.set_selected_enemy_type_index(index)


## Log a message to the file logger if available.
func _log(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[ExperimentalMenu] " + message)
	else:
		print("[ExperimentalMenu] " + message)


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


## Scroll the ScrollContainer so the given VBoxContainer child is visible at the top.
func _scroll_to_node(target_node: Control) -> void:
	# Wait one frame so layout is settled before reading positions.
	await get_tree().process_frame
	var vbox: Control = scroll_container.get_node("VBoxContainer")
	var target_pos: float = target_node.position.y
	scroll_container.scroll_vertical = int(target_pos)


func _on_nav_visualisation_pressed() -> void:
	var vbox: Node = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer
	_scroll_to_node(vbox.get_node("ShowCategoryLabel"))


func _on_nav_ai_pressed() -> void:
	var vbox: Node = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer
	_scroll_to_node(vbox.get_node("AICategoryLabel"))


func _on_nav_cheats_pressed() -> void:
	var vbox: Node = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer
	_scroll_to_node(vbox.get_node("CheatsCategoryLabel"))


func _on_nav_perf_pressed() -> void:
	var vbox: Node = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer
	_scroll_to_node(vbox.get_node("PerfCategoryLabel"))


func _on_nav_debug_pressed() -> void:
	var vbox: Node = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer
	_scroll_to_node(vbox.get_node("DebugCategoryLabel"))


func _on_nav_utilities_pressed() -> void:
	var vbox: Node = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer
	_scroll_to_node(vbox.get_node("UtilitiesCategoryLabel"))
