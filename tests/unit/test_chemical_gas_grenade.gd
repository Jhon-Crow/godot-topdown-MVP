extends GutTest
## Unit tests for chemical_gas_grenade.gd projectile.
##
## Tests gas cloud parameters, illusion duration, and contact detonation behavior
## for the chemical gas grenade that creates illusion copies of enemies.


# ============================================================================
# Mock Classes
# ============================================================================


class MockChemicalGasGrenade:
	## Effect radius for the gas cloud (2x bigger, Issue #1367).
	var effect_radius: float = 600.0

	## Duration the gas cloud persists (seconds).
	var cloud_duration: float = 20.0

	## Duration of each illusion copy (seconds).
	var illusion_duration: float = 20.0

	## Grenade position.
	var global_position: Vector2 = Vector2.ZERO

	## Has exploded (released gas) flag.
	var _has_exploded: bool = false

	## Track whether gas cloud was spawned.
	var gas_cloud_spawned: bool = false

	## Track whether contact detonation occurred.
	var contact_detonated: bool = false

	## Check if position is in effect radius.
	func is_in_effect_radius(pos: Vector2) -> bool:
		return global_position.distance_to(pos) <= effect_radius

	## Spawn chemical cloud (mock).
	func _spawn_chemical_cloud() -> void:
		gas_cloud_spawned = true

	## Gas release handler (mirrors _on_explode).
	func on_explode() -> void:
		if _has_exploded:
			return
		_has_exploded = true
		_spawn_chemical_cloud()

	## Contact detonation (Issue #1367) — explodes on landing or wall hit.
	func on_grenade_landed() -> void:
		if not _has_exploded:
			contact_detonated = true
			on_explode()

	## Wall collision detonation (Issue #1367).
	func on_body_entered_wall() -> void:
		if not _has_exploded:
			contact_detonated = true
			on_explode()


var grenade: MockChemicalGasGrenade


func before_each() -> void:
	grenade = MockChemicalGasGrenade.new()
	grenade.global_position = Vector2(400, 400)


func after_each() -> void:
	grenade = null


# ============================================================================
# Default Configuration Tests
# ============================================================================


func test_default_effect_radius() -> void:
	assert_eq(grenade.effect_radius, 600.0,
		"Effect radius should be 600.0 (2x bigger cloud, Issue #1367)")


func test_default_cloud_duration() -> void:
	assert_eq(grenade.cloud_duration, 20.0,
		"Cloud duration should be 20.0 seconds")


func test_default_illusion_duration() -> void:
	assert_eq(grenade.illusion_duration, 20.0,
		"Illusion duration should be 20.0 seconds")


func test_effect_radius_larger_than_aggression() -> void:
	var aggression_radius := 300.0
	assert_gt(grenade.effect_radius, aggression_radius,
		"Chemical gas radius should be larger than aggression gas radius")


# ============================================================================
# Gas Release Tests
# ============================================================================


func test_gas_cloud_spawned_on_explode() -> void:
	grenade.on_explode()
	assert_true(grenade.gas_cloud_spawned,
		"Chemical gas cloud should be spawned on explode")


func test_explode_only_once() -> void:
	grenade.on_explode()
	grenade.gas_cloud_spawned = false
	grenade.on_explode()
	assert_false(grenade.gas_cloud_spawned,
		"Gas should only release once")


# ============================================================================
# Contact Detonation Tests (Issue #1367)
# ============================================================================


func test_detonates_on_landing() -> void:
	grenade.on_grenade_landed()
	assert_true(grenade.contact_detonated,
		"Should detonate on landing (impact-only, Issue #1367)")
	assert_true(grenade._has_exploded,
		"Should be marked as exploded after landing")


func test_detonates_on_wall_hit() -> void:
	grenade.on_body_entered_wall()
	assert_true(grenade.contact_detonated,
		"Should detonate on wall collision (Issue #1367)")
	assert_true(grenade._has_exploded,
		"Should be marked as exploded after wall hit")


func test_no_double_detonation_landing_then_wall() -> void:
	grenade.on_grenade_landed()
	grenade.contact_detonated = false
	grenade.on_body_entered_wall()
	assert_false(grenade.contact_detonated,
		"Should not detonate twice")


# ============================================================================
# Effect Radius Tests
# ============================================================================


func test_is_in_effect_radius_within_range() -> void:
	assert_true(grenade.is_in_effect_radius(Vector2(800, 400)),
		"Position 400 units away should be within 600 radius")


func test_is_not_in_effect_radius_outside() -> void:
	assert_false(grenade.is_in_effect_radius(Vector2(1100, 400)),
		"Position 700 units away should be outside 600 radius")


func test_is_in_effect_radius_at_edge() -> void:
	var edge_pos := Vector2(400 + 600, 400)
	assert_true(grenade.is_in_effect_radius(edge_pos),
		"Position at exact radius edge should be in range")
