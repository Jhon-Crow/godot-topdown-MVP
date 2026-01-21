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
## The visual is a continuous dark trail from entry to exit point,
## drawn like a brush stroke through the wall texture.

## Collision layers this hole affects (default: obstacles layer 3)
const OBSTACLE_LAYER: int = 4  # Layer 3 in Godot is value 4 (2^2)

## The collision shape of this hole.
var _collision_shape: CollisionShape2D = null

## The visual Line2D trail.
var _visual_line: Line2D = null

## Direction the bullet was traveling (for trail orientation).
var bullet_direction: Vector2 = Vector2.RIGHT

## Width of the bullet trail (based on caliber).
var trail_width: float = 4.0

## Length of the trail (based on penetration distance traveled).
var trail_length: float = 8.0

## Entry point in global coordinates (stored for visual rendering).
var _entry_point: Vector2 = Vector2.ZERO

## Exit point in global coordinates (stored for visual rendering).
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

	# Don't create visuals yet - wait for set_from_entry_exit to be called
	# with the actual entry/exit points


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


## Creates or updates the visual representation of the hole.
## The visual is drawn in GLOBAL coordinates as a line from entry to exit.
func _create_or_update_visual() -> void:
	if _visual_line == null:
		_visual_line = Line2D.new()
		_visual_line.default_color = Color(0.02, 0.02, 0.02, 0.95)
		_visual_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		_visual_line.end_cap_mode = Line2D.LINE_CAP_ROUND
		# Use global coordinates so the line is positioned correctly
		_visual_line.top_level = true
		# Ensure position is at origin so points are at their true global positions
		_visual_line.position = Vector2.ZERO
		add_child(_visual_line)

	# Update line properties
	_visual_line.width = trail_width
	_visual_line.clear_points()

	# Draw line from entry to exit in global coordinates
	_visual_line.add_point(_entry_point)
	_visual_line.add_point(_exit_point)


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

	# Update visual if we have entry/exit points
	if _is_configured:
		_create_or_update_visual()


## Sets the hole from entry and exit points.
## This is the primary method for configuring the hole.
## @param entry_point: Where the bullet entered the wall (global coords).
## @param exit_point: Where the bullet exited the wall (global coords).
func set_from_entry_exit(entry_point: Vector2, exit_point: Vector2) -> void:
	# Store entry/exit points for visual rendering
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

	# Now create/update collision shape and visual
	configure(bullet_direction, trail_width, trail_length)
