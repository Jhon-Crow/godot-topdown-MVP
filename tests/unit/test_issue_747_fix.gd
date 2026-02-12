extends GutTest

# Unit tests for Issue #747: Fix revolver cylinder display color bug
# Tests that the highlighted slot is red only when hammer is cocked,
# not after firing when hammer should be uncocked.

class MockRevolverIssue747:
	# Hammer state
	var is_hammer_cocked: bool = false
	var is_manually_hammer_cocked: bool = false
	
	# Cylinder state
	var chamber_occupied: Array[bool] = [true, true, true, true, true]
	var current_chamber_index: int = 0
	var current_ammo: int = 5
	
	# Signal tracking
	var cylinder_state_changed_emitted: bool = false
	var signal_count: int = 0
	
	# Mock methods
	func is_any_hammer_cocked() -> bool:
		return is_hammer_cocked or is_manually_hammer_cocked
	
	func simulate_normal_fire() -> bool:
		# Simulate normal fire sequence: cock -> delay -> uncock
		is_hammer_cocked = true
		cylinder_state_changed_emitted = true
		signal_count += 1
		
		# Simulate shot completion (hammer becomes uncocked)
		is_hammer_cocked = false
		cylinder_state_changed_emitted = true
		signal_count += 1
		
		return true
	
	func simulate_manual_cock_fire() -> bool:
		# Simulate manual cock: cock -> fire -> uncock
		is_manually_hammer_cocked = true
		cylinder_state_changed_emitted = true
		signal_count += 1
		
		# Check chamber
		if not chamber_occupied[current_chamber_index]:
			# Empty chamber - uncock without shot
			is_manually_hammer_cocked = false
			cylinder_state_changed_emitted = true
			signal_count += 1
			return true
		
		# Fire shot
		chamber_occupied[current_chamber_index] = false
		current_ammo -= 1
		is_manually_hammer_cocked = false
		cylinder_state_changed_emitted = true
		signal_count += 1
		
		return true
	
	func simulate_empty_chamber_manual_cock() -> bool:
		# Set up empty chamber scenario
		chamber_occupied = [false, false, false, false, false]
		current_ammo = 0
		current_chamber_index = 0
		
		# Manual cock on empty chamber
		is_manually_hammer_cocked = true
		cylinder_state_changed_emitted = true
		signal_count += 1
		
		# Try to fire - should click and uncock
		is_manually_hammer_cocked = false
		cylinder_state_changed_emitted = true
		signal_count += 1
		
		return true
	
	func reset_tracking() -> void:
		cylinder_state_changed_emitted = false
		signal_count = 0

class MockCylinderUIIssue747:
	var revolver_ref: MockRevolverIssue747
	var last_ui_hammer_state: bool = false
	
	func _init(revolver: MockRevolverIssue747):
		revolver_ref = revolver
	
	func update_from_revolver() -> void:
		last_ui_hammer_state = revolver_ref.is_any_hammer_cocked()
	
	func should_be_red() -> bool:
		return last_ui_hammer_state
	
	func should_be_yellow() -> bool:
		return not last_ui_hammer_state

var revolver: MockRevolverIssue747
var cylinder_ui: MockCylinderUIIssue747

func before_each() -> void:
	revolver = MockRevolverIssue747.new()
	cylinder_ui = MockCylinderUIIssue747.new(revolver)

func after_each() -> void:
	revolver = null
	cylinder_ui = null

# ============================================================================
# Issue #747: Fix revolver cylinder display color bug
# ============================================================================

func test_initial_state_is_yellow() -> void:
	# Initially, hammer should not be cocked, so slot should be yellow
	revolver.reset_tracking()
	cylinder_ui.update_from_revolver()
	
	assert_false(cylinder_ui.should_be_red(), "Initial state: slot should be yellow (hammer not cocked)")
	assert_true(cylinder_ui.should_be_yellow(), "Initial state: should be yellow")
	assert_false(revolver.is_any_hammer_cocked(), "Hammer should not be cocked initially")

func test_normal_fire_sequence_color_changes() -> void:
	# Test normal fire: cock (red) -> uncock (yellow)
	revolver.reset_tracking()
	
	# Step 1: Fire starts - hammer becomes cocked (should be red)
	var fire_result = revolver.simulate_normal_fire()
	assert_true(fire_result, "Fire should succeed")
	assert_true(revolver.cylinder_state_changed_emitted, "Should emit state changed")
	assert_eq(revolver.signal_count, 2, "Should emit 2 signals: cock and uncock")
	
	# After fire completes, hammer should be uncocked (should be yellow)
	cylinder_ui.update_from_revolver()
	assert_false(cylinder_ui.should_be_red(), "After fire: slot should be yellow (hammer uncocked)")
	assert_true(cylinder_ui.should_be_yellow(), "After fire: should be yellow")
	assert_false(revolver.is_any_hammer_cocked(), "Hammer should be uncocked after fire")

func test_manual_cock_fire_sequence_color_changes() -> void:
	# Test manual cock fire: cock (red) -> fire -> uncock (yellow)
	revolver.reset_tracking()
	
	var fire_result = revolver.simulate_manual_cock_fire()
	assert_true(fire_result, "Manual cock fire should succeed")
	assert_true(revolver.cylinder_state_changed_emitted, "Should emit state changed")
	assert_eq(revolver.signal_count, 2, "Should emit 2 signals: cock and uncock")
	
	# After fire completes, hammer should be uncocked (should be yellow)
	cylinder_ui.update_from_revolver()
	assert_false(cylinder_ui.should_be_red(), "After manual cock fire: slot should be yellow")
	assert_true(cylinder_ui.should_be_yellow(), "After manual cock fire: should be yellow")
	assert_false(revolver.is_any_hammer_cocked(), "Hammer should be uncocked after fire")

func test_empty_chamber_manual_cock_color_changes() -> void:
	# Test manual cock on empty chamber: cock (red) -> click -> uncock (yellow)
	revolver.reset_tracking()
	
	var click_result = revolver.simulate_empty_chamber_manual_cock()
	assert_true(click_result, "Empty chamber manual cock should succeed")
	assert_true(revolver.cylinder_state_changed_emitted, "Should emit state changed")
	assert_eq(revolver.signal_count, 2, "Should emit 2 signals: cock and uncock")
	
	# After click, hammer should be uncocked (should be yellow)
	cylinder_ui.update_from_revolver()
	assert_false(cylinder_ui.should_be_red(), "After empty click: slot should be yellow")
	assert_true(cylinder_ui.should_be_yellow(), "After empty click: should be yellow")
	assert_false(revolver.is_any_hammer_cocked(), "Hammer should be uncocked after empty click")

func test_multiple_fires_stay_yellow() -> void:
	# Test multiple fires - after each, slot should be yellow
	revolver.reset_tracking()
	
	# First shot
	revolver.simulate_normal_fire()
	cylinder_ui.update_from_revolver()
	assert_false(cylinder_ui.should_be_red(), "After 1st shot: should be yellow")
	
	# Second shot
	revolver.simulate_normal_fire()
	cylinder_ui.update_from_revolver()
	assert_false(cylinder_ui.should_be_red(), "After 2nd shot: should be yellow")
	
	# Third shot
	revolver.simulate_normal_fire()
	cylinder_ui.update_from_revolver()
	assert_false(cylinder_ui.should_be_red(), "After 3rd shot: should be yellow")

func test_manual_cock_during_empty_cylinder() -> void:
	# Test manual cock with completely empty cylinder
	revolver.current_ammo = 0
	revolver.chamber_occupied = [false, false, false, false, false]
	revolver.reset_tracking()
	
	# Manual cock should still work (allow cocking even on empty)
	revolver.is_manually_hammer_cocked = true
	cylinder_ui.update_from_revolver()
	
	assert_true(cylinder_ui.should_be_red(), "Manual cock on empty cylinder: should be red while cocked")
	assert_true(revolver.is_any_hammer_cocked(), "Hammer should be cocked")
	
	# Fire should click and uncock
	revolver.is_manually_hammer_cocked = false
	cylinder_ui.update_from_revolver()
	
	assert_false(cylinder_ui.should_be_red(), "After empty click: should be yellow")
	assert_false(revolver.is_any_hammer_cocked(), "Hammer should be uncocked")

func test_cylinder_state_change_signal_always_emitted() -> void:
	# Test that CylinderStateChanged is always emitted when hammer state changes
	revolver.reset_tracking()
	
	# Normal fire
	revolver.simulate_normal_fire()
	assert_gt(revolver.signal_count, 0, "Normal fire should emit signals")
	
	# Reset and test manual cock
	revolver.reset_tracking()
	revolver.simulate_manual_cock_fire()
	assert_gt(revolver.signal_count, 0, "Manual cock fire should emit signals")
	
	# Reset and test empty chamber
	revolver.reset_tracking()
	revolver.simulate_empty_chamber_manual_cock()
	assert_gt(revolver.signal_count, 0, "Empty chamber manual cock should emit signals")