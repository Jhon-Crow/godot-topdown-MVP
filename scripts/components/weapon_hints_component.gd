extends Node
## WeaponHintsComponent - Shows weapon-specific tutorial hints when a new weapon is picked up.
##
## This component displays floating hints above the player explaining the unique
## features of each weapon. It respects the user's preference from WeaponHintsSettings:
## - ALWAYS: Show hints every time a weapon is picked up
## - FIRST_TIME_ONLY: Show hints only for first use of each weapon
## - NEVER: Never show hints
##
## Visual style exactly matches the Labyrinth level tutorial hints (labyrinth_level.gd):
## - Font size 20 with drop shadows
## - Per-hint colors matching Labyrinth palette
## - Fade-in animation
## - Progressive strikethrough via Line2D (Issue #944 / #1080 style)
## - Strikethrough-then-fade-out dismiss animation
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

## Strikethrough animation duration (matches Labyrinth TUTORIAL_HINT_STRIKETHROUGH_DURATION).
const HINT_STRIKETHROUGH_DURATION: float = 0.4

## Fade-out duration (matches Labyrinth TUTORIAL_HINT_FADE_OUT_DURATION).
const HINT_FADE_OUT_DURATION: float = 0.3

## Issue #944 style: Tracks hints currently being animated (prevents double-dismiss).
var _animating_hints: Dictionary = {}

## Issue #944 style: Track Line2D strikethrough nodes for each hint (hint_key -> Array[Line2D]).
## Each hint has one Line2D per text line so lines animate independently without connectors.
var _hint_strike_lines: Dictionary = {}

## Issue #944 style: Track current strikethrough progress for each hint (hint_key -> float 0.0-1.0).
var _hint_strike_progress: Dictionary = {}

## Issue #944 style: Track line count for each hint (hint_key -> int).
var _hint_line_counts: Dictionary = {}

## Issue #1080 style: Track per-line text widths for each hint (hint_key -> Array[float]).
var _hint_line_widths: Dictionary = {}

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

	# Connect to GameManager signals to respond when weapon is picked up or changed.
	# weapon_unlocked: fired when a weapon pickup object is collected for the first time.
	#   We reset the "seen" flag here so FIRST_TIME_ONLY mode will show hints on unlock.
	# weapon_selected: fired when the active weapon changes (after unlock or manual switch).
	#   We show hints here so the display is triggered on the actual weapon equip event.
	# This supports showing hints for each weapon taken in sequence (Issue #809 req 2 & 3).
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager:
		if game_manager.has_signal("weapon_unlocked"):
			if not game_manager.weapon_unlocked.is_connected(_on_weapon_unlocked):
				game_manager.weapon_unlocked.connect(_on_weapon_unlocked)
		if game_manager.has_signal("weapon_selected"):
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


## Called when GameManager emits weapon_unlocked (weapon picked up from the game world).
## Resets the "seen" flag for this weapon so FIRST_TIME_ONLY mode will display hints.
## Issue #809 req 2: hints appear when weapon is picked up (unlocked) for the first time.
func _on_weapon_unlocked(weapon_id: String) -> void:
	var settings: Node = get_node_or_null("/root/WeaponHintsSettings")
	if settings and settings.has_method("reset_weapon_seen"):
		settings.reset_weapon_seen(weapon_id)
	_log_to_file("Weapon unlocked, reset seen flag: %s" % weapon_id)


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
## Uses Labyrinth-style visuals: strikethrough Line2D, per-hint colors, fade-in/strikethrough/fade-out.
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
		_add_hint(hint["hint_key"], hint["color_key"], hint["text"])

	_hints_showing = true
	_dismiss_timer.start(HINT_DURATION)


## Add a single hint label with Labyrinth-style BBCode, shadows, fade-in, and strikethrough Line2D.
## Mirrors labyrinth_level.gd _add_tutorial_hint().
## @param hint_key: Unique identifier for this hint.
## @param color_key: Key into HINT_COLORS for the label color.
## @param text: BBCode-formatted text to display.
func _add_hint(hint_key: String, color_key: String, text: String) -> void:
	if hint_key in _hint_labels:
		# Already showing this hint — update text if not animating
		if not _animating_hints.has(hint_key):
			_hint_labels[hint_key].text = text
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

	# Initialize strikethrough tracking (matching Labyrinth Issue #944 style)
	_hint_strike_lines[hint_key] = []
	_hint_strike_progress[hint_key] = 0.0

	# Set up Line2D strikethrough nodes after one frame so layout is computed
	_setup_strikethrough_lines.call_deferred(hint_key, label)

	# Position immediately
	var index := _hint_labels.size() - 1
	var canvas_transform: Transform2D = get_viewport().get_canvas_transform()
	var screen_pos: Vector2 = canvas_transform * (_player.global_position if _player else Vector2.ZERO)
	label.custom_minimum_size = HINT_MIN_SIZE
	label.position = screen_pos + Vector2(HINT_OFFSET_X, HINT_OFFSET_Y - index * HINT_SPACING)

	# Fade-in animation (matching Labyrinth TUTORIAL_HINT_FADE_IN_DURATION)
	var tween := create_tween()
	tween.tween_property(label, "modulate:a", 1.0, HINT_FADE_IN_DURATION).set_ease(Tween.EASE_OUT)

	_log_to_file("Hint added '%s': %s" % [hint_key, text])


## Set up one Line2D per text line after label layout is ready (deferred).
## Mirrors labyrinth_level.gd _setup_tutorial_strikethrough_lines().
## Issue #1080 style: computes per-line text widths so strikethrough matches actual text length.
func _setup_strikethrough_lines(hint_key: String, label: RichTextLabel) -> void:
	if not is_instance_valid(label):
		return

	# Font size 20 with default line spacing gives ~26px per line.
	const LINE_HEIGHT := 26.0

	var content_height := label.get_content_height()
	var line_count := maxi(1, roundi(content_height / LINE_HEIGHT))
	_hint_line_counts[hint_key] = line_count

	# Compute per-line text widths using font metrics (Issue #1080 style).
	var line_widths: Array = []
	var font: Font = label.get_theme_font("normal_font")
	var font_size: int = label.get_theme_font_size("normal_font_size")
	if is_instance_valid(font) and font_size > 0:
		var plain_text: String = label.get_parsed_text()
		var per_line_text: Array = []
		for _i in range(line_count):
			per_line_text.append("")
		var char_count: int = plain_text.length()
		for char_idx in range(char_count):
			var visual_line: int = label.get_character_line(char_idx)
			if visual_line >= 0 and visual_line < line_count:
				per_line_text[visual_line] += plain_text[char_idx]
		for line_idx in range(line_count):
			var w: float = font.get_string_size(per_line_text[line_idx], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			line_widths.append(maxf(w, 1.0))
	else:
		# Fallback: use label content width for all lines.
		var fallback_width: float = label.get_content_width()
		if fallback_width <= 0:
			fallback_width = label.custom_minimum_size.x
		if fallback_width <= 0:
			fallback_width = 300.0
		for _i in range(line_count):
			line_widths.append(fallback_width)
	_hint_line_widths[hint_key] = line_widths

	# Create one Line2D per text line to avoid diagonal connectors between lines.
	var lines: Array = []
	for line_idx in range(line_count):
		var line_y := line_idx * LINE_HEIGHT + LINE_HEIGHT * 0.55
		var seg := Line2D.new()
		seg.name = "StrikeLine_%s_%d" % [hint_key, line_idx]
		seg.width = 1.5
		seg.default_color = Color(0.6, 0.6, 0.6, 0.6)
		seg.z_index = 1
		seg.add_point(Vector2(0, line_y))
		seg.add_point(Vector2(0, line_y))
		label.add_child(seg)
		lines.append(seg)

	_hint_strike_lines[hint_key] = lines
	_log_to_file("Setup strikethrough for '%s': %d lines, widths: %s" % [hint_key, line_count, str(line_widths)])


## Update per-line Line2D end points for multi-line strikethrough.
## Mirrors labyrinth_level.gd _update_tutorial_strikethrough_points().
func _update_strikethrough_points(strike_lines: Array, line_count: int, line_widths: Array, progress: float) -> void:
	for line_idx in range(line_count):
		if line_idx >= strike_lines.size():
			break
		var seg: Line2D = strike_lines[line_idx]
		if not is_instance_valid(seg):
			continue

		var line_start_progress := float(line_idx) / line_count
		var line_end_progress := float(line_idx + 1) / line_count
		var line_progress: float

		if progress <= line_start_progress:
			line_progress = 0.0
		elif progress >= line_end_progress:
			line_progress = 1.0
		else:
			line_progress = (progress - line_start_progress) / (line_end_progress - line_start_progress)

		var line_width: float = line_widths[line_idx] if line_idx < line_widths.size() else 300.0
		seg.set_point_position(1, Vector2(line_width * line_progress, seg.get_point_position(0).y))


## Dismiss a single hint with strikethrough-then-fade-out animation.
## Mirrors labyrinth_level.gd _dismiss_tutorial_hint() + _animate_tutorial_hint_strikethrough_and_fade().
func _dismiss_hint(hint_key: String) -> void:
	if not _hint_labels.has(hint_key):
		return

	# Prevent double-dismiss while animating
	if _animating_hints.has(hint_key):
		return

	var label: RichTextLabel = _hint_labels[hint_key]
	if not is_instance_valid(label):
		_hint_labels.erase(hint_key)
		return

	_animating_hints[hint_key] = true
	_log_to_file("Dismissing hint '%s' (strikethrough animation)" % hint_key)

	# Get strike lines and widths
	var strike_lines: Array = _hint_strike_lines.get(hint_key, [])
	var line_widths: Array = _hint_line_widths.get(hint_key, [])
	if line_widths.is_empty():
		var fallback_width: float = label.get_content_width()
		if fallback_width <= 0:
			fallback_width = label.custom_minimum_size.x
		if fallback_width <= 0:
			fallback_width = 300.0
		var line_count_fb: int = _hint_line_counts.get(hint_key, 1)
		for _i in range(line_count_fb):
			line_widths.append(fallback_width)

	var line_count: int = _hint_line_counts.get(hint_key, 1)
	var current_progress: float = _hint_strike_progress.get(hint_key, 0.0)

	var tween := create_tween()

	if not strike_lines.is_empty():
		tween.tween_method(
			func(progress: float):
				_update_strikethrough_points(strike_lines, line_count, line_widths, progress),
			current_progress, 1.0, HINT_STRIKETHROUGH_DURATION
		).set_ease(Tween.EASE_OUT)

	# After strikethrough, fade out the label
	tween.tween_property(label, "modulate:a", 0.0, HINT_FADE_OUT_DURATION).set_ease(Tween.EASE_IN)
	tween.tween_callback(_finalize_hint_dismiss.bind(hint_key, label))


## Finalize hint removal after animation completes.
## Mirrors labyrinth_level.gd _finalize_tutorial_hint_dismiss().
func _finalize_hint_dismiss(hint_key: String, label: RichTextLabel) -> void:
	_animating_hints.erase(hint_key)
	_hint_labels.erase(hint_key)
	_hint_strike_lines.erase(hint_key)
	_hint_strike_progress.erase(hint_key)
	_hint_line_counts.erase(hint_key)
	_hint_line_widths.erase(hint_key)
	if is_instance_valid(label):
		label.queue_free()
	_log_to_file("Hint '%s' dismissed (animation complete)" % hint_key)


## Dismiss all hints with strikethrough-then-fade-out animation.
func dismiss_hints() -> void:
	_dismiss_timer.stop()
	_hints_showing = false

	for hint_key in _hint_labels.keys():
		_dismiss_hint(hint_key)

	_log_to_file("All hints dismissed")


## Dismiss hints immediately without animation (used when weapon changes mid-display).
func _dismiss_hints_immediate() -> void:
	_dismiss_timer.stop()
	_hints_showing = false

	for hint_key in _hint_labels.keys():
		var label: RichTextLabel = _hint_labels[hint_key]
		if label != null and is_instance_valid(label):
			label.queue_free()

	_hint_labels.clear()
	_hint_strike_lines.clear()
	_hint_strike_progress.clear()
	_hint_line_counts.clear()
	_hint_line_widths.clear()
	_animating_hints.clear()
	_log_to_file("All hints dismissed immediately")


## Update positions of all hint labels to float above the player.
## Mirrors labyrinth_level.gd _update_tutorial_hint_positions().
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


## Called when the dismiss timer times out — dismiss all with strikethrough animation.
func _on_dismiss_timer_timeout() -> void:
	dismiss_hints()


## Clean up when component is removed.
func _exit_tree() -> void:
	# Disconnect from GameManager to avoid dangling connections
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager:
		if game_manager.has_signal("weapon_unlocked"):
			if game_manager.weapon_unlocked.is_connected(_on_weapon_unlocked):
				game_manager.weapon_unlocked.disconnect(_on_weapon_unlocked)
		if game_manager.has_signal("weapon_selected"):
			if game_manager.weapon_selected.is_connected(_on_weapon_selected):
				game_manager.weapon_selected.disconnect(_on_weapon_selected)

	# Free hint labels immediately (no animation needed on exit)
	for hint_key in _hint_labels.keys():
		var label: RichTextLabel = _hint_labels[hint_key]
		if label != null and is_instance_valid(label):
			label.queue_free()
	_hint_labels.clear()
	_hint_strike_lines.clear()
	_hint_strike_progress.clear()
	_hint_line_counts.clear()
	_hint_line_widths.clear()
	_animating_hints.clear()


## Log a message to the file logger if available.
func _log_to_file(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[WeaponHintsComponent] " + message)
	else:
		print("[WeaponHintsComponent] " + message)
