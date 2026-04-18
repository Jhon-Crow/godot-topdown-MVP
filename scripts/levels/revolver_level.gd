extends Node2D

const LEVEL_SCENE_PATH := "res://scenes/levels/RevolverLevel.tscn"
## Double Corridor Level - Map designed for revolver and penetration gameplay.
##
## Map features:
## - Two parallel horizontal corridors for penetration kills (shoot through multiple enemies)
## - Reload zones with cover between corridors
## - Zone dividers block line-of-sight between spawn and corridor sections
## - Enemy groups limited to max 4-5 per zone (never >5 in close combat simultaneously)
## - Strategic cover placement for reload opportunities
##
## Map layout: H-shaped double corridor with blocked sight lines between zones
## Size: ~2000x1600 pixels
## Enemies: 12 total, 3 per corridor + 4 reload guards + 2 final patrol

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

## Reference to the magazines label.
var _magazines_label: Label = null

## Reference to the ColorRect for saturation effect.
var _saturation_overlay: ColorRect = null

## Reference to the combo label.
var _combo_label: Label = null
## Reference to active combo tween (to cancel if needed).
var _combo_tween: Tween = null

## Reference to the exit zone.
var _exit_zone: Area2D = null

## Whether the level has been cleared.
var _level_cleared: bool = false

## Whether the score screen is currently shown.
var _score_shown: bool = false

## Whether the level completion sequence has been triggered.
var _level_completed: bool = false

## Duration of saturation effect in seconds.
const SATURATION_DURATION: float = 0.15

## Saturation effect intensity (alpha).
const SATURATION_INTENSITY: float = 0.25

## List of enemy nodes for position tracking.
var _enemies: Array = []

## Cached reference to the ReplayManager autoload.
var _replay_manager: Node = null

## Weapon hints component instance (Issue #809).
var _weapon_hints_component: Node = null


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
	print("RevolverLevel loaded - Double Corridor map")
	print("Map size: ~2000x1600 pixels")
	print("Features: Two parallel corridors for penetration kills, reload zones between corridors")
	print("Press Q for quick restart")

	# Setup navigation mesh for enemy pathfinding
	_setup_navigation()

	# Find and connect to all enemies
	_setup_enemy_tracking()

	# Find the enemy count label
	_enemy_count_label = get_node_or_null("CanvasLayer/UI/EnemyCountLabel")
	_update_enemy_count_label()

	# Find and connect to the player
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

	# Setup exit zone
	_setup_exit_zone()

	# Start replay recording
	_start_replay_recording()

	# Setup weapon hints (Issue #809)
	_setup_weapon_hints()


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
		return

	_log_to_file("Starting replay recording - Player: %s, Enemies count: %d" % [
		_player.name if _player else "NULL",
		_enemies.size()
	])

	if replay_manager.has_method("ClearReplay"):
		replay_manager.ClearReplay()

	if replay_manager.has_method("StartRecording"):
		replay_manager.StartRecording(self, _player, _enemies)
		_log_to_file("Replay recording started successfully")


## Setup the exit zone near the end of the level.
func _setup_exit_zone() -> void:
	var exit_zone_scene = load("res://scenes/objects/ExitZone.tscn")
	if exit_zone_scene == null:
		push_warning("ExitZone scene not found - score will show immediately on level clear")
		return

	_exit_zone = exit_zone_scene.instantiate()
	# Position exit at the end of the level (right side)
	_exit_zone.position = Vector2(1900, 800)
	_exit_zone.zone_width = 60.0
	_exit_zone.zone_height = 100.0

	_exit_zone.player_reached_exit.connect(_on_player_reached_exit)

	var environment := get_node_or_null("Environment")
	if environment:
		environment.add_child(_exit_zone)
	else:
		add_child(_exit_zone)

	print("[RevolverLevel] Exit zone created at position (1900, 800)")


## Called when the player reaches the exit zone after clearing the level.
func _on_player_reached_exit() -> void:
	if not _level_cleared:
		return

	if _level_completed:
		return

	print("[RevolverLevel] Player reached exit - showing score!")
	call_deferred("_complete_level_with_score")


## Activate the exit zone after all enemies are eliminated.
func _activate_exit_zone() -> void:
	if _exit_zone and _exit_zone.has_method("activate"):
		_exit_zone.activate()
		print("[RevolverLevel] Exit zone activated - go to exit to see score!")
	else:
		push_warning("Exit zone not available - showing score immediately")
		_complete_level_with_score()


## Setup realistic visibility for the player.
func _setup_realistic_visibility() -> void:
	if _player == null:
		return

	var visibility_script = load("res://scripts/components/realistic_visibility_component.gd")
	if visibility_script == null:
		push_warning("[RevolverLevel] RealisticVisibilityComponent script not found")
		return

	var visibility_component = Node.new()
	visibility_component.name = "RealisticVisibilityComponent"
	visibility_component.set_script(visibility_script)
	_player.add_child(visibility_component)
	print("[RevolverLevel] Realistic visibility component added to player")


## Setup weapon hints component (Issue #809).
## Shows weapon-specific tutorial hints when player uses a new weapon.
func _setup_weapon_hints() -> void:
	if _player == null:
		return

	var canvas_layer: Node = get_node_or_null("CanvasLayer")
	if canvas_layer == null:
		push_warning("[RevolverLevel] CanvasLayer node not found for weapon hints")
		return

	var hints_script = load("res://scripts/components/weapon_hints_component.gd")
	if hints_script == null:
		push_warning("[RevolverLevel] WeaponHintsComponent script not found")
		return

	_weapon_hints_component = Node.new()
	_weapon_hints_component.name = "WeaponHintsComponent"
	_weapon_hints_component.set_script(hints_script)
	add_child(_weapon_hints_component)

	# Setup the component with player and CanvasLayer references (Issue #809)
	if _weapon_hints_component.has_method("setup"):
		_weapon_hints_component.setup(_player, canvas_layer)
		print("[RevolverLevel] Weapon hints component added and setup")


func _process(_delta: float) -> void:
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager and score_manager.has_method("update_enemy_positions"):
		score_manager.update_enemy_positions(_enemies)
	# Issue #959: Re-check level completion when a retaliating pacifist finishes retaliation.
	if _current_enemy_count <= 0 and not _level_cleared and not _has_retaliating_pacifists():
		print("All enemies eliminated or pacified! Level cleared!")
		_level_cleared = true
		call_deferred("_activate_exit_zone")


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
## RevolverLevel map: 2128x1728 px playfield framed by 32 px walls.
##   WallTop    (1064,   48), h=16  → bottom edge y=64   → limit_top    = 64
##   WallBottom (1064, 1680), h=16  → top edge   y=1664  → limit_bottom = 1664
##   WallLeft   (  48,  864), w=16  → right edge x=64    → limit_left   = 64
##   WallRight  (2080,  864), w=16  → left edge  x=2064  → limit_right  = 2064
func _configure_camera() -> void:
	if _player == null:
		return
	var camera: Camera2D = _player.get_node_or_null("Camera2D")
	if camera == null:
		push_warning("[RevolverLevel] Camera2D not found on player — cannot set camera limits")
		return
	const LIMIT_TOP: int    =   64   # WallTop bottom edge
	const LIMIT_BOTTOM: int = 1664   # WallBottom top edge
	const LIMIT_LEFT: int   =   64   # WallLeft right edge
	const LIMIT_RIGHT: int  = 2064   # WallRight left edge
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

	_setup_realistic_visibility()

	if GameManager:
		GameManager.set_player(_player)

	_ammo_label = get_node_or_null("CanvasLayer/UI/AmmoLabel")

	if _player.has_signal("died"):
		_player.died.connect(_on_player_died)
	elif _player.has_signal("Died"):
		_player.Died.connect(_on_player_died)

	# Try to get the player's currently equipped weapon
	var weapon = _player.get_node_or_null("Revolver")
	if weapon == null:
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


## Setup debug UI elements for kills and accuracy.
func _setup_debug_ui() -> void:
	var ui := get_node_or_null("CanvasLayer/UI")
	if ui == null:
		return
	var level_label: Label = ui.get_node_or_null("LevelLabel")
	LevelLocalization.apply_level_label(level_label, LEVEL_SCENE_PATH)

	_difficulty_label = Label.new()
	_difficulty_label.name = "DifficultyLabel"
	_difficulty_label.text = LevelLocalization.get_difficulty_text(DifficultyManager.get_difficulty_name())
	_difficulty_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_difficulty_label.offset_left = 10
	_difficulty_label.offset_top = 80
	_difficulty_label.offset_right = 200
	_difficulty_label.offset_bottom = 110
	ui.add_child(_difficulty_label)

	_magazines_label = Label.new()
	_magazines_label.name = "MagazinesLabel"
	_magazines_label.text = LevelLocalization.get_magazines_text([])
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
		_difficulty_label.text = LevelLocalization.get_difficulty_text(DifficultyManager.get_difficulty_name())


## Called when an enemy dies.
func _on_enemy_died() -> void:
	_current_enemy_count -= 1
	_update_enemy_count_label()

	if _current_enemy_count <= 0 and not _has_retaliating_pacifists():
		print("All enemies eliminated! Level cleared!")
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
func _on_enemy_became_pacifist(enemy: Node) -> void:
	_current_enemy_count -= 1
	# Issue #959: Do not count pacifist again when it dies - already counted here
	if is_instance_valid(enemy) and enemy.died.is_connected(_on_enemy_died):
		enemy.died.disconnect(_on_enemy_died)
	_update_enemy_count_label()
	print("[Revolver] Enemy became pacifist - counting as eliminated")
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


## Called when shotgun shell count changes.
func _on_shell_count_changed(shell_count: int, _capacity: int) -> void:
	var reserve_ammo: int = 0
	if _player:
		var weapon = _player.get_node_or_null("Shotgun")
		if weapon != null and weapon.get("ReserveAmmo") != null:
			reserve_ammo = weapon.ReserveAmmo
	_update_ammo_label_magazine(shell_count, reserve_ammo)


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


## Update the ammo label with color coding (simple format).
func _update_ammo_label(current: int, maximum: int) -> void:
	if _ammo_label == null:
		return

	_ammo_label.text = LevelLocalization.get_ammo_text(current, maximum)

	if current <= 2:
		_ammo_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1.0))
	elif current <= 3:
		_ammo_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.2, 1.0))
	else:
		_ammo_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))


## Update the ammo label with magazine format (for C# Player with weapon).
func _update_ammo_label_magazine(current_mag: int, reserve: int) -> void:
	if _ammo_label == null:
		return

	_ammo_label.text = LevelLocalization.get_ammo_text(current_mag, reserve)

	if current_mag <= 2:
		_ammo_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1.0))
	elif current_mag <= 3:
		_ammo_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.2, 1.0))
	else:
		_ammo_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))


## Update the magazines label showing individual magazine ammo counts.
func _update_magazines_label(magazine_ammo_counts: Array) -> void:
	if _magazines_label == null:
		return

	var weapon: Node = LevelLocalization.get_active_player_weapon(_player)

	if LevelLocalization.weapon_hides_magazines(weapon):
		_magazines_label.visible = false
		return
	_magazines_label.visible = true

	var parts: Array[String] = LevelLocalization.get_magazine_display_parts(weapon, magazine_ammo_counts)
	_magazines_label.text = LevelLocalization.get_magazines_text(parts)


## Update the enemy count label in UI.
func _update_enemy_count_label() -> void:
	if _enemy_count_label:
		_enemy_count_label.text = LevelLocalization.get_enemy_count_text(_current_enemy_count)


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
	victory_label.text = "LEVEL CLEARED!"
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


## Show the animated score screen.
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
	container.add_child(rank_label)

	var total_label := Label.new()
	total_label.text = "TOTAL SCORE: %d" % score_data.total_score
	total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	total_label.add_theme_font_size_override("font_size", 32)
	total_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 1.0))
	container.add_child(total_label)

	_add_score_screen_buttons(container)


## Adds buttons to a score screen container.
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


## Get color for a rank display.
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


## Show game over message when player runs out of ammo.
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


## Handle W key shortcut for Watch Replay when score is shown.
func _unhandled_input(event: InputEvent) -> void:
	if not _score_shown:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_W:
			var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
			if experimental_settings and experimental_settings.has_method("is_replay_enabled") and experimental_settings.is_replay_enabled():
				_on_watch_replay_pressed()


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


## Get the next level path based on the level ordering.
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


## Disable player controls after level completion.
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
		file_logger.log_info("[RevolverLevel] " + message)
	else:
		print("[RevolverLevel] " + message)
