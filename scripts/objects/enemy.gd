extends Area2D
## Enemy/Target that can be damaged and reacts when hit.
##
## Implements health-based damage system. When hit, the enemy takes damage
## and shows visual feedback. Can be destroyed or respawn after a delay.

## Color when at full health.
@export var full_health_color: Color = Color(0.9, 0.2, 0.2, 1.0)

## Color when at low health (interpolates based on health percentage).
@export var low_health_color: Color = Color(0.3, 0.1, 0.1, 1.0)

## Color to flash when hit.
@export var hit_flash_color: Color = Color(1.0, 1.0, 1.0, 1.0)

## Duration of hit flash effect in seconds.
@export var hit_flash_duration: float = 0.1

## Whether to destroy the enemy after death.
@export var destroy_on_death: bool = false

## Delay before respawning or destroying (in seconds).
@export var respawn_delay: float = 2.0

## Minimum random health.
@export var min_health: int = 2

## Maximum random health.
@export var max_health: int = 4

## Signal emitted when the enemy is hit.
signal hit

## Signal emitted when the enemy dies.
signal died

## Reference to the sprite for color changes.
@onready var _sprite: Sprite2D = $Sprite2D

## Current health of the enemy.
var _current_health: int = 0

## Maximum health of the enemy (set at spawn).
var _max_health: int = 0

## Whether the enemy is alive.
var _is_alive: bool = true


func _ready() -> void:
	_initialize_health()
	_update_health_visual()


## Initialize health with random value between min and max.
func _initialize_health() -> void:
	_max_health = randi_range(min_health, max_health)
	_current_health = _max_health
	_is_alive = true
	print("[Enemy] %s: Spawned with health %d/%d" % [name, _current_health, _max_health])


## Called when the enemy is hit (by bullet.gd).
func on_hit() -> void:
	if not _is_alive:
		return

	hit.emit()

	print("[Enemy] %s: Hit! Taking 1 damage. Current health: %d" % [name, _current_health])

	# Show hit flash effect
	_show_hit_flash()

	# Apply damage
	_current_health -= 1

	print("[Enemy] %s: Health changed to %d/%d (%.0f%%)" % [name, _current_health, _max_health, _get_health_percent() * 100])

	if _current_health <= 0:
		_on_death()
	else:
		_update_health_visual()


## Shows a brief flash effect when hit.
func _show_hit_flash() -> void:
	if not _sprite:
		return

	_sprite.modulate = hit_flash_color

	await get_tree().create_timer(hit_flash_duration).timeout

	# Restore color based on current health (if still alive)
	if _is_alive:
		_update_health_visual()


## Updates the sprite color based on current health percentage.
func _update_health_visual() -> void:
	if not _sprite:
		return

	# Interpolate color based on health percentage
	var health_percent := _get_health_percent()
	_sprite.modulate = full_health_color.lerp(low_health_color, 1.0 - health_percent)


## Returns the current health as a percentage (0.0 to 1.0).
func _get_health_percent() -> float:
	if _max_health <= 0:
		return 0.0
	return float(_current_health) / float(_max_health)


## Called when the enemy dies.
func _on_death() -> void:
	_is_alive = false
	print("[Enemy] %s: Died!" % name)
	died.emit()

	if destroy_on_death:
		await get_tree().create_timer(respawn_delay).timeout
		queue_free()
	else:
		await get_tree().create_timer(respawn_delay).timeout
		_reset()


## Resets the enemy to its initial state.
func _reset() -> void:
	_initialize_health()
	_update_health_visual()
