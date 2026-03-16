extends Node
## Autoload singleton for managing the Dead Eye passive item (Issue #1069).
##
## Dead Eye mechanics:
## - Starts with -20% damage (multiplier = 0.8)
## - Each hit increases damage by +5% (stacks: 0.8, 0.85, 0.90, ...)
## - After a miss, damage resets to the starting value (0.8)
##
## "Volley" definition:
## - For weapons that fire multiple projectiles (shotgun, sniper):
##   at least one projectile must deal damage to count as a hit.
## - For automatic weapons: a continuous burst of fire lasting up to 1 second
##   counts as one volley. If at least one bullet hits during that window, it's a hit.
##
## Integration:
## - Bullets call notify_bullet_fired() when spawned (starts/extends the volley window).
## - Bullets call notify_hit() when they hit an enemy.
## - When the volley window closes (timer expires), the manager evaluates hit/miss.

## Starting damage multiplier (base -20%).
const BASE_MULTIPLIER: float = 0.8

## Damage increase per hit streak step (+5%).
const HIT_STEP: float = 0.05

## Duration of a single volley window in seconds.
## Automatic weapons: bullets within this window are treated as one volley.
const VOLLEY_WINDOW: float = 1.0

## Current damage multiplier.
var _multiplier: float = BASE_MULTIPLIER

## Whether at least one bullet in the current volley hit an enemy.
var _volley_had_hit: bool = false

## Whether a volley is currently active.
var _volley_active: bool = false

## Timer tracking how long since the last bullet was fired.
var _volley_timer: float = 0.0

## Whether Dead Eye is currently active (item equipped).
var _is_active: bool = false


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if not _is_active or not _volley_active:
		return

	_volley_timer -= delta
	if _volley_timer <= 0.0:
		_close_volley()


## Called by Bullet/ShotgunPellet/SniperBullet when a bullet is spawned by the player.
## Starts or extends the current volley window.
func notify_bullet_fired() -> void:
	if not _is_active:
		return

	if not _volley_active:
		# Start a new volley
		_volley_active = true
		_volley_had_hit = false

	# Reset the timer — extends the window for automatic weapons
	_volley_timer = VOLLEY_WINDOW


## Called by Bullet/ShotgunPellet/SniperBullet when a player bullet hits an enemy.
func notify_hit() -> void:
	if not _is_active:
		return

	_volley_had_hit = true


## Closes the current volley window and updates the multiplier.
## Called when the volley timer expires (no more bullets fired in VOLLEY_WINDOW seconds).
func _close_volley() -> void:
	_volley_active = false
	_volley_timer = 0.0

	if _volley_had_hit:
		# At least one bullet hit — increase multiplier
		_multiplier += HIT_STEP
		FileLogger.info("[DeadEyeManager] Hit! Multiplier increased to %.2f" % _multiplier)
	else:
		# No hits in this volley — reset multiplier
		_multiplier = BASE_MULTIPLIER
		FileLogger.info("[DeadEyeManager] Miss! Multiplier reset to %.2f" % _multiplier)

	_volley_had_hit = false


## Returns the current damage multiplier.
## Returns 1.0 when Dead Eye is not active.
func get_damage_multiplier() -> float:
	if not _is_active:
		return 1.0
	return _multiplier


## Activates or deactivates Dead Eye tracking.
## Called when the player equips or unequips the Dead Eye item.
func set_active(active: bool) -> void:
	_is_active = active
	if active:
		_reset()
		FileLogger.info("[DeadEyeManager] Dead Eye activated — multiplier reset to %.2f" % _multiplier)
	else:
		FileLogger.info("[DeadEyeManager] Dead Eye deactivated")


## Resets Dead Eye state to initial values (called at level start).
func reset() -> void:
	_reset()


## Internal reset helper.
func _reset() -> void:
	_multiplier = BASE_MULTIPLIER
	_volley_active = false
	_volley_had_hit = false
	_volley_timer = 0.0
