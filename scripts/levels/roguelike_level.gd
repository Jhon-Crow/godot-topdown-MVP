extends Node2D
## Roguelike level — one room at a time, Binding of Isaac style.
##
## Issue #1061: добавить режим рогалика
## Issue #1166: treasure room after each level + multi-level progression.
##
## A "run" consists of multiple levels. Each level = 3–5 combat rooms.
## After clearing all combat rooms in a level the player enters a TREASURE ROOM
## (no enemies — just a pedestal with a free item). After collecting the item
## (or skipping via the exit) the NEXT LEVEL starts, with the same number of
## rooms but harder enemies (more health, better weapons).
##
## Flow per level:
##   1. Enter room → enemies appear → fight.
##   2. Kill all enemies → exit zone activates.
##   3. Player reaches exit → next combat room loads.
##   4. After clearing the LAST combat room → treasure room loads.
##   5. In treasure room: pedestal appears immediately (no enemies).
##      Player touches pedestal to collect item, then walks to exit.
##   6. Exit from treasure room → next level starts (difficulty +1).
##
## Run state is stored in GameManager so it survives scene reloads.
##
## Features:
## - Procedural room layouts by type
## - Player always starts with Makarov PM + Flashbang (armory ignored)
## - 3–4 enemies per room maximum (performance constraint)
## - No ReplayManager in roguelike (saves memory/CPU)
## - Difficulty scales each level: enemy health +1, harder weapon pool
## - Q restarts the whole run; Menu returns to LabyrinthLevel

## ============================================================
## Room types — each gets a distinct procedural layout
## ============================================================

enum RoomType {
	LABYRINTH,   ## Corridors / maze: horizontal + vertical interior walls
	BUILDING,    ## Indoor rooms: walled sub-rooms with doorways
	BEACH,       ## Open area: scattered obstacles (barrels, crates)
	DOCKS,       ## Container yard: long parallel walls (containers)
	CITY,        ## Urban: L-shaped cover blocks, car-like barriers
	SEWER        ## Underground: narrow corridor with pipe cover, minimal obstacles
}

## Room size options for procedural generation (Issue #1240: larger, more varied rooms)
## Three sizes: compact, standard, and large.
const ROOM_SIZE_OPTIONS: Array = [
	Vector2(1280.0, 720.0),   ## Compact — tight quarters, close combat
	Vector2(1600.0, 900.0),   ## Standard — moderate space, balanced
	Vector2(1920.0, 1080.0),  ## Large — open tactical arena, long sightlines
]

## Backwards-compatible aliases (used for fixed-size code paths like the tscn)
const ROOM_WIDTH:  float = 1280.0
const ROOM_HEIGHT: float = 720.0

## Enemy count limits per room (Issue #1240: more enemies for tactical pressure)
const ENEMIES_PER_ROOM_MIN: int = 3
const ENEMIES_PER_ROOM_MAX: int = 5

## Number of rooms per run (Issue #1451: many regular rooms so the exit is far from start)
const MIN_ROOMS: int = 7
const MAX_ROOMS: int = 10

## Minimum BFS distance from start to the exit room (Issue #1451: exit must be in a far room)
const EXIT_MIN_DISTANCE: int = 3

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
	RoomType.SEWER:     Color(0.12, 0.14, 0.12, 1.0),
}

const ROOM_TYPE_NAMES: Dictionary = {
	RoomType.LABYRINTH: "Лабиринт",
	RoomType.BUILDING:  "Здание",
	RoomType.BEACH:     "Пляж",
	RoomType.DOCKS:     "Доки",
	RoomType.CITY:      "Город",
	RoomType.SEWER:     "Канализация",
}

## Saturation flash on kill
const SATURATION_DURATION:  float = 0.15
const SATURATION_INTENSITY: float = 0.25

## ============================================================
## Treasure pedestal constants (Issue #1166)
## ============================================================

## Pedestal size (visual square)
const PEDESTAL_SIZE: float = 48.0

## Pedestal collision radius (touch-to-collect)
const PEDESTAL_RADIUS: float = 36.0

## Color of the pedestal base
const PEDESTAL_BASE_COLOR: Color = Color(0.55, 0.42, 0.20, 1.0)   ## Warm gold/wood
## Color of the item glow orb on the pedestal
const PEDESTAL_ITEM_GLOW:  Color = Color(0.90, 0.75, 0.20, 0.85)  ## Golden glow

## Passive active-item types — picking these up does NOT replace the current
## active item, it just adds their passive benefit (they always stay equipped
## alongside whatever the player already has).  All other types are "active"
## and replace the current one.
## NOTE: this list mirrors the passives in ActiveItemManager.ActiveItemType.
## Issue #1303 fix: corrected enum values (were off-by-4 for most entries).
const PASSIVE_ACTIVE_ITEM_TYPES: Array = [
	6,   # BREAKER_BULLETS
	9,   # LASER_SIGHT
	10,  # EXTENDED_MAGAZINE
	13,  # ARMORED_SKIN
	14,  # AUTO_RELOAD
	17,  # COMBAT_DISPOSITION
	21,  # GRENADE_BAG (Issue #1590)
]


## ============================================================
## Runtime state
## ============================================================

## Room type for THIS room instance (read from GameManager session)
var _room_type: int = RoomType.LABYRINTH
## 0-based index of the current room within the run
var _current_room_idx: int = 0
## Total rooms in this run
var _total_rooms: int = 3

## Dynamic room dimensions chosen at build time (Issue #1240)
var _room_w: float = 1280.0
var _room_h: float = 720.0
## Layout variant index chosen at build time (Issue #1240: multiple variants per type)
var _room_variant: int = 0

var _player: Node2D = null

## HUD refs
var _enemy_count_label:  Label = null
var _ammo_label:         Label = null
var _difficulty_label:   Label = null
var _magazines_label:    Label = null
var _combo_label:        Label = null
var _room_progress_label: Label = null
var _saturation_overlay: ColorRect = null

## Enemy tracking
var _enemies:               Array = []
var _initial_enemy_count:   int   = 0
var _current_enemy_count:   int   = 0

## State flags
var _room_cleared:    bool = false
var _game_over_shown: bool = false
var _score_shown:     bool = false
var _player_dead:     bool = false

var _exit_zone: Area2D = null

## Treasure pedestal (Issue #1166) — spawned when room is cleared.
var _treasure_pedestal: Area2D = null
## Item type stored on the current pedestal ("weapon" or an int ActiveItemType).
var _pedestal_item = null

## ── Branching map state (Issue #1399) ────────────────────────────────────
## Door zones for branching navigation (one per connected direction).
var _door_zones: Array = []  # Array of Area2D door zones

## Issue #1451: Physical door barriers that block doorway gaps during combat.
## In The Binding of Isaac, doors lock (close) when the player enters a room
## with enemies, and unlock (open) after all enemies are eliminated.
## Each entry is a StaticBody2D placed in a doorway gap.
var _door_barriers: Array = []  # Array of StaticBody2D barriers

## Directions: 0=North, 1=East, 2=South, 3=West
const DIR_NORTH: int = 0
const DIR_EAST:  int = 1
const DIR_SOUTH: int = 2
const DIR_WEST:  int = 3

## Grid offsets for each direction
const DIR_OFFSETS: Array = [
	Vector2i(0, -1),  # North
	Vector2i(1, 0),   # East
	Vector2i(0, 1),   # South
	Vector2i(-1, 0),  # West
]

## Door color constants (Issue #1399)
const DOOR_COLOR_NORMAL:   Color = Color(0.5, 0.5, 0.55, 0.7)   ## Grey — normal combat room
const DOOR_COLOR_TREASURE: Color = Color(1.0, 0.85, 0.2, 0.8)   ## Gold — treasure room
const DOOR_COLOR_EXIT:     Color = Color(1.0, 0.3, 0.2, 0.8)    ## Red — next level exit
const DOOR_COLOR_CLEARED:  Color = Color(0.3, 0.8, 0.3, 0.6)    ## Green — already cleared room
const DOOR_COLOR_START:    Color = Color(0.4, 0.6, 1.0, 0.7)    ## Blue — start room

## Minimap constants (Issue #1399)
const MINIMAP_CELL_SIZE: float = 18.0
const MINIMAP_GAP:       float = 4.0
const MINIMAP_MARGIN:    float = 12.0

## Doorway gap size in wall (pixels)
const DOOR_GAP: float = 120.0


## ============================================================
## _ready: entry point
## ============================================================

func _ready() -> void:
	randomize()

	if GameManager.roguelike_in_treasure_room:
		# ── Treasure room: no combat, just item pedestal + exit ──────────
		_current_room_idx = GameManager.roguelike_current_room
		_total_rooms       = GameManager.roguelike_total_rooms
		_room_type         = RoomType.BEACH  # Open layout suits a treasure room
		var _log_tr := "[RoguelikeLevel] TREASURE ROOM — Level %d" % GameManager.roguelike_current_level
		print(_log_tr)
		FileLogger.info(_log_tr)
		# Issue #1450: check if the treasure room item has already been collected.
		# - If collected: no pedestal, empty room (item is gone for good).
		# - If not collected: spawn pedestal — _spawn_treasure_pedestal() restores
		#   the same item if the player previously entered and left without picking up.
		var _tr_map_idx: int = GameManager.roguelike_current_map_room
		var _tr_already_collected: bool = false
		if GameManager.roguelike_room_map.size() > 0 and _tr_map_idx >= 0 and _tr_map_idx < GameManager.roguelike_room_map.size():
			_tr_already_collected = GameManager.roguelike_room_map[_tr_map_idx].get("treasure_collected", false)
			# Mark the room map entry as cleared (for minimap/door-colour purposes).
			GameManager.roguelike_room_map[_tr_map_idx]["cleared"] = true
		_build_room_scene_treasure()
		_spawn_player()
		_setup_navigation()
		_setup_player_tracking()
		_setup_exit_zone()
		_setup_debug_ui()
		_setup_saturation_overlay()
		_setup_debug_ui_treasure()
		_setup_minimap()
		if GameManager:
			GameManager.stats_updated.connect(_update_debug_ui)
		if not _tr_already_collected:
			# Spawn pedestal immediately (not deferred) so it is visible from the first frame.
			# The monitoring flag is still set deferred so body_entered fires for existing overlaps.
			# _spawn_treasure_pedestal() will restore the same item if the player previously
			# entered this room and left without picking it up (Issue #1450).
			_spawn_treasure_pedestal()
		else:
			var _log_tr_rev := "[RoguelikeLevel] Treasure room item collected — skipping pedestal (Issue #1450)"
			print(_log_tr_rev)
			FileLogger.info(_log_tr_rev)
		call_deferred("_activate_exit_zone")
		var _log_tr2 := "[RoguelikeLevel] Treasure room ready — pedestal spawned: %s" % str(_treasure_pedestal != null)
		print(_log_tr2)
		FileLogger.info(_log_tr2)
		return

	# ── Normal combat room ────────────────────────────────────
	if not GameManager.roguelike_active:
		_start_new_run()
	else:
		_continue_run()

	# Load session into local vars for convenience
	_current_room_idx = GameManager.roguelike_current_room
	_total_rooms       = GameManager.roguelike_total_rooms

	# Issue #1399: Get room type from the map if available
	var map_room_idx: int = GameManager.roguelike_current_map_room
	if GameManager.roguelike_room_map.size() > 0 and map_room_idx >= 0 and map_room_idx < GameManager.roguelike_room_map.size():
		_room_type = GameManager.roguelike_room_map[map_room_idx]["room_type"]
	elif _current_room_idx < GameManager.roguelike_room_types.size():
		_room_type = GameManager.roguelike_room_types[_current_room_idx]
	else:
		_room_type = RoomType.LABYRINTH

	print("[RoguelikeLevel] Level %d — Map Room %d — type: %s" % [
		GameManager.roguelike_current_level,
		map_room_idx,
		ROOM_TYPE_NAMES.get(_room_type, "?")])

	_force_roguelike_loadout()

	# Issue #1399: Determine if this room should have enemies
	var is_start_room: bool = false
	var is_cleared_revisit: bool = false
	var is_treasure_map_room: bool = false
	if GameManager.roguelike_room_map.size() > 0 and map_room_idx >= 0 and map_room_idx < GameManager.roguelike_room_map.size():
		var map_room: Dictionary = GameManager.roguelike_room_map[map_room_idx]
		is_start_room = (map_room["map_room_type"] == "start")
		is_cleared_revisit = map_room["cleared"]
		is_treasure_map_room = (map_room["map_room_type"] == "treasure")

	# Treasure rooms on the map use the treasure room scene builder
	if is_treasure_map_room:
		GameManager.roguelike_in_treasure_room = true
		_room_type = RoomType.BEACH
		# Issue #1450: check if the treasure item has already been collected.
		# - Collected: skip pedestal entirely.
		# - Not collected: spawn pedestal — _spawn_treasure_pedestal() restores the same
		#   item if the player previously entered and left without picking it up.
		var treasure_already_collected: bool = false
		if map_room_idx >= 0 and map_room_idx < GameManager.roguelike_room_map.size():
			treasure_already_collected = GameManager.roguelike_room_map[map_room_idx].get("treasure_collected", false)
			# Mark cleared for minimap/door-colour purposes.
			GameManager.roguelike_room_map[map_room_idx]["cleared"] = true
		_build_room_scene_treasure()
		_spawn_player()
		_setup_navigation()
		_setup_player_tracking()
		_setup_exit_zone()
		_setup_debug_ui()
		_setup_saturation_overlay()
		_setup_debug_ui_treasure()
		_setup_minimap()
		if GameManager:
			GameManager.stats_updated.connect(_update_debug_ui)
		if not treasure_already_collected:
			_spawn_treasure_pedestal()
		else:
			var _log_tr_rev := "[RoguelikeLevel] Treasure map room item collected — skipping pedestal (Issue #1450)"
			print(_log_tr_rev)
			FileLogger.info(_log_tr_rev)
		call_deferred("_activate_exit_zone")
		print("[RoguelikeLevel] Treasure map room ready (already_collected=%s)" % str(treasure_already_collected))
		return

	# Issue #1450: Start rooms and cleared-revisit rooms must NOT spawn enemies.
	# _build_room_scene() calls _spawn_enemies_in_room() internally, so the
	# cleared/start check MUST happen before calling it.
	if is_start_room or is_cleared_revisit:
		_build_room_scene_no_enemies()
		_spawn_player()
		_setup_navigation()
		_setup_player_tracking()
		_room_cleared = true
		_setup_debug_ui()
		_setup_saturation_overlay()
		_setup_exit_zone()
		_setup_minimap()
		call_deferred("_activate_exit_zone")
		if GameManager:
			GameManager.stats_updated.connect(_update_debug_ui)
		var _log_revisit := "[RoguelikeLevel] %s room ready — no enemies, doors open (Issue #1450)" % ("Start" if is_start_room else "Revisited")
		print(_log_revisit)
		FileLogger.info(_log_revisit)
		return

	_build_room_scene()
	_spawn_player()
	_setup_navigation()
	_setup_player_tracking()
	_setup_enemy_tracking()
	_setup_debug_ui()
	_setup_saturation_overlay()
	_update_enemy_count_label()
	_initialize_score_manager()
	_setup_exit_zone()
	_setup_minimap()
	# Intentionally skip ReplayManager — reduces memory and CPU overhead

	# Issue #1451: Lock doors (create physical barriers) in uncleared combat rooms.
	# In The Binding of Isaac, doors shut when the player enters a room with enemies
	# and only open after all enemies are eliminated.
	var room_node: Node2D = get_node_or_null("Room")
	if room_node:
		_create_door_barriers(room_node)

	if GameManager:
		GameManager.enemy_killed.connect(_on_game_manager_enemy_killed)
		GameManager.stats_updated.connect(_update_debug_ui)

	var _log_room_ready := "[RoguelikeLevel] Room ready — %d enemies" % _initial_enemy_count
	print(_log_room_ready)
	FileLogger.info(_log_room_ready)


func _process(_delta: float) -> void:
	var sm: Node = get_node_or_null("/root/ScoreManager")
	if sm and sm.has_method("update_enemy_positions"):
		sm.update_enemy_positions(_enemies)


## ============================================================
## Run lifecycle
## ============================================================

func _start_new_run() -> void:
	## First room of a new run: choose seed, room count, and room type sequence.
	var run_seed: int = randi()
	seed(run_seed)

	var all_types: Array = [
		RoomType.LABYRINTH,
		RoomType.BUILDING,
		RoomType.BEACH,
		RoomType.DOCKS,
		RoomType.CITY,
		RoomType.SEWER,
	]
	# Fisher-Yates shuffle
	for i in range(all_types.size() - 1, 0, -1):
		var j: int = randi_range(0, i)
		var tmp = all_types[i]
		all_types[i] = all_types[j]
		all_types[j] = tmp

	# Issue #1451: Do NOT cap count by all_types.size() — with many rooms (7-10),
	# room types cycle/repeat. The type pool is used modulo its size in _generate_room_map.
	var count: int = randi_range(MIN_ROOMS, MAX_ROOMS)

	GameManager.roguelike_active           = true
	GameManager.roguelike_current_room     = 0
	GameManager.roguelike_total_rooms      = count
	GameManager.roguelike_room_types       = all_types.slice(0, min(count, all_types.size()))
	GameManager.roguelike_run_seed         = run_seed
	GameManager.roguelike_total_kills      = 0
	GameManager.roguelike_total_shots      = 0
	GameManager.roguelike_total_hits       = 0
	GameManager.roguelike_current_level    = 1
	GameManager.roguelike_in_treasure_room = false
	# Save current weapon so we can restore it when the run ends
	GameManager.roguelike_saved_weapon = GameManager.get_selected_weapon()
	# Clear carried-weapon tracker — player always starts a fresh run with PM
	GameManager.roguelike_run_weapon = ""

	# Issue #1399: Generate branching room map
	GameManager.roguelike_room_map = _generate_room_map(count, all_types)
	GameManager.roguelike_current_map_room = 0  # Start room
	GameManager.roguelike_visited_rooms = [0]
	GameManager.roguelike_room_map[0]["visited"] = true
	GameManager.roguelike_target_room = -1

	var names: Array = []
	for t in GameManager.roguelike_room_types:
		names.append(ROOM_TYPE_NAMES.get(t, "?"))
	var _log_new_run := "[RoguelikeLevel] New run — seed=%d, rooms: %s" % [run_seed, str(names)]
	print(_log_new_run)
	FileLogger.info(_log_new_run)


func _continue_run() -> void:
	## Resuming mid-run: restore the seed offset so room geometry varies per room.
	## Issue #1399: use map room index for seed so each room on the map is unique.
	var map_room_idx: int = GameManager.roguelike_current_map_room
	seed(GameManager.roguelike_run_seed + map_room_idx)

	# Mark current map room as visited
	if map_room_idx >= 0 and map_room_idx < GameManager.roguelike_room_map.size():
		GameManager.roguelike_room_map[map_room_idx]["visited"] = true
		if not (map_room_idx in GameManager.roguelike_visited_rooms):
			GameManager.roguelike_visited_rooms.append(map_room_idx)

	print("[RoguelikeLevel] Continuing run at map room %d (room %d/%d)" % [
		map_room_idx,
		GameManager.roguelike_current_room + 1,
		GameManager.roguelike_total_rooms])


## ============================================================
## Branching room map generation (Issue #1399)
## ============================================================

## Generate an Isaac-style grid map with branching paths for one level.
## Places combat rooms via BFS expansion from a central start room,
## then adds a treasure room and an exit room on dead-end branches.
func _generate_room_map(room_count: int, room_types_pool: Array) -> Array:
	var grid: Dictionary = {}  # Vector2i → room index
	var rooms: Array = []

	# Start room at center
	var start_pos := Vector2i(3, 3)
	rooms.append({
		"grid_pos": start_pos,
		"room_type": room_types_pool[0] if room_types_pool.size() > 0 else RoomType.LABYRINTH,
		"connections": [],
		"map_room_type": "start",
		"cleared": false,
		"visited": false,
	})
	grid[start_pos] = 0

	# BFS expansion — add combat rooms branching outward
	var frontier: Array = [0]  # Room indices to expand from
	var combat_rooms_needed: int = room_count  # Total combat rooms (excluding start)
	var combat_rooms_placed: int = 0
	var type_idx: int = 1  # Index into room_types_pool (0 is used by start)

	while combat_rooms_placed < combat_rooms_needed and frontier.size() > 0:
		# Pick a random frontier room to expand from
		var fi: int = randi() % frontier.size()
		var parent_idx: int = frontier[fi]
		var parent_pos: Vector2i = rooms[parent_idx]["grid_pos"]

		# Shuffle directions
		var dirs: Array = [0, 1, 2, 3]
		for i in range(3, 0, -1):
			var j: int = randi_range(0, i)
			var tmp: int = dirs[i]
			dirs[i] = dirs[j]
			dirs[j] = tmp

		var expanded: bool = false
		for d in dirs:
			if combat_rooms_placed >= combat_rooms_needed:
				break
			var new_pos: Vector2i = parent_pos + DIR_OFFSETS[d]
			# Stay within grid bounds (0..6)
			if new_pos.x < 0 or new_pos.x > 6 or new_pos.y < 0 or new_pos.y > 6:
				continue
			# Cell must be empty
			if grid.has(new_pos):
				continue
			# Isaac branching constraint: don't place if it would have 2+ existing neighbors
			var neighbor_count: int = 0
			for nd in range(4):
				var adj: Vector2i = new_pos + DIR_OFFSETS[nd]
				if grid.has(adj):
					neighbor_count += 1
			if neighbor_count > 1:
				continue

			# Place the room
			var new_idx: int = rooms.size()
			var rtype: int = room_types_pool[type_idx % room_types_pool.size()] if type_idx < room_types_pool.size() else room_types_pool[randi() % room_types_pool.size()]
			type_idx += 1
			rooms.append({
				"grid_pos": new_pos,
				"room_type": rtype,
				"connections": [],
				"map_room_type": "combat",
				"cleared": false,
				"visited": false,
			})
			grid[new_pos] = new_idx

			# Connect parent ↔ child
			rooms[parent_idx]["connections"].append(new_idx)
			rooms[new_idx]["connections"].append(parent_idx)

			frontier.append(new_idx)
			combat_rooms_placed += 1
			expanded = true

		# If this room can't expand anymore, remove from frontier
		if not expanded:
			frontier.remove_at(fi)

	# Find dead-end rooms (exactly 1 connection, not start) for special rooms
	var dead_ends: Array = []
	for i in range(rooms.size()):
		if rooms[i]["map_room_type"] == "start":
			continue
		if rooms[i]["connections"].size() == 1:
			dead_ends.append(i)

	# Issue #1451: Sort dead ends by BFS path distance from start (farthest first).
	# Uses graph distance (number of rooms to traverse) instead of Euclidean distance,
	# matching The Binding of Isaac's boss room placement algorithm. This ensures the
	# exit is always at the end of the longest path through the dungeon.
	var bfs_dist: Dictionary = _bfs_distances(rooms, 0)
	dead_ends.sort_custom(func(a, b):
		var da: int = bfs_dist.get(a, 0)
		var db: int = bfs_dist.get(b, 0)
		return da > db
	)

	# Issue #1451: Place exit room (red) on a dead end that is at least EXIT_MIN_DISTANCE
	# rooms away from start. This prevents the exit from being directly adjacent to the
	# start room. Always use the farthest qualifying dead end; fall back to the overall
	# farthest dead end if none meets the threshold (e.g. very small map).
	if dead_ends.size() > 0:
		var exit_idx: int = dead_ends[0]  # Default: farthest dead end overall
		for de in dead_ends:
			if bfs_dist.get(de, 0) >= EXIT_MIN_DISTANCE:
				exit_idx = de
				break
		rooms[exit_idx]["map_room_type"] = "exit"
		dead_ends.erase(exit_idx)
		var exit_dist: int = bfs_dist.get(exit_idx, 0)
		var _log_exit_placed := "[RoguelikeLevel] Exit placed at room %d (BFS distance=%d from start)" % [exit_idx, exit_dist]
		print(_log_exit_placed)
		FileLogger.info(_log_exit_placed)

	# Place treasure room (gold) on the next farthest dead end
	if dead_ends.size() > 0:
		var treasure_idx: int = dead_ends[0]
		rooms[treasure_idx]["map_room_type"] = "treasure"
		# Issue #1450: persist treasure state — item offered and whether it was collected.
		rooms[treasure_idx]["treasure_item"] = null
		rooms[treasure_idx]["treasure_collected"] = false
		dead_ends.remove_at(0)
	else:
		# No dead end left — add a treasure room branching off the exit's parent
		# or just tag the second-to-last room
		if rooms.size() > 2:
			# Find a combat room that isn't the exit to become treasure
			for i in range(rooms.size() - 1, 0, -1):
				if rooms[i]["map_room_type"] == "combat":
					rooms[i]["map_room_type"] = "treasure"
					# Issue #1450: persist treasure state.
					rooms[i]["treasure_item"] = null
					rooms[i]["treasure_collected"] = false
					break

	var _log_map_generated := "[RoguelikeLevel] Map generated: %d rooms" % rooms.size()
	print(_log_map_generated)
	FileLogger.info(_log_map_generated)
	for i in range(rooms.size()):
		var r: Dictionary = rooms[i]
		print("  Room %d: pos=%s type=%s map_type=%s connections=%s" % [
			i, str(r["grid_pos"]), ROOM_TYPE_NAMES.get(r["room_type"], "?"),
			r["map_room_type"], str(r["connections"])])

	return rooms


## Issue #1451: Compute BFS shortest-path distances from a source room to all other rooms.
## Returns a Dictionary mapping room index → distance (int). Rooms unreachable from
## the source will not appear in the result.
static func _bfs_distances(rooms: Array, source: int) -> Dictionary:
	var dist: Dictionary = {source: 0}
	var queue: Array = [source]
	var head: int = 0
	while head < queue.size():
		var current: int = queue[head]
		head += 1
		for neighbor in rooms[current]["connections"]:
			if not dist.has(neighbor):
				dist[neighbor] = dist[current] + 1
				queue.append(neighbor)
	return dist


## Get the direction from room A to room B (returns DIR_NORTH..DIR_WEST or -1).
func _get_direction_between(room_a_idx: int, room_b_idx: int) -> int:
	var rooms: Array = GameManager.roguelike_room_map
	if room_a_idx < 0 or room_a_idx >= rooms.size():
		return -1
	if room_b_idx < 0 or room_b_idx >= rooms.size():
		return -1
	var diff: Vector2i = rooms[room_b_idx]["grid_pos"] - rooms[room_a_idx]["grid_pos"]
	for d in range(4):
		if DIR_OFFSETS[d] == diff:
			return d
	return -1


## Get the opposite direction.
func _opposite_dir(d: int) -> int:
	return (d + 2) % 4


## Get the door color for a connected room based on its map_room_type.
func _get_door_color(connected_room_idx: int) -> Color:
	var rooms: Array = GameManager.roguelike_room_map
	if connected_room_idx < 0 or connected_room_idx >= rooms.size():
		return DOOR_COLOR_NORMAL
	var room: Dictionary = rooms[connected_room_idx]
	if room["cleared"]:
		return DOOR_COLOR_CLEARED
	match room["map_room_type"]:
		"treasure":
			return DOOR_COLOR_TREASURE
		"exit":
			return DOOR_COLOR_EXIT
		"start":
			return DOOR_COLOR_START
		_:
			return DOOR_COLOR_NORMAL


## Get the door label for a connected room.
func _get_door_label(connected_room_idx: int) -> String:
	var rooms: Array = GameManager.roguelike_room_map
	if connected_room_idx < 0 or connected_room_idx >= rooms.size():
		return "?"
	match rooms[connected_room_idx]["map_room_type"]:
		"treasure":
			return "СОКРОВ."
		"exit":
			return "ВЫХОД"
		"start":
			return "СТАРТ"
		_:
			if rooms[connected_room_idx]["cleared"]:
				return "ПРОЙД."
			return "КОМНАТА"


## ============================================================
## Loadout override — PM + flashbang, no armory
## ============================================================

func _force_roguelike_loadout() -> void:
	if GameManager:
		# Issue #1166 Bug 2 fix: preserve weapon picked in a treasure room across level transitions.
		# roguelike_run_weapon is set when the player picks a weapon from the pedestal.
		# On the very first room of a new run it is empty, so we default to Makarov PM.
		# On subsequent level starts it carries the weapon from the last treasure room.
		var weapon_to_equip: String = GameManager.roguelike_run_weapon if GameManager.roguelike_run_weapon != "" else "makarov_pm"
		GameManager.set_selected_weapon(weapon_to_equip)
		print("[RoguelikeLevel] Loadout weapon: %s (roguelike_run_weapon='%s')" % [weapon_to_equip, GameManager.roguelike_run_weapon])
	var grenade_manager: Node = get_node_or_null("/root/GrenadeManager")
	if grenade_manager:
		if grenade_manager.get("current_grenade_type") != null:
			grenade_manager.current_grenade_type = 0  # FLASHBANG
	# Issue #1166: player must start roguelike with no active/passive items on the FIRST room only.
	# On level 1 room 1 (roguelike_current_level == 1 and roguelike_current_room == 0) clear items.
	if GameManager.roguelike_current_level == 1 and GameManager.roguelike_current_room == 0:
		if ActiveItemManager and ActiveItemManager.current_active_item != 0:
			ActiveItemManager.current_active_item = 0  # NONE — direct assignment, no restart
			ActiveItemManager.active_item_changed.emit(0)
			print("[RoguelikeLevel] Active item cleared for roguelike start")
		# Issue #1303: clear accumulated passive items at the start of a new roguelike run.
		if ActiveItemManager and ActiveItemManager.has_method("clear_passive_items"):
			ActiveItemManager.clear_passive_items()
	print("[RoguelikeLevel] Loadout forced: %s + flashbang" % GameManager.get_selected_weapon())


func _restore_loadout() -> void:
	if GameManager and GameManager.roguelike_saved_weapon != "":
		GameManager.set_selected_weapon(GameManager.roguelike_saved_weapon)


## ============================================================
## Room construction — only ONE room per scene instance
## ============================================================

func _build_room_scene() -> void:
	# Issue #1240: pick a random room size and layout variant each time.
	var size_idx: int = randi() % ROOM_SIZE_OPTIONS.size()
	var chosen_size: Vector2 = ROOM_SIZE_OPTIONS[size_idx]
	_room_w = chosen_size.x
	_room_h = chosen_size.y
	_room_variant = randi() % 3  # 0, 1, or 2 — three layout variants per type
	print("[RoguelikeLevel] Room size: %.0f×%.0f, variant: %d" % [_room_w, _room_h, _room_variant])

	# Background
	var bg := ColorRect.new()
	bg.name  = "WorldBackground"
	bg.position = Vector2(-200, -200)
	bg.size     = Vector2(_room_w + 400, _room_h + 400)
	bg.color    = BG_COLOR
	add_child(bg)

	var room_container := Node2D.new()
	room_container.name = "Room"
	room_container.position = Vector2.ZERO
	add_child(room_container)

	_build_room(room_container)
	_spawn_enemies_in_room(room_container)


## Issue #1450: Build room geometry (walls, floor, doors) WITHOUT spawning enemies.
## Used for start rooms and cleared-revisit rooms so the layout is correct but
## no new enemies appear on re-entry.
func _build_room_scene_no_enemies() -> void:
	var size_idx: int = randi() % ROOM_SIZE_OPTIONS.size()
	var chosen_size: Vector2 = ROOM_SIZE_OPTIONS[size_idx]
	_room_w = chosen_size.x
	_room_h = chosen_size.y
	_room_variant = randi() % 3
	print("[RoguelikeLevel] Room size: %.0f×%.0f, variant: %d (no enemies)" % [_room_w, _room_h, _room_variant])

	var bg := ColorRect.new()
	bg.name  = "WorldBackground"
	bg.position = Vector2(-200, -200)
	bg.size     = Vector2(_room_w + 400, _room_h + 400)
	bg.color    = BG_COLOR
	add_child(bg)

	var room_container := Node2D.new()
	room_container.name = "Room"
	room_container.position = Vector2.ZERO
	add_child(room_container)

	_build_room(room_container)
	# Intentionally skip _spawn_enemies_in_room — room is already cleared.


func _build_room(parent: Node) -> void:
	var floor_color: Color = ROOM_FLOOR_COLORS.get(_room_type, FLOOR_COLOR)
	var floor_rect := ColorRect.new()
	floor_rect.position = Vector2(0, 0)
	floor_rect.size     = Vector2(_room_w, _room_h)
	floor_rect.color    = floor_color
	parent.add_child(floor_rect)

	# Boundary walls — closed on all sides (single room, no corridors)
	_build_room_boundary_closed(parent)

	# Interior layout by type — Issue #1240: each type now has 3 variants
	match _room_type:
		RoomType.LABYRINTH:
			_build_labyrinth_interior(parent)
		RoomType.BUILDING:
			_build_building_interior(parent)
		RoomType.BEACH:
			_build_beach_interior(parent)
		RoomType.DOCKS:
			_build_docks_interior(parent)
		RoomType.CITY:
			_build_city_interior(parent)
		RoomType.SEWER:
			_build_sewer_interior(parent)

	print("[RoguelikeLevel] Room built: type=%s variant=%d size=%.0f×%.0f" % [
		ROOM_TYPE_NAMES.get(_room_type, "?"), _room_variant, _room_w, _room_h])


## Fully-enclosed boundary walls (no corridor openings — single room).
## Issue #1399: Now creates gaps (doorways) on sides where the current room
## has connections to other rooms on the branching map.
func _build_room_boundary_closed(room_node: Node2D) -> void:
	var w: float = _room_w
	var h: float = _room_h
	var t: float = 24.0  ## Wall thickness

	# Determine which directions have doors (from the branching map)
	var door_dirs: Array = _get_current_room_door_directions()

	# Top wall (North)
	if DIR_NORTH in door_dirs:
		var gap_center: float = w * 0.5
		_create_wall(room_node, Rect2(0, 0, gap_center - DOOR_GAP * 0.5, t))
		_create_wall(room_node, Rect2(gap_center + DOOR_GAP * 0.5, 0, w - gap_center - DOOR_GAP * 0.5, t))
	else:
		_create_wall(room_node, Rect2(0, 0, w, t))

	# Bottom wall (South)
	if DIR_SOUTH in door_dirs:
		var gap_center: float = w * 0.5
		_create_wall(room_node, Rect2(0, h - t, gap_center - DOOR_GAP * 0.5, t))
		_create_wall(room_node, Rect2(gap_center + DOOR_GAP * 0.5, h - t, w - gap_center - DOOR_GAP * 0.5, t))
	else:
		_create_wall(room_node, Rect2(0, h - t, w, t))

	# Left wall (West)
	if DIR_WEST in door_dirs:
		var gap_center: float = h * 0.5
		_create_wall(room_node, Rect2(0, 0, t, gap_center - DOOR_GAP * 0.5))
		_create_wall(room_node, Rect2(0, gap_center + DOOR_GAP * 0.5, t, h - gap_center - DOOR_GAP * 0.5))
	else:
		_create_wall(room_node, Rect2(0, 0, t, h))

	# Right wall (East)
	if DIR_EAST in door_dirs:
		var gap_center: float = h * 0.5
		_create_wall(room_node, Rect2(w - t, 0, t, gap_center - DOOR_GAP * 0.5))
		_create_wall(room_node, Rect2(w - t, gap_center + DOOR_GAP * 0.5, t, h - gap_center - DOOR_GAP * 0.5))
	else:
		_create_wall(room_node, Rect2(w - t, 0, t, h))


## Issue #1451: Create physical barriers (StaticBody2D) in all doorway gaps.
## Called when the player enters an uncleared combat room — doors "lock" like
## in The Binding of Isaac. Barriers are removed when the room is cleared.
func _create_door_barriers(room_node: Node2D) -> void:
	var w: float = _room_w
	var h: float = _room_h
	var t: float = 24.0  ## Wall thickness (must match _build_room_boundary_closed)
	var door_dirs: Array = _get_current_room_door_directions()

	for d in door_dirs:
		var rect: Rect2
		match d:
			DIR_NORTH:
				var gap_center: float = w * 0.5
				rect = Rect2(gap_center - DOOR_GAP * 0.5, 0, DOOR_GAP, t)
			DIR_SOUTH:
				var gap_center: float = w * 0.5
				rect = Rect2(gap_center - DOOR_GAP * 0.5, h - t, DOOR_GAP, t)
			DIR_WEST:
				var gap_center: float = h * 0.5
				rect = Rect2(0, gap_center - DOOR_GAP * 0.5, t, DOOR_GAP)
			DIR_EAST:
				var gap_center: float = h * 0.5
				rect = Rect2(w - t, gap_center - DOOR_GAP * 0.5, t, DOOR_GAP)

		# Create a StaticBody2D barrier matching the doorway gap
		var barrier := StaticBody2D.new()
		barrier.name = "DoorBarrier_%d" % d
		barrier.position = rect.position + rect.size / 2.0
		barrier.collision_layer = 4  # Obstacles layer (same as walls)
		barrier.collision_mask  = 0

		var shape_node := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		shape_node.shape = shape
		barrier.add_child(shape_node)

		# Visual: red-tinted wall to indicate locked door
		var visual := ColorRect.new()
		visual.color = Color(0.55, 0.15, 0.10, 0.9)
		visual.size = rect.size
		visual.position = -rect.size / 2.0
		barrier.add_child(visual)

		room_node.add_child(barrier)
		_door_barriers.append(barrier)

	if _door_barriers.size() > 0:
		var _log_barriers_created := "[RoguelikeLevel] %d door barriers created — room locked" % _door_barriers.size()
		print(_log_barriers_created)
		FileLogger.info(_log_barriers_created)


## Issue #1451: Remove all door barriers (unlock doors) after room is cleared.
## Plays a brief fade-out animation before freeing the barrier nodes.
func _remove_door_barriers() -> void:
	for barrier in _door_barriers:
		if is_instance_valid(barrier):
			# Disable collision immediately so player can walk through
			barrier.collision_layer = 0
			# Fade out the visual
			var visual: ColorRect = null
			for child in barrier.get_children():
				if child is ColorRect:
					visual = child
					break
			if visual:
				var tween := create_tween()
				tween.tween_property(visual, "color:a", 0.0, 0.3)
				tween.tween_callback(barrier.queue_free)
			else:
				barrier.queue_free()
	_door_barriers = []
	var _log_barriers_removed := "[RoguelikeLevel] Door barriers removed — room unlocked"
	print(_log_barriers_removed)
	FileLogger.info(_log_barriers_removed)


## Get directions that have doors in the current map room.
func _get_current_room_door_directions() -> Array:
	var directions: Array = []
	var rooms: Array = GameManager.roguelike_room_map
	var current_idx: int = GameManager.roguelike_current_map_room
	if rooms.size() == 0 or current_idx < 0 or current_idx >= rooms.size():
		return directions
	var current_room: Dictionary = rooms[current_idx]
	for conn_idx in current_room["connections"]:
		var d: int = _get_direction_between(current_idx, conn_idx)
		if d >= 0:
			directions.append(d)
	return directions


## ─── Labyrinth: horizontal and vertical divider walls ───────────────────────
## Issue #1240: 3 variants for more variety.
func _build_labyrinth_interior(room_node: Node2D) -> void:
	var w: float = _room_w
	var h: float = _room_h
	var opening: float = 140.0
	match _room_variant:
		0:
			# Classic maze: two horizontal dividers + one vertical divider with gap
			_create_wall(room_node, Rect2(60, h * 0.33, w * 0.55, 20))
			_create_wall(room_node, Rect2(w * 0.45, h * 0.66, w * 0.55 - 30, 20))
			_create_wall(room_node, Rect2(w * 0.5 - 10, 60, 20, h * 0.35))
			_create_wall(room_node, Rect2(w * 0.5 - 10, h * 0.35 + opening, 20, h * 0.30))
			_create_wall(room_node, Rect2(120, h * 0.14, 140, 20))
			_create_wall(room_node, Rect2(120, h * 0.14, 20, 80))
			_create_wall(room_node, Rect2(w - 260, h * 0.78, 140, 20))
			_create_wall(room_node, Rect2(w - 280 + 140, h * 0.72, 20, 80))
		1:
			# T-junction maze: central horizontal wall + two vertical stubs creating 3 corridors
			_create_wall(room_node, Rect2(60, h * 0.50, w * 0.35, 20))
			_create_wall(room_node, Rect2(w * 0.65, h * 0.50, w * 0.35 - 60, 20))
			# Upper channel wall
			_create_wall(room_node, Rect2(w * 0.35, 60, 20, h * 0.28))
			_create_wall(room_node, Rect2(w * 0.65, 60, 20, h * 0.28))
			# Lower channel wall
			_create_wall(room_node, Rect2(w * 0.35, h * 0.72, 20, h * 0.28))
			_create_wall(room_node, Rect2(w * 0.65, h * 0.72, 20, h * 0.28))
			# Short cross-pieces for cover
			_create_wall(room_node, Rect2(w * 0.20, h * 0.22, 80, 20))
			_create_wall(room_node, Rect2(w * 0.75, h * 0.72, 80, 20))
		2:
			# Spiral-ish: one long corridor divider + two alcove stubs + a central pillar
			_create_wall(room_node, Rect2(60, h * 0.40, w * 0.60, 20))
			_create_wall(room_node, Rect2(w * 0.40, h * 0.60, w * 0.60 - 60, 20))
			# Left alcove
			_create_wall(room_node, Rect2(60, h * 0.40, 20, h * 0.32))
			# Right alcove
			_create_wall(room_node, Rect2(w - 80, h * 0.30, 20, h * 0.32))
			# Central pillar box
			_create_wall(room_node, Rect2(w * 0.47, h * 0.40, 20, h * 0.20))
			_create_wall(room_node, Rect2(w * 0.47, h * 0.40, w * 0.08, 20))
			_create_wall(room_node, Rect2(w * 0.47, h * 0.60, w * 0.08, 20))


## ─── Building: walled sub-rooms with doorways ───────────────────────────────
## Issue #1240: 3 variants.
func _build_building_interior(room_node: Node2D) -> void:
	var w: float = _room_w
	var h: float = _room_h
	var opening: float = 100.0
	match _room_variant:
		0:
			# Classic: vertical divider with doorway, top-right alcove, bottom-left alcove
			_create_wall(room_node, Rect2(w * 0.42, 60, 20, h * 0.35))
			_create_wall(room_node, Rect2(w * 0.42, 60 + h * 0.35 + opening, 20, h - (60 + h * 0.35 + opening) - 60))
			_create_wall(room_node, Rect2(w * 0.60, 60, w * 0.22, 20))
			_create_wall(room_node, Rect2(w * 0.82 - 20, 60, 20, h * 0.28))
			_create_wall(room_node, Rect2(60, h * 0.68, w * 0.22, 20))
			_create_wall(room_node, Rect2(60, h * 0.54, 20, h * 0.14 + 20))
			_create_cover(room_node, Rect2(w * 0.18, h * 0.42, 60, 60))
			_create_cover(room_node, Rect2(w * 0.68, h * 0.55, 80, 20))
		1:
			# Three-room layout: top corridor + bottom corridor divided by horizontal wall
			_create_wall(room_node, Rect2(60, h * 0.38, w * 0.38, 20))
			_create_wall(room_node, Rect2(w * 0.38 + opening, h * 0.38, w * 0.62 - opening - 60, 20))
			_create_wall(room_node, Rect2(60, h * 0.62, w * 0.38, 20))
			_create_wall(room_node, Rect2(w * 0.38 + opening, h * 0.62, w * 0.62 - opening - 60, 20))
			# Two vertical sub-dividers creating three lanes
			_create_wall(room_node, Rect2(w * 0.38, 60, 20, h * 0.38))
			_create_wall(room_node, Rect2(w * 0.62, h * 0.62, 20, h * 0.38))
			# Cover objects
			_create_cover(room_node, Rect2(w * 0.22, h * 0.48, 60, 24))
			_create_cover(room_node, Rect2(w * 0.72, h * 0.48, 60, 24))
		2:
			# Fortress: outer ring of rooms with central open courtyard
			# Left wing
			_create_wall(room_node, Rect2(w * 0.26, 60, 20, h * 0.35))
			_create_wall(room_node, Rect2(w * 0.26, h * 0.35 + opening, 20, h * 0.30))
			# Right wing
			_create_wall(room_node, Rect2(w * 0.74, 60, 20, h * 0.35))
			_create_wall(room_node, Rect2(w * 0.74, h * 0.35 + opening, 20, h * 0.30))
			# Top bar connecting wings
			_create_wall(room_node, Rect2(w * 0.26, h * 0.24, w * 0.14, 20))
			_create_wall(room_node, Rect2(w * 0.60, h * 0.24, w * 0.14, 20))
			# Bottom bar
			_create_wall(room_node, Rect2(w * 0.26, h * 0.76, w * 0.14, 20))
			_create_wall(room_node, Rect2(w * 0.60, h * 0.76, w * 0.14, 20))
			# Central cover pair
			_create_cover(room_node, Rect2(w * 0.46, h * 0.40, 24, 80))
			_create_cover(room_node, Rect2(w * 0.54, h * 0.40, 24, 80))


## ─── Beach: open field with scattered obstacles ─────────────────────────────
## Issue #1240: 3 variants with more obstacles and tactical cover.
func _build_beach_interior(room_node: Node2D) -> void:
	var w: float = _room_w
	var h: float = _room_h
	match _room_variant:
		0:
			# Scattered crates and barrels (original, slightly expanded)
			var positions: Array[Vector2] = [
				Vector2(w * 0.18, h * 0.25),
				Vector2(w * 0.18, h * 0.65),
				Vector2(w * 0.40, h * 0.38),
				Vector2(w * 0.40, h * 0.58),
				Vector2(w * 0.62, h * 0.22),
				Vector2(w * 0.62, h * 0.72),
				Vector2(w * 0.80, h * 0.44),
				Vector2(w * 0.28, h * 0.50),
			]
			for pos in positions:
				var sz: float = 44.0 if (int(pos.x) % 2 == 0) else 32.0
				_create_cover(room_node, Rect2(pos.x - sz * 0.5, pos.y - sz * 0.5, sz, sz))
			_create_cover(room_node, Rect2(w * 0.55, h * 0.5 - 10, 120, 20))
		1:
			# Beachhead: two diagonal sandbag lines with gaps — flanking possible
			_create_cover(room_node, Rect2(w * 0.22, h * 0.18, 100, 20))
			_create_cover(room_node, Rect2(w * 0.34, h * 0.30, 100, 20))
			_create_cover(room_node, Rect2(w * 0.46, h * 0.42, 100, 20))
			# Second diagonal line (offset, creates crossfire)
			_create_cover(room_node, Rect2(w * 0.30, h * 0.72, 100, 20))
			_create_cover(room_node, Rect2(w * 0.44, h * 0.60, 100, 20))
			_create_cover(room_node, Rect2(w * 0.58, h * 0.48, 100, 20))
			# Far cover
			_create_cover(room_node, Rect2(w * 0.72, h * 0.28, 56, 56))
			_create_cover(room_node, Rect2(w * 0.78, h * 0.68, 56, 56))
		2:
			# Debris field: irregular cluster in middle + lone outpost covers
			for i in range(5):
				var angle: float = i * TAU / 5.0
				var cx: float = w * 0.50 + cos(angle) * w * 0.12
				var cy: float = h * 0.50 + sin(angle) * h * 0.16
				_create_cover(room_node, Rect2(cx - 24, cy - 24, 48, 48))
			# Outpost covers near corners
			_create_cover(room_node, Rect2(w * 0.14, h * 0.20, 36, 60))
			_create_cover(room_node, Rect2(w * 0.80, h * 0.20, 36, 60))
			_create_cover(room_node, Rect2(w * 0.14, h * 0.70, 36, 60))
			_create_cover(room_node, Rect2(w * 0.80, h * 0.70, 36, 60))
			# Central chokepoint wall
			_create_cover(room_node, Rect2(w * 0.42, h * 0.46, 20, 80))


## ─── Docks: parallel container walls ────────────────────────────────────────
## Issue #1240: 3 variants — different container configurations.
func _build_docks_interior(room_node: Node2D) -> void:
	var w: float = _room_w
	var h: float = _room_h
	match _room_variant:
		0:
			# Classic: three pairs of offset container rows
			for row in range(3):
				var y: float = h * (0.22 + row * 0.24)
				_create_wall(room_node, Rect2(80, y, w * 0.36, 22))
				_create_wall(room_node, Rect2(w * 0.52, y + 22, w * 0.36, 22))
			_create_wall(room_node, Rect2(80, h * 0.22, 22, h * 0.22))
			_create_wall(room_node, Rect2(w - 102, h * 0.46, 22, h * 0.22))
		1:
			# Staggered containers: alternating left-leaning / right-leaning
			for row in range(4):
				var y: float = h * (0.18 + row * 0.18)
				if row % 2 == 0:
					_create_wall(room_node, Rect2(80, y, w * 0.32, 22))
					_create_wall(room_node, Rect2(w * 0.56, y, w * 0.32, 22))
				else:
					_create_wall(room_node, Rect2(w * 0.12, y, w * 0.32, 22))
					_create_wall(room_node, Rect2(w * 0.60, y, w * 0.30, 22))
			# A lone container stack at centre-right
			_create_wall(room_node, Rect2(w * 0.48, h * 0.36, 22, h * 0.28))
		2:
			# Warehouse: long corridors + cross-walls creating choke corners
			_create_wall(room_node, Rect2(80, h * 0.30, w * 0.70, 22))
			_create_wall(room_node, Rect2(w * 0.30, h * 0.70, w * 0.70 - 80, 22))
			# Vertical cross-walls sealing off corners
			_create_wall(room_node, Rect2(80, h * 0.30, 22, h * 0.20))
			_create_wall(room_node, Rect2(w - 102, h * 0.50, 22, h * 0.20))
			# Mid-room gap-cover pair
			_create_cover(room_node, Rect2(w * 0.44, h * 0.46, 24, 80))
			_create_cover(room_node, Rect2(w * 0.56, h * 0.46, 24, 80))


## ─── City: L-shaped cover blocks and barriers ───────────────────────────────
## Issue #1240: 3 variants — different urban layout configurations.
func _build_city_interior(room_node: Node2D) -> void:
	var w: float = _room_w
	var h: float = _room_h
	match _room_variant:
		0:
			# Classic: two L-shapes + two car barriers + bollard cluster
			_create_cover(room_node, Rect2(w * 0.14, h * 0.20, 100, 20))
			_create_cover(room_node, Rect2(w * 0.14, h * 0.20, 20, 80))
			_create_cover(room_node, Rect2(w * 0.72, h * 0.68, 100, 20))
			_create_cover(room_node, Rect2(w * 0.72 + 80, h * 0.60, 20, 80))
			_create_cover(room_node, Rect2(w * 0.34, h * 0.42, 160, 32))
			_create_cover(room_node, Rect2(w * 0.60, h * 0.30, 160, 32))
			for i in range(3):
				_create_cover(room_node, Rect2(w * 0.46 + i * 36, h * 0.60, 24, 24))
		1:
			# Crossroads: four corner covers + two parallel road barriers in the centre
			# Corner barricades
			_create_cover(room_node, Rect2(w * 0.12, h * 0.18, 80, 20))
			_create_cover(room_node, Rect2(w * 0.76, h * 0.18, 80, 20))
			_create_cover(room_node, Rect2(w * 0.12, h * 0.72, 80, 20))
			_create_cover(room_node, Rect2(w * 0.76, h * 0.72, 80, 20))
			# Central road dividers
			_create_cover(room_node, Rect2(w * 0.38, h * 0.35, 180, 24))
			_create_cover(room_node, Rect2(w * 0.38, h * 0.60, 180, 24))
			# Lone pillar at centre
			_create_cover(room_node, Rect2(w * 0.49, h * 0.46, 32, 48))
		2:
			# Alley: walled corridor down the middle + flanking cover on both sides
			# Left flank cover
			_create_cover(room_node, Rect2(w * 0.16, h * 0.28, 28, 100))
			_create_cover(room_node, Rect2(w * 0.16, h * 0.60, 28, 80))
			# Right flank cover
			_create_cover(room_node, Rect2(w * 0.76, h * 0.28, 28, 100))
			_create_cover(room_node, Rect2(w * 0.76, h * 0.60, 28, 80))
			# Central alley walls (two long pieces with gap — the alley)
			_create_wall(room_node, Rect2(w * 0.36, 60, 20, h * 0.33))
			_create_wall(room_node, Rect2(w * 0.36, h * 0.33 + 120, 20, h * 0.33))
			_create_wall(room_node, Rect2(w * 0.64, 60, 20, h * 0.33))
			_create_wall(room_node, Rect2(w * 0.64, h * 0.33 + 120, 20, h * 0.33))


func _build_sewer_interior(room_node: Node2D) -> void:
	var w: float = _room_w
	var h: float = _room_h
	match _room_variant:
		0:
			# Central corridor with pipe covers on sides
			_create_wall(room_node, Rect2(w * 0.30, 60, 20, h * 0.35))
			_create_wall(room_node, Rect2(w * 0.30, h * 0.55, 20, h * 0.35))
			_create_wall(room_node, Rect2(w * 0.70, 60, 20, h * 0.35))
			_create_wall(room_node, Rect2(w * 0.70, h * 0.55, 20, h * 0.35))
			_create_cover(room_node, Rect2(w * 0.45, h * 0.30, 60, 24))
			_create_cover(room_node, Rect2(w * 0.45, h * 0.65, 60, 24))
			_create_cover(room_node, Rect2(w * 0.15, h * 0.50, 40, 40))
			_create_cover(room_node, Rect2(w * 0.80, h * 0.50, 40, 40))
		1:
			# Fork layout: corridor splits into left and right paths
			_create_wall(room_node, Rect2(w * 0.48, h * 0.30, 20, h * 0.40))
			_create_wall(room_node, Rect2(w * 0.25, h * 0.30, w * 0.23, 20))
			_create_wall(room_node, Rect2(w * 0.52, h * 0.30, w * 0.23, 20))
			_create_cover(room_node, Rect2(w * 0.35, h * 0.50, 60, 24))
			_create_cover(room_node, Rect2(w * 0.60, h * 0.50, 60, 24))
			_create_cover(room_node, Rect2(w * 0.48, h * 0.15, 24, 60))
		2:
			# Tight tunnel: narrow passages with debris
			_create_wall(room_node, Rect2(w * 0.22, 60, 20, h * 0.40))
			_create_wall(room_node, Rect2(w * 0.22, h * 0.60, 20, h * 0.30))
			_create_wall(room_node, Rect2(w * 0.78, 60, 20, h * 0.30))
			_create_wall(room_node, Rect2(w * 0.78, h * 0.50, 20, h * 0.40))
			_create_cover(room_node, Rect2(w * 0.40, h * 0.25, 40, 40))
			_create_cover(room_node, Rect2(w * 0.56, h * 0.55, 40, 40))
			_create_cover(room_node, Rect2(w * 0.48, h * 0.80, 60, 24))


## ============================================================
## Enemy spawning
## ============================================================

## ============================================================
## Special enemy archetypes (Issue #1297)
## ============================================================

## Special enemy types that can appear in roguelike rooms.
## Each value maps to a distinct archetype with unique traits.
enum SpecialEnemyType {
	NONE,         ## Regular enemy — no special traits
	MACHINE_GUNNER,  ## PKM belt-fed; suppresses corridors; falls back to PM
	GRENADIER,       ## Throws grenades; always 2 HP
	ARMORED,         ## Extra HP from Armored Skin passive
	FORCE_FIELD,     ## Protected by force field; harder to finish off
	SNIPER,          ## ASVK sniper rifle; long-range precision
}

## Minimum level at which special enemies can appear.
const SPECIAL_ENEMY_MIN_LEVEL: int = 2

## Base chance (0–1) to have a special enemy in a room on the minimum level.
## Increases by SPECIAL_ENEMY_CHANCE_PER_LEVEL each additional level.
const SPECIAL_ENEMY_BASE_CHANCE: float = 0.40
const SPECIAL_ENEMY_CHANCE_PER_LEVEL: float = 0.10

## Maximum spawn chance regardless of level (capped at this value).
const SPECIAL_ENEMY_MAX_CHANCE: float = 0.80


## Returns the SpecialEnemyType to spawn for the last enemy slot, or NONE.
## Called once per room; uses current roguelike level and a random roll.
func _pick_special_enemy_type(current_level: int) -> int:
	if current_level < SPECIAL_ENEMY_MIN_LEVEL:
		return SpecialEnemyType.NONE
	var chance: float = clampf(
		SPECIAL_ENEMY_BASE_CHANCE + (current_level - SPECIAL_ENEMY_MIN_LEVEL) * SPECIAL_ENEMY_CHANCE_PER_LEVEL,
		0.0, SPECIAL_ENEMY_MAX_CHANCE)
	if randf() > chance:
		return SpecialEnemyType.NONE
	# Pool of archetypes available; extends with level
	var pool: Array = [
		SpecialEnemyType.MACHINE_GUNNER,
		SpecialEnemyType.GRENADIER,
		SpecialEnemyType.ARMORED,
	]
	if current_level >= 3:
		pool.append(SpecialEnemyType.FORCE_FIELD)
	if current_level >= 4:
		pool.append(SpecialEnemyType.SNIPER)
	return pool[randi() % pool.size()]


## Applies special-enemy traits to an already-instantiated enemy node.
## The enemy is promoted to the chosen archetype in-place (no new scene needed).
func _apply_special_enemy(enemy: Node, special_type: int, level_bonus: int) -> void:
	match special_type:
		SpecialEnemyType.MACHINE_GUNNER:
			enemy.weapon_type = 6  # WeaponType.MACHINE_GUN
			enemy.min_health  = 2 + level_bonus
			enemy.max_health  = 3 + level_bonus
			enemy.behavior_mode = 1  # GUARD — holds position, suppresses
			print("[RoguelikeLevel] Special: Machine Gunner spawned")
		SpecialEnemyType.GRENADIER:
			enemy.is_grenadier = true
			enemy.weapon_type  = 0  # RIFLE (grenadier primary)
			# is_grenadier forces max_health=2 inside enemy.gd; we only touch min/max here
			# to ensure the rng range in enemy.gd stays consistent.
			enemy.min_health = 2 + level_bonus
			enemy.max_health = 2 + level_bonus
			print("[RoguelikeLevel] Special: Grenadier spawned")
		SpecialEnemyType.ARMORED:
			enemy.has_armored_skin = true
			enemy.min_health = 2 + level_bonus
			enemy.max_health = 3 + level_bonus
			print("[RoguelikeLevel] Special: Armored enemy spawned")
		SpecialEnemyType.FORCE_FIELD:
			enemy.has_force_field = true
			enemy.min_health = 1 + level_bonus
			enemy.max_health = 2 + level_bonus
			print("[RoguelikeLevel] Special: Force Field enemy spawned")
		SpecialEnemyType.SNIPER:
			enemy.weapon_type = 7  # WeaponType.SNIPER_RIFLE
			enemy.min_health  = 1 + level_bonus
			enemy.max_health  = 2 + level_bonus
			enemy.behavior_mode = 1  # GUARD — holds a firing position
			print("[RoguelikeLevel] Special: Sniper spawned")


func _spawn_enemies_in_room(room_node: Node2D) -> void:
	var enemy_scene: PackedScene = load("res://scenes/objects/Enemy.tscn")
	if enemy_scene == null:
		push_error("[RoguelikeLevel] Enemy.tscn not found!")
		return

	var positions: Array[Vector2] = _get_enemy_positions(_room_type)
	# More enemies each level (cap at positions.size() and an absolute max of 8, Issue #1240)
	var level_enemy_max: int = min(ENEMIES_PER_ROOM_MAX + (GameManager.roguelike_current_level - 1), 8)
	var count: int = randi_range(ENEMIES_PER_ROOM_MIN, min(level_enemy_max, positions.size()))

	# Shuffle positions
	for i in range(positions.size() - 1, 0, -1):
		var j: int = randi_range(0, i)
		var tmp: Vector2 = positions[i]
		positions[i] = positions[j]
		positions[j] = tmp

	# Issue #1297: decide whether to include a special enemy in this room.
	var special_type: int = _pick_special_enemy_type(GameManager.roguelike_current_level)
	# The special enemy occupies the last slot (index count - 1) so regular enemies come first.
	var special_slot: int = count - 1 if special_type != SpecialEnemyType.NONE else -1

	for i in range(count):
		var enemy: Node = enemy_scene.instantiate()
		enemy.name = "Enemy_%d" % i
		enemy.position = positions[i]
		enemy.weapon_type   = _random_enemy_weapon(_room_type)
		enemy.behavior_mode = _random_enemy_behavior(i)
		if enemy.behavior_mode == 0:  # PATROL
			# Issue #1240: varied patrol routes — choose from several patterns
			var patrol_patterns: Array = [
				[Vector2(100, 0), Vector2(-100, 0)],             # Horizontal
				[Vector2(0, 80), Vector2(0, -80)],              # Vertical
				[Vector2(120, 0), Vector2(-120, 0)],             # Wide horizontal
				[Vector2(80, 60), Vector2(-80, -60)],            # Diagonal
				[Vector2(100, 0), Vector2(0, 80), Vector2(-100, 0)],  # L-shaped
			]
			enemy.patrol_offsets = patrol_patterns[randi() % patrol_patterns.size()]
		# Difficulty scaling: each level adds 1 to enemy health pool (Issue #1166)
		var level_bonus: int = max(0, GameManager.roguelike_current_level - 1)
		enemy.min_health = 1 + level_bonus
		enemy.max_health = 2 + level_bonus
		# Must destroy on death so they don't respawn (Issue #1061 round 5).
		enemy.destroy_on_death = true
		# Issue #1297: apply special archetype to the designated slot.
		if i == special_slot:
			_apply_special_enemy(enemy, special_type, level_bonus)
		room_node.add_child(enemy)

		_enemies.append(enemy)
		if enemy.has_signal("died"):
			enemy.died.connect(_on_enemy_died)
		if enemy.has_signal("died_with_info"):
			enemy.died_with_info.connect(_on_enemy_died_with_info)
		if enemy.has_signal("hit"):
			enemy.hit.connect(_on_enemy_hit)
		if enemy.has_signal("became_pacifist"):
			enemy.became_pacifist.connect(_on_enemy_became_pacifist.bind(enemy))


func _get_enemy_positions(room_type: int) -> Array[Vector2]:
	# Issue #1240: use dynamic room dimensions; return 8 positions for more enemies.
	var w: float = _room_w
	var h: float = _room_h
	match room_type:
		RoomType.LABYRINTH:
			return [
				Vector2(w * 0.20, h * 0.22),
				Vector2(w * 0.20, h * 0.76),
				Vector2(w * 0.60, h * 0.22),
				Vector2(w * 0.60, h * 0.76),
				Vector2(w * 0.80, h * 0.50),
				Vector2(w * 0.38, h * 0.50),
				Vector2(w * 0.70, h * 0.38),
				Vector2(w * 0.70, h * 0.62),
			]
		RoomType.BUILDING:
			return [
				Vector2(w * 0.22, h * 0.32),
				Vector2(w * 0.22, h * 0.68),
				Vector2(w * 0.70, h * 0.30),
				Vector2(w * 0.70, h * 0.70),
				Vector2(w * 0.50, h * 0.50),
				Vector2(w * 0.34, h * 0.50),
				Vector2(w * 0.84, h * 0.50),
				Vector2(w * 0.56, h * 0.22),
			]
		RoomType.BEACH:
			return [
				Vector2(w * 0.30, h * 0.30),
				Vector2(w * 0.30, h * 0.68),
				Vector2(w * 0.55, h * 0.50),
				Vector2(w * 0.75, h * 0.30),
				Vector2(w * 0.75, h * 0.68),
				Vector2(w * 0.46, h * 0.22),
				Vector2(w * 0.46, h * 0.78),
				Vector2(w * 0.85, h * 0.50),
			]
		RoomType.DOCKS:
			return [
				Vector2(w * 0.18, h * 0.50),
				Vector2(w * 0.40, h * 0.30),
				Vector2(w * 0.40, h * 0.70),
				Vector2(w * 0.65, h * 0.50),
				Vector2(w * 0.82, h * 0.50),
				Vector2(w * 0.28, h * 0.50),
				Vector2(w * 0.56, h * 0.30),
				Vector2(w * 0.56, h * 0.70),
			]
		RoomType.CITY:
			return [
				Vector2(w * 0.22, h * 0.50),
				Vector2(w * 0.46, h * 0.30),
				Vector2(w * 0.46, h * 0.70),
				Vector2(w * 0.72, h * 0.50),
				Vector2(w * 0.86, h * 0.22),
				Vector2(w * 0.86, h * 0.78),
				Vector2(w * 0.60, h * 0.50),
				Vector2(w * 0.30, h * 0.22),
			]
		RoomType.SEWER:
			return [
				Vector2(w * 0.50, h * 0.20),
				Vector2(w * 0.50, h * 0.40),
				Vector2(w * 0.50, h * 0.60),
				Vector2(w * 0.50, h * 0.80),
				Vector2(w * 0.30, h * 0.30),
				Vector2(w * 0.70, h * 0.50),
				Vector2(w * 0.30, h * 0.70),
				Vector2(w * 0.70, h * 0.70),
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
			return [0, 2][randi() % 2]
		RoomType.BUILDING:
			return [0, 1, 2][randi() % 3]
		RoomType.BEACH:
			return [0, 1][randi() % 2]
		RoomType.DOCKS:
			return [0, 2, 3][randi() % 3]
		RoomType.CITY:
			return [0, 1, 2][randi() % 3]
		RoomType.SEWER:
			return [0, 1][randi() % 2]
		_:
			return 0


func _random_enemy_behavior(enemy_index: int) -> int:
	# BehaviorMode: PATROL=0, GUARD=1
	# Issue #1240: more balanced mix — 50% patrol, 50% guard (was 33/67).
	# First enemy is still a guard to ensure the room is immediately threatening.
	if enemy_index == 0:
		return 1  # First enemy is always a guard
	return randi() % 2  # 50% patrol, 50% guard


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

	# Remove any pre-existing Player node to prevent duplicates
	var existing_entities: Node = get_node_or_null("Entities")
	if existing_entities:
		var existing_player: Node = existing_entities.get_node_or_null("Player")
		if existing_player:
			print("[RoguelikeLevel] Removing pre-existing Player node to prevent duplicate spawn")
			existing_player.free()

	var entities_node: Node2D = existing_entities
	if entities_node == null:
		entities_node = Node2D.new()
		entities_node.name = "Entities"
		add_child(entities_node)

	var player: Node2D = player_scene.instantiate()
	player.name = "Player"

	# Issue #1399: Spawn player near the door they entered from.
	# Use roguelike_source_room to know exactly which room the player came from.
	var spawn_pos := Vector2(80.0, _room_h * 0.5)  # Default: left-centre
	var source_idx: int = GameManager.roguelike_source_room
	var current_idx: int = GameManager.roguelike_current_map_room
	if source_idx >= 0 and GameManager.roguelike_room_map.size() > 0:
		var rooms: Array = GameManager.roguelike_room_map
		if current_idx >= 0 and current_idx < rooms.size() and source_idx < rooms.size():
			var arrival_dir: int = _get_direction_between(current_idx, source_idx)
			if arrival_dir >= 0:
				# Spawn near the wall of the arrival direction (the door they came through)
				match arrival_dir:
					DIR_NORTH:
						spawn_pos = Vector2(_room_w * 0.5, 80.0)
					DIR_SOUTH:
						spawn_pos = Vector2(_room_w * 0.5, _room_h - 80.0)
					DIR_EAST:
						spawn_pos = Vector2(_room_w - 80.0, _room_h * 0.5)
					DIR_WEST:
						spawn_pos = Vector2(80.0, _room_h * 0.5)

	player.position = spawn_pos
	entities_node.add_child(player)
	print("[RoguelikeLevel] Player spawned at (%.0f, %.0f)" % [player.position.x, player.position.y])


## ============================================================
## Standard level setup
## ============================================================

## Setup and bake the navigation mesh for enemy pathfinding.
## Issue #1216: Parse source geometry (walls on collision layer 4) then bake
## synchronously so walls are excluded from the walkable area.
func _setup_navigation() -> void:
	var nav_region: NavigationRegion2D = get_node_or_null("NavigationRegion2D")
	if nav_region == null:
		nav_region = NavigationRegion2D.new()
		nav_region.name = "NavigationRegion2D"
		var nav_poly := NavigationPolygon.new()
		nav_poly.parsed_geometry_type = NavigationPolygon.PARSED_GEOMETRY_STATIC_COLLIDERS
		nav_poly.parsed_collision_mask = 4
		nav_poly.source_geometry_mode  = NavigationPolygon.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
		nav_poly.agent_radius = 24.0
		nav_region.navigation_polygon = nav_poly
		add_child(nav_region)

	var nav_poly: NavigationPolygon = nav_region.navigation_polygon
	if nav_poly == null:
		push_warning("[RoguelikeLevel] NavigationPolygon not found - enemy pathfinding will be limited")
		return
	# Issue #1289: wait for physics frame so CollisionShape2D nodes are registered
	# with PhysicsServer2D before parsing source geometry for navmesh carving.
	await get_tree().physics_frame

	# Define the walkable floor area outline for the room.
	var floor_outline: PackedVector2Array = PackedVector2Array([
		Vector2(0, 0),
		Vector2(ROOM_WIDTH, 0),
		Vector2(ROOM_WIDTH, ROOM_HEIGHT),
		Vector2(0, ROOM_HEIGHT)
	])
	nav_poly.clear()
	nav_poly.add_outline(floor_outline)

	print("[RoguelikeLevel] Baking navigation mesh...")
	var source_geometry: NavigationMeshSourceGeometryData2D = NavigationMeshSourceGeometryData2D.new()
	NavigationServer2D.parse_source_geometry_data(nav_poly, source_geometry, self)
	NavigationServer2D.bake_from_source_geometry_data(nav_poly, source_geometry)
	# Issue #1289: push updated polygon back into the NavigationServer's live map.
	# Without this reassignment, agents still use the pre-bake (uncarved) navmesh.
	nav_region.navigation_polygon = nav_poly
	nav_region.emit_signal("bake_finished")
	print("[RoguelikeLevel] Navigation mesh baked successfully")


func _setup_player_tracking() -> void:
	_player = get_node_or_null("Entities/Player")
	if _player == null:
		return

	if GameManager:
		GameManager.set_player(_player)

	# Remove camera limits so the camera follows freely within the room
	var camera: Camera2D = _player.get_node_or_null("Camera2D")
	if camera:
		camera.limit_left   = -10000000
		camera.limit_top    = -10000000
		camera.limit_right  =  10000000
		camera.limit_bottom =  10000000

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


## Reconnect weapon signal handlers to the current player weapon.
## Called after a mid-game weapon swap (e.g. pedestal pickup in Issue #1323) so the
## ammo/shot counter UI stays in sync with the new weapon node.
func _reconnect_weapon_signals() -> void:
	var weapon: Node = _find_player_weapon()
	if weapon == null:
		return
	if weapon.has_signal("AmmoChanged") and not weapon.AmmoChanged.is_connected(_on_weapon_ammo_changed):
		weapon.AmmoChanged.connect(_on_weapon_ammo_changed)
	if weapon.has_signal("MagazinesChanged") and not weapon.MagazinesChanged.is_connected(_on_magazines_changed):
		weapon.MagazinesChanged.connect(_on_magazines_changed)
	if weapon.has_signal("Fired") and not weapon.Fired.is_connected(_on_shot_fired):
		weapon.Fired.connect(_on_shot_fired)
	if weapon.has_signal("ShellCountChanged") and not weapon.ShellCountChanged.is_connected(_on_shell_count_changed):
		weapon.ShellCountChanged.connect(_on_shell_count_changed)
	if weapon.get("CurrentAmmo") != null and weapon.get("ReserveAmmo") != null:
		_update_ammo_label_magazine(weapon.CurrentAmmo, weapon.ReserveAmmo)
	if weapon.has_method("GetMagazineAmmoCounts"):
		var mag_counts: Array = weapon.GetMagazineAmmoCounts()
		_update_magazines_label(mag_counts)
	print("[RoguelikeLevel] Reconnected weapon signals to %s" % weapon.name)


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
	# Issue #1399: Create colored door zones for each connection on the branching map.
	# Falls back to single east-side exit if no map data.
	var rooms: Array = GameManager.roguelike_room_map
	var current_idx: int = GameManager.roguelike_current_map_room
	if rooms.size() > 0 and current_idx >= 0 and current_idx < rooms.size():
		var current_room: Dictionary = rooms[current_idx]
		for conn_idx in current_room["connections"]:
			var d: int = _get_direction_between(current_idx, conn_idx)
			if d < 0:
				continue
			_create_door_zone(d, conn_idx)
		print("[RoguelikeLevel] Created %d door zones for map room %d" % [_door_zones.size(), current_idx])
	else:
		# Fallback: single exit on the right wall (legacy behavior)
		var exit_scene: PackedScene = load("res://scenes/objects/ExitZone.tscn")
		if exit_scene == null:
			push_warning("[RoguelikeLevel] ExitZone.tscn not found")
			return
		_exit_zone = exit_scene.instantiate()
		var exit_x: float = _room_w - 120.0
		var exit_y: float = _room_h * 0.5
		_exit_zone.position    = Vector2(exit_x, exit_y)
		_exit_zone.zone_width  = 100.0
		_exit_zone.zone_height = 100.0
		if _exit_zone.has_signal("player_reached_exit"):
			_exit_zone.player_reached_exit.connect(_on_player_reached_exit)
		add_child(_exit_zone)
		print("[RoguelikeLevel] Fallback exit zone at (%.0f, %.0f)" % [_exit_zone.position.x, _exit_zone.position.y])


## Create a colored door zone at the given wall direction leading to target_room_idx.
func _create_door_zone(direction: int, target_room_idx: int) -> void:
	var door_color: Color = _get_door_color(target_room_idx)
	var door_label_text: String = _get_door_label(target_room_idx)

	# Calculate door position at the wall gap
	var door_pos := Vector2.ZERO
	var door_w: float = 80.0
	var door_h: float = 80.0
	match direction:
		DIR_NORTH:
			door_pos = Vector2(_room_w * 0.5, 12.0)
			door_w = DOOR_GAP - 20.0
			door_h = 40.0
		DIR_SOUTH:
			door_pos = Vector2(_room_w * 0.5, _room_h - 12.0)
			door_w = DOOR_GAP - 20.0
			door_h = 40.0
		DIR_EAST:
			door_pos = Vector2(_room_w - 12.0, _room_h * 0.5)
			door_w = 40.0
			door_h = DOOR_GAP - 20.0
		DIR_WEST:
			door_pos = Vector2(12.0, _room_h * 0.5)
			door_w = 40.0
			door_h = DOOR_GAP - 20.0

	var door_zone := Area2D.new()
	door_zone.name = "DoorZone_%d_%d" % [direction, target_room_idx]
	door_zone.position = door_pos
	door_zone.collision_layer = 0
	door_zone.collision_mask = 1  # Detect player

	# Collision shape
	var coll := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(door_w, door_h)
	coll.shape = shape
	door_zone.add_child(coll)

	# Visual: colored glow rect
	var glow := ColorRect.new()
	glow.color = Color(door_color.r, door_color.g, door_color.b, 0.3)
	glow.size = Vector2(door_w + 12, door_h + 12)
	glow.position = -Vector2(door_w * 0.5 + 6, door_h * 0.5 + 6)
	door_zone.add_child(glow)

	# Visual: inner solid rect
	var inner := ColorRect.new()
	inner.color = door_color
	inner.size = Vector2(door_w, door_h)
	inner.position = -Vector2(door_w * 0.5, door_h * 0.5)
	door_zone.add_child(inner)

	# Door label
	var lbl := Label.new()
	lbl.text = door_label_text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.size = Vector2(door_w + 20, 24)
	# Position label above/below/beside the door
	match direction:
		DIR_NORTH:
			lbl.position = Vector2(-door_w * 0.5 - 10, door_h * 0.5 + 4)
		DIR_SOUTH:
			lbl.position = Vector2(-door_w * 0.5 - 10, -door_h * 0.5 - 28)
		DIR_EAST:
			lbl.position = Vector2(-door_w * 0.5 - 40, -12)
		DIR_WEST:
			lbl.position = Vector2(door_w * 0.5 - 10, -12)
	door_zone.add_child(lbl)

	# Direction arrow
	var arrow := Label.new()
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	arrow.add_theme_font_size_override("font_size", 28)
	arrow.add_theme_color_override("font_color", Color.WHITE)
	match direction:
		DIR_NORTH: arrow.text = "^"
		DIR_SOUTH: arrow.text = "v"
		DIR_EAST:  arrow.text = ">"
		DIR_WEST:  arrow.text = "<"
	arrow.size = Vector2(40, 40)
	arrow.position = Vector2(-20, -20)
	door_zone.add_child(arrow)

	# Start hidden (activated after room is cleared)
	door_zone.monitoring = false
	for child in door_zone.get_children():
		if child is CanvasItem:
			child.visible = false

	# Connect signal
	door_zone.body_entered.connect(_on_door_entered.bind(target_room_idx))
	add_child(door_zone)
	_door_zones.append(door_zone)


## Called when the player enters a door zone leading to a specific room.
func _on_door_entered(body: Node2D, target_room_idx: int) -> void:
	if body.name != "Player" and not body.is_in_group("player"):
		return
	# Doors are only active after room is cleared (start rooms and revisits
	# are marked as cleared during _ready, so this check covers all cases).
	if not _room_cleared and not GameManager.roguelike_in_treasure_room:
		return

	print("[RoguelikeLevel] Player entered door to room %d" % target_room_idx)
	GameManager.roguelike_target_room = target_room_idx
	_navigate_to_map_room(target_room_idx)


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

	# Room progress label (top-centre): "Комната 2 / 4 — Здание"
	_room_progress_label = Label.new()
	_room_progress_label.name = "RoomProgressLabel"
	_room_progress_label.text = _get_room_progress_text()
	_room_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_progress_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_room_progress_label.offset_top    = 10
	_room_progress_label.offset_bottom = 36
	_room_progress_label.add_theme_font_size_override("font_size", 16)
	_room_progress_label.add_theme_color_override("font_color", Color(0.6, 0.4, 1.0, 0.9))
	ui.add_child(_room_progress_label)

	# Enemy count (top-right)
	_enemy_count_label = Label.new()
	_enemy_count_label.name = "EnemyCountLabel"
	_enemy_count_label.text = "Враги: 0"
	_enemy_count_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_enemy_count_label.offset_left   = -200
	_enemy_count_label.offset_right  = -10
	_enemy_count_label.offset_top    = 10
	_enemy_count_label.offset_bottom = 40
	_enemy_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui.add_child(_enemy_count_label)

	# Ammo (top-left)
	_ammo_label = Label.new()
	_ammo_label.name = "AmmoLabel"
	_ammo_label.text = "AMMO: -"
	_ammo_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_ammo_label.offset_left   = 10
	_ammo_label.offset_top    = 10
	_ammo_label.offset_right  = 300
	_ammo_label.offset_bottom = 40
	ui.add_child(_ammo_label)

	# Difficulty (top-left, below ammo)
	_difficulty_label = Label.new()
	_difficulty_label.name = "DifficultyLabel"
	_difficulty_label.text = "Difficulty: " + DifficultyManager.get_difficulty_name()
	_difficulty_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_difficulty_label.offset_left   = 10
	_difficulty_label.offset_top    = 80
	_difficulty_label.offset_right  = 200
	_difficulty_label.offset_bottom = 110
	ui.add_child(_difficulty_label)

	# Magazines
	_magazines_label = Label.new()
	_magazines_label.name = "MagazinesLabel"
	_magazines_label.text = "MAGS: -"
	_magazines_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_magazines_label.offset_left   = 10
	_magazines_label.offset_top    = 115
	_magazines_label.offset_right  = 400
	_magazines_label.offset_bottom = 145
	ui.add_child(_magazines_label)


func _get_room_progress_text() -> String:
	var type_name: String = ROOM_TYPE_NAMES.get(_room_type, "?")
	# Issue #1399: Show map room info if available
	var rooms: Array = GameManager.roguelike_room_map
	var map_idx: int = GameManager.roguelike_current_map_room
	if rooms.size() > 0 and map_idx >= 0 and map_idx < rooms.size():
		var map_room: Dictionary = rooms[map_idx]
		var map_type: String = map_room["map_room_type"]
		var visited_count: int = GameManager.roguelike_visited_rooms.size()
		var total_count: int = rooms.size()
		var map_type_label: String = ""
		match map_type:
			"start": map_type_label = "СТАРТ"
			"treasure": map_type_label = "СОКРОВИЩНИЦА"
			"exit": map_type_label = "ВЫХОД"
			_: map_type_label = type_name
		return "РОГАЛИК — Ур.%d — %s — Комнат: %d/%d" % [
			GameManager.roguelike_current_level,
			map_type_label,
			visited_count, total_count]
	return "РОГАЛИК — Уровень %d — Комната %d / %d — %s" % [
		GameManager.roguelike_current_level,
		_current_room_idx + 1, _total_rooms, type_name]


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

	var visual      := ColorRect.new()
	visual.color    = WALL_COLOR
	visual.size     = rect.size
	visual.position = -rect.size / 2.0
	body.add_child(visual)

	parent.add_child(body)


func _create_cover(parent: Node, rect: Rect2) -> void:
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
	visual.color   = Color(0.42, 0.38, 0.34, 1.0)
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

	if _current_enemy_count <= 0:
		print("[RoguelikeLevel] All enemies in room %d eliminated!" % (_current_room_idx + 1))
		_room_cleared = true
		# Issue #1399: Mark room as cleared on the map
		var map_idx: int = GameManager.roguelike_current_map_room
		if map_idx >= 0 and map_idx < GameManager.roguelike_room_map.size():
			GameManager.roguelike_room_map[map_idx]["cleared"] = true
		# Issue #1451: Unlock doors (remove physical barriers)
		_remove_door_barriers()
		# After the last combat room, the exit leads to the treasure room (not another combat room).
		# No pedestal in combat rooms — the pedestal is in the dedicated treasure room.
		call_deferred("_activate_exit_zone")


func _on_enemy_became_pacifist(enemy: Node) -> void:
	_current_enemy_count -= 1
	# Issue #1369: Do not double-count pacifist when it dies - already counted here
	if is_instance_valid(enemy) and enemy.died.is_connected(_on_enemy_died):
		enemy.died.disconnect(_on_enemy_died)
	_update_enemy_count_label()
	print("[RoguelikeLevel] Enemy became pacifist - counting as eliminated")
	if _current_enemy_count <= 0:
		print("[RoguelikeLevel] All enemies in room %d eliminated or pacified!" % (_current_room_idx + 1))
		_room_cleared = true
		# Issue #1451: Unlock doors (remove physical barriers)
		_remove_door_barriers()
		call_deferred("_activate_exit_zone")


func _on_enemy_died_with_info(is_ricochet: bool, is_penetration: bool, is_player_kill: bool = true) -> void:
	# Register kill with GameManager (Issue #1196: pass player kill flag to count only player kills).
	if GameManager:
		GameManager.register_kill(is_player_kill, is_penetration)
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
	# Issue #1261: Do NOT broadcast ammo-empty to all enemies globally — that bypasses the
	# sound range system and lets out-of-earshot enemies react to the empty click.
	# The EMPTY_CLICK sound emitted below already sets player_ammo_empty on enemies within range.
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
	_player_dead = true
	# Do NOT call GameManager.on_player_death() — that auto-reloads the scene
	# immediately, causing enemies to appear while death effects play (Issue #1061 r4).
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(self):
		_show_death_screen()


func _on_game_manager_enemy_killed() -> void:
	_show_saturation_effect()


func _on_player_reached_exit() -> void:
	# Treasure room is always "cleared" (no enemies)
	if not _room_cleared and not GameManager.roguelike_in_treasure_room:
		return
	var _log_exit := "[RoguelikeLevel] Player reached exit — advancing (treasure_room=%s)" % str(GameManager.roguelike_in_treasure_room)
	print(_log_exit)
	FileLogger.info(_log_exit)
	call_deferred("_advance_to_next_room")


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
## Treasure pedestal (Issue #1166) — Isaac-style item pickup
## ============================================================

## Weapon icon paths for pedestal display (Issue #1166 Bug 1 — show actual weapon icon).
const WEAPON_ICON_PATHS: Dictionary = {
	"makarov_pm":    "res://assets/sprites/weapons/makarov_pm_icon.png",
	"m16":           "res://assets/sprites/weapons/m16_simple.png",
	"shotgun":       "res://assets/sprites/weapons/shotgun_icon.png",
	"mini_uzi":      "res://assets/sprites/weapons/mini_uzi_icon.png",
	"silenced_pistol": "res://assets/sprites/weapons/silenced_pistol_icon.png",
	"sniper":        "res://assets/sprites/weapons/asvk_topdown.png",
	"revolver":      "res://assets/sprites/weapons/revolver_icon.png",
	"ak_gl":         "res://assets/sprites/weapons/ak_gl_icon.png",
}


## Pick a random item for the pedestal.
## Returns either a weapon ID String (e.g. "m16") or an int (ActiveItemType).
## The weapon is pre-selected so the pedestal can show the correct icon.
## Issue #1313: items already offered earlier in this run are excluded so each
## item can appear at most once per run.
## Issue #1313: makarov_pm is always excluded — it is the starting weapon given
## to every player at the beginning of a run and must not appear in treasure rooms.
const ROGUELIKE_STARTING_WEAPONS: Array = ["makarov_pm"]

func _pick_random_pedestal_item():
	var already_offered: Array = GameManager.roguelike_offered_items if GameManager else []

	# 40% chance of a weapon pickup, 60% chance of an active item.
	if randi() % 10 < 4:
		# Pre-select a specific weapon (different from what the player has now,
		# not already offered this run, and not a starting weapon given at run start).
		var current_weapon_id: String = GameManager.get_selected_weapon() if GameManager else "makarov_pm"
		var available: Array = []
		for weapon_id in GameManager.WEAPON_SCENES.keys():
			if weapon_id != current_weapon_id and GameManager.is_weapon_unlocked(weapon_id) \
					and not (weapon_id in already_offered) \
					and not (weapon_id in ROGUELIKE_STARTING_WEAPONS):
				available.append(weapon_id)
		if available.is_empty():
			# Fallback to active item if no other weapons are available
			pass
		else:
			return available[randi() % available.size()]

	# Choose a random active item (skip NONE index 0, skip already-offered items).
	var all_types: Array = ActiveItemManager.get_all_active_item_types()
	var candidates: Array = []
	for t in all_types:
		if t != 0 and not (t in already_offered):  # Skip NONE and already-offered
			candidates.append(t)

	if candidates.is_empty():
		return "makarov_pm"  # Ultimate fallback

	return candidates[randi() % candidates.size()]


## Spawn the treasure pedestal at the centre of the room.
## Called directly in _ready() for the treasure room (not deferred) so it
## appears on the very first frame.  Issue #1166.
func _spawn_treasure_pedestal() -> void:
	if _treasure_pedestal != null:
		return  # Already spawned

	# Issue #1450: restore the previously-offered item if the player is re-entering
	# a treasure room where the pedestal was not yet collected (item was offered but
	# the player left without picking it up).  If no item was saved yet, pick a new one.
	var map_idx: int = GameManager.roguelike_current_map_room
	var saved_item = null
	if GameManager.roguelike_room_map.size() > 0 and map_idx >= 0 and map_idx < GameManager.roguelike_room_map.size():
		saved_item = GameManager.roguelike_room_map[map_idx].get("treasure_item", null)

	var item
	if saved_item != null:
		# Restore the same item the player saw before
		item = saved_item
		var _log_restore := "[RoguelikeLevel] Restoring treasure pedestal item: %s (Issue #1450)" % _pedestal_item_label(item)
		print(_log_restore)
		FileLogger.info(_log_restore)
	else:
		item = _pick_random_pedestal_item()
		# Issue #1313: record the offered item so it won't appear again this run.
		if GameManager and not (item in GameManager.roguelike_offered_items):
			GameManager.roguelike_offered_items.append(item)
		# Issue #1450: persist the offered item in the room map so re-entry restores it.
		if GameManager.roguelike_room_map.size() > 0 and map_idx >= 0 and map_idx < GameManager.roguelike_room_map.size():
			GameManager.roguelike_room_map[map_idx]["treasure_item"] = item

	_pedestal_item = item

	var item_label_str: String = _pedestal_item_label(item)
	var _log_ped := "[RoguelikeLevel] Spawning treasure pedestal: %s" % item_label_str
	print(_log_ped)
	FileLogger.info(_log_ped)

	# ── Build the Area2D pedestal ──────────────────────────────────────────
	var pedestal := Area2D.new()
	pedestal.name = "TreasurePedestal"
	pedestal.collision_layer = 0
	pedestal.collision_mask = 1   # Detect player CharacterBody2D (layer 1)
	# Bug fix #1166 (Bug 2): keep monitoring disabled until after add_child so that
	# body_entered fires correctly even if the player already overlaps the area.
	pedestal.monitoring = false
	# Render above all world-space objects.
	pedestal.z_index = 10

	# Position at room centre
	pedestal.position = Vector2(_room_w * 0.5, _room_h * 0.5)

	# Collision circle (larger than visual so the player can't miss it)
	var col := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = PEDESTAL_RADIUS
	col.shape = circle
	pedestal.add_child(col)

	# Visual: glowing ring on the floor (Issue #1299: background square removed so item floats visually)
	var glow_ring := ColorRect.new()
	glow_ring.size    = Vector2(PEDESTAL_SIZE * 2.2, PEDESTAL_SIZE * 0.35)
	glow_ring.color   = Color(0.90, 0.75, 0.10, 0.30)
	glow_ring.position = Vector2(-PEDESTAL_SIZE * 1.1, PEDESTAL_SIZE * 0.08)
	pedestal.add_child(glow_ring)

	# Visual: base platform — fake-3D volumetric pedestal (Issue #1180).
	# Layer 1: bottom shadow (dark, shifted down-right to simulate depth)
	var base_shadow := ColorRect.new()
	base_shadow.size     = Vector2(PEDESTAL_SIZE * 1.5, PEDESTAL_SIZE * 0.5)
	base_shadow.color    = Color(0.18, 0.12, 0.05, 0.85)
	base_shadow.position = Vector2(-PEDESTAL_SIZE * 0.75 + 4, PEDESTAL_SIZE * 0.1 + 4)
	pedestal.add_child(base_shadow)
	# Layer 2: side face (slightly darker than front, visible on right)
	var base_side := ColorRect.new()
	base_side.size     = Vector2(4, PEDESTAL_SIZE * 0.5)
	base_side.color    = Color(0.35, 0.25, 0.10, 1.0)
	base_side.position = Vector2(-PEDESTAL_SIZE * 0.75 + PEDESTAL_SIZE * 1.5, PEDESTAL_SIZE * 0.1 + 2)
	pedestal.add_child(base_side)
	# Layer 3: top face highlight (lighter strip, simulates light on top edge)
	var base_top := ColorRect.new()
	base_top.size     = Vector2(PEDESTAL_SIZE * 1.5, 4)
	base_top.color    = Color(0.80, 0.65, 0.35, 1.0)
	base_top.position = Vector2(-PEDESTAL_SIZE * 0.75, PEDESTAL_SIZE * 0.1)
	pedestal.add_child(base_top)
	# Layer 4: front face (main visible face)
	var base := ColorRect.new()
	base.size    = Vector2(PEDESTAL_SIZE * 1.5, PEDESTAL_SIZE * 0.5 - 4)
	base.color   = PEDESTAL_BASE_COLOR
	base.position = Vector2(-PEDESTAL_SIZE * 0.75, PEDESTAL_SIZE * 0.1 + 4)
	pedestal.add_child(base)

	# Visual: item icon — Bug fix #1166 (Bug 3): show actual icon texture without
	# background instead of a plain coloured square.
	# Bug fix #1166 (Bug 1): weapon pedestal now pre-selects a specific weapon,
	# so we show that weapon's icon instead of a generic case icon.
	# Issue #1299: item floats in a Node2D container so the tween animation moves
	# the whole icon group (icon + shadow) together without a background panel.
	var icon_path: String = ""
	if item is String and item != "" and item in WEAPON_ICON_PATHS:
		icon_path = WEAPON_ICON_PATHS[item]
		if not ResourceLoader.exists(icon_path):
			icon_path = "res://assets/sprites/weapons/weapon_case_icon.png"
	elif item is int and ActiveItemManager:
		icon_path = ActiveItemManager.get_active_item_icon_path(item)

	# Float container — the looping tween animates this node's Y offset.
	var float_node := Node2D.new()
	float_node.name = "ItemFloat"
	float_node.position = Vector2(0.0, -PEDESTAL_SIZE * 1.1)
	pedestal.add_child(float_node)

	var icon_ok := false
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var icon_tex = load(icon_path)
		if icon_tex != null:
			var icon_rect := TextureRect.new()
			icon_rect.name = "ItemIcon"  # Named so _apply_pedestal_weapon can find and update it (Issue #1180)
			icon_rect.texture = icon_tex
			icon_rect.expand_mode = TextureRect.EXPAND_KEEP_SIZE
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			var icon_size := Vector2(PEDESTAL_SIZE, PEDESTAL_SIZE)
			icon_rect.custom_minimum_size = icon_size
			icon_rect.size = icon_size
			icon_rect.position = Vector2(-icon_size.x * 0.5, 0.0)
			float_node.add_child(icon_rect)
			icon_ok = true

	if not icon_ok:
		# Fallback: bright coloured orb if icon not found or failed to load
		var orb := ColorRect.new()
		orb.size    = Vector2(PEDESTAL_SIZE * 0.8, PEDESTAL_SIZE * 0.8)
		orb.color   = PEDESTAL_ITEM_GLOW
		orb.position = Vector2(-PEDESTAL_SIZE * 0.4, 0.0)
		float_node.add_child(orb)

	# Issue #1299: gentle floating animation — item bobs ±4 px over 1.4 s, looping.
	# Bind the tween to the pedestal (not the level) so it is automatically killed
	# when the pedestal is queue_free()-d.  Using `create_tween()` (bound to self/level)
	# caused a crash: the tween survived pedestal removal and tried to animate the
	# freed float_node → engine segfault (Issue #1323 regression).
	var float_tween := pedestal.create_tween()
	float_tween.set_loops()
	float_tween.tween_property(float_node, "position:y", -PEDESTAL_SIZE * 1.1 - 4.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	float_tween.tween_property(float_node, "position:y", -PEDESTAL_SIZE * 1.1 + 4.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Label: item name (larger font)
	var label := Label.new()
	label.name = "ItemLabel"
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.text = item_label_str
	label.position = Vector2(-80, -PEDESTAL_SIZE * 1.3 - 22)
	label.custom_minimum_size = Vector2(160, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pedestal.add_child(label)

	# Hint label (larger font)
	var hint := Label.new()
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
	hint.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	hint.add_theme_constant_override("shadow_offset_x", 1)
	hint.add_theme_constant_override("shadow_offset_y", 1)
	hint.text = "подойди, чтобы взять"
	hint.position = Vector2(-80, PEDESTAL_SIZE * 0.5)
	hint.custom_minimum_size = Vector2(160, 0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pedestal.add_child(hint)

	pedestal.set_meta("pedestal_item", item)
	pedestal.body_entered.connect(_on_pedestal_body_entered.bind(pedestal))

	add_child(pedestal)
	_treasure_pedestal = pedestal
	# Enable monitoring after add_child so body_entered fires for existing overlaps
	pedestal.set_deferred("monitoring", true)

	var _log_ped2 := "[RoguelikeLevel] Treasure pedestal added to scene at (%d, %d)" % [
		int(pedestal.position.x), int(pedestal.position.y)]
	print(_log_ped2)
	FileLogger.info(_log_ped2)


## Returns a human-readable name for the pedestal item.
## Weapon pedestal shows the specific pre-selected weapon name (Issue #1166 Bug 1).
const WEAPON_DISPLAY_NAMES: Dictionary = {
	"makarov_pm":      "Макаров ПМ",
	"m16":             "M16",
	"shotgun":         "Дробовик",
	"mini_uzi":        "Мини-Узи",
	"silenced_pistol": "Тихий пистолет",
	"sniper":          "Снайперская винтовка",
	"revolver":        "Револьвер",
	"ak_gl":           "АК-74 + ГП",
}

func _pedestal_item_label(item) -> String:
	if item is String and item in WEAPON_DISPLAY_NAMES:
		return WEAPON_DISPLAY_NAMES[item]
	if item is int and ActiveItemManager:
		return ActiveItemManager.get_active_item_name(item)
	return "???"


## Issue #1450: Mark the current treasure room's item as permanently collected.
## Called whenever the pedestal item is consumed (not merely swapped onto the pedestal).
func _mark_treasure_collected() -> void:
	var map_idx: int = GameManager.roguelike_current_map_room
	if GameManager.roguelike_room_map.size() > 0 and map_idx >= 0 and map_idx < GameManager.roguelike_room_map.size():
		GameManager.roguelike_room_map[map_idx]["treasure_collected"] = true
		var _log_col := "[RoguelikeLevel] Treasure room %d marked collected (Issue #1450)" % map_idx
		print(_log_col)
		FileLogger.info(_log_col)


## Called when the player's body enters the pedestal Area2D.
func _on_pedestal_body_entered(body: Node2D, pedestal: Area2D) -> void:
	if body.name != "Player" and not body.is_in_group("player"):
		return
	if not is_instance_valid(pedestal):
		return

	var item = pedestal.get_meta("pedestal_item", null)
	if item == null:
		return

	print("[RoguelikeLevel] Pedestal collected by player: %s" % _pedestal_item_label(item))

	if item is String and item in GameManager.WEAPON_SCENES:
		_apply_pedestal_weapon(body, pedestal)
	elif item is int:
		_apply_pedestal_active_item(body, item, pedestal)


## Give the player the pre-selected weapon from the pedestal (weapon pedestal).
## Issue #1166 Bug 1 fix: the player's old weapon is put back on the pedestal so they
## can swap back before leaving the room — mirrors the active-item swap mechanic.
func _apply_pedestal_weapon(player: Node2D, pedestal: Area2D) -> void:
	if GameManager == null:
		_mark_treasure_collected()
		pedestal.queue_free()
		_treasure_pedestal = null
		return

	# The item on the pedestal is the pre-selected weapon ID string.
	var new_weapon_id: String = _pedestal_item if (_pedestal_item is String and _pedestal_item in GameManager.WEAPON_SCENES) else ""

	if new_weapon_id == "":
		# Fallback: pick any other unlocked weapon at pickup time.
		var current_weapon_id: String = GameManager.get_selected_weapon()
		var available: Array = []
		for weapon_id in GameManager.WEAPON_SCENES.keys():
			if weapon_id != current_weapon_id and GameManager.is_weapon_unlocked(weapon_id):
				available.append(weapon_id)
		if available.is_empty():
			print("[RoguelikeLevel] Weapon pedestal: no other weapons available — skipping")
			_mark_treasure_collected()
			pedestal.queue_free()
			_treasure_pedestal = null
			return
		new_weapon_id = available[randi() % available.size()]

	# Remember the player's current weapon before the swap.
	var old_weapon_id: String = GameManager.get_selected_weapon()

	# Give the new weapon to the player.
	GameManager.set_selected_weapon(new_weapon_id)
	# Track the carried weapon so it survives level transitions (Bug 2 fix).
	GameManager.roguelike_run_weapon = new_weapon_id

	if player.has_method("ApplySelectedWeaponFromGameManager"):
		player.ApplySelectedWeaponFromGameManager()
	# Reconnect level signal handlers to the new weapon after the swap,
	# so the ammo/shot counter UI stays in sync (Issue #1323 regression fix).
	_reconnect_weapon_signals()

	print("[RoguelikeLevel] Weapon pedestal: player took %s, old weapon %s returned to pedestal" % [new_weapon_id, old_weapon_id])

	# Put the player's old weapon back on the pedestal so they can swap back.
	# Only do this if the old weapon differs from the new one.
	if old_weapon_id != "" and old_weapon_id != new_weapon_id:
		_pedestal_item = old_weapon_id
		pedestal.set_meta("pedestal_item", old_weapon_id)

		# Update the icon on the pedestal to show the old weapon (Issue #1180).
		# Issue #1299: ItemIcon now lives inside ItemFloat; try both paths for safety.
		if old_weapon_id in WEAPON_ICON_PATHS:
			var old_icon_path: String = WEAPON_ICON_PATHS[old_weapon_id]
			if ResourceLoader.exists(old_icon_path):
				var tex: Texture2D = load(old_icon_path) as Texture2D
				if tex:
					var icon_rect: TextureRect = pedestal.get_node_or_null("ItemFloat/ItemIcon")
					if icon_rect == null:
						icon_rect = pedestal.get_node_or_null("ItemIcon")
					if icon_rect:
						icon_rect.texture = tex
					else:
						# Icon node missing — add it to the float container if present,
						# otherwise fall back to direct pedestal child.
						var float_node: Node2D = pedestal.get_node_or_null("ItemFloat")
						var new_icon := TextureRect.new()
						new_icon.name = "ItemIcon"
						new_icon.texture = tex
						new_icon.expand_mode = TextureRect.EXPAND_KEEP_SIZE
						new_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
						var icon_size := Vector2(PEDESTAL_SIZE, PEDESTAL_SIZE)
						new_icon.custom_minimum_size = icon_size
						new_icon.size = icon_size
						if float_node:
							new_icon.position = Vector2(-icon_size.x * 0.5, 0.0)
							float_node.add_child(new_icon)
						else:
							new_icon.position = Vector2(-icon_size.x * 0.5, -PEDESTAL_SIZE * 1.1)
							pedestal.add_child(new_icon)

		# Update the item name label.
		var item_lbl: Label = pedestal.get_node_or_null("ItemLabel")
		if item_lbl:
			item_lbl.text = _pedestal_item_label(old_weapon_id)

		print("[RoguelikeLevel] Old weapon '%s' placed back on pedestal" % old_weapon_id)
		# Issue #1450: persist the updated pedestal item (old weapon now on pedestal).
		var _wp_map_idx: int = GameManager.roguelike_current_map_room
		if GameManager.roguelike_room_map.size() > 0 and _wp_map_idx >= 0 and _wp_map_idx < GameManager.roguelike_room_map.size():
			GameManager.roguelike_room_map[_wp_map_idx]["treasure_item"] = old_weapon_id
		# Leave pedestal alive so player can pick it back up.
	else:
		# No meaningful old weapon — remove pedestal.
		_mark_treasure_collected()
		pedestal.queue_free()
		_treasure_pedestal = null


## Give the player an active item (active-item pedestal).
## Passive items accumulate (player keeps both the old and new).
## Active (non-passive) items replace the current one without scene restart;
## the displaced item is put back on the pedestal for the player to reconsider.
func _apply_pedestal_active_item(player: Node2D, item_type: int, pedestal: Area2D) -> void:
	if ActiveItemManager == null:
		_mark_treasure_collected()
		pedestal.queue_free()
		_treasure_pedestal = null
		return

	var is_passive: bool = item_type in PASSIVE_ACTIVE_ITEM_TYPES
	var current: int = ActiveItemManager.current_active_item

	if is_passive:
		# Passive: add to passive collection (it coexists with any active item and other passives).
		# Issue #1303: use add_passive_item() so multiple passives work simultaneously.
		if ActiveItemManager.has_method("has_passive_item") and ActiveItemManager.has_passive_item(item_type):
			print("[RoguelikeLevel] Active-item pedestal: already have passive %s — skipping" %
				ActiveItemManager.get_active_item_name(item_type))
			_mark_treasure_collected()
			pedestal.queue_free()
			_treasure_pedestal = null
			return
		if ActiveItemManager.has_method("add_passive_item"):
			ActiveItemManager.add_passive_item(item_type)
		else:
			ActiveItemManager.set_active_item(item_type, false)  # fallback for older builds
		print("[RoguelikeLevel] Passive item collected: %s" %
			ActiveItemManager.get_active_item_name(item_type))
		_mark_treasure_collected()
		pedestal.queue_free()
		_treasure_pedestal = null
	else:
		# Active item: swap — put the old item back on the pedestal so the player
		# can take it again if they change their mind.
		var old_type: int = current

		ActiveItemManager.set_active_item(item_type, false)  # false = no scene restart
		print("[RoguelikeLevel] Active item collected: %s (replaced %s)" % [
			ActiveItemManager.get_active_item_name(item_type),
			ActiveItemManager.get_active_item_name(old_type)])

		if old_type != 0 and old_type != item_type:
			# Update pedestal to offer the displaced item
			pedestal.set_meta("pedestal_item", old_type)
			_pedestal_item = old_type
			# Update item name label (identified by its name set during spawn)
			var item_lbl: Label = pedestal.get_node_or_null("ItemLabel")
			if item_lbl:
				item_lbl.text = _pedestal_item_label(old_type)
			# Issue #1303: Update the icon on the pedestal to show the displaced item.
			var old_icon_path: String = ActiveItemManager.get_active_item_icon_path(old_type)
			if old_icon_path != "" and ResourceLoader.exists(old_icon_path):
				var tex: Texture2D = load(old_icon_path) as Texture2D
				if tex:
					var icon_rect: TextureRect = pedestal.get_node_or_null("ItemIcon")
					if icon_rect:
						icon_rect.texture = tex
					else:
						var new_icon := TextureRect.new()
						new_icon.name = "ItemIcon"
						new_icon.texture = tex
						new_icon.expand_mode = TextureRect.EXPAND_KEEP_SIZE
						new_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
						var icon_size := Vector2(PEDESTAL_SIZE, PEDESTAL_SIZE)
						new_icon.custom_minimum_size = icon_size
						new_icon.size = icon_size
						new_icon.position = Vector2(-icon_size.x * 0.5, -PEDESTAL_SIZE * 1.1)
						pedestal.add_child(new_icon)
			print("[RoguelikeLevel] Displaced item '%s' placed back on pedestal" %
				ActiveItemManager.get_active_item_name(old_type))
			# Issue #1450: persist the updated pedestal item (displaced item now on pedestal).
			var _ai_map_idx: int = GameManager.roguelike_current_map_room
			if GameManager.roguelike_room_map.size() > 0 and _ai_map_idx >= 0 and _ai_map_idx < GameManager.roguelike_room_map.size():
				GameManager.roguelike_room_map[_ai_map_idx]["treasure_item"] = old_type
		else:
			# No old item to put back — remove pedestal
			_mark_treasure_collected()
			pedestal.queue_free()
			_treasure_pedestal = null


## ============================================================
## Room progression — Isaac-style
## ============================================================

func _activate_exit_zone() -> void:
	# Issue #1399: Activate all door zones (branching map)
	if _door_zones.size() > 0:
		for door in _door_zones:
			if is_instance_valid(door):
				door.monitoring = true
				for child in door.get_children():
					if child is CanvasItem:
						child.visible = true
				# Fade-in animation
				var tween := create_tween()
				tween.set_parallel(true)
				for child in door.get_children():
					if child is CanvasItem:
						child.modulate = Color(1, 1, 1, 0)
						tween.tween_property(child, "modulate:a", 1.0, 0.5)
		print("[RoguelikeLevel] %d door zones activated" % _door_zones.size())
	elif _exit_zone and _exit_zone.has_method("activate"):
		_exit_zone.activate()
		print("[RoguelikeLevel] Exit zone activated — proceed to next room!")
	else:
		# No exit zone — advance automatically
		_advance_to_next_room()


func _advance_to_next_room() -> void:
	if GameManager.roguelike_in_treasure_room:
		## Leaving the treasure room → start the next level
		_start_next_level()
		return

	# Issue #1399: This legacy path is used only when _on_player_reached_exit fires
	# (from the fallback single ExitZone). With branching map, _navigate_to_map_room
	# handles navigation. Keep for backwards compatibility.

	## Accumulate this room's stats into the run totals in GameManager
	if GameManager:
		GameManager.roguelike_total_kills += GameManager.kills
		GameManager.roguelike_total_shots += GameManager.shots_fired
		GameManager.roguelike_total_hits  += GameManager.hits_landed

	var next_room: int = _current_room_idx + 1

	if next_room >= _total_rooms:
		## Last combat room cleared — enter the treasure room
		print("[RoguelikeLevel] Level %d complete! Entering treasure room." % GameManager.roguelike_current_level)
		_enter_treasure_room()
	else:
		## More combat rooms remaining — load next room
		GameManager.roguelike_current_room = next_room
		print("[RoguelikeLevel] Advancing to room %d/%d" % [next_room + 1, _total_rooms])
		_show_room_transition(next_room)


## Issue #1399: Navigate to a specific room on the branching map.
func _navigate_to_map_room(target_room_idx: int) -> void:
	var rooms: Array = GameManager.roguelike_room_map
	if target_room_idx < 0 or target_room_idx >= rooms.size():
		return

	var current_idx: int = GameManager.roguelike_current_map_room

	# Accumulate stats
	if GameManager:
		GameManager.roguelike_total_kills += GameManager.kills
		GameManager.roguelike_total_shots += GameManager.shots_fired
		GameManager.roguelike_total_hits  += GameManager.hits_landed

	# Mark current room as cleared
	if current_idx >= 0 and current_idx < rooms.size():
		rooms[current_idx]["cleared"] = true

	# Update state for the target room
	GameManager.roguelike_source_room = current_idx  # Track where we came from
	GameManager.roguelike_current_map_room = target_room_idx
	GameManager.roguelike_target_room = target_room_idx

	var target_room: Dictionary = rooms[target_room_idx]

	# Handle special room types
	match target_room["map_room_type"]:
		"treasure":
			print("[RoguelikeLevel] Navigating to TREASURE room %d" % target_room_idx)
			GameManager.roguelike_in_treasure_room = true
			# Issue #1450: mark treasure room as cleared/visited on first entry so
			# re-entry from any connected room is detected and no new pedestal spawns.
			rooms[target_room_idx]["visited"] = true
			if not (target_room_idx in GameManager.roguelike_visited_rooms):
				GameManager.roguelike_visited_rooms.append(target_room_idx)
			_show_map_room_transition(target_room_idx, "Сокровищница!", Color(1.0, 0.85, 0.3, 1.0))
		"exit":
			print("[RoguelikeLevel] Navigating to EXIT room %d — next level!" % target_room_idx)
			# Mark as visited and cleared, then start next level
			rooms[target_room_idx]["visited"] = true
			rooms[target_room_idx]["cleared"] = true
			if not (target_room_idx in GameManager.roguelike_visited_rooms):
				GameManager.roguelike_visited_rooms.append(target_room_idx)
			_start_next_level()
			return
		_:
			# Issue #1450: leaving the treasure room to a combat/start room —
			# reset the treasure-room flag so _ready() doesn't misidentify the
			# next room as a treasure room via the legacy roguelike_in_treasure_room path.
			GameManager.roguelike_in_treasure_room = false
			if target_room["cleared"]:
				print("[RoguelikeLevel] Revisiting cleared room %d" % target_room_idx)
			else:
				print("[RoguelikeLevel] Navigating to combat room %d" % target_room_idx)

			var type_name: String = ROOM_TYPE_NAMES.get(target_room["room_type"], "?")
			_show_map_room_transition(target_room_idx, type_name, Color(0.5, 1.0, 0.5, 1.0))


## Show a brief transition overlay when moving between map rooms.
func _show_map_room_transition(target_room_idx: int, room_name: String, color: Color) -> void:
	var ui: Node = get_node_or_null("CanvasLayer/UI")
	if ui == null:
		get_tree().change_scene_to_file("res://scenes/levels/RoguelikeLevel.tscn")
		return

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bg)

	var lbl := Label.new()
	lbl.text = room_name
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 40)
	lbl.add_theme_color_override("font_color", color)
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(lbl)

	var tween := create_tween()
	tween.tween_property(bg, "color:a", 0.85, 0.3)
	tween.tween_interval(0.7)
	tween.tween_callback(func():
		get_tree().change_scene_to_file("res://scenes/levels/RoguelikeLevel.tscn"))


## Transition into the treasure room after all combat rooms are cleared.
func _enter_treasure_room() -> void:
	GameManager.roguelike_in_treasure_room = true

	var ui: Node = get_node_or_null("CanvasLayer/UI")
	if ui == null:
		get_tree().change_scene_to_file("res://scenes/levels/RoguelikeLevel.tscn")
		return

	# Dark overlay with "level cleared" message
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bg)

	var lbl := Label.new()
	lbl.text = "Уровень %d пройден!\nДобро пожаловать в Сокровищницу!" % GameManager.roguelike_current_level
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 40)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(lbl)

	var tween := create_tween()
	tween.tween_property(bg, "color:a", 0.85, 0.4)
	tween.tween_interval(1.5)
	tween.tween_callback(func():
		get_tree().change_scene_to_file("res://scenes/levels/RoguelikeLevel.tscn"))


## Start the next roguelike level after leaving the treasure room.
## Increases difficulty and resets room progression.
func _start_next_level() -> void:
	GameManager.roguelike_in_treasure_room = false
	GameManager.roguelike_current_level   += 1

	# Generate a fresh seed so rooms differ from previous levels
	var new_seed: int = randi()
	seed(new_seed)
	GameManager.roguelike_run_seed = new_seed

	# Build a new room sequence for the next level (re-randomise)
	var all_types: Array = [
		RoomType.LABYRINTH,
		RoomType.BUILDING,
		RoomType.BEACH,
		RoomType.DOCKS,
		RoomType.CITY,
		RoomType.SEWER,
	]
	for i in range(all_types.size() - 1, 0, -1):
		var j: int = randi_range(0, i)
		var tmp = all_types[i]
		all_types[i] = all_types[j]
		all_types[j] = tmp

	# Issue #1451: Do NOT cap count by all_types.size() — with many rooms (7-10),
	# room types cycle/repeat. The type pool is used modulo its size in _generate_room_map.
	var count: int = randi_range(MIN_ROOMS, MAX_ROOMS)

	GameManager.roguelike_total_rooms  = count
	GameManager.roguelike_room_types   = all_types.slice(0, min(count, all_types.size()))
	GameManager.roguelike_current_room = 0
	# Keep roguelike_active = true; the run continues

	# Issue #1399: Generate new branching map for the next level
	GameManager.roguelike_room_map = _generate_room_map(count, all_types)
	GameManager.roguelike_current_map_room = 0
	GameManager.roguelike_visited_rooms = [0]
	GameManager.roguelike_room_map[0]["visited"] = true
	GameManager.roguelike_target_room = -1

	print("[RoguelikeLevel] Starting Level %d — %d rooms, difficulty ×%d" % [
		GameManager.roguelike_current_level, count, GameManager.roguelike_current_level])

	var ui: Node = get_node_or_null("CanvasLayer/UI")
	if ui == null:
		get_tree().change_scene_to_file("res://scenes/levels/RoguelikeLevel.tscn")
		return

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bg)

	var lbl := Label.new()
	lbl.text = "УРОВЕНЬ %d\nВраги стали опаснее!" % GameManager.roguelike_current_level
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 44)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3, 1.0))
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(lbl)

	var tween := create_tween()
	tween.tween_property(bg, "color:a", 0.85, 0.4)
	tween.tween_interval(1.5)
	tween.tween_callback(func():
		get_tree().change_scene_to_file("res://scenes/levels/RoguelikeLevel.tscn"))


## Build the treasure room scene: simple open floor, no enemies, warm golden colours.
func _build_room_scene_treasure() -> void:
	# Treasure room always uses standard size for readability
	_room_w = ROOM_WIDTH
	_room_h = ROOM_HEIGHT

	var bg := ColorRect.new()
	bg.name  = "WorldBackground"
	bg.position = Vector2(-200, -200)
	bg.size     = Vector2(_room_w + 400, _room_h + 400)
	bg.color    = Color(0.08, 0.06, 0.02, 1.0)  ## Dark warm background
	add_child(bg)

	var room_container := Node2D.new()
	room_container.name = "Room"
	add_child(room_container)

	# Floor — warm golden tone to distinguish from combat rooms
	var floor_rect := ColorRect.new()
	floor_rect.position = Vector2(0, 0)
	floor_rect.size     = Vector2(_room_w, _room_h)
	floor_rect.color    = Color(0.22, 0.18, 0.08, 1.0)
	room_container.add_child(floor_rect)

	_build_room_boundary_closed(room_container)

	# Decorative pillars in the four corners (treasure room feel)
	var pillar_size := Vector2(40, 40)
	var offsets := [
		Vector2(60, 60), Vector2(_room_w - 100, 60),
		Vector2(60, _room_h - 100), Vector2(_room_w - 100, _room_h - 100),
	]
	for pos in offsets:
		_create_cover(room_container, Rect2(pos.x, pos.y, pillar_size.x, pillar_size.y))


## Add a "СОКРОВИЩНИЦА" header label for the treasure room HUD.
func _setup_debug_ui_treasure() -> void:
	var ui: Node = get_node_or_null("CanvasLayer/UI")
	if ui == null:
		return
	var lbl := Label.new()
	lbl.name = "TreasureRoomLabel"
	lbl.text = "✦ СОКРОВИЩНИЦА — Уровень %d ✦" % GameManager.roguelike_current_level
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl.offset_top    = 10
	lbl.offset_bottom = 40
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
	ui.add_child(lbl)


## ============================================================
## Minimap UI (Issue #1399) — shows branching room layout
## ============================================================

func _setup_minimap() -> void:
	var rooms: Array = GameManager.roguelike_room_map
	if rooms.size() == 0:
		return

	var ui: Node = get_node_or_null("CanvasLayer/UI")
	if ui == null:
		return

	var current_idx: int = GameManager.roguelike_current_map_room

	# Calculate grid bounds to center the minimap
	var min_pos := Vector2i(99, 99)
	var max_pos := Vector2i(-99, -99)
	for room in rooms:
		var gp: Vector2i = room["grid_pos"]
		min_pos.x = min(min_pos.x, gp.x)
		min_pos.y = min(min_pos.y, gp.y)
		max_pos.x = max(max_pos.x, gp.x)
		max_pos.y = max(max_pos.y, gp.y)

	var grid_w: int = max_pos.x - min_pos.x + 1
	var grid_h: int = max_pos.y - min_pos.y + 1
	var cell_total: float = MINIMAP_CELL_SIZE + MINIMAP_GAP
	var minimap_w: float = grid_w * cell_total + MINIMAP_MARGIN * 2
	var minimap_h: float = grid_h * cell_total + MINIMAP_MARGIN * 2

	# Container panel (bottom-right corner)
	var panel := ColorRect.new()
	panel.name = "MinimapPanel"
	panel.color = Color(0.0, 0.0, 0.0, 0.55)
	panel.size = Vector2(minimap_w, minimap_h)
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.offset_left   = -minimap_w - 10
	panel.offset_top    = -minimap_h - 10
	panel.offset_right  = -10
	panel.offset_bottom = -10
	panel.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	ui.add_child(panel)

	# Build a grid lookup for connection drawing
	var grid_to_idx: Dictionary = {}
	for i in range(rooms.size()):
		grid_to_idx[rooms[i]["grid_pos"]] = i

	# Draw connections (lines between rooms)
	for i in range(rooms.size()):
		var room: Dictionary = rooms[i]
		var gp: Vector2i = room["grid_pos"]
		var cell_x: float = (gp.x - min_pos.x) * cell_total + MINIMAP_MARGIN + MINIMAP_CELL_SIZE * 0.5
		var cell_y: float = (gp.y - min_pos.y) * cell_total + MINIMAP_MARGIN + MINIMAP_CELL_SIZE * 0.5

		for conn_idx in room["connections"]:
			if conn_idx <= i:  # Draw each connection once
				continue
			var conn_room: Dictionary = rooms[conn_idx]
			var cgp: Vector2i = conn_room["grid_pos"]
			var cx: float = (cgp.x - min_pos.x) * cell_total + MINIMAP_MARGIN + MINIMAP_CELL_SIZE * 0.5
			var cy: float = (cgp.y - min_pos.y) * cell_total + MINIMAP_MARGIN + MINIMAP_CELL_SIZE * 0.5

			# Determine connection color based on destination room type
			var conn_color: Color = _get_minimap_connection_color(i, conn_idx)

			# Draw connection as a thin rect
			var line := ColorRect.new()
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if abs(cx - cell_x) > abs(cy - cell_y):
				# Horizontal connection
				var lx: float = min(cell_x, cx)
				line.position = Vector2(lx, cell_y - 2)
				line.size = Vector2(abs(cx - cell_x), 4)
			else:
				# Vertical connection
				var ly: float = min(cell_y, cy)
				line.position = Vector2(cell_x - 2, ly)
				line.size = Vector2(4, abs(cy - cell_y))
			line.color = conn_color
			panel.add_child(line)

	# Draw rooms
	for i in range(rooms.size()):
		var room: Dictionary = rooms[i]
		var gp: Vector2i = room["grid_pos"]
		var cell_x: float = (gp.x - min_pos.x) * cell_total + MINIMAP_MARGIN
		var cell_y: float = (gp.y - min_pos.y) * cell_total + MINIMAP_MARGIN

		var cell := ColorRect.new()
		cell.position = Vector2(cell_x, cell_y)
		cell.size = Vector2(MINIMAP_CELL_SIZE, MINIMAP_CELL_SIZE)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE

		# Color based on room type and state
		if i == current_idx:
			cell.color = Color.WHITE  # Current room — bright
		elif room["visited"] or (i in GameManager.roguelike_visited_rooms):
			cell.color = _get_minimap_room_color(room)
		else:
			# Unvisited — dim outline
			cell.color = Color(0.3, 0.3, 0.3, 0.5)

		panel.add_child(cell)

		# Inner indicator for current room
		if i == current_idx:
			var inner := ColorRect.new()
			inner.position = Vector2(cell_x + 3, cell_y + 3)
			inner.size = Vector2(MINIMAP_CELL_SIZE - 6, MINIMAP_CELL_SIZE - 6)
			inner.color = _get_minimap_room_color(room)
			inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
			panel.add_child(inner)


## Get color for a room cell on the minimap.
func _get_minimap_room_color(room: Dictionary) -> Color:
	match room["map_room_type"]:
		"start":
			return Color(0.4, 0.6, 1.0, 1.0)   # Blue
		"treasure":
			return Color(1.0, 0.85, 0.2, 1.0)   # Gold
		"exit":
			return Color(1.0, 0.3, 0.2, 1.0)    # Red
		_:
			if room["cleared"]:
				return Color(0.3, 0.8, 0.3, 0.9)  # Green (cleared)
			return Color(0.6, 0.6, 0.65, 0.8)    # Grey (normal)


## Get color for a connection line between two rooms on the minimap.
func _get_minimap_connection_color(room_a_idx: int, room_b_idx: int) -> Color:
	var rooms: Array = GameManager.roguelike_room_map
	var room_a: Dictionary = rooms[room_a_idx]
	var room_b: Dictionary = rooms[room_b_idx]
	# Use the more "special" of the two rooms for the color
	for r in [room_a, room_b]:
		if r["map_room_type"] == "treasure":
			return Color(1.0, 0.85, 0.2, 0.8)  # Gold
		if r["map_room_type"] == "exit":
			return Color(1.0, 0.3, 0.2, 0.8)   # Red
	return Color(0.5, 0.5, 0.55, 0.6)  # Grey


func _show_room_transition(next_room_idx: int) -> void:
	## Brief "КОМНАТА ПРОЙДЕНА" flash before loading the next room.
	var ui: Node = get_node_or_null("CanvasLayer/UI")
	if ui == null:
		get_tree().change_scene_to_file("res://scenes/levels/RoguelikeLevel.tscn")
		return

	# Dark overlay
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bg)

	# "Room cleared" message
	var next_type: int = GameManager.roguelike_room_types[next_room_idx]
	var next_type_name: String = ROOM_TYPE_NAMES.get(next_type, "?")
	var lbl := Label.new()
	lbl.text = "Комната пройдена!\nСледующая: %s (%d/%d)" % [
		next_type_name, next_room_idx + 1, _total_rooms]
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 40)
	lbl.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5, 1.0))
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(lbl)

	# Fade in overlay, then load next room
	var tween := create_tween()
	tween.tween_property(bg, "color:a", 0.85, 0.4)
	tween.tween_interval(1.0)
	tween.tween_callback(func():
		get_tree().change_scene_to_file("res://scenes/levels/RoguelikeLevel.tscn"))


## ============================================================
## Run completion / score (shown only after ALL rooms cleared)
## ============================================================

func _complete_run_with_score() -> void:
	_restore_loadout()
	GameManager.roguelike_active = false   # Run is over

	var sm: Node = get_node_or_null("/root/ScoreManager")
	if sm and sm.has_method("complete_level"):
		var data: Dictionary = sm.complete_level()
		# Merge accumulated run stats into score data
		data["total_kills_run"]  = GameManager.roguelike_total_kills
		data["total_rooms"]      = _total_rooms
		_show_score_screen(data)
	else:
		_show_victory_message()


func _show_score_screen(score_data: Dictionary) -> void:
	_score_shown = true
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
	container.offset_top    = -220
	container.offset_bottom = 220
	container.add_theme_constant_override("separation", 10)
	ui.add_child(container)

	var title := Label.new()
	title.text = "РОГАЛИК ПРОЙДЕН!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(0.6, 0.4, 1.0, 1.0))
	container.add_child(title)

	var rooms_lbl := Label.new()
	rooms_lbl.text = "Комнат пройдено: %d" % score_data.get("total_rooms", _total_rooms)
	rooms_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rooms_lbl.add_theme_font_size_override("font_size", 20)
	rooms_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1.0))
	container.add_child(rooms_lbl)

	var kills_lbl := Label.new()
	kills_lbl.text = "Всего убийств: %d" % score_data.get("total_kills_run", GameManager.roguelike_total_kills)
	kills_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kills_lbl.add_theme_font_size_override("font_size", 20)
	kills_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1.0))
	container.add_child(kills_lbl)

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
	lbl.text = "РОГАЛИК ПРОЙДЕН!\n%d комнат / %d убийств" % [_total_rooms, GameManager.roguelike_total_kills]
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 48)
	lbl.add_theme_color_override("font_color", Color(0.6, 0.4, 1.0, 1.0))
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.offset_left   = -300
	lbl.offset_right  = 300
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
	if _difficulty_label:
		_difficulty_label.text = "Difficulty: " + DifficultyManager.get_difficulty_name()


func _show_saturation_effect() -> void:
	if _saturation_overlay == null:
		return
	var tween := create_tween()
	tween.tween_property(_saturation_overlay, "color:a", SATURATION_INTENSITY, SATURATION_DURATION * 0.3)
	tween.tween_property(_saturation_overlay, "color:a", 0.0, SATURATION_DURATION * 0.7)


## ============================================================
## Death screen (shown if player dies mid-run)
## ============================================================

func _show_death_screen() -> void:
	if _game_over_shown:
		return
	_game_over_shown = true

	# Run is aborted on death
	_restore_loadout()
	GameManager.roguelike_reset_session()

	var ui: Node = get_node_or_null("CanvasLayer/UI")
	if ui == null:
		return

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.80)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bg)

	var container := VBoxContainer.new()
	container.set_anchors_preset(Control.PRESET_CENTER)
	container.offset_left   = -200
	container.offset_right  = 200
	container.offset_top    = -140
	container.offset_bottom = 140
	container.add_theme_constant_override("separation", 16)
	ui.add_child(container)

	var lbl := Label.new()
	lbl.text = "YOU DIED"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 64)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.15, 0.15, 1.0))
	container.add_child(lbl)

	var room_lbl := Label.new()
	room_lbl.text = "Комната %d / %d" % [_current_room_idx + 1, _total_rooms]
	room_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	room_lbl.add_theme_font_size_override("font_size", 22)
	room_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 0.8))
	container.add_child(room_lbl)

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
			# Only allow Q-restart after death or run completion
			if _game_over_shown or _score_shown:
				_on_restart_pressed()


## ============================================================
## Button handlers
## ============================================================

func _on_restart_pressed() -> void:
	## Start a brand-new run from room 1
	GameManager.roguelike_reset_session()
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
	get_tree().change_scene_to_file("res://scenes/levels/RoguelikeLevel.tscn")


func _on_level_select_pressed() -> void:
	GameManager.roguelike_reset_session()
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)
	_restore_loadout()
	var sl: Node = get_node_or_null("/root/SceneLoader")
	if sl and sl.has_method("load_level"):
		sl.load_level("res://scenes/levels/LabyrinthLevel.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/levels/LabyrinthLevel.tscn")
