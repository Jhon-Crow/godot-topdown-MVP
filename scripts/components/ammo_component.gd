class_name AmmoComponent
extends Node
## Ammunition management component for entities that can shoot.
##
## Handles magazine-based ammunition system with reload mechanics.

## Magazine size (bullets per magazine).
@export var magazine_size: int = 30

## Total number of magazines the entity carries.
@export var total_magazines: int = 5

## Time to reload in seconds.
@export var reload_time: float = 3.0

## Current ammo in the magazine.
var _current_ammo: int = 0

## Reserve ammo (ammo in remaining magazines).
var _reserve_ammo: int = 0

## Whether currently reloading.
var _is_reloading: bool = false

## Timer for reload progress.
var _reload_timer: float = 0.0

## Signal emitted when ammo changes.
signal ammo_changed(current_ammo: int, reserve_ammo: int)

## Signal emitted when reload starts.
signal reload_started

## Signal emitted when reload finishes.
signal reload_finished

## Signal emitted when all ammo is depleted.
signal ammo_depleted


func _ready() -> void:
	initialize_ammo()


## Initialize ammunition.
func initialize_ammo() -> void:
	_current_ammo = magazine_size
	# Reserve ammo is (total_magazines - 1) since one magazine is loaded
	_reserve_ammo = (total_magazines - 1) * magazine_size
	_is_reloading = false
	_reload_timer = 0.0


## Process reload timer (call from _physics_process).
func update_reload(delta: float) -> void:
	if not _is_reloading:
		return

	_reload_timer += delta
	if _reload_timer >= reload_time:
		_finish_reload()


## Check if can shoot (has ammo and not reloading).
func can_shoot() -> bool:
	return _current_ammo > 0 and not _is_reloading


## Consume one round of ammo.
## Returns true if successful, false if no ammo.
func consume_ammo() -> bool:
	if _current_ammo <= 0:
		return false

	_current_ammo -= 1
	ammo_changed.emit(_current_ammo, _reserve_ammo)

	# Auto-reload when magazine is empty
	if _current_ammo <= 0 and _reserve_ammo > 0:
		start_reload()
	elif _current_ammo <= 0 and _reserve_ammo <= 0:
		ammo_depleted.emit()

	return true


## Start reloading.
func start_reload() -> void:
	if _is_reloading or _reserve_ammo <= 0 or _current_ammo >= magazine_size:
		return

	_is_reloading = true
	_reload_timer = 0.0
	reload_started.emit()


## Finish reloading.
func _finish_reload() -> void:
	var ammo_needed := magazine_size - _current_ammo
	var ammo_to_load := mini(ammo_needed, _reserve_ammo)

	_current_ammo += ammo_to_load
	_reserve_ammo -= ammo_to_load
	_is_reloading = false
	_reload_timer = 0.0

	ammo_changed.emit(_current_ammo, _reserve_ammo)
	reload_finished.emit()


## Reset ammo to full.
func reset() -> void:
	initialize_ammo()


## Get current ammo in magazine.
func get_current_ammo() -> int:
	return _current_ammo


## Get reserve ammo.
func get_reserve_ammo() -> int:
	return _reserve_ammo


## Get total ammo (current + reserve).
func get_total_ammo() -> int:
	return _current_ammo + _reserve_ammo


## Check if reloading.
func is_reloading() -> bool:
	return _is_reloading


## Check if has any ammo.
func has_ammo() -> bool:
	return _current_ammo > 0 or _reserve_ammo > 0
