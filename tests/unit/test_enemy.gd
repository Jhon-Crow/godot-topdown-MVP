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
		ASSAULT
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


	func on_bullet_hit() -> void:
		if not _is_alive:
			return

		_current_health -= 1
		_hits_taken += 1

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
		MockEnemy.AIState.ASSAULT
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
