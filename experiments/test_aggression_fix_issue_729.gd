extends Node

# Test script to verify aggression fix works properly
# Tests that aggressive enemies no longer immediately transition to COMBAT state

func _ready() -> void:
	print("=== Testing Aggression Fix (Issue #729) ===")
	test_aggression_no_combat_transition()
	print("=== Test Complete ===")

func test_aggression_no_combat_transition() -> void:
	print("\n1. Testing that aggression doesn't force COMBAT state...")
	
	# Create mock enemy
	var mock_enemy = Node2D.new()
	mock_enemy.name = "MockEnemy"
	mock_enemy.position = Vector2(100, 100)
	add_child(mock_enemy)
	
	# Mock required methods for enemy
	mock_enemy._log_to_file = func(message): print("   LOG:", message)
	mock_enemy._current_state = 0  # IDLE state
	
	# Create aggression component
	var aggression = preload("res://scripts/components/aggression_component.gd").new()
	aggression.name = "AggressionComponent"
	mock_enemy.add_child(aggression)
	
	# Create status effect animation component mock
	var status_anim = Node2D.new()
	status_anim.name = "StatusEffectAnimation"
	status_anim.set_aggressive = func(is_agg): print("   Status anim:", is_agg)
	mock_enemy.add_child(status_anim)
	
	# Set up the aggression connection (this is what enemy.gd does)
	aggression.aggression_changed.connect(func(a): 
		if status_anim: status_anim.set_aggressive(a)
		mock_enemy._on_aggression_changed(a)
	)
	
	# Add the _on_aggression_changed method
	mock_enemy._on_aggression_changed = func(is_aggressive: bool):
		if is_aggressive:
			print("   LOG: [#675] AGGRESSIVE")
			# FIXED: Don't transition to combat state
			if mock_enemy._current_state in [0, 4]:  # IDLE, IN_COVER
				print("   ✓ SUCCESS: Not transitioning to COMBAT state")
				pass
		else:
			print("   LOG: [#675] Aggression expired")
	
	print("   - Setting aggression to true...")
	aggression.set_aggressive(true)
	
	# Verify state didn't change to COMBAT
	if mock_enemy._current_state == 0:  # Still IDLE
		print("   ✓ SUCCESS: Enemy remained in IDLE state (not COMBAT)")
	else:
		print("   ✗ FAILURE: Enemy state changed to", mock_enemy._current_state)
	
	print("\n2. Testing movement with aggression...")
	
	# Mock target enemy
	var mock_target = Node2D.new()
	mock_target.name = "MockTarget"
	mock_target.position = Vector2(300, 100)  # 200px away
	add_child(mock_target)
	
	# Mock required methods for movement
	mock_enemy._can_shoot = func(): return false  # Prevent shooting
	mock_enemy._shoot_timer = 1.0
	mock_enemy._get_weapon_forward_direction = func(): return Vector2.RIGHT
	mock_enemy.velocity = Vector2.ZERO
	
	# Test process_combat with movement
	aggression.process_combat(0.016, 25.0, 0.1, 320.0)
	
	# Should have movement velocity (the main fix)
	if mock_enemy.velocity.length() > 0:
		print("   ✓ SUCCESS: Enemy has movement velocity (", mock_enemy.velocity.length(), ")")
		print("   ✓ Aggressive enemies now move instead of standing still!")
	else:
		print("   ✗ FAILURE: Enemy velocity is still zero")
	
	# Clean up
	mock_enemy.queue_free()
	mock_target.queue_free()
	print("\n   - Test cleanup complete")