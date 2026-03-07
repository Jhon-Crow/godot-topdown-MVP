extends Node

# Experiment to reproduce laser glow lag issue (#748)
# This script will help identify which component is causing the lag

var player: Node2D
var weapon: Node2D
var laser_sight: Line2D
var laser_glow: Node
var dust_particles: Node2D
var frame_count = 0
var test_results = []

func _ready():
	# Find player and weapon
	player = get_tree().get_first_node_in_group("player")
	if not player:
		GDPrint("ERROR: Player not found!")
		return
		
	# Try to find a weapon with laser sight
	var weapons = get_tree().get_nodes_in_group("weapons")
	for w in weapons:
		if w.has_method("UpdateLaserSight"):
			weapon = w
			break
			
	if not weapon:
		GDPrint("ERROR: Weapon with laser sight not found!")
		return
		
	# Enable Power Fantasy mode to ensure laser is active
	var difficulty_manager = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager:
		difficulty_manager.call("set_difficulty", 2)  # Power Fantasy
		
	GDPrint("Test setup complete. Player: ", player.name, " Weapon: ", weapon.name)
	
	# Wait a bit for everything to initialize
	await get_tree().create_timer(2.0).timeout
	
	# Start the test
	start_lag_test()

func start_lag_test():
	GDPrint("Starting laser lag test...")
	
	# Test 1: Check if LocalCoords is properly set on dust particles
	dust_particles = weapon.get_node_or_null("LaserDustParticles")
	if dust_particles:
		var local_coords = dust_particles.get("local_coords")
		GDPrint("Dust particles LocalCoords: ", local_coords)
		test_results.append({"test": "LocalCoords", "value": local_coords, "expected": true})
	else:
		GDPrint("WARNING: LaserDustParticles node not found")
	
	# Test 2: Measure laser position vs player position over time
	set_process(true)

func _process(delta):
	frame_count += 1
	
	if frame_count % 6 == 0:  # Check every 6 frames (roughly 10 times per second)
		if player and weapon:
			var player_pos = player.global_position
			var weapon_pos = weapon.global_position
			
			# Try to get laser sight line
			laser_sight = weapon.get_node_or_null("LaserSight")
			if laser_sight:
				var laser_start = laser_sight.global_position
				var laser_end_global = laser_sight.to_global(laser_sight.get_point_position(1))
				
				# Calculate expected laser end based on current weapon position and mouse
				var mouse_pos = get_global_mouse_position()
				var direction = (mouse_pos - weapon_pos).normalized()
				var expected_end = weapon_pos + direction * 500
				
				# Measure lag
				var actual_distance = laser_end_global.distance_to(expected_end)
				var position_lag = weapon_pos.distance_to(player_pos)
				
				# Store measurement
				var measurement = {
					"frame": frame_count,
					"player_pos": player_pos,
					"weapon_pos": weapon_pos,
					"laser_end": laser_end_global,
					"expected_end": expected_end,
					"laser_deviation": actual_distance,
					"weapon_player_offset": position_lag
				}
				
				test_results.append(measurement)
				
				# Only log significant deviations
				if actual_distance > 5.0:
					GDPrint("LAG DETECTED! Frame ", frame_count, " Laser deviation: ", actual_distance, "px")
				
				# Visual indicator - show red circle if lag detected
				if actual_distance > 10.0:
					show_lag_indicator(laser_end_global, expected_end)

func show_lag_indicator(actual_pos, expected_pos):
	# Create visual indicators for debugging
	var actual_indicator = ColorRect.new()
	actual_indicator.size = Vector2(10, 10)
	actual_indicator.color = Color.RED
	actual_indicator.position = actual_pos - Vector2(5, 5)
	get_tree().current_scene.add_child(actual_indicator)
	
	var expected_indicator = ColorRect.new()
	expected_indicator.size = Vector2(8, 8)
	expected_indicator.color = Color.GREEN
	expected_indicator.position = expected_pos - Vector2(4, 4)
	get_tree().current_scene.add_child(expected_indicator)
	
	# Remove after 1 second
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(actual_indicator):
		actual_indicator.queue_free()
	if is_instance_valid(expected_indicator):
		expected_indicator.queue_free()

func _input(event):
	# Press SPACE to end test and show results
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		end_test()

func end_test():
	GDPrint("Test ended. Analyzing results...")
	
	# Calculate statistics
	var avg_deviation = 0.0
	var max_deviation = 0.0
	var lag_samples = 0
	
	for result in test_results:
		if result.has("laser_deviation"):
			var deviation = result["laser_deviation"]
			avg_deviation += deviation
			max_deviation = max(max_deviation, deviation)
			lag_samples += 1
	
	if lag_samples > 0:
		avg_deviation /= lag_samples
		
		GDPrint("=== LAG ANALYSIS ===")
		GDPrint("Samples analyzed: ", lag_samples)
		GDPrint("Average laser deviation: ", avg_deviation, "px")
		GDPrint("Maximum laser deviation: ", max_deviation, "px")
		
		if avg_deviation > 5.0:
			GDPrint("CONFIRMED: Significant laser lag detected!")
		elif max_deviation > 15.0:
			GDPrint("CONFIRMED: Intermittent laser lag detected!")
		else:
			GDPrint("No significant lag detected.")
	
	# Save results to file
	var json_string = JSON.stringify(test_results)
	var file = FileAccess.open("user://laser_lag_test_results.json", FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		GDPrint("Results saved to user://laser_lag_test_results.json")
	
	get_tree().quit()

func GDPrint(msg):
	if OS.is_debug_build():
		print("[LaserLagTest] ", msg)