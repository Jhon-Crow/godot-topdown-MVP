extends Control
## Animated score screen with Hotline Miami 2 style sequential reveal.
##
## Features:
## - Sequential item reveal (each category appears after the previous one finishes)
## - Counting animation (numbers animate from 0 to final value)
## - Pulsing effect (color change and slight scale increase during counting)
## - Retro-style filling sound effect
## - Final rank animation (fullscreen flash → shrink to position)
##
## Usage:
##   var score_screen = AnimatedScoreScreen.new()
##   add_child(score_screen)
##   score_screen.show_score(score_data)

## Signal emitted when all animations are complete.
signal animation_complete

## Animation timing constants.
const TITLE_FADE_DURATION: float = 0.3
const ITEM_REVEAL_DURATION: float = 0.15
const ITEM_COUNT_DURATION: float = 0.8
const PULSE_FREQUENCY: float = 12.0  ## Pulses per second during counting
const RANK_FLASH_DURATION: float = 0.8
const RANK_SHRINK_DURATION: float = 0.6
const HINT_FADE_DURATION: float = 0.3

## Pulse animation settings.
const PULSE_SCALE_MIN: float = 1.0
const PULSE_SCALE_MAX: float = 1.15
const PULSE_COLOR_INTENSITY: float = 0.4

## Sound settings.
const BEEP_BASE_FREQUENCY: float = 440.0  ## Hz
const BEEP_DURATION: float = 0.03  ## Seconds per beep
const BEEP_VOLUME: float = -12.0  ## dB

## Rank colors for different grades.
const RANK_COLORS: Dictionary = {
	"S": Color(1.0, 0.84, 0.0, 1.0),   # Gold
	"A+": Color(0.0, 1.0, 0.5, 1.0),   # Bright green
	"A": Color(0.2, 0.8, 0.2, 1.0),    # Green
	"B": Color(0.3, 0.7, 1.0, 1.0),    # Blue
	"C": Color(1.0, 1.0, 1.0, 1.0),    # White
	"D": Color(1.0, 0.6, 0.2, 1.0),    # Orange
	"F": Color(1.0, 0.2, 0.2, 1.0)     # Red
}

## Flash colors for rank reveal background.
const FLASH_COLORS: Array[Color] = [
	Color(1.0, 0.0, 0.0, 0.9),   # Red
	Color(0.0, 1.0, 0.0, 0.9),   # Green
	Color(0.0, 0.0, 1.0, 0.9),   # Blue
	Color(1.0, 1.0, 0.0, 0.9),   # Yellow
	Color(1.0, 0.0, 1.0, 0.9),   # Magenta
	Color(0.0, 1.0, 1.0, 0.9)    # Cyan
]

## Internal references.
var _background: ColorRect
var _container: VBoxContainer
var _title_label: Label
var _score_items: Array[Dictionary] = []
var _rank_label: Label
var _rank_background: ColorRect
var _total_label: Label
var _hint_label: Label

## Animation state.
var _score_data: Dictionary = {}
var _current_item_index: int = -1
var _is_animating: bool = false
var _counting_value: float = 0.0
var _counting_target: int = 0
var _counting_label: Label = null
var _counting_points_label: Label = null
var _pulse_time: float = 0.0
var _original_color: Color = Color.WHITE

## Audio player for beep sounds.
var _beep_player: AudioStreamPlayer = null
var _beep_generator: AudioStreamGenerator = null
var _beep_playback: AudioStreamGeneratorPlayback = null
var _last_beep_value: int = -1


func _ready() -> void:
	# Print to console immediately - this is the most reliable way to confirm _ready() is called
	print("[AnimatedScoreScreen] _ready() STARTING - is_inside_tree: ", is_inside_tree())
	_log_debug("AnimatedScoreScreen _ready() called - is_inside_tree: %s" % str(is_inside_tree()))

	# Log parent info for debugging
	var parent_name := get_parent().name if get_parent() else "null"
	print("[AnimatedScoreScreen] Parent node: ", parent_name)
	_log_debug("Parent node: %s" % parent_name)

	# Set to cover full screen - must also set size to parent's size
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# Get the viewport size for proper sizing
	var viewport_size := get_viewport_rect().size
	print("[AnimatedScoreScreen] Viewport size: ", viewport_size)
	_log_debug("Viewport size: %s" % str(viewport_size))

	# Force size update to match viewport
	size = viewport_size
	_log_debug("Set size to: %s" % str(size))

	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Create beep audio player with generator
	_setup_beep_audio()

	print("[AnimatedScoreScreen] _ready() COMPLETED successfully")
	_log_debug("AnimatedScoreScreen _ready() completed")


func _process(delta: float) -> void:
	if not _is_animating:
		return

	# Handle counting animation
	if _counting_label != null and _counting_target > 0:
		_pulse_time += delta

		# Update counting value
		var count_progress := _counting_value / float(_counting_target)
		if count_progress < 1.0:
			_counting_value += (float(_counting_target) / ITEM_COUNT_DURATION) * delta
			_counting_value = minf(_counting_value, float(_counting_target))

			var current_int := int(_counting_value)
			_counting_label.text = _format_counting_value(current_int)

			# Play beep on value change (throttled)
			if current_int != _last_beep_value:
				_last_beep_value = current_int
				_play_beep()

			# Apply pulse effect
			_apply_pulse_effect()


## Setup the beep sound generator for retro-style counting sounds.
func _setup_beep_audio() -> void:
	_beep_player = AudioStreamPlayer.new()
	_beep_player.bus = "Master"
	_beep_player.volume_db = BEEP_VOLUME
	add_child(_beep_player)

	# Create generator stream
	_beep_generator = AudioStreamGenerator.new()
	_beep_generator.mix_rate = 44100.0
	_beep_generator.buffer_length = 0.1
	_beep_player.stream = _beep_generator


## Play a short major arpeggio sound.
## Major arpeggio: root, major third (+4 semitones), perfect fifth (+7 semitones)
func _play_beep() -> void:
	if _beep_player == null:
		return

	# Start playback if not already playing
	if not _beep_player.playing:
		_beep_player.play()
		_beep_playback = _beep_player.get_stream_playback()

	if _beep_playback == null:
		return

	# Generate a short major arpeggio (root, major third, perfect fifth)
	var sample_rate := _beep_generator.mix_rate
	var note_duration := BEEP_DURATION / 3.0  # Each note gets 1/3 of total duration
	var samples_per_note := int(note_duration * sample_rate)

	# Calculate frequencies for major arpeggio
	# Major third = root * 2^(4/12), Perfect fifth = root * 2^(7/12)
	var root_freq := BEEP_BASE_FREQUENCY + randf_range(-20.0, 20.0)
	var third_freq := root_freq * pow(2.0, 4.0 / 12.0)  # Major third
	var fifth_freq := root_freq * pow(2.0, 7.0 / 12.0)  # Perfect fifth

	var arpeggio_freqs := [root_freq, third_freq, fifth_freq]

	for note_idx in range(3):
		var frequency := arpeggio_freqs[note_idx]
		for i in range(samples_per_note):
			if _beep_playback.can_push_buffer(1):
				var t := float(i) / sample_rate
				# Square wave for retro sound
				var sample := 0.25 if fmod(t * frequency, 1.0) < 0.5 else -0.25
				# Apply envelope for each note (attack and decay)
				var note_progress := float(i) / float(samples_per_note)
				var envelope := 1.0 - (note_progress * 0.5)  # Gentle decay
				_beep_playback.push_frame(Vector2(sample * envelope, sample * envelope))


## Format counting value with sign and proper formatting.
func _format_counting_value(value: int) -> String:
	return "%d" % value


## Apply pulsing effect to the current counting label.
func _apply_pulse_effect() -> void:
	if _counting_points_label == null:
		return

	# Calculate pulse factor (0 to 1, oscillating)
	var pulse_factor := (sin(_pulse_time * PULSE_FREQUENCY * TAU) + 1.0) / 2.0

	# Apply scale pulse
	var scale_value := lerpf(PULSE_SCALE_MIN, PULSE_SCALE_MAX, pulse_factor)
	_counting_points_label.scale = Vector2(scale_value, scale_value)

	# Apply color pulse (interpolate toward white/bright)
	var pulse_color := _original_color.lerp(Color.WHITE, pulse_factor * PULSE_COLOR_INTENSITY)
	_counting_points_label.add_theme_color_override("font_color", pulse_color)


## Show the animated score screen with the given score data.
## @param score_data: Dictionary from ScoreManager.complete_level()
func show_score(score_data: Dictionary) -> void:
	# Print to console immediately for debugging
	print("[AnimatedScoreScreen] show_score() CALLED - rank: ", score_data.get("rank", "?"))
	print("[AnimatedScoreScreen] is_inside_tree: ", is_inside_tree(), ", visible: ", visible)

	_log_debug("show_score() called with data: %s" % str(score_data))
	_log_debug("Control properties - size: %s, position: %s, visible: %s, modulate: %s" % [
		str(size), str(position), str(visible), str(modulate)])
	_log_debug("Is in tree: %s, parent: %s" % [
		str(is_inside_tree()),
		get_parent().name if get_parent() else "null"])

	_score_data = score_data
	_is_animating = true

	# Create background - starts transparent, will animate to semi-opaque
	_background = ColorRect.new()
	_background.name = "ScoreBackground"
	_background.color = Color(0.0, 0.0, 0.0, 0.0)  # Starts fully transparent
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.visible = true  # Ensure visible
	add_child(_background)
	_log_debug("Background created - color.a: %f, visible: %s" % [_background.color.a, str(_background.visible)])

	# Create main container - starts invisible, will animate to visible
	_container = VBoxContainer.new()
	_container.name = "ScoreContainer"
	_container.set_anchors_preset(Control.PRESET_CENTER)
	_container.offset_left = -300
	_container.offset_right = 300
	_container.offset_top = -280
	_container.offset_bottom = 350
	_container.add_theme_constant_override("separation", 8)
	_container.modulate.a = 0.0  # Starts invisible, will animate to 1.0
	_container.visible = true  # Ensure visible property is set
	add_child(_container)
	_log_debug("Container created - modulate.a: %f, visible: %s, offsets: l=%d r=%d t=%d b=%d" % [
		_container.modulate.a, str(_container.visible), -300, 300, -280, 350])

	# Build score items list
	_build_score_items()
	_log_debug("Built %d score items" % _score_items.size())

	# Start animation sequence
	_animate_background_fade()
	_log_debug("Animation sequence started")


## Build the list of score items to display.
func _build_score_items() -> void:
	_score_items.clear()

	# Core score categories
	_score_items.append({
		"category": "KILLS",
		"value": "%d/%d" % [_score_data.get("kills", 0), _score_data.get("total_enemies", 0)],
		"points": _score_data.get("kill_points", 0),
		"is_positive": true
	})

	_score_items.append({
		"category": "COMBOS",
		"value": "Max x%d" % _score_data.get("max_combo", 0),
		"points": _score_data.get("combo_points", 0),
		"is_positive": true
	})

	_score_items.append({
		"category": "TIME",
		"value": "%.1fs" % _score_data.get("completion_time", 0.0),
		"points": _score_data.get("time_bonus", 0),
		"is_positive": true
	})

	_score_items.append({
		"category": "ACCURACY",
		"value": "%.1f%%" % _score_data.get("accuracy", 0.0),
		"points": _score_data.get("accuracy_bonus", 0),
		"is_positive": true
	})

	# Optional: Special kills
	var ricochet_kills: int = _score_data.get("ricochet_kills", 0)
	var penetration_kills: int = _score_data.get("penetration_kills", 0)
	if ricochet_kills > 0 or penetration_kills > 0:
		var special_text := ""
		if ricochet_kills > 0:
			special_text += "%d ricochet" % ricochet_kills
		if penetration_kills > 0:
			if special_text != "":
				special_text += ", "
			special_text += "%d penetration" % penetration_kills

		var special_eligible: bool = _score_data.get("special_kills_eligible", false)
		_score_items.append({
			"category": "SPECIAL KILLS",
			"value": special_text,
			"points": _score_data.get("special_kill_bonus", 0) if special_eligible else 0,
			"is_positive": special_eligible,
			"note": "" if special_eligible else "(need aggression)"
		})

	# Optional: Damage penalty
	var damage_taken: int = _score_data.get("damage_taken", 0)
	if damage_taken > 0:
		_score_items.append({
			"category": "DAMAGE TAKEN",
			"value": "%d hits" % damage_taken,
			"points": _score_data.get("damage_penalty", 0),
			"is_positive": false
		})


## Animate background fade in.
func _animate_background_fade() -> void:
	_log_debug("_animate_background_fade() starting")

	var tween := create_tween()
	if tween == null:
		_log_debug("ERROR: create_tween() returned null! Is node in tree: %s" % str(is_inside_tree()))
		# Fallback: directly set values without animation
		_background.color.a = 0.7
		_container.modulate.a = 1.0
		_create_title()
		return

	_log_debug("Tween created successfully, animating background and container")

	tween.tween_property(_background, "color:a", 0.7, TITLE_FADE_DURATION)
	tween.tween_property(_container, "modulate:a", 1.0, TITLE_FADE_DURATION)
	tween.tween_callback(_create_title)
	_log_debug("Tween animations queued")


## Create and animate the title.
func _create_title() -> void:
	_title_label = Label.new()
	_title_label.text = "LEVEL CLEARED!"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 42)
	_title_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3, 1.0))
	_title_label.modulate.a = 0.0
	_container.add_child(_title_label)

	var tween := create_tween()
	tween.tween_property(_title_label, "modulate:a", 1.0, TITLE_FADE_DURATION)
	tween.tween_callback(_start_item_sequence)


## Start the sequential item reveal.
func _start_item_sequence() -> void:
	_current_item_index = -1
	_animate_next_item()


## Animate the next score item in sequence.
func _animate_next_item() -> void:
	_current_item_index += 1

	if _current_item_index >= _score_items.size():
		# All items done, show total score
		_animate_total_score()
		return

	var item_data: Dictionary = _score_items[_current_item_index]
	_create_score_item_row(item_data)


## Create a score item row with animation.
func _create_score_item_row(item_data: Dictionary) -> void:
	var line_container := HBoxContainer.new()
	line_container.add_theme_constant_override("separation", 20)
	line_container.modulate.a = 0.0
	_container.add_child(line_container)

	# Category label
	var category_label := Label.new()
	category_label.text = item_data.category
	category_label.add_theme_font_size_override("font_size", 18)
	category_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
	category_label.custom_minimum_size.x = 150
	line_container.add_child(category_label)

	# Value label
	var value_label := Label.new()
	value_label.text = item_data.value
	value_label.add_theme_font_size_override("font_size", 18)
	value_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	value_label.custom_minimum_size.x = 150
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line_container.add_child(value_label)

	# Points label (will be animated)
	var points_label := Label.new()
	var points_value: int = item_data.points
	var is_positive: bool = item_data.is_positive
	var note: String = item_data.get("note", "")

	if note != "":
		points_label.text = note
		points_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 1.0))
	else:
		points_label.text = "0"
		if is_positive:
			points_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4, 1.0))
		else:
			points_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 1.0))

	points_label.add_theme_font_size_override("font_size", 18)
	points_label.custom_minimum_size.x = 100
	points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Set pivot for scaling from center
	points_label.pivot_offset = Vector2(50, 9)  # Approximate center
	line_container.add_child(points_label)

	# Fade in the row
	var tween := create_tween()
	tween.tween_property(line_container, "modulate:a", 1.0, ITEM_REVEAL_DURATION)

	# Start counting animation if has points
	if points_value > 0 and note == "":
		tween.tween_callback(func():
			_start_counting_animation(points_label, points_value, is_positive)
		)
	else:
		# No counting needed, proceed to next item
		tween.tween_interval(0.2)
		tween.tween_callback(_animate_next_item)


## Start the counting animation for a points label.
func _start_counting_animation(label: Label, target: int, is_positive: bool) -> void:
	_counting_label = label
	_counting_points_label = label
	_counting_target = target
	_counting_value = 0.0
	_pulse_time = 0.0
	_last_beep_value = -1

	# Store original color
	if is_positive:
		_original_color = Color(0.4, 1.0, 0.4, 1.0)
	else:
		_original_color = Color(1.0, 0.4, 0.4, 1.0)

	# Create timer to end counting
	var timer := get_tree().create_timer(ITEM_COUNT_DURATION)
	timer.timeout.connect(func():
		_finish_counting_animation(is_positive)
	)


## Finish the counting animation.
func _finish_counting_animation(is_positive: bool) -> void:
	if _counting_points_label != null:
		# Set final value with proper formatting
		var prefix := "+" if is_positive else "-"
		_counting_points_label.text = "%s%d" % [prefix, _counting_target]

		# Reset scale and color
		_counting_points_label.scale = Vector2.ONE
		_counting_points_label.add_theme_color_override("font_color", _original_color)

	_counting_label = null
	_counting_points_label = null
	_counting_target = 0
	_counting_value = 0.0

	# Proceed to next item after brief pause
	var tween := create_tween()
	tween.tween_interval(0.15)
	tween.tween_callback(_animate_next_item)


## Animate the total score display.
func _animate_total_score() -> void:
	# Add separator
	var separator := HSeparator.new()
	separator.add_theme_constant_override("separation", 15)
	separator.modulate.a = 0.0
	_container.add_child(separator)

	# Total score label
	_total_label = Label.new()
	_total_label.text = "TOTAL: 0"
	_total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_total_label.add_theme_font_size_override("font_size", 32)
	_total_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 1.0))
	_total_label.modulate.a = 0.0
	_total_label.pivot_offset = Vector2(150, 16)
	_container.add_child(_total_label)

	var tween := create_tween()
	tween.tween_property(separator, "modulate:a", 1.0, ITEM_REVEAL_DURATION)
	tween.tween_property(_total_label, "modulate:a", 1.0, ITEM_REVEAL_DURATION)
	tween.tween_callback(_start_total_counting)


## Start counting animation for total score.
func _start_total_counting() -> void:
	var total_score: int = _score_data.get("total_score", 0)
	_counting_label = _total_label
	_counting_points_label = _total_label
	_counting_target = total_score
	_counting_value = 0.0
	_pulse_time = 0.0
	_last_beep_value = -1
	_original_color = Color(1.0, 0.9, 0.3, 1.0)

	var timer := get_tree().create_timer(ITEM_COUNT_DURATION * 1.2)  # Slightly longer for total
	timer.timeout.connect(_finish_total_counting)


## Finish total score counting and show rank.
func _finish_total_counting() -> void:
	if _total_label != null:
		_total_label.text = "TOTAL: %d" % _score_data.get("total_score", 0)
		_total_label.scale = Vector2.ONE
		_total_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 1.0))

	_counting_label = null
	_counting_points_label = null

	var tween := create_tween()
	tween.tween_interval(0.3)
	tween.tween_callback(_start_rank_animation)


## Start the dramatic rank reveal animation.
func _start_rank_animation() -> void:
	var rank: String = _score_data.get("rank", "F")
	var rank_color: Color = RANK_COLORS.get(rank, Color.WHITE)

	# Create fullscreen flash background
	_rank_background = ColorRect.new()
	_rank_background.name = "RankFlashBackground"
	_rank_background.color = FLASH_COLORS[0]
	_rank_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rank_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rank_background.modulate.a = 0.0
	add_child(_rank_background)

	# Create large centered rank label
	_rank_label = Label.new()
	_rank_label.text = rank
	_rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rank_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_rank_label.add_theme_font_size_override("font_size", 200)
	_rank_label.add_theme_color_override("font_color", rank_color)
	_rank_label.set_anchors_preset(Control.PRESET_CENTER)
	_rank_label.offset_left = -150
	_rank_label.offset_right = 150
	_rank_label.offset_top = -120
	_rank_label.offset_bottom = 120
	_rank_label.modulate.a = 0.0
	add_child(_rank_label)

	# Animate flash background and rank appear
	var tween := create_tween()
	tween.tween_property(_rank_background, "modulate:a", 1.0, 0.1)
	tween.parallel().tween_property(_rank_label, "modulate:a", 1.0, 0.1)

	# Flash color cycling
	var flash_count := 6
	for i in range(flash_count):
		var color_index := (i + 1) % FLASH_COLORS.size()
		tween.tween_property(_rank_background, "color", FLASH_COLORS[color_index], RANK_FLASH_DURATION / float(flash_count))

	tween.tween_callback(_shrink_rank_to_position)


## Shrink the rank label to its final position.
func _shrink_rank_to_position() -> void:
	# Fade out flash background
	var tween := create_tween()
	tween.tween_property(_rank_background, "modulate:a", 0.0, RANK_SHRINK_DURATION * 0.5)

	# Calculate final position (below total, centered)
	var final_font_size := 48
	var final_offset_top := 250  # Below total score in container
	# Keep rank centered horizontally (symmetric offsets around center)
	var final_half_width := 75  # Half of the label width

	# Animate rank shrinking
	tween.parallel().tween_method(
		func(font_size: int): _rank_label.add_theme_font_size_override("font_size", font_size),
		200, final_font_size, RANK_SHRINK_DURATION
	)

	# Move to final position (centered horizontally, below total score)
	tween.parallel().tween_property(_rank_label, "offset_top", final_offset_top, RANK_SHRINK_DURATION)
	tween.parallel().tween_property(_rank_label, "offset_bottom", final_offset_top + 60, RANK_SHRINK_DURATION)
	tween.parallel().tween_property(_rank_label, "offset_left", -final_half_width, RANK_SHRINK_DURATION)
	tween.parallel().tween_property(_rank_label, "offset_right", final_half_width, RANK_SHRINK_DURATION)

	tween.tween_callback(_show_restart_hint)


## Show the restart hint after all animations complete.
func _show_restart_hint() -> void:
	_hint_label = Label.new()
	_hint_label.text = "\nPress Q to restart"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 16)
	_hint_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1.0))
	_hint_label.modulate.a = 0.0
	_container.add_child(_hint_label)

	var tween := create_tween()
	tween.tween_property(_hint_label, "modulate:a", 1.0, HINT_FADE_DURATION)
	tween.tween_callback(_on_animation_complete)


## Called when all animations are complete.
func _on_animation_complete() -> void:
	_is_animating = false
	animation_complete.emit()


## Get the rank color for a given rank string.
static func get_rank_color(rank: String) -> Color:
	return RANK_COLORS.get(rank, Color.WHITE)


## Log a debug message to the file logger if available.
## Uses the autoload pattern to ensure logging works even in dynamically created nodes.
func _log_debug(message: String) -> void:
	# Try to get FileLogger from autoload singleton pattern
	var file_logger: Node = null

	# Method 1: Try getting from scene tree root
	if is_inside_tree():
		file_logger = get_tree().root.get_node_or_null("FileLogger")

	# Method 2: Fallback to absolute path
	if file_logger == null:
		file_logger = get_node_or_null("/root/FileLogger")

	if file_logger != null and file_logger.has_method("log_info"):
		file_logger.log_info("[AnimatedScoreScreen] " + message)
	else:
		# Always print to console as fallback - this still helps debugging
		print("[AnimatedScoreScreen] " + message)
