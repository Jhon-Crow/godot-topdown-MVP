class_name RealisticVisibilityComponent
extends Node
## Realistic visibility component for player fog of war (Issue #540).
##
## Implements Door Kickers 2 style visibility where the player cannot see
## through walls. Uses PointLight2D for player illumination and CanvasModulate
## to darken areas outside the player's line of sight.
##
## Requires LightOccluder2D nodes on walls/obstacles for shadow casting.
## Controlled via ExperimentalSettings.realistic_visibility_enabled toggle.

## Radius of the player's visibility light in pixels.
const VISIBILITY_RADIUS: float = 600.0

## Energy (brightness) of the visibility light.
const LIGHT_ENERGY: float = 1.5

## Color of the fog of war (darkness outside player's vision).
const FOG_COLOR: Color = Color(0.02, 0.02, 0.04, 1.0)

## Color of the visibility light (warm white to simulate natural vision).
const LIGHT_COLOR: Color = Color(1.0, 0.98, 0.95, 1.0)

## Reference to the parent player node.
var _player: Node2D = null

## CanvasModulate node for darkening the scene.
var _canvas_modulate: CanvasModulate = null

## PointLight2D node for player illumination.
var _point_light: PointLight2D = null

## Whether the visibility system is currently active.
var _is_active: bool = false


func _ready() -> void:
	_player = get_parent() as Node2D
	_setup_visibility_system()

	# Listen for experimental settings changes
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		experimental_settings.settings_changed.connect(_on_settings_changed)
		# Apply initial state
		_apply_visibility_state(experimental_settings.is_realistic_visibility_enabled())


## Setup the CanvasModulate and PointLight2D nodes.
func _setup_visibility_system() -> void:
	if _player == null:
		push_warning("[RealisticVisibility] Parent is not a Node2D")
		return

	# Create CanvasModulate for scene-wide darkness
	_canvas_modulate = CanvasModulate.new()
	_canvas_modulate.name = "FogOfWarModulate"
	_canvas_modulate.color = FOG_COLOR
	_canvas_modulate.visible = false

	# Create PointLight2D for player vision
	_point_light = PointLight2D.new()
	_point_light.name = "VisibilityLight"
	_point_light.color = LIGHT_COLOR
	_point_light.energy = LIGHT_ENERGY
	_point_light.shadow_enabled = true
	_point_light.shadow_filter = PointLight2D.SHADOW_FILTER_PCF5
	_point_light.shadow_filter_smooth = 2.0
	_point_light.shadow_item_cull_mask = 1  # Default occlusion mask
	_point_light.texture = _create_light_texture()
	_point_light.texture_scale = VISIBILITY_RADIUS / 512.0
	_point_light.visible = false

	# Add CanvasModulate as sibling of player (it needs to be in the scene tree)
	# PointLight2D should be child of player to follow it
	_player.add_child(_point_light)

	# CanvasModulate must be added to the scene root or level
	# We defer this to ensure the scene tree is ready
	call_deferred("_add_canvas_modulate")


## Add CanvasModulate to the appropriate parent in the scene tree.
func _add_canvas_modulate() -> void:
	if _canvas_modulate == null or _player == null:
		return

	# Add to the level root (parent of player or its container)
	var level_root: Node = _player.get_parent()
	while level_root and level_root.get_parent() and level_root.get_parent() != get_tree().root:
		level_root = level_root.get_parent()

	if level_root:
		level_root.add_child(_canvas_modulate)
	else:
		_player.get_parent().add_child(_canvas_modulate)


## Create a radial gradient texture for the light.
func _create_light_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	# Bright center, smooth falloff to dark edges
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.add_point(0.5, Color(0.8, 0.8, 0.8, 1.0))
	gradient.add_point(0.75, Color(0.4, 0.4, 0.4, 1.0))
	gradient.set_color(1, Color(0.0, 0.0, 0.0, 1.0))

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 1024
	texture.height = 1024
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)

	return texture


## Apply the visibility state (enable/disable fog of war).
func _apply_visibility_state(enabled: bool) -> void:
	_is_active = enabled
	if _canvas_modulate:
		_canvas_modulate.visible = enabled
	if _point_light:
		_point_light.visible = enabled


## Called when experimental settings change.
func _on_settings_changed() -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		_apply_visibility_state(experimental_settings.is_realistic_visibility_enabled())


## Check if the visibility system is currently active.
func is_active() -> bool:
	return _is_active


## Get the current visibility radius.
func get_visibility_radius() -> float:
	return VISIBILITY_RADIUS


## Clean up when removed from scene.
func _exit_tree() -> void:
	if _canvas_modulate and is_instance_valid(_canvas_modulate):
		_canvas_modulate.queue_free()
