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

	## Scatter light wall pullback distance in pixels (Issue #640).
	const SCATTER_WALL_PULLBACK: float = 8.0

	## Beam-direction wall clamp distance threshold (Issue #640).
	const BEAM_WALL_CLAMP_DISTANCE: float = 30.0

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

	## Mock: simulated player center position (for wall clamping).
	var _mock_player_center: Vector2 = Vector2.ZERO

	## Mock: simulated wall hit position between center and barrel (null = no wall hit).
	var _mock_wall_hit_pos = null

	## Mock: simulated beam-direction wall hit position (null = no wall hit).
	## Used when the barrel is on the player's side but the beam direction
	## immediately enters a wall (Issue #640 root cause #6).
	var _mock_beam_wall_hit_pos = null

	## The PointLight2D position after clamping (local coordinates relative to flashlight).
	var point_light_position: Vector2 = Vector2.ZERO

	## Whether the main beam is currently wall-clamped (Issue #640).
	var _is_wall_clamped: bool = false

	## Current texture_scale of the PointLight2D (may be reduced when wall-clamped).
	var point_light_texture_scale: float = LIGHT_TEXTURE_SCALE

	## Current shadow_filter mode of the PointLight2D.
	var point_light_shadow_filter: int = 1  # SHADOW_FILTER_PCF5

	## Mock: scatter light position (Issue #644).
	var scatter_light_position: Vector2 = Vector2.ZERO

	## Mock: scatter light visible state (Issue #644).
	var scatter_light_visible: bool = false

	## Set mock line of sight.
	func set_mock_line_of_sight(enabled: bool) -> void:
		_mock_line_of_sight = enabled

	## Set mock time (milliseconds).
	func set_mock_time_msec(time_msec: int) -> void:
		_mock_time_msec = time_msec

	## Set mock player center position (for wall clamping tests).
	func set_mock_player_center(pos: Vector2) -> void:
		_mock_player_center = pos

	## Set mock wall hit position between center and barrel (null = no wall, Vector2 = wall hit at position).
	func set_mock_wall_hit(hit_pos) -> void:
		_mock_wall_hit_pos = hit_pos

	## Set mock beam-direction wall hit position (null = no wall, Vector2 = wall hit at position).
	## Simulates a wall immediately in front of the barrel along the beam direction.
	func set_mock_beam_wall_hit(hit_pos) -> void:
		_mock_beam_wall_hit_pos = hit_pos

	## Clamp the PointLight2D position to avoid penetrating walls (Issue #640).
	## Mirrors the logic in flashlight_effect.gd _clamp_light_to_walls().
	func clamp_light_to_walls() -> void:
		var intended_pos: Vector2 = global_position
		var to_light: Vector2 = intended_pos - _mock_player_center
		var dist: float = to_light.length()

		if dist < 1.0:
			point_light_position = Vector2.ZERO
			_is_wall_clamped = false
			_restore_light_defaults()
			return

		if _mock_wall_hit_pos == null:
			# No wall between player and barrel — check beam direction.
			if _mock_beam_wall_hit_pos == null:
				# No wall in beam direction either — use default
				point_light_position = Vector2.ZERO
				_is_wall_clamped = false
				_restore_light_defaults()
			else:
				# Wall found immediately in beam direction — clamp the beam.
				_is_wall_clamped = true
				point_light_position = _mock_player_center - global_position
				var wall_dist: float = (_mock_beam_wall_hit_pos - _mock_player_center).length()
				var cone_texture_size: float = 2048.0
				var clamped_scale: float = maxf(wall_dist * 2.0 / cone_texture_size, 0.1)
				point_light_texture_scale = minf(clamped_scale, LIGHT_TEXTURE_SCALE)
				point_light_shadow_filter = 0  # SHADOW_FILTER_NONE
		else:
			# Wall hit: move the light back to the player center.
			point_light_position = _mock_player_center - global_position
			_is_wall_clamped = true

			# Reduce texture_scale so beam only reaches wall surface.
			var wall_dist: float = (_mock_wall_hit_pos - _mock_player_center).length()
			var cone_texture_size: float = 2048.0
			var clamped_scale: float = maxf(wall_dist * 2.0 / cone_texture_size, 0.1)
			point_light_texture_scale = minf(clamped_scale, LIGHT_TEXTURE_SCALE)

			# Switch to sharp shadows near walls.
			point_light_shadow_filter = 0  # SHADOW_FILTER_NONE

	## Restore PointLight2D to default settings when not wall-clamped.
	func _restore_light_defaults() -> void:
		point_light_texture_scale = LIGHT_TEXTURE_SCALE
		point_light_shadow_filter = 1  # SHADOW_FILTER_PCF5

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

	## Check if the flashlight beam is wall-clamped (Issue #640).
	func is_wall_clamped() -> bool:
		return _is_wall_clamped

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

		# Issue #640: When wall-clamped, the beam is blocked — skip blindness checks.
		if _is_wall_clamped:
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

	## Update scatter light position based on beam direction and wall hit (Issue #644).
	## Mirrors the logic from flashlight_effect.gd _update_scatter_light_position().
	func update_scatter_light_position() -> void:
		if not _is_on:
			scatter_light_visible = false
			return

		# If wall-clamped, hide scatter light entirely (Issue #640).
		if _is_wall_clamped:
			scatter_light_visible = false
			return

		var beam_direction := Vector2.RIGHT.rotated(global_rotation)
		var beam_end := global_position + beam_direction * BEAM_RANGE

		if _mock_wall_hit_pos != null:
			# Pull scatter light back from wall surface to avoid sitting on
			# the LightOccluder2D boundary (Issue #640).
			var pullback_dir: Vector2 = -beam_direction
			scatter_light_position = _mock_wall_hit_pos + pullback_dir * SCATTER_WALL_PULLBACK
		else:
			scatter_light_position = beam_end

		scatter_light_visible = true


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
# Wall Clamping Tests (Issue #640: flashlight passes through wall)
# ============================================================================


func test_no_wall_keeps_default_position() -> void:
	# Player center at origin, flashlight at offset (20, 0)
	flashlight.set_mock_player_center(Vector2(0, 0))
	flashlight.global_position = Vector2(20, 0)
	flashlight.set_mock_wall_hit(null)

	flashlight.clamp_light_to_walls()

	assert_eq(flashlight.point_light_position, Vector2.ZERO,
		"PointLight2D should stay at default position when no wall is nearby")
	assert_false(flashlight._is_wall_clamped,
		"Wall clamped flag should be false when no wall is nearby")
	assert_eq(flashlight.point_light_texture_scale, flashlight.LIGHT_TEXTURE_SCALE,
		"Texture scale should be default when no wall is nearby")
	assert_eq(flashlight.point_light_shadow_filter, 1,
		"Shadow filter should be PCF5 (1) when no wall is nearby")


func test_wall_pulls_light_back_to_player_center() -> void:
	# Player center at origin, flashlight at offset (20, 0)
	# Wall hit at (18, 0) — between player and flashlight
	flashlight.set_mock_player_center(Vector2(0, 0))
	flashlight.global_position = Vector2(20, 0)
	flashlight.set_mock_wall_hit(Vector2(18, 0))

	flashlight.clamp_light_to_walls()

	# When wall is detected, light moves to player center (0,0).
	# Local offset relative to flashlight at (20,0): (0,0) - (20,0) = (-20, 0)
	assert_almost_eq(flashlight.point_light_position.x, -20.0, 0.1,
		"PointLight2D should be pulled back to player center when wall is detected")
	assert_almost_eq(flashlight.point_light_position.y, 0.0, 0.1,
		"PointLight2D Y should remain 0")
	assert_true(flashlight._is_wall_clamped,
		"Wall clamped flag should be true when wall is detected")


func test_wall_close_to_player_pulls_light_to_player_center() -> void:
	# Player center at origin, flashlight at offset (20, 0)
	# Wall hit at (5, 0) — very close to player
	flashlight.set_mock_player_center(Vector2(0, 0))
	flashlight.global_position = Vector2(20, 0)
	flashlight.set_mock_wall_hit(Vector2(5, 0))

	flashlight.clamp_light_to_walls()

	# When wall is detected, light always moves to player center (0,0).
	# Local offset: (0,0) - (20,0) = (-20, 0)
	assert_almost_eq(flashlight.point_light_position.x, -20.0, 0.1,
		"PointLight2D should be at player center when wall is detected")


func test_wall_clamping_reduces_texture_scale() -> void:
	# Player center at origin, flashlight at offset (20, 0)
	# Wall hit at (18, 0) — 18px from player center
	flashlight.set_mock_player_center(Vector2(0, 0))
	flashlight.global_position = Vector2(20, 0)
	flashlight.set_mock_wall_hit(Vector2(18, 0))

	flashlight.clamp_light_to_walls()

	# Expected scale: wall_dist * 2 / 2048 = 18 * 2 / 2048 ≈ 0.0176
	# Clamped to minimum of 0.1
	assert_almost_eq(flashlight.point_light_texture_scale, 0.1, 0.01,
		"Texture scale should be reduced to minimum when wall is very close")


func test_wall_clamping_uses_sharp_shadows() -> void:
	# When wall-clamped, shadow filter should switch to SHADOW_FILTER_NONE (0)
	flashlight.set_mock_player_center(Vector2(0, 0))
	flashlight.global_position = Vector2(20, 0)
	flashlight.set_mock_wall_hit(Vector2(18, 0))

	flashlight.clamp_light_to_walls()

	assert_eq(flashlight.point_light_shadow_filter, 0,
		"Shadow filter should be NONE (0) when wall-clamped for crisp edges")


func test_wall_clamping_restores_defaults_when_clear() -> void:
	# First: wall-clamp
	flashlight.set_mock_player_center(Vector2(0, 0))
	flashlight.global_position = Vector2(20, 0)
	flashlight.set_mock_wall_hit(Vector2(18, 0))
	flashlight.clamp_light_to_walls()
	assert_true(flashlight._is_wall_clamped)

	# Then: no wall
	flashlight.set_mock_wall_hit(null)
	flashlight.clamp_light_to_walls()
	assert_false(flashlight._is_wall_clamped,
		"Wall clamped flag should be false after wall is cleared")
	assert_eq(flashlight.point_light_texture_scale, flashlight.LIGHT_TEXTURE_SCALE,
		"Texture scale should be restored to default after wall is cleared")
	assert_eq(flashlight.point_light_shadow_filter, 1,
		"Shadow filter should be restored to PCF5 after wall is cleared")


func test_wall_clamping_with_rotated_beam() -> void:
	# Player at (100, 100), flashlight at 45 degrees (offset 20px along diagonal)
	var offset := Vector2(20, 0).rotated(PI / 4)  # ~(14.14, 14.14)
	flashlight.set_mock_player_center(Vector2(100, 100))
	flashlight.global_position = Vector2(100, 100) + offset

	# Wall hit at diagonal position between player and flashlight
	var wall_hit := Vector2(100, 100) + offset * 0.8  # 80% of the way
	flashlight.set_mock_wall_hit(wall_hit)

	flashlight.clamp_light_to_walls()

	# The light should be moved back to player center (100, 100)
	# Local offset: (100,100) - (100+14.14, 100+14.14) = (-14.14, -14.14)
	assert_almost_eq(flashlight.point_light_position.x, -offset.x, 0.1,
		"PointLight2D X should be at player center offset when wall blocks at diagonal")
	assert_almost_eq(flashlight.point_light_position.y, -offset.y, 0.1,
		"PointLight2D Y should be at player center offset when wall blocks at diagonal")


func test_wall_clamping_no_effect_when_light_at_player() -> void:
	# Edge case: flashlight at same position as player (dist < 1)
	flashlight.set_mock_player_center(Vector2(100, 100))
	flashlight.global_position = Vector2(100, 100)
	flashlight.set_mock_wall_hit(null)

	flashlight.clamp_light_to_walls()

	assert_eq(flashlight.point_light_position, Vector2.ZERO,
		"PointLight2D should stay at zero when flashlight is at player center")
	assert_false(flashlight._is_wall_clamped,
		"Wall clamped flag should be false when light is at player center")


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


func test_scatter_light_pulled_back_from_wall() -> void:
	flashlight.global_position = Vector2(100, 100)
	flashlight.global_rotation = 0.0  # Pointing right
	flashlight.turn_on()

	# Wall hit at 400 pixels to the right
	flashlight.set_mock_wall_hit(Vector2(500, 100))
	flashlight.update_scatter_light_position()

	# Scatter light should be pulled back 8px from wall toward player
	# Beam direction is (1, 0), pullback is (-1, 0) * 8 = (-8, 0)
	assert_almost_eq(flashlight.scatter_light_position.x, 492.0, 0.1,
		"Scatter light should be pulled back 8px from wall surface")
	assert_almost_eq(flashlight.scatter_light_position.y, 100.0, 0.1,
		"Scatter light Y should match wall hit Y")


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


func test_scatter_light_pulled_back_at_diagonal_wall_hit() -> void:
	flashlight.global_position = Vector2(0, 0)
	flashlight.global_rotation = PI / 4  # Pointing bottom-right at 45 degrees
	flashlight.turn_on()

	# Wall at diagonal position
	flashlight.set_mock_wall_hit(Vector2(200, 200))
	flashlight.update_scatter_light_position()

	# Pullback direction is opposite of beam direction at 45 degrees
	# Beam direction: (cos(45°), sin(45°)) ≈ (0.707, 0.707)
	# Pullback: (-0.707, -0.707) * 8 ≈ (-5.66, -5.66)
	var expected_pullback := Vector2.RIGHT.rotated(PI / 4) * -8.0
	assert_almost_eq(flashlight.scatter_light_position.x, 200.0 + expected_pullback.x, 0.1,
		"Scatter light X should be pulled back from diagonal wall hit")
	assert_almost_eq(flashlight.scatter_light_position.y, 200.0 + expected_pullback.y, 0.1,
		"Scatter light Y should be pulled back from diagonal wall hit")


func test_scatter_light_updates_when_wall_hit_changes() -> void:
	flashlight.global_position = Vector2(0, 0)
	flashlight.global_rotation = 0.0
	flashlight.turn_on()

	# First: wall at 300 pixels (scatter is pulled back 8px)
	flashlight.set_mock_wall_hit(Vector2(300, 0))
	flashlight.update_scatter_light_position()
	assert_almost_eq(flashlight.scatter_light_position.x, 292.0, 0.1,
		"Scatter light should be 8px before first wall hit")

	# Wall moves to 500 pixels (e.g. door opened)
	flashlight.set_mock_wall_hit(Vector2(500, 0))
	flashlight.update_scatter_light_position()
	assert_almost_eq(flashlight.scatter_light_position.x, 492.0, 0.1,
		"Scatter light should update to 8px before new wall position")


func test_scatter_light_hidden_when_wall_clamped() -> void:
	flashlight.global_position = Vector2(20, 0)
	flashlight.global_rotation = 0.0
	flashlight.turn_on()

	# Simulate wall clamping (player flush against wall)
	flashlight.set_mock_player_center(Vector2(0, 0))
	flashlight.set_mock_wall_hit(Vector2(18, 0))
	flashlight.clamp_light_to_walls()

	# Scatter light should be hidden when wall-clamped
	flashlight.update_scatter_light_position()
	assert_false(flashlight.scatter_light_visible,
		"Scatter light should be hidden when main beam is wall-clamped")


func test_no_blinding_when_wall_clamped() -> void:
	# Issue #640: When wall-clamped, enemies should not be blinded through walls.
	flashlight.turn_on()
	flashlight.global_rotation = 0.0
	flashlight.set_mock_time_msec(0)

	# Simulate wall clamping (player flush against wall)
	flashlight.set_mock_player_center(Vector2(0, 0))
	flashlight.global_position = Vector2(20, 0)
	flashlight.set_mock_wall_hit(Vector2(18, 0))
	flashlight.clamp_light_to_walls()
	assert_true(flashlight._is_wall_clamped)

	# Enemy is in front of the flashlight (would be in beam if no wall)
	var enemies := [
		{"id": 1, "position": Vector2(300, 0)},
	]

	flashlight.check_enemies(enemies)

	assert_eq(flashlight.blindness_applied.size(), 0,
		"Enemies should NOT be blinded when flashlight is wall-clamped (beam blocked by wall)")


func test_blinding_resumes_after_wall_clamp_clears() -> void:
	# Issue #640: After moving away from wall, blinding should work again.
	flashlight.turn_on()
	flashlight.global_rotation = 0.0
	flashlight.set_mock_time_msec(0)

	# First: wall-clamp
	flashlight.set_mock_player_center(Vector2(0, 0))
	flashlight.global_position = Vector2(20, 0)
	flashlight.set_mock_wall_hit(Vector2(18, 0))
	flashlight.clamp_light_to_walls()
	assert_true(flashlight._is_wall_clamped)

	var enemies := [
		{"id": 1, "position": Vector2(300, 0)},
	]

	# No blinding when wall-clamped
	flashlight.check_enemies(enemies)
	assert_eq(flashlight.blindness_applied.size(), 0)

	# Then: move away from wall
	flashlight.set_mock_wall_hit(null)
	flashlight.clamp_light_to_walls()
	assert_false(flashlight._is_wall_clamped)

	# Blinding should work again
	flashlight.check_enemies(enemies)
	assert_eq(flashlight.blindness_applied.size(), 1,
		"Enemy should be blinded after wall clamp clears")


func test_scatter_light_restored_after_wall_clamp_clears() -> void:
	flashlight.global_position = Vector2(20, 0)
	flashlight.global_rotation = 0.0
	flashlight.turn_on()

	# First: wall clamp
	flashlight.set_mock_player_center(Vector2(0, 0))
	flashlight.set_mock_wall_hit(Vector2(18, 0))
	flashlight.clamp_light_to_walls()
	flashlight.update_scatter_light_position()
	assert_false(flashlight.scatter_light_visible)

	# Then: move away from wall
	flashlight.set_mock_wall_hit(null)
	flashlight.clamp_light_to_walls()
	flashlight.update_scatter_light_position()
	assert_true(flashlight.scatter_light_visible,
		"Scatter light should be visible again after wall clamp clears")


# ============================================================================
# Beam-Direction Wall Clamping Tests (Issue #640 root cause #6)
# When the barrel is on the player's side of a wall but the beam direction
# immediately enters the wall, enemies should not detect/be blinded by it.
# ============================================================================


func test_beam_direction_wall_clamps() -> void:
	# Player at origin, barrel at (20, 0), no wall between center and barrel.
	# But beam direction (pointing right) immediately hits a wall at (25, 0).
	flashlight.set_mock_player_center(Vector2(0, 0))
	flashlight.global_position = Vector2(20, 0)
	flashlight.global_rotation = 0.0  # Pointing right
	flashlight.set_mock_wall_hit(null)  # No wall between center and barrel
	flashlight.set_mock_beam_wall_hit(Vector2(25, 0))  # Wall immediately in beam direction

	flashlight.clamp_light_to_walls()

	assert_true(flashlight._is_wall_clamped,
		"Wall clamped should be true when beam direction immediately hits a wall")


func test_beam_direction_wall_clamp_reduces_texture_scale() -> void:
	flashlight.set_mock_player_center(Vector2(0, 0))
	flashlight.global_position = Vector2(20, 0)
	flashlight.global_rotation = 0.0
	flashlight.set_mock_wall_hit(null)
	flashlight.set_mock_beam_wall_hit(Vector2(25, 0))  # 25px from player center

	flashlight.clamp_light_to_walls()

	# Expected scale: 25 * 2 / 2048 ≈ 0.024 → clamped to minimum 0.1
	assert_almost_eq(flashlight.point_light_texture_scale, 0.1, 0.01,
		"Texture scale should be reduced when beam direction hits nearby wall")
	assert_eq(flashlight.point_light_shadow_filter, 0,
		"Shadow filter should be NONE when beam-direction wall-clamped")


func test_beam_direction_wall_clamp_suppresses_blinding() -> void:
	flashlight.turn_on()
	flashlight.global_rotation = 0.0
	flashlight.set_mock_time_msec(0)

	# Barrel on player's side, but beam hits wall immediately
	flashlight.set_mock_player_center(Vector2(0, 0))
	flashlight.global_position = Vector2(20, 0)
	flashlight.set_mock_wall_hit(null)
	flashlight.set_mock_beam_wall_hit(Vector2(25, 0))
	flashlight.clamp_light_to_walls()
	assert_true(flashlight._is_wall_clamped)

	var enemies := [
		{"id": 1, "position": Vector2(300, 0)},
	]

	flashlight.check_enemies(enemies)

	assert_eq(flashlight.blindness_applied.size(), 0,
		"Enemies should NOT be blinded when beam immediately hits wall in beam direction")


func test_beam_direction_wall_clamp_clears_when_wall_removed() -> void:
	flashlight.set_mock_player_center(Vector2(0, 0))
	flashlight.global_position = Vector2(20, 0)
	flashlight.global_rotation = 0.0
	flashlight.set_mock_wall_hit(null)
	flashlight.set_mock_beam_wall_hit(Vector2(25, 0))

	flashlight.clamp_light_to_walls()
	assert_true(flashlight._is_wall_clamped)

	# Remove beam-direction wall
	flashlight.set_mock_beam_wall_hit(null)
	flashlight.clamp_light_to_walls()
	assert_false(flashlight._is_wall_clamped,
		"Wall clamped should be false after beam-direction wall is removed")
	assert_eq(flashlight.point_light_texture_scale, flashlight.LIGHT_TEXTURE_SCALE,
		"Texture scale should be restored to default")
	assert_eq(flashlight.point_light_shadow_filter, 1,
		"Shadow filter should be restored to PCF5")
