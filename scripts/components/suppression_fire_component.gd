class_name SuppressionFireComponent
extends RefCounted
## Component for managing enemy suppression fire behavior (Issue #711).
##
## This component handles the logic for enemies to fire suppression bursts
## toward detected sound or muzzle flash positions when they can't directly
## see the player. It works in conjunction with MuzzleFlashDetectionComponent.
##
## Suppression fire characteristics:
## - 3-5 shot bursts with inaccurate "blind fire" spread
## - Cooldown between bursts to prevent spam
## - Ammo-aware (won't suppress if low on ammo)
## - Melee enemies excluded
##
## Usage:
##   var suppression = SuppressionFireComponent.new()
##   suppression.start_suppression(target_position)
##   # In _physics_process:
##   suppression.update(delta)
##   if suppression.should_fire():
##       fire_bullet_toward(suppression.get_aim_direction(enemy_pos))
##       suppression.shot_fired()

## Suppression burst configuration.
const BURST_COUNT_MIN: int = 3
const BURST_COUNT_MAX: int = 5
const BURST_INTERVAL: float = 0.08  ## Time between shots in burst (seconds).
const COOLDOWN_DURATION: float = 3.0  ## Cooldown between bursts (seconds).
const INACCURACY_SPREAD: float = 0.25  ## Spread angle in radians for blind fire.
const SOUND_SUPPRESSION_RANGE: float = 500.0  ## Max range for sound-based suppression.

## Whether currently firing a suppression burst.
var is_active: bool = false

## Target position to suppress toward.
var target_position: Vector2 = Vector2.ZERO

## Remaining shots in current burst.
var _burst_remaining: int = 0

## Timer between shots in burst.
var _burst_timer: float = 0.0

## Cooldown timer between bursts.
var _cooldown_timer: float = 0.0

## Whether suppression is available (cooldown elapsed).
var can_suppress: bool = true

## Debug logging.
var debug_logging: bool = false


## Start a suppression burst toward the target position.
func start_suppression(target: Vector2) -> void:
	if not can_suppress:
		return

	is_active = true
	target_position = target
	_burst_remaining = randi_range(BURST_COUNT_MIN, BURST_COUNT_MAX)
	_burst_timer = 0.0

	# Start cooldown immediately
	can_suppress = false
	_cooldown_timer = COOLDOWN_DURATION

	if debug_logging:
		print("[SuppressionFire] Started: target=%s, burst=%d" % [target, _burst_remaining])


## Update timers. Call this every frame.
func update(delta: float) -> void:
	# Update burst timer
	if is_active:
		_burst_timer += delta

	# Update cooldown
	if not can_suppress:
		_cooldown_timer -= delta
		if _cooldown_timer <= 0.0:
			can_suppress = true


## Check if a shot should be fired this frame.
func should_fire() -> bool:
	if not is_active:
		return false

	if _burst_remaining <= 0:
		return false

	return _burst_timer >= BURST_INTERVAL


## Get the aim direction with suppression inaccuracy applied.
## Returns a normalized vector from enemy position toward target with spread.
func get_aim_direction(enemy_pos: Vector2) -> Vector2:
	var base_direction := (target_position - enemy_pos).normalized()
	var spread_angle := randf_range(-INACCURACY_SPREAD, INACCURACY_SPREAD)
	return base_direction.rotated(spread_angle)


## Call after firing a shot to update burst state.
func shot_fired() -> void:
	_burst_remaining -= 1
	_burst_timer = 0.0

	if _burst_remaining <= 0:
		is_active = false
		if debug_logging:
			print("[SuppressionFire] Burst complete")


## Stop suppression fire immediately.
func stop() -> void:
	is_active = false
	_burst_remaining = 0
	target_position = Vector2.ZERO


## Reset all state including cooldown.
func reset() -> void:
	stop()
	can_suppress = true
	_cooldown_timer = 0.0


## Check if a distance is within sound-based suppression range.
static func is_in_sound_range(distance: float) -> bool:
	return distance <= SOUND_SUPPRESSION_RANGE


## Get the inaccuracy spread value.
func get_inaccuracy() -> float:
	return INACCURACY_SPREAD


## Get the remaining shots in current burst.
func get_burst_remaining() -> int:
	return _burst_remaining


## Create string representation for debugging.
func _to_string() -> String:
	if not is_active:
		return "SuppressionFire(inactive, can=%s)" % can_suppress
	return "SuppressionFire(target=%s, remaining=%d, can=%s)" % [
		target_position, _burst_remaining, can_suppress
	]
