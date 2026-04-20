extends Node
## WeaponHintsComponent - Shows weapon-specific tutorial hints when a new weapon is picked up.
##
## This component displays floating hints above the player explaining the unique
## features of each weapon. It respects the user's preference from WeaponHintsSettings:
## - ALWAYS: Show hints every time a weapon is picked up
## - FIRST_TIME_ONLY: Show hints only for first use of each weapon
## - NEVER: Never show hints
##
## Visual style and behaviour exactly matches the Labyrinth level tutorial hints (labyrinth_level.gd):
## - Font size 20 with drop shadows
## - Per-hint colors matching Labyrinth palette
## - Fade-in animation
## - Sequential hint display: first hint shown immediately, next hints appear one by one
##   after player actions (first shot → bolt/pump hint, second shot → reload hint)
## - Each hint dismissed when player performs the action (Fired, ReloadCompleted,
##   HammerCocked, ScopeStateChanged, FireModeChanged)
## - Progressive strikethrough via Line2D (Issue #944 / #1080 style)
## - Strikethrough-then-fade-out dismiss animation
## - Positioned via canvas_transform above player
##
## Issue #809: добавь обучение новому оружию (add weapon training)
##
## Usage:
##   1. Add this component to a level script
##   2. Call setup() with the player node and canvas layer
##   3. Component will automatically show hints when weapon is unlocked and equipped
##      (GameManager.weapon_unlocked → GameManager.weapon_selected)

class_name WeaponHintsComponent

## Optional NodePaths let a scene-owned component bootstrap itself without relying
## on level GDScript _ready() or the C# fallback to call setup().
@export var player_path: NodePath = NodePath("")
@export var canvas_layer_path: NodePath = NodePath("")

## Reference to the player node.
var _player: Node2D = null

## Reference to the CanvasLayer for hints (matching Labyrinth style).
var _canvas_layer: Node = null

## Currently shown weapon ID.
var _current_weapon_id: String = ""

## Flag: a weapon was just unlocked, so show hints on next weapon_selected even if same ID.
var _pending_unlock: String = ""

## Reference to the current weapon node attached to the player.
var _current_weapon_node: Node = null

## Dictionary of active hint labels: hint_key -> RichTextLabel node.
var _hint_labels: Dictionary = {}

## Whether hints are currently being displayed.
var _hints_showing: bool = false

## Whether we are in the process of showing hints for a weapon (tracking shot count etc).
var _hints_active: bool = false

## Tracks whether the last hint was dismissed by a player action (not auto-dismiss timer or weapon switch).
## Used to decide whether to call mark_weapon_seen() in FIRST_TIME_ONLY mode.
var _last_dismiss_was_player_action: bool = false

## Number of shots fired with current weapon (for sequential hint reveal).
var _shots_fired: int = 0

## Whether the bolt-cycle / pump hint has been revealed (after 1st shot).
var _bolt_cycle_hint_revealed: bool = false

## Whether the reload hint has been revealed (after 2nd shot).
var _reload_hint_revealed: bool = false

## Whether the scope hint has been used/dismissed.
var _scope_used: bool = false

## Whether the hammer has been cocked (revolver).
var _hammer_cocked: bool = false

## Whether the fire-mode hint is waiting to be shown.
var _fire_mode_hint_pending: bool = false

## Whether the shotgun full-reload hint is currently active (mirrors labyrinth_level.gd).
var _shotgun_full_reload_active: bool = false

## Reference to the weapon node used for shotgun shell-count queries.
var _shotgun_node: Node = null

## Tracks whether a shotgun full reload inserted at least one shell before closing.
var _shotgun_reload_loaded_shell: bool = false

## Tracks whether a revolver reload inserted at least one cartridge before closing.
var _revolver_reload_loaded_cartridge: bool = false

## Whether the AK GL grenade launcher hint has been shown (to avoid re-showing).
var _ak_gl_launcher_hint_shown: bool = false

## Grenade hint step state mirrors tutorial grenade training.
var _grenade_hint_step: int = 0
var _grenade_g_was_held: bool = false
var _grenade_drag_completed: bool = false
var _grenade_rmb_held_after_release: bool = false
var _grenade_rmb_was_pressed: bool = false
var _grenade_hint_drag_start: Vector2 = Vector2.ZERO

## Timer for auto-dismissing all hints after a long idle period.
var _dismiss_timer: Timer = null

## Per-hint auto-dismiss timers: hint_key -> Timer.
var _hint_timers: Dictionary = {}

## Duration to auto-dismiss individual hints (seconds).
const HINT_AUTO_DISMISS: float = 8.0

## Vertical spacing between stacked hints (matches Labyrinth TUTORIAL_HINT_SPACING).
const HINT_SPACING: float = 60.0

## Vertical offset from player position (matches Labyrinth offset of -80).
const HINT_OFFSET_Y: float = -80.0

## Horizontal offset from player center (matches Labyrinth offset of -150).
const HINT_OFFSET_X: float = -150.0

## Minimum hint label size (matches Labyrinth custom_minimum_size).
const HINT_MIN_SIZE := Vector2(300, 30)

## Fade-in duration (matches Labyrinth TUTORIAL_HINT_FADE_IN_DURATION).
const HINT_FADE_IN_DURATION: float = 0.3

## Strikethrough animation duration (matches Labyrinth TUTORIAL_HINT_STRIKETHROUGH_DURATION).
const HINT_STRIKETHROUGH_DURATION: float = 0.4

## Fade-out duration (matches Labyrinth TUTORIAL_HINT_FADE_OUT_DURATION).
const HINT_FADE_OUT_DURATION: float = 0.3

## Issue #944 style: Tracks hints currently being animated (prevents double-dismiss).
var _animating_hints: Dictionary = {}

## Issue #944 style: Track Line2D strikethrough nodes for each hint (hint_key -> Array[Line2D]).
var _hint_strike_lines: Dictionary = {}

## Issue #944 style: Track current strikethrough progress for each hint (hint_key -> float 0.0-1.0).
var _hint_strike_progress: Dictionary = {}

## Issue #944 style: Track line count for each hint (hint_key -> int).
var _hint_line_counts: Dictionary = {}

## Issue #1080 style: Track per-line text widths for each hint (hint_key -> Array[float]).
var _hint_line_widths: Dictionary = {}

## Hint keys — mirrors Labyrinth constant names for easy reference.
const HINT_KEY_RELOAD := "reload"
const HINT_KEY_BOLT_CYCLE := "bolt_cycle"
const HINT_KEY_HAMMER_COCK := "hammer_cock"
const HINT_KEY_SCOPE := "scope"
const HINT_KEY_FIRE_MODE := "fire_mode"
const HINT_KEY_LAUNCHER := "launcher"
const HINT_KEY_GRENADE := "grenade"

## Per-hint colors matching Labyrinth level color palette.
const HINT_COLOR_RELOAD := Color(0.4, 1.0, 0.5, 1.0)              ## Green
const HINT_COLOR_BOLT_CYCLE := Color(0.85, 0.6, 1.0, 1.0)         ## Purple
const HINT_COLOR_HAMMER_COCK := Color(1.0, 0.8, 0.3, 1.0)         ## Yellow
const HINT_COLOR_SCOPE := Color(0.3, 0.9, 1.0, 1.0)               ## Cyan
const HINT_COLOR_FIRE_MODE := Color(0.3, 0.9, 1.0, 1.0)           ## Cyan
const HINT_COLOR_LAUNCHER := Color(1.0, 0.4, 0.2, 1.0)            ## Red-orange
const HINT_COLOR_GRENADE := Color(1.0, 0.65, 0.0, 1.0)            ## Orange
const HINT_COLOR_DEFAULT := Color(1.0, 1.0, 0.3, 1.0)             ## Yellow fallback

## Color mapping by hint key.
func _get_hint_color(hint_key: String) -> Color:
	match hint_key:
		HINT_KEY_RELOAD:    return HINT_COLOR_RELOAD
		HINT_KEY_BOLT_CYCLE: return HINT_COLOR_BOLT_CYCLE
		HINT_KEY_HAMMER_COCK: return HINT_COLOR_HAMMER_COCK
		HINT_KEY_SCOPE:     return HINT_COLOR_SCOPE
		HINT_KEY_FIRE_MODE: return HINT_COLOR_FIRE_MODE
		HINT_KEY_LAUNCHER:  return HINT_COLOR_LAUNCHER
		HINT_KEY_GRENADE:   return HINT_COLOR_GRENADE
		_:                  return HINT_COLOR_DEFAULT


func _ready() -> void:
	# Create main dismiss timer (fallback for all hints)
	_dismiss_timer = Timer.new()
	_dismiss_timer.one_shot = true
	_dismiss_timer.timeout.connect(_on_dismiss_timer_timeout)
	add_child(_dismiss_timer)

	if not player_path.is_empty() and not canvas_layer_path.is_empty():
		var configured_player := get_node_or_null(player_path) as Node2D
		var configured_canvas_layer := get_node_or_null(canvas_layer_path)
		if configured_player != null and configured_canvas_layer != null:
			setup(configured_player, configured_canvas_layer)
			_log_to_file("Auto-setup from exported NodePaths")
		else:
			push_warning("[WeaponHintsComponent] Auto-setup paths could not be resolved")


## Setup the component with required references.
## Connects to GameManager.weapon_unlocked and weapon_selected signals.
## @param player: The player node to follow.
## @param canvas_layer: The CanvasLayer node to add hints to.
func setup(player: Node2D, canvas_layer: Node) -> void:
	_player = player
	_canvas_layer = canvas_layer

	if _player == null:
		push_warning("[WeaponHintsComponent] Player is null")
		return

	if _canvas_layer == null:
		push_warning("[WeaponHintsComponent] CanvasLayer is null")
		return

	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager:
		if game_manager.has_signal("weapon_unlocked"):
			if not game_manager.weapon_unlocked.is_connected(_on_weapon_unlocked):
				game_manager.weapon_unlocked.connect(_on_weapon_unlocked)
		if game_manager.has_signal("weapon_selected"):
			if not game_manager.weapon_selected.is_connected(_on_weapon_selected):
				game_manager.weapon_selected.connect(_on_weapon_selected)

	# Show hints for the weapon already equipped when level starts.
	if game_manager and game_manager.has_method("get_selected_weapon"):
		var weapon_id: String = game_manager.get_selected_weapon()
		if not weapon_id.is_empty():
			_on_weapon_selected(weapon_id)


## Called every frame to update hint positions above the player.
func _process(_delta: float) -> void:
	if _hints_showing:
		_update_hint_positions()
	if _hints_active:
		_update_grenade_hint()


## Called when GameManager emits weapon_unlocked (weapon opened in armory and taken for first time).
## Resets the "seen" flag so FIRST_TIME_ONLY mode will show hints on next weapon_selected.
## Also sets a pending flag so weapon_selected shows hints even if same weapon ID is re-selected.
func _on_weapon_unlocked(weapon_id: String) -> void:
	var settings: Node = get_node_or_null("/root/WeaponHintsSettings")
	if settings and settings.has_method("reset_weapon_seen"):
		settings.reset_weapon_seen(weapon_id)
	_pending_unlock = weapon_id
	_log_to_file("Weapon unlocked, seen flag reset: %s" % weapon_id)


## Called when GameManager emits weapon_selected (weapon becomes the active weapon).
## Dismisses current hints and starts hint sequence for the new weapon.
func _on_weapon_selected(weapon_id: String) -> void:
	# If this is the same weapon being re-selected after an unlock, still show hints.
	var is_same_weapon_after_unlock: bool = (weapon_id == _current_weapon_id and _pending_unlock == weapon_id)
	_pending_unlock = ""

	if weapon_id == _current_weapon_id and not is_same_weapon_after_unlock:
		return

	# Dismiss any currently showing hints immediately (new weapon equipped)
	if _hints_showing or _hints_active:
		_dismiss_hints_immediate()

	_current_weapon_id = weapon_id
	_try_start_hints(weapon_id)


## Decide whether to show hints for this weapon based on settings, then start hint sequence.
func _try_start_hints(weapon_id: String) -> void:
	if weapon_id.is_empty():
		return

	var settings: Node = get_node_or_null("/root/WeaponHintsSettings")
	if settings == null or settings.should_show_hints(weapon_id):
		_last_dismiss_was_player_action = false
		_start_hint_sequence(weapon_id)


## Begin the hint sequence for a weapon.
## Mirrors Labyrinth: connect to weapon node signals, show first hints immediately,
## then reveal subsequent hints progressively as player performs actions.
func _start_hint_sequence(weapon_id: String) -> void:
	_reset_hint_state()
	_hints_active = true
	_connect_player_action_signals()

	# Locate the weapon node on the player (same detection logic as labyrinth_level.gd)
	_current_weapon_node = _find_weapon_node(weapon_id)
	if _current_weapon_node == null:
		_log_to_file("Weapon node not found on player for: %s — hints not connected to actions" % weapon_id)
	else:
		_connect_weapon_signals(_current_weapon_node, weapon_id)

	# Show the first hints for this weapon immediately
	_show_initial_hints(weapon_id)

	# Safety: dismiss everything after HINT_AUTO_DISMISS seconds if not already cleared
	_dismiss_timer.start(HINT_AUTO_DISMISS)

	_log_to_file("Hint sequence started for weapon: %s" % weapon_id)


## Find the weapon node on the player by weapon ID.
## Mirrors the weapon detection in labyrinth_level.gd.
func _find_weapon_node(weapon_id: String) -> Node:
	if _player == null:
		return null

	# Map weapon IDs to the node names used in the player scene (C# PascalCase)
	var node_name_map: Dictionary = {
		"makarov_pm": "MakarovPM",
		"m16": "AssaultRifle",
		"shotgun": "Shotgun",
		"mini_uzi": "MiniUzi",
		"silenced_pistol": "SilencedPistol",
		"sniper": "SniperRifle",
		"revolver": "Revolver",
		"ak_gl": "AKGL",
	}

	var node_name: String = node_name_map.get(weapon_id, "")
	if not node_name.is_empty():
		var node: Node = _player.get_node_or_null(node_name)
		if node != null:
			return node

	# Fallback: scan player children for matching node
	for child in _player.get_children():
		if child.name == node_name:
			return child

	return null


## Connect player-level action signals used by hints regardless of weapon-node lookup.
func _connect_player_action_signals() -> void:
	if _player == null or not is_instance_valid(_player):
		return

	if _player.has_signal("ReloadCompleted"):
		if not _player.ReloadCompleted.is_connected(_on_reload_completed):
			_player.ReloadCompleted.connect(_on_reload_completed)
	elif _player.has_signal("reload_completed"):
		if not _player.reload_completed.is_connected(_on_reload_completed):
			_player.reload_completed.connect(_on_reload_completed)

	if _player.has_signal("ReloadSequenceProgress"):
		if not _player.ReloadSequenceProgress.is_connected(_on_reload_sequence_progress):
			_player.ReloadSequenceProgress.connect(_on_reload_sequence_progress)

	if _player.has_signal("GrenadeThrown"):
		if not _player.GrenadeThrown.is_connected(_on_player_grenade_thrown):
			_player.GrenadeThrown.connect(_on_player_grenade_thrown)
	elif _player.has_signal("grenade_thrown"):
		if not _player.grenade_thrown.is_connected(_on_player_grenade_thrown):
			_player.grenade_thrown.connect(_on_player_grenade_thrown)


## Connect to weapon-specific action signals so hints can be dismissed when player acts.
## Mirrors labyrinth_level.gd weapon signal connection logic.
func _connect_weapon_signals(weapon: Node, weapon_id: String) -> void:
	# Connect shot-fired signal for sequential hint reveal (bolt/pump after 1st, reload after 2nd)
	if weapon.has_signal("Fired"):
		if not weapon.Fired.is_connected(_on_weapon_fired):
			weapon.Fired.connect(_on_weapon_fired)
	elif weapon.has_signal("ShotFired"):
		if not weapon.ShotFired.is_connected(_on_weapon_fired):
			weapon.ShotFired.connect(_on_weapon_fired)

	# Weapon-type-specific signals
	match weapon_id:
		"shotgun":
			if weapon.has_signal("ActionStateChanged"):
				if not weapon.ActionStateChanged.is_connected(_on_shotgun_action_state_changed):
					weapon.ActionStateChanged.connect(_on_shotgun_action_state_changed)
			if weapon.has_signal("ReloadStateChanged"):
				if not weapon.ReloadStateChanged.is_connected(_on_shotgun_reload_state_changed):
					weapon.ReloadStateChanged.connect(_on_shotgun_reload_state_changed)
		"sniper":
			if weapon.has_signal("BoltStepChanged"):
				if not weapon.BoltStepChanged.is_connected(_on_sniper_bolt_step_changed):
					weapon.BoltStepChanged.connect(_on_sniper_bolt_step_changed)
			if weapon.has_signal("ScopeStateChanged"):
				if not weapon.ScopeStateChanged.is_connected(_on_scope_state_changed):
					weapon.ScopeStateChanged.connect(_on_scope_state_changed)
		"revolver":
			if weapon.has_signal("HammerCocked"):
				if not weapon.HammerCocked.is_connected(_on_hammer_cocked):
					weapon.HammerCocked.connect(_on_hammer_cocked)
			if weapon.has_signal("ReloadStateChanged"):
				if not weapon.ReloadStateChanged.is_connected(_on_revolver_reload_state_changed):
					weapon.ReloadStateChanged.connect(_on_revolver_reload_state_changed)
		"m16":
			if weapon.has_signal("FireModeChanged"):
				if not weapon.FireModeChanged.is_connected(_on_fire_mode_changed):
					weapon.FireModeChanged.connect(_on_fire_mode_changed)
		"ak_gl":
			# Note: AKGL does NOT have FireModeChanged — no connection needed (mirrors labyrinth_level.gd).
			if weapon.has_signal("GrenadeFired"):
				if not weapon.GrenadeFired.is_connected(_on_grenade_launcher_fired):
					weapon.GrenadeFired.connect(_on_grenade_launcher_fired)

	# Store shotgun node reference for shell-count queries
	if weapon_id == "shotgun":
		_shotgun_node = weapon

	_log_to_file("Connected weapon signals for: %s (node: %s)" % [weapon_id, weapon.name])


## Show the first hints for this weapon immediately when equipped.
## For revolver: show hammer-cock hint immediately (mirrors Labyrinth).
## For sniper: show scope hint immediately (mirrors Labyrinth Issue #998).
## For all: bolt-cycle hint after 1st shot, reload hint after 2nd shot.
func _show_initial_hints(weapon_id: String) -> void:
	match weapon_id:
		"revolver":
			_add_hint(HINT_KEY_HAMMER_COCK,
				"[color=#ff4444][ПКМ][/color] " + tr("HINT_COCK_HAMMER"))
		"sniper":
			_add_hint(HINT_KEY_SCOPE,
				"[color=#ff4444][ПКМ][/color] " + tr("HINT_SCOPE"))

	# All other weapons: bolt-cycle/pump hint appears after 1st shot,
	# reload hint appears after 2nd shot (see _on_weapon_fired).
	_hints_showing = true


## Called when the player fires a shot.
## Mirrors Labyrinth _on_tutorial_weapon_fired():
## - After 1st shot: show bolt-cycle hint (sniper/shotgun)
## - After 2nd shot: show reload hint (all weapons)
func _on_weapon_fired() -> void:
	_shots_fired += 1
	_log_to_file("Shot fired with %s (%d total)" % [_current_weapon_id, _shots_fired])

	# After 1st shot: reveal bolt-cycle/pump hint for weapons that need it
	if _shots_fired >= 1 and not _bolt_cycle_hint_revealed:
		match _current_weapon_id:
			"sniper":
				_bolt_cycle_hint_revealed = true
				if not _hint_labels.has(HINT_KEY_BOLT_CYCLE):
					_add_hint(HINT_KEY_BOLT_CYCLE,
						"[color=#ff4444][←][/color] [color=#888888][↓] [↑] [→][/color] " + tr("HINT_BOLT_ACTION_WORD"))
			"shotgun":
				_bolt_cycle_hint_revealed = true
				if not _hint_labels.has(HINT_KEY_BOLT_CYCLE):
					_add_hint(HINT_KEY_BOLT_CYCLE,
						"[color=#ff4444][ПКМ↑][/color] [color=#888888][ПКМ↓][/color] " + tr("HINT_BOLT_ACTION_WORD"))

	# After 2nd shot: reveal reload hint for all weapons
	if _shots_fired >= 2 and not _reload_hint_revealed:
		_reload_hint_revealed = true
		_reveal_reload_hint()


## Reveal the reload hint appropriate for the current weapon.
## Mirrors labyrinth_level.gd _add_tutorial_reload_hints().
func _reveal_reload_hint() -> void:
	match _current_weapon_id:
		"shotgun":
			# Replace pump-action hint with full reload hint (mirrors labyrinth round 4 fix)
			_shotgun_full_reload_active = true
			if _hint_labels.has(HINT_KEY_BOLT_CYCLE):
				_dismiss_hint(HINT_KEY_BOLT_CYCLE)
			_add_hint(HINT_KEY_BOLT_CYCLE,
				_build_shotgun_full_reload_hint_bbcode(0))
		"sniper":
			_add_hint(HINT_KEY_RELOAD,
				_build_reload_hint_bbcode(0, 3))
		"revolver":
			_add_hint(HINT_KEY_RELOAD,
				_build_revolver_reload_hint_bbcode(0))
		"makarov_pm":
			_add_hint(HINT_KEY_RELOAD,
				_build_reload_hint_bbcode(0, 2))
		_:
			# Standard R → F → R (m16, mini_uzi, silenced_pistol, ak_gl, etc.)
			_add_hint(HINT_KEY_RELOAD,
				_build_reload_hint_bbcode(0, 3))

	_log_to_file("Reload hint revealed for: %s" % _current_weapon_id)


## Called when sniper bolt step changes.
## Mirrors labyrinth_level.gd _on_tutorial_sniper_bolt_step_changed(): updates hint text then dismisses on completion.
func _on_sniper_bolt_step_changed(step: int, total_steps: int) -> void:
	if _hint_labels.has(HINT_KEY_BOLT_CYCLE):
		var label: RichTextLabel = _hint_labels[HINT_KEY_BOLT_CYCLE]
		if is_instance_valid(label):
			label.text = _build_sniper_bolt_hint_bbcode(step)
	if step >= total_steps:
		_last_dismiss_was_player_action = true
		_dismiss_hint(HINT_KEY_BOLT_CYCLE)


## Called when shotgun action state changes (pump-action cycling).
## Mirrors labyrinth_level.gd _on_tutorial_shotgun_action_state_changed().
## ShotgunActionState: 0=Ready, 1=NeedsPumpUp, 2=NeedsPumpDown
func _on_shotgun_action_state_changed(new_state: int) -> void:
	# Do not overwrite the full reload hint with the pump hint
	if _shotgun_full_reload_active:
		return

	if new_state == 0:
		# Bolt cycle complete — dismiss pump hint
		if _hint_labels.has(HINT_KEY_BOLT_CYCLE):
			_last_dismiss_was_player_action = true
			_dismiss_hint(HINT_KEY_BOLT_CYCLE)
	elif _hint_labels.has(HINT_KEY_BOLT_CYCLE):
		var label: RichTextLabel = _hint_labels[HINT_KEY_BOLT_CYCLE]
		if is_instance_valid(label):
			label.text = _build_shotgun_pump_hint_bbcode(new_state)


## Called when shotgun reload state changes (full shell-by-shell reload).
## Mirrors labyrinth_level.gd _on_tutorial_shotgun_reload_state_changed().
## ShotgunReloadState: 0=NotReloading, 1=WaitingToOpen, 2=Loading, 3=WaitingToClose
func _on_shotgun_reload_state_changed(new_state: int) -> void:
	if not _hint_labels.has(HINT_KEY_BOLT_CYCLE):
		return

	# State 0 means the action was closed. Only dismiss if at least one shell was loaded;
	# otherwise the player just opened/closed the bolt and the training must roll back.
	if new_state == 0:
		if _shotgun_reload_loaded_shell:
			_log_to_file("Shotgun reload completed after shell load")
			_on_reload_completed()
		else:
			_rollback_shotgun_reload_hint()
		return

	if new_state == 2 or new_state == 3:
		_shotgun_reload_loaded_shell = new_state == 3

	var label: RichTextLabel = _hint_labels[HINT_KEY_BOLT_CYCLE]
	if is_instance_valid(label):
		label.text = _build_shotgun_full_reload_hint_bbcode(new_state)


## Called when hammer is cocked on revolver — dismisses hammer-cock hint.
func _on_hammer_cocked() -> void:
	_hammer_cocked = true
	_last_dismiss_was_player_action = true
	_dismiss_hint(HINT_KEY_HAMMER_COCK)
	_log_to_file("Hammer cocked — hammer hint dismissed")


## Called when scope state changes — dismisses scope hint on first activation.
func _on_scope_state_changed(is_active: bool) -> void:
	if not is_active or _scope_used:
		return
	_scope_used = true
	_last_dismiss_was_player_action = true
	_dismiss_hint(HINT_KEY_SCOPE)
	_log_to_file("Scope used — scope hint dismissed")


## Called when fire mode changes — dismisses fire-mode hint.
func _on_fire_mode_changed(_new_mode: int) -> void:
	if _hint_labels.has(HINT_KEY_FIRE_MODE):
		_last_dismiss_was_player_action = true
		_dismiss_hint(HINT_KEY_FIRE_MODE)
		_log_to_file("Fire mode changed — fire mode hint dismissed")


## Called when grenade launcher fires — dismisses launcher hint.
func _on_grenade_launcher_fired() -> void:
	_last_dismiss_was_player_action = true
	_dismiss_hint(HINT_KEY_LAUNCHER)
	_log_to_file("Grenade launcher fired — launcher hint dismissed")


func _update_grenade_hint() -> void:
	if _player == null or not is_instance_valid(_player):
		return

	var grenade_hint_visible := _hint_labels.has(HINT_KEY_GRENADE)
	var should_track_grenade_hint := _hints_active and (_player_has_grenades() or (grenade_hint_visible and _player_has_active_grenade_sequence()))
	if not should_track_grenade_hint:
		if _hint_labels.has(HINT_KEY_GRENADE):
			_reset_grenade_hint_tracking()
			_dismiss_hint(HINT_KEY_GRENADE)
		return

	var grenade_pressed: bool = Input.is_action_pressed("grenade_prepare")
	if not _hint_labels.has(HINT_KEY_GRENADE) and not grenade_pressed:
		return

	if not _hint_labels.has(HINT_KEY_GRENADE):
		_reset_grenade_hint_tracking()
		_add_hint(HINT_KEY_GRENADE, _build_grenade_hint_bbcode(0))
		_log_to_file("Grenade hint shown after grenade_prepare")

	_update_grenade_hint_step()


## Called when player completes a reload.
## Mirrors labyrinth_level.gd _on_tutorial_reload_completed(): dismisses reload hint.
## For M16: shows fire-mode hint after reload (mirrors Labyrinth).
## For AK GL: shows grenade launcher hint after reload (mirrors Labyrinth Issue #991).
func _on_reload_completed() -> void:
	if not _hints_active:
		return
	_last_dismiss_was_player_action = true
	if _hint_labels.has(HINT_KEY_RELOAD):
		_dismiss_hint(HINT_KEY_RELOAD)
	if _current_weapon_id == "shotgun":
		if _hint_labels.has(HINT_KEY_BOLT_CYCLE):
			_dismiss_hint(HINT_KEY_BOLT_CYCLE)
		_shotgun_full_reload_active = false
		_shotgun_reload_loaded_shell = false

	# M16: show fire-mode hint after reload (mirrors Labyrinth)
	if _current_weapon_id == "m16":
		_fire_mode_hint_pending = true
		if not _hint_labels.has(HINT_KEY_FIRE_MODE):
			_add_hint(HINT_KEY_FIRE_MODE,
				"[color=#ff4444][B][/color] " + tr("HINT_FIRE_MODE_SWITCH"))

	# AK GL: show grenade launcher hint after reload (Issue #991 pattern — sequential, no overlap)
	if _current_weapon_id == "ak_gl" and not _ak_gl_launcher_hint_shown:
		if _ak_gl_has_round_loaded():
			_ak_gl_launcher_hint_shown = true
			if not _hint_labels.has(HINT_KEY_LAUNCHER):
				_add_hint(HINT_KEY_LAUNCHER,
					"[color=#ff4444][ПКМ][/color] " + tr("HINT_LAUNCHER_FIRE"))

	_log_to_file("Reload completed — reload hint dismissed for: %s" % _current_weapon_id)


## Called when the reload sequence progresses — updates hint text to highlight the next step.
## Mirrors labyrinth_level.gd _on_tutorial_reload_sequence_progress().
## Shotgun uses ReloadStateChanged instead — skipped here.
## @param step: last completed step (0 = nothing done yet).
## @param total: total reload steps.
func _on_reload_sequence_progress(step: int, total: int) -> void:
	# Shotgun uses ReloadStateChanged for step-by-step highlighting
	if _current_weapon_id == "shotgun":
		return

	if _current_weapon_id == "revolver":
		if _hint_labels.has(HINT_KEY_RELOAD):
			var label: RichTextLabel = _hint_labels[HINT_KEY_RELOAD]
			if is_instance_valid(label):
				label.text = _build_revolver_reload_hint_bbcode(step)
		return

	if not _hint_labels.has(HINT_KEY_RELOAD):
		return

	var new_text := _build_reload_hint_bbcode(step, total)
	if new_text.is_empty():
		return
	var label: RichTextLabel = _hint_labels[HINT_KEY_RELOAD]
	if is_instance_valid(label):
		label.text = new_text
	_log_to_file("Reload sequence step %d/%d — hint updated" % [step, total])


## Build BBCode reload hint text based on step and total steps.
## Mirrors labyrinth_level.gd _build_tutorial_reload_hint_bbcode().
func _build_reload_hint_bbcode(step: int, total: int) -> String:
	var reload_word: String = tr("HINT_RELOAD_WORD")
	if _current_weapon_id == "makarov_pm" or total <= 2:
		# Makarov PM / 2-step reload: R → R
		match step:
			0:
				return "[color=#ff4444][R][/color] [color=#888888][R][/color] " + reload_word
			1:
				_extend_hint_strikethrough(HINT_KEY_RELOAD, 0.25)
				return "[color=#888888][R][/color] [color=#ff4444][R][/color] " + reload_word
			_:
				_extend_hint_strikethrough(HINT_KEY_RELOAD, 0.5)
				return "[color=#888888][R] [R][/color] " + reload_word
	else:
		# Standard 3-step reload: R → F → R
		match step:
			0:
				return "[color=#ff4444][R][/color] [color=#888888][F] [R][/color] " + reload_word
			1:
				_extend_hint_strikethrough(HINT_KEY_RELOAD, 0.17)
				return "[color=#888888][R][/color] [color=#ff4444][F][/color] [color=#888888][R][/color] " + reload_word
			2:
				_extend_hint_strikethrough(HINT_KEY_RELOAD, 0.33)
				return "[color=#888888][R] [F][/color] [color=#ff4444][R][/color] " + reload_word
			_:
				_extend_hint_strikethrough(HINT_KEY_RELOAD, 0.5)
				return "[color=#888888][R] [F] [R][/color] " + reload_word
	return ""


## Build BBCode for revolver reload hint with step-based highlighting.
## Mirrors labyrinth_level.gd _build_tutorial_revolver_reload_hint_bbcode().
func _build_revolver_reload_hint_bbcode(step: int) -> String:
	var k_open: String = tr("HINT_KEY_R_OPEN")
	var k_bullet: String = tr("HINT_KEY_RMB_UP_BULLET")
	var k_scroll: String = tr("HINT_KEY_SCROLL")
	var k_close: String = tr("HINT_KEY_R_CLOSE")
	match step:
		0:
			return "[color=#ff4444][%s][/color] [color=#888888][%s] [%s] [%s][/color]" % [k_open, k_bullet, k_scroll, k_close]
		1:
			_extend_hint_strikethrough(HINT_KEY_RELOAD, 0.15)
			return "[color=#888888][%s][/color] [color=#ff4444][%s][/color] [color=#888888][%s] [%s][/color]" % [k_open, k_bullet, k_scroll, k_close]
		2:
			_extend_hint_strikethrough(HINT_KEY_RELOAD, 0.55)
			return "[color=#888888][%s] [%s] [%s][/color] [color=#ff4444][%s][/color]" % [k_open, k_bullet, k_scroll, k_close]
		_:
			_extend_hint_strikethrough(HINT_KEY_RELOAD, 0.75)
			return "[color=#888888][%s] [%s] [%s] [%s][/color]" % [k_open, k_bullet, k_scroll, k_close]
	return ""


## Build BBCode for shotgun full reload hint with step-based highlighting.
## Mirrors labyrinth_level.gd _build_tutorial_shotgun_full_reload_hint_bbcode().
## ShotgunReloadState: 0=NotReloading, 1=WaitingToOpen, 2=Loading, 3=WaitingToClose
func _build_shotgun_full_reload_hint_bbcode(state: int) -> String:
	var shells_needed: int = _get_shotgun_shells_to_load()
	var k_open: String = tr("HINT_KEY_RMB_UP_OPEN")
	var k_load: String = tr("HINT_KEY_MMB_RMB_DOWN") % shells_needed
	var k_close: String = tr("HINT_KEY_RMB_DOWN_CLOSE")
	match state:
		0, 1:
			return "[color=#ff4444][%s][/color] [color=#888888][%s] [%s][/color]" % [k_open, k_load, k_close]
		2:
			_extend_hint_strikethrough(HINT_KEY_BOLT_CYCLE, 0.25)
			return "[color=#888888][%s][/color] [color=#ff4444][%s][/color] [color=#888888][%s][/color]" % [k_open, k_load, k_close]
		3:
			_extend_hint_strikethrough(HINT_KEY_BOLT_CYCLE, 0.55)
			return "[color=#888888][%s] [%s][/color] [color=#ff4444][%s][/color]" % [k_open, k_load, k_close]
		_:
			_extend_hint_strikethrough(HINT_KEY_BOLT_CYCLE, 0.8)
			return "[color=#888888][%s] [%s] [%s][/color]" % [k_open, k_load, k_close]
	return ""


## Build BBCode for shotgun between-shots pump hint.
## Mirrors labyrinth_level.gd _build_tutorial_shotgun_pump_hint_bbcode().
## ShotgunActionState: 1=NeedsPumpUp, 2=NeedsPumpDown
func _build_shotgun_pump_hint_bbcode(state: int) -> String:
	var bolt_word: String = tr("HINT_BOLT_ACTION_WORD")
	match state:
		1:
			return "[color=#ff4444][ПКМ↑][/color] [color=#888888][ПКМ↓][/color] " + bolt_word
		2:
			_extend_hint_strikethrough(HINT_KEY_BOLT_CYCLE, 0.2)
			return "[color=#888888][ПКМ↑][/color] [color=#ff4444][ПКМ↓][/color] " + bolt_word
		_:
			_extend_hint_strikethrough(HINT_KEY_BOLT_CYCLE, 0.4)
			return "[color=#888888][ПКМ↑] [ПКМ↓][/color] " + bolt_word
	return ""


func _get_grenade_hint_actions() -> Array:
	return [
		"[%s]" % tr("HINT_GRENADE_HOLD_G_RMB"),
		"[%s]" % tr("HINT_GRENADE_DRAG_RIGHT"),
		"[%s]" % tr("HINT_GRENADE_RELEASE_RMB"),
		"[%s]" % tr("HINT_GRENADE_HOLD_RMB"),
		"[%s]" % tr("HINT_GRENADE_RELEASE_G"),
		"[%s]" % tr("HINT_GRENADE_AIM_RELEASE_RMB"),
	]


func _get_grenade_hint_strikethrough_progress(completed_actions: int, actions: Array) -> float:
	if completed_actions <= 0 or actions.is_empty():
		return 0.0

	var all_actions := PackedStringArray()
	for action in actions:
		all_actions.append(str(action))
	var total_text := " ".join(all_actions)
	if total_text.is_empty():
		return 0.0

	var completed := PackedStringArray()
	var completed_count := mini(completed_actions, actions.size())
	for i in range(completed_count):
		completed.append(str(actions[i]))
	return float(" ".join(completed).length()) / float(total_text.length())


func _build_grenade_hint_bbcode(step: int) -> String:
	var parts := _get_grenade_hint_actions()
	var clamped_step := clampi(step, 0, parts.size() - 1)
	_extend_hint_strikethrough(
		HINT_KEY_GRENADE,
		_get_grenade_hint_strikethrough_progress(clamped_step, parts)
	)

	var styled: PackedStringArray = []
	for i in range(parts.size()):
		if i < clamped_step:
			styled.append("[color=#888888]%s[/color]" % parts[i])
		elif i == clamped_step:
			styled.append("[color=#ff4444]%s[/color]" % parts[i])
		else:
			styled.append("[color=#888888]%s[/color]" % parts[i])
	return " ".join(styled)


func _reset_grenade_hint_tracking() -> void:
	_grenade_hint_step = 0
	_grenade_g_was_held = false
	_grenade_drag_completed = false
	_grenade_rmb_held_after_release = false
	_grenade_rmb_was_pressed = false
	_grenade_hint_drag_start = Vector2.ZERO


func _reset_grenade_hint_to_start() -> void:
	_reset_grenade_hint_tracking()
	if _hint_labels.has(HINT_KEY_GRENADE):
		var label: RichTextLabel = _hint_labels[HINT_KEY_GRENADE]
		if is_instance_valid(label):
			label.text = _build_grenade_hint_bbcode(0)
	_reset_hint_strikethrough(HINT_KEY_GRENADE)


func _update_grenade_hint_step() -> void:
	if not _hint_labels.has(HINT_KEY_GRENADE):
		_reset_grenade_hint_tracking()
		return

	var grenade_state := _get_player_grenade_state()
	var g_pressed: bool = Input.is_action_pressed("grenade_prepare")
	var rmb_pressed: bool = Input.is_action_pressed("grenade_throw")
	var current_mouse_pos := _get_grenade_mouse_position()
	var rmb_just_pressed := rmb_pressed and not _grenade_rmb_was_pressed

	if grenade_state == 0 and _grenade_hint_step > 0:
		var awaiting_pin_state := (
			_grenade_hint_step == 2
			and g_pressed
			and not rmb_pressed
			and _grenade_drag_completed
			and _grenade_rmb_was_pressed
		)
		if not ((g_pressed and rmb_pressed and _grenade_hint_step <= 2) or awaiting_pin_state):
			_reset_grenade_hint_to_start()
	elif grenade_state == 1 and _grenade_hint_step > 3:
		_reset_grenade_hint_to_start()
	elif _grenade_hint_step == 0 and not (g_pressed and rmb_pressed):
		if g_pressed or rmb_pressed or _grenade_rmb_was_pressed:
			_reset_grenade_hint_to_start()
	elif _grenade_hint_step == 1 and not g_pressed and not _grenade_drag_completed:
		_reset_grenade_hint_to_start()
	elif _grenade_hint_step == 2 and not g_pressed and not rmb_pressed:
		_reset_grenade_hint_to_start()
	elif _grenade_hint_step == 3 and not g_pressed and not rmb_pressed:
		_reset_grenade_hint_to_start()
	elif _grenade_hint_step == 4 and not rmb_pressed and not _grenade_rmb_held_after_release:
		_reset_grenade_hint_to_start()

	if _grenade_hint_step <= 1 and g_pressed and rmb_pressed and rmb_just_pressed:
		_grenade_drag_completed = false
		_grenade_hint_drag_start = current_mouse_pos

	if _grenade_hint_step == 1 and g_pressed and rmb_pressed:
		if current_mouse_pos.x - _grenade_hint_drag_start.x > 20.0:
			_grenade_drag_completed = true
			_grenade_hint_step = 2

	if _grenade_hint_step == 0 and g_pressed and rmb_pressed:
		_grenade_hint_step = 1
		_grenade_g_was_held = true
	elif _grenade_hint_step == 2 and _grenade_drag_completed and not rmb_pressed and grenade_state >= 1:
		_grenade_hint_step = 3
	elif _grenade_hint_step == 3 and g_pressed and rmb_just_pressed and grenade_state >= 1:
		_grenade_rmb_held_after_release = true
		_grenade_hint_step = 4
	elif _grenade_hint_step == 4 and not g_pressed and rmb_pressed and _grenade_rmb_held_after_release and grenade_state >= 2:
		_grenade_hint_step = 5
		_grenade_g_was_held = false

	var label: RichTextLabel = _hint_labels[HINT_KEY_GRENADE]
	if is_instance_valid(label):
		var new_text := _build_grenade_hint_bbcode(_grenade_hint_step)
		if label.text != new_text:
			label.text = new_text

	_grenade_rmb_was_pressed = rmb_pressed


func _on_player_grenade_thrown() -> void:
	if not _hint_labels.has(HINT_KEY_GRENADE):
		return

	_last_dismiss_was_player_action = true
	_reset_grenade_hint_tracking()
	_dismiss_hint(HINT_KEY_GRENADE)
	_log_to_file("Grenade thrown — grenade hint dismissed")


## Build BBCode for sniper bolt-cycle hint showing 4-step sequence.
## Mirrors labyrinth_level.gd _build_tutorial_sniper_bolt_hint_bbcode().
func _build_sniper_bolt_hint_bbcode(step: int) -> String:
	const STEPS := ["←", "↓", "↑", "→"]
	var parts: PackedStringArray = []
	for i in range(STEPS.size()):
		if i < step:
			parts.append("[color=#888888][%s][/color]" % STEPS[i])
		elif i == step:
			parts.append("[color=#ff4444][%s][/color]" % STEPS[i])
		else:
			parts.append("[color=#888888][%s][/color]" % STEPS[i])
	if step > 0:
		_extend_hint_strikethrough(HINT_KEY_BOLT_CYCLE, float(step) * 0.125)
	return " ".join(parts) + " " + tr("HINT_BOLT_ACTION_WORD")


## Get number of shells the shotgun needs to reload to capacity.
## Mirrors labyrinth_level.gd _get_tutorial_shotgun_shells_to_load().
func _get_shotgun_shells_to_load() -> int:
	if _shotgun_node == null or not is_instance_valid(_shotgun_node):
		return 8
	var shells_in_tube = _shotgun_node.get("ShellsInTube")
	var tube_capacity = _shotgun_node.get("TubeMagazineCapacity")
	if shells_in_tube == null or tube_capacity == null:
		return 8
	return int(tube_capacity) - int(shells_in_tube)


## Check whether the AK GL has a round loaded in the grenade launcher.
## Mirrors labyrinth_level.gd _tutorial_ak_gl_has_round_loaded().
func _ak_gl_has_round_loaded() -> bool:
	if _current_weapon_node == null or not is_instance_valid(_current_weapon_node):
		return true  # Assume loaded if node not found
	var available = _current_weapon_node.get("GrenadeAvailable")
	if available != null:
		return bool(available)
	return true  # Assume loaded if property not found


func _player_has_grenades() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false

	if _player.has_method("GetCurrentGrenades"):
		return int(_player.call("GetCurrentGrenades")) > 0

	var grenade_count = _player.get("GrenadeCount")
	if grenade_count != null:
		return int(grenade_count) > 0

	return false


func _get_player_grenade_state() -> int:
	if _player != null and is_instance_valid(_player) and _player.has_method("GetGrenadeState"):
		return int(_player.call("GetGrenadeState"))
	return 0


func _player_has_active_grenade_sequence() -> bool:
	return _get_player_grenade_state() > 0


func _get_grenade_mouse_position() -> Vector2:
	if _player != null and is_instance_valid(_player):
		return _player.get_global_mouse_position()
	return Vector2.ZERO


## Extend the strikethrough progress for a hint (used by BBCode builders).
## Mirrors labyrinth_level.gd _extend_tutorial_hint_strikethrough().
func _extend_hint_strikethrough(hint_key: String, progress: float) -> void:
	if not _hint_strike_progress.has(hint_key):
		return
	var current: float = _hint_strike_progress[hint_key]
	if progress <= current and hint_key != HINT_KEY_GRENADE:
		return
	_hint_strike_progress[hint_key] = progress
	var strike_lines: Array = _hint_strike_lines.get(hint_key, [])
	var line_count: int = _hint_line_counts.get(hint_key, 1)
	var line_widths: Array = _hint_line_widths.get(hint_key, [])
	if not strike_lines.is_empty():
		_update_strikethrough_points(strike_lines, line_count, line_widths, progress)


## Called when the global dismiss timer times out — clear all remaining hints.
func _on_dismiss_timer_timeout() -> void:
	_log_to_file("Auto-dismiss timer: clearing all remaining hints for %s" % _current_weapon_id)
	dismiss_hints()


## Add a single hint label with Labyrinth-style BBCode, shadows, fade-in, and strikethrough Line2D.
## Mirrors labyrinth_level.gd _add_tutorial_hint().
## @param hint_key: Unique identifier for this hint.
## @param text: BBCode-formatted text to display.
func _add_hint(hint_key: String, text: String) -> void:
	if hint_key in _hint_labels:
		# Already showing — update text if not animating
		if not _animating_hints.has(hint_key):
			_hint_labels[hint_key].text = text
		return

	var label := RichTextLabel.new()
	label.name = "WeaponHint_" + hint_key
	label.bbcode_enabled = true
	label.text = text
	label.add_theme_font_size_override("normal_font_size", 20)

	label.add_theme_color_override("default_color", _get_hint_color(hint_key))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.custom_minimum_size = HINT_MIN_SIZE
	label.fit_content = true
	label.scroll_active = false

	# Start transparent for fade-in
	label.modulate.a = 0.0

	_canvas_layer.add_child(label)
	_hint_labels[hint_key] = label
	_hints_showing = true
	_hints_active = true  # Re-arm in case previous hints cleared the flag between stages

	# Initialize strikethrough tracking
	_hint_strike_lines[hint_key] = []
	_hint_strike_progress[hint_key] = 0.0

	# Set up Line2D strikethrough nodes after one frame
	_setup_strikethrough_lines.call_deferred(hint_key, label)

	# Position immediately
	var index := _hint_labels.size() - 1
	var canvas_transform: Transform2D = get_viewport().get_canvas_transform()
	var screen_pos: Vector2 = canvas_transform * (_player.global_position if _player else Vector2.ZERO)
	label.custom_minimum_size = HINT_MIN_SIZE
	label.position = screen_pos + Vector2(HINT_OFFSET_X, HINT_OFFSET_Y - index * HINT_SPACING)

	# Fade-in animation
	var tween := create_tween()
	tween.tween_property(label, "modulate:a", 1.0, HINT_FADE_IN_DURATION).set_ease(Tween.EASE_OUT)

	_log_to_file("Hint added '%s': %s" % [hint_key, text])


## Set up one Line2D per text line after label layout is ready (deferred).
## Mirrors labyrinth_level.gd _setup_tutorial_strikethrough_lines().
func _setup_strikethrough_lines(hint_key: String, label: RichTextLabel) -> void:
	if not is_instance_valid(label):
		return

	const LINE_HEIGHT := 26.0

	var content_height := label.get_content_height()
	var line_count := maxi(1, roundi(content_height / LINE_HEIGHT))
	_hint_line_counts[hint_key] = line_count

	var line_widths: Array = []
	var font: Font = label.get_theme_font("normal_font")
	var font_size: int = label.get_theme_font_size("normal_font_size")
	if is_instance_valid(font) and font_size > 0:
		var plain_text: String = label.get_parsed_text()
		var per_line_text: Array = []
		for _i in range(line_count):
			per_line_text.append("")
		for char_idx in range(plain_text.length()):
			var visual_line: int = label.get_character_line(char_idx)
			if visual_line >= 0 and visual_line < line_count:
				per_line_text[visual_line] += plain_text[char_idx]
		for line_idx in range(line_count):
			var w: float = font.get_string_size(per_line_text[line_idx], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			line_widths.append(maxf(w, 1.0))
	else:
		var fallback_width: float = label.get_content_width()
		if fallback_width <= 0:
			fallback_width = label.custom_minimum_size.x
		if fallback_width <= 0:
			fallback_width = 300.0
		for _i in range(line_count):
			line_widths.append(fallback_width)
	_hint_line_widths[hint_key] = line_widths

	var lines: Array = []
	for line_idx in range(line_count):
		var line_y := line_idx * LINE_HEIGHT + LINE_HEIGHT * 0.55
		var seg := Line2D.new()
		seg.name = "StrikeLine_%s_%d" % [hint_key, line_idx]
		seg.width = 1.5
		seg.default_color = Color(0.6, 0.6, 0.6, 0.6)
		seg.z_index = 1
		seg.add_point(Vector2(0, line_y))
		seg.add_point(Vector2(0, line_y))
		label.add_child(seg)
		lines.append(seg)

	_hint_strike_lines[hint_key] = lines
	_log_to_file("Strikethrough setup '%s': %d lines" % [hint_key, line_count])


## Update per-line Line2D end points for multi-line strikethrough.
## Mirrors labyrinth_level.gd _update_tutorial_strikethrough_points().
func _update_strikethrough_points(strike_lines: Array, line_count: int, line_widths: Array, progress: float) -> void:
	for line_idx in range(line_count):
		if line_idx >= strike_lines.size():
			break
		var seg: Line2D = strike_lines[line_idx]
		if not is_instance_valid(seg):
			continue
		var line_start_progress := float(line_idx) / line_count
		var line_end_progress := float(line_idx + 1) / line_count
		var line_progress: float
		if progress <= line_start_progress:
			line_progress = 0.0
		elif progress >= line_end_progress:
			line_progress = 1.0
		else:
			line_progress = (progress - line_start_progress) / (line_end_progress - line_start_progress)
		var line_width: float = line_widths[line_idx] if line_idx < line_widths.size() else 300.0
		seg.set_point_position(1, Vector2(line_width * line_progress, seg.get_point_position(0).y))


## Dismiss a single hint with strikethrough-then-fade-out animation.
## Mirrors labyrinth_level.gd _dismiss_tutorial_hint() + _animate_tutorial_hint_strikethrough_and_fade().
func _dismiss_hint(hint_key: String) -> void:
	if not _hint_labels.has(hint_key):
		return
	if _animating_hints.has(hint_key):
		return

	var label: RichTextLabel = _hint_labels[hint_key]
	if not is_instance_valid(label):
		_hint_labels.erase(hint_key)
		return

	_animating_hints[hint_key] = true
	_log_to_file("Dismissing hint '%s'" % hint_key)

	var strike_lines: Array = _hint_strike_lines.get(hint_key, [])
	var line_widths: Array = _hint_line_widths.get(hint_key, [])
	if line_widths.is_empty():
		var fw: float = label.get_content_width()
		if fw <= 0: fw = label.custom_minimum_size.x
		if fw <= 0: fw = 300.0
		var lc: int = _hint_line_counts.get(hint_key, 1)
		for _i in range(lc):
			line_widths.append(fw)

	var line_count: int = _hint_line_counts.get(hint_key, 1)
	var current_progress: float = _hint_strike_progress.get(hint_key, 0.0)

	var tween := create_tween()
	if not strike_lines.is_empty():
		tween.tween_method(
			func(progress: float):
				_update_strikethrough_points(strike_lines, line_count, line_widths, progress),
			current_progress, 1.0, HINT_STRIKETHROUGH_DURATION
		).set_ease(Tween.EASE_OUT)

	tween.tween_property(label, "modulate:a", 0.0, HINT_FADE_OUT_DURATION).set_ease(Tween.EASE_IN)
	tween.tween_callback(_finalize_hint_dismiss.bind(hint_key, label))


## Finalize hint removal after animation completes.
func _finalize_hint_dismiss(hint_key: String, label: RichTextLabel) -> void:
	_animating_hints.erase(hint_key)
	_hint_labels.erase(hint_key)
	_hint_strike_lines.erase(hint_key)
	_hint_strike_progress.erase(hint_key)
	_hint_line_counts.erase(hint_key)
	_hint_line_widths.erase(hint_key)
	if is_instance_valid(label):
		label.queue_free()
	if _hint_labels.is_empty() and _animating_hints.is_empty():
		_hints_showing = false
		_hints_active = false
		_dismiss_timer.stop()
		# Mark weapon seen only when all hints were dismissed by player completing the training.
		# Not when dismissed by auto-dismiss timer or weapon switch (_dismiss_hints_immediate).
		if _last_dismiss_was_player_action and not _current_weapon_id.is_empty():
			var settings: Node = get_node_or_null("/root/WeaponHintsSettings")
			if settings:
				settings.mark_weapon_seen(_current_weapon_id)
	_log_to_file("Hint '%s' dismissed" % hint_key)


## Dismiss all hints with strikethrough-then-fade-out animation.
func dismiss_hints() -> void:
	_dismiss_timer.stop()

	for hint_key in _hint_labels.keys().duplicate():
		_dismiss_hint(hint_key)


## Dismiss hints immediately without animation (used when weapon changes mid-display).
func _dismiss_hints_immediate() -> void:
	_dismiss_timer.stop()
	_hints_showing = false
	_hints_active = false

	for hint_key in _hint_labels.keys():
		var label: RichTextLabel = _hint_labels[hint_key]
		if label != null and is_instance_valid(label):
			label.queue_free()

	_hint_labels.clear()
	_hint_strike_lines.clear()
	_hint_strike_progress.clear()
	_hint_line_counts.clear()
	_hint_line_widths.clear()
	_animating_hints.clear()
	_disconnect_weapon_signals()
	_log_to_file("All hints dismissed immediately")


## Disconnect signals from the current weapon node.
func _disconnect_weapon_signals() -> void:
	var weapon := _current_weapon_node
	_current_weapon_node = null

	if weapon != null and is_instance_valid(weapon):
		if weapon.has_signal("Fired") and weapon.Fired.is_connected(_on_weapon_fired):
			weapon.Fired.disconnect(_on_weapon_fired)
		if weapon.has_signal("ShotFired") and weapon.ShotFired.is_connected(_on_weapon_fired):
			weapon.ShotFired.disconnect(_on_weapon_fired)
		if weapon.has_signal("ActionStateChanged") and weapon.ActionStateChanged.is_connected(_on_shotgun_action_state_changed):
			weapon.ActionStateChanged.disconnect(_on_shotgun_action_state_changed)
		if weapon.has_signal("ReloadStateChanged") and weapon.ReloadStateChanged.is_connected(_on_shotgun_reload_state_changed):
			weapon.ReloadStateChanged.disconnect(_on_shotgun_reload_state_changed)
		if weapon.has_signal("ReloadStateChanged") and weapon.ReloadStateChanged.is_connected(_on_revolver_reload_state_changed):
			weapon.ReloadStateChanged.disconnect(_on_revolver_reload_state_changed)
		if weapon.has_signal("BoltStepChanged") and weapon.BoltStepChanged.is_connected(_on_sniper_bolt_step_changed):
			weapon.BoltStepChanged.disconnect(_on_sniper_bolt_step_changed)
		if weapon.has_signal("ScopeStateChanged") and weapon.ScopeStateChanged.is_connected(_on_scope_state_changed):
			weapon.ScopeStateChanged.disconnect(_on_scope_state_changed)
		if weapon.has_signal("HammerCocked") and weapon.HammerCocked.is_connected(_on_hammer_cocked):
			weapon.HammerCocked.disconnect(_on_hammer_cocked)
		if weapon.has_signal("FireModeChanged") and weapon.FireModeChanged.is_connected(_on_fire_mode_changed):
			weapon.FireModeChanged.disconnect(_on_fire_mode_changed)
		if weapon.has_signal("GrenadeFired") and weapon.GrenadeFired.is_connected(_on_grenade_launcher_fired):
			weapon.GrenadeFired.disconnect(_on_grenade_launcher_fired)

	if _player and is_instance_valid(_player):
		if _player.has_signal("ReloadCompleted") and _player.ReloadCompleted.is_connected(_on_reload_completed):
			_player.ReloadCompleted.disconnect(_on_reload_completed)
		if _player.has_signal("reload_completed") and _player.reload_completed.is_connected(_on_reload_completed):
			_player.reload_completed.disconnect(_on_reload_completed)
		if _player.has_signal("ReloadSequenceProgress") and _player.ReloadSequenceProgress.is_connected(_on_reload_sequence_progress):
			_player.ReloadSequenceProgress.disconnect(_on_reload_sequence_progress)
		if _player.has_signal("GrenadeThrown") and _player.GrenadeThrown.is_connected(_on_player_grenade_thrown):
			_player.GrenadeThrown.disconnect(_on_player_grenade_thrown)
		if _player.has_signal("grenade_thrown") and _player.grenade_thrown.is_connected(_on_player_grenade_thrown):
			_player.grenade_thrown.disconnect(_on_player_grenade_thrown)


## Reset per-weapon hint tracking state.
func _reset_hint_state() -> void:
	_shots_fired = 0
	_bolt_cycle_hint_revealed = false
	_reload_hint_revealed = false
	_scope_used = false
	_hammer_cocked = false
	_fire_mode_hint_pending = false
	_shotgun_full_reload_active = false
	_shotgun_node = null
	_shotgun_reload_loaded_shell = false
	_revolver_reload_loaded_cartridge = false
	_ak_gl_launcher_hint_shown = false
	_reset_grenade_hint_tracking()
	_last_dismiss_was_player_action = false
	_disconnect_weapon_signals()
	# Note: _pending_unlock is NOT cleared here — it is consumed by _on_weapon_selected


## Update positions of all hint labels to float above the player.
## Mirrors labyrinth_level.gd _update_tutorial_hint_positions().
func _update_hint_positions() -> void:
	if _player == null or not is_instance_valid(_player):
		return

	var canvas_transform: Transform2D = get_viewport().get_canvas_transform()
	var screen_pos: Vector2 = canvas_transform * _player.global_position

	var index := 0
	for hint_key in _hint_labels:
		var label: RichTextLabel = _hint_labels[hint_key]
		if label == null or not is_instance_valid(label):
			continue
		label.custom_minimum_size = HINT_MIN_SIZE
		label.position = screen_pos + Vector2(HINT_OFFSET_X, HINT_OFFSET_Y - index * HINT_SPACING)
		index += 1


## Called when revolver reload state changes — updates hint text step-by-step.
## Mirrors labyrinth_level.gd _on_tutorial_revolver_reload_state_changed().
## RevolverReloadState: 0=NotReloading, 1=CylinderOpen, 2=Loading, 3=ClosingCylinder
func _on_revolver_reload_state_changed(new_state: int) -> void:
	if not _hint_labels.has(HINT_KEY_RELOAD):
		return

	# State 0 means the cylinder closed. Only dismiss after a cartridge was inserted;
	# opening and closing without loading is an aborted taught action.
	if new_state == 0:
		if _revolver_reload_loaded_cartridge:
			_log_to_file("Revolver reload completed after cartridge load")
			_on_reload_completed()
		else:
			_rollback_revolver_reload_hint()
		return

	var hint_step: int = 0
	match new_state:
		1:
			hint_step = 1  # CylinderOpen → highlight insert cartridge
		2:
			hint_step = 2  # Loading → highlight close cylinder
			_revolver_reload_loaded_cartridge = true
		_:
			hint_step = 3  # Done (shouldn't normally reach here now)

	var label: RichTextLabel = _hint_labels[HINT_KEY_RELOAD]
	if is_instance_valid(label):
		label.text = _build_revolver_reload_hint_bbcode(hint_step)
	_log_to_file("Revolver reload state %d → hint step %d updated" % [new_state, hint_step])


func _rollback_shotgun_reload_hint() -> void:
	_shotgun_reload_loaded_shell = false
	if _hint_labels.has(HINT_KEY_BOLT_CYCLE):
		_reset_hint_strikethrough(HINT_KEY_BOLT_CYCLE)
		var label: RichTextLabel = _hint_labels[HINT_KEY_BOLT_CYCLE]
		if is_instance_valid(label):
			label.text = _build_shotgun_full_reload_hint_bbcode(0)
	_log_to_file("Shotgun reload closed without loading — hint rolled back")


func _rollback_revolver_reload_hint() -> void:
	_revolver_reload_loaded_cartridge = false
	if _hint_labels.has(HINT_KEY_RELOAD):
		_reset_hint_strikethrough(HINT_KEY_RELOAD)
		var label: RichTextLabel = _hint_labels[HINT_KEY_RELOAD]
		if is_instance_valid(label):
			label.text = _build_revolver_reload_hint_bbcode(0)
	_log_to_file("Revolver reload closed without loading — hint rolled back")


func _reset_hint_strikethrough(hint_key: String) -> void:
	if not _hint_strike_progress.has(hint_key):
		return
	_hint_strike_progress[hint_key] = 0.0
	var strike_lines: Array = _hint_strike_lines.get(hint_key, [])
	var line_count: int = _hint_line_counts.get(hint_key, 1)
	var line_widths: Array = _hint_line_widths.get(hint_key, [])
	if not strike_lines.is_empty():
		_update_strikethrough_points(strike_lines, line_count, line_widths, 0.0)


## Clean up when component is removed.
func _exit_tree() -> void:
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager:
		if game_manager.has_signal("weapon_unlocked") and game_manager.weapon_unlocked.is_connected(_on_weapon_unlocked):
			game_manager.weapon_unlocked.disconnect(_on_weapon_unlocked)
		if game_manager.has_signal("weapon_selected") and game_manager.weapon_selected.is_connected(_on_weapon_selected):
			game_manager.weapon_selected.disconnect(_on_weapon_selected)

	_disconnect_weapon_signals()

	for hint_key in _hint_labels.keys():
		var label = _hint_labels[hint_key]
		if label != null and is_instance_valid(label):
			label.queue_free()
	_hint_labels.clear()
	_hint_strike_lines.clear()
	_hint_strike_progress.clear()
	_hint_line_counts.clear()
	_hint_line_widths.clear()
	_animating_hints.clear()


## Log a message to the file logger if available.
func _log_to_file(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[WeaponHintsComponent] " + message)
	else:
		print("[WeaponHintsComponent] " + message)
