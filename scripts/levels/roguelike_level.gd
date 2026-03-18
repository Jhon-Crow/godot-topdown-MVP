extends Node2D
## Roguelike level with procedural room generation by type.
##
## Issue #1061: добавить режим рогалика
##
## Each run generates 3–5 rooms of different types (Labyrinth, Building, Beach, Docks, City)
## with procedurally placed walls, covers and enemies. This avoids the heavy overhead of
## loading full level scenes (which caused 55+ enemies and 2–6 fps drops).
##
## Features:
## - Procedural room layouts by type — each type has a characteristic geometry
## - Player always starts with Makarov PM + Flashbang grenade (armory ignored)
## - 3–4 enemies per room maximum (performance constraint)
## - No ReplayManager in roguelike (saves memory/CPU)
## - Q restarts with a new seed
## - Exit zone activates after all enemies are cleared


## ============================================================
## Room types — each gets a distinct procedural layout
## ============================================================

enum RoomType {
	LABYRINTH,   ## Corridors / maze: horizontal + vertical interior walls
	BUILDING,    ## Indoor rooms: walled sub-rooms with doorways
	BEACH,       ## Open area: scattered obstacles (barrels, crates)
	DOCKS,       ## Container yard: long parallel walls (containers)
	CITY         ## Urban: L-shaped cover blocks, car-like barriers
}

## Room size for procedural generation (all rooms same size for simplicity)
const ROOM_WIDTH: float  = 1280.0
const ROOM_HEIGHT: float = 720.0

## Corridor connecting rooms
const CORRIDOR_GAP: float    = 200.0   ## Horizontal space between rooms
const CORRIDOR_HEIGHT: float = 180.0   ## Opening height for the corridor

## Enemy count limits per room
const ENEMIES_PER_ROOM_MIN: int = 3
const ENEMIES_PER_ROOM_MAX: int = 4

## Number of rooms per run
const MIN_ROOMS: int = 3
const MAX_ROOMS: int = 5

## Wall / visual colour constants
const WALL_COLOR:  Color = Color(0.3,  0.3,  0.35, 1.0)
const FLOOR_COLOR: Color = Color(0.18, 0.18, 0.22, 1.0)
const BG_COLOR:    Color = Color(0.05, 0.05, 0.07, 1.0)

## Floor tint per room type (subtle)
const ROOM_FLOOR_COLORS: Dictionary = {
	RoomType.LABYRINTH: Color(0.16, 0.18, 0.22, 1.0),
	RoomType.BUILDING:  Color(0.20, 0.18, 0.18, 1.0),
	RoomType.BEACH:     Color(0.22, 0.20, 0.14, 1.0),
	RoomType.DOCKS:     Color(0.14, 0.18, 0.20, 1.0),
	RoomType.CITY:      Color(0.20, 0.20, 0.20, 1.0),
}

const ROOM_TYPE_NAMES: Dictionary = {
	RoomType.LABYRINTH: "Лабиринт",
	RoomType.BUILDING:  "Здание",
	RoomType.BEACH:     "Пляж",
	RoomType.DOCKS:     "Доки",
	RoomType.CITY:      "Город",
}

## Saturation flash on kill
const SATURATION_DURATION:  float = 0.15
const SATURATION_INTENSITY: float = 0.25


## ============================================================
## Runtime state
## ============================================================

var _selected_types:  Array[int]   = []   ## RoomType values
var _room_offsets:    Array[float] = []   ## World-space X start of each room

var _player: Node2D = null

## HUD refs
var _enemy_count_label:  Label = null
var _ammo_label:         Label = null
var _kills_label:        Label = null
var _accuracy_label:     Label = null
var _magazines_label:    Label = null
var _combo_label:        Label = null
var _saturation_overlay: ColorRect = null

## Enemy tracking
var _enemies:               Array = []
var _initial_enemy_count:   int   = 0
var _current_enemy_count:   int   = 0

## State flags
var _level_cleared:   bool = false
var _game_over_shown: bool = false
var _score_shown:     bool = false
var _level_completed: bool = false

var _exit_zone: Area2D = null

## Saved GameManager weapon before roguelike (restored on exit)
var _saved_weapon: String = ""


## ============================================================
## _ready: entry point
## ============================================================

func _ready() -> void:
	randomize()
	var seed_used: int = randi()
	seed(seed_used)
	print("[RoguelikeLevel] Generating level with seed: %d" % seed_used)

	_force_roguelike_loadout()
	_select_room_types()
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
	# Intentionally skip ReplayManager — reduces memory and CPU overhead

	if GameManager:
		GameManager.enemy_killed.connect(_on_game_manager_enemy_killed)
		GameManager.stats_updated.connect(_update_debug_ui)

	print("[RoguelikeLevel] Level ready — %d rooms, %d enemies" % [_selected_types.size(), _initial_enemy_count])


func _process(_delta: float) -> void:
	var sm: Node = get_node_or_null("/root/ScoreManager")
	if sm and sm.has_method("update_enemy_positions"):
		sm.update_enemy_positions(_enemies)


## ============================================================
## Loadout override — PM + flashbang, no armory
## ============================================================

func _force_roguelike_loadout() -> void:
	if GameManager:
		_saved_weapon = GameManager.get_selected_weapon()
		GameManager.set_selected_weapon("makarov_pm")
	var grenade_manager: Node = get_node_or_null("/root/GrenadeManager")
	if grenade_manager:
		# GrenadeType.FLASHBANG = 0
		if grenade_manager.get("current_grenade_type") != null:
			grenade_manager.current_grenade_type = 0  # FLASHBANG
	print("[RoguelikeLevel] Loadout forced: makarov_pm + flashbang")


func _restore_loadout() -> void:
	if GameManager and _saved_weapon != "":
		GameManager.set_selected_weapon(_saved_weapon)


## ============================================================
## Room type selection
## ============================================================

func _select_room_types() -> void:
	_selected_types.clear()
	var all_types: Array[int] = [
		RoomType.LABYRINTH,
		RoomType.BUILDING,
		RoomType.BEACH,
		RoomType.DOCKS,
		RoomType.CITY,
	]
	# Shuffle
	for i in range(all_types.size() - 1, 0, -1):
		var j: int = randi_range(0, i)
		var tmp: int = all_types[i]
		all_types[i] = all_types[j]
		all_types[j] = tmp

	var count: int = randi_range(MIN_ROOMS, MAX_ROOMS)
	count = min(count, all_types.size())
	for i in range(count):
		_selected_types.append(all_types[i])

	var names: Array[String] = []
	for t in _selected_types:
		names.append(ROOM_TYPE_NAMES.get(t, "?"))
	print("[RoguelikeLevel] Room types: %s" % str(names))


## ============================================================
## Level construction
## ============================================================

func _build_level() -> void:
	_room_offsets.clear()

	var current_x: float = 0.0
	for _t in _selected_types:
		_room_offsets.append(current_x)
		current_x += ROOM_WIDTH + CORRIDOR_GAP

	var total_width: float = current_x

	# Background
	var bg := ColorRect.new()
	bg.name = "WorldBackground"
	bg.position = Vector2(-200, -200)
	bg.size = Vector2(total_width + 400, ROOM_HEIGHT + 400)
	bg.color = BG_COLOR
	add_child(bg)

	# Build each room
	var rooms_container := Node2D.new()
	rooms_container.name = "Rooms"
	add_child(rooms_container)

	for i in range(_selected_types.size()):
		_build_room(rooms_container, i)

	# Corridors between rooms
	var corridor_container := Node2D.new()
	corridor_container.name = "Corridors"
	add_child(corridor_container)
	_build_corridors(corridor_container)


func _build_room(parent: Node, room_index: int) -> void:
	var room_type: int = _selected_types[room_index]
	var offset_x: float = _room_offsets[room_index]

	var room_node := Node2D.new()
	room_node.name = "Room%d" % room_index
	room_node.position = Vector2(offset_x, 0.0)
	parent.add_child(room_node)

	# Floor
	var floor_color: Color = ROOM_FLOOR_COLORS.get(room_type, FLOOR_COLOR)
	var floor_rect := ColorRect.new()
	floor_rect.position = Vector2(0, 0)
	floor_rect.size = Vector2(ROOM_WIDTH, ROOM_HEIGHT)
	floor_rect.color = floor_color
	room_node.add_child(floor_rect)

	# Boundary walls (with corridor openings on left/right sides)
	_build_room_boundary(room_node, room_index)

	# Interior layout
	match room_type:
		RoomType.LABYRINTH:
			_build_labyrinth_interior(room_node)
		RoomType.BUILDING:
			_build_building_interior(room_node)
		RoomType.BEACH:
			_build_beach_interior(room_node)
		RoomType.DOCKS:
			_build_docks_interior(room_node)
		RoomType.CITY:
			_build_city_interior(room_node)

	# Spawn enemies in this room
	_spawn_enemies_in_room(room_node, room_index)

	print("[RoguelikeLevel] Room %d built: type=%s, offset_x=%.0f" % [room_index, ROOM_TYPE_NAMES.get(room_type, "?"), offset_x])


## Boundary walls with openings where corridors connect.
func _build_room_boundary(room_node: Node2D, room_index: int) -> void:
	var w: float = ROOM_WIDTH
	var h: float = ROOM_HEIGHT
	var wall_t: float = 24.0

	var corridor_mid_y: float = h * 0.5
	var half_opening: float   = CORRIDOR_HEIGHT * 0.5

	# Top wall (full)
	_create_wall(room_node, Rect2(0, 0, w, wall_t))
	# Bottom wall (full)
	_create_wall(room_node, Rect2(0, h - wall_t, w, wall_t))

	# Left wall — open if not first room
	var is_first: bool = (room_index == 0)
	if is_first:
		_create_wall(room_node, Rect2(0, 0, wall_t, h))
	else:
		# Left wall above opening
		_create_wall(room_node, Rect2(0, 0, wall_t, corridor_mid_y - half_opening))
		# Left wall below opening
		_create_wall(room_node, Rect2(0, corridor_mid_y + half_opening, wall_t, h - (corridor_mid_y + half_opening)))

	# Right wall — open if not last room
	var is_last: bool = (room_index == _selected_types.size() - 1)
	if is_last:
		_create_wall(room_node, Rect2(w - wall_t, 0, wall_t, h))
	else:
		# Right wall above opening
		_create_wall(room_node, Rect2(w - wall_t, 0, wall_t, corridor_mid_y - half_opening))
		# Right wall below opening
		_create_wall(room_node, Rect2(w - wall_t, corridor_mid_y + half_opening, wall_t, h - (corridor_mid_y + half_opening)))


## ─── Labyrinth: horizontal and vertical divider walls ───────────────────────
func _build_labyrinth_interior(room_node: Node2D) -> void:
	var w: float = ROOM_WIDTH
	var h: float = ROOM_HEIGHT
	var opening: float = 140.0

	# Horizontal divider at 1/3 height — gap on right side
	_create_wall(room_node, Rect2(60, h * 0.33, w * 0.55, 20))
	# Horizontal divider at 2/3 height — gap on left side
	_create_wall(room_node, Rect2(w * 0.45, h * 0.66, w * 0.55 - 30, 20))
	# Vertical divider at centre — gap in middle
	_create_wall(room_node, Rect2(w * 0.5 - 10, 60, 20, h * 0.35))
	_create_wall(room_node, Rect2(w * 0.5 - 10, h * 0.35 + opening, 20, h * 0.30))
	# Short L-wall in upper-left quadrant
	_create_wall(room_node, Rect2(120, h * 0.14, 140, 20))
	_create_wall(room_node, Rect2(120, h * 0.14, 20, 80))
	# Short L-wall in lower-right quadrant
	_create_wall(room_node, Rect2(w - 260, h * 0.78, 140, 20))
	_create_wall(room_node, Rect2(w - 280 + 140, h * 0.72, 20, 80))


## ─── Building: walled sub-rooms with doorways ───────────────────────────────
func _build_building_interior(room_node: Node2D) -> void:
	var w: float = ROOM_WIDTH
	var h: float = ROOM_HEIGHT
	var opening: float = 100.0

	# Vertical wall dividing left and right sub-rooms — doorway at mid-height
	_create_wall(room_node, Rect2(w * 0.42, 60, 20, h * 0.35))
	_create_wall(room_node, Rect2(w * 0.42, 60 + h * 0.35 + opening, 20, h - (60 + h * 0.35 + opening) - 60))

	# Top-right alcove
	_create_wall(room_node, Rect2(w * 0.60, 60, w * 0.22, 20))
	_create_wall(room_node, Rect2(w * 0.82 - 20, 60, 20, h * 0.28))

	# Bottom-left alcove
	_create_wall(room_node, Rect2(60, h * 0.68, w * 0.22, 20))
	_create_wall(room_node, Rect2(60, h * 0.54, 20, h * 0.14 + 20))

	# Cover crate in left room
	_create_cover(room_node, Rect2(w * 0.18, h * 0.42, 60, 60))
	# Cover panel in right room
	_create_cover(room_node, Rect2(w * 0.68, h * 0.55, 80, 20))


## ─── Beach: open field with scattered obstacles ─────────────────────────────
func _build_beach_interior(room_node: Node2D) -> void:
	var w: float = ROOM_WIDTH
	var h: float = ROOM_HEIGHT

	# Scattered crates and barrels
	var positions: Array[Vector2] = [
		Vector2(w * 0.18, h * 0.25),
		Vector2(w * 0.18, h * 0.65),
		Vector2(w * 0.40, h * 0.38),
		Vector2(w * 0.40, h * 0.58),
		Vector2(w * 0.62, h * 0.22),
		Vector2(w * 0.62, h * 0.72),
		Vector2(w * 0.80, h * 0.44),
	]
	for pos in positions:
		# Alternate between small and large covers
		var sz: float = 44.0 if (int(pos.x) % 2 == 0) else 32.0
		_create_cover(room_node, Rect2(pos.x - sz * 0.5, pos.y - sz * 0.5, sz, sz))

	# A low sandbag wall segment
	_create_cover(room_node, Rect2(w * 0.55, h * 0.5 - 10, 120, 20))


## ─── Docks: parallel container walls ────────────────────────────────────────
func _build_docks_interior(room_node: Node2D) -> void:
	var w: float = ROOM_WIDTH
	var h: float = ROOM_HEIGHT
	var gap: float = 110.0  ## Aisle width

	# Three pairs of container walls (horizontal, parallel)
	for row in range(3):
		var y: float = h * (0.22 + row * 0.24)
		# Left container
		_create_wall(room_node, Rect2(80, y, w * 0.36, 22))
		# Right container (offset)
		_create_wall(room_node, Rect2(w * 0.52, y + 22, w * 0.36, 22))

	# End container stack on left
	_create_wall(room_node, Rect2(80, h * 0.22, 22, h * 0.22))
	# End container stack on right
	_create_wall(room_node, Rect2(w - 102, h * 0.46, 22, h * 0.22))


## ─── City: L-shaped cover blocks and barriers ───────────────────────────────
func _build_city_interior(room_node: Node2D) -> void:
	var w: float = ROOM_WIDTH
	var h: float = ROOM_HEIGHT

	# L-shaped cover in upper-left
	_create_cover(room_node, Rect2(w * 0.14, h * 0.20, 100, 20))
	_create_cover(room_node, Rect2(w * 0.14, h * 0.20, 20, 80))

	# L-shaped cover in lower-right
	_create_cover(room_node, Rect2(w * 0.72, h * 0.68, 100, 20))
	_create_cover(room_node, Rect2(w * 0.72 + 80, h * 0.60, 20, 80))

	# Car-like long barriers
	_create_cover(room_node, Rect2(w * 0.34, h * 0.42, 160, 32))
	_create_cover(room_node, Rect2(w * 0.60, h * 0.30, 160, 32))

	# Bollard cluster
	for i in range(3):
		_create_cover(room_node, Rect2(w * 0.46 + i * 36, h * 0.60, 24, 24))


## ============================================================
## Corridor floors and walls between rooms
## ============================================================

func _build_corridors(parent: Node) -> void:
	for i in range(_selected_types.size() - 1):
		var left_x: float   = _room_offsets[i] + ROOM_WIDTH
		var right_x: float  = _room_offsets[i + 1]
		var mid_y: float    = ROOM_HEIGHT * 0.5
		var half_h: float   = CORRIDOR_HEIGHT * 0.5

		# Floor strip
		var floor_rect := ColorRect.new()
		floor_rect.position = Vector2(left_x, mid_y - half_h)
		floor_rect.size = Vector2(CORRIDOR_GAP, CORRIDOR_HEIGHT)
		floor_rect.color = FLOOR_COLOR
		parent.add_child(floor_rect)

		# Top wall of corridor
		_create_wall(parent, Rect2(left_x, mid_y - half_h - 24, CORRIDOR_GAP, 24))
		# Bottom wall of corridor
		_create_wall(parent, Rect2(left_x, mid_y + half_h, CORRIDOR_GAP, 24))


## ============================================================
## Enemy spawning (procedural, per room)
## ============================================================

func _spawn_enemies_in_room(room_node: Node2D, room_index: int) -> void:
	var room_type: int = _selected_types[room_index]
	var enemy_scene: PackedScene = load("res://scenes/objects/Enemy.tscn")
	if enemy_scene == null:
		push_error("[RoguelikeLevel] Enemy.tscn not found!")
		return

	var positions: Array[Vector2] = _get_enemy_positions(room_type)
	var count: int = randi_range(ENEMIES_PER_ROOM_MIN, min(ENEMIES_PER_ROOM_MAX, positions.size()))

	# Shuffle positions
	for i in range(positions.size() - 1, 0, -1):
		var j: int = randi_range(0, i)
		var tmp: Vector2 = positions[i]
		positions[i] = positions[j]
		positions[j] = tmp

	for i in range(count):
		var enemy: Node = enemy_scene.instantiate()
		enemy.name = "Enemy_R%d_%d" % [room_index, i]
		enemy.position = positions[i]
		# Randomise weapon
		enemy.weapon_type = _random_enemy_weapon(room_type)
		enemy.behavior_mode = _random_enemy_behavior(room_type, i)
		if enemy.behavior_mode == 0:  # PATROL
			enemy.patrol_offsets = [Vector2(80, 0), Vector2(-80, 0)]
		enemy.min_health = 1
		enemy.max_health = 2
		room_node.add_child(enemy)

		# Track enemy
		_enemies.append(enemy)
		if enemy.has_signal("died"):
			enemy.died.connect(_on_enemy_died)
		if enemy.has_signal("died_with_info"):
			enemy.died_with_info.connect(_on_enemy_died_with_info)
		if enemy.has_signal("hit"):
			enemy.hit.connect(_on_enemy_hit)


## Enemy spawn positions per room type (relative to room origin).
func _get_enemy_positions(room_type: int) -> Array[Vector2]:
	var w: float = ROOM_WIDTH
	var h: float = ROOM_HEIGHT
	match room_type:
		RoomType.LABYRINTH:
			return [
				Vector2(w * 0.20, h * 0.22),
				Vector2(w * 0.20, h * 0.76),
				Vector2(w * 0.60, h * 0.22),
				Vector2(w * 0.60, h * 0.76),
				Vector2(w * 0.80, h * 0.50),
			]
		RoomType.BUILDING:
			return [
				Vector2(w * 0.22, h * 0.32),
				Vector2(w * 0.22, h * 0.68),
				Vector2(w * 0.70, h * 0.30),
				Vector2(w * 0.70, h * 0.70),
				Vector2(w * 0.50, h * 0.50),
			]
		RoomType.BEACH:
			return [
				Vector2(w * 0.30, h * 0.30),
				Vector2(w * 0.30, h * 0.68),
				Vector2(w * 0.55, h * 0.50),
				Vector2(w * 0.75, h * 0.30),
				Vector2(w * 0.75, h * 0.68),
			]
		RoomType.DOCKS:
			return [
				Vector2(w * 0.18, h * 0.50),
				Vector2(w * 0.40, h * 0.30),
				Vector2(w * 0.40, h * 0.70),
				Vector2(w * 0.65, h * 0.50),
				Vector2(w * 0.82, h * 0.50),
			]
		RoomType.CITY:
			return [
				Vector2(w * 0.22, h * 0.50),
				Vector2(w * 0.46, h * 0.30),
				Vector2(w * 0.46, h * 0.70),
				Vector2(w * 0.72, h * 0.50),
				Vector2(w * 0.86, h * 0.22),
			]
		_:
			return [
				Vector2(w * 0.30, h * 0.40),
				Vector2(w * 0.30, h * 0.60),
				Vector2(w * 0.70, h * 0.40),
				Vector2(w * 0.70, h * 0.60),
			]


func _random_enemy_weapon(room_type: int) -> int:
	# WeaponType: RIFLE=0, SHOTGUN=1, UZI=2, MACHETE=3
	match room_type:
		RoomType.LABYRINTH:
			return [0, 2][randi() % 2]           # Rifle or UZI — good in corridors
		RoomType.BUILDING:
			return [0, 1, 2][randi() % 3]        # All ranged
		RoomType.BEACH:
			return [0, 1][randi() % 2]           # Rifle or Shotgun — open area
		RoomType.DOCKS:
			return [0, 2, 3][randi() % 3]        # Rifle, UZI, or Machete between containers
		RoomType.CITY:
			return [0, 1, 2][randi() % 3]        # All ranged
		_:
			return 0  # Default RIFLE


func _random_enemy_behavior(room_type: int, enemy_index: int) -> int:
	# BehaviorMode: PATROL=0, GUARD=1
	if enemy_index == 0:
		return 1  # First enemy is always a guard
	return 0 if (randi() % 3 == 0) else 1  # 33% patrol, 67% guard


## ============================================================
## Player spawning
## ============================================================

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

	# Start in the first room, just right of the left wall
	var spawn_x: float = _room_offsets[0] + 80.0
	var spawn_y: float = ROOM_HEIGHT * 0.5
	player.position = Vector2(spawn_x, spawn_y)

	entities_node.add_child(player)
	print("[RoguelikeLevel] Player spawned at (%.0f, %.0f)" % [player.position.x, player.position.y])


## ============================================================
## Standard level setup
## ============================================================

func _setup_navigation() -> void:
	var nav_region: NavigationRegion2D = get_node_or_null("NavigationRegion2D")
	if nav_region == null:
		nav_region = NavigationRegion2D.new()
		nav_region.name = "NavigationRegion2D"
		var nav_poly := NavigationPolygon.new()
		nav_poly.parsed_geometry_type = NavigationPolygon.PARSED_GEOMETRY_STATIC_COLLIDERS
		nav_poly.parsed_collision_mask = 4
		nav_poly.source_geometry_mode = NavigationPolygon.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
		nav_poly.agent_radius = 24.0
		nav_region.navigation_polygon = nav_poly
		add_child(nav_region)


func _setup_player_tracking() -> void:
	_player = get_node_or_null("Entities/Player")
	if _player == null:
		return

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
	_initial_enemy_count = _enemies.size()
	_current_enemy_count = _initial_enemy_count
	print("[RoguelikeLevel] Tracking %d enemies" % _initial_enemy_count)


func _initialize_score_manager() -> void:
	var sm: Node = get_node_or_null("/root/ScoreManager")
	if sm == null:
		return
	sm.start_level(_initial_enemy_count)
	if _player and sm.has_method("set_player"):
		sm.set_player(_player)
	if not sm.combo_changed.is_connected(_on_combo_changed):
		sm.combo_changed.connect(_on_combo_changed)


func _setup_exit_zone() -> void:
	var exit_scene: PackedScene = load("res://scenes/objects/ExitZone.tscn")
	if exit_scene == null:
		push_warning("[RoguelikeLevel] ExitZone.tscn not found")
		return

	_exit_zone = exit_scene.instantiate()

	# Place in last room — near the right wall
	var last_idx: int   = _selected_types.size() - 1
	var exit_x: float   = _room_offsets[last_idx] + ROOM_WIDTH - 120.0
	var exit_y: float   = ROOM_HEIGHT * 0.5
	_exit_zone.position = Vector2(exit_x, exit_y)
	_exit_zone.zone_width  = 100.0
	_exit_zone.zone_height = 100.0

	if _exit_zone.has_signal("player_reached_exit"):
		_exit_zone.player_reached_exit.connect(_on_player_reached_exit)
	add_child(_exit_zone)

	print("[RoguelikeLevel] Exit zone at (%.0f, %.0f)" % [_exit_zone.position.x, _exit_zone.position.y])


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
		var pm: Node = pause_menu_scene.instantiate()
		canvas_layer.add_child(pm)

	# Enemy count
	_enemy_count_label = Label.new()
	_enemy_count_label.name = "EnemyCountLabel"
	_enemy_count_label.text = "Enemies: 0"
	_enemy_count_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_enemy_count_label.offset_left   = -200
	_enemy_count_label.offset_right  = -10
	_enemy_count_label.offset_top    = 10
	_enemy_count_label.offset_bottom = 40
	_enemy_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui.add_child(_enemy_count_label)

	# Ammo
	_ammo_label = Label.new()
	_ammo_label.name = "AmmoLabel"
	_ammo_label.text = "AMMO: -"
	_ammo_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_ammo_label.offset_left   = 10
	_ammo_label.offset_top    = 10
	_ammo_label.offset_right  = 300
	_ammo_label.offset_bottom = 40
	ui.add_child(_ammo_label)

	# Kills
	_kills_label = Label.new()
	_kills_label.name = "KillsLabel"
	_kills_label.text = "Kills: 0"
	_kills_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_kills_label.offset_left   = 10
	_kills_label.offset_top    = 45
	_kills_label.offset_right  = 200
	_kills_label.offset_bottom = 75
	ui.add_child(_kills_label)

	# Accuracy
	_accuracy_label = Label.new()
	_accuracy_label.name = "AccuracyLabel"
	_accuracy_label.text = "Accuracy: 0%"
	_accuracy_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_accuracy_label.offset_left   = 10
	_accuracy_label.offset_top    = 75
	_accuracy_label.offset_right  = 200
	_accuracy_label.offset_bottom = 105
	ui.add_child(_accuracy_label)

	# Magazines
	_magazines_label = Label.new()
	_magazines_label.name = "MagazinesLabel"
	_magazines_label.text = "MAGS: -"
	_magazines_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_magazines_label.offset_left   = 10
	_magazines_label.offset_top    = 105
	_magazines_label.offset_right  = 400
	_magazines_label.offset_bottom = 135
	ui.add_child(_magazines_label)

	# Mode label
	var names: Array[String] = []
	for t in _selected_types:
		names.append(ROOM_TYPE_NAMES.get(t, "?"))
	var mode_label := Label.new()
	mode_label.name  = "ModeLabel"
	mode_label.text  = "РОГАЛИК — %s" % " → ".join(names)
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	mode_label.offset_top    = 10
	mode_label.offset_bottom = 36
	mode_label.add_theme_font_size_override("font_size", 14)
	mode_label.add_theme_color_override("font_color", Color(0.6, 0.4, 1.0, 0.8))
	ui.add_child(mode_label)


func _setup_saturation_overlay() -> void:
	var cl: Node = get_node_or_null("CanvasLayer")
	if cl == null:
		return
	_saturation_overlay = ColorRect.new()
	_saturation_overlay.name  = "SaturationOverlay"
	_saturation_overlay.color = Color(1.0, 0.9, 0.3, 0.0)
	_saturation_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_saturation_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(_saturation_overlay)


func _find_player_weapon() -> Node:
	if _player == null:
		return null
	for n in ["MakarovPM", "Shotgun", "MiniUzi", "SilencedPistol", "SniperRifle", "AssaultRifle", "AKGL", "Revolver"]:
		var w: Node = _player.get_node_or_null(n)
		if w != null:
			return w
	return null


## ============================================================
## Wall / cover helpers
## ============================================================

func _create_wall(parent: Node, rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 4
	body.collision_mask  = 0
	body.position        = rect.get_center()

	var shape_node := CollisionShape2D.new()
	var shape      := RectangleShape2D.new()
	shape.size     = rect.size
	shape_node.shape = shape
	body.add_child(shape_node)

	var visual        := ColorRect.new()
	visual.color      = WALL_COLOR
	visual.size       = rect.size
	visual.position   = -rect.size / 2.0
	body.add_child(visual)

	parent.add_child(body)


func _create_cover(parent: Node, rect: Rect2) -> void:
	# Same as wall but slightly lighter colour (movable cover appearance)
	var body := StaticBody2D.new()
	body.collision_layer = 4
	body.collision_mask  = 0
	body.position        = rect.get_center()

	var shape_node := CollisionShape2D.new()
	var shape      := RectangleShape2D.new()
	shape.size     = rect.size
	shape_node.shape = shape
	body.add_child(shape_node)

	var visual     := ColorRect.new()
	visual.color   = Color(0.42, 0.38, 0.34, 1.0)   ## Brownish — crate/barrel colour
	visual.size    = rect.size
	visual.position = -rect.size / 2.0
	body.add_child(visual)

	parent.add_child(body)


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
		_level_cleared = true
		call_deferred("_activate_exit_zone")


func _on_enemy_died_with_info(is_ricochet: bool, is_penetration: bool) -> void:
	var sm: Node = get_node_or_null("/root/ScoreManager")
	if sm and sm.has_method("register_kill"):
		sm.register_kill(is_ricochet, is_penetration)


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


func _on_weapon_ammo_changed(current_mag: int, reserve: int) -> void:
	_update_ammo_label_magazine(current_mag, reserve)
	if current_mag <= 0 and reserve <= 0 and _current_enemy_count > 0 and not _game_over_shown:
		_show_game_over_message()


func _on_magazines_changed(mag_counts: Array) -> void:
	_update_magazines_label(mag_counts)


func _on_shell_count_changed(shell_count: int, _capacity: int) -> void:
	var reserve: int = 0
	if _player:
		var w: Node = _player.get_node_or_null("Shotgun")
		if w and w.get("ReserveAmmo") != null:
			reserve = w.ReserveAmmo
	_update_ammo_label_magazine(shell_count, reserve)


func _on_player_ammo_depleted() -> void:
	_broadcast_player_ammo_empty(true)
	if _player:
		var sp: Node = get_node_or_null("/root/SoundPropagation")
		if sp and sp.has_method("emit_player_empty_click"):
			sp.emit_player_empty_click(_player.global_position, _player)
	if _player and _player.has_method("get_current_ammo"):
		if _player.get_current_ammo() <= 0 and _current_enemy_count > 0 and not _game_over_shown:
			_show_game_over_message()


func _on_player_reload_started() -> void:
	_broadcast_player_reloading(true)
	if _player:
		var sp: Node = get_node_or_null("/root/SoundPropagation")
		if sp and sp.has_method("emit_player_reload"):
			sp.emit_player_reload(_player.global_position, _player)


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
	var ui: Node = get_node_or_null("CanvasLayer/UI")
	if ui == null:
		return

	if _combo_label == null:
		_combo_label = Label.new()
		_combo_label.name = "ComboLabel"
		_combo_label.text = ""
		_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_combo_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_combo_label.offset_left   = -200
		_combo_label.offset_right  = -10
		_combo_label.offset_top    = 80
		_combo_label.offset_bottom = 120
		_combo_label.add_theme_font_size_override("font_size", 28)
		_combo_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2, 1.0))
		_combo_label.visible = false
		ui.add_child(_combo_label)

	if combo > 0:
		_combo_label.text    = "x%d COMBO (+%d)" % [combo, points]
		_combo_label.visible = true
		_combo_label.modulate = Color.WHITE
		var tween := create_tween()
		tween.tween_property(_combo_label, "modulate", Color(1.0, 0.8, 0.2, 1.0), 0.1)
	else:
		_combo_label.visible = false


## ============================================================
## Level completion / score
## ============================================================

func _activate_exit_zone() -> void:
	if _exit_zone and _exit_zone.has_method("activate"):
		_exit_zone.activate()
		print("[RoguelikeLevel] Exit zone activated!")
	else:
		_complete_level_with_score()


func _complete_level_with_score() -> void:
	if _level_completed:
		return
	_level_completed = true
	_restore_loadout()

	var sm: Node = get_node_or_null("/root/ScoreManager")
	if sm and sm.has_method("complete_level"):
		var data: Dictionary = sm.complete_level()
		_show_score_screen(data)
	else:
		_show_victory_message()


func _show_score_screen(score_data: Dictionary) -> void:
	var ui: Node = get_node_or_null("CanvasLayer/UI")
	if ui == null:
		_show_victory_message()
		return

	var animated_script = load("res://scripts/ui/animated_score_screen.gd")
	if animated_script:
		var ss = animated_script.new()
		add_child(ss)
		ss.animation_completed.connect(_on_score_animation_completed)
		ss.show_animated_score(ui, score_data)
	else:
		_show_fallback_score_screen(ui, score_data)


func _on_score_animation_completed(container: VBoxContainer) -> void:
	_add_score_buttons(container)


func _add_score_buttons(container: VBoxContainer) -> void:
	var btn_restart := Button.new()
	btn_restart.text = "↻ Снова (Q)"
	btn_restart.custom_minimum_size = Vector2(200, 40)
	btn_restart.add_theme_font_size_override("font_size", 18)
	btn_restart.pressed.connect(_on_restart_pressed)
	container.add_child(btn_restart)

	var btn_menu := Button.new()
	btn_menu.text = "☰ Меню"
	btn_menu.custom_minimum_size = Vector2(200, 40)
	btn_menu.add_theme_font_size_override("font_size", 18)
	btn_menu.pressed.connect(_on_level_select_pressed)
	container.add_child(btn_menu)


func _show_fallback_score_screen(ui: Control, score_data: Dictionary) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bg)

	var container := VBoxContainer.new()
	container.set_anchors_preset(Control.PRESET_CENTER)
	container.offset_left   = -250
	container.offset_right  = 250
	container.offset_top    = -200
	container.offset_bottom = 200
	container.add_theme_constant_override("separation", 10)
	ui.add_child(container)

	var title := Label.new()
	title.text = "РОГАЛИК ПРОЙДЕН!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(0.6, 0.4, 1.0, 1.0))
	container.add_child(title)

	var total := Label.new()
	total.text = "ИТОГО: %d | РАНГ: %s" % [score_data.get("total_score", 0), score_data.get("rank", "?")]
	total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	total.add_theme_font_size_override("font_size", 28)
	total.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 1.0))
	container.add_child(total)

	_add_score_buttons(container)


func _show_victory_message() -> void:
	_score_shown = true
	var ui: Node = get_node_or_null("CanvasLayer/UI")
	if ui == null:
		return

	var lbl := Label.new()
	lbl.text = "РОГАЛИК ПРОЙДЕН!"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 48)
	lbl.add_theme_color_override("font_color", Color(0.6, 0.4, 1.0, 1.0))
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.offset_left   = -250
	lbl.offset_right  = 250
	lbl.offset_top    = -80
	lbl.offset_bottom = -30
	ui.add_child(lbl)


## ============================================================
## HUD helpers
## ============================================================

func _update_enemy_count_label() -> void:
	if _enemy_count_label:
		_enemy_count_label.text = "Враги: %d" % _current_enemy_count


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


func _update_magazines_label(mag_counts: Array) -> void:
	if _magazines_label == null:
		return
	var weapon: Node = _find_player_weapon()
	if weapon != null and weapon.get("UsesTubeMagazine") == true:
		_magazines_label.visible = false
		return
	_magazines_label.visible = true
	if mag_counts.is_empty():
		_magazines_label.text = "MAGS: -"
		return
	var parts: Array = []
	for i in range(mag_counts.size()):
		parts.append("[%d]" % mag_counts[i] if i == 0 else "%d" % mag_counts[i])
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
	var ui: Node = get_node_or_null("CanvasLayer/UI")
	if ui == null:
		return
	var lbl := Label.new()
	lbl.text = "YOU DIED"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 64)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.15, 0.15, 1.0))
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.offset_left   = -200
	lbl.offset_right  = 200
	lbl.offset_top    = -50
	lbl.offset_bottom = 50
	ui.add_child(lbl)


func _show_game_over_message() -> void:
	_game_over_shown = true
	var ui: Node = get_node_or_null("CanvasLayer/UI")
	if ui == null:
		return
	var lbl := Label.new()
	lbl.text = "OUT OF AMMO\n%d enemies remaining" % _current_enemy_count
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 48)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1.0))
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.offset_left   = -250
	lbl.offset_right  = 250
	lbl.offset_top    = -75
	lbl.offset_bottom = 75
	ui.add_child(lbl)


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
## Input: Q to restart
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
	_restore_loadout()
	var sl: Node = get_node_or_null("/root/SceneLoader")
	if sl and sl.has_method("load_level"):
		sl.load_level("res://scenes/levels/LabyrinthLevel.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/levels/LabyrinthLevel.tscn")


func _get_next_level_path() -> String:
	return "res://scenes/levels/RoguelikeLevel.tscn"
