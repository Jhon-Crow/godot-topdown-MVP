extends Node
## Sniper rifle enemy component (Issues #1163, #1171, #1336).
## Handles three responsibilities:
##   1. AI behaviour: kiting (standoff range), retreat when player closes in,
##      and blind-fire through cover at last-known / predicted player positions.
##   2. Hitscan shooting: instant raycast avoids physics tunnelling at 10000px/s.
##   3. Laser sight: red aiming laser matching the player's M16 assault rifle (Issue #1336).
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

# ============================================================================
# Configuration — Laser sight (Issue #1336)
# ============================================================================

## Laser sight color: red with transparency, same as M16 assault rifle.
const LASER_COLOR: Color = Color(1.0, 0.0, 0.0, 0.5)
## Laser sight line width in pixels.
const LASER_WIDTH: float = 2.0
## Maximum raycast distance for the laser (px).
const LASER_MAX_LENGTH: float = 10000.0

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

## [#1336] Laser sight Line2D node (added to the scene tree as top-level).
var _laser_sight: Line2D = null
## [#1336] Glow layers for the laser sight (additive-blended Line2D nodes).
var _laser_glow_layers: Array[Line2D] = []
## [#1336] Endpoint glow PointLight2D.
var _laser_endpoint_light: PointLight2D = null


func _ready() -> void:
	if enemy == null:
		enemy = get_parent() as CharacterBody2D
	_create_laser_sight()


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
		enemy._transition_to_pursuing()
		return true

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
		return false
	if enemy.global_position.distance_to(blind_pos) < MIN_DISTANCE:
		return false  # Too close — fall through to normal pursuit to reposition

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

## [#1171] Hitscan shot — instant raycast avoids physics tunneling at 10000px/s.
func shoot_sniper_hitscan(direction: Vector2, spawn_pos: Vector2) -> void:
	var world_2d := enemy.get_world_2d()
	if world_2d == null: return
	var space_state := world_2d.direct_space_state
	if space_state == null: return
	var damage := 50.0; var end_pos := spawn_pos + direction * 5000.0; var bullet_end_point := end_pos
	var shooter_id := enemy.get_instance_id(); var walls_penetrated := 0; var current_pos := spawn_pos
	var exclude_rids := []; var damaged_ids: Dictionary = {}
	for _i in range(50):
		if current_pos.distance_to(end_pos) < 1.0: break
		var wall_result := space_state.intersect_ray(PhysicsRayQueryParameters2D.create(current_pos, end_pos, 4, exclude_rids))
		var char_result := space_state.intersect_ray(PhysicsRayQueryParameters2D.create(current_pos, end_pos, 1, exclude_rids))
		var wall_dist := INF if wall_result.is_empty() else current_pos.distance_to(wall_result["position"])
		var char_dist := INF if char_result.is_empty() else current_pos.distance_to(char_result["position"])
		if wall_dist == INF and char_dist == INF: break
		if char_dist <= wall_dist and not char_result.is_empty():
			var hit_node: Node2D = char_result["collider"]; var hit_id := hit_node.get_instance_id()
			if hit_id != shooter_id and not damaged_ids.has(hit_id):
				if (not hit_node.has_method("is_alive")) or hit_node.call("is_alive"):
					if hit_node.has_method("on_hit_with_bullet_info"):
						hit_node.call("on_hit_with_bullet_info", direction, enemy.get("_caliber_data"), false, walls_penetrated > 0, damage)
					elif hit_node.has_method("TakeDamage"): hit_node.call("TakeDamage", damage)
					elif hit_node.has_method("take_damage"): hit_node.call("take_damage", damage)
					elif hit_node.has_method("on_hit"): hit_node.call("on_hit")
					damaged_ids[hit_id] = true
					if log_to_file_fn.is_valid(): log_to_file_fn.call("[SniperHitscan] Hit %s damage=%.0f" % [hit_node.name, damage])
			exclude_rids.append(char_result["rid"]); current_pos = char_result["position"] + direction * 5.0
		elif not wall_result.is_empty():
			var impact_mgr := enemy.get_node_or_null("/root/ImpactEffectsManager")
			if impact_mgr and impact_mgr.has_method("spawn_dust_effect"):
				impact_mgr.spawn_dust_effect(wall_result["position"], -direction, null)
			if walls_penetrated < 2:
				walls_penetrated += 1; exclude_rids.append(wall_result["rid"])
				current_pos = wall_result["position"] + direction * 5.0
			else: bullet_end_point = wall_result["position"]; break
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
	get_tree().current_scene.add_child(tracer); _fade_sniper_tracer(tracer)

## Async fade-out for the sniper tracer.
func _fade_sniper_tracer(tracer: Line2D) -> void:
	var elapsed := 0.0; var initial_width := tracer.width
	while elapsed < 2.0 and is_instance_valid(tracer):
		elapsed += get_process_delta_time(); var p := elapsed / 2.0; var a := lerpf(0.7, 0.0, p)
		tracer.default_color = Color(0.8, 0.8, 0.8, a); tracer.width = initial_width + p * 3.0
		var grad := Gradient.new()
		grad.set_color(0, Color(0.9, 0.9, 0.85, a)); grad.add_point(0.5, Color(0.7, 0.7, 0.65, a * 0.6))
		grad.set_color(grad.get_point_count() - 1, Color(0.5, 0.5, 0.5, a * 0.3))
		tracer.gradient = grad; await get_tree().process_frame
	if is_instance_valid(tracer): tracer.queue_free()


# ============================================================================
# Issue #1336 — Laser sight (same red laser as player M16)
# ============================================================================

## Create the laser sight Line2D with glow layers (called once from _ready).
func _create_laser_sight() -> void:
	_laser_sight = Line2D.new()
	_laser_sight.name = "SniperEnemyLaser"
	_laser_sight.width = LASER_WIDTH
	_laser_sight.default_color = LASER_COLOR
	_laser_sight.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_laser_sight.end_cap_mode = Line2D.LINE_CAP_ROUND
	_laser_sight.top_level = true
	_laser_sight.z_index = 5
	_laser_sight.add_point(Vector2.ZERO)
	_laser_sight.add_point(Vector2.ZERO)
	add_child(_laser_sight)

	# Glow layers: additive-blended wider lines for volumetric look (like LaserGlowEffect.cs).
	var glow_configs := [
		{"width": 6.0, "alpha": 0.15},
		{"width": 14.0, "alpha": 0.05},
		{"width": 28.0, "alpha": 0.02},
	]
	for cfg in glow_configs:
		var glow := Line2D.new()
		glow.name = "LaserGlow"
		glow.width = cfg["width"]
		glow.default_color = Color(LASER_COLOR.r, LASER_COLOR.g, LASER_COLOR.b, cfg["alpha"])
		glow.begin_cap_mode = Line2D.LINE_CAP_ROUND
		glow.end_cap_mode = Line2D.LINE_CAP_ROUND
		glow.top_level = true
		glow.z_index = 4
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		glow.material = mat
		glow.add_point(Vector2.ZERO)
		glow.add_point(Vector2.ZERO)
		add_child(glow)
		_laser_glow_layers.append(glow)

	# Endpoint glow: small PointLight2D at the laser impact point.
	_laser_endpoint_light = PointLight2D.new()
	_laser_endpoint_light.name = "LaserEndpointGlow"
	_laser_endpoint_light.color = Color(LASER_COLOR.r, LASER_COLOR.g, LASER_COLOR.b, 1.0)
	_laser_endpoint_light.energy = 0.4
	_laser_endpoint_light.texture_scale = 0.15
	_laser_endpoint_light.blend_mode = PointLight2D.BLEND_MODE_ADD
	# Create a simple radial gradient texture procedurally.
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var center := Vector2(32, 32)
	for y in range(64):
		for x in range(64):
			var dist := Vector2(x, y).distance_to(center) / 32.0
			var a := clampf(1.0 - dist, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var tex := ImageTexture.create_from_image(img)
	_laser_endpoint_light.texture = tex
	add_child(_laser_endpoint_light)


## Update laser sight position and endpoint every frame.
## Called from enemy.gd _physics_process when weapon_type == SNIPER_RIFLE.
func update_laser_sight() -> void:
	if _laser_sight == null or enemy == null:
		return
	if not enemy.get("_is_alive"):
		_set_laser_visible(false)
		return

	# Only show laser when the enemy is a sniper rifle type.
	if enemy.weapon_type != enemy.WeaponType.SNIPER_RIFLE:
		_set_laser_visible(false)
		return

	_set_laser_visible(true)

	# [#1336] Use the same direction and spawn position as bullets (_execute_shoot)
	# so the laser accurately represents where the sniper will actually shoot.
	# _get_weapon_forward_direction() returns direct-to-player when _can_see_player
	# is true, which matches the bullet flight direction.
	var direction: Vector2 = enemy._get_weapon_forward_direction()
	var start_pos: Vector2 = enemy._get_bullet_spawn_position(direction)

	# Raycast to find the first wall or character hit.
	# Collision mask 5 = walls (layer 3, value 4) + characters (layer 1, value 1).
	# This stops the laser at the player body instead of passing through.
	var end_pos := start_pos + direction * LASER_MAX_LENGTH
	var world_2d := enemy.get_world_2d()
	if world_2d == null:
		return
	var space_state := world_2d.direct_space_state
	if space_state == null:
		return

	var query := PhysicsRayQueryParameters2D.create(start_pos, end_pos, 5)
	query.exclude = [enemy.get_rid()]  # Exclude own collider
	var result := space_state.intersect_ray(query)
	var laser_end := end_pos
	if not result.is_empty():
		# Extend 4px into the surface for visual penetration (like M16 laser).
		laser_end = result["position"] + direction * 4.0

	# Update Line2D points (top_level = true, so use global coordinates).
	_laser_sight.set_point_position(0, start_pos)
	_laser_sight.set_point_position(1, laser_end)

	for glow in _laser_glow_layers:
		glow.set_point_position(0, start_pos)
		glow.set_point_position(1, laser_end)

	if _laser_endpoint_light:
		_laser_endpoint_light.global_position = laser_end


## Hide the laser sight (e.g. on death).
func hide_laser() -> void:
	_set_laser_visible(false)


## Toggle visibility of all laser components.
func _set_laser_visible(visible: bool) -> void:
	if _laser_sight:
		_laser_sight.visible = visible
	for glow in _laser_glow_layers:
		glow.visible = visible
	if _laser_endpoint_light:
		_laser_endpoint_light.visible = visible


# ============================================================================
# Helpers
# ============================================================================

## Forward message to enemy file logger if available.
func _log(message: String) -> void:
	if log_to_file_fn.is_valid():
		log_to_file_fn.call(message)
