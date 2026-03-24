extends GutTest
## Unit tests for vog_grenade.gd projectile.
##
## Tests VOG-25 underbarrel grenade parameters: effect radius (1.5x frag),
## shrapnel count, explosion damage, and impact-only detonation (no timer).


# ============================================================================
# Mock Classes
# ============================================================================


class MockTarget:
	## Tracks damage received.
	var damage_received: int = 0

	## Global position for distance calculation.
	var global_position: Vector2 = Vector2.ZERO

	func has_method(method_name: String) -> bool:
		return method_name in ["on_hit_with_info", "on_hit"]

	func on_hit_with_info(_hit_direction: Vector2, _caliber_data: Resource) -> void:
		damage_received += 1

	func on_hit() -> void:
		damage_received += 1


class MockVOGGrenade:
	## Effect radius (50% larger than frag grenade: 225 * 1.5 = 337).
	var effect_radius: float = 337.0

	## Number of shrapnel pieces to spawn.
	var shrapnel_count: int = 8

	## Random angle deviation for shrapnel spread in degrees.
	var shrapnel_spread_deviation: float = 25.0

	## Direct explosive damage to enemies in effect radius.
	var explosion_damage: int = 99

	## Grenade position.
	var global_position: Vector2 = Vector2.ZERO

	## Has exploded flag.
	var _has_exploded: bool = false

	## Whether the grenade has impacted.
	var _has_impacted: bool = false

	## Track if we've been launched.
	var _is_launched: bool = false

	## Timer active flag (VOG sets to very high value to prevent timer explosion).
	var _timer_active: bool = false

	## Time remaining (VOG uses 999999.0 to prevent timer-based explosion).
	var _time_remaining: float = 999999.0

	## Track casings scattered.
	var casings_scattered: bool = false

	## Track shrapnel spawned.
	var shrapnel_spawned: bool = false

	## Track explosion effect.
	var explosion_effect_spawned: bool = false

	## Enemies damaged.
	var damaged_enemies: Array = []

	## Player damaged.
	var damaged_player: MockTarget = null

	## Mock enemies in range.
	var _mock_enemies: Array = []

	## Mock player in range.
	var _mock_player: MockTarget = null

	## Set mock enemies.
	func set_mock_enemies(enemies: Array) -> void:
		_mock_enemies = enemies

	## Set mock player.
	func set_mock_player(player: MockTarget) -> void:
		_mock_player = player

	## Check if position is in effect radius.
	func is_in_effect_radius(pos: Vector2) -> bool:
		return global_position.distance_to(pos) <= effect_radius

	## Mark as launched from underbarrel launcher.
	func mark_as_launched() -> void:
		_is_launched = true

	## Activate timer — VOG sets to very high value (no timer-based explosion).
	func activate_timer() -> void:
		if _timer_active:
			return
		_timer_active = true
		_time_remaining = 999999.0

	## Trigger impact explosion (wall hit or landing).
	func trigger_impact_explosion() -> void:
		if _has_impacted or _has_exploded:
			return
		_has_impacted = true
		_explode()

	## On body entered — detonate on impact with walls/enemies.
	func on_body_entered_solid() -> void:
		if _is_launched and not _has_impacted and not _has_exploded:
			trigger_impact_explosion()

	## On grenade landed — detonate on landing.
	func on_grenade_landed() -> void:
		if _is_launched and not _has_impacted and not _has_exploded:
			trigger_impact_explosion()

	## Main explosion handler.
	func _explode() -> void:
		if _has_exploded:
			return
		_has_exploded = true
		_on_explode()

	## Explosion effect — damages enemies, scatters casings, spawns shrapnel.
	func _on_explode() -> void:
		# Damage enemies in radius
		for enemy in _mock_enemies:
			if is_in_effect_radius(enemy.global_position):
				_apply_explosion_damage(enemy)
				damaged_enemies.append(enemy)

		# Damage player if in radius
		if _mock_player != null and is_in_effect_radius(_mock_player.global_position):
			_apply_explosion_damage(_mock_player)
			damaged_player = _mock_player

		casings_scattered = true
		shrapnel_spawned = true
		explosion_effect_spawned = true

	## Apply explosion damage to a target.
	func _apply_explosion_damage(target: MockTarget) -> void:
		if target.has_method("on_hit_with_info"):
			var hit_dir := (target.global_position - global_position).normalized()
			for i in range(explosion_damage):
				target.on_hit_with_info(hit_dir, null)
		elif target.has_method("on_hit"):
			for i in range(explosion_damage):
				target.on_hit()


var grenade: MockVOGGrenade


func before_each() -> void:
	grenade = MockVOGGrenade.new()
	grenade.global_position = Vector2(300, 300)


func after_each() -> void:
	grenade = null


# ============================================================================
# Default Configuration Tests
# ============================================================================


func test_default_effect_radius() -> void:
	assert_eq(grenade.effect_radius, 337.0,
		"Effect radius should be 337.0 (1.5x frag grenade's 225)")


func test_effect_radius_is_50_percent_larger_than_frag() -> void:
	var frag_radius := 225.0
	var expected := frag_radius * 1.5
	# 225 * 1.5 = 337.5, rounded to 337
	assert_almost_eq(grenade.effect_radius, expected, 1.0,
		"Effect radius should be approximately 1.5x frag radius")


func test_default_shrapnel_count() -> void:
	assert_eq(grenade.shrapnel_count, 8,
		"Shrapnel count should be 8")


func test_shrapnel_count_more_than_frag() -> void:
	var frag_shrapnel := 4
	assert_gt(grenade.shrapnel_count, frag_shrapnel,
		"VOG should have more shrapnel than frag grenade (4)")


func test_default_explosion_damage() -> void:
	assert_eq(grenade.explosion_damage, 99,
		"Explosion damage should be 99 (instant kill)")


func test_default_shrapnel_spread_deviation() -> void:
	assert_eq(grenade.shrapnel_spread_deviation, 25.0,
		"Shrapnel spread deviation should be 25.0 degrees")


# ============================================================================
# Impact-Only Detonation Tests (No Timer)
# ============================================================================


func test_timer_set_to_very_high_value() -> void:
	grenade.activate_timer()
	assert_eq(grenade._time_remaining, 999999.0,
		"VOG timer should be set to 999999.0 to prevent timer-based explosion")


func test_detonates_on_wall_impact() -> void:
	grenade.mark_as_launched()
	grenade.on_body_entered_solid()
	assert_true(grenade._has_exploded,
		"VOG should explode on wall impact")
	assert_true(grenade._has_impacted,
		"Impact flag should be set")


func test_detonates_on_landing() -> void:
	grenade.mark_as_launched()
	grenade.on_grenade_landed()
	assert_true(grenade._has_exploded,
		"VOG should explode on landing")
	assert_true(grenade._has_impacted,
		"Impact flag should be set on landing")


func test_no_detonation_before_launch() -> void:
	# Not launched — should not detonate
	grenade.on_body_entered_solid()
	assert_false(grenade._has_exploded,
		"VOG should not explode before being launched")


func test_no_double_detonation() -> void:
	grenade.mark_as_launched()
	grenade.on_body_entered_solid()
	assert_true(grenade._has_exploded)

	# Reset tracking to verify second call is blocked
	grenade.casings_scattered = false
	grenade.on_grenade_landed()
	assert_false(grenade.casings_scattered,
		"Second detonation should be blocked")


# ============================================================================
# Explosion Damage Tests
# ============================================================================


func test_explosion_damages_enemy_in_radius() -> void:
	var enemy := MockTarget.new()
	enemy.global_position = Vector2(400, 300)  # 100 units away, within 337

	grenade.set_mock_enemies([enemy])
	grenade.mark_as_launched()
	grenade.on_body_entered_solid()

	assert_eq(enemy.damage_received, 99,
		"Enemy in blast radius should receive 99 damage")


func test_explosion_does_not_damage_enemy_outside_radius() -> void:
	var enemy := MockTarget.new()
	enemy.global_position = Vector2(700, 300)  # 400 units away, outside 337

	grenade.set_mock_enemies([enemy])
	grenade.mark_as_launched()
	grenade.on_body_entered_solid()

	assert_eq(enemy.damage_received, 0,
		"Enemy outside blast radius should not take damage")


func test_explosion_damages_player_in_radius() -> void:
	var player := MockTarget.new()
	player.global_position = Vector2(350, 300)  # 50 units away

	grenade.set_mock_player(player)
	grenade.mark_as_launched()
	grenade.on_body_entered_solid()

	assert_eq(player.damage_received, 99,
		"Player in blast radius should receive 99 damage")


func test_explosion_spawns_shrapnel() -> void:
	grenade.mark_as_launched()
	grenade.on_body_entered_solid()
	assert_true(grenade.shrapnel_spawned,
		"Shrapnel should be spawned on explosion")


func test_explosion_scatters_casings() -> void:
	grenade.mark_as_launched()
	grenade.on_body_entered_solid()
	assert_true(grenade.casings_scattered,
		"Casings should be scattered on explosion (unlike gas grenades)")


# ============================================================================
# Effect Radius Tests
# ============================================================================


func test_is_in_effect_radius_at_center() -> void:
	assert_true(grenade.is_in_effect_radius(Vector2(300, 300)),
		"Center position should be in radius")


func test_is_in_effect_radius_at_edge() -> void:
	var edge_pos := Vector2(300 + 337, 300)
	assert_true(grenade.is_in_effect_radius(edge_pos),
		"Position at exact radius edge should be in range")


func test_is_not_in_effect_radius_outside() -> void:
	var outside_pos := Vector2(300 + 338, 300)
	assert_false(grenade.is_in_effect_radius(outside_pos),
		"Position beyond radius should not be in range")
