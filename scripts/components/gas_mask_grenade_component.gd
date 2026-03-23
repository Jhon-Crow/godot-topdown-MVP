extends Node
class_name GasMaskGrenadeComponent
## Component for Gas Mask Enemy chemical grenade throwing (Issue #1353).
##
## Simplified grenade component that handles chemical grenade throwing.
## The Gas Mask Enemy throws 4 chemical grenades that release illusion-creating
## gas clouds. Throws at player in combat state before shooting.
##
## Behavior:
## - Throws chemical grenade at player when entering combat
## - 4-second cooldown if player is NOT under illusion effect
## - Waits until existing illusion effect expires before re-throwing
## - Maximum 4 grenades total

## Signal emitted when a grenade is thrown.
signal grenade_thrown(grenade: Node, target_position: Vector2)

## Maximum number of chemical grenades.
@export var max_grenades: int = 4

## Cooldown between throws (seconds).
@export var throw_cooldown: float = 1.0

## Maximum throw distance (pixels).
@export var max_throw_distance: float = 900.0

## Minimum safe distance (pixels).
@export var min_throw_distance: float = 100.0

## Throw inaccuracy (radians).
@export var inaccuracy: float = 0.15

## Delay before throw animation (seconds).
@export var throw_delay: float = 0.1

## Chemical grenade scene.
var _grenade_scene: PackedScene = null

## Grenades remaining.
var grenades_remaining: int = 0

## Cooldown timer.
var _cooldown: float = 0.0

## Whether currently in throw animation.
var _is_throwing: bool = false

## Reference to parent enemy.
var _enemy: CharacterBody2D = null

## Logger reference.
var _logger: Node = null


func _ready() -> void:
	_logger = get_node_or_null("/root/FileLogger")
	_enemy = get_parent() as CharacterBody2D
	grenades_remaining = max_grenades
	_grenade_scene = preload("res://scenes/projectiles/ChemicalGasGrenade.tscn")
	_log("GasMaskGrenadeComponent ready: %d grenades" % grenades_remaining)


func _physics_process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta


## Attempt to throw a chemical grenade at the target position.
## Returns true if a grenade was thrown.
func try_throw(target_position: Vector2) -> bool:
	if not _can_throw(target_position):
		return false

	_is_throwing = true
	_cooldown = throw_cooldown

	# Wait for throw delay
	await get_tree().create_timer(throw_delay).timeout

	if not is_instance_valid(_enemy) or not _enemy.has_method("is_alive") or not _enemy.is_alive():
		_is_throwing = false
		return false

	_throw_grenade(target_position)
	_is_throwing = false
	return true


## Check if we can throw a grenade right now.
func _can_throw(target_position: Vector2) -> bool:
	if grenades_remaining <= 0:
		return false
	if _cooldown > 0.0:
		return false
	if _is_throwing:
		return false

	# Don't throw if illusions are still active on the map
	if IllusionEffect.get_illusion_count(get_tree()) > 0:
		return false

	# Distance check
	var distance := _enemy.global_position.distance_to(target_position)
	if distance < min_throw_distance or distance > max_throw_distance:
		return false

	return true


## Actually throw the grenade.
func _throw_grenade(target_position: Vector2) -> void:
	if _grenade_scene == null:
		_log("ERROR: Chemical grenade scene not loaded!")
		return

	var grenade: RigidBody2D = _grenade_scene.instantiate()
	if grenade == null:
		_log("ERROR: Failed to instantiate chemical grenade!")
		return

	# Calculate throw direction with inaccuracy
	var direction := (_enemy.global_position.direction_to(target_position))
	direction = direction.rotated(randf_range(-inaccuracy, inaccuracy))

	# Calculate throw speed based on distance
	var distance := _enemy.global_position.distance_to(target_position)
	var throw_speed := clampf(distance * 1.5, 200.0, 850.0)

	# Position at enemy
	grenade.global_position = _enemy.global_position

	# Add to scene
	get_tree().current_scene.add_child(grenade)

	# Activate the fuse timer (must be called before throwing)
	if grenade.has_method("activate_timer"):
		grenade.activate_timer()

	# Throw using GrenadeBase.throw_grenade() which handles unfreeze + velocity
	if grenade.has_method("throw_grenade"):
		grenade.throw_grenade(direction, distance)
	else:
		# Fallback: manually unfreeze and set velocity
		grenade.freeze = false
		grenade.linear_velocity = direction * throw_speed

	grenades_remaining -= 1

	_log("Chemical grenade thrown at %s (remaining: %d)" % [str(target_position), grenades_remaining])
	grenade_thrown.emit(grenade, target_position)


## Check if component is currently throwing.
func is_throwing() -> bool:
	return _is_throwing


## Check if any grenades remain.
func has_grenades() -> bool:
	return grenades_remaining > 0


## Log helper.
func _log(message: String) -> void:
	if _logger and _logger.has_method("log_info"):
		_logger.log_info("[GasMaskGrenade] " + message)
	else:
		FileLogger.info("[GasMaskGrenade] " + message)
