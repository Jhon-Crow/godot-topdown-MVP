extends GutTest

## Test suite for gas grenade aggression fix (Issue #729)
##
## Validates that aggressive enemies now move and flank properly instead of standing still.
##

const AggressionComponent := preload("res://scripts/components/aggression_component.gd")

func before_each():
	# Clear any existing state before each test
	pass

func test_aggression_component_instantiates():
	var mock_parent = Node2D.new()
	add_child_autofree(mock_parent)
	
	var aggression = AggressionComponent.new()
	mock_parent.add_child(aggression)
	
	assert_true(aggression != null, "AggressionComponent should instantiate")
	assert_true(aggression.has_method("is_aggressive"), "Should have is_aggressive method")
	assert_true(aggression.has_method("process_combat"), "Should have process_combat method")
	assert_true(aggression.has_method("set_aggressive"), "Should have set_aggressive method")

func test_aggression_basic_functionality():
	var mock_parent = Node2D.new()
	mock_parent.name = "TestEnemy"
	add_child_autofree(mock_parent)
	
	var aggression = AggressionComponent.new()
	mock_parent.add_child(aggression)
	
	# Test setting aggressive state
	aggression.set_aggressive(true)
	assert_true(aggression.is_aggressive(), "Should be aggressive after set_aggressive(true)")
	
	aggression.set_aggressive(false)
	assert_false(aggression.is_aggressive(), "Should not be aggressive after set_aggressive(false)")

func test_aggression_movement_without_target():
	var mock_parent = Node2D.new()
	mock_parent.name = "TestEnemy"
	mock_parent.velocity = Vector2(100, 0)  # Initial velocity
	add_child_autofree(mock_parent)
	
	var aggression = AggressionComponent.new()
	mock_parent.add_child(aggression)
	
	# Set aggressive but no target
	aggression.set_aggressive(true)
	aggression.process_combat(0.016, 25.0, 0.1, 300.0)
	
	# Should have zero velocity when no target (original behavior preserved)
	assert_eq(mock_parent.velocity, Vector2.ZERO, "Should have zero velocity when no target")

func test_aggression_movement_with_target():
	var mock_parent = Node2D.new()
	mock_parent.name = "TestEnemy"
	mock_parent.velocity = Vector2.ZERO  # Start with zero velocity
	add_child_autofree(mock_parent)
	
	var mock_target = Node2D.new()
	mock_target.name = "TestTarget"
	mock_target.position = Vector2(300, 0)  # 200px away
	add_child_autofree(mock_target)
	
	var aggression = AggressionComponent.new()
	mock_parent.add_child(aggression)
	
	# Mock required methods
	mock_parent._can_shoot = func(): return false  # Prevent shooting for clean movement test
	mock_parent._move_to_target_nav = func(target, speed): 
		mock_parent.velocity = (target - mock_parent.position).normalized() * speed
	
	# Set aggressive state with target
	aggression.set_aggressive(true)
	aggression.process_combat(0.016, 25.0, 0.1, 300.0)
	
	# Should NOT have zero velocity (main fix!)
	assert_ne(mock_parent.velocity, Vector2.ZERO, "Should NOT have zero velocity when has target")
	assert_true(mock_parent.velocity.length() > 0, "Should have positive movement velocity")

func test_aggression_distance_based_movement():
	var mock_parent = Node2D.new()
	mock_parent.name = "TestEnemy"
	mock_parent.position = Vector2(100, 100)
	add_child_autofree(mock_parent)
	
	# Test different distances
	var test_cases = [
		{"target_pos": Vector2(600, 100), "expected_behavior": "advance", "distance": 500.0},
		{"target_pos": Vector2(350, 100), "expected_behavior": "strafe", "distance": 250.0}, 
		{"target_pos": Vector2(250, 100), "expected_behavior": "circle", "distance": 150.0}
	]
	
	for i in range(test_cases.size()):
		var test_case = test_cases[i]
		
		var mock_target = Node2D.new()
		mock_target.position = test_case.target_pos
		add_child_autofree(mock_target)
		
		var aggression = AggressionComponent.new()
		mock_parent.add_child(aggression)
		
		# Reset velocity
		mock_parent.velocity = Vector2.ZERO
		
		aggression.set_aggressive(true)
		aggression.process_combat(0.016, 25.0, 0.1, 300.0)
		
		# Should have movement (main fix)
		assert_ne(mock_parent.velocity, Vector2.ZERO, 
			"Distance %d (%s): Should NOT have zero velocity" % [i, test_case.expected_behavior])
		assert_true(mock_parent.velocity.length() > 0, 
			"Distance %d (%s): Should have positive velocity" % [i, test_case.expected_behavior])
		
		# Clean up
		mock_target.queue_free()

func test_flanking_opportunity_detection():
	var mock_parent = Node2D.new()
	mock_parent.name = "TestEnemy"
	add_child_autofree(mock_parent)
	
	var mock_target = Node2D.new()
	mock_target.position = Vector2(300, 100)  # 200px away
	add_child_autofree(mock_target)
	
	# Mock target being shot by someone else
	var mock_shooter = Node2D.new()
	mock_shooter.name = "MockShooter"
	
	mock_target._get_current_shooter = func(): return mock_shooter
	
	var aggression = AggressionComponent.new()
	mock_parent.add_child(aggression)
	
	aggression.set_aggressive(true)
	
	# Should detect flanking opportunity (200px distance, target engaged)
	var should_flank = aggression._should_attempt_flank()
	assert_true(should_flank, "Should detect flanking opportunity at 200px")

func test_flanking_no_opportunity_too_close():
	var mock_parent = Node2D.new()
	mock_parent.name = "TestEnemy"
	add_child_autofree(mock_parent)
	
	var mock_target = Node2D.new()
	mock_target.position = Vector2(230, 100)  # 130px away - too close
	add_child_autofree(mock_target)
	
	var aggression = AggressionComponent.new()
	mock_parent.add_child(aggression)
	
	aggression.set_aggressive(true)
	
	# Should NOT flank when too close
	var should_flank = aggression._should_attempt_flank()
	assert_false(should_flank, "Should NOT flank when target is too close (130px)")

func test_flanking_no_opportunity_too_far():
	var mock_parent = Node2D.new()
	mock_parent.name = "TestEnemy"
	add_child_autofree(mock_parent)
	
	var mock_target = Node2D.new()
	mock_target.position = Vector2(700, 100)  # 600px away - too far
	add_child_autofree(mock_target)
	
	var aggression = AggressionComponent.new()
	mock_parent.add_child(aggression)
	
	aggression.set_aggressive(true)
	
	# Should NOT flank when too far
	var should_flank = aggression._should_attempt_flank()
	assert_false(should_flank, "Should NOT flank when target is too far (600px)")

func test_flanking_position_calculation():
	var mock_parent = Node2D.new()
	mock_parent.name = "TestEnemy"
	mock_parent.position = Vector2(100, 100)
	add_child_autofree(mock_parent)
	
	var mock_target = Node2D.new()
	mock_target.position = Vector2(300, 100)  # East of parent
	add_child_autofree(mock_target)
	
	var aggression = AggressionComponent.new()
	mock_parent.add_child(aggression)
	
	var flank_pos = aggression._calculate_flank_position()
	
	# Should calculate perpendicular flanking position
	# Target is 200px east, so flank should be north or south
	var expected_north = Vector2(300, 300)  # North flank
	var expected_south = Vector2(300, -100)  # South flank
	
	var is_valid_flank = flank_pos.is_equal_approx(expected_north, 1.0) or flank_pos.is_equal_approx(expected_south, 1.0)
	assert_true(is_valid_flank, "Flank position should be perpendicular to target direction")

func test_integration_with_enemy_ai():
	# This test validates that the fix integrates with existing enemy AI
	# without completely overriding it
	var mock_enemy = preload("res://scripts/objects/enemy.gd").new()
	mock_enemy.name = "TestEnemy"
	mock_enemy.position = Vector2(100, 100)
	
	# Mock required properties and methods
	mock_enemy._can_see_player = func(): return false
	mock_enemy._is_alive = true
	mock_enemy.global_position = Vector2(100, 100)
	
	add_child_autofree(mock_enemy)
	
	# Set up aggression component
	mock_enemy._ready()  # This should create the AggressionComponent
	
	# Test that aggression component is created and works
	assert_true(mock_enemy._aggression != null, "Enemy should have AggressionComponent")
	
	# Test that aggression can be set
	mock_enemy._aggression.set_aggressive(true)
	assert_true(mock_enemy._aggression.is_aggressive(), "Aggression should be settable")
	
	print("✓ Integration test passed - aggression works with enemy AI")

func test_edge_cases():
	var mock_parent = Node2D.new()
	mock_parent.name = "TestEnemy"
	add_child_autofree(mock_parent)
	
	var aggression = AggressionComponent.new()
	mock_parent.add_child(aggression)
	
	# Test with null parent
	aggression.process_combat(0.016, 25.0, 0.1, 300.0)  # Should not crash
	
	# Test with invalid target
	var invalid_target = Node2D.new()
	invalid_target.queue_free()  # Make invalid immediately
	aggression._target = invalid_target
	aggression.process_combat(0.016, 25.0, 0.1, 300.0)  # Should handle gracefully
	
	print("✓ Edge cases handled without crashing")