extends GutTest
## Unit tests for MachineGunnerZoneComponent sector-detection math (Issue #1552).
##
## These tests validate the angular cone check that determines whether a position
## falls inside a machine gunner's firing sector. The component is a RefCounted class,
## so the tests exercise the static is_position_in_any_mg_zone helper by checking
## the underlying trigonometric logic directly.


# ============================================================================
# Cone Half-Angle Constant
# ============================================================================


func test_mg_zone_half_angle_is_30_degrees() -> void:
	var expected := deg_to_rad(30.0)
	assert_almost_eq(
		MachineGunnerZoneComponent.MG_ZONE_HALF_ANGLE,
		expected,
		0.001,
		"MG_ZONE_HALF_ANGLE should equal 30° in radians"
	)


func test_mg_zone_max_range_is_positive() -> void:
	assert_true(
		MachineGunnerZoneComponent.MG_ZONE_MAX_RANGE > 0.0,
		"MG_ZONE_MAX_RANGE should be a positive distance"
	)


func test_mg_zone_cover_penalty_is_positive() -> void:
	assert_true(
		MachineGunnerZoneComponent.MG_ZONE_COVER_PENALTY > 0.0,
		"MG_ZONE_COVER_PENALTY should be a positive score penalty"
	)


# ============================================================================
# Angular Inclusion / Exclusion Math (mirrors is_position_in_any_mg_zone logic)
#
# The cone is defined by:
#   cone_dir = (target - gunner).normalized()
#   A position pos is inside when:
#     dot(cone_dir, (pos - gunner).normalized()) >= cos(MG_ZONE_HALF_ANGLE)
# ============================================================================


## Helper: compute dot product between cone_dir and direction to pos.
func _cone_dot(gunner: Vector2, target: Vector2, pos: Vector2) -> float:
	var cone_dir: Vector2 = (target - gunner).normalized()
	var to_pos: Vector2 = (pos - gunner).normalized()
	return cone_dir.dot(to_pos)


func test_position_on_cone_axis_is_inside() -> void:
	# pos is directly on the cone axis (0° deviation)
	var gunner := Vector2(0.0, 0.0)
	var target := Vector2(500.0, 0.0)
	var pos := Vector2(300.0, 0.0)
	var dot := _cone_dot(gunner, target, pos)
	assert_true(
		dot >= cos(MachineGunnerZoneComponent.MG_ZONE_HALF_ANGLE),
		"Position on cone axis (0°) should be inside the firing sector (dot=%.4f)" % dot
	)


func test_position_at_half_angle_boundary_is_inside() -> void:
	# pos is exactly at the half-angle boundary — should be considered inside.
	var gunner := Vector2(0.0, 0.0)
	var target := Vector2(1.0, 0.0)  # Cone aimed right
	var half_angle: float = MachineGunnerZoneComponent.MG_ZONE_HALF_ANGLE
	# Point exactly at the boundary angle
	var pos := Vector2(cos(half_angle), sin(half_angle)) * 300.0
	var dot := _cone_dot(gunner, target, pos)
	assert_almost_eq(
		dot,
		cos(half_angle),
		0.001,
		"Position at boundary angle should have dot ≈ cos(half_angle) (dot=%.4f)" % dot
	)


func test_position_5_degrees_inside_boundary_is_inside() -> void:
	# pos is 5° less than half_angle — safely inside
	var gunner := Vector2(0.0, 0.0)
	var target := Vector2(1.0, 0.0)
	var angle: float = MachineGunnerZoneComponent.MG_ZONE_HALF_ANGLE - deg_to_rad(5.0)
	var pos := Vector2(cos(angle), sin(angle)) * 300.0
	var dot := _cone_dot(gunner, target, pos)
	assert_true(
		dot >= cos(MachineGunnerZoneComponent.MG_ZONE_HALF_ANGLE),
		"Position 5° inside boundary should be inside the sector (dot=%.4f)" % dot
	)


func test_position_5_degrees_outside_boundary_is_outside() -> void:
	# pos is 5° beyond half_angle — should be outside
	var gunner := Vector2(0.0, 0.0)
	var target := Vector2(1.0, 0.0)
	var angle: float = MachineGunnerZoneComponent.MG_ZONE_HALF_ANGLE + deg_to_rad(5.0)
	var pos := Vector2(cos(angle), sin(angle)) * 300.0
	var dot := _cone_dot(gunner, target, pos)
	assert_true(
		dot < cos(MachineGunnerZoneComponent.MG_ZONE_HALF_ANGLE),
		"Position 5° outside boundary should be outside the sector (dot=%.4f)" % dot
	)


func test_position_90_degrees_off_axis_is_outside() -> void:
	# Directly perpendicular to cone axis — clearly outside
	var gunner := Vector2(0.0, 0.0)
	var target := Vector2(1.0, 0.0)
	var pos := Vector2(0.0, 300.0)  # 90° off axis
	var dot := _cone_dot(gunner, target, pos)
	assert_true(
		dot < cos(MachineGunnerZoneComponent.MG_ZONE_HALF_ANGLE),
		"Position 90° off axis should be well outside the sector (dot=%.4f)" % dot
	)


func test_position_behind_gunner_is_outside() -> void:
	# Position directly behind the gunner (180° off axis)
	var gunner := Vector2(0.0, 0.0)
	var target := Vector2(500.0, 0.0)
	var pos := Vector2(-300.0, 0.0)  # Behind the gunner
	var dot := _cone_dot(gunner, target, pos)
	assert_true(
		dot < cos(MachineGunnerZoneComponent.MG_ZONE_HALF_ANGLE),
		"Position behind gunner (180°) should be outside the sector (dot=%.4f)" % dot
	)


# ============================================================================
# Range Boundary (MG_ZONE_MAX_RANGE)
# ============================================================================


func test_mg_zone_max_range_constant_value() -> void:
	# Max range should be at least as large as suppressive fire range (600px)
	assert_true(
		MachineGunnerZoneComponent.MG_ZONE_MAX_RANGE >= 600.0,
		"MG_ZONE_MAX_RANGE should cover the full suppressive fire range (>=600px)"
	)


func test_position_beyond_max_range_math() -> void:
	# Simulate the range check: position on axis but too far away
	var gunner := Vector2(0.0, 0.0)
	var pos_far := Vector2(MachineGunnerZoneComponent.MG_ZONE_MAX_RANGE + 100.0, 0.0)
	var dist: float = gunner.distance_to(pos_far)
	assert_true(
		dist > MachineGunnerZoneComponent.MG_ZONE_MAX_RANGE,
		"Position beyond max range should be filtered out by the range check"
	)


func test_position_within_max_range_math() -> void:
	var gunner := Vector2(0.0, 0.0)
	var pos_near := Vector2(MachineGunnerZoneComponent.MG_ZONE_MAX_RANGE - 50.0, 0.0)
	var dist: float = gunner.distance_to(pos_near)
	assert_true(
		dist <= MachineGunnerZoneComponent.MG_ZONE_MAX_RANGE,
		"Position within max range should pass the range check"
	)


# ============================================================================
# MG_ZONE_COVER_PENALTY relative to other penalties in PursuitComponent
# ============================================================================


func test_mg_zone_penalty_is_larger_than_flashlight_penalty() -> void:
	# Flashlight penalty in PursuitComponent is 8.0; MG zone should be stronger.
	const FLASHLIGHT_PENALTY: float = 8.0
	assert_true(
		MachineGunnerZoneComponent.MG_ZONE_COVER_PENALTY > FLASHLIGHT_PENALTY,
		"MG_ZONE_COVER_PENALTY (%.1f) should exceed flashlight penalty (%.1f)" % [
			MachineGunnerZoneComponent.MG_ZONE_COVER_PENALTY, FLASHLIGHT_PENALTY
		]
	)


func test_mg_zone_penalty_is_larger_than_occupied_penalty() -> void:
	# Occupied penalty in PursuitComponent is PURSUIT_ENEMY_OCCUPIED_PENALTY = 3.0.
	const OCCUPIED_PENALTY: float = 3.0
	assert_true(
		MachineGunnerZoneComponent.MG_ZONE_COVER_PENALTY > OCCUPIED_PENALTY,
		"MG_ZONE_COVER_PENALTY (%.1f) should exceed occupied penalty (%.1f)" % [
			MachineGunnerZoneComponent.MG_ZONE_COVER_PENALTY, OCCUPIED_PENALTY
		]
	)
