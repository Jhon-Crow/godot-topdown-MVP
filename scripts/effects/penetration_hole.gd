extends Area2D
## Permanent penetration hole that creates a gap in wall collision.
##
## This creates an actual hole in the wall that allows:
## - Bullets to pass through without triggering new penetration
## - Vision/raycasts to pass through
## - Enemies to see and shoot through
##
## The hole is permanent and does not fade over time.
## Similar to Red Faction Guerrilla or Teardown destruction (without physics).
##
## Visual feedback is provided by dust effects at entry and exit points,
## spawned by the bullet script (not by this collision hole).

## Collision layers this hole affects (default: obstacles layer 3)
const OBSTACLE_LAYER: int = 4  # Layer 3 in Godot is value 4 (2^2)

## The collision shape of this hole.
var _collision_shape: CollisionShape2D = null

## Direction the bullet was traveling (for collision orientation).
var bullet_direction: Vector2 = Vector2.RIGHT

## Width of the hole (based on caliber).
var trail_width: float = 4.0

## Length of the hole (based on penetration distance traveled).
var trail_length: float = 8.0

## Entry point in global coordinates.
var _entry_point: Vector2 = Vector2.ZERO

## Exit point in global coordinates.
var _exit_point: Vector2 = Vector2.ZERO

## Whether the hole has been fully configured.
var _is_configured: bool = false


func _ready() -> void:
	# Configure area to be a hole that disables wall collision for bullets
	# Bullets should pass through this area without hitting walls
	collision_layer = 0  # Don't collide with anything
	collision_mask = OBSTACLE_LAYER  # Detect obstacles to create hole effect

	# Monitoring must be true for bullets to detect this area
	monitoring = true
	monitorable = true


## Creates or updates the collision shape for the hole.
func _create_or_update_collision_shape() -> void:
	if _collision_shape == null:
		_collision_shape = CollisionShape2D.new()
		var rect_shape := RectangleShape2D.new()
		_collision_shape.shape = rect_shape
		add_child(_collision_shape)

	# Update shape size
	var rect := _collision_shape.shape as RectangleShape2D
	if rect:
		# Width is the bullet diameter, length is the penetration distance
		rect.size = Vector2(trail_length, trail_width)


## Configures the hole with bullet information.
## @param direction: Direction the bullet was traveling.
## @param width: Width of the hole (based on caliber).
## @param length: Length of the hole (penetration distance).
func configure(direction: Vector2, width: float, length: float) -> void:
	bullet_direction = direction.normalized()
	trail_width = maxf(width, 2.0)  # Minimum width of 2 pixels
	trail_length = maxf(length, 4.0)  # Minimum length of 4 pixels

	# Update collision shape
	_create_or_update_collision_shape()

	# Set rotation for collision shape (centered at hole position)
	rotation = bullet_direction.angle()


## Sets the hole from entry and exit points.
## This is the primary method for configuring the hole.
## @param entry_point: Where the bullet entered the wall (global coords).
## @param exit_point: Where the bullet exited the wall (global coords).
func set_from_entry_exit(entry_point: Vector2, exit_point: Vector2) -> void:
	# Store entry/exit points
	_entry_point = entry_point
	_exit_point = exit_point

	# Position collision shape at center of entry and exit
	global_position = (entry_point + exit_point) / 2.0

	# Calculate direction and length
	var path := exit_point - entry_point
	trail_length = maxf(path.length(), 4.0)  # Minimum length of 4 pixels
	bullet_direction = path.normalized() if trail_length > 4.0 else Vector2.RIGHT

	# Mark as configured
	_is_configured = true

	# Now create/update collision shape
	configure(bullet_direction, trail_width, trail_length)
