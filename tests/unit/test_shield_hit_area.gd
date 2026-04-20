extends GutTest
## Unit tests for ShieldHitArea.
##
## Tests the hit forwarding logic and multiple on_hit overload signatures
## for the SWAT shield hit detection area.


# ============================================================================
# Mock Classes
# ============================================================================


class MockShieldComponent:
	var _active: bool = true
	var intercept_called: int = 0
	var last_caliber_data: Resource = null
	var last_bullet_damage: float = 0.0
	var last_hit_direction: Vector2 = Vector2.ZERO
	var should_block: bool = true

	func is_active() -> bool:
		return _active

	func try_intercept_hit(caliber_data: Resource, bullet_damage: float, hit_direction: Vector2) -> bool:
		intercept_called += 1
		last_caliber_data = caliber_data
		last_bullet_damage = bullet_damage
		last_hit_direction = hit_direction
		return should_block


class MockEnemy:
	var hit_called: int = 0
	var on_hit_called: int = 0
	var last_hit_direction: Vector2 = Vector2.ZERO
	var last_caliber_data: Resource = null
	var last_ricocheted: bool = false
	var last_penetrated: bool = false
	var last_bullet_damage: float = 0.0
	var last_is_from_player: bool = false
	var last_attacker_node: Node2D = null
	var hit_reaction_target: Vector2 = Vector2.ZERO
	var hit_reaction_called: int = 0

	func on_hit_with_bullet_info(hit_direction: Vector2, caliber_data: Resource, has_ricocheted: bool, has_penetrated: bool, bullet_damage: float, is_from_player: bool, attacker_node: Node2D = null) -> void:
		hit_called += 1
		last_hit_direction = hit_direction
		last_caliber_data = caliber_data
		last_ricocheted = has_ricocheted
		last_penetrated = has_penetrated
		last_bullet_damage = bullet_damage
		last_is_from_player = is_from_player
		last_attacker_node = attacker_node

	func on_hit() -> void:
		on_hit_called += 1

	func _set_hit_reaction_target(direction: Vector2) -> void:
		hit_reaction_called += 1
		hit_reaction_target = direction

	func has_method(method_name: String) -> bool:
		return method_name in ["on_hit_with_bullet_info", "on_hit", "_set_hit_reaction_target"]


class MockEnemyOnlyOnHit:
	var on_hit_called: int = 0

	func on_hit() -> void:
		on_hit_called += 1

	func has_method(method_name: String) -> bool:
		return method_name == "on_hit"


class MockShieldHitArea:
	var shield_component = null
	var enemy = null

	func on_hit_with_bullet_info_and_damage(hit_direction: Vector2, caliber_data: Resource, has_ricocheted: bool, has_penetrated: bool, bullet_damage: float, is_from_player: bool = false, attacker_node: Node2D = null) -> void:
		if shield_component and shield_component.is_active():
			if shield_component.try_intercept_hit(caliber_data, bullet_damage, hit_direction):
				if enemy and enemy.has_method("_set_hit_reaction_target"):
					enemy._set_hit_reaction_target(-hit_direction.normalized())
				return
		_forward_to_enemy(hit_direction, caliber_data, has_ricocheted, has_penetrated, bullet_damage, is_from_player, attacker_node)

	func on_hit_with_bullet_info(hit_direction: Vector2, caliber_data: Resource, has_ricocheted: bool, has_penetrated: bool, is_from_player: bool = false, attacker_node: Node2D = null) -> void:
		on_hit_with_bullet_info_and_damage(hit_direction, caliber_data, has_ricocheted, has_penetrated, 1.0, is_from_player, attacker_node)

	func on_hit_with_info(hit_direction: Vector2, caliber_data: Resource) -> void:
		on_hit_with_bullet_info_and_damage(hit_direction, caliber_data, false, false, 1.0, false)

	func on_hit() -> void:
		on_hit_with_bullet_info_and_damage(Vector2.RIGHT, null, false, false, 1.0, false)

	func _forward_to_enemy(hit_direction: Vector2, caliber_data: Resource, has_ricocheted: bool, has_penetrated: bool, bullet_damage: float, is_from_player: bool, attacker_node: Node2D = null) -> void:
		if enemy and enemy.has_method("on_hit_with_bullet_info"):
			enemy.on_hit_with_bullet_info(hit_direction, caliber_data, has_ricocheted, has_penetrated, bullet_damage, is_from_player, attacker_node)
		elif enemy and enemy.has_method("on_hit"):
			enemy.on_hit()


var hit_area: MockShieldHitArea
var shield: MockShieldComponent
var enemy: MockEnemy


func before_each() -> void:
	hit_area = MockShieldHitArea.new()
	shield = MockShieldComponent.new()
	enemy = MockEnemy.new()
	hit_area.shield_component = shield
	hit_area.enemy = enemy


func after_each() -> void:
	hit_area = null
	shield = null
	enemy = null


# ============================================================================
# Shield Blocking Tests
# ============================================================================


func test_shield_blocks_hit_when_active() -> void:
	shield._active = true
	shield.should_block = true

	hit_area.on_hit_with_bullet_info_and_damage(Vector2.RIGHT, null, false, false, 1.0, false)

	assert_eq(shield.intercept_called, 1,
		"Shield should attempt to intercept the hit")
	assert_eq(enemy.hit_called, 0,
		"Enemy should not receive damage when shield blocks")


func test_shield_forwards_hit_when_inactive() -> void:
	shield._active = false

	hit_area.on_hit_with_bullet_info_and_damage(Vector2.LEFT, null, false, false, 2.0, true)

	assert_eq(shield.intercept_called, 0,
		"Shield should not attempt intercept when inactive")
	assert_eq(enemy.hit_called, 1,
		"Enemy should receive damage when shield is inactive")


func test_shield_forwards_hit_when_not_blocking() -> void:
	shield._active = true
	shield.should_block = false

	hit_area.on_hit_with_bullet_info_and_damage(Vector2.UP, null, false, false, 5.0, true)

	assert_eq(shield.intercept_called, 1,
		"Shield should attempt intercept")
	assert_eq(enemy.hit_called, 1,
		"Enemy should receive damage when shield fails to block")


func test_hit_reaction_target_set_on_shield_block() -> void:
	shield._active = true
	shield.should_block = true

	var hit_dir := Vector2(1, 0)
	hit_area.on_hit_with_bullet_info_and_damage(hit_dir, null, false, false, 1.0, false)

	assert_eq(enemy.hit_reaction_called, 1,
		"Hit reaction target should be set when shield absorbs hit")
	assert_eq(enemy.hit_reaction_target, -hit_dir.normalized(),
		"Hit reaction should be opposite to hit direction")


func test_no_hit_reaction_when_shield_fails() -> void:
	shield._active = true
	shield.should_block = false

	hit_area.on_hit_with_bullet_info_and_damage(Vector2.RIGHT, null, false, false, 1.0, false)

	assert_eq(enemy.hit_reaction_called, 0,
		"No hit reaction when shield does not block")


# ============================================================================
# Forward to Enemy Tests
# ============================================================================


func test_forward_passes_all_parameters() -> void:
	shield._active = false

	hit_area.on_hit_with_bullet_info_and_damage(Vector2.DOWN, null, true, true, 3.5, true)

	assert_eq(enemy.last_hit_direction, Vector2.DOWN)
	assert_eq(enemy.last_ricocheted, true)
	assert_eq(enemy.last_penetrated, true)
	assert_eq(enemy.last_bullet_damage, 3.5)
	assert_eq(enemy.last_is_from_player, true)


func test_forward_falls_back_to_on_hit() -> void:
	var simple_enemy := MockEnemyOnlyOnHit.new()
	hit_area.enemy = simple_enemy
	hit_area.shield_component = null

	hit_area.on_hit_with_bullet_info_and_damage(Vector2.RIGHT, null, false, false, 1.0, false)

	assert_eq(simple_enemy.on_hit_called, 1,
		"Should fall back to on_hit when on_hit_with_bullet_info is unavailable")


func test_no_forward_when_enemy_null() -> void:
	hit_area.enemy = null
	hit_area.shield_component = null

	# Should not crash
	hit_area.on_hit_with_bullet_info_and_damage(Vector2.RIGHT, null, false, false, 1.0, false)


func test_no_shield_component_forwards_directly() -> void:
	hit_area.shield_component = null

	hit_area.on_hit_with_bullet_info_and_damage(Vector2.LEFT, null, false, false, 2.0, true)

	assert_eq(enemy.hit_called, 1,
		"Should forward to enemy when no shield component")


# ============================================================================
# On Hit Overload Signature Tests
# ============================================================================


func test_on_hit_with_bullet_info_delegates_with_default_damage() -> void:
	shield._active = false

	hit_area.on_hit_with_bullet_info(Vector2.LEFT, null, true, false, true)

	assert_eq(enemy.hit_called, 1)
	assert_eq(enemy.last_bullet_damage, 1.0,
		"on_hit_with_bullet_info should use default damage of 1.0")
	assert_eq(enemy.last_ricocheted, true)
	assert_eq(enemy.last_is_from_player, true)


func test_on_hit_with_info_delegates_with_defaults() -> void:
	shield._active = false

	hit_area.on_hit_with_info(Vector2.UP, null)

	assert_eq(enemy.hit_called, 1)
	assert_eq(enemy.last_hit_direction, Vector2.UP)
	assert_eq(enemy.last_ricocheted, false,
		"on_hit_with_info should default ricocheted to false")
	assert_eq(enemy.last_penetrated, false,
		"on_hit_with_info should default penetrated to false")
	assert_eq(enemy.last_bullet_damage, 1.0)
	assert_eq(enemy.last_is_from_player, false)


func test_on_hit_no_args_delegates_with_all_defaults() -> void:
	shield._active = false

	hit_area.on_hit()

	assert_eq(enemy.hit_called, 1)
	assert_eq(enemy.last_hit_direction, Vector2.RIGHT,
		"on_hit should default direction to Vector2.RIGHT")
	assert_eq(enemy.last_bullet_damage, 1.0)
	assert_eq(enemy.last_is_from_player, false)


func test_on_hit_no_args_checked_by_shield() -> void:
	shield._active = true
	shield.should_block = true

	hit_area.on_hit()

	assert_eq(shield.intercept_called, 1,
		"on_hit() should still check shield")
	assert_eq(enemy.hit_called, 0,
		"on_hit() should be blocked by active shield")
