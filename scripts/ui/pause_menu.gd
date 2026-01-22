extends CanvasLayer
## Pause menu controller.
##
## Handles game pausing and provides access to controls menu and resume/quit options.
## This menu pauses the game tree when visible.

## Reference to the controls menu scene.
@export var controls_menu_scene: PackedScene

## Reference to the main menu container.
@onready var menu_container: Control = $MenuContainer
@onready var resume_button: Button = $MenuContainer/VBoxContainer/ResumeButton
@onready var controls_button: Button = $MenuContainer/VBoxContainer/ControlsButton
@onready var difficulty_button: Button = $MenuContainer/VBoxContainer/DifficultyButton
@onready var armory_button: Button = $MenuContainer/VBoxContainer/ArmoryButton
@onready var levels_button: Button = $MenuContainer/VBoxContainer/LevelsButton
@onready var quit_button: Button = $MenuContainer/VBoxContainer/QuitButton

## The instantiated controls menu.
var _controls_menu: CanvasLayer = null

## The instantiated difficulty menu.
var _difficulty_menu: CanvasLayer = null

## The instantiated levels menu.
var _levels_menu: CanvasLayer = null

## The instantiated armory menu.
var _armory_menu: CanvasLayer = null

## Reference to the difficulty menu scene.
@export var difficulty_menu_scene: PackedScene

## Reference to the levels menu scene.
@export var levels_menu_scene: PackedScene

## Reference to the armory menu scene.
@export var armory_menu_scene: PackedScene


func _ready() -> void:
	# Start hidden
	hide()
	set_process_unhandled_input(true)

	# Connect button signals
	resume_button.pressed.connect(_on_resume_pressed)
	controls_button.pressed.connect(_on_controls_pressed)
	difficulty_button.pressed.connect(_on_difficulty_pressed)
	armory_button.pressed.connect(_on_armory_pressed)
	levels_button.pressed.connect(_on_levels_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	# Preload controls menu if not set
	if controls_menu_scene == null:
		controls_menu_scene = preload("res://scenes/ui/ControlsMenu.tscn")

	# Preload difficulty menu if not set
	if difficulty_menu_scene == null:
		difficulty_menu_scene = preload("res://scenes/ui/DifficultyMenu.tscn")

	# Preload levels menu if not set
	if levels_menu_scene == null:
		levels_menu_scene = preload("res://scenes/ui/LevelsMenu.tscn")

	# Preload armory menu if not set
	if armory_menu_scene == null:
		armory_menu_scene = preload("res://scenes/ui/ArmoryMenu.tscn")


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
	if _controls_menu and _controls_menu.visible:
		_controls_menu.hide()
	if _difficulty_menu and _difficulty_menu.visible:
		_difficulty_menu.hide()
	if _levels_menu and _levels_menu.visible:
		_levels_menu.hide()
	if _armory_menu and _armory_menu.visible:
		_armory_menu.hide()

	# Ensure main menu container is visible
	menu_container.show()

	show()
	resume_button.grab_focus()


## Resumes the game and hides the menu.
func resume_game() -> void:
	get_tree().paused = false
	# Hide cursor again for gameplay (confined and hidden)
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
	hide()

	# Also close controls menu if open
	if _controls_menu and _controls_menu.visible:
		_controls_menu.hide()

	# Also close difficulty menu if open
	if _difficulty_menu and _difficulty_menu.visible:
		_difficulty_menu.hide()

	# Also close levels menu if open
	if _levels_menu and _levels_menu.visible:
		_levels_menu.hide()

	# Also close armory menu if open
	if _armory_menu and _armory_menu.visible:
		_armory_menu.hide()


func _on_resume_pressed() -> void:
	resume_game()


func _on_controls_pressed() -> void:
	# Hide main menu, show controls menu
	menu_container.hide()

	if _controls_menu == null:
		_controls_menu = controls_menu_scene.instantiate()
		_controls_menu.back_pressed.connect(_on_controls_back)
		add_child(_controls_menu)
	else:
		_controls_menu.show()


func _on_controls_back() -> void:
	# Show main menu again
	if _controls_menu:
		_controls_menu.hide()
	menu_container.show()
	controls_button.grab_focus()


func _on_difficulty_pressed() -> void:
	# Hide main menu, show difficulty menu
	menu_container.hide()

	if _difficulty_menu == null:
		_difficulty_menu = difficulty_menu_scene.instantiate()
		_difficulty_menu.back_pressed.connect(_on_difficulty_back)
		add_child(_difficulty_menu)
	else:
		_difficulty_menu.show()


func _on_difficulty_back() -> void:
	# Show main menu again
	if _difficulty_menu:
		_difficulty_menu.hide()
	menu_container.show()
	difficulty_button.grab_focus()


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
	armory_button.grab_focus()


func _on_levels_pressed() -> void:
	# Hide main menu, show levels menu
	menu_container.hide()

	if _levels_menu == null:
		_levels_menu = levels_menu_scene.instantiate()
		_levels_menu.back_pressed.connect(_on_levels_back)
		add_child(_levels_menu)
	else:
		# Refresh level list in case current scene changed
		_levels_menu._populate_level_list()
		_levels_menu.show()


func _on_levels_back() -> void:
	# Show main menu again
	if _levels_menu:
		_levels_menu.hide()
	menu_container.show()
	levels_button.grab_focus()


func _on_quit_pressed() -> void:
	get_tree().paused = false
	get_tree().quit()
