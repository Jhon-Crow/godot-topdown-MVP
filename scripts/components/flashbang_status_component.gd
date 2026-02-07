class_name FlashbangStatusComponent
extends Node
## Manages flashbang status effects (blindness and stun) on an enemy.
##
## Extracted from enemy.gd to reduce file size (Issue #328).
## Attach this component as a child node to apply flashbang-based
## blindness and stun effects with automatic timer decay.

## Emitted when blindness status changes.
signal blinded_changed(is_blinded: bool)

## Emitted when stun status changes.
signal stunned_changed(is_stunned: bool)

## Whether the entity is currently blinded (cannot see player).
var _is_blinded: bool = false

## Whether the entity is currently stunned (cannot move/act).
var _is_stunned: bool = false

## Remaining blindness duration in seconds.
var _blindness_timer: float = 0.0

## Remaining stun duration in seconds.
var _stun_timer: float = 0.0

## Reference to FileLogger for logging.
var _logger: Node = null


func _ready() -> void:
	_logger = get_node_or_null("/root/FileLogger")


## Update timers each physics frame. Call from parent _physics_process.
func update(delta: float) -> void:
	if _blindness_timer > 0.0:
		_blindness_timer -= delta
		if _blindness_timer <= 0.0:
			_blindness_timer = 0.0
			set_blinded(false)
	if _stun_timer > 0.0:
		_stun_timer -= delta
		if _stun_timer <= 0.0:
			_stun_timer = 0.0
			set_stunned(false)


## Apply flashbang effect (Issue #432). Called by C# GrenadeTimer.
func apply_flashbang_effect(blindness_duration: float, stun_duration: float) -> void:
	_log("Flashbang: blind=%.1fs, stun=%.1fs" % [blindness_duration, stun_duration])
	if blindness_duration > 0.0:
		_blindness_timer = maxf(_blindness_timer, blindness_duration)
		set_blinded(true)
	if stun_duration > 0.0:
		_stun_timer = maxf(_stun_timer, stun_duration)
		set_stunned(true)


func set_blinded(blinded: bool) -> void:
	var was := _is_blinded
	_is_blinded = blinded
	if blinded and not was:
		_log("Status: BLINDED applied")
		blinded_changed.emit(true)
	elif not blinded and was:
		_log("Status: BLINDED removed")
		blinded_changed.emit(false)


func set_stunned(stunned: bool) -> void:
	var was := _is_stunned
	_is_stunned = stunned
	if stunned and not was:
		_log("Status: STUNNED applied")
		stunned_changed.emit(true)
	elif not stunned and was:
		_log("Status: STUNNED removed")
		stunned_changed.emit(false)


func is_blinded() -> bool:
	return _is_blinded


func is_stunned() -> bool:
	return _is_stunned


func _log(message: String) -> void:
	if _logger and _logger.has_method("log_info"):
		_logger.log_info("[FlashbangStatus] " + message)
