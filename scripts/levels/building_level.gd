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

## Whether level has been completed (all enemies killed).
var _level_completed: bool = false

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

## ANIMATED SCORE SCREEN - INLINE IMPLEMENTATION
## This bypasses Godot 4.x binary tokens export bug where external scripts
## may fail to attach properly in exported builds.
## See: https://github.com/godotengine/godot/issues/94150

## Animation timing constants for score screen.
const SCORE_TITLE_FADE_DURATION: float = 0.3
const SCORE_ITEM_REVEAL_DURATION: float = 0.15
const SCORE_ITEM_COUNT_DURATION: float = 0.8
const SCORE_PULSE_FREQUENCY: float = 12.0  ## Pulses per second during counting
const SCORE_RANK_FLASH_DURATION: float = 0.8
const SCORE_RANK_SHRINK_DURATION: float = 0.6
const SCORE_HINT_FADE_DURATION: float = 0.3

## Pulse animation settings for score screen.
const SCORE_PULSE_SCALE_MIN: float = 1.0
const SCORE_PULSE_SCALE_MAX: float = 1.15
const SCORE_PULSE_COLOR_INTENSITY: float = 0.4

## Sound settings for score screen.
const SCORE_BEEP_BASE_FREQUENCY: float = 440.0  ## Hz
const SCORE_BEEP_DURATION: float = 0.03  ## Seconds per beep
const SCORE_BEEP_VOLUME: float = -12.0  ## dB

## Rank colors for different grades in score screen.
const SCORE_RANK_COLORS: Dictionary = {
	"S": Color(1.0, 0.84, 0.0, 1.0),   # Gold
	"A+": Color(0.0, 1.0, 0.5, 1.0),   # Bright green
	"A": Color(0.2, 0.8, 0.2, 1.0),    # Green
	"B": Color(0.3, 0.7, 1.0, 1.0),    # Blue
	"C": Color(1.0, 1.0, 1.0, 1.0),    # White
	"D": Color(1.0, 0.6, 0.2, 1.0),    # Orange
	"F": Color(1.0, 0.2, 0.2, 1.0)     # Red
}

## Flash colors for rank reveal background in score screen.
const SCORE_FLASH_COLORS: Array[Color] = [
	Color(1.0, 0.0, 0.0, 0.9),   # Red
	Color(0.0, 1.0, 0.0, 0.9),   # Green
	Color(0.0, 0.0, 1.0, 0.9),   # Blue
	Color(1.0, 1.0, 0.0, 0.9),   # Yellow
	Color(1.0, 0.0, 1.0, 0.9),   # Magenta
	Color(0.0, 1.0, 1.0, 0.9)    # Cyan
]

## Score screen animation state variables.
var _score_screen_root: Control = null
var _score_background: ColorRect = null
var _score_container: VBoxContainer = null
var _score_title_label: Label = null
var _score_items_data: Array[Dictionary] = []
var _score_rank_label: Label = null
var _score_rank_background: ColorRect = null
var _score_total_label: Label = null
var _score_hint_label: Label = null
var _score_data_cache: Dictionary = {}
var _score_current_item_index: int = -1
var _score_is_animating: bool = false
var _score_counting_value: float = 0.0
var _score_counting_target: int = 0
var _score_counting_label: Label = null
var _score_counting_points_label: Label = null
var _score_pulse_time: float = 0.0
var _score_original_color: Color = Color.WHITE

## Audio player for beep sounds in score screen.
var _score_beep_player: AudioStreamPlayer = null
var _score_beep_generator: AudioStreamGenerator = null
var _score_beep_playback: AudioStreamGeneratorPlayback = null
var _score_last_beep_value: int = -1

## Duration of saturation effect in seconds.
const SATURATION_DURATION: float = 0.15

## Saturation effect intensity (alpha).
const SATURATION_INTENSITY: float = 0.25

## List of enemy nodes for position tracking.
var _enemies: Array = []


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


func _process(delta: float) -> void:
	# Update enemy positions for aggressiveness tracking
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager and score_manager.has_method("update_enemy_positions"):
		score_manager.update_enemy_positions(_enemies)

	# Handle score screen counting animation
	if _score_is_animating and _score_counting_label != null and _score_counting_target > 0:
		_score_pulse_time += delta

		# Update counting value
		var count_progress := _score_counting_value / float(_score_counting_target)
		if count_progress < 1.0:
			_score_counting_value += (float(_score_counting_target) / SCORE_ITEM_COUNT_DURATION) * delta
			_score_counting_value = minf(_score_counting_value, float(_score_counting_target))

			var current_int := int(_score_counting_value)
			_score_counting_label.text = "%d" % current_int

			# Play beep on value change (throttled)
			if current_int != _score_last_beep_value:
				_score_last_beep_value = current_int
				_score_play_beep()

			# Apply pulse effect
			_score_apply_pulse_effect()


## Called when combo changes.
func _on_combo_changed(combo: int, points: int) -> void:
	if _combo_label == null:
		return

	if combo > 0:
		_combo_label.text = "x%d COMBO (+%d)" % [combo, points]
		_combo_label.visible = true
		# Flash effect for combo
		_combo_label.modulate = Color.WHITE
		var tween := create_tween()
		tween.tween_property(_combo_label, "modulate", Color(1.0, 0.8, 0.2, 1.0), 0.1)
	else:
		_combo_label.visible = false


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
	_level_completed = true
	_log_to_file("Level completed, setting _level_completed = true")

	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager and score_manager.has_method("complete_level"):
		var score_data: Dictionary = score_manager.complete_level()
		_show_score_screen(score_data)
	else:
		# Fallback to simple victory message if ScoreManager not available
		_log_to_file("ScoreManager not available, showing simple victory message")
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
	# Check if completely out of ammo (but not if level is already completed)
	if current_ammo <= 0 and reserve_ammo <= 0:
		if _current_enemy_count > 0 and not _game_over_shown and not _level_completed:
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
		if current_ammo <= 0 and _current_enemy_count > 0 and not _game_over_shown and not _level_completed:
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

	var parts: Array[String] = []
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


## Show the animated score screen with full breakdown (Hotline Miami 2 style).
## @param score_data: Dictionary containing all score components from ScoreManager.
##
## Features sequential item reveal, counting animations, pulsing effects,
## retro sound effects, and dramatic rank reveal animation.
##
## Note: The score screen is created in its own CanvasLayer (layer 100) to ensure
## it renders on top of all other UI elements, including cinema effects (layer 99).
##
## Session 6 Fix: Uses preload() instead of load() to ensure the scene and its
## script are properly embedded at compile time. Runtime load() may fail to
## properly attach scripts in exported builds.
##
## Session 7 Fix: Added forced script re-attachment workaround for Godot 4.x
## binary tokens export bug where has_method() returns false despite script
## being attached. The preloaded script is re-applied if needed.
## See: https://github.com/godotengine/godot/issues/94150
## Show the animated score screen with inline implementation.
## This bypasses Godot 4.x binary tokens export bug (godotengine/godot#94150).
## All animation logic is implemented directly in this file instead of relying
## on external scripts that may fail to attach properly in exported builds.
func _show_score_screen(score_data: Dictionary) -> void:
	_log_to_file("_show_score_screen called with score_data: %s" % str(score_data))
	print("[BuildingLevel] _show_score_screen called - rank: %s" % score_data.get("rank", "?"))
	print("[BuildingLevel] Using INLINE animated score screen (bypasses binary tokens bug)")

	var ui := get_node_or_null("CanvasLayer/UI")
	if ui == null:
		_log_to_file("ERROR: CanvasLayer/UI not found, falling back to victory message")
		_show_victory_message()  # Fallback
		return

	_log_to_file("Found UI node: %s, size: %s" % [ui.name, str(ui.size) if ui is Control else "N/A"])

	# Hide the "OUT OF AMMO" message if it was shown (level was completed despite low ammo)
	var game_over_label := ui.get_node_or_null("GameOverLabel")
	if game_over_label:
		game_over_label.queue_free()
		_log_to_file("Removed GameOverLabel (out of ammo message)")

	# Store score data for animation callbacks
	_score_data_cache = score_data
	_score_is_animating = true

	# Create a dedicated CanvasLayer for the score screen
	# Layer 100 ensures it renders above everything, including CinemaEffects (layer 99)
	var score_canvas_layer := CanvasLayer.new()
	score_canvas_layer.name = "ScoreScreenCanvasLayer"
	score_canvas_layer.layer = 100
	add_child(score_canvas_layer)
	_log_to_file("Created ScoreScreenCanvasLayer at layer 100")

	# Create root control for the score screen
	_score_screen_root = Control.new()
	_score_screen_root.name = "InlineAnimatedScoreScreen"
	_score_screen_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_score_screen_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_canvas_layer.add_child(_score_screen_root)
	_log_to_file("Created InlineAnimatedScoreScreen root control")

	# Force the size to match viewport
	var viewport_size := get_viewport().get_visible_rect().size
	_score_screen_root.size = viewport_size
	_log_to_file("Set score_screen size to viewport: %s" % str(viewport_size))

	# Setup beep audio for counting sounds
	_score_setup_beep_audio()

	# Create background - starts transparent, will animate to semi-opaque
	_score_background = ColorRect.new()
	_score_background.name = "ScoreBackground"
	_score_background.color = Color(0.0, 0.0, 0.0, 0.0)  # Starts fully transparent
	_score_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_score_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_background.visible = true
	_score_screen_root.add_child(_score_background)
	_log_to_file("Background created")

	# Create main container - starts invisible, will animate to visible
	_score_container = VBoxContainer.new()
	_score_container.name = "ScoreContainer"
	_score_container.set_anchors_preset(Control.PRESET_CENTER)
	_score_container.offset_left = -300
	_score_container.offset_right = 300
	_score_container.offset_top = -280
	_score_container.offset_bottom = 350
	_score_container.add_theme_constant_override("separation", 8)
	_score_container.modulate.a = 0.0  # Starts invisible
	_score_container.visible = true
	_score_screen_root.add_child(_score_container)
	_log_to_file("Container created")

	# Build score items list
	_score_build_items()
	_log_to_file("Built %d score items" % _score_items_data.size())

	# Start animation sequence
	_score_animate_background_fade()
	_log_to_file("Animation sequence started")
	print("[BuildingLevel] Inline score screen animation started")


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


#region INLINE ANIMATED SCORE SCREEN FUNCTIONS
## These functions implement the animated score screen directly in building_level.gd
## to bypass Godot 4.x binary tokens export bug (godotengine/godot#94150).

## Setup the beep sound generator for retro-style counting sounds.
func _score_setup_beep_audio() -> void:
	_score_beep_player = AudioStreamPlayer.new()
	_score_beep_player.bus = "Master"
	_score_beep_player.volume_db = SCORE_BEEP_VOLUME
	_score_screen_root.add_child(_score_beep_player)

	# Create generator stream
	_score_beep_generator = AudioStreamGenerator.new()
	_score_beep_generator.mix_rate = 44100.0
	_score_beep_generator.buffer_length = 0.1
	_score_beep_player.stream = _score_beep_generator


## Play a short major arpeggio sound for score counting.
func _score_play_beep() -> void:
	if _score_beep_player == null:
		return

	# Start playback if not already playing
	if not _score_beep_player.playing:
		_score_beep_player.play()
		_score_beep_playback = _score_beep_player.get_stream_playback()

	if _score_beep_playback == null:
		return

	# Generate a short major arpeggio (root, major third, perfect fifth)
	var sample_rate := _score_beep_generator.mix_rate
	var note_duration := SCORE_BEEP_DURATION / 3.0
	var samples_per_note := int(note_duration * sample_rate)

	# Calculate frequencies for major arpeggio
	var root_freq := SCORE_BEEP_BASE_FREQUENCY + randf_range(-20.0, 20.0)
	var third_freq := root_freq * pow(2.0, 4.0 / 12.0)  # Major third
	var fifth_freq := root_freq * pow(2.0, 7.0 / 12.0)  # Perfect fifth

	var arpeggio_freqs := [root_freq, third_freq, fifth_freq]

	for note_idx in range(3):
		var frequency := arpeggio_freqs[note_idx]
		for i in range(samples_per_note):
			if _score_beep_playback.can_push_buffer(1):
				var t := float(i) / sample_rate
				# Square wave for retro sound
				var sample := 0.25 if fmod(t * frequency, 1.0) < 0.5 else -0.25
				# Apply envelope for each note (attack and decay)
				var note_progress := float(i) / float(samples_per_note)
				var envelope := 1.0 - (note_progress * 0.5)
				_score_beep_playback.push_frame(Vector2(sample * envelope, sample * envelope))


## Apply pulsing effect to the current counting label.
func _score_apply_pulse_effect() -> void:
	if _score_counting_points_label == null:
		return

	# Calculate pulse factor (0 to 1, oscillating)
	var pulse_factor := (sin(_score_pulse_time * SCORE_PULSE_FREQUENCY * TAU) + 1.0) / 2.0

	# Apply scale pulse
	var scale_value := lerpf(SCORE_PULSE_SCALE_MIN, SCORE_PULSE_SCALE_MAX, pulse_factor)
	_score_counting_points_label.scale = Vector2(scale_value, scale_value)

	# Apply color pulse (interpolate toward white/bright)
	var pulse_color := _score_original_color.lerp(Color.WHITE, pulse_factor * SCORE_PULSE_COLOR_INTENSITY)
	_score_counting_points_label.add_theme_color_override("font_color", pulse_color)


## Build the list of score items to display.
func _score_build_items() -> void:
	_score_items_data.clear()

	# Core score categories
	_score_items_data.append({
		"category": "KILLS",
		"value": "%d/%d" % [_score_data_cache.get("kills", 0), _score_data_cache.get("total_enemies", 0)],
		"points": _score_data_cache.get("kill_points", 0),
		"is_positive": true
	})

	_score_items_data.append({
		"category": "COMBOS",
		"value": "Max x%d" % _score_data_cache.get("max_combo", 0),
		"points": _score_data_cache.get("combo_points", 0),
		"is_positive": true
	})

	_score_items_data.append({
		"category": "TIME",
		"value": "%.1fs" % _score_data_cache.get("completion_time", 0.0),
		"points": _score_data_cache.get("time_bonus", 0),
		"is_positive": true
	})

	_score_items_data.append({
		"category": "ACCURACY",
		"value": "%.1f%%" % _score_data_cache.get("accuracy", 0.0),
		"points": _score_data_cache.get("accuracy_bonus", 0),
		"is_positive": true
	})

	# Optional: Special kills
	var ricochet_kills: int = _score_data_cache.get("ricochet_kills", 0)
	var penetration_kills: int = _score_data_cache.get("penetration_kills", 0)
	if ricochet_kills > 0 or penetration_kills > 0:
		var special_text := ""
		if ricochet_kills > 0:
			special_text += "%d ricochet" % ricochet_kills
		if penetration_kills > 0:
			if special_text != "":
				special_text += ", "
			special_text += "%d penetration" % penetration_kills

		var special_eligible: bool = _score_data_cache.get("special_kills_eligible", false)
		_score_items_data.append({
			"category": "SPECIAL KILLS",
			"value": special_text,
			"points": _score_data_cache.get("special_kill_bonus", 0) if special_eligible else 0,
			"is_positive": special_eligible,
			"note": "" if special_eligible else "(need aggression)"
		})

	# Optional: Damage penalty
	var damage_taken: int = _score_data_cache.get("damage_taken", 0)
	if damage_taken > 0:
		_score_items_data.append({
			"category": "DAMAGE TAKEN",
			"value": "%d hits" % damage_taken,
			"points": _score_data_cache.get("damage_penalty", 0),
			"is_positive": false
		})


## Animate background fade in.
func _score_animate_background_fade() -> void:
	_log_to_file("_score_animate_background_fade() starting")

	var tween := create_tween()
	if tween == null:
		_log_to_file("ERROR: create_tween() returned null!")
		# Fallback: directly set values without animation
		_score_background.color.a = 0.7
		_score_container.modulate.a = 1.0
		_score_create_title()
		return

	_log_to_file("Tween created successfully")
	tween.tween_property(_score_background, "color:a", 0.7, SCORE_TITLE_FADE_DURATION)
	tween.tween_property(_score_container, "modulate:a", 1.0, SCORE_TITLE_FADE_DURATION)
	tween.tween_callback(_score_create_title)


## Create and animate the title.
func _score_create_title() -> void:
	_score_title_label = Label.new()
	_score_title_label.text = "LEVEL CLEARED!"
	_score_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_title_label.add_theme_font_size_override("font_size", 42)
	_score_title_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3, 1.0))
	_score_title_label.modulate.a = 0.0
	_score_container.add_child(_score_title_label)

	var tween := create_tween()
	tween.tween_property(_score_title_label, "modulate:a", 1.0, SCORE_TITLE_FADE_DURATION)
	tween.tween_callback(_score_start_item_sequence)


## Start the sequential item reveal.
func _score_start_item_sequence() -> void:
	_score_current_item_index = -1
	_score_animate_next_item()


## Animate the next score item in sequence.
func _score_animate_next_item() -> void:
	_score_current_item_index += 1

	if _score_current_item_index >= _score_items_data.size():
		# All items done, show total score
		_score_animate_total()
		return

	var item_data: Dictionary = _score_items_data[_score_current_item_index]
	_score_create_item_row(item_data)


## Create a score item row with animation.
func _score_create_item_row(item_data: Dictionary) -> void:
	var line_container := HBoxContainer.new()
	line_container.add_theme_constant_override("separation", 20)
	line_container.modulate.a = 0.0
	_score_container.add_child(line_container)

	# Category label
	var category_label := Label.new()
	category_label.text = item_data.category
	category_label.add_theme_font_size_override("font_size", 18)
	category_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
	category_label.custom_minimum_size.x = 150
	line_container.add_child(category_label)

	# Value label
	var value_label := Label.new()
	value_label.text = item_data.value
	value_label.add_theme_font_size_override("font_size", 18)
	value_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	value_label.custom_minimum_size.x = 150
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line_container.add_child(value_label)

	# Points label (will be animated)
	var points_label := Label.new()
	var points_value: int = item_data.points
	var is_positive: bool = item_data.is_positive
	var note: String = item_data.get("note", "")

	if note != "":
		points_label.text = note
		points_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 1.0))
	else:
		points_label.text = "0"
		if is_positive:
			points_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4, 1.0))
		else:
			points_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 1.0))

	points_label.add_theme_font_size_override("font_size", 18)
	points_label.custom_minimum_size.x = 100
	points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	points_label.pivot_offset = Vector2(50, 9)
	line_container.add_child(points_label)

	# Fade in the row
	var tween := create_tween()
	tween.tween_property(line_container, "modulate:a", 1.0, SCORE_ITEM_REVEAL_DURATION)

	# Start counting animation if has points
	if points_value > 0 and note == "":
		tween.tween_callback(func():
			_score_start_counting(points_label, points_value, is_positive)
		)
	else:
		# No counting needed, proceed to next item
		tween.tween_interval(0.2)
		tween.tween_callback(_score_animate_next_item)


## Start the counting animation for a points label.
func _score_start_counting(label: Label, target: int, is_positive: bool) -> void:
	_score_counting_label = label
	_score_counting_points_label = label
	_score_counting_target = target
	_score_counting_value = 0.0
	_score_pulse_time = 0.0
	_score_last_beep_value = -1

	# Store original color
	if is_positive:
		_score_original_color = Color(0.4, 1.0, 0.4, 1.0)
	else:
		_score_original_color = Color(1.0, 0.4, 0.4, 1.0)

	# Create timer to end counting
	var timer := get_tree().create_timer(SCORE_ITEM_COUNT_DURATION)
	timer.timeout.connect(func():
		_score_finish_counting(is_positive)
	)


## Finish the counting animation.
func _score_finish_counting(is_positive: bool) -> void:
	if _score_counting_points_label != null:
		# Set final value with proper formatting
		var prefix := "+" if is_positive else "-"
		_score_counting_points_label.text = "%s%d" % [prefix, _score_counting_target]

		# Reset scale and color
		_score_counting_points_label.scale = Vector2.ONE
		_score_counting_points_label.add_theme_color_override("font_color", _score_original_color)

	_score_counting_label = null
	_score_counting_points_label = null
	_score_counting_target = 0
	_score_counting_value = 0.0

	# Proceed to next item after brief pause
	var tween := create_tween()
	tween.tween_interval(0.15)
	tween.tween_callback(_score_animate_next_item)


## Animate the total score display.
func _score_animate_total() -> void:
	# Add separator
	var separator := HSeparator.new()
	separator.add_theme_constant_override("separation", 15)
	separator.modulate.a = 0.0
	_score_container.add_child(separator)

	# Total score label
	_score_total_label = Label.new()
	_score_total_label.text = "TOTAL: 0"
	_score_total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_total_label.add_theme_font_size_override("font_size", 32)
	_score_total_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 1.0))
	_score_total_label.modulate.a = 0.0
	_score_total_label.pivot_offset = Vector2(150, 16)
	_score_container.add_child(_score_total_label)

	var tween := create_tween()
	tween.tween_property(separator, "modulate:a", 1.0, SCORE_ITEM_REVEAL_DURATION)
	tween.tween_property(_score_total_label, "modulate:a", 1.0, SCORE_ITEM_REVEAL_DURATION)
	tween.tween_callback(_score_start_total_counting)


## Start counting animation for total score.
func _score_start_total_counting() -> void:
	var total_score: int = _score_data_cache.get("total_score", 0)
	_score_counting_label = _score_total_label
	_score_counting_points_label = _score_total_label
	_score_counting_target = total_score
	_score_counting_value = 0.0
	_score_pulse_time = 0.0
	_score_last_beep_value = -1
	_score_original_color = Color(1.0, 0.9, 0.3, 1.0)

	var timer := get_tree().create_timer(SCORE_ITEM_COUNT_DURATION * 1.2)
	timer.timeout.connect(_score_finish_total_counting)


## Finish total score counting and show rank.
func _score_finish_total_counting() -> void:
	if _score_total_label != null:
		_score_total_label.text = "TOTAL: %d" % _score_data_cache.get("total_score", 0)
		_score_total_label.scale = Vector2.ONE
		_score_total_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 1.0))

	_score_counting_label = null
	_score_counting_points_label = null

	var tween := create_tween()
	tween.tween_interval(0.3)
	tween.tween_callback(_score_start_rank_animation)


## Start the dramatic rank reveal animation.
func _score_start_rank_animation() -> void:
	var rank: String = _score_data_cache.get("rank", "F")
	var rank_color: Color = SCORE_RANK_COLORS.get(rank, Color.WHITE)

	# Create fullscreen flash background
	_score_rank_background = ColorRect.new()
	_score_rank_background.name = "RankFlashBackground"
	_score_rank_background.color = SCORE_FLASH_COLORS[0]
	_score_rank_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_score_rank_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_rank_background.modulate.a = 0.0
	_score_screen_root.add_child(_score_rank_background)

	# Create large centered rank label
	_score_rank_label = Label.new()
	_score_rank_label.text = rank
	_score_rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_rank_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_score_rank_label.add_theme_font_size_override("font_size", 200)
	_score_rank_label.add_theme_color_override("font_color", rank_color)
	_score_rank_label.set_anchors_preset(Control.PRESET_CENTER)
	_score_rank_label.offset_left = -150
	_score_rank_label.offset_right = 150
	_score_rank_label.offset_top = -120
	_score_rank_label.offset_bottom = 120
	_score_rank_label.modulate.a = 0.0
	_score_screen_root.add_child(_score_rank_label)

	# Animate flash background and rank appear
	var tween := create_tween()
	tween.tween_property(_score_rank_background, "modulate:a", 1.0, 0.1)
	tween.parallel().tween_property(_score_rank_label, "modulate:a", 1.0, 0.1)

	# Flash color cycling
	var flash_count := 6
	for i in range(flash_count):
		var color_index := (i + 1) % SCORE_FLASH_COLORS.size()
		tween.tween_property(_score_rank_background, "color", SCORE_FLASH_COLORS[color_index], SCORE_RANK_FLASH_DURATION / float(flash_count))

	tween.tween_callback(_score_shrink_rank)


## Shrink the rank label to its final position.
func _score_shrink_rank() -> void:
	# Fade out flash background
	var tween := create_tween()
	tween.tween_property(_score_rank_background, "modulate:a", 0.0, SCORE_RANK_SHRINK_DURATION * 0.5)

	# Calculate final position (below total, centered)
	var final_font_size := 48
	var final_offset_top := 250
	var final_half_width := 75

	# Animate rank shrinking
	tween.parallel().tween_method(
		func(font_size: int): _score_rank_label.add_theme_font_size_override("font_size", font_size),
		200, final_font_size, SCORE_RANK_SHRINK_DURATION
	)

	# Move to final position (centered horizontally, below total score)
	tween.parallel().tween_property(_score_rank_label, "offset_top", final_offset_top, SCORE_RANK_SHRINK_DURATION)
	tween.parallel().tween_property(_score_rank_label, "offset_bottom", final_offset_top + 60, SCORE_RANK_SHRINK_DURATION)
	tween.parallel().tween_property(_score_rank_label, "offset_left", -final_half_width, SCORE_RANK_SHRINK_DURATION)
	tween.parallel().tween_property(_score_rank_label, "offset_right", final_half_width, SCORE_RANK_SHRINK_DURATION)

	tween.tween_callback(_score_show_restart_hint)


## Show the restart hint after all animations complete.
func _score_show_restart_hint() -> void:
	_score_hint_label = Label.new()
	_score_hint_label.text = "\nPress Q to restart"
	_score_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_hint_label.add_theme_font_size_override("font_size", 16)
	_score_hint_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1.0))
	_score_hint_label.modulate.a = 0.0
	_score_container.add_child(_score_hint_label)

	var tween := create_tween()
	tween.tween_property(_score_hint_label, "modulate:a", 1.0, SCORE_HINT_FADE_DURATION)
	tween.tween_callback(_score_on_animation_complete)


## Called when all score screen animations are complete.
func _score_on_animation_complete() -> void:
	_score_is_animating = false
	_log_to_file("Score screen animation completed")
	print("[BuildingLevel] Score screen animation completed")

#endregion


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

	print("BuildingLevel: Setting up weapon: %s" % selected_weapon_id)

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
	# For M16 (assault rifle), it's already in the scene
	else:
		var assault_rifle = _player.get_node_or_null("AssaultRifle")
		if assault_rifle:
			# Reduce M16 ammunition by half for Building level (issue #413)
			# The weapon is already initialized, so we need to reinitialize magazines
			# M16 has magazine size of 30, so 2 magazines = 60 rounds total (30+30)
			if assault_rifle.has_method("ReinitializeMagazines"):
				assault_rifle.ReinitializeMagazines(2, true)
				print("BuildingLevel: M16 magazines reinitialized to 2 (reduced by half)")
			else:
				print("BuildingLevel: WARNING - M16 doesn't have ReinitializeMagazines method")

			if _player.get("CurrentWeapon") == null:
				if _player.has_method("EquipWeapon"):
					_player.EquipWeapon(assault_rifle)
				elif _player.get("CurrentWeapon") != null:
					_player.CurrentWeapon = assault_rifle


## Log a message to the file logger if available.
func _log_to_file(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[BuildingLevel] " + message)
	else:
		print("[BuildingLevel] " + message)
