class_name SniperComponent
extends RefCounted
## Sniper-specific logic for enemy AI (Issue #581).
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
static func perform_hitscan(enemy: Node2D, direction: Vector2, spawn_pos: Vector2,
		hitscan_range_val: float, damage: float, max_penetrations: int) -> Vector2:
	var space := enemy.get_world_2d().direct_space_state
	var end_pos := spawn_pos + direction * hitscan_range_val
	var walls_penetrated := 0
	var bullet_end := end_pos
	var current_pos := spawn_pos
	var exclude_rids: Array[RID] = []
	var damaged_ids: Dictionary = {}

	# Combined mask: Layer 2 (enemies) + Layer 4 (walls)
	var combined_mask := 4 + 2

	for _i in range(50):  # Safety limit
		var query := PhysicsRayQueryParameters2D.create(current_pos, end_pos, combined_mask)
		query.collide_with_areas = true
		query.collide_with_bodies = true
		query.hit_from_inside = true
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

		# Enemy/player hit
		var instance_id := collider.get_instance_id()
		if instance_id not in damaged_ids:
			damaged_ids[instance_id] = true
			if collider.has_method("take_damage"):
				collider.take_damage(damage)
			elif collider.get_parent() and collider.get_parent().has_method("take_damage"):
				collider.get_parent().take_damage(damage)

		exclude_rids.append(result["rid"])
		current_pos = hit_pos + direction * 5.0

	return bullet_end


## Spawn a smoke tracer line from start to end position.
static func spawn_tracer(scene_tree: SceneTree, start_pos: Vector2, end_pos: Vector2) -> void:
	var tracer := Line2D.new()
	tracer.name = "SniperTracer"
	tracer.width = 5.0
	tracer.z_index = 10
	tracer.top_level = true

	var width_curve := Curve.new()
	width_curve.add_point(Vector2(0.0, 1.0))
	width_curve.add_point(Vector2(0.3, 0.8))
	width_curve.add_point(Vector2(1.0, 0.3))
	tracer.width_curve = width_curve

	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.9, 0.9, 0.85, 0.8))
	gradient.add_point(0.5, Color(0.7, 0.7, 0.65, 0.5))
	gradient.set_color(gradient.get_point_count() - 1, Color(0.5, 0.5, 0.5, 0.2))
	tracer.gradient = gradient

	tracer.add_point(start_pos)
	tracer.add_point(end_pos)

	scene_tree.current_scene.add_child(tracer)

	# Fade out and remove
	var tween := scene_tree.create_tween()
	tween.tween_property(tracer, "modulate:a", 0.0, 2.0)
	tween.tween_callback(tracer.queue_free)


## Create a red laser sight Line2D node for sniper enemy.
static func create_laser() -> Line2D:
	var laser := Line2D.new()
	laser.name = "SniperLaser"
	laser.width = 3.0
	laser.default_color = Color(1.0, 0.0, 0.0, 0.7)  # Bright red laser
	laser.begin_cap_mode = Line2D.LINE_CAP_ROUND
	laser.end_cap_mode = Line2D.LINE_CAP_ROUND
	laser.points = PackedVector2Array([Vector2.ZERO, Vector2(500, 0)])
	laser.z_index = 100  # Above all game elements for visibility
	laser.top_level = true  # Use global coordinates to avoid parent rotation double-transform
	# Make unshaded for visibility in dark mode
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	laser.material = mat
	return laser


## Update sniper laser sight position and direction (global coordinates since top_level=true).
static func update_laser(laser: Line2D, enemy: Node2D, weapon_forward: Vector2,
		muzzle_offset: Vector2, hitscan_range_val: float) -> void:
	if laser == null:
		return

	var space := enemy.get_world_2d().direct_space_state
	var start := enemy.global_position + muzzle_offset
	var end_pos := start + weapon_forward * hitscan_range_val
	var query := PhysicsRayQueryParameters2D.create(start, end_pos, 4)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result := space.intersect_ray(query)

	var laser_end: Vector2
	if result:
		laser_end = result["position"]
	else:
		laser_end = end_pos

	laser.points = PackedVector2Array([start, laser_end])


## NOTE: process_combat_state and process_in_cover_state were inlined into enemy.gd
## to avoid GDScript 4.x static function typed parameter dispatch issues (Issue #581 round 5).
## Utility functions (count_walls, calculate_spread, perform_hitscan, etc.) remain here
## since they only access Node2D-level properties.

## Spawn a bullet casing with ejection physics.
## Extracted from enemy.gd to reduce file size.
static func spawn_casing(scene_tree: SceneTree, casing_scene: PackedScene, spawn_pos: Vector2,
		weapon_forward: Vector2, caliber_data: Resource) -> void:
	if casing_scene == null:
		return
	var casing: RigidBody2D = casing_scene.instantiate()
	casing.global_position = spawn_pos
	var weapon_right := Vector2(-weapon_forward.y, weapon_forward.x)
	var ejection_direction := weapon_right.rotated(randf_range(-0.3, 0.3)).rotated(randf_range(-0.1, 0.1))
	casing.linear_velocity = ejection_direction * randf_range(120.0, 180.0)
	casing.angular_velocity = randf_range(-15.0, 15.0)
	if caliber_data:
		casing.set("caliber_data", caliber_data)
	else:
		var fallback := load("res://resources/calibers/caliber_545x39.tres")
		if fallback: casing.set("caliber_data", fallback)
	scene_tree.current_scene.add_child(casing)
