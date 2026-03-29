extends Sprite2D
## Bloody snow indentation decal — oval shape like SnowFootprint but tinted pale red.
##
## Spawned by BloodyFeetComponent when the character is on a snow surface and
## has blood on their feet.  Uses the same oval snow_print textures but with a
## pale pinkish-red modulate so it looks like blood absorbed/pressed into snow.
## Does NOT use boot-shaped textures — only oval dents, same as SnowFootprint.
class_name SnowBloodFootprint

## Default pale red blood-on-snow color.
var _blood_color: Color = Color(0.85, 0.35, 0.35, 1.0)

## Preloaded oval snow indentation textures (shared with SnowFootprint).
static var _left_texture: Texture2D = null
static var _right_texture: Texture2D = null
static var _textures_loaded: bool = false


func _ready() -> void:
	z_index = 0
	_load_textures()


static func _load_textures() -> void:
	if _textures_loaded:
		return

	var left_path := "res://assets/sprites/effects/snow_print_left.png"
	var right_path := "res://assets/sprites/effects/snow_print_right.png"

	if ResourceLoader.exists(left_path):
		_left_texture = load(left_path)
	else:
		push_warning("SnowBloodFootprint: Left snow print texture not found at " + left_path)

	if ResourceLoader.exists(right_path):
		_right_texture = load(right_path)
	else:
		push_warning("SnowBloodFootprint: Right snow print texture not found at " + right_path)

	_textures_loaded = true


## Sets which foot this print belongs to (left or right).
func set_foot(is_left: bool) -> void:
	_load_textures()
	if is_left and _left_texture:
		texture = _left_texture
	elif not is_left and _right_texture:
		texture = _right_texture
	else:
		if _left_texture:
			texture = _left_texture
		elif _right_texture:
			texture = _right_texture


## Sets the blood color (pale red tint applied as modulate).
func set_blood_color(puddle_color: Color) -> void:
	_blood_color = puddle_color
	# Desaturate toward pale pink-red to look like blood absorbed into snow.
	var pale_r := lerpf(puddle_color.r, 1.0, 0.45)
	var pale_g := lerpf(puddle_color.g, 0.85, 0.45)
	var pale_b := lerpf(puddle_color.b, 0.85, 0.45)
	modulate.r = pale_r
	modulate.g = pale_g
	modulate.b = pale_b


## Sets the alpha of this footprint.
func set_alpha(alpha: float) -> void:
	modulate.a = alpha


## Immediately removes this footprint.
func remove() -> void:
	queue_free()
