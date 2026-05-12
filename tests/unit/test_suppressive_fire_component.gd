extends GutTest
## Tests for SuppressiveFireComponent (Issue #910).
##
## Validates range/spread constants and initial state.
## The shoot/try_suppress methods require a full enemy node with bullet scenes,
## so we focus on constants and state verification.

const SuppressiveFireComp := preload("res://scripts/components/suppressive_fire_component.gd")


# =============================================================================
# Constants
# =============================================================================

func test_suppressive_range_constant() -> void:
	assert_eq(SuppressiveFireComp.SUPPRESSIVE_RANGE, 600.0,
		"SUPPRESSIVE_RANGE should be 600.0 px")


func test_fan_spread_constant() -> void:
	assert_eq(SuppressiveFireComp.FAN_SPREAD, 0.5,
		"FAN_SPREAD should be 0.5 radians (~28.6 degrees)")


# =============================================================================
# Constant Relationships
# =============================================================================

func test_suppressive_range_is_positive() -> void:
	assert_gt(SuppressiveFireComp.SUPPRESSIVE_RANGE, 0.0,
		"SUPPRESSIVE_RANGE should be positive")


func test_fan_spread_is_positive() -> void:
	assert_gt(SuppressiveFireComp.FAN_SPREAD, 0.0,
		"FAN_SPREAD should be positive")


func test_fan_spread_less_than_pi() -> void:
	assert_lt(SuppressiveFireComp.FAN_SPREAD, PI,
		"FAN_SPREAD should be less than PI (180 degrees)")


# =============================================================================
# Initial State
# =============================================================================

func test_initial_enemy_ref_null_before_ready() -> void:
	var comp := SuppressiveFireComp.new()
	# Before adding to tree, _enemy should be null
	assert_null(comp._enemy, "Enemy ref should be null before _ready")


func test_enemy_ref_set_on_ready() -> void:
	var comp := SuppressiveFireComp.new()
	var parent := Node2D.new()
	parent.add_child(comp)
	add_child_autofree(parent)

	comp._ready()

	assert_eq(comp._enemy, parent,
		"Enemy ref should be set to parent after _ready")


func test_muzzle_flash_detection_created_on_ready() -> void:
	var comp := SuppressiveFireComp.new()
	var parent := Node2D.new()
	parent.add_child(comp)
	add_child_autofree(parent)

	comp._ready()

	assert_not_null(comp._muzzle_flash_detection,
		"Muzzle flash detection should be created in _ready")
