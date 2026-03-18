class_name EnemyInvisibilityComponent
extends Node
## Manages invisibility cloak shader for enemies (Issue #1121).
##
## Extracted from enemy.gd to reduce file size.
## Attach as a child of the enemy node. Call initialize() after the enemy model is ready.
## Call reveal() when the enemy shoots or throws a grenade to briefly show them.
## Call update(delta) each physics frame to tick the re-cloak timer.
## Call remove() on enemy death to restore original materials.

const INVISIBLE_SHADER_PATH: String = "res://scripts/shaders/invisibility_cloak.gdshader"
const REVEAL_DURATION: float = 2.0  ## Seconds enemy stays visible after shooting/throwing.

## Slower ripple speed makes enemies harder to spot than the player's cloak.
const ENEMY_RIPPLE_SPEED: float = 0.6
## Near-zero shimmer so the blue tint outline is barely visible.
const ENEMY_SHIMMER_INTENSITY: float = 0.05

## Whether the enemy invisibility cloak is currently active.
var is_cloaked: bool = false

var _reveal_timer: float = 0.0
var _shader: Shader = null
var _affected_sprites: Array[CanvasItem] = []
var _original_materials: Dictionary = {}
var _logger: Node = null


func _ready() -> void:
	_logger = get_node_or_null("/root/FileLogger")


## Initialize the cloak on the given model node. Call after all nodes are ready.
func initialize(enemy_model: Node) -> void:
	if enemy_model == null:
		_log("[Invisible] WARNING: No enemy model")
		return
	if not ResourceLoader.exists(INVISIBLE_SHADER_PATH):
		_log("[Invisible] WARNING: Shader not found: %s" % INVISIBLE_SHADER_PATH)
		return
	_shader = load(INVISIBLE_SHADER_PATH)
	if _shader == null:
		_log("[Invisible] WARNING: Failed to load shader")
		return
	is_cloaked = true
	_apply_to_model(enemy_model)
	_log("[Invisible] Enemy cloaked at spawn")


## Tick the reveal timer each physics frame; re-cloaks when timer expires.
func update(delta: float) -> void:
	if not is_cloaked or _reveal_timer <= 0.0:
		return
	_reveal_timer -= delta
	if _reveal_timer <= 0.0:
		_set_mix(1.0)
		_reveal_timer = 0.0


## Temporarily reveal the enemy (e.g. when shooting or throwing grenade).
func reveal() -> void:
	if not is_cloaked:
		return
	_set_mix(0.0)
	_reveal_timer = REVEAL_DURATION


## Remove the cloak shader from all sprites, restoring original materials.
func remove() -> void:
	for sprite in _affected_sprites:
		if is_instance_valid(sprite):
			var key: String = str(sprite.get_instance_id())
			sprite.material = _original_materials.get(key, null)
	_affected_sprites.clear()
	_original_materials.clear()
	is_cloaked = false


func _apply_to_model(model: Node) -> void:
	_affected_sprites.clear()
	_original_materials.clear()
	_apply_recursive(model)


func _apply_recursive(node: Node) -> void:
	for child in node.get_children():
		if child is CanvasItem:
			_apply_to_canvas_item(child as CanvasItem)
		_apply_recursive(child)


func _apply_to_canvas_item(canvas_item: CanvasItem) -> void:
	var key: String = str(canvas_item.get_instance_id())
	if _original_materials.has(key):
		return
	_original_materials[key] = canvas_item.material
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("mix_amount", 1.0)
	mat.set_shader_parameter("ripple_speed", ENEMY_RIPPLE_SPEED)
	mat.set_shader_parameter("shimmer_intensity", ENEMY_SHIMMER_INTENSITY)
	canvas_item.material = mat
	_affected_sprites.append(canvas_item)


func _set_mix(amount: float) -> void:
	for sprite in _affected_sprites:
		if is_instance_valid(sprite) and sprite.material is ShaderMaterial:
			(sprite.material as ShaderMaterial).set_shader_parameter("mix_amount", amount)


func _log(msg: String) -> void:
	if _logger and _logger.has_method("write_log"):
		_logger.write_log(msg)
