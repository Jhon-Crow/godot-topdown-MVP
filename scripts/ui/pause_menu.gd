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
@onready var quit_button: Button = $MenuContainer/VBoxContainer/QuitButton

## The instantiated controls menu.
var _controls_menu: CanvasLayer = null


func _ready() -> void:
	# Start hidden
	hide()
	set_process_unhandled_input(true)

	# Connect button signals
	resume_button.pressed.connect(_on_resume_pressed)
	controls_button.pressed.connect(_on_controls_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	# Preload controls menu if not set
	if controls_menu_scene == null:
		controls_menu_scene = preload("res://scenes/ui/ControlsMenu.tscn")


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
	show()
	resume_button.grab_focus()


## Resumes the game and hides the menu.
func resume_game() -> void:
	get_tree().paused = false
	hide()

	# Also close controls menu if open
	if _controls_menu and _controls_menu.visible:
		_controls_menu.hide()


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


func _on_quit_pressed() -> void:
	get_tree().paused = false
	get_tree().quit()
