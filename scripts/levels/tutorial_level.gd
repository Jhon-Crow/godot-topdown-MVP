extends Node2D
## Tutorial level script for teaching player basic controls.
##
## This script handles the tutorial flow:
## 1. Player approaches the targets (WASD movement)
## 2. Player shoots at targets (LMB)
## 3. Player switches fire mode (B key) - only if player has assault rifle
## 4. Player reloads using R -> F -> R sequence
## 5. Shows completion message with Q restart hint
##
## Floating key prompts appear near the player until the action is completed.

## Reference to the player node.
var _player: Node2D = null

## Reference to the UI container.
var _ui: Control = null

## Reference to the ammo count label.
var _ammo_label: Label = null

## Tutorial state tracking.
enum TutorialStep {
	MOVE_TO_TARGETS,
	SHOOT_TARGETS,
	SWITCH_FIRE_MODE,
	RELOAD,
	COMPLETED
}

## Current tutorial step.
var _current_step: TutorialStep = TutorialStep.MOVE_TO_TARGETS

## Whether each target has been hit.
var _targets_hit: int = 0

## Total number of targets in the level.
var _total_targets: int = 0

## Whether the player has reloaded.
var _has_reloaded: bool = false

## Whether the player has switched fire mode.
var _has_switched_fire_mode: bool = false

## Whether the player has an assault rifle (for fire mode tutorial step).
var _has_assault_rifle: bool = false

## Reference to the player's assault rifle weapon (for fire mode tracking).
var _assault_rifle: Node = null

## Floating prompt label that follows the player.
var _prompt_label: Label = null

## Distance threshold for being "near" targets (in pixels).
const TARGET_PROXIMITY_THRESHOLD: float = 300.0

## Position of the target zone center (average of target positions).
var _target_zone_center: Vector2 = Vector2.ZERO

## Whether player has reached the target zone.
var _reached_target_zone: bool = false


func _ready() -> void:
	print("Tutorial level loaded - Обучение")

	# Find player
	_player = get_node_or_null("Entities/Player")
	if _player == null:
		push_error("Tutorial: Player not found!")
		return

	# Find UI container
	_ui = get_node_or_null("CanvasLayer/UI")

	# Find the ammo label
	_ammo_label = get_node_or_null("CanvasLayer/UI/AmmoLabel")

	# Connect to player signals for tracking actions
	_connect_player_signals()

	# Setup ammo tracking
	_setup_ammo_tracking()

	# Find and setup targets
	_setup_targets()

	# Create floating prompt
	_create_floating_prompt()

	# Update prompt for initial step
	_update_prompt_text()

	# Register player with GameManager
	if GameManager:
		GameManager.set_player(_player)


func _process(_delta: float) -> void:
	# Update floating prompt position to follow player
	_update_prompt_position()

	# Check tutorial progression
	match _current_step:
		TutorialStep.MOVE_TO_TARGETS:
			_check_player_near_targets()
		TutorialStep.SHOOT_TARGETS:
			# Shooting is tracked via target hit signals
			pass
		TutorialStep.SWITCH_FIRE_MODE:
			# Fire mode switching is tracked via weapon signal
			pass
		TutorialStep.RELOAD:
			# Reloading is tracked via player signal
			pass
		TutorialStep.COMPLETED:
			# Tutorial is complete
			pass


## Connect to player signals for tracking tutorial actions.
func _connect_player_signals() -> void:
	if _player == null:
		return

	# Try to connect to weapon signals (C# Player)
	var weapon = _player.get_node_or_null("AssaultRifle")
	if weapon != null:
		_assault_rifle = weapon
		_has_assault_rifle = true
		print("Tutorial: Player has AssaultRifle - fire mode tutorial enabled")

		# Connect to reload signals from player (C# Player)
		if _player.has_signal("ReloadCompleted"):
			_player.ReloadCompleted.connect(_on_player_reload_completed)
		elif _player.has_signal("reload_completed"):
			_player.reload_completed.connect(_on_player_reload_completed)

		# Connect to fire mode changed signal from weapon
		if weapon.has_signal("FireModeChanged"):
			weapon.FireModeChanged.connect(_on_fire_mode_changed)
			print("Tutorial: Connected to FireModeChanged signal")
	else:
		# GDScript player
		if _player.has_signal("reload_completed"):
			_player.reload_completed.connect(_on_player_reload_completed)


## Setup ammo tracking for the player's weapon.
func _setup_ammo_tracking() -> void:
	if _player == null:
		return

	# Try to get the player's weapon for C# Player
	var weapon = _player.get_node_or_null("AssaultRifle")
	if weapon != null:
		# C# Player with weapon - connect to weapon signals
		if weapon.has_signal("AmmoChanged"):
			weapon.AmmoChanged.connect(_on_weapon_ammo_changed)
		# Initial ammo display from weapon
		if weapon.get("CurrentAmmo") != null and weapon.get("ReserveAmmo") != null:
			_update_ammo_label_magazine(weapon.CurrentAmmo, weapon.ReserveAmmo)
	else:
		# GDScript Player - connect to player signals
		if _player.has_signal("ammo_changed"):
			_player.ammo_changed.connect(_on_player_ammo_changed)
		# Initial ammo display
		if _player.has_method("get_current_ammo") and _player.has_method("get_max_ammo"):
			_update_ammo_label(_player.get_current_ammo(), _player.get_max_ammo())


## Called when weapon ammo changes (C# Player).
func _on_weapon_ammo_changed(current_ammo: int, reserve_ammo: int) -> void:
	_update_ammo_label_magazine(current_ammo, reserve_ammo)


## Called when player ammo changes (GDScript Player).
func _on_player_ammo_changed(current: int, maximum: int) -> void:
	_update_ammo_label(current, maximum)


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


## Setup targets and connect to their hit signals.
func _setup_targets() -> void:
	var targets_node := get_node_or_null("Environment/Targets")
	if targets_node == null:
		push_error("Tutorial: Targets node not found!")
		return

	var target_positions: Array[Vector2] = []

	for target in targets_node.get_children():
		_total_targets += 1
		target_positions.append(target.global_position)

		# Connect to target_hit signal for tracking (GDScript target)
		if target.has_signal("target_hit"):
			target.target_hit.connect(_on_target_hit)
		# Connect to Hit signal for C# targets
		elif target.has_signal("Hit"):
			target.Hit.connect(_on_target_hit)

	# Calculate target zone center
	if target_positions.size() > 0:
		var sum := Vector2.ZERO
		for pos in target_positions:
			sum += pos
		_target_zone_center = sum / target_positions.size()

	print("Tutorial: Found %d targets" % _total_targets)


## Check if player is near the targets.
func _check_player_near_targets() -> void:
	if _player == null or _reached_target_zone:
		return

	var distance := _player.global_position.distance_to(_target_zone_center)
	if distance < TARGET_PROXIMITY_THRESHOLD:
		_reached_target_zone = true
		_advance_to_step(TutorialStep.SHOOT_TARGETS)
		print("Tutorial: Player reached target zone")


## Called when a target is hit by the player's bullet.
func _on_target_hit() -> void:
	if _current_step != TutorialStep.SHOOT_TARGETS:
		return

	_targets_hit += 1
	print("Tutorial: Target hit (%d/%d)" % [_targets_hit, _total_targets])

	if _targets_hit >= _total_targets:
		# If player has assault rifle, go to fire mode switch step
		# Otherwise, skip directly to reload
		if _has_assault_rifle:
			_advance_to_step(TutorialStep.SWITCH_FIRE_MODE)
		else:
			_advance_to_step(TutorialStep.RELOAD)


## Called when player switches fire mode.
func _on_fire_mode_changed(_new_mode: int) -> void:
	if _current_step != TutorialStep.SWITCH_FIRE_MODE:
		return

	if not _has_switched_fire_mode:
		_has_switched_fire_mode = true
		print("Tutorial: Player switched fire mode")
		_advance_to_step(TutorialStep.RELOAD)


## Called when player completes reload.
func _on_player_reload_completed() -> void:
	if _current_step != TutorialStep.RELOAD:
		return

	if not _has_reloaded:
		_has_reloaded = true
		print("Tutorial: Player reloaded")
		_advance_to_step(TutorialStep.COMPLETED)


## Advance to the next tutorial step.
func _advance_to_step(step: TutorialStep) -> void:
	_current_step = step
	_update_prompt_text()

	if step == TutorialStep.COMPLETED:
		_show_completion_message()


## Create the floating prompt label.
func _create_floating_prompt() -> void:
	_prompt_label = Label.new()
	_prompt_label.name = "TutorialPrompt"
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 20)
	_prompt_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.3, 1.0))

	# Add shadow for better visibility
	_prompt_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_prompt_label.add_theme_constant_override("shadow_offset_x", 2)
	_prompt_label.add_theme_constant_override("shadow_offset_y", 2)

	# Set minimum size for consistent width
	_prompt_label.custom_minimum_size = Vector2(300, 30)

	# Add to CanvasLayer so it's always visible on screen
	var canvas_layer := get_node_or_null("CanvasLayer")
	if canvas_layer:
		canvas_layer.add_child(_prompt_label)
		print("Tutorial: Floating prompt created and added to CanvasLayer")
	else:
		push_error("Tutorial: CanvasLayer not found - prompts will not be displayed!")


## Update the prompt position to follow the player.
func _update_prompt_position() -> void:
	if _prompt_label == null or _player == null:
		return

	if _current_step == TutorialStep.COMPLETED:
		_prompt_label.visible = false
		return

	_prompt_label.visible = true

	# Get the canvas transform to convert world position to screen position
	# This works correctly in both editor and exported builds
	var canvas_transform: Transform2D = get_viewport().get_canvas_transform()
	var screen_pos: Vector2 = canvas_transform * _player.global_position

	# Position above the player
	# Use custom_minimum_size to ensure we get consistent label width
	_prompt_label.custom_minimum_size = Vector2(300, 30)
	_prompt_label.position = screen_pos + Vector2(-150, -80)


## Update the prompt text based on current tutorial step.
func _update_prompt_text() -> void:
	if _prompt_label == null:
		return

	match _current_step:
		TutorialStep.MOVE_TO_TARGETS:
			_prompt_label.text = "[WASD] Подойди к мишеням"
		TutorialStep.SHOOT_TARGETS:
			_prompt_label.text = "[ЛКМ] Стреляй по мишеням"
		TutorialStep.SWITCH_FIRE_MODE:
			_prompt_label.text = "[B] Переключи режим стрельбы"
		TutorialStep.RELOAD:
			_prompt_label.text = "[R] [F] [R] Перезарядись"
		TutorialStep.COMPLETED:
			_prompt_label.text = ""


## Show the completion message.
func _show_completion_message() -> void:
	if _ui == null:
		return

	# Create completion label
	var completion_label := Label.new()
	completion_label.name = "CompletionLabel"
	completion_label.text = "УРОВЕНЬ ПРОЙДЕН!"
	completion_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	completion_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	completion_label.add_theme_font_size_override("font_size", 48)
	completion_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3, 1.0))

	# Center the label
	completion_label.set_anchors_preset(Control.PRESET_CENTER)
	completion_label.offset_left = -250
	completion_label.offset_right = 250
	completion_label.offset_top = -75
	completion_label.offset_bottom = -25

	_ui.add_child(completion_label)

	# Create restart hint label
	var restart_label := Label.new()
	restart_label.name = "RestartHintLabel"
	restart_label.text = "Нажми [Q] для быстрого перезапуска"
	restart_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	restart_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	restart_label.add_theme_font_size_override("font_size", 24)
	restart_label.add_theme_color_override("font_color", Color(0.8, 0.9, 0.8, 1.0))

	# Position below completion message
	restart_label.set_anchors_preset(Control.PRESET_CENTER)
	restart_label.offset_left = -250
	restart_label.offset_right = 250
	restart_label.offset_top = 25
	restart_label.offset_bottom = 75

	_ui.add_child(restart_label)

	print("Tutorial completed!")


