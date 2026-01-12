extends Node2D
## Test tier/level scene for the Godot Top-Down Template.
##
## This scene serves as a tactical combat arena for testing game mechanics.
## Features:
## - Large map (4000x2960 playable area) with multiple combat zones
## - Various cover types (low walls, barricades, crates, pillars)
## - 14 enemies in strategic positions (8 guards, 6 patrols)
## - Enemies do not respawn after death
## - Visual indicators for cover positions

## Reference to the enemy count label.
var _enemy_count_label: Label = null

## Total enemy count at start.
var _initial_enemy_count: int = 0

## Current enemy count.
var _current_enemy_count: int = 0


func _ready() -> void:
	print("TestTier loaded - Tactical Combat Arena")
	print("Map size: 4000x2960 pixels")
	print("Clear all zones to win!")

	# Find and connect to all enemies
	_setup_enemy_tracking()

	# Find the enemy count label
	_enemy_count_label = get_node_or_null("CanvasLayer/UI/EnemyCountLabel")
	_update_enemy_count_label()


func _process(_delta: float) -> void:
	pass


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
