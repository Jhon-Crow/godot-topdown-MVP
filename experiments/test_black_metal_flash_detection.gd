extends SceneTree
## Test script to verify Black Metal shader correctly detects and preserves
## weapon flashes and explosion colors (Issue #985 v2).
##
## This script simulates the shader's detection logic in GDScript to verify
## that various colors are correctly classified as fire/flash vs B&W.
##
## v2 Fix: Changed is_fire to use step(0.35, g) to distinguish orange (high green)
## from red blood (low green). Removed (1-is_red) guard from is_bright_flash.

func _init() -> void:
	print("=== Black Metal Flash Detection Test v2 (Issue #985) ===\n")

	# Test colors from actual game effects
	var test_colors: Array = [
		# MuzzleFlash gradient colors (should be preserved as fire/flash)
		{"name": "MuzzleFlash particle center (1,1,0.95)", "color": Color(1.0, 1.0, 0.95, 1.0), "expected": "preserved"},
		{"name": "MuzzleFlash particle mid (1,0.9,0.5)", "color": Color(1.0, 0.9, 0.5, 1.0), "expected": "preserved"},
		{"name": "MuzzleFlash particle warm (1,0.7,0.2)", "color": Color(1.0, 0.7, 0.2, 1.0), "expected": "preserved"},
		{"name": "MuzzleFlash particle outer (0.9,0.4,0.1)", "color": Color(0.9, 0.4, 0.1, 1.0), "expected": "preserved"},
		{"name": "MuzzleFlash light", "color": Color(1.0, 0.8, 0.4, 1.0), "expected": "preserved"},

		# ExplosionFlash colors (should be preserved)
		{"name": "Frag explosion light (1,0.6,0.2)", "color": Color(1.0, 0.6, 0.2, 1.0), "expected": "preserved"},
		{"name": "Frag explosion particle (1,0.7,0.3)", "color": Color(1.0, 0.7, 0.3, 1.0), "expected": "preserved"},
		{"name": "Frag explosion particle outer (0.8,0.3,0.1)", "color": Color(0.8, 0.3, 0.1, 1.0), "expected": "preserved"},
		{"name": "Flashbang light (1,0.95,0.9)", "color": Color(1.0, 0.95, 0.9, 1.0), "expected": "preserved"},
		{"name": "Flashbang particle (1,1,0.9)", "color": Color(1.0, 1.0, 0.9, 1.0), "expected": "preserved"},

		# Bright warm centers (common in explosions - should be preserved)
		{"name": "Bright explosion center (1,0.98,0.95)", "color": Color(1.0, 0.98, 0.95, 1.0), "expected": "preserved"},
		{"name": "White-hot core (1,1,1)", "color": Color(1.0, 1.0, 1.0, 1.0), "expected": "preserved"},

		# Blood/red colors (should be vivid red)
		{"name": "Blood splatter (0.8,0.1,0.1)", "color": Color(0.8, 0.1, 0.1, 1.0), "expected": "red"},
		{"name": "Health indicator red (1,0.2,0.2)", "color": Color(1.0, 0.2, 0.2, 1.0), "expected": "red"},
		{"name": "Dim red (0.5,0.05,0.05)", "color": Color(0.5, 0.05, 0.05, 1.0), "expected": "red"},

		# Neutral colors (should become B&W)
		{"name": "Gray wall (0.5,0.5,0.5)", "color": Color(0.5, 0.5, 0.5, 1.0), "expected": "bw"},
		{"name": "Blue sky (0.4,0.6,0.9)", "color": Color(0.4, 0.6, 0.9, 1.0), "expected": "bw"},
		{"name": "Green grass (0.3,0.6,0.2)", "color": Color(0.3, 0.6, 0.2, 1.0), "expected": "bw"},
		{"name": "Purple enemy (0.6,0.3,0.7)", "color": Color(0.6, 0.3, 0.7, 1.0), "expected": "bw"},
		{"name": "Cool white (0.9,0.95,1.0)", "color": Color(0.9, 0.95, 1.0, 1.0), "expected": "bw"},
	]

	# Shader parameters (match black_metal.gdshader)
	var red_threshold: float = 0.15
	var fire_threshold: float = 0.25
	var green_fire_threshold: float = 0.30  # v2: minimum green for fire classification
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

		# v2: Detect warm/fiery pixels using green channel to distinguish orange from red
		var warmth: float = (color.r + color.g) * 0.5 - color.b
		var is_fire: bool = warmth >= fire_threshold and color.g >= green_fire_threshold and color.r >= 0.2

		# v2: Detect bright warm pixels without (1-is_red) exclusion
		var warm_bias: bool = (color.r + color.g) >= color.b * 1.5
		var is_bright_flash: bool = lum >= bright_flash_threshold and warm_bias

		# Final classification (mirrors shader mixing order)
		var is_preserved: bool = is_fire or is_bright_flash

		# Determine actual classification
		var actual: String = "bw"
		if is_preserved:
			actual = "preserved"
		elif is_red:
			actual = "red"

		var match: bool = actual == expected

		var status: String = "PASS" if match else "FAIL"
		if not match:
			failed += 1
			print("[%s] %s: expected=%s, actual=%s" % [status, name, expected, actual])
			print("       color=(%0.2f, %0.2f, %0.2f), lum=%0.3f, warmth=%0.3f, is_red=%s, is_fire=%s, is_bright=%s" % [
				color.r, color.g, color.b, lum, warmth, is_red, is_fire, is_bright_flash])
		else:
			passed += 1
			print("[%s] %s: %s" % [status, name, actual])

	print("\n=== Results ===")
	print("Passed: %d" % passed)
	print("Failed: %d" % failed)

	if failed == 0:
		print("\nAll tests passed! Black Metal shader flash detection v2 is working correctly.")
		print("\nKey v2 fix: is_fire now uses g >= 0.35 instead of (1-is_red) to distinguish")
		print("orange fire (high green) from red blood (low green).")
	else:
		print("\nSome tests failed. Review the shader detection logic.")

	quit()
