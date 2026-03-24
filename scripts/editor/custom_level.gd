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
