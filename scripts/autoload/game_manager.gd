extends Node
## Autoload singleton for managing game state and statistics.
##
## Tracks player statistics like kills, shots fired, accuracy, and game state.
## Provides functionality for scene restart and game-wide events.

## Total enemies killed in current session.
var kills: int = 0

## Cumulative kills made without the Laser Sight active item equipped.
## Persists across sessions — used as the unlock condition for Laser Sight (Issue #1196).
var kills_without_laser_sight: int = 0

## Cumulative shots fired with shotgun, sniper rifle, or revolver.
## Persists across sessions — used as the unlock condition for Fine Motor Skills (Issue #1346).
var shots_fired_special_weapons: int = 0

## Weapon IDs that count toward the Fine Motor Skills unlock condition (Issue #1346).
const FINE_MOTOR_SKILLS_WEAPONS: Array[String] = ["shotgun", "sniper", "revolver"]

## Total shots fired in current session.
var shots_fired: int = 0

## Total hits landed in current session.
var hits_landed: int = 0

## Whether the player is currently alive.
var player_alive: bool = true

## Reference to the current player node.
var player: Node2D = null

## Whether debug mode is enabled (shows debug labels on enemies).
## Toggle with F7 key - delegated to ExperimentalSettings for persistence.
var debug_mode_enabled: bool = false

## Whether invincibility mode is enabled (player takes no damage).
## Toggle with F6 key - delegated to ExperimentalSettings for persistence.
var invincibility_enabled: bool = false

## Currently selected weapon ID for player equipment.
## Valid values: "makarov_pm", "m16", "shotgun", "mini_uzi", "silenced_pistol", "sniper", "revolver", "ak_gl" (corresponds to armory_menu WEAPONS keys)
## Default: "makarov_pm" (Makarov PM starting pistol)
var selected_weapon: String = "makarov_pm"

## Unlocked weapons tracking.
## PM is always unlocked (starting weapon).
## Weapons with unlock conditions (shotgun, mini_uzi, sniper, revolver) start locked.
## All other weapons (m16, silenced_pistol, ak_gl) are freely available from the start.
## Weapons can be unlocked by holding LMB on their case in the armory menu once condition is met.
## Issue #894: "all unspecified items can be opened from the start"
var unlocked_weapons: Dictionary = {
	"makarov_pm": true,
	"m16": true,       # No unlock condition — freely available from start
	"shotgun": false,  # Condition: Building D+
	"mini_uzi": false, # Condition: Labyrinth D+
	"silenced_pistol": true,  # No unlock condition — freely available from start
	"sniper": false,   # Condition: Polygon D+
	"revolver": false, # Condition: Castle F+
	"ak_gl": true,     # No unlock condition — freely available from start
	"smg": false       # Coming soon — not yet available
}

## Weapon scene paths mapped to weapon IDs.
const WEAPON_SCENES: Dictionary = {
	"makarov_pm": "res://scenes/weapons/csharp/MakarovPM.tscn",
	"m16": "res://scenes/weapons/csharp/AssaultRifle.tscn",
	"shotgun": "res://scenes/weapons/csharp/Shotgun.tscn",
	"mini_uzi": "res://scenes/weapons/csharp/MiniUzi.tscn",
	"silenced_pistol": "res://scenes/weapons/csharp/SilencedPistol.tscn",
	"sniper": "res://scenes/weapons/csharp/SniperRifle.tscn",
	"revolver": "res://scenes/weapons/csharp/Revolver.tscn",
	"ak_gl": "res://scenes/weapons/csharp/AKGL.tscn"
}

## Signal emitted when an enemy is killed (for screen effects).
signal enemy_killed

## Signal emitted when kills_without_laser_sight changes (for kill-based unlock checks).
## Issue #1196.
signal kills_without_laser_sight_updated(new_count: int)

## Signal emitted when shots_fired_special_weapons changes (for shot-based unlock checks).
## Issue #1346.
signal shots_fired_special_weapons_updated(new_count: int)

## Signal emitted when player dies.
signal player_died

## Signal emitted when game stats change.
signal stats_updated

## Signal emitted when debug mode is toggled (F7 key).
signal debug_mode_toggled(enabled: bool)

## Signal emitted when invincibility mode is toggled (F6 key).
signal invincibility_toggled(enabled: bool)

## Signal emitted when weapon selection changes.
signal weapon_selected(weapon_id: String)

## Signal emitted when a weapon is unlocked.
signal weapon_unlocked(weapon_id: String)

## Timer accumulator for F8 hold-to-spawn (Issue #1112).
## Tracks how long F8 has been held. Resets on key release.
var _f8_hold_time: float = 0.0

## Whether F8 is currently being held down (Issue #1112).
var _f8_held: bool = false

## Whether a spawn was already triggered during the current F8 hold (Issue #1112).
## Prevents repeated spawns while the key is held.
var _f8_spawn_triggered: bool = false

## Hold duration in seconds required to trigger F8 spawn (Issue #1112).
const F8_HOLD_THRESHOLD: float = 0.2

## ── Roguelike session state (Issue #1061) ─────────────────────────────────
## Persists across room-to-room scene reloads so the run can advance
## one room at a time (Binding of Isaac style).

## Whether a roguelike run is currently active.
var roguelike_active: bool = false

## 0-based index of the room currently being played.
var roguelike_current_room: int = 0

## Total number of rooms planned for this run (3–5, chosen at run start).
var roguelike_total_rooms: int = 0

## Predetermined sequence of RoomType values for the full run.
## Stored as Array so the room order is fixed for the entire run.
var roguelike_room_types: Array = []

## Initial random seed for the run (for reproducibility / future sharing).
var roguelike_run_seed: int = 0

## Accumulated kills across all rooms in the current run.
var roguelike_total_kills: int = 0

## Accumulated shots across all rooms in the current run.
var roguelike_total_shots: int = 0

## Accumulated hits across all rooms in the current run.
var roguelike_total_hits: int = 0

## Saved weapon selection before roguelike started (restored on exit/death).
var roguelike_saved_weapon: String = ""

## Current stage/level number within the roguelike run (1 = first level, increments each time
## all rooms of a level are cleared and the treasure room is passed).
var roguelike_current_level: int = 1

## Whether the player is currently inside the treasure room
## (the special room shown between a completed level and the next level).
var roguelike_in_treasure_room: bool = false

## Weapon the player is currently carrying through the roguelike run.
## Set when the player picks up a weapon from a treasure pedestal.
## Empty string means the default Makarov PM starting weapon.
var roguelike_run_weapon: String = ""

## Items already offered in treasure rooms during this run (Issue #1313).
## Each entry is either a weapon ID String or an int ActiveItemType.
## Used to prevent the same item from appearing on a pedestal twice in one run.
var roguelike_offered_items: Array = []

## Resets all roguelike session variables to their default (not-in-run) state.
func roguelike_reset_session() -> void:
	roguelike_active = false
	roguelike_current_room = 0
	roguelike_total_rooms = 0
	roguelike_room_types = []
	roguelike_run_seed = 0
	roguelike_total_kills = 0
	roguelike_total_shots = 0
	roguelike_total_hits = 0
	roguelike_saved_weapon = ""
	roguelike_current_level = 1
	roguelike_in_treasure_room = false
	roguelike_run_weapon = ""
	roguelike_offered_items = []


func _ready() -> void:
	# Reset stats when starting
	_reset_stats()
	# Set mouse mode: confined and hidden (keeps cursor within window and hides it)
	# This provides immersive fullscreen gameplay experience
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
	# Set PROCESS_MODE_ALWAYS to ensure quick restart (Q key) works during time freeze effects
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Sync debug/invincibility state from ExperimentalSettings (persisted)
	_sync_from_experimental_settings()
	# Log that GameManager is ready
	_log_to_file("GameManager ready")


func _input(event: InputEvent) -> void:
	# Handle quick restart with Q key
	if event is InputEventKey:
		if event.pressed and event.physical_keycode == KEY_Q:
			restart_scene()
		# Handle invincibility toggle with F6 key (works in exported builds)
		elif event.pressed and event.physical_keycode == KEY_F6:
			toggle_invincibility()
		# Handle debug mode toggle with F7 key (works in exported builds)
		elif event.pressed and event.physical_keycode == KEY_F7:
			toggle_debug_mode()
		# Track F8 press/release for hold-to-spawn (Issue #1112)
		elif event.physical_keycode == KEY_F8:
			if event.pressed and not event.echo:
				_f8_held = true
				_f8_hold_time = 0.0
				_f8_spawn_triggered = false
			elif not event.pressed:
				_f8_held = false
				_f8_hold_time = 0.0
				_f8_spawn_triggered = false


func _process(delta: float) -> void:
	# F8 hold-to-spawn: after holding F8 for 200ms outside a menu, spawn the selected enemy (Issue #1112).
	if _f8_held and not _f8_spawn_triggered:
		_f8_hold_time += delta
		if _f8_hold_time >= F8_HOLD_THRESHOLD:
			_f8_spawn_triggered = true
			_spawn_selected_enemy_at_player()


## Resets all statistics to initial values.
func _reset_stats() -> void:
	kills = 0
	shots_fired = 0
	hits_landed = 0
	player_alive = true
	player = null


## Registers a shot fired by the player.
## Also increments shots_fired_special_weapons when the selected weapon qualifies (Issue #1346).
func register_shot() -> void:
	shots_fired += 1
	stats_updated.emit()
	# Track shots with special weapons for Fine Motor Skills unlock (Issue #1346).
	if selected_weapon in FINE_MOTOR_SKILLS_WEAPONS:
		shots_fired_special_weapons += 1
		shots_fired_special_weapons_updated.emit(shots_fired_special_weapons)
		_log_to_file("shots_fired_special_weapons: %d (weapon: %s)" % [shots_fired_special_weapons, selected_weapon])


## Registers a hit landed by the player.
func register_hit() -> void:
	hits_landed += 1
	stats_updated.emit()


## Registers an enemy kill.
## @param is_player_kill: Whether the kill was made by the player (not enemy-vs-enemy). Issue #1196.
## Also increments kills_without_laser_sight only for player kills without any laser sight active (Issue #1196).
func register_kill(is_player_kill: bool = true) -> void:
	kills += 1
	enemy_killed.emit()
	stats_updated.emit()
	# Only count kills made by the player toward the Laser Sight unlock condition (Issue #1196).
	# Kills by enemies against other enemies do not count.
	if not is_player_kill:
		_log_to_file("register_kill: skipping non-player kill (enemy-vs-enemy or ally-vs-enemy)")
		return
	# Track kills made without ANY laser sight active (used for the Laser Sight unlock condition).
	# This covers all laser sight sources: active item, Power Fantasy difficulty, or weapon-level (Issue #1196).
	var active_item_manager: Node = get_node_or_null("/root/ActiveItemManager")
	var has_laser: bool = false
	if active_item_manager and active_item_manager.has_method("has_any_laser_sight_active"):
		has_laser = active_item_manager.has_any_laser_sight_active()
	elif active_item_manager and active_item_manager.has_method("has_laser_sight"):
		# Fallback: only check active item (e.g. early startup tests).
		has_laser = active_item_manager.has_laser_sight()
	if not has_laser:
		kills_without_laser_sight += 1
		kills_without_laser_sight_updated.emit(kills_without_laser_sight)
		_log_to_file("kills_without_laser_sight: %d" % kills_without_laser_sight)
	else:
		_log_to_file("register_kill: laser sight active — kill not counted toward unlock condition")


## Returns the current accuracy as a percentage (0-100).
func get_accuracy() -> float:
	if shots_fired == 0:
		return 0.0
	return (float(hits_landed) / float(shots_fired)) * 100.0


## Called when the player dies.
func on_player_death() -> void:
	player_alive = false
	player_died.emit()
	# Auto-restart the scene immediately
	restart_scene()


## Restarts the current scene.
## Resets mouse mode to hidden before reloading so the cursor does not persist
## from the score screen (Issue #905).
func restart_scene() -> void:
	_reset_stats()
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
	get_tree().reload_current_scene()


## Sets the player reference.
func set_player(p: Node2D) -> void:
	player = p


## Toggles debug mode on/off.
## When enabled, shows debug labels on enemies (AI state).
## Delegates to ExperimentalSettings for persistence.
func toggle_debug_mode() -> void:
	debug_mode_enabled = not debug_mode_enabled
	debug_mode_toggled.emit(debug_mode_enabled)
	# Sync to ExperimentalSettings for persistence
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings and experimental_settings.has_method("set_debug_mode_enabled"):
		experimental_settings.set_debug_mode_enabled(debug_mode_enabled)
	_log_to_file("Debug mode toggled: %s" % ("ON" if debug_mode_enabled else "OFF"))


## Returns whether debug mode is currently enabled.
func is_debug_mode_enabled() -> bool:
	return debug_mode_enabled


## Toggles invincibility mode on/off.
## When enabled, player takes no damage from any source.
## Delegates to ExperimentalSettings for persistence.
func toggle_invincibility() -> void:
	invincibility_enabled = not invincibility_enabled
	invincibility_toggled.emit(invincibility_enabled)
	# Sync to ExperimentalSettings for persistence
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings and experimental_settings.has_method("set_invincibility_enabled"):
		experimental_settings.set_invincibility_enabled(invincibility_enabled)
	_log_to_file("Invincibility mode toggled: %s" % ("ON" if invincibility_enabled else "OFF"))


## Returns whether invincibility mode is currently enabled.
func is_invincibility_enabled() -> bool:
	return invincibility_enabled


## Syncs debug mode and invincibility state from ExperimentalSettings.
## Called on _ready() to restore persisted state.
func _sync_from_experimental_settings() -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		if experimental_settings.has_method("is_debug_mode_enabled"):
			var saved_debug: bool = experimental_settings.is_debug_mode_enabled()
			if saved_debug != debug_mode_enabled:
				debug_mode_enabled = saved_debug
				debug_mode_toggled.emit(debug_mode_enabled)
		if experimental_settings.has_method("is_invincibility_enabled"):
			var saved_invincibility: bool = experimental_settings.is_invincibility_enabled()
			if saved_invincibility != invincibility_enabled:
				invincibility_enabled = saved_invincibility
				invincibility_toggled.emit(invincibility_enabled)


## Sets the currently selected weapon.
## @param weapon_id: The weapon identifier (e.g., "m16", "shotgun")
func set_selected_weapon(weapon_id: String) -> void:
	if weapon_id in WEAPON_SCENES:
		selected_weapon = weapon_id
		weapon_selected.emit(weapon_id)
		_log_to_file("Weapon selected: %s" % weapon_id)
	else:
		push_warning("Unknown weapon ID: %s" % weapon_id)


## Gets the currently selected weapon ID.
func get_selected_weapon() -> String:
	return selected_weapon


## Gets the scene path for the selected weapon.
func get_selected_weapon_scene_path() -> String:
	if selected_weapon in WEAPON_SCENES:
		return WEAPON_SCENES[selected_weapon]
	return WEAPON_SCENES["makarov_pm"]  # Default to Makarov PM starting pistol


## Check if a weapon is unlocked.
## @param weapon_id: The weapon identifier to check.
## @return: true if the weapon is unlocked, false otherwise.
## Note: If all_weapons_unlocked is enabled in ExperimentalSettings, all weapons return true.
func is_weapon_unlocked(weapon_id: String) -> bool:
	# Check if all weapons are unlocked via experimental setting (Issue #882)
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings and experimental_settings.has_method("is_all_weapons_unlocked"):
		if experimental_settings.is_all_weapons_unlocked():
			return true
	return unlocked_weapons.get(weapon_id, false)


## Unlock a weapon.
## @param weapon_id: The weapon identifier to unlock.
func unlock_weapon(weapon_id: String) -> void:
	if weapon_id in unlocked_weapons:
		if not unlocked_weapons[weapon_id]:
			unlocked_weapons[weapon_id] = true
			weapon_unlocked.emit(weapon_id)
			_log_to_file("Weapon unlocked: %s" % weapon_id)


## Get all unlocked weapons.
## @return: Dictionary of weapon_id -> bool pairs.
func get_unlocked_weapons() -> Dictionary:
	return unlocked_weapons


## Spawn the selected enemy type near the player (Issue #1112).
## Used for F8 hold-to-spawn while outside the experimental menu.
func _spawn_selected_enemy_at_player() -> void:
	var scene: PackedScene = load("res://scenes/objects/Enemy.tscn")
	if scene == null:
		push_warning("[GameManager] F8 spawn: Enemy.tscn not found.")
		return

	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		push_warning("[GameManager] F8 spawn: No active scene.")
		return

	# Find player position for spawn offset.
	var p: Node = player
	if p == null:
		p = get_node_or_null("/root/Player")
	if p == null and current_scene:
		p = current_scene.find_child("Player", true, false)
	var spawn_pos: Vector2 = Vector2(400.0, 400.0)
	if p and p.get("global_position") != null:
		spawn_pos = p.global_position + Vector2(200.0, 0.0)

	# Get selected enemy type from ExperimentalSettings.
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	var selected_idx: int = 0
	if experimental_settings and experimental_settings.has_method("get_selected_enemy_type_index"):
		selected_idx = experimental_settings.get_selected_enemy_type_index()

	# Enemy type definitions (must match experimental_menu.gd _setup_enemy_spawner() order).
	var types: Array[Dictionary] = [
		{"name": "Rifle (M16)", "weapon_type": 0, "behavior": 1},
		{"name": "Shotgun", "weapon_type": 1, "behavior": 1},
		{"name": "UZI (SMG)", "weapon_type": 2, "behavior": 1},
		{"name": "Machete (melee)", "weapon_type": 3, "behavior": 1},
		{"name": "RPG + PM pistol", "weapon_type": 4, "behavior": 1},
		{"name": "PM (Makarov pistol)", "weapon_type": 5, "behavior": 1},
		{"name": "Machine Gunner (PKM)", "weapon_type": 6, "behavior": 1},
		{"name": "Sniper (ASVK)", "weapon_type": 7, "behavior": 1},
		{"name": "Patrol Rifle", "weapon_type": 0, "behavior": 0},
		{"name": "Teleporter (Rifle)", "weapon_type": 0, "behavior": 1, "is_teleporter": true},
		{"name": "Armored Skin (Rifle)", "weapon_type": 0, "behavior": 1, "has_armored_skin": true},
		{"name": "Force Field (Rifle)", "weapon_type": 0, "behavior": 1, "has_force_field": true},
		{"name": "Grenadier (Rifle)", "weapon_type": 0, "behavior": 1, "is_grenadier": true},
		{"name": "Invisible (Rifle)", "weapon_type": 0, "behavior": 1, "start_invisible": true},
	]
	if selected_idx < 0 or selected_idx >= types.size():
		selected_idx = 0
	var meta: Dictionary = types[selected_idx]

	# Instantiate and configure.
	var enemy: Node = scene.instantiate()
	enemy.global_position = spawn_pos
	if enemy.get("weapon_type") != null:
		enemy.set("weapon_type", meta.get("weapon_type", 0))
	if enemy.get("behavior_mode") != null:
		enemy.set("behavior_mode", meta.get("behavior", 1))
	if enemy.get("destroy_on_death") != null:
		enemy.set("destroy_on_death", true)
	# Apply special enemy flags if present in metadata.
	if meta.get("is_teleporter", false) and enemy.get("is_teleporter") != null:
		enemy.set("is_teleporter", true)
	if meta.get("has_armored_skin", false) and enemy.get("has_armored_skin") != null:
		enemy.set("has_armored_skin", true)
	if meta.get("has_force_field", false) and enemy.get("has_force_field") != null:
		enemy.set("has_force_field", true)
	if meta.get("is_grenadier", false) and enemy.get("is_grenadier") != null:
		enemy.set("is_grenadier", true)
	if meta.get("start_invisible", false) and enemy.get("start_invisible") != null:
		enemy.set("start_invisible", true)

	# Add to Enemies node if it exists, otherwise directly to scene.
	var enemies_node: Node = current_scene.find_child("Enemies", true, false)
	if enemies_node:
		enemies_node.add_child(enemy)
	else:
		current_scene.add_child(enemy)

	_log_to_file("F8 spawn: '%s' at %s" % [meta.get("name", "Unknown"), str(spawn_pos)])


## Log a message to the file logger if available.
func _log_to_file(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[GameManager] " + message)
	else:
		print("[GameManager] " + message)
