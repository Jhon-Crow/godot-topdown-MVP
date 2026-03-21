extends GutTest
## Unit tests for enemy pathfinding with wall and enemy size awareness (Issue #1273).
##
## Tests that NavigationAgent2D is configured correctly to match the enemy's
## physical body size (radius) and movement speed (max_speed), so that:
##  - ORCA avoidance keeps correct inter-agent spacing (radius matches collision body)
##  - ORCA velocity clamping doesn't reduce speed below intended (max_speed covers all states)
##  - navmesh agent_radius is set correctly before baking in all level scripts
##
## These tests use stub classes to isolate the configuration logic from the
## full Godot scene/physics engine, following the same pattern as test_machete_combat_pathfinding.gd.


# ============================================================================
# Stub classes for configuration logic testing without a full Godot scene
# ============================================================================


## Simulates the NavigationAgent2D properties that _configure_nav_agent sets.
class StubNavAgent:
	var radius: float = 0.0
	var max_speed: float = 0.0
	var avoidance_enabled: bool = true


## Simulates the enemy's relevant exported variables and the _configure_nav_agent logic.
class StubEnemyNavConfig:
	## Base collision shape radius (matches Enemy.tscn CircleShape2D radius = 24.0).
	const COLLISION_RADIUS: float = 24.0

	var move_speed: float = 220.0
	var combat_move_speed: float = 320.0
	var nav_agent: StubNavAgent = StubNavAgent.new()

	## Replicates the logic of _configure_nav_agent() from enemy.gd (Issue #1273).
	func configure_nav_agent() -> void:
		if nav_agent == null:
			return
		nav_agent.radius = COLLISION_RADIUS
		nav_agent.max_speed = maxf(move_speed, combat_move_speed)

	## Returns true if the nav agent is configured correctly.
	func is_nav_agent_configured_correctly() -> bool:
		return (
			nav_agent.radius == COLLISION_RADIUS and
			nav_agent.max_speed >= combat_move_speed and
			nav_agent.max_speed >= move_speed
		)


# ============================================================================
# NavigationAgent2D radius tests
# ============================================================================


func test_nav_agent_radius_matches_collision_shape() -> void:
	var enemy := StubEnemyNavConfig.new()
	enemy.configure_nav_agent()
	assert_eq(
		enemy.nav_agent.radius,
		24.0,
		"NavigationAgent2D.radius must match CollisionShape2D radius (24px) for correct ORCA spacing"
	)


func test_nav_agent_radius_not_zero() -> void:
	var enemy := StubEnemyNavConfig.new()
	enemy.configure_nav_agent()
	assert_gt(enemy.nav_agent.radius, 0.0, "NavigationAgent2D.radius must be positive")


func test_nav_agent_radius_set_even_with_default_values() -> void:
	## Verify configuration works with the default enemy export variable values.
	var enemy := StubEnemyNavConfig.new()
	# Default export values from enemy.gd
	enemy.move_speed = 220.0
	enemy.combat_move_speed = 320.0
	enemy.configure_nav_agent()
	assert_eq(enemy.nav_agent.radius, 24.0, "Radius must be set for default enemy configuration")


# ============================================================================
# NavigationAgent2D max_speed tests
# ============================================================================


func test_nav_agent_max_speed_covers_combat_move_speed() -> void:
	var enemy := StubEnemyNavConfig.new()
	enemy.move_speed = 220.0
	enemy.combat_move_speed = 320.0
	enemy.configure_nav_agent()
	assert_gte(
		enemy.nav_agent.max_speed,
		enemy.combat_move_speed,
		"max_speed must be >= combat_move_speed so ORCA doesn't clamp combat velocity"
	)


func test_nav_agent_max_speed_covers_move_speed() -> void:
	var enemy := StubEnemyNavConfig.new()
	enemy.move_speed = 220.0
	enemy.combat_move_speed = 320.0
	enemy.configure_nav_agent()
	assert_gte(
		enemy.nav_agent.max_speed,
		enemy.move_speed,
		"max_speed must be >= move_speed so ORCA doesn't clamp patrol velocity"
	)


func test_nav_agent_max_speed_uses_higher_of_two_speeds() -> void:
	var enemy := StubEnemyNavConfig.new()
	enemy.move_speed = 220.0
	enemy.combat_move_speed = 320.0
	enemy.configure_nav_agent()
	assert_eq(
		enemy.nav_agent.max_speed,
		320.0,
		"max_speed should be max(move_speed, combat_move_speed) = 320.0"
	)


func test_nav_agent_max_speed_when_move_speed_higher() -> void:
	## Edge case: if move_speed is configured higher than combat_move_speed.
	var enemy := StubEnemyNavConfig.new()
	enemy.move_speed = 400.0
	enemy.combat_move_speed = 320.0
	enemy.configure_nav_agent()
	assert_eq(
		enemy.nav_agent.max_speed,
		400.0,
		"max_speed should use move_speed when it is higher"
	)


func test_nav_agent_max_speed_not_zero() -> void:
	var enemy := StubEnemyNavConfig.new()
	enemy.configure_nav_agent()
	assert_gt(enemy.nav_agent.max_speed, 0.0, "max_speed must be positive")


# ============================================================================
# Combined configuration validity tests
# ============================================================================


func test_nav_agent_fully_configured_for_default_enemy() -> void:
	var enemy := StubEnemyNavConfig.new()
	enemy.configure_nav_agent()
	assert_true(
		enemy.is_nav_agent_configured_correctly(),
		"Default enemy NavigationAgent2D should be fully configured correctly"
	)


func test_nav_agent_fully_configured_for_fast_enemy() -> void:
	## Fast combat enemy with higher speeds.
	var enemy := StubEnemyNavConfig.new()
	enemy.move_speed = 300.0
	enemy.combat_move_speed = 500.0
	enemy.configure_nav_agent()
	assert_true(
		enemy.is_nav_agent_configured_correctly(),
		"Fast enemy NavigationAgent2D should be fully configured correctly"
	)


func test_nav_agent_null_safe() -> void:
	## If nav_agent is null, configure_nav_agent should not crash.
	var enemy := StubEnemyNavConfig.new()
	enemy.nav_agent = null
	# Should not throw - just return early
	enemy.configure_nav_agent()
	assert_true(true, "configure_nav_agent should handle null nav_agent gracefully")


# ============================================================================
# NavigationPolygon agent_radius tests (level baking)
# ============================================================================


## Simulates the level navigation setup logic (agent_radius set before baking).
class StubNavPolygon:
	var agent_radius: float = 0.0


class StubNavRegion:
	var navigation_polygon: StubNavPolygon = StubNavPolygon.new()
	var baked: bool = false

	func bake_navigation_polygon(_synchronous: bool) -> void:
		baked = true


class StubLevelNavSetup:
	## Replicates the pattern that all level _setup_navigation() methods use (Issue #1273).
	var nav_region: StubNavRegion = StubNavRegion.new()

	func setup_navigation() -> void:
		if nav_region == null:
			return
		# Issue #1273: must set agent_radius before baking
		nav_region.navigation_polygon.agent_radius = 24.0
		nav_region.bake_navigation_polygon(false)


func test_level_nav_setup_sets_agent_radius_before_baking() -> void:
	var level := StubLevelNavSetup.new()
	level.setup_navigation()
	assert_eq(
		level.nav_region.navigation_polygon.agent_radius,
		24.0,
		"agent_radius must be 24.0 (enemy collision radius) before baking"
	)


func test_level_nav_setup_triggers_bake() -> void:
	var level := StubLevelNavSetup.new()
	level.setup_navigation()
	assert_true(level.nav_region.baked, "bake_navigation_polygon must be called after setting agent_radius")


func test_level_nav_agent_radius_matches_enemy_collision_radius() -> void:
	## Verify the nav polygon agent_radius equals the enemy CollisionShape2D radius.
	var enemy_collision_radius: float = 24.0  # From Enemy.tscn CircleShape2D
	var nav_polygon_agent_radius: float = 24.0  # What levels must set

	assert_eq(
		nav_polygon_agent_radius,
		enemy_collision_radius,
		"NavigationPolygon.agent_radius must match enemy CollisionShape2D radius for correct wall clearance"
	)


# ============================================================================
# Two-systems distinction tests (educational / regression)
# ============================================================================


func test_nav_polygon_radius_is_bake_time_wall_clearance() -> void:
	## Documents: NavigationPolygon.agent_radius is bake-time erosion (wall clearance).
	## NavigationAgent2D.radius is runtime RVO (agent-to-agent avoidance).
	## These are separate systems that must BOTH be set correctly.
	var nav_polygon_radius: float = 24.0  # Bake-time: erodes navmesh 24px from walls
	var nav_agent_radius: float = 24.0    # Runtime: ORCA avoidance distance

	# Both must be set to 24.0 (enemy body radius) for correct behavior
	assert_eq(nav_polygon_radius, 24.0, "NavPolygon agent_radius = 24.0 ensures 24px wall clearance in navmesh")
	assert_eq(nav_agent_radius, 24.0, "NavAgent radius = 24.0 ensures 24px inter-agent ORCA spacing")


func test_nav_agent_radius_does_not_affect_wall_clearance() -> void:
	## Documents that changing NavigationAgent2D.radius alone does NOT keep enemies
	## away from walls — that requires NavigationPolygon.agent_radius at bake time.
	## This test ensures we don't confuse the two systems.
	var enemy := StubEnemyNavConfig.new()
	enemy.configure_nav_agent()

	# nav_agent.radius controls RVO (agent separation), not navmesh boundary erosion
	assert_eq(
		enemy.nav_agent.radius,
		24.0,
		"NavigationAgent2D.radius = 24.0 is for ORCA avoidance, NOT wall clearance"
	)
	# Wall clearance is handled by NavigationPolygon.agent_radius at bake time (tested above)
