extends GutTest
## Unit tests for shell casing reaction to explosions (Issue #432, #506, #522).
##
## Tests that shell casings on the floor react appropriately to explosions:
## 1. Casings inside lethal blast zone scatter with strong impulse
## 2. Casings in proximity zone receive weak impulse
## 3. Casings far away are not affected
## 4. Works with both FragGrenade and FlashbangGrenade
## 5. Casings behind obstacles are NOT pushed (Issue #506)
## 6. Time-frozen casings queue impulse and apply on unfreeze (Issue #522)


# ============================================================================
# Mock Classes for Logic Tests
# ============================================================================


class MockCasing:
	## Simulates a shell casing on the floor.
	## Updated for Issue #522: supports pending impulse during time freeze.
	var global_position: Vector2 = Vector2.ZERO
	var received_kicks: Array = []
	var _has_landed: bool = true
	var _is_time_frozen: bool = false
	var _pending_kick_impulse: Vector2 = Vector2.ZERO

	func receive_kick(impulse: Vector2) -> void:
		# Issue #522: Queue impulse during freeze instead of discarding
		if _is_time_frozen:
			_pending_kick_impulse += impulse
			return
		received_kicks.append(impulse)

	func unfreeze_time() -> void:
		_is_time_frozen = false
		# Issue #522: Apply pending impulse on unfreeze
		if _pending_kick_impulse != Vector2.ZERO:
			receive_kick(_pending_kick_impulse)
			_pending_kick_impulse = Vector2.ZERO

	func has_method(method_name: String) -> bool:
		return method_name == "receive_kick" or method_name == "unfreeze_time"

	func get_total_impulse_strength() -> float:
		var total: float = 0.0
		for kick in received_kicks:
			total += kick.length()
		return total


## Represents an obstacle segment (wall) that blocks line of sight (Issue #506).
class MockObstacle:
	var start: Vector2
	var end: Vector2

	func _init(s: Vector2, e: Vector2) -> void:
		start = s
		end = e


class MockGrenade:
	## Simulates a grenade for testing casing scatter.
	var global_position: Vector2 = Vector2.ZERO
	var _mock_casings: Array = []
	## Obstacles that block shockwave line of sight (Issue #506).
	var _mock_obstacles: Array = []

	## Set mock casings for testing.
	func set_mock_casings(casings: Array) -> void:
		_mock_casings = casings

	## Set mock obstacles (wall segments) for testing (Issue #506).
	func set_mock_obstacles(obstacles: Array) -> void:
		_mock_obstacles = obstacles

	## Check if a line segment from A to B intersects with any obstacle (Issue #506).
	## Uses simple 2D line segment intersection test.
	func _is_blocked_by_obstacle(from: Vector2, to: Vector2) -> bool:
		for obstacle in _mock_obstacles:
			if _segments_intersect(from, to, obstacle.start, obstacle.end):
				return true
		return false

	## 2D line segment intersection test using cross product method.
	static func _segments_intersect(a1: Vector2, a2: Vector2, b1: Vector2, b2: Vector2) -> bool:
		var d1 := _cross_2d(b2 - b1, a1 - b1)
		var d2 := _cross_2d(b2 - b1, a2 - b1)
		var d3 := _cross_2d(a2 - a1, b1 - a1)
		var d4 := _cross_2d(a2 - a1, b2 - a1)
		if ((d1 > 0 and d2 < 0) or (d1 < 0 and d2 > 0)) and \
		   ((d3 > 0 and d4 < 0) or (d3 < 0 and d4 > 0)):
			return true
		return false

	## 2D cross product of two vectors.
	static func _cross_2d(a: Vector2, b: Vector2) -> float:
		return a.x * b.y - a.y * b.x

	## Scatter shell casings within and near the explosion radius (Issue #432, #506).
	## This is a copy of the actual implementation for testing logic.
	## Issue #506: Now checks obstacle line of sight before applying impulse.
	func scatter_casings(effect_radius: float) -> void:
		if _mock_casings.is_empty():
			return

		# Proximity zone extends to 1.5x the effect radius
		var proximity_radius := effect_radius * 1.5

		# Impulse strengths (calibrated based on player kick force ~6-9 units)
		var lethal_impulse_base: float = 45.0
		var proximity_impulse_base: float = 10.0

		for casing in _mock_casings:
			if casing == null:
				continue

			var distance := global_position.distance_to(casing.global_position)

			# Skip casings too far away
			if distance > proximity_radius:
				continue

			# Issue #506: Check if obstacle blocks line of sight to casing
			if _is_blocked_by_obstacle(global_position, casing.global_position):
				continue

			# Calculate direction from explosion to casing
			var direction := (casing.global_position - global_position).normalized()

			var impulse_strength: float = 0.0

			if distance <= effect_radius:
				# Inside lethal zone - strong scatter effect
				var distance_factor := 1.0 - (distance / effect_radius)
				impulse_strength = lethal_impulse_base * sqrt(distance_factor + 0.1)
			else:
				# Proximity zone - weak push
				var proximity_factor := 1.0 - ((distance - effect_radius) / (proximity_radius - effect_radius))
				impulse_strength = proximity_impulse_base * proximity_factor

			# Apply the kick impulse to the casing
			if casing.has_method("receive_kick"):
				var impulse := direction * impulse_strength
				casing.receive_kick(impulse)


var grenade: MockGrenade


func before_each() -> void:
	grenade = MockGrenade.new()
	grenade.global_position = Vector2(100, 100)


func after_each() -> void:
	grenade = null


# ============================================================================
# Issue #432 Tests: Casing Scatter in Lethal Zone
# ============================================================================


func test_casing_in_lethal_zone_receives_strong_impulse() -> void:
	# Requirement 1: Casings in lethal blast zone should scatter
	var casing := MockCasing.new()
	casing.global_position = Vector2(150, 100)  # 50 units away, inside 225 radius

	grenade.set_mock_casings([casing])
	grenade.scatter_casings(225.0)

	assert_gt(casing.received_kicks.size(), 0,
		"Casing in lethal zone should receive kick")
	assert_gt(casing.get_total_impulse_strength(), 30.0,
		"Casing in lethal zone should receive strong impulse (>30)")


func test_casing_at_explosion_center_receives_strongest_impulse() -> void:
	var casing_center := MockCasing.new()
	casing_center.global_position = Vector2(101, 100)  # Very close to center

	var casing_edge := MockCasing.new()
	casing_edge.global_position = Vector2(300, 100)  # Near edge of 225 radius

	grenade.set_mock_casings([casing_center, casing_edge])
	grenade.scatter_casings(225.0)

	assert_gt(casing_center.get_total_impulse_strength(), casing_edge.get_total_impulse_strength(),
		"Casing closer to center should receive stronger impulse")


func test_multiple_casings_in_lethal_zone_all_scatter() -> void:
	var casings: Array = []
	for i in range(5):
		var casing := MockCasing.new()
		# Place casings around the explosion within lethal zone
		casing.global_position = Vector2(100 + i * 30, 100 + i * 20)
		casings.append(casing)

	grenade.set_mock_casings(casings)
	grenade.scatter_casings(225.0)

	for casing in casings:
		assert_gt(casing.received_kicks.size(), 0,
			"All casings in lethal zone should receive kick")


# ============================================================================
# Issue #432 Tests: Proximity Zone (Weak Impulse)
# ============================================================================


func test_casing_in_proximity_zone_receives_weak_impulse() -> void:
	# Requirement 2: Casings near lethal zone should move slightly
	var casing := MockCasing.new()
	# Place casing just outside lethal zone (225) but inside proximity (337.5)
	casing.global_position = Vector2(350, 100)  # 250 units away

	grenade.set_mock_casings([casing])
	grenade.scatter_casings(225.0)

	assert_gt(casing.received_kicks.size(), 0,
		"Casing in proximity zone should receive kick")
	assert_lt(casing.get_total_impulse_strength(), 15.0,
		"Casing in proximity zone should receive weak impulse (<15)")


func test_proximity_impulse_weaker_than_lethal_zone() -> void:
	var casing_lethal := MockCasing.new()
	casing_lethal.global_position = Vector2(200, 100)  # 100 units away, inside lethal

	var casing_proximity := MockCasing.new()
	casing_proximity.global_position = Vector2(350, 100)  # 250 units away, proximity

	grenade.set_mock_casings([casing_lethal, casing_proximity])
	grenade.scatter_casings(225.0)

	assert_gt(casing_lethal.get_total_impulse_strength(), casing_proximity.get_total_impulse_strength(),
		"Lethal zone impulse should be stronger than proximity zone")


# ============================================================================
# Issue #432 Tests: Casings Outside Effect Range
# ============================================================================


func test_casing_far_away_not_affected() -> void:
	var casing := MockCasing.new()
	casing.global_position = Vector2(500, 100)  # 400 units away, outside proximity (337.5)

	grenade.set_mock_casings([casing])
	grenade.scatter_casings(225.0)

	assert_eq(casing.received_kicks.size(), 0,
		"Casing far from explosion should not receive kick")


func test_casing_just_outside_proximity_not_affected() -> void:
	var casing := MockCasing.new()
	# Proximity radius = 225 * 1.5 = 337.5
	casing.global_position = Vector2(440, 100)  # 340 units away, just outside

	grenade.set_mock_casings([casing])
	grenade.scatter_casings(225.0)

	assert_eq(casing.received_kicks.size(), 0,
		"Casing just outside proximity zone should not receive kick")


# ============================================================================
# Issue #432 Tests: Direction of Impulse
# ============================================================================


func test_impulse_direction_away_from_explosion() -> void:
	var casing := MockCasing.new()
	casing.global_position = Vector2(200, 100)  # 100 units to the right

	grenade.set_mock_casings([casing])
	grenade.scatter_casings(225.0)

	assert_gt(casing.received_kicks.size(), 0)
	var impulse: Vector2 = casing.received_kicks[0]
	# Impulse should point away from explosion (positive X direction)
	assert_gt(impulse.x, 0, "Impulse should push casing away from explosion")


func test_impulse_direction_different_angles() -> void:
	var casing_right := MockCasing.new()
	casing_right.global_position = Vector2(200, 100)  # Right of explosion

	var casing_up := MockCasing.new()
	casing_up.global_position = Vector2(100, 0)  # Above explosion

	var casing_left := MockCasing.new()
	casing_left.global_position = Vector2(0, 100)  # Left of explosion

	grenade.set_mock_casings([casing_right, casing_up, casing_left])
	grenade.scatter_casings(225.0)

	# Check directions are correct (with some tolerance for random rotation)
	var right_impulse: Vector2 = casing_right.received_kicks[0]
	var up_impulse: Vector2 = casing_up.received_kicks[0]
	var left_impulse: Vector2 = casing_left.received_kicks[0]

	assert_gt(right_impulse.x, 0, "Right casing should be pushed right")
	assert_lt(up_impulse.y, 0, "Up casing should be pushed up (negative Y)")
	assert_lt(left_impulse.x, 0, "Left casing should be pushed left")


# ============================================================================
# Issue #432 Tests: Time-Frozen Casings
# Issue #522: Frozen casings now queue impulse instead of discarding
# ============================================================================


func test_time_frozen_casing_queues_impulse() -> void:
	# Issue #522: Frozen casings should queue the impulse, not discard it
	var casing := MockCasing.new()
	casing.global_position = Vector2(150, 100)  # Inside lethal zone
	casing._is_time_frozen = true

	grenade.set_mock_casings([casing])
	grenade.scatter_casings(225.0)

	# During freeze, no kicks are applied immediately
	assert_eq(casing.received_kicks.size(), 0,
		"Time-frozen casing should not receive kick immediately")
	# But the impulse should be queued
	assert_ne(casing._pending_kick_impulse, Vector2.ZERO,
		"Time-frozen casing should have pending impulse queued")


func test_time_frozen_casing_applies_impulse_on_unfreeze() -> void:
	# Issue #522: When time unfreezes, pending impulse should be applied
	var casing := MockCasing.new()
	casing.global_position = Vector2(150, 100)  # Inside lethal zone
	casing._is_time_frozen = true

	grenade.set_mock_casings([casing])
	grenade.scatter_casings(225.0)

	# Verify impulse was queued
	assert_eq(casing.received_kicks.size(), 0,
		"No kicks during freeze")
	var pending := casing._pending_kick_impulse
	assert_ne(pending, Vector2.ZERO,
		"Impulse should be pending")

	# Unfreeze time - pending impulse should be applied
	casing.unfreeze_time()

	assert_gt(casing.received_kicks.size(), 0,
		"Casing should receive kick after unfreeze")
	assert_gt(casing.get_total_impulse_strength(), 0.0,
		"Applied impulse should have non-zero strength")
	assert_eq(casing._pending_kick_impulse, Vector2.ZERO,
		"Pending impulse should be cleared after unfreeze")


func test_time_frozen_casing_impulse_direction_preserved() -> void:
	# Issue #522: Direction of queued impulse should be correct after unfreeze
	var casing := MockCasing.new()
	casing.global_position = Vector2(200, 100)  # 100 units to the right
	casing._is_time_frozen = true

	grenade.set_mock_casings([casing])
	grenade.scatter_casings(225.0)

	# Unfreeze and check direction
	casing.unfreeze_time()

	assert_gt(casing.received_kicks.size(), 0)
	var impulse: Vector2 = casing.received_kicks[0]
	# Impulse should point away from explosion (positive X direction)
	assert_gt(impulse.x, 0,
		"Queued impulse should preserve direction away from explosion")


# ============================================================================
# Issue #432 Tests: No Casings in Scene
# ============================================================================


func test_no_casings_does_not_crash() -> void:
	# Empty casings array - should not crash
	grenade.set_mock_casings([])
	grenade.scatter_casings(225.0)
	# Test passes if no crash occurs
	assert_true(true, "Should handle empty casings array gracefully")


# ============================================================================
# Issue #432 Tests: Different Grenade Types
# ============================================================================


func test_flashbang_smaller_effective_radius() -> void:
	# Flashbang uses 40% of its radius (400 * 0.4 = 160) as lethal-equivalent
	var casing := MockCasing.new()
	casing.global_position = Vector2(200, 100)  # 100 units away

	grenade.set_mock_casings([casing])
	# Flashbang effective radius: 160 (40% of 400)
	grenade.scatter_casings(160.0)

	assert_gt(casing.received_kicks.size(), 0,
		"Casing should be affected by flashbang explosion")


func test_frag_grenade_larger_effective_radius() -> void:
	# FragGrenade uses full 225 radius
	var casing := MockCasing.new()
	casing.global_position = Vector2(300, 100)  # 200 units away, inside 225

	grenade.set_mock_casings([casing])
	grenade.scatter_casings(225.0)

	assert_gt(casing.received_kicks.size(), 0,
		"Casing should be affected by frag grenade explosion")


# ============================================================================
# Edge Cases
# ============================================================================


func test_casing_at_exact_lethal_radius_edge() -> void:
	var casing := MockCasing.new()
	casing.global_position = Vector2(325, 100)  # Exactly at 225 radius

	grenade.set_mock_casings([casing])
	grenade.scatter_casings(225.0)

	# Should still receive some impulse (minimum for lethal zone edge)
	assert_gt(casing.received_kicks.size(), 0,
		"Casing at lethal radius edge should receive kick")


func test_casing_at_exact_proximity_radius_edge() -> void:
	var casing := MockCasing.new()
	# Proximity radius = 225 * 1.5 = 337.5
	casing.global_position = Vector2(437.5, 100)  # Exactly at proximity radius

	grenade.set_mock_casings([casing])
	grenade.scatter_casings(225.0)

	# Should receive minimal impulse
	assert_gt(casing.received_kicks.size(), 0,
		"Casing at proximity radius edge should receive (minimal) kick")


# ============================================================================
# Issue #506 Tests: Obstacle Blocking (Line of Sight)
# ============================================================================


func test_casing_behind_wall_not_pushed() -> void:
	# Issue #506: Casing behind a wall should NOT be pushed by explosion
	var casing := MockCasing.new()
	casing.global_position = Vector2(200, 100)  # 100 units away, inside lethal zone

	# Place a wall between grenade and casing
	var wall := MockObstacle.new(Vector2(150, 0), Vector2(150, 200))  # Vertical wall at x=150

	grenade.set_mock_casings([casing])
	grenade.set_mock_obstacles([wall])
	grenade.scatter_casings(225.0)

	assert_eq(casing.received_kicks.size(), 0,
		"Casing behind a wall should NOT receive kick from explosion")


func test_casing_not_behind_wall_still_pushed() -> void:
	# Issue #506: Casing with clear line of sight should still be pushed
	var casing := MockCasing.new()
	casing.global_position = Vector2(200, 100)  # 100 units away, inside lethal zone

	# Place a wall that does NOT block the path (wall is above the line of fire)
	var wall := MockObstacle.new(Vector2(150, 0), Vector2(150, 50))  # Wall ends at y=50, casing at y=100

	grenade.set_mock_casings([casing])
	grenade.set_mock_obstacles([wall])
	grenade.scatter_casings(225.0)

	assert_gt(casing.received_kicks.size(), 0,
		"Casing with clear line of sight should still receive kick")


func test_some_casings_blocked_some_not() -> void:
	# Issue #506: Mix of blocked and unblocked casings
	var casing_exposed := MockCasing.new()
	casing_exposed.global_position = Vector2(200, 100)  # Same Y, no wall in the way

	var casing_blocked := MockCasing.new()
	casing_blocked.global_position = Vector2(100, 300)  # Below the wall

	# Horizontal wall at y=200, blocking path from grenade (100,100) to casing (100,300)
	var wall := MockObstacle.new(Vector2(50, 200), Vector2(150, 200))

	grenade.set_mock_casings([casing_exposed, casing_blocked])
	grenade.set_mock_obstacles([wall])
	grenade.scatter_casings(225.0)

	assert_gt(casing_exposed.received_kicks.size(), 0,
		"Exposed casing should receive kick")
	assert_eq(casing_blocked.received_kicks.size(), 0,
		"Blocked casing should NOT receive kick")


func test_casing_in_proximity_zone_behind_wall_not_pushed() -> void:
	# Issue #506: Casing in proximity zone behind wall should not be pushed
	var casing := MockCasing.new()
	casing.global_position = Vector2(350, 100)  # 250 units away, in proximity zone

	# Wall between grenade and casing
	var wall := MockObstacle.new(Vector2(250, 0), Vector2(250, 200))

	grenade.set_mock_casings([casing])
	grenade.set_mock_obstacles([wall])
	grenade.scatter_casings(225.0)

	assert_eq(casing.received_kicks.size(), 0,
		"Casing in proximity zone behind wall should NOT receive kick")


# ============================================================================
# Issue #522 Tests: Power Fantasy Explosion Sequence Simulation
# ============================================================================


func test_power_fantasy_explosion_sequence() -> void:
	# Issue #522: Simulates the exact sequence that occurs in Power Fantasy mode:
	# 1. Grenade explodes
	# 2. PowerFantasyEffectsManager triggers time freeze (casings get frozen)
	# 3. scatter_casings() runs (casings are already frozen)
	# 4. Time unfreezes later (casings should scatter at this point)
	var casing1 := MockCasing.new()
	casing1.global_position = Vector2(150, 100)  # Inside lethal zone
	var casing2 := MockCasing.new()
	casing2.global_position = Vector2(250, 100)  # Also inside lethal zone

	# Step 1: Time freeze happens (before scatter_casings)
	casing1._is_time_frozen = true
	casing2._is_time_frozen = true

	# Step 2: scatter_casings runs while casings are frozen
	grenade.set_mock_casings([casing1, casing2])
	grenade.scatter_casings(225.0)

	# Verify: no immediate kicks, but impulses are queued
	assert_eq(casing1.received_kicks.size(), 0, "No immediate kick during freeze")
	assert_eq(casing2.received_kicks.size(), 0, "No immediate kick during freeze")
	assert_ne(casing1._pending_kick_impulse, Vector2.ZERO, "Impulse queued for casing1")
	assert_ne(casing2._pending_kick_impulse, Vector2.ZERO, "Impulse queued for casing2")

	# Step 3: Time unfreezes
	casing1.unfreeze_time()
	casing2.unfreeze_time()

	# Verify: both casings scatter after unfreeze
	assert_gt(casing1.received_kicks.size(), 0,
		"Casing1 should scatter after unfreeze")
	assert_gt(casing2.received_kicks.size(), 0,
		"Casing2 should scatter after unfreeze")
	assert_gt(casing1.get_total_impulse_strength(), 0.0,
		"Casing1 should have non-zero impulse")
	assert_gt(casing2.get_total_impulse_strength(), 0.0,
		"Casing2 should have non-zero impulse")


func test_multiple_explosions_during_freeze_accumulate() -> void:
	# Issue #522: If multiple explosions happen during freeze, impulses should add up
	var casing := MockCasing.new()
	casing.global_position = Vector2(150, 100)  # Inside lethal zone
	casing._is_time_frozen = true

	# First explosion
	grenade.set_mock_casings([casing])
	grenade.scatter_casings(225.0)

	var first_pending := casing._pending_kick_impulse

	# Second explosion from different position
	grenade.global_position = Vector2(100, 50)  # Move grenade
	grenade.scatter_casings(225.0)

	# Impulses should accumulate
	assert_ne(casing._pending_kick_impulse, first_pending,
		"Multiple explosions should accumulate pending impulse")

	# Unfreeze and verify combined impulse is applied
	casing.unfreeze_time()
	assert_gt(casing.received_kicks.size(), 0,
		"Accumulated impulse should be applied on unfreeze")
