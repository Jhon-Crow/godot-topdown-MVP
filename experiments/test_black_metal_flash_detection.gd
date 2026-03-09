extends SceneTree
## Test script to verify Black Metal shader correctly detects and preserves
## weapon flashes and explosion colors (Issue #985).
##
## This script simulates the shader's detection logic in GDScript to verify
## that various colors are correctly classified as fire/flash vs B&W.

func _init() -> void:
	print("=== Black Metal Flash Detection Test (Issue #985) ===\n")

	# Test colors from actual game effects
	var test_colors: Array = [
		# MuzzleFlash colors (should be preserved as fire/flash)
		{"name": "MuzzleFlash particle", "color": Color(1.0, 0.9, 0.5, 1.0), "expected": "fire"},
		{"name": "MuzzleFlash light", "color": Color(1.0, 0.8, 0.4, 1.0), "expected": "fire"},

		# ExplosionFlash colors (should be preserved)
		{"name": "Frag explosion light", "color": Color(1.0, 0.6, 0.2, 1.0), "expected": "fire"},
		{"name": "Frag explosion particle", "color": Color(1.0, 0.7, 0.3, 1.0), "expected": "fire"},
		{"name": "Flashbang light", "color": Color(1.0, 0.95, 0.9, 1.0), "expected": "bright_flash"},
		{"name": "Flashbang particle", "color": Color(1.0, 1.0, 0.9, 1.0), "expected": "bright_flash"},

		# Bright warm centers (common in explosions - should be preserved)
		{"name": "Bright explosion center", "color": Color(1.0, 0.98, 0.95, 1.0), "expected": "bright_flash"},
		{"name": "White-hot core", "color": Color(1.0, 1.0, 1.0, 1.0), "expected": "bright_flash"},

		# Blood/red colors (should be vivid red)
		{"name": "Blood splatter", "color": Color(0.8, 0.1, 0.1, 1.0), "expected": "red"},
		{"name": "Health indicator red", "color": Color(1.0, 0.2, 0.2, 1.0), "expected": "red"},

		# Neutral colors (should become B&W)
		{"name": "Gray wall", "color": Color(0.5, 0.5, 0.5, 1.0), "expected": "bw"},
		{"name": "Blue sky", "color": Color(0.4, 0.6, 0.9, 1.0), "expected": "bw"},
		{"name": "Green grass", "color": Color(0.3, 0.6, 0.2, 1.0), "expected": "bw"},
		{"name": "Purple enemy", "color": Color(0.6, 0.3, 0.7, 1.0), "expected": "bw"},

		# Edge cases
		{"name": "Dim orange", "color": Color(0.4, 0.2, 0.1, 1.0), "expected": "fire"},
		{"name": "Pure white", "color": Color(1.0, 1.0, 1.0, 1.0), "expected": "bright_flash"},
		{"name": "Warm white", "color": Color(1.0, 0.9, 0.8, 1.0), "expected": "bright_flash"},
		{"name": "Cool white", "color": Color(0.9, 0.95, 1.0, 1.0), "expected": "bw"},
	]

	# Shader parameters
	var red_threshold: float = 0.15
	var fire_threshold: float = 0.25
	var bright_flash_threshold: float = 0.85

	var passed: int = 0
	var failed: int = 0

	for test in test_colors:
		var color: Color = test["color"]
		var expected: String = test["expected"]
		var name: String = test["name"]

		# Calculate luminance
		var lum: float = color.r * 0.299 + color.g * 0.587 + color.b * 0.114

		# Detect red-ish pixels
		var red_dominance: float = color.r - maxf(color.g, color.b)
		var is_red: bool = red_dominance >= red_threshold and color.r >= 0.1

		# Detect warm/fiery pixels
		var warmth: float = (color.r + color.g) * 0.5 - color.b
		var is_fire: bool = warmth >= fire_threshold and color.r >= 0.2 and not is_red

		# Detect bright warm pixels (Issue #985 fix)
		var warm_bias: bool = (color.r + color.g) >= color.b * 1.5
		var is_bright_flash: bool = lum >= bright_flash_threshold and warm_bias and not is_red

		# Determine actual classification
		var actual: String = "bw"
		if is_red:
			actual = "red"
		elif is_fire or is_bright_flash:
			if is_bright_flash and not is_fire:
				actual = "bright_flash"
			else:
				actual = "fire"

		var match: bool = (actual == expected) or (expected == "bright_flash" and actual == "fire") or (expected == "fire" and actual == "bright_flash")

		var status: String = "PASS" if match else "FAIL"
		if not match:
			failed += 1
			print("[%s] %s: expected=%s, actual=%s" % [status, name, expected, actual])
			print("       color=(%0.2f, %0.2f, %0.2f), lum=%0.3f, warmth=%0.3f" % [color.r, color.g, color.b, lum, warmth])
		else:
			passed += 1
			print("[%s] %s: %s" % [status, name, actual])

	print("\n=== Results ===")
	print("Passed: %d" % passed)
	print("Failed: %d" % failed)

	if failed == 0:
		print("\nAll tests passed! Black Metal shader flash detection is working correctly.")
	else:
		print("\nSome tests failed. Review the shader detection logic.")

	quit()
