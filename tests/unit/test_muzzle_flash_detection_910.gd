extends GutTest
## Unit tests for MuzzleFlashDetectionComponent (Issue #910).
##
## When the player fires while invisible, enemies with LOS to the muzzle flash
## should detect it and use that position for suppressive fire.
##
## Tests verify:
## 1. Detection only happens when player is invisible
## 2. FOV check (flash outside FOV → not detected)
## 3. Range check (flash too far → not detected)
## 4. Flash age check (old flash → not detected)
## 5. Player visible → no flash detection (use normal combat)
## 6. COMBAT state: suppressive fire now fires immediately (not delayed by 0.5s)


# ============================================================================
# Mock Classes
# ============================================================================


class MockImpactManager:
	## Simulates ImpactEffectsManager.get_active_muzzle_flashes().
	var flashes: Array = []

	func get_active_muzzle_flashes() -> Array:
		return flashes

	func add_flash(position: Vector2, direction: Vector2, age: float = 0.05) -> void:
		flashes.append({
			"position": position,
			"direction": direction.normalized(),
			"age": age
		})

	func clear_flashes() -> void:
		flashes.clear()


class MockPlayer:
	## Mock player with invisibility and position.
	var global_position: Vector2 = Vector2(300.0, 0.0)
	var _invisible: bool = true
	var _mock_impact_manager: MockImpactManager = null

	func is_invisible() -> bool:
		return _invisible

	func get_node_or_null(path: String) -> Variant:
		if path == "/root/ImpactEffectsManager" and _mock_impact_manager != null:
			return _mock_impact_manager
		return null


class MockDetectionComponent:
	## Testable version of MuzzleFlashDetectionComponent without Godot scene dependencies.
	## Uses MockImpactManager instead of the actual ImpactEffectsManager.

	const MUZZLE_FLASH_MAX_RANGE: float = 500.0
	const FLASH_MAX_AGE: float = 0.35
	const CHECK_INTERVAL: float = 0.1

	var detected: bool = false
	var estimated_player_position: Vector2 = Vector2.ZERO
	var flash_direction: Vector2 = Vector2.ZERO
	var flash_position: Vector2 = Vector2.ZERO

	var _check_timer: float = CHECK_INTERVAL  # Start ready to check
	var _impact_manager: MockImpactManager = null

	func setup(impact_manager: MockImpactManager) -> void:
		_impact_manager = impact_manager

	func check_flash(
		enemy_pos: Vector2,
		enemy_facing_angle: float,
		enemy_fov_deg: float,
		enemy_fov_enabled: bool,
		player: MockPlayer,
		can_see_player: bool,
		delta: float
	) -> bool:
		_check_timer += delta
		if _check_timer < CHECK_INTERVAL:
			return detected
		_check_timer = 0.0

		detected = false
		estimated_player_position = Vector2.ZERO
		flash_direction = Vector2.ZERO
		flash_position = Vector2.ZERO

		if can_see_player:
			return false

		if player == null:
			return false
		if not player.is_invisible():
			return false

		if _impact_manager == null:
			return false

		var active_flashes := _impact_manager.get_active_muzzle_flashes()
		if active_flashes.is_empty():
			return false

		var enemy_facing_dir := Vector2.from_angle(enemy_facing_angle)
		var fov_half_angle_rad := deg_to_rad(enemy_fov_deg / 2.0) if enemy_fov_deg > 0.0 else PI

		for flash_data in active_flashes:
			var f_pos: Vector2 = flash_data.get("position", Vector2.ZERO)
			var f_dir: Vector2 = flash_data.get("direction", Vector2.ZERO)
			var f_age: float = flash_data.get("age", 999.0)

			if f_age > FLASH_MAX_AGE:
				continue

			var dist: float = enemy_pos.distance_to(f_pos)
			if dist > MUZZLE_FLASH_MAX_RANGE:
				continue

			if enemy_fov_enabled and enemy_fov_deg > 0.0:
				var dir_to_flash := (f_pos - enemy_pos).normalized()
				if enemy_facing_dir.dot(dir_to_flash) < cos(fov_half_angle_rad):
					continue

			# For unit tests we skip LOS check (no raycast available) — tested at integration level
			detected = true
			flash_position = f_pos
			flash_direction = f_dir
			estimated_player_position = f_pos - f_dir * 30.0
			return true

		return false

	func reset() -> void:
		detected = false
		estimated_player_position = Vector2.ZERO
		flash_direction = Vector2.ZERO
		flash_position = Vector2.ZERO
		_check_timer = 0.0


# ============================================================================
# Test Setup
# ============================================================================


var _detection: MockDetectionComponent
var _player: MockPlayer
var _impact_mgr: MockImpactManager

var _enemy_pos := Vector2.ZERO
var _flash_pos := Vector2(200.0, 0.0)
var _flash_dir := Vector2(1.0, 0.0)  # Player was shooting to the right


func before_each() -> void:
	_impact_mgr = MockImpactManager.new()
	_player = MockPlayer.new()
	_player._mock_impact_manager = _impact_mgr

	_detection = MockDetectionComponent.new()
	_detection.setup(_impact_mgr)

	# Reset to ready-to-check state
	_detection._check_timer = MockDetectionComponent.CHECK_INTERVAL


# ============================================================================
# Test: Constants
# ============================================================================


func test_max_range_is_reasonable() -> void:
	assert_gt(MockDetectionComponent.MUZZLE_FLASH_MAX_RANGE, 100.0, "Range > 100px")
	assert_lt(MockDetectionComponent.MUZZLE_FLASH_MAX_RANGE, 1500.0, "Range < viewport diagonal")


func test_flash_max_age_slightly_longer_than_visual_effect() -> void:
	# Muzzle flash visual duration is 0.3s, detection tolerance should be slightly longer
	assert_gt(MockDetectionComponent.FLASH_MAX_AGE, 0.3, "Max age should exceed visual duration")
	assert_lt(MockDetectionComponent.FLASH_MAX_AGE, 1.0, "Max age should not be excessively long")


func test_check_interval_is_reasonable() -> void:
	# Check interval should prevent every-frame overhead
	assert_gt(MockDetectionComponent.CHECK_INTERVAL, 0.0, "Check interval must be positive")
	assert_lt(MockDetectionComponent.CHECK_INTERVAL, 0.5, "Check interval should be sub-second")


# ============================================================================
# Test: Basic Detection
# ============================================================================


func test_detects_fresh_flash_in_range_with_fov() -> void:
	_impact_mgr.add_flash(_flash_pos, _flash_dir, 0.05)  # Fresh flash

	# Enemy at origin, facing right (0°), FOV 180°
	var result := _detection.check_flash(_enemy_pos, 0.0, 180.0, false, _player, false, 0.2)

	assert_true(result, "Should detect fresh flash in range")
	assert_true(_detection.detected, "detected flag should be true")
	assert_ne(_detection.flash_position, Vector2.ZERO, "Flash position should be set")


func test_estimated_player_position_is_behind_flash() -> void:
	_impact_mgr.add_flash(_flash_pos, _flash_dir, 0.05)

	_detection.check_flash(_enemy_pos, 0.0, 180.0, false, _player, false, 0.2)

	# Player should be ~30px behind the muzzle (opposite to shoot direction)
	var expected_pos := _flash_pos - _flash_dir * 30.0
	assert_almost_eq(_detection.estimated_player_position.x, expected_pos.x, 1.0,
		"Estimated x position should be behind flash")
	assert_almost_eq(_detection.estimated_player_position.y, expected_pos.y, 1.0,
		"Estimated y position should be behind flash")


# ============================================================================
# Test: No Detection Conditions
# ============================================================================


func test_no_detection_when_player_is_visible() -> void:
	_impact_mgr.add_flash(_flash_pos, _flash_dir, 0.05)

	# can_see_player = true → skip flash detection
	var result := _detection.check_flash(_enemy_pos, 0.0, 180.0, false, _player, true, 0.2)

	assert_false(result, "Should NOT detect when player is visible")
	assert_false(_detection.detected, "detected flag should be false")


func test_no_detection_when_player_is_not_invisible() -> void:
	_player._invisible = false
	_impact_mgr.add_flash(_flash_pos, _flash_dir, 0.05)

	var result := _detection.check_flash(_enemy_pos, 0.0, 180.0, false, _player, false, 0.2)

	assert_false(result, "Should NOT detect when player is NOT invisible")
	assert_false(_detection.detected, "detected flag should be false when player visible")


func test_no_detection_when_flash_too_old() -> void:
	_impact_mgr.add_flash(_flash_pos, _flash_dir, MockDetectionComponent.FLASH_MAX_AGE + 0.01)

	var result := _detection.check_flash(_enemy_pos, 0.0, 180.0, false, _player, false, 0.2)

	assert_false(result, "Should NOT detect flash that is too old")
	assert_false(_detection.detected, "detected flag should be false for old flash")


func test_no_detection_when_flash_too_far() -> void:
	var far_pos := Vector2(MockDetectionComponent.MUZZLE_FLASH_MAX_RANGE + 50.0, 0.0)
	_impact_mgr.add_flash(far_pos, _flash_dir, 0.05)

	var result := _detection.check_flash(_enemy_pos, 0.0, 180.0, false, _player, false, 0.2)

	assert_false(result, "Should NOT detect flash beyond max range")
	assert_false(_detection.detected, "detected flag should be false for far flash")


func test_no_detection_when_no_flashes() -> void:
	# No flashes in impact manager
	var result := _detection.check_flash(_enemy_pos, 0.0, 180.0, false, _player, false, 0.2)

	assert_false(result, "Should NOT detect when no flashes exist")
	assert_false(_detection.detected, "detected flag should be false with no flashes")


# ============================================================================
# Test: FOV Constraint
# ============================================================================


func test_no_detection_when_flash_outside_fov() -> void:
	# Enemy facing LEFT (180°), flash is to the RIGHT → outside 90° FOV
	_impact_mgr.add_flash(_flash_pos, _flash_dir, 0.05)

	var result := _detection.check_flash(
		_enemy_pos,
		PI,        # Facing left (180°)
		90.0,      # 90° FOV (half = 45°)
		true,      # FOV enabled
		_player, false, 0.2
	)

	assert_false(result, "Should NOT detect flash outside FOV")
	assert_false(_detection.detected, "detected flag should be false outside FOV")


func test_detects_flash_inside_fov() -> void:
	# Enemy facing RIGHT (0°), flash is slightly to the right → inside 90° FOV
	var near_flash_pos := Vector2(100.0, 20.0)  # Slightly off center
	_impact_mgr.add_flash(near_flash_pos, _flash_dir, 0.05)

	var result := _detection.check_flash(
		_enemy_pos,
		0.0,       # Facing right
		90.0,      # 90° FOV
		true,      # FOV enabled
		_player, false, 0.2
	)

	assert_true(result, "Should detect flash inside FOV")


func test_detects_flash_when_fov_disabled() -> void:
	# When FOV is disabled, enemy has 360° vision
	_impact_mgr.add_flash(_flash_pos, _flash_dir, 0.05)

	var result := _detection.check_flash(
		_enemy_pos,
		PI,        # Facing away from flash
		90.0,      # FOV setting (ignored when disabled)
		false,     # FOV DISABLED
		_player, false, 0.2
	)

	assert_true(result, "Should detect flash when FOV is disabled (360° vision)")


# ============================================================================
# Test: Check Interval
# ============================================================================


func test_check_interval_not_ready() -> void:
	_impact_mgr.add_flash(_flash_pos, _flash_dir, 0.05)
	_detection._check_timer = 0.0  # Just checked, not ready yet

	# Call with tiny delta (not enough to reach CHECK_INTERVAL)
	var result := _detection.check_flash(_enemy_pos, 0.0, 180.0, false, _player, false, 0.01)

	# Should return previous state (false, not newly detected)
	assert_false(result, "Should not re-check before interval expires")


func test_check_triggers_after_interval() -> void:
	_impact_mgr.add_flash(_flash_pos, _flash_dir, 0.05)
	_detection._check_timer = 0.0

	# Call with enough delta to reach CHECK_INTERVAL
	var result := _detection.check_flash(_enemy_pos, 0.0, 180.0, false, _player, false, MockDetectionComponent.CHECK_INTERVAL + 0.01)

	assert_true(result, "Should detect flash after check interval expires")


# ============================================================================
# Test: Reset
# ============================================================================


func test_reset_clears_all_state() -> void:
	_impact_mgr.add_flash(_flash_pos, _flash_dir, 0.05)
	_detection.check_flash(_enemy_pos, 0.0, 180.0, false, _player, false, 0.2)
	assert_true(_detection.detected, "Should be detected before reset")

	_detection.reset()

	assert_false(_detection.detected, "detected should be false after reset")
	assert_eq(_detection.estimated_player_position, Vector2.ZERO, "estimated position should be zero after reset")
	assert_eq(_detection.flash_position, Vector2.ZERO, "flash position should be zero after reset")
	assert_eq(_detection.flash_direction, Vector2.ZERO, "flash direction should be zero after reset")


# ============================================================================
# Test: COMBAT State Suppressive Fire (Issue #910 Root Cause C)
# ============================================================================


class MockCombatEnemy:
	## Simulates the relevant part of _process_combat_state() after the fix.
	##
	## Before fix: enemy in COMBAT with invisible player does nothing for 0.5s, then pursues.
	## After fix: enemy in COMBAT IMMEDIATELY fires suppressive shots then waits to pursue.

	const COMBAT_MIN_DURATION: float = 0.5
	const SUPPRESSIVE_RANGE: float = 600.0

	var _combat_state_timer: float = 0.0
	var _can_see_player: bool = false
	var _last_known_player_position: Vector2 = Vector2(200.0, 0.0)
	var global_position: Vector2 = Vector2.ZERO
	var _shoot_timer: float = 999.0  # Ready to shoot
	var _shoot_cooldown: float = 0.1
	var _is_melee_weapon: bool = false
	var _is_reloading: bool = false
	var suppressive_shots_fired: int = 0
	var transitioned_to_pursuing: bool = false

	var _player_invisible: bool = true

	func _try_suppress() -> void:
		if _can_see_player or _last_known_player_position == Vector2.ZERO or _is_melee_weapon:
			return
		if not _player_invisible:
			return
		var dist := global_position.distance_to(_last_known_player_position)
		if dist > SUPPRESSIVE_RANGE or _is_reloading:
			return
		if _shoot_timer >= _shoot_cooldown:
			suppressive_shots_fired += 1
			_shoot_timer = 0.0

	func process_combat(delta: float) -> void:
		_combat_state_timer += delta
		if not _can_see_player:
			if _combat_state_timer >= COMBAT_MIN_DURATION:
				transitioned_to_pursuing = true
				return
			# After fix: call suppressive fire here
			_try_suppress()


func test_combat_state_fires_immediately_not_after_delay() -> void:
	## Verifies that after PR #911 fix, suppressive fire in COMBAT state
	## happens BEFORE the 0.5s transition-to-pursuing delay expires.
	var enemy := MockCombatEnemy.new()
	enemy._can_see_player = false
	enemy._player_invisible = true
	enemy._shoot_timer = 1.0  # Ready to shoot

	# Process for just 0.1s (less than COMBAT_MIN_DURATION = 0.5s)
	enemy.process_combat(0.1)

	assert_eq(enemy.suppressive_shots_fired, 1,
		"Should fire suppressive shot immediately in COMBAT (not wait 0.5s)")
	assert_false(enemy.transitioned_to_pursuing,
		"Should NOT transition to PURSUING after only 0.1s")


func test_combat_state_still_transitions_after_min_duration() -> void:
	var enemy := MockCombatEnemy.new()
	enemy._can_see_player = false
	enemy._player_invisible = true

	# Process for longer than COMBAT_MIN_DURATION
	enemy.process_combat(0.6)

	assert_true(enemy.transitioned_to_pursuing,
		"Should transition to PURSUING after min duration")


func test_combat_state_no_suppressive_fire_when_player_visible() -> void:
	var enemy := MockCombatEnemy.new()
	enemy._can_see_player = true  # Normal combat - player is visible
	enemy._player_invisible = false

	enemy.process_combat(0.1)

	assert_eq(enemy.suppressive_shots_fired, 0,
		"No suppressive fire in COMBAT when player is visible")


func test_combat_state_no_suppressive_fire_when_player_not_invisible() -> void:
	var enemy := MockCombatEnemy.new()
	enemy._can_see_player = false
	enemy._player_invisible = false  # Not using invisibility suit

	enemy.process_combat(0.1)

	assert_eq(enemy.suppressive_shots_fired, 0,
		"No suppressive fire in COMBAT when player not invisible")
