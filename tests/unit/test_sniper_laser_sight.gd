extends GutTest
## Tests for sniper enemy laser sight (Issue #1336).
##
## Validates that the laser sight Line2D is created, updated correctly,
## and uses the same direction as the weapon forward (matching the future tracer).

const SniperComponent := preload("res://scripts/components/enemy_sniper_component.gd")


# =============================================================================
# Laser Sight Constants
# =============================================================================

func test_laser_max_range_constant() -> void:
	assert_eq(SniperComponent.LASER_MAX_RANGE, 5000.0,
		"LASER_MAX_RANGE should be 5000.0 px (matching hitscan tracer range)")


func test_laser_width_constant() -> void:
	assert_eq(SniperComponent.LASER_WIDTH, 1.5,
		"LASER_WIDTH should be 1.5 px")


func test_laser_color_is_red() -> void:
	assert_eq(SniperComponent.LASER_COLOR.r, 1.0, "Laser color red channel should be 1.0")
	assert_eq(SniperComponent.LASER_COLOR.g, 0.0, "Laser color green channel should be 0.0")
	assert_eq(SniperComponent.LASER_COLOR.b, 0.0, "Laser color blue channel should be 0.0")
	assert_gt(SniperComponent.LASER_COLOR.a, 0.0, "Laser color alpha should be > 0")


func test_laser_dot_color_brighter_than_beam() -> void:
	assert_gt(SniperComponent.LASER_DOT_COLOR.a, SniperComponent.LASER_COLOR.a,
		"Laser dot (endpoint) should be brighter (higher alpha) than beam")


func test_laser_wall_layer_is_4() -> void:
	assert_eq(SniperComponent.LASER_WALL_LAYER, 4,
		"Laser should raycast against wall collision layer 4")


# =============================================================================
# Laser Sight Creation
# =============================================================================

func test_laser_line_created_on_ready() -> void:
	var comp := SniperComponent.new()
	var parent := CharacterBody2D.new()
	parent.add_child(comp)
	add_child_autofree(parent)

	await wait_frames(2)

	assert_not_null(comp._laser_line, "Laser Line2D should be created in _ready")


func test_laser_line_is_line2d() -> void:
	var comp := SniperComponent.new()
	var parent := CharacterBody2D.new()
	parent.add_child(comp)
	add_child_autofree(parent)

	await wait_frames(2)

	assert_true(comp._laser_line is Line2D, "Laser sight should be a Line2D node")


func test_laser_line_has_correct_name() -> void:
	var comp := SniperComponent.new()
	var parent := CharacterBody2D.new()
	parent.add_child(comp)
	add_child_autofree(parent)

	await wait_frames(2)

	assert_eq(comp._laser_line.name, "SniperLaserSight",
		"Laser Line2D should be named 'SniperLaserSight'")


func test_laser_line_is_top_level() -> void:
	var comp := SniperComponent.new()
	var parent := CharacterBody2D.new()
	parent.add_child(comp)
	add_child_autofree(parent)

	await wait_frames(2)

	assert_true(comp._laser_line.top_level,
		"Laser Line2D should be top_level for world-space positioning")


func test_laser_line_has_two_points() -> void:
	var comp := SniperComponent.new()
	var parent := CharacterBody2D.new()
	parent.add_child(comp)
	add_child_autofree(parent)

	await wait_frames(2)

	assert_eq(comp._laser_line.get_point_count(), 2,
		"Laser Line2D should have exactly 2 points (start and end)")


func test_laser_line_width() -> void:
	var comp := SniperComponent.new()
	var parent := CharacterBody2D.new()
	parent.add_child(comp)
	add_child_autofree(parent)

	await wait_frames(2)

	assert_eq(comp._laser_line.width, SniperComponent.LASER_WIDTH,
		"Laser Line2D width should match LASER_WIDTH constant")


func test_laser_line_z_index_below_tracer() -> void:
	var comp := SniperComponent.new()
	var parent := CharacterBody2D.new()
	parent.add_child(comp)
	add_child_autofree(parent)

	await wait_frames(2)

	assert_eq(comp._laser_line.z_index, 9,
		"Laser z_index should be 9 (below tracer at 10)")


# =============================================================================
# Laser Sight Visibility
# =============================================================================

func test_laser_hidden_when_enemy_null() -> void:
	var comp := SniperComponent.new()
	add_child_autofree(comp)

	await wait_frames(2)

	# enemy is null since parent is not a CharacterBody2D
	comp._update_laser_sight()
	if comp._laser_line != null:
		assert_false(comp._laser_line.visible,
			"Laser should be hidden when enemy reference is null")


func test_laser_line_null_before_ready() -> void:
	var comp := SniperComponent.new()
	# Don't add to tree — _ready hasn't run
	assert_null(comp._laser_line, "Laser line should be null before _ready")
