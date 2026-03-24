extends Sprite2D
class_name ExplosionScorchMark
## Persistent scorch mark that remains on the floor after grenade explosions.
##
## Scorch marks represent the burn damage from explosions. Size and visibility
## vary based on grenade type:
## - Flashbang: Small, almost invisible (non-lethal, minimal heat)
## - Frag (Offensive): Medium, noticeable burnt mark
## - F-1 (Defensive): Large, prominent burnt mark
##
## Issue #1005: After grenade explosion there should be a mark on the floor.

## Scorch mark radius in pixels.
## This determines the size of the circular scorch mark.
@export var scorch_radius: float = 40.0

## Alpha (opacity) of the scorch mark.
## Flashbang marks are almost invisible (0.15), while F-1 marks are prominent (0.7).
@export var scorch_alpha: float = 0.6

## Whether the scorch mark should fade out over time.
## Default is false for permanent marks.
@export var auto_fade: bool = false

## Time in seconds before the mark starts fading (only if auto_fade is true).
@export var fade_delay: float = 120.0

## Time in seconds for the fade-out animation (only if auto_fade is true).
@export var fade_duration: float = 30.0

## Grenade type that created this mark (for debugging/logging).
var grenade_type: String = "unknown"


func _ready() -> void:
	# Generate the scorch mark texture based on configured radius
	texture = _create_scorch_texture(int(scorch_radius))

	# Apply the configured alpha
	modulate = Color(1.0, 1.0, 1.0, scorch_alpha)

	# Draw below most effects but above floor
	z_index = 0

	# Add small random rotation for visual variety
	rotation = randf_range(0, TAU)

	if auto_fade:
		_start_fade_timer()

	FileLogger.info("[ExplosionScorchMark] Created %s scorch mark at %s (radius: %.1f, alpha: %.2f)" % [
		grenade_type, str(global_position), scorch_radius, scorch_alpha
	])


## Creates a radial gradient texture for the scorch mark.
## The texture has a dark center fading to transparent edges.
func _create_scorch_texture(radius: int) -> ImageTexture:
	var size := radius * 2
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(radius, radius)

	for x in range(size):
		for y in range(size):
			var pos := Vector2(x, y)
			var distance := pos.distance_to(center)
			var normalized_dist := distance / radius

			if normalized_dist <= 1.0:
				# Calculate color based on distance from center
				# Center is dark charcoal, edges fade to transparent
				var alpha: float
				var brightness: float

				if normalized_dist < 0.3:
					# Inner core - darkest, full opacity
					alpha = 1.0
					brightness = 0.05
				elif normalized_dist < 0.6:
					# Mid section - slightly lighter, still mostly opaque
					var t := (normalized_dist - 0.3) / 0.3
					alpha = lerp(1.0, 0.7, t)
					brightness = lerp(0.05, 0.12, t)
				else:
					# Outer edge - fading out
					var t := (normalized_dist - 0.6) / 0.4
					alpha = lerp(0.7, 0.0, t)
					brightness = lerp(0.12, 0.18, t)

				# Add slight brown/red tint to simulate burnt appearance
				var r := brightness * 1.0
				var g := brightness * 0.85
				var b := brightness * 0.75

				image.set_pixel(x, y, Color(r, g, b, alpha))
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))

	return ImageTexture.create_from_image(image)


## Starts the timer for automatic fade-out.
## Only called if auto_fade is true.
func _start_fade_timer() -> void:
	var tree := get_tree()
	if tree == null:
		return

	await tree.create_timer(fade_delay).timeout

	# Check if node is still valid after await
	if not is_instance_valid(self) or not is_inside_tree():
		return

	# Gradually fade out
	var tween := create_tween()
	if tween == null:
		queue_free()
		return

	tween.tween_property(self, "modulate:a", 0.0, fade_duration)
	tween.tween_callback(queue_free)


## Immediately removes the scorch mark.
func remove() -> void:
	queue_free()


## Fades out the scorch mark quickly (for cleanup).
func fade_out_quick() -> void:
	var tween := create_tween()
	if tween:
		tween.tween_property(self, "modulate:a", 0.0, 0.5)
		tween.tween_callback(queue_free)
	else:
		queue_free()


## Factory method to create a scorch mark with specific parameters.
## @param pos: Global position for the scorch mark.
## @param radius: Radius in pixels.
## @param alpha: Opacity (0.0 to 1.0).
## @param type: Grenade type string for logging.
static func create_at(pos: Vector2, radius: float, alpha: float, type: String) -> ExplosionScorchMark:
	var mark := ExplosionScorchMark.new()
	mark.scorch_radius = radius
	mark.scorch_alpha = alpha
	mark.grenade_type = type
	mark.global_position = pos
	return mark
