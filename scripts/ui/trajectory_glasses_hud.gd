extends Node2D
## Progress bar HUD for the trajectory glasses (Issue #744).
##
## Displays charge pips and remaining time above the player.
## Visible while effect is active and shows countdown timer.

## Vertical offset above the player center (negative = above).
const OFFSET_Y: float = -40.0

## Width of each charge pip in pixels.
const PIP_WIDTH: float = 10.0

## Height of each charge pip in pixels.
const PIP_HEIGHT: float = 4.0

## Gap between pips.
const PIP_GAP: float = 3.0

## Color for filled (available) charge pips.
const PIP_FILLED_COLOR: Color = Color(0.0, 1.0, 0.5, 0.9)  # Greenish

## Color for empty (used) charge pips.
const PIP_EMPTY_COLOR: Color = Color(0.3, 0.3, 0.3, 0.5)

## Timer bar width.
const TIMER_BAR_WIDTH: float = 40.0

## Timer bar height.
const TIMER_BAR_HEIGHT: float = 3.0

## Timer bar vertical offset from pips.
const TIMER_BAR_OFFSET_Y: float = 8.0

## Timer bar fill color.
const TIMER_FILL_COLOR: Color = Color(0.0, 1.0, 0.0, 0.8)

## Timer bar background color.
const TIMER_BG_COLOR: Color = Color(0.2, 0.2, 0.2, 0.5)

## Current charges.
var _charges: int = 2

## Maximum charges.
var _max_charges: int = 2

## Effect duration for timer calculation.
var _effect_duration: float = 10.0

## Reference to the trajectory glasses effect.
var _effect: Node = null


func _ready() -> void:
	# Start hidden
	visible = false
	z_index = 10


## Initialize with effect reference.
func initialize(effect: Node) -> void:
	_effect = effect
	if _effect:
		_charges = _effect.charges
		_max_charges = _effect.MAX_CHARGES
		_effect_duration = _effect.EFFECT_DURATION


## Update charges display.
func update_charges(current: int, maximum: int) -> void:
	_charges = current
	_max_charges = maximum
	queue_redraw()


## Show/hide the HUD based on effect state.
func set_active(active: bool) -> void:
	visible = active
	queue_redraw()


func _process(_delta: float) -> void:
	# Keep position at offset above parent
	position = Vector2(0.0, OFFSET_Y)

	# Update visibility based on effect state
	if _effect:
		if _effect.is_active != visible:
			visible = _effect.is_active
		if visible:
			queue_redraw()


func _draw() -> void:
	if _max_charges <= 0:
		return

	# Draw charge pips
	var total_pip_width: float = _max_charges * PIP_WIDTH + (_max_charges - 1) * PIP_GAP
	var start_x: float = -total_pip_width / 2.0

	for i in range(_max_charges):
		var x: float = start_x + i * (PIP_WIDTH + PIP_GAP)
		var color: Color = PIP_FILLED_COLOR if i < _charges else PIP_EMPTY_COLOR
		draw_rect(Rect2(x, 0.0, PIP_WIDTH, PIP_HEIGHT), color)

	# Draw timer bar (only when effect is active)
	if _effect and _effect.is_active:
		var remaining := _effect.get_remaining_time()
		var progress := remaining / _effect_duration

		var bar_x := -TIMER_BAR_WIDTH / 2.0
		var bar_y := TIMER_BAR_OFFSET_Y

		# Background
		draw_rect(Rect2(bar_x, bar_y, TIMER_BAR_WIDTH, TIMER_BAR_HEIGHT), TIMER_BG_COLOR)

		# Fill
		var fill_width := TIMER_BAR_WIDTH * progress
		draw_rect(Rect2(bar_x, bar_y, fill_width, TIMER_BAR_HEIGHT), TIMER_FILL_COLOR)
