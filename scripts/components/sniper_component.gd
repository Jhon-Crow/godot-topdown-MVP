class_name SniperComponent
extends RefCounted
## Sniper-specific logic for enemy AI (Issue #581, fixes in Issue #665).
## Handles hitscan shooting, spread calculation, laser sight, and smoke tracers.
## Extracted from enemy.gd to keep file size manageable.

## Hitscan range for sniper shots (pixels).
var hitscan_range: float = 5000.0
## Hitscan damage per shot.
var hitscan_damage: float = 50.0
## Max wall penetrations for sniper hitscan.
var max_wall_penetrations: int = 2
## Bolt cycle duration in seconds.
const BOLT_CYCLE_TIME: float = 2.0


## Calculate sniper spread based on distance and wall penetrations.
## Rules from issue #581:
## - Through 1 wall: 10 degrees (5 each side)
## - Through 2 walls: 15 degrees
## - Direct LOS at 2+ viewports: 0 degrees (perfect)
## - Direct LOS at 1 viewport: 3 degrees
## - Direct LOS under 1 viewport: 5 degrees
static func calculate_spread(enemy: Node2D, target_pos: Vector2, can_see_player: bool, memory: RefCounted) -> float:
	if not is_instance_valid(enemy):
		return 15.0

	# Use memory position if player not visible
	var actual_target := target_pos
	if not can_see_player and memory and memory.has_method("has_target") and memory.has_target():
		actual_target = memory.suspected_position

	var distance := enemy.global_position.distance_to(actual_target)
	var viewport_size := enemy.get_viewport_rect().size.length()

	# Count walls between sniper and target
	var walls_count := count_walls(enemy, actual_target)

	if walls_count >= 2:
		return 15.0  # Through 2+ walls: 15 degrees spread
	elif walls_count == 1:
		return 10.0  # Through 1 wall: 10 degrees spread
	else:
		# Direct line of sight - spread based on distance
		if distance >= viewport_size * 2.0:
			return 0.0  # 2+ viewports away: perfect accuracy
		elif distance >= viewport_size:
			return 3.0  # 1 viewport: 3 degrees
		else:
			return 5.0  # Under 1 viewport: 5 degrees (close range)


## Count the number of walls between the enemy and a target position.
static func count_walls(enemy: Node2D, target_pos: Vector2) -> int:
	var space := enemy.get_world_2d().direct_space_state
	var current_pos := enemy.global_position
	var direction := (target_pos - current_pos).normalized()
	var walls := 0
	var exclude_rids: Array[RID] = []

	for _i in range(10):  # Safety limit
		var query := PhysicsRayQueryParameters2D.create(current_pos, target_pos, 4)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		query.exclude = exclude_rids
		var result := space.intersect_ray(query)

		if not result:
			break

		var collider := result["collider"]
		if collider is StaticBody2D:
			walls += 1
			exclude_rids.append(result["rid"])
			current_pos = result["position"] + direction * 5.0
		else:
			break

		if walls >= 2:
			break

	return walls


## Perform sniper hitscan shot - sequential raycasts with wall penetration.
## @param extra_exclude_rids: Additional RIDs to exclude (e.g., enemy's HitArea).
## Issue #665: Delivers damage via on_hit_with_bullet_info for correct damage through
## HitArea -> Player chain. Skips friendly enemy CharacterBody2D hits (only damages
## player and player HitArea). Logs all results for diagnostics.
static func perform_hitscan(enemy: Node2D, direction: Vector2, spawn_pos: Vector2,
		hitscan_range_val: float, damage: float, max_penetrations: int,
		extra_exclude_rids: Array[RID] = []) -> Vector2:
	var space := enemy.get_world_2d().direct_space_state
	var walls_penetrated := 0
	var exclude_rids: Array[RID] = [enemy.get_rid()]  # Exclude self (CharacterBody2D)
	for rid in extra_exclude_rids:
		exclude_rids.append(rid)
	var damaged_ids: Dictionary = {}
	var hit_player := false

	# Mask: Layer 1 (player=1) + Layer 3 (walls=4). Skip layer 2 (enemies) — snipers
	# shoot through friendlies. We detect player CharacterBody2D (layer 1) and walls
	# (layer 3=StaticBody2D). Player HitArea is also on layer 1 so it's detected too.
	var combined_mask := 4 + 1

	# Issue #665 fix: Check if muzzle (spawn_pos) is inside or behind a wall relative
	# to the enemy center. If so, start the hitscan from the enemy center and
	# pre-exclude that wall to avoid the bullet getting stuck in adjacent walls.
	var actual_start := spawn_pos
	var muzzle_check := PhysicsRayQueryParameters2D.create(enemy.global_position, spawn_pos, 4)
	muzzle_check.collide_with_bodies = true
	muzzle_check.collide_with_areas = false
	muzzle_check.exclude = exclude_rids
	var muzzle_result := space.intersect_ray(muzzle_check)
	if muzzle_result:
		actual_start = enemy.global_position
		exclude_rids.append(muzzle_result["rid"])

	var end_pos := actual_start + direction * hitscan_range_val
	var bullet_end := end_pos
	var current_pos := actual_start
	var fl: Node = enemy.get_node_or_null("/root/FileLogger")

	for _i in range(50):  # Safety limit
		var query := PhysicsRayQueryParameters2D.create(current_pos, end_pos, combined_mask)
		query.collide_with_areas = true
		query.collide_with_bodies = true
		query.hit_from_inside = false
		query.exclude = exclude_rids

		var result := space.intersect_ray(query)
		if not result:
			bullet_end = end_pos
			break

		var hit_pos: Vector2 = result["position"]
		var collider: Object = result["collider"]

		# Wall hit
		if collider is StaticBody2D:
			var impact_mgr: Node = enemy.get_node_or_null("/root/ImpactEffectsManager")
			if impact_mgr and impact_mgr.has_method("spawn_dust_effect"):
				impact_mgr.spawn_dust_effect(hit_pos, -direction.normalized())
			if walls_penetrated < max_penetrations:
				walls_penetrated += 1
				exclude_rids.append(result["rid"])
				current_pos = hit_pos + direction * 5.0
				continue
			else:
				bullet_end = hit_pos
				break

		# Character/area hit — deliver damage to player targets
		var instance_id := collider.get_instance_id()
		if instance_id in damaged_ids:
			exclude_rids.append(result["rid"])
			current_pos = hit_pos + direction * 5.0
			continue
		damaged_ids[instance_id] = true
		# Determine damage target: use parent if collider is a HitArea (Area2D forwarding)
		var target: Node = collider
		if collider is Area2D and collider.get_parent():
			target = collider.get_parent()
		# Log the hit
		if fl and fl.has_method("log_enemy"):
			fl.log_enemy(enemy.name, "HITSCAN HIT: %s (via %s) at %s (dmg=%.0f)" % [target.name, collider.name, str(hit_pos), damage])
		# Deliver damage using the most specific method available on target
		if target.has_method("on_hit_with_bullet_info"):
			target.on_hit_with_bullet_info(-direction.normalized(), null, false, false, damage)
		elif target.has_method("on_hit_with_info"):
			target.on_hit_with_info(-direction.normalized(), null)
		elif target.has_method("take_damage"):
			target.take_damage(damage)
		elif target.has_method("TakeDamage"):
			target.TakeDamage(damage)
		elif target.has_method("on_hit"):
			target.on_hit()
		hit_player = true
		exclude_rids.append(result["rid"])
		current_pos = hit_pos + direction * 5.0

	# Log result
	if fl and fl.has_method("log_enemy"):
		if not hit_player:
			var dist := actual_start.distance_to(bullet_end)
			fl.log_enemy(enemy.name, "HITSCAN MISS: walls=%d, range=%.0f, start=%s, end=%s" % [walls_penetrated, dist, str(actual_start), str(bullet_end)])
		else:
			fl.log_enemy(enemy.name, "HITSCAN DONE: walls=%d, hit_player=true" % walls_penetrated)

	return bullet_end


## Spawn a smoke tracer line from start to end position.
static func spawn_tracer(scene_tree: SceneTree, start_pos: Vector2, end_pos: Vector2) -> void:
	var tracer := Line2D.new()
	tracer.name = "SniperTracer"
	tracer.width = 8.0
	tracer.z_index = 90
	tracer.z_as_relative = false  # Use absolute z_index to render above game elements
	tracer.top_level = true

	var width_curve := Curve.new()
	width_curve.add_point(Vector2(0.0, 1.0))
	width_curve.add_point(Vector2(0.3, 0.8))
	width_curve.add_point(Vector2(1.0, 0.3))
	tracer.width_curve = width_curve

	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 0.8, 1.0))  # Bright start
	gradient.add_point(0.5, Color(0.8, 0.8, 0.7, 0.7))  # Mid fade
	gradient.set_color(gradient.get_point_count() - 1, Color(0.6, 0.6, 0.55, 0.3))  # Tail
	tracer.gradient = gradient

	# Unshaded material for visibility in dark mode
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	tracer.material = mat

	tracer.add_point(start_pos)
	tracer.add_point(end_pos)

	if scene_tree.current_scene == null:
		tracer.queue_free()
		return
	scene_tree.current_scene.add_child(tracer)

	# Fade out and remove
	var tween := scene_tree.create_tween()
	tween.tween_property(tracer, "modulate:a", 0.0, 2.0)
	tween.tween_callback(tracer.queue_free)


## Create a red laser sight Line2D node for sniper enemy.
static func create_laser() -> Line2D:
	var laser := Line2D.new()
	laser.name = "SniperLaser"
	laser.width = 4.0
	laser.default_color = Color(1.0, 0.0, 0.0, 0.9)  # Bright red laser, high alpha
	laser.begin_cap_mode = Line2D.LINE_CAP_ROUND
	laser.end_cap_mode = Line2D.LINE_CAP_ROUND
	laser.points = PackedVector2Array([Vector2.ZERO, Vector2(500, 0)])
	laser.z_index = 100  # Above all game elements for visibility
	laser.z_as_relative = false  # Use absolute z_index to render above everything
	laser.top_level = true  # Use global coordinates to avoid parent rotation double-transform
	# Make unshaded for visibility in dark mode
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	laser.material = mat
	return laser


## Update sniper laser sight position and direction (global coordinates since top_level=true).
## @param extra_exclude_rids: Additional RIDs to exclude (e.g., enemy's HitArea).
static func update_laser(laser: Line2D, enemy: Node2D, weapon_forward: Vector2,
		muzzle_offset: Vector2, hitscan_range_val: float,
		extra_exclude_rids: Array[RID] = []) -> void:
	if laser == null:
		return

	var space := enemy.get_world_2d().direct_space_state
	var start := enemy.global_position + muzzle_offset
	var end_pos := start + weapon_forward * hitscan_range_val
	# Mask: layer 1 (player=1) + layer 2 (enemies=2) + layer 3 (walls=4)
	var exclude: Array[RID] = [enemy.get_rid()]
	for rid in extra_exclude_rids:
		exclude.append(rid)
	var query := PhysicsRayQueryParameters2D.create(start, end_pos, 4 + 2 + 1)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = exclude
	var result := space.intersect_ray(query)

	var laser_end: Vector2
	if result:
		laser_end = result["position"]
	else:
		laser_end = end_pos

	laser.points = PackedVector2Array([start, laser_end])


## Update the enemy's sniper laser sight (handles visibility, direction, and HitArea exclusion).
static func update_enemy_laser(enemy: Node2D, laser: Line2D, is_alive: bool,
		can_see_player: bool, hit_area: Area2D, hitscan_range_val: float) -> void:
	if laser == null or not is_alive:
		if laser: laser.visible = false
		return
	laser.visible = true
	var wf := enemy.call("_get_weapon_forward_direction") if can_see_player else Vector2.from_angle(enemy.rotation)
	var extra_rids: Array[RID] = []
	if hit_area: extra_rids.append(hit_area.get_rid())
	var spawn_pos: Vector2 = enemy.call("_get_bullet_spawn_position", wf)
	update_laser(laser, enemy, wf, spawn_pos - enemy.global_position, hitscan_range_val, extra_rids)


## Perform sniper hitscan shot with tracer and screen shake.
static func shoot_hitscan(enemy: Node2D, direction: Vector2, spawn_pos: Vector2,
		hit_area: Area2D, hitscan_range_val: float, damage: float,
		max_penetrations: int, player: Node2D) -> void:
	var extra_rids: Array[RID] = []
	if hit_area: extra_rids.append(hit_area.get_rid())
	var bullet_end := perform_hitscan(enemy, direction, spawn_pos, hitscan_range_val, damage, max_penetrations, extra_rids)
	spawn_tracer(enemy.get_tree(), spawn_pos, bullet_end)
	var shake_mgr: Node = enemy.get_node_or_null("/root/ScreenShakeManager")
	if shake_mgr and shake_mgr.has_method("shake") and player and enemy.global_position.distance_to(player.global_position) < 1000.0:
		shake_mgr.shake(5.0)


## Sniper retreat cooldown time in seconds.
const RETREAT_COOLDOWN_TIME: float = 3.0


## Smooth rotation toward target position for sniper enemies.
static func _rotate_toward(enemy: Node2D, target_pos: Vector2) -> void:
	var dir_to_target := (target_pos - enemy.global_position).normalized()
	var target_angle := dir_to_target.angle()
	var angle_diff := wrapf(target_angle - enemy.rotation, -PI, PI)
	var dt := enemy.get_physics_process_delta_time()
	if abs(angle_diff) <= enemy.rotation_speed * dt: enemy.rotation = target_angle
	elif angle_diff > 0: enemy.rotation += enemy.rotation_speed * dt
	else: enemy.rotation -= enemy.rotation_speed * dt
	if enemy._enemy_model: enemy._target_model_rotation = target_angle
