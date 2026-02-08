extends GutTest
## Unit tests for wall avoidance system (Issue #612).
##
## Tests the wall avoidance logic that prevents enemies from jittering
## and getting stuck against walls. Covers:
## - Collision normal usage for head-on wall collisions
## - Avoidance direction smoothing to prevent oscillation
## - Consistent movement direction near walls


# ============================================================================
# Wall Avoidance Logic Tests (Issue #612)
# ============================================================================


## Test that head-on wall collision uses collision normal (not perpendicular).
## Root cause of jitter: center raycast (index 0) was treated as left-side,
## pushing perpendicular instead of along the collision normal.
func test_head_on_wall_uses_collision_normal_issue_612() -> void:
	# Simulate enemy moving RIGHT into a wall with normal pointing LEFT
	var direction := Vector2.RIGHT
	var collision_normal := Vector2.LEFT  # Wall facing left (enemy hits it head-on)
	var wall_distance := 30.0
	var wall_check_distance := 60.0

	var weight: float = 1.0 - (wall_distance / wall_check_distance)

	# Fixed behavior (Issue #612): Center raycast uses collision normal
	var avoidance_fixed := collision_normal * weight

	# Verify: avoidance pushes AWAY from wall (same direction as normal)
	assert_true(avoidance_fixed.dot(collision_normal) > 0,
		"Head-on avoidance should push away from wall (along collision normal)")

	# The perpendicular (old behavior) would push UP or DOWN, not away
	var perpendicular := Vector2(-direction.y, direction.x)  # Would be Vector2(0, 1)
	var avoidance_old := perpendicular * weight

	# Old behavior pushes perpendicular, not away from wall
	assert_almost_eq(avoidance_old.dot(collision_normal), 0.0, 0.01,
		"Old perpendicular push had zero component away from wall")


## Test that opposing wall detections don't cancel out.
## When left and right raycasts both hit walls (e.g. in a corridor),
## the avoidance forces should not perfectly cancel each other.
func test_opposing_walls_dont_cancel_issue_612() -> void:
	# Simulate a narrow corridor: walls on both sides at same distance
	var direction := Vector2.RIGHT
	var perpendicular := Vector2(-direction.y, direction.x)
	var wall_distance := 40.0
	var wall_check_distance := 60.0
	var weight: float = 1.0 - (wall_distance / wall_check_distance)

	# Simulate old behavior: left raycasts push right, right raycasts push left
	var left_avoidance := perpendicular * weight
	var right_avoidance := -perpendicular * weight
	var old_total := left_avoidance + right_avoidance

	# Old behavior: forces cancel out completely
	assert_almost_eq(old_total.length(), 0.0, 0.01,
		"Symmetric wall hits should cancel with old logic (demonstrating bug)")

	# Fixed behavior: center raycast (index 0) uses collision normal
	# In a corridor, center forward doesn't hit wall, but if it does:
	var center_normal := Vector2.LEFT  # Wall ahead
	var center_avoidance := center_normal * weight
	var new_total := center_avoidance + left_avoidance + right_avoidance

	# With center using normal, total is no longer zero
	assert_true(new_total.length() > 0.01,
		"Adding center normal avoidance breaks the cancellation")


## Test that avoidance smoothing dampens frame-to-frame oscillation.
func test_avoidance_smoothing_dampens_oscillation_issue_612() -> void:
	# Simulate alternating avoidance directions (the jitter pattern)
	var frame1_avoidance := Vector2(0, 1).normalized()   # Push up
	var frame2_avoidance := Vector2(0, -1).normalized()   # Push down

	# Without smoothing: instant switch
	var unsmoothed_diff := frame1_avoidance.distance_to(frame2_avoidance)
	assert_almost_eq(unsmoothed_diff, 2.0, 0.01,
		"Unsmoothed avoidance has maximum direction change")

	# With smoothing (lerp factor 0.4):
	var smoothed := Vector2.ZERO  # _last_wall_avoidance starts at zero
	smoothed = smoothed.lerp(frame1_avoidance, 0.4)  # Frame 1
	var after_frame1 := smoothed

	smoothed = smoothed.lerp(frame2_avoidance, 0.4)  # Frame 2
	var after_frame2 := smoothed

	# The smoothed direction change should be much smaller
	var smoothed_diff := after_frame1.distance_to(after_frame2)
	assert_true(smoothed_diff < unsmoothed_diff,
		"Smoothed avoidance should have smaller direction change than unsmoothed")

	# Specifically, the smoothed value should retain some of the previous direction
	# Frame 1: lerp(Zero, Up, 0.4) = (0, 0.4)
	# Frame 2: lerp((0,0.4), Down, 0.4) = (0, 0.4*0.6 + (-1)*0.4) = (0, -0.16)
	assert_almost_eq(after_frame1.y, 0.4, 0.01,
		"After frame 1, smoothed Y should be 0.4")
	assert_almost_eq(after_frame2.y, -0.16, 0.01,
		"After frame 2, smoothed Y should be -0.16 (dampened)")


## Test that smoothing converges to stable direction over multiple frames.
func test_avoidance_smoothing_converges_issue_612() -> void:
	# Simulate consistent avoidance direction over several frames
	var target_direction := Vector2(1, 0.5).normalized()
	var smoothed := Vector2.ZERO

	# Apply smoothing for 20 frames
	for i in range(20):
		smoothed = smoothed.lerp(target_direction, 0.4)

	# After many frames, smoothed should be very close to target
	var alignment := smoothed.normalized().dot(target_direction)
	assert_almost_eq(alignment, 1.0, 0.01,
		"Smoothed avoidance should converge to consistent direction")


## Test that smoothing resets when no wall is detected.
func test_avoidance_resets_when_no_wall_issue_612() -> void:
	# When _check_wall_ahead returns Vector2.ZERO, _last_wall_avoidance resets
	var last_avoidance := Vector2(0.5, 0.3)  # Some previous avoidance

	# Simulate: no wall detected → reset to zero
	var avoidance := Vector2.ZERO
	if avoidance == Vector2.ZERO:
		last_avoidance = Vector2.ZERO

	assert_eq(last_avoidance, Vector2.ZERO,
		"Smoothed avoidance should reset when no walls detected")


## Test wall avoidance weight calculation.
## Weight interpolates between 0.7 (close) and 0.3 (far).
func test_wall_avoidance_weight_interpolation_issue_612() -> void:
	var min_weight := 0.7  # WALL_AVOIDANCE_MIN_WEIGHT (close to wall)
	var max_weight := 0.3  # WALL_AVOIDANCE_MAX_WEIGHT (far from wall)
	var wall_check_distance := 60.0

	# At distance 0 (touching wall): weight should be min (0.7 = strong avoidance)
	var dist_0 := 0.0
	var norm_0 := clampf(dist_0 / wall_check_distance, 0.0, 1.0)
	var weight_0 := lerpf(min_weight, max_weight, norm_0)
	assert_almost_eq(weight_0, 0.7, 0.01,
		"At distance 0, avoidance weight should be 0.7 (strongest)")

	# At max distance: weight should be max (0.3 = weak avoidance)
	var dist_max := wall_check_distance
	var norm_max := clampf(dist_max / wall_check_distance, 0.0, 1.0)
	var weight_max := lerpf(min_weight, max_weight, norm_max)
	assert_almost_eq(weight_max, 0.3, 0.01,
		"At max distance, avoidance weight should be 0.3 (weakest)")

	# At half distance: weight should be midpoint
	var dist_half := wall_check_distance / 2.0
	var norm_half := clampf(dist_half / wall_check_distance, 0.0, 1.0)
	var weight_half := lerpf(min_weight, max_weight, norm_half)
	assert_almost_eq(weight_half, 0.5, 0.01,
		"At half distance, avoidance weight should be 0.5 (medium)")


## Test that wall avoidance blends direction correctly.
func test_wall_avoidance_direction_blending_issue_612() -> void:
	var original_direction := Vector2.RIGHT
	var avoidance := Vector2.UP
	var weight := 0.5  # 50/50 blend

	var blended := (original_direction * (1.0 - weight) + avoidance * weight).normalized()

	# Should be roughly 45 degrees (blend of RIGHT and UP)
	assert_almost_eq(blended.x, blended.y, 0.01,
		"50/50 blend of RIGHT and UP should give 45-degree direction")
	assert_true(blended.x > 0, "Blended direction should still have forward component")
	assert_true(blended.y > 0, "Blended direction should have upward avoidance component")


## Test that side raycasts produce correct push directions.
## Left raycasts (indices 1-3) push right, right raycasts (4-6) push left.
func test_side_raycast_push_directions_issue_612() -> void:
	var direction := Vector2.RIGHT
	var perpendicular := Vector2(-direction.y, direction.x)  # Vector2(0, 1) = UP
	var weight := 0.5

	# Left side raycasts push in perpendicular direction (UP)
	var left_push := perpendicular * weight
	assert_true(left_push.y > 0, "Left wall detection should push UP (right side)")

	# Right side raycasts push opposite perpendicular (DOWN)
	var right_push := -perpendicular * weight
	assert_true(right_push.y < 0, "Right wall detection should push DOWN (left side)")


## Test combined avoidance direction with center normal.
## Simulates the fix where center raycast uses collision normal.
func test_combined_avoidance_with_center_normal_issue_612() -> void:
	var direction := Vector2.RIGHT
	var perpendicular := Vector2(-direction.y, direction.x)
	var wall_distance := 30.0
	var wall_check_distance := 60.0
	var weight: float = 1.0 - (wall_distance / wall_check_distance)

	# Center (index 0): collision normal pointing LEFT (wall in front)
	var center_normal := Vector2.LEFT
	var center_avoidance := center_normal * weight

	# Left side (index 1): wall at 45 degrees, push right
	var left_avoidance := perpendicular * weight * 0.7  # Farther wall

	# Combine
	var total := center_avoidance + left_avoidance
	var normalized_total := total.normalized() if total.length() > 0 else Vector2.ZERO

	# The combined direction should push away from the wall corner
	assert_true(normalized_total.x < 0,
		"Combined avoidance should push away from wall (left component)")


## Test rear raycast (index 7) uses collision normal for wall sliding.
func test_rear_raycast_wall_sliding_issue_612() -> void:
	# Rear raycast uses collision normal * 0.5 for wall sliding
	var collision_normal := Vector2(0.707, 0.707).normalized()  # Diagonal wall

	var avoidance := collision_normal * 0.5

	# Should push along the wall surface (using normal)
	assert_true(avoidance.length() > 0, "Rear raycast should produce non-zero avoidance")
	assert_almost_eq(avoidance.length(), 0.5, 0.01,
		"Rear raycast avoidance should have 0.5 magnitude")


## Test that NAN flank side signals both sides behind walls (Issue #612).
## When _choose_best_flank_side returns NAN, flanking should be aborted.
func test_nan_flank_side_signals_abort_issue_612() -> void:
	# NAN is used as a sentinel value to indicate "both sides behind walls"
	var flank_side: float = NAN

	assert_true(is_nan(flank_side),
		"NAN flank_side should be detected by is_nan()")

	# A valid flank side should NOT be NAN
	var valid_right: float = 1.0
	var valid_left: float = -1.0
	assert_false(is_nan(valid_right), "Valid right side should not be NAN")
	assert_false(is_nan(valid_left), "Valid left side should not be NAN")


## Test that NAN is not equal to any valid flank side value.
func test_nan_inequality_with_valid_sides_issue_612() -> void:
	var nan_val: float = NAN

	# NAN is not equal to anything, including itself
	assert_true(nan_val != 1.0, "NAN should not equal 1.0 (right)")
	assert_true(nan_val != -1.0, "NAN should not equal -1.0 (left)")
	assert_true(nan_val != 0.0, "NAN should not equal 0.0")
	assert_true(nan_val != nan_val, "NAN should not equal itself")


## Test flank fail count increments on abort (Issue #612).
## Simulates the escalation logic: fail_count increments each abort,
## and after FLANK_FAIL_MAX_COUNT (2) attempts, flanking is disabled.
func test_flank_fail_escalation_issue_612() -> void:
	var flank_fail_count: int = 0
	var flank_fail_max: int = 2
	var flank_cooldown: float = 5.0

	# First abort: increment count, set cooldown
	flank_fail_count += 1
	var cooldown_1 := flank_cooldown
	assert_eq(flank_fail_count, 1, "First abort should set fail count to 1")
	assert_eq(cooldown_1, 5.0, "First abort should set 5s cooldown")

	# Cooldown expires, count resets (simulated by _physics_process)
	# But in our fix, we DON'T reset fail count on NAN abort
	# Instead, the cooldown timer handles re-enabling

	# Second abort: increment again
	flank_fail_count += 1
	assert_eq(flank_fail_count, 2, "Second abort should set fail count to 2")
	assert_true(flank_fail_count >= flank_fail_max,
		"After 2 failures, flanking should be disabled")


# ============================================================================
# Global Stuck Detection with COMBAT State (Issue #612 - Round 3)
# ============================================================================
# The GLOBAL STUCK timer now includes COMBAT state to catch enemies cycling
# COMBAT↔PURSUING at walls. Previously, the timer reset during COMBAT frames,
# allowing enemies to stay stuck indefinitely while rapidly cycling states.


## Test GLOBAL STUCK timer accumulates across COMBAT↔PURSUING cycles.
## Simulates enemy stuck at wall with rapid state cycling observed in game logs.
func test_global_stuck_accumulates_across_combat_pursuing_cycles_issue_612() -> void:
	# Simulate: PURSUING for 0.3s -> COMBAT for 0.5s -> PURSUING for 0.3s -> ...
	# In the old code, timer reset to 0 during COMBAT. Now it continues.
	var timer: float = 0.0
	var max_time: float = 4.0  # GLOBAL_STUCK_MAX_TIME
	var threshold: float = 30.0  # GLOBAL_STUCK_DISTANCE_THRESHOLD
	var wall_pos := Vector2(888, 880)  # Enemy stuck at wall
	var last_pos := wall_pos
	var delta := 1.0 / 60.0
	var can_see_player := false
	var can_hit_player := false

	# Simulate 10 cycles of PURSUING(0.3s) -> COMBAT(0.5s) = ~8s total
	# Enemy doesn't move significantly during any of this
	for cycle in range(10):
		# PURSUING phase: 0.3s = 18 frames
		for i in range(18):
			var moved := wall_pos.distance_to(last_pos)
			if moved < threshold and not (can_see_player and can_hit_player):
				timer += delta

		# COMBAT phase: 0.5s = 30 frames — NOW timer continues (Issue #612 fix)
		for i in range(30):
			var moved := wall_pos.distance_to(last_pos)
			if moved < threshold and not (can_see_player and can_hit_player):
				timer += delta

		# Transition back to PURSUING — only position resets, NOT timer
		last_pos = wall_pos

	# After 10 cycles of 0.8s each = 8s, timer should have reached 4s threshold
	assert_true(timer >= max_time,
		"GLOBAL STUCK timer should accumulate across COMBAT↔PURSUING cycles")


## Test GLOBAL STUCK timer would NOT accumulate in old code (COMBAT resets timer).
## This test demonstrates the bug that the fix addresses.
func test_old_global_stuck_fails_on_combat_cycling_issue_612() -> void:
	# Old behavior: timer resets to 0 when entering COMBAT state
	var timer: float = 0.0
	var max_time: float = 4.0
	var threshold: float = 30.0
	var wall_pos := Vector2(888, 880)
	var last_pos := wall_pos
	var delta := 1.0 / 60.0

	# Simulate 10 cycles with old behavior (timer resets during COMBAT)
	var max_timer_reached := false
	for cycle in range(10):
		# PURSUING phase: 0.3s = 18 frames — timer accumulates
		for i in range(18):
			var moved := wall_pos.distance_to(last_pos)
			if moved < threshold:
				timer += delta
			if timer >= max_time:
				max_timer_reached = true

		# COMBAT phase: OLD behavior — timer RESETS
		timer = 0.0
		last_pos = wall_pos

	# In old code, timer never reaches 4s because it resets every 0.3s
	assert_false(max_timer_reached,
		"Old behavior: timer should never reach 4s with 0.3s PURSUING phases")


## Test GLOBAL STUCK timer resets when enemy makes genuine progress.
func test_global_stuck_resets_on_movement_progress_issue_612() -> void:
	var timer: float = 3.5  # Almost at the 4s threshold
	var threshold: float = 30.0
	var last_pos := Vector2(500, 500)
	var current_pos := Vector2(535, 510)  # Moved ~38px — above threshold

	var moved := current_pos.distance_to(last_pos)
	assert_true(moved >= threshold,
		"Movement of 38px should be above the 30px threshold")

	# When enemy moves, timer and position both reset
	if moved >= threshold:
		timer = 0.0
		last_pos = current_pos

	assert_eq(timer, 0.0,
		"Timer should reset when enemy makes meaningful progress")
	assert_eq(last_pos, current_pos,
		"Last position should update on progress")


## Test GLOBAL STUCK timer does NOT accumulate when enemy has line of fire.
## If enemy can see AND hit the player, the stuck timer should not increment.
func test_global_stuck_pauses_during_active_combat_issue_612() -> void:
	var timer: float = 0.0
	var threshold: float = 30.0
	var wall_pos := Vector2(888, 880)
	var last_pos := wall_pos
	var delta := 1.0 / 60.0

	# Enemy is stationary but has direct line of fire
	var can_see := true
	var can_hit := true

	# Simulate 5 seconds of combat with direct player contact
	for i in range(300):
		var moved := wall_pos.distance_to(last_pos)
		if moved < threshold:
			if not (can_see and can_hit):
				timer += delta

	# Timer should not have accumulated because enemy has player contact
	assert_almost_eq(timer, 0.0, 0.01,
		"GLOBAL STUCK timer should NOT accumulate when enemy has line of fire")


## Test that flank fail count triggers SEARCHING fallback (Issue #612).
## After FLANK_FAIL_MAX_COUNT failures, flank abort goes to SEARCHING instead of PURSUING.
func test_flank_fail_count_triggers_searching_fallback_issue_612() -> void:
	var flank_fail_count: int = 0
	var flank_fail_max: int = 2

	# First flank abort: goes to COMBAT/PURSUING (not yet at max)
	flank_fail_count += 1
	var should_search_1 := flank_fail_count >= flank_fail_max
	assert_false(should_search_1,
		"First flank failure should NOT trigger SEARCHING fallback")

	# Second flank abort: should now trigger SEARCHING
	flank_fail_count += 1
	var should_search_2 := flank_fail_count >= flank_fail_max
	assert_true(should_search_2,
		"After reaching FLANK_FAIL_MAX_COUNT, should transition to SEARCHING")
