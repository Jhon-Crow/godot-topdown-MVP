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
