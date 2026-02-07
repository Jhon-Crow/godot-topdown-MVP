extends CanvasLayer
## Difficulty selection menu.
##
## Allows the player to select between Power Fantasy, Easy, Normal, and Hard difficulty modes.
## Power Fantasy mode: 10 HP, 3x ammo, reduced recoil, blue laser sights, special effects
## Easy mode: Longer enemy reaction delay - enemies take more time to shoot after spotting player
## Normal mode: Classic game behavior
## Hard mode: Enemies react when player looks away, reduced ammo
## Also includes a Night Mode toggle right under the Difficulty title.

## Signal emitted when the back button is pressed.
signal back_pressed

## Reference to UI elements.
@onready var night_mode_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/NightModeContainer/NightModeCheckbox
@onready var power_fantasy_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/PowerFantasyButton
@onready var easy_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/EasyButton
@onready var normal_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/NormalButton
@onready var hard_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/HardButton
@onready var back_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/BackButton
@onready var status_label: Label = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/StatusLabel


func _ready() -> void:
	# Connect button signals
	night_mode_checkbox.toggled.connect(_on_night_mode_toggled)
	power_fantasy_button.pressed.connect(_on_power_fantasy_pressed)
	easy_button.pressed.connect(_on_easy_pressed)
	normal_button.pressed.connect(_on_normal_pressed)
	hard_button.pressed.connect(_on_hard_pressed)
	back_button.pressed.connect(_on_back_pressed)

	# Update button states based on current difficulty
	_update_button_states()

	# Connect to difficulty changes
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager:
		difficulty_manager.difficulty_changed.connect(_on_difficulty_changed)

	# Connect to experimental settings changes (for night mode)
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		experimental_settings.settings_changed.connect(_on_settings_changed)

	# Set process mode to allow input while paused
	process_mode = Node.PROCESS_MODE_ALWAYS


func _update_button_states() -> void:
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager == null:
		return

	var is_easy: bool = difficulty_manager.is_easy_mode()
	var is_normal: bool = difficulty_manager.is_normal_mode()
	var is_hard: bool = difficulty_manager.is_hard_mode()
	var is_power_fantasy: bool = difficulty_manager.is_power_fantasy_mode()

	# Highlight current difficulty - disable the selected button
	power_fantasy_button.disabled = is_power_fantasy
	easy_button.disabled = is_easy
	normal_button.disabled = is_normal
	hard_button.disabled = is_hard

	# Update button text to show selection
	power_fantasy_button.text = "Power Fantasy (Selected)" if is_power_fantasy else "Power Fantasy"
	easy_button.text = "Easy (Selected)" if is_easy else "Easy"
	normal_button.text = "Normal (Selected)" if is_normal else "Normal"
	hard_button.text = "Hard (Selected)" if is_hard else "Hard"

	# Update night mode checkbox
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		night_mode_checkbox.button_pressed = experimental_settings.is_realistic_visibility_enabled()

	# Update status label based on current difficulty
	var status_text: String = ""
	if is_power_fantasy:
		status_text = "Power Fantasy: 10 HP, 3x ammo, blue lasers"
	elif is_easy:
		status_text = "Easy mode: Enemies react slower"
	elif is_hard:
		status_text = "Hard mode: Enemies react when you look away"
	else:
		status_text = "Normal mode: Classic gameplay"

	if experimental_settings and experimental_settings.is_realistic_visibility_enabled():
		status_text += " | Night Mode ON"

	status_label.text = status_text


func _on_night_mode_toggled(enabled: bool) -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		experimental_settings.set_realistic_visibility_enabled(enabled)
	_update_button_states()


func _on_power_fantasy_pressed() -> void:
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager:
		difficulty_manager.set_difficulty(difficulty_manager.Difficulty.POWER_FANTASY)
	_update_button_states()


func _on_easy_pressed() -> void:
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager:
		difficulty_manager.set_difficulty(difficulty_manager.Difficulty.EASY)
	_update_button_states()


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


func _on_settings_changed() -> void:
	_update_button_states()
