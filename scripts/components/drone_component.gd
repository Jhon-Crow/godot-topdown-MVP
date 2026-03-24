class_name DroneComponent
extends Node
## Drone entity spawned by the Drone Operator enemy (Issue #1397).
##
## Minimal implementation (per issue: "residual principle"):
## - Spawns as a flying entity near the operator
## - Can receive damage and be destroyed
## - Moves slowly toward the player
## - Emits signal when destroyed so the operator knows to switch to pistol

## Health points of the drone.
const DRONE_HP: int = 2

## Movement speed of the drone (px/s).
const DRONE_SPEED: float = 150.0

## Hover height offset (visual only, for top-down appearance).
const HOVER_OFFSET: float = -20.0

## Drone detection range (px). 0 = unlimited.
const DETECTION_RANGE: float = 600.0

## Signal emitted when drone is destroyed.
signal drone_destroyed

## Signal emitted when drone takes damage.
signal drone_hit

## Current HP.
var _hp: int = DRONE_HP

## Whether the drone is alive.
var _is_alive: bool = true

## Reference to the drone's CharacterBody2D scene root.
var _drone_body: CharacterBody2D = null

## Reference to the player.
var _player: Node2D = null

## Reference to the operator who spawned this drone.
var _operator: Node2D = null

## Logging flag.
var debug_logging: bool = false


func _ready() -> void:
	_drone_body = get_parent() as CharacterBody2D
	_find_player()


## Initialize the drone with operator reference.
func initialize(operator: Node2D) -> void:
	_operator = operator
	FileLogger.info("[Drone] Initialized by operator: %s" % (operator.name if operator else "null"))


## Find the player in the scene tree.
func _find_player() -> void:
	if _drone_body == null:
		return
	var players: Array = _drone_body.get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]
	else:
		# Fallback: search for Player node
		var root: Node = _drone_body.get_tree().current_scene
		if root:
			_player = root.find_child("Player", true, false)


func _physics_process(delta: float) -> void:
	if not _is_alive or _drone_body == null:
		return

	if _player == null:
		_find_player()
		return

	# Simple movement toward player
	var direction: Vector2 = (_player.global_position - _drone_body.global_position)
	var distance: float = direction.length()

	if DETECTION_RANGE > 0.0 and distance > DETECTION_RANGE:
		# Outside detection range — hover in place
		_drone_body.velocity = Vector2.ZERO
		_drone_body.move_and_slide()
		return

	if distance > 50.0:
		direction = direction.normalized()
		_drone_body.velocity = direction * DRONE_SPEED
	else:
		# Close enough — hover near player
		_drone_body.velocity = Vector2.ZERO

	_drone_body.move_and_slide()


## Apply damage to the drone.
## Returns true if the drone was destroyed by this hit.
func take_damage(amount: int = 1) -> bool:
	if not _is_alive:
		return false

	_hp -= amount
	drone_hit.emit()
	FileLogger.info("[Drone] Took %d damage (hp=%d/%d)" % [amount, _hp, DRONE_HP])

	if _hp <= 0:
		_die()
		return true
	return false


## Destroy the drone.
func _die() -> void:
	_is_alive = false
	_hp = 0
	FileLogger.info("[Drone] Destroyed!")
	drone_destroyed.emit()

	# Visual death: fade out and remove
	if _drone_body:
		var tween: Tween = _drone_body.create_tween()
		tween.tween_property(_drone_body, "modulate:a", 0.0, 0.3)
		tween.tween_callback(_drone_body.queue_free)


## Check if the drone is alive.
func is_alive() -> bool:
	return _is_alive


## Get current HP.
func get_hp() -> int:
	return _hp
