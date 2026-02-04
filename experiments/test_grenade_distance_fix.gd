extends Node2D

## Test script to validate grenade trajectory calculations
## This script tests the physics formula used in Player.cs against actual Godot physics

func _ready():
	print("=== Grenade Distance Fix Test ===")
	print()

	# Test case from log: Distance: 764, Speed: 677, Friction: 300
	test_grenade_distance(764.0, 677.0, 300.0)
	print()

	# Test case 2: Distance: 622, Speed: 610.9, Friction: 300
	test_grenade_distance(622.0, 610.9, 300.0)
	print()

	# Test if we need to adjust the formula
	print("=== Testing adjusted formulas ===")
	test_adjusted_formulas(764.0, 300.0)

func test_grenade_distance(target_distance: float, throw_speed: float, friction: float):
	print("Test case: Target=%0.1f, Speed=%0.1f, Friction=%0.1f" % [target_distance, throw_speed, friction])

	# Formula used in Player.cs: d = v² / (2 * friction)
	var formula_distance = (throw_speed * throw_speed) / (2.0 * friction)
	print("  Formula predicts: %0.2f pixels" % formula_distance)
	print("  Difference: %0.2f pixels" % (formula_distance - target_distance))

	# Simulate actual physics (60 FPS)
	var simulated_distance = simulate_physics(throw_speed, friction)
	print("  Simulation actual: %0.2f pixels" % simulated_distance)
	print("  Shortfall: %0.2f pixels (%0.1f%%)" % [(target_distance - simulated_distance), (simulated_distance / target_distance) * 100.0])

func simulate_physics(initial_speed: float, friction: float) -> float:
	var delta = 1.0 / 60.0  # 60 FPS
	var velocity = initial_speed
	var position = 0.0
	var iterations = 0

	while velocity > 1.0 and iterations < 10000:
		# Apply friction (from grenade_base.gd line 152)
		var friction_force = friction * delta
		if friction_force >= velocity:
			velocity = 0.0
		else:
			velocity -= friction_force

		# Update position
		position += velocity * delta
		iterations += 1

	return position

func test_adjusted_formulas(target_distance: float, friction: float):
	print("Finding correct formula to reach exactly %0.1f pixels with friction %0.1f:" % [target_distance, friction])

	# Current formula
	var speed_current = sqrt(2.0 * friction * target_distance)
	var actual_current = simulate_physics(speed_current, friction)
	print("  Current formula v = sqrt(2*f*d): speed=%0.2f, actual=%0.2f, shortfall=%0.2f" % [speed_current, actual_current, target_distance - actual_current])

	# Try compensating for discrete integration
	# The discrete integration loses about 0.75% of distance
	var compensation_factor = 1.008  # Compensate for ~0.8% loss
	var speed_compensated = sqrt(2.0 * friction * target_distance * compensation_factor)
	var actual_compensated = simulate_physics(speed_compensated, friction)
	print("  With 0.8%% compensation: speed=%0.2f, actual=%0.2f, shortfall=%0.2f" % [speed_compensated, actual_compensated, target_distance - actual_compensated])

	# Try finding exact multiplier
	var best_multiplier = 1.0
	var best_error = 1000.0
	for i in range(1000, 1020):
		var mult = i / 1000.0
		var test_speed = sqrt(2.0 * friction * target_distance * mult)
		var test_dist = simulate_physics(test_speed, friction)
		var error = abs(target_distance - test_dist)
		if error < best_error:
			best_error = error
			best_multiplier = mult

	var speed_best = sqrt(2.0 * friction * target_distance * best_multiplier)
	var actual_best = simulate_physics(speed_best, friction)
	print("  Optimal compensation (%0.3fx): speed=%0.2f, actual=%0.2f, error=%0.3f" % [best_multiplier, speed_best, actual_best, target_distance - actual_best])
