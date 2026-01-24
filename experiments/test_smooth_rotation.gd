extends Node2D
## Test script for smooth enemy rotation (Issue #347)
##
## This script demonstrates the smooth rotation behavior.
## Place this script on a Node2D in a test scene with an Enemy to verify the rotation.

@export var enemy: CharacterBody2D  ## Reference to enemy to test
@export var test_duration: float = 5.0  ## How long to run each test
@export var rotation_speed: float = 3.0  ## MODEL_ROTATION_SPEED from enemy.gd

var test_timer: float = 0.0
var current_test: int = 0
var start_angle: float = 0.0
var target_angle: float = 0.0

func _ready() -> void:
	if enemy:
		print("[SmoothRotationTest] Starting smooth rotation tests")
		print("[SmoothRotationTest] Rotation speed: %.2f rad/s (%.1f deg/s)" % [rotation_speed, rad_to_deg(rotation_speed)])
		_start_test_0()
	else:
		print("[SmoothRotationTest] ERROR: No enemy reference set!")

func _process(delta: float) -> void:
	if not enemy:
		return

	test_timer += delta

	match current_test:
		0:  # Test 180-degree rotation
			if test_timer >= test_duration:
				_start_test_1()
		1:  # Test continuous rotation
			if test_timer >= test_duration:
				_start_test_2()
		2:  # Test rapid direction changes
			if test_timer >= test_duration:
				print("[SmoothRotationTest] All tests completed!")
				current_test = -1

func _start_test_0() -> void:
	print("\n[SmoothRotationTest] Test 0: 180-degree rotation")
	print("[SmoothRotationTest] Expected time: %.2f seconds" % (PI / rotation_speed))
	current_test = 0
	test_timer = 0.0
	start_angle = 0.0
	target_angle = PI
	print("[SmoothRotationTest] Start angle: %.2f rad (%.1f deg)" % [start_angle, rad_to_deg(start_angle)])
	print("[SmoothRotationTest] Target angle: %.2f rad (%.1f deg)" % [target_angle, rad_to_deg(target_angle)])

func _start_test_1() -> void:
	print("\n[SmoothRotationTest] Test 1: Continuous 360-degree rotation")
	print("[SmoothRotationTest] Expected time: %.2f seconds" % (TAU / rotation_speed))
	current_test = 1
	test_timer = 0.0
	start_angle = enemy.rotation if enemy else 0.0
	target_angle = start_angle + TAU
	print("[SmoothRotationTest] Start angle: %.2f rad (%.1f deg)" % [start_angle, rad_to_deg(start_angle)])

func _start_test_2() -> void:
	print("\n[SmoothRotationTest] Test 2: Rapid direction changes (90 degrees)")
	print("[SmoothRotationTest] Expected time per change: %.2f seconds" % (PI / 2.0 / rotation_speed))
	current_test = 2
	test_timer = 0.0
	print("[SmoothRotationTest] Will alternate between 0, 90, 180, 270 degrees")

## Calculate expected rotation for current delta time
func _expected_rotation_delta(delta: float, angle_diff: float) -> float:
	var max_rotation := rotation_speed * delta
	if abs(angle_diff) <= max_rotation:
		return angle_diff
	elif angle_diff > 0:
		return max_rotation
	else:
		return -max_rotation

## Log rotation progress
func _physics_process(_delta: float) -> void:
	if enemy and current_test >= 0:
		var progress_marker := int(test_timer * 10) % 10
		if progress_marker == 0:
			var current_angle := enemy.rotation if enemy else 0.0
			print("[SmoothRotationTest] t=%.1fs: rotation=%.2f rad (%.1f deg)" % [test_timer, current_angle, rad_to_deg(current_angle)])
