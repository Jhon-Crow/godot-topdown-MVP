extends GutTest
## Unit tests for aggression_gas_grenade.gd projectile.
##
## Tests gas cloud parameters, aggression effect duration, and the fact that
## this grenade releases gas (no casing scatter) instead of exploding.


# ============================================================================
# Mock Classes
# ============================================================================


class MockAggressionGasGrenade:
	## Effect radius for the gas cloud (slightly larger than frag's 225px).
	var effect_radius: float = 300.0

	## Duration the gas cloud persists (seconds).
	var cloud_duration: float = 20.0

	## Duration of aggression effect on each enemy (seconds).
	var aggression_duration: float = 10.0

	## Grenade position.
	var global_position: Vector2 = Vector2.ZERO

	## Has exploded (released gas) flag.
	var _has_exploded: bool = false

	## Track whether casing scatter was called.
	var casings_scattered: bool = false

	## Track whether gas cloud was spawned.
	var gas_cloud_spawned: bool = false

	## Track enemies affected by aggression.
	var affected_enemies: Array = []

	## Mock enemies in range.
	var _mock_enemies: Array = []

	## Set mock enemies for testing.
	func set_mock_enemies(enemies: Array) -> void:
		_mock_enemies = enemies

	## Check if position is in effect radius.
	func is_in_effect_radius(pos: Vector2) -> bool:
		return global_position.distance_to(pos) <= effect_radius

	## Spawn aggression cloud (mock).
	func _spawn_aggression_cloud() -> void:
		gas_cloud_spawned = true
		# Apply aggression effect to enemies in radius
		for enemy in _mock_enemies:
			if is_in_effect_radius(enemy.global_position):
				affected_enemies.append(enemy)

	## Gas release handler (mirrors _on_explode from aggression_gas_grenade.gd).
	## No casing scatter — this is a gas release, not an explosion.
	func on_explode() -> void:
		if _has_exploded:
			return
		_has_exploded = true
		_spawn_aggression_cloud()
		# No casing scatter — gas release, not explosion

	## Scatter casings (should NOT be called for gas grenade).
	func scatter_casings() -> void:
		casings_scattered = true


class MockEnemy:
	## Enemy position.
	var global_position: Vector2 = Vector2.ZERO

	## Whether this enemy is aggressive toward others.
	var is_aggressive: bool = false


var grenade: MockAggressionGasGrenade


func before_each() -> void:
	grenade = MockAggressionGasGrenade.new()
	grenade.global_position = Vector2(500, 500)


func after_each() -> void:
	grenade = null


# ============================================================================
# Default Configuration Tests
# ============================================================================


func test_default_effect_radius() -> void:
	assert_eq(grenade.effect_radius, 300.0,
		"Effect radius should be 300.0 (slightly larger than frag's 225)")


func test_default_cloud_duration() -> void:
	assert_eq(grenade.cloud_duration, 20.0,
		"Cloud duration should be 20.0 seconds")


func test_default_aggression_duration() -> void:
	assert_eq(grenade.aggression_duration, 10.0,
		"Aggression effect duration should be 10.0 seconds")


func test_effect_radius_larger_than_frag() -> void:
	var frag_radius := 225.0
	assert_gt(grenade.effect_radius, frag_radius,
		"Aggression gas radius should be larger than frag grenade radius")


# ============================================================================
# Gas Release Tests (No Casing Scatter)
# ============================================================================


func test_no_casing_scatter_on_explode() -> void:
	grenade.on_explode()
	assert_false(grenade.casings_scattered,
		"Gas grenade should NOT scatter casings — it releases gas, not an explosion")


func test_gas_cloud_spawned_on_explode() -> void:
	grenade.on_explode()
	assert_true(grenade.gas_cloud_spawned,
		"Gas cloud should be spawned on explode")


func test_explode_only_once() -> void:
	grenade.on_explode()
	grenade.gas_cloud_spawned = false  # Reset to check second call
	grenade.on_explode()
	assert_false(grenade.gas_cloud_spawned,
		"Gas should only release once")


# ============================================================================
# Effect Radius Tests
# ============================================================================


func test_enemy_in_radius_affected() -> void:
	var enemy := MockEnemy.new()
	enemy.global_position = Vector2(600, 500)  # 100 units away, within 300

	grenade.set_mock_enemies([enemy])
	grenade.on_explode()

	assert_eq(grenade.affected_enemies.size(), 1,
		"Enemy within radius should be affected")


func test_enemy_outside_radius_not_affected() -> void:
	var enemy := MockEnemy.new()
	enemy.global_position = Vector2(900, 500)  # 400 units away, outside 300

	grenade.set_mock_enemies([enemy])
	grenade.on_explode()

	assert_eq(grenade.affected_enemies.size(), 0,
		"Enemy outside radius should not be affected")


func test_is_in_effect_radius_at_edge() -> void:
	var edge_pos := Vector2(500 + 300, 500)
	assert_true(grenade.is_in_effect_radius(edge_pos),
		"Position at exact radius edge should be in range")


func test_is_not_in_effect_radius_beyond_edge() -> void:
	var beyond_pos := Vector2(500 + 301, 500)
	assert_false(grenade.is_in_effect_radius(beyond_pos),
		"Position beyond radius should not be in range")
