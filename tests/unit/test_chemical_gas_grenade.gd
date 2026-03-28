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

	## Issue #1688: Track that sound plays before (or simultaneously with) cloud spawn.
	var sound_played: bool = false
	var cloud_spawned_after_sound: bool = false

	## Issue #1688: grow-in duration passed to the spawned cloud.
	var last_grow_in_duration: float = 0.0

	## Simulated sound duration (seconds) for testing Issue #1688 timing.
	var mock_sound_length: float = 1.0

	## Check if position is in effect radius.
	func is_in_effect_radius(pos: Vector2) -> bool:
		return global_position.distance_to(pos) <= effect_radius

	## Play sound (mock) — records that sound was played.
	func _play_explosion_sound_mock() -> void:
		sound_played = true

	## Spawn chemical cloud (mock) with grow-in support.
	func _spawn_chemical_cloud_with_grow_in(grow_in: float) -> void:
		gas_cloud_spawned = true
		last_grow_in_duration = grow_in
		# Issue #1688: cloud is spawned right after sound starts.
		cloud_spawned_after_sound = sound_played

	## Spawn cloud without grow-in (legacy shortcut).
	func _spawn_chemical_cloud() -> void:
		_spawn_chemical_cloud_with_grow_in(0.0)

	## Get gas sound length (mock) — returns simulated duration (Issue #1688).
	func _get_gas_sound_length_mock() -> float:
		return mock_sound_length

	## Gas release handler (mirrors _on_explode).
	func on_explode() -> void:
		if _has_exploded:
			return
		_has_exploded = true
		_spawn_chemical_cloud()

	## Simulated _explode() that mirrors Issue #1688 behavior:
	## sound starts, then cloud is spawned immediately (with gradual grow-in).
	func on_explode_with_sound_first() -> void:
		if _has_exploded:
			return
		_has_exploded = true
		_play_explosion_sound_mock()
		# Issue #1688: Cloud is spawned when sound starts (not after it ends).
		# grow-in duration matches the sound length for gradual spreading.
		_spawn_chemical_cloud_with_grow_in(_get_gas_sound_length_mock())

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


# ============================================================================
# Sound + Gradual Grow-In Synchronization Tests (Issue #1688)
# ============================================================================


func test_sound_played_before_cloud_spawned() -> void:
	grenade.on_explode_with_sound_first()
	assert_true(grenade.sound_played,
		"Sound must be played when gas is released (Issue #1688)")
	assert_true(grenade.gas_cloud_spawned,
		"Gas cloud must be spawned when sound starts (Issue #1688)")
	assert_true(grenade.cloud_spawned_after_sound,
		"Cloud must be spawned after sound has started (Issue #1688)")


func test_cloud_spawned_with_grow_in_duration() -> void:
	# Issue #1688: Cloud must receive the grow-in duration matching the sound length
	# so it spreads gradually during the hiss sound.
	grenade.on_explode_with_sound_first()
	assert_eq(grenade.last_grow_in_duration, grenade.mock_sound_length,
		"Cloud grow-in duration should match sound length for gradual spreading (Issue #1688)")


func test_cloud_not_spawned_without_sound() -> void:
	# Verify cloud_spawned_after_sound stays false if sound never played
	grenade.gas_cloud_spawned = false
	grenade.sound_played = false
	grenade.cloud_spawned_after_sound = false
	# Directly spawn cloud without playing sound first (mimics wrong order)
	grenade._spawn_chemical_cloud()
	assert_false(grenade.cloud_spawned_after_sound,
		"Cloud spawned without sound should not satisfy the ordering contract (Issue #1688)")


func test_mock_sound_length_positive() -> void:
	assert_gt(grenade.mock_sound_length, 0.0,
		"Simulated sound length must be positive to test timing (Issue #1688)")
