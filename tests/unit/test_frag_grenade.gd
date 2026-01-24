extends GutTest
## Unit tests for FragGrenade offensive grenade damage.
##
## Tests that frag grenades deal the same damage to both player and enemies.
## Regression test for issue #261: "наступательная граната должна наносить такой же урон игроку как и врагам"
## Translation: "offensive grenade should deal the same damage to the player as it does to enemies"


# ============================================================================
# Mock Classes for Logic Tests
# ============================================================================


class MockTarget:
	## Tracks damage received via on_hit_with_info calls.
	var damage_received: int = 0

	## Tracks hit directions.
	var hit_directions: Array = []

	## Global position for distance calculation.
	var global_position: Vector2 = Vector2.ZERO

	## Whether this target is a Node2D (for type checking).
	func is_node2d() -> bool:
		return true

	## Damage method that player and enemies both have.
	func on_hit_with_info(hit_direction: Vector2, _caliber_data: Resource) -> void:
		damage_received += 1
		hit_directions.append(hit_direction)

	## Alternative damage method.
	func on_hit() -> void:
		damage_received += 1

	func has_method(method_name: String) -> bool:
		return method_name in ["on_hit_with_info", "on_hit"]


class MockFragGrenade:
	## Explosion damage per target (should be 99 for instant kill).
	var explosion_damage: int = 99

	## Effect radius of explosion.
	var effect_radius: float = 225.0

	## Grenade position.
	var global_position: Vector2 = Vector2.ZERO

	## Has exploded flag.
	var _has_exploded: bool = false

	## Enemies that received damage.
	var damaged_enemies: Array = []

	## Player reference if damaged.
	var damaged_player: MockTarget = null

	## Mock enemies in range.
	var _mock_enemies: Array = []

	## Mock player in range.
	var _mock_player: MockTarget = null

	## Mock line of sight enabled.
	var _mock_line_of_sight: bool = true

	## Set mock enemies for testing.
	func set_mock_enemies(enemies: Array) -> void:
		_mock_enemies = enemies

	## Set mock player for testing.
	func set_mock_player(player: MockTarget) -> void:
		_mock_player = player

	## Set mock line of sight.
	func set_mock_line_of_sight(enabled: bool) -> void:
		_mock_line_of_sight = enabled

	## Check if position is in effect radius.
	func is_in_effect_radius(pos: Vector2) -> bool:
		return global_position.distance_to(pos) <= effect_radius

	## Mock line of sight check.
	func _has_line_of_sight_to(_target: MockTarget) -> bool:
		return _mock_line_of_sight

	## Get enemies in radius (mock).
	func _get_enemies_in_radius() -> Array:
		var in_range: Array = []
		for enemy in _mock_enemies:
			if is_in_effect_radius(enemy.global_position):
				if _has_line_of_sight_to(enemy):
					in_range.append(enemy)
		return in_range

	## Get player in radius (FIX for issue #261).
	## This is the new functionality being tested.
	func _get_player_in_radius() -> MockTarget:
		if _mock_player == null:
			return null

		if not is_in_effect_radius(_mock_player.global_position):
			return null

		if not _has_line_of_sight_to(_mock_player):
			return null

		return _mock_player

	## Apply explosion damage to a target.
	func _apply_explosion_damage(target: MockTarget) -> void:
		var final_damage := explosion_damage

		if target.has_method("on_hit_with_info"):
			var hit_direction := (target.global_position - global_position).normalized()
			for i in range(final_damage):
				target.on_hit_with_info(hit_direction, null)
		elif target.has_method("on_hit"):
			for i in range(final_damage):
				target.on_hit()

	## Explosion handler (simulates _on_explode from FragGrenade).
	## This is the fixed version that includes player damage.
	func on_explode() -> void:
		if _has_exploded:
			return
		_has_exploded = true

		# Damage all enemies in range
		var enemies := _get_enemies_in_radius()
		for enemy in enemies:
			_apply_explosion_damage(enemy)
			damaged_enemies.append(enemy)

		# ALSO damage the player if in range (FIX for issue #261)
		var player := _get_player_in_radius()
		if player != null:
			_apply_explosion_damage(player)
			damaged_player = player


var grenade: MockFragGrenade


func before_each() -> void:
	grenade = MockFragGrenade.new()
	grenade.global_position = Vector2(100, 100)


func after_each() -> void:
	grenade = null


# ============================================================================
# Issue #261 Regression Tests: Player Damage
# ============================================================================


func test_explosion_damages_player_in_radius() -> void:
	# Issue #261: Player should take damage from frag grenade
	var player := MockTarget.new()
	player.global_position = Vector2(150, 100)  # 50 units away, within 225 radius

	grenade.set_mock_player(player)
	grenade.on_explode()

	assert_eq(player.damage_received, 99,
		"Player in blast radius should receive 99 damage")
	assert_eq(grenade.damaged_player, player,
		"Player should be tracked as damaged")


func test_explosion_damages_player_same_as_enemies() -> void:
	# Issue #261: Player should receive same damage as enemies (99 damage)
	var player := MockTarget.new()
	player.global_position = Vector2(150, 100)

	var enemy := MockTarget.new()
	enemy.global_position = Vector2(200, 100)

	grenade.set_mock_player(player)
	grenade.set_mock_enemies([enemy])
	grenade.on_explode()

	assert_eq(player.damage_received, 99,
		"Player should receive 99 damage")
	assert_eq(enemy.damage_received, 99,
		"Enemy should receive 99 damage")
	assert_eq(player.damage_received, enemy.damage_received,
		"Player and enemy should receive identical damage")


func test_explosion_does_not_damage_player_outside_radius() -> void:
	var player := MockTarget.new()
	player.global_position = Vector2(500, 100)  # 400 units away, outside 225 radius

	grenade.set_mock_player(player)
	grenade.on_explode()

	assert_eq(player.damage_received, 0,
		"Player outside blast radius should not take damage")
	assert_null(grenade.damaged_player,
		"Player outside radius should not be tracked")


func test_explosion_does_not_damage_player_without_line_of_sight() -> void:
	var player := MockTarget.new()
	player.global_position = Vector2(150, 100)  # In radius

	grenade.set_mock_player(player)
	grenade.set_mock_line_of_sight(false)  # Wall blocking
	grenade.on_explode()

	assert_eq(player.damage_received, 0,
		"Player behind wall should not take damage")
	assert_null(grenade.damaged_player,
		"Player without LOS should not be tracked")


func test_explosion_at_player_feet_kills_instantly() -> void:
	# Player stands on grenade - should die instantly (99 damage > 5 HP)
	var player := MockTarget.new()
	player.global_position = grenade.global_position  # Same position as grenade

	grenade.set_mock_player(player)
	grenade.on_explode()

	assert_eq(player.damage_received, 99,
		"Player at grenade position should receive full 99 damage (instant kill)")


func test_explosion_damages_both_player_and_multiple_enemies() -> void:
	var player := MockTarget.new()
	player.global_position = Vector2(150, 100)

	var enemy1 := MockTarget.new()
	enemy1.global_position = Vector2(200, 100)

	var enemy2 := MockTarget.new()
	enemy2.global_position = Vector2(100, 200)

	var enemy_outside := MockTarget.new()
	enemy_outside.global_position = Vector2(500, 500)  # Outside radius

	grenade.set_mock_player(player)
	grenade.set_mock_enemies([enemy1, enemy2, enemy_outside])
	grenade.on_explode()

	assert_eq(player.damage_received, 99, "Player should take damage")
	assert_eq(enemy1.damage_received, 99, "Enemy 1 should take damage")
	assert_eq(enemy2.damage_received, 99, "Enemy 2 should take damage")
	assert_eq(enemy_outside.damage_received, 0, "Enemy outside should not take damage")


# ============================================================================
# Default Configuration Tests
# ============================================================================


func test_default_explosion_damage() -> void:
	assert_eq(grenade.explosion_damage, 99,
		"Default explosion damage should be 99 (instant kill)")


func test_default_effect_radius() -> void:
	assert_eq(grenade.effect_radius, 225.0,
		"Default effect radius should be 225 pixels")


# ============================================================================
# Effect Radius Tests
# ============================================================================


func test_is_in_effect_radius_at_center() -> void:
	assert_true(grenade.is_in_effect_radius(Vector2(100, 100)))


func test_is_in_effect_radius_within_range() -> void:
	assert_true(grenade.is_in_effect_radius(Vector2(300, 100)))  # 200 units, within 225


func test_is_in_effect_radius_at_edge() -> void:
	# Position exactly at radius edge
	var edge_pos := Vector2(100 + 225, 100)
	assert_true(grenade.is_in_effect_radius(edge_pos))


func test_is_not_in_effect_radius_outside() -> void:
	assert_false(grenade.is_in_effect_radius(Vector2(400, 100)))  # 300 units, outside 225


# ============================================================================
# Damage Application Tests
# ============================================================================


func test_apply_explosion_damage_uses_on_hit_with_info() -> void:
	var target := MockTarget.new()
	target.global_position = Vector2(150, 100)

	grenade._apply_explosion_damage(target)

	assert_eq(target.damage_received, 99)
	assert_eq(target.hit_directions.size(), 99,
		"Should receive 99 separate hit events")


func test_apply_explosion_damage_hit_direction() -> void:
	var target := MockTarget.new()
	target.global_position = Vector2(200, 100)  # 100 units to the right

	grenade._apply_explosion_damage(target)

	# Hit direction should point from grenade to target (right)
	var expected_direction := Vector2.RIGHT
	assert_almost_eq(target.hit_directions[0].x, expected_direction.x, 0.01)
	assert_almost_eq(target.hit_directions[0].y, expected_direction.y, 0.01)


# ============================================================================
# Edge Cases
# ============================================================================


func test_explosion_without_player_in_scene() -> void:
	# No player set - should not crash
	var enemy := MockTarget.new()
	enemy.global_position = Vector2(150, 100)

	grenade.set_mock_enemies([enemy])
	# No player set
	grenade.on_explode()

	assert_eq(enemy.damage_received, 99,
		"Enemies should still take damage without player")
	assert_null(grenade.damaged_player,
		"No player should be tracked when none exists")


func test_explosion_only_happens_once() -> void:
	var player := MockTarget.new()
	player.global_position = Vector2(150, 100)

	grenade.set_mock_player(player)
	grenade.on_explode()
	grenade.on_explode()  # Second call

	assert_eq(player.damage_received, 99,
		"Player should only receive damage once even if explode called twice")
