extends CanvasLayer
## Language selection submenu (Issue #1718).
##
## Allows the player to switch between English and Russian.
## The selected locale is applied immediately and persisted across sessions.

## Signal emitted when the back button is pressed.
signal back_pressed

@onready var menu_container: Control = $MenuContainer
@onready var english_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/EnglishButton
@onready var russian_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/RussianButton
@onready var back_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/BackButton


func _ready() -> void:
	english_button.pressed.connect(_on_english_pressed)
	russian_button.pressed.connect(_on_russian_pressed)
	back_button.pressed.connect(_on_back_pressed)

	_refresh_buttons()

	var loc: Node = get_node_or_null("/root/LocalizationSettings")
	if loc and loc.has_signal("locale_changed"):
		loc.locale_changed.connect(_on_locale_changed)

	process_mode = Node.PROCESS_MODE_ALWAYS


## Highlights the button for the currently active locale.
func _refresh_buttons() -> void:
	var loc: Node = get_node_or_null("/root/LocalizationSettings")
	var current: String = "en"
	if loc:
		current = loc.get_locale()

	_set_button_selected(english_button, current == "en")
	_set_button_selected(russian_button, current == "ru")


func _set_button_selected(button: Button, selected: bool) -> void:
	if selected:
		button.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0))
	else:
		button.remove_theme_color_override("font_color")


func _on_english_pressed() -> void:
	var loc: Node = get_node_or_null("/root/LocalizationSettings")
	if loc:
		loc.set_locale("en")


func _on_russian_pressed() -> void:
	var loc: Node = get_node_or_null("/root/LocalizationSettings")
	if loc:
		loc.set_locale("ru")


func _on_locale_changed(_new_locale: String) -> void:
	_refresh_buttons()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func _on_back_pressed() -> void:
	back_pressed.emit()
