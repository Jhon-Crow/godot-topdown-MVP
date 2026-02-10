extends Node2D
class_name ActiveItemProgressBar
## Progress bar displayed above the player for active items with limited usage.
##
## Supports two display modes:
## - Segmented: Shows discrete charge segments (e.g., teleport bracers with 6 charges).
## - Continuous: Shows a smooth progress bar for time-limited items.
##
## The bar is drawn using _draw() for lightweight rendering without UI nodes.
## Position is set relative to the parent (typically the Player node).

## Display mode for the progress bar.
enum DisplayMode {
	SEGMENTED,  # Discrete charge segments (for charge-limited items)
	CONTINUOUS  # Smooth progress bar (for time-limited items)
}

## Current display mode.
var display_mode: int = DisplayMode.SEGMENTED

## Current value (charges remaining or time remaining).
var current_value: float = 0.0

## Maximum value (max charges or max time).
var max_value: float = 1.0

## Whether the progress bar is currently visible.
var is_visible: bool = false

## Width of the progress bar in pixels.
const BAR_WIDTH: float = 40.0

## Height of the progress bar in pixels.
const BAR_HEIGHT: float = 6.0

## Vertical offset above the player center (negative = above).
const BAR_Y_OFFSET: float = -30.0

## Gap between segments in segmented mode.
const SEGMENT_GAP: float = 2.0

## Border width for the bar outline.
const BORDER_WIDTH: float = 1.0

## Background color of the bar.
const COLOR_BACKGROUND: Color = Color(0.1, 0.1, 0.1, 0.6)

## Border color.
const COLOR_BORDER: Color = Color(0.3, 0.3, 0.3, 0.7)

## Fill color when value is above 50%.
const COLOR_FILL_HIGH: Color = Color(0.2, 0.8, 0.4, 0.85)

## Fill color when value is between 25% and 50%.
const COLOR_FILL_MEDIUM: Color = Color(0.9, 0.7, 0.1, 0.85)

## Fill color when value is below 25%.
const COLOR_FILL_LOW: Color = Color(0.9, 0.2, 0.2, 0.85)

## Fill color for empty segments in segmented mode.
const COLOR_SEGMENT_EMPTY: Color = Color(0.2, 0.2, 0.2, 0.4)


## Show the progress bar with the given parameters.
## @param mode: DisplayMode.SEGMENTED or DisplayMode.CONTINUOUS
## @param current: Current value (charges or time remaining).
## @param maximum: Maximum value (max charges or max time).
func show_bar(mode: int, current: float, maximum: float) -> void:
	display_mode = mode
	current_value = current
	max_value = maxf(maximum, 0.001)  # Prevent division by zero
	is_visible = true
	queue_redraw()


## Hide the progress bar.
func hide_bar() -> void:
	is_visible = false
	queue_redraw()


## Update the current value without changing mode or max.
## @param current: New current value.
func update_value(current: float) -> void:
	current_value = current
	if is_visible:
		queue_redraw()


## Get the fill color based on the current percentage.
func _get_fill_color() -> Color:
	if max_value <= 0.0:
		return COLOR_FILL_LOW
	var percent: float = current_value / max_value
	if percent > 0.5:
		return COLOR_FILL_HIGH
	elif percent > 0.25:
		return COLOR_FILL_MEDIUM
	else:
		return COLOR_FILL_LOW


func _draw() -> void:
	if not is_visible:
		return

	if display_mode == DisplayMode.SEGMENTED:
		_draw_segmented_bar()
	else:
		_draw_continuous_bar()


## Draw a segmented progress bar (discrete charges).
func _draw_segmented_bar() -> void:
	var segment_count: int = int(max_value)
	if segment_count <= 0:
		return

	var filled_count: int = int(current_value)
	var total_gaps: float = SEGMENT_GAP * float(segment_count - 1) if segment_count > 1 else 0.0
	var segment_width: float = (BAR_WIDTH - total_gaps) / float(segment_count)

	# Ensure minimum segment width
	if segment_width < 2.0:
		segment_width = 2.0

	var start_x: float = -BAR_WIDTH / 2.0
	var fill_color: Color = _get_fill_color()

	for i in range(segment_count):
		var seg_x: float = start_x + float(i) * (segment_width + SEGMENT_GAP)
		var seg_rect := Rect2(seg_x, BAR_Y_OFFSET, segment_width, BAR_HEIGHT)

		# Draw segment background
		draw_rect(seg_rect, COLOR_BACKGROUND)

		# Draw segment fill or empty
		if i < filled_count:
			draw_rect(seg_rect, fill_color)
		else:
			draw_rect(seg_rect, COLOR_SEGMENT_EMPTY)

		# Draw segment border
		draw_rect(seg_rect, COLOR_BORDER, false, BORDER_WIDTH)


## Draw a continuous progress bar (time-based).
func _draw_continuous_bar() -> void:
	var bar_rect := Rect2(-BAR_WIDTH / 2.0, BAR_Y_OFFSET, BAR_WIDTH, BAR_HEIGHT)

	# Draw background
	draw_rect(bar_rect, COLOR_BACKGROUND)

	# Draw filled portion
	if max_value > 0.0 and current_value > 0.0:
		var fill_ratio: float = clampf(current_value / max_value, 0.0, 1.0)
		var fill_width: float = BAR_WIDTH * fill_ratio
		var fill_rect := Rect2(-BAR_WIDTH / 2.0, BAR_Y_OFFSET, fill_width, BAR_HEIGHT)
		var fill_color: Color = _get_fill_color()
		draw_rect(fill_rect, fill_color)

	# Draw border
	draw_rect(bar_rect, COLOR_BORDER, false, BORDER_WIDTH)
