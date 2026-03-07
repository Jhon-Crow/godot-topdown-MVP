extends Node

# Comprehensive test to identify laser glow lag issue #748
# Tests both translation and rotation lag separately

var player: Node2D
var weapon: Node2D
var laser_glow: Node
var dust_particles: Node2D
var frame_count = 0
var test_results = []
var is_test_running = false

# Lag detection thresholds
var TRANSLATION_LAG_THRESHOLD = 5.0  # pixels
var ROTATION_LAG_THRESHOLD = 0.1     # radians

func _ready():
	# Find player and weapon
	player = get_tree().get_first_node_in_group("player")
	if not player:
		print("[ERROR] Player not found!")
		return
		
	# Try to find a weapon with laser sight
	var weapons = get_tree().get_nodes_in_group("weapons")
	for w in weapons:
		if w.has_method("UpdateLaserSight"):
			weapon = w
			break
			
	if not weapon:
		print("[ERROR] Weapon with laser sight not found!")
		return
		
	# Enable Power Fantasy mode to ensure laser is active
	var difficulty_manager = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager:
		difficulty_manager.call("set_difficulty", 2)  # Power Fantasy
		
	print("[INFO] Test setup complete. Player: ", player.name, " Weapon: ", weapon.name)
	
	# Wait a bit for everything to initialize
	await get_tree().create_timer(2.0).timeout
	
	# Start the test
	start_comprehensive_test()

func start_comprehensive_test():
	print("[INFO] Starting comprehensive laser lag test...")
	
	# Test 1: Verify LocalCoords setting
	test_local_coords_setting()
	
	# Test 2: Begin continuous monitoring
	is_test_running = true
	set_process(true)

func test_local_coords_setting():
	print("[INFO] Testing LocalCoords configuration...")
	
	# Find dust particles
	dust_particles = weapon.get_node_or_null("LaserDustParticles")
	if dust_particles:
		var local_coords = dust_particles.get("local_coords")
		print("[INFO] Dust particles LocalCoords: ", local_coords)
		
		if local_coords != true:
			print("[WARNING] LocalCoords is not TRUE! This is likely the translation lag cause.")
			test_results.append({"type": "config_error", "issue": "LocalCoords not true", "value": local_coords})
		else:
			print("[INFO] LocalCoords is correctly set to TRUE")
	else:
		print("[ERROR] LaserDustParticles node not found!")
	
	# Find laser glow lines
	var glow_lines = []
	for i in range(10):  # Check for up to 10 glow layers
		var line = weapon.get_node_or_null("LaserGlow_" + str(i))
		if line:
			glow_lines.append(line)
		else:
			break
	
	print("[INFO] Found ", glow_lines.size(), " laser glow lines")
	test_results.append({"type": "config", "glow_lines": glow_lines.size(), "has_dust": dust_particles != null})

func _process(delta):
	if not is_test_running:
		return
		
	frame_count += 1
	
	if frame_count % 6 == 0:  # Check every 6 frames (roughly 10 times per second)
		if player and weapon:
			analyze_lag()

func analyze_lag():
	# Get current positions and rotations
	var player_pos = player.global_position
	var weapon_pos = weapon.global_position
	var player_rotation = player.rotation if player.has_method("get") else 0.0
	
	# Test 1: Translation lag detection
	var weapon_player_offset = weapon_pos.distance_to(player_pos)
	
	# Test 2: Rotation lag detection (if weapon has rotation)
	var expected_weapon_rotation = 0.0
	var actual_weapon_rotation = weapon.rotation if weapon.has_method("get") else 0.0
	
	# Try to get mouse direction to determine expected weapon rotation
	var mouse_pos = get_global_mouse_position()
	var direction_to_mouse = (mouse_pos - weapon_pos).normalized()
	expected_weapon_rotation = direction_to_mouse.angle()
	
	# Analyze laser components
	analyze_laser_components(expected_weapon_rotation)
	
	# Store measurement
	var measurement = {
		"frame": frame_count,
		"timestamp": Time.get_ticks_msec(),
		"player_pos": player_pos,
		"weapon_pos": weapon_pos,
		"weapon_player_offset": weapon_player_offset,
		"expected_rotation": expected_weapon_rotation,
		"actual_rotation": actual_weapon_rotation,
		"rotation_error": abs(expected_weapon_rotation - actual_weapon_rotation)
	}
	
	test_results.append(measurement)
	
	# Check for significant lag
	if weapon_player_offset > TRANSLATION_LAG_THRESHOLD:
		print("[LAG] Translation lag detected! Offset: ", weapon_player_offset, "px")
		
	if abs(expected_weapon_rotation - actual_weapon_rotation) > ROTATION_LAG_THRESHOLD:
		print("[LAG] Rotation lag detected! Error: ", abs(expected_weapon_rotation - actual_weapon_rotation), " rad")

func analyze_laser_components(expected_rotation):
	# Analyze laser sight line
	var laser_sight = weapon.get_node_or_null("LaserSight")
	if laser_sight:
		var laser_start = laser_sight.global_position
		var laser_end_local = laser_sight.get_point_position(1)
		var laser_end_global = laser_sight.to_global(laser_end_local)
		
		# Calculate expected laser end based on current weapon position and mouse
		var mouse_pos = get_global_mouse_position()
		var direction = (mouse_pos - weapon.global_position).normalized()
		var expected_end = weapon.global_position + direction * 500
		
		var laser_deviation = laser_end_global.distance_to(expected_end)
		
		if laser_deviation > TRANSLATION_LAG_THRESHOLD:
			print("[LAG] Laser sight deviation: ", laser_deviation, "px")
			
		test_results.append({
			"type": "laser_analysis",
			"laser_deviation": laser_deviation,
			"laser_start": laser_start,
			"laser_end": laser_end_global,
			"expected_end": expected_end
		})
	
	# Analyze dust particles specifically
	if dust_particles:
		var dust_pos = dust_particles.global_position
		var dust_rotation = dust_particles.rotation
		var expected_dust_rotation = expected_rotation
		
		# Check if dust particles are following weapon position
		var dust_weapon_offset = dust_pos.distance_to(weapon.global_position)
		if dust_weapon_offset > TRANSLATION_LAG_THRESHOLD:
			print("[LAG] Dust particles translation lag: ", dust_weapon_offset, "px")
			
		# Check if dust particles are following weapon rotation
		var dust_rotation_error = abs(dust_rotation - expected_dust_rotation)
		if dust_rotation_error > ROTATION_LAG_THRESHOLD:
			print("[LAG] Dust particles rotation lag: ", dust_rotation_error, " rad")
			
		test_results.append({
			"type": "dust_analysis",
			"dust_pos": dust_pos,
			"dust_rotation": dust_rotation,
			"expected_rotation": expected_dust_rotation,
			"translation_error": dust_weapon_offset,
			"rotation_error": dust_rotation_error
		})

func _input(event):
	# Press SPACE to end test and show results
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		end_test()
		
	# Press R to run translation test specifically
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		test_translation_only()
		
	# Press T to run rotation test specifically
	if event is InputEventKey and event.pressed and event.keycode == KEY_T:
		test_rotation_only()

func test_translation_only():
	print("[INFO] Testing translation lag only...")
	# Move player forward for a few seconds
	if player:
		var forward_direction = Vector2.RIGHT  # Adjust based on your game
		for i in range(60):  # 1 second at 60 FPS
			player.global_position += forward_direction * 2
			await get_tree().process_frame

func test_rotation_only():
	print("[INFO] Testing rotation lag only...")
	# Rotate player in place for a few seconds
	if weapon:
		for i in range(60):  # 1 second at 60 FPS
			weapon.rotation += 0.1  # Small rotation
			await get_tree().process_frame

func end_test():
	print("[INFO] Test ended. Analyzing results...")
	is_test_running = false
	
	# Analyze results
	analyze_results()
	
	# Save results to file
	var json_string = JSON.stringify(test_results)
	var file = FileAccess.open("user://laser_lag_comprehensive_test.json", FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		print("[INFO] Results saved to user://laser_lag_comprehensive_test.json")
	
	print("[INFO] Test complete. Press ESC to quit.")

func analyze_results():
	var translation_errors = []
	var rotation_errors = []
	var config_errors = []
	
	for result in test_results:
		if result.get("type") == "config_error":
			config_errors.append(result)
		elif result.get("weapon_player_offset", 0) > TRANSLATION_LAG_THRESHOLD:
			translation_errors.append(result.weapon_player_offset)
		elif result.get("rotation_error", 0) > ROTATION_LAG_THRESHOLD:
			rotation_errors.append(result.rotation_error)
	
	print("\n=== COMPREHENSIVE LAG ANALYSIS ===")
	print("Total measurements: ", test_results.size())
	
	if config_errors.size() > 0:
		print("❌ CONFIG ERRORS FOUND: ", config_errors.size())
		for error in config_errors:
			print("   - ", error.issue, " (value: ", error.value, ")")
	
	if translation_errors.size() > 0:
		print("❌ TRANSLATION LAG DETECTED: ", translation_errors.size(), " instances")
		var avg_translation = translation_errors.reduce(func(a, b): return a + b, 0) / translation_errors.size()
		var max_translation = translation_errors.reduce(func(a, b): return max(a, b), 0)
		print("   Average: ", avg_translation, "px")
		print("   Maximum: ", max_translation, "px")
	else:
		print("✅ No significant translation lag detected")
	
	if rotation_errors.size() > 0:
		print("❌ ROTATION LAG DETECTED: ", rotation_errors.size(), " instances")
		var avg_rotation = rotation_errors.reduce(func(a, b): return a + b, 0) / rotation_errors.size()
		var max_rotation = rotation_errors.reduce(func(a, b): return max(a, b), 0)
		print("   Average: ", avg_rotation, " rad")
		print("   Maximum: ", max_rotation, " rad")
	else:
		print("✅ No significant rotation lag detected")
	
	# Provide diagnosis
	if config_errors.size() > 0:
		print("\n🔧 DIAGNOSIS: Configuration issues found. Check LocalCoords setting.")
	elif translation_errors.size() > 0 and rotation_errors.size() > 0:
		print("\n🔧 DIAGNOSIS: Both translation and rotation lag detected.")
	elif translation_errors.size() > 0:
		print("\n🔧 DIAGNOSIS: Translation lag only. Issue #694 fix may not be working properly.")
	elif rotation_errors.size() > 0:
		print("\n🔧 DIAGNOSIS: Rotation lag only. Issue #748 rotation fix needed.")
	else:
		print("\n✅ DIAGNOSIS: No significant lag detected in current test conditions.")