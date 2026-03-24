extends Area2D
class_name ArmoredSkinShard
## Glass/crystal shard projectile from the Armored Skin passive item (Issue #1045).
##
## When the player has 2 HP or less and takes a hit, 20 shards fly in all
## directions. Unlike grenade shrapnel, these shards:
## - Do NOT ricochet off walls (destroyed on wall hit)
## - Do NOT penetrate walls
## - Deals 1 damage per piece
## - Has a glassy/crystalline visual appearance (cyan/blue-white tinted)
## - Does NOT hit the player who triggered them

## Speed of the shard in pixels per second.
@export var speed: float = 1600.0

## Maximum lifetime in seconds before auto-destruction.
@export var lifetime: float = 0.7

## Damage dealt on hit.
@export var damage: int = 1

## Maximum number of trail points to maintain.
@export var trail_length: int = 5

## Direction the shard travels.
var direction: Vector2 = Vector2.RIGHT

## Instance ID of the player who triggered this shard.
## Used to prevent self-damage.
var source_id: int = -1

## Timer tracking remaining lifetime.
var _time_alive: float = 0.0

## Reference to the trail Line2D node (if present).
var _trail: Line2D = null

## History of global positions for the trail effect.
var _position_history: Array[Vector2] = []

## Enable/disable debug logging.
var _debug: bool = false


func _ready() -> void:
	if _debug:
		FileLogger.info("[ArmoredSkinShard] Spawned at %s, direction: %s, source_id: %d" % [
			global_position, direction, source_id])
	add_to_group("armored_skin_shards")

	# Connect to collision signals
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

	# Get trail reference if it exists
	_trail = get_node_or_null("Trail")
	if _trail:
		_trail.clear_points()
		_trail.top_level = true
		_trail.position = Vector2.ZERO

	# Set initial rotation based on direction
	_update_rotation()


func _physics_process(delta: float) -> void:
	# Move in the set direction
	var movement := direction * speed * delta
	position += movement

	# Decelerate gradually
	speed = maxf(speed * 0.994, 150.0)

	# Update trail effect
	_update_trail(delta)

	# Track lifetime and auto-destroy if exceeded
	_time_alive += delta
	if _time_alive >= lifetime:
		_destroy()


## Updates the shard rotation to match its travel direction.
func _update_rotation() -> void:
	rotation = direction.angle()


## Updates the visual trail effect.
func _update_trail(_delta: float) -> void:
	if not _trail:
		return

	_position_history.push_front(global_position)

	while _position_history.size() > trail_length:
		_position_history.pop_back()

	_trail.clear_points()
	for pos in _position_history:
		_trail.add_point(pos)


func _on_body_entered(body: Node2D) -> void:
	# Don't collide with the source player
	if source_id == body.get_instance_id():
		return

	# Pass through dead entities
	if body.has_method("is_alive") and not body.is_alive():
		return

	# Hit a wall/obstacle — armored skin shards do NOT ricochet, just destroy
	if body is StaticBody2D or body is TileMap:
		if _debug:
			FileLogger.info("[ArmoredSkinShard] Hit wall at %s, destroying (no ricochet)" % global_position)
		var audio_manager: Node = get_node_or_null("/root/AudioManager")
		if audio_manager and audio_manager.has_method("play_bullet_wall_hit"):
			audio_manager.play_bullet_wall_hit(global_position)
		_destroy()
		return

	# Hit other bodies — destroy
	_destroy()


func _on_area_entered(area: Area2D) -> void:
	# Hit a target with hit detection
	if area.has_method("on_hit"):
		var parent: Node = area.get_parent()
		if parent and source_id == parent.get_instance_id():
			return  # Don't hit the source player

		# Check if the parent is dead
		if parent and parent.has_method("is_alive") and not parent.is_alive():
			return  # Pass through dead entities

		# Don't damage other players if somehow area is player
		if parent and parent.is_in_group("player"):
			return

		if _debug:
			FileLogger.info("[ArmoredSkinShard] Hit target at %s, dealing %d damage" % [
				global_position, damage])

		if area.has_method("on_hit_with_info"):
			area.on_hit_with_info(direction, null)
		else:
			area.on_hit()

		_destroy()


## Destroys the shard.
func _destroy() -> void:
	queue_free()
