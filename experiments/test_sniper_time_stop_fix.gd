## Experiment: Validate sniper rifle time-stop fix logic (Issue #977)
##
## This script validates the logic flow of the deferred sniper hitscan approach.
## Run with: godot --headless --script experiments/test_sniper_time_stop_fix.gd
##
## The fix ensures that when the player fires the sniper rifle during stopped time
## (LastChanceEffectsManager active), the damage is deferred until time unfreezes,
## and the tracer remains visible (frozen) during the time-stop.

extends SceneTree

## Simulates the LastChanceEffectsManager's is_effect_active behavior
var _time_stop_active: bool = false

## Simulates the SniperRifle's pending shots list
var _pending_sniper_shots: Array = []

## Simulates the frozen tracers list
var _frozen_sniper_tracers: Array = []

## Track if damage was applied (for assertion)
var _damage_applied_count: int = 0

## Track when damage was applied
var _damage_applied_during_freeze: bool = false

func _init() -> void:
	print("=== Test: Sniper Rifle Time-Stop Fix (Issue #977) ===")
	print("")

	_test_normal_fire()
	_test_fire_during_time_stop()
	_test_deferred_damage_on_unfreeze()
	_test_no_pending_shots_after_unfreeze()
	_test_multiple_shots_during_freeze()

	print("")
	print("=== All tests passed! ===")
	quit(0)


## Test 1: Normal fire (no time stop) - damage applied immediately
func _test_normal_fire() -> void:
	print("Test 1: Normal fire (no time stop)")
	_time_stop_active = false
	_damage_applied_count = 0

	# Simulate firing when time is NOT stopped
	var result = _simulate_sniper_fire()

	assert(result == "hitscan_immediate", "Expected immediate hitscan, got: %s" % result)
	print("  PASS: Normal fire applies damage immediately")


## Test 2: Fire during time stop - damage deferred
func _test_fire_during_time_stop() -> void:
	print("Test 2: Fire during time stop - damage deferred")
	_time_stop_active = true
	_pending_sniper_shots.clear()
	_frozen_sniper_tracers.clear()

	# Simulate firing when time IS stopped
	var result = _simulate_sniper_fire()

	assert(result == "shot_deferred", "Expected deferred shot, got: %s" % result)
	assert(_pending_sniper_shots.size() == 1, "Expected 1 pending shot, got: %d" % _pending_sniper_shots.size())
	print("  PASS: Shot deferred during time stop, %d pending shot(s)" % _pending_sniper_shots.size())


## Test 3: Deferred damage applied when time unfreezes
func _test_deferred_damage_on_unfreeze() -> void:
	print("Test 3: Deferred damage applied when time unfreezes")
	_time_stop_active = true
	_pending_sniper_shots.clear()
	_damage_applied_count = 0

	# Fire during time stop
	_simulate_sniper_fire()
	assert(_pending_sniper_shots.size() == 1, "Should have 1 pending shot")
	assert(_damage_applied_count == 0, "Damage should NOT be applied yet")

	# Unfreeze time
	_time_stop_active = false
	_simulate_unfreeze()

	assert(_damage_applied_count == 1, "Damage should be applied after unfreeze, got: %d" % _damage_applied_count)
	assert(_pending_sniper_shots.size() == 0, "Pending shots should be cleared after execution")
	print("  PASS: Damage applied on unfreeze, pending shots cleared")


## Test 4: No pending shots remain after unfreeze
func _test_no_pending_shots_after_unfreeze() -> void:
	print("Test 4: No pending shots remain after unfreeze")
	_time_stop_active = true
	_pending_sniper_shots.clear()

	_simulate_sniper_fire()

	_time_stop_active = false
	_simulate_unfreeze()

	assert(_pending_sniper_shots.size() == 0, "No pending shots should remain after unfreeze")
	print("  PASS: Pending shots cleared after unfreeze")


## Test 5: Multiple shots during freeze all execute on unfreeze
func _test_multiple_shots_during_freeze() -> void:
	print("Test 5: Multiple shots during freeze all execute on unfreeze")
	_time_stop_active = true
	_pending_sniper_shots.clear()
	_damage_applied_count = 0

	# Fire multiple times during freeze (normally requires bolt cycling, but testing logic)
	_simulate_sniper_fire()
	_simulate_sniper_fire()
	_simulate_sniper_fire()

	assert(_pending_sniper_shots.size() == 3, "Expected 3 pending shots, got: %d" % _pending_sniper_shots.size())
	assert(_damage_applied_count == 0, "No damage should be applied yet")

	_time_stop_active = false
	_simulate_unfreeze()

	assert(_damage_applied_count == 3, "All 3 shots should deal damage on unfreeze, got: %d" % _damage_applied_count)
	assert(_pending_sniper_shots.size() == 0, "All pending shots should be cleared")
	print("  PASS: All deferred shots executed on unfreeze")


## Simulates SniperRifle.Fire() logic during/outside time stop
func _simulate_sniper_fire() -> String:
	if _time_stop_active:
		# Issue #977 fix: defer the hitscan
		var shot = {
			"origin": Vector2(100, 100),
			"direction": Vector2(1, 0),
			"is_breaker": false,
			"tracer": "frozen_tracer_node",  # Represents a Line2D node
		}
		_pending_sniper_shots.append(shot)
		return "shot_deferred"
	else:
		# Normal hitscan
		_apply_hitscan_damage()
		return "hitscan_immediate"


## Simulates what happens when time unfreezes (SniperRifle._Process detects freeze ending)
func _simulate_unfreeze() -> void:
	for shot in _pending_sniper_shots:
		_apply_hitscan_damage()
		# Tracer fade would start here
	_pending_sniper_shots.clear()
	_frozen_sniper_tracers.clear()


## Simulates applying hitscan damage to enemies
func _apply_hitscan_damage() -> void:
	_damage_applied_count += 1
	print("    > Hitscan damage applied (count: %d)" % _damage_applied_count)
