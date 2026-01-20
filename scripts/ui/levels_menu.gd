extends CanvasLayer
## Levels selection menu.
##
## Allows the player to select and load different levels from the pause menu.
## Shows a list of available levels that can be loaded during gameplay.

## Signal emitted when the back button is pressed.
signal back_pressed

## Dictionary mapping level names to their scene paths.
const LEVELS: Dictionary = {
	"Building Level": "res://scenes/levels/BuildingLevel.tscn",
	"Test Tier": "res://scenes/levels/TestTier.tscn",
	"Test Tier (C#)": "res://scenes/levels/csharp/TestTier.tscn"
}

## Reference to UI elements.
@onready var level_list: VBoxContainer = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/ScrollContainer/LevelList
@onready var back_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/BackButton
@onready var status_label: Label = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/StatusLabel


func _ready() -> void:
	# Connect button signals
	back_button.pressed.connect(_on_back_pressed)

	# Populate level list
	_populate_level_list()

	# Set process mode to allow input while paused
	process_mode = Node.PROCESS_MODE_ALWAYS


func _populate_level_list() -> void:
	# Clear existing children
	for child in level_list.get_children():
		child.queue_free()

	# Get current scene path to highlight it
	var current_scene_path: String = ""
	var current_scene: Node = get_tree().current_scene
	if current_scene and current_scene.scene_file_path:
		current_scene_path = current_scene.scene_file_path

	# Create a button for each level
	for level_name in LEVELS:
		var level_path: String = LEVELS[level_name]
		var button := Button.new()
		button.custom_minimum_size = Vector2(250, 40)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

		# Mark current level
		if level_path == current_scene_path:
			button.text = level_name + " (Current)"
			button.disabled = true
		else:
			button.text = level_name

		button.pressed.connect(_on_level_selected.bind(level_path))
		level_list.add_child(button)


func _on_level_selected(level_path: String) -> void:
	status_label.text = "Loading..."

	# Unpause the game before changing scene
	get_tree().paused = false

	# Change to the selected level
	var error := get_tree().change_scene_to_file(level_path)
	if error != OK:
		status_label.text = "Error loading level!"
		get_tree().paused = true


func _on_back_pressed() -> void:
	back_pressed.emit()
