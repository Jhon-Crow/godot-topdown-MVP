class_name GunslingerGlowComponent
extends Node
## Manages the red PointLight2D glow and warm sprite tint for Gunslinger difficulty enemies.
## Issues #1727, #1732, #1753.
##
## Extracted from enemy.gd to reduce file size.
## Call initialize() once the enemy is ready, passing sprite nodes and the invisibility component.
## Call show_glow() when the enemy is revealed; call hide_glow() when the enemy re-cloaks.

const GLOW_COLOR: Color = Color(1.0, 0.1, 0.05, 1.0)
const WARM_TINT: Color = Color(1.3, 1.15, 1.1, 1.0)
const GLOW_ENERGY: float = 2.0
const GLOW_SCALE: float = 1.6
const TEXTURE_SIZE: int = 256

var _glow_node: PointLight2D = null
var _body_sprite: Node = null
var _head_sprite: Node = null
var _left_arm_sprite: Node = null
var _right_arm_sprite: Node = null


## Set up glow light and tint. Pass sprite nodes and optionally the invisibility component.
## If the enemy starts cloaked, glow is hidden until show_glow() is called.
func initialize(
		owner_node: Node,
		body_sprite: Node,
		head_sprite: Node,
		left_arm_sprite: Node,
		right_arm_sprite: Node,
		invisibility: EnemyInvisibilityComponent
	) -> void:
	_body_sprite = body_sprite
	_head_sprite = head_sprite
	_left_arm_sprite = left_arm_sprite
	_right_arm_sprite = right_arm_sprite

	var gl := PointLight2D.new()
	gl.name = "GunslingerEnemyGlow"
	gl.color = GLOW_COLOR
	gl.energy = GLOW_ENERGY
	gl.texture_scale = GLOW_SCALE
	gl.shadow_enabled = false
	gl.blend_mode = Light2D.BLEND_MODE_ADD
	# Issue #1732: Build circular ImageTexture (pixel-distance falloff, like room lights) so glow is round.
	var sz := TEXTURE_SIZE
	var c := Vector2(sz * 0.5, sz * 0.5)
	var r := sz * 0.5
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	for y in range(sz):
		for x in range(sz):
			var b := pow(1.0 - clampf(Vector2(x, y).distance_to(c) / r, 0.0, 1.0), 2.0)
			img.set_pixel(x, y, Color(b, b, b, 1.0))
	gl.texture = ImageTexture.create_from_image(img)
	owner_node.add_child(gl)
	_glow_node = gl

	# Issue #1753: If enemy starts cloaked, hide the glow; connect to recloaked signal.
	if invisibility != null and invisibility.is_cloaked:
		gl.visible = false
		invisibility.recloaked.connect(hide_glow)
	else:
		_apply_warm_tint()


## Show glow and warm tint (called when cloaked enemy is revealed).
func show_glow() -> void:
	if _glow_node == null:
		return
	_glow_node.visible = true
	_apply_warm_tint()


## Hide glow and reset tint (called when enemy re-cloaks).
func hide_glow() -> void:
	if _glow_node == null:
		return
	_glow_node.visible = false
	_reset_tint()


func _apply_warm_tint() -> void:
	if _body_sprite: (_body_sprite as CanvasItem).modulate = WARM_TINT
	if _head_sprite: (_head_sprite as CanvasItem).modulate = WARM_TINT
	if _left_arm_sprite: (_left_arm_sprite as CanvasItem).modulate = WARM_TINT
	if _right_arm_sprite: (_right_arm_sprite as CanvasItem).modulate = WARM_TINT


func _reset_tint() -> void:
	if _body_sprite: (_body_sprite as CanvasItem).modulate = Color.WHITE
	if _head_sprite: (_head_sprite as CanvasItem).modulate = Color.WHITE
	if _left_arm_sprite: (_left_arm_sprite as CanvasItem).modulate = Color.WHITE
	if _right_arm_sprite: (_right_arm_sprite as CanvasItem).modulate = Color.WHITE
