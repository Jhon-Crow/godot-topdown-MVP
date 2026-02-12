extends Node

# Focused test for issue #748: "laser remains behind player when walking forward"
# This test specifically targets the translation lag issue

var player: Node2D
var weapon: Node2D
var test_active = false
var test_start_time = 0
var measurements = []

func _ready():
	setup_test()
	
func setup_test():
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
		
	print("[INFO] Test setup complete. Press W to start forward walking test.")
	
	# Wait for initialization
	await get_tree().create_timer(2.0).timeout
	test_active = true

func _input(event):
	if not test_active:
		return
		
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_W:
				start_forward_walk_test()
			KEY_S:
				start_backward_walk_test()
			KEY_SPACE:
				end_test()

func start_forward_walk_test():
	print("[INFO] Starting forward walk test...")
	test_start_time = Time.get_ticks_msec()
	
	# Move player forward continuously for 3 seconds
	var original_player_pos = player.global_position
	var test_duration = 3.0  # seconds
	var start_time = Time.get_ticks_msec()
	
	while Time.get_ticks_msec() - start_time < test_duration * 1000:
		if player:
			# Move player forward (right)
			player.global_position += Vector2.RIGHT * 100 * get_process_delta_time()
			
			# Record measurements every 100ms
			if Time.get_ticks_msec() % 100 < 20:
				record_measurement("forward")
				
		await get_tree().process_frame
	
	print("[INFO] Forward walk test completed. Original pos: ", original_player_pos, " Final pos: ", player.global_position)

func start_backward_walk_test():
	print("[INFO] Starting backward walk test...")
	test_start_time = Time.get_ticks_msec()
	
	# Move player backward continuously for 3 seconds
	var original_player_pos = player.global_position
	var test_duration = 3.0
	var start_time = Time.get_ticks_msec()
	
	while Time.get_ticks_msec() - start_time < test_duration * 1000:
		if player:
			# Move player backward (left)
			player.global_position += Vector2.LEFT * 100 * get_process_delta_time()
			
			# Record measurements
			if Time.get_ticks_msec() % 100 < 20:
				record_measurement("backward")
				
		await get_tree().process_frame
	
	print("[INFO] Backward walk test completed.")

func record_measurement(direction: String):
	if not player or not weapon:
		return
		
	var timestamp = (Time.get_ticks_msec() - test_start_time) / 1000.0
	
	# Get positions
	var player_pos = player.global_position
	var weapon_pos = weapon.global_position
	
	# Get laser sight end position
	var laser_sight = weapon.get_node_or_null("LaserSight")
	var laser_end_global = Vector2.ZERO
	var laser_expected_end = Vector2.ZERO
	
	if laser_sight:
		var laser_end_local = laser_sight.get_point_position(1)
		laser_end_global = laser_sight.to_global(laser_end_local)
		
		# Calculate expected laser end based on current weapon position
		var mouse_pos = get_global_mouse_position()
		var direction = (mouse_pos - weapon_pos).normalized()
		laser_expected_end = weapon_pos + direction * 500
	
	# Get dust particles position
	var dust_particles = weapon.get_node_or_null("LaserDustParticles")
	var dust_pos = Vector2.ZERO
	if dust_particles:
		dust_pos = dust_particles.global_position
	
	var measurement = {
		"timestamp": timestamp,
		"direction": direction,
		"player_pos": player_pos,
		"weapon_pos": weapon_pos,
		"laser_end": laser_end_global,
		"laser_expected": laser_expected_end,
		"laser_deviation": laser_end_global.distance_to(laser_expected_end),
		"dust_pos": dust_pos,
		"dust_weapon_offset": dust_pos.distance_to(weapon_pos),
		"weapon_player_offset": weapon_pos.distance_to(player_pos)
	}
	
	measurements.append(measurement)
	
	# Real-time lag detection
	var laser_deviation = measurement["laser_deviation"]
	var dust_offset = measurement["dust_weapon_offset"]
	
	if laser_deviation > 5.0:
		print("[LAG] Frame ", timestamp, "s: Laser deviation ", laser_deviation, "px (should be < 5px)")
		
	if dust_offset > 5.0:
		print("[LAG] Frame ", timestamp, "s: Dust particles offset ", dust_offset, "px (should be < 5px)")

func end_test():
	print("[INFO] Analyzing test results...")
	
	if measurements.size() == 0:
		print("[ERROR] No measurements collected!")
		return
	
	# Analyze forward movement separately from backward
	var forward_measurements = measurements.filter(func(m): return m.direction == "forward")
	var backward_measurements = measurements.filter(func(m): return m.direction == "backward")
	
	analyze_direction("Forward", forward_measurements)
	analyze_direction("Backward", backward_measurements)
	
	# Save results
	save_results()

func analyze_direction(direction: String, data: Array):
	if data.size() == 0:
		print("[INFO] No ", direction.to_lower(), " measurements")
		return
	
	print("\n=== ", direction.upper(), " MOVEMENT ANALYSIS ===")
	
	# Laser deviation analysis
	var laser_deviations = data.map(func(m): return m.laser_deviation)
	var avg_laser_dev = laser_deviations.reduce(func(a, b): return a + b, 0) / laser_deviations.size()
	var max_laser_dev = laser_deviations.reduce(func(a, b): return max(a, b), 0)
	
	print("Laser Deviation:")
	print("  Average: ", avg_laser_dev, "px")
	print("  Maximum: ", max_laser_dev, "px")
	print("  Threshold: 5px")
	
	if avg_laser_dev > 5.0:
		print("  ❌ SIGNIFICANT TRANSLATION LAG DETECTED!")
	elif max_laser_dev > 10.0:
		print("  ⚠️  INTERMITTENT TRANSLATION LAG DETECTED!")
	else:
		print("  ✅ No significant translation lag")
	
	# Dust particle offset analysis
	var dust_offsets = data.map(func(m): return m.dust_weapon_offset)
	var avg_dust_offset = dust_offsets.reduce(func(a, b): return a + b, 0) / dust_offsets.size()
	var max_dust_offset = dust_offsets.reduce(func(a, b): return max(a, b), 0)
	
	print("Dust Particle Offset:")
	print("  Average: ", avg_dust_offset, "px")
	print("  Maximum: ", max_dust_offset, "px")
	print("  Threshold: 5px")
	
	if avg_dust_offset > 5.0:
		print("  ❌ SIGNIFICANT DUST PARTICLE LAG DETECTED!")
	elif max_dust_offset > 10.0:
		print("  ⚠️  INTERMITTENT DUST PARTICLE LAG DETECTED!")
	else:
		print("  ✅ No significant dust particle lag")
	
	# Weapon-Player offset analysis
	var weapon_player_offsets = data.map(func(m): return m.weapon_player_offset)
	var avg_wp_offset = weapon_player_offsets.reduce(func(a, b): return a + b, 0) / weapon_player_offsets.size()
	var max_wp_offset = weapon_player_offsets.reduce(func(a, b): return max(a, b), 0)
	
	print("Weapon-Player Offset:")
	print("  Average: ", avg_wp_offset, "px")
	print("  Maximum: ", max_wp_offset, "px")

func save_results():
	var json_string = JSON.stringify(measurements)
	var file = FileAccess.open("user://translation_lag_test.json", FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		print("[INFO] Results saved to user://translation_lag_test.json")
	
	get_tree().quit()