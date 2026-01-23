extends Node

## Experiment to understand Godot rotation with vertical flip
## This script tests how rotation and scale.y=-1 interact

func _ready():
	print("=== Godot Rotation with Vertical Flip Test ===")
	print("")

	# Test various directions
	var test_cases = [
		{"name": "Right", "dir": Vector2(1, 0), "angle_deg": 0},
		{"name": "Up-Right", "dir": Vector2(1, -1).normalized(), "angle_deg": -45},
		{"name": "Up", "dir": Vector2(0, -1), "angle_deg": -90},
		{"name": "Up-Left", "dir": Vector2(-1, -1).normalized(), "angle_deg": -135},
		{"name": "Left", "dir": Vector2(-1, 0), "angle_deg": 180},
		{"name": "Down-Left", "dir": Vector2(-1, 1).normalized(), "angle_deg": 135},
		{"name": "Down", "dir": Vector2(0, 1), "angle_deg": 90},
		{"name": "Down-Right", "dir": Vector2(1, 1).normalized(), "angle_deg": 45},
	]

	for test in test_cases:
		var dir: Vector2 = test["dir"]
		var angle_rad = dir.angle()
		var angle_deg = rad_to_deg(angle_rad)

		print("Direction: %s, Vector: (%.2f, %.2f)" % [test["name"], dir.x, dir.y])
		print("  Calculated angle: %.1f° (%.3f rad)" % [angle_deg, angle_rad])
		print("  Expected angle: %.1f°" % test["angle_deg"])

		# Test what happens with vertical flip
		var aiming_left = absf(angle_rad) > PI / 2
		if aiming_left:
			print("  Aiming LEFT - would flip vertically and negate angle")
			print("    Negated angle: %.1f° (%.3f rad)" % [rad_to_deg(-angle_rad), -angle_rad])
			print("    With scale.y = -1, this would make sprite face...")
			# When scale.y is negative, the coordinate system is mirrored vertically
			# A rotation of θ with negative scale.y is equivalent to rotation of -θ with positive scale.y
			# So -θ with negative scale.y = -(-θ) = θ with positive scale.y = correct!
		else:
			print("  Aiming RIGHT - normal rotation")
			print("    Angle: %.1f° (%.3f rad)" % [angle_deg, angle_rad])
		print("")

	print("=== Conclusion ===")
	print("In Godot's coordinate system (Y-down):")
	print("- Angle 0° = Right (positive X)")
	print("- Angle -90° = Up (negative Y)")
	print("- Angle 90° = Down (positive Y)")
	print("- Angle ±180° = Left (negative X)")
	print("")
	print("When scale.y = -1 (vertical flip):")
	print("- The sprite is mirrored across the X-axis")
	print("- To maintain the same visual direction, we MUST negate the rotation angle")
	print("- Current code: if aiming_left: global_rotation = -target_angle")
	print("")
