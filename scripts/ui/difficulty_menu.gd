extends CanvasLayer
## Difficulty selection menu.
##
## Allows the player to select between Normal and Hard difficulty modes.
## Normal mode: Classic game behavior
## Hard mode: Enemies react when player looks away, reduced ammo

## Signal emitted when the back button is pressed.
signal back_pressed

## Reference to UI elements.
@onready var normal_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/NormalButton
@onready var hard_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/HardButton
@onready var back_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/BackButton
@onready var status_label: Label = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/StatusLabel


func _ready() -> void:
	# Connect button signals
	normal_button.pressed.connect(_on_normal_pressed)
	hard_button.pressed.connect(_on_hard_pressed)
	back_button.pressed.connect(_on_back_pressed)

	# Update button states based on current difficulty
	_update_button_states()

	# Connect to difficulty changes
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager:
		difficulty_manager.difficulty_changed.connect(_on_difficulty_changed)

	# Set process mode to allow input while paused
	process_mode = Node.PROCESS_MODE_ALWAYS


func _update_button_states() -> void:
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager == null:
		return

	var is_hard: bool = difficulty_manager.is_hard_mode()

	# Highlight current difficulty
	normal_button.disabled = not is_hard
	hard_button.disabled = is_hard

	# Update button text to show selection
	if is_hard:
		normal_button.text = "Normal"
		hard_button.text = "Hard (Selected)"
		status_label.text = "Hard mode: Enemies react when you look away"
	else:
		normal_button.text = "Normal (Selected)"
		hard_button.text = "Hard"
		status_label.text = "Normal mode: Classic gameplay"


func _on_normal_pressed() -> void:
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager:
		difficulty_manager.set_difficulty(difficulty_manager.Difficulty.NORMAL)
	_update_button_states()


func _on_hard_pressed() -> void:
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager:
		difficulty_manager.set_difficulty(difficulty_manager.Difficulty.HARD)
	_update_button_states()


func _on_back_pressed() -> void:
	back_pressed.emit()


func _on_difficulty_changed(_new_difficulty: int) -> void:
	_update_button_states()
