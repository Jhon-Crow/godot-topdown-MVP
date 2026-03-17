extends Node2D
## Roguelike level with procedural generation using existing level scenes as rooms.
##
## Issue #1061: добавить режим рогалика
##
## Each run randomly selects 3–5 existing level scenes and stitches them together
## side-by-side with wide connecting corridors, giving the player proper rooms with
## full geometry, cover, and exits rather than tiny procedurally generated boxes.
##
## Features:
## - Uses real existing level scenes (Labyrinth, Building, Castle, City, Beach, Docks) as rooms
## - Rooms are arranged left-to-right with wide corridors between them
## - Enemies come from the level scenes themselves — random per run
## - Player starts in the first (leftmost) room, exit zone appears in the last room
## - Full HUD (enemy count, ammo, kills, accuracy, combo) matching other levels
## - Score tracking with rank system (ScoreManager / ProgressManager)
## - Q key restarts with a new random room selection


## ============================================================
## Room (existing level scene) pool — scenes that can appear as roguelike rooms
## ============================================================

## All candidate level scenes.  Each has a scene path and the approximate bounding
## box of its walkable area (used to compute the room's footprint for layout).
const ROOM_POOL: Array[Dictionary] = [
	{
		"path": "res://scenes/levels/LabyrinthLevel.tscn",
		"size": Vector2(1920, 1080),
		"player_spawn": Vector2(100, 540),
		"exit_spawn": Vector2(1800, 540)
	},
	{
		"path": "res://scenes/levels/BuildingLevel.tscn",
		"size": Vector2(2400, 2000),
		"player_spawn": Vector2(200, 1000),
		"exit_spawn": Vector2(2200, 1000)
	},
	{
		"path": "res://scenes/levels/CastleLevel.tscn",
		"size": Vector2(6000, 2560),
		"player_spawn": Vector2(300, 1280),
		"exit_spawn": Vector2(5700, 1280)
	},
	{
		"path": "res://scenes/levels/CityLevel.tscn",
		"size": Vector2(6000, 5000),
		"player_spawn": Vector2(300, 2500),
		"exit_spawn": Vector2(5700, 2500)
	},
	{
		"path": "res://scenes/levels/BeachLevel.tscn",
		"size": Vector2(2400, 2000),
		"player_spawn": Vector2(200, 1000),
		"exit_spawn": Vector2(2200, 1000)
	},
	{
		"path": "res://scenes/levels/DocksLevel.tscn",
		"size": Vector2(5000, 4000),
		"player_spawn": Vector2(300, 2000),
		"exit_spawn": Vector2(4700, 2000)
	},
	{
		"path": "res://scenes/levels/RevolverLevel.tscn",
		"size": Vector2(2000, 1600),
		"player_spawn": Vector2(200, 800),
		"exit_spawn": Vector2(1800, 800)
	},
]

## Number of rooms to pick per run.
const MIN_ROOMS: int = 3
const MAX_ROOMS: int = 5

## Horizontal gap between rooms (corridor width in pixels).
const CORRIDOR_GAP: float = 300.0

## Corridor height (vertical opening between rooms).
const CORRIDOR_HEIGHT: float = 200.0

## Wall/corridor color constants (matching other levels).
const WALL_COLOR: Color = Color(0.3, 0.3, 0.35, 1.0)
const FLOOR_COLOR: Color = Color(0.18, 0.18, 0.22, 1.0)
const BG_COLOR: Color = Color(0.05, 0.05, 0.07, 1.0)

## Saturation effect constants (matching other levels).
const SATURATION_DURATION: float = 0.15
const SATURATION_INTENSITY: float = 0.25


## ============================================================
## Runtime state
## ============================================================

## Selected room descriptors (Dictionary from ROOM_POOL) in order.
var _selected_rooms: Array[Dictionary] = []

## World-space X offset for each room (rooms laid out left-to-right).
var _room_offsets: Array[float] = []

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

	_select_rooms()
	_build_level()
	_spawn_player()
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

	print("[RoguelikeLevel] Level ready — %d rooms, %d enemies" % [_selected_rooms.size(), _initial_enemy_count])


func _process(_delta: float) -> void:
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager and score_manager.has_method("update_enemy_positions"):
		score_manager.update_enemy_positions(_enemies)


## ============================================================
## Room selection and level construction
## ============================================================

## Pick a random subset of rooms from the pool (no duplicates).
func _select_rooms() -> void:
	_selected_rooms.clear()
	var pool: Array[Dictionary] = ROOM_POOL.duplicate()

	# Shuffle the pool
	for i in range(pool.size() - 1, 0, -1):
		var j: int = randi_range(0, i)
		var tmp: Dictionary = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp

	var count: int = randi_range(MIN_ROOMS, MAX_ROOMS)
	count = min(count, pool.size())
	for i in range(count):
		_selected_rooms.append(pool[i])

	print("[RoguelikeLevel] Selected rooms: %s" % str(_selected_rooms.map(func(r): return r.path.get_file())))


## Build the world: background, corridors, and instantiate room sub-scenes.
func _build_level() -> void:
	_room_offsets.clear()

	# Calculate X offset for each room (laid out left-to-right)
	var current_x: float = 0.0
	for room_data in _selected_rooms:
		_room_offsets.append(current_x)
		current_x += room_data.size.x + CORRIDOR_GAP

	# Total world dimensions
	var total_width: float = current_x
	var max_height: float = 0.0
	for room_data in _selected_rooms:
		max_height = max(max_height, room_data.size.y)

	# Dark background behind everything
	var bg := ColorRect.new()
	bg.name = "WorldBackground"
	bg.position = Vector2(-200, -200)
	bg.size = Vector2(total_width + 400, max_height + 400)
	bg.color = BG_COLOR
	add_child(bg)

	# Corridor floors and walls between rooms
	var corridor_container := Node2D.new()
	corridor_container.name = "Corridors"
	add_child(corridor_container)
	_build_corridors(corridor_container)

	# Instantiate room sub-scenes
	var rooms_container := Node2D.new()
	rooms_container.name = "Rooms"
	add_child(rooms_container)

	for i in range(_selected_rooms.size()):
		_instantiate_room(rooms_container, i)


## Build corridor floors and walls between adjacent rooms.
func _build_corridors(parent: Node) -> void:
	for i in range(_selected_rooms.size() - 1):
		var left_room: Dictionary = _selected_rooms[i]
		var right_room: Dictionary = _selected_rooms[i + 1]
		var left_x: float = _room_offsets[i]
		var right_x: float = _room_offsets[i + 1]

		# The corridor spans from the right edge of the left room to the left edge of the right room
		var corridor_start_x: float = left_x + left_room.size.x
		var corridor_end_x: float = right_x
		var corridor_width: float = corridor_end_x - corridor_start_x

		# Vertical center of both rooms' exit/entry points
		var left_center_y: float = left_room.size.y * 0.5
		var right_center_y: float = right_room.size.y * 0.5

		# Corridor floor (horizontal strip connecting the two rooms)
		var floor_rect := ColorRect.new()
		floor_rect.position = Vector2(corridor_start_x, left_center_y - CORRIDOR_HEIGHT * 0.5)
		floor_rect.size = Vector2(corridor_width, CORRIDOR_HEIGHT)
		floor_rect.color = FLOOR_COLOR
		parent.add_child(floor_rect)

		# If the rooms have different heights, add a vertical ramp section
		if abs(left_center_y - right_center_y) > 10.0:
			var v_floor := ColorRect.new()
			var v_top: float = min(left_center_y, right_center_y) - CORRIDOR_HEIGHT * 0.5
			var v_bottom: float = max(left_center_y, right_center_y) + CORRIDOR_HEIGHT * 0.5
			v_floor.position = Vector2(corridor_end_x - CORRIDOR_HEIGHT, v_top)
			v_floor.size = Vector2(CORRIDOR_HEIGHT, v_bottom - v_top)
			v_floor.color = FLOOR_COLOR
			parent.add_child(v_floor)

		# Top wall above the corridor
		_create_wall_body(parent, Rect2(
			corridor_start_x,
			left_center_y - CORRIDOR_HEIGHT * 0.5 - 24,
			corridor_width,
			24
		))
		# Bottom wall below the corridor
		_create_wall_body(parent, Rect2(
			corridor_start_x,
			left_center_y + CORRIDOR_HEIGHT * 0.5,
			corridor_width,
			24
		))


## Instantiate a room scene, strip its HUD/player/exit-zone, and position it.
func _instantiate_room(parent: Node, room_index: int) -> void:
	var room_data: Dictionary = _selected_rooms[room_index]
	var offset_x: float = _room_offsets[room_index]

	var scene: PackedScene = load(room_data.path)
	if scene == null:
		push_error("[RoguelikeLevel] Failed to load room scene: %s" % room_data.path)
		return

	var room_instance: Node = scene.instantiate()
	room_instance.name = "Room%d" % room_index
	room_instance.position = Vector2(offset_x, 0.0)

	# Disable the room's own _ready logic by removing its script before adding to tree,
	# so it doesn't run its own setup, register enemies twice, etc.
	# We keep all the geometry but strip runtime-only nodes.
	room_instance.set_script(null)

	parent.add_child(room_instance)

	# Remove the room's own CanvasLayer (HUD), PauseMenu, and player nodes —
	# we manage these at the roguelike level.
	for child_name in ["CanvasLayer", "PauseMenu", "Player", "Entities"]:
		var node: Node = room_instance.get_node_or_null(child_name)
		if node:
			node.queue_free()

	# Remove the room's ExitZone (we place our own in the last room)
	_remove_exit_zones_recursive(room_instance)

	# Collect all enemy nodes from this room into our global enemy list
	_collect_enemies_from_room(room_instance)

	# Move the player from this room's scene if present
	var player_node: Node = room_instance.get_node_or_null("Player")
	if player_node == null:
		# Try nested paths
		for path in ["Entities/Player", "Environment/Player"]:
			player_node = room_instance.get_node_or_null(path)
			if player_node:
				break

	print("[RoguelikeLevel] Room %d instantiated from %s at x=%.0f" % [room_index, room_data.path.get_file(), offset_x])


## Recursively remove any ExitZone nodes from a room subtree.
func _remove_exit_zones_recursive(node: Node) -> void:
	for child in node.get_children():
		if child.get_script() != null:
			var script_path: String = child.get_script().resource_path
			if "exit_zone" in script_path.to_lower():
				child.queue_free()
				continue
		if child.name.to_lower().contains("exit"):
			child.queue_free()
			continue
		_remove_exit_zones_recursive(child)


## Collect all enemy nodes from a room into _enemies, connecting their signals.
func _collect_enemies_from_room(room_node: Node) -> void:
	_collect_enemies_recursive(room_node)


func _collect_enemies_recursive(node: Node) -> void:
	for child in node.get_children():
		if child.has_signal("died") and not (child in _enemies):
			_enemies.append(child)
			child.died.connect(_on_enemy_died)
			if child.has_signal("died_with_info"):
				child.died_with_info.connect(_on_enemy_died_with_info)
			if child.has_signal("hit"):
				child.hit.connect(_on_enemy_hit)
		_collect_enemies_recursive(child)


## Create a single wall StaticBody2D with collision and visual.
func _create_wall_body(parent: Node, rect: Rect2) -> void:
	var wall := StaticBody2D.new()
	wall.collision_layer = 4
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


## ============================================================
## Player spawning
## ============================================================

## Spawn the player in the first room.
func _spawn_player() -> void:
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

	# Place player at the entry point of the first room
	var first_room: Dictionary = _selected_rooms[0]
	var spawn_x: float = _room_offsets[0] + first_room.player_spawn.x
	var spawn_y: float = first_room.player_spawn.y
	player.position = Vector2(spawn_x, spawn_y)

	entities_node.add_child(player)
	print("[RoguelikeLevel] Player spawned at (%.0f, %.0f)" % [player.position.x, player.position.y])


## ============================================================
## Standard level setup (mirrors docks_level.gd / labyrinth_level.gd)
## ============================================================

func _setup_navigation() -> void:
	var nav_region: NavigationRegion2D = get_node_or_null("NavigationRegion2D")
	if nav_region == null:
		# Create navigation region programmatically
		nav_region = NavigationRegion2D.new()
		nav_region.name = "NavigationRegion2D"
		var nav_poly := NavigationPolygon.new()
		nav_poly.parsed_geometry_type = NavigationPolygon.PARSED_GEOMETRY_STATIC_COLLIDERS
		nav_poly.parsed_collision_mask = 4
		nav_poly.source_geometry_mode = NavigationPolygon.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
		nav_poly.agent_radius = 24.0
		nav_region.navigation_polygon = nav_poly
		add_child(nav_region)

	print("[RoguelikeLevel] Navigation region set up")


func _setup_player_tracking() -> void:
	_player = get_node_or_null("Entities/Player")
	if _player == null:
		_player = get_node_or_null("Player")
	if _player == null:
		return

	_setup_selected_weapon()

	if GameManager:
		GameManager.set_player(_player)

	_ammo_label = get_node_or_null("CanvasLayer/UI/AmmoLabel")

	if _player.has_signal("died"):
		_player.died.connect(_on_player_died)
	elif _player.has_signal("Died"):
		_player.Died.connect(_on_player_died)

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
		if _player.has_signal("ammo_changed"):
			_player.ammo_changed.connect(_on_player_ammo_changed)

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
	# Enemies were already collected during room instantiation in _collect_enemies_from_room().
	# Just count them and update the HUD.
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

	# Place exit zone at the far end of the last room
	var last_index: int = _selected_rooms.size() - 1
	var last_room: Dictionary = _selected_rooms[last_index]
	var exit_x: float = _room_offsets[last_index] + last_room.exit_spawn.x
	var exit_y: float = last_room.exit_spawn.y
	_exit_zone.position = Vector2(exit_x, exit_y)
	_exit_zone.zone_width = 120.0
	_exit_zone.zone_height = 120.0

	_exit_zone.player_reached_exit.connect(_on_player_reached_exit)
	add_child(_exit_zone)

	print("[RoguelikeLevel] Exit zone placed at (%.0f, %.0f)" % [_exit_zone.position.x, _exit_zone.position.y])


func _setup_debug_ui() -> void:
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
	mode_label.text = "РОГАЛИК — %d комнат(ы)" % _selected_rooms.size()
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

	var weapon_names: Dictionary = {
		"shotgun": "Shotgun", "mini_uzi": "MiniUzi", "silenced_pistol": "SilencedPistol",
		"sniper": "SniperRifle", "m16": "AssaultRifle", "ak_gl": "AKGL",
		"revolver": "Revolver", "makarov_pm": "MakarovPM"
	}
	if selected_weapon_id in weapon_names:
		var expected_name: String = weapon_names[selected_weapon_id]
		var existing: Node = _player.get_node_or_null(expected_name)
		if existing != null and _player.get("CurrentWeapon") == existing:
			return

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
	restart_button.text = "↻ Снова (Q)"
	restart_button.custom_minimum_size = Vector2(200, 40)
	restart_button.add_theme_font_size_override("font_size", 18)
	restart_button.pressed.connect(_on_restart_pressed)
	container.add_child(restart_button)

	var level_select_button := Button.new()
	level_select_button.text = "☰ Меню"
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
	title.text = "РОГАЛИК ПРОЙДЕН!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(0.6, 0.4, 1.0, 1.0))
	container.add_child(title)

	var total_label := Label.new()
	total_label.text = "ИТОГО: %d | РАНГ: %s" % [score_data.get("total_score", 0), score_data.get("rank", "?")]
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
	victory_label.text = "РОГАЛИК ПРОЙДЕН!"
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
	for enemy in _enemies:
		if is_instance_valid(enemy) and enemy.has_method("set_player_reloading"):
			enemy.set_player_reloading(is_reloading)


func _broadcast_player_ammo_empty(is_empty: bool) -> void:
	for enemy in _enemies:
		if is_instance_valid(enemy) and enemy.has_method("set_player_ammo_empty"):
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
	var scene_loader: Node = get_node_or_null("/root/SceneLoader")
	if scene_loader and scene_loader.has_method("load_level"):
		scene_loader.load_level("res://scenes/levels/LabyrinthLevel.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/levels/LabyrinthLevel.tscn")


## Return the next level path (roguelike loops back to itself for now)
func _get_next_level_path() -> String:
	return "res://scenes/levels/RoguelikeLevel.tscn"
