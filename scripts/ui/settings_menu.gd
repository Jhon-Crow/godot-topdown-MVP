extends CanvasLayer
## Settings submenu for the pause menu (Issue #1139).
##
## Provides a single entry point for all settings:
## - Controls
## - Difficulty
## - Sound
## - Gameplay
## - Performance (includes wall hit particles, AI toggles - Issue #1186)
## - Dev
## - Language (Issue #1718)

## Signal emitted when the back button is pressed.
signal back_pressed

## References to sub-menu scenes (set via export or preloaded in _ready).
@export var controls_menu_scene: PackedScene
@export var difficulty_menu_scene: PackedScene
@export var sound_menu_scene: PackedScene
@export var gameplay_menu_scene: PackedScene
@export var performance_menu_scene: PackedScene
@export var experimental_menu_scene: PackedScene
@export var language_menu_scene: PackedScene

## Instantiated sub-menus.
var _controls_menu: CanvasLayer = null
var _difficulty_menu: CanvasLayer = null
var _sound_menu: CanvasLayer = null
var _gameplay_menu: CanvasLayer = null
var _performance_menu: CanvasLayer = null
var _experimental_menu: CanvasLayer = null
var _language_menu: CanvasLayer = null

## Reference to the menu container (hidden when a sub-menu is open).
@onready var menu_container: Control = $MenuContainer
@onready var controls_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/ControlsButton
@onready var difficulty_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/DifficultyButton
@onready var sound_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/SoundButton
@onready var gameplay_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/GameplayButton
@onready var performance_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/PerformanceButton
@onready var experimental_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/ExperimentalButton
@onready var language_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/LanguageButton
@onready var back_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/BackButton


func _ready() -> void:
	# Setup short-name tooltips for category buttons (Issue #1200)
	controls_button.tooltip_text = tr("CONTROLS")
	difficulty_button.tooltip_text = tr("DIFFICULTY")
	sound_button.tooltip_text = tr("SOUND")
	gameplay_button.tooltip_text = tr("GAMEPLAY")
	experimental_button.tooltip_text = tr("DEV")
	performance_button.tooltip_text = tr("PERFORMANCE")
	language_button.tooltip_text = tr("LANGUAGE")

	controls_button.pressed.connect(_on_controls_pressed)
	difficulty_button.pressed.connect(_on_difficulty_pressed)
	sound_button.pressed.connect(_on_sound_pressed)
	gameplay_button.pressed.connect(_on_gameplay_pressed)
	performance_button.pressed.connect(_on_performance_pressed)
	experimental_button.pressed.connect(_on_experimental_pressed)
	language_button.pressed.connect(_on_language_pressed)
	back_button.pressed.connect(_on_back_pressed)

	if controls_menu_scene == null:
		controls_menu_scene = preload("res://scenes/ui/ControlsMenu.tscn")
	if difficulty_menu_scene == null:
		difficulty_menu_scene = preload("res://scenes/ui/DifficultyMenu.tscn")
	if sound_menu_scene == null:
		sound_menu_scene = preload("res://scenes/ui/SoundMenu.tscn")
	if gameplay_menu_scene == null:
		gameplay_menu_scene = preload("res://scenes/ui/GameplayMenu.tscn")
	if performance_menu_scene == null:
		performance_menu_scene = preload("res://scenes/ui/PerformanceMenu.tscn")
	if experimental_menu_scene == null:
		experimental_menu_scene = preload("res://scenes/ui/ExperimentalMenu.tscn")
	if language_menu_scene == null:
		language_menu_scene = preload("res://scenes/ui/LanguageMenu.tscn")

	process_mode = Node.PROCESS_MODE_ALWAYS


func _on_controls_pressed() -> void:
	menu_container.hide()
	if _controls_menu == null:
		_controls_menu = controls_menu_scene.instantiate()
		_controls_menu.back_pressed.connect(_on_sub_back.bind(_controls_menu, controls_button))
		add_child(_controls_menu)
	else:
		_controls_menu.show()


func _on_difficulty_pressed() -> void:
	menu_container.hide()
	if _difficulty_menu == null:
		_difficulty_menu = difficulty_menu_scene.instantiate()
		_difficulty_menu.back_pressed.connect(_on_sub_back.bind(_difficulty_menu, difficulty_button))
		add_child(_difficulty_menu)
	else:
		_difficulty_menu.show()


func _on_sound_pressed() -> void:
	menu_container.hide()
	if _sound_menu == null:
		_sound_menu = sound_menu_scene.instantiate()
		_sound_menu.back_pressed.connect(_on_sub_back.bind(_sound_menu, sound_button))
		add_child(_sound_menu)
	else:
		_sound_menu.show()


func _on_gameplay_pressed() -> void:
	menu_container.hide()
	if _gameplay_menu == null:
		_gameplay_menu = gameplay_menu_scene.instantiate()
		_gameplay_menu.back_pressed.connect(_on_sub_back.bind(_gameplay_menu, gameplay_button))
		add_child(_gameplay_menu)
	else:
		_gameplay_menu.show()


func _on_performance_pressed() -> void:
	menu_container.hide()
	if _performance_menu == null:
		_performance_menu = performance_menu_scene.instantiate()
		_performance_menu.back_pressed.connect(_on_sub_back.bind(_performance_menu, performance_button))
		add_child(_performance_menu)
	else:
		_performance_menu.show()


func _on_experimental_pressed() -> void:
	menu_container.hide()
	if _experimental_menu == null:
		_experimental_menu = experimental_menu_scene.instantiate()
		_experimental_menu.back_pressed.connect(_on_sub_back.bind(_experimental_menu, experimental_button))
		add_child(_experimental_menu)
	else:
		_experimental_menu.show()


func _on_language_pressed() -> void:
	menu_container.hide()
	if _language_menu == null:
		_language_menu = language_menu_scene.instantiate()
		_language_menu.back_pressed.connect(_on_sub_back.bind(_language_menu, language_button))
		add_child(_language_menu)
	else:
		_language_menu.show()


## Generic back handler for all sub-menus.
func _on_sub_back(sub_menu: CanvasLayer, focus_button: Button) -> void:
	if sub_menu:
		sub_menu.hide()
	menu_container.show()
	focus_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause") and menu_container.visible:
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func _on_back_pressed() -> void:
	back_pressed.emit()
