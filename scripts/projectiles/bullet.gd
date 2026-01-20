extends Area2D
## Bullet projectile that travels in a direction and handles collisions.
##
## The bullet moves at a constant speed in its rotation direction.
## It destroys itself when hitting walls or targets, and triggers
## target reactions on hit.
##
## Features a visual tracer trail effect for better visibility and
## realistic appearance during fast movement.

## Speed of the bullet in pixels per second.
## Default is 2500 for faster projectiles that make combat more challenging.
@export var speed: float = 2500.0

## Maximum lifetime in seconds before auto-destruction.
@export var lifetime: float = 3.0

## Maximum number of trail points to maintain.
## Higher values create longer trails but use more memory.
@export var trail_length: int = 8

## Direction the bullet travels (set by the shooter).
var direction: Vector2 = Vector2.RIGHT

## Instance ID of the node that shot this bullet.
## Used to prevent self-detection (e.g., enemies detecting their own bullets).
var shooter_id: int = -1

## Timer tracking remaining lifetime.
var _time_alive: float = 0.0

## Reference to the trail Line2D node (if present).
var _trail: Line2D = null

## History of global positions for the trail effect.
var _position_history: Array[Vector2] = []


func _ready() -> void:
	# Connect to collision signals
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

	# Get trail reference if it exists
	_trail = get_node_or_null("Trail")
	if _trail:
		_trail.clear_points()
		# Set trail to use global coordinates (not relative to bullet)
		_trail.top_level = true

	# Set initial rotation based on direction
	_update_rotation()


## Updates the bullet rotation to match its travel direction.
func _update_rotation() -> void:
	rotation = direction.angle()


func _physics_process(delta: float) -> void:
	# Move in the set direction
	position += direction * speed * delta

	# Update trail effect
	_update_trail()

	# Track lifetime and auto-destroy if exceeded
	_time_alive += delta
	if _time_alive >= lifetime:
		queue_free()


## Updates the visual trail effect by maintaining position history.
func _update_trail() -> void:
	if not _trail:
		return

	# Add current position to history
	_position_history.push_front(global_position)

	# Limit trail length
	while _position_history.size() > trail_length:
		_position_history.pop_back()

	# Update Line2D points
	_trail.clear_points()
	for pos in _position_history:
		_trail.add_point(pos)


func _on_body_entered(body: Node2D) -> void:
	# Check if this is the shooter - don't collide with own body
	if shooter_id == body.get_instance_id():
		return  # Pass through the shooter

	# Check if this is a dead enemy - bullets should pass through dead entities
	# This handles the CharacterBody2D collision (separate from HitArea collision)
	if body.has_method("is_alive") and not body.is_alive():
		return  # Pass through dead entities

	# Hit a static body (wall or obstacle) or alive enemy body
	# Play wall impact sound
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_bullet_wall_hit"):
		audio_manager.play_bullet_wall_hit(global_position)
	queue_free()


func _on_area_entered(area: Area2D) -> void:
	# Hit another area (like a target or hit detection area)
	# Only destroy bullet if the area has on_hit method (actual hit targets)
	# This allows bullets to pass through detection-only areas like ThreatSpheres
	if area.has_method("on_hit"):
		# Check if this is a HitArea - if so, check against parent's instance ID
		# This prevents the shooter from damaging themselves
		var parent: Node = area.get_parent()
		if parent and shooter_id == parent.get_instance_id():
			return  # Don't hit the shooter

		# Check if the parent is dead - bullets should pass through dead entities
		# This is a fallback check in case the collision shape/layer disabling
		# doesn't take effect immediately (see Godot issues #62506, #100687)
		if parent and parent.has_method("is_alive") and not parent.is_alive():
			return  # Pass through dead entities

		area.on_hit()

		# Trigger hit effects if this is a player bullet hitting an enemy
		if _is_player_bullet():
			_trigger_player_hit_effects()

		queue_free()


## Checks if this bullet was fired by the player.
func _is_player_bullet() -> bool:
	if shooter_id == -1:
		return false

	var shooter: Object = instance_from_id(shooter_id)
	if shooter == null:
		return false

	# Check if the shooter is a player by script path
	var script: Script = shooter.get_script()
	if script and script.resource_path.contains("player"):
		return true

	return false


## Triggers hit effects via the HitEffectsManager autoload.
## Effects: time slowdown to 0.9 for 3 seconds, saturation boost for 400ms.
func _trigger_player_hit_effects() -> void:
	var hit_effects_manager: Node = get_node_or_null("/root/HitEffectsManager")
	if hit_effects_manager and hit_effects_manager.has_method("on_player_hit_enemy"):
		hit_effects_manager.on_player_hit_enemy()
