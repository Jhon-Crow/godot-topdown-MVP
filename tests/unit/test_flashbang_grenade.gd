extends GutTest
## Unit tests for FlashbangGrenade.
##
## Tests the flashbang grenade implementation including effect application,
## line of sight checks, and sound/visual effects.


# ============================================================================
# Mock Classes for Testing
# ============================================================================


class MockFlashbangGrenade:
	## Duration of blindness effect in seconds.
	var blindness_duration: float = 12.0

	## Duration of stun effect in seconds.
	var stun_duration: float = 6.0

	## Effect radius - doubled per user request.
	var effect_radius: float = 400.0

	## Position of the grenade.
	var global_position: Vector2 = Vector2.ZERO

	## Sound range multiplier (from GrenadeBase).
	var sound_range_multiplier: float = 1.0

	## Tracking for method calls
	var flash_effect_spawned: int = 0
	var enemies_affected: Array = []

	## Mock player for testing.
	var _mock_player: MockPlayer = null

	## Mock line of sight enabled (Issue #469 - walls block effects).
	var _mock_line_of_sight: bool = true

	## Set mock player for testing.
	func set_mock_player(player: MockPlayer) -> void:
		_mock_player = player

	## Set mock line of sight for testing wall blocking.
	func set_mock_line_of_sight(enabled: bool) -> void:
		_mock_line_of_sight = enabled

	## Check if position is in effect radius.
	func is_in_effect_radius(pos: Vector2) -> bool:
		return global_position.distance_to(pos) <= effect_radius

	## Get the effect radius for this grenade type.
	func _get_effect_radius() -> float:
		return effect_radius

	## Apply flashbang effects to an enemy.
	func apply_effects_to_enemy(enemy: Node2D) -> void:
		enemies_affected.append({
			"enemy": enemy,
			"blindness": blindness_duration,
			"stun": stun_duration
		})

	## Spawn visual flash effect.
	func spawn_flash() -> void:
		flash_effect_spawned += 1

	## Mock line of sight check.
	func _has_line_of_sight_to(_target) -> bool:
		return _mock_line_of_sight

	## Check if the player is within the flashbang effect radius and has line of sight.
	## Walls block both the visual and audio effects of the flashbang (Issue #469).
	func _is_player_in_zone() -> bool:
		if _mock_player == null:
			return false

		# Check if player is in effect radius first
		if not is_in_effect_radius(_mock_player.global_position):
			return false

		# Check line of sight - walls block the flashbang effect (Issue #469)
		return _has_line_of_sight_to(_mock_player)


class MockEnemy:
	extends Node2D

	var blindness_applied: float = 0.0
	var stun_applied: float = 0.0

	func apply_blindness(duration: float) -> void:
		blindness_applied = duration

	func apply_stun(duration: float) -> void:
		stun_applied = duration


class MockPlayer:
	extends Node2D

	## Player position for zone detection.


var grenade: MockFlashbangGrenade


func before_each() -> void:
	grenade = MockFlashbangGrenade.new()


func after_each() -> void:
	grenade = null


# ============================================================================
# Default Property Tests
# ============================================================================


func test_default_blindness_duration() -> void:
	assert_eq(grenade.blindness_duration, 12.0,
		"Default blindness duration should be 12 seconds")


func test_default_stun_duration() -> void:
	assert_eq(grenade.stun_duration, 6.0,
		"Default stun duration should be 6 seconds")


func test_default_effect_radius() -> void:
	assert_eq(grenade.effect_radius, 400.0,
		"Default effect radius should be 400 pixels")


func test_get_effect_radius() -> void:
	assert_eq(grenade._get_effect_radius(), 400.0,
		"_get_effect_radius should return effect_radius")


# ============================================================================
# Effect Radius Tests
# ============================================================================


func test_in_effect_radius_at_center() -> void:
	grenade.global_position = Vector2(100, 100)

	assert_true(grenade.is_in_effect_radius(Vector2(100, 100)),
		"Center position should be in radius")


func test_in_effect_radius_at_boundary() -> void:
	grenade.global_position = Vector2(100, 100)

	assert_true(grenade.is_in_effect_radius(Vector2(500, 100)),
		"Position at boundary should be in radius")


func test_out_of_effect_radius() -> void:
	grenade.global_position = Vector2(100, 100)

	assert_false(grenade.is_in_effect_radius(Vector2(600, 100)),
		"Position outside boundary should not be in radius")


func test_in_effect_radius_diagonal() -> void:
	grenade.global_position = Vector2(0, 0)
	# Distance to (282, 282) is ~399, within 400
	assert_true(grenade.is_in_effect_radius(Vector2(282, 282)),
		"Diagonal position within radius should be detected")


func test_out_of_effect_radius_diagonal() -> void:
	grenade.global_position = Vector2(0, 0)
	# Distance to (300, 300) is ~424, outside 400
	assert_false(grenade.is_in_effect_radius(Vector2(300, 300)),
		"Diagonal position outside radius should not be detected")


func test_custom_effect_radius() -> void:
	grenade.effect_radius = 200.0
	grenade.global_position = Vector2(0, 0)

	assert_true(grenade.is_in_effect_radius(Vector2(200, 0)),
		"Position at custom boundary should be in radius")
	assert_false(grenade.is_in_effect_radius(Vector2(201, 0)),
		"Position outside custom boundary should not be in radius")


# ============================================================================
# Effect Application Tests
# ============================================================================


func test_apply_effects_records_enemy() -> void:
	var enemy := MockEnemy.new()

	grenade.apply_effects_to_enemy(enemy)

	assert_eq(grenade.enemies_affected.size(), 1,
		"Should record affected enemy")


func test_apply_effects_uses_blindness_duration() -> void:
	var enemy := MockEnemy.new()

	grenade.apply_effects_to_enemy(enemy)

	assert_eq(grenade.enemies_affected[0]["blindness"], 12.0,
		"Should apply correct blindness duration")


func test_apply_effects_uses_stun_duration() -> void:
	var enemy := MockEnemy.new()

	grenade.apply_effects_to_enemy(enemy)

	assert_eq(grenade.enemies_affected[0]["stun"], 6.0,
		"Should apply correct stun duration")


func test_apply_effects_custom_durations() -> void:
	grenade.blindness_duration = 20.0
	grenade.stun_duration = 10.0
	var enemy := MockEnemy.new()

	grenade.apply_effects_to_enemy(enemy)

	assert_eq(grenade.enemies_affected[0]["blindness"], 20.0,
		"Should use custom blindness duration")
	assert_eq(grenade.enemies_affected[0]["stun"], 10.0,
		"Should use custom stun duration")


func test_apply_effects_multiple_enemies() -> void:
	var enemy1 := MockEnemy.new()
	var enemy2 := MockEnemy.new()
	var enemy3 := MockEnemy.new()

	grenade.apply_effects_to_enemy(enemy1)
	grenade.apply_effects_to_enemy(enemy2)
	grenade.apply_effects_to_enemy(enemy3)

	assert_eq(grenade.enemies_affected.size(), 3,
		"Should affect multiple enemies")


# ============================================================================
# Flash Effect Tests
# ============================================================================


func test_spawn_flash() -> void:
	grenade.spawn_flash()

	assert_eq(grenade.flash_effect_spawned, 1,
		"Should spawn flash effect")


func test_spawn_flash_multiple() -> void:
	grenade.spawn_flash()
	grenade.spawn_flash()

	assert_eq(grenade.flash_effect_spawned, 2,
		"Should be able to spawn multiple flashes")


# ============================================================================
# Configuration Tests
# ============================================================================


func test_configure_for_short_duration() -> void:
	grenade.blindness_duration = 3.0
	grenade.stun_duration = 1.5

	assert_eq(grenade.blindness_duration, 3.0,
		"Short blindness duration should be configurable")
	assert_eq(grenade.stun_duration, 1.5,
		"Short stun duration should be configurable")


func test_configure_for_large_radius() -> void:
	grenade.effect_radius = 800.0
	grenade.global_position = Vector2(0, 0)

	assert_true(grenade.is_in_effect_radius(Vector2(800, 0)),
		"Large radius should work correctly")


func test_configure_for_small_radius() -> void:
	grenade.effect_radius = 50.0
	grenade.global_position = Vector2(0, 0)

	assert_false(grenade.is_in_effect_radius(Vector2(51, 0)),
		"Small radius should work correctly")


# ============================================================================
# Edge Case Tests
# ============================================================================


func test_zero_effect_radius() -> void:
	grenade.effect_radius = 0.0
	grenade.global_position = Vector2(0, 0)

	assert_true(grenade.is_in_effect_radius(Vector2(0, 0)),
		"Zero radius should still include center")
	assert_false(grenade.is_in_effect_radius(Vector2(1, 0)),
		"Zero radius should not include any other position")


func test_zero_durations() -> void:
	grenade.blindness_duration = 0.0
	grenade.stun_duration = 0.0
	var enemy := MockEnemy.new()

	grenade.apply_effects_to_enemy(enemy)

	assert_eq(grenade.enemies_affected[0]["blindness"], 0.0,
		"Zero blindness duration should be valid")
	assert_eq(grenade.enemies_affected[0]["stun"], 0.0,
		"Zero stun duration should be valid")


func test_negative_position() -> void:
	grenade.global_position = Vector2(-100, -100)

	assert_true(grenade.is_in_effect_radius(Vector2(-100, -100)),
		"Should work with negative positions")
	assert_true(grenade.is_in_effect_radius(Vector2(200, -100)),
		"Should work with mixed positions within radius")


func test_very_large_positions() -> void:
	grenade.global_position = Vector2(10000, 10000)

	assert_true(grenade.is_in_effect_radius(Vector2(10000, 10000)),
		"Should work with large positions")
	assert_true(grenade.is_in_effect_radius(Vector2(10400, 10000)),
		"Should correctly calculate large position distances")


# ============================================================================
# Duration Comparison Tests
# ============================================================================


func test_blindness_longer_than_stun() -> void:
	# Default values
	assert_true(grenade.blindness_duration > grenade.stun_duration,
		"Blindness should last longer than stun by default")


func test_effect_ratio() -> void:
	# Blindness should be 2x stun duration by default
	var ratio := grenade.blindness_duration / grenade.stun_duration

	assert_eq(ratio, 2.0,
		"Blindness should be 2x stun duration by default")


# ============================================================================
# Boundary Tests
# ============================================================================


func test_exact_boundary_distance() -> void:
	grenade.global_position = Vector2(0, 0)
	grenade.effect_radius = 100.0

	assert_true(grenade.is_in_effect_radius(Vector2(100, 0)),
		"Exactly at boundary should be included")


func test_just_inside_boundary() -> void:
	grenade.global_position = Vector2(0, 0)
	grenade.effect_radius = 100.0

	assert_true(grenade.is_in_effect_radius(Vector2(99.9, 0)),
		"Just inside boundary should be included")


func test_just_outside_boundary() -> void:
	grenade.global_position = Vector2(0, 0)
	grenade.effect_radius = 100.0

	assert_false(grenade.is_in_effect_radius(Vector2(100.1, 0)),
		"Just outside boundary should not be included")


# ============================================================================
# Relative Positioning Tests
# ============================================================================


func test_positions_in_all_quadrants() -> void:
	grenade.global_position = Vector2(0, 0)
	grenade.effect_radius = 200.0

	# All quadrants
	assert_true(grenade.is_in_effect_radius(Vector2(100, 100)),
		"Bottom-right quadrant should be in radius")
	assert_true(grenade.is_in_effect_radius(Vector2(-100, 100)),
		"Bottom-left quadrant should be in radius")
	assert_true(grenade.is_in_effect_radius(Vector2(-100, -100)),
		"Top-left quadrant should be in radius")
	assert_true(grenade.is_in_effect_radius(Vector2(100, -100)),
		"Top-right quadrant should be in radius")


func test_grenade_at_offset_position() -> void:
	grenade.global_position = Vector2(500, 500)
	grenade.effect_radius = 100.0

	assert_true(grenade.is_in_effect_radius(Vector2(550, 500)),
		"Should detect within radius from offset position")
	assert_false(grenade.is_in_effect_radius(Vector2(0, 0)),
		"Should not detect origin from offset position")


# ============================================================================
# Real-World Scenario Tests
# ============================================================================


func test_small_room_coverage() -> void:
	# A small room is approximately 200 pixels
	grenade.effect_radius = 200.0
	grenade.global_position = Vector2(100, 100)

	# All corners of a 200x200 room centered on grenade should be in range
	assert_true(grenade.is_in_effect_radius(Vector2(0, 0)),
		"Top-left corner should be in range")
	# Note: corners of a square are further than edge midpoints
	# Distance from center to corner of 200x200 square = ~141 pixels


func test_doubled_radius_coverage() -> void:
	# The effect radius was doubled per user request from ~200 to 400
	grenade.effect_radius = 400.0
	grenade.global_position = Vector2(200, 200)

	# Should cover a much larger area
	assert_true(grenade.is_in_effect_radius(Vector2(0, 200)),
		"Should reach 200 pixels to the left")
	assert_true(grenade.is_in_effect_radius(Vector2(400, 200)),
		"Should reach 200 pixels to the right")
	assert_true(grenade.is_in_effect_radius(Vector2(200, 0)),
		"Should reach 200 pixels up")
	assert_true(grenade.is_in_effect_radius(Vector2(200, 400)),
		"Should reach 200 pixels down")


# ============================================================================
# Wall Blocking Tests (Issue #469)
# Tests for "визуальный и обычный эффект светошумовой гранаты не должен
# проходить сквозь стены" - flashbang effects should not pass through walls
# ============================================================================


func test_player_in_zone_with_line_of_sight() -> void:
	grenade.global_position = Vector2(100, 100)
	var player := MockPlayer.new()
	player.global_position = Vector2(200, 100)  # In radius, distance = 100

	grenade.set_mock_player(player)
	grenade.set_mock_line_of_sight(true)

	assert_true(grenade._is_player_in_zone(),
		"Player with clear line of sight should be in zone")


func test_player_not_in_zone_when_wall_blocks() -> void:
	grenade.global_position = Vector2(100, 100)
	var player := MockPlayer.new()
	player.global_position = Vector2(200, 100)  # In radius, distance = 100

	grenade.set_mock_player(player)
	grenade.set_mock_line_of_sight(false)  # Wall blocking

	assert_false(grenade._is_player_in_zone(),
		"Player behind wall should NOT be in zone (Issue #469)")


func test_player_not_in_zone_when_outside_radius() -> void:
	grenade.global_position = Vector2(100, 100)
	grenade.effect_radius = 100.0
	var player := MockPlayer.new()
	player.global_position = Vector2(300, 100)  # Outside radius, distance = 200

	grenade.set_mock_player(player)
	grenade.set_mock_line_of_sight(true)

	assert_false(grenade._is_player_in_zone(),
		"Player outside radius should not be in zone even with clear LOS")


func test_player_not_in_zone_when_both_blocked_and_outside() -> void:
	grenade.global_position = Vector2(100, 100)
	grenade.effect_radius = 100.0
	var player := MockPlayer.new()
	player.global_position = Vector2(300, 100)  # Outside radius

	grenade.set_mock_player(player)
	grenade.set_mock_line_of_sight(false)  # Also blocked

	assert_false(grenade._is_player_in_zone(),
		"Player outside radius AND behind wall should not be in zone")


func test_no_player_returns_false() -> void:
	grenade.global_position = Vector2(100, 100)
	# No player set

	assert_false(grenade._is_player_in_zone(),
		"Should return false when no player is found")


func test_player_at_boundary_with_wall() -> void:
	grenade.global_position = Vector2(100, 100)
	grenade.effect_radius = 200.0
	var player := MockPlayer.new()
	player.global_position = Vector2(300, 100)  # Exactly at boundary, distance = 200

	grenade.set_mock_player(player)
	grenade.set_mock_line_of_sight(false)  # Wall blocking

	assert_false(grenade._is_player_in_zone(),
		"Player at boundary behind wall should not be in zone (Issue #469)")


func test_player_at_boundary_without_wall() -> void:
	grenade.global_position = Vector2(100, 100)
	grenade.effect_radius = 200.0
	var player := MockPlayer.new()
	player.global_position = Vector2(300, 100)  # Exactly at boundary, distance = 200

	grenade.set_mock_player(player)
	grenade.set_mock_line_of_sight(true)  # Clear LOS

	assert_true(grenade._is_player_in_zone(),
		"Player at boundary with clear LOS should be in zone")


func test_player_very_close_behind_wall() -> void:
	grenade.global_position = Vector2(100, 100)
	var player := MockPlayer.new()
	player.global_position = Vector2(110, 100)  # Very close, distance = 10

	grenade.set_mock_player(player)
	grenade.set_mock_line_of_sight(false)  # Wall between them (corner case)

	assert_false(grenade._is_player_in_zone(),
		"Even very close player behind wall should not be affected (Issue #469)")
