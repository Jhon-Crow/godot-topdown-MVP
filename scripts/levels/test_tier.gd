extends Node2D
## Test tier/level scene for the Godot Top-Down Template.
##
## This scene serves as a tactical combat arena for testing game mechanics.
## Features:
## - Large map (4000x2960 playable area) with multiple combat zones
## - Various cover types (low walls, barricades, crates, pillars)
## - 10 enemies in strategic positions (6 guards, 4 patrols)
## - Enemies do not respawn after death
## - Visual indicators for cover positions
## - Ammo counter with color-coded warnings
## - Kill counter and accuracy display
## - Screen saturation effect on enemy kills
## - Death/victory messages
## - Quick restart with Q key

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

## Duration of saturation effect in seconds.
const SATURATION_DURATION: float = 0.15

## Saturation effect intensity (alpha).
const SATURATION_INTENSITY: float = 0.25

## Reference to the combo label.
var _combo_label: Label = null

## Reference to the running score label.
var _running_score_label: Label = null

## Reference to the timer label.
var _timer_label: Label = null


func _ready() -> void:
	print("TestTier loaded - Tactical Combat Arena")
	print("Map size: 4000x2960 pixels")
	print("Clear all zones to win!")
	print("Press Q for quick restart")

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
		GameManager.score_ui_visibility_changed.connect(_on_score_ui_visibility_changed)

	# Initialize score tracking
	_setup_score_tracking()


func _process(_delta: float) -> void:
	# Update timer display
	_update_timer_display()


## Setup tracking for the player.
func _setup_player_tracking() -> void:
	_player = get_node_or_null("Entities/Player")
	if _player == null:
		return

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
	var weapon = _player.get_node_or_null("AssaultRifle")
	if weapon != null:
		# C# Player with weapon - connect to weapon signals
		if weapon.has_signal("AmmoChanged"):
			weapon.AmmoChanged.connect(_on_weapon_ammo_changed)
		if weapon.has_signal("MagazinesChanged"):
			weapon.MagazinesChanged.connect(_on_magazines_changed)
		if weapon.has_signal("Fired"):
			weapon.Fired.connect(_on_shot_fired)
		# Initial ammo display from weapon
		if weapon.get("CurrentAmmo") != null and weapon.get("ReserveAmmo") != null:
			_update_ammo_label_magazine(weapon.CurrentAmmo, weapon.ReserveAmmo)
		# Initial magazine display
		if weapon.has_method("GetMagazineAmmoCounts"):
			var mag_counts: Array = weapon.GetMagazineAmmoCounts()
			_update_magazines_label(mag_counts)
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
		push_warning("[TestTier] Environment/Enemies node not found!")
		return

	var enemies := []
	for child in enemies_node.get_children():
		if child.has_signal("died"):
			enemies.append(child)
			# Use a unique connection per enemy to avoid issues with duplicate connections
			if not child.died.is_connected(_on_enemy_died):
				child.died.connect(_on_enemy_died)
		# Track when enemy is hit for accuracy
		if child.has_signal("hit"):
			if not child.hit.is_connected(_on_enemy_hit):
				child.hit.connect(_on_enemy_hit)

	_initial_enemy_count = enemies.size()
	_current_enemy_count = _initial_enemy_count
	print("[TestTier] Tracking %d enemies" % _initial_enemy_count)
	_log_to_file("Setup tracking for %d enemies" % _initial_enemy_count)


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


## Setup score tracking and UI elements.
func _setup_score_tracking() -> void:
	var ui := get_node_or_null("CanvasLayer/UI")
	if ui == null:
		return

	# Initialize ScoreManager for this level
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager:
		score_manager.reset_for_new_level()
		score_manager.combo_changed.connect(_on_combo_changed)
		score_manager.kill_scored.connect(_on_kill_scored)

	# Create timer label (top right)
	_timer_label = Label.new()
	_timer_label.name = "TimerLabel"
	_timer_label.text = "00:00.00"
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_timer_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_timer_label.offset_left = -150
	_timer_label.offset_right = -10
	_timer_label.offset_top = 10
	_timer_label.offset_bottom = 40
	_timer_label.add_theme_font_size_override("font_size", 20)
	ui.add_child(_timer_label)

	# Create running score label (below timer)
	_running_score_label = Label.new()
	_running_score_label.name = "RunningScoreLabel"
	_running_score_label.text = "SCORE: 0"
	_running_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_running_score_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_running_score_label.offset_left = -150
	_running_score_label.offset_right = -10
	_running_score_label.offset_top = 40
	_running_score_label.offset_bottom = 70
	_running_score_label.add_theme_font_size_override("font_size", 18)
	_running_score_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 1.0))
	ui.add_child(_running_score_label)

	# Create combo label (center-top, appears when combo active)
	_combo_label = Label.new()
	_combo_label.name = "ComboLabel"
	_combo_label.text = ""
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo_label.set_anchors_preset(Control.PRESET_TOP_CENTER)
	_combo_label.offset_left = -100
	_combo_label.offset_right = 100
	_combo_label.offset_top = 60
	_combo_label.offset_bottom = 100
	_combo_label.add_theme_font_size_override("font_size", 32)
	_combo_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.0, 1.0))
	_combo_label.visible = false
	ui.add_child(_combo_label)

	# Connect to player hit signal for damage tracking
	if _player and _player.has_signal("hit"):
		_player.hit.connect(_on_player_hit)

	# Apply initial score UI visibility setting
	if GameManager:
		_update_score_ui_visibility(GameManager.score_ui_visible)


## Update timer display.
func _update_timer_display() -> void:
	if _timer_label == null:
		return

	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager:
		var elapsed := score_manager.get_elapsed_time()
		_timer_label.text = score_manager.format_time(elapsed)


## Called when combo changes.
func _on_combo_changed(combo: int, is_active: bool) -> void:
	if _combo_label == null:
		return

	# Respect score UI visibility setting
	if GameManager and not GameManager.score_ui_visible:
		_combo_label.visible = false
		return

	if is_active and combo >= 2:
		_combo_label.text = "%dx COMBO!" % combo
		_combo_label.visible = true
		# Flash effect for combo
		var tween := create_tween()
		tween.tween_property(_combo_label, "modulate:a", 1.0, 0.05)
		tween.tween_property(_combo_label, "modulate:a", 0.7, 0.1)
	else:
		# Fade out combo label
		if _combo_label.visible:
			var tween := create_tween()
			tween.tween_property(_combo_label, "modulate:a", 0.0, 0.3)
			tween.tween_callback(func(): _combo_label.visible = false)


## Called when a kill is scored.
func _on_kill_scored(_points: int, _combo: int) -> void:
	# Update running score display
	if _running_score_label == null:
		return

	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager:
		var running_score := score_manager.get_running_score()
		_running_score_label.text = "SCORE: %s" % score_manager.format_score(running_score)


## Called when player takes damage (for score tracking).
func _on_player_hit() -> void:
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager:
		score_manager.register_damage()


## Called when score UI visibility changes from settings.
func _on_score_ui_visibility_changed(visible: bool) -> void:
	_update_score_ui_visibility(visible)


## Updates the visibility of score-related UI elements.
func _update_score_ui_visibility(visible: bool) -> void:
	if _timer_label:
		_timer_label.visible = visible
	if _running_score_label:
		_running_score_label.visible = visible
	if _combo_label and visible == false:
		_combo_label.visible = false


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
	_log_to_file("Enemy died signal received. Remaining: %d" % _current_enemy_count)
	_update_enemy_count_label()

	# Register kill with GameManager
	if GameManager:
		GameManager.register_kill()

	# Register kill with ScoreManager for combo and points
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager:
		score_manager.register_kill()

	if _current_enemy_count <= 0:
		_log_to_file("All enemies eliminated! Arena cleared!")
		print("All enemies eliminated! Arena cleared!")
		_show_victory_message()


## Log a message to the file logger if available.
func _log_to_file(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[TestTier] " + message)
	else:
		print("[TestTier] " + message)


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
func _update_magazines_label(magazine_ammo_counts: Array) -> void:
	if _magazines_label == null:
		return

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

	# Calculate final score
	var score_result: Dictionary = {}
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager and GameManager:
		score_result = score_manager.calculate_final_score(
			GameManager.shots_fired,
			GameManager.hits_landed,
			GameManager.kills
		)
	else:
		score_result = {
			"total_score": 0,
			"grade": "F",
			"base_kill_points": 0,
			"combo_bonus_points": 0,
			"time_bonus_points": 0,
			"accuracy_bonus_points": 0,
			"aggressiveness_bonus_points": 0,
			"damage_penalty_points": 0,
			"max_combo": 0,
			"completion_time": 0.0,
			"accuracy": 0.0,
			"damage_taken": 0,
			"kills_per_minute": 0.0,
		}

	# Create semi-transparent background for score display
	var score_bg := ColorRect.new()
	score_bg.name = "ScoreBackground"
	score_bg.color = Color(0.0, 0.0, 0.0, 0.7)
	score_bg.set_anchors_preset(Control.PRESET_CENTER)
	score_bg.offset_left = -250
	score_bg.offset_right = 250
	score_bg.offset_top = -200
	score_bg.offset_bottom = 200
	ui.add_child(score_bg)

	# Victory header with grade
	var grade_color := _get_grade_color(score_result.grade)
	var victory_label := Label.new()
	victory_label.name = "VictoryLabel"
	victory_label.text = "ARENA CLEARED!"
	victory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	victory_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	victory_label.add_theme_font_size_override("font_size", 36)
	victory_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3, 1.0))
	victory_label.set_anchors_preset(Control.PRESET_CENTER)
	victory_label.offset_left = -240
	victory_label.offset_right = 240
	victory_label.offset_top = -190
	victory_label.offset_bottom = -150
	ui.add_child(victory_label)

	# Grade display
	var grade_label := Label.new()
	grade_label.name = "GradeLabel"
	grade_label.text = "GRADE: %s" % score_result.grade
	grade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grade_label.add_theme_font_size_override("font_size", 48)
	grade_label.add_theme_color_override("font_color", grade_color)
	grade_label.set_anchors_preset(Control.PRESET_CENTER)
	grade_label.offset_left = -240
	grade_label.offset_right = 240
	grade_label.offset_top = -145
	grade_label.offset_bottom = -85
	ui.add_child(grade_label)

	# Score breakdown
	var breakdown_text := ""
	if score_manager:
		breakdown_text = """KILLS: %s
COMBO BONUS: %s (Max: %dx)
TIME BONUS: %s (%s)
ACCURACY BONUS: %s (%.1f%%)
AGGRESSIVENESS: %s (%.1f/min)
DAMAGE PENALTY: -%s (%d hits)
---
TOTAL SCORE: %s""" % [
			score_manager.format_score(score_result.base_kill_points),
			score_manager.format_score(score_result.combo_bonus_points),
			score_result.max_combo,
			score_manager.format_score(score_result.time_bonus_points),
			score_manager.format_time(score_result.completion_time),
			score_manager.format_score(score_result.accuracy_bonus_points),
			score_result.accuracy,
			score_manager.format_score(score_result.aggressiveness_bonus_points),
			score_result.kills_per_minute,
			score_manager.format_score(score_result.damage_penalty_points),
			score_result.damage_taken,
			score_manager.format_score(score_result.total_score)
		]
	else:
		breakdown_text = "Kills: %d | Accuracy: %.1f%%" % [GameManager.kills if GameManager else 0, GameManager.get_accuracy() if GameManager else 0.0]

	var breakdown_label := Label.new()
	breakdown_label.name = "BreakdownLabel"
	breakdown_label.text = breakdown_text
	breakdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	breakdown_label.add_theme_font_size_override("font_size", 16)
	breakdown_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
	breakdown_label.set_anchors_preset(Control.PRESET_CENTER)
	breakdown_label.offset_left = -230
	breakdown_label.offset_right = 230
	breakdown_label.offset_top = -75
	breakdown_label.offset_bottom = 150
	ui.add_child(breakdown_label)

	# Restart hint
	var restart_label := Label.new()
	restart_label.name = "RestartLabel"
	restart_label.text = "Press Q to restart"
	restart_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	restart_label.add_theme_font_size_override("font_size", 14)
	restart_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
	restart_label.set_anchors_preset(Control.PRESET_CENTER)
	restart_label.offset_left = -240
	restart_label.offset_right = 240
	restart_label.offset_top = 160
	restart_label.offset_bottom = 190
	ui.add_child(restart_label)


## Get color for grade display.
func _get_grade_color(grade: String) -> Color:
	match grade:
		"S":
			return Color(1.0, 0.0, 0.8, 1.0)  # Magenta/Pink for S (special)
		"A+":
			return Color(1.0, 0.84, 0.0, 1.0)  # Gold
		"A":
			return Color(0.2, 1.0, 0.3, 1.0)  # Green
		"B":
			return Color(0.3, 0.7, 1.0, 1.0)  # Light blue
		"C":
			return Color(1.0, 1.0, 0.3, 1.0)  # Yellow
		"D":
			return Color(1.0, 0.5, 0.2, 1.0)  # Orange
		_:
			return Color(1.0, 0.2, 0.2, 1.0)  # Red for F


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
