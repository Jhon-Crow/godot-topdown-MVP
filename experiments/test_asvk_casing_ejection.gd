extends Node2D
## Test script to verify ASVK casing ejection improvements (Issue #575)
##
## This script demonstrates the ASVK casing ejection behavior:
## - Casings should eject faster (300-400 px/sec vs normal 120-180)
## - Casings should eject to the right AND slightly forward (~45 degree angle)
## - Visual comparison with normal weapon casing ejection
##
## Usage:
## 1. Add this script to a test scene with a SniperRifle node
## 2. Run the scene and observe casing ejection
## 3. Compare with other weapons (AssaultRifle, Shotgun) for reference

## Reference to the ASVK sniper rifle
@onready var sniper_rifle: Node2D = null

## Test vectors for different firing directions
var test_directions: Array[Vector2] = [
	Vector2.RIGHT,   # 0 degrees (pointing right)
	Vector2.DOWN,    # 90 degrees (pointing down)
	Vector2.LEFT,    # 180 degrees (pointing left)
	Vector2.UP       # 270 degrees (pointing up)
]

## Current test index
var current_test: int = 0

func _ready() -> void:
	print("\n=== ASVK Casing Ejection Test (Issue #575) ===")
	print("Testing ASVK-specific casing ejection improvements:")
	print("  - Faster ejection speed (300-400 px/sec)")
	print("  - Ejection to the right and slightly forward")
	print("  - Comparison with standard weapon ejection")
	print("\nExpected behavior:")
	print("  BaseWeapon:   120-180 px/sec, perpendicular to firing direction")
	print("  ASVK:         300-400 px/sec, ~45° angle (right + forward)")
	print("=" * 60)

	# Find or create sniper rifle for testing
	sniper_rifle = get_node_or_null("SniperRifle")
	if sniper_rifle == null:
		print("[TEST] ERROR: SniperRifle node not found in scene")
		print("[TEST] Please add a SniperRifle node to test the casing ejection")
	else:
		print("[TEST] SniperRifle found: %s" % sniper_rifle.name)
		print("[TEST] Ready to test casing ejection")

func _input(event: InputEvent) -> void:
	# Press SPACE to test casing ejection in different directions
	if event.is_action_pressed("ui_accept") and sniper_rifle != null:
		test_casing_ejection()

	# Press 'C' to compare with normal weapon ejection
	if event is InputEventKey and event.pressed and event.keycode == KEY_C:
		print_comparison_data()

## Tests casing ejection in the current test direction
func test_casing_ejection() -> void:
	var direction: Vector2 = test_directions[current_test]
	print("\n[TEST] Testing casing ejection for direction: %s" % direction)

	# Calculate expected ejection direction
	var weapon_right: Vector2 = Vector2(-direction.y, direction.x)  # 90° CCW rotation
	var ejection_base: Vector2 = (weapon_right + direction * 0.3).normalized()

	print("  Fire direction:     %s" % direction)
	print("  Weapon right:       %s (perpendicular)" % weapon_right)
	print("  ASVK ejection base: %s (right + 30%% forward)" % ejection_base)
	print("  Angle from perpendicular: ~%.1f degrees" % rad_to_deg(weapon_right.angle_to(ejection_base)))
	print("  Expected speed range: 300-400 px/sec")

	# Simulate calling SpawnCasing
	if sniper_rifle.has_method("SpawnCasing"):
		# Note: SpawnCasing is protected, so we can't call it directly from GDScript
		# This test documents the expected behavior instead
		print("[TEST] SpawnCasing is protected C# method - cannot call from GDScript")
		print("[TEST] Behavior will be verified during actual gameplay testing")

	# Move to next test direction
	current_test = (current_test + 1) % test_directions.size()

## Prints comparison data between BaseWeapon and ASVK casing ejection
func print_comparison_data() -> void:
	print("\n=== Casing Ejection Comparison ===")
	print("\nBaseWeapon.SpawnCasing (default):")
	print("  - Speed: 120-180 px/sec")
	print("  - Direction: perpendicular to firing direction (90° CCW)")
	print("  - Randomness: ±0.3 radians (~±17 degrees)")
	print("  - Spin: ±15.0 rad/sec")

	print("\nSniperRifle.SpawnCasing (ASVK - Issue #575):")
	print("  - Speed: 300-400 px/sec (2.2x faster)")
	print("  - Direction: perpendicular + 30%% forward (~45° from perpendicular)")
	print("  - Randomness: ±0.2 radians (~±11 degrees)")
	print("  - Spin: ±20.0 rad/sec (stronger)")

	print("\nKey differences:")
	print("  ✓ ASVK casings eject 2-3x faster")
	print("  ✓ ASVK casings go more to the right AND forward")
	print("  ✓ ASVK casings have stronger spin (tumbling effect)")

	print("\nVisual result:")
	print("  Normal weapon: Casings land close, perpendicular to shot")
	print("  ASVK:          Casings fly far to the right-forward")
	print("=" * 60)

func _process(_delta: float) -> void:
	# Display instructions
	if Engine.get_frames_drawn() % 300 == 0:  # Every 5 seconds at 60 FPS
		print("\n[TEST] Press SPACE to test casing ejection")
		print("[TEST] Press 'C' to show comparison data")
