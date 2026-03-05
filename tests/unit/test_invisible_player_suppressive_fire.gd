extends GutTest
## Unit tests for Issue #910: Enemies should fire suppressive rounds toward invisible player's sound source.
##
## When the player has the Invisibility Suit active and fires their weapon:
## 1. The gunshot sound propagates to enemies and sets _last_known_player_position
## 2. Enemies in PURSUING/IN_COVER states fire suppressive fan-fire toward the sound position
## 3. The fan spread (INVISIBLE_PLAYER_FAN_SPREAD ~28°) simulates "shooting toward sound" uncertainty
## 4. Enemies do NOT fire suppressive shots when player is visible (normal combat mode)
## 5. Enemies do NOT fire when out of INVISIBLE_PLAYER_SUPPRESSIVE_RANGE or reloading


# ============================================================================
# Mock Classes for Testing
# ============================================================================


class MockPlayer:
	## Mock player with invisibility state.
	var global_position: Vector2 = Vector2.ZERO
	var _invisible: bool = false

	func is_invisible() -> bool:
		return _invisible

	func set_invisible(value: bool) -> void:
		_invisible = value


class MockProjectile:
	## Records what direction a projectile was fired in.
	var direction: Vector2 = Vector2.ZERO
	var position: Vector2 = Vector2.ZERO


class MockEnemyAI:
	## Minimal mock of the enemy AI suppressive fire logic from enemy.gd (Issue #910).
	##
	## This tests the logic isolated from the full Godot scene, allowing unit tests
	## to run without instantiating the actual enemy scene.

	# --- Constants from enemy.gd (Issue #910) ---
	const INVISIBLE_PLAYER_FAN_SPREAD: float = 0.5  ## ~28.6° half-angle
	const INVISIBLE_PLAYER_SUPPRESSIVE_RANGE: float = 600.0
	const SUPPRESSIVE_AIM_TOLERANCE_DOT: float = 0.5

	# --- AI State enum ---
	enum AIState { IDLE, COMBAT, PURSUING, IN_COVER, SUPPRESSED }

	# --- State variables ---
	var global_position: Vector2 = Vector2.ZERO
	var _can_see_player: bool = false
	var _last_known_player_position: Vector2 = Vector2.ZERO
	var _is_reloading: bool = false
	var _is_melee_weapon: bool = false
	var _shoot_timer: float = 0.0
	var shoot_cooldown: float = 0.1
	var _current_state: AIState = AIState.IDLE
	var _suppressing_invisible_player: bool = false

	# --- Mock references ---
	var _player: MockPlayer = null
	var bullet_scene: bool = true  # Non-null means bullet_scene exists
	var _current_ammo: int = 30
	var _reserve_ammo: int = 120

	# --- Test tracking ---
	var shots_fired: Array[Dictionary] = []
	var shot_blocked_reasons: Array[String] = []
	var can_shoot_result: bool = true
	var bullet_spawn_clear_result: bool = true
	var last_suppressive_shot_direction: Vector2 = Vector2.ZERO

	## Simulate _can_shoot()
	func _can_shoot() -> bool:
		if _current_ammo <= 0:
			return false
		if _is_reloading:
			return false
		return can_shoot_result

	## Simulate _is_bullet_spawn_clear()
	func _is_bullet_spawn_clear(_direction: Vector2) -> bool:
		return bullet_spawn_clear_result

	## Simulate _get_weapon_forward_direction()
	func _get_weapon_forward_direction() -> Vector2:
		if _player != null:
			return (_player.global_position - global_position).normalized()
		return Vector2.RIGHT

	## Simulate _get_bullet_spawn_position()
	func _get_bullet_spawn_position(_direction: Vector2) -> Vector2:
		return global_position + _direction * 30.0

	## Simulate _shoot_suppressive_at() from enemy.gd (Issue #910)
	func _shoot_suppressive_at(target_pos: Vector2) -> void:
		if not bullet_scene:
			return
		if not _can_shoot():
			shot_blocked_reasons.append("cannot_shoot")
			return
		var to_target := (target_pos - global_position).normalized()
		if to_target == Vector2.ZERO:
			shot_blocked_reasons.append("zero_direction")
			return
		# Apply random fan spread
		var fan_angle := randf_range(-INVISIBLE_PLAYER_FAN_SPREAD, INVISIBLE_PLAYER_FAN_SPREAD)
		var direction := to_target.rotated(fan_angle)
		if not _is_bullet_spawn_clear(direction):
			shot_blocked_reasons.append("wall_blocked")
			return
		# Record shot
		last_suppressive_shot_direction = direction
		shots_fired.append({
			"direction": direction,
			"fan_angle": fan_angle,
			"target_pos": target_pos,
		})
		_current_ammo -= 1

	## Simulate the invisible player suppressive fire check from _process_pursuing_state().
	## Returns true if suppressive fire was triggered.
	func check_and_fire_suppressive_pursuing() -> bool:
		if _can_see_player or _last_known_player_position == Vector2.ZERO or _is_melee_weapon:
			_suppressing_invisible_player = false
			return false
		if _player == null or not _player.has_method("is_invisible") or not _player.is_invisible():
			_suppressing_invisible_player = false
			return false
		var dist_to_sound := global_position.distance_to(_last_known_player_position)
		if dist_to_sound > INVISIBLE_PLAYER_SUPPRESSIVE_RANGE or _is_reloading:
			_suppressing_invisible_player = false
			return false
		if _shoot_timer >= shoot_cooldown:
			_shoot_suppressive_at(_last_known_player_position)
			_shoot_timer = 0.0
		_suppressing_invisible_player = true
		return true

	## Simulate the invisible player suppressive fire check from _process_in_cover_state().
	## Returns true if suppressive fire was triggered (stay in cover).
	func check_and_fire_suppressive_in_cover() -> bool:
		if _can_see_player or _player == null:
			return false
		var player_is_invisible := _player.has_method("is_invisible") and _player.is_invisible()
		if not player_is_invisible or _last_known_player_position == Vector2.ZERO or _is_melee_weapon:
			return false
		var dist_to_sound := global_position.distance_to(_last_known_player_position)
		if dist_to_sound > INVISIBLE_PLAYER_SUPPRESSIVE_RANGE or _is_reloading:
			return false
		if _shoot_timer >= shoot_cooldown:
			_shoot_suppressive_at(_last_known_player_position)
			_shoot_timer = 0.0
		return true


# ============================================================================
# Test Setup
# ============================================================================


var _enemy: MockEnemyAI
var _player: MockPlayer


func before_each() -> void:
	_player = MockPlayer.new()
	_player.global_position = Vector2(200.0, 100.0)
	_player.set_invisible(true)

	_enemy = MockEnemyAI.new()
	_enemy.global_position = Vector2.ZERO
	_enemy._player = _player
	_enemy._can_see_player = false
	_enemy._shoot_timer = 999.0  # Ready to shoot
	_enemy._last_known_player_position = Vector2(200.0, 100.0)


# ============================================================================
# Test: Constants
# ============================================================================


func test_fan_spread_constant_is_reasonable() -> void:
	# INVISIBLE_PLAYER_FAN_SPREAD ~28.6° half-angle spread
	var spread_deg := rad_to_deg(MockEnemyAI.INVISIBLE_PLAYER_FAN_SPREAD)
	assert_gt(spread_deg, 15.0, "Fan spread should be at least 15 degrees")
	assert_lt(spread_deg, 60.0, "Fan spread should be less than 60 degrees")


func test_suppressive_range_constant_is_reasonable() -> void:
	# INVISIBLE_PLAYER_SUPPRESSIVE_RANGE should be meaningful combat distance
	assert_gt(MockEnemyAI.INVISIBLE_PLAYER_SUPPRESSIVE_RANGE, 100.0, "Range should cover more than 100px")
	assert_lt(MockEnemyAI.INVISIBLE_PLAYER_SUPPRESSIVE_RANGE, 2000.0, "Range should not be excessively long")


func test_suppressive_aim_tolerance_allows_wide_angle() -> void:
	# SUPPRESSIVE_AIM_TOLERANCE_DOT = 0.5 = cos(60°) - wider than normal AIM_TOLERANCE_DOT (0.866 = cos(30°))
	# This test verifies the constant is set for wider tolerance
	assert_lt(MockEnemyAI.SUPPRESSIVE_AIM_TOLERANCE_DOT, 0.87, "Suppressive tolerance should be wider than normal (0.866)")
	assert_gt(MockEnemyAI.SUPPRESSIVE_AIM_TOLERANCE_DOT, 0.0, "Suppressive tolerance should be positive")


# ============================================================================
# Test: Basic Suppressive Fire Triggering
# ============================================================================


func test_suppressive_fire_triggers_when_player_invisible_in_pursuing() -> void:
	# When enemy is pursuing and player is invisible with known sound position,
	# suppressive fire should be triggered
	var triggered := _enemy.check_and_fire_suppressive_pursuing()
	assert_true(triggered, "Suppressive fire should trigger when player is invisible")
	assert_eq(_enemy.shots_fired.size(), 1, "One suppressive shot should be fired")


func test_suppressive_fire_triggers_when_player_invisible_in_cover() -> void:
	# When enemy is in cover and player is invisible with known sound position,
	# suppressive fire should be triggered
	var triggered := _enemy.check_and_fire_suppressive_in_cover()
	assert_true(triggered, "Suppressive fire from cover should trigger when player is invisible")
	assert_eq(_enemy.shots_fired.size(), 1, "One suppressive shot should be fired from cover")


func test_suppressive_fire_does_not_trigger_when_player_visible() -> void:
	# When enemy can see the player (normal combat), no suppressive fire
	_enemy._can_see_player = true
	_player.set_invisible(false)  # Player visible

	var triggered := _enemy.check_and_fire_suppressive_pursuing()
	assert_false(triggered, "Suppressive fire should NOT trigger when player is visible")
	assert_eq(_enemy.shots_fired.size(), 0, "No shots should be fired when player is visible")


func test_suppressive_fire_does_not_trigger_without_sound_position() -> void:
	# If we don't know where the gunshot came from, don't fire
	_enemy._last_known_player_position = Vector2.ZERO

	var triggered := _enemy.check_and_fire_suppressive_pursuing()
	assert_false(triggered, "Suppressive fire should NOT trigger without a known sound position")
	assert_eq(_enemy.shots_fired.size(), 0, "No shots should be fired without sound position")


func test_suppressive_fire_does_not_trigger_when_player_not_invisible() -> void:
	# If player is NOT invisible (normal situation), suppressive fire should NOT trigger
	# (enemy would use normal combat AI instead)
	_player.set_invisible(false)

	var triggered := _enemy.check_and_fire_suppressive_pursuing()
	assert_false(triggered, "Suppressive fire should NOT trigger when player is not invisible")
	assert_eq(_enemy.shots_fired.size(), 0, "No shots should be fired when player is visible")


# ============================================================================
# Test: Range Check
# ============================================================================


func test_suppressive_fire_respects_range_limit() -> void:
	# If the sound position is beyond INVISIBLE_PLAYER_SUPPRESSIVE_RANGE, don't fire
	var far_position := Vector2(MockEnemyAI.INVISIBLE_PLAYER_SUPPRESSIVE_RANGE + 100.0, 0.0)
	_enemy._last_known_player_position = far_position

	var triggered := _enemy.check_and_fire_suppressive_pursuing()
	assert_false(triggered, "Suppressive fire should NOT trigger when sound position is out of range")
	assert_eq(_enemy.shots_fired.size(), 0, "No shots should be fired when out of range")


func test_suppressive_fire_triggers_within_range() -> void:
	# If the sound position is within range, suppressive fire should trigger
	var near_position := Vector2(MockEnemyAI.INVISIBLE_PLAYER_SUPPRESSIVE_RANGE - 100.0, 0.0)
	_enemy._last_known_player_position = near_position

	var triggered := _enemy.check_and_fire_suppressive_pursuing()
	assert_true(triggered, "Suppressive fire should trigger when sound position is within range")
	assert_eq(_enemy.shots_fired.size(), 1, "One shot should be fired within range")


# ============================================================================
# Test: Melee Weapon Exception
# ============================================================================


func test_suppressive_fire_does_not_trigger_for_melee_weapons() -> void:
	# Melee enemies (machete) should NOT fire suppressive rounds (they have no gun)
	_enemy._is_melee_weapon = true

	var triggered := _enemy.check_and_fire_suppressive_pursuing()
	assert_false(triggered, "Suppressive fire should NOT trigger for melee weapons")
	assert_eq(_enemy.shots_fired.size(), 0, "Melee enemies should not fire suppressive shots")


# ============================================================================
# Test: Reload State
# ============================================================================


func test_suppressive_fire_does_not_trigger_while_reloading() -> void:
	# If enemy is reloading, they can't fire suppressive shots
	_enemy._is_reloading = true

	var triggered := _enemy.check_and_fire_suppressive_pursuing()
	assert_false(triggered, "Suppressive fire should NOT trigger while reloading")
	assert_eq(_enemy.shots_fired.size(), 0, "No shots fired while reloading")


# ============================================================================
# Test: Shoot Timer Cooldown
# ============================================================================


func test_suppressive_fire_respects_shoot_cooldown() -> void:
	# If shoot_timer < shoot_cooldown, the trigger is set but no shot is fired yet
	_enemy._shoot_timer = 0.0  # Just fired, cooldown active
	_enemy.shoot_cooldown = 0.5

	var triggered := _enemy.check_and_fire_suppressive_pursuing()
	assert_true(triggered, "Suppressive fire trigger should be set even on cooldown")
	assert_eq(_enemy.shots_fired.size(), 0, "No shot should be fired while on cooldown")


func test_suppressive_fire_fires_when_cooldown_expires() -> void:
	# When shoot_timer >= shoot_cooldown, shot is fired
	_enemy._shoot_timer = 1.0  # Cooldown expired
	_enemy.shoot_cooldown = 0.1

	var triggered := _enemy.check_and_fire_suppressive_pursuing()
	assert_true(triggered, "Suppressive fire trigger should be set")
	assert_eq(_enemy.shots_fired.size(), 1, "Shot should be fired when cooldown expires")


# ============================================================================
# Test: Fan Spread
# ============================================================================


func test_suppressive_fire_direction_is_roughly_toward_sound_position() -> void:
	# The fired bullet should be directed roughly toward the sound position
	# (within fan spread of INVISIBLE_PLAYER_FAN_SPREAD radians)
	_enemy._shoot_suppressive_at(_enemy._last_known_player_position)

	assert_eq(_enemy.shots_fired.size(), 1, "One shot should be fired")
	var shot: Dictionary = _enemy.shots_fired[0]
	var ideal_dir := (_enemy._last_known_player_position - _enemy.global_position).normalized()
	var fired_dir: Vector2 = shot["direction"]
	var dot := ideal_dir.dot(fired_dir)
	# dot product should be >= cos(INVISIBLE_PLAYER_FAN_SPREAD) since fan_angle is within spread
	var min_cos := cos(MockEnemyAI.INVISIBLE_PLAYER_FAN_SPREAD)
	assert_gte(dot, min_cos - 0.01, "Shot direction should be within fan spread of ideal direction")


func test_suppressive_fire_has_random_spread() -> void:
	# Fire multiple shots and verify they're not all identical (fan spread is applied)
	var directions: Array[Vector2] = []
	for i in range(20):
		_enemy._shoot_suppressive_at(_enemy._last_known_player_position)
		if _enemy.shots_fired.size() > directions.size():
			directions.append(_enemy.shots_fired.back()["direction"])

	# Check that at least some shots are different (random spread)
	var unique_angles: Array[float] = []
	for dir in directions:
		var angle := dir.angle()
		if unique_angles.is_empty() or abs(unique_angles.back() - angle) > 0.001:
			unique_angles.append(angle)

	assert_gt(unique_angles.size(), 1, "Fan spread should produce varied shot directions")


# ============================================================================
# Test: Wall Block
# ============================================================================


func test_suppressive_fire_is_blocked_when_wall_in_the_way() -> void:
	# If there's a wall in the fire direction, the shot should be blocked
	_enemy.bullet_spawn_clear_result = false

	_enemy._shoot_suppressive_at(_enemy._last_known_player_position)

	assert_eq(_enemy.shots_fired.size(), 0, "No shot should be fired when wall blocks muzzle")
	assert_eq(_enemy.shot_blocked_reasons.size(), 1, "One blocked reason should be recorded")
	assert_eq(_enemy.shot_blocked_reasons[0], "wall_blocked", "Should be blocked by wall")


# ============================================================================
# Test: Ammo Tracking
# ============================================================================


func test_suppressive_fire_consumes_ammo() -> void:
	var initial_ammo := _enemy._current_ammo

	_enemy._shoot_suppressive_at(_enemy._last_known_player_position)

	assert_eq(_enemy._current_ammo, initial_ammo - 1, "One ammo should be consumed per suppressive shot")


func test_suppressive_fire_blocked_when_no_ammo() -> void:
	_enemy._current_ammo = 0

	_enemy._shoot_suppressive_at(_enemy._last_known_player_position)

	assert_eq(_enemy.shots_fired.size(), 0, "No shot should be fired when out of ammo")
	assert_gt(_enemy.shot_blocked_reasons.size(), 0, "Should record block reason")


# ============================================================================
# Test: Suppressing Flag State
# ============================================================================


func test_suppressing_flag_set_when_active() -> void:
	# When actively suppressing invisible player, flag should be set
	_enemy.check_and_fire_suppressive_pursuing()
	assert_true(_enemy._suppressing_invisible_player, "Suppressing flag should be true when active")


func test_suppressing_flag_cleared_when_player_becomes_visible() -> void:
	# When player stops being invisible, flag should be cleared
	_player.set_invisible(false)
	_enemy._can_see_player = true

	_enemy.check_and_fire_suppressive_pursuing()
	assert_false(_enemy._suppressing_invisible_player, "Suppressing flag should be false when player is visible")


func test_suppressing_flag_cleared_when_out_of_range() -> void:
	# When sound position is out of range, flag should be cleared
	_enemy._last_known_player_position = Vector2(MockEnemyAI.INVISIBLE_PLAYER_SUPPRESSIVE_RANGE + 100.0, 0.0)

	_enemy.check_and_fire_suppressive_pursuing()
	assert_false(_enemy._suppressing_invisible_player, "Suppressing flag should be false when out of range")
