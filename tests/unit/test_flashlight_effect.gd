extends GutTest
## Unit tests for FlashlightEffect.
##
## Tests the flashlight effect including beam detection, enemy blinding,
## per-activation tracking, and cone geometry calculations.


# ============================================================================
# Mock Classes for Testing
# ============================================================================


class MockFlashlightEffect:
	## Light energy constant.
	const LIGHT_ENERGY: float = 8.0

	## Texture scale.
	const LIGHT_TEXTURE_SCALE: float = 6.0

	## Beam half-angle in degrees (9 degrees each side = 18 total).
	const BEAM_HALF_ANGLE_DEG: float = 9.0

	## Maximum beam range for blinding.
	const BEAM_RANGE: float = 600.0

	## Blindness duration in seconds (200ms).
	const BLINDNESS_DURATION: float = 0.2

	## Collision mask for obstacles.
	const OBSTACLE_COLLISION_MASK: int = 4

	## Whether the flashlight is on.
	var _is_on: bool = false

	## Tracks which enemies have been blinded this activation.
	var _blinded_enemies: Dictionary = {}

	## Global position of the flashlight.
	var global_position: Vector2 = Vector2.ZERO

	## Global rotation of the flashlight (radians).
	var global_rotation: float = 0.0

	## Mock: whether line of sight is clear.
	var _mock_line_of_sight: bool = true

	## Mock: tracks blindness applications for testing.
	var blindness_applied: Array = []

	## Set mock line of sight.
	func set_mock_line_of_sight(enabled: bool) -> void:
		_mock_line_of_sight = enabled

	## Turn on the flashlight.
	func turn_on() -> void:
		if _is_on:
			return
		_is_on = true
		_blinded_enemies.clear()

	## Turn off the flashlight.
	func turn_off() -> void:
		if not _is_on:
			return
		_is_on = false
		_blinded_enemies.clear()

	## Check if the flashlight is on.
	func is_on() -> bool:
		return _is_on

	## Check if an enemy is within the flashlight beam cone.
	func _is_enemy_in_beam(enemy_position: Vector2) -> bool:
		var beam_origin := global_position
		var beam_direction := Vector2.RIGHT.rotated(global_rotation)
		var to_enemy := enemy_position - beam_origin
		var distance := to_enemy.length()

		# Check range
		if distance > BEAM_RANGE or distance < 1.0:
			return false

		# Check angle: enemy must be within the beam half-angle
		var angle_to_enemy := abs(beam_direction.angle_to(to_enemy))
		if angle_to_enemy > deg_to_rad(BEAM_HALF_ANGLE_DEG):
			return false

		# Check line of sight (mocked)
		return _mock_line_of_sight

	## Check all enemies and blind those in the beam.
	func check_enemies(enemies: Array) -> void:
		if not _is_on:
			return

		for enemy_data in enemies:
			var enemy_id: int = enemy_data["id"]
			var enemy_position: Vector2 = enemy_data["position"]

			if _blinded_enemies.has(enemy_id):
				continue

			if _is_enemy_in_beam(enemy_position):
				_blind_enemy(enemy_id)

	## Apply blindness to an enemy.
	func _blind_enemy(enemy_id: int) -> void:
		_blinded_enemies[enemy_id] = true
		blindness_applied.append({
			"enemy_id": enemy_id,
			"duration": BLINDNESS_DURATION
		})

	## Get blinded enemies dictionary (for testing).
	func get_blinded_enemies() -> Dictionary:
		return _blinded_enemies


var flashlight: MockFlashlightEffect


func before_each() -> void:
	flashlight = MockFlashlightEffect.new()


func after_each() -> void:
	flashlight = null


# ============================================================================
# Constants Tests
# ============================================================================


func test_beam_half_angle_is_9_degrees() -> void:
	assert_eq(flashlight.BEAM_HALF_ANGLE_DEG, 9.0,
		"Beam half-angle should be 9 degrees (18 degrees total)")


func test_beam_range_is_600() -> void:
	assert_eq(flashlight.BEAM_RANGE, 600.0,
		"Beam range should be 600 pixels")


func test_blindness_duration_is_200ms() -> void:
	assert_eq(flashlight.BLINDNESS_DURATION, 0.2,
		"Blindness duration should be 0.2 seconds (200ms)")


func test_light_energy() -> void:
	assert_eq(flashlight.LIGHT_ENERGY, 8.0,
		"Light energy should be 8.0")


func test_obstacle_collision_mask() -> void:
	assert_eq(flashlight.OBSTACLE_COLLISION_MASK, 4,
		"Obstacle collision mask should be 4 (layer 3)")


# ============================================================================
# Toggle Tests
# ============================================================================


func test_flashlight_starts_off() -> void:
	assert_false(flashlight.is_on(),
		"Flashlight should start off")


func test_turn_on() -> void:
	flashlight.turn_on()

	assert_true(flashlight.is_on(),
		"Flashlight should be on after turn_on")


func test_turn_off() -> void:
	flashlight.turn_on()
	flashlight.turn_off()

	assert_false(flashlight.is_on(),
		"Flashlight should be off after turn_off")


func test_turn_on_twice_no_effect() -> void:
	flashlight.turn_on()
	flashlight.turn_on()

	assert_true(flashlight.is_on(),
		"Double turn_on should still be on")


func test_turn_off_when_already_off() -> void:
	flashlight.turn_off()

	assert_false(flashlight.is_on(),
		"Turn off when already off should stay off")


# ============================================================================
# Blinded Enemies Tracking Tests
# ============================================================================


func test_blinded_enemies_cleared_on_turn_on() -> void:
	flashlight.turn_on()
	# Simulate blinding an enemy
	flashlight._blinded_enemies[123] = true

	# Turn off and on again
	flashlight.turn_off()
	flashlight.turn_on()

	assert_true(flashlight.get_blinded_enemies().is_empty(),
		"Blinded enemies should be cleared on new activation")


func test_blinded_enemies_cleared_on_turn_off() -> void:
	flashlight.turn_on()
	flashlight._blinded_enemies[123] = true

	flashlight.turn_off()

	assert_true(flashlight.get_blinded_enemies().is_empty(),
		"Blinded enemies should be cleared when flashlight turns off")


# ============================================================================
# Beam Cone Detection Tests
# ============================================================================


func test_enemy_directly_in_front_detected() -> void:
	flashlight.global_position = Vector2(0, 0)
	flashlight.global_rotation = 0.0  # Pointing right

	assert_true(flashlight._is_enemy_in_beam(Vector2(300, 0)),
		"Enemy directly in front should be in beam")


func test_enemy_behind_not_detected() -> void:
	flashlight.global_position = Vector2(0, 0)
	flashlight.global_rotation = 0.0  # Pointing right

	assert_false(flashlight._is_enemy_in_beam(Vector2(-300, 0)),
		"Enemy behind should not be in beam")


func test_enemy_outside_cone_angle_not_detected() -> void:
	flashlight.global_position = Vector2(0, 0)
	flashlight.global_rotation = 0.0  # Pointing right

	# 9 degrees half-angle: at distance 300, max offset is 300*tan(9°) ≈ 47.5
	# Place enemy at offset 100 (well outside the cone)
	assert_false(flashlight._is_enemy_in_beam(Vector2(300, 100)),
		"Enemy outside cone angle should not be in beam")


func test_enemy_inside_cone_angle_detected() -> void:
	flashlight.global_position = Vector2(0, 0)
	flashlight.global_rotation = 0.0  # Pointing right

	# At distance 300, offset of 30 gives angle ≈ 5.7 degrees (< 9 degrees)
	assert_true(flashlight._is_enemy_in_beam(Vector2(300, 30)),
		"Enemy inside cone angle should be in beam")


func test_enemy_at_cone_edge_detected() -> void:
	flashlight.global_position = Vector2(0, 0)
	flashlight.global_rotation = 0.0  # Pointing right

	# At distance 300, max offset for 9 degrees is ~47.5 pixels
	# Place enemy at offset 45 (just inside)
	assert_true(flashlight._is_enemy_in_beam(Vector2(300, 45)),
		"Enemy just inside cone edge should be in beam")


func test_enemy_beyond_range_not_detected() -> void:
	flashlight.global_position = Vector2(0, 0)
	flashlight.global_rotation = 0.0

	assert_false(flashlight._is_enemy_in_beam(Vector2(700, 0)),
		"Enemy beyond beam range should not be in beam")


func test_enemy_at_range_boundary_detected() -> void:
	flashlight.global_position = Vector2(0, 0)
	flashlight.global_rotation = 0.0

	assert_true(flashlight._is_enemy_in_beam(Vector2(600, 0)),
		"Enemy at exact beam range should be in beam")


func test_enemy_just_beyond_range_not_detected() -> void:
	flashlight.global_position = Vector2(0, 0)
	flashlight.global_rotation = 0.0

	assert_false(flashlight._is_enemy_in_beam(Vector2(601, 0)),
		"Enemy just beyond beam range should not be in beam")


func test_enemy_too_close_not_detected() -> void:
	flashlight.global_position = Vector2(0, 0)
	flashlight.global_rotation = 0.0

	assert_false(flashlight._is_enemy_in_beam(Vector2(0.5, 0)),
		"Enemy too close (< 1.0 pixel) should not be in beam")


func test_enemy_at_same_position_not_detected() -> void:
	flashlight.global_position = Vector2(100, 100)
	flashlight.global_rotation = 0.0

	assert_false(flashlight._is_enemy_in_beam(Vector2(100, 100)),
		"Enemy at exact flashlight position should not be in beam")


# ============================================================================
# Rotated Beam Tests
# ============================================================================


func test_beam_pointing_up() -> void:
	flashlight.global_position = Vector2(0, 0)
	flashlight.global_rotation = -PI / 2  # Pointing up (negative Y)

	assert_true(flashlight._is_enemy_in_beam(Vector2(0, -300)),
		"Enemy above should be detected when beam points up")
	assert_false(flashlight._is_enemy_in_beam(Vector2(0, 300)),
		"Enemy below should not be detected when beam points up")


func test_beam_pointing_down() -> void:
	flashlight.global_position = Vector2(0, 0)
	flashlight.global_rotation = PI / 2  # Pointing down (positive Y)

	assert_true(flashlight._is_enemy_in_beam(Vector2(0, 300)),
		"Enemy below should be detected when beam points down")
	assert_false(flashlight._is_enemy_in_beam(Vector2(0, -300)),
		"Enemy above should not be detected when beam points down")


func test_beam_pointing_left() -> void:
	flashlight.global_position = Vector2(0, 0)
	flashlight.global_rotation = PI  # Pointing left

	assert_true(flashlight._is_enemy_in_beam(Vector2(-300, 0)),
		"Enemy to the left should be detected when beam points left")
	assert_false(flashlight._is_enemy_in_beam(Vector2(300, 0)),
		"Enemy to the right should not be detected when beam points left")


func test_beam_45_degrees() -> void:
	flashlight.global_position = Vector2(0, 0)
	flashlight.global_rotation = PI / 4  # Pointing bottom-right at 45 degrees

	# Enemy along the 45 degree diagonal
	var enemy_pos := Vector2(200, 200)  # ~283 pixels away along diagonal
	assert_true(flashlight._is_enemy_in_beam(enemy_pos),
		"Enemy on 45-degree diagonal should be detected")


# ============================================================================
# Line of Sight Tests
# ============================================================================


func test_enemy_blocked_by_wall_not_detected() -> void:
	flashlight.global_position = Vector2(0, 0)
	flashlight.global_rotation = 0.0
	flashlight.set_mock_line_of_sight(false)

	assert_false(flashlight._is_enemy_in_beam(Vector2(300, 0)),
		"Enemy blocked by wall should not be in beam")


func test_enemy_with_clear_los_detected() -> void:
	flashlight.global_position = Vector2(0, 0)
	flashlight.global_rotation = 0.0
	flashlight.set_mock_line_of_sight(true)

	assert_true(flashlight._is_enemy_in_beam(Vector2(300, 0)),
		"Enemy with clear LOS should be in beam")


# ============================================================================
# Enemy Blinding Integration Tests
# ============================================================================


func test_blind_enemy_records_in_dictionary() -> void:
	flashlight.turn_on()

	flashlight._blind_enemy(42)

	assert_true(flashlight.get_blinded_enemies().has(42),
		"Blinded enemy should be recorded in dictionary")


func test_blind_enemy_records_blindness_application() -> void:
	flashlight.turn_on()

	flashlight._blind_enemy(42)

	assert_eq(flashlight.blindness_applied.size(), 1,
		"Should record one blindness application")
	assert_eq(flashlight.blindness_applied[0]["enemy_id"], 42,
		"Should record correct enemy ID")
	assert_eq(flashlight.blindness_applied[0]["duration"], 0.2,
		"Should apply 200ms blindness duration")


func test_enemy_blinded_only_once_per_activation() -> void:
	flashlight.turn_on()

	var enemies := [
		{"id": 1, "position": Vector2(300, 0)},
	]

	# Check twice
	flashlight.check_enemies(enemies)
	flashlight.check_enemies(enemies)

	assert_eq(flashlight.blindness_applied.size(), 1,
		"Enemy should only be blinded once per activation")


func test_enemy_can_be_blinded_again_after_toggle() -> void:
	flashlight.turn_on()

	var enemies := [
		{"id": 1, "position": Vector2(300, 0)},
	]

	flashlight.check_enemies(enemies)
	assert_eq(flashlight.blindness_applied.size(), 1)

	# Toggle off and on
	flashlight.turn_off()
	flashlight.turn_on()

	flashlight.check_enemies(enemies)
	assert_eq(flashlight.blindness_applied.size(), 2,
		"Enemy should be blinded again after flashlight re-activation")


func test_multiple_enemies_blinded_independently() -> void:
	flashlight.turn_on()

	var enemies := [
		{"id": 1, "position": Vector2(300, 0)},
		{"id": 2, "position": Vector2(200, 0)},
		{"id": 3, "position": Vector2(400, 0)},
	]

	flashlight.check_enemies(enemies)

	assert_eq(flashlight.blindness_applied.size(), 3,
		"All three enemies in beam should be blinded")


func test_enemies_outside_beam_not_blinded() -> void:
	flashlight.turn_on()
	flashlight.global_rotation = 0.0

	var enemies := [
		{"id": 1, "position": Vector2(300, 0)},     # In beam
		{"id": 2, "position": Vector2(-300, 0)},     # Behind
		{"id": 3, "position": Vector2(300, 200)},    # Outside cone
	]

	flashlight.check_enemies(enemies)

	assert_eq(flashlight.blindness_applied.size(), 1,
		"Only enemy in beam should be blinded")
	assert_eq(flashlight.blindness_applied[0]["enemy_id"], 1,
		"Only the enemy directly in beam should be blinded")


func test_no_blinding_when_flashlight_off() -> void:
	# Flashlight stays off

	var enemies := [
		{"id": 1, "position": Vector2(300, 0)},
	]

	flashlight.check_enemies(enemies)

	assert_eq(flashlight.blindness_applied.size(), 0,
		"No enemies should be blinded when flashlight is off")


# ============================================================================
# Edge Cases
# ============================================================================


func test_no_enemies_in_scene() -> void:
	flashlight.turn_on()

	flashlight.check_enemies([])

	assert_eq(flashlight.blindness_applied.size(), 0,
		"No blindness should be applied when no enemies exist")


func test_enemy_at_different_positions_over_time() -> void:
	flashlight.turn_on()
	flashlight.global_rotation = 0.0

	# Enemy starts outside beam
	var enemies := [{"id": 1, "position": Vector2(-300, 0)}]
	flashlight.check_enemies(enemies)
	assert_eq(flashlight.blindness_applied.size(), 0,
		"Enemy behind should not be blinded")

	# Enemy moves into beam
	enemies[0]["position"] = Vector2(300, 0)
	flashlight.check_enemies(enemies)
	assert_eq(flashlight.blindness_applied.size(), 1,
		"Enemy that moved into beam should be blinded")

	# Enemy stays in beam (should not be blinded again)
	flashlight.check_enemies(enemies)
	assert_eq(flashlight.blindness_applied.size(), 1,
		"Enemy should not be blinded again during same activation")


func test_flashlight_at_offset_position() -> void:
	flashlight.global_position = Vector2(500, 300)
	flashlight.global_rotation = 0.0
	flashlight.turn_on()

	var enemies := [
		{"id": 1, "position": Vector2(800, 300)},  # 300 pixels to the right
	]

	flashlight.check_enemies(enemies)

	assert_eq(flashlight.blindness_applied.size(), 1,
		"Should detect enemy relative to flashlight position")


func test_wall_blocks_blinding() -> void:
	flashlight.turn_on()
	flashlight.global_rotation = 0.0
	flashlight.set_mock_line_of_sight(false)

	var enemies := [
		{"id": 1, "position": Vector2(300, 0)},
	]

	flashlight.check_enemies(enemies)

	assert_eq(flashlight.blindness_applied.size(), 0,
		"Enemies behind walls should not be blinded")


# ============================================================================
# Debug Status Display Tests (Issue #584 fix)
# ============================================================================


func test_debug_label_shows_blinded_status() -> void:
	# Simulate the debug label format logic from enemy.gd
	var _is_blinded := true
	var _is_stunned := false
	var effects: Array = []
	if _is_blinded: effects.append("BLINDED")
	if _is_stunned: effects.append("STUNNED")
	var status_text := "\n{%s}" % " + ".join(effects)

	assert_eq(status_text, "\n{BLINDED}",
		"Debug label should show {BLINDED} when enemy is blinded")


func test_debug_label_shows_stunned_status() -> void:
	var _is_blinded := false
	var _is_stunned := true
	var effects: Array = []
	if _is_blinded: effects.append("BLINDED")
	if _is_stunned: effects.append("STUNNED")
	var status_text := "\n{%s}" % " + ".join(effects)

	assert_eq(status_text, "\n{STUNNED}",
		"Debug label should show {STUNNED} when enemy is stunned")


func test_debug_label_shows_both_statuses() -> void:
	var _is_blinded := true
	var _is_stunned := true
	var effects: Array = []
	if _is_blinded: effects.append("BLINDED")
	if _is_stunned: effects.append("STUNNED")
	var status_text := "\n{%s}" % " + ".join(effects)

	assert_eq(status_text, "\n{BLINDED + STUNNED}",
		"Debug label should show both when blinded and stunned")


func test_debug_label_no_status_when_not_affected() -> void:
	var _is_blinded := false
	var _is_stunned := false
	var has_status := _is_blinded or _is_stunned

	assert_false(has_status,
		"No status text should be added when not blinded or stunned")
