extends Node
## WeaponHintsComponent - Shows weapon-specific tutorial hints when equipping new weapons.
##
## This component displays floating hints above the player explaining the unique
## features of each weapon. It respects the user's preference from WeaponHintsSettings:
## - ALWAYS: Show hints every time
## - FIRST_TIME_ONLY: Show hints only for first use of each weapon
## - NEVER: Never show hints
##
## Issue #809: добавь обучение новому оружию (add weapon training)
##
## Usage:
##   1. Add this component to a level script
##   2. Call setup() with the player node and UI container
##   3. Component will automatically show hints based on current weapon

class_name WeaponHintsComponent

## Reference to the player node.
var _player: Node2D = null

## Reference to the UI container for hints.
var _ui: Control = null

## Currently equipped weapon ID.
var _current_weapon_id: String = ""

## Dictionary of active hint labels: hint_key -> RichTextLabel node.
var _hint_labels: Dictionary = {}

## Whether hints are currently being displayed.
var _hints_showing: bool = false

## Timer for auto-dismissing hints.
var _dismiss_timer: Timer = null

## Duration to show hints before auto-dismiss (seconds).
const HINT_DURATION: float = 8.0

## Vertical spacing between stacked hints.
const HINT_SPACING := 60

## Vertical offset from player position.
const HINT_OFFSET_Y := -100

## Hint color for weapon hints (light blue/cyan).
const HINT_COLOR := Color(0.5, 0.9, 1.0, 1.0)

## Weapon hint definitions.
## Each weapon has an array of hint objects with "key" and "text" fields.
const WEAPON_HINTS: Dictionary = {
	"makarov_pm": [
		{"key": "pm_reload", "text": "[color=yellow][R][/color] + [color=yellow][F][/color] + [color=yellow][R][/color] — перезарядка\n[R]+[F]+[R] — reload"}
	],
	"m16": [
		{"key": "m16_fire_mode", "text": "[color=yellow][B][/color] — переключение режима огня\n[B] — switch fire mode (auto/semi)"},
		{"key": "m16_reload", "text": "[color=yellow][R][/color] + [color=yellow][F][/color] + [color=yellow][R][/color] — перезарядка\n[R]+[F]+[R] — reload"}
	],
	"shotgun": [
		{"key": "shotgun_pump", "text": "После выстрела: [color=yellow][ПКМ↑][/color] для перезарядки затвора\nAfter shot: [color=yellow][RMB↑][/color] to pump"},
		{"key": "shotgun_reload", "text": "[color=yellow][ПКМ↑][/color] → [color=yellow][СКМ+ПКМ↓][/color] xN → [color=yellow][ПКМ↓][/color] — полная перезарядка\n[RMB↑] → [MMB+RMB↓] xN → [RMB↓] — full reload"}
	],
	"mini_uzi": [
		{"key": "uzi_rate", "text": "Высокая скорострельность — экономьте патроны!\nHigh fire rate — conserve ammo!"},
		{"key": "uzi_reload", "text": "[color=yellow][R][/color] + [color=yellow][F][/color] + [color=yellow][R][/color] — перезарядка\n[R]+[F]+[R] — reload"}
	],
	"silenced_pistol": [
		{"key": "silenced_stealth", "text": "Бесшумный — враги не услышат выстрелы\nSilenced — enemies won't hear shots"},
		{"key": "silenced_reload", "text": "[color=yellow][R][/color] + [color=yellow][F][/color] + [color=yellow][R][/color] — перезарядка\n[R]+[F]+[R] — reload"}
	],
	"sniper": [
		{"key": "sniper_scope", "text": "[color=yellow][ПКМ][/color] — прицел (удержание)\n[color=yellow][RMB][/color] — scope (hold)"},
		{"key": "sniper_bolt", "text": "[color=yellow][←][/color][color=yellow][↓][/color][color=yellow][↑][/color][color=yellow][→][/color] — перезарядка затвора\n[color=yellow][←][/color][color=yellow][↓][/color][color=yellow][↑][/color][color=yellow][→][/color] — bolt-action reload"}
	],
	"revolver": [
		{"key": "revolver_cylinder", "text": "[color=yellow][R][/color] — открыть барабан, [color=yellow][F][/color] xN — вставить патроны, [color=yellow][R][/color] — закрыть\n[R] — open cylinder, [F] xN — load rounds, [R] — close"},
		{"key": "revolver_hammer", "text": "[color=yellow][СКМ][/color] — взвести курок для точного выстрела\n[color=yellow][MMB][/color] — cock hammer for accurate shot"}
	],
	"ak_gl": [
		{"key": "akgl_launcher", "text": "[color=yellow][ПКМ][/color] — подствольный гранатомёт (когда заряжен)\n[color=yellow][RMB][/color] — underbarrel grenade launcher (when loaded)"},
		{"key": "akgl_reload", "text": "[color=yellow][R][/color] + [color=yellow][F][/color] + [color=yellow][R][/color] — перезарядка магазина\n[R]+[F]+[R] — magazine reload"}
	]
}


func _ready() -> void:
	# Create dismiss timer
	_dismiss_timer = Timer.new()
	_dismiss_timer.one_shot = true
	_dismiss_timer.timeout.connect(_on_dismiss_timer_timeout)
	add_child(_dismiss_timer)


## Setup the component with required references.
## @param player: The player node to follow.
## @param ui: The UI Control node to add hints to.
func setup(player: Node2D, ui: Control) -> void:
	_player = player
	_ui = ui

	if _player == null:
		push_warning("[WeaponHintsComponent] Player is null")
		return

	# Get current weapon from GameManager
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("get_selected_weapon"):
		_current_weapon_id = game_manager.get_selected_weapon()
		_try_show_hints()


## Called every frame to update hint positions.
func _process(_delta: float) -> void:
	if _hints_showing:
		_update_hint_positions()


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
## @param weapon_id: The weapon identifier.
func _show_weapon_hints(weapon_id: String) -> void:
	if not weapon_id in WEAPON_HINTS:
		_log_to_file("No hints defined for weapon: %s" % weapon_id)
		return

	if _ui == null:
		push_warning("[WeaponHintsComponent] UI is null, cannot show hints")
		return

	_log_to_file("Showing hints for weapon: %s" % weapon_id)

	var hints: Array = WEAPON_HINTS[weapon_id]
	for hint in hints:
		_show_hint(hint["key"], hint["text"])

	_hints_showing = true

	# Start dismiss timer
	_dismiss_timer.start(HINT_DURATION)


## Show a single hint with the given key and text.
## @param hint_key: Unique identifier for this hint.
## @param text: BBCode-formatted text to display.
func _show_hint(hint_key: String, text: String) -> void:
	if hint_key in _hint_labels:
		# Already showing this hint
		return

	var hint_label := RichTextLabel.new()
	hint_label.name = "WeaponHint_" + hint_key
	hint_label.bbcode_enabled = true
	hint_label.fit_content = true
	hint_label.scroll_active = false
	hint_label.autowrap_mode = TextServer.AUTOWRAP_OFF

	# Style the hint
	hint_label.add_theme_color_override("default_color", HINT_COLOR)
	hint_label.add_theme_font_size_override("normal_font_size", 16)

	# Center text
	hint_label.text = "[center]" + text + "[/center]"

	# Add semi-transparent background
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.7)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	hint_label.add_theme_stylebox_override("normal", style)

	# Add to UI
	_ui.add_child(hint_label)
	_hint_labels[hint_key] = hint_label

	# Initial position update
	_update_hint_positions()


## Update positions of all hint labels to follow the player.
func _update_hint_positions() -> void:
	if _player == null or not is_instance_valid(_player):
		return

	# Get player screen position
	var camera: Camera2D = _player.get_node_or_null("Camera2D")
	var screen_center := get_viewport().get_visible_rect().size / 2.0

	# Calculate position above player
	var hint_keys := _hint_labels.keys()
	var index := 0

	for hint_key in hint_keys:
		var label: RichTextLabel = _hint_labels[hint_key]
		if label == null or not is_instance_valid(label):
			continue

		# Center horizontally, stack vertically above player
		var label_size := label.size
		var x_pos := screen_center.x - label_size.x / 2.0
		var y_pos := screen_center.y + HINT_OFFSET_Y - (index * HINT_SPACING)

		label.position = Vector2(x_pos, y_pos)
		index += 1


## Dismiss all hints.
func dismiss_hints() -> void:
	for hint_key in _hint_labels.keys():
		var label: RichTextLabel = _hint_labels[hint_key]
		if label != null and is_instance_valid(label):
			label.queue_free()

	_hint_labels.clear()
	_hints_showing = false
	_dismiss_timer.stop()
	_log_to_file("All hints dismissed")


## Called when the dismiss timer times out.
func _on_dismiss_timer_timeout() -> void:
	dismiss_hints()


## Clean up when component is removed.
func _exit_tree() -> void:
	dismiss_hints()


## Log a message to the file logger if available.
func _log_to_file(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[WeaponHintsComponent] " + message)
	else:
		print("[WeaponHintsComponent] " + message)
