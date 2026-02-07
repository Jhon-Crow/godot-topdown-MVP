extends Node2D
## Beach level scene (Issue #579).
##
## Open outdoor beach environment with scattered cover (rocks, huts, barrels).
## Features machete-wielding melee enemies alongside ranged enemies.
## Beach layout: ~2400x2000 pixels with water boundaries on top and right.

var _enemy_count_label: Label = null
var _ammo_label: Label = null
var _player: Node2D = null
var _initial_enemy_count: int = 0
var _current_enemy_count: int = 0
var _game_over_shown: bool = false
var _kills_label: Label = null
var _accuracy_label: Label = null
var _magazines_label: Label = null
var _saturation_overlay: ColorRect = null
var _combo_label: Label = null
var _exit_zone: Area2D = null
var _level_cleared: bool = false
var _score_shown: bool = false
var _level_completed: bool = false
const SATURATION_DURATION: float = 0.15
const SATURATION_INTENSITY: float = 0.25
var _enemies: Array = []
var _replay_manager: Node = null


func _get_or_create_replay_manager() -> Node:
	if _replay_manager != null and is_instance_valid(_replay_manager):
		return _replay_manager
	_replay_manager = get_node_or_null("/root/ReplayManager")
	if _replay_manager != null:
		if _replay_manager.has_method("StartRecording"):
			_log_to_file("ReplayManager found as C# autoload")
	return _replay_manager


func _ready() -> void:
	print("BeachLevel loaded - Outdoor Beach Combat")
	print("Beach size: ~2400x2000 pixels")
	print("Clear all enemies to win!")
	_setup_navigation()
	_setup_enemy_tracking()
	_enemy_count_label = get_node_or_null("CanvasLayer/UI/EnemyCountLabel")
	_update_enemy_count_label()
	_setup_player_tracking()
	_setup_debug_ui()
	_setup_saturation_overlay()
	if GameManager:
		GameManager.enemy_killed.connect(_on_game_manager_enemy_killed)
		GameManager.stats_updated.connect(_update_debug_ui)
	_initialize_score_manager()
	_setup_exit_zone()
	_start_replay_recording()


func _initialize_score_manager() -> void:
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager == null: return
	score_manager.start_level(_initial_enemy_count)
	if _player: score_manager.set_player(_player)
	if not score_manager.combo_changed.is_connected(_on_combo_changed):
		score_manager.combo_changed.connect(_on_combo_changed)


func _start_replay_recording() -> void:
	var replay_manager: Node = _get_or_create_replay_manager()
	if replay_manager == null: return
	if replay_manager.has_method("ClearReplay"): replay_manager.ClearReplay()
	if replay_manager.has_method("StartRecording"):
		replay_manager.StartRecording(self, _player, _enemies)


func _setup_exit_zone() -> void:
	var exit_zone_scene = load("res://scenes/objects/ExitZone.tscn")
	if exit_zone_scene == null:
		push_warning("ExitZone scene not found")
		return
	_exit_zone = exit_zone_scene.instantiate()
	_exit_zone.position = Vector2(120, 1800)
	_exit_zone.zone_width = 60.0; _exit_zone.zone_height = 100.0
	_exit_zone.player_reached_exit.connect(_on_player_reached_exit)
	var environment := get_node_or_null("Environment")
	if environment: environment.add_child(_exit_zone)
	else: add_child(_exit_zone)


func _on_player_reached_exit() -> void:
	if not _level_cleared or _level_completed: return
	call_deferred("_complete_level_with_score")


func _activate_exit_zone() -> void:
	if _exit_zone and _exit_zone.has_method("activate"): _exit_zone.activate()
	else: _complete_level_with_score()


func _setup_realistic_visibility() -> void:
	if _player == null: return
	var visibility_script = load("res://scripts/components/realistic_visibility_component.gd")
	if visibility_script == null: return
	var visibility_component = Node.new()
	visibility_component.name = "RealisticVisibilityComponent"
	visibility_component.set_script(visibility_script)
	_player.add_child(visibility_component)


func _process(_delta: float) -> void:
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager and score_manager.has_method("update_enemy_positions"):
		score_manager.update_enemy_positions(_enemies)


func _on_combo_changed(combo: int, points: int) -> void:
	if _combo_label == null: return
	if combo > 0:
		_combo_label.text = "x%d COMBO (+%d)" % [combo, points]
		_combo_label.visible = true
		_combo_label.add_theme_color_override("font_color", _get_combo_color(combo))
		_combo_label.modulate = Color.WHITE
		var tween := create_tween()
		tween.tween_property(_combo_label, "modulate", Color.WHITE, 0.1)
	else:
		_combo_label.visible = false


func _get_combo_color(combo: int) -> Color:
	if combo >= 10: return Color(1.0, 0.0, 1.0, 1.0)
	elif combo >= 7: return Color(1.0, 0.1, 0.0, 1.0)
	elif combo >= 5: return Color(1.0, 0.5, 0.0, 1.0)
	elif combo >= 3: return Color(1.0, 0.8, 0.0, 1.0)
	else: return Color(1.0, 1.0, 1.0, 1.0)


func _setup_navigation() -> void:
	var nav_region: NavigationRegion2D = get_node_or_null("NavigationRegion2D")
	if nav_region:
		nav_region.navigation_polygon.agent_radius = 24.0
		nav_region.bake_navigation_polygon(false)


func _setup_player_tracking() -> void:
	_player = get_node_or_null("Entities/Player")
	if _player == null:
		push_warning("Player node not found")
		return
	_ammo_label = get_node_or_null("CanvasLayer/UI/AmmoLabel")
	if _player.has_signal("ammo_changed"):
		_player.ammo_changed.connect(_on_player_ammo_changed)
	if _player.has_signal("magazine_changed"):
		_player.magazine_changed.connect(_on_player_magazine_changed)
	if _player.has_signal("died"):
		_player.died.connect(_on_player_died)
	_setup_realistic_visibility()


func _on_player_ammo_changed(current: int, reserve: int) -> void:
	if _ammo_label: _ammo_label.text = "AMMO: %d/%d" % [current, reserve]


func _on_player_magazine_changed(magazines_info: String) -> void:
	if _magazines_label: _magazines_label.text = magazines_info


func _on_player_died() -> void:
	if _game_over_shown: return
	_game_over_shown = true
	var replay_manager: Node = _get_or_create_replay_manager()
	if replay_manager and replay_manager.has_method("StopRecording"):
		replay_manager.StopRecording()
	await get_tree().create_timer(1.5).timeout
	get_tree().reload_current_scene()


func _setup_enemy_tracking() -> void:
	var enemies_node := get_node_or_null("Environment/Enemies")
	if enemies_node == null:
		push_warning("Enemies node not found"); return
	for child in enemies_node.get_children():
		if child.has_signal("died"):
			child.died.connect(_on_enemy_died)
			_enemies.append(child)
	_initial_enemy_count = _enemies.size()
	_current_enemy_count = _initial_enemy_count
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("set_enemy_count"): gm.set_enemy_count(_initial_enemy_count)


func _setup_debug_ui() -> void:
	var ui := get_node_or_null("CanvasLayer/UI")
	if ui == null: return
	_kills_label = ui.get_node_or_null("KillsLabel")
	_accuracy_label = ui.get_node_or_null("AccuracyLabel")
	_magazines_label = ui.get_node_or_null("MagazinesLabel")
	_combo_label = ui.get_node_or_null("ComboLabel")
	_update_debug_ui()


func _setup_saturation_overlay() -> void:
	var canvas_layer := get_node_or_null("CanvasLayer")
	if canvas_layer == null: return
	_saturation_overlay = ColorRect.new()
	_saturation_overlay.name = "SaturationOverlay"
	_saturation_overlay.color = Color(1.0, 0.0, 0.0, 0.0)
	_saturation_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_saturation_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas_layer.add_child(_saturation_overlay)


func _on_enemy_died() -> void:
	_current_enemy_count -= 1
	_update_enemy_count_label()
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager and score_manager.has_method("register_kill"):
		score_manager.register_kill()
	if _current_enemy_count <= 0:
		_level_cleared = true
		_activate_exit_zone()


func _complete_level_with_score() -> void:
	if _level_completed: return
	_level_completed = true
	var replay_manager: Node = _get_or_create_replay_manager()
	if replay_manager and replay_manager.has_method("StopRecording"):
		replay_manager.StopRecording()
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager and score_manager.has_method("finish_level"):
		score_manager.finish_level()
	_show_score_screen()


func _show_score_screen() -> void:
	_score_shown = true
	var score_scene = load("res://scenes/ui/ScoreScreen.tscn")
	if score_scene == null:
		push_warning("ScoreScreen not found"); return
	var score_instance = score_scene.instantiate()
	var canvas_layer := get_node_or_null("CanvasLayer")
	if canvas_layer: canvas_layer.add_child(score_instance)
	else: add_child(score_instance)


func _on_game_manager_enemy_killed() -> void:
	_show_saturation_effect()


func _show_saturation_effect() -> void:
	if _saturation_overlay == null: return
	_saturation_overlay.color = Color(1.0, 0.0, 0.0, SATURATION_INTENSITY)
	var tween := create_tween()
	tween.tween_property(_saturation_overlay, "color:a", 0.0, SATURATION_DURATION)


func _update_enemy_count_label() -> void:
	if _enemy_count_label:
		_enemy_count_label.text = "Enemies: %d" % _current_enemy_count


func _update_debug_ui() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null: return
	if _kills_label and gm.has_method("get_kills"):
		_kills_label.text = "Kills: %d" % gm.get_kills()
	if _accuracy_label and gm.has_method("get_accuracy"):
		_accuracy_label.text = "Accuracy: %.0f%%" % (gm.get_accuracy() * 100.0)


func _log_to_file(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[BeachLevel] " + message)
	else:
		print("[BeachLevel] " + message)
