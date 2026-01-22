extends Node2D
## Tutorial level script for teaching player basic controls.
##
## This script handles the tutorial flow:
## 1. Player approaches the targets (WASD movement)
## 2. Player shoots at targets (LMB)
##    - For shotgun: LMB shoot → RMB UP (eject shell) → RMB DOWN (chamber)
## 3. Player switches fire mode (B key) - only if player has assault rifle
## 4. Player reloads using R -> F -> R sequence
##    - For shotgun: RMB UP (open bolt) → MMB+RMB DOWN (load shells) → RMB DOWN (close bolt)
## 5. Player throws a grenade (G + RMB drag right, then G+RMB held → release G, then RMB drag and release)
## 6. Shows completion message with Q restart hint
##
## On this tutorial level, grenades are infinite so player can practice.
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
	THROW_GRENADE,
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

## Whether the player has thrown a grenade.
var _has_thrown_grenade: bool = false

## Whether the player has an assault rifle (for fire mode tutorial step).
var _has_assault_rifle: bool = false

## Whether the player has a shotgun (for shotgun-specific tutorial).
var _has_shotgun: bool = false

## Reference to the player's assault rifle weapon (for fire mode tracking).
var _assault_rifle: Node = null

## Reference to the player's shotgun weapon (for shotgun-specific tracking).
var _shotgun: Node = null

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

	# Swap weapon based on GameManager selection
	_setup_selected_weapon()

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


## Setup the weapon based on GameManager's selected weapon.
## Removes the default AssaultRifle and loads the selected weapon.
func _setup_selected_weapon() -> void:
	if _player == null:
		return

	# Get selected weapon from GameManager
	var selected_weapon_id: String = "m16"  # Default
	if GameManager:
		selected_weapon_id = GameManager.get_selected_weapon()

	print("Tutorial: Setting up weapon: %s" % selected_weapon_id)

	# If shotgun is selected, we need to swap weapons
	if selected_weapon_id == "shotgun":
		# Remove the default AssaultRifle
		var assault_rifle = _player.get_node_or_null("AssaultRifle")
		if assault_rifle:
			assault_rifle.queue_free()
			print("Tutorial: Removed default AssaultRifle")

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

			print("Tutorial: Shotgun equipped successfully")
		else:
			push_error("Tutorial: Failed to load Shotgun scene!")
	# If Mini UZI is selected, swap weapons
	elif selected_weapon_id == "mini_uzi":
		# Remove the default AssaultRifle
		var assault_rifle = _player.get_node_or_null("AssaultRifle")
		if assault_rifle:
			assault_rifle.queue_free()
			print("Tutorial: Removed default AssaultRifle")

		# Load and add the Mini UZI
		var mini_uzi_scene = load("res://scenes/weapons/csharp/MiniUzi.tscn")
		if mini_uzi_scene:
			var mini_uzi = mini_uzi_scene.instantiate()
			mini_uzi.name = "MiniUzi"
			_player.add_child(mini_uzi)

			# Set the CurrentWeapon reference in C# Player
			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(mini_uzi)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = mini_uzi

			print("Tutorial: Mini UZI equipped successfully")
		else:
			push_error("Tutorial: Failed to load MiniUzi scene!")
	# For M16 (assault rifle), it's already in the scene - just ensure it's equipped
	else:
		var assault_rifle = _player.get_node_or_null("AssaultRifle")
		if assault_rifle and _player.get("CurrentWeapon") == null:
			if _player.has_method("EquipWeapon"):
				_player.EquipWeapon(assault_rifle)
			elif _player.get("CurrentWeapon") != null:
				_player.CurrentWeapon = assault_rifle


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
		TutorialStep.THROW_GRENADE:
			# Grenade throwing is tracked via player signal
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
	var shotgun = _player.get_node_or_null("Shotgun")
	var mini_uzi = _player.get_node_or_null("MiniUzi")

	if shotgun != null:
		_shotgun = shotgun
		_has_shotgun = true
		print("Tutorial: Player has Shotgun - shotgun-specific tutorial enabled")

		# Connect to reload signals from player (C# Player)
		if _player.has_signal("ReloadCompleted"):
			_player.ReloadCompleted.connect(_on_player_reload_completed)
		elif _player.has_signal("reload_completed"):
			_player.reload_completed.connect(_on_player_reload_completed)

		# Connect to shotgun ammo signal
		if shotgun.has_signal("AmmoChanged"):
			shotgun.AmmoChanged.connect(_on_weapon_ammo_changed)

	elif mini_uzi != null:
		# Mini UZI uses rifle-like reload (no fire mode switching)
		print("Tutorial: Player has Mini UZI - rifle-like reload tutorial")

		# Connect to reload signals from player (C# Player)
		if _player.has_signal("ReloadCompleted"):
			_player.ReloadCompleted.connect(_on_player_reload_completed)
		elif _player.has_signal("reload_completed"):
			_player.reload_completed.connect(_on_player_reload_completed)

		# Connect to Mini UZI ammo signal
		if mini_uzi.has_signal("AmmoChanged"):
			mini_uzi.AmmoChanged.connect(_on_weapon_ammo_changed)

	elif weapon != null:
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

	# Connect to grenade thrown signal (both C# and GDScript players)
	if _player.has_signal("GrenadeThrown"):
		_player.GrenadeThrown.connect(_on_player_grenade_thrown)
		print("Tutorial: Connected to GrenadeThrown signal (C#)")
	elif _player.has_signal("grenade_thrown"):
		_player.grenade_thrown.connect(_on_player_grenade_thrown)
		print("Tutorial: Connected to grenade_thrown signal (GDScript)")


## Setup ammo tracking for the player's weapon.
func _setup_ammo_tracking() -> void:
	if _player == null:
		return

	# Try to get the player's weapon for C# Player
	var shotgun = _player.get_node_or_null("Shotgun")
	var mini_uzi = _player.get_node_or_null("MiniUzi")
	var weapon = _player.get_node_or_null("AssaultRifle")

	if shotgun != null:
		# C# Player with shotgun - connect to weapon signals
		if shotgun.has_signal("AmmoChanged"):
			shotgun.AmmoChanged.connect(_on_weapon_ammo_changed)
		# Connect to ShellCountChanged for real-time UI update during shell-by-shell reload
		if shotgun.has_signal("ShellCountChanged"):
			shotgun.ShellCountChanged.connect(_on_shell_count_changed)
		# Initial ammo display from shotgun
		if shotgun.get("CurrentAmmo") != null and shotgun.get("ReserveAmmo") != null:
			_update_ammo_label_magazine(shotgun.CurrentAmmo, shotgun.ReserveAmmo)
	elif mini_uzi != null:
		# C# Player with Mini UZI - connect to weapon signals
		if mini_uzi.has_signal("AmmoChanged"):
			mini_uzi.AmmoChanged.connect(_on_weapon_ammo_changed)
		# Initial ammo display from Mini UZI
		if mini_uzi.get("CurrentAmmo") != null and mini_uzi.get("ReserveAmmo") != null:
			_update_ammo_label_magazine(mini_uzi.CurrentAmmo, mini_uzi.ReserveAmmo)
	elif weapon != null:
		# C# Player with assault rifle - connect to weapon signals
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


## Called when shotgun shell count changes (during shell-by-shell reload).
## This allows the ammo counter to update immediately as each shell is loaded.
func _on_shell_count_changed(shell_count: int, _capacity: int) -> void:
	# Get the reserve ammo from the weapon for display
	var reserve_ammo: int = 0
	if _player:
		var shotgun = _player.get_node_or_null("Shotgun")
		if shotgun != null and shotgun.get("ReserveAmmo") != null:
			reserve_ammo = shotgun.ReserveAmmo
	_update_ammo_label_magazine(shell_count, reserve_ammo)


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
		_advance_to_step(TutorialStep.THROW_GRENADE)


## Called when player throws a grenade.
func _on_player_grenade_thrown() -> void:
	if _current_step != TutorialStep.THROW_GRENADE:
		return

	if not _has_thrown_grenade:
		_has_thrown_grenade = true
		print("Tutorial: Player threw grenade")
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
			if _has_shotgun:
				# Shotgun-specific shooting instructions with pump-action gestures
				# LMB shoot → RMB drag UP (eject shell) → RMB drag DOWN (chamber)
				_prompt_label.text = "[ЛКМ стрельба] [ПКМ↑ извлечь] [ПКМ↓ дослать]"
			else:
				_prompt_label.text = "[ЛКМ] Стреляй по мишеням"
		TutorialStep.SWITCH_FIRE_MODE:
			_prompt_label.text = "[B] Переключи режим стрельбы"
		TutorialStep.RELOAD:
			if _has_shotgun:
				# Shotgun-specific reload instructions with shell loading gestures
				# RMB drag UP (open bolt) → MMB+RMB drag DOWN (load shells, up to 8) → RMB drag DOWN (close bolt)
				_prompt_label.text = "[ПКМ↑ открыть] [СКМ+ПКМ↓ x8] [ПКМ↓ закрыть]"
			else:
				_prompt_label.text = "[R] [F] [R] Перезарядись"
		TutorialStep.THROW_GRENADE:
			# 2-step grenade throwing:
			# Step 1: G + RMB drag right = start timer (pin pulled)
			# Step 2: G+RMB held → release G = ready to throw (only RMB held)
			# Step 3: RMB drag and release = throw
			_prompt_label.text = "[G+ПКМ вправо] [G+ПКМ→отпусти G] [ПКМ бросок]"
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


