extends Node
## Animated Score Screen for Hotline Miami 2 Style Statistics Display.
##
## Issue #415: Statistics items should appear gradually like in Hotline Miami 2.
## Features:
## - Sequential reveal: Items appear one after another
## - Counting animation: Numbers animate from 0 to final value with pulsing
## - Sound effects: Retro beeps during counting
## - Dramatic rank reveal: Fullscreen with flashing background, then shrinks
##
## Usage:
##   var score_screen = load("res://scripts/ui/animated_score_screen.gd").new()
##   parent_node.add_child(score_screen)
##   score_screen.show_animated_score(ui_node, score_data)
##   score_screen.animation_completed.connect(func(c): add_buttons(c))


## Emitted when all score animations are complete and the container is ready for buttons.
signal animation_completed(container: VBoxContainer)

## Audio player for score counting beeps (created on demand).
var _score_audio_player: AudioStreamPlayer = null

## Duration for counting animation per stat item (seconds).
const SCORE_COUNT_DURATION: float = 1.5

## Delay between stat items appearing (seconds).
const SCORE_ITEM_DELAY: float = 0.25

## Duration for rank reveal fullscreen animation (seconds).
const RANK_REVEAL_DURATION: float = 1.5

## Duration for rank shrink animation (seconds).
const RANK_SHRINK_DURATION: float = 0.5

## Flashing colors for rank reveal background.
const RANK_FLASH_COLORS: Array[Color] = [
	Color(1.0, 0.0, 0.0, 0.9),   # Red
	Color(0.0, 1.0, 0.0, 0.9),   # Green
	Color(0.0, 0.0, 1.0, 0.9),   # Blue
	Color(1.0, 1.0, 0.0, 0.9),   # Yellow
	Color(1.0, 0.0, 1.0, 0.9),   # Magenta
	Color(0.0, 1.0, 1.0, 0.9),   # Cyan
]

## Rank order from lowest to highest (for total score color progression).
const RANK_ORDER: Array[String] = ["F", "D", "C", "B", "A", "A+", "S"]

## Rank score thresholds as ratio of max possible score (matching ScoreManager).
const RANK_THRESHOLDS: Dictionary = {
	"S": 1.0,
	"A+": 0.85,
	"A": 0.70,
	"B": 0.55,
	"C": 0.38,
	"D": 0.22,
	"F": 0.0
}

## Speed of gradient animation on rank background (radians per second).
const RANK_BG_GRADIENT_SPEED: float = 2.5

## Base frequency for score beeps (Hz).
const BEEP_BASE_FREQUENCY: float = 440.0

## Major scale intervals for arpeggio (in semitones).
const MAJOR_ARPEGGIO: Array[int] = [0, 4, 7, 12, 16, 19, 24]


## Creates a simple sine wave beep sound and plays it.
## @param frequency: The frequency of the beep in Hz.
## @param duration: Duration of the beep in seconds.
## @param volume_db: Volume in decibels (default -10).
func _play_beep(frequency: float, duration: float = 0.05, volume_db: float = -10.0) -> void:
	if _score_audio_player == null:
		_score_audio_player = AudioStreamPlayer.new()
		_score_audio_player.bus = "Master"
		add_child(_score_audio_player)

	# Create a simple AudioStreamGenerator for the beep
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 44100.0
	generator.buffer_length = 0.1

	_score_audio_player.stream = generator
	_score_audio_player.volume_db = volume_db
	_score_audio_player.play()

	var playback: AudioStreamGeneratorPlayback = _score_audio_player.get_stream_playback()

	# Generate sine wave samples
	var sample_rate: float = 44100.0
	var num_samples: int = int(duration * sample_rate)

	for i in range(num_samples):
		var t: float = float(i) / sample_rate
		# Sine wave with envelope (fade out)
		var envelope: float = 1.0 - (float(i) / float(num_samples))
		envelope = envelope * envelope  # Quadratic falloff
		var sample: float = sin(2.0 * PI * frequency * t) * envelope * 0.3
		playback.push_frame(Vector2(sample, sample))


## Plays a series of ascending beeps (major arpeggio) for rank reveal.
func _play_rank_arpeggio() -> void:
	for i in range(MAJOR_ARPEGGIO.size()):
		var semitones: int = MAJOR_ARPEGGIO[i]
		var frequency: float = BEEP_BASE_FREQUENCY * pow(2.0, float(semitones) / 12.0)
		# Delay each note slightly
		get_tree().create_timer(i * 0.08).timeout.connect(
			func(): _play_beep(frequency, 0.15, -8.0)
		)


## Show the animated score screen.
## @param ui: The Control node to add UI elements to.
## @param score_data: Dictionary containing all score components from ScoreManager.
func show_animated_score(ui: Control, score_data: Dictionary) -> void:
	# Create a semi-transparent background
	var background := ColorRect.new()
	background.name = "ScoreBackground"
	background.color = Color(0.0, 0.0, 0.0, 0.85)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(background)

	# Create a container for all score elements
	var container := VBoxContainer.new()
	container.name = "ScoreContainer"
	container.set_anchors_preset(Control.PRESET_CENTER)
	container.offset_left = -300
	container.offset_right = 300
	container.offset_top = -280
	container.offset_bottom = 280
	container.add_theme_constant_override("separation", 8)
	ui.add_child(container)

	# Prepare the breakdown data
	var breakdown_data := _prepare_breakdown_data(score_data)

	# Start the animated sequence
	_animate_score_sequence(ui, container, score_data, breakdown_data)


## Prepares the breakdown data array for display.
## @param score_data: Dictionary containing all score components.
## @returns: Array of arrays [category, value_text, points_value, is_penalty]
func _prepare_breakdown_data(score_data: Dictionary) -> Array:
	var breakdown_data: Array = []

	# Basic stats
	breakdown_data.append(["KILLS", "%d/%d" % [score_data.kills, score_data.total_enemies], score_data.kill_points, false])
	breakdown_data.append(["COMBOS", "Max x%d" % score_data.max_combo, score_data.combo_points, false])
	breakdown_data.append(["TIME", "%.1fs" % score_data.completion_time, score_data.time_bonus, false])
	breakdown_data.append(["ACCURACY", "%.1f%%" % score_data.accuracy, score_data.accuracy_bonus, false])

	# Special kills (if any)
	if score_data.ricochet_kills > 0 or score_data.penetration_kills > 0:
		var special_text := ""
		if score_data.ricochet_kills > 0:
			special_text += "%d ricochet" % score_data.ricochet_kills
		if score_data.penetration_kills > 0:
			if special_text != "":
				special_text += ", "
			special_text += "%d penetration" % score_data.penetration_kills
		if score_data.special_kills_eligible:
			breakdown_data.append(["SPECIAL KILLS", special_text, score_data.special_kill_bonus, false])
		else:
			breakdown_data.append(["SPECIAL KILLS", special_text, 0, false])

	# Damage penalty (if any)
	if score_data.damage_taken > 0:
		breakdown_data.append(["DAMAGE TAKEN", "%d hits" % score_data.damage_taken, score_data.damage_penalty, true])

	return breakdown_data


## Animates the entire score sequence.
func _animate_score_sequence(ui: Control, container: VBoxContainer, score_data: Dictionary, breakdown_data: Array) -> void:
	var delay: float = 0.0

	# 1. Title appears with fade-in
	delay = _animate_title(container, delay)

	# 2. Separator
	delay = _animate_separator(container, delay)

	# 3. Each stat item appears sequentially with counting animation
	for i in range(breakdown_data.size()):
		delay = _animate_stat_row(container, breakdown_data[i], delay, i)

	# 4. Total score appears with counting
	delay = _animate_total_score(container, score_data, delay)

	# 5. Dramatic rank reveal
	delay += 0.3  # Small pause before rank
	_animate_rank_reveal(ui, container, score_data, delay)

	# 6. Restart hint (appears after rank animation)
	get_tree().create_timer(delay + RANK_REVEAL_DURATION + RANK_SHRINK_DURATION + 0.5).timeout.connect(
		func(): _show_restart_hint(container)
	)


## Animates the title appearing.
func _animate_title(container: VBoxContainer, start_delay: float) -> float:
	var title_label := Label.new()
	title_label.text = "LEVEL CLEARED!"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 42)
	title_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3, 1.0))
	title_label.modulate.a = 0.0  # Start invisible
	container.add_child(title_label)

	# Fade in with scale pop
	get_tree().create_timer(start_delay).timeout.connect(
		func():
			var tween := create_tween()
			tween.set_parallel(true)
			tween.tween_property(title_label, "modulate:a", 1.0, 0.3)
			tween.tween_property(title_label, "scale", Vector2(1.0, 1.0), 0.3).from(Vector2(0.5, 0.5))
			_play_beep(BEEP_BASE_FREQUENCY * 2.0, 0.1, -8.0)
	)

	return start_delay + 0.4


## Animates a separator line.
func _animate_separator(container: VBoxContainer, start_delay: float) -> float:
	var separator := HSeparator.new()
	separator.add_theme_constant_override("separation", 15)
	separator.modulate.a = 0.0
	container.add_child(separator)

	get_tree().create_timer(start_delay).timeout.connect(
		func():
			var tween := create_tween()
			tween.tween_property(separator, "modulate:a", 1.0, 0.2)
	)

	return start_delay + 0.25


## Animates a single stat row with counting effect.
func _animate_stat_row(container: VBoxContainer, data: Array, start_delay: float, index: int) -> float:
	var line_container := HBoxContainer.new()
	line_container.add_theme_constant_override("separation", 20)
	line_container.modulate.a = 0.0  # Start invisible
	container.add_child(line_container)

	# Category label
	var category_label := Label.new()
	category_label.text = data[0]
	category_label.add_theme_font_size_override("font_size", 18)
	category_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
	category_label.custom_minimum_size.x = 150
	line_container.add_child(category_label)

	# Value label
	var value_label := Label.new()
	value_label.text = data[1]
	value_label.add_theme_font_size_override("font_size", 18)
	value_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	value_label.custom_minimum_size.x = 150
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line_container.add_child(value_label)

	# Points label (will be animated)
	var points_label := Label.new()
	points_label.text = "0"
	points_label.add_theme_font_size_override("font_size", 18)
	var is_penalty: bool = data[3]
	var base_color: Color = Color(1.0, 0.4, 0.4, 1.0) if is_penalty else Color(0.4, 1.0, 0.4, 1.0)
	points_label.add_theme_color_override("font_color", base_color)
	points_label.custom_minimum_size.x = 100
	points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line_container.add_child(points_label)

	var target_points: int = data[2]
	var prefix: String = "-" if is_penalty else "+"

	# Animate the row appearing and points counting
	get_tree().create_timer(start_delay).timeout.connect(
		func():
			# Fade in the row
			var tween := create_tween()
			tween.tween_property(line_container, "modulate:a", 1.0, 0.15)

			# Start counting animation
			_animate_points_counting(points_label, target_points, prefix, base_color, index)
	)

	return start_delay + SCORE_COUNT_DURATION + SCORE_ITEM_DELAY


## Animates the points counting with pulsing effect and sound.
func _animate_points_counting(label: Label, target: int, prefix: String, base_color: Color, pitch_offset: int) -> void:
	if target == 0:
		label.text = prefix + "0"
		return

	var start_time := Time.get_ticks_msec() / 1000.0
	var duration: float = SCORE_COUNT_DURATION
	var last_beep_value: int = -1
	var beep_interval: int = maxi(1, target / 10)  # Beep every ~10% of progress

	# Create a timer to update the counting
	var timer := Timer.new()
	timer.wait_time = 0.016  # ~60 FPS
	timer.one_shot = false
	add_child(timer)

	timer.timeout.connect(
		func():
			var elapsed: float = (Time.get_ticks_msec() / 1000.0) - start_time
			var progress: float = minf(elapsed / duration, 1.0)
			# Ease out for satisfying feel
			var eased_progress: float = 1.0 - pow(1.0 - progress, 3.0)

			var current_value: int = int(float(target) * eased_progress)
			label.text = prefix + str(current_value)

			# Pulse effect during counting
			var pulse: float = sin(elapsed * 20.0) * 0.5 + 0.5
			var pulse_color: Color = base_color.lerp(Color.WHITE, pulse * 0.3)
			label.add_theme_color_override("font_color", pulse_color)

			# Scale pulse
			var scale_pulse: float = 1.0 + sin(elapsed * 15.0) * 0.05
			label.scale = Vector2(scale_pulse, scale_pulse)

			# Play beep at intervals
			if current_value / beep_interval > last_beep_value / beep_interval:
				last_beep_value = current_value
				var pitch: float = BEEP_BASE_FREQUENCY * (1.0 + float(pitch_offset) * 0.1 + progress * 0.5)
				_play_beep(pitch, 0.03, -15.0)

			# Animation complete
			if progress >= 1.0:
				label.text = prefix + str(target)
				label.add_theme_color_override("font_color", base_color)
				label.scale = Vector2(1.0, 1.0)

				# Final "landing" beep
				var final_pitch: float = BEEP_BASE_FREQUENCY * (1.5 + float(pitch_offset) * 0.1)
				_play_beep(final_pitch, 0.08, -10.0)

				timer.stop()
				timer.queue_free()
	)

	timer.start()


## Animates the total score with counting.
## The total score color changes through rank colors (F→S) as the value counts up.
func _animate_total_score(container: VBoxContainer, score_data: Dictionary, start_delay: float) -> float:
	# Add separator before total
	var separator := HSeparator.new()
	separator.add_theme_constant_override("separation", 15)
	separator.modulate.a = 0.0
	container.add_child(separator)

	# Total score label - starts with F rank color (red)
	var total_label := Label.new()
	total_label.text = "TOTAL: 0"
	total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	total_label.add_theme_font_size_override("font_size", 32)
	total_label.add_theme_color_override("font_color", _get_rank_color("F"))
	total_label.modulate.a = 0.0
	container.add_child(total_label)

	var target_score: int = score_data.total_score
	var max_possible: int = score_data.max_possible_score

	get_tree().create_timer(start_delay).timeout.connect(
		func():
			# Fade in separator and label
			var tween := create_tween()
			tween.set_parallel(true)
			tween.tween_property(separator, "modulate:a", 1.0, 0.2)
			tween.tween_property(total_label, "modulate:a", 1.0, 0.2)

			# Animate the total counting with rank color progression
			_animate_total_counting(total_label, target_score, max_possible)
	)

	return start_delay + SCORE_COUNT_DURATION + 0.3


## Animates the total score counting with rank color progression.
## As the score counts up, the color transitions through rank colors (F→D→C→B→A→A+→S)
## based on the current counting value relative to max possible score.
func _animate_total_counting(label: Label, target: int, max_possible: int) -> void:
	var start_time := Time.get_ticks_msec() / 1000.0
	var duration: float = SCORE_COUNT_DURATION * 1.5  # Longer for total
	var last_beep_value: int = -1
	var beep_interval: int = maxi(1, target / 20)

	var timer := Timer.new()
	timer.wait_time = 0.016
	timer.one_shot = false
	add_child(timer)

	timer.timeout.connect(
		func():
			var elapsed: float = (Time.get_ticks_msec() / 1000.0) - start_time
			var progress: float = minf(elapsed / duration, 1.0)
			var eased_progress: float = 1.0 - pow(1.0 - progress, 4.0)

			var current_value: int = int(float(target) * eased_progress)
			label.text = "TOTAL: %d" % current_value

			# Determine rank color based on current counting value
			var score_ratio: float = 0.0
			if max_possible > 0:
				score_ratio = float(current_value) / float(max_possible)
			var current_rank: String = _get_rank_for_score_ratio(score_ratio)
			var base_color: Color = _get_rank_color(current_rank)

			# Pulse effect during counting
			var pulse: float = sin(elapsed * 25.0) * 0.5 + 0.5
			var pulse_color: Color = base_color.lerp(Color.WHITE, pulse * 0.5)
			label.add_theme_color_override("font_color", pulse_color)

			# Scale pulse
			var scale_pulse: float = 1.0 + sin(elapsed * 20.0) * 0.08
			label.scale = Vector2(scale_pulse, scale_pulse)

			# Play beep at intervals
			if current_value / beep_interval > last_beep_value / beep_interval:
				last_beep_value = current_value
				var pitch: float = BEEP_BASE_FREQUENCY * (1.2 + progress * 0.8)
				_play_beep(pitch, 0.04, -12.0)

			if progress >= 1.0:
				label.text = "TOTAL: %d" % target
				# Final color matches the actual rank
				var final_ratio: float = 0.0
				if max_possible > 0:
					final_ratio = float(target) / float(max_possible)
				var final_rank: String = _get_rank_for_score_ratio(final_ratio)
				label.add_theme_color_override("font_color", _get_rank_color(final_rank))
				label.scale = Vector2(1.0, 1.0)
				_play_beep(BEEP_BASE_FREQUENCY * 2.5, 0.15, -8.0)
				timer.stop()
				timer.queue_free()
	)

	timer.start()


## Animates the dramatic rank reveal (fullscreen then shrinks).
func _animate_rank_reveal(ui: Control, container: VBoxContainer, score_data: Dictionary, start_delay: float) -> void:
	var rank: String = score_data.rank
	var rank_color := _get_rank_color(rank)

	# Create fullscreen flashing background
	var flash_bg := ColorRect.new()
	flash_bg.name = "RankFlashBackground"
	flash_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_bg.color = Color(0.0, 0.0, 0.0, 0.0)  # Start invisible
	flash_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(flash_bg)

	# Create animated gradient background covering the entire screen
	var rank_bg := ColorRect.new()
	rank_bg.name = "RankGradientBackground"
	rank_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	rank_bg.color = Color(0.0, 0.0, 0.0, 0.0)  # Start invisible
	rank_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(rank_bg)

	# Create large centered rank label
	var big_rank_label := Label.new()
	big_rank_label.name = "BigRankLabel"
	big_rank_label.text = rank
	big_rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_rank_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	big_rank_label.add_theme_font_size_override("font_size", 200)
	big_rank_label.add_theme_color_override("font_color", rank_color)
	big_rank_label.set_anchors_preset(Control.PRESET_CENTER)
	big_rank_label.offset_left = -200
	big_rank_label.offset_right = 200
	big_rank_label.offset_top = -150
	big_rank_label.offset_bottom = 150
	big_rank_label.modulate.a = 0.0  # Start invisible
	ui.add_child(big_rank_label)

	# Create final rank label in container (starts invisible)
	var final_rank_label := Label.new()
	final_rank_label.name = "FinalRankLabel"
	final_rank_label.text = "RANK: %s" % rank
	final_rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	final_rank_label.add_theme_font_size_override("font_size", 48)
	final_rank_label.add_theme_color_override("font_color", rank_color)
	final_rank_label.modulate.a = 0.0
	container.add_child(final_rank_label)

	get_tree().create_timer(start_delay).timeout.connect(
		func():
			# Play arpeggio
			_play_rank_arpeggio()

			# Start flashing background
			_flash_rank_background(flash_bg, RANK_REVEAL_DURATION)

			# Start animated gradient behind big rank letter
			_animate_rank_gradient_background(rank_bg, rank_color)

			# Fade in big rank label with scale and fullscreen gradient background
			var tween := create_tween()
			tween.set_parallel(true)
			tween.tween_property(big_rank_label, "modulate:a", 1.0, 0.2)
			tween.tween_property(big_rank_label, "scale", Vector2(1.0, 1.0), 0.3).from(Vector2(3.0, 3.0))
			tween.tween_property(rank_bg, "modulate:a", 1.0, 0.2)

			# After flash duration, shrink rank to position
			get_tree().create_timer(RANK_REVEAL_DURATION).timeout.connect(
				func():
					# Fade out flash background
					var fade_tween := create_tween()
					fade_tween.tween_property(flash_bg, "color:a", 0.0, 0.3)

					# Shrink big rank letter and fade out gradient background
					var shrink_tween := create_tween()
					shrink_tween.set_parallel(true)
					shrink_tween.tween_property(big_rank_label, "scale", Vector2(0.3, 0.3), RANK_SHRINK_DURATION)
					shrink_tween.tween_property(big_rank_label, "modulate:a", 0.0, RANK_SHRINK_DURATION)
					shrink_tween.tween_property(rank_bg, "modulate:a", 0.0, RANK_SHRINK_DURATION)

					# Show final rank in container (no gradient background)
					shrink_tween.tween_property(final_rank_label, "modulate:a", 1.0, RANK_SHRINK_DURATION)

					# Clean up after animation
					shrink_tween.chain().tween_callback(
						func():
							flash_bg.queue_free()
							big_rank_label.queue_free()
							rank_bg.queue_free()
					)
			)
	)


## Flashes the background with contrasting colors.
func _flash_rank_background(bg: ColorRect, duration: float) -> void:
	var start_time := Time.get_ticks_msec() / 1000.0
	var color_index: int = 0

	var timer := Timer.new()
	timer.wait_time = 0.08  # Flash rate
	timer.one_shot = false
	add_child(timer)

	timer.timeout.connect(
		func():
			var elapsed: float = (Time.get_ticks_msec() / 1000.0) - start_time
			if elapsed >= duration:
				timer.stop()
				timer.queue_free()
				return

			color_index = (color_index + 1) % RANK_FLASH_COLORS.size()
			bg.color = RANK_FLASH_COLORS[color_index]
	)

	timer.start()


## Shows the restart hint at the end of the animation and emits animation_completed.
func _show_restart_hint(container: VBoxContainer) -> void:
	# Emit signal so callers can add buttons (e.g., Watch Replay)
	animation_completed.emit(container)

	var hint_label := Label.new()
	hint_label.text = "\nPress Q to restart"
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 16)
	hint_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1.0))
	hint_label.modulate.a = 0.0
	container.add_child(hint_label)

	var tween := create_tween()
	tween.tween_property(hint_label, "modulate:a", 1.0, 0.5)


## Get the color for a given rank.
func _get_rank_color(rank: String) -> Color:
	match rank:
		"S":
			return Color(1.0, 0.84, 0.0, 1.0)  # Gold
		"A+":
			return Color(0.0, 1.0, 0.5, 1.0)  # Bright green
		"A":
			return Color(0.2, 0.8, 0.2, 1.0)  # Green
		"B":
			return Color(0.3, 0.7, 1.0, 1.0)  # Blue
		"C":
			return Color(1.0, 1.0, 1.0, 1.0)  # White
		"D":
			return Color(1.0, 0.6, 0.2, 1.0)  # Orange
		"F":
			return Color(1.0, 0.2, 0.2, 1.0)  # Red
		_:
			return Color(1.0, 1.0, 1.0, 1.0)  # Default white


## Get contrasting colors for animated gradient background behind a rank letter.
## Generates colors by shifting the hue away from the rank color to ensure contrast.
## @param rank_color: The color of the rank letter text.
## @returns: Array of 3 contrasting colors for the gradient animation.
func _get_contrasting_colors(rank_color: Color) -> Array[Color]:
	var h: float = rank_color.h
	var s: float = rank_color.s
	# Use high saturation and moderate value for vibrant contrasting backgrounds
	var bg_s: float = maxf(s, 0.7)
	var bg_v: float = 0.5

	# For white/low-saturation rank colors (like C rank), use darker vivid colors
	if s < 0.2:
		bg_s = 0.9
		bg_v = 0.4

	# Shift hue by 120 and 240 degrees for maximum contrast (triadic colors)
	var c1 := Color.from_hsv(fmod(h + 0.33, 1.0), bg_s, bg_v, 0.85)
	var c2 := Color.from_hsv(fmod(h + 0.55, 1.0), bg_s, bg_v, 0.85)
	var c3 := Color.from_hsv(fmod(h + 0.78, 1.0), bg_s, bg_v, 0.85)

	return [c1, c2, c3]


## Animate gradient background behind the rank label using contrasting colors.
## Creates a smoothly cycling color animation on the background ColorRect.
## @param bg: The ColorRect to animate.
## @param rank_color: The rank letter color (used to calculate contrasting colors).
func _animate_rank_gradient_background(bg: ColorRect, rank_color: Color) -> void:
	var colors := _get_contrasting_colors(rank_color)
	var start_time := Time.get_ticks_msec() / 1000.0

	var timer := Timer.new()
	timer.wait_time = 0.016  # ~60 FPS for smooth gradient
	timer.one_shot = false
	add_child(timer)

	timer.timeout.connect(
		func():
			if not is_instance_valid(bg) or not bg.is_inside_tree():
				timer.stop()
				timer.queue_free()
				return

			var elapsed: float = (Time.get_ticks_msec() / 1000.0) - start_time
			var t: float = elapsed * RANK_BG_GRADIENT_SPEED

			# Smoothly cycle between the 3 contrasting colors
			var cycle: float = fmod(t, 3.0)
			var color: Color
			if cycle < 1.0:
				color = colors[0].lerp(colors[1], cycle)
			elif cycle < 2.0:
				color = colors[1].lerp(colors[2], cycle - 1.0)
			else:
				color = colors[2].lerp(colors[0], cycle - 2.0)

			bg.color = color
	)

	timer.start()


## Get the rank corresponding to a given score ratio (score / max_possible_score).
## Used for animating total score color through grade progression.
## @param score_ratio: The ratio of current score to max possible score (0.0 to 1.0+).
## @returns: The rank string for the given ratio.
func _get_rank_for_score_ratio(score_ratio: float) -> String:
	if score_ratio >= RANK_THRESHOLDS["S"]:
		return "S"
	elif score_ratio >= RANK_THRESHOLDS["A+"]:
		return "A+"
	elif score_ratio >= RANK_THRESHOLDS["A"]:
		return "A"
	elif score_ratio >= RANK_THRESHOLDS["B"]:
		return "B"
	elif score_ratio >= RANK_THRESHOLDS["C"]:
		return "C"
	elif score_ratio >= RANK_THRESHOLDS["D"]:
		return "D"
	else:
		return "F"
