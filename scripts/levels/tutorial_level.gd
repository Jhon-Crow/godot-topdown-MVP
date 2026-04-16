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
## 4. Shows completion message with Q hold-to-restart hint
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
## Bug fixes (5th review round, Issue #945):
## Fix R5-1: Grenade hint highlighted step switches as player progresses (G held/released).
## Fix R5-2: Shotgun full-reload hint protected from pump-hint overwrite after 2nd shot.
## Fix R5-3: M16 fire-mode [B] hint shown AFTER grenade training (as the final step).
## Fix R5-4: AKGL starts at RELOAD step (no fire mode switching); _has_assault_rifle not set for AKGL.
## Fix R5-4b: Revolver ReloadStateChanged connected for step-by-step hint update.
## Fix R5-4c: Revolver AmmoChanged double-connection removed from _setup_ammo_tracking.
##
## Bug fixes (Issue #991):
## Fix #991-1: AK GL hint no longer overlaps grenade hint — GL hint appears on reload, grenade
##   hint appears only AFTER the GL fires (sequential, not simultaneous).
## Fix #991-2: AK GL hint is now dismissed when the launcher fires (GrenadeFired signal connected).
##
## Bug fix (Issue #998):
## Fix #998: Scope RMB hint is shown from the very start when player has sniper rifle (not only
##   after the reload step). Scope hint is dismissed as soon as player activates scope; if scope
##   was used before completing reload, SCOPE_TRAINING step is skipped automatically.
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

## Grenade hint step tracking (Issue #1818 / PR review feedback):
## 0 = [удерживать G+ПКМ]
## 1 = [дёрнуть мышкой вправо]
## 2 = [отпустить ПКМ]
## 3 = [зажать ПКМ]
## 4 = [отпустить G]
## 5 = [прицелиться и отпустить ПКМ]
var _grenade_hint_step: int = 0

## Whether G was held during the last frame (for grenade hint step tracking).
var _grenade_g_was_held: bool = false
var _grenade_drag_completed: bool = false
var _grenade_rmb_held_after_release: bool = false
var _grenade_rmb_was_pressed: bool = false
var _grenade_hint_drag_start: Vector2 = Vector2.ZERO

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

## Whether the shotgun full-reload hint is currently active (Bug fix round 5).
## Used to prevent ActionStateChanged from replacing the full-reload hint with pump hint.
var _shotgun_full_reload_active: bool = false

## Whether the M16 fire-mode [B] hint should appear after grenade training (Bug fix round 5).
## Set to true after reload completes for M16; hint is shown after grenade step.
var _m16_needs_fire_mode_hint: bool = false

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

## Issue #944: Animation durations for tutorial hint transitions.
## Fade-in duration for new hints appearing (seconds).
const HINT_FADE_IN_DURATION := 0.3
## Strikethrough display duration before fade-out (seconds).
const HINT_STRIKETHROUGH_DURATION := 0.4
## Fade-out duration after strikethrough (seconds).
const HINT_FADE_OUT_DURATION := 0.3

## Issue #944: Track hints that are currently animating (strikethrough + fade-out).
## These hints should not be updated or re-dismissed while animating.
var _animating_hints: Dictionary = {}

## Issue #944: Track Line2D strikethrough nodes for each hint (hint_key -> Array[Line2D]).
## Each hint has one Line2D per text line, so lines animate independently without connectors.
var _hint_strike_lines: Dictionary = {}

## Issue #944: Track current strikethrough progress for each hint (hint_key -> float 0.0-1.0).
## Progress increases as each step completes; used to animate Line2D extension.
var _hint_strike_progress: Dictionary = {}

## Issue #944 Session 4: Track line count for each hint (hint_key -> int).
## Multi-line hints need multiple Line2D segments, one per line.
var _hint_line_counts: Dictionary = {}

## Issue #1080: Track per-line text widths for each hint (hint_key -> Array[float]).
## Each entry is the rendered pixel width of the corresponding text line,
## so strikethrough lines match the actual text length instead of the label width.
var _hint_line_widths: Dictionary = {}

## Number of shots fired by the player (Issue #945: reload hint appears after 2 shots).
var _shots_fired: int = 0

## Whether the reload hint has already been revealed (Issue #945).
var _reload_hint_revealed: bool = false

## Whether the bolt-cycle hint has already been revealed (sniper/shotgun after 1st shot).
var _bolt_cycle_hint_revealed: bool = false

## Revolver tutorial state snapshot used to distinguish "inserted" vs "scrolled".
## `CanInsertCartridge` alone is ambiguous because it becomes true both before the first insert
## and after scrolling to another empty chamber.
var _revolver_last_inserted_count: int = 0
var _revolver_last_inserted_chamber_index: int = -1
var _revolver_minimum_inserts_required: int = 2
var _revolver_scroll_completed_since_last_insert: bool = false

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

	# Issue #1534: bake navmesh so obstacles are carved out (same pattern as all other levels).
	_setup_navigation()

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

	# Restrict camera so the border walls are never visible (Issue #1682).
	_configure_camera()

	# Register player with GameManager
	if GameManager:
		GameManager.set_player(_player)


## Clamps the camera so the outer border walls are never visible (Issue #1682).
##
## TestTier map: 4128x3088 px playfield framed by 32 px walls.
##   WallTop    (2064,   48), h=16  → bottom edge y=64   → limit_top    = 64
##   WallBottom (2064, 3040), h=16  → top edge   y=3024  → limit_bottom = 3024
##   WallLeft   (  48, 1544), w=16  → right edge x=64    → limit_left   = 64
##   WallRight  (4080, 1544), w=16  → left edge  x=4064  → limit_right  = 4064
func _configure_camera() -> void:
	if _player == null:
		return
	var camera: Camera2D = _player.get_node_or_null("Camera2D")
	if camera == null:
		push_warning("[TutorialLevel] Camera2D not found on player — cannot set camera limits")
		return
	const LIMIT_TOP: int    =   64   # WallTop bottom edge
	const LIMIT_BOTTOM: int = 3024   # WallBottom top edge
	const LIMIT_LEFT: int   =   64   # WallLeft right edge
	const LIMIT_RIGHT: int  = 4064   # WallRight left edge
	camera.limit_top    = LIMIT_TOP
	camera.limit_bottom = LIMIT_BOTTOM
	camera.limit_left   = LIMIT_LEFT
	camera.limit_right  = LIMIT_RIGHT
	print("[TutorialLevel] Camera2D limits set — top=%d bottom=%d left=%d right=%d — Issue #1682" % [
		LIMIT_TOP, LIMIT_BOTTOM, LIMIT_LEFT, LIMIT_RIGHT
	])


## Bake the navigation mesh so StaticBody2D obstacles on collision layer 4 are carved
## out of the walkable area (Issue #1534). Must await a physics frame so CollisionShape2D
## nodes are registered before parsing (Issue #1289).
func _setup_navigation() -> void:
	var nav_region: NavigationRegion2D = get_node_or_null("NavigationRegion2D")
	if nav_region == null:
		push_warning("NavigationRegion2D not found")
		return
	var nav_poly: NavigationPolygon = nav_region.navigation_polygon
	if nav_poly == null:
		push_warning("NavigationPolygon not found")
		return
	# Wait for physics frame so CollisionShape2D nodes are registered with PhysicsServer2D
	# before parsing source geometry for navmesh carving (Issue #1289).
	await get_tree().physics_frame
	# Explicit parse+bake so all wall/obstacle StaticBody2D nodes are found.
	print("Baking navigation mesh...")
	var source_geometry: NavigationMeshSourceGeometryData2D = NavigationMeshSourceGeometryData2D.new()
	NavigationServer2D.parse_source_geometry_data(nav_poly, source_geometry, self)
	NavigationServer2D.bake_from_source_geometry_data(nav_poly, source_geometry)
	# Push updated polygon back into the NavigationServer's live map (Issue #1289).
	nav_region.navigation_polygon = nav_poly
	nav_region.emit_signal("bake_finished")
	print("Navigation mesh baked successfully")


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
## Only the M16 (AssaultRifle) starts with fire mode switching.
## AKGL does NOT have fire mode switching, so it starts with reload.
## Bug fix round 5: AKGL starts with RELOAD (not SWITCH_FIRE_MODE).
func _set_initial_step() -> void:
	# Check which weapon the player has
	var weapon = _player.get_node_or_null("AssaultRifle")

	if weapon != null:
		# M16 has fire mode switching
		_current_step = TutorialStep.SWITCH_FIRE_MODE
		print("[TutorialLevel] Starting with SWITCH_FIRE_MODE step (M16 detected)")
	else:
		# AKGL, revolver, shotgun, sniper, etc. start with reload
		_current_step = TutorialStep.RELOAD
		print("[TutorialLevel] Starting with RELOAD step (non-M16 weapon)")


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

	# Bug fix round 5: update grenade hint step based on key state
	_update_grenade_hint_step()


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

	# Bug fix round 4: connect ActionStateChanged and ReloadStateChanged for shotgun
	# to track bolt-cycle and reload progress for step-by-step hint updating.
	if weapon_node.has_signal("ActionStateChanged"):
		weapon_node.ActionStateChanged.connect(_on_shotgun_action_state_changed)
		print("Tutorial: Connected to ActionStateChanged signal on %s" % weapon_node.name)
	if weapon_node.has_signal("ReloadStateChanged"):
		weapon_node.ReloadStateChanged.connect(_on_shotgun_reload_state_changed)
		print("Tutorial: Connected to ReloadStateChanged signal on %s" % weapon_node.name)


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
		# Bug fix round 5: AKGL does NOT have fire mode switching — do NOT set _has_assault_rifle.
		# _assault_rifle is kept for _ak_gl_has_round_loaded() grenade launcher check.
		_has_ak_gl = true
		print("Tutorial: Player has AKGL - underbarrel GL tutorial enabled (no fire mode switching)")

		# Connect shot counter for reload hint reveal (Issue #945)
		_connect_weapon_fired_signal(akgl)

		# Connect to reload signals from player (C# Player)
		if _player.has_signal("ReloadCompleted"):
			_player.ReloadCompleted.connect(_on_player_reload_completed)
		elif _player.has_signal("reload_completed"):
			_player.reload_completed.connect(_on_player_reload_completed)

		# Issue #991 fix: connect GrenadeFired to dismiss GL hint and show grenade hint sequentially.
		# Without this connection the GL hint never disappears after the player fires the launcher,
		# and both GL hint + grenade hint would appear simultaneously (causing overlap).
		if akgl.has_signal("GrenadeFired"):
			akgl.GrenadeFired.connect(_on_grenade_launcher_fired)
			print("Tutorial: Connected to GrenadeFired signal (AKGL)")

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

		# Bug fix round 5: connect ReloadStateChanged to update revolver reload hint step-by-step.
		# RevolverReloadState: 0=NotReloading, 1=CylinderOpen, 2=Loading, 3=ClosingCylinder.
		# This provides the step=2 update (cartridges inserted → highlight [R закрыть]).
		if revolver.has_signal("ReloadStateChanged"):
			revolver.ReloadStateChanged.connect(_on_revolver_reload_state_changed)
			print("Tutorial: Connected to ReloadStateChanged signal (Revolver)")
		if revolver.has_signal("CylinderRotated"):
			revolver.CylinderRotated.connect(_on_revolver_cylinder_rotated)
			print("Tutorial: Connected to CylinderRotated signal (Revolver)")

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
		# C# Player with Revolver - AmmoChanged already connected in _connect_player_signals.
		# Connect to CartridgeInserted for real-time UI update during cylinder reload (unique to ammo tracking).
		# Bug fix round 5: do NOT connect AmmoChanged again here to avoid double-update.
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

	_ammo_label.text = tr("TUTORIAL_AMMO_LABEL") % [current, maximum]

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

	_ammo_label.text = tr("TUTORIAL_AMMO_LABEL") % [current_mag, reserve]

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
## Bug fix round 4: updates using full reload hint builder that also tracks reload state.
## Issue #1025 fix: skip hint update when ShellCountChanged fires due to a shot (reload_state=0)
##   while the full-reload hint is active. Without this guard, firing extra shots after the
##   2nd shot overwrites the full-reload hint with the state=0 (open-bolt highlighted) format,
##   causing the one-step lag: bolt-open no longer advances the highlight until a shell loads.
func _on_shell_count_changed(shell_count: int, _capacity: int) -> void:
	# Get the reserve ammo from the weapon for display
	var reserve_ammo: int = 0
	var reload_state: int = 0  # NotReloading (default for hint update)
	if _player:
		var shotgun = _player.get_node_or_null("Shotgun")
		if shotgun != null and shotgun.get("ReserveAmmo") != null:
			reserve_ammo = shotgun.ReserveAmmo
		if shotgun != null and shotgun.get("ReloadState") != null:
			reload_state = int(shotgun.ReloadState)
	_update_ammo_label_magazine(shell_count, reserve_ammo)
	# Bug fix #7 + round 4: update bolt-cycle hint with new shell count and current reload state.
	# Issue #1025: skip update when reload_state=0 (shot fired, not reloading) and the full-reload
	# hint is active — otherwise the hint resets to state=0 (open-bolt highlighted) on every shot.
	if _hint_labels.has(HINT_BOLT_CYCLE) and (reload_state != 0 or not _shotgun_full_reload_active):
		var label: RichTextLabel = _hint_labels[HINT_BOLT_CYCLE]
		if is_instance_valid(label):
			label.text = _build_shotgun_full_reload_hint_bbcode(reload_state)


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
		if revolver != null:
			_revolver_last_inserted_count = loaded
			_revolver_scroll_completed_since_last_insert = false
			if revolver.get("CurrentChamberIndex") != null:
				_revolver_last_inserted_chamber_index = int(revolver.get("CurrentChamberIndex"))


func _on_revolver_cylinder_rotated(chamber_index: int) -> void:
	if not _hint_labels.has(HINT_RELOAD):
		return
	if not _has_revolver:
		return

	var revolver := _player.get_node_or_null("Revolver")
	if revolver == null:
		return

	var cartridges_loaded: int = 0
	var current_ammo: int = 0
	if revolver.get("CartridgesLoadedThisReload") != null:
		cartridges_loaded = int(revolver.get("CartridgesLoadedThisReload"))
	if revolver.get("CurrentAmmo") != null:
		current_ammo = int(revolver.get("CurrentAmmo"))

	if cartridges_loaded <= 0:
		return

	_revolver_scroll_completed_since_last_insert = true
	var hint_step := 1
	if cartridges_loaded >= _revolver_minimum_inserts_required or current_ammo >= 5:
		hint_step = 3

	var label: RichTextLabel = _hint_labels[HINT_RELOAD]
	if is_instance_valid(label):
		label.text = _build_revolver_reload_hint_bbcode(hint_step)
	print("Tutorial: Revolver cylinder rotated to chamber %d → hint step %d updated" % [chamber_index, hint_step])


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
	# Track shot in GameManager for unlock conditions (Issue #1346).
	if GameManager:
		GameManager.register_shot()

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
## Bug fix #5: Revolver has a special multi-step hint; shotgun uses ActionStateChanged.
## Bug fix round 4: revolver hint now updates step-by-step as reload progresses.
func _on_reload_sequence_progress(step: int, total: int) -> void:
	# Shotgun uses ActionStateChanged for step-by-step highlighting (not ReloadSequenceProgress)
	if _has_shotgun:
		return

	if not _hint_labels.has(HINT_RELOAD):
		return

	# Bug fix round 4: revolver step highlighting update
	if _has_revolver:
		var new_text := _build_revolver_reload_hint_bbcode(step)
		var label: RichTextLabel = _hint_labels[HINT_RELOAD]
		if is_instance_valid(label):
			label.text = new_text
		print("Tutorial: Revolver reload sequence step %d/%d - hint updated" % [step, total])
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
## Bug fix #5: Revolver and shotgun use separate hint builders.
## Issue #944: Strikethrough is now animated via Line2D, not BBCode [s] tags.
func _build_reload_hint_bbcode(step: int, total: int) -> String:
	# Guard: shotgun uses static/ActionState-based hints
	if _has_shotgun:
		return ""

	var reload_word: String = tr("HINT_RELOAD_WORD")
	if _has_makarov_pm or (_has_sniper_rifle == false and total <= 2):
		# Makarov PM / 2-step reload: R -> R
		# step=0 → next is R (first); step=1 → next is R (second); step=2 → done
		match step:
			0:
				return "[color=#ff4444][R][/color] [color=#888888][R][/color] " + reload_word
			1:
				# Step 1 completed: extend strikethrough to 50%
				_extend_hint_strikethrough(HINT_RELOAD, 0.25)
				return "[color=#888888][R][/color] [color=#ff4444][R][/color] " + reload_word
			_:
				# All steps done: extend strikethrough to cover both [R] keys (~50%)
				_extend_hint_strikethrough(HINT_RELOAD, 0.5)
				return "[color=#888888][R] [R][/color] " + reload_word
	else:
		# Standard 3-step reload: R -> F -> R
		# step=0 → next is R; step=1 → next is F; step=2 → next is R (final); step=3 → done
		match step:
			0:
				return "[color=#ff4444][R][/color] [color=#888888][F] [R][/color] " + reload_word
			1:
				# Step 1 completed: extend strikethrough to ~17%
				_extend_hint_strikethrough(HINT_RELOAD, 0.17)
				return "[color=#888888][R][/color] [color=#ff4444][F][/color] [color=#888888][R][/color] " + reload_word
			2:
				# Step 2 completed: extend strikethrough to ~33%
				_extend_hint_strikethrough(HINT_RELOAD, 0.33)
				return "[color=#888888][R] [F][/color] [color=#ff4444][R][/color] " + reload_word
			_:
				# All steps done: extend strikethrough to ~50%
				_extend_hint_strikethrough(HINT_RELOAD, 0.5)
				return "[color=#888888][R] [F] [R][/color] " + reload_word


## Reveal the bolt-cycle hint after the 1st shot (sniper/shotgun only).
## Bolt-cycle hint is shown separately from the reload hint so it appears earlier.
## Bug fix round 4: Shotgun now shows a simple "pump action" hint (open/close bolt)
## after the 1st shot, not the full reload sequence.
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
		# Bug fix round 4: show pump-action hint (open/close bolt between shots), NOT full reload.
		# Full reload hint appears later via _add_reload_hints() after 2nd shot.
		if not _hint_labels.has(HINT_BOLT_CYCLE):
			_add_hint(HINT_BOLT_CYCLE,
				"[color=#ff4444][ПКМ↑][/color] [color=#888888][ПКМ↓][/color] " + tr("HINT_BOLT_ACTION_WORD"),
				canvas_layer)


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
## Bug fix round 5: also handles the final M16 fire-mode switch hint (after grenade step).
func _on_fire_mode_changed(_new_mode: int) -> void:
	# Bug fix round 5: if M16 fire-mode hint is the final training step, dismiss and complete.
	if _m16_needs_fire_mode_hint and _hint_labels.has(HINT_FIRE_MODE):
		_m16_needs_fire_mode_hint = false
		_dismiss_hint(HINT_FIRE_MODE)
		_advance_to_step(TutorialStep.COMPLETED)
		return

	if _current_step != TutorialStep.SWITCH_FIRE_MODE:
		return

	if not _has_switched_fire_mode:
		_has_switched_fire_mode = true
		print("Tutorial: Player switched fire mode")
		# Remove fire mode hint and advance; reload + grenade hints will be shown together
		_dismiss_hint(HINT_FIRE_MODE)
		_advance_to_step(TutorialStep.RELOAD)


## Called when sniper rifle bolt step changes.
## Bug fix #3: dynamically updates bolt-cycle hint text to highlight the NEXT step in red.
## Bug fix round 4: bolt-cycle completion now only dismisses the HINT_BOLT_CYCLE hint —
## it does NOT advance the tutorial step. The magazine reload (R→F→R) must complete first.
## After the 1st bolt-cycle the hint is dismissed; after 2nd shot the reload hint appears.
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
		print("Tutorial: Sniper bolt cycling completed — dismissing bolt-cycle hint")
		# Dismiss bolt-cycle hint only; keep reload hint if visible.
		# Bug fix round 4: do NOT set _has_reloaded or advance to SCOPE_TRAINING here.
		# The magazine reload (R→F→R) handles tutorial advancement via _on_player_reload_completed.
		_dismiss_hint(HINT_BOLT_CYCLE)
		# Reset for next shot (player may need to cycle bolt again after 2nd shot)
		_sniper_bolt_cycled = false


## Build BBCode for sniper bolt-cycle hint showing 4-step sequence with NEXT step in red.
## step = last COMPLETED step: 0=nothing done, 1=bolt up done, 2=bolt back done, etc.
## Issue #944: Strikethrough is now animated via Line2D, not BBCode [s] tags.
func _build_sniper_bolt_hint_bbcode(step: int) -> String:
	# 4 steps: ← (bolt up/open), ↓ (bolt back), ↑ (bolt forward), → (bolt down/close)
	const STEPS := ["←", "↓", "↑", "→"]
	var parts: PackedStringArray = []
	for i in range(STEPS.size()):
		if i < step:
			# Completed step: grey (strikethrough animated via Line2D)
			parts.append("[color=#888888][%s][/color]" % STEPS[i])
		elif i == step:
			# Current step: highlighted in red
			parts.append("[color=#ff4444][%s][/color]" % STEPS[i])
		else:
			# Future step: grey
			parts.append("[color=#888888][%s][/color]" % STEPS[i])

	# Extend strikethrough progressively based on completed steps
	# Each step is ~12.5% of the total hint width (4 steps + text = ~50% for keys)
	if step > 0:
		var progress := float(step) * 0.125  # 12.5% per step
		_extend_hint_strikethrough(HINT_BOLT_CYCLE, progress)

	return " ".join(parts) + " " + tr("HINT_BOLT_ACTION_WORD")


## Build BBCode for shotgun reload hint with dynamic shell count (Bug fix #7).
## Shows: [ПКМ↑ открыть] [СКМ+ПКМ↓ xN] [ПКМ↓ закрыть] where N = shells to load.
func _build_shotgun_reload_hint_bbcode() -> String:
	var shells_needed: int = _get_shotgun_shells_to_load()
	var k_open: String = tr("HINT_KEY_RMB_UP_OPEN")
	var k_load: String = tr("HINT_KEY_MMB_RMB_DOWN") % shells_needed
	var k_close: String = tr("HINT_KEY_RMB_DOWN_CLOSE")
	return "[color=#ff4444][%s][/color] [color=#888888][%s] [%s][/color]" % [k_open, k_load, k_close]


## Return the number of shells the shotgun still needs to fill up to capacity (Bug fix #7).
## Issue #983 Fix 2: use ShellsInTube and TubeMagazineCapacity (the actual shotgun properties)
##   instead of CurrentAmmo/MaxAmmo which are always null/0 for the shotgun.
func _get_shotgun_shells_to_load() -> int:
	if _shotgun == null:
		return 8  # Default fallback
	var shells_in_tube = _shotgun.get("ShellsInTube")
	var tube_capacity = _shotgun.get("TubeMagazineCapacity")
	if shells_in_tube == null or tube_capacity == null:
		return 8
	return int(tube_capacity) - int(shells_in_tube)


## Build BBCode for the revolver reload hint with step-based highlighting (Bug fix round 4).
## step=1: cylinder opened → highlight insert-cartridge action
## step=2: cartridge inserted → highlight scroll action
## step=3: cylinder rotated after insert → highlight close action
## step=4: cylinder closed → all grey (done)
## Issue #944: Strikethrough is now animated via Line2D, not BBCode [s] tags.
func _build_revolver_reload_hint_bbcode(step: int) -> String:
	var k_open: String = tr("HINT_KEY_R_OPEN")
	var k_bullet: String = tr("HINT_KEY_RMB_UP_BULLET")
	var k_scroll: String = tr("HINT_KEY_SCROLL")
	var k_close: String = tr("HINT_KEY_R_CLOSE")
	match step:
		0:
			# Nothing done yet: highlight open-cylinder (R)
			return "[color=#ff4444][%s][/color] [color=#888888][%s] [%s] [%s][/color]" % [k_open, k_bullet, k_scroll, k_close]
		1:
			# Cylinder opened: next is insert cartridges (open is completed)
			_extend_hint_strikethrough(HINT_RELOAD, 0.15)  # ~15% for first segment
			return "[color=#888888][%s][/color] [color=#ff4444][%s][/color] [color=#888888][%s] [%s][/color]" % [k_open, k_bullet, k_scroll, k_close]
		2:
			# Cartridge inserted: next is scroll/rotate cylinder
			_extend_hint_strikethrough(HINT_RELOAD, 0.35)  # open + insert completed
			return "[color=#888888][%s] [%s][/color] [color=#ff4444][%s][/color] [color=#888888][%s][/color]" % [k_open, k_bullet, k_scroll, k_close]
		3:
			# Cylinder rotated after insertion: next is close cylinder
			_extend_hint_strikethrough(HINT_RELOAD, 0.55)  # open + insert + scroll completed
			return "[color=#888888][%s] [%s] [%s][/color] [color=#ff4444][%s][/color]" % [k_open, k_bullet, k_scroll, k_close]
		_:
			# All steps done
			_extend_hint_strikethrough(HINT_RELOAD, 0.75)  # ~75% for all key segments
			return "[color=#888888][%s] [%s] [%s] [%s][/color]" % [k_open, k_bullet, k_scroll, k_close]


## Called when the shotgun's action state changes (pump-action between shots).
## Bug fix round 4: updates the HINT_BOLT_CYCLE hint to show which pump step is needed.
## Bug fix round 5: skip pump hint updates when full-reload hint is active (_shotgun_full_reload_active).
## ShotgunActionState: 0=Ready, 1=NeedsPumpUp, 2=NeedsPumpDown
func _on_shotgun_action_state_changed(new_state: int) -> void:
	if _current_step != TutorialStep.RELOAD:
		return

	# Bug fix round 5: once the full reload hint is shown (after 2nd shot), do not
	# replace it with the pump hint when the shotgun enters NeedsPumpUp state.
	if _shotgun_full_reload_active:
		return

	# state 1 = NeedsPumpUp (drag up to eject shell)
	# state 2 = NeedsPumpDown (drag down to chamber)
	# state 0 = Ready (bolt cycled, ready to fire)
	if new_state == 0:
		# Bolt cycle complete — dismiss pump hint
		if _hint_labels.has(HINT_BOLT_CYCLE):
			_dismiss_hint(HINT_BOLT_CYCLE)
	elif _hint_labels.has(HINT_BOLT_CYCLE):
		var label: RichTextLabel = _hint_labels[HINT_BOLT_CYCLE]
		if is_instance_valid(label):
			label.text = _build_shotgun_pump_hint_bbcode(new_state)


## Build BBCode for the shotgun between-shots pump hint.
## state=1 (NeedsPumpUp): highlight drag-up; state=2 (NeedsPumpDown): highlight drag-down.
## Issue #944: Strikethrough is now animated via Line2D, not BBCode [s] tags.
func _build_shotgun_pump_hint_bbcode(state: int) -> String:
	var bolt_word: String = tr("HINT_BOLT_ACTION_WORD")
	match state:
		1:  # NeedsPumpUp (nothing completed yet)
			return "[color=#ff4444][ПКМ↑][/color] [color=#888888][ПКМ↓][/color] " + bolt_word
		2:  # NeedsPumpDown (pump-up completed)
			_extend_hint_strikethrough(HINT_BOLT_CYCLE, 0.2)  # ~20% for first key
			return "[color=#888888][ПКМ↑][/color] [color=#ff4444][ПКМ↓][/color] " + bolt_word
		_:
			# Both completed
			_extend_hint_strikethrough(HINT_BOLT_CYCLE, 0.4)  # ~40% for both keys
			return "[color=#888888][ПКМ↑] [ПКМ↓][/color] " + bolt_word


## Called when the shotgun's reload state changes (full shell-by-shell reload).
## Bug fix round 4: updates the HINT_BOLT_CYCLE hint to highlight the current reload step.
## Issue #983 Fix 1: when state=0 (NotReloading), the reload is complete — dismiss hint
##   and advance tutorial instead of resetting the hint text to the first step.
## ShotgunReloadState: 0=NotReloading, 1=WaitingToOpen, 2=Loading, 3=WaitingToClose
func _on_shotgun_reload_state_changed(new_state: int) -> void:
	if _current_step != TutorialStep.RELOAD:
		return

	if not _hint_labels.has(HINT_BOLT_CYCLE):
		return

	# state=0 means reload is fully complete (bolt closed) — treat as reload done.
	if new_state == 0:
		_dismiss_hint(HINT_BOLT_CYCLE)
		_shotgun_full_reload_active = false
		if not _has_reloaded:
			_has_reloaded = true
			print("Tutorial: Shotgun reload completed via ReloadStateChanged(0)")
			if _has_thrown_grenade:
				_advance_to_step(TutorialStep.COMPLETED)
			else:
				_advance_to_step(TutorialStep.THROW_GRENADE)
		return

	var label: RichTextLabel = _hint_labels[HINT_BOLT_CYCLE]
	if is_instance_valid(label):
		label.text = _build_shotgun_full_reload_hint_bbcode(new_state)


## Build BBCode for the shotgun full-reload hint with step-based highlighting (Bug fix round 4).
## state=0: NotReloading (initial, no step highlighted)
## state=1: WaitingToOpen → highlight open-bolt [ПКМ↑]
## state=2: Loading → highlight load-shells [СКМ+ПКМ↓]
## state=3: WaitingToClose → highlight close-bolt [ПКМ↓]
## Issue #944: Strikethrough is now animated via Line2D, not BBCode [s] tags.
func _build_shotgun_full_reload_hint_bbcode(state: int) -> String:
	var shells_needed: int = _get_shotgun_shells_to_load()
	var k_open: String = tr("HINT_KEY_RMB_UP_OPEN")
	var k_load: String = tr("HINT_KEY_MMB_RMB_DOWN") % shells_needed
	var k_close: String = tr("HINT_KEY_RMB_DOWN_CLOSE")
	match state:
		0, 1:  # Not reloading or waiting to open
			return "[color=#ff4444][%s][/color] [color=#888888][%s] [%s][/color]" % [k_open, k_load, k_close]
		2:  # Loading shells (open is completed)
			_extend_hint_strikethrough(HINT_BOLT_CYCLE, 0.25)  # ~25% for first segment
			return "[color=#888888][%s][/color] [color=#ff4444][%s][/color] [color=#888888][%s][/color]" % [k_open, k_load, k_close]
		3:  # Waiting to close (open and loading completed)
			_extend_hint_strikethrough(HINT_BOLT_CYCLE, 0.55)  # ~55% for first two segments
			return "[color=#888888][%s] [%s][/color] [color=#ff4444][%s][/color]" % [k_open, k_load, k_close]
		_:
			# All steps completed
			_extend_hint_strikethrough(HINT_BOLT_CYCLE, 0.8)  # ~80% for all key segments
			return "[color=#888888][%s] [%s] [%s][/color]" % [k_open, k_load, k_close]


## Called when scope state changes (activated/deactivated).
## Completes the scope training step when scope is used.
## Issue #998: Also dismisses the scope hint if the player uses the scope early (during RELOAD).
func _on_scope_state_changed(is_active: bool) -> void:
	if not is_active or _scope_used:
		return

	_scope_used = true
	print("Tutorial: Scope used - scope training complete")
	# Dismiss scope hint
	_dismiss_hint(HINT_SCOPE)
	# Only advance to THROW_GRENADE if we are currently in the SCOPE_TRAINING step.
	# If scope is used early (during RELOAD), the step advancement happens later via _on_player_reload_completed().
	if _current_step == TutorialStep.SCOPE_TRAINING:
		_advance_to_step(TutorialStep.THROW_GRENADE)


## Called when player completes reload.
## Bug fix round 4: sniper magazine reload (R→F→R) now correctly advances to SCOPE_TRAINING.
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
			_shotgun_full_reload_active = false
		var canvas_layer := get_node_or_null("CanvasLayer")
		# Bug fix round 4: sniper uses scope training after magazine reload.
		# Issue #998: If scope was already used early (hint shown from start), skip SCOPE_TRAINING.
		if _has_sniper_rifle:
			if _scope_used:
				# Player already used scope early — skip SCOPE_TRAINING, go to next step.
				print("Tutorial: Scope already used — skipping SCOPE_TRAINING step")
			else:
				_advance_to_step(TutorialStep.SCOPE_TRAINING)
				return
		# Bug fix round 5: M16 [B] hint shown AFTER grenade training (not right after reload).
		# Set a flag so the hint is added when the grenade step completes.
		if _has_assault_rifle and not _has_ak_gl:
			_m16_needs_fire_mode_hint = true
		# Issue #991 fix: AK GL shows underbarrel grenade launcher hint after reload (if round
		# loaded), then waits for the GrenadeFired signal before advancing to THROW_GRENADE.
		# This prevents the GL hint and grenade hint from appearing simultaneously (overlap bug).
		if _has_ak_gl and canvas_layer and _ak_gl_has_round_loaded():
			_add_hint(HINT_GRENADE_LAUNCHER,
				"[color=#ff4444][ПКМ][/color] " + tr("HINT_LAUNCHER_FIRE"), canvas_layer)
			# Do NOT advance to THROW_GRENADE yet — wait for GL to fire (_on_grenade_launcher_fired).
			return
		# If grenade was already thrown, go to COMPLETED; otherwise wait for grenade
		if _has_thrown_grenade:
			_advance_to_step(TutorialStep.COMPLETED)
		else:
			_advance_to_step(TutorialStep.THROW_GRENADE)


## Called when the AK GL underbarrel grenade launcher fires (Issue #991).
## Dismisses the GL hint (which was lingering) and then advances to THROW_GRENADE step
## so that the grenade hint appears AFTER the GL hint disappears (no overlap).
func _on_grenade_launcher_fired() -> void:
	# Dismiss GL hint now that the launcher has been fired
	_dismiss_hint(HINT_GRENADE_LAUNCHER)
	print("Tutorial: Grenade launcher fired — GL hint dismissed")
	# Now advance to grenade throw step (shows grenade hint after GL hint is gone)
	if _has_thrown_grenade:
		_advance_to_step(TutorialStep.COMPLETED)
	else:
		_advance_to_step(TutorialStep.THROW_GRENADE)


## Called when the revolver hammer is cocked (RMB press or LMB fire).
## Dismisses the hammer cock hint the first time the hammer is cocked (Issue #808).
func _on_revolver_hammer_cocked() -> void:
	_dismiss_hint(HINT_HAMMER_COCK)


## Called when the revolver reload state changes (Bug fix round 5).
## RevolverReloadState: 0=NotReloading, 1=CylinderOpen, 2=Loading, 3=ClosingCylinder.
## Maps actual reload state to the next tutorial action:
##   state=1 (CylinderOpen): highlight [ПКМ↑ патрон] (step=1)
##   state=2 (Loading) with another insert possible: highlight [скролл] (step=2)
##   state=2 (Loading) but insertion blocked or chamber occupied: highlight [R закрыть] (step=3)
##   state=0/3 (not reloading/closing): all grey (done)
func _on_revolver_reload_state_changed(new_state: int) -> void:
	if not _hint_labels.has(HINT_RELOAD):
		return
	if not _has_revolver:
		return

	var hint_step: int = 0
	match new_state:
		1:
			hint_step = 1
		2:
			hint_step = _get_revolver_reload_hint_step_for_loading_state()
		_:
			hint_step = 4

	var new_text := _build_revolver_reload_hint_bbcode(hint_step)
	var label: RichTextLabel = _hint_labels[HINT_RELOAD]
	if is_instance_valid(label):
		label.text = new_text
	print("Tutorial: Revolver reload state %d → hint step %d updated" % [new_state, hint_step])


func _get_revolver_reload_hint_step_for_loading_state() -> int:
	if _player == null:
		return 2

	var revolver := _player.get_node_or_null("Revolver")
	if revolver == null:
		return 2

	var cartridges_loaded: int = 0
	var current_ammo: int = 0
	if revolver.get("CartridgesLoadedThisReload") != null:
		cartridges_loaded = int(revolver.get("CartridgesLoadedThisReload"))
	if revolver.get("CurrentAmmo") != null:
		current_ammo = int(revolver.get("CurrentAmmo"))

	if cartridges_loaded <= 0:
		return 2

	# After the player inserts enough cartridges during this tutorial prompt, or fully tops off
	# the cylinder to 5/5, only the final close step should remain.
	if cartridges_loaded >= _revolver_minimum_inserts_required or current_ammo >= 5:
		return 3

	var current_chamber_index: int = -1
	if revolver.get("CurrentChamberIndex") != null:
		current_chamber_index = int(revolver.get("CurrentChamberIndex"))

	# Scroll completion must come from an actual cylinder rotation event, not just a Loading-state
	# snapshot. Once scroll happened, loop back to another insert until the tutorial quota is met.
	if _revolver_scroll_completed_since_last_insert \
	and cartridges_loaded == _revolver_last_inserted_count \
	and _revolver_last_inserted_chamber_index >= 0 \
	and current_chamber_index >= 0 \
	and current_chamber_index != _revolver_last_inserted_chamber_index:
		return 1

	return 2


## Build BBCode for the grenade throw hint with step-based highlighting (Issue #1818).
func _build_grenade_hint_bbcode(step: int) -> String:
	var parts := [
		"[удерживать G+ПКМ]",
		"[дёрнуть мышкой вправо] [отпустить ПКМ]",
		"[зажать ПКМ]",
		"[отпустить G]",
		"[прицелиться и отпустить ПКМ]",
	]
	var strikethrough_progress := [0.0, 0.2, 0.34, 0.5, 0.68, 0.86]
	var clamped_step := clampi(step, 0, strikethrough_progress.size() - 1)
	var highlighted_part := mini(clamped_step, parts.size() - 1)
	_extend_hint_strikethrough(HINT_GRENADE, strikethrough_progress[clamped_step])
	var styled: PackedStringArray = []
	for i in range(parts.size()):
		if i < highlighted_part:
			styled.append("[color=#888888]%s[/color]" % parts[i])
		elif i == highlighted_part:
			styled.append("[color=#ff4444]%s[/color]" % parts[i])
		else:
			styled.append("[color=#888888]%s[/color]" % parts[i])
	return " ".join(styled)


func _reset_grenade_hint_tracking() -> void:
	_grenade_g_was_held = false
	_grenade_hint_step = 0
	_grenade_drag_completed = false
	_grenade_rmb_held_after_release = false
	_grenade_rmb_was_pressed = false
	_grenade_hint_drag_start = Vector2.ZERO


## Update the grenade hint step based on current input state (Issue #1818).
## Called every frame to dynamically highlight the next required action.
func _update_grenade_hint_step() -> void:
	if not _hint_labels.has(HINT_GRENADE):
		_reset_grenade_hint_tracking()
		return

	var g_pressed: bool = Input.is_action_pressed("grenade_prepare")
	var rmb_pressed: bool = Input.is_action_pressed("grenade_throw")
	var current_mouse_pos := get_global_mouse_position()
	var rmb_just_pressed := rmb_pressed and not _grenade_rmb_was_pressed
	var rmb_just_released := not rmb_pressed and _grenade_rmb_was_pressed

	if _grenade_hint_step == 0 and not (g_pressed and rmb_pressed):
		if g_pressed or rmb_pressed or _grenade_rmb_was_pressed:
			_reset_grenade_hint_tracking()
	elif _grenade_hint_step == 1 and not g_pressed and not _grenade_drag_completed:
		_reset_grenade_hint_tracking()
	elif _grenade_hint_step == 2 and not g_pressed and not rmb_pressed:
		_reset_grenade_hint_tracking()
	elif _grenade_hint_step == 3 and not g_pressed and not rmb_pressed:
		_reset_grenade_hint_tracking()
	elif _grenade_hint_step == 4 and not rmb_pressed and not _grenade_rmb_held_after_release:
		_reset_grenade_hint_tracking()

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
	elif _grenade_hint_step == 2 and _grenade_drag_completed and rmb_just_released:
		_grenade_hint_step = 3
	elif _grenade_hint_step == 3 and g_pressed and rmb_just_pressed:
		_grenade_rmb_held_after_release = true
		_grenade_hint_step = 4
	elif _grenade_hint_step == 4 and not g_pressed and rmb_pressed and _grenade_rmb_held_after_release:
		_grenade_hint_step = 5
		_grenade_g_was_held = false
	elif _grenade_hint_step == 5 and not rmb_pressed and _grenade_rmb_held_after_release:
		_grenade_hint_step = 4

	# Update the label text to reflect current step
	var label: RichTextLabel = _hint_labels[HINT_GRENADE]
	if is_instance_valid(label):
		var new_text := _build_grenade_hint_bbcode(_grenade_hint_step)
		if label.text != new_text:
			label.text = new_text

	_grenade_rmb_was_pressed = rmb_pressed


## Called when player throws a grenade.
## Grenade can be thrown at any step that shows the grenade hint (RELOAD or THROW_GRENADE).
## Bug fix round 5: M16 fire-mode [B] hint is shown AFTER grenade is thrown (final step).
func _on_player_grenade_thrown() -> void:
	# Allow grenade dismissal from RELOAD step too (thrown before reload completes)
	if _current_step != TutorialStep.THROW_GRENADE and _current_step != TutorialStep.RELOAD:
		return

	if not _has_thrown_grenade:
		_has_thrown_grenade = true
		print("Tutorial: Player threw grenade")
		# Dismiss only the grenade hint (Issue #808)
		# Issue #944: Strikethrough will animate to 100% during dismiss
		_dismiss_hint(HINT_GRENADE)
		# Bug fix round 5: show M16 fire-mode [B] hint after grenade (as the last training hint).
		if _m16_needs_fire_mode_hint:
			var canvas_layer := get_node_or_null("CanvasLayer")
			if canvas_layer:
				_add_hint(HINT_FIRE_MODE,
					"[color=#ff4444][B][/color] " + tr("HINT_FIRE_MODE_SWITCH"), canvas_layer)
			# Don't advance to COMPLETED yet — wait for fire-mode switch to complete.
			return
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
				"[color=#ff4444][B][/color] " + tr("HINT_FIRE_MODE_SWITCH"), canvas_layer)
		TutorialStep.RELOAD:
			# Issue #945: Reload hint is delayed until player fires 2 shots.
			# Do not show reload hints here; _on_weapon_fired() will reveal them.
			# Bug fix #3: Revolver hammer-cock hint is shown from the very start (on weapon pickup).
			if _has_revolver:
				_add_hint(HINT_HAMMER_COCK, "[color=#ff4444][ПКМ][/color] " + tr("HINT_COCK_HAMMER"), canvas_layer)
			# Issue #998: Scope hint is shown from the very start for sniper rifle.
			if _has_sniper_rifle:
				_add_hint(HINT_SCOPE, "[color=#ff4444][ПКМ][/color] " + tr("HINT_SCOPE"), canvas_layer)


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
			_add_hint(HINT_SCOPE, "[color=#ff4444][ПКМ][/color] " + tr("HINT_SCOPE"), canvas_layer)
		TutorialStep.THROW_GRENADE:
			# Bug fix #9: only show grenade hint if the player actually has grenades
			if _player_has_grenades():
				if not _hint_labels.has(HINT_GRENADE):
					_reset_grenade_hint_tracking()
					_add_hint(HINT_GRENADE, _build_grenade_hint_bbcode(0), canvas_layer)
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
## Bug fix round 4: use GrenadeAvailable (bool) instead of GrenadeLauncherAmmo (did not exist).
func _ak_gl_has_round_loaded() -> bool:
	if _assault_rifle == null:
		return false
	# Check C# AKGL property GrenadeAvailable (bool)
	var available = _assault_rifle.get("GrenadeAvailable")
	if available != null:
		return bool(available)
	# Fallback: assume loaded if property not found
	return true


## Add reload-related hints for the current weapon type.
## For weapons with special features (sniper bolt, revolver hammer), each feature gets its own line.
## Issue #945: Reload hint uses BBCode with the first step highlighted in red.
## Bug fix round 4: Shotgun shows full reload hint (replacing pump-action hint) after 2nd shot.
## Bug fix round 5: Set _shotgun_full_reload_active to block pump hint from overwriting full reload hint.
## Bug fix: Sniper bolt-cycle hint is NOT added here (it appears after 1st shot).
## Revolver hammer-cock hint is NOT added here (it appears from start).
func _add_reload_hints(canvas_layer: Node) -> void:
	# Add reload hint based on weapon type
	if _has_shotgun:
		# Bug fix round 4: replace the pump-action hint with the full reload hint after 2nd shot.
		# Bug fix round 5: set _shotgun_full_reload_active so ActionStateChanged skips pump updates.
		_shotgun_full_reload_active = true
		_dismiss_hint(HINT_BOLT_CYCLE)
		_add_hint(HINT_BOLT_CYCLE, _build_shotgun_full_reload_hint_bbcode(0), canvas_layer)
	elif _has_sniper_rifle:
		# Sniper: magazine swap reload hint. Bolt-cycle hint already shown after 1st shot.
		# Initial text = step 0 (nothing done yet, first R highlighted red).
		_add_hint(HINT_RELOAD, _build_reload_hint_bbcode(0, 3), canvas_layer)
	elif _has_revolver:
		# Revolver: cylinder reload hint. Hammer-cock hint is shown from start (Bug fix #3).
		_add_hint(HINT_RELOAD, _build_revolver_reload_hint_bbcode(0), canvas_layer)
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
## Issue #944: Adds fade-in animation when new hints appear + creates Line2D for progressive strikethrough.
func _add_hint(hint_key: String, text: String, canvas_layer: Node) -> void:
	if _hint_labels.has(hint_key):
		# Already exists - just update text (don't animate)
		if not _animating_hints.has(hint_key):
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

	# Issue #944: Start transparent for fade-in animation
	label.modulate.a = 0.0

	canvas_layer.add_child(label)
	_hint_labels[hint_key] = label

	# Issue #944 Session 5: Initialize empty array; Line2D nodes created per-line in deferred setup.
	_hint_strike_lines[hint_key] = []
	_hint_strike_progress[hint_key] = 0.0

	# Session 5: Calculate line count and create one Line2D per text line after layout.
	# Font size 20 with default line spacing gives ~26px per line.
	# We need to wait a frame for RichTextLabel to calculate its content size.
	_setup_strikethrough_lines.call_deferred(hint_key, label)

	print("Tutorial: Added hint '%s': %s" % [hint_key, text])

	# Position immediately
	_update_hint_position(hint_key, label)

	# Issue #944: Animate fade-in
	var tween := create_tween()
	tween.tween_property(label, "modulate:a", 1.0, HINT_FADE_IN_DURATION).set_ease(Tween.EASE_OUT)


## Issue #944 Session 5: Set up one Line2D per text line after label layout is ready.
## Each line gets its own Line2D node so there are no diagonal connectors between lines.
## Issue #1080: Also computes per-line text widths so strikethrough matches actual text length.
func _setup_strikethrough_lines(hint_key: String, label: RichTextLabel) -> void:
	if not is_instance_valid(label):
		return

	# Get font metrics. Font size is 20, typical line height with spacing is ~26px.
	const LINE_HEIGHT := 26.0  # Font size + default line spacing

	# Calculate number of lines based on content height vs line height.
	var content_height := label.get_content_height()
	var line_count := maxi(1, roundi(content_height / LINE_HEIGHT))
	_hint_line_counts[hint_key] = line_count

	# Issue #1080: Compute per-line text widths using font metrics.
	# Map each character in the plain text to its visual line, then measure each line's width.
	var line_widths: Array = []
	var font: Font = label.get_theme_font("normal_font")
	var font_size: int = label.get_theme_font_size("normal_font_size")
	if is_instance_valid(font) and font_size > 0:
		var plain_text: String = label.get_parsed_text()
		# Build per-line text strings by mapping character indices to visual lines.
		var per_line_text: Array = []
		for _i in range(line_count):
			per_line_text.append("")
		var char_count: int = plain_text.length()
		for char_idx in range(char_count):
			var visual_line: int = label.get_character_line(char_idx)
			if visual_line >= 0 and visual_line < line_count:
				per_line_text[visual_line] += plain_text[char_idx]
		for line_idx in range(line_count):
			var w: float = font.get_string_size(per_line_text[line_idx], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			line_widths.append(maxf(w, 1.0))
	else:
		# Fallback: use label content width for all lines.
		var fallback_width: float = label.get_content_width()
		if fallback_width <= 0:
			fallback_width = label.custom_minimum_size.x
		if fallback_width <= 0:
			fallback_width = 300.0
		for _i in range(line_count):
			line_widths.append(fallback_width)
	_hint_line_widths[hint_key] = line_widths

	# Create one Line2D per text line to avoid diagonal connectors between lines.
	var lines: Array = []
	for line_idx in range(line_count):
		# Vertical center of each line: ~55% of line height.
		var line_y := line_idx * LINE_HEIGHT + LINE_HEIGHT * 0.55
		var seg := Line2D.new()
		seg.name = "StrikeLine_%s_%d" % [hint_key, line_idx]
		seg.width = 1.5
		seg.default_color = Color(0.6, 0.6, 0.6, 0.6)
		seg.z_index = 1
		# Start and end both at x=0 (invisible until animation begins).
		seg.add_point(Vector2(0, line_y))
		seg.add_point(Vector2(0, line_y))
		label.add_child(seg)
		lines.append(seg)

	_hint_strike_lines[hint_key] = lines
	print("Tutorial: Setup strikethrough for '%s': %d lines, widths: %s" % [hint_key, line_count, str(line_widths)])


## Issue #944 Session 5: Animate the strikethrough lines to extend progressively as steps complete.
## target_progress: 0.0-1.0 representing how much of the hint text should be struck through.
## For multi-line text, progress spans all lines (e.g., 2 lines: 0.5 = line 1 fully struck).
func _extend_hint_strikethrough(hint_key: String, target_progress: float) -> void:
	if not _hint_strike_lines.has(hint_key):
		return

	var strike_lines: Array = _hint_strike_lines[hint_key]
	if strike_lines.is_empty():
		return

	var current_progress: float = _hint_strike_progress.get(hint_key, 0.0)
	if target_progress <= current_progress:
		return  # Already at or past this progress

	# Issue #1080: Use per-line widths if available, otherwise fall back to content width.
	var line_widths: Array = _hint_line_widths.get(hint_key, [])
	if line_widths.is_empty():
		var fallback_width := 300.0
		if _hint_labels.has(hint_key):
			var label: RichTextLabel = _hint_labels[hint_key]
			if is_instance_valid(label):
				var content_width := label.get_content_width()
				if content_width > 0:
					fallback_width = content_width
				elif label.custom_minimum_size.x > 0:
					fallback_width = label.custom_minimum_size.x
		var line_count: int = _hint_line_counts.get(hint_key, 1)
		for _i in range(line_count):
			line_widths.append(fallback_width)

	var line_count: int = _hint_line_counts.get(hint_key, 1)

	# Animate the line extension from current position to new position.
	var tween := create_tween()
	tween.tween_method(
		func(progress: float):
			_update_strikethrough_points(strike_lines, line_count, line_widths, progress),
		current_progress, target_progress, HINT_STRIKETHROUGH_DURATION * 0.5
	).set_ease(Tween.EASE_OUT)

	_hint_strike_progress[hint_key] = target_progress
	print("Tutorial: Strikethrough extended for '%s': %.0f%% -> %.0f%%" % [hint_key, current_progress * 100, target_progress * 100])


## Issue #944 Session 5: Update per-line Line2D end points for multi-line strikethrough.
## progress: 0.0-1.0 overall progress across all lines.
## Each Line2D in the array represents one text line and is animated independently.
## Issue #1080: line_widths is an Array[float] with the pixel width of each text line,
## so the strikethrough only extends over the actual text, not over empty space.
func _update_strikethrough_points(strike_lines: Array, line_count: int, line_widths: Array, progress: float) -> void:
	for line_idx in range(line_count):
		if line_idx >= strike_lines.size():
			break
		var seg: Line2D = strike_lines[line_idx]
		if not is_instance_valid(seg):
			continue

		# Calculate how much of this line should be struck through.
		var line_start_progress := float(line_idx) / line_count
		var line_end_progress := float(line_idx + 1) / line_count
		var line_progress: float

		if progress <= line_start_progress:
			line_progress = 0.0
		elif progress >= line_end_progress:
			line_progress = 1.0
		else:
			line_progress = (progress - line_start_progress) / (line_end_progress - line_start_progress)

		# Issue #1080: Use per-line width so the strikethrough matches the actual text length.
		var line_width: float = line_widths[line_idx] if line_idx < line_widths.size() else 300.0
		seg.set_point_position(1, Vector2(line_width * line_progress, seg.get_point_position(0).y))


## Dismiss (remove) a single hint by key, leaving other hints visible.
## Issue #944: Extends strikethrough to 100% before fade-out for all hints.
## Uses the persistent Line2D attached to the hint (created in _add_hint).
func _dismiss_hint(hint_key: String) -> void:
	if not _hint_labels.has(hint_key):
		return

	# Issue #944: Prevent double-dismiss while animating
	if _animating_hints.has(hint_key):
		return

	var label: RichTextLabel = _hint_labels[hint_key]
	if not is_instance_valid(label):
		_hint_labels.erase(hint_key)
		return

	# Mark as animating to prevent updates during animation
	_animating_hints[hint_key] = true

	print("Tutorial: Dismissing hint '%s' (with strikethrough animation)" % hint_key)
	_animate_hint_strikethrough_and_fade(hint_key, label)


## Issue #944 Session 5: Extend the per-line Line2D strikethroughs to 100% and then fade out.
## Uses the persistent Line2D array created per text line in _setup_strikethrough_lines.
func _animate_hint_strikethrough_and_fade(hint_key: String, label: RichTextLabel) -> void:
	# Get the existing strike lines for this hint
	var strike_lines: Array = []
	if _hint_strike_lines.has(hint_key):
		strike_lines = _hint_strike_lines[hint_key]

	# Issue #1080: Use per-line widths if available, otherwise fall back to content width.
	var line_widths: Array = _hint_line_widths.get(hint_key, [])
	if line_widths.is_empty():
		var fallback_width: float = label.get_content_width()
		if fallback_width <= 0:
			fallback_width = label.custom_minimum_size.x
		if fallback_width <= 0:
			fallback_width = 300.0
		var line_count_fb: int = _hint_line_counts.get(hint_key, 1)
		for _i in range(line_count_fb):
			line_widths.append(fallback_width)

	var line_count: int = _hint_line_counts.get(hint_key, 1)
	var current_progress: float = _hint_strike_progress.get(hint_key, 0.0)

	# Animate the lines from current position to full width (100%)
	var tween := create_tween()

	if not strike_lines.is_empty():
		tween.tween_method(
			func(progress: float):
				_update_strikethrough_points(strike_lines, line_count, line_widths, progress),
			current_progress, 1.0, HINT_STRIKETHROUGH_DURATION
		).set_ease(Tween.EASE_OUT)

	# After strikethrough animation completes, fade out the whole label
	tween.tween_property(label, "modulate:a", 0.0, HINT_FADE_OUT_DURATION).set_ease(Tween.EASE_IN)
	tween.tween_callback(_finalize_hint_dismiss.bind(hint_key, label))


## Issue #944 Session 4: Finalize hint dismissal after animation completes.
func _finalize_hint_dismiss(hint_key: String, label: RichTextLabel) -> void:
	_animating_hints.erase(hint_key)
	_hint_labels.erase(hint_key)
	_hint_strike_lines.erase(hint_key)
	_hint_strike_progress.erase(hint_key)
	_hint_line_counts.erase(hint_key)
	_hint_line_widths.erase(hint_key)
	if is_instance_valid(label):
		label.queue_free()
	print("Tutorial: Hint '%s' dismissed (animation complete)" % hint_key)


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
	completion_label.text = tr("TUTORIAL_LEVEL_COMPLETE")
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
	restart_label.text = tr("TUTORIAL_RESTART_HINT")
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
