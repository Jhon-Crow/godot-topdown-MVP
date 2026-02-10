extends Area2D
class_name ExitZone
## Exit zone component for level completion.
##
## This component creates an exit zone that the player must touch after clearing
## all enemies to complete the level and show the score. The exit is initially
## hidden and becomes visible when all enemies are eliminated.
##
## Usage:
## 1. Add this scene to your level
## 2. Connect the level's _on_all_enemies_eliminated signal to show the exit
## 3. The exit emits player_reached_exit when the player enters the zone

## Signal emitted when the player reaches the exit zone.
signal player_reached_exit

## Whether the exit zone is currently active (all enemies eliminated).
var _is_active: bool = false

## Whether the teleport animation is currently playing.
var _teleport_animating: bool = false

## Reference to the teleport effect instance.
var _teleport_effect: Node2D = null

## Teleport effect scene path.
const TELEPORT_EFFECT_SCENE: String = "res://scenes/effects/TeleportEffect.tscn"

## Visual indicator for the exit.
var _exit_visual: ColorRect = null

## Label showing "EXIT" text.
var _exit_label: Label = null

## Arrow indicator pointing to the exit.
var _arrow_indicator: Label = null

## Reference to the player for distance calculation.
var _player: Node2D = null

## Collision shape for detection.
var _collision_shape: CollisionShape2D = null

## Exit zone size.
@export var zone_width: float = 80.0
@export var zone_height: float = 120.0

## Exit zone position offset from this node's position.
@export var zone_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	# Create the collision shape
	_create_collision_shape()

	# Create visual elements
	_create_visuals()

	# Set collision layers - detect player (layer 1)
	collision_layer = 0
	collision_mask = 1  # Player is on layer 1

	# Connect area entered signal
	body_entered.connect(_on_body_entered)

	# Find player reference
	_find_player()

	# Start hidden until level is cleared
	_set_visible(false)

	# Set monitoring to false initially
	monitoring = false


func _process(_delta: float) -> void:
	if _is_active and _player != null and is_instance_valid(_player):
		_update_arrow_indicator()


## Create the collision shape for the exit zone.
func _create_collision_shape() -> void:
	_collision_shape = CollisionShape2D.new()
	_collision_shape.name = "CollisionShape2D"

	var shape := RectangleShape2D.new()
	shape.size = Vector2(zone_width, zone_height)
	_collision_shape.shape = shape
	_collision_shape.position = zone_offset

	add_child(_collision_shape)


## Create visual elements for the exit.
func _create_visuals() -> void:
	# Create background glow
	_exit_visual = ColorRect.new()
	_exit_visual.name = "ExitVisual"
	_exit_visual.color = Color(0.2, 1.0, 0.3, 0.4)
	_exit_visual.size = Vector2(zone_width + 16, zone_height + 16)
	_exit_visual.position = zone_offset - Vector2(zone_width / 2 + 8, zone_height / 2 + 8)
	add_child(_exit_visual)

	# Create inner area
	var inner_rect := ColorRect.new()
	inner_rect.name = "InnerRect"
	inner_rect.color = Color(0.3, 1.0, 0.4, 0.6)
	inner_rect.size = Vector2(zone_width, zone_height)
	inner_rect.position = zone_offset - Vector2(zone_width / 2, zone_height / 2)
	add_child(inner_rect)

	# Create exit label
	_exit_label = Label.new()
	_exit_label.name = "ExitLabel"
	_exit_label.text = "ВЫХОД"
	_exit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_exit_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_exit_label.add_theme_font_size_override("font_size", 24)
	_exit_label.add_theme_color_override("font_color", Color.WHITE)
	_exit_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_exit_label.add_theme_constant_override("shadow_offset_x", 2)
	_exit_label.add_theme_constant_override("shadow_offset_y", 2)
	_exit_label.size = Vector2(zone_width + 16, 40)
	_exit_label.position = zone_offset - Vector2(zone_width / 2 + 8, zone_height / 2 + 50)
	add_child(_exit_label)

	# Create arrow indicator (shows when player is far from exit)
	_arrow_indicator = Label.new()
	_arrow_indicator.name = "ArrowIndicator"
	_arrow_indicator.text = "← ВЫХОД"
	_arrow_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_arrow_indicator.add_theme_font_size_override("font_size", 32)
	_arrow_indicator.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4, 1.0))
	_arrow_indicator.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_arrow_indicator.add_theme_constant_override("shadow_offset_x", 2)
	_arrow_indicator.add_theme_constant_override("shadow_offset_y", 2)
	_arrow_indicator.visible = false
	add_child(_arrow_indicator)


## Find the player in the scene.
func _find_player() -> void:
	# Try to find player in common locations
	var root := get_tree().current_scene
	if root:
		_player = root.get_node_or_null("Entities/Player")


## Update the arrow indicator to point toward exit.
func _update_arrow_indicator() -> void:
	if _player == null or not is_instance_valid(_player):
		_arrow_indicator.visible = false
		return

	var exit_pos: Vector2 = global_position + zone_offset
	var player_pos: Vector2 = _player.global_position
	var distance: float = player_pos.distance_to(exit_pos)

	# Show arrow when player is far from exit
	if distance > 500.0:
		_arrow_indicator.visible = true

		# Calculate direction to exit
		var direction: Vector2 = (exit_pos - player_pos).normalized()

		# Position arrow near the player in world space (converted to local coordinates)
		# The arrow is a child of ExitZone, so we need to convert player's world position
		# to ExitZone's local coordinate space
		var arrow_offset: float = 80.0
		var arrow_world_pos: Vector2 = player_pos + direction * arrow_offset
		_arrow_indicator.position = arrow_world_pos - global_position - Vector2(80, 20)

		# Update arrow text based on direction
		if abs(direction.x) > abs(direction.y):
			if direction.x < 0:
				_arrow_indicator.text = "← ВЫХОД"
			else:
				_arrow_indicator.text = "ВЫХОД →"
		else:
			if direction.y < 0:
				_arrow_indicator.text = "↑ ВЫХОД"
			else:
				_arrow_indicator.text = "ВЫХОД ↓"
	else:
		_arrow_indicator.visible = false


## Set the visibility of the exit zone.
func _set_visible(visible_state: bool) -> void:
	for child in get_children():
		if child is CanvasItem:
			child.visible = visible_state


## Activate the exit zone when all enemies are eliminated.
func activate() -> void:
	_is_active = true
	monitoring = true
	_set_visible(true)

	# Find player again in case it wasn't found during _ready
	if _player == null:
		_find_player()

	# Animate the exit appearing
	var tween := create_tween()
	tween.set_parallel(true)

	for child in get_children():
		if child is CanvasItem:
			child.modulate = Color(1, 1, 1, 0)
			tween.tween_property(child, "modulate:a", 1.0, 0.5)

	print("[ExitZone] Exit zone activated - waiting for player")


## Deactivate the exit zone.
func deactivate() -> void:
	_is_active = false
	monitoring = false
	_set_visible(false)


## Called when a body enters the exit zone.
func _on_body_entered(body: Node2D) -> void:
	if not _is_active:
		return

	# Prevent multiple triggers while animating
	if _teleport_animating:
		return

	# Check if it's the player
	if body.name == "Player" or body.is_in_group("player"):
		print("[ExitZone] Player reached exit - starting teleport effect!")
		_play_teleport_effect(body)


## Play the teleport visual effect when player reaches exit (Issue #721).
func _play_teleport_effect(player_body: Node2D) -> void:
	_teleport_animating = true

	# Disable player input during teleportation
	if player_body.has_method("set_physics_process"):
		player_body.set_physics_process(false)

	# Try to load and instantiate the teleport effect
	var effect_scene: PackedScene = null
	if ResourceLoader.exists(TELEPORT_EFFECT_SCENE):
		effect_scene = load(TELEPORT_EFFECT_SCENE)

	if effect_scene:
		_teleport_effect = effect_scene.instantiate()
		_teleport_effect.global_position = player_body.global_position

		# Add to scene tree (add to parent so it's at the same level as player)
		var parent := player_body.get_parent()
		if parent:
			parent.add_child(_teleport_effect)
		else:
			add_child(_teleport_effect)

		# Set target for visibility control
		if _teleport_effect.has_method("set_target"):
			_teleport_effect.set_target(player_body)

		# Connect to animation finished signal
		if _teleport_effect.has_signal("animation_finished"):
			_teleport_effect.animation_finished.connect(_on_teleport_animation_finished)

		# Start the disappear animation
		if _teleport_effect.has_method("play_disappear"):
			_teleport_effect.play_disappear()
		else:
			# Fallback: complete immediately if effect doesn't have play_disappear
			_on_teleport_animation_finished("disappear")
	else:
		# Fallback: no effect scene, emit signal immediately
		print("[ExitZone] Teleport effect scene not found, completing immediately")
		_teleport_animating = false
		player_reached_exit.emit()


## Called when the teleport animation finishes.
func _on_teleport_animation_finished(animation_type: String) -> void:
	print("[ExitZone] Teleport animation finished: %s" % animation_type)

	# Clean up the effect
	if _teleport_effect and is_instance_valid(_teleport_effect):
		_teleport_effect.queue_free()
		_teleport_effect = null

	_teleport_animating = false

	# Emit the signal to complete the level
	player_reached_exit.emit()
