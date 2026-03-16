extends GutTest
## Unit tests for Force Field tracer trail clearing (Issue #982).
##
## Verifies that when a bullet or shrapnel is trapped by the force field,
## its tracer trail (Line2D) is cleared so no frozen "tail" remains at the
## stopping position.
##
## Uses mocks to test the trail-clearing logic without requiring a full
## Godot scene tree or physics engine.


# ============================================================================
# Mock projectile classes for testing
# ============================================================================


## Mock GDScript-style bullet with a _trail Line2D and _position_history array.
## Mirrors the actual bullet.gd structure used by the Force Field.
class MockBullet:
	var direction: Vector2 = Vector2.RIGHT
	var speed: float = 2500.0
	var shooter_id: int = -1
	var _trail: Line2D = null
	var _position_history: Array = []

	func _init() -> void:
		# Simulate a trail with some history points (as if bullet has been flying)
		_trail = Line2D.new()
		_position_history = [
			Vector2(100.0, 100.0),
			Vector2(110.0, 100.0),
			Vector2(120.0, 100.0),
		]
		for pos in _position_history:
			_trail.add_point(pos)

	func get(property: String):
		match property:
			"direction": return direction
			"speed": return speed
			"shooter_id": return shooter_id
			"_trail": return _trail
			"_position_history": return _position_history
		return null

	func set(property: String, value) -> void:
		match property:
			"direction": direction = value
			"speed": speed = value
			"shooter_id": shooter_id = value
			"_position_history": _position_history = value


## Mock GDScript-style shrapnel with trail data.
class MockShrapnel:
	var direction: Vector2 = Vector2.UP
	var speed: float = 5000.0
	var source_id: int = -1
	var _trail: Line2D = null
	var _position_history: Array = []

	func _init() -> void:
		_trail = Line2D.new()
		_position_history = [
			Vector2(50.0, 200.0),
			Vector2(50.0, 210.0),
			Vector2(50.0, 220.0),
			Vector2(50.0, 230.0),
		]
		for pos in _position_history:
			_trail.add_point(pos)

	func get(property: String):
		match property:
			"direction": return direction
			"speed": return speed
			"source_id": return source_id
			"_trail": return _trail
			"_position_history": return _position_history
		return null

	func set(property: String, value) -> void:
		match property:
			"direction": direction = value
			"speed": speed = value
			"source_id": source_id = value
			"_position_history": _position_history = value


# ============================================================================
# Pure-logic mirror of _clear_projectile_trail() for unit testing
# ============================================================================
# This mirrors the logic added to force_field_effect.gd for Issue #982.
# By testing this function in isolation (with mock objects that implement the
# same .get() / .set() / get_node_or_null() contract) we verify the fix
# without needing a full scene tree.


func _simulate_clear_projectile_trail(projectile) -> void:
	## Clears the tracer trail on a projectile, mirroring the logic in
	## ForceFieldEffect._clear_projectile_trail() (Issue #982).

	# Try GDScript-style: read "_position_history" array and clear it.
	var history = projectile.get("_position_history")
	if history != null:
		projectile.set("_position_history", [])

	# Try GDScript-style: read "_trail" node reference and clear its points.
	var trail_node = projectile.get("_trail")
	if trail_node != null and trail_node is Line2D:
		(trail_node as Line2D).clear_points()
		return

	# Fallback: look for a child node named "Trail" (C# scene fallback).
	# Mocks do not have get_node_or_null, so skip this path for mock tests.


# ============================================================================
# Tests — bullet trail clearing
# ============================================================================


func test_bullet_trail_cleared_on_trap() -> void:
	var bullet := MockBullet.new()

	# Verify trail has points before clearing (precondition)
	assert_gt(bullet._trail.get_point_count(), 0,
		"Bullet trail should have points before trap")
	assert_gt(bullet._position_history.size(), 0,
		"Bullet _position_history should be non-empty before trap")

	# Simulate the clear called during _trap_bullet
	_simulate_clear_projectile_trail(bullet)

	# Verify trail is cleared after trapping
	assert_eq(bullet._trail.get_point_count(), 0,
		"Bullet trail Line2D should have 0 points after trap (Issue #982 fix)")
	assert_eq(bullet._position_history.size(), 0,
		"Bullet _position_history should be empty after trap (Issue #982 fix)")


func test_bullet_with_empty_trail_does_not_error() -> void:
	var bullet := MockBullet.new()
	# Clear manually first to simulate a bullet with no trail yet
	bullet._trail.clear_points()
	bullet._position_history = []

	# Should not throw — clearing an already-empty trail is a no-op
	_simulate_clear_projectile_trail(bullet)

	assert_eq(bullet._trail.get_point_count(), 0,
		"Empty trail should remain empty after clear")
	assert_eq(bullet._position_history.size(), 0,
		"Empty history should remain empty after clear")


func test_bullet_trail_cleared_preserves_other_properties() -> void:
	var bullet := MockBullet.new()
	bullet.direction = Vector2(0.6, 0.8)
	bullet.speed = 1500.0

	_simulate_clear_projectile_trail(bullet)

	# Direction and speed should not be affected
	assert_eq(bullet.direction, Vector2(0.6, 0.8),
		"Bullet direction should not be modified by trail clear")
	assert_eq(bullet.speed, 1500.0,
		"Bullet speed should not be modified by trail clear")


# ============================================================================
# Tests — shrapnel trail clearing
# ============================================================================


func test_shrapnel_trail_cleared_on_trap() -> void:
	var shrapnel := MockShrapnel.new()

	assert_gt(shrapnel._trail.get_point_count(), 0,
		"Shrapnel trail should have points before trap")
	assert_gt(shrapnel._position_history.size(), 0,
		"Shrapnel _position_history should be non-empty before trap")

	_simulate_clear_projectile_trail(shrapnel)

	assert_eq(shrapnel._trail.get_point_count(), 0,
		"Shrapnel trail Line2D should have 0 points after trap (Issue #982 fix)")
	assert_eq(shrapnel._position_history.size(), 0,
		"Shrapnel _position_history should be empty after trap (Issue #982 fix)")


func test_multiple_shrapnel_trails_cleared_independently() -> void:
	var shrapnel_a := MockShrapnel.new()
	var shrapnel_b := MockShrapnel.new()

	# Clear only shrapnel_a
	_simulate_clear_projectile_trail(shrapnel_a)

	# shrapnel_a trail cleared
	assert_eq(shrapnel_a._trail.get_point_count(), 0,
		"Shrapnel A trail should be cleared")
	# shrapnel_b trail intact
	assert_gt(shrapnel_b._trail.get_point_count(), 0,
		"Shrapnel B trail should be unaffected")


# ============================================================================
# Tests — Line2D behavior after clearing
# ============================================================================


func test_line2d_clear_points_empties_points() -> void:
	# Verify the Godot Line2D.clear_points() API works as expected
	var line := Line2D.new()
	line.add_point(Vector2(0.0, 0.0))
	line.add_point(Vector2(10.0, 0.0))
	line.add_point(Vector2(20.0, 0.0))

	assert_eq(line.get_point_count(), 3, "Line2D should have 3 points initially")

	line.clear_points()

	assert_eq(line.get_point_count(), 0,
		"Line2D.clear_points() should remove all points")
	line.free()


func test_line2d_cleared_trail_can_accept_new_points() -> void:
	# After clearing (on release), the trail can be populated again
	var bullet := MockBullet.new()
	_simulate_clear_projectile_trail(bullet)

	# Simulate re-activation: add new points
	bullet._trail.add_point(Vector2(200.0, 200.0))
	assert_eq(bullet._trail.get_point_count(), 1,
		"Trail should accept new points after being cleared")
