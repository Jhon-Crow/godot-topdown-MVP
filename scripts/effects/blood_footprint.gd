extends Sprite2D
## Bloody boot print decal that persists on the floor.
##
## Blood footprints are spawned when characters walk after stepping
## in blood puddles. Alpha is set at spawn time (no fade animation).
## Supports left/right foot textures for realistic alternating prints.
class_name BloodFootprint

## Initial alpha value (set by spawner based on step count).
var _initial_alpha: float = 0.8

## Blood color from the puddle (RGB, alpha is handled separately).
var _blood_color: Color = Color(0.545, 0.0, 0.0, 1.0)  # Default dark red

## Preloaded textures for left and right boot prints.
static var _left_texture: Texture2D = null
static var _right_texture: Texture2D = null

## Whether textures have been loaded.
static var _textures_loaded: bool = false


func _ready() -> void:
	# Ensure footprint renders above floor but below characters
	# Higher z_index = rendered on top in Godot
	z_index = 1

	# Load textures if not already loaded
	_load_textures()


## Loads boot print textures (static, only done once).
static func _load_textures() -> void:
	if _textures_loaded:
		return

	var left_path := "res://assets/sprites/effects/boot_print_left.png"
	var right_path := "res://assets/sprites/effects/boot_print_right.png"

	if ResourceLoader.exists(left_path):
		_left_texture = load(left_path)
	else:
		push_warning("BloodFootprint: Left boot texture not found at " + left_path)

	if ResourceLoader.exists(right_path):
		_right_texture = load(right_path)
	else:
		push_warning("BloodFootprint: Right boot texture not found at " + right_path)

	_textures_loaded = true


## Sets the footprint's alpha value.
## Called by BloodyFeetComponent when spawning.
func set_alpha(alpha: float) -> void:
	_initial_alpha = alpha
	modulate.a = alpha


## Sets the blood color from the puddle the character stepped in.
## The footprint color will be the same or slightly darker than the puddle.
## Called by BloodyFeetComponent when spawning.
func set_blood_color(puddle_color: Color) -> void:
	_blood_color = puddle_color
	# Apply color to modulate (preserving alpha)
	# Make it the same or slightly darker than the puddle
	modulate.r = puddle_color.r
	modulate.g = puddle_color.g
	modulate.b = puddle_color.b
	# Alpha is set separately via set_alpha()


## Sets which foot this print is for (left or right).
## Called by BloodyFeetComponent when spawning.
func set_foot(is_left: bool) -> void:
	_load_textures()

	if is_left and _left_texture:
		texture = _left_texture
	elif not is_left and _right_texture:
		texture = _right_texture
	else:
		# Fallback: use whichever texture is available
		if _left_texture:
			texture = _left_texture
		elif _right_texture:
			texture = _right_texture


## Immediately removes the footprint.
func remove() -> void:
	queue_free()
