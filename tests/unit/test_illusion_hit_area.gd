extends GutTest
## Unit tests for illusion_hit_area.gd hit detection for illusions.
##
## Tests hit forwarding to parent illusion and is_alive dependency
## on parent state.


# ============================================================================
# Mock IllusionParent for Hit Forwarding Tests
# ============================================================================


class MockIllusionParent:
	## Whether the parent illusion is alive.
	var _is_alive: bool = true

	## Track damage received.
	var damage_received: float = 0.0

	## Track number of hits.
	var hit_count: int = 0

	## Take damage.
	func take_damage(amount: float) -> void:
		damage_received += amount
		hit_count += 1
		if damage_received >= 1.0:
			_is_alive = false

	## Check if alive.
	func is_alive() -> bool:
		return _is_alive


# ============================================================================
# Mock IllusionHitArea for Logic Tests
# ============================================================================


class MockIllusionHitArea:
	## Reference to the parent IllusionEffect.
	var illusion_parent = null

	## Called when a bullet hits this illusion.
	func on_hit() -> void:
		if illusion_parent and illusion_parent.has_method("take_damage"):
			illusion_parent.take_damage(1.0)

	## Extended hit handler with bullet info and damage.
	func on_hit_with_bullet_info_and_damage(
		_direction: Vector2, _caliber_data, _is_ricochet: bool,
		_is_penetration: bool, _damage: float, _from_player: bool
	) -> void:
		on_hit()

	## Extended hit handler with bullet info.
	func on_hit_with_bullet_info(
		_direction: Vector2, _caliber_data, _is_ricochet: bool,
		_is_penetration: bool, _from_player: bool
	) -> void:
		on_hit()

	## Extended hit handler with caliber info.
	func on_hit_with_info(_direction: Vector2, _caliber_data) -> void:
		on_hit()

	## Report as alive based on parent.
	func is_alive() -> bool:
		if illusion_parent and illusion_parent.has_method("is_alive"):
			return illusion_parent.is_alive()
		return false


var hit_area: MockIllusionHitArea
var parent: MockIllusionParent


func before_each() -> void:
	hit_area = MockIllusionHitArea.new()
	parent = MockIllusionParent.new()
	hit_area.illusion_parent = parent


func after_each() -> void:
	hit_area = null
	parent = null


# ============================================================================
# Hit Forwarding Tests
# ============================================================================


func test_on_hit_forwards_to_parent() -> void:
	hit_area.on_hit()

	assert_eq(parent.hit_count, 1,
		"on_hit should forward to parent's take_damage")
	assert_eq(parent.damage_received, 1.0,
		"Parent should receive 1.0 damage per hit")


func test_on_hit_with_bullet_info_and_damage_forwards() -> void:
	hit_area.on_hit_with_bullet_info_and_damage(
		Vector2.RIGHT, null, false, false, 10.0, true)

	assert_eq(parent.hit_count, 1,
		"on_hit_with_bullet_info_and_damage should forward to parent")


func test_on_hit_with_bullet_info_forwards() -> void:
	hit_area.on_hit_with_bullet_info(
		Vector2.RIGHT, null, false, false, true)

	assert_eq(parent.hit_count, 1,
		"on_hit_with_bullet_info should forward to parent")


func test_on_hit_with_info_forwards() -> void:
	hit_area.on_hit_with_info(Vector2.RIGHT, null)

	assert_eq(parent.hit_count, 1,
		"on_hit_with_info should forward to parent")


func test_on_hit_no_parent() -> void:
	hit_area.illusion_parent = null
	# Should not crash
	hit_area.on_hit()

	# No assertion needed — just verifying no crash


func test_on_hit_kills_parent() -> void:
	hit_area.on_hit()

	assert_false(parent.is_alive(),
		"Parent illusion should die after 1 hit (1 HP)")


# ============================================================================
# is_alive Dependency Tests
# ============================================================================


func test_is_alive_when_parent_alive() -> void:
	assert_true(hit_area.is_alive(),
		"Hit area should report alive when parent is alive")


func test_not_alive_when_parent_dead() -> void:
	parent._is_alive = false

	assert_false(hit_area.is_alive(),
		"Hit area should report not alive when parent is dead")


func test_not_alive_when_no_parent() -> void:
	hit_area.illusion_parent = null

	assert_false(hit_area.is_alive(),
		"Hit area should report not alive when parent is null")


func test_alive_changes_after_hit() -> void:
	assert_true(hit_area.is_alive())

	hit_area.on_hit()

	assert_false(hit_area.is_alive(),
		"Hit area should report not alive after parent takes fatal damage")
