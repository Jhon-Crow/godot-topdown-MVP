extends Node2D
## Charge pip HUD for the trajectory glasses (Issue #744).
##
## Displays charge pips above the player.
## Visible while effect is active.
## The timer progress bar has been removed (Issue #1049):
## instead, the trajectory ray blinks when little active time remains.

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

## How long (in seconds) to show the charge pips after activation before auto-hiding.
const ACTIVATION_SHOW_DURATION: float = 0.3

## Current charges.
var _charges: int = 2

## Maximum charges.
var _max_charges: int = 2

## Reference to the trajectory glasses effect.
var _effect: Node = null

## Timer counting down auto-hide after activation (0 = not running).
var _hide_timer: float = 0.0


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


## Update charges display.
func update_charges(current: int, maximum: int) -> void:
	_charges = current
	_max_charges = maximum
	queue_redraw()


## Show/hide the HUD based on effect state.
## When active=true, starts the 400 ms auto-hide timer.
func set_active(active: bool) -> void:
	if active:
		visible = true
		_hide_timer = ACTIVATION_SHOW_DURATION
	else:
		visible = false
		_hide_timer = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	# Keep position at offset above parent
	position = Vector2(0.0, OFFSET_Y)

	# Auto-hide after activation duration expires
	if _hide_timer > 0.0:
		_hide_timer -= delta
		if _hide_timer <= 0.0:
			_hide_timer = 0.0
			visible = false

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
