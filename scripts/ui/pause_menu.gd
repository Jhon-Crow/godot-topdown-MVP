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
@onready var levels_button: Button = $MenuContainer/VBoxContainer/LevelsButton
@onready var quit_button: Button = $MenuContainer/VBoxContainer/QuitButton

## The instantiated controls menu.
var _controls_menu: CanvasLayer = null

## The instantiated difficulty menu.
var _difficulty_menu: CanvasLayer = null

## The instantiated levels menu.
var _levels_menu: CanvasLayer = null

## Reference to the difficulty menu scene.
@export var difficulty_menu_scene: PackedScene

## Reference to the levels menu scene.
@export var levels_menu_scene: PackedScene


func _ready() -> void:
	# Start hidden
	hide()
	set_process_unhandled_input(true)

	# Connect button signals
	resume_button.pressed.connect(_on_resume_pressed)
	controls_button.pressed.connect(_on_controls_pressed)
	difficulty_button.pressed.connect(_on_difficulty_pressed)
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
