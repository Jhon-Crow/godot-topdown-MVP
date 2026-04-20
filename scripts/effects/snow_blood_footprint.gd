extends Sprite2D
## Bloody snow indentation decal — oval shape like SnowFootprint but tinted red.
##
## Spawned by BloodyFeetComponent when the character is on a snow surface and
## has blood on their feet (first snow_blood_steps_count steps after stepping in blood).
## Uses the same oval snow_print textures but with the blood puddle's red color applied
## so it looks like blood pressed into the snow. After these steps SnowyFeetComponent
## resumes normal white snow prints (Issue #1627).
## Does NOT use boot-shaped textures — only oval dents, same as SnowFootprint.
class_name SnowBloodFootprint

## Default red blood color.
var _blood_color: Color = Color(0.545, 0.0, 0.0, 1.0)

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


## Sets the blood color (red tint applied as modulate — full blood color, not desaturated).
func set_blood_color(puddle_color: Color) -> void:
	_blood_color = puddle_color
	# Apply the blood puddle color directly so prints look like red blood on snow (Issue #1627).
	modulate.r = puddle_color.r
	modulate.g = puddle_color.g
	modulate.b = puddle_color.b


## Sets the alpha of this footprint.
func set_alpha(alpha: float) -> void:
	modulate.a = alpha


## Immediately removes this footprint.
func remove() -> void:
	queue_free()
