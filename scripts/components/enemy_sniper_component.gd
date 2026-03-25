extends Node
## Sniper rifle enemy component (Issues #1163, #1171, #1336).
## Handles three responsibilities:
##   1. AI behaviour: kiting (standoff range), retreat when player closes in,
##      and blind-fire through cover at last-known / predicted player positions.
##   2. Hitscan shooting: instant raycast avoids physics tunnelling at 10000px/s.
##   3. Laser sight: always points where the next shot will travel (Issue #1336).
## Extracted from enemy.gd to keep the file below the 5000-line CI limit.
class_name EnemySniperComponent

# ============================================================================
# Configuration — AI behaviour (Issue #1163)
# ============================================================================

## Preferred engagement range (px).
const PREFERRED_DISTANCE: float = 550.0
## Below this distance: actively retreat from player.
const MIN_DISTANCE: float = 350.0
## Seconds between blind-fire shots through cover.
const BLIND_FIRE_COOLDOWN: float = 5.0

## Laser sight maximum range (px). Issue #1336.
const LASER_MAX_RANGE: float = 5000.0
## Muzzle offset from weapon sprite origin to barrel tip (px, before scale).
const MUZZLE_LOCAL_OFFSET: float = 52.0

# ============================================================================
# State
# ============================================================================

## Timer for blind fire at predicted player position.
var blind_fire_timer: float = 0.0

## Reference to the owner enemy node.  Set explicitly by enemy.gd on instantiation
## (preferred) or resolved via get_parent() in _ready() as a fallback.
var enemy: Node2D = null
## Enable file logging (forwarded from enemy debug setting).
var log_to_file_fn: Callable = Callable()

## Issue #1336: Current blind-fire target position (Vector2.ZERO when not blind-firing).
## Updated by process_combat/process_pursuing so the laser always shows where the
## next bullet will actually fly — matching the direction used in fire_at_predicted_position().
var _blind_fire_target: Vector2 = Vector2.ZERO

## Issue #1336: Laser sight Line2D node (only created for SNIPER_RIFLE enemies).
var _laser_line: Line2D = null
## Issue #1336: Laser endpoint dot (PointLight2D for glow at hit point).
var _laser_dot: Sprite2D = null


func _ready() -> void:
	if enemy == null:
		enemy = get_parent() as CharacterBody2D
	# Issue #1336: Only create laser sight for sniper rifle enemies.
	# EnemySniperComponent is added to ALL enemies (line 422 of enemy.gd) but
	# the laser must only appear on snipers. Check weapon_type after enemy is set.
	if enemy != null and enemy.get("weapon_type") != null:
		# WeaponType.SNIPER_RIFLE == 7 (enum int value)
		if int(enemy.weapon_type) == 7:
			_create_laser_sight()


func _process(_delta: float) -> void:
	if _laser_line != null:
		_update_laser_sight()


# ============================================================================
# Issue #1163 — AI behaviour: standoff range + blind-fire through cover
# ============================================================================

## Process sniper rifle combat behaviour: maintain standoff distance and blind-fire through cover.
## Returns true if sniper handling was applied (caller should return early).
func process_combat(delta: float, can_see_player: bool, player: Node,
		last_known_pos: Vector2, prediction) -> bool:
	if player == null:
		return false

	var player_pos: Vector2 = (player as Node2D).global_position
	var distance_to_player: float = enemy.global_position.distance_to(player_pos)
	var direction_to_player: Vector2 = (player_pos - enemy.global_position).normalized()

	blind_fire_timer += delta

	if can_see_player:
		_blind_fire_target = Vector2.ZERO  # Issue #1336: clear blind-fire target when player visible
		if distance_to_player < MIN_DISTANCE:
			var retreat_dir := -direction_to_player
			retreat_dir = (enemy._apply_wall_avoidance(retreat_dir) as Vector2)
			enemy.velocity = retreat_dir * enemy.combat_move_speed
			_log("[#1163] Sniper: player too close (%.0f px), retreating" % distance_to_player)
		else:
			enemy.velocity = Vector2.ZERO

		enemy._aim_at_player()
		if enemy._detection_delay_elapsed and enemy._shoot_timer >= enemy.shoot_cooldown and enemy._can_shoot():
			enemy._shoot()
			enemy._shoot_timer = 0.0
			blind_fire_timer = 0.0
		return true

	# Player NOT visible: blind-fire at predicted position through cover.
	enemy.velocity = Vector2.ZERO

	var blind_target := last_known_pos
	if prediction != null and prediction.has_predictions:
		var predicted: Vector2 = prediction.get_best_position()
		if predicted != Vector2.ZERO:
			blind_target = predicted

	if blind_target == Vector2.ZERO:
		_blind_fire_target = Vector2.ZERO  # Issue #1336: no target
		enemy._transition_to_pursuing()
		return true

	_blind_fire_target = blind_target  # Issue #1336: track for laser direction
	_rotate_toward(blind_target, delta)

	if blind_fire_timer >= BLIND_FIRE_COOLDOWN and enemy._shoot_timer >= enemy.shoot_cooldown and enemy._can_shoot():
		fire_at_predicted_position(blind_target)
		blind_fire_timer = 0.0
	return true


## Handle sniper behaviour in PURSUING state: hold position and blind-fire when at safe range.
## Returns true if the sniper held position (caller should return early).
func process_pursuing(delta: float, can_see_player: bool, player: Node,
		last_known_pos: Vector2, prediction) -> bool:
	blind_fire_timer += delta

	# When player is visible and at safe range: shoot directly and let normal
	# PURSUING code transition to COMBAT (return false so enemy.gd continues).
	if can_see_player and player != null:
		_blind_fire_target = Vector2.ZERO  # Issue #1336: clear when player visible
		var dist := enemy.global_position.distance_to((player as Node2D).global_position)
		if dist >= MIN_DISTANCE:
			return false  # Fall through: normal pursuit will transition to COMBAT
		# Too close — retreat (fall through to reposition).
		return false

	var blind_pos := last_known_pos
	if prediction != null and prediction.has_predictions:
		var ph: Vector2 = prediction.get_best_position()
		if ph != Vector2.ZERO:
			blind_pos = ph
	if blind_pos == Vector2.ZERO:
		_blind_fire_target = Vector2.ZERO  # Issue #1336: no target
		return false
	if enemy.global_position.distance_to(blind_pos) < MIN_DISTANCE:
		_blind_fire_target = Vector2.ZERO  # Issue #1336: too close, will reposition
		return false  # Too close — fall through to normal pursuit to reposition

	_blind_fire_target = blind_pos  # Issue #1336: track for laser direction
	enemy.velocity = Vector2.ZERO
	_rotate_toward(blind_pos, delta)
	if blind_fire_timer >= BLIND_FIRE_COOLDOWN and enemy._shoot_timer >= enemy.shoot_cooldown and enemy._can_shoot():
		fire_at_predicted_position(blind_pos)
		blind_fire_timer = 0.0
	return true


## Fire sniper bullet at a predicted player position through cover walls.
## Uses the same projectile as normal shooting but bypasses the LOS requirement.
func fire_at_predicted_position(target_pos: Vector2) -> void:
	if enemy.bullet_scene == null: return
	# Issue #1334 Round 5: Don't shoot at a dead player
	var gm := enemy.get_node_or_null("/root/GameManager")
	if gm and not gm.player_alive: return
	var to_target := (target_pos - enemy.global_position).normalized()
	if to_target == Vector2.ZERO: return

	var enemy_model: Node = enemy._enemy_model
	if enemy_model: enemy_model.global_rotation = to_target.angle()
	enemy.rotation = to_target.angle()

	var spawn_pos: Vector2 = enemy._get_bullet_spawn_position(to_target)
	var spread := deg_to_rad(randf_range(-3.0, 3.0))
	var direction := to_target.rotated(spread)
	enemy._spawn_projectile(direction, spawn_pos)
	enemy._spawn_muzzle_flash(spawn_pos, direction)
	enemy._spawn_casing(direction, to_target)

	var audio: Node = enemy.get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play_asvk_shot"): audio.play_asvk_shot()

	var sp: Node = enemy.get_node_or_null("/root/SoundPropagation")
	var now_s := Time.get_ticks_msec() / 1000.0
	if sp and sp.has_method("emit_sound") and now_s - enemy._last_gunshot_propagation_time >= enemy.ENEMY_GUNSHOT_PROPAGATION_COOLDOWN:
		sp.emit_sound(0, enemy.global_position, 1, enemy, enemy.weapon_loudness)
		enemy._last_gunshot_propagation_time = now_s

	enemy._play_delayed_shell_sound()
	# [#1177] Trigger 4-step bolt-action cycle for blind-fire shots (same as direct shots)
	enemy._is_bolt_cycling = true
	enemy._bolt_cycle_timer = 0.0
	enemy._bolt_cycle_step = 1
	enemy._shoot_timer = 0.0
	enemy._current_ammo -= 1
	enemy._shot_count += 1
	enemy.ammo_changed.emit(enemy._current_ammo, enemy._reserve_ammo)
	_log("[#1163] Sniper blind-fire at predicted position %s, ammo=%d" % [target_pos, enemy._current_ammo])
	if enemy._current_ammo <= 0 and enemy._reserve_ammo > 0:
		enemy._start_reload()


func _rotate_toward(target_pos: Vector2, delta: float) -> void:
	var to_target := (target_pos - enemy.global_position).normalized()
	if to_target == Vector2.ZERO: return
	var enemy_model: Node = enemy._enemy_model
	if enemy_model:
		enemy_model.global_rotation = lerp_angle(enemy_model.global_rotation, to_target.angle(), enemy.rotation_speed * delta)
	enemy.rotation = lerp_angle(enemy.rotation, to_target.angle(), enemy.rotation_speed * delta)


# ============================================================================
# Issue #1171 — Hitscan shooting: avoids physics tunnelling at 10000px/s
# ============================================================================

## Issue #1334 Round 7: Robust alive check that works for both GDScript and C# targets.
## GDScript's get("IsAlive") returns null for non-[Export] C# properties, so we use
## multiple fallback strategies: GDScript method, C# property, GameManager.player_alive
## (for Player nodes), and collision_layer check (0 = dead, set by Player.OnDeath).
func _check_target_alive(node: Node2D) -> bool:
	if not is_instance_valid(node):
		return false
	# Strategy 1: GDScript method is_alive()
	if node.has_method("is_alive"):
		return node.call("is_alive")
	# Strategy 2: C# property via get() — may return null for non-exported properties
	var is_alive_val = node.get("IsAlive")
	if is_alive_val != null:
		return is_alive_val
	# Strategy 3: Check GameManager.player_alive (covers the Player specifically)
	var gm := enemy.get_node_or_null("/root/GameManager")
	if gm and not gm.player_alive:
		return false
	# Strategy 4: collision_layer == 0 means dead (Player.OnDeath sets CollisionLayer=0)
	if node is CharacterBody2D and node.collision_layer == 0:
		return false
	# Default: assume alive (unknown target type)
	return true


## [#1171] Hitscan shot — instant raycast avoids physics tunneling at 10000px/s.
func shoot_sniper_hitscan(direction: Vector2, spawn_pos: Vector2) -> void:
	# Issue #1334 Round 11: Guard against freed enemy node
	if not enemy.is_inside_tree(): return
	# Issue #1334 Round 5: Skip hitscan entirely if player is already dead.
	# Prevents crash from hitscan hitting dead player on same frame as death signal.
	var gm := enemy.get_node_or_null("/root/GameManager")
	if gm and not gm.player_alive: return
	var world_2d := enemy.get_world_2d()
	if world_2d == null: return
	var space_state := world_2d.direct_space_state
	if space_state == null: return
	var damage := 50.0; var end_pos := spawn_pos + direction * 5000.0; var bullet_end_point := end_pos
	var shooter_id := enemy.get_instance_id(); var walls_penetrated := 0; var current_pos := spawn_pos
	var exclude_rids := []; var damaged_ids: Dictionary = {}
	# Issue #1334 Round 8: Also get the player's RID so we can exclude it from raycasts
	# if it died between the player_alive check above and the raycast loop below.
	# When Player.OnDeath() sets CollisionLayer=0, the physics server may not process
	# the change until the next physics tick. Excluding the player's RID directly
	# prevents the raycast from hitting a dead player whose collision hasn't been
	# removed from the physics server yet (this can cause native segfaults).
	var player_node: Node2D = gm.player if gm else null
	var player_rid: RID = player_node.get_rid() if player_node and is_instance_valid(player_node) and player_node is CollisionObject2D else RID()
	# Issue #1334 Round 6: Collect hits during raycast loop, apply damage AFTER loop.
	# Calling TakeDamage() inside a direct_space_state query loop modifies physics state
	# (CollisionLayer=0 in Player.OnDeath), which is undefined behavior in Godot's physics
	# server and causes a native segfault crash. The safe pattern is: query first, damage later.
	var pending_hits: Array[Dictionary] = []
	for _i in range(50):
		if current_pos.distance_to(end_pos) < 1.0: break
		# Issue #1334 Round 8: Re-check player_alive each iteration. If another damage source
		# killed the player during this frame (e.g., rifle bullet body_entered callback fired
		# between _physics_process calls), the player's collision data may be in an inconsistent
		# state. Abort the raycast loop immediately to prevent native segfaults.
		if gm and not gm.player_alive:
			_log("[SniperHitscan] Aborting raycast loop — player died mid-frame")
			break
		# Build the exclude list, adding the dead player's RID if player died
		var char_exclude := exclude_rids.duplicate()
		if player_rid.is_valid() and gm and not gm.player_alive:
			char_exclude.append(player_rid)
		var wall_result := space_state.intersect_ray(PhysicsRayQueryParameters2D.create(current_pos, end_pos, 4, exclude_rids))
		var char_result := space_state.intersect_ray(PhysicsRayQueryParameters2D.create(current_pos, end_pos, 1, char_exclude))
		var wall_dist := INF if wall_result.is_empty() else current_pos.distance_to(wall_result["position"])
		var char_dist := INF if char_result.is_empty() else current_pos.distance_to(char_result["position"])
		if wall_dist == INF and char_dist == INF: break
		if char_dist <= wall_dist and not char_result.is_empty():
			var hit_node: Node2D = char_result["collider"]
			# Issue #1334: Verify collider is still valid (may have been freed mid-frame)
			if not is_instance_valid(hit_node): break
			var hit_id := hit_node.get_instance_id()
			if hit_id != shooter_id and not damaged_ids.has(hit_id):
				# Issue #1334 Round 7: Robust alive check using multiple fallback methods.
				# get("IsAlive") can return null for non-[Export] C# properties in GDScript,
				# causing the check to be silently skipped and damage applied to dead targets.
				var target_alive := _check_target_alive(hit_node)
				if target_alive:
					# Issue #1334 Round 6: Store hit for deferred damage — do NOT call
					# TakeDamage here, as it modifies physics state during an active query.
					pending_hits.append({"node": hit_node, "walls_penetrated": walls_penetrated})
					damaged_ids[hit_id] = true
			exclude_rids.append(char_result["rid"]); current_pos = char_result["position"] + direction * 5.0
		elif not wall_result.is_empty():
			var impact_mgr := enemy.get_node_or_null("/root/ImpactEffectsManager")
			if impact_mgr and impact_mgr.has_method("spawn_dust_effect"):
				impact_mgr.spawn_dust_effect(wall_result["position"], -direction, null)
			if walls_penetrated < 2:
				walls_penetrated += 1; exclude_rids.append(wall_result["rid"])
				current_pos = wall_result["position"] + direction * 5.0
			else: bullet_end_point = wall_result["position"]; break
	# Issue #1334 Round 6: Apply damage AFTER the raycast loop has fully completed.
	# This ensures no physics state modifications happen during active direct_space_state queries.
	for hit_info in pending_hits:
		var hit_node: Node2D = hit_info["node"]
		if not is_instance_valid(hit_node): continue
		# Re-check alive status — a prior hit in this batch may have killed the target
		if not _check_target_alive(hit_node): continue
		var hit_walls: int = hit_info["walls_penetrated"]
		if hit_node.has_method("on_hit_with_bullet_info"):
			hit_node.call("on_hit_with_bullet_info", direction, enemy.get("_caliber_data"), false, hit_walls > 0, damage)
		elif hit_node.has_method("TakeDamage"): hit_node.call("TakeDamage", damage)
		elif hit_node.has_method("take_damage"): hit_node.call("take_damage", damage)
		elif hit_node.has_method("on_hit"): hit_node.call("on_hit")
	_spawn_sniper_tracer(spawn_pos, bullet_end_point)

## Spawn a fading smoke tracer Line2D from muzzle to bullet endpoint.
func _spawn_sniper_tracer(from_pos: Vector2, end_pos: Vector2) -> void:
	var tracer := Line2D.new()
	tracer.name = "SniperEnemyTracer"; tracer.width = 4.0; tracer.default_color = Color(0.9, 0.85, 0.6, 0.7)
	tracer.begin_cap_mode = Line2D.LINE_CAP_ROUND; tracer.end_cap_mode = Line2D.LINE_CAP_ROUND
	tracer.top_level = true; tracer.position = Vector2.ZERO; tracer.z_index = 10
	var wc := Curve.new()
	wc.add_point(Vector2(0.0, 1.0)); wc.add_point(Vector2(0.3, 0.8)); wc.add_point(Vector2(1.0, 0.3))
	tracer.width_curve = wc
	var grad := Gradient.new()
	grad.set_color(0, Color(0.9, 0.9, 0.85, 0.8)); grad.add_point(0.5, Color(0.7, 0.7, 0.65, 0.5))
	grad.set_color(grad.get_point_count() - 1, Color(0.5, 0.5, 0.5, 0.2))
	tracer.gradient = grad; tracer.add_point(from_pos); tracer.add_point(end_pos)
	# Issue #1334 Round 11: Guard against null current_scene during scene transitions
	var current_scene := get_tree().current_scene
	if current_scene == null: tracer.queue_free(); return
	current_scene.add_child(tracer); _fade_sniper_tracer(tracer)

## Async fade-out for the sniper tracer.
func _fade_sniper_tracer(tracer: Line2D) -> void:
	var elapsed := 0.0; var initial_width := tracer.width
	while elapsed < 2.0 and is_instance_valid(tracer):
		# Issue #1334 Round 11: Guard coroutine against freed enemy/scene after await
		if not is_inside_tree(): break
		elapsed += get_process_delta_time(); var p := elapsed / 2.0; var a := lerpf(0.7, 0.0, p)
		tracer.default_color = Color(0.8, 0.8, 0.8, a); tracer.width = initial_width + p * 3.0
		var grad := Gradient.new()
		grad.set_color(0, Color(0.9, 0.9, 0.85, a)); grad.add_point(0.5, Color(0.7, 0.7, 0.65, a * 0.6))
		grad.set_color(grad.get_point_count() - 1, Color(0.5, 0.5, 0.5, a * 0.3))
		tracer.gradient = grad; await get_tree().process_frame
	if is_instance_valid(tracer): tracer.queue_free()


# ============================================================================
# Issue #1336 — Laser sight: always points where the next shot will travel
# ============================================================================

## Create the laser sight Line2D. Only called for SNIPER_RIFLE enemies.
func _create_laser_sight() -> void:
	_laser_line = Line2D.new()
	_laser_line.name = "SniperLaserSight"
	_laser_line.width = 1.5
	_laser_line.default_color = Color(1.0, 0.0, 0.0, 0.45)
	_laser_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_laser_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_laser_line.top_level = true
	_laser_line.z_index = 9  # Below tracers (z=10) but above most sprites
	_laser_line.add_point(Vector2.ZERO)
	_laser_line.add_point(Vector2.ZERO)
	# Add as child of current scene so it renders in world space
	call_deferred("_add_laser_to_scene")


## Deferred add to scene tree — ensures current_scene is available.
func _add_laser_to_scene() -> void:
	if _laser_line == null: return
	if not is_inside_tree(): _laser_line.queue_free(); _laser_line = null; return
	var current_scene := get_tree().current_scene
	if current_scene == null: _laser_line.queue_free(); _laser_line = null; return
	current_scene.add_child(_laser_line)


## Compute the direction the laser should point.
## This MUST match the exact direction the next bullet will travel.
##   - Direct fire: same as _get_weapon_forward_direction() which returns
##     (player.global_position - enemy.global_position).normalized() when player visible.
##   - Blind fire: (blind_target - enemy.global_position).normalized() — the exact
##     same vector used by fire_at_predicted_position() for to_target.
##   - No target: use the enemy model's current rotation (idle/patrol).
func _get_laser_direction() -> Vector2:
	# Blind-fire mode: use exact blind-fire target direction
	if _blind_fire_target != Vector2.ZERO:
		return (_blind_fire_target - enemy.global_position).normalized()
	# Direct-fire mode: use the same logic as _get_weapon_forward_direction()
	# which is what _execute_shoot() uses for the bullet direction.
	var player: Node2D = enemy.get("_player") as Node2D
	var can_see: bool = enemy.get("_can_see_player") if enemy.get("_can_see_player") != null else false
	if player and is_instance_valid(player) and can_see:
		return (player.global_position - enemy.global_position).normalized()
	# Check for current target (companion, aggression target)
	var current_target: Node2D = enemy.get("_current_target") as Node2D
	if current_target and is_instance_valid(current_target):
		var can_see_companion: bool = enemy.get("_can_see_companion") if enemy.get("_can_see_companion") != null else false
		if can_see_companion:
			return (current_target.global_position - enemy.global_position).normalized()
	# Fallback: weapon sprite direction or model rotation
	var weapon_sprite: Node2D = enemy.get("_weapon_sprite") as Node2D
	if weapon_sprite and is_instance_valid(weapon_sprite):
		return weapon_sprite.global_transform.x.normalized()
	var enemy_model: Node2D = enemy.get("_enemy_model") as Node2D
	if enemy_model and is_instance_valid(enemy_model):
		return Vector2.from_angle(enemy_model.global_rotation)
	return Vector2.RIGHT


## Compute muzzle position using the laser direction (not the lerped sprite transform).
## This avoids Bug C from previous attempts: muzzle offset in lerped direction while
## laser points in target direction, creating a diagonal mismatch.
func _get_laser_muzzle_pos(weapon_forward: Vector2) -> Vector2:
	var weapon_sprite: Node2D = enemy.get("_weapon_sprite") as Node2D
	if weapon_sprite and is_instance_valid(weapon_sprite):
		var scale_val: float = enemy.enemy_model_scale if enemy.get("enemy_model_scale") != null else 1.3
		return weapon_sprite.global_position + weapon_forward * (MUZZLE_LOCAL_OFFSET * scale_val)
	return enemy.global_position + weapon_forward * enemy.bullet_spawn_offset


## Update laser sight position and direction every frame.
func _update_laser_sight() -> void:
	if not is_instance_valid(enemy) or not enemy.is_inside_tree():
		return
	# Hide laser when enemy is dead
	if enemy.has_method("is_alive") and not enemy.is_alive():
		_laser_line.visible = false
		return
	# Hide laser during reload
	var is_reloading: bool = enemy.get("_is_reloading") if enemy.get("_is_reloading") != null else false
	if is_reloading:
		_laser_line.visible = false
		return
	_laser_line.visible = true

	var weapon_forward := _get_laser_direction()
	var muzzle_pos := _get_laser_muzzle_pos(weapon_forward)
	var laser_end := muzzle_pos + weapon_forward * LASER_MAX_RANGE

	# Raycast to find the first wall the laser hits (layer 4 = walls/obstacles)
	var world_2d := enemy.get_world_2d()
	if world_2d:
		var space_state := world_2d.direct_space_state
		if space_state:
			var query := PhysicsRayQueryParameters2D.create(muzzle_pos, laser_end, 4)
			var result := space_state.intersect_ray(query)
			if not result.is_empty():
				laser_end = result["position"]

	_laser_line.set_point_position(0, muzzle_pos)
	_laser_line.set_point_position(1, laser_end)


## Clean up laser sight when enemy dies or component is removed.
func _exit_tree() -> void:
	if _laser_line and is_instance_valid(_laser_line):
		_laser_line.queue_free()
		_laser_line = null


# ============================================================================
# Helpers
# ============================================================================

## Forward message to enemy file logger if available.
func _log(message: String) -> void:
	if log_to_file_fn.is_valid():
		log_to_file_fn.call(message)
