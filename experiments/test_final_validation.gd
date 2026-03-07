extends Node

# Final validation test for laser glow lag fixes #748
# Tests both translation and rotation synchronization

var player: Node2D
var weapon: Node2D
var dust_particles: Node2D
var test_results = []
var test_start_time = 0

func _ready():
	setup_test()
	
func setup_test():
	print("[INFO] Final validation test starting...")
	
	# Find player and weapon
	player = get_tree().get_first_node_in_group("player")
	if not player:
		print("[ERROR] Player not found!")
		return
		
	var weapons = get_tree().get_nodes_in_group("weapons")
	for w in weapons:
		if w.has_method("UpdateLaserSight"):
			weapon = w
			break
			
	if not weapon:
		print("[ERROR] Weapon with laser sight not found!")
		return
		
	# Enable Power Fantasy mode
	var difficulty_manager = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager:
		difficulty_manager.call("set_difficulty", 2)
		
	# Find dust particles for direct testing
	dust_particles = weapon.get_node_or_null("LaserDustParticles")
	
	print("[INFO] Test setup complete. Waiting 2 seconds for initialization...")
	await get_tree().create_timer(2.0).timeout
	
	test_start_time = Time.get_ticks_msec()
	
	# Run comprehensive movement test
	run_movement_tests()

func run_movement_tests():
	print("[INFO] Running comprehensive movement tests...")
	
	# Test 1: Forward walking
	print("[TEST] Forward walking test...")
	await test_forward_movement()
	await get_tree().create_timer(1.0).timeout
	
	# Test 2: Backward walking  
	print("[TEST] Backward walking test...")
	await test_backward_movement()
	await get_tree().create_timer(1.0).timeout
	
	# Test 3: Rotation in place
	print("[TEST] Rotation test...")
	await test_rotation_movement()
	await get_tree().create_timer(1.0).timeout
	
	# Test 4: Combined movement + rotation
	print("[TEST] Combined movement + rotation test...")
	await test_combined_movement()
	
	# Analyze results
	analyze_final_results()

func test_forward_movement():
	var start_pos = player.global_position
	var duration = 2.0  # seconds
	var start_time = Time.get_ticks_msec()
	
	while Time.get_ticks_msec() - start_time < duration * 1000:
		player.global_position += Vector2.RIGHT * 80 * get_process_delta_time()
		
		if Time.get_ticks_msec() % 200 < 20:  # Sample every 200ms
			record_sync_state("forward_walk")
			
		await get_tree().process_frame
	
	var end_pos = player.global_position
	print("[TEST] Forward: ", start_pos, " -> ", end_pos, " (distance: ", start_pos.distance_to(end_pos), "px)")

func test_backward_movement():
	var start_pos = player.global_position
	var duration = 2.0
	var start_time = Time.get_ticks_msec()
	
	while Time.get_ticks_msec() - start_time < duration * 1000:
		player.global_position += Vector2.LEFT * 80 * get_process_delta_time()
		
		if Time.get_ticks_msec() % 200 < 20:
			record_sync_state("backward_walk")
			
		await get_tree().process_frame
	
	var end_pos = player.global_position
	print("[TEST] Backward: ", start_pos, " -> ", end_pos, " (distance: ", start_pos.distance_to(end_pos), "px)")

func test_rotation_movement():
	var start_rotation = weapon.rotation
	var duration = 2.0
	var start_time = Time.get_ticks_msec()
	
	while Time.get_ticks_msec() - start_time < duration * 1000:
		weapon.rotation += 0.05  # Rotate continuously
		
		if Time.get_ticks_msec() % 200 < 20:
			record_sync_state("rotation")
			
		await get_tree().process_frame
	
	var end_rotation = weapon.rotation
	print("[TEST] Rotation: ", start_rotation, " -> ", end_rotation, " (delta: ", end_rotation - start_rotation, " rad)")

func test_combined_movement():
	var start_pos = player.global_position
	var start_rot = weapon.rotation
	var duration = 2.0
	var start_time = Time.get_ticks_msec()
	
	while Time.get_ticks_msec() - start_time < duration * 1000:
		# Move forward and rotate simultaneously
		player.global_position += Vector2.RIGHT * 60 * get_process_delta_time()
		weapon.rotation += 0.03
		
		if Time.get_ticks_msec() % 200 < 20:
			record_sync_state("combined")
			
		await get_tree().process_frame
	
	var end_pos = player.global_position
	var end_rot = weapon.rotation
	print("[TEST] Combined: Pos ", start_pos, " -> ", end_pos, " | Rot ", start_rot, " -> ", end_rot)

func record_sync_state(test_type: String):
	if not player or not weapon or not dust_particles:
		return
		
	var timestamp = (Time.get_ticks_msec() - test_start_time) / 1000.0
	
	var player_pos = player.global_position
	var weapon_pos = weapon.global_position
	var dust_pos = dust_particles.global_position
	
	# Calculate synchronization metrics
	var weapon_player_offset = weapon_pos.distance_to(player_pos)
	var dust_weapon_offset = dust_pos.distance_to(weapon_pos)
	var expected_dust_pos = weapon_pos + Vector2(0, 0)  # Dust should be at weapon position
	var dust_pos_error = dust_pos.distance_to(expected_dust_pos)
	
	# Get laser endpoint for comparison
	var laser_sight = weapon.get_node_or_null("LaserSight")
	var laser_deviation = 0.0
	if laser_sight:
		var laser_end_local = laser_sight.get_point_position(1)
		var laser_end_global = laser_sight.to_global(laser_end_local)
		var mouse_pos = get_global_mouse_position()
		var direction = (mouse_pos - weapon_pos).normalized()
		var expected_end = weapon_pos + direction * 500
		laser_deviation = laser_end_global.distance_to(expected_end)
	
	var measurement = {
		"timestamp": timestamp,
		"test_type": test_type,
		"player_pos": player_pos,
		"weapon_pos": weapon_pos,
		"dust_pos": dust_pos,
		"weapon_player_offset": weapon_player_offset,
		"dust_weapon_offset": dust_weapon_offset,
		"dust_pos_error": dust_pos_error,
		"laser_deviation": laser_deviation,
		"weapon_rotation": weapon.rotation,
		"dust_rotation": dust_particles.rotation
	}
	
	test_results.append(measurement)
	
	# Real-time feedback
	if weapon_player_offset > 2.0:
		print("[LAG] Frame ", timestamp, "s: Weapon offset ", weapon_player_offset, "px (>2px threshold)")
		
	if dust_weapon_offset > 2.0:
		print("[LAG] Frame ", timestamp, "s: Dust offset ", dust_weapon_offset, "px (>2px threshold)")
		
	if laser_deviation > 3.0:
		print("[LAG] Frame ", timestamp, "s: Laser deviation ", laser_deviation, "px (>3px threshold)")

func analyze_final_results():
	print("[INFO] Analyzing final results...")
	
	if test_results.size() == 0:
		print("[ERROR] No measurements collected!")
		return
	
	# Group by test type
	var forward_results = test_results.filter(func(m): return m.test_type == "forward_walk")
	var backward_results = test_results.filter(func(m): return m.test_type == "backward_walk")
	var rotation_results = test_results.filter(func(m): return m.test_type == "rotation")
	var combined_results = test_results.filter(func(m): return m.test_type == "combined")
	
	print("\n=== FINAL VALIDATION RESULTS ===")
	analyze_test_group("Forward Walking", forward_results)
	analyze_test_group("Backward Walking", backward_results)
	analyze_test_group("Rotation", rotation_results)
	analyze_test_group("Combined Movement", combined_results)
	
	# Overall assessment
	var all_offsets = test_results.map(func(m): return m.dust_weapon_offset)
	var all_laser_dev = test_results.map(func(m): return m.laser_deviation)
	
	if all_offsets.size() > 0:
		var avg_offset = all_offsets.reduce(func(a, b): return a + b, 0) / all_offsets.size()
		var max_offset = all_offsets.reduce(func(a, b): return max(a, b), 0)
		var avg_laser_dev = all_laser_dev.reduce(func(a, b): return a + b, 0) / all_laser_dev.size()
		var max_laser_dev = all_laser_dev.reduce(func(a, b): return max(a, b), 0)
		
		print("\n=== OVERALL ASSESSMENT ===")
		print("Average dust particle offset: ", avg_offset, "px (target: <2px)")
		print("Maximum dust particle offset: ", max_offset, "px")
		print("Average laser deviation: ", avg_laser_dev, "px (target: <3px)")
		print("Maximum laser deviation: ", max_laser_dev, "px")
		
		if avg_offset < 2.0 and avg_laser_dev < 3.0:
			print("✅ SUCCESS: Both translation and rotation lag are FIXED!")
		elif avg_offset < 2.0:
			print("✅ TRANSLATION FIXED but rotation lag may remain")
		elif avg_laser_dev < 3.0:
			print("✅ ROTATION FIXED but translation lag may remain")
		else:
			print("❌ FAILURE: Both translation and rotation lag detected")
	
	save_results()

func analyze_test_group(test_name: String, results: Array):
	if results.size() == 0:
		print("[", test_name, "] No data")
		return
	
	var dust_offsets = results.map(func(m): return m.dust_weapon_offset)
	var laser_devs = results.map(func(m): return m.laser_deviation)
	
	var avg_dust = dust_offsets.reduce(func(a, b): return a + b, 0) / dust_offsets.size()
	var max_dust = dust_offsets.reduce(func(a, b): return max(a, b), 0)
	var avg_laser = laser_devs.reduce(func(a, b): return a + b, 0) / laser_devs.size()
	var max_laser = laser_devs.reduce(func(a, b): return max(a, b), 0)
	
	print("[", test_name, "] Dust: avg ", avg_dust, "px, max ", max_dust, "px | Laser: avg ", avg_laser, "px, max ", max_laser, "px")
	
	var dust_ok = avg_dust < 2.0 and max_dust < 5.0
	var laser_ok = avg_laser < 3.0 and max_laser < 8.0
	
	if dust_ok and laser_ok:
		print("[", test_name, "] ✅ PASS")
	else:
		print("[", test_name, "] ❌ FAIL - ", "dust ok" if dust_ok else "dust lag", " + ", "laser ok" if laser_ok else "laser lag")

func save_results():
	var json_string = JSON.stringify(test_results)
	var file = FileAccess.open("user://laser_final_validation.json", FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		print("[INFO] Results saved to user://laser_final_validation.json")
	
	get_tree().quit()