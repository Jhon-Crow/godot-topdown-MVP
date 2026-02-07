extends Node
## Autoload singleton for recording and playing back game replays.
##
## Records entity positions, rotations, and key events each physics frame.
## Provides playback functionality to watch completed levels.
##
## Recording captures:
## - Player position, rotation, model scale, and health color
## - Enemy positions, rotations, alive state, and health color
## - Bullet positions and rotations
## - Grenade positions
## - Sound events (shots, hits, deaths) with positions
## - Blood decal and casing positions (for progressive floor effects)
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
## - player_color: Color (health-based sprite color)
## - enemies: Array of {position, rotation, alive, color}
## - bullets: Array of {position, rotation}
## - grenades: Array of {position}
## - events: Array of {type, position, ...} event dictionaries
## - blood_decals: Array of {position, rotation, scale} (cumulative floor state)
## - casings: Array of {position, rotation} (cumulative floor state)
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

## Ghost trail line for the player (Issue #544: trail should follow contour).
var _ghost_player_trail: Line2D = null

## Maximum number of trail points for the ghost player trail.
const GHOST_TRAIL_MAX_POINTS: int = 20

## Blood decal and casing ghost nodes spawned during playback.
var _replay_blood_decals: Array = []
var _replay_casings: Array = []

## Tracks how many blood decals / casings have been spawned so far in playback.
var _spawned_blood_count: int = 0
var _spawned_casing_count: int = 0

## Baseline count of blood decals and casings from frame 0 (Issue #544 fix 5b).
## These exist before the replay starts and should NOT be spawned during playback.
var _baseline_blood_count: int = 0
var _baseline_casing_count: int = 0

## Tracks the last frame index that was applied (for event playback).
var _last_applied_frame: int = -1

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
		"player_color": Color(0.2, 0.6, 1.0, 1.0),
		"enemies": [],
		"bullets": [],
		"grenades": [],
		"events": [],
		"blood_decals": [],
		"casings": []
	}


func _ready() -> void:
	# Run in PROCESS_MODE_ALWAYS to work during pause
	process_mode = Node.PROCESS_MODE_ALWAYS
	_log_to_file("ReplayManager ready (script loaded and _ready called)")
	_log_to_file("ReplayManager methods: start_recording=%s, stop_recording=%s, has_replay=%s, start_playback=%s" % [
		has_method("start_recording"),
		has_method("stop_recording"),
		has_method("has_replay"),
		has_method("start_playback")
	])
	var scr = get_script()
	var script_path: String = scr.resource_path if scr else "NO SCRIPT"
	_log_to_file("ReplayManager script path: %s" % script_path)
	_log_to_file("ReplayManager script has source: %s" % (scr.has_source_code() if scr else false))


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
	_last_applied_frame = -1
	_spawned_blood_count = 0
	_spawned_casing_count = 0

	# Determine baseline floor state from first frame (Issue #544 fix 5b)
	# Blood and casings already present at recording start should NOT be re-spawned.
	_baseline_blood_count = 0
	_baseline_casing_count = 0
	if not _frames.is_empty():
		if _frames[0].has("blood_decals"):
			_baseline_blood_count = _frames[0].blood_decals.size()
		if _frames[0].has("casings"):
			_baseline_casing_count = _frames[0].casings.size()

	# Clean the floor of existing blood and casings (Issue #544 fix 5)
	_clean_floor(level)

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
	_last_applied_frame = -1

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

		# Record player health color (Issue #544 fix 3, 6)
		var body_sprite: Sprite2D = _player.get_node_or_null("PlayerModel/Body")
		if body_sprite:
			frame.player_color = body_sprite.modulate

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
				"alive": true,
				"color": Color(0.9, 0.2, 0.2, 1.0)
			}
			# Check if enemy is alive
			if enemy.has_method("is_alive"):
				enemy_data.alive = enemy.is_alive()
			elif enemy.get("_is_alive") != null:
				enemy_data.alive = enemy._is_alive

			# Record enemy health color (Issue #544 fix 3)
			var enemy_body: Sprite2D = enemy.get_node_or_null("EnemyModel/Body")
			if enemy_body:
				enemy_data.color = enemy_body.modulate
			elif not enemy_data.alive:
				enemy_data.color = Color(0.3, 0.3, 0.3, 0.5)

			frame.enemies.append(enemy_data)
		else:
			frame.enemies.append({
				"position": Vector2.ZERO,
				"rotation": 0.0,
				"alive": false,
				"color": Color(0.3, 0.3, 0.3, 0.5)
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

		# Record grenades (with texture path for proper visual during replay)
		var grenades_in_scene := _level_node.get_tree().get_nodes_in_group("grenades")
		for grenade in grenades_in_scene:
			if grenade is Node2D:
				var grenade_data := {
					"position": grenade.global_position,
					"rotation": grenade.global_rotation,
					"texture_path": ""
				}
				# Try to capture the grenade's sprite texture path for replay visuals
				var grenade_sprite: Sprite2D = grenade.get_node_or_null("Sprite2D")
				if grenade_sprite and grenade_sprite.texture:
					grenade_data.texture_path = grenade_sprite.texture.resource_path
				frame.grenades.append(grenade_data)

		# Record blood decals on the floor (Issue #544 fix 5)
		var blood_puddles := _level_node.get_tree().get_nodes_in_group("blood_puddle")
		for puddle in blood_puddles:
			if puddle is Sprite2D and is_instance_valid(puddle):
				frame.blood_decals.append({
					"position": puddle.global_position,
					"rotation": puddle.rotation,
					"scale": puddle.scale
				})

		# Record casings on the floor (Issue #544 fix 5)
		var casings := _level_node.get_tree().get_nodes_in_group("casings")
		for casing in casings:
			if casing is Node2D and is_instance_valid(casing):
				frame.casings.append({
					"position": casing.global_position,
					"rotation": casing.rotation
				})

	# Record sound events by detecting new bullets and enemy state changes (Issue #544 fix 2)
	_record_sound_events(frame)

	_frames.append(frame)


## Detects and records sound events by comparing current frame to previous.
## This captures shot sounds, hit sounds, and death sounds.
func _record_sound_events(frame: Dictionary) -> void:
	if _frames.is_empty():
		return

	var prev_frame: Dictionary = _frames[-1]

	# Detect new bullets (shot event) - if bullet count increased, a shot occurred
	if frame.bullets.size() > prev_frame.bullets.size():
		# Determine shot position from new bullets
		for i in range(prev_frame.bullets.size(), frame.bullets.size()):
			if i < frame.bullets.size():
				frame.events.append({
					"type": "shot",
					"position": frame.bullets[i].position
				})

	# Detect enemy deaths (death event)
	for i in range(mini(frame.enemies.size(), prev_frame.enemies.size())):
		if prev_frame.enemies[i].alive and not frame.enemies[i].alive:
			frame.events.append({
				"type": "death",
				"position": frame.enemies[i].position
			})

	# Detect enemy hits (health color change indicating damage)
	for i in range(mini(frame.enemies.size(), prev_frame.enemies.size())):
		if frame.enemies[i].alive and prev_frame.enemies[i].alive:
			var prev_color: Color = prev_frame.enemies[i].color
			var curr_color: Color = frame.enemies[i].color
			# White flash = hit (hit_flash_color is white)
			if curr_color.r > 0.95 and curr_color.g > 0.95 and curr_color.b > 0.95:
				frame.events.append({
					"type": "hit",
					"position": frame.enemies[i].position
				})

	# Detect player death
	if prev_frame.player_alive and not frame.player_alive:
		frame.events.append({
			"type": "player_death",
			"position": frame.player_position
		})

	# Detect player hit (white flash on player)
	if frame.player_alive and prev_frame.player_alive:
		var curr_p_color: Color = frame.player_color
		if curr_p_color.r > 0.95 and curr_p_color.g > 0.95 and curr_p_color.b > 0.95:
			frame.events.append({
				"type": "player_hit",
				"position": frame.player_position
			})

	# Detect penultimate hit state (player at 1 HP, dramatic slowdown active)
	# Check if PenultimateHitEffectsManager effect is currently active
	var penultimate_mgr: Node = get_node_or_null("/root/PenultimateHitEffectsManager")
	if penultimate_mgr and penultimate_mgr.get("_is_effect_active") != null:
		var is_active: bool = penultimate_mgr._is_effect_active
		var was_active: bool = false
		# Check previous frame for effect state (stored in events)
		for ev in prev_frame.events:
			if ev.type == "penultimate_hit":
				was_active = true
				break
		# Record penultimate hit event when effect becomes active
		if is_active and not was_active:
			frame.events.append({
				"type": "penultimate_hit",
				"position": frame.player_position
			})


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
	var prev_frame_idx := _playback_frame
	while _playback_frame < _frames.size() - 1 and _frames[_playback_frame + 1].time <= _playback_time:
		_playback_frame += 1

	# Play events for all frames we skipped over (Issue #544 fix 2)
	if _playback_frame > _last_applied_frame:
		for fi in range(maxi(_last_applied_frame + 1, 0), _playback_frame + 1):
			if fi < _frames.size():
				_play_frame_events(_frames[fi])
		_last_applied_frame = _playback_frame

	# Apply the current frame
	_apply_frame_dict(_frames[_playback_frame])


## Plays sound events and visual effects for a frame during playback.
## During replay, triggers visual effects but avoids modifying Engine.time_scale
## since the replay has its own timing system (Issue #544 fix 4).
func _play_frame_events(frame: Dictionary) -> void:
	if not frame.has("events"):
		return

	var audio_manager: Node = get_node_or_null("/root/AudioManager")

	for event in frame.events:
		var event_type: String = event.type
		var event_pos: Vector2 = event.position

		match event_type:
			"shot":
				# Play shot sound (Issue #544 fix 2)
				if audio_manager and audio_manager.has_method("play_m16_shot"):
					audio_manager.play_m16_shot(event_pos)
			"death":
				# Play lethal hit sound (Issue #544 fix 2)
				if audio_manager and audio_manager.has_method("play_hit_lethal"):
					audio_manager.play_hit_lethal(event_pos)
				# Trigger saturation effect only (no time slowdown during replay)
				_trigger_replay_hit_effect()
			"hit":
				# Play non-lethal hit sound (Issue #544 fix 2)
				if audio_manager and audio_manager.has_method("play_hit_non_lethal"):
					audio_manager.play_hit_non_lethal(event_pos)
				# Trigger saturation effect only (no time slowdown during replay)
				_trigger_replay_hit_effect()
			"player_death":
				if audio_manager and audio_manager.has_method("play_hit_lethal"):
					audio_manager.play_hit_lethal(event_pos)
			"player_hit":
				if audio_manager and audio_manager.has_method("play_hit_non_lethal"):
					audio_manager.play_hit_non_lethal(event_pos)
			"penultimate_hit":
				# Trigger penultimate hit saturation/contrast effect (Issue #544 fix 4)
				_trigger_replay_penultimate_effect()


## Triggers hit saturation effect during replay without modifying Engine.time_scale.
## In normal gameplay, HitEffectsManager.on_player_hit_enemy() slows time to 0.8x,
## but during replay we only want the saturation boost visual (Issue #544 fix 4).
func _trigger_replay_hit_effect() -> void:
	var hit_effects: Node = get_node_or_null("/root/HitEffectsManager")
	if hit_effects == null:
		return

	# Directly trigger saturation effect without time slowdown.
	# We access the saturation overlay to apply the boost manually.
	if hit_effects.has_method("_start_saturation_effect"):
		hit_effects._start_saturation_effect()
	elif hit_effects.has_method("on_player_hit_enemy"):
		# Fallback: call the full method but save/restore time_scale
		var saved_time_scale := Engine.time_scale
		hit_effects.on_player_hit_enemy()
		Engine.time_scale = saved_time_scale


## Triggers penultimate hit visual effects during replay (Issue #544 fix 4).
## Applies saturation/contrast boost without time slowdown.
func _trigger_replay_penultimate_effect() -> void:
	var penultimate_effects: Node = get_node_or_null("/root/PenultimateHitEffectsManager")
	if penultimate_effects == null:
		return

	# Access the saturation overlay directly to apply visual effect without time change
	if penultimate_effects.has_method("_start_penultimate_effect"):
		# Save time_scale, trigger effect, restore time_scale
		var saved_time_scale := Engine.time_scale
		penultimate_effects._start_penultimate_effect()
		Engine.time_scale = saved_time_scale


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

		# Apply player health color to all sprite parts (Issue #544 fix 3, 6)
		if frame.has("player_color"):
			_apply_color_to_ghost_sprites(_ghost_player, "PlayerModel", frame.player_color, frame.player_alive)

		# Update ghost player trail (Issue #544 fix 7)
		_update_ghost_player_trail(frame.player_position)

	# Update ghost enemies
	for i in range(mini(_ghost_enemies.size(), frame.enemies.size())):
		var ghost_enemy: Node2D = _ghost_enemies[i]
		var enemy_data: Dictionary = frame.enemies[i]

		if ghost_enemy and is_instance_valid(ghost_enemy):
			ghost_enemy.global_position = enemy_data.position
			ghost_enemy.global_rotation = enemy_data.rotation
			ghost_enemy.visible = enemy_data.alive

			# Apply enemy health color (Issue #544 fix 3)
			if enemy_data.has("color"):
				_apply_color_to_ghost_sprites(ghost_enemy, "EnemyModel", enemy_data.color, enemy_data.alive)

	# Update ghost bullets (create/remove as needed)
	_update_ghost_projectiles(frame.bullets, _ghost_bullets, "bullet")

	# Update ghost grenades
	_update_ghost_projectiles(frame.grenades, _ghost_grenades, "grenade")

	# Update floor blood decals progressively (Issue #544 fix 5)
	if frame.has("blood_decals"):
		_update_replay_blood_decals(frame.blood_decals)

	# Update floor casings progressively (Issue #544 fix 5)
	if frame.has("casings"):
		_update_replay_casings(frame.casings)


## Applies a health-based color to the sprite parts of a ghost entity.
## Handles both alive (health color) and dead (gray) states.
func _apply_color_to_ghost_sprites(ghost: Node2D, model_name: String, color: Color, is_alive: bool) -> void:
	var model: Node2D = ghost.get_node_or_null(model_name)
	if not model:
		return

	var target_color := color
	if not is_alive:
		target_color = Color(0.3, 0.3, 0.3, 0.5)

	# Apply to all sprite children of the model
	for child in model.get_children():
		if child is Sprite2D:
			child.modulate = target_color


## Updates the ghost player trailing line (Issue #544 fix 7).
func _update_ghost_player_trail(player_pos: Vector2) -> void:
	if not _ghost_player_trail or not is_instance_valid(_ghost_player_trail):
		return

	# Add current position as a new point
	_ghost_player_trail.add_point(player_pos)

	# Remove oldest points if over limit
	while _ghost_player_trail.get_point_count() > GHOST_TRAIL_MAX_POINTS:
		_ghost_player_trail.remove_point(0)


## Updates ghost projectile entities to match frame data.
func _update_ghost_projectiles(projectile_data: Array, ghost_array: Array, projectile_type: String) -> void:
	# Remove excess ghosts
	while ghost_array.size() > projectile_data.size():
		var ghost: Node2D = ghost_array.pop_back()
		if ghost and is_instance_valid(ghost):
			ghost.queue_free()

	# Add new ghosts if needed
	while ghost_array.size() < projectile_data.size():
		var texture_path := ""
		# For grenades, get texture path from the data for proper visual
		var idx := ghost_array.size()
		if projectile_type == "grenade" and idx < projectile_data.size():
			if projectile_data[idx].has("texture_path"):
				texture_path = projectile_data[idx].texture_path
		var ghost := _create_projectile_ghost(projectile_type, texture_path)
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

			# Update bullet trail (Issue #544 fix 1)
			if projectile_type == "bullet":
				_update_bullet_trail(ghost, data.position)


## Updates the trailing line on a ghost bullet for visual feedback.
func _update_bullet_trail(ghost: Node2D, current_pos: Vector2) -> void:
	var trail: Line2D = ghost.get_node_or_null("Trail")
	if not trail:
		return

	trail.add_point(current_pos)
	while trail.get_point_count() > 6:
		trail.remove_point(0)


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

	# Create ghost player trail (Issue #544 fix 7)
	_ghost_player_trail = _create_player_trail()
	ghost_container.add_child(_ghost_player_trail)

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
## Issue #544 fix 6: Player model looks the same as during gameplay.
func _create_player_ghost() -> Node2D:
	# Try to load the player scene and create a visual-only copy
	var player_scene: PackedScene = load("res://scenes/characters/Player.tscn")
	if player_scene:
		var ghost: Node2D = player_scene.instantiate()
		ghost.name = "GhostPlayer"
		ghost.process_mode = Node.PROCESS_MODE_ALWAYS

		# Disable all scripts/processing - we only want visuals
		_disable_node_processing(ghost)

		# Issue #544 fix 6: Do NOT apply a global modulate override.
		# The health color will be set per-frame via _apply_color_to_ghost_sprites()
		# so the player model looks the same as during gameplay.

		return ghost

	# Fallback: create a simple colored sprite
	var ghost := Node2D.new()
	ghost.name = "GhostPlayer"
	var sprite := Sprite2D.new()
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.6, 1.0, 0.8))
	sprite.texture = ImageTexture.create_from_image(img)
	ghost.add_child(sprite)
	return ghost


## Creates a trailing line that follows the player ghost contour (Issue #544 fix 7).
func _create_player_trail() -> Line2D:
	var trail := Line2D.new()
	trail.name = "GhostPlayerTrail"
	trail.process_mode = Node.PROCESS_MODE_ALWAYS
	trail.width = 3.0
	trail.default_color = Color(0.3, 0.7, 1.0, 0.5)
	trail.z_index = -1  # Render behind the player ghost

	# Create a gradient for the trail (fade out at the tail)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.3, 0.7, 1.0, 0.0))  # Tail: transparent
	gradient.set_color(1, Color(0.3, 0.7, 1.0, 0.6))  # Head: visible
	trail.gradient = gradient

	trail.joint_mode = Line2D.LINE_JOINT_ROUND
	trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	trail.end_cap_mode = Line2D.LINE_CAP_ROUND

	return trail


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

		# Issue #544 fix 3: Do NOT apply a global modulate override.
		# The health color will be set per-frame via _apply_color_to_ghost_sprites().

		return ghost

	# Fallback: create a simple colored sprite
	var ghost := Node2D.new()
	ghost.name = "GhostEnemy"
	var sprite := Sprite2D.new()
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 0.2, 0.2, 0.8))
	sprite.texture = ImageTexture.create_from_image(img)
	ghost.add_child(sprite)
	return ghost


## Creates a ghost representation of a projectile.
## Issue #544 fix 1: Bullets use actual Bullet.tscn scene for proper visuals.
## Issue #544 fix grenade: Grenades use actual grenade textures.
func _create_projectile_ghost(projectile_type: String, texture_path: String = "") -> Node2D:
	if projectile_type == "bullet":
		return _create_bullet_ghost()
	else:
		return _create_grenade_ghost(texture_path)


## Creates a ghost bullet using the actual Bullet.tscn scene (Issue #544 fix 1).
## This ensures the bullet looks identical to gameplay (proper sprite, trail, color).
func _create_bullet_ghost() -> Node2D:
	var ghost: Node2D = null

	# Try to load the actual bullet scene for visual fidelity
	if ResourceLoader.exists("res://scenes/projectiles/Bullet.tscn"):
		var bullet_scene: PackedScene = load("res://scenes/projectiles/Bullet.tscn")
		if bullet_scene:
			ghost = bullet_scene.instantiate()
			ghost.name = "GhostBullet"
			ghost.process_mode = Node.PROCESS_MODE_ALWAYS
			# Disable scripts and collision — visual only
			_disable_node_processing(ghost)
			# Re-add a fresh trail since the original Line2D may have been reset
			var original_trail: Line2D = ghost.get_node_or_null("Trail")
			if original_trail:
				original_trail.name = "Trail"
				original_trail.process_mode = Node.PROCESS_MODE_ALWAYS
				original_trail.clear_points()

	# Fallback: create a simple visible bullet sprite
	if ghost == null:
		ghost = Node2D.new()
		ghost.name = "GhostBullet"
		ghost.process_mode = Node.PROCESS_MODE_ALWAYS

		var sprite := Sprite2D.new()
		var img := Image.create(16, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color(1.0, 0.9, 0.2, 1.0))
		sprite.texture = ImageTexture.create_from_image(img)
		ghost.add_child(sprite)

		# Add trailing line for visibility
		var trail := Line2D.new()
		trail.name = "Trail"
		trail.process_mode = Node.PROCESS_MODE_ALWAYS
		trail.width = 3.0
		trail.default_color = Color(1.0, 0.9, 0.2, 1.0)
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1.0, 0.9, 0.2, 0.0))
		gradient.set_color(1, Color(1.0, 0.9, 0.2, 1.0))
		trail.gradient = gradient
		trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
		trail.end_cap_mode = Line2D.LINE_CAP_ROUND
		ghost.add_child(trail)

	# Add to level
	if _level_node and is_instance_valid(_level_node):
		var ghost_container := _level_node.get_node_or_null("ReplayGhosts")
		if ghost_container:
			ghost_container.add_child(ghost)

	return ghost


## Creates a ghost grenade using the actual grenade texture (Issue #544 fix grenade).
## Loads the appropriate grenade sprite based on recorded texture_path.
func _create_grenade_ghost(texture_path: String = "") -> Node2D:
	var ghost := Node2D.new()
	ghost.name = "GhostGrenade"
	ghost.process_mode = Node.PROCESS_MODE_ALWAYS

	var sprite := Sprite2D.new()
	var loaded_texture: Texture2D = null

	# Try to load the specific grenade texture that was recorded
	if texture_path != "" and ResourceLoader.exists(texture_path):
		loaded_texture = load(texture_path)

	# Fallback: try common grenade textures in order
	if loaded_texture == null:
		for path in [
			"res://assets/sprites/weapons/flashbang.png",
			"res://assets/sprites/weapons/frag_grenade.png",
			"res://assets/sprites/weapons/defensive_grenade.png"
		]:
			if ResourceLoader.exists(path):
				loaded_texture = load(path)
				break

	if loaded_texture:
		sprite.texture = loaded_texture
	else:
		# Final fallback: create a round-ish sprite (not a square)
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.0, 0.0, 0.0, 0.0))
		# Draw a filled circle manually
		var center := Vector2(8, 8)
		for x in range(16):
			for y in range(16):
				if Vector2(x, y).distance_to(center) <= 7.0:
					img.set_pixel(x, y, Color(0.4, 0.45, 0.3, 1.0))
		sprite.texture = ImageTexture.create_from_image(img)

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


## Cleans the floor of blood decals and casings at the start of replay (Issue #544 fix 5).
## They will be progressively re-added during playback.
func _clean_floor(level: Node2D) -> void:
	# Remove existing blood decals
	var blood_puddles := level.get_tree().get_nodes_in_group("blood_puddle")
	for puddle in blood_puddles:
		if puddle and is_instance_valid(puddle):
			puddle.visible = false

	# Remove existing casings
	var casings := level.get_tree().get_nodes_in_group("casings")
	for casing in casings:
		if casing and is_instance_valid(casing):
			casing.visible = false

	# Also clear via ImpactEffectsManager if available
	var impact_manager: Node = get_node_or_null("/root/ImpactEffectsManager")
	if impact_manager and impact_manager.has_method("clear_blood_decals"):
		impact_manager.clear_blood_decals()

	_log_to_file("Floor cleaned for replay playback")


## Updates blood decals during replay to show progressive accumulation (Issue #544 fix 5).
## Only spawns decals that appeared AFTER the recording started (skips baseline).
func _update_replay_blood_decals(decals_data: Array) -> void:
	# Skip decals that existed before recording started (baseline from frame 0)
	var new_count := decals_data.size() - _baseline_blood_count
	if new_count <= _spawned_blood_count or new_count <= 0:
		return

	var blood_decal_scene: PackedScene = null
	if ResourceLoader.exists("res://scenes/effects/BloodDecal.tscn"):
		blood_decal_scene = load("res://scenes/effects/BloodDecal.tscn")

	var start_idx := _baseline_blood_count + _spawned_blood_count

	if blood_decal_scene == null:
		# Fallback: use simple colored sprites
		for i in range(start_idx, decals_data.size()):
			var data: Dictionary = decals_data[i]
			var decal := Sprite2D.new()
			var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
			img.fill(Color(0.5, 0.0, 0.0, 0.7))
			decal.texture = ImageTexture.create_from_image(img)
			decal.global_position = data.position
			decal.rotation = data.rotation
			decal.scale = data.scale if data.has("scale") else Vector2.ONE
			decal.z_index = -1
			if _level_node and is_instance_valid(_level_node):
				_level_node.add_child(decal)
				_replay_blood_decals.append(decal)
	else:
		for i in range(start_idx, decals_data.size()):
			var data: Dictionary = decals_data[i]
			var decal: Node2D = blood_decal_scene.instantiate()
			decal.global_position = data.position
			decal.rotation = data.rotation
			if data.has("scale"):
				decal.scale = data.scale
			if _level_node and is_instance_valid(_level_node):
				_level_node.add_child(decal)
				_replay_blood_decals.append(decal)

	_spawned_blood_count = new_count


## Updates casings during replay to show progressive accumulation (Issue #544 fix 5).
## Only spawns casings that appeared AFTER the recording started (skips baseline).
func _update_replay_casings(casings_data: Array) -> void:
	# Skip casings that existed before recording started (baseline from frame 0)
	var new_count := casings_data.size() - _baseline_casing_count
	if new_count <= _spawned_casing_count or new_count <= 0:
		return

	var start_idx := _baseline_casing_count + _spawned_casing_count
	var casing_texture: Texture2D = null
	if ResourceLoader.exists("res://assets/sprites/effects/casing_rifle.png"):
		casing_texture = load("res://assets/sprites/effects/casing_rifle.png")

	# Create simple casing sprites (no physics during replay)
	for i in range(start_idx, casings_data.size()):
		var data: Dictionary = casings_data[i]
		var casing := Sprite2D.new()
		if casing_texture:
			casing.texture = casing_texture
		else:
			var img := Image.create(6, 3, false, Image.FORMAT_RGBA8)
			img.fill(Color(0.9, 0.8, 0.4, 0.9))  # Brass color
			casing.texture = ImageTexture.create_from_image(img)
		casing.global_position = data.position
		casing.rotation = data.rotation
		casing.z_index = -1
		if _level_node and is_instance_valid(_level_node):
			_level_node.add_child(casing)
			_replay_casings.append(casing)

	_spawned_casing_count = new_count


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

	if _ghost_player_trail and is_instance_valid(_ghost_player_trail):
		_ghost_player_trail.queue_free()
	_ghost_player_trail = null

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

	# Clean up replay blood decals and casings
	for decal in _replay_blood_decals:
		if decal and is_instance_valid(decal):
			decal.queue_free()
	_replay_blood_decals.clear()

	for casing in _replay_casings:
		if casing and is_instance_valid(casing):
			casing.queue_free()
	_replay_casings.clear()

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
