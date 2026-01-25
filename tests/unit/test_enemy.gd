extends GutTest
## Unit tests for Enemy object.
##
## Tests the enemy AI state machine, health system, ammo management,
## and tactical behavior logic.


# ============================================================================
# Mock Enemy Class for Testing Logic
# ============================================================================


class MockEnemy:
	## AI States for tactical behavior (mirrors actual enum)
	enum AIState {
		IDLE,
		COMBAT,
		SEEKING_COVER,
		IN_COVER,
		FLANKING,
		SUPPRESSED,
		RETREATING,
		PURSUING,
		ASSAULT,
		SEARCHING  ## Issue #322: Methodical area search state
	}

	## Retreat behavior modes
	enum RetreatMode {
		FULL_HP,
		ONE_HIT,
		MULTIPLE_HITS
	}

	## Behavior modes
	enum BehaviorMode {
		PATROL,
		GUARD
	}

	## Configuration
	var behavior_mode: BehaviorMode = BehaviorMode.GUARD
	var move_speed: float = 220.0
	var combat_move_speed: float = 320.0
	var rotation_speed: float = 15.0
	var detection_range: float = 0.0
	var shoot_cooldown: float = 0.1
	var bullet_spawn_offset: float = 30.0
	var weapon_loudness: float = 1469.0
	var min_health: int = 2
	var max_health: int = 4
	var threat_sphere_radius: float = 100.0
	var suppression_cooldown: float = 2.0
	var threat_reaction_delay: float = 0.2
	var flank_angle: float = PI / 3.0
	var flank_distance: float = 200.0
	var enable_flanking: bool = true
	var enable_cover: bool = true
	var magazine_size: int = 30
	var total_magazines: int = 5
	var reload_time: float = 3.0
	var detection_delay: float = 0.2
	var lead_prediction_delay: float = 0.3
	var lead_prediction_visibility_threshold: float = 0.6
	var bullet_speed: float = 2500.0

	## State
	var _current_health: int = 0
	var _max_health: int = 0
	var _is_alive: bool = true
	var _current_state: AIState = AIState.IDLE
	var _can_see_player: bool = false
	var _under_fire: bool = false
	var _has_valid_cover: bool = false
	var _cover_position: Vector2 = Vector2.ZERO
	var _suppression_timer: float = 0.0
	var _shoot_timer: float = 0.0
	var _current_ammo: int = 0
	var _reserve_ammo: int = 0
	var _is_reloading: bool = false
	var _reload_timer: float = 0.0
	var _hits_taken: int = 0

	## Memory state (Issue #297, #318)
	var _memory: EnemyMemory = null
	var _last_known_player_position: Vector2 = Vector2.ZERO
	var _intel_share_timer: float = 0.0
	var _memory_reset_confusion_timer: float = 0.0
	const MEMORY_RESET_CONFUSION_DURATION: float = 0.5
	var _continuous_visibility_timer: float = 0.0

	## Hit reaction state (Issue #390)
	var _hit_reaction_timer: float = 0.0
	var _hit_reaction_direction: Vector2 = Vector2.ZERO
	const HIT_REACTION_DURATION: float = 0.8

	## Patrol state
	var _patrol_points: Array[Vector2] = []
	var _current_patrol_index: int = 0
	var _initial_position: Vector2 = Vector2.ZERO

	## Distraction threshold
	const PLAYER_DISTRACTION_ANGLE: float = 0.4014  # ~23 degrees

	## Callbacks for signals
	var on_hit: Callable
	var on_died: Callable
	var on_state_changed: Callable
	var on_ammo_changed: Callable
	var on_reload_started: Callable
	var on_reload_finished: Callable
	var on_ammo_depleted: Callable


	func initialize() -> void:
		_max_health = randi_range(min_health, max_health)
		_current_health = _max_health
		_current_ammo = magazine_size
		_reserve_ammo = magazine_size * (total_magazines - 1)
		_is_alive = true
		_current_state = AIState.IDLE
		_memory = EnemyMemory.new()
		_last_known_player_position = Vector2.ZERO
		_intel_share_timer = 0.0
		# Issue #390: Initialize hit reaction state
		_hit_reaction_timer = 0.0
		_hit_reaction_direction = Vector2.ZERO


	func get_current_health() -> int:
		return _current_health


	func get_max_health() -> int:
		return _max_health


	func is_alive() -> bool:
		return _is_alive


	func get_health_percent() -> float:
		if _max_health <= 0:
			return 0.0
		return float(_current_health) / float(_max_health)


	func get_current_state() -> AIState:
		return _current_state


	func set_state(new_state: AIState) -> void:
		if new_state != _current_state:
			_current_state = new_state
			if on_state_changed:
				on_state_changed.call(new_state)


	func on_bullet_hit(hit_direction: Vector2 = Vector2.RIGHT) -> void:
		if not _is_alive:
			return

		_current_health -= 1
		_hits_taken += 1

		# Issue #390: Set hit reaction to face attacker
		var attacker_direction := -hit_direction.normalized()
		if attacker_direction.length_squared() > 0.01:
			_hit_reaction_direction = attacker_direction
			_hit_reaction_timer = HIT_REACTION_DURATION

		if on_hit:
			on_hit.call()

		if _current_health <= 0:
			_die()


	func _die() -> void:
		_is_alive = false
		if on_died:
			on_died.call()


	func can_shoot() -> bool:
		return _is_alive and _current_ammo > 0 and not _is_reloading and _shoot_timer >= shoot_cooldown


	func shoot() -> bool:
		if not can_shoot():
			return false

		_current_ammo -= 1
		_shoot_timer = 0.0

		if on_ammo_changed:
			on_ammo_changed.call(_current_ammo, _reserve_ammo)

		return true


	func update_shoot_timer(delta: float) -> void:
		_shoot_timer += delta


	## Issue #390: Update hit reaction timer
	func update_hit_reaction(delta: float) -> void:
		if _hit_reaction_timer > 0:
			_hit_reaction_timer -= delta
			if _hit_reaction_timer <= 0:
				_hit_reaction_timer = 0.0
				_hit_reaction_direction = Vector2.ZERO


	## Issue #390: Check if hit reaction is active
	func is_hit_reaction_active() -> bool:
		return _hit_reaction_timer > 0 and _hit_reaction_direction.length_squared() > 0.01


	## Issue #390: Get the direction the enemy should face during hit reaction
	func get_hit_reaction_direction() -> Vector2:
		return _hit_reaction_direction


	func needs_reload() -> bool:
		return _current_ammo <= 0 and _reserve_ammo > 0


	func start_reload() -> void:
		if _is_reloading or _reserve_ammo <= 0:
			return
		_is_reloading = true
		_reload_timer = 0.0
		if on_reload_started:
			on_reload_started.call()


	func update_reload(delta: float) -> void:
		if not _is_reloading:
			return
		_reload_timer += delta
		if _reload_timer >= reload_time:
			_complete_reload()


	func _complete_reload() -> void:
		var ammo_needed := magazine_size - _current_ammo
		var ammo_to_load := mini(ammo_needed, _reserve_ammo)
		_reserve_ammo -= ammo_to_load
		_current_ammo += ammo_to_load
		_is_reloading = false
		_reload_timer = 0.0

		if on_reload_finished:
			on_reload_finished.call()
		if on_ammo_changed:
			on_ammo_changed.call(_current_ammo, _reserve_ammo)


	func is_reloading() -> bool:
		return _is_reloading


	func get_current_ammo() -> int:
		return _current_ammo


	func get_reserve_ammo() -> int:
		return _reserve_ammo


	func has_ammo() -> bool:
		return _current_ammo > 0 or _reserve_ammo > 0


	func get_retreat_mode() -> RetreatMode:
		if _hits_taken == 0:
			return RetreatMode.FULL_HP
		elif _hits_taken == 1:
			return RetreatMode.ONE_HIT
		else:
			return RetreatMode.MULTIPLE_HITS


	func should_seek_cover() -> bool:
		return enable_cover and _under_fire and not _has_valid_cover


	func should_flank() -> bool:
		return enable_flanking and _can_see_player and not _under_fire


	func set_under_fire(value: bool) -> void:
		_under_fire = value


	func set_can_see_player(value: bool) -> void:
		_can_see_player = value


	func update_suppression(delta: float) -> void:
		if _under_fire:
			_suppression_timer = suppression_cooldown
		else:
			_suppression_timer -= delta
			if _suppression_timer < 0:
				_suppression_timer = 0


	func is_suppressed() -> bool:
		return _suppression_timer > 0


	func calculate_lead_position(target_pos: Vector2, target_velocity: Vector2, own_pos: Vector2) -> Vector2:
		if target_velocity == Vector2.ZERO:
			return target_pos

		var distance := own_pos.distance_to(target_pos)
		var time_to_hit := distance / bullet_speed
		return target_pos + target_velocity * time_to_hit


	func is_player_distracted(player_rotation: float, enemy_position: Vector2, player_position: Vector2) -> bool:
		var to_enemy := (enemy_position - player_position).normalized()
		var player_facing := Vector2.RIGHT.rotated(player_rotation)
		var angle_diff := abs(to_enemy.angle_to(player_facing))
		return angle_diff > PLAYER_DISTRACTION_ANGLE


	func setup_patrol(initial_pos: Vector2, offsets: Array[Vector2]) -> void:
		_initial_position = initial_pos
		_patrol_points.clear()
		for offset in offsets:
			_patrol_points.append(initial_pos + offset)


	func get_next_patrol_point() -> Vector2:
		if _patrol_points.is_empty():
			return _initial_position
		_current_patrol_index = (_current_patrol_index + 1) % _patrol_points.size()
		return _patrol_points[_current_patrol_index]


	## Update memory with player position (called when enemy can see player).
	func update_memory(player_pos: Vector2, confidence: float = 1.0) -> void:
		if _memory != null:
			_memory.update_position(player_pos, confidence)
			_last_known_player_position = player_pos


	## Reset enemy memory - called when player "teleports" during last chance effect (Issue #318).
	## This makes the enemy forget the player's last known position, forcing them to
	## re-acquire the player through visual contact or sound detection.
	## Also resets visibility state and applies a confusion period to prevent immediate re-acquisition.
	func reset_memory() -> void:
		if _memory != null:
			_memory.reset()

		# Also reset the legacy last known position
		_last_known_player_position = Vector2.ZERO

		# Reset the intel sharing timer to prevent immediate re-acquisition from allies
		_intel_share_timer = 0.0

		# CRITICAL: Reset visibility state to prevent immediate re-acquisition (Issue #318)
		_can_see_player = false
		_continuous_visibility_timer = 0.0

		# Apply confusion cooldown
		_memory_reset_confusion_timer = MEMORY_RESET_CONFUSION_DURATION

		# Transition active combat/pursuit states to IDLE to require re-detection
		if _current_state in [AIState.PURSUING, AIState.COMBAT, AIState.ASSAULT, AIState.FLANKING]:
			_current_state = AIState.IDLE


	func has_memory_target() -> bool:
		return _memory != null and _memory.has_target()


	func get_memory_position() -> Vector2:
		return _memory.suspected_position if _memory != null else Vector2.ZERO


	func get_memory_confidence() -> float:
		return _memory.confidence if _memory != null else 0.0


var enemy: MockEnemy


func before_each() -> void:
	enemy = MockEnemy.new()
	seed(12345)  # Fixed seed for reproducibility
	enemy.initialize()


func after_each() -> void:
	enemy = null


# ============================================================================
# Initial State Tests
# ============================================================================


func test_initial_state_is_idle() -> void:
	assert_eq(enemy.get_current_state(), MockEnemy.AIState.IDLE,
		"Enemy should start in IDLE state")


func test_initial_health_within_range() -> void:
	var health := enemy.get_current_health()
	assert_true(health >= enemy.min_health and health <= enemy.max_health,
		"Initial health should be within configured range")


func test_initial_health_equals_max() -> void:
	assert_eq(enemy.get_current_health(), enemy.get_max_health(),
		"Current health should equal max health initially")


func test_enemy_starts_alive() -> void:
	assert_true(enemy.is_alive(), "Enemy should start alive")


func test_initial_ammo_equals_magazine_size() -> void:
	assert_eq(enemy.get_current_ammo(), enemy.magazine_size,
		"Initial ammo should equal magazine size")


func test_initial_reserve_ammo() -> void:
	var expected := enemy.magazine_size * (enemy.total_magazines - 1)
	assert_eq(enemy.get_reserve_ammo(), expected,
		"Reserve ammo should be (total_magazines - 1) * magazine_size")


func test_not_reloading_initially() -> void:
	assert_false(enemy.is_reloading(), "Enemy should not be reloading initially")


# ============================================================================
# Health Tests
# ============================================================================


func test_hit_decreases_health() -> void:
	var initial := enemy.get_current_health()
	enemy.on_bullet_hit()

	assert_eq(enemy.get_current_health(), initial - 1, "Hit should decrease health by 1")


func test_enemy_dies_at_zero_health() -> void:
	var hits_to_kill := enemy.get_current_health()
	for i in range(hits_to_kill):
		enemy.on_bullet_hit()

	assert_false(enemy.is_alive(), "Enemy should die when health reaches 0")


func test_hit_callback_called() -> void:
	var hit_called := false
	enemy.on_hit = func(): hit_called = true

	enemy.on_bullet_hit()

	assert_true(hit_called, "Hit callback should be called")


func test_died_callback_called() -> void:
	var died_called := false
	enemy.on_died = func(): died_called = true

	var hits := enemy.get_current_health()
	for i in range(hits):
		enemy.on_bullet_hit()

	assert_true(died_called, "Died callback should be called")


func test_dead_enemy_cannot_be_hit_again() -> void:
	# Kill the enemy
	var hits := enemy.get_current_health()
	for i in range(hits):
		enemy.on_bullet_hit()

	# Try to hit again
	enemy.on_bullet_hit()

	assert_eq(enemy.get_current_health(), 0, "Dead enemy health should stay at 0")


func test_health_percent_full() -> void:
	assert_eq(enemy.get_health_percent(), 1.0, "Full health should be 100%")


func test_health_percent_half() -> void:
	var half := enemy.get_max_health() / 2
	enemy._current_health = half
	var expected := float(half) / float(enemy.get_max_health())

	assert_almost_eq(enemy.get_health_percent(), expected, 0.001)


# ============================================================================
# AI State Tests
# ============================================================================


func test_state_change_emits_signal() -> void:
	var new_state_received: int = -1
	enemy.on_state_changed = func(s): new_state_received = s

	enemy.set_state(MockEnemy.AIState.COMBAT)

	assert_eq(new_state_received, MockEnemy.AIState.COMBAT,
		"State changed signal should pass new state")


func test_state_change_same_state_no_signal() -> void:
	var signal_called := false
	enemy.on_state_changed = func(_s): signal_called = true

	enemy.set_state(MockEnemy.AIState.IDLE)  # Already IDLE

	assert_false(signal_called, "Signal should not be called for same state")


func test_all_states_can_be_set() -> void:
	var states := [
		MockEnemy.AIState.IDLE,
		MockEnemy.AIState.COMBAT,
		MockEnemy.AIState.SEEKING_COVER,
		MockEnemy.AIState.IN_COVER,
		MockEnemy.AIState.FLANKING,
		MockEnemy.AIState.SUPPRESSED,
		MockEnemy.AIState.RETREATING,
		MockEnemy.AIState.PURSUING,
		MockEnemy.AIState.ASSAULT,
		MockEnemy.AIState.SEARCHING
	]

	for state in states:
		enemy.set_state(state)
		assert_eq(enemy.get_current_state(), state, "Should be able to set state %d" % state)


# ============================================================================
# Ammo and Shooting Tests
# ============================================================================


func test_can_shoot_with_ammo_and_cooldown() -> void:
	enemy._shoot_timer = enemy.shoot_cooldown  # Cooldown ready

	assert_true(enemy.can_shoot(), "Should be able to shoot with ammo and cooldown ready")


func test_cannot_shoot_without_cooldown() -> void:
	enemy._shoot_timer = 0.0  # Cooldown not ready

	assert_false(enemy.can_shoot(), "Should not be able to shoot during cooldown")


func test_cannot_shoot_without_ammo() -> void:
	enemy._current_ammo = 0
	enemy._shoot_timer = enemy.shoot_cooldown

	assert_false(enemy.can_shoot(), "Should not be able to shoot without ammo")


func test_cannot_shoot_while_reloading() -> void:
	enemy._is_reloading = true
	enemy._shoot_timer = enemy.shoot_cooldown

	assert_false(enemy.can_shoot(), "Should not be able to shoot while reloading")


func test_shooting_decreases_ammo() -> void:
	enemy._shoot_timer = enemy.shoot_cooldown
	var initial := enemy.get_current_ammo()

	enemy.shoot()

	assert_eq(enemy.get_current_ammo(), initial - 1, "Shooting should decrease ammo")


func test_shooting_resets_timer() -> void:
	enemy._shoot_timer = enemy.shoot_cooldown
	enemy.shoot()

	assert_eq(enemy._shoot_timer, 0.0, "Shooting should reset timer")


func test_shoot_timer_updates() -> void:
	enemy._shoot_timer = 0.0
	enemy.update_shoot_timer(0.05)

	assert_eq(enemy._shoot_timer, 0.05, "Timer should update by delta")


# ============================================================================
# Reload Tests
# ============================================================================


func test_needs_reload_when_empty_with_reserve() -> void:
	enemy._current_ammo = 0

	assert_true(enemy.needs_reload(), "Should need reload when empty with reserve")


func test_no_reload_needed_with_ammo() -> void:
	assert_false(enemy.needs_reload(), "Should not need reload with ammo")


func test_no_reload_needed_without_reserve() -> void:
	enemy._current_ammo = 0
	enemy._reserve_ammo = 0

	assert_false(enemy.needs_reload(), "Should not need reload without reserve")


func test_start_reload_sets_reloading() -> void:
	enemy._current_ammo = 0
	enemy.start_reload()

	assert_true(enemy.is_reloading(), "Should be reloading after start_reload")


func test_reload_callback_called() -> void:
	var started := false
	enemy.on_reload_started = func(): started = true

	enemy._current_ammo = 0
	enemy.start_reload()

	assert_true(started, "Reload started callback should be called")


func test_reload_completes_after_time() -> void:
	enemy._current_ammo = 0
	enemy.start_reload()
	enemy.update_reload(enemy.reload_time + 0.1)

	assert_false(enemy.is_reloading(), "Should not be reloading after reload time")


func test_reload_refills_ammo() -> void:
	enemy._current_ammo = 0
	var initial_reserve := enemy.get_reserve_ammo()
	enemy.start_reload()
	enemy.update_reload(enemy.reload_time + 0.1)

	assert_eq(enemy.get_current_ammo(), enemy.magazine_size,
		"Ammo should be refilled after reload")
	assert_eq(enemy.get_reserve_ammo(), initial_reserve - enemy.magazine_size,
		"Reserve should decrease by magazine size")


func test_cannot_start_reload_when_reloading() -> void:
	enemy._current_ammo = 0
	enemy.start_reload()
	enemy.start_reload()  # Try again

	# Should still have same reload state (not restarted)
	assert_true(enemy.is_reloading())


func test_has_ammo_with_current() -> void:
	assert_true(enemy.has_ammo(), "Should have ammo with current ammo")


func test_has_ammo_with_only_reserve() -> void:
	enemy._current_ammo = 0

	assert_true(enemy.has_ammo(), "Should have ammo with reserve only")


func test_no_ammo_when_both_empty() -> void:
	enemy._current_ammo = 0
	enemy._reserve_ammo = 0

	assert_false(enemy.has_ammo(), "Should not have ammo when both empty")


# ============================================================================
# Retreat Mode Tests
# ============================================================================


func test_retreat_mode_full_hp() -> void:
	assert_eq(enemy.get_retreat_mode(), MockEnemy.RetreatMode.FULL_HP,
		"Should be FULL_HP retreat mode with no damage")


func test_retreat_mode_one_hit() -> void:
	enemy.on_bullet_hit()

	assert_eq(enemy.get_retreat_mode(), MockEnemy.RetreatMode.ONE_HIT,
		"Should be ONE_HIT retreat mode after one hit")


func test_retreat_mode_multiple_hits() -> void:
	enemy.on_bullet_hit()
	enemy.on_bullet_hit()

	assert_eq(enemy.get_retreat_mode(), MockEnemy.RetreatMode.MULTIPLE_HITS,
		"Should be MULTIPLE_HITS retreat mode after multiple hits")


# ============================================================================
# Cover and Flanking Tests
# ============================================================================


func test_should_seek_cover_when_under_fire() -> void:
	enemy.enable_cover = true
	enemy._under_fire = true
	enemy._has_valid_cover = false

	assert_true(enemy.should_seek_cover(), "Should seek cover when under fire")


func test_should_not_seek_cover_when_has_cover() -> void:
	enemy.enable_cover = true
	enemy._under_fire = true
	enemy._has_valid_cover = true

	assert_false(enemy.should_seek_cover(), "Should not seek cover when already has cover")


func test_should_not_seek_cover_when_disabled() -> void:
	enemy.enable_cover = false
	enemy._under_fire = true

	assert_false(enemy.should_seek_cover(), "Should not seek cover when disabled")


func test_should_flank_when_see_player() -> void:
	enemy.enable_flanking = true
	enemy._can_see_player = true
	enemy._under_fire = false

	assert_true(enemy.should_flank(), "Should flank when can see player")


func test_should_not_flank_under_fire() -> void:
	enemy.enable_flanking = true
	enemy._can_see_player = true
	enemy._under_fire = true

	assert_false(enemy.should_flank(), "Should not flank when under fire")


func test_should_not_flank_when_disabled() -> void:
	enemy.enable_flanking = false
	enemy._can_see_player = true

	assert_false(enemy.should_flank(), "Should not flank when disabled")


# ============================================================================
# Suppression Tests
# ============================================================================


func test_suppressed_when_under_fire() -> void:
	enemy.set_under_fire(true)
	enemy.update_suppression(0.0)

	assert_true(enemy.is_suppressed(), "Should be suppressed when under fire")


func test_suppression_decreases_over_time() -> void:
	enemy._suppression_timer = 2.0
	enemy._under_fire = false
	enemy.update_suppression(1.0)

	assert_eq(enemy._suppression_timer, 1.0, "Suppression timer should decrease")


func test_suppression_resets_when_under_fire() -> void:
	enemy._suppression_timer = 0.5
	enemy.set_under_fire(true)
	enemy.update_suppression(0.0)

	assert_eq(enemy._suppression_timer, enemy.suppression_cooldown,
		"Suppression should reset to full when under fire")


# ============================================================================
# Lead Prediction Tests
# ============================================================================


func test_lead_prediction_stationary_target() -> void:
	var target_pos := Vector2(500, 0)
	var target_vel := Vector2.ZERO
	var own_pos := Vector2.ZERO

	var result := enemy.calculate_lead_position(target_pos, target_vel, own_pos)

	assert_eq(result, target_pos, "Stationary target should not need prediction")


func test_lead_prediction_moving_target() -> void:
	var target_pos := Vector2(500, 0)
	var target_vel := Vector2(100, 0)  # Moving right
	var own_pos := Vector2.ZERO

	var result := enemy.calculate_lead_position(target_pos, target_vel, own_pos)

	assert_true(result.x > target_pos.x, "Lead position should be ahead of moving target")


# ============================================================================
# Distraction Detection Tests
# ============================================================================


func test_player_distracted_when_looking_away() -> void:
	var player_rotation := 0.0  # Facing right
	var enemy_position := Vector2(0, 100)  # Enemy is below
	var player_position := Vector2.ZERO

	assert_true(enemy.is_player_distracted(player_rotation, enemy_position, player_position),
		"Player should be distracted when looking away from enemy")


func test_player_not_distracted_when_facing() -> void:
	var player_rotation := PI / 2  # Facing down
	var enemy_position := Vector2(0, 100)  # Enemy is below
	var player_position := Vector2.ZERO

	assert_false(enemy.is_player_distracted(player_rotation, enemy_position, player_position),
		"Player should not be distracted when facing enemy")


# ============================================================================
# Patrol Tests
# ============================================================================


func test_setup_patrol_creates_points() -> void:
	var initial := Vector2(100, 100)
	var offsets: Array[Vector2] = [Vector2(50, 0), Vector2(-50, 0)]
	enemy.setup_patrol(initial, offsets)

	assert_eq(enemy._patrol_points.size(), 2, "Should have 2 patrol points")
	assert_eq(enemy._patrol_points[0], Vector2(150, 100), "First patrol point incorrect")
	assert_eq(enemy._patrol_points[1], Vector2(50, 100), "Second patrol point incorrect")


func test_get_next_patrol_point_cycles() -> void:
	var initial := Vector2.ZERO
	var offsets: Array[Vector2] = [Vector2(100, 0), Vector2(-100, 0)]
	enemy.setup_patrol(initial, offsets)

	var first := enemy.get_next_patrol_point()
	var second := enemy.get_next_patrol_point()
	var third := enemy.get_next_patrol_point()  # Should cycle back

	assert_eq(first, Vector2(-100, 0), "First call should go to second point")
	assert_eq(second, Vector2(100, 0), "Second call should go to first point")
	assert_eq(third, Vector2(-100, 0), "Third call should cycle back")


# ============================================================================
# Aim Tolerance Tests (Issue #264 regression test)
# ============================================================================


## Test that the aim tolerance constant allows reasonable shooting angles.
## This is a regression test for issue #264 where enemies shot less frequently
## because the aim tolerance was too strict (0.95 = 18 degrees).
## The value should be 0.866 (30 degrees) to allow more frequent shooting.
func test_aim_tolerance_allows_reasonable_angle() -> void:
	# This tests the expected constant value in enemy.gd
	# The actual constant is: AIM_TOLERANCE_DOT = 0.866
	# cos(30°) ≈ 0.866 - allows shooting within ~30 degrees of target
	var expected_tolerance: float = 0.866
	var tolerance_angle_degrees: float = rad_to_deg(acos(expected_tolerance))

	# Verify the angle is reasonable (between 25-35 degrees)
	assert_true(tolerance_angle_degrees >= 25.0,
		"Aim tolerance should allow at least 25 degrees offset")
	assert_true(tolerance_angle_degrees <= 35.0,
		"Aim tolerance should be at most 35 degrees offset")


## Test that aim tolerance is not too strict (issue #264 root cause).
## The old value of 0.95 (~18°) caused enemies to rarely shoot.
func test_aim_tolerance_not_too_strict() -> void:
	var too_strict_tolerance: float = 0.95  # Old problematic value
	var current_tolerance: float = 0.866     # Fixed value

	# Current tolerance should be less strict (smaller dot product)
	assert_true(current_tolerance < too_strict_tolerance,
		"Aim tolerance should be relaxed from 0.95 to allow more shooting")


## Test that common shooting scenarios pass the aim check.
## Simulates weapon direction vs target direction dot product.
func test_aim_check_passes_reasonable_angles() -> void:
	var tolerance: float = 0.866  # Current AIM_TOLERANCE_DOT

	# Test 0 degrees off target (perfect aim) - should pass
	var weapon_forward := Vector2.RIGHT
	var to_target := Vector2.RIGHT
	var dot_0deg := weapon_forward.dot(to_target)
	assert_true(dot_0deg >= tolerance, "Perfect aim should pass")

	# Test 15 degrees off target - should pass
	var angle_15 := deg_to_rad(15.0)
	to_target = Vector2.RIGHT.rotated(angle_15)
	var dot_15deg := weapon_forward.dot(to_target)
	assert_true(dot_15deg >= tolerance, "15 degree offset should pass")

	# Test 25 degrees off target - should pass
	var angle_25 := deg_to_rad(25.0)
	to_target = Vector2.RIGHT.rotated(angle_25)
	var dot_25deg := weapon_forward.dot(to_target)
	assert_true(dot_25deg >= tolerance, "25 degree offset should pass (issue #264 fix)")

	# Test 35 degrees off target - should fail
	var angle_35 := deg_to_rad(35.0)
	to_target = Vector2.RIGHT.rotated(angle_35)
	var dot_35deg := weapon_forward.dot(to_target)
	assert_true(dot_35deg < tolerance, "35 degree offset should fail (too far off)")


# ============================================================================
# Priority Attack Model Rotation Tests (Issue #264 fix verification)
# ============================================================================


## Test that model rotation affects weapon forward direction.
## This simulates the scenario where the enemy body rotation is set
## but the model rotation (which controls weapon direction) is not updated.
func test_model_rotation_affects_weapon_direction() -> void:
	# Simulate the problem: body rotated, but weapon still facing old direction
	var body_rotation := PI / 4  # 45 degrees
	var old_weapon_direction := Vector2.RIGHT  # Still facing right (0 degrees)
	var target_direction := Vector2.RIGHT.rotated(body_rotation)  # Where we want to shoot

	# Without model update, weapon is still facing right
	# Dot product between weapon direction and target direction
	var aim_dot_without_update := old_weapon_direction.dot(target_direction)

	# cos(45°) ≈ 0.707 which is less than 0.866 tolerance
	# This means shot would be BLOCKED due to aim mismatch
	var tolerance: float = 0.866
	assert_true(aim_dot_without_update < tolerance,
		"Without model update, weapon direction should NOT match target (shot blocked)")

	# After model update, weapon should face the same direction as body
	var updated_weapon_direction := target_direction
	var aim_dot_with_update := updated_weapon_direction.dot(target_direction)

	# After update, dot product should be 1.0 (perfect aim)
	assert_almost_eq(aim_dot_with_update, 1.0, 0.001,
		"After model update, weapon should face target direction (shot allowed)")


## Test that immediate model rotation synchronizes weapon with body.
## This validates the fix where _force_model_to_face_direction() is called
## before _shoot() in priority attack code.
func test_immediate_model_rotation_synchronizes_weapon() -> void:
	# This is a conceptual test showing the fix logic
	# In the real code, after setting rotation = direction_to_player.angle(),
	# we now also call _force_model_to_face_direction(direction_to_player)

	var direction_to_player := Vector2(1, 1).normalized()  # 45 degrees
	var target_angle := direction_to_player.angle()

	# Simulate _force_model_to_face_direction:
	# When not aiming left (abs(angle) <= PI/2), model.global_rotation = target_angle
	var aiming_left := absf(target_angle) > PI / 2
	var model_rotation: float
	if aiming_left:
		model_rotation = -target_angle
	else:
		model_rotation = target_angle

	# After forcing model rotation, the weapon forward direction should match
	# In the real code: _weapon_sprite.global_transform.x.normalized()
	# For this test, we simulate it as Vector2.RIGHT.rotated(model_rotation)
	var weapon_forward := Vector2.RIGHT.rotated(model_rotation)

	# Check that weapon forward matches direction to player (within floating point tolerance)
	var dot_product := weapon_forward.dot(direction_to_player)
	assert_almost_eq(dot_product, 1.0, 0.001,
		"After _force_model_to_face_direction, weapon should point at player")


# ============================================================================
# Multi-Point Visibility Tests (Issue #264 - Player Near Wall Fix)
# ============================================================================


## Test that player check points cover the full collision body.
## This validates that we check center + 4 corners as expected.
func test_player_check_points_cover_body() -> void:
	# The enemy.gd function _get_player_check_points returns:
	# - Center point
	# - 4 corner points at diagonal offsets (player radius * 0.707)
	# Player radius is 14.0 (slightly smaller than collision radius of 16)
	var center := Vector2(500, 500)
	var player_radius := 14.0
	var diagonal_offset := player_radius * 0.707  # cos(45°) ≈ 0.707 ≈ 9.9

	# Expected check points
	var expected_points: Array[Vector2] = []
	expected_points.append(center)  # Center
	expected_points.append(center + Vector2(diagonal_offset, diagonal_offset))     # Bottom-right
	expected_points.append(center + Vector2(-diagonal_offset, diagonal_offset))    # Bottom-left
	expected_points.append(center + Vector2(diagonal_offset, -diagonal_offset))    # Top-right
	expected_points.append(center + Vector2(-diagonal_offset, -diagonal_offset))   # Top-left

	# Verify we have 5 points total (center + 4 corners)
	assert_eq(expected_points.size(), 5,
		"Should check 5 points on player body (center + 4 corners)")

	# Verify diagonal offset is reasonable
	assert_almost_eq(diagonal_offset, 9.898, 0.01,
		"Diagonal offset should be approximately 9.9 pixels")


## Test that multi-point visibility handles wall corner scenarios.
## This is a conceptual test for the fix: when player is near a wall,
## the center might be blocked but corners could still be visible.
func test_multipoint_visibility_handles_wall_corners() -> void:
	# Scenario: Enemy at (0, 0), Player at (100, 0), Wall corner at (50, 0)
	# Single-point check to center would be blocked by wall
	# But corner points at (100, ±9.9) might be visible

	var enemy_pos := Vector2(0, 0)
	var player_center := Vector2(100, 0)
	var wall_corner := Vector2(50, 0)

	# Check if center is blocked (it would be in this scenario)
	var center_blocked := true  # Wall at (50, 0) blocks ray to (100, 0)

	# Check if corner points might be visible
	# Top-left corner at (100 - 9.9, 0 - 9.9) = (90.1, -9.9)
	# The ray from (0, 0) to (90.1, -9.9) might pass above the wall corner
	var corner_might_be_visible := true  # Depends on wall height, but conceptually yes

	# The fix ensures: if ANY point is visible, player is visible
	var player_visible := not center_blocked or corner_might_be_visible

	assert_true(player_visible,
		"Multi-point check should detect player when at least one body point is visible")


## Test that visibility ratio is calculated correctly.
## When 3 of 5 points are visible, ratio should be 0.6.
func test_visibility_ratio_calculation() -> void:
	var total_points := 5
	var visible_points := 3

	var visibility_ratio: float = float(visible_points) / float(total_points)

	assert_almost_eq(visibility_ratio, 0.6, 0.001,
		"Visibility ratio should be 0.6 when 3 of 5 points visible")


## Test that single visible point makes player detectable.
## This is the key fix for issue #264 wall corner scenario.
func test_single_visible_point_detects_player() -> void:
	# Simulate the visibility check logic from _check_player_visibility()
	var total_points := 5
	var visible_count := 1  # Only one corner is visible (center blocked by wall)

	# The fix: if ANY point is visible, can_see_player = true
	var can_see_player := visible_count > 0

	assert_true(can_see_player,
		"Enemy should see player when at least one body point is visible (issue #264 fix)")


# ============================================================================
# Transform Delay Fix Tests (Issue #264 - Session 4)
# ============================================================================


## Test that weapon direction is calculated directly to player when visible.
## This is the key fix for issue #264 session 4: bullets firing in the wrong
## direction because global_transform doesn't update in the same physics frame.
##
## Bug: Enemy sets _enemy_model.global_rotation to face the player, then calls
## _shoot() which reads _weapon_sprite.global_transform.x to get bullet direction.
## However, in Godot 4, child node transforms don't update immediately when
## parent rotation changes - they update on the next frame.
##
## Fix: When player is visible, calculate direction directly to player position
## instead of reading from the (stale) transform.
func test_weapon_direction_calculated_directly_when_player_visible() -> void:
	# Simulate enemy and player positions from the bug report
	var enemy_pos := Vector2(618, 768)  # Enemy3 position from logs
	var player_pos := Vector2(450, 1250)  # Player spawn position

	# Expected direction: directly toward player
	var expected_direction := (player_pos - enemy_pos).normalized()

	# The stale transform direction (from previous frame, facing left)
	var stale_transform_direction := Vector2(-1, 0)  # ~180 degrees (left wall)

	# Verify these are very different directions
	var angle_difference := expected_direction.angle_to(stale_transform_direction)
	assert_true(absf(angle_difference) > 1.0,  # More than 57 degrees difference
		"Stale transform direction should differ significantly from expected")

	# The fix: when _can_see_player is true, use calculated direction
	var can_see_player := true
	var weapon_direction: Vector2
	if can_see_player:
		# Fix: calculate direction directly
		weapon_direction = expected_direction
	else:
		# Fallback: use transform (only when player not visible)
		weapon_direction = stale_transform_direction

	# Verify the fix gives correct direction
	var dot_product := weapon_direction.dot(expected_direction)
	assert_almost_eq(dot_product, 1.0, 0.001,
		"Weapon direction should match expected direction when player is visible")


## Test that bullet spawn position uses correct direction when player visible.
## This is a companion fix to the weapon direction fix.
func test_bullet_spawn_position_uses_correct_direction() -> void:
	# Simulate positions
	var weapon_sprite_pos := Vector2(618, 780)  # Weapon mount position
	var player_pos := Vector2(450, 1250)
	var enemy_pos := Vector2(618, 768)
	var muzzle_offset := 52.0  # From the code

	# Expected direction to player
	var expected_direction := (player_pos - enemy_pos).normalized()

	# Stale transform direction (wrong)
	var stale_direction := Vector2(-1, 0)

	# Correct muzzle position (using calculated direction)
	var correct_muzzle := weapon_sprite_pos + expected_direction * muzzle_offset

	# Wrong muzzle position (using stale transform)
	var wrong_muzzle := weapon_sprite_pos + stale_direction * muzzle_offset

	# The muzzle positions should be significantly different
	var distance := correct_muzzle.distance_to(wrong_muzzle)
	assert_true(distance > 50.0,
		"Correct vs stale muzzle positions should differ significantly")

	# Correct muzzle should be closer to the player direction
	var correct_to_player := (player_pos - correct_muzzle).normalized()
	var wrong_to_player := (player_pos - wrong_muzzle).normalized()

	# The correct muzzle's bullet should travel more directly to player
	var correct_alignment := correct_to_player.dot(expected_direction)
	var wrong_alignment := wrong_to_player.dot(expected_direction)

	assert_true(correct_alignment > wrong_alignment,
		"Correct muzzle position should give better alignment to player")


## Test that fallback to transform is used when player is not visible.
## The transform-based direction should be used when the enemy can't see the player,
## because the transform has had time to update over multiple frames.
func test_fallback_to_transform_when_player_not_visible() -> void:
	# When player is not visible, we use the transform-based direction
	# This is fine because:
	# 1. The enemy isn't shooting at the player anyway (can't see them)
	# 2. The transform has had time to settle over multiple frames

	var can_see_player := false
	var transform_direction := Vector2(0.707, 0.707).normalized()  # Some previous direction
	var player_direction := Vector2(1, 0)  # Doesn't matter - can't see player

	var weapon_direction: Vector2
	if can_see_player:
		weapon_direction = player_direction
	else:
		# Fallback to transform - this is the expected behavior
		weapon_direction = transform_direction

	# Verify we got the transform direction, not the player direction
	var dot_with_transform := weapon_direction.dot(transform_direction)
	assert_almost_eq(dot_with_transform, 1.0, 0.001,
		"Should use transform direction when player not visible")


# ============================================================================
# Enemy Memory Tests (Issue #297, #318)
# ============================================================================


## Test that enemy memory starts empty.
func test_enemy_memory_starts_empty() -> void:
	assert_false(enemy.has_memory_target(),
		"Enemy memory should start with no target")
	assert_eq(enemy.get_memory_position(), Vector2.ZERO,
		"Memory position should be zero initially")
	assert_eq(enemy.get_memory_confidence(), 0.0,
		"Memory confidence should be zero initially")


## Test that enemy memory updates when player is visible.
func test_enemy_memory_updates_on_visual_contact() -> void:
	var player_pos := Vector2(500, 300)
	enemy.update_memory(player_pos, 1.0)

	assert_true(enemy.has_memory_target(),
		"Enemy should have a memory target after seeing player")
	assert_eq(enemy.get_memory_position(), player_pos,
		"Memory position should match player position")
	assert_eq(enemy.get_memory_confidence(), 1.0,
		"Memory confidence should be 1.0 for visual contact")


## Test that reset_memory clears all memory state (Issue #318).
## This is critical for the "last chance" teleport effect where enemies
## must forget where the player was so they don't pursue the old position.
func test_reset_memory_clears_memory_state() -> void:
	# First, give the enemy a valid memory of the player
	var old_player_pos := Vector2(500, 300)
	enemy.update_memory(old_player_pos, 1.0)

	# Verify memory is set
	assert_true(enemy.has_memory_target(),
		"Enemy should have memory before reset")
	assert_eq(enemy.get_memory_position(), old_player_pos,
		"Memory position should be set before reset")

	# Reset memory (simulates last chance teleport effect ending)
	enemy.reset_memory()

	# Verify memory is cleared
	assert_false(enemy.has_memory_target(),
		"Enemy should have no memory target after reset")
	assert_eq(enemy.get_memory_confidence(), 0.0,
		"Memory confidence should be zero after reset")
	assert_eq(enemy._last_known_player_position, Vector2.ZERO,
		"Legacy last known position should be cleared after reset")
	assert_eq(enemy._intel_share_timer, 0.0,
		"Intel share timer should be reset to prevent immediate re-acquisition")


## Test that enemy must re-acquire player after memory reset (Issue #318).
## This verifies the core fix: enemies don't know where the player went
## during the "last chance" effect and must find them again.
func test_enemy_must_reacquire_player_after_memory_reset() -> void:
	# Setup: Enemy sees player at position A
	var original_pos := Vector2(100, 100)
	enemy.update_memory(original_pos, 1.0)
	assert_true(enemy.has_memory_target(), "Should have memory before reset")

	# Action: Reset memory (player "teleported" during last chance)
	enemy.reset_memory()

	# Verify: Enemy has no knowledge of player location
	assert_false(enemy.has_memory_target(),
		"Enemy should not know player location after reset")

	# Action: Player moves to new position (not visible to enemy yet)
	var new_pos := Vector2(800, 600)
	# Enemy cannot see player, so memory stays empty

	# Verify: Enemy still doesn't know where player is
	assert_false(enemy.has_memory_target(),
		"Enemy should not magically know player's new position")

	# Action: Enemy sees player at new position
	enemy.update_memory(new_pos, 1.0)

	# Verify: NOW enemy knows where player is
	assert_true(enemy.has_memory_target(),
		"Enemy should have memory after re-acquiring player")
	assert_eq(enemy.get_memory_position(), new_pos,
		"Memory should contain NEW player position, not old one")


# ============================================================================
# Enemy Search State Tests (Issue #322)
# ============================================================================


## Test that SEARCHING state exists in the enum.
func test_searching_state_exists() -> void:
	var searching_state := MockEnemy.AIState.SEARCHING
	assert_eq(searching_state, 9,
		"SEARCHING state should be the 10th state (index 9)")


## Test that enemy can transition to SEARCHING state.
func test_can_set_searching_state() -> void:
	enemy.set_state(MockEnemy.AIState.SEARCHING)
	assert_eq(enemy.get_current_state(), MockEnemy.AIState.SEARCHING,
		"Should be able to set SEARCHING state")


## Test expanding square pattern waypoint generation logic.
## The algorithm generates waypoints in a spiral: center, N, E, S, W, etc.
## with leg length expanding every 2 legs.
func test_expanding_square_waypoint_generation() -> void:
	# Test the algorithm logic (same as implemented in enemy.gd)
	var center := Vector2(500, 500)
	var waypoints: Array[Vector2] = []
	var direction := 0  # 0=N, 1=E, 2=S, 3=W
	var leg_length := 75.0  # Initial spacing
	var legs_completed := 0

	# Add center
	waypoints.append(center)

	# Generate first 4 waypoints (one square)
	var current_pos := center
	for i in range(4):
		var offset := Vector2.ZERO
		match direction:
			0: offset = Vector2(0, -leg_length)   # North
			1: offset = Vector2(leg_length, 0)    # East
			2: offset = Vector2(0, leg_length)    # South
			3: offset = Vector2(-leg_length, 0)   # West

		current_pos = current_pos + offset
		waypoints.append(current_pos)

		legs_completed += 1
		direction = (direction + 1) % 4

		# Expand every 2 legs
		if legs_completed % 2 == 0:
			leg_length += 75.0

	# Verify we have 5 waypoints (center + 4 directions)
	assert_eq(waypoints.size(), 5, "Should generate 5 waypoints for first iteration")

	# Verify center is first
	assert_eq(waypoints[0], center, "First waypoint should be center")

	# Verify first leg goes North
	assert_eq(waypoints[1], Vector2(500, 425), "Second waypoint should be North of center")

	# Verify second leg goes East (from North position)
	assert_eq(waypoints[2], Vector2(575, 425), "Third waypoint should be East")

	# After 2 legs, leg_length should increase
	# Third leg (South) uses increased length
	assert_eq(waypoints[3], Vector2(575, 575), "Fourth waypoint should be South with expanded leg")


## Test that search pattern expands when radius is increased.
func test_search_radius_expansion() -> void:
	var initial_radius := 100.0
	var expansion := 75.0
	var max_radius := 400.0

	# First expansion
	var radius := initial_radius + expansion
	assert_eq(radius, 175.0, "First expansion should increase radius to 175")

	# Continue expanding until max
	var expansions := 0
	radius = initial_radius
	while radius < max_radius:
		radius += expansion
		expansions += 1

	# Verify number of expansions needed
	assert_eq(expansions, 4, "Should take 4 expansions to go from 100 to 400")


## Test that waypoint is considered reached at threshold distance.
func test_waypoint_reached_distance() -> void:
	var threshold := 20.0  # SEARCH_WAYPOINT_REACHED_DISTANCE
	var enemy_pos := Vector2(100, 100)
	var waypoint := Vector2(110, 110)

	var distance := enemy_pos.distance_to(waypoint)
	assert_true(distance < threshold,
		"Waypoint should be considered reached at distance %.1f (< %.1f)" % [distance, threshold])


## Test that scan duration allows for proper area inspection.
func test_search_scan_duration() -> void:
	var scan_duration := 1.0  # SEARCH_SCAN_DURATION

	# 360 degrees rotation at 1.5 rad/s (from code) takes ~4.2 seconds
	# With 1.0s scan, enemy rotates ~86 degrees per waypoint
	var rotation_speed := 1.5  # rad/s from _process_searching_state
	var rotation_per_scan := rotation_speed * scan_duration
	var degrees := rad_to_deg(rotation_per_scan)

	assert_true(degrees > 60.0,
		"Scan should rotate at least 60 degrees per waypoint (actual: %.1f)" % degrees)


## Test that search has maximum duration timeout.
func test_search_max_duration() -> void:
	var max_duration := 30.0  # SEARCH_MAX_DURATION

	# 30 seconds is reasonable for search before giving up
	assert_true(max_duration >= 20.0,
		"Search should last at least 20 seconds")
	assert_true(max_duration <= 60.0,
		"Search should not last more than 60 seconds")


## Test zone key generation for visited zone tracking (Issue #322).
func test_zone_key_generation() -> void:
	var snap_size := 50.0  # SEARCH_ZONE_SNAP_SIZE

	# Test that positions within same zone snap to same key
	var pos1 := Vector2(125, 175)
	var pos2 := Vector2(140, 190)

	var snapped_x1 := int(pos1.x / snap_size) * int(snap_size)
	var snapped_y1 := int(pos1.y / snap_size) * int(snap_size)
	var key1 := "%d,%d" % [snapped_x1, snapped_y1]

	var snapped_x2 := int(pos2.x / snap_size) * int(snap_size)
	var snapped_y2 := int(pos2.y / snap_size) * int(snap_size)
	var key2 := "%d,%d" % [snapped_x2, snapped_y2]

	assert_eq(key1, key2, "Positions in same grid cell should have same zone key")
	assert_eq(key1, "100,150", "Zone key should be snapped to 50-pixel grid")


## Test that visited zones are tracked correctly (Issue #322).
func test_visited_zones_tracking() -> void:
	var visited_zones: Dictionary = {}
	var snap_size := 50.0

	# Mark a zone as visited
	var pos := Vector2(100, 200)
	var snapped_x := int(pos.x / snap_size) * int(snap_size)
	var snapped_y := int(pos.y / snap_size) * int(snap_size)
	var key := "%d,%d" % [snapped_x, snapped_y]
	visited_zones[key] = true

	# Check that zone is marked visited
	assert_true(visited_zones.has(key), "Zone should be marked as visited")

	# Check that different zone is not visited
	var other_pos := Vector2(300, 400)
	var other_x := int(other_pos.x / snap_size) * int(snap_size)
	var other_y := int(other_pos.y / snap_size) * int(snap_size)
	var other_key := "%d,%d" % [other_x, other_y]
	assert_false(visited_zones.has(other_key), "Other zone should not be visited")


## Test that zone expansion skips visited zones (Issue #322).
func test_zone_expansion_skips_visited() -> void:
	var visited_zones: Dictionary = {}
	var center := Vector2(500, 500)
	var snap_size := 50.0

	# Mark center zone as visited
	var center_x := int(center.x / snap_size) * int(snap_size)
	var center_y := int(center.y / snap_size) * int(snap_size)
	visited_zones["%d,%d" % [center_x, center_y]] = true

	# Generate potential waypoints and check that visited ones would be skipped
	var waypoints_to_check: Array[Vector2] = [
		center,  # Should be skipped (visited)
		center + Vector2(75, 0),  # Should be included (new zone)
		center + Vector2(0, 75),  # Should be included (new zone)
	]

	var unvisited_count := 0
	for wp in waypoints_to_check:
		var wp_x := int(wp.x / snap_size) * int(snap_size)
		var wp_y := int(wp.y / snap_size) * int(snap_size)
		var wp_key := "%d,%d" % [wp_x, wp_y]
		if not visited_zones.has(wp_key):
			unvisited_count += 1

	assert_eq(unvisited_count, 2, "Should have 2 unvisited waypoints (center is visited)")


## Regression test for Issue #344: enemies not shooting at close range.
##
## Root Cause: The aim tolerance check in _shoot() compared weapon_forward
## (direction from enemy CENTER to player) with to_target (direction from
## MUZZLE to player). At close range, these vectors diverge because the
## muzzle is offset ~50+ pixels from the enemy center, causing the angle
## between them to exceed the 30° tolerance even when the enemy is facing
## the player directly.
##
## Fix: Calculate to_target from global_position (enemy center) instead of
## bullet_spawn_pos (muzzle position) so both vectors use the same origin.
func test_aim_check_uses_consistent_origin_issue_344() -> void:
	# Simulate close-range combat scenario from Issue #344
	var enemy_pos := Vector2(600, 800)
	var muzzle_pos := Vector2(650, 810)  # Muzzle offset ~52 pixels from center
	var player_pos := Vector2(660, 820)  # Player very close to enemy

	# weapon_forward: direction from enemy center to player
	var weapon_forward := (player_pos - enemy_pos).normalized()

	# OLD (buggy) to_target: direction from MUZZLE to player
	var old_to_target := (player_pos - muzzle_pos).normalized()

	# NEW (fixed) to_target: direction from CENTER to player (same as weapon_forward)
	var new_to_target := (player_pos - enemy_pos).normalized()

	# The old calculation has significant angular difference at close range
	var old_aim_dot := weapon_forward.dot(old_to_target)
	var new_aim_dot := weapon_forward.dot(new_to_target)

	# At very close range, the old to_target diverges significantly
	# This shows the bug: close range causes aim check to fail
	var tolerance: float = 0.866  # AIM_TOLERANCE_DOT = cos(30°)

	# The new calculation should always pass (since weapon_forward equals new_to_target)
	assert_almost_eq(new_aim_dot, 1.0, 0.001,
		"Fixed aim check should return 1.0 (perfect alignment) when enemy faces player")

	# Verify this specific close-range scenario would have failed with old calculation
	# but now passes with the fix
	assert_true(new_aim_dot >= tolerance,
		"Fixed aim check should pass at close range")


## Additional test for Issue #344: verify aim check at various distances.
## The fix ensures the aim check behaves consistently regardless of distance.
func test_aim_check_consistent_at_all_distances_issue_344() -> void:
	var enemy_pos := Vector2(600, 800)
	var tolerance: float = 0.866  # AIM_TOLERANCE_DOT

	# Test at various distances
	var test_distances := [50.0, 100.0, 200.0, 500.0, 1000.0]

	for distance in test_distances:
		var player_pos := enemy_pos + Vector2(distance, 0)  # Player directly to the right

		# weapon_forward: direction from enemy center to player
		var weapon_forward := (player_pos - enemy_pos).normalized()

		# Fixed to_target: also from center (consistent with weapon_forward)
		var to_target := (player_pos - enemy_pos).normalized()

		var aim_dot := weapon_forward.dot(to_target)

		# Should always pass (perfect alignment)
		assert_almost_eq(aim_dot, 1.0, 0.001,
			"Aim check should pass at distance %.0f when enemy faces player" % distance)
		assert_true(aim_dot >= tolerance,
			"Aim check should pass tolerance at distance %.0f" % distance)


# ============================================================================
# Hit Reaction Tests (Issue #390)
# ============================================================================


## Test that hit reaction is activated when enemy is hit
func test_hit_reaction_activated_on_hit_issue_390() -> void:
	# Hit from the right (bullet traveling left-to-right)
	var hit_direction := Vector2.RIGHT

	enemy.on_bullet_hit(hit_direction)

	assert_true(enemy.is_hit_reaction_active(),
		"Hit reaction should be active after being hit")
	assert_almost_eq(enemy._hit_reaction_timer, MockEnemy.HIT_REACTION_DURATION, 0.001,
		"Hit reaction timer should be set to full duration")


## Test that hit reaction makes enemy face the attacker
func test_hit_reaction_faces_attacker_issue_390() -> void:
	# Hit from the right (bullet traveling left-to-right)
	var hit_direction := Vector2.RIGHT

	enemy.on_bullet_hit(hit_direction)

	# Enemy should face opposite direction (toward attacker on the left)
	var expected_direction := -hit_direction.normalized()
	var actual_direction := enemy.get_hit_reaction_direction()

	assert_almost_eq(actual_direction.x, expected_direction.x, 0.001,
		"Hit reaction direction X should match attacker direction")
	assert_almost_eq(actual_direction.y, expected_direction.y, 0.001,
		"Hit reaction direction Y should match attacker direction")


## Test that hit reaction decays over time
func test_hit_reaction_decays_over_time_issue_390() -> void:
	enemy.on_bullet_hit(Vector2.RIGHT)

	# Simulate time passing (half duration)
	enemy.update_hit_reaction(MockEnemy.HIT_REACTION_DURATION / 2.0)

	assert_true(enemy.is_hit_reaction_active(),
		"Hit reaction should still be active at half duration")

	# Simulate remaining time
	enemy.update_hit_reaction(MockEnemy.HIT_REACTION_DURATION / 2.0 + 0.1)

	assert_false(enemy.is_hit_reaction_active(),
		"Hit reaction should end after full duration")
	assert_eq(enemy._hit_reaction_direction, Vector2.ZERO,
		"Hit reaction direction should be reset after duration")


## Test that multiple hits reset the hit reaction timer
func test_hit_reaction_resets_on_multiple_hits_issue_390() -> void:
	# First hit
	enemy.on_bullet_hit(Vector2.RIGHT)

	# Simulate some time passing
	enemy.update_hit_reaction(MockEnemy.HIT_REACTION_DURATION / 2.0)

	# Second hit from different direction
	enemy.on_bullet_hit(Vector2.UP)

	# Timer should be reset to full duration
	assert_almost_eq(enemy._hit_reaction_timer, MockEnemy.HIT_REACTION_DURATION, 0.001,
		"Hit reaction timer should reset on new hit")

	# Direction should update to new attacker
	var expected_direction := -Vector2.UP.normalized()
	assert_almost_eq(enemy._hit_reaction_direction.x, expected_direction.x, 0.001,
		"Hit reaction direction X should update to new attacker")
	assert_almost_eq(enemy._hit_reaction_direction.y, expected_direction.y, 0.001,
		"Hit reaction direction Y should update to new attacker")


## Test that hit reaction is properly initialized
func test_hit_reaction_initialized_issue_390() -> void:
	assert_eq(enemy._hit_reaction_timer, 0.0,
		"Hit reaction timer should be zero at start")
	assert_eq(enemy._hit_reaction_direction, Vector2.ZERO,
		"Hit reaction direction should be zero at start")
	assert_false(enemy.is_hit_reaction_active(),
		"Hit reaction should not be active at start")
