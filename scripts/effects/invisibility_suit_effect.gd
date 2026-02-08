extends Node
## Invisibility suit effect controller (Issue #673).
##
## Manages the Predator-style invisibility cloak for the player.
## When activated via Space key, the player becomes invisible to enemies
## for a limited duration. The visual effect is a transparent ripple
## (chromatic distortion) applied to all player sprites.
##
## Gameplay rules:
## - 2 charges per battle (resets on level restart)
## - Each activation lasts 4 seconds
## - Enemies cannot see the player while invisible (vision blocked)
## - Enemies can still hear gunshots and reload sounds (sound NOT blocked)

## Duration of invisibility effect in seconds.
const EFFECT_DURATION: float = 4.0

## Maximum charges per battle.
const MAX_CHARGES: int = 2

## Time for the cloak to fade in (seconds).
const FADE_IN_TIME: float = 0.3

## Time for the cloak to fade out (seconds).
const FADE_OUT_TIME: float = 0.5

## Shader path for the invisibility cloak effect.
const SHADER_PATH: String = "res://scripts/shaders/invisibility_cloak.gdshader"

## Current number of charges remaining.
var charges: int = MAX_CHARGES

## Whether the invisibility effect is currently active.
var is_active: bool = false

## Timer tracking remaining effect duration.
var _effect_timer: float = 0.0

## Current fade amount (0.0 = visible, 1.0 = fully cloaked).
var _current_mix: float = 0.0

## Whether we are currently fading in or out.
var _is_fading_in: bool = false
var _is_fading_out: bool = false

## Loaded shader resource.
var _shader: Shader = null

## ShaderMaterial applied to player sprites.
var _shader_material: ShaderMaterial = null

## Reference to the player node.
var _player: Node2D = null

## List of sprite nodes that have the shader applied.
var _affected_sprites: Array[CanvasItem] = []

## Original materials saved before applying the cloak shader.
var _original_materials: Dictionary = {}

## Signal emitted when invisibility is activated.
signal invisibility_activated(charges_remaining: int)

## Signal emitted when invisibility wears off.
signal invisibility_deactivated(charges_remaining: int)

## Signal emitted when charges change.
signal charges_changed(current: int, maximum: int)


func _ready() -> void:
	# Load the invisibility shader
	if ResourceLoader.exists(SHADER_PATH):
		_shader = load(SHADER_PATH)
		if _shader:
			_shader_material = ShaderMaterial.new()
			_shader_material.shader = _shader
			_shader_material.set_shader_parameter("mix_amount", 0.0)
			FileLogger.info("[InvisibilitySuit] Shader loaded successfully")
		else:
			FileLogger.info("[InvisibilitySuit] WARNING: Failed to load shader")
	else:
		FileLogger.info("[InvisibilitySuit] WARNING: Shader not found: %s" % SHADER_PATH)


## Initialize with a reference to the player node.
## Must be called after the player model is ready.
func initialize(player: Node2D) -> void:
	_player = player
	FileLogger.info("[InvisibilitySuit] Initialized with player: %s, charges: %d/%d" % [
		player.name, charges, MAX_CHARGES
	])


## Attempt to activate the invisibility effect.
## Returns true if activation was successful.
func activate() -> bool:
	if is_active:
		return false  # Already active

	if charges <= 0:
		FileLogger.info("[InvisibilitySuit] No charges remaining")
		return false

	# Consume a charge
	charges -= 1
	is_active = true
	_effect_timer = EFFECT_DURATION
	_is_fading_in = true
	_is_fading_out = false
	_current_mix = 0.0

	# Apply shader to all player sprites
	_apply_shader_to_player()

	FileLogger.info("[InvisibilitySuit] Activated! Duration: %.1fs, Charges remaining: %d/%d" % [
		EFFECT_DURATION, charges, MAX_CHARGES
	])

	invisibility_activated.emit(charges)
	charges_changed.emit(charges, MAX_CHARGES)
	return true


## Deactivate the invisibility effect (start fade out).
func deactivate() -> void:
	if not is_active:
		return

	_is_fading_in = false
	_is_fading_out = true
	FileLogger.info("[InvisibilitySuit] Deactivating (fade out)")


## Force-stop the invisibility effect immediately (no fade).
func force_stop() -> void:
	is_active = false
	_is_fading_in = false
	_is_fading_out = false
	_current_mix = 0.0
	_effect_timer = 0.0
	_remove_shader_from_player()
	FileLogger.info("[InvisibilitySuit] Force stopped")
	invisibility_deactivated.emit(charges)


func _process(delta: float) -> void:
	if not is_active and not _is_fading_out:
		return

	# Handle fade in
	if _is_fading_in:
		_current_mix = minf(_current_mix + delta / FADE_IN_TIME, 1.0)
		if _current_mix >= 1.0:
			_is_fading_in = false
		_update_shader_mix()

	# Count down effect timer
	if is_active:
		_effect_timer -= delta
		if _effect_timer <= 0.0:
			deactivate()

	# Handle fade out
	if _is_fading_out:
		_current_mix = maxf(_current_mix - delta / FADE_OUT_TIME, 0.0)
		_update_shader_mix()
		if _current_mix <= 0.0:
			_is_fading_out = false
			is_active = false
			_remove_shader_from_player()
			invisibility_deactivated.emit(charges)


## Check if the player is currently invisible to enemies.
## Returns true during the active phase (including fade-in), false during fade-out.
func is_invisible() -> bool:
	return is_active


## Get the remaining effect time in seconds.
func get_remaining_time() -> float:
	return _effect_timer if is_active else 0.0


## Get the current number of charges.
func get_charges() -> int:
	return charges


## Update the shader mix_amount parameter on all affected sprites.
func _update_shader_mix() -> void:
	for sprite in _affected_sprites:
		if is_instance_valid(sprite) and sprite.material is ShaderMaterial:
			(sprite.material as ShaderMaterial).set_shader_parameter("mix_amount", _current_mix)


## Apply the invisibility shader to all player model sprites.
func _apply_shader_to_player() -> void:
	if _player == null or _shader_material == null:
		return

	_affected_sprites.clear()
	_original_materials.clear()

	# Find the PlayerModel node
	var player_model: Node2D = _player.get_node_or_null("PlayerModel")
	if player_model == null:
		FileLogger.info("[InvisibilitySuit] WARNING: PlayerModel not found")
		return

	# Apply shader to all CanvasItem children of PlayerModel (Body, Head, Arms, WeaponMount children)
	_apply_shader_recursive(player_model)

	FileLogger.info("[InvisibilitySuit] Shader applied to %d sprites" % _affected_sprites.size())


## Recursively apply the invisibility shader to a node and its children.
func _apply_shader_recursive(node: Node) -> void:
	for child in node.get_children():
		if child is CanvasItem:
			var canvas_item: CanvasItem = child as CanvasItem
			var key: String = str(canvas_item.get_instance_id())

			# Save original material
			_original_materials[key] = canvas_item.material

			# Create a unique ShaderMaterial copy for each sprite
			# so they can be individually controlled if needed
			var mat := ShaderMaterial.new()
			mat.shader = _shader
			mat.set_shader_parameter("mix_amount", _current_mix)
			canvas_item.material = mat
			_affected_sprites.append(canvas_item)

		# Recurse into children (e.g., WeaponMount -> weapon sprites)
		_apply_shader_recursive(child)


## Remove the invisibility shader from all affected sprites, restoring originals.
func _remove_shader_from_player() -> void:
	for sprite in _affected_sprites:
		if is_instance_valid(sprite):
			var key: String = str(sprite.get_instance_id())
			if _original_materials.has(key):
				sprite.material = _original_materials[key]
			else:
				sprite.material = null

	_affected_sprites.clear()
	_original_materials.clear()
