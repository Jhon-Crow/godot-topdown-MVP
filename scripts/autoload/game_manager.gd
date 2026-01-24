extends Node
## Autoload singleton for managing game state and statistics.
##
## Tracks player statistics like kills, shots fired, accuracy, and game state.
## Provides functionality for scene restart and game-wide events.

## Total enemies killed in current session.
var kills: int = 0

## Total shots fired in current session.
var shots_fired: int = 0

## Total hits landed in current session.
var hits_landed: int = 0

## Whether the player is currently alive.
var player_alive: bool = true

## Reference to the current player node.
var player: Node2D = null

## Whether debug mode is enabled (shows debug labels on enemies).
## Toggle with F7 key - works in both editor and exported builds.
var debug_mode_enabled: bool = false

## Whether invincibility mode is enabled (player takes no damage).
## Toggle with F6 key - works in both editor and exported builds.
## For debugging purposes only.
var invincibility_enabled: bool = false

## Currently selected weapon ID for player equipment.
## Valid values: "m16", "shotgun", "mini_uzi", "silenced_pistol" (corresponds to armory_menu WEAPONS keys)
## Default: "m16" (assault rifle)
var selected_weapon: String = "m16"

## Weapon scene paths mapped to weapon IDs.
const WEAPON_SCENES: Dictionary = {
	"m16": "res://scenes/weapons/csharp/AssaultRifle.tscn",
	"shotgun": "res://scenes/weapons/csharp/Shotgun.tscn",
	"mini_uzi": "res://scenes/weapons/csharp/MiniUzi.tscn",
	"silenced_pistol": "res://scenes/weapons/csharp/SilencedPistol.tscn"
}

## Signal emitted when an enemy is killed (for screen effects).
signal enemy_killed

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


func _ready() -> void:
	# Reset stats when starting
	_reset_stats()
	# Set mouse mode: confined and hidden (keeps cursor within window and hides it)
	# This provides immersive fullscreen gameplay experience
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
	# Set PROCESS_MODE_ALWAYS to ensure quick restart (Q key) works during time freeze effects
	process_mode = Node.PROCESS_MODE_ALWAYS
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


## Resets all statistics to initial values.
func _reset_stats() -> void:
	kills = 0
	shots_fired = 0
	hits_landed = 0
	player_alive = true
	player = null


## Registers a shot fired by the player.
func register_shot() -> void:
	shots_fired += 1
	stats_updated.emit()


## Registers a hit landed by the player.
func register_hit() -> void:
	hits_landed += 1
	stats_updated.emit()


## Registers an enemy kill.
func register_kill() -> void:
	kills += 1
	enemy_killed.emit()
	stats_updated.emit()


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
func restart_scene() -> void:
	_reset_stats()
	get_tree().reload_current_scene()


## Sets the player reference.
func set_player(p: Node2D) -> void:
	player = p


## Toggles debug mode on/off.
## When enabled, shows debug labels on enemies (AI state).
## Works in both editor and exported builds.
func toggle_debug_mode() -> void:
	debug_mode_enabled = not debug_mode_enabled
	debug_mode_toggled.emit(debug_mode_enabled)
	_log_to_file("Debug mode toggled: %s" % ("ON" if debug_mode_enabled else "OFF"))


## Returns whether debug mode is currently enabled.
func is_debug_mode_enabled() -> bool:
	return debug_mode_enabled


## Toggles invincibility mode on/off.
## When enabled, player takes no damage from any source.
## Works in both editor and exported builds.
func toggle_invincibility() -> void:
	invincibility_enabled = not invincibility_enabled
	invincibility_toggled.emit(invincibility_enabled)
	_log_to_file("Invincibility mode toggled: %s" % ("ON" if invincibility_enabled else "OFF"))


## Returns whether invincibility mode is currently enabled.
func is_invincibility_enabled() -> bool:
	return invincibility_enabled


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
	return WEAPON_SCENES["m16"]  # Default to assault rifle


## Log a message to the file logger if available.
func _log_to_file(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[GameManager] " + message)
	else:
		print("[GameManager] " + message)
