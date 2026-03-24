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
	CITY         ## Urban: L-shaped cover blocks, car-like barriers
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
		_build_room_scene_treasure()
		_spawn_player()
		_setup_navigation()
		_setup_player_tracking()
		_setup_exit_zone()
		_setup_debug_ui()
		_setup_saturation_overlay()
		_setup_debug_ui_treasure()
		if GameManager:
			GameManager.stats_updated.connect(_update_debug_ui)
		# Spawn pedestal immediately (not deferred) so it is visible from the first frame.
		# The monitoring flag is still set deferred so body_entered fires for existing overlaps.
		_spawn_treasure_pedestal()
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
	_room_type         = GameManager.roguelike_room_types[_current_room_idx]

	print("[RoguelikeLevel] Level %d — Room %d/%d — type: %s" % [
		GameManager.roguelike_current_level,
		_current_room_idx + 1, _total_rooms,
		ROOM_TYPE_NAMES.get(_room_type, "?")])

	_force_roguelike_loadout()
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
	# Intentionally skip ReplayManager — reduces memory and CPU overhead

	if GameManager:
		GameManager.enemy_killed.connect(_on_game_manager_enemy_killed)
		GameManager.stats_updated.connect(_update_debug_ui)

	print("[RoguelikeLevel] Room ready — %d enemies" % _initial_enemy_count)


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
	]
	# Fisher-Yates shuffle
	for i in range(all_types.size() - 1, 0, -1):
		var j: int = randi_range(0, i)
		var tmp = all_types[i]
		all_types[i] = all_types[j]
		all_types[j] = tmp

	var count: int = randi_range(MIN_ROOMS, MAX_ROOMS)
	count = min(count, all_types.size())

	GameManager.roguelike_active           = true
	GameManager.roguelike_current_room     = 0
	GameManager.roguelike_total_rooms      = count
	GameManager.roguelike_room_types       = all_types.slice(0, count)
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

	var names: Array = []
	for t in GameManager.roguelike_room_types:
		names.append(ROOM_TYPE_NAMES.get(t, "?"))
	print("[RoguelikeLevel] New run — seed=%d, rooms: %s" % [run_seed, str(names)])


func _continue_run() -> void:
	## Resuming mid-run: restore the seed offset so room geometry varies per room.
	## We re-seed with (run_seed + current_room_idx) so each room is different but
	## the sequence is reproducible from the original run seed.
	seed(GameManager.roguelike_run_seed + GameManager.roguelike_current_room)
	print("[RoguelikeLevel] Continuing run at room %d/%d" % [
		GameManager.roguelike_current_room + 1,
		GameManager.roguelike_total_rooms])


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

	print("[RoguelikeLevel] Room built: type=%s variant=%d size=%.0f×%.0f" % [
		ROOM_TYPE_NAMES.get(_room_type, "?"), _room_variant, _room_w, _room_h])


## Fully-enclosed boundary walls (no corridor openings — single room).
func _build_room_boundary_closed(room_node: Node2D) -> void:
	var w: float = _room_w
	var h: float = _room_h
	var t: float = 24.0  ## Wall thickness
	_create_wall(room_node, Rect2(0,     0,     w, t))   ## Top
	_create_wall(room_node, Rect2(0,     h - t, w, t))   ## Bottom
	_create_wall(room_node, Rect2(0,     0,     t, h))   ## Left
	_create_wall(room_node, Rect2(w - t, 0,     t, h))   ## Right


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

	# Spawn at the left-centre of the room, just inside the boundary wall
	player.position = Vector2(80.0, _room_h * 0.5)
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
	var exit_scene: PackedScene = load("res://scenes/objects/ExitZone.tscn")
	if exit_scene == null:
		push_warning("[RoguelikeLevel] ExitZone.tscn not found")
		return

	_exit_zone = exit_scene.instantiate()

	# Place near the right wall, vertically centred (use dynamic room size)
	var exit_x: float = _room_w - 120.0
	var exit_y: float = _room_h * 0.5
	_exit_zone.position    = Vector2(exit_x, exit_y)
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
	_difficulty_label.offset_top    = 45
	_difficulty_label.offset_right  = 200
	_difficulty_label.offset_bottom = 75
	ui.add_child(_difficulty_label)

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


func _get_room_progress_text() -> String:
	var type_name: String = ROOM_TYPE_NAMES.get(_room_type, "?")
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
		call_deferred("_activate_exit_zone")


func _on_enemy_died_with_info(is_ricochet: bool, is_penetration: bool, is_player_kill: bool = true) -> void:
	# Register kill with GameManager (Issue #1196: pass player kill flag to count only player kills).
	if GameManager:
		GameManager.register_kill(is_player_kill)
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

	var item = _pick_random_pedestal_item()
	_pedestal_item = item

	# Issue #1313: record the offered item so it won't appear again this run.
	if GameManager and not (item in GameManager.roguelike_offered_items):
		GameManager.roguelike_offered_items.append(item)

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
		# Leave pedestal alive so player can pick it back up.
	else:
		# No meaningful old weapon — remove pedestal.
		pedestal.queue_free()
		_treasure_pedestal = null


## Give the player an active item (active-item pedestal).
## Passive items accumulate (player keeps both the old and new).
## Active (non-passive) items replace the current one without scene restart;
## the displaced item is put back on the pedestal for the player to reconsider.
func _apply_pedestal_active_item(player: Node2D, item_type: int, pedestal: Area2D) -> void:
	if ActiveItemManager == null:
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
			pedestal.queue_free()
			_treasure_pedestal = null
			return
		if ActiveItemManager.has_method("add_passive_item"):
			ActiveItemManager.add_passive_item(item_type)
		else:
			ActiveItemManager.set_active_item(item_type, false)  # fallback for older builds
		print("[RoguelikeLevel] Passive item collected: %s" %
			ActiveItemManager.get_active_item_name(item_type))
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
		else:
			# No old item to put back — remove pedestal
			pedestal.queue_free()
			_treasure_pedestal = null


## ============================================================
## Room progression — Isaac-style
## ============================================================

func _activate_exit_zone() -> void:
	if _exit_zone and _exit_zone.has_method("activate"):
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
	]
	for i in range(all_types.size() - 1, 0, -1):
		var j: int = randi_range(0, i)
		var tmp = all_types[i]
		all_types[i] = all_types[j]
		all_types[j] = tmp

	var count: int = randi_range(MIN_ROOMS, MAX_ROOMS)
	count = min(count, all_types.size())

	GameManager.roguelike_total_rooms  = count
	GameManager.roguelike_room_types   = all_types.slice(0, count)
	GameManager.roguelike_current_room = 0
	# Keep roguelike_active = true; the run continues

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
