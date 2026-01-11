extends Area2D
## Bullet projectile that travels in a direction and handles collisions.
##
## The bullet moves at a constant speed in its rotation direction.
## It destroys itself when hitting walls or targets, and triggers
## target reactions on hit.

## Speed of the bullet in pixels per second.
@export var speed: float = 600.0

## Maximum lifetime in seconds before auto-destruction.
@export var lifetime: float = 3.0

## Direction the bullet travels (set by the shooter).
var direction: Vector2 = Vector2.RIGHT

## Timer tracking remaining lifetime.
var _time_alive: float = 0.0


func _ready() -> void:
	# Connect to collision signals
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	# Move in the set direction
	position += direction * speed * delta

	# Track lifetime and auto-destroy if exceeded
	_time_alive += delta
	if _time_alive >= lifetime:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	# Hit a static body (wall or obstacle)
	queue_free()


func _on_area_entered(area: Area2D) -> void:
	# Hit another area (like a target)
	if area.has_method("on_hit"):
		area.on_hit()
	queue_free()
