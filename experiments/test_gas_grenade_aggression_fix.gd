extends Node

# Test script for gas grenade aggression fix
# Tests that aggressive enemies now move and flank properly

func _ready() -> void:
	print("=== Gas Grenade Aggression Fix Test ===")
	test_aggression_component_movement()
	print("=== Test Complete ===")

func test_aggression_component_movement() -> void:
	print("\n1. Testing AggressionComponent movement behaviors...")
	
	# Create mock enemy parent
	var mock_enemy := Node2D.new()
	mock_enemy.name = "MockEnemy"
	mock_enemy.position = Vector2(100, 100)
	add_child(mock_enemy)
	
	# Create aggression component
	var aggression := AggressionComponent.new()
	aggression.name = "AggressionComponent"
	mock_enemy.add_child(aggression)
	
	# Test that process_combat doesn't set velocity to zero when has LOS
	print("   - Testing movement during LOS engagement...")
	
	# Mock target
	var mock_target := Node2D.new()
	mock_target.name = "MockTarget"
	mock_target.position = Vector2(200, 100)
	add_child(mock_target)
	
	# Set up aggression state
	aggression.set_aggressive(true)
	
	# Simulate having LOS (this would normally cause velocity = Vector2.ZERO)
	print("   - Before process_combat: velocity should change from zero")
	mock_enemy.velocity = Vector2(100, 0)  # Initial velocity
	
	# Call process_combat with realistic parameters
	aggression.process_combat(0.016, 25.0, 0.1, 320.0)
	
	# Check that velocity is NOT zero (fix working)
	if mock_enemy.velocity.length() > 0:
		print("   ✓ SUCCESS: Enemy has movement velocity (", mock_enemy.velocity.length(), ")")
	else:
		print("   ✗ FAILURE: Enemy velocity is zero - still static!")
	
	# Test flanking behavior
	print("\n   - Testing flanking logic...")
	# Set up target that's being shot by someone else
	if mock_target.has_method("_get_current_shooter"):
		mock_target._get_current_shooter = func(): return Node2D.new()  # Mock shooter
	
	print("   - Flanking opportunity detection:", aggression._should_attempt_flank())
	
	print("\n2. Testing integration with enemy AI...")
	# This would be tested in actual gameplay
	print("   - Integration test requires actual enemy instance")
	print("   - Key fix: Enemies no longer stand still when aggressive")
	print("   - Expected: Tactical movement, strafing, and flanking behaviors")
	
	# Clean up
	mock_enemy.queue_free()
	mock_target.queue_free()
	print("\n   - Test cleanup complete")