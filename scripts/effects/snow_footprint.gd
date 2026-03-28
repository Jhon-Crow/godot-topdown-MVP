extends Sprite2D
## Boot-print decal left in snow by characters walking on the Winter Forest ground (Issue #1627).
##
## Snow footprints use the same boot-print textures as BloodFootprint but are
## tinted near-white to blend with the snow surface.  Alpha is set at spawn time
## and never changes (no fade animation) — tracks simply persist on the ground
## until the scene ends.
class_name SnowFootprint

## Initial alpha value (set by SnowyFeetComponent when spawning).
var _initial_alpha: float = 0.55

## Snow tint color — slightly off-white so prints are subtly visible.
var _snow_tint: Color = Color(0.82, 0.85, 0.9, 1.0)

## Preloaded textures for left and right boot prints (shared with BloodFootprint).
static var _left_texture: Texture2D = null
static var _right_texture: Texture2D = null

## Whether textures have been loaded.
static var _textures_loaded: bool = false


func _ready() -> void:
	# Render above floor but below characters (same layer as BloodFootprint).
	z_index = 0
	_load_textures()


## Loads boot print textures (static, loaded once for all instances).
static func _load_textures() -> void:
	if _textures_loaded:
		return

	var left_path := "res://assets/sprites/effects/boot_print_left.png"
	var right_path := "res://assets/sprites/effects/boot_print_right.png"

	if ResourceLoader.exists(left_path):
		_left_texture = load(left_path)
	else:
		push_warning("SnowFootprint: Left boot texture not found at " + left_path)

	if ResourceLoader.exists(right_path):
		_right_texture = load(right_path)
	else:
		push_warning("SnowFootprint: Right boot texture not found at " + right_path)

	_textures_loaded = true


## Sets the alpha value of this footprint.
## Called by SnowyFeetComponent when spawning.
func set_alpha(alpha: float) -> void:
	_initial_alpha = alpha
	modulate.a = alpha


## Sets which foot this print belongs to (left or right).
## Called by SnowyFeetComponent when spawning.
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

	# Apply snow tint (near-white) after setting the texture so both RGB and A are correct.
	modulate.r = _snow_tint.r
	modulate.g = _snow_tint.g
	modulate.b = _snow_tint.b
	# Alpha is set separately via set_alpha().


## Immediately removes this footprint node.
func remove() -> void:
	queue_free()
