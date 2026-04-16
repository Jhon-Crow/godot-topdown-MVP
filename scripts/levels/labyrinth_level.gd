extends Node2D
## Labyrinth level scene for the Godot Top-Down Template.
##
## This scene is a labyrinth of technical rooms (enclosed spaces).
## It serves as the new first level of the game.
## Features:
## - Compact labyrinth layout (1920x1080 pixels) matching viewport height
## - Multiple interconnected technical rooms with narrow corridors
## - 5 enemies: 3 with default weapon (1-2 HP), 1 with shotgun (1-2 HP),
##   1 with M16 armored (2-4 HP)
## - Dark industrial color scheme for technical facility atmosphere
## - Score tracking with Hotline Miami style ranking system

## Reference to the enemy count label.
var _enemy_count_label: Label = null

## Reference to the ammo count label.
var _ammo_label: Label = null

## Reference to the player.
var _player: Node2D = null

## Total enemy count at start.
var _initial_enemy_count: int = 0

## Current enemy count.
var _current_enemy_count: int = 0

## Whether game over has been shown.
var _game_over_shown: bool = false

## Reference to the difficulty label.
var _difficulty_label: Label = null

## Reference to the magazines label (shows individual magazine ammo counts).
var _magazines_label: Label = null

## Reference to the ColorRect for saturation effect.
var _saturation_overlay: ColorRect = null

## Reference to the combo label.
var _combo_label: Label = null
## Reference to active combo tween (to cancel if needed).
var _combo_tween: Tween = null

## Reference to the exit zone.
var _exit_zone: Area2D = null

## Whether the level has been cleared (all enemies eliminated).
var _level_cleared: bool = false

## Whether the score screen is currently shown (for W key shortcut).
var _score_shown: bool = false

## Whether the level completion sequence has been triggered (prevents duplicate calls).
var _level_completed: bool = false

## Duration of saturation effect in seconds.
const SATURATION_DURATION: float = 0.15

## Saturation effect intensity (alpha).
const SATURATION_INTENSITY: float = 0.25

## Laboratory-specific rank thresholds (Issue #823).
## Shifted one step down from the default so that the old A score now gives S.
## S=70% (was A), A+=55% (was B), A=38% (was C), B=22% (was D), C=12%, D=6%, F=0%.
const LABYRINTH_RANK_THRESHOLDS: Dictionary = {
	"S": 0.70,
	"A+": 0.55,
	"A": 0.38,
	"B": 0.22,
	"C": 0.12,
	"D": 0.06,
	"F": 0.0
}

## List of enemy nodes for position tracking.
var _enemies: Array = []

## Cached reference to the ReplayManager autoload (C# singleton).
var _replay_manager: Node = null

## ============================================================
## Tutorial hint system for the Laboratory level (Issue #808, #945)
## Mirrors tutorial_level.gd: weapon-dependent hints, grenade hint, no walk/shoot hints.
## Issue #945: RichTextLabel with BBCode colors, red NEXT-button highlight, 2-shot reload delay.
## Bug fixes (3rd review round): spacing, bolt-cycle timing, sniper sequence, grenade ordering,
## shotgun reload count, hammer-cock persistence, grenade check, AK GL hint.
## Bug fixes (Issue #991): AK GL hint no longer overlaps grenade hint (sequential flow via
## GrenadeFired signal); GL hint is dismissed when launcher fires.
## Bug fix (Issue #998): Scope RMB hint shown from the very start for sniper rifle;
## dismissed when player activates scope (ScopeStateChanged signal connected).
## ============================================================

## Tutorial hint labels: hint_key -> RichTextLabel node (Issue #945: was Label).
var _tutorial_hints: Dictionary = {}

## Tutorial state machine (same as tutorial_level.gd).
enum TutorialStep {
	RELOAD,
	THROW_GRENADE,
	COMPLETED
}

## Current tutorial step.
var _tutorial_step: TutorialStep = TutorialStep.RELOAD

## Whether the player has reloaded (for step tracking).
var _tutorial_has_reloaded: bool = false

## Whether the player has thrown a grenade (for step tracking).
var _tutorial_has_thrown_grenade: bool = false

## Whether the player has a shotgun (shotgun-specific reload hint).
var _tutorial_has_shotgun: bool = false

## Whether the player has a sniper rifle (bolt-cycle hint).
var _tutorial_has_sniper_rifle: bool = false

## Whether the player has a revolver (hammer cock hint).
var _tutorial_has_revolver: bool = false

## Whether the player has a Makarov PM (R->R reload hint).
var _tutorial_has_makarov_pm: bool = false

## Whether the player has an AK GL (for underbarrel grenade launcher tutorial, Bug fix #10).
var _tutorial_has_ak_gl: bool = false

## Reference to the player's assault rifle node (for GL ammo check, Bug fix #10).
var _tutorial_assault_rifle: Node = null

## Reference to the player's shotgun node (for shell count, Bug fix #7).
var _tutorial_shotgun: Node = null

## Reference to the player's sniper rifle node (for bolt step tracking, Bug fix #3).
var _tutorial_sniper_rifle: Node = null

## Whether the sniper bolt has been cycled (for reload step tracking).
var _tutorial_sniper_bolt_cycled: bool = false

## Whether the scope has been used (for sniper scope training, Issue #998).
var _tutorial_scope_used: bool = false

## Hint keys (same as tutorial_level.gd).
const TUTORIAL_HINT_RELOAD := "reload"
const TUTORIAL_HINT_GRENADE := "grenade"
const TUTORIAL_HINT_HAMMER_COCK := "hammer_cock"
const TUTORIAL_HINT_BOLT_CYCLE := "bolt_cycle"
const TUTORIAL_HINT_GRENADE_LAUNCHER := "grenade_launcher"  ## AK GL underbarrel (Bug fix #10)
const TUTORIAL_HINT_FIRE_MODE := "fire_mode"  ## M16 fire-mode switch [B] (Bug fix round 5)
const TUTORIAL_HINT_SCOPE := "scope"  ## Sniper scope RMB hint (Issue #998)

## Vertical spacing between stacked tutorial hints (pixels).
## Increased to 60 to prevent overlap when hints wrap to 2 lines (Bug fix #1 round 3).
const TUTORIAL_HINT_SPACING: float = 60.0

## Issue #944: Animation timing constants for hint fade-in, strikethrough, and fade-out.
const TUTORIAL_HINT_FADE_IN_DURATION := 0.3
const TUTORIAL_HINT_STRIKETHROUGH_DURATION := 0.4
const TUTORIAL_HINT_FADE_OUT_DURATION := 0.3

## Issue #944: Tracks hints currently being animated (prevents double-dismiss).
var _tutorial_animating_hints: Dictionary = {}

## Issue #944: Track Line2D strikethrough nodes for each hint (hint_key -> Array[Line2D]).
## Each hint has one Line2D per text line, so lines animate independently without connectors.
var _tutorial_hint_strike_lines: Dictionary = {}

## Issue #944: Track current strikethrough progress for each hint (hint_key -> float 0.0-1.0).
## Progress increases as each step completes; used to animate Line2D extension.
var _tutorial_hint_strike_progress: Dictionary = {}

## Issue #944 Session 4: Track line count for each hint (hint_key -> int).
## Multi-line hints need multiple Line2D segments, one per line.
var _tutorial_hint_line_counts: Dictionary = {}

## Issue #1080: Track per-line text widths for each hint (hint_key -> Array[float]).
## Each entry is the rendered pixel width of the corresponding text line,
## so strikethrough lines match the actual text length instead of the label width.
var _tutorial_hint_line_widths: Dictionary = {}

## Number of shots fired (Issue #945: reload hint appears after 2 shots).
var _tutorial_shots_fired: int = 0

## Whether the reload hint has already been revealed (Issue #945).
var _tutorial_reload_hint_revealed: bool = false

## Whether the bolt-cycle hint has already been revealed (sniper/shotgun after 1st shot).
var _tutorial_bolt_cycle_hint_revealed: bool = false

## Whether the shotgun full-reload hint is currently active (Bug fix round 5).
var _tutorial_shotgun_full_reload_active: bool = false

## Whether M16 fire-mode [B] hint should appear after grenade training (Bug fix round 5).
var _tutorial_m16_needs_fire_mode_hint: bool = false

## Grenade hint step (Issue #1818 / PR review feedback): 0..4 map to the effective actions.
var _tutorial_grenade_hint_step: int = 0

## Whether G key was held last frame (for grenade hint step tracking).
var _tutorial_grenade_g_was_held: bool = false
var _tutorial_grenade_drag_completed: bool = false
var _tutorial_grenade_rmb_held_after_release: bool = false
var _tutorial_grenade_rmb_was_pressed: bool = false
var _tutorial_grenade_hint_drag_start: Vector2 = Vector2.ZERO

## Unique colors per hint type (Issue #945: simultaneously displayed hints should be different colors).
const TUTORIAL_HINT_COLOR_RELOAD := Color(0.4, 1.0, 0.5, 1.0)              ## Green — reload
const TUTORIAL_HINT_COLOR_GRENADE := Color(1.0, 0.65, 0.0, 1.0)            ## Orange — grenade
const TUTORIAL_HINT_COLOR_BOLT_CYCLE := Color(0.85, 0.6, 1.0, 1.0)         ## Purple — bolt cycling
const TUTORIAL_HINT_COLOR_HAMMER_COCK := Color(1.0, 0.8, 0.3, 1.0)         ## Yellow — hammer cock
const TUTORIAL_HINT_COLOR_GRENADE_LAUNCHER := Color(1.0, 0.4, 0.2, 1.0)    ## Red-orange — AK GL
const TUTORIAL_HINT_COLOR_FIRE_MODE := Color(0.3, 0.9, 1.0, 1.0)           ## Cyan — fire mode switch (Bug fix round 5)
const TUTORIAL_HINT_COLOR_SCOPE := Color(0.3, 0.9, 1.0, 1.0)               ## Cyan — scope aiming (Issue #998)


## Gets the ReplayManager autoload node.
func _get_or_create_replay_manager() -> Node:
	if _replay_manager != null and is_instance_valid(_replay_manager):
		return _replay_manager

	_replay_manager = get_node_or_null("/root/ReplayManager")
	if _replay_manager != null:
		if _replay_manager.has_method("StartRecording"):
			_log_to_file("ReplayManager found as C# autoload - verified OK")
		else:
			_log_to_file("WARNING: ReplayManager autoload exists but has no StartRecording method")
	else:
		_log_to_file("ERROR: ReplayManager autoload not found at /root/ReplayManager")

	return _replay_manager


func _ready() -> void:
	print("LabyrinthLevel loaded - Technical Labyrinth")
	print("Labyrinth size: 1920x1080 pixels")
	print("Clear all rooms to win!")
	print("Press Q for quick restart")

	# Setup navigation mesh for enemy pathfinding
	_setup_navigation()

	# Find and connect to all enemies
	_setup_enemy_tracking()

	# Find the enemy count label
	_enemy_count_label = get_node_or_null("CanvasLayer/UI/EnemyCountLabel")
	_update_enemy_count_label()

	# Find and setup player tracking
	_setup_player_tracking()

	# Restrict camera so the border walls are never visible (Issue #1682).
	_configure_camera()

	# Setup debug UI
	_setup_debug_ui()

	# Setup saturation overlay for kill effect
	_setup_saturation_overlay()

	# Connect to GameManager signals
	if GameManager:
		GameManager.enemy_killed.connect(_on_game_manager_enemy_killed)
		GameManager.stats_updated.connect(_update_debug_ui)

	# Initialize ScoreManager for this level
	_initialize_score_manager()

	# Setup exit zone near player spawn (bottom-left)
	_setup_exit_zone()

	# Setup window lights in corridors without enemies
	_setup_window_lights()

	# Setup cold ceiling lights in all rooms (Issue #1208)
	_setup_room_cold_lights()

	# Show tutorial hints for basic controls (Issue #808)
	_setup_tutorial_hints()

	# Start replay recording
	_start_replay_recording()


## Initialize the ScoreManager for this level.
func _initialize_score_manager() -> void:
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager == null:
		return

	score_manager.start_level(_initial_enemy_count)

	# Apply Laboratory-specific rank thresholds (Issue #823):
	# the score that used to give A now gives S, all other ranks shift accordingly.
	if score_manager.has_method("set_rank_thresholds"):
		score_manager.set_rank_thresholds(LABYRINTH_RANK_THRESHOLDS)

	if _player:
		score_manager.set_player(_player)

	if not score_manager.combo_changed.is_connected(_on_combo_changed):
		score_manager.combo_changed.connect(_on_combo_changed)


## Starts recording the replay for this level.
func _start_replay_recording() -> void:
	var replay_manager: Node = _get_or_create_replay_manager()
	if replay_manager == null:
		_log_to_file("ERROR: ReplayManager could not be loaded, replay recording disabled")
		print("[LabyrinthLevel] ERROR: ReplayManager could not be loaded!")
		return

	_log_to_file("Starting replay recording - Player: %s, Enemies count: %d" % [
		_player.name if _player else "NULL",
		_enemies.size()
	])

	if _player == null:
		_log_to_file("WARNING: Player is null, replay may not record properly")
		print("[LabyrinthLevel] WARNING: Player is null for replay recording!")

	if _enemies.is_empty():
		_log_to_file("WARNING: No enemies to track in replay")
		print("[LabyrinthLevel] WARNING: No enemies registered for replay!")

	if replay_manager.has_method("ClearReplay"):
		replay_manager.ClearReplay()
		_log_to_file("Previous replay data cleared")

	if replay_manager.has_method("StartRecording"):
		replay_manager.StartRecording(self, _player, _enemies)
		_log_to_file("Replay recording started successfully")
		print("[LabyrinthLevel] Replay recording started with %d enemies" % _enemies.size())
	else:
		_log_to_file("ERROR: ReplayManager.StartRecording method not found")
		print("[LabyrinthLevel] ERROR: StartRecording method not found!")


## Setup the exit zone near the player spawn point (bottom-left).
func _setup_exit_zone() -> void:
	var exit_zone_scene = load("res://scenes/objects/ExitZone.tscn")
	if exit_zone_scene == null:
		push_warning("ExitZone scene not found - score will show immediately on level clear")
		return

	_exit_zone = exit_zone_scene.instantiate()
	# Position exit on the left wall near player spawn (player starts at 150, 1000)
	_exit_zone.position = Vector2(80, 1000)
	_exit_zone.zone_width = 60.0
	_exit_zone.zone_height = 100.0

	_exit_zone.player_reached_exit.connect(_on_player_reached_exit)

	var environment := get_node_or_null("Environment")
	if environment:
		environment.add_child(_exit_zone)
	else:
		add_child(_exit_zone)

	print("[LabyrinthLevel] Exit zone created at position (80, 1000)")


## Called when the player reaches the exit zone after clearing the level.
func _on_player_reached_exit() -> void:
	if not _level_cleared:
		return

	if _level_completed:
		return

	print("[LabyrinthLevel] Player reached exit - showing score!")
	call_deferred("_complete_level_with_score")


## Activate the exit zone after all enemies are eliminated.
func _activate_exit_zone() -> void:
	if _exit_zone and _exit_zone.has_method("activate"):
		_exit_zone.activate()
		print("[LabyrinthLevel] Exit zone activated - go to exit to see score!")
	else:
		push_warning("Exit zone not available - showing score immediately")
		_complete_level_with_score()


## Setup realistic visibility for the player.
func _setup_realistic_visibility() -> void:
	if _player == null:
		return

	var visibility_script = load("res://scripts/components/realistic_visibility_component.gd")
	if visibility_script == null:
		push_warning("[LabyrinthLevel] RealisticVisibilityComponent script not found")
		return

	var visibility_component = Node.new()
	visibility_component.name = "RealisticVisibilityComponent"
	visibility_component.set_script(visibility_script)
	_player.add_child(visibility_component)

	# Tint the visibility light to match the cold-blue laboratory atmosphere
	# so it blends with the room cold lights (Color(0.55, 0.75, 1.0)) instead
	# of washing them out with a warm-white glow (Issue #1263).
	# Color is deeper blue (lower R) to avoid white cast; energy is reduced
	# from the default 1.5 so it no longer overpowers the room cold lights (≤0.65).
	visibility_component.set_light_color(Color(0.45, 0.65, 1.0))
	visibility_component.set_light_energy(0.8)
	print("[LabyrinthLevel] Realistic visibility component added to player")


## Setup window lights in corridors without enemies.
func _setup_window_lights() -> void:
	var environment := get_node_or_null("Environment")
	if environment == null:
		return

	var windows_node := Node2D.new()
	windows_node.name = "WindowLights"
	environment.add_child(windows_node)

	# Left wall windows - near storage/hall area (no enemies nearby)
	_create_window_light(windows_node, Vector2(48, 600), "left")
	_create_window_light(windows_node, Vector2(48, 800), "left")

	# Top wall windows - above corridor between rooms
	_create_window_light(windows_node, Vector2(900, 48), "top")

	# Bottom wall windows - below storage and server room
	_create_window_light(windows_node, Vector2(700, 1128), "bottom")
	_create_window_light(windows_node, Vector2(1200, 1128), "bottom")

	# Scene-wide ambient moonlight
	_create_ambient_moonlight(windows_node)

	print("[LabyrinthLevel] Window lights placed in corridors without enemies")


## Create a single window light source at the given position on a wall.
func _create_window_light(parent: Node2D, pos: Vector2, wall_side: String) -> void:
	var window_node := Node2D.new()
	window_node.name = "Window_%s_%d_%d" % [wall_side, int(pos.x), int(pos.y)]
	window_node.position = pos
	parent.add_child(window_node)

	var window_rect := ColorRect.new()
	window_rect.color = Color(0.3, 0.4, 0.7, 0.6)
	match wall_side:
		"left":
			window_rect.offset_left = -4.0
			window_rect.offset_top = -20.0
			window_rect.offset_right = 4.0
			window_rect.offset_bottom = 20.0
		"right":
			window_rect.offset_left = -4.0
			window_rect.offset_top = -20.0
			window_rect.offset_right = 4.0
			window_rect.offset_bottom = 20.0
		"top":
			window_rect.offset_left = -20.0
			window_rect.offset_top = -4.0
			window_rect.offset_right = 20.0
			window_rect.offset_bottom = 4.0
		"bottom":
			window_rect.offset_left = -20.0
			window_rect.offset_top = -4.0
			window_rect.offset_right = 20.0
			window_rect.offset_bottom = 4.0
	window_node.add_child(window_rect)

	var light := PointLight2D.new()
	light.name = "MoonLight"
	light.color = Color(0.4, 0.5, 0.9, 1.0)
	light.energy = 0.12
	light.shadow_enabled = true
	light.shadow_filter = PointLight2D.SHADOW_FILTER_PCF5
	light.shadow_filter_smooth = 4.0
	light.shadow_color = Color(0, 0, 0, 0.7)
	light.texture = _create_window_light_texture()
	light.texture_scale = 6.0
	match wall_side:
		"left":
			light.position = Vector2(60, 0)
		"right":
			light.position = Vector2(-60, 0)
		"top":
			light.position = Vector2(0, 60)
		"bottom":
			light.position = Vector2(0, -60)
	window_node.add_child(light)


## Create a radial gradient texture for the primary window moonlight.
func _create_window_light_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.add_point(0.1, Color(0.7, 0.7, 0.7, 1.0))
	gradient.add_point(0.2, Color(0.45, 0.45, 0.45, 1.0))
	gradient.add_point(0.3, Color(0.25, 0.25, 0.25, 1.0))
	gradient.add_point(0.4, Color(0.1, 0.1, 0.1, 1.0))
	gradient.add_point(0.5, Color(0.02, 0.02, 0.02, 1.0))
	gradient.add_point(0.55, Color(0.0, 0.0, 0.0, 1.0))
	gradient.set_color(1, Color(0.0, 0.0, 0.0, 1.0))

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 512
	texture.height = 512
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	return texture


## Create a scene-wide ambient moonlight using DirectionalLight2D.
func _create_ambient_moonlight(parent: Node2D) -> void:
	var ambient := DirectionalLight2D.new()
	ambient.name = "AmbientMoonlight"
	ambient.color = Color(0.35, 0.45, 0.85, 1.0)
	ambient.energy = 0.06
	ambient.shadow_enabled = false
	parent.add_child(ambient)


## Setup cold ceiling lights in all rooms (Issue #1208).
## Adds dim PointLight2D nodes with a cold blue tint to simulate fluorescent
## laboratory lighting. Energy and scale are lower than the warm BuildingLevel
## lights to keep the atmosphere tense and cold.
##
## Room centers (derived from InteriorWall positions in the scene):
## - Generator Room:  ~(400, 270)   — upper-left, left of x=750 wall
## - Control Room:    ~(1500, 220)  — upper-right, between x=1050 and x=1920
## - Storage Hall:    ~(220, 840)   — lower-left, left of x=450 wall
## - Corridor Area:   ~(700, 380)   — centre passage between rooms
## - Server Room:     ~(1100, 900)  — lower-centre, below y=680 wall
## - Pipe/Elec Room:  ~(1700, 700)  — right side, between pipe and elec walls
func _setup_room_cold_lights() -> void:
	var environment := get_node_or_null("Environment")
	if environment == null:
		return

	# Container node for all room lights
	var room_lights_node := Node2D.new()
	room_lights_node.name = "RoomLights"
	environment.add_child(room_lights_node)

	# Cold blue-tinted dim lights for each room.
	# Energy is ~25% lower than the warm BuildingLevel equivalents.
	# Format: [position, energy, texture_scale, label]
	var room_configs: Array = [
		# Upper-left — Generator Room
		[Vector2(400, 270),  0.65, 3.5, "GeneratorRoom"],
		# Upper-right — Control Room (larger space)
		[Vector2(1500, 220), 0.65, 4.0, "ControlRoom"],
		# Lower-left — Storage Hall
		[Vector2(220, 840),  0.55, 3.0, "StorageHall"],
		# Centre passage
		[Vector2(700, 380),  0.50, 3.0, "Corridor"],
		# Lower-centre — Server Room
		[Vector2(1100, 900), 0.65, 3.5, "ServerRoom"],
		# Right side — Pipe/Electrical Room
		[Vector2(1700, 700), 0.55, 3.0, "PipeElecRoom"],
	]

	for cfg in room_configs:
		_create_room_cold_light(room_lights_node, cfg[0], cfg[1], cfg[2], cfg[3])

	print("[LabyrinthLevel] Cold ceiling lights placed in all rooms (Issue #1208)")


## Create a single cold ceiling light at the given room-center position.
## Uses a Sprite2D fixture (not ColorRect/Control) so it never intercepts mouse
## events and cannot break pause-menu clicks.
## @param parent: Container node.
## @param pos: World-space position (room center).
## @param energy: Light brightness (lower → dimmer and more atmospheric).
## @param scale: Texture scale controlling the light radius.
## @param room_name: Name suffix for the node (debug convenience).
func _create_room_cold_light(parent: Node2D, pos: Vector2, energy: float, scale: float, room_name: String) -> void:
	var light_node := Node2D.new()
	light_node.name = "ColdLight_%s" % room_name
	light_node.position = pos
	parent.add_child(light_node)

	# Small round ceiling lamp fixture — cold white-blue tint, semi-transparent.
	# Sprite2D is a Node2D and never blocks input, unlike Control-based nodes.
	var fixture := Sprite2D.new()
	fixture.name = "Fixture"
	fixture.texture = _create_lamp_fixture_texture()
	fixture.modulate = Color(0.7, 0.85, 1.0, 0.45)  # Pale cold blue, semi-transparent
	light_node.add_child(fixture)

	# The actual PointLight2D — cold blue tint, shadows on.
	var light := PointLight2D.new()
	light.name = "PointLight"
	light.color = Color(0.55, 0.75, 1.0, 1.0)   # Cold blue-white
	light.energy = energy
	light.shadow_enabled = true
	light.shadow_filter = PointLight2D.SHADOW_FILTER_PCF5
	light.shadow_filter_smooth = 3.0
	light.shadow_color = Color(0.0, 0.0, 0.05, 0.65)
	light.texture = _create_cold_light_texture()
	light.texture_scale = scale
	light_node.add_child(light)


## Create a soft radial gradient texture for the cold room lights.
## Uses the same power-law circular falloff as the warm BuildingLevel lights
## so there are no hard visible edges — the light fades naturally to black.
func _create_cold_light_texture() -> ImageTexture:
	var size := 512
	var center := Vector2(size * 0.5, size * 0.5)
	var outer_r := size * 0.5  # 256 px

	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)

	for y in range(size):
		for x in range(size):
			var dist := Vector2(x, y).distance_to(center)
			var t := clampf(dist / outer_r, 0.0, 1.0)  # 0 = centre, 1 = edge
			var brightness := pow(1.0 - t, 2.2)
			image.set_pixel(x, y, Color(brightness, brightness, brightness, 1.0))

	return ImageTexture.create_from_image(image)


## Create a small circular texture for the ceiling lamp fixture visual.
## Draws a soft-edged disc so the fixture looks round, matching the
## circular PointLight2D pool beneath it.
func _create_lamp_fixture_texture() -> ImageTexture:
	var size := 32
	var center := Vector2(size * 0.5, size * 0.5)
	var outer_r := size * 0.5  # full disc radius

	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)

	for y in range(size):
		for x in range(size):
			var dist := Vector2(x, y).distance_to(center)
			if dist >= outer_r:
				image.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
			else:
				var t := clampf(dist / outer_r, 0.0, 1.0)
				var alpha := pow(1.0 - t, 1.5)
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))

	return ImageTexture.create_from_image(image)


func _process(_delta: float) -> void:
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager and score_manager.has_method("update_enemy_positions"):
		score_manager.update_enemy_positions(_enemies)
	# Issue #959: Re-check level completion when a retaliating pacifist finishes retaliation.
	if _current_enemy_count <= 0 and not _level_cleared and not _has_retaliating_pacifists():
		print("All enemies eliminated or pacified! Labyrinth cleared!")
		_level_cleared = true
		call_deferred("_activate_exit_zone")

	# Update tutorial hint positions to follow player (Issue #808)
	_update_tutorial_hint_positions()

	# Bug fix round 5: update grenade hint step based on key state
	_update_tutorial_grenade_hint_step()


## Called when combo changes.
func _on_combo_changed(combo: int, points: int) -> void:
	if _combo_label == null:
		return

	if combo > 0:
		_combo_label.text = "x%d COMBO\n+%d" % [combo, points]
		_combo_label.visible = true
		var combo_color := _get_combo_color(combo)
		_combo_label.add_theme_color_override("font_color", combo_color)
		# Combo pop animation: scale bounce + fade in (stays visible until combo resets)
		if _combo_tween != null and _combo_tween.is_valid():
			_combo_tween.kill()
		_combo_label.scale = Vector2(0.7, 0.7)
		_combo_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
		_combo_tween = create_tween()
		_combo_tween.set_parallel(true)
		_combo_tween.tween_property(_combo_label, "scale", Vector2(1.0, 1.0), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_combo_tween.tween_property(_combo_label, "modulate:a", 1.0, 0.1)
		_combo_tween.set_parallel(false)
	else:
		if _combo_tween != null and _combo_tween.is_valid():
			_combo_tween.kill()
		_combo_tween = create_tween()
		_combo_tween.tween_property(_combo_label, "modulate:a", 0.0, 0.3)
		_combo_tween.tween_callback(_combo_label.hide)


## Returns a color based on the current combo count.
func _get_combo_color(combo: int) -> Color:
	if combo >= 10:
		return Color(1.0, 0.0, 1.0, 1.0)
	elif combo >= 7:
		return Color(1.0, 0.0, 0.3, 1.0)
	elif combo >= 5:
		return Color(1.0, 0.1, 0.1, 1.0)
	elif combo >= 4:
		return Color(1.0, 0.2, 0.0, 1.0)
	elif combo >= 3:
		return Color(1.0, 0.4, 0.0, 1.0)
	elif combo >= 2:
		return Color(1.0, 0.6, 0.1, 1.0)
	else:
		return Color(1.0, 0.8, 0.2, 1.0)


## Setup the navigation mesh for enemy pathfinding.
## Clamps the camera so the outer border walls are never visible (Issue #1682).
##
## LabyrinthLevel map: ~2016x1176 px playfield framed by 32 px walls.
##   WallTop    (1008,   32), h=16  → bottom edge y=48   → limit_top    = 48
##   WallBottom (1008, 1144), h=16  → top edge   y=1128  → limit_bottom = 1128
##   WallLeft   (  32,  588), w=16  → right edge x=48    → limit_left   = 48
##   WallRight  (1984,  588), w=16  → left edge  x=1968  → limit_right  = 1968
func _configure_camera() -> void:
	if _player == null:
		return
	var camera: Camera2D = _player.get_node_or_null("Camera2D")
	if camera == null:
		push_warning("[LabyrinthLevel] Camera2D not found on player — cannot set camera limits")
		return
	const LIMIT_TOP: int    =   48   # WallTop bottom edge
	const LIMIT_BOTTOM: int = 1128   # WallBottom top edge
	const LIMIT_LEFT: int   =   48   # WallLeft right edge
	const LIMIT_RIGHT: int  = 1968   # WallRight left edge
	camera.limit_top    = LIMIT_TOP
	camera.limit_bottom = LIMIT_BOTTOM
	camera.limit_left   = LIMIT_LEFT
	camera.limit_right  = LIMIT_RIGHT
	_log_to_file("Camera2D limits set — top=%d bottom=%d left=%d right=%d — Issue #1682" % [
		LIMIT_TOP, LIMIT_BOTTOM, LIMIT_LEFT, LIMIT_RIGHT
	])


func _setup_navigation() -> void:
	var nav_region: NavigationRegion2D = get_node_or_null("NavigationRegion2D")
	if nav_region == null:
		push_warning("NavigationRegion2D not found - enemy pathfinding will be limited")
		return
	var nav_poly: NavigationPolygon = nav_region.navigation_polygon
	if nav_poly == null:
		push_warning("NavigationPolygon not found - enemy pathfinding will be limited")
		return
	# Issue #1289: wait for physics frame so CollisionShape2D nodes are registered
	# with PhysicsServer2D before parsing source geometry for navmesh carving.
	await get_tree().physics_frame
	# Issue #1289: explicit parse+bake so all wall StaticBody2D nodes are found.
	print("Baking navigation mesh...")
	var source_geometry: NavigationMeshSourceGeometryData2D = NavigationMeshSourceGeometryData2D.new()
	NavigationServer2D.parse_source_geometry_data(nav_poly, source_geometry, self)
	NavigationServer2D.bake_from_source_geometry_data(nav_poly, source_geometry)
	# Issue #1289: push updated polygon back into the NavigationServer's live map.
	# Without this reassignment, agents still use the pre-bake (uncarved) navmesh.
	nav_region.navigation_polygon = nav_poly
	nav_region.emit_signal("bake_finished")
	print("Navigation mesh baked successfully")


## Setup tracking for the player.
func _setup_player_tracking() -> void:
	_player = get_node_or_null("Entities/Player")
	if _player == null:
		return

	# Setup realistic visibility component
	_setup_realistic_visibility()

	# Setup selected weapon based on GameManager selection
	_setup_selected_weapon()

	# Register player with GameManager
	if GameManager:
		GameManager.set_player(_player)

	_ammo_label = get_node_or_null("CanvasLayer/UI/AmmoLabel")

	# Connect to player death signal
	if _player.has_signal("died"):
		_player.died.connect(_on_player_died)
	elif _player.has_signal("Died"):
		_player.Died.connect(_on_player_died)

	# Try to get the player's weapon for C# Player
	var weapon = _player.get_node_or_null("Shotgun")
	if weapon == null:
		weapon = _player.get_node_or_null("MiniUzi")
	if weapon == null:
		weapon = _player.get_node_or_null("SilencedPistol")
	if weapon == null:
		weapon = _player.get_node_or_null("SniperRifle")
	if weapon == null:
		weapon = _player.get_node_or_null("AssaultRifle")
	if weapon == null:
		weapon = _player.get_node_or_null("AKGL")
	if weapon == null:
		weapon = _player.get_node_or_null("Revolver")
	if weapon == null:
		weapon = _player.get_node_or_null("MakarovPM")
	if weapon != null:
		if weapon.has_signal("AmmoChanged"):
			weapon.AmmoChanged.connect(_on_weapon_ammo_changed)
		if weapon.has_signal("MagazinesChanged"):
			weapon.MagazinesChanged.connect(_on_magazines_changed)
		if weapon.has_signal("Fired"):
			weapon.Fired.connect(_on_shot_fired)
			# Also count shots for reload hint reveal (Issue #945)
			weapon.Fired.connect(_on_tutorial_weapon_fired)
		elif weapon.has_signal("ShotFired"):
			# Bug fix #2: fallback signal name for weapons that use ShotFired
			weapon.ShotFired.connect(_on_tutorial_weapon_fired)
		if weapon.has_signal("ShellCountChanged"):
			weapon.ShellCountChanged.connect(_on_shell_count_changed)
		if weapon.get("CurrentAmmo") != null and weapon.get("ReserveAmmo") != null:
			_update_ammo_label_magazine(weapon.CurrentAmmo, weapon.ReserveAmmo)
		if weapon.has_method("GetMagazineAmmoCounts"):
			var mag_counts: Array = weapon.GetMagazineAmmoCounts()
			_update_magazines_label(mag_counts)
		_configure_silenced_pistol_ammo(weapon)
		_configure_makarov_pm_ammo(weapon)

		# Detect weapon type for tutorial hints (Issue #808, #945)
		match weapon.name:
			"Shotgun":
				_tutorial_has_shotgun = true
				_tutorial_shotgun = weapon  # Bug fix #7: reference for shell count
				# Bug fix round 4: connect ActionStateChanged for pump-action hint updates
				if weapon.has_signal("ActionStateChanged"):
					weapon.ActionStateChanged.connect(_on_tutorial_shotgun_action_state_changed)
				if weapon.has_signal("ReloadStateChanged"):
					weapon.ReloadStateChanged.connect(_on_tutorial_shotgun_reload_state_changed)
			"SniperRifle":
				_tutorial_has_sniper_rifle = true
				_tutorial_sniper_rifle = weapon  # Bug fix #3: reference for bolt step hints
				if weapon.has_signal("BoltStepChanged"):
					weapon.BoltStepChanged.connect(_on_tutorial_sniper_bolt_step_changed)
				# Issue #998: Connect scope state signal to dismiss scope hint when player uses scope.
				if weapon.has_signal("ScopeStateChanged"):
					weapon.ScopeStateChanged.connect(_on_tutorial_scope_state_changed)
			"Revolver":
				_tutorial_has_revolver = true
				# Connect to HammerCocked signal to dismiss hammer hint (Issue #808)
				if weapon.has_signal("HammerCocked"):
					weapon.HammerCocked.connect(_on_tutorial_hammer_cocked)
				# Bug fix round 5: connect ReloadStateChanged to update revolver reload hint step-by-step.
				if weapon.has_signal("ReloadStateChanged"):
					weapon.ReloadStateChanged.connect(_on_tutorial_revolver_reload_state_changed)
				# Bug fix round 6: connect CartridgeInserted for real-time ammo counter during cylinder reload.
				# AmmoChanged fires only when the full reload completes; CartridgeInserted fires per cartridge.
				if weapon.has_signal("CartridgeInserted"):
					weapon.CartridgeInserted.connect(_on_revolver_cartridge_inserted)
			"MakarovPM":
				_tutorial_has_makarov_pm = true
			"AssaultRifle":
				_tutorial_assault_rifle = weapon
				# Bug fix round 5: connect FireModeChanged to detect when M16 fire-mode [B] is pressed.
				if weapon.has_signal("FireModeChanged"):
					weapon.FireModeChanged.connect(_on_tutorial_fire_mode_changed)
			"AKGL":
				_tutorial_has_ak_gl = true  # Bug fix #10
				_tutorial_assault_rifle = weapon  # Bug fix #10: reference for GL ammo check
				# Note: AKGL does NOT have FireModeChanged — no connection needed.
				# Issue #991 fix: connect GrenadeFired to dismiss GL hint and show grenade hint
				# sequentially. Without this the GL hint never disappears after firing, and both
				# GL hint + grenade hint appear simultaneously causing overlap.
				if weapon.has_signal("GrenadeFired"):
					weapon.GrenadeFired.connect(_on_tutorial_grenade_launcher_fired)
					print("[LabyrinthLevel] Connected to GrenadeFired signal (AKGL)")
	else:
		if _player.has_signal("ammo_changed"):
			_player.ammo_changed.connect(_on_player_ammo_changed)
		if _player.has_method("get_current_ammo") and _player.has_method("get_max_ammo"):
			_update_ammo_label(_player.get_current_ammo(), _player.get_max_ammo())

	# Connect reload/ammo depleted signals
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

	# Connect to grenade thrown signal for grenade tutorial hint (Issue #808)
	if _player.has_signal("GrenadeThrown"):
		_player.GrenadeThrown.connect(_on_tutorial_grenade_thrown)
	elif _player.has_signal("grenade_thrown"):
		_player.grenade_thrown.connect(_on_tutorial_grenade_thrown)

	# Connect ReloadSequenceProgress for dynamic next-button highlighting (Issue #945)
	if _player.has_signal("ReloadSequenceProgress"):
		_player.ReloadSequenceProgress.connect(_on_tutorial_reload_sequence_progress)
		print("[LabyrinthLevel] Connected to ReloadSequenceProgress signal")


## Setup tracking for all enemies in the scene.
func _setup_enemy_tracking() -> void:
	var enemies_node := get_node_or_null("Environment/Enemies")
	if enemies_node == null:
		_log_to_file("ERROR: Environment/Enemies node not found!")
		return

	_log_to_file("Found Environment/Enemies node with %d children" % enemies_node.get_child_count())
	_enemies.clear()
	for child in enemies_node.get_children():
		var has_died_signal := child.has_signal("died")
		var script_attached := child.get_script() != null
		_log_to_file("Child '%s': script=%s, has_died_signal=%s" % [child.name, script_attached, has_died_signal])
		if has_died_signal:
			_enemies.append(child)
			child.died.connect(_on_enemy_died)
			if child.has_signal("died_with_info"):
				child.died_with_info.connect(_on_enemy_died_with_info)
		if child.has_signal("hit"):
			child.hit.connect(_on_enemy_hit)
		# Issue #959: Connect to pacifist signal - pacifists count as killed for level completion
		if child.has_signal("became_pacifist"):
			child.became_pacifist.connect(_on_enemy_became_pacifist.bind(child))

	_initial_enemy_count = _enemies.size()
	_current_enemy_count = _initial_enemy_count
	_log_to_file("Enemy tracking complete: %d enemies registered" % _initial_enemy_count)
	print("Tracking %d enemies" % _initial_enemy_count)


## Configure silenced pistol ammo based on enemy count.
func _configure_silenced_pistol_ammo(weapon: Node) -> void:
	if weapon.name != "SilencedPistol":
		return

	if weapon.has_method("ConfigureAmmoForEnemyCount"):
		var enemy_count: int = _initial_enemy_count
		var ammo_multiplier: int = DifficultyManager.get_ammo_multiplier()
		if ammo_multiplier > 1:
			enemy_count *= ammo_multiplier
			print("[LabyrinthLevel] Gunslinger/PowerFantasy mode: silenced pistol enemy count multiplied by %dx" % ammo_multiplier)
		weapon.ConfigureAmmoForEnemyCount(enemy_count)
		print("[LabyrinthLevel] Configured silenced pistol ammo for %d enemies" % enemy_count)

		if weapon.get("CurrentAmmo") != null and weapon.get("ReserveAmmo") != null:
			_update_ammo_label_magazine(weapon.CurrentAmmo, weapon.ReserveAmmo)
		if weapon.has_method("GetMagazineAmmoCounts"):
			var mag_counts: Array = weapon.GetMagazineAmmoCounts()
			_update_magazines_label(mag_counts)


## Configure Makarov PM ammo - 2.5x magazines (Issue #636).
func _configure_makarov_pm_ammo(weapon: Node) -> void:
	if weapon == null:
		return

	if weapon.name != "MakarovPM":
		return

	var starting_magazines: int = 4
	if weapon.get("StartingMagazineCount") != null:
		starting_magazines = weapon.StartingMagazineCount

	var pm_magazines: int = int(round(starting_magazines * 2.5))
	var ammo_multiplier: int = DifficultyManager.get_ammo_multiplier()
	if ammo_multiplier > 1:
		pm_magazines *= ammo_multiplier
		print("[LabyrinthLevel] Gunslinger/PowerFantasy mode: MakarovPM magazines multiplied by %dx" % ammo_multiplier)

	if weapon.has_method("ReinitializeMagazines"):
		weapon.ReinitializeMagazines(pm_magazines, true)
		print("[LabyrinthLevel] 2.5x ammo for MakarovPM: %d magazines (was %d)" % [pm_magazines, starting_magazines])

		if weapon.get("CurrentAmmo") != null and weapon.get("ReserveAmmo") != null:
			_update_ammo_label_magazine(weapon.CurrentAmmo, weapon.ReserveAmmo)
		if weapon.has_method("GetMagazineAmmoCounts"):
			var mag_counts: Array = weapon.GetMagazineAmmoCounts()
			_update_magazines_label(mag_counts)

	# Reapply auto-reload magazine size reduction if active (Issue #1067).
	if _player != null and _player.has_method("ApplyAutoReloadAfterLevelAmmoConfig"):
		_player.ApplyAutoReloadAfterLevelAmmoConfig()


## Apply Labyrinth level ammo configuration to a weapon (Issue #1422).
## Silenced pistol: exactly as many bullets as enemies.
## Mini UZI and rifles: 2 magazines to match level difficulty.
## Shotgun, sniper, revolver: defaults are sufficient for 5 enemies.
##
## Issue #1774 fix: magazine sizes are now passed explicitly to ReinitializeMagazines so
## that ammo initialisation succeeds even when WeaponData is null (first-load C# resource
## race where the [GlobalClass] WeaponData type is not yet registered by Godot).
const _MAGAZINE_SIZES: Dictionary = {
	"mini_uzi": 32,   ## MiniUziData.tres MagazineSize = 32
	"m16": 30,        ## AssaultRifleData.tres MagazineSize = 30
	"ak_gl": 30,      ## AKGLData.tres MagazineSize = 30
}

func _configure_labyrinth_weapon_ammo(weapon: Node, weapon_id: String) -> void:
	if weapon == null:
		return

	if weapon_id == "silenced_pistol":
		_configure_silenced_pistol_ammo(weapon)
	elif weapon_id == "mini_uzi" or weapon_id == "m16" or weapon_id == "ak_gl":
		var base_magazines: int = 2
		var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
		if difficulty_manager:
			var ammo_multiplier: int = difficulty_manager.get_ammo_multiplier()
			if ammo_multiplier > 1:
				base_magazines *= ammo_multiplier
				print("[LabyrinthLevel] Power Fantasy mode - %s magazines multiplied by %dx" % [weapon.name, ammo_multiplier])
		if weapon.has_method("ReinitializeMagazines"):
			# Issue #1774: pass explicit magazine size so ReinitializeMagazines works even when
			# WeaponData is null due to first-load C# resource race condition.
			var mag_size: int = _MAGAZINE_SIZES.get(weapon_id, 30)
			weapon.ReinitializeMagazines(base_magazines, mag_size, true)
			print("[LabyrinthLevel] %s magazines reinitialized to %d x %d rounds" % [weapon.name, base_magazines, mag_size])
		if weapon.get("CurrentAmmo") != null and weapon.get("ReserveAmmo") != null:
			_update_ammo_label_magazine(weapon.CurrentAmmo, weapon.ReserveAmmo)
		if weapon.has_method("GetMagazineAmmoCounts"):
			var mag_counts: Array = weapon.GetMagazineAmmoCounts()
			_update_magazines_label(mag_counts)

	if _player != null and _player.has_method("ApplyAutoReloadAfterLevelAmmoConfig"):
		_player.ApplyAutoReloadAfterLevelAmmoConfig()
		_log_to_file("Re-applied auto-reload magazine reduction after ammo config for %s" % weapon_id)


## Setup debug UI elements for kills and accuracy.
func _setup_debug_ui() -> void:
	var ui := get_node_or_null("CanvasLayer/UI")
	if ui == null:
		return

	_difficulty_label = Label.new()
	_difficulty_label.name = "DifficultyLabel"
	_difficulty_label.text = "Difficulty: " + DifficultyManager.get_difficulty_name()
	_difficulty_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_difficulty_label.offset_left = 10
	_difficulty_label.offset_top = 80
	_difficulty_label.offset_right = 200
	_difficulty_label.offset_bottom = 110
	ui.add_child(_difficulty_label)

	_magazines_label = Label.new()
	_magazines_label.name = "MagazinesLabel"
	_magazines_label.text = "MAGS: -"
	_magazines_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_magazines_label.offset_left = 10
	_magazines_label.offset_top = 115
	_magazines_label.offset_right = 400
	_magazines_label.offset_bottom = 145
	ui.add_child(_magazines_label)

	var gameplay_settings: Node = get_node_or_null("/root/GameplaySettings")
	var combo_size: int = gameplay_settings.get_combo_font_size() if gameplay_settings and gameplay_settings.has_method("get_combo_font_size") else 112
	_combo_label = Label.new()
	_combo_label.name = "ComboLabel"
	_combo_label.text = ""
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combo_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_combo_label.offset_left = 10
	_combo_label.offset_right = -10
	_combo_label.offset_top = 80
	_combo_label.offset_bottom = _combo_label.offset_top + combo_size * 2 + 20
	_combo_label.add_theme_font_size_override("font_size", combo_size)
	_combo_label.add_theme_constant_override("line_spacing", 0)
	_combo_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2, 1.0))
	_combo_label.add_theme_font_override("font", load("res://assets/fonts/gothic_bitmap.fnt"))
	_combo_label.clip_contents = true
	_combo_label.visible = false
	ui.add_child(_combo_label)


## Setup saturation overlay for kill effect.
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
	canvas_layer.move_child(_saturation_overlay, canvas_layer.get_child_count() - 1)


## Update debug UI with current stats.
func _update_debug_ui() -> void:
	if GameManager == null:
		return

	if _difficulty_label:
		_difficulty_label.text = "Difficulty: " + DifficultyManager.get_difficulty_name()


## Called when an enemy dies.
func _on_enemy_died() -> void:
	_current_enemy_count -= 1
	_update_enemy_count_label()

	if _current_enemy_count <= 0 and not _has_retaliating_pacifists():
		print("All enemies eliminated! Labyrinth cleared!")
		_level_cleared = true
		call_deferred("_activate_exit_zone")


## Called when an enemy dies with special kill information.
func _on_enemy_died_with_info(is_ricochet_kill: bool, is_penetration_kill: bool, is_player_kill: bool = true) -> void:
	# Register kill with GameManager (Issue #1196: pass player kill flag to count only player kills).
	if GameManager:
		GameManager.register_kill(is_player_kill, is_penetration_kill)
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager and score_manager.has_method("register_kill"):
		score_manager.register_kill(is_ricochet_kill, is_penetration_kill)


## Issue #959: Called when an enemy becomes a pacifist via loudspeaker.
## Pacifists count as "killed" for level completion purposes.
## NOTE: Does NOT activate exit zone while any pacifist is still retaliating (attacking the player).
func _on_enemy_became_pacifist(enemy: Node) -> void:
	_current_enemy_count -= 1
	# Issue #959: Do not count pacifist again when it dies - already counted here
	if is_instance_valid(enemy) and enemy.died.is_connected(_on_enemy_died):
		enemy.died.disconnect(_on_enemy_died)
	_update_enemy_count_label()
	_log_to_file("[LabyrinthLevel] Enemy became pacifist - counting as eliminated")
	if _current_enemy_count <= 0 and not _has_retaliating_pacifists():
		print("All enemies eliminated or pacified! Labyrinth cleared!")
		_level_cleared = true
		call_deferred("_activate_exit_zone")


## Returns true if any enemy is a pacifist who is currently retaliating (attacking the player).
## Level should not complete while any enemy is still a threat (Issue #959).
func _has_retaliating_pacifists() -> bool:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and enemy.has_method("is_alive") and enemy.is_alive():
			if enemy.has_method("is_retaliating") and enemy.is_retaliating():
				return true
	return false


## Complete the level and show the score screen.
func _complete_level_with_score() -> void:
	if _level_completed:
		return
	_level_completed = true

	_disable_player_controls()

	if _exit_zone and _exit_zone.has_method("deactivate"):
		_exit_zone.deactivate()

	var replay_manager: Node = _get_or_create_replay_manager()
	if replay_manager:
		if replay_manager.has_method("StopRecording"):
			replay_manager.StopRecording()
			_log_to_file("Replay recording stopped")

		if replay_manager.has_method("HasReplay"):
			var has_replay: bool = replay_manager.HasReplay()
			var duration: float = 0.0
			if replay_manager.has_method("GetReplayDuration"):
				duration = replay_manager.GetReplayDuration()
			_log_to_file("Replay status: has_replay=%s, duration=%.2fs" % [has_replay, duration])
			print("[LabyrinthLevel] Replay status: has_replay=%s, duration=%.2fs" % [has_replay, duration])
	else:
		_log_to_file("ERROR: ReplayManager not found when completing level")
		print("[LabyrinthLevel] ERROR: ReplayManager not found!")

	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager and score_manager.has_method("complete_level"):
		var score_data: Dictionary = score_manager.complete_level()
		# Notify loudspeaker progression (Issue #959)
		var aim: Node = get_node_or_null("/root/ActiveItemManager")
		if aim and aim.has_method("notify_level_completed"):
			aim.notify_level_completed(score_data.get("kills", 0) > 0)
		_show_score_screen(score_data)
	else:
		_show_victory_message()


## Called when an enemy is hit (for accuracy tracking).
func _on_enemy_hit() -> void:
	if GameManager:
		GameManager.register_hit()


## Called when a shot is fired (from C# weapon).
func _on_shot_fired() -> void:
	if GameManager:
		GameManager.register_shot()


## Called when player ammo changes (GDScript Player).
func _on_player_ammo_changed(current: int, maximum: int) -> void:
	_update_ammo_label(current, maximum)
	if GameManager:
		GameManager.register_shot()


## Called when weapon ammo changes (C# Player).
func _on_weapon_ammo_changed(current_ammo: int, reserve_ammo: int) -> void:
	_update_ammo_label_magazine(current_ammo, reserve_ammo)
	if current_ammo <= 0 and reserve_ammo <= 0:
		if _current_enemy_count > 0 and not _game_over_shown:
			_show_game_over_message()


## Called when magazine inventory changes (C# Player).
func _on_magazines_changed(magazine_ammo_counts: Array) -> void:
	_update_magazines_label(magazine_ammo_counts)


## Called when shotgun shell count changes (during shell-by-shell reload).
## Bug fix #7: also updates the bolt-cycle hint to reflect remaining shells to load.
## Bug fix round 4: updates using full reload hint builder that tracks reload state.
func _on_shell_count_changed(shell_count: int, capacity: int) -> void:
	var reserve_ammo: int = 0
	var reload_state: int = 0
	if _player:
		var weapon = _player.get_node_or_null("Shotgun")
		if weapon != null and weapon.get("ReserveAmmo") != null:
			reserve_ammo = weapon.ReserveAmmo
		if weapon != null and weapon.get("ReloadState") != null:
			reload_state = int(weapon.ReloadState)
	_update_ammo_label_magazine(shell_count, reserve_ammo)
	# Bug fix #7 + round 4: update bolt-cycle hint with new shell count and current reload state.
	# Issue #1025: skip update when reload_state=0 (shot fired, not reloading) and the full-reload
	# hint is active — otherwise the hint resets to state=0 (open-bolt highlighted) on every shot.
	if _tutorial_hints.has(TUTORIAL_HINT_BOLT_CYCLE) and (reload_state != 0 or not _tutorial_shotgun_full_reload_active):
		var label: RichTextLabel = _tutorial_hints[TUTORIAL_HINT_BOLT_CYCLE]
		if is_instance_valid(label):
			label.text = _build_tutorial_shotgun_full_reload_hint_bbcode(reload_state)


## Called when player runs out of ammo in current magazine.
func _on_player_ammo_depleted() -> void:
	# Issue #1261: Do NOT broadcast ammo-empty to all enemies globally — that bypasses the
	# sound range system and lets out-of-earshot enemies react to the empty click.
	# The EMPTY_CLICK sound emitted below already sets player_ammo_empty on enemies within range.
	if _player:
		var sound_propagation: Node = get_node_or_null("/root/SoundPropagation")
		if sound_propagation and sound_propagation.has_method("emit_player_empty_click"):
			sound_propagation.emit_player_empty_click(_player.global_position, _player)

	if _player and _player.has_method("get_current_ammo"):
		var current_ammo: int = _player.get_current_ammo()
		if current_ammo <= 0 and _current_enemy_count > 0 and not _game_over_shown:
			_show_game_over_message()


## Called when player starts reloading.
func _on_player_reload_started() -> void:
	_broadcast_player_reloading(true)
	if _player:
		var sound_propagation: Node = get_node_or_null("/root/SoundPropagation")
		if sound_propagation and sound_propagation.has_method("emit_player_reload"):
			sound_propagation.emit_player_reload(_player.global_position, _player)


## Called when player finishes reloading.
func _on_player_reload_completed() -> void:
	_broadcast_player_reloading(false)
	_broadcast_player_ammo_empty(false)
	# Tutorial: handle reload step (Issue #808)
	_on_tutorial_reload_completed()


## Broadcast player reloading state to all enemies.
func _broadcast_player_reloading(is_reloading: bool) -> void:
	var enemies_node := get_node_or_null("Environment/Enemies")
	if enemies_node == null:
		return

	for enemy in enemies_node.get_children():
		if enemy.has_method("set_player_reloading"):
			enemy.set_player_reloading(is_reloading)


## Broadcast player ammo empty state to all enemies.
func _broadcast_player_ammo_empty(is_empty: bool) -> void:
	var enemies_node := get_node_or_null("Environment/Enemies")
	if enemies_node == null:
		return

	for enemy in enemies_node.get_children():
		if enemy.has_method("set_player_ammo_empty"):
			enemy.set_player_ammo_empty(is_empty)


## Called when player dies.
func _on_player_died() -> void:
	_show_death_message()
	if GameManager:
		await get_tree().create_timer(0.5).timeout
		# Issue #1334: After await, verify this node is still valid (scene may have reloaded)
		if not is_instance_valid(self):
			return
		GameManager.on_player_death()


## Called when GameManager signals enemy killed (for screen effect).
func _on_game_manager_enemy_killed() -> void:
	_show_saturation_effect()


## Shows the saturation effect when killing an enemy.
func _show_saturation_effect() -> void:
	if _saturation_overlay == null:
		return

	var tween := create_tween()
	tween.tween_property(_saturation_overlay, "color:a", SATURATION_INTENSITY, SATURATION_DURATION * 0.3)
	tween.tween_property(_saturation_overlay, "color:a", 0.0, SATURATION_DURATION * 0.7)


## Update the ammo label with color coding (simple format for GDScript Player).
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


## Update the ammo label with magazine format (for C# Player with weapon).
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


## Update the magazines label showing individual magazine ammo counts.
func _update_magazines_label(magazine_ammo_counts: Array) -> void:
	if _magazines_label == null:
		return

	var weapon = null
	if _player:
		weapon = _player.get_node_or_null("Shotgun")
		if weapon == null:
			weapon = _player.get_node_or_null("MiniUzi")
		if weapon == null:
			weapon = _player.get_node_or_null("SilencedPistol")
		if weapon == null:
			weapon = _player.get_node_or_null("SniperRifle")
		if weapon == null:
			weapon = _player.get_node_or_null("AssaultRifle")
		if weapon == null:
			weapon = _player.get_node_or_null("AKGL")
		if weapon == null:
			weapon = _player.get_node_or_null("Revolver")
		if weapon == null:
			weapon = _player.get_node_or_null("MakarovPM")

	if weapon != null and weapon.get("UsesTubeMagazine") == true:
		_magazines_label.visible = false
		return
	if weapon != null and weapon.has_signal("CylinderStateChanged"):
		_magazines_label.visible = false
		return
	_magazines_label.visible = true

	if magazine_ammo_counts.is_empty():
		_magazines_label.text = "MAGS: -"
		return

	# Get magazine capacities to distinguish full vs partial spares
	var mag_max_counts: Array = []
	if weapon != null and weapon.has_method("GetMagazineMaxCounts"):
		mag_max_counts = Array(weapon.GetMagazineMaxCounts())

	var parts: Array = []
	# Current magazine always shown in brackets
	parts.append("[%d]" % magazine_ammo_counts[0])

	# Spare magazines: skip empty, show partial individually, abbreviate full as + xN
	var full_spare_count: int = 0
	for i in range(1, magazine_ammo_counts.size()):
		var ammo: int = magazine_ammo_counts[i]
		if ammo <= 0:
			continue
		var cap: int = mag_max_counts[i] if i < mag_max_counts.size() else 0
		if cap > 0 and ammo >= cap:
			full_spare_count += 1
		else:
			parts.append("%d" % ammo)

	if full_spare_count > 0:
		parts.append("+ x%d" % full_spare_count)

	_magazines_label.text = "MAGS: " + " | ".join(parts)


## Update the enemy count label in UI.
func _update_enemy_count_label() -> void:
	if _enemy_count_label:
		_enemy_count_label.text = "Enemies: %d" % _current_enemy_count


## Show death message when player dies.
func _show_death_message() -> void:
	if _game_over_shown:
		return

	_game_over_shown = true

	var ui := get_node_or_null("CanvasLayer/UI")
	if ui == null:
		return

	var death_label := Label.new()
	death_label.name = "DeathLabel"
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


## Show victory message when all enemies are eliminated.
func _show_victory_message() -> void:
	var ui := get_node_or_null("CanvasLayer/UI")
	if ui == null:
		return

	var victory_label := Label.new()
	victory_label.name = "VictoryLabel"
	victory_label.text = "LABYRINTH CLEARED!"
	victory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	victory_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	victory_label.add_theme_font_size_override("font_size", 48)
	victory_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3, 1.0))

	victory_label.set_anchors_preset(Control.PRESET_CENTER)
	victory_label.offset_left = -200
	victory_label.offset_right = 200
	victory_label.offset_top = -50
	victory_label.offset_bottom = 50

	ui.add_child(victory_label)

	var stats_label := Label.new()
	stats_label.name = "StatsLabel"
	if GameManager:
		stats_label.text = "Kills: %d | Accuracy: %.1f%%" % [GameManager.kills, GameManager.get_accuracy()]
	else:
		stats_label.text = ""
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stats_label.add_theme_font_size_override("font_size", 24)
	stats_label.add_theme_color_override("font_color", Color(0.8, 0.9, 0.8, 1.0))

	stats_label.set_anchors_preset(Control.PRESET_CENTER)
	stats_label.offset_left = -200
	stats_label.offset_right = 200
	stats_label.offset_top = 50
	stats_label.offset_bottom = 100

	ui.add_child(stats_label)


## Show the animated score screen with Hotline Miami 2 style effects.
func _show_score_screen(score_data: Dictionary) -> void:
	var ui := get_node_or_null("CanvasLayer/UI")
	if ui == null:
		_show_victory_message()
		return

	var animated_score_screen_script = load("res://scripts/ui/animated_score_screen.gd")
	if animated_score_screen_script:
		var score_screen = animated_score_screen_script.new()
		add_child(score_screen)
		score_screen.animation_completed.connect(_on_score_animation_completed)
		score_screen.show_animated_score(ui, score_data)
	else:
		_show_fallback_score_screen(ui, score_data)


## Called when the animated score screen finishes all animations.
func _on_score_animation_completed(container: VBoxContainer) -> void:
	_add_score_screen_buttons(container)


## Fallback score screen if animated component is not available.
func _show_fallback_score_screen(ui: Control, score_data: Dictionary) -> void:
	var gothic_font = load("res://assets/fonts/gothic_bitmap.fnt")
	var _font_loaded := gothic_font != null

	var background := ColorRect.new()
	background.name = "ScoreBackground"
	background.color = Color(0.0, 0.0, 0.0, 0.7)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(background)

	var container := VBoxContainer.new()
	container.name = "ScoreContainer"
	container.set_anchors_preset(Control.PRESET_CENTER)
	container.offset_left = -300
	container.offset_right = 300
	container.offset_top = -200
	container.offset_bottom = 200
	container.add_theme_constant_override("separation", 8)
	ui.add_child(container)

	var title_label := Label.new()
	title_label.text = "LEVEL CLEARED!"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 42)
	title_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3, 1.0))
	container.add_child(title_label)

	var rank_label := Label.new()
	rank_label.text = "RANK: %s" % score_data.rank
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_label.add_theme_font_size_override("font_size", 64)
	rank_label.add_theme_color_override("font_color", _get_rank_color(score_data.rank))
	if _font_loaded:
		rank_label.add_theme_font_override("font", gothic_font)
	container.add_child(rank_label)

	var total_label := Label.new()
	total_label.text = "TOTAL SCORE: %d" % score_data.total_score
	total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	total_label.add_theme_font_size_override("font_size", 32)
	total_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 1.0))
	container.add_child(total_label)

	_add_score_screen_buttons(container)


## Adds Restart, Next Level, Level Select, and Watch Replay buttons to a score screen container.
func _add_score_screen_buttons(container: VBoxContainer) -> void:
	_score_shown = true

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 10
	container.add_child(spacer)

	var buttons_container := VBoxContainer.new()
	buttons_container.name = "ButtonsContainer"
	buttons_container.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons_container.add_theme_constant_override("separation", 10)
	container.add_child(buttons_container)

	var next_level_path: String = _get_next_level_path()
	if next_level_path != "":
		var next_button := Button.new()
		next_button.name = "NextLevelButton"
		next_button.text = "→ Next Level"
		next_button.custom_minimum_size = Vector2(200, 40)
		next_button.add_theme_font_size_override("font_size", 18)
		next_button.pressed.connect(_on_next_level_pressed.bind(next_level_path))
		buttons_container.add_child(next_button)

	var restart_button := Button.new()
	restart_button.name = "RestartButton"
	restart_button.text = "↻ Restart (Q)"
	restart_button.custom_minimum_size = Vector2(200, 40)
	restart_button.add_theme_font_size_override("font_size", 18)
	restart_button.pressed.connect(_on_restart_pressed)
	buttons_container.add_child(restart_button)

	var level_select_button := Button.new()
	level_select_button.name = "LevelSelectButton"
	level_select_button.text = "☰ Level Select"
	level_select_button.custom_minimum_size = Vector2(200, 40)
	level_select_button.add_theme_font_size_override("font_size", 18)
	level_select_button.pressed.connect(_on_level_select_pressed)
	buttons_container.add_child(level_select_button)

	# Watch Replay button (Issue #807: only shown if replay viewing is enabled in experimental settings)
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	var replay_enabled: bool = experimental_settings != null and experimental_settings.has_method("is_replay_enabled") and experimental_settings.is_replay_enabled()

	if replay_enabled:
		var replay_button := Button.new()
		replay_button.name = "ReplayButton"
		replay_button.text = "▶ Watch Replay (W)"
		replay_button.custom_minimum_size = Vector2(200, 40)
		replay_button.add_theme_font_size_override("font_size", 18)

		var replay_manager: Node = _get_or_create_replay_manager()
		var has_replay_data: bool = replay_manager != null and replay_manager.has_method("HasReplay") and replay_manager.HasReplay()

		if has_replay_data:
			replay_button.pressed.connect(_on_watch_replay_pressed)
			_log_to_file("Watch Replay button created (replay data available)")
		else:
			replay_button.disabled = true
			replay_button.text = "▶ Watch Replay (W) - no data"
			replay_button.tooltip_text = "Replay recording was not available for this session"
			_log_to_file("Watch Replay button created (disabled - no replay data)")

		buttons_container.add_child(replay_button)
	else:
		_log_to_file("Watch Replay button not shown (replay viewing disabled in experimental settings)")

	# Armory button (Issue #897: shown highlighted when items are available to unlock; Issue #1622: always shown)
	var unlock_manager: Node = get_node_or_null("/root/UnlockManager")
	var armory_button := Button.new()
	armory_button.name = "ArmoryButton"
	armory_button.pressed.connect(_on_armory_button_pressed)
	buttons_container.add_child(armory_button)
	var has_available_unlock: bool = unlock_manager != null and unlock_manager.has_method("has_any_available_unlock") and unlock_manager.has_any_available_unlock()
	if has_available_unlock:
		armory_button.text = "★ Armory — Items Available!"
		armory_button.custom_minimum_size = Vector2(200, 40)
		armory_button.add_theme_font_size_override("font_size", 18)
		armory_button.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0))
		var armory_style := StyleBoxFlat.new()
		armory_style.bg_color = Color(0.28, 0.22, 0.08, 0.9)
		armory_style.border_color = Color(1.0, 0.8, 0.1, 1.0)
		armory_style.border_width_left = 2
		armory_style.border_width_right = 2
		armory_style.border_width_top = 2
		armory_style.border_width_bottom = 2
		armory_style.corner_radius_top_left = 4
		armory_style.corner_radius_top_right = 4
		armory_style.corner_radius_bottom_left = 4
		armory_style.corner_radius_bottom_right = 4
		armory_button.add_theme_stylebox_override("normal", armory_style)
		# Add gold shine shader overlay (Issue #1536).
		var _armory_shine_shader := load("res://scripts/shaders/gold_shine.gdshader") as Shader
		if _armory_shine_shader:
			var _armory_shine_mat := ShaderMaterial.new()
			_armory_shine_mat.shader = _armory_shine_shader
			var _armory_shine_overlay := ColorRect.new()
			_armory_shine_overlay.name = "ArmoryGoldShineOverlay"
			_armory_shine_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			_armory_shine_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_armory_shine_overlay.material = _armory_shine_mat
			armory_button.add_child(_armory_shine_overlay)
	else:
		armory_button.text = "Armory"

	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)

	if next_level_path != "":
		buttons_container.get_node("NextLevelButton").grab_focus()
	else:
		restart_button.grab_focus()


## Get the color for a given rank.
func _get_rank_color(rank: String) -> Color:
	match rank:
		"S":
			return Color(1.0, 0.84, 0.0, 1.0)
		"A+":
			return Color(0.0, 1.0, 0.5, 1.0)
		"A":
			return Color(0.2, 0.8, 0.2, 1.0)
		"B":
			return Color(0.3, 0.7, 1.0, 1.0)
		"C":
			return Color(1.0, 1.0, 1.0, 1.0)
		"D":
			return Color(1.0, 0.6, 0.2, 1.0)
		"F":
			return Color(1.0, 0.2, 0.2, 1.0)
		_:
			return Color(1.0, 1.0, 1.0, 1.0)


## Show game over message when player runs out of ammo with enemies remaining.
func _show_game_over_message() -> void:
	_game_over_shown = true

	var ui := get_node_or_null("CanvasLayer/UI")
	if ui == null:
		return

	var game_over_label := Label.new()
	game_over_label.name = "GameOverLabel"
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


## Setup the weapon based on GameManager's selected weapon.
func _setup_selected_weapon() -> void:
	if _player == null:
		return

	var selected_weapon_id: String = "makarov_pm"
	if GameManager:
		selected_weapon_id = GameManager.get_selected_weapon()

	_log_to_file("Setting up weapon: %s" % selected_weapon_id)

	if selected_weapon_id != "makarov_pm":
		# Bug fix round 6: include ak_gl and revolver so the early-return check applies.
		# Without these entries the check was always skipped for AKGL/Revolver, causing
		# _setup_selected_weapon() to add a second, duplicate weapon node even though
		# the C# Player._Ready() had already added the correct one via
		# ApplySelectedWeaponFromGameManager(). Godot auto-renamed the duplicate (e.g.
		# "AKGL2"), so _setup_player_tracking() then connected all signals (AmmoChanged,
		# Fired, etc.) to the first (unused) AKGL while the player actually fired the
		# duplicate. This caused tutorial hint shot-counters and ammo labels to never
		# update, making tutorial lines invisible and the counter broken for both weapons.
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
				_log_to_file("%s already equipped by C# Player - applying labyrinth ammo config" % expected_name)
				_configure_labyrinth_weapon_ammo(existing_weapon, selected_weapon_id)
				return

	if selected_weapon_id == "shotgun":
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov:
			makarov.queue_free()
			print("LabyrinthLevel: Removed default MakarovPM")

		var shotgun_scene = load("res://scenes/weapons/csharp/Shotgun.tscn")
		if shotgun_scene:
			var shotgun = shotgun_scene.instantiate()
			shotgun.name = "Shotgun"
			_player.add_child(shotgun)

			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(shotgun)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = shotgun

			print("LabyrinthLevel: Shotgun equipped successfully")
		else:
			push_error("LabyrinthLevel: Failed to load Shotgun scene!")
	elif selected_weapon_id == "mini_uzi":
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov:
			makarov.queue_free()
			print("LabyrinthLevel: Removed default MakarovPM")

		var mini_uzi_scene = load("res://scenes/weapons/csharp/MiniUzi.tscn")
		if mini_uzi_scene:
			var mini_uzi = mini_uzi_scene.instantiate()
			mini_uzi.name = "MiniUzi"

			if mini_uzi.get("StartingMagazineCount") != null:
				mini_uzi.StartingMagazineCount = 2
				print("LabyrinthLevel: Mini UZI StartingMagazineCount set to 2 (before initialization)")

			_player.add_child(mini_uzi)

			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(mini_uzi)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = mini_uzi

			print("LabyrinthLevel: Mini UZI equipped successfully")
		else:
			push_error("LabyrinthLevel: Failed to load MiniUzi scene!")
	elif selected_weapon_id == "silenced_pistol":
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov:
			makarov.queue_free()
			print("LabyrinthLevel: Removed default MakarovPM")

		var pistol_scene = load("res://scenes/weapons/csharp/SilencedPistol.tscn")
		if pistol_scene:
			var pistol = pistol_scene.instantiate()
			pistol.name = "SilencedPistol"
			_player.add_child(pistol)

			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(pistol)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = pistol

			print("LabyrinthLevel: Silenced Pistol equipped successfully")
		else:
			push_error("LabyrinthLevel: Failed to load SilencedPistol scene!")
	elif selected_weapon_id == "sniper":
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov:
			makarov.queue_free()
			print("LabyrinthLevel: Removed default MakarovPM")

		var sniper_scene = load("res://scenes/weapons/csharp/SniperRifle.tscn")
		if sniper_scene:
			var sniper = sniper_scene.instantiate()
			sniper.name = "SniperRifle"
			_player.add_child(sniper)

			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(sniper)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = sniper

			print("LabyrinthLevel: ASVK Sniper Rifle equipped successfully")
		else:
			push_error("LabyrinthLevel: Failed to load SniperRifle scene!")
	elif selected_weapon_id == "m16":
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov:
			makarov.queue_free()
			print("LabyrinthLevel: Removed default MakarovPM")

		var m16_scene = load("res://scenes/weapons/csharp/AssaultRifle.tscn")
		if m16_scene:
			var m16 = m16_scene.instantiate()
			m16.name = "AssaultRifle"
			_player.add_child(m16)

			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(m16)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = m16

			var base_magazines: int = 2
			var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
			if difficulty_manager:
				var ammo_multiplier: int = difficulty_manager.get_ammo_multiplier()
				if ammo_multiplier > 1:
					base_magazines *= ammo_multiplier
					print("LabyrinthLevel: Power Fantasy mode - M16 magazines multiplied by %dx" % ammo_multiplier)
			if m16.has_method("ReinitializeMagazines"):
				m16.ReinitializeMagazines(base_magazines, true)
				print("LabyrinthLevel: M16 magazines reinitialized to %d" % base_magazines)

			# Reapply auto-reload magazine size reduction if active (Issue #1067).
			if _player != null and _player.has_method("ApplyAutoReloadAfterLevelAmmoConfig"):
				_player.ApplyAutoReloadAfterLevelAmmoConfig()

			print("LabyrinthLevel: M16 Assault Rifle equipped successfully")
		else:
			push_error("LabyrinthLevel: Failed to load AssaultRifle scene!")
	# Bug fix round 4: AK + GL support on Lab map (was missing)
	elif selected_weapon_id == "ak_gl":
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov:
			makarov.queue_free()
			print("LabyrinthLevel: Removed default MakarovPM")

		var akgl_scene = load("res://scenes/weapons/csharp/AKGL.tscn")
		if akgl_scene:
			var akgl = akgl_scene.instantiate()
			akgl.name = "AKGL"
			_player.add_child(akgl)

			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(akgl)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = akgl

			_configure_labyrinth_weapon_ammo(akgl, "ak_gl")
			print("LabyrinthLevel: AK + GL equipped successfully")
		else:
			push_error("LabyrinthLevel: Failed to load AKGL scene!")
	# Bug fix round 4: Revolver support on Lab map (was missing)
	elif selected_weapon_id == "revolver":
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov:
			makarov.queue_free()
			print("LabyrinthLevel: Removed default MakarovPM")

		var revolver_scene = load("res://scenes/weapons/csharp/Revolver.tscn")
		if revolver_scene:
			var revolver = revolver_scene.instantiate()
			revolver.name = "Revolver"
			_player.add_child(revolver)

			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(revolver)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = revolver

			print("LabyrinthLevel: RSh-12 Revolver equipped successfully")
		else:
			push_error("LabyrinthLevel: Failed to load Revolver scene!")
	else:
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov and _player.get("CurrentWeapon") == null:
			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(makarov)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = makarov

			_configure_makarov_pm_ammo(makarov)


## Handle W key shortcut for Watch Replay when score is shown.
func _unhandled_input(event: InputEvent) -> void:
	if not _score_shown:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_W:
			_on_watch_replay_pressed()


## Called when the Watch Replay button is pressed (or W key).
func _on_watch_replay_pressed() -> void:
	_log_to_file("Watch Replay triggered")
	var replay_manager: Node = _get_or_create_replay_manager()
	if replay_manager and replay_manager.has_method("HasReplay") and replay_manager.HasReplay():
		if replay_manager.has_method("StartPlayback"):
			replay_manager.StartPlayback(self)
	else:
		_log_to_file("Watch Replay: no replay data available")


## Called when the Restart button is pressed.
func _on_restart_pressed() -> void:
	_log_to_file("Restart button pressed")
	if GameManager:
		GameManager.restart_scene()
	else:
		get_tree().reload_current_scene()


## Called when the Next Level button is pressed.
func _on_next_level_pressed(level_path: String) -> void:
	_log_to_file("Next Level button pressed: %s" % level_path)
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
	var error := get_tree().change_scene_to_file(level_path)
	if error != OK:
		_log_to_file("ERROR: Failed to load next level: %s" % level_path)
		Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)


## Called when the Level Select button is pressed.
func _on_level_select_pressed() -> void:
	_log_to_file("Level Select button pressed")
	var levels_menu_script = load("res://scripts/ui/levels_menu.gd")
	if levels_menu_script:
		var levels_menu = CanvasLayer.new()
		levels_menu.set_script(levels_menu_script)
		levels_menu.layer = 100
		get_tree().root.add_child(levels_menu)
		levels_menu.back_pressed.connect(func(): levels_menu.queue_free())
	else:
		_log_to_file("ERROR: Could not load levels menu script")


## Called when the Armory button is pressed on the score screen (Issue #897).
func _on_armory_button_pressed() -> void:
	_log_to_file("Armory button pressed from score screen")
	var armory_menu_scene = load("res://scenes/ui/ArmoryMenu.tscn")
	if armory_menu_scene:
		var armory_menu = armory_menu_scene.instantiate()
		armory_menu.layer = 100
		# Issue #1006: Mark as opened from score screen to prevent level restart on Apply
		armory_menu.opened_from_score_screen = true
		get_tree().root.add_child(armory_menu)
		armory_menu.back_pressed.connect(func():
			armory_menu.queue_free()
			# Issue #1050: Remove gold highlight from armory button if all available items have been opened
			var unlock_manager: Node = get_node_or_null("/root/UnlockManager")
			if unlock_manager == null or not unlock_manager.has_method("has_any_available_unlock") or not unlock_manager.has_any_available_unlock():
				_remove_armory_button_gold_style()
		)
		armory_menu.apply_pressed_from_score_screen.connect(func():
			# Issue #1050: Remove gold highlight from armory button if all available items have been opened
			var unlock_manager: Node = get_node_or_null("/root/UnlockManager")
			if unlock_manager == null or not unlock_manager.has_method("has_any_available_unlock") or not unlock_manager.has_any_available_unlock():
				_remove_armory_button_gold_style()
		)
	else:
		_log_to_file("ERROR: Could not load armory menu scene")


## Issue #1050: Remove gold highlight from the ArmoryButton when no items remain to unlock.
## The button stays visible but loses its gold styling and reverts to plain "Armory" text.
func _remove_armory_button_gold_style() -> void:
	var armory_btn := get_tree().current_scene.find_child("ArmoryButton", true, false)
	if armory_btn:
		armory_btn.text = "Armory"
		armory_btn.remove_theme_color_override("font_color")
		armory_btn.remove_theme_stylebox_override("normal")
		# Issue #1582: Remove gold shine overlay added by issue #1536
		var shine_overlay := armory_btn.find_child("ArmoryGoldShineOverlay", true, false)
		if shine_overlay:
			shine_overlay.queue_free()


## Get the next level path based on the level ordering from LevelsMenu.
func _get_next_level_path() -> String:
	var current_scene_path: String = ""
	var current_scene: Node = get_tree().current_scene
	if current_scene and current_scene.scene_file_path:
		current_scene_path = current_scene.scene_file_path

	# Level ordering (matching LevelsMenu.LEVELS)
	var level_paths: Array[String] = [
		"res://scenes/levels/LabyrinthLevel.tscn",
		"res://scenes/levels/BuildingLevel.tscn",
		"res://scenes/levels/TestTier.tscn",
		"res://scenes/levels/CastleLevel.tscn",
		"res://scenes/levels/RevolverLevel.tscn",
		"res://scenes/levels/CityLevel.tscn",
		"res://scenes/levels/BeachLevel.tscn",
		"res://scenes/levels/DocksLevel.tscn",
		"res://scenes/levels/FactoryLevel.tscn",
		"res://scenes/levels/DecadenceLevel.tscn",
		"res://scenes/levels/Labyrinth2Level.tscn",
		"res://scenes/levels/SewerLevel.tscn",
		"res://scenes/levels/WinterForestLevel.tscn",
		"res://scenes/levels/RailwayStationLevel.tscn",
	]

	for i in range(level_paths.size()):
		if level_paths[i] == current_scene_path:
			if i + 1 < level_paths.size():
				return level_paths[i + 1]
			return ""

	return ""


## Disable player controls after level completion (score screen shown).
func _disable_player_controls() -> void:
	if _player == null or not is_instance_valid(_player):
		return

	_player.set_physics_process(false)
	_player.set_process(false)
	_player.set_process_input(false)
	_player.set_process_unhandled_input(false)

	if _player is CharacterBody2D:
		_player.velocity = Vector2.ZERO

	_log_to_file("Player controls disabled (level completed)")


## ============================================================
## Tutorial hints for the Laboratory level (Issue #808)
## Weapon-dependent hints mirroring tutorial_level.gd behavior.
## No walk/shoot hints. Shows: reload (weapon-specific), hammer cock (revolver),
## bolt cycle (sniper), and grenade throw — same as Tutorial level.
## ============================================================


## Create and show weapon-dependent tutorial hints at level start (Issue #808, #945).
## Mirrors tutorial_level.gd: shows reload + weapon-feature + grenade hints.
## No movement or shooting hints (owner request).
## Issue #945: Reload hint is delayed until player fires 2 shots.
## Bug fix #3: Revolver hammer-cock hint is shown from the very start (on weapon pickup).
func _setup_tutorial_hints() -> void:
	_tutorial_step = TutorialStep.RELOAD
	print("[LabyrinthLevel] Tutorial hints initialised — reload hint will appear after 2 shots (Issue #945)")
	# Bug fix #3: Show hammer-cock hint immediately for revolver
	if _tutorial_has_revolver:
		var canvas_layer := get_node_or_null("CanvasLayer")
		if canvas_layer:
			_add_tutorial_hint(TUTORIAL_HINT_HAMMER_COCK, "[color=#ff4444][ПКМ][/color] Взведи курок", canvas_layer)
	# Issue #998: Show scope hint from the very start for sniper rifle.
	if _tutorial_has_sniper_rifle:
		var canvas_layer := get_node_or_null("CanvasLayer")
		if canvas_layer:
			_add_tutorial_hint(TUTORIAL_HINT_SCOPE, "[color=#ff4444][ПКМ][/color] Прицелься через оптику", canvas_layer)


## Called when player's weapon fires a shot (Issue #945).
## Counts shots and reveals hints based on shot count:
##   - Bolt-cycle hint (sniper/shotgun) appears after 1st shot.
##   - Reload hint appears after 2nd shot.
func _on_tutorial_weapon_fired() -> void:
	_tutorial_shots_fired += 1
	print("[LabyrinthLevel] Tutorial shot fired (%d total)" % _tutorial_shots_fired)

	# Bug fix #4: bolt-cycle hint (sniper bolt-action, shotgun bolt) shown after 1st shot.
	if _tutorial_shots_fired >= 1 and not _tutorial_bolt_cycle_hint_revealed:
		if _tutorial_has_sniper_rifle or _tutorial_has_shotgun:
			_tutorial_bolt_cycle_hint_revealed = true
			_reveal_tutorial_bolt_cycle_hint()

	if not _tutorial_reload_hint_revealed and _tutorial_shots_fired >= 2:
		_tutorial_reload_hint_revealed = true
		_reveal_tutorial_reload_hint()


## Reveal the bolt-cycle hint after the 1st shot (sniper/shotgun only).
## Bug fix #4: Bolt-cycle hint shown earlier, separately from the 2-shot reload hint.
## Bug fix round 4: Shotgun shows simple pump-action hint, not full reload sequence.
func _reveal_tutorial_bolt_cycle_hint() -> void:
	if _tutorial_step != TutorialStep.RELOAD:
		return

	print("[LabyrinthLevel] 1st shot fired — revealing bolt-cycle hint")
	var canvas_layer := get_node_or_null("CanvasLayer")
	if canvas_layer == null:
		return

	if _tutorial_has_sniper_rifle:
		if not _tutorial_hints.has(TUTORIAL_HINT_BOLT_CYCLE):
			# Bug fix #4: show 4 separate steps. Bug fix #3: first step highlighted red (step=0).
			_add_tutorial_hint(TUTORIAL_HINT_BOLT_CYCLE, _build_tutorial_sniper_bolt_hint_bbcode(0), canvas_layer)
	elif _tutorial_has_shotgun:
		# Bug fix round 4: show pump-action hint (open/close bolt between shots), NOT full reload.
		if not _tutorial_hints.has(TUTORIAL_HINT_BOLT_CYCLE):
			_add_tutorial_hint(TUTORIAL_HINT_BOLT_CYCLE,
				"[color=#ff4444][ПКМ↑][/color] [color=#888888][ПКМ↓][/color] Передёрни затвор",
				canvas_layer)


## Reveal the reload-related hints after the player has fired 2 shots (Issue #945).
func _reveal_tutorial_reload_hint() -> void:
	if _tutorial_step != TutorialStep.RELOAD:
		return

	print("[LabyrinthLevel] 2 shots fired — revealing reload hint")
	var canvas_layer := get_node_or_null("CanvasLayer")
	if canvas_layer == null:
		return

	_add_tutorial_reload_hints(canvas_layer)


## Called when the reload sequence progresses (Issue #945).
## Updates the reload hint to highlight the NEXT button in red.
## Bug fix round 4: revolver hint now updates step-by-step as reload progresses.
## Shotgun uses ActionStateChanged for step-by-step highlighting.
func _on_tutorial_reload_sequence_progress(step: int, total: int) -> void:
	# Shotgun uses ActionStateChanged — skip
	if _tutorial_has_shotgun:
		return

	if not _tutorial_hints.has(TUTORIAL_HINT_RELOAD):
		return

	# Bug fix round 4: revolver step highlighting update
	if _tutorial_has_revolver:
		var new_text := _build_tutorial_revolver_reload_hint_bbcode(step)
		var label: RichTextLabel = _tutorial_hints[TUTORIAL_HINT_RELOAD]
		if is_instance_valid(label):
			label.text = new_text
		print("[LabyrinthLevel] Revolver reload sequence step %d/%d — hint updated" % [step, total])
		return

	var new_text := _build_tutorial_reload_hint_bbcode(step, total)
	if new_text.is_empty():
		return
	var label: RichTextLabel = _tutorial_hints[TUTORIAL_HINT_RELOAD]
	if is_instance_valid(label):
		label.text = new_text
	print("[LabyrinthLevel] Reload sequence step %d/%d — hint updated" % [step, total])


## Build BBCode text for the reload hint based on current step (Issue #945).
## The NEXT required button is highlighted in red; completed steps are shown in grey.
## Bug fix #2: `step` is the LAST COMPLETED step (0 = nothing done yet, 1 = first press done, etc.).
##   So we highlight step+1 as the next action to perform.
## Bug fix #5: Revolver and shotgun use separate hint builders.
## Issue #944: Strikethrough is now animated via Line2D, not BBCode [s] tags.
func _build_tutorial_reload_hint_bbcode(step: int, total: int) -> String:
	# Guard: shotgun uses static/ActionState-based hints
	if _tutorial_has_shotgun:
		return ""

	if _tutorial_has_makarov_pm or (not _tutorial_has_sniper_rifle and total <= 2):
		# Makarov PM / 2-step reload: R -> R
		# step=0 → next is R (first); step=1 → next is R (second); step=2 → done
		match step:
			0:
				return "[color=#ff4444][R][/color] [color=#888888][R][/color] Перезарядись"
			1:
				# Step 1 completed: extend strikethrough to 25%
				_extend_tutorial_hint_strikethrough(TUTORIAL_HINT_RELOAD, 0.25)
				return "[color=#888888][R][/color] [color=#ff4444][R][/color] Перезарядись"
			_:
				# All steps done: extend strikethrough to cover both [R] keys (~50%)
				_extend_tutorial_hint_strikethrough(TUTORIAL_HINT_RELOAD, 0.5)
				return "[color=#888888][R] [R][/color] Перезарядись"
	else:
		# Standard 3-step reload: R -> F -> R
		# step=0 → next is R; step=1 → next is F; step=2 → next is R (final); step=3 → done
		match step:
			0:
				return "[color=#ff4444][R][/color] [color=#888888][F] [R][/color] Перезарядись"
			1:
				# Step 1 completed: extend strikethrough to ~17%
				_extend_tutorial_hint_strikethrough(TUTORIAL_HINT_RELOAD, 0.17)
				return "[color=#888888][R][/color] [color=#ff4444][F][/color] [color=#888888][R][/color] Перезарядись"
			2:
				# Step 2 completed: extend strikethrough to ~33%
				_extend_tutorial_hint_strikethrough(TUTORIAL_HINT_RELOAD, 0.33)
				return "[color=#888888][R] [F][/color] [color=#ff4444][R][/color] Перезарядись"
			_:
				# All steps done: extend strikethrough to ~50%
				_extend_tutorial_hint_strikethrough(TUTORIAL_HINT_RELOAD, 0.5)
				return "[color=#888888][R] [F] [R][/color] Перезарядись"


## Get the unique color for a tutorial hint by its key (Issue #945).
func _get_tutorial_hint_color(hint_key: String) -> Color:
	match hint_key:
		TUTORIAL_HINT_RELOAD:
			return TUTORIAL_HINT_COLOR_RELOAD
		TUTORIAL_HINT_GRENADE:
			return TUTORIAL_HINT_COLOR_GRENADE
		TUTORIAL_HINT_BOLT_CYCLE:
			return TUTORIAL_HINT_COLOR_BOLT_CYCLE
		TUTORIAL_HINT_HAMMER_COCK:
			return TUTORIAL_HINT_COLOR_HAMMER_COCK
		TUTORIAL_HINT_GRENADE_LAUNCHER:
			return TUTORIAL_HINT_COLOR_GRENADE_LAUNCHER
		TUTORIAL_HINT_FIRE_MODE:
			return TUTORIAL_HINT_COLOR_FIRE_MODE  # Bug fix round 5
		TUTORIAL_HINT_SCOPE:
			return TUTORIAL_HINT_COLOR_SCOPE  # Issue #998
		_:
			return Color(1.0, 1.0, 0.3, 1.0)  # Default yellow fallback


## Add reload-related hints for the current weapon type.
## Mirrors _add_reload_hints() from tutorial_level.gd.
## Issue #945: Uses BBCode with the first step highlighted in red.
## Bug fix #5: Grenade hint is shown AFTER reload disappears, NOT simultaneously.
## Bug fix round 4: Shotgun shows full reload hint (replacing pump-action hint) after 2nd shot.
## Bug fix: Sniper bolt-cycle hint is NOT added here (it appears after 1st shot).
## Revolver hammer-cock hint is NOT added here (shown from start).
func _add_tutorial_reload_hints(canvas_layer: Node) -> void:
	if _tutorial_has_shotgun:
		# Bug fix round 4: replace the pump-action hint with the full reload hint after 2nd shot.
		# Bug fix round 5: set flag to block ActionStateChanged from re-showing pump hint.
		_tutorial_shotgun_full_reload_active = true
		_dismiss_tutorial_hint(TUTORIAL_HINT_BOLT_CYCLE)
		_add_tutorial_hint(TUTORIAL_HINT_BOLT_CYCLE, _build_tutorial_shotgun_full_reload_hint_bbcode(0), canvas_layer)
	elif _tutorial_has_sniper_rifle:
		# Sniper: magazine swap reload hint. Bolt-cycle hint already shown after 1st shot.
		_add_tutorial_hint(TUTORIAL_HINT_RELOAD, _build_tutorial_reload_hint_bbcode(0, 3), canvas_layer)
	elif _tutorial_has_revolver:
		# Revolver: cylinder reload hint. Hammer-cock hint is shown from start (Bug fix #3).
		_add_tutorial_hint(TUTORIAL_HINT_RELOAD,
			"[color=#ff4444][R открыть][/color] [color=#888888][ПКМ↑ патрон] [скролл] [R закрыть][/color]",
			canvas_layer)
	elif _tutorial_has_makarov_pm:
		# Makarov PM uses simplified R->R reload. Initial text = step 0.
		_add_tutorial_hint(TUTORIAL_HINT_RELOAD, _build_tutorial_reload_hint_bbcode(0, 2), canvas_layer)
	else:
		# Standard R->F->R. Initial text = step 0.
		_add_tutorial_hint(TUTORIAL_HINT_RELOAD, _build_tutorial_reload_hint_bbcode(0, 3), canvas_layer)

	# Bug fix #5: grenade hint shown AFTER reload disappears, not simultaneously.


## Called when sniper bolt step changes (Issue #808 - Lab sniper tutorial).
## Bug fix #3: dynamically updates bolt-cycle hint text to highlight the NEXT step in red.
## Bug fix round 4: bolt-cycle completion only dismisses HINT_BOLT_CYCLE; does NOT advance
## the tutorial step. The magazine reload (R→F→R) must complete first.
func _on_tutorial_sniper_bolt_step_changed(step: int, total_steps: int) -> void:
	if _tutorial_step != TutorialStep.RELOAD:
		return
	# Bug fix #3: update bolt-cycle hint text step-by-step
	if _tutorial_hints.has(TUTORIAL_HINT_BOLT_CYCLE):
		var label: RichTextLabel = _tutorial_hints[TUTORIAL_HINT_BOLT_CYCLE]
		if is_instance_valid(label):
			label.text = _build_tutorial_sniper_bolt_hint_bbcode(step)
	if step >= total_steps and not _tutorial_sniper_bolt_cycled:
		_tutorial_sniper_bolt_cycled = true
		print("[LabyrinthLevel] Sniper bolt cycling completed — dismissing bolt-cycle hint")
		# Dismiss bolt-cycle hint only; keep reload hint if visible.
		# Bug fix round 4: do NOT set _tutorial_has_reloaded or advance tutorial step here.
		# The magazine reload (R→F→R) via _on_tutorial_reload_completed handles advancement.
		_dismiss_tutorial_hint(TUTORIAL_HINT_BOLT_CYCLE)
		# Reset for next shot
		_tutorial_sniper_bolt_cycled = false


## Called when revolver hammer is cocked — dismisses hammer hint (Issue #808).
func _on_tutorial_hammer_cocked() -> void:
	_dismiss_tutorial_hint(TUTORIAL_HINT_HAMMER_COCK)


## Called when scope state changes (activated/deactivated).
## Dismisses the scope hint when the player uses the scope for the first time (Issue #998).
func _on_tutorial_scope_state_changed(is_active: bool) -> void:
	if not is_active or _tutorial_scope_used:
		return
	_tutorial_scope_used = true
	print("[LabyrinthLevel] Scope used — dismissing scope hint")
	_dismiss_tutorial_hint(TUTORIAL_HINT_SCOPE)


## Called when player switches fire mode (M16 final training hint, Bug fix round 5).
## Dismisses the fire-mode hint and completes the tutorial.
func _on_tutorial_fire_mode_changed(_new_mode: int) -> void:
	if _tutorial_m16_needs_fire_mode_hint and _tutorial_hints.has(TUTORIAL_HINT_FIRE_MODE):
		_tutorial_m16_needs_fire_mode_hint = false
		_dismiss_tutorial_hint(TUTORIAL_HINT_FIRE_MODE)
		_tutorial_step = TutorialStep.COMPLETED
		_dismiss_all_tutorial_hints()


## Called when the revolver reload state changes (Bug fix round 5).
## Updates the revolver reload hint to highlight the next action based on reload state.
## RevolverReloadState: 0=NotReloading, 1=CylinderOpen, 2=Loading, 3=ClosingCylinder.
func _on_tutorial_revolver_reload_state_changed(new_state: int) -> void:
	if not _tutorial_hints.has(TUTORIAL_HINT_RELOAD):
		return
	if not _tutorial_has_revolver:
		return

	var hint_step: int = 0
	match new_state:
		1:
			hint_step = 1  # CylinderOpen → highlight insert cartridge
		2:
			hint_step = 2  # Loading → highlight close cylinder
		_:
			hint_step = 3  # Done

	var new_text := _build_tutorial_revolver_reload_hint_bbcode(hint_step)
	var label: RichTextLabel = _tutorial_hints[TUTORIAL_HINT_RELOAD]
	if is_instance_valid(label):
		label.text = new_text
	print("[LabyrinthLevel] Revolver reload state %d → hint step %d updated" % [new_state, hint_step])


## Called when the revolver has a cartridge inserted during cylinder reload (Bug fix round 6).
## Updates the ammo counter in real time as each cartridge is loaded, mirroring tutorial_level.gd.
## AmmoChanged only fires at reload completion; CartridgeInserted fires per cartridge (Issue #626).
func _on_revolver_cartridge_inserted(_loaded: int, _capacity: int) -> void:
	if _player == null:
		return
	var revolver = _player.get_node_or_null("Revolver")
	if revolver == null:
		return
	if revolver.get("CurrentAmmo") != null and revolver.get("ReserveAmmo") != null:
		_update_ammo_label_magazine(revolver.CurrentAmmo, revolver.ReserveAmmo)


## Called on tutorial reload completion (Issue #808).
## Bug fix #5: grenade hint shown AFTER reload (not simultaneously).
## Bug fix #7: shotgun bolt-cycle hint dismissed on reload completion.
## Bug fix #8: hammer-cock hint NOT dismissed here — only via HammerCocked signal.
## Bug fix #9: grenade hint only shown if player has grenades.
## Bug fix round 4: sniper magazine reload (R→F→R) now correctly advances the tutorial.
## Bug fix round 5: M16 [B] hint shown after grenade (not right after reload).
func _on_tutorial_reload_completed() -> void:
	if _tutorial_step != TutorialStep.RELOAD:
		return
	if not _tutorial_has_reloaded:
		_tutorial_has_reloaded = true
		# Dismiss reload hint; also dismiss bolt-cycle hint for shotgun (Bug fix #7).
		# Bug fix #8: do NOT dismiss hammer-cock hint here — stays until player manually cocks.
		_dismiss_tutorial_hint(TUTORIAL_HINT_RELOAD)
		if _tutorial_has_shotgun:
			_dismiss_tutorial_hint(TUTORIAL_HINT_BOLT_CYCLE)
			_tutorial_shotgun_full_reload_active = false  # Bug fix round 5: reset flag
		var canvas_layer := get_node_or_null("CanvasLayer")
		# Bug fix round 5: M16 fire-mode [B] hint should appear after grenade, not now.
		if _tutorial_assault_rifle != null and not _tutorial_has_ak_gl:
			_tutorial_m16_needs_fire_mode_hint = true
		# Issue #991 fix: AK GL shows underbarrel grenade launcher hint after reload (if round
		# loaded), then waits for the GrenadeFired signal before advancing to THROW_GRENADE.
		# This prevents the GL hint and grenade hint from appearing simultaneously (overlap bug).
		if _tutorial_has_ak_gl and canvas_layer and _tutorial_ak_gl_has_round_loaded():
			_add_tutorial_hint(TUTORIAL_HINT_GRENADE_LAUNCHER,
				"[color=#ff4444][ПКМ][/color] Выстрели подствольным гранатомётом", canvas_layer)
			# Do NOT advance to THROW_GRENADE yet — wait for GL to fire (_on_tutorial_grenade_launcher_fired).
			return
		if _tutorial_has_thrown_grenade:
			_tutorial_step = TutorialStep.COMPLETED
			_dismiss_all_tutorial_hints()
		else:
			_tutorial_step = TutorialStep.THROW_GRENADE
			# Bug fix #5: grenade hint shown AFTER reload disappears.
			# Bug fix #9 (round 4 fix): use GetCurrentGrenades() method for reliable check.
			if _tutorial_player_has_grenades():
				if canvas_layer and not _tutorial_hints.has(TUTORIAL_HINT_GRENADE):
					_reset_tutorial_grenade_hint_tracking()
					_add_tutorial_hint(TUTORIAL_HINT_GRENADE,
						_build_tutorial_grenade_hint_bbcode(0),
						canvas_layer)
			else:
				# No grenades — skip grenade step
				print("[LabyrinthLevel] Player has no grenades — skipping grenade hint")
				_tutorial_step = TutorialStep.COMPLETED
				_dismiss_all_tutorial_hints()


## Called when the AK GL underbarrel grenade launcher fires (Issue #991).
## Dismisses the GL hint (which was lingering) and then advances to THROW_GRENADE step
## so that the grenade hint appears AFTER the GL hint disappears (no overlap).
func _on_tutorial_grenade_launcher_fired() -> void:
	# Dismiss GL hint now that the launcher has been fired
	_dismiss_tutorial_hint(TUTORIAL_HINT_GRENADE_LAUNCHER)
	print("[LabyrinthLevel] Grenade launcher fired — GL hint dismissed")
	# Now advance to grenade throw step (shows grenade hint after GL hint is gone)
	if _tutorial_has_thrown_grenade:
		_tutorial_step = TutorialStep.COMPLETED
		_dismiss_all_tutorial_hints()
	else:
		_tutorial_step = TutorialStep.THROW_GRENADE
		var canvas_layer := get_node_or_null("CanvasLayer")
		if _tutorial_player_has_grenades():
			if canvas_layer and not _tutorial_hints.has(TUTORIAL_HINT_GRENADE):
				_reset_tutorial_grenade_hint_tracking()
				_add_tutorial_hint(TUTORIAL_HINT_GRENADE,
					_build_tutorial_grenade_hint_bbcode(0),
					canvas_layer)
		else:
			print("[LabyrinthLevel] Player has no grenades — skipping grenade hint")
			_tutorial_step = TutorialStep.COMPLETED
			_dismiss_all_tutorial_hints()


## Build BBCode for the grenade throw hint with the reviewed issue #1818 steps.
func _build_tutorial_grenade_hint_bbcode(step: int) -> String:
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
	_extend_tutorial_hint_strikethrough(TUTORIAL_HINT_GRENADE, strikethrough_progress[clamped_step])
	var styled: PackedStringArray = []
	for i in range(parts.size()):
		if i < highlighted_part:
			styled.append("[color=#888888]%s[/color]" % parts[i])
		elif i == highlighted_part:
			styled.append("[color=#ff4444]%s[/color]" % parts[i])
		else:
			styled.append("[color=#888888]%s[/color]" % parts[i])
	return " ".join(styled)


func _reset_tutorial_grenade_hint_tracking() -> void:
	_tutorial_grenade_g_was_held = false
	_tutorial_grenade_hint_step = 0
	_tutorial_grenade_drag_completed = false
	_tutorial_grenade_rmb_held_after_release = false
	_tutorial_grenade_rmb_was_pressed = false
	_tutorial_grenade_hint_drag_start = Vector2.ZERO


## Update the grenade hint step based on current input (Issue #1818).
func _update_tutorial_grenade_hint_step() -> void:
	if not _tutorial_hints.has(TUTORIAL_HINT_GRENADE):
		_reset_tutorial_grenade_hint_tracking()
		return

	var g_pressed: bool = Input.is_action_pressed("grenade_prepare")
	var rmb_pressed: bool = Input.is_action_pressed("grenade_throw")
	var current_mouse_pos := get_global_mouse_position()
	var rmb_just_pressed := rmb_pressed and not _tutorial_grenade_rmb_was_pressed
	var rmb_just_released := not rmb_pressed and _tutorial_grenade_rmb_was_pressed

	if _tutorial_grenade_hint_step == 0 and not (g_pressed and rmb_pressed):
		if g_pressed or rmb_pressed or _tutorial_grenade_rmb_was_pressed:
			_reset_tutorial_grenade_hint_tracking()
	elif _tutorial_grenade_hint_step == 1 and not g_pressed and not _tutorial_grenade_drag_completed:
		_reset_tutorial_grenade_hint_tracking()
	elif _tutorial_grenade_hint_step == 2 and not g_pressed and not rmb_pressed:
		_reset_tutorial_grenade_hint_tracking()
	elif _tutorial_grenade_hint_step == 3 and not g_pressed and not rmb_pressed:
		_reset_tutorial_grenade_hint_tracking()
	elif _tutorial_grenade_hint_step == 4 and not rmb_pressed and not _tutorial_grenade_rmb_held_after_release:
		_reset_tutorial_grenade_hint_tracking()

	if _tutorial_grenade_hint_step <= 1 and g_pressed and rmb_pressed and rmb_just_pressed:
		_tutorial_grenade_drag_completed = false
		_tutorial_grenade_hint_drag_start = current_mouse_pos

	if _tutorial_grenade_hint_step == 1 and g_pressed and rmb_pressed:
		if current_mouse_pos.x - _tutorial_grenade_hint_drag_start.x > 20.0:
			_tutorial_grenade_drag_completed = true
			_tutorial_grenade_hint_step = 2

	if _tutorial_grenade_hint_step == 0 and g_pressed and rmb_pressed:
		_tutorial_grenade_hint_step = 1
		_tutorial_grenade_g_was_held = true
	elif _tutorial_grenade_hint_step == 2 and _tutorial_grenade_drag_completed and rmb_just_released:
		_tutorial_grenade_hint_step = 3
	elif _tutorial_grenade_hint_step == 3 and g_pressed and rmb_just_pressed:
		_tutorial_grenade_rmb_held_after_release = true
		_tutorial_grenade_hint_step = 4
	elif _tutorial_grenade_hint_step == 4 and not g_pressed and rmb_pressed and _tutorial_grenade_rmb_held_after_release:
		_tutorial_grenade_hint_step = 5
		_tutorial_grenade_g_was_held = false
	elif _tutorial_grenade_hint_step == 5 and not rmb_pressed and _tutorial_grenade_rmb_held_after_release:
		_tutorial_grenade_hint_step = 4

	var label: RichTextLabel = _tutorial_hints[TUTORIAL_HINT_GRENADE]
	if is_instance_valid(label):
		var new_text := _build_tutorial_grenade_hint_bbcode(_tutorial_grenade_hint_step)
		if label.text != new_text:
			label.text = new_text

	_tutorial_grenade_rmb_was_pressed = rmb_pressed


## Called when player throws a grenade — dismisses grenade hint (Issue #808).
## Bug fix round 5: M16 fire-mode [B] hint shown AFTER grenade (as the final training hint).
func _on_tutorial_grenade_thrown() -> void:
	if _tutorial_step != TutorialStep.THROW_GRENADE and _tutorial_step != TutorialStep.RELOAD:
		return
	if not _tutorial_has_thrown_grenade:
		_tutorial_has_thrown_grenade = true
		_dismiss_tutorial_hint(TUTORIAL_HINT_GRENADE)
		# Bug fix round 5: show M16 fire-mode [B] hint as the last training hint.
		if _tutorial_m16_needs_fire_mode_hint and _tutorial_step == TutorialStep.THROW_GRENADE:
			var canvas_layer := get_node_or_null("CanvasLayer")
			if canvas_layer:
				_add_tutorial_hint(TUTORIAL_HINT_FIRE_MODE,
					"[color=#ff4444][B][/color] Переключи режим стрельбы", canvas_layer)
			# Wait for the player to switch fire mode before completing
			return
		if _tutorial_step == TutorialStep.THROW_GRENADE:
			_tutorial_step = TutorialStep.COMPLETED
			_dismiss_all_tutorial_hints()


## Check whether the player currently holds at least one grenade (Bug fix #9).
## Bug fix round 4: use GetCurrentGrenades() method instead of get("GrenadeCount") since
## _currentGrenades is a private C# field not accessible via Godot property reflection.
## Player spawns with 1 grenade on normal levels (see Player.cs).
func _tutorial_player_has_grenades() -> bool:
	if _player == null:
		return false
	# Try C# method GetCurrentGrenades() first
	if _player.has_method("GetCurrentGrenades"):
		return int(_player.GetCurrentGrenades()) > 0
	# Fallback: try GrenadeCount property (GDScript player)
	var grenade_count = _player.get("GrenadeCount")
	if grenade_count != null:
		return int(grenade_count) > 0
	# Last fallback: player always starts with at least 1 grenade on Lab level
	return true


## Check whether the AK GL has a round in the grenade launcher (Bug fix #10).
## Bug fix round 4: use GrenadeAvailable (bool) instead of GrenadeLauncherAmmo (did not exist).
func _tutorial_ak_gl_has_round_loaded() -> bool:
	if _tutorial_assault_rifle == null:
		return false
	# Check C# AKGL property GrenadeAvailable (bool)
	var available = _tutorial_assault_rifle.get("GrenadeAvailable")
	if available != null:
		return bool(available)
	return true  # Assume loaded if property not found


## Build BBCode for sniper bolt-cycle hint showing 4-step sequence (Bug fix #4).
## Bug fix #3: highlights the NEXT step in red based on last completed step.
## Issue #944: Strikethrough is now animated via Line2D, not BBCode [s] tags.
func _build_tutorial_sniper_bolt_hint_bbcode(step: int) -> String:
	const STEPS := ["←", "↓", "↑", "→"]
	var parts: PackedStringArray = []
	for i in range(STEPS.size()):
		if i < step:
			# Completed step: grey (strikethrough animated via Line2D)
			parts.append("[color=#888888][%s][/color]" % STEPS[i])
		elif i == step:
			# Current step - red highlight
			parts.append("[color=#ff4444][%s][/color]" % STEPS[i])
		else:
			# Future step - grey
			parts.append("[color=#888888][%s][/color]" % STEPS[i])

	# Extend strikethrough progressively based on completed steps
	# Each step is ~12.5% of the total hint width (4 steps + text = ~50% for keys)
	if step > 0:
		var progress := float(step) * 0.125  # 12.5% per step
		_extend_tutorial_hint_strikethrough(TUTORIAL_HINT_BOLT_CYCLE, progress)

	return " ".join(parts) + " " + tr("HINT_BOLT_ACTION_WORD")


## Build BBCode for shotgun reload hint with dynamic shell count (Bug fix #7).
func _build_tutorial_shotgun_reload_hint_bbcode() -> String:
	var shells_needed: int = _get_tutorial_shotgun_shells_to_load()
	return "[color=#ff4444][ПКМ↑ открыть][/color] [color=#888888][СКМ+ПКМ↓ x%d] [ПКМ↓ закрыть][/color]" % shells_needed


## Build BBCode for shotgun full-reload hint with step-based highlighting (Bug fix round 4).
## Mirrors _build_shotgun_full_reload_hint_bbcode() from tutorial_level.gd.
## state=0/1: highlight open-bolt; state=2: highlight load-shells; state=3: highlight close-bolt.
## Issue #944: Strikethrough is now animated via Line2D, not BBCode [s] tags.
func _build_tutorial_shotgun_full_reload_hint_bbcode(state: int) -> String:
	var shells_needed: int = _get_tutorial_shotgun_shells_to_load()
	match state:
		0, 1:  # Not reloading or waiting to open
			return "[color=#ff4444][ПКМ↑ открыть][/color] [color=#888888][СКМ+ПКМ↓ x%d] [ПКМ↓ закрыть][/color]" % shells_needed
		2:  # Loading shells (open is completed)
			_extend_tutorial_hint_strikethrough(TUTORIAL_HINT_BOLT_CYCLE, 0.25)
			return "[color=#888888][ПКМ↑ открыть][/color] [color=#ff4444][СКМ+ПКМ↓ x%d][/color] [color=#888888][ПКМ↓ закрыть][/color]" % shells_needed
		3:  # Waiting to close (open and loading completed)
			_extend_tutorial_hint_strikethrough(TUTORIAL_HINT_BOLT_CYCLE, 0.55)
			return "[color=#888888][ПКМ↑ открыть] [СКМ+ПКМ↓ x%d][/color] [color=#ff4444][ПКМ↓ закрыть][/color]" % shells_needed
		_:
			# All steps completed
			_extend_tutorial_hint_strikethrough(TUTORIAL_HINT_BOLT_CYCLE, 0.8)
			return "[color=#888888][ПКМ↑ открыть] [СКМ+ПКМ↓ x%d] [ПКМ↓ закрыть][/color]" % shells_needed


## Build BBCode for the revolver reload hint with step-based highlighting (Bug fix round 4).
## Mirrors _build_revolver_reload_hint_bbcode() from tutorial_level.gd.
## Issue #944: Strikethrough is now animated via Line2D, not BBCode [s] tags.
func _build_tutorial_revolver_reload_hint_bbcode(step: int) -> String:
	match step:
		0:
			return "[color=#ff4444][R открыть][/color] [color=#888888][ПКМ↑ патрон] [скролл] [R закрыть][/color]"
		1:
			# Cylinder opened: next is insert cartridges (open is completed)
			_extend_tutorial_hint_strikethrough(TUTORIAL_HINT_RELOAD, 0.15)
			return "[color=#888888][R открыть][/color] [color=#ff4444][ПКМ↑ патрон][/color] [color=#888888][скролл] [R закрыть][/color]"
		2:
			# Scrolled (cylinder rotated): next is close cylinder (open and insert completed)
			_extend_tutorial_hint_strikethrough(TUTORIAL_HINT_RELOAD, 0.55)
			return "[color=#888888][R открыть] [ПКМ↑ патрон] [скролл][/color] [color=#ff4444][R закрыть][/color]"
		_:
			# All steps done
			_extend_tutorial_hint_strikethrough(TUTORIAL_HINT_RELOAD, 0.75)
			return "[color=#888888][R открыть] [ПКМ↑ патрон] [скролл] [R закрыть][/color]"


## Called when the shotgun's action state changes (pump-action between shots).
## Bug fix round 4: updates the TUTORIAL_HINT_BOLT_CYCLE hint for shotgun pump-action steps.
## Bug fix round 5: skip pump hint updates when full-reload hint is active.
## ShotgunActionState: 0=Ready, 1=NeedsPumpUp, 2=NeedsPumpDown
func _on_tutorial_shotgun_action_state_changed(new_state: int) -> void:
	if _tutorial_step != TutorialStep.RELOAD:
		return

	# Bug fix round 5: do not overwrite the full reload hint with the pump hint.
	if _tutorial_shotgun_full_reload_active:
		return

	if new_state == 0:
		# Bolt cycle complete — dismiss pump hint
		if _tutorial_hints.has(TUTORIAL_HINT_BOLT_CYCLE):
			_dismiss_tutorial_hint(TUTORIAL_HINT_BOLT_CYCLE)
	elif _tutorial_hints.has(TUTORIAL_HINT_BOLT_CYCLE):
		var label: RichTextLabel = _tutorial_hints[TUTORIAL_HINT_BOLT_CYCLE]
		if is_instance_valid(label):
			label.text = _build_tutorial_shotgun_pump_hint_bbcode(new_state)


## Build BBCode for the shotgun between-shots pump hint (Bug fix round 4).
## state=1 (NeedsPumpUp): highlight drag-up; state=2 (NeedsPumpDown): highlight drag-down.
## Issue #944: Strikethrough is now animated via Line2D, not BBCode [s] tags.
func _build_tutorial_shotgun_pump_hint_bbcode(state: int) -> String:
	match state:
		1:  # NeedsPumpUp (nothing completed yet)
			return "[color=#ff4444][ПКМ↑][/color] [color=#888888][ПКМ↓][/color] Передёрни затвор"
		2:  # NeedsPumpDown (pump-up completed)
			_extend_tutorial_hint_strikethrough(TUTORIAL_HINT_BOLT_CYCLE, 0.2)
			return "[color=#888888][ПКМ↑][/color] [color=#ff4444][ПКМ↓][/color] Передёрни затвор"
		_:
			# Both completed
			_extend_tutorial_hint_strikethrough(TUTORIAL_HINT_BOLT_CYCLE, 0.4)
			return "[color=#888888][ПКМ↑] [ПКМ↓][/color] Передёрни затвор"


## Called when the shotgun's reload state changes (full shell-by-shell reload).
## Bug fix round 4: updates the TUTORIAL_HINT_BOLT_CYCLE hint to highlight the current reload step.
## Issue #983: when state=0 (NotReloading), reload is complete — dismiss hint and advance tutorial.
## ShotgunReloadState: 0=NotReloading, 1=WaitingToOpen, 2=Loading, 3=WaitingToClose
func _on_tutorial_shotgun_reload_state_changed(new_state: int) -> void:
	if _tutorial_step != TutorialStep.RELOAD:
		return

	if not _tutorial_hints.has(TUTORIAL_HINT_BOLT_CYCLE):
		return

	# state=0 means reload is fully complete (bolt closed) — treat as reload done.
	if new_state == 0:
		print("[LabyrinthLevel] Shotgun reload completed via ReloadStateChanged(0)")
		_on_tutorial_reload_completed()
		return

	var label: RichTextLabel = _tutorial_hints[TUTORIAL_HINT_BOLT_CYCLE]
	if is_instance_valid(label):
		label.text = _build_tutorial_shotgun_full_reload_hint_bbcode(new_state)


## Return the number of shells the shotgun still needs to fill up to capacity (Bug fix #7).
## Issue #1025: use ShellsInTube/TubeMagazineCapacity (same as tutorial_level.gd) instead of
##   CurrentAmmo/MaxAmmo which the Shotgun does not populate.
func _get_tutorial_shotgun_shells_to_load() -> int:
	if _tutorial_shotgun == null:
		return 8
	var shells_in_tube = _tutorial_shotgun.get("ShellsInTube")
	var tube_capacity = _tutorial_shotgun.get("TubeMagazineCapacity")
	if shells_in_tube == null or tube_capacity == null:
		return 8
	return int(tube_capacity) - int(shells_in_tube)


## Get the unique color for a tutorial hint by its key (Issue #945).
## Extends the existing function to include GRENADE_LAUNCHER color.
func _get_tutorial_hint_color_extended(hint_key: String) -> Color:
	if hint_key == TUTORIAL_HINT_GRENADE_LAUNCHER:
		return TUTORIAL_HINT_COLOR_GRENADE_LAUNCHER
	return _get_tutorial_hint_color(hint_key)


## Dismiss all remaining tutorial hints.
func _dismiss_all_tutorial_hints() -> void:
	for key in _tutorial_hints.keys():
		_dismiss_tutorial_hint(key)


## Create and register a tutorial hint RichTextLabel with BBCode support.
## Issue #945: Uses RichTextLabel for BBCode color support (per-hint unique colors + red key highlights).
## Issue #944: Adds fade-in animation when new hints appear + creates Line2D for progressive strikethrough.
func _add_tutorial_hint(hint_key: String, text: String, canvas_layer: Node) -> void:
	if _tutorial_hints.has(hint_key):
		# Already exists - just update text (don't animate)
		if not _tutorial_animating_hints.has(hint_key):
			_tutorial_hints[hint_key].text = text
		return

	var label := RichTextLabel.new()
	label.name = "TutorialHint_" + hint_key
	label.bbcode_enabled = true
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("normal_font_size", 20)
	# Issue #945: unique color per hint type for easy differentiation
	label.add_theme_color_override("default_color", _get_tutorial_hint_color(hint_key))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.custom_minimum_size = Vector2(300, 30)
	label.fit_content = true
	label.scroll_active = false

	# Issue #944: Start transparent for fade-in animation
	label.modulate.a = 0.0

	canvas_layer.add_child(label)
	_tutorial_hints[hint_key] = label

	# Issue #944 Session 5: Initialize empty array; Line2D nodes created per-line in deferred setup.
	_tutorial_hint_strike_lines[hint_key] = []
	_tutorial_hint_strike_progress[hint_key] = 0.0

	# Session 5: Calculate line count and create one Line2D per text line after layout.
	# Font size 20 with default line spacing gives ~26px per line.
	# We need to wait a frame for RichTextLabel to calculate its content size.
	_setup_tutorial_strikethrough_lines.call_deferred(hint_key, label)

	# Position immediately
	var index := _tutorial_hints.size() - 1
	var canvas_transform: Transform2D = get_viewport().get_canvas_transform()
	var screen_pos: Vector2 = canvas_transform * (_player.global_position if _player else Vector2.ZERO)
	label.custom_minimum_size = Vector2(300, 30)
	label.position = screen_pos + Vector2(-150, -80 - index * TUTORIAL_HINT_SPACING)

	# Issue #944: Animate fade-in
	var tween := create_tween()
	tween.tween_property(label, "modulate:a", 1.0, TUTORIAL_HINT_FADE_IN_DURATION).set_ease(Tween.EASE_OUT)

	print("[LabyrinthLevel] Tutorial hint added '%s': %s" % [hint_key, text])


## Issue #944 Session 5: Set up one Line2D per text line after label layout is ready.
## Each line gets its own Line2D node so there are no diagonal connectors between lines.
## Issue #1080: Also computes per-line text widths so strikethrough matches actual text length.
func _setup_tutorial_strikethrough_lines(hint_key: String, label: RichTextLabel) -> void:
	if not is_instance_valid(label):
		return

	# Get font metrics. Font size is 20, typical line height with spacing is ~26px.
	const LINE_HEIGHT := 26.0  # Font size + default line spacing

	# Calculate number of lines based on content height vs line height.
	var content_height := label.get_content_height()
	var line_count := maxi(1, roundi(content_height / LINE_HEIGHT))
	_tutorial_hint_line_counts[hint_key] = line_count

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
	_tutorial_hint_line_widths[hint_key] = line_widths

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

	_tutorial_hint_strike_lines[hint_key] = lines
	print("[LabyrinthLevel] Setup strikethrough for '%s': %d lines, widths: %s" % [hint_key, line_count, str(line_widths)])


## Issue #944 Session 5: Animate the strikethrough lines to extend progressively as steps complete.
## target_progress: 0.0-1.0 representing how much of the hint text should be struck through.
## For multi-line text, progress spans all lines (e.g., 2 lines: 0.5 = line 1 fully struck).
func _extend_tutorial_hint_strikethrough(hint_key: String, target_progress: float) -> void:
	if not _tutorial_hint_strike_lines.has(hint_key):
		return

	var strike_lines: Array = _tutorial_hint_strike_lines[hint_key]
	if strike_lines.is_empty():
		return

	var current_progress: float = _tutorial_hint_strike_progress.get(hint_key, 0.0)
	if target_progress <= current_progress:
		return  # Already at or past this progress

	# Issue #1080: Use per-line widths if available, otherwise fall back to content width.
	var line_widths: Array = _tutorial_hint_line_widths.get(hint_key, [])
	if line_widths.is_empty():
		var fallback_width := 300.0
		if _tutorial_hints.has(hint_key):
			var label: RichTextLabel = _tutorial_hints[hint_key]
			if is_instance_valid(label):
				var content_width := label.get_content_width()
				if content_width > 0:
					fallback_width = content_width
				elif label.custom_minimum_size.x > 0:
					fallback_width = label.custom_minimum_size.x
		var line_count_fb: int = _tutorial_hint_line_counts.get(hint_key, 1)
		for _i in range(line_count_fb):
			line_widths.append(fallback_width)

	var line_count: int = _tutorial_hint_line_counts.get(hint_key, 1)

	# Animate the line extension from current position to new position.
	var tween := create_tween()
	tween.tween_method(
		func(progress: float):
			_update_tutorial_strikethrough_points(strike_lines, line_count, line_widths, progress),
		current_progress, target_progress, TUTORIAL_HINT_STRIKETHROUGH_DURATION * 0.5
	).set_ease(Tween.EASE_OUT)

	_tutorial_hint_strike_progress[hint_key] = target_progress
	print("[LabyrinthLevel] Strikethrough extended for '%s': %.0f%% -> %.0f%%" % [hint_key, current_progress * 100, target_progress * 100])


## Issue #944 Session 5: Update per-line Line2D end points for multi-line strikethrough.
## progress: 0.0-1.0 overall progress across all lines.
## Each Line2D in the array represents one text line and is animated independently.
## Issue #1080: line_widths is an Array[float] with the pixel width of each text line,
## so the strikethrough only extends over the actual text, not over empty space.
func _update_tutorial_strikethrough_points(strike_lines: Array, line_count: int, line_widths: Array, progress: float) -> void:
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


## Remove a tutorial hint label by key.
## Issue #944: Extends strikethrough to 100% before fade-out for all hints.
## Uses the persistent Line2D attached to the hint (created in _add_tutorial_hint).
func _dismiss_tutorial_hint(hint_key: String) -> void:
	if not _tutorial_hints.has(hint_key):
		return

	# Issue #944: Prevent double-dismiss while animating
	if _tutorial_animating_hints.has(hint_key):
		return

	var label: RichTextLabel = _tutorial_hints[hint_key]
	if not is_instance_valid(label):
		_tutorial_hints.erase(hint_key)
		return

	# Mark as animating to prevent updates during animation
	_tutorial_animating_hints[hint_key] = true

	print("[LabyrinthLevel] Dismissing hint '%s' (with strikethrough animation)" % hint_key)
	_animate_tutorial_hint_strikethrough_and_fade(hint_key, label)


## Issue #944 Session 5: Extend the per-line Line2D strikethroughs to 100% and then fade out.
## Uses the persistent Line2D array created per text line in _setup_tutorial_strikethrough_lines.
func _animate_tutorial_hint_strikethrough_and_fade(hint_key: String, label: RichTextLabel) -> void:
	# Get the existing strike lines for this hint
	var strike_lines: Array = []
	if _tutorial_hint_strike_lines.has(hint_key):
		strike_lines = _tutorial_hint_strike_lines[hint_key]

	# Issue #1080: Use per-line widths if available, otherwise fall back to content width.
	var line_widths: Array = _tutorial_hint_line_widths.get(hint_key, [])
	if line_widths.is_empty():
		var fallback_width: float = label.get_content_width()
		if fallback_width <= 0:
			fallback_width = label.custom_minimum_size.x
		if fallback_width <= 0:
			fallback_width = 300.0
		var line_count_fb: int = _tutorial_hint_line_counts.get(hint_key, 1)
		for _i in range(line_count_fb):
			line_widths.append(fallback_width)

	var line_count: int = _tutorial_hint_line_counts.get(hint_key, 1)
	var current_progress: float = _tutorial_hint_strike_progress.get(hint_key, 0.0)

	# Animate the lines from current position to full width (100%)
	var tween := create_tween()

	if not strike_lines.is_empty():
		tween.tween_method(
			func(progress: float):
				_update_tutorial_strikethrough_points(strike_lines, line_count, line_widths, progress),
			current_progress, 1.0, TUTORIAL_HINT_STRIKETHROUGH_DURATION
		).set_ease(Tween.EASE_OUT)

	# After strikethrough animation completes, fade out the whole label
	tween.tween_property(label, "modulate:a", 0.0, TUTORIAL_HINT_FADE_OUT_DURATION).set_ease(Tween.EASE_IN)
	tween.tween_callback(_finalize_tutorial_hint_dismiss.bind(hint_key, label))


## Issue #944 Session 4: Finalize hint dismissal after animation completes.
func _finalize_tutorial_hint_dismiss(hint_key: String, label: RichTextLabel) -> void:
	_tutorial_animating_hints.erase(hint_key)
	_tutorial_hints.erase(hint_key)
	_tutorial_hint_strike_lines.erase(hint_key)
	_tutorial_hint_strike_progress.erase(hint_key)
	_tutorial_hint_line_counts.erase(hint_key)
	_tutorial_hint_line_widths.erase(hint_key)
	if is_instance_valid(label):
		label.queue_free()
	print("[LabyrinthLevel] Hint '%s' dismissed (animation complete)" % hint_key)


## Update tutorial hint positions to float above the player.
func _update_tutorial_hint_positions() -> void:
	if _player == null or _tutorial_hints.is_empty():
		return

	var canvas_transform: Transform2D = get_viewport().get_canvas_transform()
	var screen_pos: Vector2 = canvas_transform * _player.global_position

	var index := 0
	for hint_key in _tutorial_hints:
		var label: RichTextLabel = _tutorial_hints[hint_key]
		if is_instance_valid(label):
			label.custom_minimum_size = Vector2(300, 30)
			label.position = screen_pos + Vector2(-150, -80 - index * TUTORIAL_HINT_SPACING)
			index += 1


## Log a message to the file logger if available.
func _log_to_file(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[LabyrinthLevel] " + message)
	else:
		print("[LabyrinthLevel] " + message)
