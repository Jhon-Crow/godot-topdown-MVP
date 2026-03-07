extends Node2D
## Tutorial level script for teaching player advanced controls.
##
## This script handles the tutorial flow:
## 1. Player switches fire mode (B key) - only if player has assault rifle
## 2. Player reloads (weapon-specific sequence; hint appears after 2 shots so player first
##    experiences running out of ammo)
##    - Standard: R -> F -> R with dynamic red highlight on NEXT step
##    - Shotgun: RMB UP → [MMB+RMB↓ xN] → RMB↓ (N updates live as shells are loaded)
##    - Sniper: 4-step bolt-action [←][↓][↑][→] with per-step red highlight
##    - Revolver: cylinder reload + hammer-cock hint from weapon pickup
## 3. Player throws a grenade — hint appears AFTER reload hint disappears (Bug fix #5)
##    (only shown if player actually has grenades, Bug fix #9)
## 4. Shows completion message with Q restart hint
##
## Issue #808: Each hint shown independently; dismissed independently when action is done.
## Issue #945: (1) Reload hint shown after 2 shots. (2) Each hint has a unique color.
## (3) The NEXT button in a multi-step action is highlighted in red using BBCode.
##
## Bug fixes (3rd review round, Issue #945):
## Fix #1: HINT_SPACING increased to 60 px to prevent overlap.
## Fix #2: ShotFired fallback signal added for shotgun bolt-cycle hint.
## Fix #3: Sniper bolt-cycle hint text updated step-by-step via BoltStepChanged.
## Fix #4: Sniper bolt-action shows 4 separate steps [←][↓][↑][→] (not [←↓↑→]).
## Fix #5: Grenade hint shown AFTER reload disappears, not simultaneously.
## Fix #6: M16 shows fire-mode switch (B) hint after reload completes.
## Fix #7: Shotgun reload hint count (xN) updates live as shells are loaded; dismissed on reload.
## Fix #8: Revolver hammer-cock hint stays until player manually cocks (not dismissed on reload).
## Fix #9: Grenade hint only shown when player actually has grenades.
## Fix #10: AK GL shows underbarrel grenade launcher hint (RMB) after reload if round is loaded.
##
## On this tutorial level, grenades are infinite so player can practice.
## Floating key prompts appear near the player until the action is completed.

## Reference to the player node.
var _player: Node2D = null

## Reference to the UI container.
var _ui: Control = null

## Reference to the ammo count label.
var _ammo_label: Label = null

## Tutorial state tracking.
enum TutorialStep {
	SWITCH_FIRE_MODE,
	RELOAD,
	SCOPE_TRAINING,
	THROW_GRENADE,
	COMPLETED
}

## Current tutorial step.
var _current_step: TutorialStep = TutorialStep.SWITCH_FIRE_MODE

## Whether the player has reloaded.
var _has_reloaded: bool = false

## Whether the player has switched fire mode.
var _has_switched_fire_mode: bool = false

## Whether the player has thrown a grenade.
var _has_thrown_grenade: bool = false

## Whether the player has an assault rifle (for fire mode tutorial step).
var _has_assault_rifle: bool = false

## Whether the player has a shotgun (for shotgun-specific tutorial).
var _has_shotgun: bool = false

## Whether the player has a sniper rifle (for sniper-specific tutorial).
var _has_sniper_rifle: bool = false

## Whether the player has a Makarov PM (for pistol R->R reload tutorial).
var _has_makarov_pm: bool = false

## Whether the player has a revolver (for revolver-specific cylinder reload tutorial).
var _has_revolver: bool = false

## Whether the player has an AK GL (for underbarrel grenade launcher tutorial, Bug fix #10).
var _has_ak_gl: bool = false

## Reference to the player's assault rifle weapon (for fire mode tracking).
var _assault_rifle: Node = null

## Reference to the player's shotgun weapon (for shotgun-specific tracking).
var _shotgun: Node = null

## Reference to the player's sniper rifle weapon (for sniper-specific tracking).
var _sniper_rifle: Node = null

## Whether the sniper bolt has been cycled (for tutorial reload step tracking).
var _sniper_bolt_cycled: bool = false

## Whether the scope has been used (for sniper scope training step).
var _scope_used: bool = false

## Hint keys used in the multi-hint system (Issue #808).
const HINT_RELOAD := "reload"
const HINT_GRENADE := "grenade"
const HINT_BOLT_CYCLE := "bolt_cycle"
const HINT_SCOPE := "scope"
const HINT_FIRE_MODE := "fire_mode"
const HINT_HAMMER_COCK := "hammer_cock"
const HINT_GRENADE_LAUNCHER := "grenade_launcher"  ## AK GL underbarrel (Bug fix #10)

## Dictionary of active hint labels: hint_key -> RichTextLabel node.
## Each hint is shown simultaneously and removed independently when the action completes.
var _hint_labels: Dictionary = {}

## Vertical spacing between stacked hints above the player (pixels).
## Increased to 60 to prevent overlap when hints wrap to 2 lines (Bug fix #1 round 3).
const HINT_SPACING := 60

## Number of shots fired by the player (Issue #945: reload hint appears after 2 shots).
var _shots_fired: int = 0

## Whether the reload hint has already been revealed (Issue #945).
var _reload_hint_revealed: bool = false

## Whether the bolt-cycle hint has already been revealed (sniper/shotgun after 1st shot).
var _bolt_cycle_hint_revealed: bool = false

## Unique colors for each hint type (Issue #945: simultaneously displayed hints should be different colors).
const HINT_COLOR_FIRE_MODE := Color(0.3, 0.9, 1.0, 1.0)          ## Cyan — fire mode switch
const HINT_COLOR_RELOAD := Color(0.4, 1.0, 0.5, 1.0)             ## Green — reload
const HINT_COLOR_GRENADE := Color(1.0, 0.65, 0.0, 1.0)           ## Orange — grenade
const HINT_COLOR_BOLT_CYCLE := Color(0.85, 0.6, 1.0, 1.0)        ## Purple — bolt cycling
const HINT_COLOR_SCOPE := Color(0.3, 0.9, 1.0, 1.0)              ## Cyan — scope aiming
const HINT_COLOR_HAMMER_COCK := Color(1.0, 0.8, 0.3, 1.0)        ## Yellow — hammer cock
const HINT_COLOR_GRENADE_LAUNCHER := Color(1.0, 0.4, 0.2, 1.0)   ## Red-orange — AK GL


func _ready() -> void:
	print("Tutorial level loaded - Обучение")

	# Find player
	_player = get_node_or_null("Entities/Player")
	if _player == null:
		push_error("Tutorial: Player not found!")
		return

	# Swap weapon based on GameManager selection
	_setup_selected_weapon()

	# Setup realistic visibility component (Issue #540)
	_setup_realistic_visibility()

	# Find UI container
	_ui = get_node_or_null("CanvasLayer/UI")

	# Find the ammo label
	_ammo_label = get_node_or_null("CanvasLayer/UI/AmmoLabel")

	# Connect to player signals for tracking actions
	_connect_player_signals()

	# Setup ammo tracking
	_setup_ammo_tracking()

	# Find and setup targets (for practice, but not part of tutorial progression)
	_setup_targets()

	# Determine initial tutorial step based on weapon type
	_set_initial_step()

	# Create initial hints based on starting step
	_setup_initial_hints()

	# Register player with GameManager
	if GameManager:
		GameManager.set_player(_player)


## Setup realistic visibility for the player (Issue #540).
## Adds the RealisticVisibilityComponent to the player node.
func _setup_realistic_visibility() -> void:
	if _player == null:
		return

	var visibility_script = load("res://scripts/components/realistic_visibility_component.gd")
	if visibility_script == null:
		push_warning("[TutorialLevel] RealisticVisibilityComponent script not found")
		return

	var visibility_component = Node.new()
	visibility_component.name = "RealisticVisibilityComponent"
	visibility_component.set_script(visibility_script)
	_player.add_child(visibility_component)
	print("[TutorialLevel] Realistic visibility component added to player")


## Determine the initial tutorial step based on weapon type.
## Assault rifles start with fire mode switching, others skip to reload.
func _set_initial_step() -> void:
	# Check which weapon the player has
	var weapon = _player.get_node_or_null("AssaultRifle")
	var akgl = _player.get_node_or_null("AKGL")

	if weapon != null or akgl != null:
		# Assault rifles have fire mode switching
		_current_step = TutorialStep.SWITCH_FIRE_MODE
		print("[TutorialLevel] Starting with SWITCH_FIRE_MODE step (assault rifle detected)")
	else:
		# All other weapons skip fire mode and start with reload
		_current_step = TutorialStep.RELOAD
		print("[TutorialLevel] Starting with RELOAD step (non-assault rifle)")


## Setup the weapon based on GameManager's selected weapon.
## Removes the default MakarovPM and loads the selected weapon.
func _setup_selected_weapon() -> void:
	if _player == null:
		return

	# Get selected weapon from GameManager
	var selected_weapon_id: String = "makarov_pm"  # Default
	if GameManager:
		selected_weapon_id = GameManager.get_selected_weapon()

	print("Tutorial: Setting up weapon: %s" % selected_weapon_id)

	# Check if C# Player already equipped the correct weapon (via ApplySelectedWeaponFromGameManager)
	# This prevents double-equipping when both C# and GDScript weapon setup run
	if selected_weapon_id != "makarov_pm":
		var weapon_names: Dictionary = {
			"shotgun": "Shotgun",
			"mini_uzi": "MiniUzi",
			"silenced_pistol": "SilencedPistol",
			"sniper": "SniperRifle",
			"m16": "AssaultRifle",
			"ak_gl": "AKGL",
			"revolver": "Revolver"
		}
		if selected_weapon_id in weapon_names:
			var expected_name: String = weapon_names[selected_weapon_id]
			var existing_weapon = _player.get_node_or_null(expected_name)
			if existing_weapon != null and _player.get("CurrentWeapon") == existing_weapon:
				print("Tutorial: %s already equipped by C# Player - skipping" % expected_name)
				return

	# If shotgun is selected, we need to swap weapons
	if selected_weapon_id == "shotgun":
		# Remove the default MakarovPM
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov:
			makarov.queue_free()
			print("Tutorial: Removed default MakarovPM")

		# Load and add the shotgun
		var shotgun_scene = load("res://scenes/weapons/csharp/Shotgun.tscn")
		if shotgun_scene:
			var shotgun = shotgun_scene.instantiate()
			shotgun.name = "Shotgun"
			_player.add_child(shotgun)

			# Set the CurrentWeapon reference in C# Player
			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(shotgun)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = shotgun

			print("Tutorial: Shotgun equipped successfully")
		else:
			push_error("Tutorial: Failed to load Shotgun scene!")
	# If Mini UZI is selected, swap weapons
	elif selected_weapon_id == "mini_uzi":
		# Remove the default MakarovPM
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov:
			makarov.queue_free()
			print("Tutorial: Removed default MakarovPM")

		# Load and add the Mini UZI
		var mini_uzi_scene = load("res://scenes/weapons/csharp/MiniUzi.tscn")
		if mini_uzi_scene:
			var mini_uzi = mini_uzi_scene.instantiate()
			mini_uzi.name = "MiniUzi"
			_player.add_child(mini_uzi)

			# Set the CurrentWeapon reference in C# Player
			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(mini_uzi)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = mini_uzi

			print("Tutorial: Mini UZI equipped successfully")
		else:
			push_error("Tutorial: Failed to load MiniUzi scene!")
	# If Silenced Pistol is selected, swap weapons
	elif selected_weapon_id == "silenced_pistol":
		# Remove the default MakarovPM
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov:
			makarov.queue_free()
			print("Tutorial: Removed default MakarovPM")

		# Load and add the Silenced Pistol
		var pistol_scene = load("res://scenes/weapons/csharp/SilencedPistol.tscn")
		if pistol_scene:
			var pistol = pistol_scene.instantiate()
			pistol.name = "SilencedPistol"
			_player.add_child(pistol)

			# Set the CurrentWeapon reference in C# Player
			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(pistol)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = pistol

			print("Tutorial: Silenced Pistol equipped successfully")
		else:
			push_error("Tutorial: Failed to load SilencedPistol scene!")
	# If Sniper Rifle (ASVK) is selected, swap weapons
	elif selected_weapon_id == "sniper":
		# Remove the default MakarovPM
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov:
			makarov.queue_free()
			print("Tutorial: Removed default MakarovPM")

		# Load and add the Sniper Rifle
		var sniper_scene = load("res://scenes/weapons/csharp/SniperRifle.tscn")
		if sniper_scene:
			var sniper = sniper_scene.instantiate()
			sniper.name = "SniperRifle"
			_player.add_child(sniper)

			# Set the CurrentWeapon reference in C# Player
			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(sniper)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = sniper

			print("Tutorial: ASVK Sniper Rifle equipped successfully")
		else:
			push_error("Tutorial: Failed to load SniperRifle scene!")
	# If M16 (assault rifle) is selected, swap weapons
	elif selected_weapon_id == "m16":
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov:
			makarov.queue_free()
			print("Tutorial: Removed default MakarovPM")

		var m16_scene = load("res://scenes/weapons/csharp/AssaultRifle.tscn")
		if m16_scene:
			var m16 = m16_scene.instantiate()
			m16.name = "AssaultRifle"
			_player.add_child(m16)

			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(m16)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = m16

			print("Tutorial: M16 Assault Rifle equipped successfully")
		else:
			push_error("Tutorial: Failed to load AssaultRifle scene!")
	# If AK + GL is selected, swap weapons
	elif selected_weapon_id == "ak_gl":
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov:
			makarov.queue_free()
			print("Tutorial: Removed default MakarovPM")

		var akgl_scene = load("res://scenes/weapons/csharp/AKGL.tscn")
		if akgl_scene:
			var akgl = akgl_scene.instantiate()
			akgl.name = "AKGL"
			_player.add_child(akgl)

			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(akgl)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = akgl

			print("Tutorial: AK + GL equipped successfully")
		else:
			push_error("Tutorial: Failed to load AKGL scene!")
	# If Revolver is selected, swap weapons
	elif selected_weapon_id == "revolver":
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov:
			makarov.queue_free()
			print("Tutorial: Removed default MakarovPM")

		var revolver_scene = load("res://scenes/weapons/csharp/Revolver.tscn")
		if revolver_scene:
			var revolver = revolver_scene.instantiate()
			revolver.name = "Revolver"
			_player.add_child(revolver)

			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(revolver)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = revolver

			print("Tutorial: RSh-12 Revolver equipped successfully")
		else:
			push_error("Tutorial: Failed to load Revolver scene!")
	# For Makarov PM, it's already in the scene - just ensure it's equipped
	else:
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov and _player.get("CurrentWeapon") == null:
			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(makarov)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = makarov


func _process(_delta: float) -> void:
	# Update all floating hint positions to follow player
	_update_all_hint_positions()


## Connect the Fired signal of a weapon node to the shot counter (Issue #945).
## Bug fix #2: also try "ShotFired" as an alternative signal name for compatibility.
func _connect_weapon_fired_signal(weapon_node: Node) -> void:
	if weapon_node == null:
		return
	if weapon_node.has_signal("Fired"):
		weapon_node.Fired.connect(_on_weapon_fired)
		print("Tutorial: Connected to Fired signal on %s" % weapon_node.name)
	elif weapon_node.has_signal("ShotFired"):
		weapon_node.ShotFired.connect(_on_weapon_fired)
		print("Tutorial: Connected to ShotFired signal on %s" % weapon_node.name)
	else:
		push_warning("Tutorial: No Fired/ShotFired signal on %s — bolt-cycle hint may not appear" % weapon_node.name)


## Connect to player signals for tracking tutorial actions.
func _connect_player_signals() -> void:
	if _player == null:
		return

	# Connect ReloadSequenceProgress for dynamic next-button highlighting (Issue #945)
	if _player.has_signal("ReloadSequenceProgress"):
		_player.ReloadSequenceProgress.connect(_on_reload_sequence_progress)
		print("Tutorial: Connected to ReloadSequenceProgress signal")

	# Try to connect to weapon signals (C# Player)
	var weapon = _player.get_node_or_null("AssaultRifle")
	var akgl = _player.get_node_or_null("AKGL")
	var sniper_rifle = _player.get_node_or_null("SniperRifle")
	var shotgun = _player.get_node_or_null("Shotgun")
	var mini_uzi = _player.get_node_or_null("MiniUzi")
	var makarov_pm = _player.get_node_or_null("MakarovPM")
	var revolver = _player.get_node_or_null("Revolver")

	if sniper_rifle != null:
		_sniper_rifle = sniper_rifle
		_has_sniper_rifle = true
		print("Tutorial: Player has ASVK Sniper Rifle - sniper-specific tutorial enabled")

		# Connect shot counter for reload hint reveal (Issue #945)
		_connect_weapon_fired_signal(sniper_rifle)

		# Connect to bolt step changed signal for tracking reload
		if sniper_rifle.has_signal("BoltStepChanged"):
			sniper_rifle.BoltStepChanged.connect(_on_sniper_bolt_step_changed)
			print("Tutorial: Connected to BoltStepChanged signal")

		# Connect to sniper ammo signal
		if sniper_rifle.has_signal("AmmoChanged"):
			sniper_rifle.AmmoChanged.connect(_on_weapon_ammo_changed)

		# Connect to scope state changed signal for scope training
		if sniper_rifle.has_signal("ScopeStateChanged"):
			sniper_rifle.ScopeStateChanged.connect(_on_scope_state_changed)
			print("Tutorial: Connected to ScopeStateChanged signal")

	elif shotgun != null:
		_shotgun = shotgun
		_has_shotgun = true
		print("Tutorial: Player has Shotgun - shotgun-specific tutorial enabled")

		# Connect shot counter for reload hint reveal (Issue #945)
		_connect_weapon_fired_signal(shotgun)

		# Connect to reload signals from player (C# Player)
		if _player.has_signal("ReloadCompleted"):
			_player.ReloadCompleted.connect(_on_player_reload_completed)
		elif _player.has_signal("reload_completed"):
			_player.reload_completed.connect(_on_player_reload_completed)

		# Connect to shotgun ammo signal
		if shotgun.has_signal("AmmoChanged"):
			shotgun.AmmoChanged.connect(_on_weapon_ammo_changed)

	elif mini_uzi != null:
		# Mini UZI uses rifle-like reload (no fire mode switching)
		print("Tutorial: Player has Mini UZI - rifle-like reload tutorial")

		# Connect shot counter for reload hint reveal (Issue #945)
		_connect_weapon_fired_signal(mini_uzi)

		# Connect to reload signals from player (C# Player)
		if _player.has_signal("ReloadCompleted"):
			_player.ReloadCompleted.connect(_on_player_reload_completed)
		elif _player.has_signal("reload_completed"):
			_player.reload_completed.connect(_on_player_reload_completed)

		# Connect to Mini UZI ammo signal
		if mini_uzi.has_signal("AmmoChanged"):
			mini_uzi.AmmoChanged.connect(_on_weapon_ammo_changed)

	elif weapon != null:
		_assault_rifle = weapon
		_has_assault_rifle = true
		print("Tutorial: Player has AssaultRifle - fire mode tutorial enabled")

		# Connect shot counter for reload hint reveal (Issue #945)
		_connect_weapon_fired_signal(weapon)

		# Connect to reload signals from player (C# Player)
		if _player.has_signal("ReloadCompleted"):
			_player.ReloadCompleted.connect(_on_player_reload_completed)
		elif _player.has_signal("reload_completed"):
			_player.reload_completed.connect(_on_player_reload_completed)

		# Connect to fire mode changed signal from weapon
		if weapon.has_signal("FireModeChanged"):
			weapon.FireModeChanged.connect(_on_fire_mode_changed)
			print("Tutorial: Connected to FireModeChanged signal")

	elif akgl != null:
		_assault_rifle = akgl
		_has_assault_rifle = true
		_has_ak_gl = true
		print("Tutorial: Player has AKGL - fire mode tutorial enabled")

		# Connect shot counter for reload hint reveal (Issue #945)
		_connect_weapon_fired_signal(akgl)

		# Connect to reload signals from player (C# Player)
		if _player.has_signal("ReloadCompleted"):
			_player.ReloadCompleted.connect(_on_player_reload_completed)
		elif _player.has_signal("reload_completed"):
			_player.reload_completed.connect(_on_player_reload_completed)

		# Connect to fire mode changed signal from AKGL
		if akgl.has_signal("FireModeChanged"):
			akgl.FireModeChanged.connect(_on_fire_mode_changed)
			print("Tutorial: Connected to FireModeChanged signal (AKGL)")

	elif revolver != null:
		_has_revolver = true
		print("Tutorial: Player has RSh-12 Revolver - cylinder reload tutorial enabled")

		# Connect shot counter for reload hint reveal (Issue #945)
		_connect_weapon_fired_signal(revolver)

		# Connect to reload signals from player (C# Player)
		if _player.has_signal("ReloadCompleted"):
			_player.ReloadCompleted.connect(_on_player_reload_completed)
		elif _player.has_signal("reload_completed"):
			_player.reload_completed.connect(_on_player_reload_completed)

		# Connect to hammer cocked signal to dismiss hammer hint (Issue #808)
		if revolver.has_signal("HammerCocked"):
			revolver.HammerCocked.connect(_on_revolver_hammer_cocked)
			print("Tutorial: Connected to HammerCocked signal")

		# Connect to revolver ammo signal
		if revolver.has_signal("AmmoChanged"):
			revolver.AmmoChanged.connect(_on_weapon_ammo_changed)

	elif makarov_pm != null:
		_has_makarov_pm = true
		print("Tutorial: Player has MakarovPM - pistol tutorial (R->R reload)")

		# Connect shot counter for reload hint reveal (Issue #945)
		_connect_weapon_fired_signal(makarov_pm)

		# Connect to reload signals from player (C# Player)
		if _player.has_signal("ReloadCompleted"):
			_player.ReloadCompleted.connect(_on_player_reload_completed)
		elif _player.has_signal("reload_completed"):
			_player.reload_completed.connect(_on_player_reload_completed)

		# Connect to MakarovPM ammo signal
		if makarov_pm.has_signal("AmmoChanged"):
			makarov_pm.AmmoChanged.connect(_on_weapon_ammo_changed)

	elif not _has_sniper_rifle:
		# GDScript player (only if no sniper rifle was detected earlier)
		if _player.has_signal("reload_completed"):
			_player.reload_completed.connect(_on_player_reload_completed)

	# Connect to grenade thrown signal (both C# and GDScript players)
	if _player.has_signal("GrenadeThrown"):
		_player.GrenadeThrown.connect(_on_player_grenade_thrown)
		print("Tutorial: Connected to GrenadeThrown signal (C#)")
	elif _player.has_signal("grenade_thrown"):
		_player.grenade_thrown.connect(_on_player_grenade_thrown)
		print("Tutorial: Connected to grenade_thrown signal (GDScript)")


## Setup ammo tracking for the player's weapon.
func _setup_ammo_tracking() -> void:
	if _player == null:
		return

	# Try to get the player's weapon for C# Player
	var shotgun = _player.get_node_or_null("Shotgun")
	var mini_uzi = _player.get_node_or_null("MiniUzi")
	var silenced_pistol = _player.get_node_or_null("SilencedPistol")
	var sniper_rifle = _player.get_node_or_null("SniperRifle")
	var weapon = _player.get_node_or_null("AssaultRifle")
	var akgl = _player.get_node_or_null("AKGL")
	var makarov_pm = _player.get_node_or_null("MakarovPM")
	var revolver = _player.get_node_or_null("Revolver")

	if shotgun != null:
		# C# Player with shotgun - connect to weapon signals
		if shotgun.has_signal("AmmoChanged"):
			shotgun.AmmoChanged.connect(_on_weapon_ammo_changed)
		# Connect to ShellCountChanged for real-time UI update during shell-by-shell reload
		if shotgun.has_signal("ShellCountChanged"):
			shotgun.ShellCountChanged.connect(_on_shell_count_changed)
		# Initial ammo display from shotgun
		if shotgun.get("CurrentAmmo") != null and shotgun.get("ReserveAmmo") != null:
			_update_ammo_label_magazine(shotgun.CurrentAmmo, shotgun.ReserveAmmo)
	elif mini_uzi != null:
		# C# Player with Mini UZI - connect to weapon signals
		if mini_uzi.has_signal("AmmoChanged"):
			mini_uzi.AmmoChanged.connect(_on_weapon_ammo_changed)
		# Initial ammo display from Mini UZI
		if mini_uzi.get("CurrentAmmo") != null and mini_uzi.get("ReserveAmmo") != null:
			_update_ammo_label_magazine(mini_uzi.CurrentAmmo, mini_uzi.ReserveAmmo)
	elif silenced_pistol != null:
		# C# Player with Silenced Pistol - connect to weapon signals
		if silenced_pistol.has_signal("AmmoChanged"):
			silenced_pistol.AmmoChanged.connect(_on_weapon_ammo_changed)
		# Initial ammo display from Silenced Pistol
		if silenced_pistol.get("CurrentAmmo") != null and silenced_pistol.get("ReserveAmmo") != null:
			_update_ammo_label_magazine(silenced_pistol.CurrentAmmo, silenced_pistol.ReserveAmmo)
	elif sniper_rifle != null:
		# C# Player with Sniper Rifle - connect to weapon signals
		if sniper_rifle.has_signal("AmmoChanged"):
			sniper_rifle.AmmoChanged.connect(_on_weapon_ammo_changed)
		# Initial ammo display from Sniper Rifle
		if sniper_rifle.get("CurrentAmmo") != null and sniper_rifle.get("ReserveAmmo") != null:
			_update_ammo_label_magazine(sniper_rifle.CurrentAmmo, sniper_rifle.ReserveAmmo)
	elif weapon != null:
		# C# Player with assault rifle - connect to weapon signals
		if weapon.has_signal("AmmoChanged"):
			weapon.AmmoChanged.connect(_on_weapon_ammo_changed)
		# Initial ammo display from weapon
		if weapon.get("CurrentAmmo") != null and weapon.get("ReserveAmmo") != null:
			_update_ammo_label_magazine(weapon.CurrentAmmo, weapon.ReserveAmmo)
	elif akgl != null:
		# C# Player with AKGL - connect to weapon signals
		if akgl.has_signal("AmmoChanged"):
			akgl.AmmoChanged.connect(_on_weapon_ammo_changed)
		# Initial ammo display from AKGL
		if akgl.get("CurrentAmmo") != null and akgl.get("ReserveAmmo") != null:
			_update_ammo_label_magazine(akgl.CurrentAmmo, akgl.ReserveAmmo)
	elif revolver != null:
		# C# Player with Revolver - connect to weapon signals
		if revolver.has_signal("AmmoChanged"):
			revolver.AmmoChanged.connect(_on_weapon_ammo_changed)
		# Connect to CartridgeInserted for real-time UI update during cylinder reload
		if revolver.has_signal("CartridgeInserted"):
			revolver.CartridgeInserted.connect(_on_revolver_cartridge_inserted)
		# Initial ammo display from Revolver
		if revolver.get("CurrentAmmo") != null and revolver.get("ReserveAmmo") != null:
			_update_ammo_label_magazine(revolver.CurrentAmmo, revolver.ReserveAmmo)
	elif makarov_pm != null:
		# C# Player with MakarovPM - connect to weapon signals
		if makarov_pm.has_signal("AmmoChanged"):
			makarov_pm.AmmoChanged.connect(_on_weapon_ammo_changed)
		# Initial ammo display from MakarovPM
		if makarov_pm.get("CurrentAmmo") != null and makarov_pm.get("ReserveAmmo") != null:
			_update_ammo_label_magazine(makarov_pm.CurrentAmmo, makarov_pm.ReserveAmmo)
	else:
		# GDScript Player - connect to player signals
		if _player.has_signal("ammo_changed"):
			_player.ammo_changed.connect(_on_player_ammo_changed)
		# Initial ammo display
		if _player.has_method("get_current_ammo") and _player.has_method("get_max_ammo"):
			_update_ammo_label(_player.get_current_ammo(), _player.get_max_ammo())


## Called when weapon ammo changes (C# Player).
func _on_weapon_ammo_changed(current_ammo: int, reserve_ammo: int) -> void:
	_update_ammo_label_magazine(current_ammo, reserve_ammo)


## Called when player ammo changes (GDScript Player).
func _on_player_ammo_changed(current: int, maximum: int) -> void:
	_update_ammo_label(current, maximum)


## Update the ammo label with color coding (simple format for GDScript Player).
func _update_ammo_label(current: int, maximum: int) -> void:
	if _ammo_label == null:
		return

	_ammo_label.text = "AMMO: %d/%d" % [current, maximum]

	# Color coding: red at <=5, yellow at <=10, white otherwise
	if current <= 5:
		_ammo_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1.0))
	elif current <= 10:
		_ammo_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.2, 1.0))
	else:
		_ammo_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))


## Update the ammo label with magazine format (for C# Player with weapon).
## Shows format: AMMO: magazine/reserve (e.g., "AMMO: 30/60")
func _update_ammo_label_magazine(current_mag: int, reserve: int) -> void:
	if _ammo_label == null:
		return

	_ammo_label.text = "AMMO: %d/%d" % [current_mag, reserve]

	# Color coding: red when mag <=5, yellow when mag <=10
	if current_mag <= 5:
		_ammo_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1.0))
	elif current_mag <= 10:
		_ammo_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.2, 1.0))
	else:
		_ammo_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))


## Called when shotgun shell count changes (during shell-by-shell reload).
## This allows the ammo counter to update immediately as each shell is loaded.
## Bug fix #7: also updates the bolt-cycle hint to reflect the remaining shells to load.
func _on_shell_count_changed(shell_count: int, _capacity: int) -> void:
	# Get the reserve ammo from the weapon for display
	var reserve_ammo: int = 0
	if _player:
		var shotgun = _player.get_node_or_null("Shotgun")
		if shotgun != null and shotgun.get("ReserveAmmo") != null:
			reserve_ammo = shotgun.ReserveAmmo
	_update_ammo_label_magazine(shell_count, reserve_ammo)
	# Bug fix #7: update bolt-cycle hint with new shell count to load
	if _hint_labels.has(HINT_BOLT_CYCLE):
		var label: RichTextLabel = _hint_labels[HINT_BOLT_CYCLE]
		if is_instance_valid(label):
			label.text = _build_shotgun_reload_hint_bbcode()


## Called when revolver cartridge is inserted (during cylinder reload).
## This allows the ammo counter to update immediately as each cartridge is loaded.
func _on_revolver_cartridge_inserted(loaded: int, _capacity: int) -> void:
	# Get the reserve ammo from the weapon for display
	var reserve_ammo: int = 0
	if _player:
		var revolver = _player.get_node_or_null("Revolver")
		if revolver != null and revolver.get("ReserveAmmo") != null:
			reserve_ammo = revolver.ReserveAmmo
		if revolver != null and revolver.get("CurrentAmmo") != null:
			_update_ammo_label_magazine(revolver.CurrentAmmo, reserve_ammo)


## Setup targets for shooting practice (optional, not part of tutorial progression).
func _setup_targets() -> void:
	var targets_node := get_node_or_null("Environment/Targets")
	if targets_node == null:
		print("Tutorial: No targets found (optional for practice)")
		return

	var target_count := 0
	for _target in targets_node.get_children():
		target_count += 1

	print("Tutorial: Found %d targets for practice" % target_count)


## Called when the player's weapon fires a shot (Issue #945).
## Counts shots and reveals hints based on shot count:
##   - Bolt-cycle hint (sniper/shotgun) appears after 1st shot.
##   - Reload hint appears after 2nd shot.
func _on_weapon_fired() -> void:
	_shots_fired += 1
	print("Tutorial: Shot fired (%d total)" % _shots_fired)

	# Bug fix: bolt-cycle hint (sniper bolt-action, shotgun bolt) shown after 1st shot.
	if _shots_fired >= 1 and not _bolt_cycle_hint_revealed:
		if _has_sniper_rifle or _has_shotgun:
			_bolt_cycle_hint_revealed = true
			_reveal_bolt_cycle_hint()

	if not _reload_hint_revealed and _shots_fired >= 2:
		_reload_hint_revealed = true
		_reveal_reload_hint()


## Called when the reload sequence progresses (Issue #945).
## Updates the reload hint to highlight the NEXT button in red.
## Bug fix #5: Revolver and shotgun have static reload hints that must not be overwritten.
func _on_reload_sequence_progress(step: int, total: int) -> void:
	# Revolver and shotgun use static hints — skip dynamic update to prevent overwriting
	if _has_revolver or _has_shotgun:
		return

	if not _hint_labels.has(HINT_RELOAD):
		return

	var new_text := _build_reload_hint_bbcode(step, total)
	if new_text.is_empty():
		return
	var label: RichTextLabel = _hint_labels[HINT_RELOAD]
	if is_instance_valid(label):
		label.text = new_text
	print("Tutorial: Reload sequence step %d/%d - hint updated" % [step, total])


## Build BBCode text for the reload hint based on current step (Issue #945).
## The NEXT required button is highlighted in red; completed steps are shown in grey.
## Bug fix #2: `step` is the LAST COMPLETED step (0 = nothing done yet, 1 = first press done, etc.).
##   So we highlight step+1 as the next action to perform.
## Bug fix #5: Only applies to weapons that use the R→F→R or R→R sequence.
##   Revolver and shotgun have their own static hints that should not be overwritten.
func _build_reload_hint_bbcode(step: int, total: int) -> String:
	# Guard: revolver and shotgun use static hints - do not overwrite them
	if _has_revolver or _has_shotgun:
		return ""

	if _has_makarov_pm or (_has_sniper_rifle == false and total <= 2):
		# Makarov PM / 2-step reload: R -> R
		# step=0 → next is R (first); step=1 → next is R (second); step=2 → done
		match step:
			0:
				return "[color=#ff4444][R][/color] [color=#888888][R][/color] Перезарядись"
			1:
				return "[color=#888888][R][/color] [color=#ff4444][R][/color] Перезарядись"
			_:
				return "[color=#888888][R] [R][/color] Перезарядись"
	else:
		# Standard 3-step reload: R -> F -> R
		# step=0 → next is R; step=1 → next is F; step=2 → next is R (final); step=3 → done
		match step:
			0:
				return "[color=#ff4444][R][/color] [color=#888888][F] [R][/color] Перезарядись"
			1:
				return "[color=#888888][R][/color] [color=#ff4444][F][/color] [color=#888888][R][/color] Перезарядись"
			2:
				return "[color=#888888][R] [F][/color] [color=#ff4444][R][/color] Перезарядись"
			_:
				return "[color=#888888][R] [F] [R][/color] Перезарядись"


## Reveal the bolt-cycle hint after the 1st shot (sniper/shotgun only).
## Bolt-cycle hint is shown separately from the reload hint so it appears earlier.
func _reveal_bolt_cycle_hint() -> void:
	if _current_step != TutorialStep.RELOAD:
		return

	print("Tutorial: 1st shot fired - revealing bolt-cycle hint")
	var canvas_layer := get_node_or_null("CanvasLayer")
	if canvas_layer == null:
		return

	if _has_sniper_rifle:
		if not _hint_labels.has(HINT_BOLT_CYCLE):
			# Bug fix #4: show 4 separate steps. Bug fix #3: first step highlighted red (step=0).
			_add_hint(HINT_BOLT_CYCLE, _build_sniper_bolt_hint_bbcode(0), canvas_layer)
	elif _has_shotgun:
		# Bug fix #7: hint shows actual number of shells to load based on remaining space.
		if not _hint_labels.has(HINT_BOLT_CYCLE):
			_add_hint(HINT_BOLT_CYCLE, _build_shotgun_reload_hint_bbcode(), canvas_layer)


## Reveal the reload-related hints when the player has fired 2 shots (Issue #945).
func _reveal_reload_hint() -> void:
	if _current_step != TutorialStep.RELOAD:
		return

	print("Tutorial: 2 shots fired - revealing reload hint")
	var canvas_layer := get_node_or_null("CanvasLayer")
	if canvas_layer == null:
		return

	_add_reload_hints(canvas_layer)


## Called when player switches fire mode.
func _on_fire_mode_changed(_new_mode: int) -> void:
	if _current_step != TutorialStep.SWITCH_FIRE_MODE:
		return

	if not _has_switched_fire_mode:
		_has_switched_fire_mode = true
		print("Tutorial: Player switched fire mode")
		# Remove fire mode hint and advance; reload + grenade hints will be shown together
		_dismiss_hint(HINT_FIRE_MODE)
		_advance_to_step(TutorialStep.RELOAD)


## Called when sniper rifle bolt step changes.
## The sniper bolt-action reload is complete when step 4 (close bolt) is reached.
## Bug fix #3: dynamically updates bolt-cycle hint text to highlight the NEXT step in red.
func _on_sniper_bolt_step_changed(step: int, total_steps: int) -> void:
	if _current_step != TutorialStep.RELOAD:
		return

	print("Tutorial: Sniper bolt step %d/%d" % [step, total_steps])

	# Bug fix #3: update bolt-cycle hint text to highlight the next step in red
	if _hint_labels.has(HINT_BOLT_CYCLE):
		var label: RichTextLabel = _hint_labels[HINT_BOLT_CYCLE]
		if is_instance_valid(label):
			label.text = _build_sniper_bolt_hint_bbcode(step)

	# Bolt cycling is complete when step reaches total (4/4 = bolt closed, ready to fire)
	if step >= total_steps and not _sniper_bolt_cycled:
		_sniper_bolt_cycled = true
		_has_reloaded = true
		print("Tutorial: Sniper bolt cycling completed")
		# Dismiss reload and bolt cycle hints; keep scope hint active
		_dismiss_hint(HINT_RELOAD)
		_dismiss_hint(HINT_BOLT_CYCLE)
		# After bolt-action reload, teach scope usage
		_advance_to_step(TutorialStep.SCOPE_TRAINING)


## Build BBCode for sniper bolt-cycle hint showing 4-step sequence with NEXT step in red.
## step = last COMPLETED step: 0=nothing done, 1=bolt up done, 2=bolt back done, etc.
func _build_sniper_bolt_hint_bbcode(step: int) -> String:
	# 4 steps: ← (bolt up/open), ↓ (bolt back), ↑ (bolt forward), → (bolt down/close)
	const STEPS := ["←", "↓", "↑", "→"]
	var parts: PackedStringArray = []
	for i in range(STEPS.size()):
		if i < step:
			parts.append("[color=#888888][%s][/color]" % STEPS[i])
		elif i == step:
			parts.append("[color=#ff4444][%s][/color]" % STEPS[i])
		else:
			parts.append("[color=#888888][%s][/color]" % STEPS[i])
	return " ".join(parts) + " Передёрни затвор"


## Build BBCode for shotgun reload hint with dynamic shell count (Bug fix #7).
## Shows: [ПКМ↑ открыть] [СКМ+ПКМ↓ xN] [ПКМ↓ закрыть] where N = shells to load.
func _build_shotgun_reload_hint_bbcode() -> String:
	var shells_needed: int = _get_shotgun_shells_to_load()
	return "[color=#ff4444][ПКМ↑ открыть][/color] [color=#888888][СКМ+ПКМ↓ x%d] [ПКМ↓ закрыть][/color]" % shells_needed


## Return the number of shells the shotgun still needs to fill up to capacity (Bug fix #7).
func _get_shotgun_shells_to_load() -> int:
	if _shotgun == null:
		return 8  # Default fallback
	var current_ammo = _shotgun.get("CurrentAmmo")
	var max_ammo = _shotgun.get("MaxAmmo")
	if current_ammo == null or max_ammo == null:
		return 8
	return int(max_ammo) - int(current_ammo)


## Called when scope state changes (activated/deactivated).
## Completes the scope training step when scope is used.
func _on_scope_state_changed(is_active: bool) -> void:
	if _current_step != TutorialStep.SCOPE_TRAINING:
		return

	# Scope training completes when the player activates the scope
	if is_active and not _scope_used:
		_scope_used = true
		print("Tutorial: Scope used - scope training complete")
		# Dismiss scope hint only; grenade hint remains
		_dismiss_hint(HINT_SCOPE)
		_advance_to_step(TutorialStep.THROW_GRENADE)


## Called when player completes reload.
func _on_player_reload_completed() -> void:
	if _current_step != TutorialStep.RELOAD:
		return

	if not _has_reloaded:
		_has_reloaded = true
		print("Tutorial: Player reloaded")
		# Dismiss reload hint; also dismiss bolt-cycle hint for shotgun (Bug fix #7).
		# Bug fix #8: do NOT dismiss hammer-cock hint here — it stays until player manually cocks.
		_dismiss_hint(HINT_RELOAD)
		if _has_shotgun:
			_dismiss_hint(HINT_BOLT_CYCLE)
		var canvas_layer := get_node_or_null("CanvasLayer")
		# Bug fix #6: M16 (assault rifle, not AK GL) shows fire-mode switch hint after reload.
		if _has_assault_rifle and not _has_ak_gl:
			if canvas_layer:
				_add_hint(HINT_FIRE_MODE,
					"[color=#ff4444][B][/color] Переключи режим стрельбы", canvas_layer)
		# Bug fix #10: AK GL shows underbarrel grenade launcher hint after reload (if round loaded).
		if _has_ak_gl and canvas_layer and _ak_gl_has_round_loaded():
			_add_hint(HINT_GRENADE_LAUNCHER,
				"[color=#ff4444][ПКМ][/color] Выстрели подствольным гранатомётом", canvas_layer)
		# If grenade was already thrown, go to COMPLETED; otherwise wait for grenade
		if _has_thrown_grenade:
			_advance_to_step(TutorialStep.COMPLETED)
		else:
			_advance_to_step(TutorialStep.THROW_GRENADE)


## Called when the revolver hammer is cocked (RMB press or LMB fire).
## Dismisses the hammer cock hint the first time the hammer is cocked (Issue #808).
func _on_revolver_hammer_cocked() -> void:
	_dismiss_hint(HINT_HAMMER_COCK)


## Called when player throws a grenade.
## Grenade can be thrown at any step that shows the grenade hint (RELOAD or THROW_GRENADE).
func _on_player_grenade_thrown() -> void:
	# Allow grenade dismissal from RELOAD step too (thrown before reload completes)
	if _current_step != TutorialStep.THROW_GRENADE and _current_step != TutorialStep.RELOAD:
		return

	if not _has_thrown_grenade:
		_has_thrown_grenade = true
		print("Tutorial: Player threw grenade")
		# Dismiss only the grenade hint (Issue #808)
		_dismiss_hint(HINT_GRENADE)
		# If grenade thrown before reload, stay in RELOAD step (reload hint still visible)
		if _current_step == TutorialStep.THROW_GRENADE:
			_advance_to_step(TutorialStep.COMPLETED)


## Advance to the next tutorial step.
func _advance_to_step(step: TutorialStep) -> void:
	_current_step = step
	_show_hints_for_step(step)

	if step == TutorialStep.COMPLETED:
		_show_completion_message()


## ============================================================
## Multi-hint system (Issue #808)
## ============================================================


## Setup initial hints based on the starting tutorial step.
func _setup_initial_hints() -> void:
	var canvas_layer := get_node_or_null("CanvasLayer")
	if canvas_layer == null:
		push_error("Tutorial: CanvasLayer not found - hints will not be displayed!")
		return

	match _current_step:
		TutorialStep.SWITCH_FIRE_MODE:
			_add_hint(HINT_FIRE_MODE,
				"[color=#ff4444][B][/color] Переключи режим стрельбы", canvas_layer)
		TutorialStep.RELOAD:
			# Issue #945: Reload hint is delayed until player fires 2 shots.
			# Do not show reload hints here; _on_weapon_fired() will reveal them.
			# Bug fix #3: Revolver hammer-cock hint is shown from the very start (on weapon pickup).
			if _has_revolver:
				_add_hint(HINT_HAMMER_COCK, "[color=#ff4444][ПКМ][/color] Взведи курок", canvas_layer)


## Show hints appropriate for the given step.
## Bug fix #5: grenade hint now appears AFTER reload disappears, not simultaneously.
## Bug fix #9: grenade hint only shown when player actually has grenades.
func _show_hints_for_step(step: TutorialStep) -> void:
	var canvas_layer := get_node_or_null("CanvasLayer")
	if canvas_layer == null:
		return

	match step:
		TutorialStep.RELOAD:
			# Issue #945: Reload hint is only shown after 2 shots.
			# _reveal_reload_hint() is called by _on_weapon_fired() after 2 shots.
			# If the player has already fired 2+ shots (e.g. after fire mode step), show immediately.
			if _reload_hint_revealed:
				_add_reload_hints(canvas_layer)
		TutorialStep.SCOPE_TRAINING:
			# Scope hint added after reload completes
			_add_hint(HINT_SCOPE, "[color=#ff4444][ПКМ][/color] Прицелься через оптику", canvas_layer)
		TutorialStep.THROW_GRENADE:
			# Bug fix #9: only show grenade hint if the player actually has grenades
			if _player_has_grenades():
				if not _hint_labels.has(HINT_GRENADE):
					_add_hint(HINT_GRENADE,
						"[color=#ff4444][G+ПКМ вправо][/color] [color=#888888][G+ПКМ→отпусти G] [ПКМ бросок][/color]",
						canvas_layer)
			else:
				# No grenades — skip grenade step and complete tutorial
				print("Tutorial: Player has no grenades — skipping grenade hint")
				_advance_to_step(TutorialStep.COMPLETED)
		TutorialStep.COMPLETED:
			# Remove any remaining hints
			for key in _hint_labels.keys():
				_dismiss_hint(key)


## Check whether the player currently holds at least one grenade (Bug fix #9).
func _player_has_grenades() -> bool:
	if _player == null:
		return false
	# Check via C# player property
	var grenade_count = _player.get("GrenadeCount")
	if grenade_count != null:
		return int(grenade_count) > 0
	# Fallback: tutorial level gives infinite grenades — always true on Tutorial map
	return true


## Check whether the AK GL currently has a round loaded in the grenade launcher (Bug fix #10).
func _ak_gl_has_round_loaded() -> bool:
	if _assault_rifle == null:
		return false
	# Check C# AKGL property for grenade launcher ammo
	var gl_ammo = _assault_rifle.get("GrenadeLauncherAmmo")
	if gl_ammo != null:
		return int(gl_ammo) > 0
	# Fallback: assume loaded if property not found
	return true


## Add reload-related hints for the current weapon type.
## For weapons with special features (sniper bolt, revolver hammer), each feature gets its own line.
## The grenade hint is always added alongside (Issue #808).
## Issue #945: Reload hint uses BBCode with the first step highlighted in red.
## Bug fix: Shotgun/sniper bolt-cycle hint is NOT added here (it appears after 1st shot via
##   _reveal_bolt_cycle_hint). Revolver hammer-cock hint is NOT added here (it appears from start).
func _add_reload_hints(canvas_layer: Node) -> void:
	# Add reload hint based on weapon type
	if _has_shotgun:
		# Shotgun: bolt-cycle hint already shown after 1st shot; reload hint is the same mechanic.
		# No separate reload hint needed - the bolt-cycle hint IS the reload instruction.
		pass
	elif _has_sniper_rifle:
		# Sniper: magazine swap reload hint. Bolt-cycle hint already shown after 1st shot.
		# Initial text = step 0 (nothing done yet, first R highlighted red).
		_add_hint(HINT_RELOAD, _build_reload_hint_bbcode(0, 3), canvas_layer)
	elif _has_revolver:
		# Revolver: cylinder reload hint. Hammer-cock hint is shown from start (Bug fix #3).
		_add_hint(HINT_RELOAD,
			"[color=#ff4444][R открыть][/color] [color=#888888][ПКМ↑ патрон] [скролл] [R закрыть][/color]",
			canvas_layer)
	elif _has_makarov_pm:
		# Makarov PM uses simplified R->R reload. Initial text = step 0.
		_add_hint(HINT_RELOAD, _build_reload_hint_bbcode(0, 2), canvas_layer)
	else:
		# Standard R->F->R. Initial text = step 0.
		_add_hint(HINT_RELOAD, _build_reload_hint_bbcode(0, 3), canvas_layer)

	# Bug fix #5: grenade hint is shown AFTER reload disappears, not simultaneously.
	# It is added in _show_hints_for_step(THROW_GRENADE) when reload is done.


## Get the unique color for a hint by its key (Issue #945: different colors per hint).
func _get_hint_color(hint_key: String) -> Color:
	match hint_key:
		HINT_FIRE_MODE:
			return HINT_COLOR_FIRE_MODE
		HINT_RELOAD:
			return HINT_COLOR_RELOAD
		HINT_GRENADE:
			return HINT_COLOR_GRENADE
		HINT_BOLT_CYCLE:
			return HINT_COLOR_BOLT_CYCLE
		HINT_SCOPE:
			return HINT_COLOR_SCOPE
		HINT_HAMMER_COCK:
			return HINT_COLOR_HAMMER_COCK
		HINT_GRENADE_LAUNCHER:
			return HINT_COLOR_GRENADE_LAUNCHER
		_:
			return Color(1.0, 1.0, 0.3, 1.0)  # Default yellow fallback


## Create and register a hint RichTextLabel with the given key and BBCode text.
## Issue #945: Uses RichTextLabel for BBCode color support (per-hint unique colors + red key highlights).
func _add_hint(hint_key: String, text: String, canvas_layer: Node) -> void:
	if _hint_labels.has(hint_key):
		# Already exists - just update text
		_hint_labels[hint_key].text = text
		return

	var label := RichTextLabel.new()
	label.name = "TutorialHint_" + hint_key
	label.bbcode_enabled = true
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("normal_font_size", 20)
	# Issue #945: unique color per hint type for easy differentiation
	label.add_theme_color_override("default_color", _get_hint_color(hint_key))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.custom_minimum_size = Vector2(300, 30)
	label.fit_content = true
	label.scroll_active = false

	canvas_layer.add_child(label)
	_hint_labels[hint_key] = label
	print("Tutorial: Added hint '%s': %s" % [hint_key, text])

	# Position immediately
	_update_hint_position(hint_key, label)


## Dismiss (remove) a single hint by key, leaving other hints visible.
func _dismiss_hint(hint_key: String) -> void:
	if not _hint_labels.has(hint_key):
		return

	var label: RichTextLabel = _hint_labels[hint_key]
	# Hide immediately so the label does not overlap new hints during the same frame
	# before queue_free() is processed.
	label.visible = false
	label.queue_free()
	_hint_labels.erase(hint_key)
	print("Tutorial: Dismissed hint '%s'" % hint_key)


## Update positions of all active hints to follow the player.
func _update_all_hint_positions() -> void:
	if _player == null or _hint_labels.is_empty():
		return

	var index := 0
	for hint_key in _hint_labels:
		var label: RichTextLabel = _hint_labels[hint_key]
		if is_instance_valid(label):
			_update_hint_position_indexed(label, index)
			index += 1


## Update a single hint label's position.
func _update_hint_position(hint_key: String, label: RichTextLabel) -> void:
	# Find this hint's index among active hints
	var index := 0
	for key in _hint_labels:
		if key == hint_key:
			break
		index += 1
	_update_hint_position_indexed(label, index)


## Position a hint label above the player at the given vertical index (0 = closest to player).
func _update_hint_position_indexed(label: RichTextLabel, index: int) -> void:
	if _player == null:
		return

	var canvas_transform: Transform2D = get_viewport().get_canvas_transform()
	var screen_pos: Vector2 = canvas_transform * _player.global_position

	# Stack hints above player: index 0 is closest, higher indices are further up
	label.custom_minimum_size = Vector2(300, 30)
	label.position = screen_pos + Vector2(-150, -80 - index * HINT_SPACING)


## Show the completion message.
func _show_completion_message() -> void:
	if _ui == null:
		return

	# Create completion label
	var completion_label := Label.new()
	completion_label.name = "CompletionLabel"
	completion_label.text = "УРОВЕНЬ ПРОЙДЕН!"
	completion_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	completion_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	completion_label.add_theme_font_size_override("font_size", 48)
	completion_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3, 1.0))

	# Center the label
	completion_label.set_anchors_preset(Control.PRESET_CENTER)
	completion_label.offset_left = -250
	completion_label.offset_right = 250
	completion_label.offset_top = -75
	completion_label.offset_bottom = -25

	_ui.add_child(completion_label)

	# Create restart hint label
	var restart_label := Label.new()
	restart_label.name = "RestartHintLabel"
	restart_label.text = "Нажми [Q] для быстрого перезапуска"
	restart_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	restart_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	restart_label.add_theme_font_size_override("font_size", 24)
	restart_label.add_theme_color_override("font_color", Color(0.8, 0.9, 0.8, 1.0))

	# Position below completion message
	restart_label.set_anchors_preset(Control.PRESET_CENTER)
	restart_label.offset_left = -250
	restart_label.offset_right = 250
	restart_label.offset_top = 25
	restart_label.offset_bottom = 75

	_ui.add_child(restart_label)

	print("Tutorial completed!")
