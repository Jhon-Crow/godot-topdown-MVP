extends SceneTree
## Test script for water spring physics simulation (Issue #1495).
##
## Verifies the core spring-column algorithm:
## 1. Springs oscillate and settle to equilibrium
## 2. Wave propagation works between columns
## 3. Splash creates visible disturbance
## 4. Explosion creates wide disturbance
## 5. Values stay within bounds
##
## Run: godot --headless --script experiments/test_water_spring_physics.gd

var _passed: int = 0
var _failed: int = 0
var _total: int = 0


func _init() -> void:
	print("\n=== Water Spring Physics Tests ===\n")

	test_column_initialization()
	test_single_spring_oscillation()
	test_wave_propagation()
	test_splash_force()
	test_explosion_splash()
	test_displacement_clamping()
	test_continuous_disturb()
	test_surface_height_query()

	print("\n=== Results: %d/%d passed, %d failed ===\n" % [_passed, _total, _failed])

	if _failed > 0:
		quit(1)
	else:
		quit(0)


func assert_true(condition: bool, test_name: String) -> void:
	_total += 1
	if condition:
		_passed += 1
		print("  PASS: %s" % test_name)
	else:
		_failed += 1
		print("  FAIL: %s" % test_name)


func assert_near(value: float, expected: float, tolerance: float, test_name: String) -> void:
	assert_true(abs(value - expected) <= tolerance, "%s (got %.4f, expected %.4f ± %.4f)" % [test_name, value, expected, tolerance])


func test_column_initialization() -> void:
	print("-- Column Initialization --")

	# Simulate initialization with 100px width and 4px column spacing
	var width: float = 100.0
	var col_width: float = 4.0
	var col_count: int = int(width / col_width) + 1

	assert_true(col_count == 26, "Column count for 100px width with 4px spacing")

	var heights := PackedFloat32Array()
	heights.resize(col_count)
	heights.fill(0.0)

	assert_true(heights.size() == 26, "Heights array initialized")
	assert_near(heights[0], 0.0, 0.001, "Initial height is zero")
	assert_near(heights[col_count - 1], 0.0, 0.001, "Last column height is zero")


func test_single_spring_oscillation() -> void:
	print("-- Single Spring Oscillation --")

	var spring_k: float = 0.025
	var damp: float = 0.025
	var height: float = 10.0  # Initial displacement
	var velocity: float = 0.0

	# Simulate 100 frames of a single spring
	for _i in range(100):
		var displacement: float = height
		velocity += -spring_k * displacement
		velocity *= (1.0 - damp)
		height += velocity

	# After 100 frames, spring should have mostly settled
	assert_true(abs(height) < 1.0, "Spring settles after 100 frames (height=%.4f)" % height)
	assert_true(abs(velocity) < 0.1, "Spring velocity near zero after 100 frames")

	# Test that spring passes through zero (oscillates)
	height = 10.0
	velocity = 0.0
	var crossed_zero: bool = false
	for _i in range(50):
		var old_height: float = height
		var displacement: float = height
		velocity += -spring_k * displacement
		velocity *= (1.0 - damp)
		height += velocity
		if old_height > 0.0 and height < 0.0:
			crossed_zero = true

	assert_true(crossed_zero, "Spring oscillates through zero")


func test_wave_propagation() -> void:
	print("-- Wave Propagation --")

	var col_count: int = 50
	var spread_factor: float = 0.25
	var spring_k: float = 0.025
	var damp: float = 0.025
	var passes: int = 8

	var heights := PackedFloat32Array()
	var velocities := PackedFloat32Array()
	heights.resize(col_count)
	velocities.resize(col_count)
	heights.fill(0.0)
	velocities.fill(0.0)

	# Create initial disturbance at center
	var center: int = col_count / 2
	heights[center] = 10.0

	# Simulate 20 frames
	for _frame in range(20):
		# Spring update
		for i in range(col_count):
			velocities[i] += -spring_k * heights[i]
			velocities[i] *= (1.0 - damp)
			heights[i] += velocities[i]

		# Propagation
		var left_deltas := PackedFloat32Array()
		var right_deltas := PackedFloat32Array()
		left_deltas.resize(col_count)
		right_deltas.resize(col_count)

		for _p in range(passes):
			left_deltas.fill(0.0)
			right_deltas.fill(0.0)
			for i in range(col_count):
				if i > 0:
					left_deltas[i] = spread_factor * (heights[i] - heights[i - 1])
					velocities[i - 1] += left_deltas[i]
				if i < col_count - 1:
					right_deltas[i] = spread_factor * (heights[i] - heights[i + 1])
					velocities[i + 1] += right_deltas[i]
			for i in range(col_count):
				if i > 0:
					heights[i - 1] += left_deltas[i]
				if i < col_count - 1:
					heights[i + 1] += right_deltas[i]

	# After propagation, neighbors should have been disturbed
	assert_true(abs(heights[center + 5]) > 0.01, "Wave propagated right (+5 columns)")
	assert_true(abs(heights[center - 5]) > 0.01, "Wave propagated left (-5 columns)")
	# Far edges should have some disturbance too (with 8 passes over 20 frames)
	assert_true(abs(heights[center + 15]) > 0.001, "Wave reached +15 columns")


func test_splash_force() -> void:
	print("-- Splash Force --")

	var col_count: int = 100
	var col_width: float = 4.0
	var left_x: float = -200.0

	var heights := PackedFloat32Array()
	var velocities := PackedFloat32Array()
	heights.resize(col_count)
	velocities.resize(col_count)
	heights.fill(0.0)
	velocities.fill(0.0)

	# Simulate a splash at the center
	var splash_x: float = 0.0  # World position
	var global_x: float = 0.0   # Surface global position
	var local_x: float = splash_x - global_x
	var col_index: int = int((local_x - left_x) / col_width)

	var force: float = 100.0 * 0.15  # velocity * scale
	var spread_cols: int = 5

	for offset in range(-spread_cols, spread_cols + 1):
		var idx: int = col_index + offset
		if idx >= 0 and idx < col_count:
			var dist_factor: float = 1.0 - (abs(float(offset)) / float(spread_cols + 1))
			dist_factor *= dist_factor
			velocities[idx] += force * dist_factor

	assert_true(velocities[col_index] > 10.0, "Center column received force")
	assert_true(velocities[col_index + 3] > 0.0, "Neighbor +3 received reduced force")
	assert_true(velocities[col_index + 3] < velocities[col_index], "Force decreases with distance")


func test_explosion_splash() -> void:
	print("-- Explosion Splash --")

	var col_count: int = 200
	var col_width: float = 4.0
	var left_x: float = -400.0

	var velocities := PackedFloat32Array()
	velocities.resize(col_count)
	velocities.fill(0.0)

	# Simulate explosion at center
	var center_col: int = 100
	var explosion_radius: float = 100.0
	var force: float = 300.0
	var radius_cols: int = int(explosion_radius / col_width)

	for offset in range(-radius_cols, radius_cols + 1):
		var idx: int = center_col + offset
		if idx >= 0 and idx < col_count:
			var dist_norm: float = abs(float(offset)) / float(radius_cols + 1)
			var profile: float = cos(dist_norm * PI)
			velocities[idx] += force * 0.15 * profile

	# Center should go down (positive force)
	assert_true(velocities[center_col] > 0.0, "Explosion center has positive force")
	# Edges should go up (negative force from cosine profile)
	assert_true(velocities[center_col + radius_cols - 1] < velocities[center_col], "Edge force is less than center")
	# Verify sinusoidal profile — halfway point should be near zero
	var halfway: int = center_col + radius_cols / 2
	assert_true(abs(velocities[halfway]) < abs(velocities[center_col]), "Halfway force less than center")


func test_displacement_clamping() -> void:
	print("-- Displacement Clamping --")

	var max_disp: float = 30.0
	var height: float = 50.0  # Way above max
	height = clampf(height, -max_disp, max_disp)
	assert_near(height, 30.0, 0.001, "Positive displacement clamped to max")

	height = -50.0
	height = clampf(height, -max_disp, max_disp)
	assert_near(height, -30.0, 0.001, "Negative displacement clamped to -max")


func test_continuous_disturb() -> void:
	print("-- Continuous Disturb --")

	var col_count: int = 50
	var velocities := PackedFloat32Array()
	velocities.resize(col_count)
	velocities.fill(0.0)

	# Simulate continuous disturbance at column 25
	var strength: float = 2.0
	var idx: int = 25
	velocities[idx] += strength
	velocities[idx - 1] += strength * 0.5
	velocities[idx + 1] += strength * 0.5

	assert_near(velocities[idx], 2.0, 0.001, "Center column disturbed")
	assert_near(velocities[idx - 1], 1.0, 0.001, "Left neighbor disturbed at half strength")
	assert_near(velocities[idx + 1], 1.0, 0.001, "Right neighbor disturbed at half strength")


func test_surface_height_query() -> void:
	print("-- Surface Height Query --")

	var col_count: int = 100
	var col_width: float = 4.0
	var left_x: float = -200.0

	var heights := PackedFloat32Array()
	heights.resize(col_count)
	heights.fill(0.0)
	heights[50] = 5.0  # Set a known height

	# Query column 50 position
	var world_x: float = 0.0  # global position = 0
	var local_x: float = world_x - 0.0
	var col_index: int = int((local_x - left_x) / col_width)

	assert_true(col_index == 50, "Column index calculation correct")
	assert_near(heights[col_index], 5.0, 0.001, "Surface height at column 50")
