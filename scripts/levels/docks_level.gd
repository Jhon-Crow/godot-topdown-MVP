extends Node2D
## Docks level scene (Issue #753).
##
## Large industrial docks environment with shipping containers, warehouses,
## and open spaces. Features 20 enemies with varied weapons for tactical gameplay.
## Map layout: ~5000x4000 pixels with water boundaries.

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
var _exit_zone: Area2D = null
var _level_cleared: bool = false
var _score_shown: bool = false
var _level_completed: bool = false
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
	print("DocksLevel loaded - Industrial Docks Combat")
	print("Docks size: ~5000x4000 pixels")
	print("Clear all enemies to win!")
	_setup_navigation()
	_setup_enemy_tracking()
	_enemy_count_label = get_node_or_null("CanvasLayer/UI/EnemyCountLabel")
	_update_enemy_count_label()
	_setup_player_tracking()
	_configure_camera()
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

	# Setup rare rain precipitation (Issue #1394)
	_setup_rain()


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
	_exit_zone.position = Vector2(120, 3800)
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


## Setup weapon hints component (Issue #809).
## Shows weapon-specific tutorial hints when player uses a new weapon.
func _setup_weapon_hints() -> void:
	if _player == null:
		return

	var canvas_layer: Node = get_node_or_null("CanvasLayer")
	if canvas_layer == null:
		push_warning("[DocksLevel] CanvasLayer node not found for weapon hints")
		return

	var hints_script = load("res://scripts/components/weapon_hints_component.gd")
	if hints_script == null:
		push_warning("[DocksLevel] WeaponHintsComponent script not found")
		return

	_weapon_hints_component = Node.new()
	_weapon_hints_component.name = "WeaponHintsComponent"
	_weapon_hints_component.set_script(hints_script)
	add_child(_weapon_hints_component)

	# Setup the component with player and CanvasLayer references (Issue #809)
	if _weapon_hints_component.has_method("setup"):
		_weapon_hints_component.setup(_player, canvas_layer)
		print("[DocksLevel] Weapon hints component added and setup")


func _process(_delta: float) -> void:
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager and score_manager.has_method("update_enemy_positions"):
		score_manager.update_enemy_positions(_enemies)
	# Issue #959: Re-check level completion when a retaliating pacifist finishes retaliation.
	if _current_enemy_count <= 0 and not _level_cleared and not _has_retaliating_pacifists():
		print("All enemies eliminated or pacified! Level cleared!")
		_level_cleared = true
		call_deferred("_activate_exit_zone")


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
	if nav_region == null:
		return
	var nav_poly: NavigationPolygon = nav_region.navigation_polygon
	if nav_poly == null:
		return
	# Issue #1289: wait for physics frame so CollisionShape2D nodes are registered
	# with PhysicsServer2D before parsing source geometry for navmesh carving.
	await get_tree().physics_frame
	nav_poly.agent_radius = 24.0
	# Issue #1289: explicit parse+bake so all wall StaticBody2D nodes are found.
	var source_geometry: NavigationMeshSourceGeometryData2D = NavigationMeshSourceGeometryData2D.new()
	NavigationServer2D.parse_source_geometry_data(nav_poly, source_geometry, self)
	NavigationServer2D.bake_from_source_geometry_data(nav_poly, source_geometry)
	# Issue #1289: push updated polygon back into the NavigationServer's live map.
	# Without this reassignment, agents still use the pre-bake (uncarved) navmesh.
	nav_region.navigation_polygon = nav_poly
	nav_region.emit_signal("bake_finished")


## Configures camera limits to allow free movement across the entire Docks map.
##
## The Docks map is 5128x4128 pixels, which is larger than the default camera limits
## set in Player.tscn (4128x3088). Without this configuration, the player spawns
## at position (200, 3900) which is outside the camera's view range (max Y = 3088),
## making the player invisible at game start.
##
## This function removes all camera limits by setting them to very large values
## (±10,000,000), allowing the camera to follow the player everywhere on this large map.
## This approach is consistent with other large maps (CastleLevel, CityLevel).
func _configure_camera() -> void:
	if _player == null:
		return

	var camera: Camera2D = _player.get_node_or_null("Camera2D")
	if camera == null:
		return

	# Remove all camera limits so it follows the player everywhere
	# This is important for large maps like the Docks where the map extends
	# beyond the default camera limits set in Player.tscn
	camera.limit_left = -10000000
	camera.limit_top = -10000000
	camera.limit_right = 10000000
	camera.limit_bottom = 10000000

	print("Camera configured: limits removed to follow player everywhere")


func _setup_player_tracking() -> void:
	_player = get_node_or_null("Entities/Player")
	if _player == null:
		push_warning("Player node not found")
		return

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
		weapon.ConfigureAmmoForEnemyCount(_initial_enemy_count)
		_log_to_file("Configured silenced pistol ammo for %d enemies" % _initial_enemy_count)
		if weapon.get("CurrentAmmo") != null and weapon.get("ReserveAmmo") != null:
			_update_ammo_label_magazine(weapon.CurrentAmmo, weapon.ReserveAmmo)
		if weapon.has_method("GetMagazineAmmoCounts"):
			var mag_counts: Array = weapon.GetMagazineAmmoCounts()
			_update_magazines_label(mag_counts)


## Configure weapon ammo for Docks level - 2x ammo for all weapons except SilencedPistol (Issue #866).
func _configure_docks_weapon_ammo(weapon: Node) -> void:
	if weapon == null:
		return

	# SilencedPistol uses enemy-count-based ammo instead (handled by _configure_silenced_pistol_ammo)
	if weapon.name == "SilencedPistol":
		return

	# Get the default starting magazine count (usually 4)
	var starting_magazines: int = 4
	if weapon.get("StartingMagazineCount") != null:
		starting_magazines = weapon.StartingMagazineCount

	# Double the magazine count for Docks level
	var docks_magazines: int = starting_magazines * 2

	# Use ReinitializeMagazines to set the new magazine count
	if weapon.has_method("ReinitializeMagazines"):
		weapon.ReinitializeMagazines(docks_magazines, true)
		_log_to_file("Doubled ammo for %s: %d magazines (was %d)" % [weapon.name, docks_magazines, starting_magazines])

		# Update UI to reflect new ammo counts
		if weapon.get("CurrentAmmo") != null and weapon.get("ReserveAmmo") != null:
			_update_ammo_label_magazine(weapon.CurrentAmmo, weapon.ReserveAmmo)
		if weapon.has_method("GetMagazineAmmoCounts"):
			var mag_counts: Array = weapon.GetMagazineAmmoCounts()
			_update_magazines_label(mag_counts)
	else:
		push_warning("[DocksLevel] Weapon %s doesn't have ReinitializeMagazines method" % weapon.name)
	# Reapply auto-reload magazine size reduction if active (Issue #1067).
	if _player != null and _player.has_method("ApplyAutoReloadAfterLevelAmmoConfig"):
		_player.ApplyAutoReloadAfterLevelAmmoConfig()


func _configure_makarov_pm_ammo(weapon: Node) -> void:
	if weapon == null:
		return
	if weapon.name != "MakarovPM":
		return
	var starting_magazines: int = 4
	if weapon.get("StartingMagazineCount") != null:
		starting_magazines = weapon.StartingMagazineCount
	var pm_magazines: int = int(round(starting_magazines * 2.5))
	if weapon.has_method("ReinitializeMagazines"):
		weapon.ReinitializeMagazines(pm_magazines, true)
		_log_to_file("2.5x ammo for MakarovPM: %d magazines (was %d)" % [pm_magazines, starting_magazines])
		if weapon.get("CurrentAmmo") != null and weapon.get("ReserveAmmo") != null:
			_update_ammo_label_magazine(weapon.CurrentAmmo, weapon.ReserveAmmo)
		if weapon.has_method("GetMagazineAmmoCounts"):
			var mag_counts: Array = weapon.GetMagazineAmmoCounts()
			_update_magazines_label(mag_counts)
	# Reapply auto-reload magazine size reduction if active (Issue #1067).
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
		# Issue #1334: After await, verify this node is still valid (scene may have reloaded)
		if not is_instance_valid(self):
			return
		GameManager.on_player_death()


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


func _setup_debug_ui() -> void:
	var ui := get_node_or_null("CanvasLayer/UI")
	if ui == null: return

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
	# Register kill with GameManager (Issue #1196: pass player kill flag to count only player kills).
	if GameManager:
		GameManager.register_kill(is_player_kill, is_penetration_kill)
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager and score_manager.has_method("register_kill"):
		score_manager.register_kill(is_ricochet_kill, is_penetration_kill)


## Issue #959: Called when an enemy becomes a pacifist via loudspeaker.
## Pacifists count as "killed" for level completion purposes.
func _on_enemy_became_pacifist(enemy: Node) -> void:
	_current_enemy_count -= 1
	# Issue #959: Do not count pacifist again when it dies - already counted here
	if is_instance_valid(enemy) and enemy.died.is_connected(_on_enemy_died):
		enemy.died.disconnect(_on_enemy_died)
	_update_enemy_count_label()
	print("[Docks] Enemy became pacifist - counting as eliminated")
	if _current_enemy_count <= 0 and not _has_retaliating_pacifists():
		print("All enemies eliminated or pacified! Level cleared!")
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
		# Notify loudspeaker progression (Issue #959)
		var aim: Node = get_node_or_null("/root/ActiveItemManager")
		if aim and aim.has_method("notify_level_completed"):
			aim.notify_level_completed(score_data.get("kills", 0) > 0)
		_show_score_screen(score_data)
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
	title_label.text = "DOCKS CLEARED!"
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
			weapon = _player.get_node_or_null("Revolver")
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
	victory_label.text = "DOCKS CLEARED!"
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
	var current_scene_path: String = get_tree().current_scene.scene_file_path
	for i in range(level_paths.size()):
		if level_paths[i] == current_scene_path:
			if i + 1 < level_paths.size():
				return level_paths[i + 1]
			return ""
	return ""


func _unhandled_input(event: InputEvent) -> void:
	if not _score_shown:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_W:
			# Issue #807: Only trigger replay if enabled in experimental settings
			var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
			if experimental_settings and experimental_settings.has_method("is_replay_enabled") and experimental_settings.is_replay_enabled():
				_on_watch_replay_pressed()


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
				# Still apply Docks-specific ammo configuration (Issue #866)
				_configure_docks_weapon_ammo(existing_weapon)
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

			# Configure 2x ammo for Docks level (Issue #866)
			_configure_docks_weapon_ammo(shotgun)

			_log_to_file("Shotgun equipped successfully")
		else:
			push_error("[DocksLevel] Failed to load Shotgun scene!")
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

			# Configure 2x ammo for Docks level (Issue #866)
			_configure_docks_weapon_ammo(mini_uzi)

			_log_to_file("Mini UZI equipped successfully")
		else:
			push_error("[DocksLevel] Failed to load MiniUzi scene!")
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
			push_error("[DocksLevel] Failed to load SilencedPistol scene!")
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

			# Configure 2x ammo for Docks level (Issue #866)
			_configure_docks_weapon_ammo(sniper)

			_log_to_file("ASVK Sniper Rifle equipped successfully")
		else:
			push_error("[DocksLevel] Failed to load SniperRifle scene!")
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

			# Configure 2x ammo for Docks level (Issue #866)
			_configure_docks_weapon_ammo(m16)

			_log_to_file("M16 Assault Rifle equipped successfully")
		else:
			push_error("[DocksLevel] Failed to load AssaultRifle scene!")
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

			# Configure 2x ammo for Docks level (Issue #866)
			_configure_docks_weapon_ammo(akgl)

			_log_to_file("AK + GL equipped successfully")
		else:
			push_error("[DocksLevel] Failed to load AKGL scene!")
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
			push_error("[DocksLevel] Failed to load Revolver scene!")
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


## Setup rare rain precipitation effect for the Docks level (Issue #1394).
## Configures the RainEffect node with exclusion zones for indoor areas
## (WarehouseA and WarehouseB) so rain does not appear inside buildings.
func _setup_rain() -> void:
	var rain: Node = get_node_or_null("RainEffect")
	if rain == null:
		push_warning("[DocksLevel] RainEffect node not found")
		return

	# WarehouseA: position (400, 1800), floor from (-250, -300) to (250, 300)
	# Including walls, the covered area is approximately:
	var warehouse_a_rect := Rect2(
		400 - 270, 1800 - 320,  # top-left corner (global)
		540, 640  # width, height (including walls)
	)
	rain.add_exclusion_zone(warehouse_a_rect)

	# WarehouseB: position (4400, 2800), floor from (-350, -400) to (350, 400)
	# Including walls, the covered area is approximately:
	var warehouse_b_rect := Rect2(
		4400 - 370, 2800 - 420,  # top-left corner (global)
		740, 840  # width, height (including walls)
	)
	rain.add_exclusion_zone(warehouse_b_rect)

	_log_to_file("Rain precipitation setup with 2 exclusion zones (WarehouseA, WarehouseB)")


func _log_to_file(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[DocksLevel] " + message)
	else:
		print("[DocksLevel] " + message)
