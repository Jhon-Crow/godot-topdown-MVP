extends Node2D
## Roguelike level with procedural generation.
##
## Issue #1061: добавить режим рогалика
##
## Features:
## - Procedurally generated room layout each run (scatter-and-reject algorithm)
## - Random enemy placement with weighted weapon type selection
## - Random enemy health and behavior (GUARD/PATROL)
## - L-shaped corridor connections between rooms
## - Full HUD (enemy count, ammo, kills, accuracy, combo) matching other levels
## - Score tracking with rank system (ScoreManager / ProgressManager)
## - Level re-generates with new seed on every restart

## ============================================================
## Level generation constants
## ============================================================

## Map dimensions (3× viewport: 1280×720).
const MAP_WIDTH: float = 3840.0
const MAP_HEIGHT: float = 2160.0

## Wall thickness in pixels.
const WALL_THICKNESS: float = 24.0

## Margin inset from map border for room placement.
const MAP_MARGIN: float = 80.0

## Room size bounds.
const MIN_ROOM_W: float = 180.0
const MAX_ROOM_W: float = 400.0
const MIN_ROOM_H: float = 150.0
const MAX_ROOM_H: float = 320.0

## Corridor width.
const CORRIDOR_W: float = 80.0

## Room generation parameters.
const MIN_ROOMS: int = 6
const MAX_ROOMS: int = 10
const MAX_PLACE_ATTEMPTS: int = 200

## Padding between rooms (prevents walls from touching/overlapping).
const ROOM_PADDING: float = 40.0

## Saturation effect constants (matching other levels).
const SATURATION_DURATION: float = 0.15
const SATURATION_INTENSITY: float = 0.25

## Wall color.
const WALL_COLOR: Color = Color(0.3, 0.3, 0.35, 1.0)

## Room floor color.
const FLOOR_COLOR: Color = Color(0.18, 0.18, 0.22, 1.0)

## Background color (outside all rooms).
const BG_COLOR: Color = Color(0.05, 0.05, 0.07, 1.0)

## ============================================================
## Enemy configuration
## ============================================================

## Enemies per room: [min, max] (skip player spawn room and exit room).
const ENEMIES_PER_ROOM_MIN: int = 1
const ENEMIES_PER_ROOM_MAX: int = 3

## Weighted weapon type spawn table: {type, weight}.
## Type: 0=RIFLE, 1=SHOTGUN, 2=UZI, 3=MACHETE (matches WeaponType enum in enemy.gd).
const WEAPON_WEIGHTS: Array[Dictionary] = [
	{"type": 0, "weight": 35},   # RIFLE
	{"type": 1, "weight": 25},   # SHOTGUN
	{"type": 2, "weight": 20},   # UZI
	{"type": 3, "weight": 20},   # MACHETE
]

## Enemy health range.
const ENEMY_MIN_HEALTH: int = 1
const ENEMY_MAX_HEALTH: int = 3

## Probability of PATROL vs GUARD behavior (0.0–1.0 for patrol).
const PATROL_PROBABILITY: float = 0.4

## ============================================================
## Runtime state
## ============================================================

## Generated rooms as Array[Rect2] — all in world space.
var _rooms: Array[Rect2] = []

## Index of the player spawn room (always rooms[0]).
var _spawn_room_index: int = 0

## Index of the exit room (farthest room from spawn).
var _exit_room_index: int = 0

## Reference to player node.
var _player: Node2D = null

## Reference to HUD nodes.
var _enemy_count_label: Label = null
var _ammo_label: Label = null
var _kills_label: Label = null
var _accuracy_label: Label = null
var _magazines_label: Label = null
var _combo_label: Label = null
var _saturation_overlay: ColorRect = null

## Enemy tracking.
var _enemies: Array = []
var _initial_enemy_count: int = 0
var _current_enemy_count: int = 0

## Game state flags.
var _level_cleared: bool = false
var _game_over_shown: bool = false
var _score_shown: bool = false
var _level_completed: bool = false

## Exit zone reference.
var _exit_zone: Area2D = null

## Replay manager cache.
var _replay_manager: Node = null


## ============================================================
## _ready: entry point
## ============================================================

func _ready() -> void:
	randomize()
	var seed_used: int = randi()
	seed(seed_used)
	print("[RoguelikeLevel] Generating level with seed: %d" % seed_used)

	_generate_level()
	_setup_navigation()
	_setup_player_tracking()
	_setup_enemy_tracking()
	_setup_debug_ui()
	_setup_saturation_overlay()
	_update_enemy_count_label()
	_initialize_score_manager()
	_setup_exit_zone()
	_start_replay_recording()

	if GameManager:
		GameManager.enemy_killed.connect(_on_game_manager_enemy_killed)
		GameManager.stats_updated.connect(_update_debug_ui)

	print("[RoguelikeLevel] Level ready — %d rooms, %d enemies" % [_rooms.size(), _initial_enemy_count])


func _process(_delta: float) -> void:
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager and score_manager.has_method("update_enemy_positions"):
		score_manager.update_enemy_positions(_enemies)


## ============================================================
## Level generation
## ============================================================

## Main generation entry point.
func _generate_level() -> void:
	_rooms.clear()

	# Build the scene tree containers
	var environment := Node2D.new()
	environment.name = "Environment"
	add_child(environment)

	# Full background (dark, covers the whole map)
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.position = Vector2.ZERO
	bg.size = Vector2(MAP_WIDTH + WALL_THICKNESS * 2, MAP_HEIGHT + WALL_THICKNESS * 2)
	bg.color = BG_COLOR
	environment.add_child(bg)

	# Node containers
	var floors_node := Node2D.new()
	floors_node.name = "Floors"
	environment.add_child(floors_node)

	var walls_node := Node2D.new()
	walls_node.name = "Walls"
	environment.add_child(walls_node)

	var enemies_node := Node2D.new()
	enemies_node.name = "Enemies"
	environment.add_child(enemies_node)

	# 1. Generate rooms
	_place_rooms()
	if _rooms.size() < 2:
		push_error("[RoguelikeLevel] Failed to generate enough rooms!")
		return

	# 2. Determine spawn and exit rooms
	_spawn_room_index = 0
	_exit_room_index = _find_farthest_room(_spawn_room_index)

	print("[RoguelikeLevel] Spawn room: %d, Exit room: %d" % [_spawn_room_index, _exit_room_index])

	# 3. Connect rooms with corridors
	var corridors: Array[Rect2] = _connect_rooms()

	# 4. Render floors and walls
	for room in _rooms:
		_create_floor_rect(floors_node, room)
	for corridor in corridors:
		_create_floor_rect(floors_node, corridor)

	# Build walls around the entire walkable area (outer perimeter of all rooms + corridors)
	_build_perimeter_walls(walls_node)

	# 5. Add cover objects inside rooms (optional, improves gameplay)
	_add_cover_in_rooms(walls_node)

	# 6. Spawn enemies
	_spawn_enemies(enemies_node)

	# 7. Spawn player in the spawn room
	_spawn_player()

	# 8. Navigation region (baked after all geometry is in place)
	_create_navigation_region()


## Place rooms using scatter-and-reject algorithm.
func _place_rooms() -> void:
	var attempts: int = 0
	var target_rooms: int = randi_range(MIN_ROOMS, MAX_ROOMS)

	while _rooms.size() < target_rooms and attempts < MAX_PLACE_ATTEMPTS:
		attempts += 1

		var w: float = randf_range(MIN_ROOM_W, MAX_ROOM_W)
		var h: float = randf_range(MIN_ROOM_H, MAX_ROOM_H)
		var x: float = randf_range(MAP_MARGIN, MAP_WIDTH - MAP_MARGIN - w)
		var y: float = randf_range(MAP_MARGIN, MAP_HEIGHT - MAP_MARGIN - h)

		var candidate := Rect2(x, y, w, h)

		# Check against all existing rooms (with padding)
		var overlaps: bool = false
		for existing in _rooms:
			var padded := existing.grow(ROOM_PADDING)
			if padded.intersects(candidate):
				overlaps = true
				break

		if not overlaps:
			_rooms.append(candidate)

	print("[RoguelikeLevel] Placed %d rooms in %d attempts" % [_rooms.size(), attempts])


## Find the room index farthest from the given origin room (by center distance).
func _find_farthest_room(origin_index: int) -> int:
	var origin_center: Vector2 = _rooms[origin_index].get_center()
	var farthest_index: int = 0
	var farthest_dist: float = 0.0

	for i in range(_rooms.size()):
		if i == origin_index:
			continue
		var d: float = origin_center.distance_to(_rooms[i].get_center())
		if d > farthest_dist:
			farthest_dist = d
			farthest_index = i

	return farthest_index


## Connect rooms with L-shaped corridors (each room to the nearest unconnected room).
## Returns array of corridor Rect2 (may include both H and V segments per connection).
func _connect_rooms() -> Array[Rect2]:
	var corridors: Array[Rect2] = []

	# Simple sequential connection: each room connects to the next closest unconnected room.
	# Build a minimum-spanning-like chain using nearest-neighbor.
	var connected: Array[int] = [0]
	var unconnected: Array[int] = []
	for i in range(1, _rooms.size()):
		unconnected.append(i)

	while unconnected.size() > 0:
		var best_connected_idx: int = -1
		var best_unconnected_idx: int = -1
		var best_dist: float = INF

		for ci in connected:
			for ui in unconnected:
				var d: float = _rooms[ci].get_center().distance_to(_rooms[ui].get_center())
				if d < best_dist:
					best_dist = d
					best_connected_idx = ci
					best_unconnected_idx = ui

		if best_unconnected_idx == -1:
			break

		# Build L-shaped corridor between rooms[best_connected_idx] and rooms[best_unconnected_idx]
		var new_corridors: Array[Rect2] = _make_l_corridor(
			_rooms[best_connected_idx].get_center(),
			_rooms[best_unconnected_idx].get_center()
		)
		corridors.append_array(new_corridors)

		connected.append(best_unconnected_idx)
		unconnected.erase(best_unconnected_idx)

	return corridors


## Build an L-shaped corridor (two Rect2 segments) between two center points.
func _make_l_corridor(a: Vector2, b: Vector2) -> Array[Rect2]:
	var segments: Array[Rect2] = []
	var half_w: float = CORRIDOR_W / 2.0

	# Randomly choose H-then-V or V-then-H
	if randf() < 0.5:
		# Horizontal segment first
		var h_rect := Rect2(
			min(a.x, b.x) - half_w,
			a.y - half_w,
			abs(b.x - a.x) + CORRIDOR_W,
			CORRIDOR_W
		)
		segments.append(h_rect)
		# Vertical segment
		var v_rect := Rect2(
			b.x - half_w,
			min(a.y, b.y) - half_w,
			CORRIDOR_W,
			abs(b.y - a.y) + CORRIDOR_W
		)
		segments.append(v_rect)
	else:
		# Vertical segment first
		var v_rect := Rect2(
			a.x - half_w,
			min(a.y, b.y) - half_w,
			CORRIDOR_W,
			abs(b.y - a.y) + CORRIDOR_W
		)
		segments.append(v_rect)
		# Horizontal segment
		var h_rect := Rect2(
			min(a.x, b.x) - half_w,
			b.y - half_w,
			abs(b.x - a.x) + CORRIDOR_W,
			CORRIDOR_W
		)
		segments.append(h_rect)

	return segments


## Create a visible floor ColorRect (no collision — just visual).
func _create_floor_rect(parent: Node, rect: Rect2) -> void:
	var floor_rect := ColorRect.new()
	floor_rect.position = rect.position
	floor_rect.size = rect.size
	floor_rect.color = FLOOR_COLOR
	parent.add_child(floor_rect)


## Build thin walls around each room (4 sides, only where there's no corridor overlap).
## We use a simple approach: add a StaticBody2D wall segment for each side of each room.
func _build_perimeter_walls(parent: Node) -> void:
	var t: float = WALL_THICKNESS

	for room in _rooms:
		# Top wall
		_create_wall_body(parent, Rect2(room.position.x - t, room.position.y - t, room.size.x + t * 2, t))
		# Bottom wall
		_create_wall_body(parent, Rect2(room.position.x - t, room.end.y, room.size.x + t * 2, t))
		# Left wall
		_create_wall_body(parent, Rect2(room.position.x - t, room.position.y, t, room.size.y))
		# Right wall
		_create_wall_body(parent, Rect2(room.end.x, room.position.y, t, room.size.y))


## Create a single wall StaticBody2D with collision and visual.
func _create_wall_body(parent: Node, rect: Rect2) -> void:
	var wall := StaticBody2D.new()
	wall.collision_layer = 4   # walls layer (matching all other levels)
	wall.collision_mask = 0
	wall.position = rect.get_center()

	var shape_node := CollisionShape2D.new()
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = rect.size
	shape_node.shape = rect_shape
	wall.add_child(shape_node)

	var visual := ColorRect.new()
	visual.color = WALL_COLOR
	visual.size = rect.size
	visual.position = -rect.size / 2.0
	wall.add_child(visual)

	parent.add_child(wall)


## Add simple cover objects (small StaticBody2D crates/pillars) in rooms.
func _add_cover_in_rooms(parent: Node) -> void:
	for i in range(_rooms.size()):
		if i == _spawn_room_index or i == _exit_room_index:
			continue
		var room: Rect2 = _rooms[i]
		# Add 1–3 cover objects per non-spawn/exit room
		var num_covers: int = randi_range(1, 3)
		var margin: float = 60.0
		for _j in range(num_covers):
			var cover_w: float = randf_range(30.0, 70.0)
			var cover_h: float = randf_range(30.0, 70.0)
			var cx: float = randf_range(room.position.x + margin, room.end.x - margin - cover_w)
			var cy: float = randf_range(room.position.y + margin, room.end.y - margin - cover_h)
			_create_wall_body(parent, Rect2(cx, cy, cover_w, cover_h))


## Create NavigationRegion2D for enemy pathfinding.
## The actual baking is deferred to _setup_navigation() which runs after all nodes are ready.
func _create_navigation_region() -> void:
	var nav_region := NavigationRegion2D.new()
	nav_region.name = "NavigationRegion2D"

	var nav_poly := NavigationPolygon.new()
	nav_poly.parsed_geometry_type = NavigationPolygon.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_poly.parsed_collision_mask = 4  # walls layer
	nav_poly.source_geometry_mode = NavigationPolygon.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nav_poly.agent_radius = 24.0

	nav_region.navigation_polygon = nav_poly
	add_child(nav_region)


## ============================================================
## Enemy spawning
## ============================================================

## Spawn enemies in all rooms except spawn and exit rooms.
func _spawn_enemies(enemies_node: Node) -> void:
	var enemy_scene: PackedScene = load("res://scenes/objects/Enemy.tscn")
	if enemy_scene == null:
		push_error("[RoguelikeLevel] Failed to load Enemy.tscn!")
		return

	var margin: float = 50.0

	for i in range(_rooms.size()):
		if i == _spawn_room_index or i == _exit_room_index:
			continue

		var room: Rect2 = _rooms[i]
		# Don't place enemies in rooms too small for a margin
		if room.size.x < margin * 2.5 or room.size.y < margin * 2.5:
			continue

		var num_enemies: int = randi_range(ENEMIES_PER_ROOM_MIN, ENEMIES_PER_ROOM_MAX)
		for _j in range(num_enemies):
			var enemy: Node2D = enemy_scene.instantiate()

			# Random position inside the room (not on walls)
			var ex: float = randf_range(room.position.x + margin, room.end.x - margin)
			var ey: float = randf_range(room.position.y + margin, room.end.y - margin)
			enemy.position = Vector2(ex, ey)

			# Random weapon type (weighted)
			enemy.weapon_type = _pick_weapon_type()

			# Random health
			enemy.min_health = ENEMY_MIN_HEALTH
			enemy.max_health = randi_range(ENEMY_MIN_HEALTH + 1, ENEMY_MAX_HEALTH + 1)

			# Random behavior
			if randf() < PATROL_PROBABILITY:
				enemy.behavior_mode = 1  # PATROL
				# Set patrol offsets within the room
				var patrol_range: float = min(room.size.x, room.size.y) * 0.3
				enemy.patrol_offsets = [
					Vector2(randf_range(-patrol_range, patrol_range), 0.0),
					Vector2(randf_range(-patrol_range, patrol_range), randf_range(-patrol_range, patrol_range))
				]
			else:
				enemy.behavior_mode = 0  # GUARD

			enemies_node.add_child(enemy)


## Pick a random weapon type using weighted probabilities.
func _pick_weapon_type() -> int:
	var total_weight: int = 0
	for entry in WEAPON_WEIGHTS:
		total_weight += entry.weight

	var roll: int = randi_range(0, total_weight - 1)
	var cumulative: int = 0
	for entry in WEAPON_WEIGHTS:
		cumulative += entry.weight
		if roll < cumulative:
			return entry.type

	return 0  # Fallback: RIFLE


## ============================================================
## Player spawning
## ============================================================

## Spawn the player in the spawn room center, or use existing scene player.
func _spawn_player() -> void:
	# Check if a player scene is already instanced (added via tscn)
	var existing_player: Node = get_node_or_null("Entities/Player")
	if existing_player:
		# Move the pre-placed player to the spawn room center
		var spawn_center: Vector2 = _rooms[_spawn_room_index].get_center()
		existing_player.position = spawn_center
		return

	# No pre-placed player — instantiate one
	var player_scene: PackedScene = load("res://scenes/characters/csharp/Player.tscn")
	if player_scene == null:
		player_scene = load("res://scenes/characters/Player.tscn")
	if player_scene == null:
		push_error("[RoguelikeLevel] Failed to load Player scene!")
		return

	var entities_node := Node2D.new()
	entities_node.name = "Entities"
	add_child(entities_node)

	var player: Node2D = player_scene.instantiate()
	player.name = "Player"
	player.position = _rooms[_spawn_room_index].get_center()
	entities_node.add_child(player)


## ============================================================
## Standard level setup (mirrors test_tier.gd / labyrinth_level.gd)
## ============================================================

func _setup_navigation() -> void:
	var nav_region: NavigationRegion2D = get_node_or_null("NavigationRegion2D")
	if nav_region == null:
		push_warning("[RoguelikeLevel] NavigationRegion2D not found")
		return

	var nav_poly: NavigationPolygon = nav_region.navigation_polygon
	if nav_poly == null:
		push_warning("[RoguelikeLevel] NavigationPolygon not found")
		return

	print("[RoguelikeLevel] Baking navigation mesh...")
	nav_poly.clear()

	# Outline covering the full walkable area
	var outline := PackedVector2Array([
		Vector2(0, 0),
		Vector2(MAP_WIDTH, 0),
		Vector2(MAP_WIDTH, MAP_HEIGHT),
		Vector2(0, MAP_HEIGHT)
	])
	nav_poly.add_outline(outline)

	var source_geometry: NavigationMeshSourceGeometryData2D = NavigationMeshSourceGeometryData2D.new()
	NavigationServer2D.parse_source_geometry_data(nav_poly, source_geometry, self)
	NavigationServer2D.bake_from_source_geometry_data(nav_poly, source_geometry)

	print("[RoguelikeLevel] Navigation mesh baked")


func _setup_player_tracking() -> void:
	_player = get_node_or_null("Entities/Player")
	if _player == null:
		# Try common alternative paths
		_player = get_node_or_null("Player")
	if _player == null:
		return

	_setup_selected_weapon()

	if GameManager:
		GameManager.set_player(_player)

	# Find HUD ammo label
	_ammo_label = get_node_or_null("CanvasLayer/UI/AmmoLabel")

	# Connect player death
	if _player.has_signal("died"):
		_player.died.connect(_on_player_died)
	elif _player.has_signal("Died"):
		_player.Died.connect(_on_player_died)

	# Connect weapon signals (C# Player)
	var weapon: Node = _find_player_weapon()
	if weapon != null:
		if weapon.has_signal("AmmoChanged"):
			weapon.AmmoChanged.connect(_on_weapon_ammo_changed)
		if weapon.has_signal("MagazinesChanged"):
			weapon.MagazinesChanged.connect(_on_magazines_changed)
		if weapon.has_signal("Fired"):
			weapon.Fired.connect(_on_shot_fired)
		if weapon.has_signal("ShellCountChanged"):
			weapon.ShellCountChanged.connect(_on_shell_count_changed)
		if weapon.get("CurrentAmmo") != null and weapon.get("ReserveAmmo") != null:
			_update_ammo_label_magazine(weapon.CurrentAmmo, weapon.ReserveAmmo)
		if weapon.has_method("GetMagazineAmmoCounts"):
			var mag_counts: Array = weapon.GetMagazineAmmoCounts()
			_update_magazines_label(mag_counts)
	else:
		# GDScript Player
		if _player.has_signal("ammo_changed"):
			_player.ammo_changed.connect(_on_player_ammo_changed)

	# Reload / ammo-depleted signals
	if _player.has_signal("ReloadStarted"):
		_player.ReloadStarted.connect(_on_player_reload_started)
	elif _player.has_signal("reload_started"):
		_player.reload_started.connect(_on_player_reload_started)

	if _player.has_signal("ReloadCompleted"):
		_player.ReloadCompleted.connect(_on_player_reload_completed)
	elif _player.has_signal("reload_completed"):
		_player.reload_completed.connect(_on_player_reload_completed)

	if _player.has_signal("AmmoDepleted"):
		_player.AmmoDepleted.connect(_on_player_ammo_depleted)
	elif _player.has_signal("ammo_depleted"):
		_player.ammo_depleted.connect(_on_player_ammo_depleted)


func _setup_enemy_tracking() -> void:
	var enemies_node := get_node_or_null("Environment/Enemies")
	if enemies_node == null:
		return

	_enemies.clear()
	for child in enemies_node.get_children():
		if child.has_signal("died"):
			_enemies.append(child)
			child.died.connect(_on_enemy_died)
			if child.has_signal("died_with_info"):
				child.died_with_info.connect(_on_enemy_died_with_info)
		if child.has_signal("hit"):
			child.hit.connect(_on_enemy_hit)

	_initial_enemy_count = _enemies.size()
	_current_enemy_count = _initial_enemy_count
	print("[RoguelikeLevel] Tracking %d enemies" % _initial_enemy_count)


func _initialize_score_manager() -> void:
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager == null:
		return
	score_manager.start_level(_initial_enemy_count)
	if _player:
		if score_manager.has_method("set_player"):
			score_manager.set_player(_player)
	if not score_manager.combo_changed.is_connected(_on_combo_changed):
		score_manager.combo_changed.connect(_on_combo_changed)


func _setup_exit_zone() -> void:
	var exit_zone_scene: PackedScene = load("res://scenes/objects/ExitZone.tscn")
	if exit_zone_scene == null:
		push_warning("[RoguelikeLevel] ExitZone scene not found")
		return

	_exit_zone = exit_zone_scene.instantiate()

	# Place exit zone in the exit room center
	var exit_room: Rect2 = _rooms[_exit_room_index]
	_exit_zone.position = exit_room.get_center()
	_exit_zone.zone_width = 80.0
	_exit_zone.zone_height = 80.0

	_exit_zone.player_reached_exit.connect(_on_player_reached_exit)

	var environment := get_node_or_null("Environment")
	if environment:
		environment.add_child(_exit_zone)
	else:
		add_child(_exit_zone)

	print("[RoguelikeLevel] Exit zone placed at room %d: %s" % [_exit_room_index, str(_exit_zone.position)])


func _setup_debug_ui() -> void:
	# Build CanvasLayer + UI programmatically (same pattern as test_tier.gd)
	var canvas_layer := CanvasLayer.new()
	canvas_layer.name = "CanvasLayer"
	add_child(canvas_layer)

	var ui := Control.new()
	ui.name = "UI"
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas_layer.add_child(ui)

	# PauseMenu
	var pause_menu_scene: PackedScene = load("res://scenes/ui/PauseMenu.tscn")
	if pause_menu_scene:
		var pause_menu: Node = pause_menu_scene.instantiate()
		canvas_layer.add_child(pause_menu)

	# Enemy count label
	_enemy_count_label = Label.new()
	_enemy_count_label.name = "EnemyCountLabel"
	_enemy_count_label.text = "Enemies: 0"
	_enemy_count_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_enemy_count_label.offset_left = -200
	_enemy_count_label.offset_right = -10
	_enemy_count_label.offset_top = 10
	_enemy_count_label.offset_bottom = 40
	_enemy_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui.add_child(_enemy_count_label)

	# Ammo label
	_ammo_label = Label.new()
	_ammo_label.name = "AmmoLabel"
	_ammo_label.text = "AMMO: -"
	_ammo_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_ammo_label.offset_left = 10
	_ammo_label.offset_top = 10
	_ammo_label.offset_right = 300
	_ammo_label.offset_bottom = 40
	ui.add_child(_ammo_label)

	# Kills label
	_kills_label = Label.new()
	_kills_label.name = "KillsLabel"
	_kills_label.text = "Kills: 0"
	_kills_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_kills_label.offset_left = 10
	_kills_label.offset_top = 45
	_kills_label.offset_right = 200
	_kills_label.offset_bottom = 75
	ui.add_child(_kills_label)

	# Accuracy label
	_accuracy_label = Label.new()
	_accuracy_label.name = "AccuracyLabel"
	_accuracy_label.text = "Accuracy: 0%"
	_accuracy_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_accuracy_label.offset_left = 10
	_accuracy_label.offset_top = 75
	_accuracy_label.offset_right = 200
	_accuracy_label.offset_bottom = 105
	ui.add_child(_accuracy_label)

	# Magazines label
	_magazines_label = Label.new()
	_magazines_label.name = "MagazinesLabel"
	_magazines_label.text = "MAGS: -"
	_magazines_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_magazines_label.offset_left = 10
	_magazines_label.offset_top = 105
	_magazines_label.offset_right = 400
	_magazines_label.offset_bottom = 135
	ui.add_child(_magazines_label)

	# Roguelike mode indicator
	var mode_label := Label.new()
	mode_label.name = "ModeLabel"
	mode_label.text = "ROGUELIKE"
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	mode_label.offset_top = 10
	mode_label.offset_bottom = 36
	mode_label.add_theme_font_size_override("font_size", 14)
	mode_label.add_theme_color_override("font_color", Color(0.6, 0.4, 1.0, 0.8))
	ui.add_child(mode_label)


func _setup_saturation_overlay() -> void:
	var canvas_layer := get_node_or_null("CanvasLayer")
	if canvas_layer == null:
		return
	_saturation_overlay = ColorRect.new()
	_saturation_overlay.name = "SaturationOverlay"
	_saturation_overlay.color = Color(1.0, 0.9, 0.3, 0.0)
	_saturation_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_saturation_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas_layer.add_child(_saturation_overlay)


func _setup_selected_weapon() -> void:
	if _player == null:
		return

	var selected_weapon_id: String = "makarov_pm"
	if GameManager:
		selected_weapon_id = GameManager.get_selected_weapon()

	print("[RoguelikeLevel] Setting up weapon: %s" % selected_weapon_id)

	# Check if C# Player already equipped the correct weapon
	var weapon_names: Dictionary = {
		"shotgun": "Shotgun", "mini_uzi": "MiniUzi", "silenced_pistol": "SilencedPistol",
		"sniper": "SniperRifle", "m16": "AssaultRifle", "ak_gl": "AKGL",
		"revolver": "Revolver", "makarov_pm": "MakarovPM"
	}
	if selected_weapon_id in weapon_names:
		var expected_name: String = weapon_names[selected_weapon_id]
		var existing: Node = _player.get_node_or_null(expected_name)
		if existing != null and _player.get("CurrentWeapon") == existing:
			print("[RoguelikeLevel] %s already equipped by C# Player - skipping" % expected_name)
			return

	# Swap weapon if needed (mirrors test_tier.gd logic)
	if selected_weapon_id != "makarov_pm":
		var weapon_scene_paths: Dictionary = {
			"shotgun": "res://scenes/weapons/csharp/Shotgun.tscn",
			"mini_uzi": "res://scenes/weapons/csharp/MiniUzi.tscn",
			"silenced_pistol": "res://scenes/weapons/csharp/SilencedPistol.tscn",
			"sniper": "res://scenes/weapons/csharp/SniperRifle.tscn",
			"m16": "res://scenes/weapons/csharp/AssaultRifle.tscn",
			"ak_gl": "res://scenes/weapons/csharp/AKGL.tscn",
			"revolver": "res://scenes/weapons/csharp/Revolver.tscn",
		}
		if selected_weapon_id in weapon_scene_paths:
			var makarov: Node = _player.get_node_or_null("MakarovPM")
			if makarov:
				makarov.queue_free()
			var weapon_scene: PackedScene = load(weapon_scene_paths[selected_weapon_id])
			if weapon_scene:
				var new_weapon: Node = weapon_scene.instantiate()
				new_weapon.name = weapon_names.get(selected_weapon_id, selected_weapon_id)
				_player.add_child(new_weapon)
				if _player.has_method("EquipWeapon"):
					_player.EquipWeapon(new_weapon)
				elif _player.get("CurrentWeapon") != null:
					_player.CurrentWeapon = new_weapon


## Find the currently active weapon on the player node.
func _find_player_weapon() -> Node:
	if _player == null:
		return null
	for weapon_name in ["Shotgun", "MiniUzi", "SilencedPistol", "SniperRifle", "AssaultRifle", "AKGL", "Revolver", "MakarovPM"]:
		var w: Node = _player.get_node_or_null(weapon_name)
		if w != null:
			return w
	return null


func _start_replay_recording() -> void:
	_replay_manager = get_node_or_null("/root/ReplayManager")
	if _replay_manager and _replay_manager.has_method("StartRecording"):
		_replay_manager.StartRecording(_enemies)


## ============================================================
## Event handlers
## ============================================================

func _on_enemy_died() -> void:
	_current_enemy_count -= 1
	_update_enemy_count_label()

	if GameManager:
		GameManager.register_kill()

	if _current_enemy_count <= 0:
		print("[RoguelikeLevel] All enemies eliminated!")
		if _replay_manager and _replay_manager.has_method("StopRecording"):
			_replay_manager.StopRecording()
		_level_cleared = true
		call_deferred("_activate_exit_zone")


func _on_enemy_died_with_info(is_ricochet_kill: bool, is_penetration_kill: bool) -> void:
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager and score_manager.has_method("register_kill"):
		score_manager.register_kill(is_ricochet_kill, is_penetration_kill)


func _on_enemy_hit() -> void:
	if GameManager:
		GameManager.register_hit()


func _on_shot_fired() -> void:
	if GameManager:
		GameManager.register_shot()


func _on_player_ammo_changed(current: int, maximum: int) -> void:
	_update_ammo_label(current, maximum)
	if GameManager:
		GameManager.register_shot()


func _on_weapon_ammo_changed(current_ammo: int, reserve_ammo: int) -> void:
	_update_ammo_label_magazine(current_ammo, reserve_ammo)
	if current_ammo <= 0 and reserve_ammo <= 0:
		if _current_enemy_count > 0 and not _game_over_shown:
			_show_game_over_message()


func _on_magazines_changed(magazine_ammo_counts: Array) -> void:
	_update_magazines_label(magazine_ammo_counts)


func _on_shell_count_changed(shell_count: int, _capacity: int) -> void:
	var reserve_ammo: int = 0
	if _player:
		var weapon: Node = _player.get_node_or_null("Shotgun")
		if weapon != null and weapon.get("ReserveAmmo") != null:
			reserve_ammo = weapon.ReserveAmmo
	_update_ammo_label_magazine(shell_count, reserve_ammo)


func _on_player_ammo_depleted() -> void:
	_broadcast_player_ammo_empty(true)
	if _player:
		var sound_propagation: Node = get_node_or_null("/root/SoundPropagation")
		if sound_propagation and sound_propagation.has_method("emit_player_empty_click"):
			sound_propagation.emit_player_empty_click(_player.global_position, _player)
	if _player and _player.has_method("get_current_ammo"):
		if _player.get_current_ammo() <= 0 and _current_enemy_count > 0 and not _game_over_shown:
			_show_game_over_message()


func _on_player_reload_started() -> void:
	_broadcast_player_reloading(true)
	if _player:
		var sound_propagation: Node = get_node_or_null("/root/SoundPropagation")
		if sound_propagation and sound_propagation.has_method("emit_player_reload"):
			sound_propagation.emit_player_reload(_player.global_position, _player)


func _on_player_reload_completed() -> void:
	_broadcast_player_reloading(false)
	_broadcast_player_ammo_empty(false)


func _on_player_died() -> void:
	_show_death_message()
	if GameManager:
		await get_tree().create_timer(0.5).timeout
		GameManager.on_player_death()


func _on_game_manager_enemy_killed() -> void:
	_show_saturation_effect()


func _on_player_reached_exit() -> void:
	if not _level_cleared:
		return
	print("[RoguelikeLevel] Player reached exit — showing score!")
	call_deferred("_complete_level_with_score")


func _on_combo_changed(combo: int, points: int) -> void:
	var ui := get_node_or_null("CanvasLayer/UI")
	if ui == null:
		return

	if _combo_label == null:
		_combo_label = Label.new()
		_combo_label.name = "ComboLabel"
		_combo_label.text = ""
		_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_combo_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_combo_label.offset_left = -200
		_combo_label.offset_right = -10
		_combo_label.offset_top = 80
		_combo_label.offset_bottom = 120
		_combo_label.add_theme_font_size_override("font_size", 28)
		_combo_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2, 1.0))
		_combo_label.visible = false
		ui.add_child(_combo_label)

	if combo > 0:
		_combo_label.text = "x%d COMBO (+%d)" % [combo, points]
		_combo_label.visible = true
		_combo_label.modulate = Color.WHITE
		var tween := create_tween()
		tween.tween_property(_combo_label, "modulate", Color(1.0, 0.8, 0.2, 1.0), 0.1)
	else:
		_combo_label.visible = false


## ============================================================
## Level completion and score
## ============================================================

func _activate_exit_zone() -> void:
	if _exit_zone and _exit_zone.has_method("activate"):
		_exit_zone.activate()
		print("[RoguelikeLevel] Exit zone activated — go to exit to see score!")
	else:
		push_warning("[RoguelikeLevel] Exit zone not available — showing score immediately")
		_complete_level_with_score()


func _complete_level_with_score() -> void:
	if _level_completed:
		return
	_level_completed = true

	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager and score_manager.has_method("complete_level"):
		var score_data: Dictionary = score_manager.complete_level()
		_show_score_screen(score_data)
	else:
		_show_victory_message()


func _show_score_screen(score_data: Dictionary) -> void:
	var ui := get_node_or_null("CanvasLayer/UI")
	if ui == null:
		_show_victory_message()
		return

	var animated_script = load("res://scripts/ui/animated_score_screen.gd")
	if animated_script:
		var score_screen = animated_script.new()
		add_child(score_screen)
		score_screen.animation_completed.connect(_on_score_animation_completed)
		score_screen.show_animated_score(ui, score_data)
	else:
		_show_fallback_score_screen(ui, score_data)


func _on_score_animation_completed(container: VBoxContainer) -> void:
	_add_score_screen_buttons(container)


func _add_score_screen_buttons(container: VBoxContainer) -> void:
	var restart_button := Button.new()
	restart_button.text = "↻ Restart (Q)"
	restart_button.custom_minimum_size = Vector2(200, 40)
	restart_button.add_theme_font_size_override("font_size", 18)
	restart_button.pressed.connect(_on_restart_pressed)
	container.add_child(restart_button)

	var level_select_button := Button.new()
	level_select_button.text = "☰ Level Select"
	level_select_button.custom_minimum_size = Vector2(200, 40)
	level_select_button.add_theme_font_size_override("font_size", 18)
	level_select_button.pressed.connect(_on_level_select_pressed)
	container.add_child(level_select_button)


func _show_fallback_score_screen(ui: Control, score_data: Dictionary) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bg)

	var container := VBoxContainer.new()
	container.set_anchors_preset(Control.PRESET_CENTER)
	container.offset_left = -250
	container.offset_right = 250
	container.offset_top = -200
	container.offset_bottom = 200
	container.add_theme_constant_override("separation", 10)
	ui.add_child(container)

	var title := Label.new()
	title.text = "ROGUELIKE CLEARED!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(0.6, 0.4, 1.0, 1.0))
	container.add_child(title)

	var total_label := Label.new()
	total_label.text = "TOTAL: %d | RANK: %s" % [score_data.get("total_score", 0), score_data.get("rank", "?")]
	total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	total_label.add_theme_font_size_override("font_size", 28)
	total_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 1.0))
	container.add_child(total_label)

	_add_score_screen_buttons(container)


func _show_victory_message() -> void:
	_score_shown = true
	var ui := get_node_or_null("CanvasLayer/UI")
	if ui == null:
		return

	var victory_label := Label.new()
	victory_label.text = "ROGUELIKE CLEARED!"
	victory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	victory_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	victory_label.add_theme_font_size_override("font_size", 48)
	victory_label.add_theme_color_override("font_color", Color(0.6, 0.4, 1.0, 1.0))
	victory_label.set_anchors_preset(Control.PRESET_CENTER)
	victory_label.offset_left = -250
	victory_label.offset_right = 250
	victory_label.offset_top = -80
	victory_label.offset_bottom = -30
	ui.add_child(victory_label)


## ============================================================
## HUD helpers
## ============================================================

func _update_enemy_count_label() -> void:
	if _enemy_count_label:
		_enemy_count_label.text = "Enemies: %d" % _current_enemy_count


func _update_ammo_label(current: int, maximum: int) -> void:
	if _ammo_label == null:
		return
	_ammo_label.text = "AMMO: %d/%d" % [current, maximum]
	if current <= 5:
		_ammo_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1.0))
	elif current <= 10:
		_ammo_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.2, 1.0))
	else:
		_ammo_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))


func _update_ammo_label_magazine(current_mag: int, reserve: int) -> void:
	if _ammo_label == null:
		return
	_ammo_label.text = "AMMO: %d/%d" % [current_mag, reserve]
	if current_mag <= 5:
		_ammo_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1.0))
	elif current_mag <= 10:
		_ammo_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.2, 1.0))
	else:
		_ammo_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))


func _update_magazines_label(magazine_ammo_counts: Array) -> void:
	if _magazines_label == null:
		return
	var weapon: Node = _find_player_weapon()
	if weapon != null and weapon.get("UsesTubeMagazine") == true:
		_magazines_label.visible = false
		return
	_magazines_label.visible = true
	if magazine_ammo_counts.is_empty():
		_magazines_label.text = "MAGS: -"
		return
	var parts: Array = []
	for i in range(magazine_ammo_counts.size()):
		if i == 0:
			parts.append("[%d]" % magazine_ammo_counts[i])
		else:
			parts.append("%d" % magazine_ammo_counts[i])
	_magazines_label.text = "MAGS: " + " | ".join(parts)


func _update_debug_ui() -> void:
	if GameManager == null:
		return
	if _kills_label:
		_kills_label.text = "Kills: %d" % GameManager.kills
	if _accuracy_label:
		_accuracy_label.text = "Accuracy: %.1f%%" % GameManager.get_accuracy()


func _show_saturation_effect() -> void:
	if _saturation_overlay == null:
		return
	var tween := create_tween()
	tween.tween_property(_saturation_overlay, "color:a", SATURATION_INTENSITY, SATURATION_DURATION * 0.3)
	tween.tween_property(_saturation_overlay, "color:a", 0.0, SATURATION_DURATION * 0.7)


func _show_death_message() -> void:
	if _game_over_shown:
		return
	_game_over_shown = true
	var ui := get_node_or_null("CanvasLayer/UI")
	if ui == null:
		return
	var death_label := Label.new()
	death_label.text = "YOU DIED"
	death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	death_label.add_theme_font_size_override("font_size", 64)
	death_label.add_theme_color_override("font_color", Color(1.0, 0.15, 0.15, 1.0))
	death_label.set_anchors_preset(Control.PRESET_CENTER)
	death_label.offset_left = -200
	death_label.offset_right = 200
	death_label.offset_top = -50
	death_label.offset_bottom = 50
	ui.add_child(death_label)


func _show_game_over_message() -> void:
	_game_over_shown = true
	var ui := get_node_or_null("CanvasLayer/UI")
	if ui == null:
		return
	var game_over_label := Label.new()
	game_over_label.text = "OUT OF AMMO\n%d enemies remaining" % _current_enemy_count
	game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	game_over_label.add_theme_font_size_override("font_size", 48)
	game_over_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1.0))
	game_over_label.set_anchors_preset(Control.PRESET_CENTER)
	game_over_label.offset_left = -250
	game_over_label.offset_right = 250
	game_over_label.offset_top = -75
	game_over_label.offset_bottom = 75
	ui.add_child(game_over_label)


## ============================================================
## Navigation helpers
## ============================================================

func _broadcast_player_reloading(is_reloading: bool) -> void:
	var enemies_node := get_node_or_null("Environment/Enemies")
	if enemies_node == null:
		return
	for enemy in enemies_node.get_children():
		if enemy.has_method("set_player_reloading"):
			enemy.set_player_reloading(is_reloading)


func _broadcast_player_ammo_empty(is_empty: bool) -> void:
	var enemies_node := get_node_or_null("Environment/Enemies")
	if enemies_node == null:
		return
	for enemy in enemies_node.get_children():
		if enemy.has_method("set_player_ammo_empty"):
			enemy.set_player_ammo_empty(is_empty)


## ============================================================
## Input: Q to restart, W to toggle score
## ============================================================

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.physical_keycode == KEY_Q:
			_on_restart_pressed()
		elif event.physical_keycode == KEY_W and _level_cleared:
			if not _score_shown:
				_complete_level_with_score()


## ============================================================
## Button handlers
## ============================================================

func _on_restart_pressed() -> void:
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
	get_tree().change_scene_to_file("res://scenes/levels/RoguelikeLevel.tscn")


func _on_level_select_pressed() -> void:
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)
	# Use SceneLoader if available, otherwise direct change
	var scene_loader: Node = get_node_or_null("/root/SceneLoader")
	if scene_loader and scene_loader.has_method("load_level"):
		scene_loader.load_level("res://scenes/levels/LabyrinthLevel.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/levels/LabyrinthLevel.tscn")
