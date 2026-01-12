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
## - Limited ammunition (90 bullets = 3 magazines of 30) - no reload
## Balance: 10 enemies × (2-4 HP) = 20-40 HP total, 90 bullets available

## Reference to the enemy count label.
var _enemy_count_label: Label = null

## Reference to the ammo label.
var _ammo_label: Label = null

## Reference to the player.
var _player: CharacterBody2D = null

## Total enemy count at start.
var _initial_enemy_count: int = 0

## Current enemy count.
var _current_enemy_count: int = 0


func _ready() -> void:
	print("TestTier loaded - Tactical Combat Arena")
	print("Map size: 4000x2960 pixels")
	print("Balance: 10 enemies (2-4 HP each), 90 bullets (3 magazines)")
	print("Clear all zones to win!")

	# Find and connect to all enemies
	_setup_enemy_tracking()

	# Find the enemy count label
	_enemy_count_label = get_node_or_null("CanvasLayer/UI/EnemyCountLabel")
	_update_enemy_count_label()

	# Find and setup ammo label
	_ammo_label = get_node_or_null("CanvasLayer/UI/AmmoLabel")
	_setup_player_tracking()


func _process(_delta: float) -> void:
	pass


## Setup tracking for the player's ammo.
func _setup_player_tracking() -> void:
	_player = get_node_or_null("Entities/Player")
	if _player == null:
		return

	# Connect to player's ammo signals
	if _player.has_signal("ammo_changed"):
		_player.ammo_changed.connect(_on_player_ammo_changed)
		# Update initial ammo display
		_update_ammo_label(_player.current_ammo, _player.max_ammo)

	if _player.has_signal("out_of_ammo"):
		_player.out_of_ammo.connect(_on_player_out_of_ammo)


## Called when player's ammo changes.
func _on_player_ammo_changed(current: int, max_ammo: int) -> void:
	_update_ammo_label(current, max_ammo)


## Called when player runs out of ammo.
func _on_player_out_of_ammo() -> void:
	print("Out of ammo!")
	if _current_enemy_count > 0:
		_show_game_over_message()


## Update the ammo label in UI.
func _update_ammo_label(current: int, max_ammo: int) -> void:
	if _ammo_label:
		_ammo_label.text = "Ammo: %d/%d" % [current, max_ammo]
		# Change color based on ammo level
		if current <= 5:
			_ammo_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0))
		elif current <= 10:
			_ammo_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3, 1.0))
		else:
			_ammo_label.remove_theme_color_override("font_color")


## Setup tracking for all enemies in the scene.
func _setup_enemy_tracking() -> void:
	var enemies_node := get_node_or_null("Environment/Enemies")
	if enemies_node == null:
		return

	var enemies := []
	for child in enemies_node.get_children():
		if child.has_signal("died"):
			enemies.append(child)
			child.died.connect(_on_enemy_died)

	_initial_enemy_count = enemies.size()
	_current_enemy_count = _initial_enemy_count
	print("Tracking %d enemies" % _initial_enemy_count)


## Called when an enemy dies.
func _on_enemy_died() -> void:
	_current_enemy_count -= 1
	_update_enemy_count_label()

	if _current_enemy_count <= 0:
		print("All enemies eliminated! Arena cleared!")
		_show_victory_message()


## Update the enemy count label in UI.
func _update_enemy_count_label() -> void:
	if _enemy_count_label:
		_enemy_count_label.text = "Enemies: %d" % _current_enemy_count


## Show victory message when all enemies are eliminated.
func _show_victory_message() -> void:
	var ui := get_node_or_null("CanvasLayer/UI")
	if ui == null:
		return

	var victory_label := Label.new()
	victory_label.name = "VictoryLabel"
	victory_label.text = "ARENA CLEARED!"
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


## Show game over message when player runs out of ammo with enemies remaining.
func _show_game_over_message() -> void:
	var ui := get_node_or_null("CanvasLayer/UI")
	if ui == null:
		return

	# Check if game over message already exists
	if ui.get_node_or_null("GameOverLabel") != null:
		return

	var game_over_label := Label.new()
	game_over_label.name = "GameOverLabel"
	game_over_label.text = "OUT OF AMMO!\n%d enemies remaining" % _current_enemy_count
	game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	game_over_label.add_theme_font_size_override("font_size", 36)
	game_over_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0))

	# Center the label
	game_over_label.set_anchors_preset(Control.PRESET_CENTER)
	game_over_label.offset_left = -200
	game_over_label.offset_right = 200
	game_over_label.offset_top = -50
	game_over_label.offset_bottom = 50

	ui.add_child(game_over_label)
