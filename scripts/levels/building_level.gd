extends Node2D
## Building level scene for the Godot Top-Down Template.
##
## This scene is a Hotline Miami 2 style building with rooms and halls.
## Features:
## - Building interior layout (~2400x2000 pixels) larger than viewport
## - Multiple interconnected rooms with corridors
## - 10 enemies distributed across different rooms (2+ per room)
## - Clear room boundaries with walls and doorways
## - Similar mechanics to TestTier (ammo tracking, enemy tracking, etc.)
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
## The ReplayManager is now a C# autoload that works reliably in exported builds,
## replacing the GDScript version that had Godot 4.3 binary tokenization issues
## (godotengine/godot#94150, godotengine/godot#96065).
func _get_or_create_replay_manager() -> Node:
	if _replay_manager != null and is_instance_valid(_replay_manager):
		return _replay_manager

	_replay_manager = get_node_or_null("/root/ReplayManager")
	if _replay_manager != null:
		# C# methods must be called with PascalCase from GDScript (no auto-conversion for user methods)
		if _replay_manager.has_method("StartRecording"):
			_log_to_file("ReplayManager found as C# autoload - verified OK")
		else:
			_log_to_file("WARNING: ReplayManager autoload exists but has no StartRecording method")
	else:
		_log_to_file("ERROR: ReplayManager autoload not found at /root/ReplayManager")

	return _replay_manager


func _ready() -> void:
	print("BuildingLevel loaded - Hotline Miami Style")
	print("Building size: ~2400x2000 pixels")
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
		print("[BuildingLevel] ERROR: ReplayManager could not be loaded!")
		return

	# Log player and enemies status for debugging
	_log_to_file("Starting replay recording - Player: %s, Enemies count: %d" % [
		_player.name if _player else "NULL",
		_enemies.size()
	])

	if _player == null:
		_log_to_file("WARNING: Player is null, replay may not record properly")
		print("[BuildingLevel] WARNING: Player is null for replay recording!")

	if _enemies.is_empty():
		_log_to_file("WARNING: No enemies to track in replay")
		print("[BuildingLevel] WARNING: No enemies registered for replay!")

	# Clear any previous replay data
	if replay_manager.has_method("ClearReplay"):
		replay_manager.ClearReplay()
		_log_to_file("Previous replay data cleared")

	# Start recording with player and enemies
	if replay_manager.has_method("StartRecording"):
		replay_manager.StartRecording(self, _player, _enemies)
		_log_to_file("Replay recording started successfully")
		print("[BuildingLevel] Replay recording started with %d enemies" % _enemies.size())
	else:
		_log_to_file("ERROR: ReplayManager.StartRecording method not found")
		print("[BuildingLevel] ERROR: StartRecording method not found!")


## Setup the exit zone near the player spawn point (left wall).
## The exit appears after all enemies are eliminated.
func _setup_exit_zone() -> void:
	# Load and instantiate the exit zone
	var exit_zone_scene = load("res://scenes/objects/ExitZone.tscn")
	if exit_zone_scene == null:
		push_warning("ExitZone scene not found - score will show immediately on level clear")
		return

	_exit_zone = exit_zone_scene.instantiate()
	# Position exit on the left wall near player spawn (player starts at 450, 1250)
	# Place exit at left wall (x=80) at similar y position
	_exit_zone.position = Vector2(120, 1250)
	_exit_zone.zone_width = 60.0
	_exit_zone.zone_height = 100.0

	# Connect the player reached exit signal
	_exit_zone.player_reached_exit.connect(_on_player_reached_exit)

	# Add to the environment node
	var environment := get_node_or_null("Environment")
	if environment:
		environment.add_child(_exit_zone)
	else:
		add_child(_exit_zone)

	print("[BuildingLevel] Exit zone created at position (120, 1250)")


## Called when the player reaches the exit zone after clearing the level.
func _on_player_reached_exit() -> void:
	if not _level_cleared:
		return

	# Prevent duplicate calls (exit zone can fire multiple times)
	if _level_completed:
		return

	print("[BuildingLevel] Player reached exit - showing score!")
	call_deferred("_complete_level_with_score")


## Activate the exit zone after all enemies are eliminated.
func _activate_exit_zone() -> void:
	if _exit_zone and _exit_zone.has_method("activate"):
		_exit_zone.activate()
		print("[BuildingLevel] Exit zone activated - go to exit to see score!")
	else:
		# Fallback: if exit zone not available, show score immediately
		push_warning("Exit zone not available - showing score immediately")
		_complete_level_with_score()


## Setup realistic visibility for the player (Issue #540).
## Adds the RealisticVisibilityComponent to the player node.
## The component handles CanvasModulate (darkness) + PointLight2D (player vision)
## and reacts to ExperimentalSettings.realistic_visibility_enabled toggle.
func _setup_realistic_visibility() -> void:
	if _player == null:
		return

	var visibility_script = load("res://scripts/components/realistic_visibility_component.gd")
	if visibility_script == null:
		push_warning("[BuildingLevel] RealisticVisibilityComponent script not found")
		return

	var visibility_component = Node.new()
	visibility_component.name = "RealisticVisibilityComponent"
	visibility_component.set_script(visibility_script)
	_player.add_child(visibility_component)
	print("[BuildingLevel] Realistic visibility component added to player")


func _process(_delta: float) -> void:
	# Update enemy positions for aggressiveness tracking
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
		# Color changes based on combo count
		var combo_color := _get_combo_color(combo)
		_combo_label.add_theme_color_override("font_color", combo_color)
		# Flash effect for combo
		_combo_label.modulate = Color.WHITE
		var tween := create_tween()
		tween.tween_property(_combo_label, "modulate", Color.WHITE, 0.1)
	else:
		_combo_label.visible = false


## Returns a color based on the current combo count.
## Higher combos produce more intense/hotter colors.
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
## Bakes the NavigationPolygon using physics collision layer 4 (walls).
func _setup_navigation() -> void:
	var nav_region: NavigationRegion2D = get_node_or_null("NavigationRegion2D")
	if nav_region == null:
		push_warning("NavigationRegion2D not found - enemy pathfinding will be limited")
		return

	var nav_poly: NavigationPolygon = nav_region.navigation_polygon
	if nav_poly == null:
		push_warning("NavigationPolygon not found - enemy pathfinding will be limited")
		return

	# Bake the navigation mesh to include physics obstacles from collision layer 4
	# This is needed because we set parsed_geometry_type = 1 (static colliders)
	# and parsed_collision_mask = 4 (walls layer) in the NavigationPolygon resource
	print("Baking navigation mesh...")
	nav_poly.clear()

	# Re-add the outline for the walkable floor area
	var floor_outline: PackedVector2Array = PackedVector2Array([
		Vector2(64, 64),
		Vector2(2464, 64),
		Vector2(2464, 2064),
		Vector2(64, 2064)
	])
	nav_poly.add_outline(floor_outline)

	# Use NavigationServer2D to bake from source geometry
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

	# Find the ammo label
	_ammo_label = get_node_or_null("CanvasLayer/UI/AmmoLabel")

	# Connect to player death signal (handles both GDScript "died" and C# "Died")
	if _player.has_signal("died"):
		_player.died.connect(_on_player_died)
	elif _player.has_signal("Died"):
		_player.Died.connect(_on_player_died)

	# Try to get the player's weapon for C# Player
	# First try shotgun (if selected), then Mini UZI, then Silenced Pistol, then assault rifle
	var weapon = _player.get_node_or_null("Shotgun")
	if weapon == null:
		weapon = _player.get_node_or_null("MiniUzi")
	if weapon == null:
		weapon = _player.get_node_or_null("SilencedPistol")
	if weapon == null:
		weapon = _player.get_node_or_null("SniperRifle")
	if weapon == null:
		weapon = _player.get_node_or_null("AssaultRifle")
	if weapon != null:
		# C# Player with weapon - connect to weapon signals
		if weapon.has_signal("AmmoChanged"):
			weapon.AmmoChanged.connect(_on_weapon_ammo_changed)
		if weapon.has_signal("MagazinesChanged"):
			weapon.MagazinesChanged.connect(_on_magazines_changed)
		if weapon.has_signal("Fired"):
			weapon.Fired.connect(_on_shot_fired)
		# Connect to ShellCountChanged for shotgun - updates ammo UI during shell-by-shell reload
		if weapon.has_signal("ShellCountChanged"):
			weapon.ShellCountChanged.connect(_on_shell_count_changed)
		# Initial ammo display from weapon
		if weapon.get("CurrentAmmo") != null and weapon.get("ReserveAmmo") != null:
			_update_ammo_label_magazine(weapon.CurrentAmmo, weapon.ReserveAmmo)
		# Initial magazine display
		if weapon.has_method("GetMagazineAmmoCounts"):
			var mag_counts: Array = weapon.GetMagazineAmmoCounts()
			_update_magazines_label(mag_counts)
		# Configure silenced pistol ammo based on enemy count
		_configure_silenced_pistol_ammo(weapon)
	else:
		# GDScript Player - connect to player signals
		if _player.has_signal("ammo_changed"):
			_player.ammo_changed.connect(_on_player_ammo_changed)
		# Initial ammo display
		if _player.has_method("get_current_ammo") and _player.has_method("get_max_ammo"):
			_update_ammo_label(_player.get_current_ammo(), _player.get_max_ammo())

	# Connect reload/ammo depleted signals for enemy aggression behavior
	# These signals are used by BOTH C# and GDScript players to notify enemies
	# that the player is vulnerable (reloading or out of ammo)
	# C# Player uses PascalCase signal names, GDScript uses snake_case
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
			# Connect to died_with_info for score tracking if available
			if child.has_signal("died_with_info"):
				child.died_with_info.connect(_on_enemy_died_with_info)
		# Track when enemy is hit for accuracy
		if child.has_signal("hit"):
			child.hit.connect(_on_enemy_hit)

	_initial_enemy_count = _enemies.size()
	_current_enemy_count = _initial_enemy_count
	_log_to_file("Enemy tracking complete: %d enemies registered" % _initial_enemy_count)
	print("Tracking %d enemies" % _initial_enemy_count)


## Configure silenced pistol ammo based on enemy count.
## This ensures the pistol has exactly enough bullets for all enemies in the level.
func _configure_silenced_pistol_ammo(weapon: Node) -> void:
	# Check if this is a silenced pistol
	if weapon.name != "SilencedPistol":
		return

	# Call the ConfigureAmmoForEnemyCount method if it exists
	if weapon.has_method("ConfigureAmmoForEnemyCount"):
		weapon.ConfigureAmmoForEnemyCount(_initial_enemy_count)
		print("[BuildingLevel] Configured silenced pistol ammo for %d enemies" % _initial_enemy_count)

		# Update the ammo display after configuration
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

	# Create kills label
	_kills_label = Label.new()
	_kills_label.name = "KillsLabel"
	_kills_label.text = "Kills: 0"
	_kills_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_kills_label.offset_left = 10
	_kills_label.offset_top = 45
	_kills_label.offset_right = 200
	_kills_label.offset_bottom = 75
	ui.add_child(_kills_label)

	# Create accuracy label
	_accuracy_label = Label.new()
	_accuracy_label.name = "AccuracyLabel"
	_accuracy_label.text = "Accuracy: 0%"
	_accuracy_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_accuracy_label.offset_left = 10
	_accuracy_label.offset_top = 75
	_accuracy_label.offset_right = 200
	_accuracy_label.offset_bottom = 105
	ui.add_child(_accuracy_label)

	# Create magazines label (shows individual magazine ammo counts)
	_magazines_label = Label.new()
	_magazines_label.name = "MagazinesLabel"
	_magazines_label.text = "MAGS: -"
	_magazines_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_magazines_label.offset_left = 10
	_magazines_label.offset_top = 105
	_magazines_label.offset_right = 400
	_magazines_label.offset_bottom = 135
	ui.add_child(_magazines_label)

	# Create combo label (shows current combo)
	# Positioned below the enemy count label (which ends at offset_bottom = 75)
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
	# Yellow/gold tint for saturation increase effect
	_saturation_overlay.color = Color(1.0, 0.9, 0.3, 0.0)
	_saturation_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_saturation_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Add to the front
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

	# Register kill with GameManager
	if GameManager:
		GameManager.register_kill()

	if _current_enemy_count <= 0:
		print("All enemies eliminated! Building cleared!")
		_level_cleared = true
		# Activate exit zone - score will show when player reaches it
		call_deferred("_activate_exit_zone")


## Called when an enemy dies with special kill information.
func _on_enemy_died_with_info(is_ricochet_kill: bool, is_penetration_kill: bool) -> void:
	# Register kill with ScoreManager including special kill info
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager and score_manager.has_method("register_kill"):
		score_manager.register_kill(is_ricochet_kill, is_penetration_kill)


## Complete the level and show the score screen.
func _complete_level_with_score() -> void:
	# Prevent duplicate calls
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

		# Log replay status for debugging
		if replay_manager.has_method("HasReplay"):
			var has_replay: bool = replay_manager.HasReplay()
			var duration: float = 0.0
			if replay_manager.has_method("GetReplayDuration"):
				duration = replay_manager.GetReplayDuration()
			_log_to_file("Replay status: has_replay=%s, duration=%.2fs" % [has_replay, duration])
			print("[BuildingLevel] Replay status: has_replay=%s, duration=%.2fs" % [has_replay, duration])
	else:
		_log_to_file("ERROR: ReplayManager not found when completing level")
		print("[BuildingLevel] ERROR: ReplayManager not found!")

	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager and score_manager.has_method("complete_level"):
		var score_data: Dictionary = score_manager.complete_level()
		_show_score_screen(score_data)
	else:
		# Fallback to simple victory message if ScoreManager not available
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
	# Register shot for accuracy tracking
	if GameManager:
		GameManager.register_shot()


## Called when weapon ammo changes (C# Player).
func _on_weapon_ammo_changed(current_ammo: int, reserve_ammo: int) -> void:
	_update_ammo_label_magazine(current_ammo, reserve_ammo)
	# Check if completely out of ammo
	if current_ammo <= 0 and reserve_ammo <= 0:
		if _current_enemy_count > 0 and not _game_over_shown:
			_show_game_over_message()


## Called when magazine inventory changes (C# Player).
func _on_magazines_changed(magazine_ammo_counts: Array) -> void:
	_update_magazines_label(magazine_ammo_counts)


## Called when shotgun shell count changes (during shell-by-shell reload).
## This allows the ammo counter to update immediately as each shell is loaded.
func _on_shell_count_changed(shell_count: int, capacity: int) -> void:
	# Get the reserve ammo from the weapon for display
	var reserve_ammo: int = 0
	if _player:
		var weapon = _player.get_node_or_null("Shotgun")
		if weapon != null and weapon.get("ReserveAmmo") != null:
			reserve_ammo = weapon.ReserveAmmo
	_update_ammo_label_magazine(shell_count, reserve_ammo)


## Called when player runs out of ammo in current magazine.
## This notifies nearby enemies that the player tried to shoot with empty weapon.
## Note: This does NOT show game over - the player may still have reserve ammo.
## Game over is only shown when BOTH current AND reserve ammo are depleted
## (handled in _on_weapon_ammo_changed for C# player, or when GDScript player
## truly has no ammo left).
func _on_player_ammo_depleted() -> void:
	# Notify all enemies that player tried to shoot with empty weapon
	_broadcast_player_ammo_empty(true)
	# Emit empty click sound via SoundPropagation system so enemies can hear through walls
	# This has shorter range than reload sound but still propagates through obstacles
	if _player:
		var sound_propagation: Node = get_node_or_null("/root/SoundPropagation")
		if sound_propagation and sound_propagation.has_method("emit_player_empty_click"):
			sound_propagation.emit_player_empty_click(_player.global_position, _player)

	# For GDScript player, check if truly out of all ammo (no reserve)
	# For C# player, game over is handled in _on_weapon_ammo_changed
	if _player and _player.has_method("get_current_ammo"):
		# GDScript player - max_ammo is the only ammo they have
		var current_ammo: int = _player.get_current_ammo()
		if current_ammo <= 0 and _current_enemy_count > 0 and not _game_over_shown:
			_show_game_over_message()
	# C# player game over is handled via _on_weapon_ammo_changed signal


## Called when player starts reloading.
## Notifies nearby enemies that player is vulnerable via sound propagation.
## The reload sound can be heard through walls at greater distance than line of sight.
func _on_player_reload_started() -> void:
	_broadcast_player_reloading(true)
	# Emit reload sound via SoundPropagation system so enemies can hear through walls
	if _player:
		var sound_propagation: Node = get_node_or_null("/root/SoundPropagation")
		if sound_propagation and sound_propagation.has_method("emit_player_reload"):
			sound_propagation.emit_player_reload(_player.global_position, _player)


## Called when player finishes reloading.
## Clears the reloading state for all enemies.
func _on_player_reload_completed() -> void:
	_broadcast_player_reloading(false)
	# Also clear ammo empty state since player now has ammo
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
	# Auto-restart via GameManager
	if GameManager:
		# Small delay to show death message
		await get_tree().create_timer(0.5).timeout
		GameManager.on_player_death()


## Called when GameManager signals enemy killed (for screen effect).
func _on_game_manager_enemy_killed() -> void:
	_show_saturation_effect()


## Shows the saturation effect when killing an enemy.
func _show_saturation_effect() -> void:
	if _saturation_overlay == null:
		return

	# Create a tween for the saturation effect
	var tween := create_tween()
	# Flash in
	tween.tween_property(_saturation_overlay, "color:a", SATURATION_INTENSITY, SATURATION_DURATION * 0.3)
	# Flash out
	tween.tween_property(_saturation_overlay, "color:a", 0.0, SATURATION_DURATION * 0.7)


## Update the ammo label with color coding (simple format for GDScript Player).
func _update_ammo_label(current: int, maximum: int) -> void:
	if _ammo_label == null:
		return

	_ammo_label.text = "AMMO: %d/%d" % [current, maximum]

	# Color coding: red at <=5, yellow at <=10, white otherwise
	if current <= 5:
		_ammo_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1.0))
	elif current <= 10:
		_ammo_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.2, 1.0))
	else:
		_ammo_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))


## Update the ammo label with magazine format (for C# Player with weapon).
## Shows format: AMMO: magazine/reserve (e.g., "AMMO: 30/60")
func _update_ammo_label_magazine(current_mag: int, reserve: int) -> void:
	if _ammo_label == null:
		return

	_ammo_label.text = "AMMO: %d/%d" % [current_mag, reserve]

	# Color coding: red when mag <=5, yellow when mag <=10
	if current_mag <= 5:
		_ammo_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1.0))
	elif current_mag <= 10:
		_ammo_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.2, 1.0))
	else:
		_ammo_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))


## Update the magazines label showing individual magazine ammo counts.
## Shows format: MAGS: [30] | 25 | 10 where [30] is current magazine.
## Hidden when a shotgun (tube magazine weapon) is equipped.
func _update_magazines_label(magazine_ammo_counts: Array) -> void:
	if _magazines_label == null:
		return

	# Check if player has a weapon with tube magazine (shotgun)
	# If so, hide the magazine label as shotguns don't use detachable magazines
	var weapon = null
	if _player:
		weapon = _player.get_node_or_null("Shotgun")
		if weapon == null:
			weapon = _player.get_node_or_null("AssaultRifle")

	if weapon != null and weapon.get("UsesTubeMagazine") == true:
		# Shotgun equipped - hide magazine display
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
			# Current magazine in brackets
			parts.append("[%d]" % ammo)
		else:
			# Spare magazines
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

	# Center the label
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
	victory_label.text = "BUILDING CLEARED!"
	victory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	victory_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	victory_label.add_theme_font_size_override("font_size", 48)
	victory_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3, 1.0))

	# Center the label
	victory_label.set_anchors_preset(Control.PRESET_CENTER)
	victory_label.offset_left = -200
	victory_label.offset_right = 200
	victory_label.offset_top = -50
	victory_label.offset_bottom = 50

	ui.add_child(victory_label)

	# Show final stats
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

	# Position below victory message
	stats_label.set_anchors_preset(Control.PRESET_CENTER)
	stats_label.offset_left = -200
	stats_label.offset_right = 200
	stats_label.offset_top = 50
	stats_label.offset_bottom = 100

	ui.add_child(stats_label)


## Show the animated score screen with Hotline Miami 2 style effects (Issue #415).
## Uses the AnimatedScoreScreen component for sequential reveal and counting animations.
## After animations complete, adds replay and restart buttons (Issue #416).
## @param score_data: Dictionary containing all score components from ScoreManager.
func _show_score_screen(score_data: Dictionary) -> void:
	var ui := get_node_or_null("CanvasLayer/UI")
	if ui == null:
		_show_victory_message()  # Fallback
		return

	# Load and use the animated score screen component
	var animated_score_screen_script = load("res://scripts/ui/animated_score_screen.gd")
	if animated_score_screen_script:
		var score_screen = animated_score_screen_script.new()
		add_child(score_screen)
		# Connect to animation_completed to add replay/restart buttons after animation
		score_screen.animation_completed.connect(_on_score_animation_completed)
		score_screen.show_animated_score(ui, score_data)
	else:
		# Fallback to simple display if animated script not found
		_show_fallback_score_screen(ui, score_data)


## Called when the animated score screen finishes all animations.
## Adds replay and restart buttons to the score screen container.
func _on_score_animation_completed(container: VBoxContainer) -> void:
	_add_score_screen_buttons(container)


## Fallback score screen if animated component is not available.
func _show_fallback_score_screen(ui: Control, score_data: Dictionary) -> void:
	# Load Gothic bitmap font for score screen labels
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

	# Add replay and restart buttons to fallback screen
	_add_score_screen_buttons(container)


## Adds Restart and Watch Replay buttons to a score screen container.
## Restart button appears first, Watch Replay button appears below it.
## W key shortcut is also enabled for Watch Replay.
func _add_score_screen_buttons(container: VBoxContainer) -> void:
	_score_shown = true

	# Add spacer
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 10
	container.add_child(spacer)

	# Add buttons container (vertical layout: Restart on top, Watch Replay below)
	var buttons_container := VBoxContainer.new()
	buttons_container.name = "ButtonsContainer"
	buttons_container.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons_container.add_theme_constant_override("separation", 10)
	container.add_child(buttons_container)

	# Restart button (on top)
	var restart_button := Button.new()
	restart_button.name = "RestartButton"
	restart_button.text = "↻ Restart (Q)"
	restart_button.custom_minimum_size = Vector2(200, 40)
	restart_button.add_theme_font_size_override("font_size", 18)
	restart_button.pressed.connect(_on_restart_pressed)
	buttons_container.add_child(restart_button)

	# Watch Replay button (below Restart)
	var replay_button := Button.new()
	replay_button.name = "ReplayButton"
	replay_button.text = "▶ Watch Replay (W)"
	replay_button.custom_minimum_size = Vector2(200, 40)
	replay_button.add_theme_font_size_override("font_size", 18)

	# Check if replay data is available
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

	# Show cursor for button interaction
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)

	# Focus the restart button
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

	# Center the label
	game_over_label.set_anchors_preset(Control.PRESET_CENTER)
	game_over_label.offset_left = -250
	game_over_label.offset_right = 250
	game_over_label.offset_top = -75
	game_over_label.offset_bottom = 75

	ui.add_child(game_over_label)


## Setup the weapon based on GameManager's selected weapon.
## Removes the default AssaultRifle and loads the selected weapon if different.
func _setup_selected_weapon() -> void:
	if _player == null:
		return

	# Get selected weapon from GameManager
	var selected_weapon_id: String = "m16"  # Default
	if GameManager:
		selected_weapon_id = GameManager.get_selected_weapon()

	_log_to_file("Setting up weapon: %s" % selected_weapon_id)

	# Check if C# Player already equipped the correct weapon (via ApplySelectedWeaponFromGameManager)
	# This prevents double-equipping when both C# and GDScript weapon setup run
	if selected_weapon_id != "m16":
		var weapon_names: Dictionary = {
			"shotgun": "Shotgun",
			"mini_uzi": "MiniUzi",
			"silenced_pistol": "SilencedPistol",
			"sniper": "SniperRifle"
		}
		if selected_weapon_id in weapon_names:
			var expected_name: String = weapon_names[selected_weapon_id]
			var existing_weapon = _player.get_node_or_null(expected_name)
			if existing_weapon != null and _player.get("CurrentWeapon") == existing_weapon:
				_log_to_file("%s already equipped by C# Player - skipping GDScript weapon swap" % expected_name)
				return

	# If shotgun is selected, we need to swap weapons
	if selected_weapon_id == "shotgun":
		# Remove the default AssaultRifle
		var assault_rifle = _player.get_node_or_null("AssaultRifle")
		if assault_rifle:
			assault_rifle.queue_free()
			print("BuildingLevel: Removed default AssaultRifle")

		# Load and add the shotgun
		var shotgun_scene = load("res://scenes/weapons/csharp/Shotgun.tscn")
		if shotgun_scene:
			var shotgun = shotgun_scene.instantiate()
			shotgun.name = "Shotgun"
			_player.add_child(shotgun)

			# Set the CurrentWeapon reference in C# Player
			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(shotgun)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = shotgun

			print("BuildingLevel: Shotgun equipped successfully")
		else:
			push_error("BuildingLevel: Failed to load Shotgun scene!")
	# If Mini UZI is selected, swap weapons
	elif selected_weapon_id == "mini_uzi":
		# Remove the default AssaultRifle
		var assault_rifle = _player.get_node_or_null("AssaultRifle")
		if assault_rifle:
			assault_rifle.queue_free()
			print("BuildingLevel: Removed default AssaultRifle")

		# Load and add the Mini UZI
		var mini_uzi_scene = load("res://scenes/weapons/csharp/MiniUzi.tscn")
		if mini_uzi_scene:
			var mini_uzi = mini_uzi_scene.instantiate()
			mini_uzi.name = "MiniUzi"

			# Reduce Mini UZI ammunition by half for Building level (issue #413)
			# Set StartingMagazineCount to 2 BEFORE adding to scene tree
			# This ensures magazines are initialized with correct count when _Ready() is called
			if mini_uzi.get("StartingMagazineCount") != null:
				mini_uzi.StartingMagazineCount = 2
				print("BuildingLevel: Mini UZI StartingMagazineCount set to 2 (before initialization)")

			_player.add_child(mini_uzi)

			# Set the CurrentWeapon reference in C# Player
			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(mini_uzi)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = mini_uzi

			print("BuildingLevel: Mini UZI equipped successfully")
		else:
			push_error("BuildingLevel: Failed to load MiniUzi scene!")
	# If Silenced Pistol is selected, swap weapons
	elif selected_weapon_id == "silenced_pistol":
		# Remove the default AssaultRifle
		var assault_rifle = _player.get_node_or_null("AssaultRifle")
		if assault_rifle:
			assault_rifle.queue_free()
			print("BuildingLevel: Removed default AssaultRifle")

		# Load and add the Silenced Pistol
		var pistol_scene = load("res://scenes/weapons/csharp/SilencedPistol.tscn")
		if pistol_scene:
			var pistol = pistol_scene.instantiate()
			pistol.name = "SilencedPistol"
			_player.add_child(pistol)

			# Set the CurrentWeapon reference in C# Player
			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(pistol)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = pistol

			print("BuildingLevel: Silenced Pistol equipped successfully")
		else:
			push_error("BuildingLevel: Failed to load SilencedPistol scene!")
	# If Sniper Rifle (ASVK) is selected, swap weapons
	elif selected_weapon_id == "sniper":
		# Remove the default AssaultRifle
		var assault_rifle = _player.get_node_or_null("AssaultRifle")
		if assault_rifle:
			assault_rifle.queue_free()
			print("BuildingLevel: Removed default AssaultRifle")

		# Load and add the Sniper Rifle
		var sniper_scene = load("res://scenes/weapons/csharp/SniperRifle.tscn")
		if sniper_scene:
			var sniper = sniper_scene.instantiate()
			sniper.name = "SniperRifle"
			_player.add_child(sniper)

			# Set the CurrentWeapon reference in C# Player
			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(sniper)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = sniper

			print("BuildingLevel: ASVK Sniper Rifle equipped successfully")
		else:
			push_error("BuildingLevel: Failed to load SniperRifle scene!")
	# For M16 (assault rifle), it's already in the scene
	else:
		var assault_rifle = _player.get_node_or_null("AssaultRifle")
		if assault_rifle:
			# Reduce M16 ammunition by half for Building level (issue #413)
			# The weapon is already initialized, so we need to reinitialize magazines
			# M16 has magazine size of 30, so 2 magazines = 60 rounds total (30+30)
			# In Power Fantasy mode, apply 3x ammo multiplier (issue #501)
			var base_magazines: int = 2
			var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
			if difficulty_manager:
				var ammo_multiplier: int = difficulty_manager.get_ammo_multiplier()
				if ammo_multiplier > 1:
					base_magazines *= ammo_multiplier
					print("BuildingLevel: Power Fantasy mode - M16 magazines multiplied by %dx (%d -> %d)" % [ammo_multiplier, 2, base_magazines])
			if assault_rifle.has_method("ReinitializeMagazines"):
				assault_rifle.ReinitializeMagazines(base_magazines, true)
				print("BuildingLevel: M16 magazines reinitialized to %d" % base_magazines)
			else:
				print("BuildingLevel: WARNING - M16 doesn't have ReinitializeMagazines method")

			if _player.get("CurrentWeapon") == null:
				if _player.has_method("EquipWeapon"):
					_player.EquipWeapon(assault_rifle)
				elif _player.get("CurrentWeapon") != null:
					_player.CurrentWeapon = assault_rifle


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


## Disable player controls after level completion (score screen shown).
## Stops physics processing and input on the player node so the player
## cannot move, shoot, or interact during the score screen.
func _disable_player_controls() -> void:
	if _player == null or not is_instance_valid(_player):
		return

	_player.set_physics_process(false)
	_player.set_process(false)
	_player.set_process_input(false)
	_player.set_process_unhandled_input(false)

	# Stop any current velocity so player doesn't slide
	if _player is CharacterBody2D:
		_player.velocity = Vector2.ZERO

	_log_to_file("Player controls disabled (level completed)")


## Log a message to the file logger if available.
func _log_to_file(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[BuildingLevel] " + message)
	else:
		print("[BuildingLevel] " + message)
