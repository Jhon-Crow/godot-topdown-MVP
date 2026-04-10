extends Node2D
## Labyrinth 2 level scene for the Godot Top-Down Template.
##
## This scene is a larger labyrinth-style building with more rooms and enemies.
## Similar to BuildingLevel but with more interconnected rooms and corridors,
## making navigation more maze-like and challenging.
## Features:
## - Larger labyrinth layout (~3200x2400 pixels) for more exploration
## - 17 enemies distributed across many rooms (more than BuildingLevel), including a machine gunner and 2 invisible searching enemies (Issue #1121)
## - More rooms with narrower corridors for a true labyrinth feel
## - Score tracking with Hotline Miami style ranking system
## - Warm ceiling lights in all zones (Issue #1291)

## Reference to the enemy count label.
var _enemy_count_label: Label = null

## Reference to the ammo count label.
var _ammo_label: Label = null

## Reference to the player.
var _player: Node2D = null

## Reference to the weapon hints component (Issue #809).
var _weapon_hints_component: Node = null

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

## List of enemy nodes for position tracking.
var _enemies: Array = []

## Cached reference to the ReplayManager autoload (C# singleton).
var _replay_manager: Node = null


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
	print("Labyrinth2Level loaded - Larger Labyrinth Style")
	print("Labyrinth size: ~3200x2400 pixels")
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

	# Setup exit zone near player spawn (left wall)
	_setup_exit_zone()

	# Setup window lights in corridors without enemies
	_setup_window_lights()

	# Setup warm ceiling lights in the center of each zone (Issue #1291)
	_setup_room_warm_lights()

	# Start replay recording
	_start_replay_recording()

	# Setup weapon hints (Issue #809)
	_setup_weapon_hints()


## Initialize the ScoreManager for this level.
func _initialize_score_manager() -> void:
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager == null:
		return

	# Start tracking for this level
	score_manager.start_level(_initial_enemy_count)

	# Set player reference
	if _player:
		score_manager.set_player(_player)

	# Connect to combo changes for UI feedback
	if not score_manager.combo_changed.is_connected(_on_combo_changed):
		score_manager.combo_changed.connect(_on_combo_changed)


## Starts recording the replay for this level.
func _start_replay_recording() -> void:
	var replay_manager: Node = _get_or_create_replay_manager()
	if replay_manager == null:
		_log_to_file("ERROR: ReplayManager could not be loaded, replay recording disabled")
		print("[Labyrinth2Level] ERROR: ReplayManager could not be loaded!")
		return

	_log_to_file("Starting replay recording - Player: %s, Enemies count: %d" % [
		_player.name if _player else "NULL",
		_enemies.size()
	])

	if _player == null:
		_log_to_file("WARNING: Player is null, replay may not record properly")
		print("[Labyrinth2Level] WARNING: Player is null for replay recording!")

	if _enemies.is_empty():
		_log_to_file("WARNING: No enemies to track in replay")
		print("[Labyrinth2Level] WARNING: No enemies registered for replay!")

	if replay_manager.has_method("ClearReplay"):
		replay_manager.ClearReplay()
		_log_to_file("Previous replay data cleared")

	if replay_manager.has_method("StartRecording"):
		replay_manager.StartRecording(self, _player, _enemies)
		_log_to_file("Replay recording started successfully")
		print("[Labyrinth2Level] Replay recording started with %d enemies" % _enemies.size())
	else:
		_log_to_file("ERROR: ReplayManager.StartRecording method not found")
		print("[Labyrinth2Level] ERROR: StartRecording method not found!")


## Setup the exit zone near the player spawn point (left wall).
## The exit appears after all enemies are eliminated.
func _setup_exit_zone() -> void:
	var exit_zone_scene = load("res://scenes/objects/ExitZone.tscn")
	if exit_zone_scene == null:
		push_warning("ExitZone scene not found - score will show immediately on level clear")
		return

	_exit_zone = exit_zone_scene.instantiate()
	# Position exit at the far right end of the map (player starts at 200, 1200 on the left).
	# The player must traverse the full labyrinth before reaching the exit.
	_exit_zone.position = Vector2(3200, 1200)
	_exit_zone.zone_width = 60.0
	_exit_zone.zone_height = 100.0

	_exit_zone.player_reached_exit.connect(_on_player_reached_exit)

	var environment := get_node_or_null("Environment")
	if environment:
		environment.add_child(_exit_zone)
	else:
		add_child(_exit_zone)

	print("[Labyrinth2Level] Exit zone created at position (3200, 1200)")


## Called when the player reaches the exit zone after clearing the level.
func _on_player_reached_exit() -> void:
	if not _level_cleared:
		return

	if _level_completed:
		return

	print("[Labyrinth2Level] Player reached exit - showing score!")
	call_deferred("_complete_level_with_score")


## Activate the exit zone after all enemies are eliminated.
func _activate_exit_zone() -> void:
	if _exit_zone and _exit_zone.has_method("activate"):
		_exit_zone.activate()
		print("[Labyrinth2Level] Exit zone activated - go to exit to see score!")
	else:
		push_warning("Exit zone not available - showing score immediately")
		_complete_level_with_score()


## Setup warm ceiling lights in the centers of all zones (Issue #1291).
## Adds PointLight2D nodes with warm yellow-orange color — the same style as
## BuildingLevel (Здание) — so the map has consistent interior illumination.
##
## Zone centers (derived from RoomLabel bounds in the scene):
## - Entry Hall:        ~(334,  290)  — left entry zone
## - West Wing:         ~(906,  290)  — upper-left wing
## - Central Hub:       ~(1512, 440)  — upper-centre hub (taller room)
## - North Sector:      ~(2112, 290)  — upper-right sector
## - East Wing:         ~(2836, 290)  — far-right wing
## - Central Corridor:  3 lights spread across the wide corridor
## - Lower Labyrinth:   3 lights spread across the wide lower zone
func _setup_room_warm_lights() -> void:
	var environment := get_node_or_null("Environment")
	if environment == null:
		return

	var room_lights_node := Node2D.new()
	room_lights_node.name = "RoomLights"
	environment.add_child(room_lights_node)

	# Format: [position, energy, texture_scale, label]
	var room_configs: Array = [
		# Upper zones — smaller rooms, softer lights
		[Vector2(334,  290),  0.7, 3.5, "EntryHall"],
		[Vector2(906,  290),  0.7, 3.5, "WestWing"],
		[Vector2(1512, 440),  0.85, 4.5, "CentralHub"],
		[Vector2(2112, 290),  0.7, 3.5, "NorthSector"],
		[Vector2(2836, 290),  0.7, 3.5, "EastWing"],
		# Wide zones — multiple lights spread across the length
		[Vector2(800,  1512), 0.85, 4.5, "CentralCorridor_W"],
		[Vector2(1664, 1512), 0.85, 4.5, "CentralCorridor_C"],
		[Vector2(2528, 1512), 0.85, 4.5, "CentralCorridor_E"],
		[Vector2(800,  2136), 0.85, 4.5, "LowerLabyrinth_W"],
		[Vector2(1664, 2136), 0.85, 4.5, "LowerLabyrinth_C"],
		[Vector2(2528, 2136), 0.85, 4.5, "LowerLabyrinth_E"],
	]

	for cfg in room_configs:
		_create_room_warm_light(room_lights_node, cfg[0], cfg[1], cfg[2], cfg[3])

	print("[Labyrinth2Level] Warm ceiling lights placed in all zones (Issue #1291)")


## Create a single warm ceiling light at the given room-center position.
func _create_room_warm_light(parent: Node2D, pos: Vector2, energy: float, scale: float, room_name: String) -> void:
	var light_node := Node2D.new()
	light_node.name = "WarmLight_%s" % room_name
	light_node.position = pos
	parent.add_child(light_node)

	# Small visual indicator — a dim warm-colored circle representing the lamp fixture.
	var fixture := Sprite2D.new()
	fixture.name = "Fixture"
	fixture.texture = _create_lamp_fixture_texture()
	fixture.modulate = Color(1.0, 0.85, 0.5, 0.5)
	light_node.add_child(fixture)

	var light := PointLight2D.new()
	light.name = "PointLight"
	light.color = Color(1.0, 0.75, 0.3, 1.0)
	light.energy = energy
	light.shadow_enabled = true
	light.shadow_filter = PointLight2D.SHADOW_FILTER_PCF5
	light.shadow_filter_smooth = 4.0
	light.texture = _create_warm_light_texture()
	light.texture_scale = scale
	light_node.add_child(light)


## Create a soft radial gradient texture for the warm room lights.
func _create_warm_light_texture() -> ImageTexture:
	var size := 512
	var center := Vector2(size * 0.5, size * 0.5)
	var outer_r := size * 0.5

	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)

	for y in range(size):
		for x in range(size):
			var dist := Vector2(x, y).distance_to(center)
			var t := clampf(dist / outer_r, 0.0, 1.0)
			var brightness := pow(1.0 - t, 2.2)
			image.set_pixel(x, y, Color(brightness, brightness, brightness, 1.0))

	return ImageTexture.create_from_image(image)


## Create a small circular texture for the lamp fixture visual indicator.
func _create_lamp_fixture_texture() -> ImageTexture:
	var size := 32
	var center := Vector2(size * 0.5, size * 0.5)
	var outer_r := size * 0.5

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


## Setup window lights in corridors without enemies.
func _setup_window_lights() -> void:
	var environment := get_node_or_null("Environment")
	if environment == null:
		return

	var windows_node := Node2D.new()
	windows_node.name = "WindowLights"
	environment.add_child(windows_node)

	# Left wall windows - near player spawn area (no enemies)
	_create_window_light(windows_node, Vector2(64, 1000), "left")
	_create_window_light(windows_node, Vector2(64, 1200), "left")
	_create_window_light(windows_node, Vector2(64, 1400), "left")

	# Top wall windows - above entry corridor (no enemies)
	_create_window_light(windows_node, Vector2(400, 64), "top")
	_create_window_light(windows_node, Vector2(600, 64), "top")
	_create_window_light(windows_node, Vector2(800, 64), "top")

	# Bottom wall windows - below lower corridor (no enemies there)
	_create_window_light(windows_node, Vector2(500, 2464), "bottom")
	_create_window_light(windows_node, Vector2(1000, 2464), "bottom")
	_create_window_light(windows_node, Vector2(2000, 2464), "bottom")

	# Scene-wide ambient moonlight
	_create_ambient_moonlight(windows_node)

	print("[Labyrinth2Level] Window lights placed in corridors without enemies")


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


## Create a radial gradient texture for the window moonlight.
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


func _process(_delta: float) -> void:
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager and score_manager.has_method("update_enemy_positions"):
		score_manager.update_enemy_positions(_enemies)
	# Issue #959: Re-check level completion when a retaliating pacifist finishes retaliation.
	if _current_enemy_count <= 0 and not _level_cleared and not _has_retaliating_pacifists():
		_level_cleared = true
		_activate_exit_zone()


## Called when combo changes.
func _on_combo_changed(combo: int, points: int) -> void:
	if _combo_label == null:
		return

	if combo > 0:
		_combo_label.text = "x%d COMBO\n+%d" % [combo, points]
		_combo_label.visible = true
		var combo_color := _get_combo_color(combo)
		_combo_label.add_theme_color_override("font_color", combo_color)
		# Combo pop animation: scale bounce + fade in, then fade out
		_combo_label.scale = Vector2(0.7, 0.7)
		_combo_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(_combo_label, "scale", Vector2(1.0, 1.0), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(_combo_label, "modulate:a", 1.0, 0.1)
		tween.set_parallel(false)
		tween.tween_interval(1.0)
		tween.tween_property(_combo_label, "modulate:a", 0.0, 0.3)
	else:
		_combo_label.visible = false


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
## Issue #1216: Fixed baking — parse source geometry (walls, collision layer 4)
## then bake synchronously so walls are excluded from the walkable area.
## Clamps the camera so the outer border walls are never visible (Issue #1682).
##
## Labyrinth2Level map: 3328x2528 px playfield framed by 32 px walls.
##   WallTop    (1664,   48), h=16  → bottom edge y=64   → limit_top    = 64
##   WallBottom (1664, 2480), h=16  → top edge   y=2464  → limit_bottom = 2464
##   WallLeft   (  48, 1264), w=16  → right edge x=64    → limit_left   = 64
##   WallRight  (3280, 1264), w=16  → left edge  x=3264  → limit_right  = 3264
func _configure_camera() -> void:
	if _player == null:
		return
	var camera: Camera2D = _player.get_node_or_null("Camera2D")
	if camera == null:
		push_warning("[Labyrinth2Level] Camera2D not found on player — cannot set camera limits")
		return
	const LIMIT_TOP: int    =   64   # WallTop bottom edge
	const LIMIT_BOTTOM: int = 2464   # WallBottom top edge
	const LIMIT_LEFT: int   =   64   # WallLeft right edge
	const LIMIT_RIGHT: int  = 3264   # WallRight left edge
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


## Setup enemy tracking and connect death signals.
func _setup_enemy_tracking() -> void:
	var enemies_node: Node = get_node_or_null("Environment/Enemies")
	if enemies_node == null:
		push_warning("Enemies node not found")
		return

	for enemy in enemies_node.get_children():
		if enemy.has_signal("died"):
			enemy.died.connect(_on_enemy_died)
			_enemies.append(enemy)
			if enemy.has_signal("died_with_info"):
				enemy.died_with_info.connect(_on_enemy_died_with_info)
		if enemy.has_signal("hit"):
			enemy.hit.connect(_on_enemy_hit)
		# Issue #959: Connect to pacifist signal - pacifists count as eliminated for level completion
		if enemy.has_signal("became_pacifist"):
			enemy.became_pacifist.connect(_on_enemy_became_pacifist.bind(enemy))

	_initial_enemy_count = _enemies.size()
	_current_enemy_count = _initial_enemy_count
	print("[Labyrinth2Level] Tracking %d enemies" % _initial_enemy_count)


## Setup player tracking and connect signals.
func _setup_player_tracking() -> void:
	_player = get_node_or_null("Entities/Player")
	if _player == null:
		push_warning("Player not found")
		return

	_setup_selected_weapon()

	# Register player with GameManager
	if GameManager:
		GameManager.set_player(_player)

	# Find the ammo label
	_ammo_label = get_node_or_null("CanvasLayer/UI/AmmoLabel")

	# Connect to player death signal (handles both GDScript "died" and C# "Died")
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
		# C# Player with weapon - connect to weapon signals
		if weapon.has_signal("AmmoChanged"):
			weapon.AmmoChanged.connect(_on_weapon_ammo_changed)
		if weapon.has_signal("Fired"):
			weapon.Fired.connect(_on_shot_fired)
		# Apply ammo config (silenced pistol and makarov_pm handled here as well)
		_configure_silenced_pistol_ammo(weapon)
		_configure_makarov_pm_ammo(weapon)
		# Initial ammo display from weapon
		if weapon.get("CurrentAmmo") != null and weapon.get("ReserveAmmo") != null:
			_update_ammo_label_magazine(weapon.CurrentAmmo, weapon.ReserveAmmo)
	else:
		# GDScript Player - connect to player signals
		if _player.has_signal("ammo_changed"):
			_player.ammo_changed.connect(_on_ammo_changed)
		# Initial ammo display
		if _player.has_method("get_current_ammo") and _player.has_method("get_max_ammo"):
			_update_ammo_label(_player.get_current_ammo(), _player.get_max_ammo())


## Setup debug UI labels.
func _setup_debug_ui() -> void:
	var ui := get_node_or_null("CanvasLayer/UI")
	if ui != null:
		_difficulty_label = Label.new()
		_difficulty_label.name = "DifficultyLabel"
		_difficulty_label.text = "Difficulty: " + DifficultyManager.get_difficulty_name()
		_difficulty_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_difficulty_label.offset_left = 10
		_difficulty_label.offset_top = 80
		_difficulty_label.offset_right = 200
		_difficulty_label.offset_bottom = 110
		ui.add_child(_difficulty_label)
	_magazines_label = get_node_or_null("CanvasLayer/UI/MagazinesLabel")
	# Create combo label dynamically (no ComboLabel node exists in Labyrinth2Level.tscn)
	if ui != null:
		_combo_label = Label.new()
		_combo_label.name = "ComboLabel"
		_combo_label.text = ""
		_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_combo_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_combo_label.offset_left = -500
		_combo_label.offset_right = -10
		_combo_label.offset_top = 80
		_combo_label.offset_bottom = 180
		_combo_label.add_theme_font_size_override("font_size", 56)
	_combo_label.add_theme_constant_override("line_separation", -10)
		_combo_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2, 1.0))
		_combo_label.add_theme_font_override("font", load("res://assets/fonts/gothic_bitmap.fnt"))
		_combo_label.visible = false
		ui.add_child(_combo_label)
	_update_debug_ui()


## Setup the saturation overlay for kill visual effect.
func _setup_saturation_overlay() -> void:
	_saturation_overlay = get_node_or_null("CanvasLayer/UI/SaturationOverlay")
	if _saturation_overlay:
		_saturation_overlay.color = Color(1, 0, 0, 0)
		_saturation_overlay.visible = true


## Called when an enemy dies.
func _on_enemy_died() -> void:
	_current_enemy_count -= 1
	_update_enemy_count_label()
	_trigger_saturation_effect()

	if _current_enemy_count <= 0 and not _has_retaliating_pacifists():
		_level_cleared = true
		_activate_exit_zone()
		print("[Labyrinth2Level] All enemies eliminated! Go to exit.")


## Called when an enemy dies with special kill information (ricochet/penetration).
## Registers the kill with GameManager and ScoreManager for accurate score tracking.
func _on_enemy_died_with_info(is_ricochet_kill: bool, is_penetration_kill: bool, is_player_kill: bool = true) -> void:
	if GameManager:
		GameManager.register_kill(is_player_kill)
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager and score_manager.has_method("register_kill"):
		score_manager.register_kill(is_ricochet_kill, is_penetration_kill)


## Called when an enemy is hit (for accuracy tracking).
func _on_enemy_hit() -> void:
	if GameManager:
		GameManager.register_hit()


## Called when an enemy becomes a pacifist (Issue #959).
func _on_enemy_became_pacifist(enemy: Node) -> void:
	_current_enemy_count -= 1
	# Issue #959: Do not count pacifist again when it dies - already counted here
	if is_instance_valid(enemy) and enemy.died.is_connected(_on_enemy_died):
		enemy.died.disconnect(_on_enemy_died)
	_update_enemy_count_label()
	print("[Labyrinth2Level] Enemy became pacifist - counting as eliminated")
	if _current_enemy_count <= 0 and not _has_retaliating_pacifists():
		_level_cleared = true
		_activate_exit_zone()
		print("[Labyrinth2Level] All enemies eliminated or pacified! Go to exit.")


## Returns true if any enemy is a pacifist who is currently retaliating (attacking the player).
## Level should not complete while any enemy is still a threat (Issue #959).
func _has_retaliating_pacifists() -> bool:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and enemy.has_method("is_alive") and enemy.is_alive():
			if enemy.has_method("is_retaliating") and enemy.is_retaliating():
				return true
	return false


## Called by GameManager when an enemy is killed (for score tracking).
func _on_game_manager_enemy_killed() -> void:
	_update_debug_ui()


## Update the enemy count label.
func _update_enemy_count_label() -> void:
	if _enemy_count_label:
		_enemy_count_label.text = "Enemies: %d" % _current_enemy_count


## Update debug UI labels from GameManager stats.
func _update_debug_ui() -> void:
	if not GameManager:
		return

	if _difficulty_label:
		_difficulty_label.text = "Difficulty: " + DifficultyManager.get_difficulty_name()


## Called when player ammo changes.
func _on_ammo_changed(current: int, total: int) -> void:
	if _ammo_label:
		_ammo_label.text = "AMMO: %d/%d" % [current, total]


## Trigger the red saturation flash effect on kill.
func _trigger_saturation_effect() -> void:
	if _saturation_overlay == null:
		return

	_saturation_overlay.color = Color(1, 0, 0, SATURATION_INTENSITY)
	var tween := create_tween()
	tween.tween_property(_saturation_overlay, "color", Color(1, 0, 0, 0), SATURATION_DURATION)


## Complete the level and show the score screen.
func _complete_level_with_score() -> void:
	if _level_completed:
		return
	_level_completed = true

	# Disable player controls immediately
	_disable_player_controls()

	# Deactivate exit zone to prevent further triggers
	if _exit_zone and _exit_zone.has_method("deactivate"):
		_exit_zone.deactivate()

	# Stop replay recording
	var replay_manager: Node = _get_or_create_replay_manager()
	if replay_manager:
		if replay_manager.has_method("StopRecording"):
			replay_manager.StopRecording()
			_log_to_file("Replay recording stopped")

	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager and score_manager.has_method("complete_level"):
		var score_data: Dictionary = score_manager.complete_level()
		# Notify loudspeaker progression (Issue #959)
		var aim: Node = get_node_or_null("/root/ActiveItemManager")
		if aim and aim.has_method("notify_level_completed"):
			aim.notify_level_completed(score_data.get("kills", 0) > 0)
		_show_score_screen(score_data)
	else:
		# Fallback to simple victory message if ScoreManager not available
		_show_victory_message()

	_log_to_file("Level complete!")


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

	# Next Level button
	var next_level_path: String = _get_next_level_path()
	if next_level_path != "":
		var next_button := Button.new()
		next_button.name = "NextLevelButton"
		next_button.text = "→ Next Level"
		next_button.custom_minimum_size = Vector2(200, 40)
		next_button.add_theme_font_size_override("font_size", 18)
		next_button.pressed.connect(_on_next_level_pressed.bind(next_level_path))
		buttons_container.add_child(next_button)

	# Restart button
	var restart_button := Button.new()
	restart_button.name = "RestartButton"
	restart_button.text = "↻ Restart (Q)"
	restart_button.custom_minimum_size = Vector2(200, 40)
	restart_button.add_theme_font_size_override("font_size", 18)
	restart_button.pressed.connect(_on_restart_pressed)
	buttons_container.add_child(restart_button)

	# Level Select button
	var level_select_button := Button.new()
	level_select_button.name = "LevelSelectButton"
	level_select_button.text = "☰ Level Select"
	level_select_button.custom_minimum_size = Vector2(200, 40)
	level_select_button.add_theme_font_size_override("font_size", 18)
	level_select_button.pressed.connect(_on_level_select_pressed)
	buttons_container.add_child(level_select_button)

	# Watch Replay button (only shown if replay viewing is enabled in experimental settings)
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
		else:
			replay_button.disabled = true
			replay_button.text = "▶ Watch Replay (W) - no data"

		buttons_container.add_child(replay_button)

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

	# Show cursor for button interaction
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)

	# Focus the next level button if available, otherwise restart
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
		_:
			return Color(0.6, 0.6, 0.6, 1.0)


## Show victory message fallback (when ScoreManager not available).
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


## Called when the Watch Replay button is pressed.
func _on_watch_replay_pressed() -> void:
	_log_to_file("Watch Replay triggered")
	var replay_manager: Node = _get_or_create_replay_manager()
	if replay_manager and replay_manager.has_method("HasReplay") and replay_manager.HasReplay():
		if replay_manager.has_method("StartPlayback"):
			replay_manager.StartPlayback(self)


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


## Called when the Armory button is pressed on the score screen.
func _on_armory_button_pressed() -> void:
	_log_to_file("Armory button pressed from score screen")
	var armory_menu_scene = load("res://scenes/ui/ArmoryMenu.tscn")
	if armory_menu_scene:
		var armory_menu = armory_menu_scene.instantiate()
		armory_menu.layer = 100
		armory_menu.opened_from_score_screen = true
		get_tree().root.add_child(armory_menu)
		armory_menu.back_pressed.connect(func():
			armory_menu.queue_free()
			# Issue #1582: Remove gold highlight from armory button if all available items have been opened
			var unlock_manager: Node = get_node_or_null("/root/UnlockManager")
			if unlock_manager == null or not unlock_manager.has_method("has_any_available_unlock") or not unlock_manager.has_any_available_unlock():
				_remove_armory_button_gold_style()
		)
		armory_menu.apply_pressed_from_score_screen.connect(func():
			# Issue #1690: Remove gold highlight from armory button if all available items have been opened
			var unlock_manager: Node = get_node_or_null("/root/UnlockManager")
			if unlock_manager == null or not unlock_manager.has_method("has_any_available_unlock") or not unlock_manager.has_any_available_unlock():
				_remove_armory_button_gold_style()
		)
	else:
		_log_to_file("ERROR: Could not load armory menu scene")


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
## Returns empty string if this is the last level or level not found.
func _get_next_level_path() -> String:
	var current_scene_path: String = ""
	var current_scene: Node = get_tree().current_scene
	if current_scene and current_scene.scene_file_path:
		current_scene_path = current_scene.scene_file_path

	# Level ordering (matching LevelsMenu.LEVELS) — Labyrinth Complex is last
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
			return ""  # Last level

	return ""  # Current level not found


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


## Called when the player dies.
func _on_player_died() -> void:
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


## Called when weapon ammo changes (C# Player).
func _on_weapon_ammo_changed(current_ammo: int, reserve_ammo: int) -> void:
	_update_ammo_label_magazine(current_ammo, reserve_ammo)


## Called when a shot is fired (from C# weapon).
func _on_shot_fired() -> void:
	if GameManager:
		GameManager.register_shot()


## Update the ammo label with current/maximum format (for GDScript Player).
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


## Setup weapon hints component (Issue #809).
## Shows weapon-specific tutorial hints when player uses a new weapon.
func _setup_weapon_hints() -> void:
	if _player == null:
		return

	var canvas_layer: Node = get_node_or_null("CanvasLayer")
	if canvas_layer == null:
		push_warning("[Labyrinth2Level] CanvasLayer node not found for weapon hints")
		return

	var hints_script = load("res://scripts/components/weapon_hints_component.gd")
	if hints_script == null:
		push_warning("[Labyrinth2Level] WeaponHintsComponent script not found")
		return

	_weapon_hints_component = Node.new()
	_weapon_hints_component.name = "WeaponHintsComponent"
	_weapon_hints_component.set_script(hints_script)
	add_child(_weapon_hints_component)

	if _weapon_hints_component.has_method("setup"):
		_weapon_hints_component.setup(_player, canvas_layer)
		print("[Labyrinth2Level] Weapon hints component added and setup")


## Configure silenced pistol ammo to match enemy count (Issue #1422).
## The silenced pistol gets exactly as many bullets as there are enemies.
func _configure_silenced_pistol_ammo(weapon: Node) -> void:
	if weapon.name != "SilencedPistol":
		return
	if weapon.has_method("ConfigureAmmoForEnemyCount"):
		var enemy_count: int = _initial_enemy_count
		var ammo_multiplier: int = DifficultyManager.get_ammo_multiplier()
		if ammo_multiplier > 1:
			enemy_count *= ammo_multiplier
			_log_to_file("Gunslinger/PowerFantasy mode: silenced pistol enemy count multiplied by %dx" % ammo_multiplier)
		weapon.ConfigureAmmoForEnemyCount(enemy_count)
		_log_to_file("Configured silenced pistol ammo for %d enemies" % enemy_count)
		if weapon.get("CurrentAmmo") != null and weapon.get("ReserveAmmo") != null:
			_update_ammo_label_magazine(weapon.CurrentAmmo, weapon.ReserveAmmo)


## Configure Makarov PM ammo - 2.5x magazines (Issue #1422).
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
		_log_to_file("Gunslinger/PowerFantasy mode: MakarovPM magazines multiplied by %dx" % ammo_multiplier)
	if weapon.has_method("ReinitializeMagazines"):
		weapon.ReinitializeMagazines(pm_magazines, true)
		_log_to_file("2.5x ammo for MakarovPM: %d magazines (was %d)" % [pm_magazines, starting_magazines])
		if weapon.get("CurrentAmmo") != null and weapon.get("ReserveAmmo") != null:
			_update_ammo_label_magazine(weapon.CurrentAmmo, weapon.ReserveAmmo)
	if _player != null and _player.has_method("ApplyAutoReloadAfterLevelAmmoConfig"):
		_player.ApplyAutoReloadAfterLevelAmmoConfig()


## Apply Labyrinth2 level ammo configuration to a weapon (Issue #1422).
## Silenced pistol: exactly as many bullets as enemies.
## Mini UZI and rifles: 2 magazines to match level difficulty.
## Shotgun, sniper, revolver: defaults are sufficient for 17 enemies.
func _configure_labyrinth2_weapon_ammo(weapon: Node, weapon_id: String) -> void:
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
				_log_to_file("Power Fantasy mode - %s magazines multiplied by %dx" % [weapon.name, ammo_multiplier])
		if weapon.has_method("ReinitializeMagazines"):
			weapon.ReinitializeMagazines(base_magazines, true)
			_log_to_file("%s magazines reinitialized to %d" % [weapon.name, base_magazines])
		if weapon.get("CurrentAmmo") != null and weapon.get("ReserveAmmo") != null:
			_update_ammo_label_magazine(weapon.CurrentAmmo, weapon.ReserveAmmo)

	if _player != null and _player.has_method("ApplyAutoReloadAfterLevelAmmoConfig"):
		_player.ApplyAutoReloadAfterLevelAmmoConfig()
		_log_to_file("Re-applied auto-reload magazine reduction after ammo config for %s" % weapon_id)


## Setup and equip the weapon selected by the player (Issue #1422).
func _setup_selected_weapon() -> void:
	if _player == null:
		return

	var selected_weapon_id: String = "makarov_pm"
	if GameManager:
		selected_weapon_id = GameManager.get_selected_weapon()

	_log_to_file("Setting up weapon: %s" % selected_weapon_id)

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
				_log_to_file("%s already equipped by C# Player - applying labyrinth2 ammo config" % expected_name)
				_configure_labyrinth2_weapon_ammo(existing_weapon, selected_weapon_id)
				return

	if selected_weapon_id == "shotgun":
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov: makarov.queue_free()
		var shotgun_scene = load("res://scenes/weapons/csharp/Shotgun.tscn")
		if shotgun_scene:
			var shotgun = shotgun_scene.instantiate()
			shotgun.name = "Shotgun"
			_player.add_child(shotgun)
			if _player.has_method("EquipWeapon"): _player.EquipWeapon(shotgun)
			elif _player.get("CurrentWeapon") != null: _player.CurrentWeapon = shotgun
			_log_to_file("Shotgun equipped")
		else:
			push_error("[Labyrinth2Level] Failed to load Shotgun scene!")
	elif selected_weapon_id == "mini_uzi":
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov: makarov.queue_free()
		var mini_uzi_scene = load("res://scenes/weapons/csharp/MiniUzi.tscn")
		if mini_uzi_scene:
			var mini_uzi = mini_uzi_scene.instantiate()
			mini_uzi.name = "MiniUzi"
			if mini_uzi.get("StartingMagazineCount") != null:
				mini_uzi.StartingMagazineCount = 2
			_player.add_child(mini_uzi)
			if _player.has_method("EquipWeapon"): _player.EquipWeapon(mini_uzi)
			elif _player.get("CurrentWeapon") != null: _player.CurrentWeapon = mini_uzi
			_configure_labyrinth2_weapon_ammo(mini_uzi, "mini_uzi")
			_log_to_file("Mini UZI equipped")
		else:
			push_error("[Labyrinth2Level] Failed to load MiniUzi scene!")
	elif selected_weapon_id == "silenced_pistol":
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov: makarov.queue_free()
		var pistol_scene = load("res://scenes/weapons/csharp/SilencedPistol.tscn")
		if pistol_scene:
			var pistol = pistol_scene.instantiate()
			pistol.name = "SilencedPistol"
			_player.add_child(pistol)
			if _player.has_method("EquipWeapon"): _player.EquipWeapon(pistol)
			elif _player.get("CurrentWeapon") != null: _player.CurrentWeapon = pistol
			_configure_labyrinth2_weapon_ammo(pistol, "silenced_pistol")
			_log_to_file("Silenced Pistol equipped")
		else:
			push_error("[Labyrinth2Level] Failed to load SilencedPistol scene!")
	elif selected_weapon_id == "sniper":
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov: makarov.queue_free()
		var sniper_scene = load("res://scenes/weapons/csharp/SniperRifle.tscn")
		if sniper_scene:
			var sniper = sniper_scene.instantiate()
			sniper.name = "SniperRifle"
			_player.add_child(sniper)
			if _player.has_method("EquipWeapon"): _player.EquipWeapon(sniper)
			elif _player.get("CurrentWeapon") != null: _player.CurrentWeapon = sniper
			_log_to_file("ASVK Sniper Rifle equipped")
		else:
			push_error("[Labyrinth2Level] Failed to load SniperRifle scene!")
	elif selected_weapon_id == "m16":
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov: makarov.queue_free()
		var m16_scene = load("res://scenes/weapons/csharp/AssaultRifle.tscn")
		if m16_scene:
			var m16 = m16_scene.instantiate()
			m16.name = "AssaultRifle"
			_player.add_child(m16)
			if _player.has_method("EquipWeapon"): _player.EquipWeapon(m16)
			elif _player.get("CurrentWeapon") != null: _player.CurrentWeapon = m16
			_configure_labyrinth2_weapon_ammo(m16, "m16")
			_log_to_file("M16 Assault Rifle equipped")
		else:
			push_error("[Labyrinth2Level] Failed to load AssaultRifle scene!")
	elif selected_weapon_id == "ak_gl":
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov: makarov.queue_free()
		var akgl_scene = load("res://scenes/weapons/csharp/AKGL.tscn")
		if akgl_scene:
			var akgl = akgl_scene.instantiate()
			akgl.name = "AKGL"
			_player.add_child(akgl)
			if _player.has_method("EquipWeapon"): _player.EquipWeapon(akgl)
			elif _player.get("CurrentWeapon") != null: _player.CurrentWeapon = akgl
			_configure_labyrinth2_weapon_ammo(akgl, "ak_gl")
			_log_to_file("AK + GL equipped")
		else:
			push_error("[Labyrinth2Level] Failed to load AKGL scene!")
	elif selected_weapon_id == "revolver":
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov: makarov.queue_free()
		var revolver_scene = load("res://scenes/weapons/csharp/Revolver.tscn")
		if revolver_scene:
			var revolver = revolver_scene.instantiate()
			revolver.name = "Revolver"
			_player.add_child(revolver)
			if _player.has_method("EquipWeapon"): _player.EquipWeapon(revolver)
			elif _player.get("CurrentWeapon") != null: _player.CurrentWeapon = revolver
			_log_to_file("RSh-12 Revolver equipped")
		else:
			push_error("[Labyrinth2Level] Failed to load Revolver scene!")
	else:
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov and _player.get("CurrentWeapon") == null:
			if _player.has_method("EquipWeapon"): _player.EquipWeapon(makarov)
			elif _player.get("CurrentWeapon") != null: _player.CurrentWeapon = makarov
			_configure_makarov_pm_ammo(makarov)


## Log a message to the level log file for debugging.
func _log_to_file(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[Labyrinth2Level] " + message)
	else:
		print("[Labyrinth2Level] " + message)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_Q:
			# Block restart while the score screen animation is playing so the
			# player can always see the Armory button before restarting (Issue #1589).
			var game_manager: Node = get_node_or_null("/root/GameManager")
			if game_manager and game_manager.get("score_screen_active"):
				return
			get_tree().reload_current_scene()


## Handle W key shortcut for Watch Replay when score is shown (Issue #807: check experimental setting).
func _unhandled_input(event: InputEvent) -> void:
	if not _score_shown:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_W:
			# Issue #807: Only trigger replay if enabled in experimental settings
			var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
			if experimental_settings and experimental_settings.has_method("is_replay_enabled") and experimental_settings.is_replay_enabled():
				_on_watch_replay_pressed()
