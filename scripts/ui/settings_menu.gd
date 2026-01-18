extends CanvasLayer
## Settings menu controller.
##
## Provides access to game settings like score UI visibility.
## Accessed from the pause menu.

## Signal emitted when back button is pressed.
signal back_pressed

## Reference to the main container.
@onready var container: Control = $Container
@onready var score_ui_toggle: CheckButton = $Container/VBoxContainer/ScoreUIToggle
@onready var back_button: Button = $Container/VBoxContainer/BackButton


func _ready() -> void:
	# Set initial state based on GameManager
	if GameManager:
		score_ui_toggle.button_pressed = GameManager.score_ui_visible

	# Connect signals
	score_ui_toggle.toggled.connect(_on_score_ui_toggle_changed)
	back_button.pressed.connect(_on_back_pressed)

	# Focus on toggle
	score_ui_toggle.grab_focus()


func _on_score_ui_toggle_changed(toggled_on: bool) -> void:
	if GameManager:
		GameManager.set_score_ui_visible(toggled_on)


func _on_back_pressed() -> void:
	back_pressed.emit()
