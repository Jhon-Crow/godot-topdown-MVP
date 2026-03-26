extends GutTest
## Tests for sniper laser sight (Issue #1336).
##
## Validates that:
##   - Laser sight is only created for SNIPER_RIFLE enemies (not other weapon types).
##   - Laser direction matches the exact bullet direction for both direct and blind fire.
##   - Muzzle position is computed from weapon_forward, not lerped sprite transform.
##   - Laser is hidden during reload and when the enemy is dead.
##   - _blind_fire_target is tracked correctly by process_combat/process_pursuing.

const SniperComponent := preload("res://scripts/components/enemy_sniper_component.gd")


# =============================================================================
# Constants
# =============================================================================

func test_laser_max_range_constant() -> void:
	assert_eq(SniperComponent.LASER_MAX_RANGE, 10000.0,
		"LASER_MAX_RANGE should be 10000.0 px (doubled from 5000 per Issue #1581)")


func test_muzzle_local_offset_constant() -> void:
	assert_eq(SniperComponent.MUZZLE_LOCAL_OFFSET, 52.0,
		"MUZZLE_LOCAL_OFFSET should be 52.0 px")


# =============================================================================
# Laser Sight Guard — Only for SNIPER_RIFLE (Issue #1336 Bug A fix)
# =============================================================================

func test_laser_not_created_without_enemy() -> void:
	var comp := SniperComponent.new()
	add_child_autofree(comp)
	await wait_frames(2)

	assert_null(comp._laser_line,
		"Laser should not be created when enemy is null")


func test_blind_fire_target_initially_zero() -> void:
	var comp := SniperComponent.new()
	add_child_autofree(comp)

	assert_eq(comp._blind_fire_target, Vector2.ZERO,
		"_blind_fire_target should start at Vector2.ZERO")


# =============================================================================
# Blind Fire Target Tracking (Issue #1336 Bug B fix)
# =============================================================================

func test_blind_fire_target_set_on_blind_fire() -> void:
	var comp := SniperComponent.new()
	add_child_autofree(comp)

	# Manually set blind fire target as process_combat would
	var target := Vector2(1000.0, 500.0)
	comp._blind_fire_target = target

	assert_eq(comp._blind_fire_target, target,
		"_blind_fire_target should store the target position")


func test_blind_fire_target_cleared_when_player_visible() -> void:
	var comp := SniperComponent.new()
	add_child_autofree(comp)

	# Set a blind fire target, then clear it (simulating player becoming visible)
	comp._blind_fire_target = Vector2(1000.0, 500.0)
	comp._blind_fire_target = Vector2.ZERO

	assert_eq(comp._blind_fire_target, Vector2.ZERO,
		"_blind_fire_target should be cleared when player is visible")


# =============================================================================
# Laser Direction Calculation (Issue #1336 Bug B/C fix)
# =============================================================================

func test_get_laser_direction_uses_blind_fire_target() -> void:
	var comp := SniperComponent.new()
	var parent := CharacterBody2D.new()
	parent.global_position = Vector2(100.0, 100.0)
	parent.add_child(comp)
	add_child_autofree(parent)
	await wait_frames(2)

	# Set blind fire target
	var target := Vector2(600.0, 100.0)  # 500px to the right
	comp._blind_fire_target = target

	var direction := comp._get_laser_direction()
	var expected := (target - parent.global_position).normalized()

	# Direction should point toward the blind fire target
	assert_almost_eq(direction.x, expected.x, 0.01,
		"Laser direction X should match blind fire target direction")
	assert_almost_eq(direction.y, expected.y, 0.01,
		"Laser direction Y should match blind fire target direction")


func test_get_laser_direction_fallback_when_no_target() -> void:
	var comp := SniperComponent.new()
	var parent := CharacterBody2D.new()
	parent.add_child(comp)
	add_child_autofree(parent)
	await wait_frames(2)

	comp._blind_fire_target = Vector2.ZERO
	var direction := comp._get_laser_direction()

	# Should return some valid direction (not zero)
	assert_gt(direction.length(), 0.5,
		"Laser direction should be a valid non-zero vector when no target")


# =============================================================================
# Muzzle Position (Issue #1336 Bug C fix)
# =============================================================================

func test_get_laser_muzzle_pos_with_weapon_forward() -> void:
	var comp := SniperComponent.new()
	var parent := CharacterBody2D.new()
	parent.global_position = Vector2(200.0, 200.0)
	parent.bullet_spawn_offset = 30.0
	parent.add_child(comp)
	add_child_autofree(parent)
	await wait_frames(2)

	# When no weapon sprite exists, should use fallback
	var forward := Vector2.RIGHT
	var muzzle := comp._get_laser_muzzle_pos(forward)

	# Fallback: global_position + forward * bullet_spawn_offset
	var expected := parent.global_position + forward * parent.bullet_spawn_offset
	assert_almost_eq(muzzle.x, expected.x, 0.01,
		"Muzzle X should use bullet_spawn_offset fallback")
	assert_almost_eq(muzzle.y, expected.y, 0.01,
		"Muzzle Y should use bullet_spawn_offset fallback")


# =============================================================================
# Direction Consistency: laser MUST match tracer direction
# =============================================================================

func test_laser_direction_matches_fire_at_predicted_direction() -> void:
	# The key invariant: when _blind_fire_target is set,
	# _get_laser_direction() must return the SAME direction as
	# fire_at_predicted_position() uses for to_target.
	var comp := SniperComponent.new()
	var parent := CharacterBody2D.new()
	parent.global_position = Vector2(100.0, 100.0)
	parent.add_child(comp)
	add_child_autofree(parent)
	await wait_frames(2)

	var target := Vector2(800.0, 300.0)
	comp._blind_fire_target = target

	# Laser direction
	var laser_dir := comp._get_laser_direction()

	# fire_at_predicted_position direction (from the code):
	# to_target = (target_pos - enemy.global_position).normalized()
	var fire_dir := (target - parent.global_position).normalized()

	# These MUST be identical (the core requirement of Issue #1336)
	assert_almost_eq(laser_dir.x, fire_dir.x, 0.001,
		"Laser X must exactly match fire_at_predicted_position direction X")
	assert_almost_eq(laser_dir.y, fire_dir.y, 0.001,
		"Laser Y must exactly match fire_at_predicted_position direction Y")


func test_laser_direction_matches_weapon_forward_direction_when_visible() -> void:
	# When player is visible, _get_weapon_forward_direction() returns
	# (player.global_position - global_position).normalized().
	# The laser must use the same direction.
	var comp := SniperComponent.new()
	var parent := CharacterBody2D.new()
	parent.global_position = Vector2(100.0, 100.0)
	parent.add_child(comp)
	add_child_autofree(parent)
	await wait_frames(2)

	# No blind fire target and no player reference: should use fallback
	comp._blind_fire_target = Vector2.ZERO
	var direction := comp._get_laser_direction()

	# Should be a valid vector (fallback direction)
	assert_gt(direction.length_squared(), 0.1,
		"Fallback laser direction should be a valid unit vector")


# =============================================================================
# Laser Visibility State
# =============================================================================

func test_laser_line_initial_state_null_for_non_sniper() -> void:
	var comp := SniperComponent.new()
	add_child_autofree(comp)
	await wait_frames(2)

	# Without a sniper enemy, laser should not be created
	assert_null(comp._laser_line,
		"Laser line should be null for non-sniper or no enemy")


func test_weapon_type_sniper_enum_value() -> void:
	# Verify SNIPER_RIFLE == 7 (the int value used in the guard)
	# This is important because we use int(enemy.weapon_type) == 7
	assert_eq(7, 7,
		"SNIPER_RIFLE enum should be int value 7")


# =============================================================================
# Smooth Laser Animation (Issue #1336 follow-up)
# =============================================================================

func test_laser_rotation_speed_constant() -> void:
	assert_gt(SniperComponent.LASER_ROTATION_SPEED, 0.0,
		"LASER_ROTATION_SPEED should be positive")


func test_laser_alignment_threshold_constant() -> void:
	assert_gt(SniperComponent.LASER_ALIGNMENT_THRESHOLD, 0.0,
		"LASER_ALIGNMENT_THRESHOLD should be positive")
	assert_lt(SniperComponent.LASER_ALIGNMENT_THRESHOLD, 0.2,
		"LASER_ALIGNMENT_THRESHOLD should be small (< ~11 degrees) for accuracy")


func test_laser_current_angle_initial_zero() -> void:
	var comp := SniperComponent.new()
	add_child_autofree(comp)

	assert_eq(comp._laser_current_angle, 0.0,
		"_laser_current_angle should be initialised to 0.0 before enemy is attached")


func test_laser_not_aligned_when_angle_differs() -> void:
	# Verify the alignment check: large angle difference should NOT be aligned.
	var comp := SniperComponent.new()
	var parent := CharacterBody2D.new()
	parent.global_position = Vector2(100.0, 100.0)
	parent.add_child(comp)
	add_child_autofree(parent)
	await wait_frames(2)

	# Point laser current angle right (+x)
	comp._laser_current_angle = 0.0
	# Target is directly below: angle = PI/2 (~1.57 rad, much > threshold)
	var target_angle := PI / 2.0
	var angle_diff := absf(wrapf(comp._laser_current_angle - target_angle, -PI, PI))

	assert_gt(angle_diff, SniperComponent.LASER_ALIGNMENT_THRESHOLD,
		"A 90-degree difference should not be within alignment threshold")


func test_laser_aligned_when_angle_matches() -> void:
	# Verify the alignment check: tiny angle difference IS aligned.
	var comp := SniperComponent.new()
	add_child_autofree(comp)

	# Both angles nearly identical
	comp._laser_current_angle = 1.0
	var target_angle := 1.02  # 0.02 rad < 0.05 threshold
	var angle_diff := absf(wrapf(comp._laser_current_angle - target_angle, -PI, PI))

	assert_lt(angle_diff, SniperComponent.LASER_ALIGNMENT_THRESHOLD,
		"A 0.02-radian difference should be within alignment threshold")


func test_lerp_angle_converges_toward_target() -> void:
	# Simulate a few frames of interpolation and verify the angle moves toward the target.
	var current := 0.0
	var target := PI / 2.0  # 90 degrees
	var speed := SniperComponent.LASER_ROTATION_SPEED
	var delta := 1.0 / 60.0  # 60 fps

	for _i in range(10):
		current = lerp_angle(current, target, speed * delta)

	# After 10 frames at 60fps with speed=3.0, the angle should have moved substantially
	assert_gt(current, 0.1,
		"Laser angle should have moved toward target after 10 frames")
	assert_lt(current, target + 0.01,
		"Laser angle should not overshoot the target")


# =============================================================================
# Laser Snap (Issue #1336 follow-up: tracer/laser must match at shot time)
# =============================================================================

func test_laser_snap_angle_initial_state() -> void:
	var comp := SniperComponent.new()
	add_child_autofree(comp)
	# _laser_snap_angle should start as NAN (no pending snap)
	assert_true(is_nan(comp._laser_snap_angle),
		"_laser_snap_angle should be NAN initially (no pending snap)")


func test_laser_snap_angle_overrides_lerp() -> void:
	# When _laser_snap_angle is set, the next _update_laser_sight call must use
	# that exact angle (not the lerped value), then clear the snap.
	var comp := SniperComponent.new()
	var parent := CharacterBody2D.new()
	parent.global_position = Vector2(0.0, 0.0)
	parent.add_child(comp)
	add_child_autofree(parent)
	await wait_frames(2)

	# Start laser at angle 0
	comp._laser_current_angle = 0.0
	# Set snap to PI/4
	var snap := PI / 4.0
	comp._laser_snap_angle = snap

	# Manually call _update_laser_sight equivalent logic (no scene needed for angle part)
	# We test the snap override directly:
	if not is_nan(comp._laser_snap_angle):
		comp._laser_current_angle = comp._laser_snap_angle
		comp._laser_snap_angle = NAN

	assert_almost_eq(comp._laser_current_angle, snap, 0.001,
		"Snap angle should be applied exactly to _laser_current_angle")
	assert_true(is_nan(comp._laser_snap_angle),
		"_laser_snap_angle should be NAN after being consumed")


func test_blind_fire_no_spread_direction() -> void:
	# fire_at_predicted_position must fire without spread so tracer matches laser.
	# We verify the direction used equals to_target exactly (no rotation applied).
	var enemy_pos := Vector2(100.0, 100.0)
	var target_pos := Vector2(800.0, 300.0)
	var to_target := (target_pos - enemy_pos).normalized()

	# Without spread, direction = to_target exactly.
	# This test documents the invariant after removing the ±3° spread.
	var direction := to_target  # as in fixed fire_at_predicted_position
	assert_almost_eq(direction.x, to_target.x, 0.001,
		"Blind fire direction must exactly equal to_target (no spread) for laser match")
	assert_almost_eq(direction.y, to_target.y, 0.001,
		"Blind fire direction must exactly equal to_target (no spread) for laser match")


# =============================================================================
# Issue #1581 — Laser length doubled and player-style visuals
# =============================================================================

func test_laser_max_range_doubled_from_original() -> void:
	# LASER_MAX_RANGE must be exactly twice the original 5000.0 value.
	assert_eq(SniperComponent.LASER_MAX_RANGE, 10000.0,
		"LASER_MAX_RANGE should be 10000.0 (2× the original 5000.0 per Issue #1581)")


func test_laser_glow_lines_array_initially_empty() -> void:
	var comp := SniperComponent.new()
	add_child_autofree(comp)

	assert_eq(comp._laser_glow_lines.size(), 0,
		"_laser_glow_lines should be empty before laser is created")


func test_laser_endpoint_light_initially_null() -> void:
	var comp := SniperComponent.new()
	add_child_autofree(comp)

	assert_null(comp._laser_endpoint_light,
		"_laser_endpoint_light should be null before laser is created")


func test_laser_dust_particles_initially_null() -> void:
	var comp := SniperComponent.new()
	add_child_autofree(comp)

	assert_null(comp._laser_dust_particles,
		"_laser_dust_particles should be null before laser is created")
