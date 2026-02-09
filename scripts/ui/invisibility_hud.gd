extends Node2D
## Progress bar HUD for the invisibility suit (Issue #673).
##
## Displays charge pips as a small progress bar above the player.
## Only becomes visible after pressing Space, auto-hides after 300ms.
## Shows charge count only (no timer/seconds).

## Vertical offset above the player center (negative = above).
const OFFSET_Y: float = -32.0

## Width of each charge pip in pixels.
const PIP_WIDTH: float = 10.0

## Height of each charge pip in pixels.
const PIP_HEIGHT: float = 4.0

## Gap between pips.
const PIP_GAP: float = 3.0

## How long the bar stays visible after activation (seconds).
const SHOW_DURATION: float = 0.3

## Color for filled (available) charge pips.
const PIP_FILLED_COLOR: Color = Color(0.4, 0.85, 1.0, 0.9)

## Color for empty (used) charge pips.
const PIP_EMPTY_COLOR: Color = Color(0.3, 0.3, 0.3, 0.5)

## Current charges.
var _charges: int = 2

## Maximum charges.
var _max_charges: int = 2

## Timer for auto-hide.
var _show_timer: float = 0.0

## Whether the bar is currently visible.
var _bar_visible: bool = false

## Reference to the player (parent).
var _player: Node2D = null

## Reference to the invisibility suit effect.
var _suit_effect: Node = null


func _ready() -> void:
	# Start hidden
	visible = false
	z_index = 10


## Initialize with suit effect reference.
func initialize(suit_effect: Node) -> void:
	_suit_effect = suit_effect
	_player = get_parent() as Node2D
	if _suit_effect:
		_charges = _suit_effect.charges
		_max_charges = _suit_effect.MAX_CHARGES


## Update charges display.
func update_charges(current: int, maximum: int) -> void:
	_charges = current
	_max_charges = maximum
	queue_redraw()


## Show the bar (called on activation).
func set_active(active: bool) -> void:
	if active:
		_show_timer = SHOW_DURATION
		_bar_visible = true
		visible = true
		queue_redraw()


func _process(delta: float) -> void:
	if _bar_visible:
		_show_timer -= delta
		if _show_timer <= 0.0:
			_bar_visible = false
			visible = false

	# Keep position at offset above parent
	position = Vector2(0.0, OFFSET_Y)


func _draw() -> void:
	if _max_charges <= 0:
		return

	# Calculate total bar width
	var total_width: float = _max_charges * PIP_WIDTH + (_max_charges - 1) * PIP_GAP
	var start_x: float = -total_width / 2.0

	for i in range(_max_charges):
		var x: float = start_x + i * (PIP_WIDTH + PIP_GAP)
		var color: Color = PIP_FILLED_COLOR if i < _charges else PIP_EMPTY_COLOR
		draw_rect(Rect2(x, 0.0, PIP_WIDTH, PIP_HEIGHT), color)
