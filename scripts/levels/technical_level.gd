extends Node2D
## Technical corridor level scene for the Godot Top-Down Template.
##
## This scene is a narrow long corridor with technical infrastructure.
## Features:
## - Narrow elongated corridor layout (4000x600 pixels)
## - Single long corridor with dividers and cover objects
## - 4 enemies: 3 with rifles (PM), 1 with shotgun, all unarmored (1-2 HP)
## - Tight combat in confined space
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
	print("TechnicalLevel loaded - Technical Corridor")
	print("Corridor size: 4000x600 pixels")
	print("Fight through the corridor to win!")
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

	# Setup exit zone near player spawn
	_setup_exit_zone()

	# Start replay recording
	_start_replay_recording()


## Initialize the ScoreManager for this level.
func _initialize_score_manager() -> void:
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager == null:
		return

	score_manager.start_level(_initial_enemy_count)

	if _player:
		score_manager.set_player(_player)

	if not score_manager.combo_changed.is_connected(_on_combo_changed):
		score_manager.combo_changed.connect(_on_combo_changed)


## Starts recording the replay for this level.
func _start_replay_recording() -> void:
	var replay_manager: Node = _get_or_create_replay_manager()
	if replay_manager == null:
		_log_to_file("ERROR: ReplayManager could not be loaded, replay recording disabled")
		print("[TechnicalLevel] ERROR: ReplayManager could not be loaded!")
		return

	_log_to_file("Starting replay recording - Player: %s, Enemies count: %d" % [
		_player.name if _player else "NULL",
		_enemies.size()
	])

	if _player == null:
		_log_to_file("WARNING: Player is null, replay may not record properly")
		print("[TechnicalLevel] WARNING: Player is null for replay recording!")

	if _enemies.is_empty():
		_log_to_file("WARNING: No enemies to track in replay")
		print("[TechnicalLevel] WARNING: No enemies registered for replay!")

	if replay_manager.has_method("ClearReplay"):
		replay_manager.ClearReplay()
		_log_to_file("Previous replay data cleared")

	if replay_manager.has_method("StartRecording"):
		replay_manager.StartRecording(self, _player, _enemies)
		_log_to_file("Replay recording started successfully")
		print("[TechnicalLevel] Replay recording started with %d enemies" % _enemies.size())
	else:
		_log_to_file("ERROR: ReplayManager.StartRecording method not found")
		print("[TechnicalLevel] ERROR: StartRecording method not found!")


## Setup the exit zone near the player spawn point.
## The exit appears after all enemies are eliminated.
func _setup_exit_zone() -> void:
	var exit_zone_scene = load("res://scenes/objects/ExitZone.tscn")
	if exit_zone_scene == null:
		push_warning("ExitZone scene not found - score will show immediately on level clear")
		return

	_exit_zone = exit_zone_scene.instantiate()
	# Position exit at the far right end of the corridor
	_exit_zone.position = Vector2(3850, 300)
	_exit_zone.zone_width = 80.0
	_exit_zone.zone_height = 80.0

	_exit_zone.player_reached_exit.connect(_on_player_reached_exit)

	var environment := get_node_or_null("Environment")
	if environment:
		environment.add_child(_exit_zone)
	else:
		add_child(_exit_zone)

	print("[TechnicalLevel] Exit zone created at position (3850, 300)")


## Called when the player reaches the exit zone after clearing the level.
func _on_player_reached_exit() -> void:
	if not _level_cleared:
		return

	if _level_completed:
		return

	print("[TechnicalLevel] Player reached exit - showing score!")
	call_deferred("_complete_level_with_score")


## Activate the exit zone after all enemies are eliminated.
func _activate_exit_zone() -> void:
	if _exit_zone and _exit_zone.has_method("activate"):
		_exit_zone.activate()
		print("[TechnicalLevel] Exit zone activated - go to exit to see score!")
	else:
		push_warning("Exit zone not available - showing score immediately")
		_complete_level_with_score()


## Setup realistic visibility for the player (Issue #540).
func _setup_realistic_visibility() -> void:
	if _player == null:
		return

	var visibility_script = load("res://scripts/components/realistic_visibility_component.gd")
	if visibility_script == null:
		push_warning("[TechnicalLevel] RealisticVisibilityComponent script not found")
		return

	var visibility_component = Node.new()
	visibility_component.name = "RealisticVisibilityComponent"
	visibility_component.set_script(visibility_script)
	_player.add_child(visibility_component)
	print("[TechnicalLevel] Realistic visibility component added to player")


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
		return Color(1.0, 0.0, 1.0, 1.0)   # Magenta - extreme combo
	elif combo >= 7:
		return Color(1.0, 0.0, 0.3, 1.0)   # Hot pink
	elif combo >= 5:
		return Color(1.0, 0.1, 0.1, 1.0)   # Bright red
	elif combo >= 4:
		return Color(1.0, 0.2, 0.0, 1.0)   # Red-orange
	elif combo >= 3:
		return Color(1.0, 0.4, 0.0, 1.0)   # Hot orange
	elif combo >= 2:
		return Color(1.0, 0.6, 0.1, 1.0)   # Orange
	else:
		return Color(1.0, 0.8, 0.2, 1.0)   # Gold (combo 1)


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
	nav_poly.clear()

	var floor_outline: PackedVector2Array = PackedVector2Array([
		Vector2(64, 64),
		Vector2(3936, 64),
		Vector2(3936, 536),
		Vector2(64, 536)
	])
	nav_poly.add_outline(floor_outline)

	var source_geometry: NavigationMeshSourceGeometryData2D = NavigationMeshSourceGeometryData2D.new()
	NavigationServer2D.parse_source_geometry_data(nav_poly, source_geometry, self)
	NavigationServer2D.bake_from_source_geometry_data(nav_poly, source_geometry)

	print("Navigation mesh baked successfully")


## Setup tracking for the player.
func _setup_player_tracking() -> void:
	_player = get_node_or_null("Entities/Player")
	if _player == null:
		return

	# Setup realistic visibility component (Issue #540)
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

	# Try to get the player's weapon
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
		weapon = _player.get_node_or_null("MakarovPM")
	if weapon != null:
		if weapon.has_signal("AmmoChanged"):
			weapon.AmmoChanged.connect(_on_weapon_ammo_changed)
		if weapon.has_signal("MagazinesChanged"):
			weapon.MagazinesChanged.connect(_on_magazines_changed)
		if weapon.has_signal("Fired"):
			weapon.Fired.connect(_on_shot_fired)
		if weapon.has_signal("ShellCountChanged"):
			weapon.ShellCountChanged.connect(_on_shell_count_changed)
		if weapon.get("CurrentAmmo") != null and weapon.get("ReserveAmmo") != null:
			_update_ammo_label_magazine(weapon.CurrentAmmo, weapon.ReserveAmmo)
		if weapon.has_method("GetMagazineAmmoCounts"):
			var mag_counts: Array = weapon.GetMagazineAmmoCounts()
			_update_magazines_label(mag_counts)
		_configure_silenced_pistol_ammo(weapon)
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

	_initial_enemy_count = _enemies.size()
	_current_enemy_count = _initial_enemy_count
	_log_to_file("Enemy tracking complete: %d enemies registered" % _initial_enemy_count)
	print("Tracking %d enemies" % _initial_enemy_count)


## Configure silenced pistol ammo based on enemy count.
func _configure_silenced_pistol_ammo(weapon: Node) -> void:
	if weapon.name != "SilencedPistol":
		return

	if weapon.has_method("ConfigureAmmoForEnemyCount"):
		weapon.ConfigureAmmoForEnemyCount(_initial_enemy_count)
		print("[TechnicalLevel] Configured silenced pistol ammo for %d enemies" % _initial_enemy_count)

		if weapon.get("CurrentAmmo") != null and weapon.get("ReserveAmmo") != null:
			_update_ammo_label_magazine(weapon.CurrentAmmo, weapon.ReserveAmmo)
		if weapon.has_method("GetMagazineAmmoCounts"):
			var mag_counts: Array = weapon.GetMagazineAmmoCounts()
			_update_magazines_label(mag_counts)


## Setup debug UI elements for kills and accuracy.
func _setup_debug_ui() -> void:
	var ui := get_node_or_null("CanvasLayer/UI")
	if ui == null:
		return

	_kills_label = Label.new()
	_kills_label.name = "KillsLabel"
	_kills_label.text = "Kills: 0"
	_kills_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_kills_label.offset_left = 10
	_kills_label.offset_top = 45
	_kills_label.offset_right = 200
	_kills_label.offset_bottom = 75
	ui.add_child(_kills_label)

	_accuracy_label = Label.new()
	_accuracy_label.name = "AccuracyLabel"
	_accuracy_label.text = "Accuracy: 0%"
	_accuracy_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_accuracy_label.offset_left = 10
	_accuracy_label.offset_top = 75
	_accuracy_label.offset_right = 200
	_accuracy_label.offset_bottom = 105
	ui.add_child(_accuracy_label)

	_magazines_label = Label.new()
	_magazines_label.name = "MagazinesLabel"
	_magazines_label.text = "MAGS: -"
	_magazines_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_magazines_label.offset_left = 10
	_magazines_label.offset_top = 105
	_magazines_label.offset_right = 400
	_magazines_label.offset_bottom = 135
	ui.add_child(_magazines_label)

	_combo_label = Label.new()
	_combo_label.name = "ComboLabel"
	_combo_label.text = ""
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combo_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_combo_label.offset_left = -200
	_combo_label.offset_right = -10
	_combo_label.offset_top = 80
	_combo_label.offset_bottom = 120
	_combo_label.add_theme_font_size_override("font_size", 28)
	_combo_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2, 1.0))
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

	if _kills_label:
		_kills_label.text = "Kills: %d" % GameManager.kills

	if _accuracy_label:
		_accuracy_label.text = "Accuracy: %.1f%%" % GameManager.get_accuracy()


## Called when an enemy dies.
func _on_enemy_died() -> void:
	_current_enemy_count -= 1
	_update_enemy_count_label()

	if GameManager:
		GameManager.register_kill()

	if _current_enemy_count <= 0:
		print("All enemies eliminated! Corridor cleared!")
		_level_cleared = true
		call_deferred("_activate_exit_zone")


## Called when an enemy dies with special kill information.
func _on_enemy_died_with_info(is_ricochet_kill: bool, is_penetration_kill: bool) -> void:
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager and score_manager.has_method("register_kill"):
		score_manager.register_kill(is_ricochet_kill, is_penetration_kill)


## Complete the level and show the score screen.
func _complete_level_with_score() -> void:
	if _level_completed:
		return
	_level_completed = true

	_disable_player_controls()

	if _exit_zone and _exit_zone.has_method("deactivate"):
		_exit_zone.deactivate()

	# Stop replay recording
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
			print("[TechnicalLevel] Replay status: has_replay=%s, duration=%.2fs" % [has_replay, duration])
	else:
		_log_to_file("ERROR: ReplayManager not found when completing level")
		print("[TechnicalLevel] ERROR: ReplayManager not found!")

	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager and score_manager.has_method("complete_level"):
		var score_data: Dictionary = score_manager.complete_level()
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
func _on_shell_count_changed(shell_count: int, capacity: int) -> void:
	var reserve_ammo: int = 0
	if _player:
		var weapon = _player.get_node_or_null("Shotgun")
		if weapon != null and weapon.get("ReserveAmmo") != null:
			reserve_ammo = weapon.ReserveAmmo
	_update_ammo_label_magazine(shell_count, reserve_ammo)


## Called when player runs out of ammo in current magazine.
func _on_player_ammo_depleted() -> void:
	_broadcast_player_ammo_empty(true)
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
			weapon = _player.get_node_or_null("AssaultRifle")
		if weapon == null:
			weapon = _player.get_node_or_null("MakarovPM")

	if weapon != null and weapon.get("UsesTubeMagazine") == true:
		_magazines_label.visible = false
		return
	else:
		_magazines_label.visible = true

	if magazine_ammo_counts.is_empty():
		_magazines_label.text = "MAGS: -"
		return

	var parts: Array = []
	for i in range(magazine_ammo_counts.size()):
		var ammo: int = magazine_ammo_counts[i]
		if i == 0:
			parts.append("[%d]" % ammo)
		else:
			parts.append("%d" % ammo)

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
	victory_label.text = "CORRIDOR CLEARED!"
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


## Adds Restart, Next Level, Level Select, and Watch Replay buttons.
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

	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)

	if next_level_path != "":
		buttons_container.get_node("NextLevelButton").grab_focus()
	else:
		restart_button.grab_focus()


## Get the color for a given rank.
func _get_rank_color(rank: String) -> Color:
	match rank:
		"S":
			return Color(1.0, 0.84, 0.0, 1.0)  # Gold
		"A+":
			return Color(0.0, 1.0, 0.5, 1.0)  # Bright green
		"A":
			return Color(0.2, 0.8, 0.2, 1.0)  # Green
		"B":
			return Color(0.3, 0.7, 1.0, 1.0)  # Blue
		"C":
			return Color(1.0, 1.0, 1.0, 1.0)  # White
		"D":
			return Color(1.0, 0.6, 0.2, 1.0)  # Orange
		"F":
			return Color(1.0, 0.2, 0.2, 1.0)  # Red
		_:
			return Color(1.0, 1.0, 1.0, 1.0)  # Default white


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

	# Check if C# Player already equipped the correct weapon
	if selected_weapon_id != "makarov_pm":
		var weapon_names: Dictionary = {
			"shotgun": "Shotgun",
			"mini_uzi": "MiniUzi",
			"silenced_pistol": "SilencedPistol",
			"sniper": "SniperRifle",
			"m16": "AssaultRifle"
		}
		if selected_weapon_id in weapon_names:
			var expected_name: String = weapon_names[selected_weapon_id]
			var existing_weapon = _player.get_node_or_null(expected_name)
			if existing_weapon != null and _player.get("CurrentWeapon") == existing_weapon:
				_log_to_file("%s already equipped by C# Player - skipping GDScript weapon swap" % expected_name)
				return

	if selected_weapon_id == "shotgun":
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov:
			makarov.queue_free()
			print("TechnicalLevel: Removed default MakarovPM")

		var shotgun_scene = load("res://scenes/weapons/csharp/Shotgun.tscn")
		if shotgun_scene:
			var shotgun = shotgun_scene.instantiate()
			shotgun.name = "Shotgun"
			_player.add_child(shotgun)

			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(shotgun)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = shotgun

			print("TechnicalLevel: Shotgun equipped successfully")
		else:
			push_error("TechnicalLevel: Failed to load Shotgun scene!")
	elif selected_weapon_id == "mini_uzi":
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov:
			makarov.queue_free()
			print("TechnicalLevel: Removed default MakarovPM")

		var mini_uzi_scene = load("res://scenes/weapons/csharp/MiniUzi.tscn")
		if mini_uzi_scene:
			var mini_uzi = mini_uzi_scene.instantiate()
			mini_uzi.name = "MiniUzi"

			if mini_uzi.get("StartingMagazineCount") != null:
				mini_uzi.StartingMagazineCount = 2
				print("TechnicalLevel: Mini UZI StartingMagazineCount set to 2 (before initialization)")

			_player.add_child(mini_uzi)

			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(mini_uzi)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = mini_uzi

			print("TechnicalLevel: Mini UZI equipped successfully")
		else:
			push_error("TechnicalLevel: Failed to load MiniUzi scene!")
	elif selected_weapon_id == "silenced_pistol":
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov:
			makarov.queue_free()
			print("TechnicalLevel: Removed default MakarovPM")

		var pistol_scene = load("res://scenes/weapons/csharp/SilencedPistol.tscn")
		if pistol_scene:
			var pistol = pistol_scene.instantiate()
			pistol.name = "SilencedPistol"
			_player.add_child(pistol)

			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(pistol)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = pistol

			print("TechnicalLevel: Silenced Pistol equipped successfully")
		else:
			push_error("TechnicalLevel: Failed to load SilencedPistol scene!")
	elif selected_weapon_id == "sniper":
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov:
			makarov.queue_free()
			print("TechnicalLevel: Removed default MakarovPM")

		var sniper_scene = load("res://scenes/weapons/csharp/SniperRifle.tscn")
		if sniper_scene:
			var sniper = sniper_scene.instantiate()
			sniper.name = "SniperRifle"
			_player.add_child(sniper)

			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(sniper)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = sniper

			print("TechnicalLevel: ASVK Sniper Rifle equipped successfully")
		else:
			push_error("TechnicalLevel: Failed to load SniperRifle scene!")
	elif selected_weapon_id == "m16":
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov:
			makarov.queue_free()
			print("TechnicalLevel: Removed default MakarovPM")

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
					print("TechnicalLevel: Power Fantasy mode - M16 magazines multiplied by %dx" % ammo_multiplier)
			if m16.has_method("ReinitializeMagazines"):
				m16.ReinitializeMagazines(base_magazines, true)
				print("TechnicalLevel: M16 magazines reinitialized to %d" % base_magazines)

			print("TechnicalLevel: M16 Assault Rifle equipped successfully")
		else:
			push_error("TechnicalLevel: Failed to load AssaultRifle scene!")
	else:
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov and _player.get("CurrentWeapon") == null:
			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(makarov)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = makarov


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


## Get the next level path based on the level ordering from LevelsMenu.
## Returns empty string if this is the last level or level not found.
func _get_next_level_path() -> String:
	var current_scene_path: String = ""
	var current_scene: Node = get_tree().current_scene
	if current_scene and current_scene.scene_file_path:
		current_scene_path = current_scene.scene_file_path

	var level_paths: Array[String] = [
		"res://scenes/levels/TechnicalLevel.tscn",
		"res://scenes/levels/BuildingLevel.tscn",
		"res://scenes/levels/TestTier.tscn",
		"res://scenes/levels/CastleLevel.tscn",
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


## Log a message to the file logger if available.
func _log_to_file(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[TechnicalLevel] " + message)
	else:
		print("[TechnicalLevel] " + message)
