class_name HealthComponent
extends Node
## Health management component for entities that can take damage.
##
## Attach this node to any entity to give it health functionality.
## Supports random health initialization, damage, healing, and visual feedback.

## Minimum health value (for random initialization).
@export var min_health: int = 2

## Maximum health value (for random initialization).
@export var max_health: int = 4

## Whether to randomize health between min and max on ready.
@export var randomize_on_ready: bool = true

## Color when at full health.
@export var full_health_color: Color = Color(0.9, 0.2, 0.2, 1.0)

## Color when at low health.
@export var low_health_color: Color = Color(0.3, 0.1, 0.1, 1.0)

## Color to flash when hit.
@export var hit_flash_color: Color = Color(1.0, 1.0, 1.0, 1.0)

## Duration of hit flash effect in seconds.
@export var hit_flash_duration: float = 0.1

## Current health.
var _current_health: int = 0

## Maximum health (set at initialization).
var _max_health: int = 0

## Whether the entity is alive.
var _is_alive: bool = true

## Reference to sprite for visual feedback (set externally or found automatically).
var _sprite: Sprite2D = null

## Signal emitted when hit.
signal hit

## Signal emitted when health changes.
signal health_changed(current: int, maximum: int)

## Signal emitted when the entity dies.
signal died


func _ready() -> void:
	if randomize_on_ready:
		initialize_health()

	# Try to find sprite in parent
	_find_sprite()


## Initialize health with random value between min and max.
func initialize_health() -> void:
	_max_health = randi_range(min_health, max_health)
	_current_health = _max_health
	_is_alive = true
	_update_health_visual()


## Initialize health with specific value.
func set_max_health(value: int) -> void:
	_max_health = value
	_current_health = value
	_is_alive = true
	_update_health_visual()


## Find sprite in parent for visual feedback.
func _find_sprite() -> void:
	var parent := get_parent()
	if parent:
		_sprite = parent.get_node_or_null("Sprite2D")


## Set the sprite reference manually.
func set_sprite(sprite: Sprite2D) -> void:
	_sprite = sprite


## Apply damage to the entity.
func take_damage(amount: int = 1) -> void:
	# Call extended version with default values
	take_damage_with_info(amount, Vector2.RIGHT, null)


## Apply damage to the entity with extended hit information.
## @param amount: Amount of damage to apply.
## @param hit_direction: Direction the bullet was traveling.
## @param caliber_data: Caliber resource for effect scaling.
func take_damage_with_info(amount: int, hit_direction: Vector2, caliber_data: Resource) -> void:
	if not _is_alive:
		return

	hit.emit()
	_show_hit_flash()

	_current_health -= amount
	health_changed.emit(_current_health, _max_health)

	# Spawn visual effects based on damage result
	var impact_manager: Node = get_node_or_null("/root/ImpactEffectsManager")
	var parent := get_parent()

	if _current_health <= 0:
		_current_health = 0
		# Spawn blood splatter effect for lethal hit (with decal)
		if impact_manager and impact_manager.has_method("spawn_blood_effect") and parent:
			impact_manager.spawn_blood_effect(parent.global_position, hit_direction, caliber_data, true)
		_on_death()
	else:
		# Spawn blood for non-lethal hit (smaller, no decal)
		if impact_manager and impact_manager.has_method("spawn_blood_effect") and parent:
			impact_manager.spawn_blood_effect(parent.global_position, hit_direction, caliber_data, false)
		_update_health_visual()


## Heal the entity.
func heal(amount: int) -> void:
	if not _is_alive:
		return

	_current_health = mini(_current_health + amount, _max_health)
	health_changed.emit(_current_health, _max_health)
	_update_health_visual()


## Show hit flash effect.
func _show_hit_flash() -> void:
	if not _sprite:
		return

	_sprite.modulate = hit_flash_color

	await get_tree().create_timer(hit_flash_duration).timeout

	if _is_alive:
		_update_health_visual()


## Update sprite color based on health percentage.
func _update_health_visual() -> void:
	if not _sprite:
		return

	var health_percent := get_health_percent()
	_sprite.modulate = full_health_color.lerp(low_health_color, 1.0 - health_percent)


## Handle death.
func _on_death() -> void:
	_is_alive = false
	died.emit()

	if _sprite:
		_sprite.modulate = Color(0.3, 0.3, 0.3, 0.5)


## Reset health to max (for respawn).
func reset() -> void:
	initialize_health()


## Get current health.
func get_current_health() -> int:
	return _current_health


## Get maximum health.
func get_max_health() -> int:
	return _max_health


## Get health as percentage (0.0 to 1.0).
func get_health_percent() -> float:
	if _max_health <= 0:
		return 0.0
	return float(_current_health) / float(_max_health)


## Check if alive.
func is_alive() -> bool:
	return _is_alive
