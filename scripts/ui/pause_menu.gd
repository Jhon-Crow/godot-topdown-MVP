extends CanvasLayer
## Pause menu controller (Issue #1139).
##
## Handles game pausing. Settings (Controls, Difficulty, Sound, Gameplay,
## Experimental) are grouped under the Settings submenu.
## This menu pauses the game tree when visible.

## Reference to the main menu container.
@onready var menu_container: Control = $MenuContainer
@onready var resume_button: Button = $MenuContainer/VBoxContainer/ResumeButton
@onready var armory_button: Button = $MenuContainer/VBoxContainer/ArmoryButton
@onready var levels_button: Button = $MenuContainer/VBoxContainer/LevelsButton
@onready var training_button: Button = $MenuContainer/VBoxContainer/TrainingButton
@onready var roguelike_button: Button = $MenuContainer/VBoxContainer/RoguelikeButton
@onready var arena_button: Button = $MenuContainer/VBoxContainer/ArenaButton
@onready var settings_button: Button = $MenuContainer/VBoxContainer/SettingsButton
@onready var quit_button: Button = $MenuContainer/VBoxContainer/QuitButton

## The instantiated levels menu.
var _levels_menu: CanvasLayer = null

## The instantiated armory menu.
var _armory_menu: CanvasLayer = null

## The instantiated settings menu.
var _settings_menu: CanvasLayer = null

## Gold shine overlay ColorRect on the armory button (Issue #1536).
var _armory_shine_overlay: ColorRect = null

## Reference to the levels menu scene.
@export var levels_menu_scene: PackedScene

## Reference to the armory menu scene.
@export var armory_menu_scene: PackedScene

## Reference to the settings menu scene.
@export var settings_menu_scene: PackedScene


func _ready() -> void:
	# Start hidden
	hide()
	set_process_unhandled_input(true)
	# Must process even when tree is paused so ESC can toggle the menu.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Connect button signals
	resume_button.pressed.connect(_on_resume_pressed)
	armory_button.pressed.connect(_on_armory_pressed)
	levels_button.pressed.connect(_on_levels_pressed)
	training_button.pressed.connect(_on_training_pressed)
	roguelike_button.pressed.connect(_on_roguelike_pressed)
	arena_button.pressed.connect(_on_arena_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	# Highlight armory button if there are available unlocks
	# Disable it entirely in roguelike mode (Issue #1166)
	_refresh_armory_button_state()

	# Preload levels menu if not set
	if levels_menu_scene == null:
		levels_menu_scene = preload("res://scenes/ui/LevelsMenu.tscn")

	# Preload armory menu if not set
	if armory_menu_scene == null:
		armory_menu_scene = preload("res://scenes/ui/ArmoryMenu.tscn")

	# Preload settings menu if not set
	if settings_menu_scene == null:
		settings_menu_scene = preload("res://scenes/ui/SettingsMenu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle_pause()
		get_viewport().set_input_as_handled()


## Toggles the pause state.
func toggle_pause() -> void:
	if visible:
		resume_game()
	else:
		pause_game()


## Pauses the game and shows the menu.
func pause_game() -> void:
	get_tree().paused = true
	# Show cursor for menu interaction (still confined to window)
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)

	# Close any open submenus and restore main menu container
	if _armory_menu and _armory_menu.visible:
		_armory_menu.hide()
	if _levels_menu and _levels_menu.visible:
		_levels_menu.hide()
	if _settings_menu and _settings_menu.visible:
		_settings_menu.hide()

	# Ensure main menu container is visible
	menu_container.show()

	# Refresh armory button state each time the menu opens
	_refresh_armory_button_state()

	show()
	resume_button.grab_focus()


## Resumes the game and hides the menu.
func resume_game() -> void:
	get_tree().paused = false
	# Hide cursor again for gameplay (confined and hidden)
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
	hide()

	# Also close submenus if open
	if _armory_menu and _armory_menu.visible:
		_armory_menu.hide()
	if _levels_menu and _levels_menu.visible:
		_levels_menu.hide()
	if _settings_menu and _settings_menu.visible:
		_settings_menu.hide()


func _on_resume_pressed() -> void:
	resume_game()


func _on_settings_pressed() -> void:
	# Hide main menu, show settings submenu
	menu_container.hide()

	if _settings_menu == null:
		_settings_menu = settings_menu_scene.instantiate()
		_settings_menu.back_pressed.connect(_on_settings_back)
		add_child(_settings_menu)
	else:
		_settings_menu.show()


func _on_settings_back() -> void:
	# Show main menu again
	if _settings_menu:
		_settings_menu.hide()
	menu_container.show()
	settings_button.grab_focus()


func _on_armory_pressed() -> void:
	FileLogger.info("[PauseMenu] Armory button pressed")
	# Hide main menu, show armory menu
	menu_container.hide()

	if _armory_menu == null:
		FileLogger.info("[PauseMenu] Creating new armory menu instance")
		FileLogger.info("[PauseMenu] armory_menu_scene resource path: %s" % armory_menu_scene.resource_path)
		_armory_menu = armory_menu_scene.instantiate()
		FileLogger.info("[PauseMenu] Instance created, class: %s, name: %s" % [_armory_menu.get_class(), _armory_menu.name])
		# Check if the script is properly attached
		var script = _armory_menu.get_script()
		if script:
			FileLogger.info("[PauseMenu] Script attached: %s" % script.resource_path)
		else:
			FileLogger.info("[PauseMenu] WARNING: No script attached to armory menu instance!")
		# Check if it has the expected signal (proves script is loaded)
		if _armory_menu.has_signal("back_pressed"):
			FileLogger.info("[PauseMenu] back_pressed signal exists on instance")
		else:
			FileLogger.info("[PauseMenu] WARNING: back_pressed signal NOT found on instance!")
		_armory_menu.back_pressed.connect(_on_armory_back)
		FileLogger.info("[PauseMenu] back_pressed signal connected")
		add_child(_armory_menu)
		FileLogger.info("[PauseMenu] Armory menu instance added as child, is_inside_tree: %s" % _armory_menu.is_inside_tree())
		# Check method existence after adding to tree
		if _armory_menu.has_method("_populate_weapon_grid"):
			FileLogger.info("[PauseMenu] _populate_weapon_grid method exists")
		else:
			FileLogger.info("[PauseMenu] WARNING: _populate_weapon_grid method NOT found!")
	else:
		FileLogger.info("[PauseMenu] Showing existing armory menu")
		# Refresh the weapon grid in case grenade selection changed
		if _armory_menu.has_method("_populate_weapon_grid"):
			_armory_menu._populate_weapon_grid()
		_armory_menu.show()


func _on_armory_back() -> void:
	# Show main menu again
	if _armory_menu:
		_armory_menu.hide()
	menu_container.show()
	# Refresh armory button state in case the player just unlocked an item
	_refresh_armory_button_state()
	armory_button.grab_focus()


func _on_levels_pressed() -> void:
	# Hide main menu, show levels menu
	menu_container.hide()

	if _levels_menu == null:
		_levels_menu = levels_menu_scene.instantiate()
		_levels_menu.back_pressed.connect(_on_levels_back)
		add_child(_levels_menu)
	else:
		# Refresh level cards in case current scene or difficulty changed
		if _levels_menu.has_method("_populate_level_cards"):
			_levels_menu._populate_level_cards()
		_levels_menu.show()


func _on_levels_back() -> void:
	# Show main menu again
	if _levels_menu:
		_levels_menu.hide()
	menu_container.show()
	levels_button.grab_focus()


func _on_training_pressed() -> void:
	# Load the tutorial level directly
	get_tree().paused = false
	# Restore hidden cursor for gameplay (confined and hidden)
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)

	# Load the tutorial level
	var tutorial_path: String = "res://scenes/levels/csharp/TestTier.tscn"
	var error := get_tree().change_scene_to_file(tutorial_path)
	if error != OK:
		push_error("Failed to load tutorial level: %s" % error)
		# Re-pause and show cursor if error occurs
		get_tree().paused = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)


func _on_roguelike_pressed() -> void:
	# Load the roguelike level directly (Issue #1061)
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)

	var roguelike_path: String = "res://scenes/levels/RoguelikeLevel.tscn"
	var scene_loader: Node = get_node_or_null("/root/SceneLoader")
	if scene_loader and scene_loader.has_method("load_level"):
		scene_loader.load_level(roguelike_path)
	else:
		var error := get_tree().change_scene_to_file(roguelike_path)
		if error != OK:
			push_error("Failed to load roguelike level: %s" % error)
			get_tree().paused = true
			Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)


func _on_arena_pressed() -> void:
	# Load the Arena level directly (same pattern as Training button).
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)

	var arena_path: String = "res://scenes/levels/ArenaLevel.tscn"
	var error := get_tree().change_scene_to_file(arena_path)
	if error != OK:
		push_error("Failed to load arena level: %s" % error)
		get_tree().paused = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)


func _on_quit_pressed() -> void:
	get_tree().paused = false
	get_tree().quit()


## Refresh the armory button state:
## - Disabled (greyed out) in roguelike mode (Issue #1166) — armory is not available during a run.
## - Gold highlight when available unlocks exist (normal mode).
## - No highlight when all available items are already unlocked.
func _refresh_armory_button_state() -> void:
	var game_manager: Node = get_node_or_null("/root/GameManager")
	var in_roguelike: bool = game_manager != null and game_manager.get("roguelike_active") == true

	if in_roguelike:
		# Disable armory button entirely in roguelike mode
		armory_button.disabled = true
		armory_button.tooltip_text = "Арсенал недоступен в режиме рогалика"
		if _armory_shine_overlay != null and is_instance_valid(_armory_shine_overlay):
			_armory_shine_overlay.queue_free()
		_armory_shine_overlay = null
		armory_button.remove_theme_color_override("font_color")
		return

	# Normal mode — re-enable and check for available unlocks
	armory_button.disabled = false
	armory_button.tooltip_text = ""

	var unlock_manager: Node = get_node_or_null("/root/UnlockManager")
	if unlock_manager == null or not unlock_manager.has_method("has_any_available_unlock"):
		return

	if unlock_manager.has_any_available_unlock():
		# Add gold shine shader overlay if not already present (Issue #1536).
		if _armory_shine_overlay == null or not is_instance_valid(_armory_shine_overlay):
			var shine_shader := load("res://scripts/shaders/gold_shine.gdshader") as Shader
			if shine_shader:
				var mat := ShaderMaterial.new()
				mat.shader = shine_shader
				var overlay := ColorRect.new()
				overlay.name = "ArmoryGoldShineOverlay"
				overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
				overlay.material = mat
				armory_button.add_child(overlay)
				_armory_shine_overlay = overlay
		armory_button.add_theme_color_override("font_color", Color(0.1, 0.08, 0.0, 1.0))
	else:
		# Remove shine overlay — no available unlocks
		if _armory_shine_overlay != null and is_instance_valid(_armory_shine_overlay):
			_armory_shine_overlay.queue_free()
		_armory_shine_overlay = null
		armory_button.remove_theme_color_override("font_color")
