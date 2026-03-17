extends Node2D
## Labyrinth 2 level scene for the Godot Top-Down Template.
##
## This scene is a larger labyrinth-style building with more rooms and enemies.
## Similar to BuildingLevel but with more interconnected rooms and corridors,
## making navigation more maze-like and challenging.
## Features:
## - Larger labyrinth layout (~3200x2400 pixels) for more exploration
## - 14 enemies distributed across many rooms (more than BuildingLevel)
## - More rooms with narrower corridors for a true labyrinth feel
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

## Reference to the kills label.
var _kills_label: Label = null

## Reference to the accuracy label.
var _accuracy_label: Label = null

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

	# Start replay recording
	_start_replay_recording()


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


## Called when combo changes.
func _on_combo_changed(combo: int, points: int) -> void:
	if _combo_label == null:
		return

	if combo > 0:
		_combo_label.text = "x%d COMBO (+%d)" % [combo, points]
		_combo_label.visible = true
		var combo_color := _get_combo_color(combo)
		_combo_label.add_theme_color_override("font_color", combo_color)
		_combo_label.modulate = Color.WHITE
		var tween := create_tween()
		tween.tween_property(_combo_label, "modulate", Color.WHITE, 0.1)
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
func _setup_navigation() -> void:
	var nav_region: NavigationRegion2D = get_node_or_null("NavigationRegion2D")
	if nav_region == null:
		push_warning("NavigationRegion2D not found - enemy pathfinding will be limited")
		return

	var nav_poly: NavigationPolygon = nav_region.navigation_polygon
	if nav_poly == null:
		push_warning("NavigationPolygon not found - enemy pathfinding will be limited")
		return

	print("Baking navigation mesh...")
	NavigationServer2D.bake_from_source_geometry_data(nav_poly, NavigationMeshSourceGeometryData2D.new())
	nav_region.bake_navigation_polygon()
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

	_initial_enemy_count = _enemies.size()
	_current_enemy_count = _initial_enemy_count
	print("[Labyrinth2Level] Tracking %d enemies" % _initial_enemy_count)


## Setup player tracking and connect signals.
func _setup_player_tracking() -> void:
	_player = get_node_or_null("Entities/Player")
	if _player == null:
		push_warning("Player not found")
		return

	if _player.has_signal("ammo_changed"):
		_player.ammo_changed.connect(_on_ammo_changed)

	_ammo_label = get_node_or_null("CanvasLayer/UI/AmmoLabel")

	if _player.has_method("get_ammo_info"):
		var ammo_info = _player.get_ammo_info()
		if _ammo_label:
			_ammo_label.text = "AMMO: %s" % str(ammo_info)


## Setup debug UI labels.
func _setup_debug_ui() -> void:
	_kills_label = get_node_or_null("CanvasLayer/UI/KillsLabel")
	_accuracy_label = get_node_or_null("CanvasLayer/UI/AccuracyLabel")
	_magazines_label = get_node_or_null("CanvasLayer/UI/MagazinesLabel")
	_combo_label = get_node_or_null("CanvasLayer/UI/ComboLabel")
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

	if _current_enemy_count <= 0:
		_level_cleared = true
		_activate_exit_zone()
		print("[Labyrinth2Level] All enemies eliminated! Go to exit.")


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

	if _kills_label and GameManager.has_method("get_kill_count"):
		_kills_label.text = "Kills: %d" % GameManager.get_kill_count()

	if _accuracy_label and GameManager.has_method("get_accuracy"):
		var acc: float = GameManager.get_accuracy()
		_accuracy_label.text = "Accuracy: %.0f%%" % (acc * 100.0)


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

	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager and score_manager.has_method("end_level"):
		score_manager.end_level()

	print("[Labyrinth2Level] Level complete!")


## Log a message to the level log file for debugging.
func _log_to_file(message: String) -> void:
	print("[Labyrinth2Level] " + message)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_Q:
			get_tree().reload_current_scene()
		elif event.keycode == KEY_W and _level_cleared:
			_complete_level_with_score()
