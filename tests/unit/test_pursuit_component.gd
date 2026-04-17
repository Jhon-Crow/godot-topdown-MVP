extends GutTest
## Tests for PursuitComponent (Issue #1289).
##
## Validates cover-finding constants and enemy-occupied penalty/radius values.
## The find_cover() method requires a full enemy node with raycasts, so we
## test constants and the RefCounted initialisation pattern.

const PursuitComp := preload("res://scripts/components/pursuit_component.gd")


# =============================================================================
# Constants
# =============================================================================

func test_pursuit_path_desired_distance_constant() -> void:
	assert_eq(PursuitComp.PURSUIT_PATH_DESIRED_DISTANCE, 80.0,
		"PURSUIT_PATH_DESIRED_DISTANCE should be 80.0 px")


func test_pursuit_enemy_occupied_penalty_constant() -> void:
	assert_eq(PursuitComp.PURSUIT_ENEMY_OCCUPIED_PENALTY, 3.0,
		"PURSUIT_ENEMY_OCCUPIED_PENALTY should be 3.0")


func test_pursuit_enemy_occupied_radius_constant() -> void:
	assert_eq(PursuitComp.PURSUIT_ENEMY_OCCUPIED_RADIUS, 80.0,
		"PURSUIT_ENEMY_OCCUPIED_RADIUS should be 80.0 px")


# =============================================================================
# Initialisation
# =============================================================================

func test_init_stores_enemy_reference() -> void:
	var mock_enemy := Node2D.new()
	add_child_autofree(mock_enemy)

	var comp := PursuitComp.new(mock_enemy)
	assert_eq(comp._enemy, mock_enemy,
		"Should store the enemy reference from _init")


func test_init_with_null_enemy() -> void:
	var comp := PursuitComp.new(null)
	assert_null(comp._enemy, "Should accept null enemy reference")


# =============================================================================
# find_cover — null / invalid enemy
# =============================================================================

func test_find_cover_returns_not_found_with_null_enemy() -> void:
	var comp := PursuitComp.new(null)
	var result := comp.find_cover()

	assert_false(result.found, "Should return found=false with null enemy")
	assert_eq(result.cover, Vector2.ZERO, "Cover should be Vector2.ZERO")
	assert_null(result.obstacle, "Obstacle should be null")


func test_find_cover_returns_not_found_with_freed_enemy() -> void:
	var mock_enemy := Node2D.new()
	add_child_autofree(mock_enemy)
	var comp := PursuitComp.new(mock_enemy)

	# Free the enemy to simulate an invalid reference
	mock_enemy.free()

	var result := comp.find_cover()
	assert_false(result.found, "Should return found=false with freed enemy")


# =============================================================================
# Constant Relationships
# =============================================================================

func test_occupied_radius_matches_desired_distance() -> void:
	assert_eq(PursuitComp.PURSUIT_ENEMY_OCCUPIED_RADIUS,
		PursuitComp.PURSUIT_PATH_DESIRED_DISTANCE,
		"Occupied radius should match path desired distance (both 80 px)")


func test_occupied_penalty_is_positive() -> void:
	assert_gt(PursuitComp.PURSUIT_ENEMY_OCCUPIED_PENALTY, 0.0,
		"Occupied penalty should be positive")
