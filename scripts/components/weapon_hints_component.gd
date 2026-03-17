extends Node
## WeaponHintsComponent - Shows weapon-specific tutorial hints when a new weapon is picked up.
##
## This component displays floating hints above the player explaining the unique
## features of each weapon. It respects the user's preference from WeaponHintsSettings:
## - ALWAYS: Show hints every time a weapon is picked up
## - FIRST_TIME_ONLY: Show hints only for first use of each weapon
## - NEVER: Never show hints
##
## Visual style matches the Labyrinth level tutorial hints:
## - Font size 20 with drop shadows
## - Per-hint colors matching Labyrinth palette
## - Fade-in/fade-out animation
## - Positioned via canvas_transform above player
##
## Issue #809: добавь обучение новому оружию (add weapon training)
##
## Usage:
##   1. Add this component to a level script
##   2. Call setup() with the player node and canvas layer
##   3. Component will automatically show hints when weapon is picked up (GameManager.weapon_selected)

class_name WeaponHintsComponent

## Reference to the player node.
var _player: Node2D = null

## Reference to the CanvasLayer for hints (matching Labyrinth style).
var _canvas_layer: Node = null

## Currently shown weapon ID.
var _current_weapon_id: String = ""

## Dictionary of active hint labels: hint_key -> RichTextLabel node.
var _hint_labels: Dictionary = {}

## Whether hints are currently being displayed.
var _hints_showing: bool = false

## Timer for auto-dismissing hints.
var _dismiss_timer: Timer = null

## Duration to show hints before auto-dismiss (seconds).
const HINT_DURATION: float = 8.0

## Vertical spacing between stacked hints (matches Labyrinth TUTORIAL_HINT_SPACING).
const HINT_SPACING: float = 60.0

## Vertical offset from player position (matches Labyrinth offset of -80).
const HINT_OFFSET_Y: float = -80.0

## Horizontal offset from player center (matches Labyrinth offset of -150).
const HINT_OFFSET_X: float = -150.0

## Minimum hint label size (matches Labyrinth custom_minimum_size).
const HINT_MIN_SIZE := Vector2(300, 30)

## Fade-in duration (matches Labyrinth TUTORIAL_HINT_FADE_IN_DURATION).
const HINT_FADE_IN_DURATION: float = 0.3

## Fade-out duration (matches Labyrinth TUTORIAL_HINT_FADE_OUT_DURATION).
const HINT_FADE_OUT_DURATION: float = 0.3

## Per-hint colors matching Labyrinth level color palette (Issue #945 style).
const HINT_COLORS: Dictionary = {
	"reload":           Color(0.4, 1.0, 0.5, 1.0),    ## Green — reload
	"fire_mode":        Color(0.3, 0.9, 1.0, 1.0),    ## Cyan — fire mode switch
	"bolt_cycle":       Color(0.85, 0.6, 1.0, 1.0),   ## Purple — bolt cycling / pump
	"scope":            Color(0.3, 0.9, 1.0, 1.0),    ## Cyan — scope aiming
	"hammer_cock":      Color(1.0, 0.8, 0.3, 1.0),    ## Yellow — hammer cock
	"launcher":         Color(1.0, 0.4, 0.2, 1.0),    ## Red-orange — grenade launcher
}

## Default color for unrecognized hint types.
const HINT_COLOR_DEFAULT := Color(1.0, 1.0, 0.3, 1.0)  ## Yellow fallback

## Weapon hint definitions.
## Each weapon has an array of hint objects with "hint_key", "color_key", and "text" fields.
## Issue #809: Uses same training strings as Labyrinth level (labyrinth_level.gd).
## Format: [color=#ff4444] for highlighted keys, Russian text only.
const WEAPON_HINTS: Dictionary = {
	"makarov_pm": [
		{"hint_key": "pm_reload",        "color_key": "reload",     "text": "[color=#ff4444][R][/color] [color=#888888][R][/color] Перезарядись"}
	],
	"m16": [
		{"hint_key": "m16_fire_mode",    "color_key": "fire_mode",  "text": "[color=#ff4444][B][/color] Переключи режим стрельбы"},
		{"hint_key": "m16_reload",       "color_key": "reload",     "text": "[color=#ff4444][R][/color] [color=#888888][F] [R][/color] Перезарядись"}
	],
	"shotgun": [
		{"hint_key": "shotgun_pump",     "color_key": "bolt_cycle", "text": "[color=#ff4444][ПКМ↑][/color] [color=#888888][ПКМ↓][/color] Передёрни затвор"},
		{"hint_key": "shotgun_reload",   "color_key": "reload",     "text": "[color=#ff4444][ПКМ↑ открыть][/color] [color=#888888][СКМ+ПКМ↓ xN] [ПКМ↓ закрыть][/color]"}
	],
	"mini_uzi": [
		{"hint_key": "uzi_reload",       "color_key": "reload",     "text": "[color=#ff4444][R][/color] [color=#888888][F] [R][/color] Перезарядись"}
	],
	"silenced_pistol": [
		{"hint_key": "silenced_reload",  "color_key": "reload",     "text": "[color=#ff4444][R][/color] [color=#888888][F] [R][/color] Перезарядись"}
	],
	"sniper": [
		{"hint_key": "sniper_scope",     "color_key": "scope",      "text": "[color=#ff4444][ПКМ][/color] Прицелься через оптику"},
		{"hint_key": "sniper_bolt",      "color_key": "bolt_cycle", "text": "[color=#ff4444][←][/color] [color=#888888][↓] [↑] [→][/color] Передёрни затвор"}
	],
	"revolver": [
		{"hint_key": "revolver_cylinder","color_key": "reload",     "text": "[color=#ff4444][R открыть][/color] [color=#888888][ПКМ↑ патрон] [скролл] [R закрыть][/color]"},
		{"hint_key": "revolver_hammer",  "color_key": "hammer_cock","text": "[color=#ff4444][ПКМ][/color] Взведи курок"}
	],
	"ak_gl": [
		{"hint_key": "akgl_launcher",    "color_key": "launcher",   "text": "[color=#ff4444][ПКМ][/color] Выстрели подствольным гранатомётом"},
		{"hint_key": "akgl_reload",      "color_key": "reload",     "text": "[color=#ff4444][R][/color] [color=#888888][F] [R][/color] Перезарядись"}
	]
}


func _ready() -> void:
	# Create dismiss timer
	_dismiss_timer = Timer.new()
	_dismiss_timer.one_shot = true
	_dismiss_timer.timeout.connect(_on_dismiss_timer_timeout)
	add_child(_dismiss_timer)


## Setup the component with required references.
## Connects to GameManager.weapon_selected to respond to weapon pickup/changes.
## Issue #809 req 2 & 3: show hints when weapon is picked up, support sequential changes.
## @param player: The player node to follow.
## @param canvas_layer: The CanvasLayer node to add hints to (matches Labyrinth style).
func setup(player: Node2D, canvas_layer: Node) -> void:
	_player = player
	_canvas_layer = canvas_layer

	if _player == null:
		push_warning("[WeaponHintsComponent] Player is null")
		return

	if _canvas_layer == null:
		push_warning("[WeaponHintsComponent] CanvasLayer is null")
		return

	# Connect to GameManager.weapon_selected to respond when weapon is picked up or changed.
	# This supports showing hints for each weapon taken in sequence (Issue #809 req 3).
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_signal("weapon_selected"):
		if not game_manager.weapon_selected.is_connected(_on_weapon_selected):
			game_manager.weapon_selected.connect(_on_weapon_selected)

	# Show hints for the weapon already selected when level starts.
	if game_manager and game_manager.has_method("get_selected_weapon"):
		var weapon_id: String = game_manager.get_selected_weapon()
		if not weapon_id.is_empty():
			_on_weapon_selected(weapon_id)


## Called every frame to update hint positions above the player.
func _process(_delta: float) -> void:
	if _hints_showing:
		_update_hint_positions()


## Called when GameManager emits weapon_selected (weapon picked up / changed).
## Dismisses current hints immediately and shows hints for the new weapon.
## Issue #809 req 2 & 3: responds to each weapon pickup, supports sequential changes.
func _on_weapon_selected(weapon_id: String) -> void:
	if weapon_id == _current_weapon_id:
		return

	# Dismiss any currently showing hints for the previous weapon
	if _hints_showing:
		_dismiss_hints_immediate()

	_current_weapon_id = weapon_id
	_try_show_hints()


## Try to show hints for the current weapon based on settings.
func _try_show_hints() -> void:
	if _current_weapon_id.is_empty():
		return

	var settings: Node = get_node_or_null("/root/WeaponHintsSettings")
	if settings == null:
		# Settings not available, default to showing hints
		_show_weapon_hints(_current_weapon_id)
		return

	if settings.should_show_hints(_current_weapon_id):
		_show_weapon_hints(_current_weapon_id)
		# Mark weapon as seen for FIRST_TIME_ONLY mode
		settings.mark_weapon_seen(_current_weapon_id)


## Show hints for a specific weapon.
## Uses Labyrinth-style visuals: canvas_transform positioning, shadows, per-hint colors, fade-in.
## @param weapon_id: The weapon identifier.
func _show_weapon_hints(weapon_id: String) -> void:
	if not weapon_id in WEAPON_HINTS:
		_log_to_file("No hints defined for weapon: %s" % weapon_id)
		return

	if _canvas_layer == null:
		push_warning("[WeaponHintsComponent] CanvasLayer is null, cannot show hints")
		return

	_log_to_file("Showing hints for weapon: %s" % weapon_id)

	var hints: Array = WEAPON_HINTS[weapon_id]
	for hint in hints:
		_show_hint(hint["hint_key"], hint["color_key"], hint["text"])

	_hints_showing = true
	_dismiss_timer.start(HINT_DURATION)


## Show a single hint label matching Labyrinth visual style.
## @param hint_key: Unique identifier for this hint.
## @param color_key: Key into HINT_COLORS for the label color.
## @param text: BBCode-formatted text to display.
func _show_hint(hint_key: String, color_key: String, text: String) -> void:
	if hint_key in _hint_labels:
		# Already showing this hint
		return

	var label := RichTextLabel.new()
	label.name = "WeaponHint_" + hint_key
	label.bbcode_enabled = true
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("normal_font_size", 20)

	# Per-hint color matching Labyrinth palette
	var hint_color: Color = HINT_COLORS.get(color_key, HINT_COLOR_DEFAULT)
	label.add_theme_color_override("default_color", hint_color)

	# Drop shadow matching Labyrinth style
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)

	label.custom_minimum_size = HINT_MIN_SIZE
	label.fit_content = true
	label.scroll_active = false

	# Start transparent for fade-in (matching Labyrinth Issue #944 animation)
	label.modulate.a = 0.0

	_canvas_layer.add_child(label)
	_hint_labels[hint_key] = label

	# Initial position
	_update_hint_positions()

	# Fade-in animation (matching Labyrinth TUTORIAL_HINT_FADE_IN_DURATION)
	var tween := create_tween()
	tween.tween_property(label, "modulate:a", 1.0, HINT_FADE_IN_DURATION).set_ease(Tween.EASE_OUT)


## Update positions of all hint labels to float above the player.
## Uses canvas_transform matching Labyrinth _update_tutorial_hint_positions().
func _update_hint_positions() -> void:
	if _player == null or not is_instance_valid(_player):
		return

	var canvas_transform: Transform2D = get_viewport().get_canvas_transform()
	var screen_pos: Vector2 = canvas_transform * _player.global_position

	var index := 0
	for hint_key in _hint_labels:
		var label: RichTextLabel = _hint_labels[hint_key]
		if label == null or not is_instance_valid(label):
			continue

		label.custom_minimum_size = HINT_MIN_SIZE
		label.position = screen_pos + Vector2(HINT_OFFSET_X, HINT_OFFSET_Y - index * HINT_SPACING)
		index += 1


## Dismiss all hints with fade-out animation.
func dismiss_hints() -> void:
	_dismiss_timer.stop()
	_hints_showing = false

	for hint_key in _hint_labels.keys():
		var label: RichTextLabel = _hint_labels[hint_key]
		if label != null and is_instance_valid(label):
			var tween := create_tween()
			tween.tween_property(label, "modulate:a", 0.0, HINT_FADE_OUT_DURATION).set_ease(Tween.EASE_IN)
			tween.tween_callback(label.queue_free)

	_hint_labels.clear()
	_log_to_file("All hints dismissed")


## Dismiss hints immediately without animation (used when weapon changes).
func _dismiss_hints_immediate() -> void:
	_dismiss_timer.stop()
	_hints_showing = false

	for hint_key in _hint_labels.keys():
		var label: RichTextLabel = _hint_labels[hint_key]
		if label != null and is_instance_valid(label):
			label.queue_free()

	_hint_labels.clear()
	_log_to_file("All hints dismissed immediately")


## Called when the dismiss timer times out.
func _on_dismiss_timer_timeout() -> void:
	dismiss_hints()


## Clean up when component is removed.
func _exit_tree() -> void:
	# Disconnect from GameManager to avoid dangling connections
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_signal("weapon_selected"):
		if game_manager.weapon_selected.is_connected(_on_weapon_selected):
			game_manager.weapon_selected.disconnect(_on_weapon_selected)

	# Free hint labels immediately (no animation needed on exit)
	for hint_key in _hint_labels.keys():
		var label: RichTextLabel = _hint_labels[hint_key]
		if label != null and is_instance_valid(label):
			label.queue_free()
	_hint_labels.clear()


## Log a message to the file logger if available.
func _log_to_file(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[WeaponHintsComponent] " + message)
	else:
		print("[WeaponHintsComponent] " + message)
