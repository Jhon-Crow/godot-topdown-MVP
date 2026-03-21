class_name DashComponent
extends Node
## Dash active item component (Issue #1071).
##
## Encapsulates all dash state and logic, extracted from player.gd to keep
## that file under the 5000-line limit.  The component is instantiated and
## added as a child of the player node during _ready().

## Emitted when a dash begins.
signal dash_started

## Emitted when a dash ends.
signal dash_ended

## Dash movement speed in pixels/second.
const DASH_SPEED: float = 900.0

## How long (seconds) each dash lasts.
const DASH_DURATION: float = 0.12

## Cooldown between dashes (seconds).
const DASH_COOLDOWN: float = 1.2

## Whether the dash item is currently equipped.
var _dash_equipped: bool = false

## Whether a dash is actively in progress.
var _dash_active: bool = false

## Remaining time for the current dash.
var _dash_timer: float = 0.0

## Remaining cooldown time before next dash is available.
var _dash_cooldown_timer: float = 0.0

## Direction the current dash is travelling.
var _dash_direction: Vector2 = Vector2.ZERO

## Reference to the owning player node (set via initialize()).
var _player: Node = null


## Set up the component.
## @param player: The player node that owns this component.
## @param active_item_manager: The ActiveItemManager autoload (may be null).
func initialize(player: Node, active_item_manager: Node) -> void:
	_player = player
	if active_item_manager == null:
		return
	if not active_item_manager.has_method("has_dash"):
		return
	if active_item_manager.has_dash():
		_dash_equipped = true


## Update dash timers and handle dash input.  Call every physics frame.
## @param delta: Frame delta time.
## @param input_direction: Current player input direction (unused but kept for API parity).
func update_state(delta: float, input_direction: Vector2) -> void:
	if not _dash_equipped:
		return
	if _dash_active:
		_dash_timer -= delta
		if _dash_timer <= 0.0:
			_dash_active = false
			_dash_timer = 0.0
			_dash_cooldown_timer = DASH_COOLDOWN
			dash_ended.emit()
		return
	if _dash_cooldown_timer > 0.0:
		_dash_cooldown_timer = max(0.0, _dash_cooldown_timer - delta)
		if _player != null and _player.has_method("_show_active_item_timer_bar"):
			_player._show_active_item_timer_bar(DASH_COOLDOWN - _dash_cooldown_timer, DASH_COOLDOWN)
		if _dash_cooldown_timer <= 0.0:
			if _player != null and _player.has_method("_hide_active_item_bar"):
				_player._hide_active_item_bar()
		return
	if Input.is_action_just_pressed("flashlight_toggle"):
		_start_dash()


## Begin a dash in the player's current aim direction.
func _start_dash() -> void:
	if _player != null and _player.has_method("_get_aim_direction"):
		_dash_direction = _player._get_aim_direction()
	else:
		_dash_direction = Vector2.RIGHT
	_dash_active = true
	_dash_timer = DASH_DURATION
	dash_started.emit()


## Return true while a dash is actively in progress (velocity should be overridden).
func is_active_dash() -> bool:
	return _dash_active


## Return true while a dash is actively in progress.
## Alias kept for compatibility with player.gd's public is_dashing() API.
func is_dashing() -> bool:
	return _dash_active


## Return the direction and speed vector for the current dash.
func get_dash_velocity() -> Vector2:
	return _dash_direction * DASH_SPEED
