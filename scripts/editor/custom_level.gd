extends Node2D
## Builds and runs a custom level from LevelData.
##
## This script reads level data from LevelEditorManager and constructs
## a fully playable level with walls, enemies, cover objects, navigation mesh,
## and the player character. Follows the same structure as built-in levels.

## Duration of saturation effect in seconds.
const SATURATION_DURATION: float = 0.15

## Saturation effect intensity (alpha).
const SATURATION_INTENSITY: float = 0.25

## Reference to the player.
var _player: Node2D = null

## Total enemy count at start.
var _initial_enemy_count: int = 0

## Current enemy count.
var _current_enemy_count: int = 0

## Whether game over has been shown.
var _game_over_shown: bool = false

## The level data used to build this level.
var _level_data: LevelData = null

## Reference to the enemy count label.
var _enemy_count_label: Label = null

## Reference to the ammo count label.
var _ammo_label: Label = null

## Reference to the saturation overlay.
var _saturation_overlay: ColorRect = null

## List of enemy nodes for tracking.
var _enemies: Array = []

## Whether the level has been cleared.
var _level_cleared: bool = false


func _ready() -> void:
	# Get level data from LevelEditorManager
	var manager: Node = get_node_or_null("/root/LevelEditorManager")
	if manager and manager.get("_pending_level_data") != null:
		_level_data = manager.get("_pending_level_data")
		manager.set("_pending_level_data", null)
	else:
		# Try to load the most recent custom level
		if manager and manager.has_method("list_levels"):
			var levels: Array = manager.list_levels()
			if not levels.is_empty():
				_level_data = manager.load_level(levels[-1])

	if _level_data == null:
		_level_data = LevelData.new()
		push_warning("CustomLevel: No level data found, using default.")

	_build_level()
	_setup_ui()
	_setup_enemies()


## Build the level geometry from LevelData.
func _build_level() -> void:
	# Environment node
	var environment := Node2D.new()
	environment.name = "Environment"
	add_child(environment)

	# Floor background
	var floor_rect := ColorRect.new()
	floor_rect.name = "Floor"
	floor_rect.position = Vector2.ZERO
	floor_rect.size = Vector2(_level_data.map_width, _level_data.map_height)
	floor_rect.color = _level_data.floor_color
	environment.add_child(floor_rect)

	# Walls container
	var walls_node := Node2D.new()
	walls_node.name = "Walls"
	environment.add_child(walls_node)

	# Create boundary walls
	_create_boundary_walls(walls_node)

	# Create user-placed walls
	for w in _level_data.walls:
		_create_wall(walls_node, Vector2(w["x"], w["y"]), Vector2(w["w"], w["h"]))

	# Cover container
	var cover_node := Node2D.new()
	cover_node.name = "Cover"
	add_child(cover_node)

	# Create cover objects
	for c in _level_data.cover_objects:
		_create_cover(cover_node, c)

	# Decorations container
	var decorations_node := Node2D.new()
	decorations_node.name = "Decorations"
	add_child(decorations_node)

	# Create decorations
	for d in _level_data.decorations:
		_create_decoration(decorations_node, d)

	# Trees container
	var trees_node := Node2D.new()
	trees_node.name = "Trees"
	add_child(trees_node)

	# Create trees (trunk = collision/cover, crown = visual overlay)
	for t in _level_data.trees:
		_create_tree(trees_node, t)

	# Lights container
	var lights_node := Node2D.new()
	lights_node.name = "Lights"
	add_child(lights_node)

	# Create light sources
	for l in _level_data.lights:
		_create_light(lights_node, l)

	# Navigation region
	_create_navigation_region()

	# Enemies container
	var enemies_node := Node2D.new()
	enemies_node.name = "Enemies"
	add_child(enemies_node)

	# Create enemies
	var enemy_scene: PackedScene = load("res://scenes/objects/Enemy.tscn")
	if enemy_scene:
		for e in _level_data.enemies:
			var enemy: Node2D = enemy_scene.instantiate()
			enemy.position = Vector2(e["x"], e["y"])
			# Set weapon if the enemy supports it
			if enemy.has_method("set_weapon_type"):
				enemy.set_weapon_type(e.get("weapon", "m16"))
			elif "weapon_type" in enemy:
				enemy.weapon_type = e.get("weapon", "m16")
			enemies_node.add_child(enemy)

	# Player
	var player_scene: PackedScene = load("res://scenes/characters/csharp/Player.tscn")
	if player_scene:
		_player = player_scene.instantiate()
		_player.position = _level_data.player_spawn
		add_child(_player)

		# Register player with GameManager
		var game_manager: Node = get_node_or_null("/root/GameManager")
		if game_manager:
			game_manager.player = _player
			game_manager.player_alive = true

	# Saturation overlay
	_saturation_overlay = ColorRect.new()
	_saturation_overlay.name = "SaturationOverlay"
	_saturation_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_saturation_overlay.color = Color(1, 0, 0, 0)
	_saturation_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_saturation_overlay.z_index = 100

	# Pause menu
	var pause_scene: PackedScene = load("res://scenes/ui/PauseMenu.tscn")
	if pause_scene:
		var pause_menu: Node = pause_scene.instantiate()
		add_child(pause_menu)


## Create boundary walls around the map.
func _create_boundary_walls(parent: Node2D) -> void:
	var w: float = _level_data.map_width
	var h: float = _level_data.map_height
	var thickness: float = 32.0

	# Top wall
	_create_wall(parent, Vector2(0, -thickness), Vector2(w, thickness))
	# Bottom wall
	_create_wall(parent, Vector2(0, h), Vector2(w, thickness))
	# Left wall
	_create_wall(parent, Vector2(-thickness, -thickness), Vector2(thickness, h + thickness * 2))
	# Right wall
	_create_wall(parent, Vector2(w, -thickness), Vector2(thickness, h + thickness * 2))


## Create a wall StaticBody2D with collision, visual, and light occluder.
func _create_wall(parent: Node2D, pos: Vector2, size: Vector2) -> void:
	var wall := StaticBody2D.new()
	wall.position = pos + size / 2.0
	wall.collision_layer = 4  # obstacles layer
	wall.collision_mask = 0

	# Collision shape
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	wall.add_child(collision)

	# Visual
	var visual := ColorRect.new()
	visual.position = -size / 2.0
	visual.size = size
	visual.color = _level_data.wall_color
	wall.add_child(visual)

	# Light occluder
	var occluder := LightOccluder2D.new()
	var occluder_polygon := OccluderPolygon2D.new()
	var half := size / 2.0
	occluder_polygon.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])
	occluder.occluder = occluder_polygon
	wall.add_child(occluder)

	parent.add_child(wall)


## Create a cover object with collision.
func _create_cover(parent: Node2D, data: Dictionary) -> void:
	var pos := Vector2(data["x"], data["y"])
	var size := Vector2(data["w"], data["h"])
	var ctype: String = data.get("type", "crate")

	var cover := StaticBody2D.new()
	cover.position = pos + size / 2.0
	cover.collision_layer = 4  # obstacles layer
	cover.collision_mask = 0

	# Collision shape
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	cover.add_child(collision)

	# Visual
	var visual := ColorRect.new()
	visual.position = -size / 2.0
	visual.size = size
	# Use the editor's color for the cover type
	var color_map: Dictionary = {
		"desk": Color(0.55, 0.4, 0.25, 1.0),
		"crate": Color(0.5, 0.45, 0.3, 1.0),
		"barrel": Color(0.4, 0.45, 0.5, 1.0),
		"table": Color(0.45, 0.35, 0.25, 1.0),
	}
	visual.color = color_map.get(ctype, Color(0.5, 0.45, 0.3, 1.0))
	cover.add_child(visual)

	parent.add_child(cover)


## Tree type properties matching the editor definitions.
const TREE_TYPE_PROPS: Dictionary = {
	"oak": {
		"trunk_w": 40.0, "trunk_h": 40.0,
		"crown_radius": 56.0,
		"trunk_color": Color(0.35, 0.25, 0.18, 1.0),
		"crown_color": Color(0.2, 0.35, 0.2, 0.55),
	},
	"pine": {
		"trunk_w": 32.0, "trunk_h": 32.0,
		"crown_radius": 44.0,
		"trunk_color": Color(0.33, 0.23, 0.16, 1.0),
		"crown_color": Color(0.15, 0.32, 0.15, 0.6),
	},
	"birch": {
		"trunk_w": 24.0, "trunk_h": 36.0,
		"crown_radius": 48.0,
		"trunk_color": Color(0.85, 0.82, 0.75, 1.0),
		"crown_color": Color(0.3, 0.45, 0.2, 0.5),
	},
	"dead": {
		"trunk_w": 36.0, "trunk_h": 36.0,
		"crown_radius": 0.0,
		"trunk_color": Color(0.3, 0.25, 0.2, 1.0),
		"crown_color": Color(0.0, 0.0, 0.0, 0.0),
	},
}

## Light type default properties.
const LIGHT_TYPE_PROPS: Dictionary = {
	"street_lamp": {"shadow": true},
	"campfire": {"shadow": true},
	"spotlight": {"shadow": true},
	"ambient": {"shadow": false},
	"neon": {"shadow": false},
}

## Decoration type properties.
const DECORATION_TYPE_PROPS: Dictionary = {
	"rock": {"w": 40.0, "h": 32.0, "color": Color(0.5, 0.48, 0.45, 1.0), "collision": true},
	"stump": {"w": 32.0, "h": 32.0, "color": Color(0.4, 0.3, 0.2, 1.0), "collision": true},
	"log": {"w": 80.0, "h": 24.0, "color": Color(0.45, 0.33, 0.2, 1.0), "collision": true},
	"bush": {"w": 48.0, "h": 40.0, "color": Color(0.25, 0.4, 0.2, 0.7), "collision": false},
	"crate_small": {"w": 32.0, "h": 32.0, "color": Color(0.55, 0.48, 0.3, 1.0), "collision": true},
	"trash": {"w": 24.0, "h": 24.0, "color": Color(0.35, 0.35, 0.3, 0.8), "collision": false},
}


## Create a tree with trunk (StaticBody2D + LightOccluder2D) and crown overlay.
func _create_tree(parent: Node2D, data: Dictionary) -> void:
	var pos := Vector2(data["x"], data["y"])
	var ttype: String = data.get("type", "oak")
	var props: Dictionary = TREE_TYPE_PROPS.get(ttype, TREE_TYPE_PROPS["oak"])
	var tw: float = props["trunk_w"]
	var th: float = props["trunk_h"]

	# Trunk as StaticBody2D (provides cover/collision)
	var trunk := StaticBody2D.new()
	trunk.position = pos
	trunk.collision_layer = 4  # obstacles layer
	trunk.collision_mask = 0

	# Collision shape
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(tw, th)
	collision.shape = shape
	trunk.add_child(collision)

	# Trunk visual
	var trunk_visual := ColorRect.new()
	trunk_visual.position = Vector2(-tw / 2.0, -th / 2.0)
	trunk_visual.size = Vector2(tw, th)
	trunk_visual.color = props["trunk_color"]
	trunk.add_child(trunk_visual)

	# Light occluder for trunk
	var occluder := LightOccluder2D.new()
	var occluder_polygon := OccluderPolygon2D.new()
	var half_w: float = tw / 2.0
	var half_h: float = th / 2.0
	occluder_polygon.polygon = PackedVector2Array([
		Vector2(-half_w, -half_h),
		Vector2(half_w, -half_h),
		Vector2(half_w, half_h),
		Vector2(-half_w, half_h),
	])
	occluder.occluder = occluder_polygon
	trunk.add_child(occluder)

	parent.add_child(trunk)

	# Crown (semi-transparent overlay at z_index 10, hides characters underneath)
	var crown_radius: float = props["crown_radius"]
	if crown_radius > 0.0:
		var crown := Polygon2D.new()
		crown.position = pos
		crown.z_index = 10
		var points: PackedVector2Array = PackedVector2Array()
		var segments: int = 20
		for i in range(segments):
			var angle: float = TAU * i / segments
			points.append(Vector2(cos(angle), sin(angle)) * crown_radius)
		crown.polygon = points
		crown.color = props["crown_color"]
		parent.add_child(crown)


## Create a PointLight2D light source.
func _create_light(parent: Node2D, data: Dictionary) -> void:
	var pos := Vector2(data["x"], data["y"])
	var ltype: String = data.get("type", "street_lamp")
	var lprops: Dictionary = LIGHT_TYPE_PROPS.get(ltype, LIGHT_TYPE_PROPS["street_lamp"])

	# Parse color from data
	var c_data: Dictionary = data.get("color", {})
	var light_color := Color(
		c_data.get("r", 1.0), c_data.get("g", 1.0),
		c_data.get("b", 1.0), c_data.get("a", 1.0)
	)
	var energy: float = data.get("energy", 1.5)
	var radius: float = data.get("radius", 256.0)

	# Create PointLight2D
	var light := PointLight2D.new()
	light.position = pos
	light.color = light_color
	light.energy = energy
	light.shadow_enabled = lprops.get("shadow", true)
	light.shadow_color = Color(0, 0, 0, 0.7)

	# Generate a radial gradient texture for the light
	var gradient := GradientTexture2D.new()
	gradient.width = int(radius * 2)
	gradient.height = int(radius * 2)
	gradient.fill = GradientTexture2D.FILL_RADIAL
	gradient.fill_from = Vector2(0.5, 0.5)
	gradient.fill_to = Vector2(0.5, 0.0)
	var grad := Gradient.new()
	grad.set_color(0, Color.WHITE)
	grad.set_color(1, Color(1, 1, 1, 0))
	gradient.gradient = grad
	light.texture = gradient
	light.texture_scale = 1.0

	parent.add_child(light)

	# Visual base indicator (small colored rectangle for the light fixture)
	var base := ColorRect.new()
	base.position = pos + Vector2(-8, -8)
	base.size = Vector2(16, 16)
	base.color = Color(light_color.r * 0.5, light_color.g * 0.5, light_color.b * 0.5, 0.8)
	parent.add_child(base)


## Create a decoration object (visual, optionally with collision).
func _create_decoration(parent: Node2D, data: Dictionary) -> void:
	var pos := Vector2(data["x"], data["y"])
	var dtype: String = data.get("type", "rock")
	var props: Dictionary = DECORATION_TYPE_PROPS.get(dtype, DECORATION_TYPE_PROPS["rock"])
	var dw: float = props["w"]
	var dh: float = props["h"]

	if props.get("collision", false):
		# Decoration with collision (rock, stump, log, etc.)
		var body := StaticBody2D.new()
		body.position = pos
		body.collision_layer = 4  # obstacles layer
		body.collision_mask = 0

		var collision := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(dw, dh)
		collision.shape = shape
		body.add_child(collision)

		var visual := ColorRect.new()
		visual.position = Vector2(-dw / 2.0, -dh / 2.0)
		visual.size = Vector2(dw, dh)
		visual.color = props["color"]
		body.add_child(visual)

		parent.add_child(body)
	else:
		# Decorative-only (bush, trash — no collision)
		var visual := ColorRect.new()
		visual.position = pos + Vector2(-dw / 2.0, -dh / 2.0)
		visual.size = Vector2(dw, dh)
		visual.color = props["color"]
		parent.add_child(visual)


## Create navigation region covering the entire map.
func _create_navigation_region() -> void:
	var nav_region := NavigationRegion2D.new()
	nav_region.name = "NavigationRegion2D"

	var nav_polygon := NavigationPolygon.new()
	nav_polygon.agent_radius = 24.0

	# Create outline covering the map
	var outline := PackedVector2Array([
		Vector2(0, 0),
		Vector2(_level_data.map_width, 0),
		Vector2(_level_data.map_width, _level_data.map_height),
		Vector2(0, _level_data.map_height),
	])
	nav_polygon.add_outline(outline)

	# Bake the navigation polygon (will carve out obstacles automatically if rebaked)
	nav_polygon.make_polygons_from_outlines()
	nav_region.navigation_polygon = nav_polygon

	add_child(nav_region)


## Setup UI elements (enemy count, ammo, etc.).
func _setup_ui() -> void:
	var ui_layer := CanvasLayer.new()
	ui_layer.name = "UI"
	ui_layer.layer = 5
	add_child(ui_layer)

	# Level name label
	var title_label := Label.new()
	title_label.text = _level_data.level_name
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7, 0.7))
	title_label.anchor_left = 0.5
	title_label.anchor_right = 0.5
	title_label.offset_left = -100
	title_label.offset_right = 100
	title_label.offset_top = 8
	ui_layer.add_child(title_label)

	# Enemy count
	_enemy_count_label = Label.new()
	_enemy_count_label.add_theme_font_size_override("font_size", 14)
	_enemy_count_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3, 1.0))
	_enemy_count_label.anchor_right = 1.0
	_enemy_count_label.offset_right = -16
	_enemy_count_label.offset_top = 8
	_enemy_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui_layer.add_child(_enemy_count_label)

	# Ammo label
	_ammo_label = Label.new()
	_ammo_label.add_theme_font_size_override("font_size", 14)
	_ammo_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7, 1.0))
	_ammo_label.anchor_right = 1.0
	_ammo_label.offset_right = -16
	_ammo_label.offset_top = 30
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui_layer.add_child(_ammo_label)

	# Author info
	if not _level_data.author.is_empty():
		var author_label := Label.new()
		author_label.text = "by %s" % _level_data.author
		author_label.add_theme_font_size_override("font_size", 11)
		author_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65, 0.5))
		author_label.anchor_left = 0.5
		author_label.anchor_right = 0.5
		author_label.offset_left = -50
		author_label.offset_right = 50
		author_label.offset_top = 28
		author_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ui_layer.add_child(author_label)


## Setup enemy tracking.
func _setup_enemies() -> void:
	_enemies.clear()
	var enemies_node: Node = get_node_or_null("Enemies")
	if enemies_node:
		for child in enemies_node.get_children():
			if child.is_in_group("enemies"):
				_enemies.append(child)
				if child.has_signal("died"):
					child.died.connect(_on_enemy_died)

	_initial_enemy_count = _enemies.size()
	_current_enemy_count = _initial_enemy_count
	_update_enemy_count_label()

	# Register with GameManager
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager:
		game_manager.kills = 0
		game_manager.shots_fired = 0
		game_manager.hits_landed = 0


## Called when an enemy dies.
func _on_enemy_died() -> void:
	_current_enemy_count -= 1
	_update_enemy_count_label()

	# Saturation flash effect
	if _saturation_overlay:
		_saturation_overlay.color.a = SATURATION_INTENSITY
		var tween := create_tween()
		tween.tween_property(_saturation_overlay, "color:a", 0.0, SATURATION_DURATION)

	# Check for level clear
	if _current_enemy_count <= 0 and not _level_cleared:
		_level_cleared = true
		_show_level_complete()


## Update the enemy count label.
func _update_enemy_count_label() -> void:
	if _enemy_count_label:
		_enemy_count_label.text = "Enemies: %d / %d" % [_current_enemy_count, _initial_enemy_count]


## Show level complete message.
func _show_level_complete() -> void:
	var ui_layer: Node = get_node_or_null("UI")
	if ui_layer == null:
		return

	var complete_label := Label.new()
	complete_label.text = "LEVEL COMPLETE!"
	complete_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	complete_label.add_theme_font_size_override("font_size", 32)
	complete_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4, 1.0))
	complete_label.anchor_left = 0.5
	complete_label.anchor_right = 0.5
	complete_label.anchor_top = 0.4
	complete_label.offset_left = -200
	complete_label.offset_right = 200
	ui_layer.add_child(complete_label)

	# Hint to return to editor
	var hint_label := Label.new()
	hint_label.text = "Press ESC to return"
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 16)
	hint_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75, 0.8))
	hint_label.anchor_left = 0.5
	hint_label.anchor_right = 0.5
	hint_label.anchor_top = 0.48
	hint_label.offset_left = -150
	hint_label.offset_right = 150
	ui_layer.add_child(hint_label)


func _physics_process(_delta: float) -> void:
	# Update ammo display
	if _player and is_instance_valid(_player) and _ammo_label:
		if _player.has_method("GetCurrentAmmo"):
			var ammo: int = _player.GetCurrentAmmo()
			var max_ammo: int = _player.GetMaxAmmo() if _player.has_method("GetMaxAmmo") else 0
			_ammo_label.text = "Ammo: %d / %d" % [ammo, max_ammo]

	# Check player death
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager and not game_manager.player_alive and not _game_over_shown:
		_game_over_shown = true
		_show_game_over()


## Show game over message.
func _show_game_over() -> void:
	var ui_layer: Node = get_node_or_null("UI")
	if ui_layer == null:
		return

	var death_label := Label.new()
	death_label.text = "YOU DIED"
	death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_label.add_theme_font_size_override("font_size", 32)
	death_label.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2, 1.0))
	death_label.anchor_left = 0.5
	death_label.anchor_right = 0.5
	death_label.anchor_top = 0.4
	death_label.offset_left = -200
	death_label.offset_right = 200
	ui_layer.add_child(death_label)

	var restart_label := Label.new()
	restart_label.text = "Press Q to restart"
	restart_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	restart_label.add_theme_font_size_override("font_size", 16)
	restart_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75, 0.8))
	restart_label.anchor_left = 0.5
	restart_label.anchor_right = 0.5
	restart_label.anchor_top = 0.48
	restart_label.offset_left = -150
	restart_label.offset_right = 150
	ui_layer.add_child(restart_label)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_Q:
			# Quick restart
			get_tree().reload_current_scene()
