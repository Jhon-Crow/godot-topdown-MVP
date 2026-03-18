extends Node
## Sniper hitscan component for enemy (Issue #1171).
## Extracted from enemy.gd to reduce file size below 5000 lines.
## Handles instant raycast damage and smoke tracer for SNIPER_RIFLE enemies.
class_name EnemySniperComponent

## Reference to the owner enemy node (set on instantiation).
var enemy: Node2D = null
## Enable file logging (forwarded from enemy debug setting).
var log_to_file_fn: Callable = Callable()

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
