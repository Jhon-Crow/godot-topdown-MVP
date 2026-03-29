extends Node2D
## Main scene controller for the Godot Top-Down Template.
##
## This is the entry point of the game. It handles scene management
## and can be extended to add game-wide functionality.

## Path to the DifficultyMenu scene used for first-launch selection (Issue #1734).
const DIFFICULTY_MENU_SCENE_PATH: String = "res://scenes/ui/DifficultyMenu.tscn"

## Held reference while the first-launch difficulty picker is shown (Issue #1734).
var _first_launch_menu: CanvasLayer = null


func _ready() -> void:
	print("Godot Top-Down Template loaded successfully!")
	# Issue #1734: Show difficulty selection on very first launch before any gameplay.
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager and difficulty_manager.is_first_launch():
		_show_first_launch_difficulty_menu()


## Instantiate and display the DifficultyMenu in first-launch mode (Issue #1734).
## The menu stays visible until the player selects a difficulty, then auto-hides.
func _show_first_launch_difficulty_menu() -> void:
	var packed: PackedScene = load(DIFFICULTY_MENU_SCENE_PATH)
	if packed == null:
		push_error("[Main] Could not load DifficultyMenu scene: " + DIFFICULTY_MENU_SCENE_PATH)
		return
	_first_launch_menu = packed.instantiate()
	_first_launch_menu.first_launch_mode = true
	_first_launch_menu.difficulty_selected_first_launch.connect(_on_first_launch_difficulty_selected)
	add_child(_first_launch_menu)


## Called when the player picks a difficulty during first-launch (Issue #1734).
## Removes the picker and lets normal gameplay proceed.
func _on_first_launch_difficulty_selected() -> void:
	if _first_launch_menu != null:
		_first_launch_menu.queue_free()
		_first_launch_menu = null
