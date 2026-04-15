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

## Cumulative total deaths across all sessions.
## Persists across sessions — used as the unlock condition for Armored Skin (Issue #1389).
var total_deaths: int = 0

## Cumulative levels completed without taking any damage.
## Persists across sessions — tracked for future use (Issue #1389).
var no_damage_levels_completed: int = 0

## Cumulative levels completed at rank A or higher (A, A+, or S).
## Persists across sessions — used as the unlock condition for Breaker Bullets (Issue #1589).
var levels_completed_rank_a_or_higher: int = 0

## Cumulative kills made through walls (using Drilling Bullets or any wall-piercing effect).
## Persists across sessions — used as the unlock condition for Drilling Bullets (Issue #1624).
var kills_through_wall: int = 0

## Cumulative levels completed while the silenced pistol was the selected weapon.
## Persists across sessions — used as the unlock condition for Auto Reload (Issue #1624).
var levels_completed_with_silenced_pistol: int = 0

## Set to true while the animated score screen animation is playing.
## Blocks the Q-key quick-restart shortcut so the player cannot accidentally skip the
## score screen before seeing the Armory button (Issue #1589).
var score_screen_active: bool = false

## Weapon IDs that count toward the Fine Motor Skills unlock condition (Issue #1346).
const FINE_MOTOR_SKILLS_WEAPONS: Array[String] = ["shotgun", "sniper", "revolver"]

## Total shots fired in current session.
var shots_fired: int = 0

## Total hits landed in current session.
var hits_landed: int = 0

## Whether the player is currently alive.
var player_alive: bool = true

## Issue #1334 Round 9: Absolute wall-clock timestamp (msec) when player_alive was
## last set to false. Used as an ultimate failsafe — if the player has been dead for
## more than 5 real seconds (regardless of _reloading, time_scale, scene state, etc.),
## force a scene restart. This catches ALL edge cases where the normal death pipeline
## fails: stuck timers, signal failures, C# exceptions, physics server crashes that
## don't terminate the process, etc. Set to 0 when player is alive.
var _player_dead_since_ms: int = 0

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
## Weapons with unlock conditions (shotgun, mini_uzi, sniper, revolver, m16) start locked.
## All other weapons (silenced_pistol, ak_gl) are freely available from the start.
## Weapons can be unlocked by holding LMB on their case in the armory menu once condition is met.
## Issue #894: "all unspecified items can be opened from the start"
var unlocked_weapons: Dictionary = {
	"makarov_pm": true,
	"m16": false,      # Condition: Beach D+ (Issue #1053 req.3)
	"shotgun": false,  # Condition: Building D+
	"mini_uzi": false, # Condition: Labyrinth D+
	"silenced_pistol": true,  # No unlock condition — freely available from start
	"sniper": false,   # Condition: Polygon D+
	"revolver": false, # Condition: Castle F+
	"ak_gl": true      # No unlock condition — freely available from start
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

## Signal emitted when total_deaths changes (for death-based unlock checks).
## Issue #1389.
signal total_deaths_updated(new_count: int)

## Signal emitted when no_damage_levels_completed changes.
## Issue #1389.
signal no_damage_levels_completed_updated(new_count: int)

## Signal emitted when levels_completed_rank_a_or_higher changes (for rank-A unlock checks).
## Issue #1589.
signal levels_completed_rank_a_or_higher_updated(new_count: int)

## Signal emitted when kills_through_wall changes (for wall-kill unlock checks).
## Issue #1624.
signal kills_through_wall_updated(new_count: int)

## Signal emitted when levels_completed_with_silenced_pistol changes.
## Issue #1624.
signal levels_completed_with_silenced_pistol_updated(new_count: int)

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

## Whether Q is currently being held down for quick restart (Issue #1822).
var _q_restart_held: bool = false

## Tracks how long Q has been held for quick restart (Issue #1822).
var _q_restart_hold_time: float = 0.0

## Whether quick restart already triggered during the current Q hold (Issue #1822).
var _q_restart_triggered: bool = false

## Hold duration in seconds required to trigger quick restart with Q (Issue #1822).
const Q_RESTART_HOLD_THRESHOLD: float = 2.0

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

## ── Branching room map state (Issue #1399) ───────────────────────────────
## Each level generates an Isaac-style grid map of rooms with branching paths.
## Players can navigate freely between connected rooms and skip optional ones.

## Array of room dictionaries for the current level.
## Each entry: {grid_pos: Vector2i, room_type: int, connections: Array[int],
##              map_room_type: String, cleared: bool, visited: bool}
## map_room_type is one of: "start", "combat", "treasure", "exit"
## connections is an array of room indices this room connects to.
var roguelike_room_map: Array = []

## Index into roguelike_room_map for the room currently being played.
var roguelike_current_map_room: int = 0

## Set of room indices that have been visited (so minimap can show them).
var roguelike_visited_rooms: Array = []

## Target room index when player enters a door (used during scene reload).
var roguelike_target_room: int = -1

## Source room index — the room player was in before navigating (Issue #1399).
## Used to determine spawn position in the new room.
var roguelike_source_room: int = -1

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
	roguelike_room_map = []
	roguelike_current_map_room = 0
	roguelike_visited_rooms = []
	roguelike_target_room = -1
	roguelike_source_room = -1


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
	# Connect to ScoreManager to track no-damage level completions (Issue #1389)
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager and score_manager.has_signal("score_calculated"):
		score_manager.score_calculated.connect(_on_score_calculated)
	# Log that GameManager is ready
	_log_to_file("GameManager ready")


func _input(event: InputEvent) -> void:
	# Handle quick restart with Q key
	if event is InputEventKey:
		if event.physical_keycode == KEY_Q:
			# Block restart while the score screen animation is playing — the player
			# may not have seen the Armory button yet (Issue #1589).
			if score_screen_active:
				if not event.pressed:
					_reset_q_restart_hold()
				return
			if event.pressed and not event.echo:
				_q_restart_held = true
				_q_restart_hold_time = 0.0
				_q_restart_triggered = false
			elif not event.pressed:
				_reset_q_restart_hold()
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
	if _q_restart_held and not _q_restart_triggered:
		if score_screen_active:
			_reset_q_restart_hold()
		else:
			_q_restart_hold_time += delta
			if _q_restart_hold_time >= Q_RESTART_HOLD_THRESHOLD:
				_q_restart_triggered = true
				restart_scene()

	# F8 hold-to-spawn: after holding F8 for 200ms outside a menu, spawn the selected enemy (Issue #1112).
	if _f8_held and not _f8_spawn_triggered:
		_f8_hold_time += delta
		if _f8_hold_time >= F8_HOLD_THRESHOLD:
			_f8_spawn_triggered = true
			_spawn_selected_enemy_at_player()

	# Issue #1334 Round 4: Poll-based death detection safety net.
	# Signal-based connection from GDScript to C# Died signal can silently fail
	# (has_signal() returns false for inherited C# signals in some Godot builds).
	# This polling approach detects player death regardless of signal connection status.
	# We detect death by checking collision_layer == 0, which Player.OnDeath() sets
	# immediately on death. This is a standard Godot property accessible from GDScript.
	if not _reloading and not _death_detected_by_poll and player and is_instance_valid(player):
		if player is CharacterBody2D and player.collision_layer == 0:
			_death_detected_by_poll = true
			# Issue #1334 Round 5: Also set player_alive = false here for enemy shoot prevention
			# when signal connection failed and poll is the first detection method.
			if player_alive:
				player_alive = false
				# Issue #1334 Round 9: Record wall-clock timestamp for absolute failsafe
				if _player_dead_since_ms <= 0:
					_player_dead_since_ms = Time.get_ticks_msec()
				_log_to_file("POLL DETECTED: Player collision_layer is 0 (dead) but player_alive was still true! Starting safety net.")
			else:
				_log_to_file("POLL DETECTED: Player collision_layer is 0 (confirming death already flagged)")
			_start_death_safety_net()

	# Issue #1334 Round 8: Wall-clock safety net using OS.get_ticks_msec().
	# Previous rounds used delta-based countdown, but delta is scaled by Engine.time_scale.
	# Death effects (PenultimateHit, LastChance) modify time_scale to 0.1, making the
	# 1.5s countdown take 15 real seconds. The user sees a grey screen and thinks the game
	# is stuck. Using wall-clock time guarantees the restart fires in real-world seconds
	# regardless of Engine.time_scale or any other timing manipulation.
	if _safety_net_deadline_ms > 0:
		if Time.get_ticks_msec() >= _safety_net_deadline_ms:
			_safety_net_deadline_ms = 0
			_on_death_safety_net_timer()

	# Issue #1334 Round 9: ABSOLUTE failsafe — if the player has been dead for more than
	# 5 real seconds (wall-clock) and no restart has happened, force one. This catches ALL
	# edge cases: stuck timers, signal failures, C# exceptions, physics crashes that don't
	# terminate the process, _reloading flag stuck, etc. The 5s threshold is generous enough
	# to let normal death effects play out, but short enough that the user won't think the
	# game is frozen. Unlike the 1.5s safety net which can be blocked by _reloading flag or
	# other guards, this failsafe IGNORES all guards.
	if _player_dead_since_ms > 0 and not player_alive:
		var dead_duration_ms: int = Time.get_ticks_msec() - _player_dead_since_ms
		if dead_duration_ms >= 5000:
			_log_to_file("ABSOLUTE FAILSAFE: Player dead for %d ms — forcing restart (ignoring all guards)" % dead_duration_ms)
			# Reset the timestamp to NOW + 5s so the failsafe can re-trigger if this
			# restart attempt also fails. Only set_player() clears it permanently.
			_player_dead_since_ms = Time.get_ticks_msec()
			_reloading = false  # Force-clear in case it's stuck
			_safety_net_deadline_ms = 0
			# Check special modes that should NOT auto-restart
			if roguelike_active:
				_log_to_file("ABSOLUTE FAILSAFE: roguelike mode — skipping")
			else:
				var current_scene := get_tree().current_scene
				if current_scene and current_scene.scene_file_path.find("ArenaLevel") >= 0:
					_log_to_file("ABSOLUTE FAILSAFE: ArenaLevel — skipping")
				else:
					player_alive = false  # Ensure it stays false for the restart
					restart_scene()


## Resets all statistics to initial values.
## Issue #1334 Round 9: player_alive is NOT reset here — it stays false until
## set_player() is called with a valid new player. Previously, _reset_stats() set
## player_alive = true BEFORE reload_current_scene() completed (reload is deferred).
## This created a window where enemies saw player_alive = true but the old player
## node was in a transitional/freed state, causing native segfaults. Now player_alive
## remains false throughout the reload transition and is only set true when the new
## scene's player is registered.
func _reset_stats() -> void:
	kills = 0
	shots_fired = 0
	hits_landed = 0
	# player_alive intentionally NOT reset here — see set_player()
	_death_signal_received = false
	_death_detected_by_poll = false
	_safety_net_deadline_ms = 0
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
## @param is_penetration_kill: Whether the kill was made through a wall (drilling/penetration). Issue #1624.
## Also increments kills_without_laser_sight only for player kills without any laser sight active (Issue #1196).
## Also increments kills_through_wall for player penetration kills (Issue #1624).
func register_kill(is_player_kill: bool = true, is_penetration_kill: bool = false) -> void:
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
	# Track kills through walls for Drilling Bullets unlock condition (Issue #1624).
	if is_penetration_kill:
		kills_through_wall += 1
		kills_through_wall_updated.emit(kills_through_wall)
		_log_to_file("kills_through_wall: %d" % kills_through_wall)


## Returns the current accuracy as a percentage (0-100).
func get_accuracy() -> float:
	if shots_fired == 0:
		return 0.0
	return (float(hits_landed) / float(shots_fired)) * 100.0


## Called when the player dies.
## Issue #1334: Guard against duplicate calls — both level GDScript and
## LevelInitFallback.cs may call this method via their 0.5s timers.
## Round 3: GameManager now handles restart via its own signal connection
## (_on_player_died_signal), so this method is kept as a legacy entry point
## for level scripts that still call it.
## Round 5: Changed guard from player_alive to _reloading, because player_alive
## is now set to false immediately on death signal (to prevent enemies from shooting).
func on_player_death() -> void:
	_log_to_file("on_player_death() called (legacy entry point)")
	if _reloading:
		_log_to_file("on_player_death() — already reloading, skipping")
		return
	player_alive = false
	# Track cumulative death count for Armored Skin unlock (Issue #1389)
	total_deaths += 1
	total_deaths_updated.emit(total_deaths)
	_log_to_file("total_deaths: %d" % total_deaths)
	# Issue #1334 Round 9: Record wall-clock timestamp of death for absolute failsafe
	if _player_dead_since_ms <= 0:
		_player_dead_since_ms = Time.get_ticks_msec()
	# Issue #1334 Round 10: Defer collision disable for safety
	if player and is_instance_valid(player):
		if player is CharacterBody2D:
			player.call_deferred("set", "collision_layer", 0)
			player.call_deferred("set", "collision_mask", 0)
	player_died.emit()
	# Auto-restart the scene immediately
	restart_scene()


## Whether a scene reload is already in progress (Issue #1334).
var _reloading: bool = false


## Restarts the current scene.
## Resets mouse mode to hidden before reloading so the cursor does not persist
## from the score screen (Issue #905).
## Issue #1334: Prevents re-entrant calls while a reload is already underway.
func restart_scene() -> void:
	if _reloading:
		_log_to_file("restart_scene() — already reloading, skipping")
		return
	_log_to_file("restart_scene() — starting scene reload")
	_reloading = true
	_reset_stats()
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
	get_tree().reload_current_scene()
	# Issue #1334: Reset the reload guard after the current frame ends.
	# call_deferred runs at the end of the frame, after reload_current_scene()
	# has processed.  GameManager is an autoload so it persists across reloads.
	call_deferred("_reset_reloading")


## Issue #1334: Deferred callback to clear the reload guard.
func _reset_reloading() -> void:
	_reloading = false


func _reset_q_restart_hold() -> void:
	_q_restart_held = false
	_q_restart_hold_time = 0.0
	_q_restart_triggered = false


## Sets the player reference and connects to the player's death signal.
## Issue #1334 Round 3: GameManager now directly listens for the player Died signal
## instead of relying on level scripts' fragile 0.5s timer + await coroutine.
## This ensures restart always fires regardless of level script behavior.
func set_player(p: Node2D) -> void:
	_log_to_file("set_player() called with: %s (class: %s)" % [str(p), p.get_class() if p else "null"])
	# Disconnect from previous player if any
	if player and is_instance_valid(player):
		if player.has_signal("Died") and player.is_connected("Died", _on_player_died_signal):
			player.disconnect("Died", _on_player_died_signal)
		elif player.has_signal("died") and player.is_connected("died", _on_player_died_signal):
			player.disconnect("died", _on_player_died_signal)
	player = p
	# Issue #1334 Round 9: Reset player_alive = true HERE (not in _reset_stats).
	# This ensures player_alive stays false during the entire scene reload transition
	# and only becomes true when the new player node is registered.
	if p and is_instance_valid(p):
		player_alive = true
		_player_dead_since_ms = 0  # Clear absolute failsafe timestamp
		_log_to_file("set_player: player_alive reset to true (new player registered)")
	# Connect to new player's death signal
	if player and is_instance_valid(player):
		var has_died_upper := player.has_signal("Died")
		var has_died_lower := player.has_signal("died")
		_log_to_file("set_player: has_signal('Died')=%s, has_signal('died')=%s" % [str(has_died_upper), str(has_died_lower)])
		if has_died_upper:
			if not player.is_connected("Died", _on_player_died_signal):
				player.connect("Died", _on_player_died_signal)
				_log_to_file("Connected to player 'Died' signal (C# naming)")
		elif has_died_lower:
			if not player.is_connected("died", _on_player_died_signal):
				player.connect("died", _on_player_died_signal)
				_log_to_file("Connected to player 'died' signal (GDScript naming)")
		else:
			_log_to_file("WARNING: Player has neither 'Died' nor 'died' signal — poll-based detection (collision_layer check) will be used as fallback")
		# Issue #1334 Round 4: Log collision_layer as baseline for poll-based detection
		if player is CharacterBody2D:
			_log_to_file("set_player: initial collision_layer=%d (poll expects 0 on death)" % player.collision_layer)


## Issue #1334 Round 3: Direct signal handler for player death.
## Called immediately when the player's Died/died signal fires.
## This acts as a SAFETY NET: it starts a timer, and when it fires,
## checks if restart was already triggered. If not, GameManager forces restart.
## This prevents the "grey death screen" bug where level scripts' await-based
## timers silently fail to trigger restart in exported builds.
func _on_player_died_signal() -> void:
	_log_to_file("Player Died signal received — starting safety net timer")
	_death_signal_received = true
	# Issue #1334 Round 5: Set player_alive = false IMMEDIATELY on death signal.
	# This is critical because enemies check player_alive before shooting.
	# Previously, player_alive was only set to false in on_player_death() (0.5-1.5s later),
	# allowing enemies (especially snipers) to shoot at the dead player on the same frame.
	player_alive = false
	# Issue #1334 Round 9: Record wall-clock timestamp of death for absolute failsafe
	if _player_dead_since_ms <= 0:
		_player_dead_since_ms = Time.get_ticks_msec()
	# Issue #1334 Round 10: Defer collision disable to avoid modifying physics state
	# during active physics callbacks (body_entered/area_entered). Setting CollisionLayer
	# inside a physics callback corrupts the physics server's collision pair list, causing
	# native segfaults. The player's own OnDeath() also defers this, but we do it here as
	# defense-in-depth in case the player's deferred call doesn't fire.
	if player and is_instance_valid(player):
		if player is CharacterBody2D:
			player.call_deferred("set", "collision_layer", 0)
			player.call_deferred("set", "collision_mask", 0)
			_log_to_file("Disabled dead player collision from GameManager signal handler")
	_start_death_safety_net()


## Issue #1334 Round 8: Wall-clock deadline (in msec from OS.get_ticks_msec()) for the safety net.
## When Time.get_ticks_msec() >= this value, _on_death_safety_net_timer() fires.
## Using wall-clock time (OS ticks) instead of delta-based countdown because:
## - SceneTreeTimers can silently fail (documented in Rounds 3-6)
## - delta-based countdown is scaled by Engine.time_scale (Round 7 issue — death effects
##   set time_scale to 0.1, making a 1.5s countdown take 15 real seconds)
## Set to 0 when inactive. Reset by _reset_stats() during restart.
var _safety_net_deadline_ms: int = 0

## Issue #1334 Round 4/8: Shared helper to start the death safety net timer.
## Called by both signal handler (_on_player_died_signal) and poll detection (_process).
func _start_death_safety_net() -> void:
	# Issue #1334 Round 10: Defer collision disable (defense-in-depth).
	# This may be called from a signal handler during physics callbacks.
	if player and is_instance_valid(player):
		if player is CharacterBody2D:
			player.call_deferred("set", "collision_layer", 0)
			player.call_deferred("set", "collision_mask", 0)
			_log_to_file("Disabled dead player collision (safety net)")
	# Issue #1334 Round 8: Use wall-clock deadline (OS ticks) instead of delta countdown.
	# Previous approach (delta -= in _process) was scaled by Engine.time_scale. Death effects
	# set time_scale to 0.1, making a 1.5s countdown take 15 real seconds — the user sees a
	# grey screen stuck. OS.get_ticks_msec() is unaffected by time_scale, so the deadline fires
	# in real-world time. The 1.5s delay gives level scripts time to call on_player_death() first.
	# Only start if not already counting down (avoid resetting an in-progress deadline).
	if _safety_net_deadline_ms <= 0:
		_safety_net_deadline_ms = Time.get_ticks_msec() + 1500
		_log_to_file("Safety net deadline set (1.5 real seconds, wall-clock based)")


## Whether the death signal was received but restart hasn't happened yet.
## Reset by _reset_stats() during restart or scene change.
var _death_signal_received: bool = false

## Whether the poll-based death detection has fired (prevents repeated timer starts).
## Issue #1334 Round 4.
var _death_detected_by_poll: bool = false


## Issue #1334 Round 3: Safety net timer callback.
## Forces restart if the level script's death handler failed to trigger it.
## Issue #1334 Round 5: Only check _reloading (not player_alive), since player_alive
## is now set to false immediately on death signal for enemy shoot prevention.
func _on_death_safety_net_timer() -> void:
	# If restart is already in progress, nothing to do
	if _reloading:
		_log_to_file("Safety net timer fired — restart already in progress (_reloading=true)")
		return
	# If death wasn't detected by either signal or poll (shouldn't happen), skip
	if not _death_signal_received and not _death_detected_by_poll:
		_log_to_file("Safety net timer fired — but neither signal nor poll detected death, skipping")
		return
	# Check if we're in a special mode that handles death differently
	if roguelike_active:
		_log_to_file("Safety net timer fired — roguelike mode active, skipping auto-restart")
		return
	# Check if the current scene is ArenaLevel (handles death with score screen, not restart)
	var current_scene := get_tree().current_scene
	if current_scene and current_scene.scene_file_path.find("ArenaLevel") >= 0:
		_log_to_file("Safety net timer fired — ArenaLevel detected, skipping auto-restart")
		return
	# Nobody handled the death — force restart!
	_log_to_file("Safety net timer fired — no restart after 1.5s! Level script failed to restart. Forcing on_player_death()")
	on_player_death()


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
		{"name": "SWAT Shieldbearer", "weapon_type": 8, "behavior": 1, "has_swat_shield": true, "scene": "res://scenes/objects/EnemySwatShield.tscn"},  # Issue #1242
		{"name": "Teleporter (Rifle)", "weapon_type": 0, "behavior": 1, "is_teleporter": true},
		{"name": "Armored Skin (Rifle)", "weapon_type": 0, "behavior": 1, "has_armored_skin": true},
		{"name": "Force Field (Rifle)", "weapon_type": 0, "behavior": 1, "has_force_field": true},
		{"name": "Grenadier (Rifle)", "weapon_type": 0, "behavior": 1, "is_grenadier": true},
		{"name": "Invisible (Rifle)", "weapon_type": 0, "behavior": 1, "start_invisible": true},
		{"name": "Gas Mask Enemy", "weapon_type": 0, "behavior": 1, "is_gas_mask": true},
		{"name": "Drone Operator", "weapon_type": 0, "behavior": 1, "is_drone_operator": true, "scene": "res://scenes/objects/EnemyDroneOperator.tscn"},  # Issue #1397
	]
	if selected_idx < 0 or selected_idx >= types.size():
		selected_idx = 0
	var meta: Dictionary = types[selected_idx]

	# Use scene override if provided (e.g. EnemySwatShield.tscn for the shieldbearer).
	if meta.has("scene") and ResourceLoader.exists(meta["scene"]):
		scene = load(meta["scene"])

	# Instantiate and configure.
	var enemy: Node = scene.instantiate()
	enemy.global_position = spawn_pos
	if enemy.get("weapon_type") != null:
		enemy.set("weapon_type", meta.get("weapon_type", 0))
	if enemy.get("behavior_mode") != null:
		enemy.set("behavior_mode", meta.get("behavior", 1))
	if enemy.get("destroy_on_death") != null:
		enemy.set("destroy_on_death", true)
	if meta.has("has_swat_shield") and enemy.get("has_swat_shield") != null:
		enemy.set("has_swat_shield", meta.get("has_swat_shield", false))
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
	if meta.get("is_gas_mask", false) and enemy.get("is_gas_mask") != null:
		enemy.set("is_gas_mask", true)
	if meta.get("is_drone_operator", false) and enemy.get("is_drone_operator") != null:
		enemy.set("is_drone_operator", true)

	# Add to Enemies node if it exists, otherwise directly to scene.
	var enemies_node: Node = current_scene.find_child("Enemies", true, false)
	if enemies_node:
		enemies_node.add_child(enemy)
	else:
		current_scene.add_child(enemy)

	_log_to_file("F8 spawn: '%s' at %s" % [meta.get("name", "Unknown"), str(spawn_pos)])


## Called when ScoreManager emits score_calculated after level completion.
## Tracks levels completed without taking any damage for Combat Disposition unlock (Issue #1389).
## Also tracks levels completed at rank A or higher for Breaker Bullets unlock (Issue #1589).
## Also tracks levels completed with silenced pistol for Auto Reload unlock (Issue #1624).
func _on_score_calculated(score_data: Dictionary) -> void:
	var damage_taken: int = score_data.get("damage_taken", -1)
	_log_to_file("Level completed — damage_taken: %d" % damage_taken)
	if damage_taken == 0:
		no_damage_levels_completed += 1
		no_damage_levels_completed_updated.emit(no_damage_levels_completed)
		_log_to_file("No-damage level condition met — no_damage_levels_completed: %d" % no_damage_levels_completed)
	var rank: String = score_data.get("rank", "")
	# Ranks A, A+, and S all satisfy the "A or higher" condition (Issue #1589)
	const A_OR_HIGHER: Array = ["A", "A+", "S"]
	if rank in A_OR_HIGHER:
		# Only count each unique map once toward the unlock, regardless of difficulty (Issue #1749).
		# Check if this map was already completed at A-rank or higher on any difficulty before
		# this run (ProgressManager has not yet saved the current result at this point).
		var already_counted: bool = false
		var progress_manager: Node = get_node_or_null("/root/ProgressManager")
		if progress_manager and progress_manager.has_method("is_level_completed_rank_a_or_higher_any_difficulty"):
			var current_scene: Node = get_tree().current_scene
			if current_scene and not current_scene.scene_file_path.is_empty():
				already_counted = progress_manager.is_level_completed_rank_a_or_higher_any_difficulty(current_scene.scene_file_path)
		if not already_counted:
			levels_completed_rank_a_or_higher += 1
			levels_completed_rank_a_or_higher_updated.emit(levels_completed_rank_a_or_higher)
			_log_to_file("Rank-A level completed (new unique map) — levels_completed_rank_a_or_higher: %d" % levels_completed_rank_a_or_higher)
		else:
			_log_to_file("Rank-A level completed (already counted for this map) — levels_completed_rank_a_or_higher unchanged: %d" % levels_completed_rank_a_or_higher)
	# Track levels completed with silenced pistol for Auto Reload unlock (Issue #1624).
	if selected_weapon == "silenced_pistol":
		levels_completed_with_silenced_pistol += 1
		levels_completed_with_silenced_pistol_updated.emit(levels_completed_with_silenced_pistol)
		_log_to_file("Level completed with silenced pistol — levels_completed_with_silenced_pistol: %d" % levels_completed_with_silenced_pistol)


## Log a message to the file logger if available.
func _log_to_file(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[GameManager] " + message)
	else:
		print("[GameManager] " + message)
