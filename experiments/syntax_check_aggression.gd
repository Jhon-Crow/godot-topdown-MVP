# Simple test to verify AggressionComponent syntax
extends Node

func _ready():
	var test_node = Node2D.new()
	add_child(test_node)
	
	# Test 1: Verify AggressionComponent can be instantiated
	var aggression = preload("res://scripts/components/aggression_component.gd").new()
	test_node.add_child(aggression)
	print("✓ AggressionComponent instantiated successfully")
	
	# Test 2: Verify required methods exist
	if aggression.has_method("is_aggressive"):
		print("✓ is_aggressive method exists")
	else:
		print("✗ is_aggressive method missing")
	
	if aggression.has_method("process_combat"):
		print("✓ process_combat method exists")
	else:
		print("✗ process_combat method missing")
	
	if aggression.has_method("set_aggressive"):
		print("✓ set_aggressive method exists")
	else:
		print("✗ set_aggressive method missing")
	
	# Test 3: Test basic functionality
	aggression.set_aggressive(true)
	if aggression.is_aggressive():
		print("✓ set_aggressive works")
	else:
		print("✗ set_aggressive failed")
	
	# Test 4: Test process_combat with minimal setup
	test_node.velocity = Vector2.ZERO
	aggression.process_combat(0.016, 25.0, 0.1, 300.0)
	
	# Should not crash and velocity should remain zero since no target
	print("✓ process_combat executed without crash")
	
	# Clean up
	test_node.queue_free()
	print("✓ AggressionComponent syntax check complete")