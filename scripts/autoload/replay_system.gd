extends Node
## Autoload singleton for recording and playing back game replays.
##
## Records entity positions, rotations, and key events each physics frame.
## Provides playback functionality to watch completed levels.
##
## Recording captures:
## - Player position, rotation, and model scale
## - Enemy positions, rotations, and alive state
## - Bullet positions and rotations
## - Grenade positions
## - Key events (shots, deaths, explosions)
##
## Playback recreates the visual representation without running game logic.

## Recording interval in seconds (physics frames).
const RECORD_INTERVAL: float = 1.0 / 60.0  # 60 FPS recording

## Maximum recording duration in seconds (prevent memory issues).
const MAX_RECORDING_DURATION: float = 300.0  # 5 minutes

## Frame data is stored as Dictionary with the following keys:
## - time: float
## - player_position: Vector2
## - player_rotation: float
## - player_model_scale: Vector2
## - player_alive: bool
## - enemies: Array of {position, rotation, alive}
## - bullets: Array of {position, rotation}
## - grenades: Array of {position}
## - events: Array of event strings for this frame
##
## Note: Inner classes are avoided to prevent parse errors in exported builds
## (Godot 4.3 has issues with inner classes in autoload scripts during export)


## All recorded frames for the current/last level.
var _frames: Array = []

## Current recording time.
var _recording_time: float = 0.0

## Whether we are currently recording.
var _is_recording: bool = false

## Whether we are currently playing back.
var _is_playing_back: bool = false

## Whether playback ending is scheduled (replaces await in _physics_process).
var _playback_ending: bool = false

## Timer for playback end delay.
var _playback_end_timer: float = 0.0

## Current playback frame index.
var _playback_frame: int = 0

## Playback speed multiplier (1.0 = normal, 2.0 = 2x speed).
var _playback_speed: float = 1.0

## Accumulated time for playback interpolation.
var _playback_time: float = 0.0

## Reference to the level node being recorded.
var _level_node: Node2D = null

## Reference to the player node.
var _player: Node2D = null

## References to enemy nodes (for recording).
var _enemies: Array = []

## Path to the Entities/Projectiles node for recording bullets.
var _projectiles_path: String = "Entities/Projectiles"

## Replay ghost nodes (created during playback).
var _ghost_player: Node2D = null
var _ghost_enemies: Array = []
var _ghost_bullets: Array = []
var _ghost_grenades: Array = []

## Replay UI overlay.
var _replay_ui: CanvasLayer = null

## Signal emitted when replay playback ends.
signal replay_ended

## Signal emitted when replay playback starts.
signal replay_started

## Signal emitted when playback progress changes.
signal playback_progress(current_time: float, total_time: float)


## Creates a new frame data dictionary with default values.
func _create_frame_data() -> Dictionary:
	return {
		"time": 0.0,
		"player_position": Vector2.ZERO,
		"player_rotation": 0.0,
		"player_model_scale": Vector2.ONE,
		"player_alive": true,
		"enemies": [],
		"bullets": [],
		"grenades": [],
		"events": []
	}


func _ready() -> void:
	# Run in PROCESS_MODE_ALWAYS to work during pause
	process_mode = Node.PROCESS_MODE_ALWAYS
	_log_to_file("ReplayManager ready")


func _physics_process(delta: float) -> void:
	if _is_recording:
		_record_frame(delta)
	elif _playback_ending:
		# Handle delayed playback end (replaces await to avoid coroutine in _physics_process)
		_playback_end_timer -= delta
		if _playback_end_timer <= 0.0:
			_playback_ending = false
			stop_playback()
	elif _is_playing_back:
		_playback_frame_update(delta)


## Starts recording a new replay for the given level.
## @param level: The level node to record.
## @param player: The player node.
## @param enemies: Array of enemy nodes.
func start_recording(level: Node2D, player: Node2D, enemies: Array) -> void:
	_frames.clear()
	_recording_time = 0.0
	_is_recording = true
	_is_playing_back = false
	_level_node = level
	_player = player
	_enemies = enemies.duplicate()

	# Detailed logging for debugging
	var player_name: String = player.name if player else "NULL"
	var player_valid: bool = player != null and is_instance_valid(player)
	var level_name: String = level.name if level else "NULL"

	_log_to_file("=== REPLAY RECORDING STARTED ===")
	_log_to_file("Level: %s" % level_name)
	_log_to_file("Player: %s (valid: %s)" % [player_name, player_valid])
	_log_to_file("Enemies count: %d" % enemies.size())

	# Log each enemy for debugging
	for i in range(enemies.size()):
		var enemy: Node = enemies[i]
		if enemy and is_instance_valid(enemy):
			_log_to_file("  Enemy %d: %s" % [i, enemy.name])
		else:
			_log_to_file("  Enemy %d: INVALID" % i)

	print("[ReplayManager] Recording started: Level=%s, Player=%s, Enemies=%d" % [level_name, player_name, enemies.size()])


## Stops recording and saves the replay data.
func stop_recording() -> void:
	if not _is_recording:
		_log_to_file("stop_recording called but was not recording")
		print("[ReplayManager] stop_recording called but was not recording")
		return

	_is_recording = false
	_log_to_file("=== REPLAY RECORDING STOPPED ===")
	_log_to_file("Total frames recorded: %d" % _frames.size())
	_log_to_file("Total duration: %.2fs" % _recording_time)
	_log_to_file("has_replay() will return: %s" % (_frames.size() > 0))
	print("[ReplayManager] Recording stopped: %d frames, %.2fs duration" % [_frames.size(), _recording_time])


## Returns true if there is a recorded replay available.
func has_replay() -> bool:
	return _frames.size() > 0


## Returns the duration of the recorded replay in seconds.
func get_replay_duration() -> float:
	if _frames.is_empty():
		return 0.0
	return _frames[-1].time


## Starts playback of the recorded replay.
## @param level: The level node where replay will be shown (reloaded scene).
func start_playback(level: Node2D) -> void:
	if _frames.is_empty():
		_log_to_file("Cannot start playback: no frames recorded")
		return

	_is_playing_back = true
	_is_recording = false
	_playback_ending = false
	_playback_end_timer = 0.0
	_playback_frame = 0
	_playback_time = 0.0
	_playback_speed = 1.0
	_level_node = level

	# Create ghost entities for visualization
	_create_ghost_entities(level)

	# Create replay UI
	_create_replay_ui(level)

	# Pause the game tree so real entities don't move
	# But we need our replay ghosts to update, so they should be PROCESS_MODE_ALWAYS
	level.get_tree().paused = true

	replay_started.emit()
	_log_to_file("Started replay playback. Frames: %d, Duration: %.2fs" % [
		_frames.size(),
		get_replay_duration()
	])


## Stops playback and cleans up.
func stop_playback() -> void:
	if not _is_playing_back and not _playback_ending:
		return

	_is_playing_back = false
	_playback_ending = false
	_playback_end_timer = 0.0

	# Clean up ghost entities
	_cleanup_ghost_entities()

	# Clean up replay UI
	if _replay_ui and is_instance_valid(_replay_ui):
		_replay_ui.queue_free()
		_replay_ui = null

	# Unpause the game
	if _level_node and is_instance_valid(_level_node):
		_level_node.get_tree().paused = false

	replay_ended.emit()
	_log_to_file("Stopped replay playback")


## Sets the playback speed.
## @param speed: Speed multiplier (1.0 = normal, 2.0 = 2x, 0.5 = half speed).
func set_playback_speed(speed: float) -> void:
	_playback_speed = clampf(speed, 0.25, 4.0)
	_log_to_file("Playback speed set to %.2fx" % _playback_speed)


## Gets the current playback speed.
func get_playback_speed() -> float:
	return _playback_speed


## Returns whether replay is currently playing.
func is_replaying() -> bool:
	return _is_playing_back


## Returns whether replay is currently recording.
func is_recording() -> bool:
	return _is_recording


## Seeks to a specific time in the replay.
## @param time: Time in seconds to seek to.
func seek_to(time: float) -> void:
	if _frames.is_empty():
		return

	time = clampf(time, 0.0, get_replay_duration())
	_playback_time = time

	# Find the frame at or before this time
	for i in range(_frames.size()):
		if _frames[i].time >= time:
			_playback_frame = maxi(0, i - 1)
			break

	# Update visuals immediately
	_apply_frame_dict(_frames[_playback_frame])


## Records a single frame of game state.
func _record_frame(delta: float) -> void:
	_recording_time += delta

	# Check max duration
	if _recording_time > MAX_RECORDING_DURATION:
		_log_to_file("Max recording duration reached, stopping")
		stop_recording()
		return

	var frame := _create_frame_data()
	frame.time = _recording_time

	# Debug log every 60 frames (once per second at 60 FPS)
	if _frames.size() % 60 == 0:
		_log_to_file("Recording frame %d (%.1fs): player_valid=%s, enemies=%d" % [
			_frames.size(),
			_recording_time,
			(_player != null and is_instance_valid(_player)),
			_enemies.size()
		])

	# Record player state
	if _player and is_instance_valid(_player):
		frame.player_position = _player.global_position
		frame.player_rotation = _player.global_rotation
		frame.player_alive = true

		# Get player model scale for proper sprite flipping
		var player_model: Node2D = _player.get_node_or_null("PlayerModel")
		if player_model:
			frame.player_model_scale = player_model.scale

		# Check if player is alive (GDScript or C#)
		if _player.get("_is_alive") != null:
			frame.player_alive = _player._is_alive
		elif _player.get("IsAlive") != null:
			frame.player_alive = _player.IsAlive
	else:
		frame.player_alive = false

	# Record enemy states
	for enemy in _enemies:
		if enemy and is_instance_valid(enemy):
			var enemy_data := {
				"position": enemy.global_position,
				"rotation": enemy.global_rotation,
				"alive": true
			}
			# Check if enemy is alive
			if enemy.has_method("is_alive"):
				enemy_data.alive = enemy.is_alive()
			elif enemy.get("_is_alive") != null:
				enemy_data.alive = enemy._is_alive
			frame.enemies.append(enemy_data)
		else:
			frame.enemies.append({
				"position": Vector2.ZERO,
				"rotation": 0.0,
				"alive": false
			})

	# Record projectiles (bullets)
	if _level_node and is_instance_valid(_level_node):
		var projectiles_node := _level_node.get_node_or_null(_projectiles_path)
		if projectiles_node == null:
			# Try alternative paths
			projectiles_node = _level_node.get_node_or_null("Projectiles")

		if projectiles_node:
			for projectile in projectiles_node.get_children():
				if projectile is Node2D:
					frame.bullets.append({
						"position": projectile.global_position,
						"rotation": projectile.global_rotation
					})

		# Record grenades
		var grenades_in_scene := _level_node.get_tree().get_nodes_in_group("grenades")
		for grenade in grenades_in_scene:
			if grenade is Node2D:
				frame.grenades.append({
					"position": grenade.global_position
				})

	_frames.append(frame)


## Updates playback by advancing time and applying the appropriate frame.
func _playback_frame_update(delta: float) -> void:
	if _frames.is_empty():
		stop_playback()
		return

	# Advance playback time
	_playback_time += delta * _playback_speed

	# Emit progress signal
	playback_progress.emit(_playback_time, get_replay_duration())

	# Check if playback is complete
	if _playback_time >= get_replay_duration():
		_playback_time = get_replay_duration()
		# Apply final frame
		_apply_frame_dict(_frames[-1])
		# Schedule playback end after a short delay (no await to avoid coroutine issues)
		_playback_ending = true
		_playback_end_timer = 0.5
		_is_playing_back = false
		return

	# Find the frame to display (interpolate between frames)
	while _playback_frame < _frames.size() - 1 and _frames[_playback_frame + 1].time <= _playback_time:
		_playback_frame += 1

	# Apply the current frame
	_apply_frame_dict(_frames[_playback_frame])


## Applies a frame's data (Dictionary) to the ghost entities.
func _apply_frame_dict(frame: Dictionary) -> void:
	# Update ghost player
	if _ghost_player and is_instance_valid(_ghost_player):
		_ghost_player.global_position = frame.player_position
		_ghost_player.global_rotation = frame.player_rotation
		_ghost_player.visible = frame.player_alive

		# Update player model scale for sprite flipping
		var ghost_model: Node2D = _ghost_player.get_node_or_null("PlayerModel")
		if ghost_model:
			ghost_model.scale = frame.player_model_scale

	# Update ghost enemies
	for i in range(mini(_ghost_enemies.size(), frame.enemies.size())):
		var ghost_enemy: Node2D = _ghost_enemies[i]
		var enemy_data: Dictionary = frame.enemies[i]

		if ghost_enemy and is_instance_valid(ghost_enemy):
			ghost_enemy.global_position = enemy_data.position
			ghost_enemy.global_rotation = enemy_data.rotation
			ghost_enemy.visible = enemy_data.alive

	# Update ghost bullets (create/remove as needed)
	_update_ghost_projectiles(frame.bullets, _ghost_bullets, "bullet")

	# Update ghost grenades
	_update_ghost_projectiles(frame.grenades, _ghost_grenades, "grenade")


## Updates ghost projectile entities to match frame data.
func _update_ghost_projectiles(projectile_data: Array, ghost_array: Array, projectile_type: String) -> void:
	# Remove excess ghosts
	while ghost_array.size() > projectile_data.size():
		var ghost: Node2D = ghost_array.pop_back()
		if ghost and is_instance_valid(ghost):
			ghost.queue_free()

	# Add new ghosts if needed
	while ghost_array.size() < projectile_data.size():
		var ghost := _create_projectile_ghost(projectile_type)
		if ghost:
			ghost_array.append(ghost)

	# Update positions
	for i in range(mini(ghost_array.size(), projectile_data.size())):
		var ghost: Node2D = ghost_array[i]
		var data: Dictionary = projectile_data[i]

		if ghost and is_instance_valid(ghost):
			ghost.global_position = data.position
			if data.has("rotation"):
				ghost.global_rotation = data.rotation
			ghost.visible = true


## Creates ghost entities for replay visualization.
func _create_ghost_entities(level: Node2D) -> void:
	_cleanup_ghost_entities()

	# Create a container for ghost entities
	var ghost_container := Node2D.new()
	ghost_container.name = "ReplayGhosts"
	ghost_container.process_mode = Node.PROCESS_MODE_ALWAYS
	level.add_child(ghost_container)

	# Create ghost player
	_ghost_player = _create_player_ghost()
	if _ghost_player:
		ghost_container.add_child(_ghost_player)

	# Create ghost enemies (one for each recorded enemy)
	if not _frames.is_empty() and not _frames[0].enemies.is_empty():
		for i in range(_frames[0].enemies.size()):
			var ghost_enemy := _create_enemy_ghost()
			if ghost_enemy:
				ghost_container.add_child(ghost_enemy)
				_ghost_enemies.append(ghost_enemy)

	# Hide original entities
	_hide_original_entities(level)


## Creates a ghost representation of the player.
func _create_player_ghost() -> Node2D:
	# Try to load the player scene and create a visual-only copy
	var player_scene: PackedScene = load("res://scenes/characters/Player.tscn")
	if player_scene:
		var ghost: Node2D = player_scene.instantiate()
		ghost.name = "GhostPlayer"
		ghost.process_mode = Node.PROCESS_MODE_ALWAYS

		# Disable all scripts/processing - we only want visuals
		_disable_node_processing(ghost)

		# Add a slight transparency to indicate it's a replay
		_set_ghost_modulate(ghost, Color(1.0, 1.0, 1.0, 0.9))

		return ghost

	# Fallback: create a simple colored rectangle
	var ghost := Node2D.new()
	ghost.name = "GhostPlayer"
	var sprite := Sprite2D.new()
	sprite.texture = PlaceholderTexture2D.new()
	sprite.modulate = Color(0.2, 0.6, 1.0, 0.8)
	ghost.add_child(sprite)
	return ghost


## Creates a ghost representation of an enemy.
func _create_enemy_ghost() -> Node2D:
	# Try to load the enemy scene
	var enemy_scene: PackedScene = load("res://scenes/objects/Enemy.tscn")
	if enemy_scene:
		var ghost: Node2D = enemy_scene.instantiate()
		ghost.name = "GhostEnemy"
		ghost.process_mode = Node.PROCESS_MODE_ALWAYS

		# Disable all scripts/processing
		_disable_node_processing(ghost)

		# Add transparency
		_set_ghost_modulate(ghost, Color(1.0, 1.0, 1.0, 0.9))

		return ghost

	# Fallback
	var ghost := Node2D.new()
	ghost.name = "GhostEnemy"
	var sprite := Sprite2D.new()
	sprite.texture = PlaceholderTexture2D.new()
	sprite.modulate = Color(1.0, 0.2, 0.2, 0.8)
	ghost.add_child(sprite)
	return ghost


## Creates a ghost representation of a projectile.
func _create_projectile_ghost(projectile_type: String) -> Node2D:
	var ghost := Node2D.new()
	ghost.name = "Ghost" + projectile_type.capitalize()
	ghost.process_mode = Node.PROCESS_MODE_ALWAYS

	# Create a simple visual representation
	var sprite := Sprite2D.new()

	if projectile_type == "bullet":
		# Small yellow rectangle for bullet
		var texture := GradientTexture2D.new()
		texture.width = 8
		texture.height = 3
		texture.fill_from = Vector2(0, 0)
		texture.fill_to = Vector2(1, 0)
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1.0, 0.9, 0.2, 1.0))
		gradient.set_color(1, Color(1.0, 0.7, 0.1, 1.0))
		texture.gradient = gradient
		sprite.texture = texture
	else:
		# Circle for grenade
		var texture := GradientTexture2D.new()
		texture.width = 12
		texture.height = 12
		texture.fill = GradientTexture2D.FILL_RADIAL
		var gradient := Gradient.new()
		gradient.set_color(0, Color(0.2, 0.5, 0.2, 1.0))
		gradient.set_color(1, Color(0.1, 0.3, 0.1, 0.5))
		texture.gradient = gradient
		sprite.texture = texture

	ghost.add_child(sprite)

	# Add to level
	if _level_node and is_instance_valid(_level_node):
		var ghost_container := _level_node.get_node_or_null("ReplayGhosts")
		if ghost_container:
			ghost_container.add_child(ghost)

	return ghost


## Disables processing on a node and all its children.
func _disable_node_processing(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)

	# Remove scripts to prevent any initialization logic
	if node.get_script():
		node.set_script(null)

	# Disable collision
	if node is CollisionObject2D:
		node.set_collision_layer(0)
		node.set_collision_mask(0)

	# Recursively disable children
	for child in node.get_children():
		_disable_node_processing(child)


## Sets modulate color on a node and all its sprite children.
func _set_ghost_modulate(node: Node, color: Color) -> void:
	if node is CanvasItem:
		node.modulate = color

	for child in node.get_children():
		_set_ghost_modulate(child, color)


## Hides the original game entities during replay.
func _hide_original_entities(level: Node2D) -> void:
	# Hide player
	var player := level.get_node_or_null("Entities/Player")
	if player:
		player.visible = false

	# Hide enemies
	var enemies_node := level.get_node_or_null("Environment/Enemies")
	if enemies_node:
		for enemy in enemies_node.get_children():
			enemy.visible = false

	# Hide projectiles
	var projectiles := level.get_node_or_null("Entities/Projectiles")
	if projectiles:
		projectiles.visible = false


## Cleans up ghost entities.
func _cleanup_ghost_entities() -> void:
	if _ghost_player and is_instance_valid(_ghost_player):
		_ghost_player.queue_free()
	_ghost_player = null

	for ghost in _ghost_enemies:
		if ghost and is_instance_valid(ghost):
			ghost.queue_free()
	_ghost_enemies.clear()

	for ghost in _ghost_bullets:
		if ghost and is_instance_valid(ghost):
			ghost.queue_free()
	_ghost_bullets.clear()

	for ghost in _ghost_grenades:
		if ghost and is_instance_valid(ghost):
			ghost.queue_free()
	_ghost_grenades.clear()

	# Remove ghost container
	if _level_node and is_instance_valid(_level_node):
		var ghost_container := _level_node.get_node_or_null("ReplayGhosts")
		if ghost_container:
			ghost_container.queue_free()


## Creates the replay UI overlay.
func _create_replay_ui(level: Node2D) -> void:
	_replay_ui = CanvasLayer.new()
	_replay_ui.name = "ReplayUI"
	_replay_ui.layer = 100  # On top of everything
	_replay_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	level.add_child(_replay_ui)

	# Create container
	var container := VBoxContainer.new()
	container.set_anchors_preset(Control.PRESET_BOTTOM_CENTER)
	container.offset_left = -200
	container.offset_right = 200
	container.offset_top = -120
	container.offset_bottom = -20
	container.add_theme_constant_override("separation", 10)
	_replay_ui.add_child(container)

	# Replay label
	var replay_label := Label.new()
	replay_label.text = "▶ REPLAY"
	replay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	replay_label.add_theme_font_size_override("font_size", 24)
	replay_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2, 1.0))
	container.add_child(replay_label)

	# Progress bar
	var progress_container := HBoxContainer.new()
	progress_container.add_theme_constant_override("separation", 10)
	container.add_child(progress_container)

	var time_label := Label.new()
	time_label.name = "TimeLabel"
	time_label.text = "0:00"
	time_label.add_theme_font_size_override("font_size", 16)
	progress_container.add_child(time_label)

	var progress_bar := ProgressBar.new()
	progress_bar.name = "ProgressBar"
	progress_bar.custom_minimum_size.x = 300
	progress_bar.min_value = 0.0
	progress_bar.max_value = get_replay_duration()
	progress_bar.value = 0.0
	progress_bar.show_percentage = false
	progress_container.add_child(progress_bar)

	var duration_label := Label.new()
	duration_label.name = "DurationLabel"
	var duration := get_replay_duration()
	duration_label.text = "%d:%02d" % [int(duration) / 60, int(duration) % 60]
	duration_label.add_theme_font_size_override("font_size", 16)
	progress_container.add_child(duration_label)

	# Speed controls
	var speed_container := HBoxContainer.new()
	speed_container.add_theme_constant_override("separation", 15)
	speed_container.alignment = BoxContainer.ALIGNMENT_CENTER
	container.add_child(speed_container)

	var speeds := [0.5, 1.0, 2.0, 4.0]
	for speed in speeds:
		var btn := Button.new()
		btn.text = "%.1fx" % speed if speed < 1.0 else "%dx" % int(speed)
		btn.custom_minimum_size = Vector2(50, 30)
		btn.pressed.connect(_on_speed_button_pressed.bind(speed))
		speed_container.add_child(btn)

	# Exit button
	var exit_btn := Button.new()
	exit_btn.text = "Exit Replay (ESC)"
	exit_btn.custom_minimum_size = Vector2(150, 40)
	exit_btn.pressed.connect(_on_exit_replay_pressed)
	container.add_child(exit_btn)

	# Connect progress signal to update UI
	if not playback_progress.is_connected(_update_replay_ui):
		playback_progress.connect(_update_replay_ui)


## Updates the replay UI with current progress.
func _update_replay_ui(current_time: float, total_time: float) -> void:
	if not _replay_ui or not is_instance_valid(_replay_ui):
		return

	var progress_bar: ProgressBar = _replay_ui.get_node_or_null("VBoxContainer/HBoxContainer/ProgressBar")
	if progress_bar:
		progress_bar.value = current_time

	var time_label: Label = _replay_ui.get_node_or_null("VBoxContainer/HBoxContainer/TimeLabel")
	if time_label:
		time_label.text = "%d:%02d" % [int(current_time) / 60, int(current_time) % 60]


## Called when speed button is pressed.
func _on_speed_button_pressed(speed: float) -> void:
	set_playback_speed(speed)


## Called when exit replay button is pressed.
func _on_exit_replay_pressed() -> void:
	stop_playback()
	# Restart the level
	if _level_node and is_instance_valid(_level_node):
		_level_node.get_tree().paused = false
		_level_node.get_tree().reload_current_scene()


func _input(event: InputEvent) -> void:
	if not _is_playing_back and not _playback_ending:
		return

	# Handle ESC to exit replay
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_on_exit_replay_pressed()
		# Handle speed controls with number keys
		elif event.keycode == KEY_1:
			set_playback_speed(0.5)
		elif event.keycode == KEY_2:
			set_playback_speed(1.0)
		elif event.keycode == KEY_3:
			set_playback_speed(2.0)
		elif event.keycode == KEY_4:
			set_playback_speed(4.0)


## Clears the recorded replay data.
func clear_replay() -> void:
	_frames.clear()
	_recording_time = 0.0
	_is_recording = false
	_log_to_file("Replay data cleared")


## Log a message to the file logger if available.
func _log_to_file(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[ReplayManager] " + message)
	else:
		print("[ReplayManager] " + message)
