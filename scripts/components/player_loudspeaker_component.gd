extends Node
## Component that handles the loudspeaker active item for the player (Issue #959).
## Extracted from player.gd to reduce file size below 5000 lines.
class_name PlayerLoudspeakerComponent

## Signal emitted when the loudspeaker is activated (for level scripts to apply effect).
signal loudspeaker_activated(position: Vector2, direction: Vector2, effect_chance: float)

## Signal emitted when loudspeaker charges change.
signal loudspeaker_charges_changed(current: int, maximum: int)

## Preloaded loudspeaker cone effect script.
const LoudspeakerConeEffectScript = preload("res://scripts/effects/loudspeaker_cone_effect.gd")

## Whether the loudspeaker is equipped (active item selected in armory).
var _loudspeaker_equipped: bool = false

## Reference to the loudspeaker cone visual effect node.
var _loudspeaker_cone: Node2D = null

## Loudspeaker progress tracker (7-level system).
var _loudspeaker_progress: LoudspeakerProgress = null

## Sprite shown in player's hands during loudspeaker activation (Issue #959).
var _loudspeaker_hand_sprite: Sprite2D = null

## Timer for how long to show loudspeaker in hands (seconds).
var _loudspeaker_hold_timer: float = 0.0

## Duration to show loudspeaker in hands during activation (matches cone expand duration).
const LOUDSPEAKER_HOLD_DURATION: float = 0.6

## Reference to the parent player node.
var _player: CharacterBody2D = null

var _loudspeaker_victory_canvas: CanvasLayer = null
var _loudspeaker_victory_screen_shown: bool = false
var _loudspeaker_victory_dismissed: bool = false


func _ready() -> void:
	_player = get_parent() as CharacterBody2D
	set_process_unhandled_input(true)


## Initialize the loudspeaker if the ActiveItemManager has it selected.
func initialize() -> void:
	if _player == null:
		_player = get_parent() as CharacterBody2D

	var active_item_manager: Node = get_node_or_null("/root/ActiveItemManager")
	if active_item_manager == null:
		FileLogger.info("[Player.Loudspeaker] ActiveItemManager not found")
		return

	if not active_item_manager.has_method("has_loudspeaker"):
		FileLogger.info("[Player.Loudspeaker] ActiveItemManager missing has_loudspeaker method")
		return

	if not active_item_manager.has_loudspeaker():
		FileLogger.info("[Player.Loudspeaker] No loudspeaker selected in ActiveItemManager")
		return

	FileLogger.info("[Player.Loudspeaker] Loudspeaker selected, initializing...")

	# Reuse the persistent progress tracker from ActiveItemManager (Issue #959).
	# Do NOT create a new one here — that would reset all progression on every scene load.
	_loudspeaker_progress = active_item_manager.loudspeaker_progress
	# Reset only per-run state (charges/cooldown/all_charges_used) on respawn.
	# used_this_level is NOT reset here — it persists across deaths on the same map
	# so the first-use 100% only fires once per level visit (Issue #959).
	_loudspeaker_progress.reset_for_respawn()

	# Create the cone visual effect node
	_loudspeaker_cone = LoudspeakerConeEffectScript.new()
	_loudspeaker_cone.name = "LoudspeakerConeEffect"
	_loudspeaker_cone.z_index = 1  # Draw above floor, below UI
	_player.add_child(_loudspeaker_cone)
	_loudspeaker_cone.initialize(_player)

	_loudspeaker_equipped = true

	# Create a sprite to show loudspeaker in player's hands during activation (Issue #959)
	var weapon_mount: Node2D = _player.get_node_or_null("PlayerModel/WeaponMount")
	var loudspeaker_texture_path := "res://assets/sprites/weapons/loudspeaker_icon.png"
	if ResourceLoader.exists(loudspeaker_texture_path):
		_loudspeaker_hand_sprite = Sprite2D.new()
		_loudspeaker_hand_sprite.texture = load(loudspeaker_texture_path)
		_loudspeaker_hand_sprite.name = "LoudspeakerHandSprite"
		_loudspeaker_hand_sprite.visible = false
		_loudspeaker_hand_sprite.scale = Vector2(0.6, 0.6)
		_loudspeaker_hand_sprite.position = Vector2(10, 0)
		_loudspeaker_hand_sprite.z_index = 2
		if weapon_mount:
			weapon_mount.add_child(_loudspeaker_hand_sprite)
		else:
			_player.add_child(_loudspeaker_hand_sprite)

	var max_charges := _loudspeaker_progress.get_max_charges()
	FileLogger.info("[Player.Loudspeaker] Loudspeaker equipped, level: %d, charges: %s, effect: %.0f%%, used_this_level: %s, all_charges_used: %s" % [
		_loudspeaker_progress.current_level,
		str(max_charges) + "/" + str(max_charges) if max_charges != -1 else "unlimited",
		_loudspeaker_progress.get_effect_chance() * 100.0,
		_loudspeaker_progress.used_this_level,
		_loudspeaker_progress.all_charges_used_this_level
	])

	# Apply level start states for levels 6 and 7 (Issue #959)
	if _loudspeaker_progress.should_start_with_pacifists() or _loudspeaker_progress.is_victory_state():
		_player.call_deferred("_apply_loudspeaker_level_start_state")


## Handle loudspeaker input: press Space to emit sound cone (Issue #959).
func handle_input() -> void:
	if not _loudspeaker_equipped or _loudspeaker_progress == null:
		return

	# Update cooldown timer every frame
	_loudspeaker_progress.update(_player.get_process_delta_time())

	# Update loudspeaker hold timer (show loudspeaker sprite in hands during activation)
	if _loudspeaker_hold_timer > 0.0:
		_loudspeaker_hold_timer -= _player.get_process_delta_time()
		if _loudspeaker_hold_timer <= 0.0:
			_loudspeaker_hold_timer = 0.0
			# Restore weapon visibility
			var weapon_mount: Node2D = _player.get_node_or_null("PlayerModel/WeaponMount")
			if weapon_mount:
				for child in weapon_mount.get_children():
					if child != _loudspeaker_hand_sprite:
						child.visible = true
			if _loudspeaker_hand_sprite and is_instance_valid(_loudspeaker_hand_sprite):
				_loudspeaker_hand_sprite.visible = false

	if not Input.is_action_just_pressed("flashlight_toggle"):
		return

	# Issue #1036: Block active item use when jammed by a Radio Jammer enemy
	if ActiveItemManager.is_active_item_jammed_verbose():
		FileLogger.info("[Player.Loudspeaker] Space blocked by Radio Jammer (Issue #1036)")
		return

	if not _loudspeaker_progress.can_activate():
		FileLogger.info("[Player.Loudspeaker] Cannot activate: no charges or cooldown active")
		return

	# Determine if this is the first use before consuming the charge
	var is_first_use: bool = not _loudspeaker_progress.used_this_level

	# Consume charge / start cooldown
	_loudspeaker_progress.use()

	# Get aim direction (toward mouse cursor)
	var aim_dir := get_aim_direction()

	# Show loudspeaker in player's hands: hide weapon, show loudspeaker sprite (Issue #959)
	var weapon_mount: Node2D = _player.get_node_or_null("WeaponMount")
	if _loudspeaker_hand_sprite and is_instance_valid(_loudspeaker_hand_sprite):
		_loudspeaker_hand_sprite.visible = true
		if weapon_mount:
			for child in weapon_mount.get_children():
				if child != _loudspeaker_hand_sprite:
					child.visible = false
		_loudspeaker_hold_timer = LOUDSPEAKER_HOLD_DURATION

	# Show the cone visual effect
	if _loudspeaker_cone and is_instance_valid(_loudspeaker_cone):
		_loudspeaker_cone.play(aim_dir)

	# Effect chance: only first use at level 1 gets 100% (exactly 1 enemy); all other uses use level chance
	var is_level1_first_use: bool = is_first_use and _loudspeaker_progress.current_level == 1
	var effect_chance := 1.0 if is_level1_first_use else _loudspeaker_progress.get_effect_chance()
	var max_pacify := 1 if is_level1_first_use else -1

	# Notify all enemies on the map that a loud sound was made (they all hear it)
	_alert_all_enemies_loudspeaker()

	# Apply pacifism effect to enemies in the cone sector (Stage 5)
	var hostility_chance := _loudspeaker_progress.get_hostility_chance()
	apply_loudspeaker_effect(aim_dir, effect_chance, hostility_chance, max_pacify)

	# Emit signal so level scripts can track loudspeaker activations
	loudspeaker_activated.emit(_player.global_position, aim_dir, effect_chance)

	# Update charge display
	var max_charges := _loudspeaker_progress.get_max_charges()
	var current_charges := _loudspeaker_progress.charges_remaining
	loudspeaker_charges_changed.emit(current_charges, max_charges if max_charges != -1 else 0)

	var charges_str := "%d/%d" % [current_charges, max_charges] if max_charges != -1 else "unlimited"
	FileLogger.info("[Player.Loudspeaker] Activated! Direction: %s, Effect chance: %.0f%%, Charges: %s" % [
		aim_dir, effect_chance * 100.0, charges_str
	])


## Get the current aim direction (toward mouse cursor, or last move direction).
func get_aim_direction() -> Vector2:
	# Aim toward mouse cursor
	var mouse_pos := _player.get_global_mouse_position()
	var diff := mouse_pos - _player.global_position
	if diff.length() > 1.0:
		return diff.normalized()
	# Fallback: use current velocity direction
	if _player.velocity.length() > 1.0:
		return _player.velocity.normalized()
	return Vector2.RIGHT


## Apply the loudspeaker pacifism effect to enemies in the cone sector (Issue #959, Stage 5).
##
## Rules (from issue spec):
## - Cone half-angle: 50 degrees (same as LoudspeakerConeEffect)
## - Not behind a wall: raycasted (collision mask 4 = walls)
## - Behind cover but within 500px: still gets effect
## - Only enemies NOT previously attacked by player (not wounded/suppressed)
## - Effect chance: 100% on first use, per-level chance on subsequent uses
## - Hostility: each enemy independently rolls hostility toward any pacifist created
## - max_pacify: maximum enemies to pacify this activation (-1 = unlimited)
func apply_loudspeaker_effect(direction: Vector2, effect_chance: float, hostility_chance: float, max_pacify: int = -1) -> void:
	const CONE_HALF_ANGLE: float = 0.872664625997  # 50 degrees in radians
	const COVER_MAX_DISTANCE: float = 500.0
	var wall_mask: int = 4  # Physics layer for walls

	var enemies := _player.get_tree().get_nodes_in_group("enemies")
	var pacified_count := 0

	for enemy in enemies:
		if not enemy.has_method("apply_pacifism"):
			continue
		if not enemy.has_method("is_alive") or not enemy.is_alive():
			continue
		if not enemy.has_method("is_pacifist") or enemy.is_pacifist():
			continue  # Already pacifist

		# Issue #959: Skip enemies who were actually shot/hit by the player.
		# Note: was_attacked_by_player() also returns true for _in_alarm_mode (merely alerted),
		# but the loudspeaker itself alerts all enemies, which would block level 6+ pacification.
		# Use was_hit_by_player() which checks only actual hits (_hits_taken_in_encounter > 0).
		if enemy.has_method("was_hit_by_player") and enemy.was_hit_by_player():
			continue

		var to_enemy: Vector2 = enemy.global_position - _player.global_position
		var dist: float = to_enemy.length()

		if dist < 0.1:
			continue

		# Check cone angle
		var angle_to_enemy := abs(direction.angle_to(to_enemy.normalized()))
		if angle_to_enemy > CONE_HALF_ANGLE:
			continue

		# Line-of-sight check (raycast to enemy)
		var space_state := _player.get_world_2d().direct_space_state
		var ray := PhysicsRayQueryParameters2D.new()
		ray.from = _player.global_position
		ray.to = enemy.global_position
		ray.collision_mask = wall_mask
		ray.exclude = [_player]
		var result := space_state.intersect_ray(ray)
		var behind_wall := not result.is_empty()

		# If behind a wall (not just cover), skip — unless within 500px (cover rule)
		if behind_wall and dist > COVER_MAX_DISTANCE:
			continue

		# Roll effect chance
		if randf() > effect_chance:
			continue

		# Apply pacifism
		if enemy.apply_pacifism(hostility_chance):
			pacified_count += 1
			FileLogger.info("[Player.Loudspeaker] Pacified enemy at %s (dist=%.0f, cover=%s)" % [
				enemy.global_position, dist, str(behind_wall)
			])
			# Stop after reaching the per-activation limit (e.g. 1 on very first use at level 1)
			if max_pacify != -1 and pacified_count >= max_pacify:
				break

	FileLogger.info("[Player.Loudspeaker] Effect applied: %d/%d enemies pacified" % [
		pacified_count, enemies.size()
	])


## Alert all enemies on the map that the loudspeaker was used (they hear a loud sound).
## Per issue spec: "enemies on the whole map hear the player when this item is used".
func _alert_all_enemies_loudspeaker() -> void:
	var enemies := _player.get_tree().get_nodes_in_group("enemies")
	var alerted := 0
	for enemy in enemies:
		if enemy.has_method("alert_from_loudspeaker"):
			enemy.alert_from_loudspeaker(_player.global_position)
			alerted += 1
		elif enemy.has_method("alert"):
			enemy.alert(_player.global_position)
			alerted += 1
	FileLogger.info("[Player.Loudspeaker] Alerted %d enemies" % alerted)


## Apply loudspeaker level start state for levels 6 and 7 (Issue #959).
## Level 6: 50% of enemies start as pacifists; 1 random enemy is immune.
## Level 7: ALL enemies start as pacifists; show victory message.
## Called deferred from initialize so all enemy nodes are ready.
func apply_level_start_state() -> void:
	if _loudspeaker_progress == null:
		return

	var enemies := _player.get_tree().get_nodes_in_group("enemies")
	if enemies.is_empty():
		return

	if _loudspeaker_progress.is_victory_state():
		# Level 7: ALL enemies become pacifists
		FileLogger.info("[Player.Loudspeaker] Level 7 victory state — all enemies start as pacifists!")
		for enemy in enemies:
			if enemy.has_method("apply_pacifism") and enemy.has_method("is_alive") and enemy.is_alive():
				enemy.apply_pacifism(0.0)
		# Show victory message via a label in the UI
		_show_loudspeaker_victory_message()

	elif _loudspeaker_progress.should_start_with_pacifists():
		# Level 6: 50% enemies start as pacifists; designate 1 as immune
		var alive_enemies: Array = []
		for enemy in enemies:
			if enemy.has_method("is_alive") and enemy.is_alive():
				alive_enemies.append(enemy)

		# Pick 1 random immune enemy first (before pacifying others)
		if not alive_enemies.is_empty() and _loudspeaker_progress.has_immune_enemy():
			var immune_idx := randi() % alive_enemies.size()
			var immune_enemy: Node = alive_enemies[immune_idx]
			if immune_enemy.has_method("set_immune_to_pacifism"):
				immune_enemy.set_immune_to_pacifism(true)
				FileLogger.info("[Player.Loudspeaker] Level 6: enemy at %s is immune to pacifism" % immune_enemy.global_position)
			alive_enemies.remove_at(immune_idx)

		# Pacify 50% of remaining enemies
		alive_enemies.shuffle()
		var pacify_count: int = int(alive_enemies.size() * 0.5)
		var pacified := 0
		for i in range(pacify_count):
			var enemy: Node = alive_enemies[i]
			if enemy.has_method("apply_pacifism"):
				enemy.apply_pacifism(0.0)
				pacified += 1
		FileLogger.info("[Player.Loudspeaker] Level 6: %d/%d enemies start as pacifists" % [pacified, alive_enemies.size() + 1])


## Show the victory message for Level 7 (all enemies defeated via pacifism) (Issue #959).
func _show_loudspeaker_victory_message() -> void:
	_loudspeaker_victory_screen_shown = true
	_loudspeaker_victory_dismissed = false
	set_process_unhandled_input(true)
	if _player:
		_player.set_process_input(false)
		_player.set_process_unhandled_input(false)

	var canvas := CanvasLayer.new()
	canvas.name = "LoudspeakerVictoryCanvas"
	canvas.layer = 100
	_loudspeaker_victory_canvas = canvas
	_player.add_child(canvas)

	# Victory message label
	var label := Label.new()
	label.text = tr("LOUDSPEAKER_TRUE_ENDING_MESSAGE")
	label.add_theme_font_size_override("font_size", 36)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchor(SIDE_LEFT, 0.0)
	label.set_anchor(SIDE_RIGHT, 1.0)
	label.set_anchor(SIDE_TOP, 0.3)
	label.set_anchor(SIDE_BOTTOM, 0.7)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	canvas.add_child(label)

	var hint := Label.new()
	hint.text = tr("GAME_END_DISMISS_HINT")
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 0.8))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.set_anchor(SIDE_LEFT, 0.0)
	hint.set_anchor(SIDE_RIGHT, 1.0)
	hint.set_anchor(SIDE_TOP, 0.65)
	hint.set_anchor(SIDE_BOTTOM, 0.75)
	canvas.add_child(hint)

	# Invisible click-catcher panel
	var panel := ColorRect.new()
	panel.color = Color(0, 0, 0, 0)
	panel.set_anchor(SIDE_LEFT, 0.0)
	panel.set_anchor(SIDE_RIGHT, 1.0)
	panel.set_anchor(SIDE_TOP, 0.0)
	panel.set_anchor(SIDE_BOTTOM, 1.0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			get_viewport().set_input_as_handled()
			_dismiss_loudspeaker_victory_message()
	)
	canvas.add_child(panel)

	FileLogger.info("[Player.Loudspeaker] Victory message shown (Level 7)")


func _unhandled_input(event: InputEvent) -> void:
	if _loudspeaker_victory_screen_shown and not _loudspeaker_victory_dismissed:
		if event is InputEventKey and event.is_pressed() and not event.echo:
			get_viewport().set_input_as_handled()
			_dismiss_loudspeaker_victory_message()
		elif event is InputEventMouseButton and event.is_pressed():
			get_viewport().set_input_as_handled()
			_dismiss_loudspeaker_victory_message()


func _dismiss_loudspeaker_victory_message() -> void:
	if _loudspeaker_victory_dismissed:
		return
	_loudspeaker_victory_dismissed = true
	_show_loudspeaker_end_screen(_loudspeaker_victory_canvas)


## Show end screen after player dismisses the victory message (Issue #959).
func _show_loudspeaker_end_screen(victory_canvas: CanvasLayer) -> void:
	# Remove victory screen
	if is_instance_valid(victory_canvas):
		victory_canvas.queue_free()

	# Create end screen canvas
	var canvas := CanvasLayer.new()
	canvas.name = "LoudspeakerEndCanvas"
	canvas.layer = 101
	_player.add_child(canvas)

	# Black background
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 1)
	bg.set_anchor(SIDE_LEFT, 0.0)
	bg.set_anchor(SIDE_RIGHT, 1.0)
	bg.set_anchor(SIDE_TOP, 0.0)
	bg.set_anchor(SIDE_BOTTOM, 1.0)
	canvas.add_child(bg)

	var title := Label.new()
	title.text = tr("GAME_END_TITLE")
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.set_anchor(SIDE_LEFT, 0.0)
	title.set_anchor(SIDE_RIGHT, 1.0)
	title.set_anchor(SIDE_TOP, 0.2)
	title.set_anchor(SIDE_BOTTOM, 0.45)
	canvas.add_child(title)

	# Thank you message
	var thanks := Label.new()
	thanks.text = tr("GAME_END_THANKS")
	thanks.add_theme_font_size_override("font_size", 32)
	thanks.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1))
	thanks.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	thanks.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	thanks.set_anchor(SIDE_LEFT, 0.0)
	thanks.set_anchor(SIDE_RIGHT, 1.0)
	thanks.set_anchor(SIDE_TOP, 0.5)
	thanks.set_anchor(SIDE_BOTTOM, 0.7)
	canvas.add_child(thanks)

	FileLogger.info("[Player.Loudspeaker] End screen shown (Level 7)")


## Check if the loudspeaker is equipped (Issue #959).
func has_loudspeaker() -> bool:
	return _loudspeaker_equipped


## Get the loudspeaker progress tracker (Issue #959).
func get_loudspeaker_progress() -> LoudspeakerProgress:
	return _loudspeaker_progress
