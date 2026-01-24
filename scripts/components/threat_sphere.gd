class_name ThreatSphere
extends Area2D
## ThreatSphere - Detects incoming bullets that are on a collision course with the player.
##
## This component is used for the "last chance" effect in hard mode.
## When a bullet enters the threat sphere AND is heading toward the player,
## it triggers the last chance effect via the LastChanceEffectsManager.
##
## The sphere only detects enemy bullets (not player bullets) and checks
## if the bullet's trajectory would hit the player within the sphere.

## Signal emitted when a dangerous bullet enters the threat sphere.
## The bullet is on a collision course with the player.
signal threat_detected(bullet: Area2D)

## Radius of the threat detection sphere (in pixels).
@export var threat_radius: float = 150.0

## Tolerance angle (in degrees) for trajectory checking.
## A bullet heading within this angle of the player is considered a threat.
@export var trajectory_tolerance_degrees: float = 15.0

## Reference to the parent player node.
var _player: Node2D = null

## Enable debug logging.
var _debug: bool = false


func _ready() -> void:
	# Get parent reference (should be the player)
	_player = get_parent() as Node2D
	if _player == null:
		push_error("ThreatSphere: Must be a child of a Node2D (player)")
		return

	# Set up collision shape if not present
	_setup_collision_shape()

	# Connect to area entered signal to detect bullets
	area_entered.connect(_on_area_entered)

	_log("ThreatSphere ready on %s with radius %s" % [_player.name, threat_radius])


## Sets up the collision shape for the threat sphere.
func _setup_collision_shape() -> void:
	var collision_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape == null:
		# Create collision shape if not present
		collision_shape = CollisionShape2D.new()
		collision_shape.name = "ThreatCollisionShape"
		add_child(collision_shape)

	# Create or update the circle shape
	var circle_shape := CircleShape2D.new()
	circle_shape.radius = threat_radius
	collision_shape.shape = circle_shape


## Called when an area (potentially a bullet) enters the threat sphere.
func _on_area_entered(area: Area2D) -> void:
	# Only process if we have a valid player reference
	if _player == null:
		return

	# Check if this is a bullet
	if not _is_bullet(area):
		return

	# Check if it's a player bullet - but we still want to detect it if it's
	# heading TOWARD the player (e.g., ricocheted bullets coming back)
	var is_player_bullet := _is_player_bullet(area)
	if is_player_bullet:
		# For player bullets, only consider them threats if they're heading back at the player
		# (e.g., from a ricochet)
		if not _is_bullet_heading_toward_player(area):
			_log("Ignoring player's own bullet (not heading toward player)")
			return
		else:
			_log("Player's own bullet heading toward player (ricochet threat)!")

	# Check if bullet is heading toward the player
	if _is_bullet_heading_toward_player(area):
		_log("THREAT DETECTED: Bullet heading toward player!")
		threat_detected.emit(area)


## Checks if the area is a bullet.
func _is_bullet(area: Area2D) -> bool:
	# Check by script name (GDScript bullet)
	var script: Script = area.get_script()
	if script != null:
		var script_path: String = script.resource_path
		if "bullet" in script_path.to_lower():
			return true

	# Check by class name (C# bullet)
	var class_name_str: String = area.get_class()
	if "Bullet" in class_name_str:
		return true

	# Check by node name
	if "Bullet" in area.name or "bullet" in area.name:
		return true

	return false


## Checks if the bullet was fired by the player.
func _is_player_bullet(area: Area2D) -> bool:
	# Check for shooter_id property (GDScript)
	if "shooter_id" in area:
		var shooter_id: int = area.shooter_id
		if shooter_id != -1:
			var shooter: Object = instance_from_id(shooter_id)
			if shooter != null and shooter == _player:
				return true
			# Check if shooter is in player group
			if shooter != null and shooter is Node:
				if (shooter as Node).is_in_group("player"):
					return true

	# Check for ShooterId property (C# uses different naming)
	if area.has_method("get") and area.get("ShooterId") != null:
		var shooter_id: int = area.get("ShooterId")
		if shooter_id != 0:
			var shooter: Object = instance_from_id(shooter_id)
			if shooter != null and shooter == _player:
				return true
			if shooter != null and shooter is Node:
				if (shooter as Node).is_in_group("player"):
					return true

	return false


## Checks if the bullet is heading toward the player (on a collision course).
func _is_bullet_heading_toward_player(area: Area2D) -> bool:
	# Get bullet position and direction
	var bullet_pos: Vector2 = area.global_position
	var bullet_direction: Vector2 = Vector2.ZERO

	# Try to get direction from GDScript bullet
	if "direction" in area:
		bullet_direction = area.direction

	# Try to get direction from C# bullet
	elif area.has_method("get") and area.get("Direction") != null:
		bullet_direction = area.get("Direction")

	# Fallback: try to infer direction from rotation
	else:
		bullet_direction = Vector2.RIGHT.rotated(area.rotation)

	if bullet_direction == Vector2.ZERO:
		_log("Could not determine bullet direction")
		return false

	bullet_direction = bullet_direction.normalized()

	# Calculate vector from bullet to player
	var player_pos: Vector2 = _player.global_position
	var to_player: Vector2 = (player_pos - bullet_pos).normalized()

	# Calculate angle between bullet direction and direction to player
	var angle_to_player_rad: float = bullet_direction.angle_to(to_player)
	var angle_to_player_deg: float = abs(rad_to_deg(angle_to_player_rad))

	_log("Bullet at %s heading %s, angle to player: %.1f degrees" % [bullet_pos, bullet_direction, angle_to_player_deg])

	# Check if bullet is heading toward player within tolerance
	if angle_to_player_deg <= trajectory_tolerance_degrees:
		return true

	return false


## Logs a debug message.
func _log(message: String) -> void:
	if not _debug:
		return
	var logger: Node = get_node_or_null("/root/FileLogger")
	if logger and logger.has_method("log_info"):
		logger.log_info("[ThreatSphere] " + message)
	else:
		print("[ThreatSphere] " + message)
