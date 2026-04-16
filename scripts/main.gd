extends Node2D
## Main scene controller for the Godot Top-Down Template.
##
## This is the entry point of the game. It handles scene management
## and can be extended to add game-wide functionality.
##
## Note: The project's run/main_scene is res://scenes/levels/LabyrinthLevel.tscn,
## so this scene is NOT the startup scene. First-launch logic (Issue #1734) is
## handled in PersistManager which runs as an autoload on every startup.


func _ready() -> void:
	print("Godot Top-Down Template loaded successfully!")
