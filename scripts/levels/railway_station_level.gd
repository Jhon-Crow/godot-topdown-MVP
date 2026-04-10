extends Node2D
## Railway Station level scene (Issue #1463).
##
## ЖД Станция — the level after Winter Forest.
## Player enters from the bottom and must cross the map upward through:
## 1. Station building + platform (almost no cover)
## 2. Two rows of railway tracks with trains
## 3. A narrow walkway
## 4. Two more rows of railway tracks with trains
## 5. Embankment with snowdrift (narrow player-sized passages)
## Exit at the top center-right (direction of sunlight).
## Map size: ~4000x4000 pixels. No enemies for now.

var _enemy_count_label: Label = null
var _ammo_label: Label = null
var _player: Node2D = null
var _initial_enemy_count: int = 0
var _current_enemy_count: int = 0
var _game_over_shown: bool = false
var _difficulty_label: Label = null
var _magazines_label: Label = null
var _saturation_overlay: ColorRect = null
var _combo_label: Label = null
## Reference to active combo tween (to cancel if needed).
var _combo_tween: Tween = null
var _exit_zone: Area2D = null
var _extra_exit_zones: Array = []
var _level_cleared: bool = false
var _score_shown: bool = false
var _level_completed: bool = false
var _game_end_screen_shown: bool = false
var _game_end_dismissed: bool = false
var _pending_score_data: Dictionary = {}
const SATURATION_DURATION: float = 0.15
const SATURATION_INTENSITY: float = 0.25
var _enemies: Array = []
var _replay_manager: Node = null

## Weapon hints component instance (Issue #809).
var _weapon_hints_component: Node = null


func _get_or_create_replay_manager() -> Node:
	if _replay_manager != null and is_instance_valid(_replay_manager):
		return _replay_manager
	_replay_manager = get_node_or_null("/root/ReplayManager")
	if _replay_manager != null:
		if _replay_manager.has_method("StartRecording"):
			_log_to_file("ReplayManager found as C# autoload")
	return _replay_manager


func _ready() -> void:
	print("RailwayStationLevel loaded - Railway Station (ЖД Станция)")
	print("Map size: ~4000x4000 pixels")
	print("No enemies — explore and reach the exit!")
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

	# Setup weapon hints (Issue #809)
	_setup_weapon_hints()

	# Add sunlight source off-screen in the top-right corner
	_setup_sunlight()

	# No enemies: immediately mark level as cleared so exit zone activates
	if _initial_enemy_count <= 0:
		_level_cleared = true
		call_deferred("_activate_exit_zone")


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

	# All 3 embankment gaps serve as exits:
	# Gap 1: between Embankment1 (x=50..750) and Embankment2 (x=800..1500) → center x=775, width=50
	# Gap 2: between Embankment2 (x=800..1500) and Embankment3 (x=1800..2500) → center x=1650, width=300
	# Gap 3: between Embankment3 (x=1800..2500) and Embankment4 (x=2850..3550) → center x=2675, width=350
	var exit_gaps: Array = [
		{"pos": Vector2(775, 1000), "w": 50.0, "h": 200.0},
		{"pos": Vector2(1650, 1000), "w": 300.0, "h": 200.0},
		{"pos": Vector2(2675, 1000), "w": 350.0, "h": 200.0},
	]

	var environment := get_node_or_null("Environment")
	for idx in range(exit_gaps.size()):
		var gap_data: Dictionary = exit_gaps[idx]
		var zone: Area2D = exit_zone_scene.instantiate()
		zone.position = gap_data["pos"]
		zone.zone_width = gap_data["w"]
		zone.zone_height = gap_data["h"]
		zone.player_reached_exit.connect(_on_player_reached_exit)
		if environment:
			environment.add_child(zone)
		else:
			add_child(zone)
		if idx == 0:
			_exit_zone = zone
		else:
			_extra_exit_zones.append(zone)


func _on_player_reached_exit() -> void:
	if not _level_cleared or _level_completed: return
	call_deferred("_complete_level_with_score")


func _activate_exit_zone() -> void:
	if _exit_zone and _exit_zone.has_method("activate"):
		_exit_zone.activate()
	for zone in _extra_exit_zones:
		if zone and zone.has_method("activate"):
			zone.activate()
	if _exit_zone == null:
		_complete_level_with_score()


func _setup_realistic_visibility() -> void:
	if _player == null: return
	var visibility_script = load("res://scripts/components/realistic_visibility_component.gd")
	if visibility_script == null: return
	var visibility_component = Node.new()
	visibility_component.name = "RealisticVisibilityComponent"
	visibility_component.set_script(visibility_script)
	_player.add_child(visibility_component)


## Setup weapon hints component (Issue #809).
func _setup_weapon_hints() -> void:
	if _player == null:
		return

	var canvas_layer: Node = get_node_or_null("CanvasLayer")
	if canvas_layer == null:
		push_warning("[RailwayStationLevel] CanvasLayer node not found for weapon hints")
		return

	var hints_script = load("res://scripts/components/weapon_hints_component.gd")
	if hints_script == null:
		push_warning("[RailwayStationLevel] WeaponHintsComponent script not found")
		return

	_weapon_hints_component = Node.new()
	_weapon_hints_component.name = "WeaponHintsComponent"
	_weapon_hints_component.set_script(hints_script)
	add_child(_weapon_hints_component)

	if _weapon_hints_component.has_method("setup"):
		_weapon_hints_component.setup(_player, canvas_layer)
		print("[RailwayStationLevel] Weapon hints component added and setup")


func _process(_delta: float) -> void:
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager and score_manager.has_method("update_enemy_positions"):
		score_manager.update_enemy_positions(_enemies)
	if _current_enemy_count <= 0 and not _level_cleared and not _has_retaliating_pacifists():
		print("All enemies eliminated or pacified! Level cleared!")
		_level_cleared = true
		call_deferred("_activate_exit_zone")


func _on_combo_changed(combo: int, points: int) -> void:
	if _combo_label == null: return
	if combo > 0:
		_combo_label.text = "x%d COMBO\n+%d" % [combo, points]
		_combo_label.visible = true
		_combo_label.add_theme_color_override("font_color", _get_combo_color(combo))
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


func _get_combo_color(combo: int) -> Color:
	if combo >= 10: return Color(1.0, 0.0, 1.0, 1.0)
	elif combo >= 7: return Color(1.0, 0.1, 0.0, 1.0)
	elif combo >= 5: return Color(1.0, 0.5, 0.0, 1.0)
	elif combo >= 3: return Color(1.0, 0.8, 0.0, 1.0)
	else: return Color(1.0, 1.0, 1.0, 1.0)


func _setup_navigation() -> void:
	var nav_region: NavigationRegion2D = get_node_or_null("NavigationRegion2D")
	if nav_region == null:
		return
	var nav_poly: NavigationPolygon = nav_region.navigation_polygon
	if nav_poly == null:
		return
	await get_tree().physics_frame
	nav_poly.agent_radius = 24.0
	var source_geometry: NavigationMeshSourceGeometryData2D = NavigationMeshSourceGeometryData2D.new()
	NavigationServer2D.parse_source_geometry_data(nav_poly, source_geometry, self)
	NavigationServer2D.bake_from_source_geometry_data(nav_poly, source_geometry)
	nav_region.navigation_polygon = nav_poly
	nav_region.emit_signal("bake_finished")


## Clamps the camera so the outer border walls are never visible (Issue #1682).
##
## RailwayStationLevel map: 4000x4000 px playfield framed by 32 px walls.
##   WallTopLeft (2000,   48), h=16  → bottom edge y=64   → limit_top    = 64
##   WallBottom  (2000, 3952), h=16  → top edge   y=3936  → limit_bottom = 3936
##   WallLeft    (  48, 2000), w=16  → right edge x=64    → limit_left   = 64
##   WallRight   (3952, 2000), w=16  → left edge  x=3936  → limit_right  = 3936
##
## Note: limit_top is additionally clamped to 900 so the camera cannot show the
## area above the embankment line (y=900), which has no playable content above it
## and the exit gaps are only reachable from the south side of the embankment.
func _configure_camera() -> void:
	if _player == null:
		return
	var camera: Camera2D = _player.get_node_or_null("Camera2D")
	if camera == null:
		push_warning("[RailwayStationLevel] Camera2D not found on player — cannot set camera limits")
		return
	const LIMIT_TOP: int    =  900   # embankment top (more restrictive than wall edge y=64)
	const LIMIT_BOTTOM: int = 3936   # WallBottom top edge
	const LIMIT_LEFT: int   =   64   # WallLeft right edge
	const LIMIT_RIGHT: int  = 3936   # WallRight left edge
	camera.limit_top    = LIMIT_TOP
	camera.limit_bottom = LIMIT_BOTTOM
	camera.limit_left   = LIMIT_LEFT
	camera.limit_right  = LIMIT_RIGHT
	print("[RailwayStationLevel] Camera clamped — top=%d bottom=%d left=%d right=%d — Issue #1682" % [
		LIMIT_TOP, LIMIT_BOTTOM, LIMIT_LEFT, LIMIT_RIGHT
	])


func _setup_player_tracking() -> void:
	_player = get_node_or_null("Entities/Player")
	if _player == null:
		push_warning("Player node not found")
		return

	_configure_camera()
	_setup_realistic_visibility()
	_setup_selected_weapon()

	if GameManager:
		GameManager.set_player(_player)

	_ammo_label = get_node_or_null("CanvasLayer/UI/AmmoLabel")

	if _player.has_signal("died"):
		_player.died.connect(_on_player_died)
	elif _player.has_signal("Died"):
		_player.Died.connect(_on_player_died)

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
		if weapon.has_signal("ShellCountChanged"):
			weapon.ShellCountChanged.connect(_on_shell_count_changed)
		if weapon.get("CurrentAmmo") != null and weapon.get("ReserveAmmo") != null:
			_update_ammo_label_magazine(weapon.CurrentAmmo, weapon.ReserveAmmo)
		if weapon.has_method("GetMagazineAmmoCounts"):
			var mag_counts: Array = weapon.GetMagazineAmmoCounts()
			_update_magazines_label(mag_counts)
		_configure_silenced_pistol_ammo(weapon)
		_configure_makarov_pm_ammo(weapon)
	else:
		if _player.has_signal("ammo_changed"):
			_player.ammo_changed.connect(_on_player_ammo_changed)
		if _player.has_method("get_current_ammo") and _player.has_method("get_max_ammo"):
			_update_ammo_label(_player.get_current_ammo(), _player.get_max_ammo())

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
		if weapon.has_method("GetMagazineAmmoCounts"):
			var mag_counts: Array = weapon.GetMagazineAmmoCounts()
			_update_magazines_label(mag_counts)


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
		if weapon.has_method("GetMagazineAmmoCounts"):
			var mag_counts: Array = weapon.GetMagazineAmmoCounts()
			_update_magazines_label(mag_counts)
	if _player != null and _player.has_method("ApplyAutoReloadAfterLevelAmmoConfig"):
		_player.ApplyAutoReloadAfterLevelAmmoConfig()


func _on_player_ammo_changed(current: int, maximum: int) -> void:
	_update_ammo_label(current, maximum)
	if GameManager:
		GameManager.register_shot()


func _on_weapon_ammo_changed(current_ammo: int, reserve_ammo: int) -> void:
	_update_ammo_label_magazine(current_ammo, reserve_ammo)
	if current_ammo <= 0 and reserve_ammo <= 0:
		if _current_enemy_count > 0 and not _game_over_shown:
			_show_game_over_message()


func _on_magazines_changed(magazine_ammo_counts: Array) -> void:
	_update_magazines_label(magazine_ammo_counts)


func _on_shot_fired() -> void:
	if GameManager:
		GameManager.register_shot()


func _on_shell_count_changed(shell_count: int, _capacity: int) -> void:
	var reserve_ammo: int = 0
	if _player:
		var weapon = _player.get_node_or_null("Shotgun")
		if weapon != null and weapon.get("ReserveAmmo") != null:
			reserve_ammo = weapon.ReserveAmmo
	_update_ammo_label_magazine(shell_count, reserve_ammo)


func _on_player_ammo_depleted() -> void:
	if _player:
		var sound_propagation: Node = get_node_or_null("/root/SoundPropagation")
		if sound_propagation and sound_propagation.has_method("emit_player_empty_click"):
			sound_propagation.emit_player_empty_click(_player.global_position, _player)
	if _player and _player.has_method("get_current_ammo"):
		var current_ammo: int = _player.get_current_ammo()
		if current_ammo <= 0 and _current_enemy_count > 0 and not _game_over_shown:
			_show_game_over_message()


func _on_player_reload_started() -> void:
	_broadcast_player_reloading(true)
	if _player:
		var sound_propagation: Node = get_node_or_null("/root/SoundPropagation")
		if sound_propagation and sound_propagation.has_method("emit_player_reload"):
			sound_propagation.emit_player_reload(_player.global_position, _player)


func _on_player_reload_completed() -> void:
	_broadcast_player_reloading(false)
	_broadcast_player_ammo_empty(false)


func _broadcast_player_reloading(is_reloading: bool) -> void:
	var enemies_node := get_node_or_null("Environment/Enemies")
	if enemies_node == null:
		return
	for enemy in enemies_node.get_children():
		if enemy.has_method("set_player_reloading"):
			enemy.set_player_reloading(is_reloading)


func _broadcast_player_ammo_empty(is_empty: bool) -> void:
	var enemies_node := get_node_or_null("Environment/Enemies")
	if enemies_node == null:
		return
	for enemy in enemies_node.get_children():
		if enemy.has_method("set_player_ammo_empty"):
			enemy.set_player_ammo_empty(is_empty)


func _on_player_died() -> void:
	_show_death_message()
	if GameManager:
		await get_tree().create_timer(0.5).timeout
		if not is_instance_valid(self):
			return
		GameManager.on_player_death()


func _setup_enemy_tracking() -> void:
	var enemies_node := get_node_or_null("Environment/Enemies")
	if enemies_node == null:
		_log_to_file("Environment/Enemies node not found (no enemies on this level)")
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
		if child.has_signal("became_pacifist"):
			child.became_pacifist.connect(_on_enemy_became_pacifist.bind(child))

	_initial_enemy_count = _enemies.size()
	_current_enemy_count = _initial_enemy_count
	_log_to_file("Enemy tracking complete: %d enemies registered" % _initial_enemy_count)


func _setup_debug_ui() -> void:
	var ui := get_node_or_null("CanvasLayer/UI")
	if ui == null: return

	_difficulty_label = Label.new()
	_difficulty_label.name = "DifficultyLabel"
	_difficulty_label.text = "Difficulty: " + DifficultyManager.get_difficulty_name()
	_difficulty_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_difficulty_label.offset_left = 10
	_difficulty_label.offset_top = 45
	_difficulty_label.offset_right = 200
	_difficulty_label.offset_bottom = 75
	ui.add_child(_difficulty_label)

	_magazines_label = Label.new()
	_magazines_label.name = "MagazinesLabel"
	_magazines_label.text = "MAGS: -"
	_magazines_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_magazines_label.offset_left = 10
	_magazines_label.offset_top = 105
	_magazines_label.offset_right = 400
	_magazines_label.offset_bottom = 135
	ui.add_child(_magazines_label)

	var gameplay_settings: Node = get_node_or_null("/root/GameplaySettings")
	var combo_size: int = gameplay_settings.get_combo_font_size() if gameplay_settings and gameplay_settings.has_method("get_combo_font_size") else 112
	_combo_label = Label.new()
	_combo_label.name = "ComboLabel"
	_combo_label.text = ""
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combo_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_combo_label.offset_left = -500
	_combo_label.offset_right = -10
	_combo_label.offset_top = 80
	_combo_label.offset_bottom = 150
	_combo_label.add_theme_font_size_override("font_size", combo_size)
	_combo_label.add_theme_constant_override("line_spacing", 0)
	_combo_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2, 1.0))
	_combo_label.add_theme_font_override("font", load("res://assets/fonts/gothic_bitmap.fnt"))
	_combo_label.visible = false
	ui.add_child(_combo_label)

	_update_debug_ui()


func _setup_saturation_overlay() -> void:
	var canvas_layer := get_node_or_null("CanvasLayer")
	if canvas_layer == null: return
	_saturation_overlay = ColorRect.new()
	_saturation_overlay.name = "SaturationOverlay"
	_saturation_overlay.color = Color(1.0, 0.9, 0.3, 0.0)
	_saturation_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_saturation_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas_layer.add_child(_saturation_overlay)
	canvas_layer.move_child(_saturation_overlay, canvas_layer.get_child_count() - 1)


func _on_enemy_died() -> void:
	_current_enemy_count -= 1
	_update_enemy_count_label()
	if _current_enemy_count <= 0 and not _has_retaliating_pacifists():
		_level_cleared = true
		call_deferred("_activate_exit_zone")


func _on_enemy_died_with_info(is_ricochet_kill: bool, is_penetration_kill: bool, is_player_kill: bool = true) -> void:
	if GameManager:
		GameManager.register_kill(is_player_kill, is_penetration_kill)
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager and score_manager.has_method("register_kill"):
		score_manager.register_kill(is_ricochet_kill, is_penetration_kill)


func _on_enemy_became_pacifist(enemy: Node) -> void:
	_current_enemy_count -= 1
	if is_instance_valid(enemy) and enemy.died.is_connected(_on_enemy_died):
		enemy.died.disconnect(_on_enemy_died)
	_update_enemy_count_label()
	print("[RailwayStation] Enemy became pacifist - counting as eliminated")
	if _current_enemy_count <= 0 and not _has_retaliating_pacifists():
		print("All enemies eliminated or pacified! Level cleared!")
		_level_cleared = true
		call_deferred("_activate_exit_zone")


func _has_retaliating_pacifists() -> bool:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and enemy.has_method("is_alive") and enemy.is_alive():
			if enemy.has_method("is_retaliating") and enemy.is_retaliating():
				return true
	return false


func _on_enemy_hit() -> void:
	if GameManager:
		GameManager.register_hit()


func _complete_level_with_score() -> void:
	if _level_completed: return
	_level_completed = true
	_disable_player_controls()
	if _exit_zone and _exit_zone.has_method("deactivate"):
		_exit_zone.deactivate()
	var replay_manager: Node = _get_or_create_replay_manager()
	if replay_manager and replay_manager.has_method("StopRecording"):
		replay_manager.StopRecording()
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager and score_manager.has_method("complete_level"):
		var score_data: Dictionary = score_manager.complete_level()
		var aim: Node = get_node_or_null("/root/ActiveItemManager")
		if aim and aim.has_method("notify_level_completed"):
			aim.notify_level_completed(score_data.get("kills", 0) > 0)
		_pending_score_data = score_data
		_show_game_end_screen()
	else:
		_show_game_end_screen()


## Shows the end-of-game screen: white text on solid black background (Issue #1755).
## Player must click or press any key to dismiss it, then the score screen is shown.
func _show_game_end_screen() -> void:
	if _game_end_screen_shown:
		return
	_game_end_screen_shown = true
	var canvas_layer := get_node_or_null("CanvasLayer")
	if canvas_layer == null:
		_proceed_to_score_screen()
		return

	var bg := ColorRect.new()
	bg.name = "GameEndBackground"
	bg.color = Color(0.0, 0.0, 0.0, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	# MOUSE_FILTER_STOP captures mouse clicks so gui_input fires (IGNORE would miss them).
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.is_pressed():
			_dismiss_game_end_screen()
	)
	canvas_layer.add_child(bg)

	var label := Label.new()
	label.name = "GameEndLabel"
	label.text = "Конец. Спасибо за игру"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 64)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas_layer.add_child(label)

	var hint := Label.new()
	hint.name = "GameEndHint"
	hint.text = "Нажмите любую клавишу или кнопку мыши..."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	hint.add_theme_font_size_override("font_size", 20)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))
	hint.set_anchors_preset(Control.PRESET_FULL_RECT)
	hint.offset_bottom = -30
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas_layer.add_child(hint)


func _unhandled_input(event: InputEvent) -> void:
	# Game-end screen: any key press dismisses it and shows the score screen.
	# Mouse clicks are handled via gui_input on the background ColorRect.
	if _game_end_screen_shown and not _game_end_dismissed:
		if event is InputEventKey and event.is_pressed() and not event.echo:
			_dismiss_game_end_screen()
		return
	# Score screen: W key triggers the watch-replay shortcut.
	if _score_shown:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_W:
				_on_watch_replay_pressed()


func _dismiss_game_end_screen() -> void:
	if _game_end_dismissed:
		return
	_game_end_dismissed = true
	var canvas_layer := get_node_or_null("CanvasLayer")
	if canvas_layer:
		for child_name in ["GameEndBackground", "GameEndLabel", "GameEndHint"]:
			var node := canvas_layer.get_node_or_null(child_name)
			if node:
				node.queue_free()
	_proceed_to_score_screen()


func _proceed_to_score_screen() -> void:
	if not _pending_score_data.is_empty():
		_show_score_screen(_pending_score_data)
	else:
		_show_victory_message()


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


func _on_score_animation_completed(container: VBoxContainer) -> void:
	_add_score_screen_buttons(container)


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


func _on_game_manager_enemy_killed() -> void:
	_show_saturation_effect()


func _show_saturation_effect() -> void:
	if _saturation_overlay == null: return
	var tween := create_tween()
	tween.tween_property(_saturation_overlay, "color:a", SATURATION_INTENSITY, SATURATION_DURATION * 0.3)
	tween.tween_property(_saturation_overlay, "color:a", 0.0, SATURATION_DURATION * 0.7)


func _update_enemy_count_label() -> void:
	if _enemy_count_label:
		_enemy_count_label.text = "Enemies: %d" % _current_enemy_count


func _update_debug_ui() -> void:
	if GameManager == null:
		return
	if _difficulty_label:
		_difficulty_label.text = "Difficulty: " + DifficultyManager.get_difficulty_name()


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


func _update_magazines_label(magazine_ammo_counts: Array) -> void:
	if _magazines_label == null:
		return
	var weapon = null
	if _player:
		weapon = _player.get_node_or_null("Shotgun")
		if weapon == null:
			weapon = _player.get_node_or_null("AssaultRifle")
		if weapon == null:
			weapon = _player.get_node_or_null("AKGL")
		if weapon == null:
			weapon = _player.get_node_or_null("MiniUzi")
		if weapon == null:
			weapon = _player.get_node_or_null("SilencedPistol")
		if weapon == null:
			weapon = _player.get_node_or_null("SniperRifle")
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


func _show_victory_message() -> void:
	var ui := get_node_or_null("CanvasLayer/UI")
	if ui == null:
		return
	var victory_label := Label.new()
	victory_label.name = "VictoryLabel"
	victory_label.text = "Конец. Спасибо за игру"
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
			replay_button.tooltip_text = "Replay recording was not available for this session"
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

	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)

	if next_level_path != "":
		buttons_container.get_node("NextLevelButton").grab_focus()
	else:
		restart_button.grab_focus()


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


func _get_next_level_path() -> String:
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
	var current_scene_path: String = get_tree().current_scene.scene_file_path
	for i in range(level_paths.size()):
		if level_paths[i] == current_scene_path:
			if i + 1 < level_paths.size():
				return level_paths[i + 1]
			return ""
	return ""


func _on_watch_replay_pressed() -> void:
	_log_to_file("Watch Replay triggered")
	var replay_manager: Node = _get_or_create_replay_manager()
	if replay_manager and replay_manager.has_method("HasReplay") and replay_manager.HasReplay():
		if replay_manager.has_method("StartPlayback"):
			replay_manager.StartPlayback(self)
	else:
		_log_to_file("Watch Replay: no replay data available")


func _on_restart_pressed() -> void:
	_log_to_file("Restart button pressed")
	if GameManager:
		GameManager.restart_scene()
	else:
		get_tree().reload_current_scene()


func _on_next_level_pressed(level_path: String) -> void:
	_log_to_file("Next Level button pressed: %s" % level_path)
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
	var error := get_tree().change_scene_to_file(level_path)
	if error != OK:
		_log_to_file("ERROR: Failed to load next level: %s" % level_path)
		Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)


func _on_level_select_pressed() -> void:
	_log_to_file("Level Select button pressed")
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)
	var levels_menu_script = load("res://scripts/ui/levels_menu.gd")
	if levels_menu_script:
		var levels_menu = CanvasLayer.new()
		levels_menu.set_script(levels_menu_script)
		levels_menu.layer = 100
		get_tree().root.add_child(levels_menu)
		levels_menu.back_pressed.connect(func(): levels_menu.queue_free())
	else:
		_log_to_file("ERROR: Could not load levels menu script")


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
			var unlock_manager: Node = get_node_or_null("/root/UnlockManager")
			if unlock_manager == null or not unlock_manager.has_method("has_any_available_unlock") or not unlock_manager.has_any_available_unlock():
				_remove_armory_button_gold_style()
		)
		armory_menu.apply_pressed_from_score_screen.connect(func():
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
				_log_to_file("%s already equipped by C# Player - skipping GDScript weapon swap" % expected_name)
				return

	if selected_weapon_id == "shotgun":
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov:
			makarov.queue_free()
		var shotgun_scene = load("res://scenes/weapons/csharp/Shotgun.tscn")
		if shotgun_scene:
			var shotgun = shotgun_scene.instantiate()
			shotgun.name = "Shotgun"
			_player.add_child(shotgun)
			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(shotgun)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = shotgun
			_log_to_file("Shotgun equipped successfully")
		else:
			push_error("[RailwayStationLevel] Failed to load Shotgun scene!")
	elif selected_weapon_id == "mini_uzi":
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov:
			makarov.queue_free()
		var mini_uzi_scene = load("res://scenes/weapons/csharp/MiniUzi.tscn")
		if mini_uzi_scene:
			var mini_uzi = mini_uzi_scene.instantiate()
			mini_uzi.name = "MiniUzi"
			_player.add_child(mini_uzi)
			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(mini_uzi)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = mini_uzi
			_log_to_file("Mini UZI equipped successfully")
		else:
			push_error("[RailwayStationLevel] Failed to load MiniUzi scene!")
	elif selected_weapon_id == "silenced_pistol":
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov:
			makarov.queue_free()
		var pistol_scene = load("res://scenes/weapons/csharp/SilencedPistol.tscn")
		if pistol_scene:
			var pistol = pistol_scene.instantiate()
			pistol.name = "SilencedPistol"
			_player.add_child(pistol)
			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(pistol)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = pistol
			_log_to_file("Silenced Pistol equipped successfully")
		else:
			push_error("[RailwayStationLevel] Failed to load SilencedPistol scene!")
	elif selected_weapon_id == "sniper":
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov:
			makarov.queue_free()
		var sniper_scene = load("res://scenes/weapons/csharp/SniperRifle.tscn")
		if sniper_scene:
			var sniper = sniper_scene.instantiate()
			sniper.name = "SniperRifle"
			_player.add_child(sniper)
			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(sniper)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = sniper
			_log_to_file("ASVK Sniper Rifle equipped successfully")
		else:
			push_error("[RailwayStationLevel] Failed to load SniperRifle scene!")
	elif selected_weapon_id == "m16":
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov:
			makarov.queue_free()
		var m16_scene = load("res://scenes/weapons/csharp/AssaultRifle.tscn")
		if m16_scene:
			var m16 = m16_scene.instantiate()
			m16.name = "AssaultRifle"
			_player.add_child(m16)
			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(m16)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = m16
			_log_to_file("M16 Assault Rifle equipped successfully")
		else:
			push_error("[RailwayStationLevel] Failed to load AssaultRifle scene!")
	elif selected_weapon_id == "ak_gl":
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov:
			makarov.queue_free()
		var akgl_scene = load("res://scenes/weapons/csharp/AKGL.tscn")
		if akgl_scene:
			var akgl = akgl_scene.instantiate()
			akgl.name = "AKGL"
			_player.add_child(akgl)
			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(akgl)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = akgl
			_log_to_file("AK + GL equipped successfully")
		else:
			push_error("[RailwayStationLevel] Failed to load AKGL scene!")
	elif selected_weapon_id == "revolver":
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov:
			makarov.queue_free()
		var revolver_scene = load("res://scenes/weapons/csharp/Revolver.tscn")
		if revolver_scene:
			var revolver = revolver_scene.instantiate()
			revolver.name = "Revolver"
			_player.add_child(revolver)
			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(revolver)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = revolver
			_log_to_file("RSh-12 Revolver equipped successfully")
		else:
			push_error("[RailwayStationLevel] Failed to load Revolver scene!")
	else:
		var makarov = _player.get_node_or_null("MakarovPM")
		if makarov and _player.get("CurrentWeapon") == null:
			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(makarov)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = makarov
			_configure_makarov_pm_ammo(makarov)


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


func _setup_sunlight() -> void:
	var environment := get_node_or_null("Environment")
	if environment == null:
		return
	var sun_node := Node2D.new()
	sun_node.name = "Sunlight"
	# Off-screen top-right — sunlight comes from top (issue says exit is where sun shines)
	sun_node.position = Vector2(2600, -400)
	environment.add_child(sun_node)
	var light := PointLight2D.new()
	light.name = "SunPointLight"
	# Cold winter sunlight — slightly blue-white
	light.color = Color(0.9, 0.92, 1.0, 1.0)
	light.energy = 1.0
	light.shadow_enabled = true
	light.shadow_filter = PointLight2D.SHADOW_FILTER_NONE
	light.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	light.texture = _create_sunlight_texture()
	# Scale large enough to cover the entire 4000x4000 map
	light.texture_scale = 20.0
	sun_node.add_child(light)
	print("[RailwayStationLevel] Sunlight placed off-screen at top-right corner")


func _create_sunlight_texture() -> ImageTexture:
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


func _log_to_file(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[RailwayStationLevel] " + message)
	else:
		print("[RailwayStationLevel] " + message)
