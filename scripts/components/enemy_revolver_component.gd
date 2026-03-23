class_name EnemyRevolverComponent
extends Node
## Revolver (RSh-12) reload and casing component for enemy (Issue #1242).
## Extracted from enemy.gd to keep script within CI line-count limits.
##
## Handles:
## - Multi-step reload sequence: open cylinder → eject casings → insert+rotate × N → close
## - Spent casing ejection with gentle gravity physics during reload

var enemy: Node2D  ## Reference to the owning enemy node

var _is_reloading_coroutine: bool = false  ## True while multi-step reload coroutine is running
var _rounds_fired: int = 0  ## Rounds fired since last reload (for casing ejection count)

## Whether the coroutine-based reload is currently running (blocks timer-based reload).
func is_reloading_coroutine() -> bool: return _is_reloading_coroutine

## Track a round fired (for casing ejection count on reload).
func track_round_fired() -> void: _rounds_fired += 1

## [Issue #1242] Multi-step revolver reload: open cylinder → eject casings → insert+rotate × N → close.
## Mirrors the player's Revolver.cs reload sequence with matching sounds.
func start_reload_sequence() -> void:
	_is_reloading_coroutine = true
	var audio: Node = enemy.get_node_or_null("/root/AudioManager")
	var ammo_needed: int = enemy.magazine_size - enemy._current_ammo
	var ammo_to_load: int = mini(ammo_needed, enemy._reserve_ammo)
	enemy._log_debug("[Revolver] Starting multi-step reload: need %d rounds, fired %d" % [ammo_to_load, _rounds_fired])

	# Step 1: Open cylinder (0.3s)
	if audio and audio.has_method("play_revolver_cylinder_open"): audio.play_revolver_cylinder_open(enemy.global_position)
	await enemy.get_tree().create_timer(0.3).timeout
	if not is_instance_valid(enemy) or not enemy._is_alive: _is_reloading_coroutine = false; return

	# Step 2: Eject spent casings (0.4s) — only eject casings for rounds actually fired
	if _rounds_fired > 0:
		if audio and audio.has_method("play_revolver_casings_eject"): audio.play_revolver_casings_eject(enemy.global_position)
		_spawn_casings(_rounds_fired)
		_rounds_fired = 0
		await enemy.get_tree().create_timer(0.4).timeout
		if not is_instance_valid(enemy) or not enemy._is_alive: _is_reloading_coroutine = false; return

	# Step 3: Insert cartridges one at a time with cylinder rotation between each
	for i in range(ammo_to_load):
		if not is_instance_valid(enemy) or not enemy._is_alive: _is_reloading_coroutine = false; return
		# Insert cartridge
		if audio and audio.has_method("play_revolver_cartridge_insert"): audio.play_revolver_cartridge_insert(enemy.global_position)
		await enemy.get_tree().create_timer(0.35).timeout
		if not is_instance_valid(enemy) or not enemy._is_alive: _is_reloading_coroutine = false; return
		# Rotate cylinder to next chamber
		if audio and audio.has_method("play_revolver_cylinder_rotate"): audio.play_revolver_cylinder_rotate(enemy.global_position)
		await enemy.get_tree().create_timer(0.2).timeout
		if not is_instance_valid(enemy) or not enemy._is_alive: _is_reloading_coroutine = false; return

	# Step 4: Close cylinder (0.3s)
	if audio and audio.has_method("play_revolver_cylinder_close"): audio.play_revolver_cylinder_close(enemy.global_position)
	await enemy.get_tree().create_timer(0.3).timeout
	if not is_instance_valid(enemy) or not enemy._is_alive: _is_reloading_coroutine = false; return

	# Complete reload: load ammo
	enemy._reserve_ammo -= ammo_to_load
	enemy._current_ammo += ammo_to_load
	enemy._is_reloading = false
	enemy._reload_timer = 0.0
	_is_reloading_coroutine = false
	enemy.reload_finished.emit()
	enemy.ammo_changed.emit(enemy._current_ammo, enemy._reserve_ammo)
	enemy._log_debug("[Revolver] Reload complete. Magazine: %d/%d, Reserve: %d" % [enemy._current_ammo, enemy.magazine_size, enemy._reserve_ammo])

## [Issue #1242] Spawn ejected casings during revolver reload (casings fall out when cylinder opens).
func _spawn_casings(count: int) -> void:
	if enemy.casing_scene == null: return
	for i in range(count):
		var casing: RigidBody2D = enemy.casing_scene.instantiate()
		casing.global_position = enemy.global_position + Vector2(randf_range(-8.0, 8.0), randf_range(-5.0, 5.0))
		# Casings fall gently (gravity drop, not forceful ejection like semi-auto)
		var horizontal_drift := randf_range(-30.0, 30.0)
		var downward_speed := randf_range(40.0, 80.0)
		casing.linear_velocity = Vector2(horizontal_drift, downward_speed)
		casing.angular_velocity = randf_range(-10.0, 10.0)
		if enemy._caliber_data:
			casing.set("caliber_data", enemy._caliber_data)
		enemy.get_tree().current_scene.add_child(casing)
