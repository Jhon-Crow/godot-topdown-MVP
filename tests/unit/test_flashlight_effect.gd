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

	## Blindness duration in seconds.
	const BLINDNESS_DURATION: float = 2.0

	## Cooldown in seconds before the same enemy can be blinded again.
	const BLINDNESS_COOLDOWN: float = 20.0

	## Collision mask for obstacles.
	const OBSTACLE_COLLISION_MASK: int = 4

	## Scatter light energy (Issue #644).
	const SCATTER_LIGHT_ENERGY: float = 0.4

	## Scatter light texture scale (Issue #644).
	const SCATTER_LIGHT_TEXTURE_SCALE: float = 3.0

	## Scatter light color (Issue #644).
	const SCATTER_LIGHT_COLOR: Color = Color(1.0, 1.0, 0.92, 1.0)

	## Whether the flashlight is on.
	var _is_on: bool = false

	## Tracks when each enemy was last blinded (enemy_id -> timestamp in msec).
	var _blinded_enemies: Dictionary = {}

	## Global position of the flashlight.
	var global_position: Vector2 = Vector2.ZERO

	## Global rotation of the flashlight (radians).
	var global_rotation: float = 0.0

	## Mock: whether line of sight is clear.
	var _mock_line_of_sight: bool = true

	## Mock: tracks blindness applications for testing.
	var blindness_applied: Array = []

	## Mock: simulated current time in msec (for testing cooldowns).
	var _mock_time_msec: int = 0

	## Mock: scatter light position (Issue #644).
	var scatter_light_position: Vector2 = Vector2.ZERO

	## Mock: scatter light visible state (Issue #644).
	var scatter_light_visible: bool = false

	## Mock: wall hit position (null = no wall hit).
	var _mock_wall_hit_position = null

	## Set mock line of sight.
	func set_mock_line_of_sight(enabled: bool) -> void:
		_mock_line_of_sight = enabled

	## Set mock time (milliseconds).
	func set_mock_time_msec(time_msec: int) -> void:
		_mock_time_msec = time_msec

	## Turn on the flashlight.
	func turn_on() -> void:
		if _is_on:
			return
		_is_on = true

	## Turn off the flashlight.
	func turn_off() -> void:
		if not _is_on:
			return
		_is_on = false

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
				var last_blinded: int = int(_blinded_enemies[enemy_id])
				var elapsed_sec: float = float(_mock_time_msec - last_blinded) / 1000.0
				if elapsed_sec < BLINDNESS_COOLDOWN:
					continue

			if _is_enemy_in_beam(enemy_position):
				_blind_enemy(enemy_id)

	## Apply blindness to an enemy.
	func _blind_enemy(enemy_id: int) -> void:
		_blinded_enemies[enemy_id] = _mock_time_msec
		blindness_applied.append({
			"enemy_id": enemy_id,
			"duration": BLINDNESS_DURATION
		})

	## Get blinded enemies dictionary (for testing).
	func get_blinded_enemies() -> Dictionary:
		return _blinded_enemies

	## Set mock wall hit position (Issue #644).
	func set_mock_wall_hit(position) -> void:
		_mock_wall_hit_position = position

	## Update scatter light position based on beam direction and wall hit (Issue #644).
	## Mirrors the logic from flashlight_effect.gd _update_scatter_light_position().
	func update_scatter_light_position() -> void:
		if not _is_on:
			scatter_light_visible = false
			return

		scatter_light_visible = true
		var beam_direction := Vector2.RIGHT.rotated(global_rotation)
		var beam_end := global_position + beam_direction * BEAM_RANGE

		if _mock_wall_hit_position != null:
			scatter_light_position = _mock_wall_hit_position
		else:
			scatter_light_position = beam_end


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


func test_blindness_duration_is_2_seconds() -> void:
	assert_eq(flashlight.BLINDNESS_DURATION, 2.0,
		"Blindness duration should be 2.0 seconds")


func test_blindness_cooldown_is_20_seconds() -> void:
	assert_eq(flashlight.BLINDNESS_COOLDOWN, 20.0,
		"Blindness cooldown should be 20.0 seconds")


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


func test_blinded_enemies_persist_across_toggle() -> void:
	flashlight.turn_on()
	# Simulate blinding an enemy (stores timestamp)
	flashlight._blinded_enemies[123] = 1000

	# Turn off and on again
	flashlight.turn_off()
	flashlight.turn_on()

	assert_true(flashlight.get_blinded_enemies().has(123),
		"Blinded enemies should persist across toggle (time-based cooldown)")


func test_blinded_enemies_not_cleared_on_turn_off() -> void:
	flashlight.turn_on()
	flashlight._blinded_enemies[123] = 1000

	flashlight.turn_off()

	assert_true(flashlight.get_blinded_enemies().has(123),
		"Blinded enemies should not be cleared when flashlight turns off")


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
	assert_eq(flashlight.blindness_applied[0]["duration"], 2.0,
		"Should apply 2 second blindness duration")


func test_enemy_blinded_only_once_within_cooldown() -> void:
	flashlight.turn_on()
	flashlight.set_mock_time_msec(0)

	var enemies := [
		{"id": 1, "position": Vector2(300, 0)},
	]

	# First check blinds the enemy
	flashlight.check_enemies(enemies)
	assert_eq(flashlight.blindness_applied.size(), 1,
		"Enemy should be blinded on first check")

	# Second check within cooldown should not blind again
	flashlight.set_mock_time_msec(10000)  # 10 seconds later
	flashlight.check_enemies(enemies)
	assert_eq(flashlight.blindness_applied.size(), 1,
		"Enemy should not be blinded again within 20s cooldown")


func test_enemy_can_be_blinded_again_after_cooldown() -> void:
	flashlight.turn_on()
	flashlight.set_mock_time_msec(0)

	var enemies := [
		{"id": 1, "position": Vector2(300, 0)},
	]

	flashlight.check_enemies(enemies)
	assert_eq(flashlight.blindness_applied.size(), 1)

	# 20 seconds later — cooldown expired
	flashlight.set_mock_time_msec(20000)
	flashlight.check_enemies(enemies)
	assert_eq(flashlight.blindness_applied.size(), 2,
		"Enemy should be blinded again after 20s cooldown expires")


func test_enemy_cannot_be_blinded_again_by_toggle_within_cooldown() -> void:
	flashlight.turn_on()
	flashlight.set_mock_time_msec(0)

	var enemies := [
		{"id": 1, "position": Vector2(300, 0)},
	]

	flashlight.check_enemies(enemies)
	assert_eq(flashlight.blindness_applied.size(), 1)

	# Toggle off and on within cooldown
	flashlight.turn_off()
	flashlight.turn_on()

	flashlight.set_mock_time_msec(5000)  # Only 5 seconds later
	flashlight.check_enemies(enemies)
	assert_eq(flashlight.blindness_applied.size(), 1,
		"Enemy should NOT be blinded again by toggle within cooldown")


func test_multiple_enemies_blinded_independently() -> void:
	flashlight.turn_on()
	flashlight.set_mock_time_msec(0)

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
	flashlight.set_mock_time_msec(0)

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
	flashlight.set_mock_time_msec(0)

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
	flashlight.set_mock_time_msec(0)

	flashlight.check_enemies([])

	assert_eq(flashlight.blindness_applied.size(), 0,
		"No blindness should be applied when no enemies exist")


func test_enemy_at_different_positions_over_time() -> void:
	flashlight.turn_on()
	flashlight.global_rotation = 0.0
	flashlight.set_mock_time_msec(0)

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

	# Enemy stays in beam (should not be blinded again within cooldown)
	flashlight.set_mock_time_msec(5000)
	flashlight.check_enemies(enemies)
	assert_eq(flashlight.blindness_applied.size(), 1,
		"Enemy should not be blinded again within cooldown")


func test_flashlight_at_offset_position() -> void:
	flashlight.global_position = Vector2(500, 300)
	flashlight.global_rotation = 0.0
	flashlight.turn_on()
	flashlight.set_mock_time_msec(0)

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
	flashlight.set_mock_time_msec(0)

	var enemies := [
		{"id": 1, "position": Vector2(300, 0)},
	]

	flashlight.check_enemies(enemies)

	assert_eq(flashlight.blindness_applied.size(), 0,
		"Enemies behind walls should not be blinded")


# ============================================================================
# Debug Status Display Tests (Issue #584 fix)
# ============================================================================


func _get_status_text(is_blinded: bool, is_stunned: bool) -> String:
	# Replicate the compact logic from enemy.gd _update_debug_label
	if is_blinded or is_stunned:
		return "\n{%s}" % ("BLINDED + STUNNED" if is_blinded and is_stunned else "BLINDED" if is_blinded else "STUNNED")
	return ""


func test_debug_label_shows_blinded_status() -> void:
	assert_eq(_get_status_text(true, false), "\n{BLINDED}",
		"Debug label should show {BLINDED} when enemy is blinded")


func test_debug_label_shows_stunned_status() -> void:
	assert_eq(_get_status_text(false, true), "\n{STUNNED}",
		"Debug label should show {STUNNED} when enemy is stunned")


func test_debug_label_shows_both_statuses() -> void:
	assert_eq(_get_status_text(true, true), "\n{BLINDED + STUNNED}",
		"Debug label should show both when blinded and stunned")


func test_debug_label_no_status_when_not_affected() -> void:
	assert_eq(_get_status_text(false, false), "",
		"No status text should be added when not blinded or stunned")


# ============================================================================
# Scatter Light Tests (Issue #644)
# ============================================================================


func test_scatter_light_energy_constant() -> void:
	assert_eq(flashlight.SCATTER_LIGHT_ENERGY, 0.4,
		"Scatter light energy should be 0.4 (subtle ambient glow)")


func test_scatter_light_texture_scale_constant() -> void:
	assert_eq(flashlight.SCATTER_LIGHT_TEXTURE_SCALE, 3.0,
		"Scatter light texture scale should be 3.0")


func test_scatter_light_color_is_warm_white() -> void:
	assert_eq(flashlight.SCATTER_LIGHT_COLOR, Color(1.0, 1.0, 0.92, 1.0),
		"Scatter light color should be warm white matching beam tint")


func test_scatter_light_energy_lower_than_main_beam() -> void:
	assert_true(flashlight.SCATTER_LIGHT_ENERGY < flashlight.LIGHT_ENERGY,
		"Scatter light energy (%.1f) should be much lower than main beam (%.1f)" % [
			flashlight.SCATTER_LIGHT_ENERGY, flashlight.LIGHT_ENERGY])


func test_scatter_light_at_wall_hit_position() -> void:
	flashlight.global_position = Vector2(100, 100)
	flashlight.global_rotation = 0.0  # Pointing right
	flashlight.turn_on()

	# Wall hit at 400 pixels to the right
	flashlight.set_mock_wall_hit(Vector2(500, 100))
	flashlight.update_scatter_light_position()

	assert_eq(flashlight.scatter_light_position, Vector2(500, 100),
		"Scatter light should be at wall hit position")


func test_scatter_light_at_max_range_when_no_wall() -> void:
	flashlight.global_position = Vector2(100, 100)
	flashlight.global_rotation = 0.0  # Pointing right
	flashlight.turn_on()

	# No wall hit
	flashlight.set_mock_wall_hit(null)
	flashlight.update_scatter_light_position()

	assert_eq(flashlight.scatter_light_position, Vector2(700, 100),
		"Scatter light should be at max beam range (100 + 600 = 700) when no wall hit")


func test_scatter_light_follows_beam_direction() -> void:
	flashlight.global_position = Vector2(0, 0)
	flashlight.global_rotation = PI / 2  # Pointing down
	flashlight.turn_on()

	flashlight.set_mock_wall_hit(null)
	flashlight.update_scatter_light_position()

	# Beam points down, so scatter light should be at (0, 600)
	assert_almost_eq(flashlight.scatter_light_position.x, 0.0, 0.01,
		"Scatter light X should be ~0 when beam points down")
	assert_almost_eq(flashlight.scatter_light_position.y, 600.0, 0.01,
		"Scatter light Y should be ~600 when beam points down")


func test_scatter_light_hidden_when_flashlight_off() -> void:
	flashlight.turn_off()
	flashlight.update_scatter_light_position()

	assert_false(flashlight.scatter_light_visible,
		"Scatter light should be hidden when flashlight is off")


func test_scatter_light_visible_when_flashlight_on() -> void:
	flashlight.turn_on()
	flashlight.set_mock_wall_hit(null)
	flashlight.update_scatter_light_position()

	assert_true(flashlight.scatter_light_visible,
		"Scatter light should be visible when flashlight is on")


func test_scatter_light_at_diagonal_wall_hit() -> void:
	flashlight.global_position = Vector2(0, 0)
	flashlight.global_rotation = PI / 4  # Pointing bottom-right at 45 degrees
	flashlight.turn_on()

	# Wall at diagonal position
	flashlight.set_mock_wall_hit(Vector2(200, 200))
	flashlight.update_scatter_light_position()

	assert_eq(flashlight.scatter_light_position, Vector2(200, 200),
		"Scatter light should follow diagonal wall hit position")


func test_scatter_light_updates_when_wall_hit_changes() -> void:
	flashlight.global_position = Vector2(0, 0)
	flashlight.global_rotation = 0.0
	flashlight.turn_on()

	# First: wall at 300 pixels
	flashlight.set_mock_wall_hit(Vector2(300, 0))
	flashlight.update_scatter_light_position()
	assert_eq(flashlight.scatter_light_position, Vector2(300, 0),
		"Scatter light should be at first wall hit")

	# Wall moves to 500 pixels (e.g. door opened)
	flashlight.set_mock_wall_hit(Vector2(500, 0))
	flashlight.update_scatter_light_position()
	assert_eq(flashlight.scatter_light_position, Vector2(500, 0),
		"Scatter light should update to new wall position")
