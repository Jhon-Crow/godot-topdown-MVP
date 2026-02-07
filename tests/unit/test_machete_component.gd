extends GutTest
## Unit tests for MacheteComponent (Issue #579, #595).
##
## Tests machete melee attack, bullet dodging, backstab detection,
## sneaking behavior, and attack animation for machete-wielding enemies.


# ============================================================================
# Mock MacheteComponent for Logic Tests
# ============================================================================


class MockMacheteComponent:
	## Animation phases for the machete swing attack (Issue #595).
	enum AttackPhase { IDLE, WINDUP, PAUSE, STRIKE, RECOVERY }

	## Melee attack range in pixels.
	var melee_range: float = 80.0
	## Melee attack damage.
	var melee_damage: int = 2
	## Melee attack cooldown in seconds.
	var melee_cooldown: float = 1.5
	## Dodge speed in pixels per second.
	var dodge_speed: float = 400.0
	## Dodge distance in pixels.
	var dodge_distance: float = 120.0
	## Dodge cooldown in seconds.
	var dodge_cooldown: float = 1.2
	## Speed multiplier when sneaking.
	var sneak_speed_multiplier: float = 0.6
	## Timer since last melee attack.
	var _melee_timer: float = 0.0
	## Timer since last dodge.
	var _dodge_timer: float = 0.0
	## Whether currently performing a dodge.
	var _is_dodging: bool = false
	## Dodge target position.
	var _dodge_target: Vector2 = Vector2.ZERO
	## Dodge start position.
	var _dodge_start: Vector2 = Vector2.ZERO
	## Dodge progress.
	var _dodge_progress: float = 0.0
	## Parent position (simulated).
	var _parent_position: Vector2 = Vector2.ZERO
	## Current attack animation phase (Issue #595).
	var _attack_phase: int = AttackPhase.IDLE
	## Timer for current attack animation phase (Issue #595).
	var _attack_anim_timer: float = 0.0
	## Whether damage was already applied during this attack (Issue #595).
	var _damage_applied: bool = false
	## Current weapon rotation angle from animation (Issue #595).
	var _weapon_rotation: float = 0.0
	## Current arm offset from animation (Issue #595).
	var _arm_offset: float = 0.0

	# Animation duration constants (must match MacheteComponent).
	const WINDUP_DURATION: float = 0.25
	const PAUSE_DURATION: float = 0.1
	const STRIKE_DURATION: float = 0.15
	const RECOVERY_DURATION: float = 0.2
	const WINDUP_ANGLE: float = -PI / 2.0
	const STRIKE_END_ANGLE: float = PI / 2.0

	func set_parent_position(pos: Vector2) -> void:
		_parent_position = pos

	func update(delta: float) -> void:
		_melee_timer += delta
		_dodge_timer += delta
		if _is_dodging:
			var total_dodge_time := dodge_distance / dodge_speed
			_dodge_progress += delta / total_dodge_time
			if _dodge_progress >= 1.0:
				_is_dodging = false
				_dodge_progress = 0.0
		if _attack_phase != AttackPhase.IDLE:
			_process_attack_animation(delta)

	func is_attack_ready() -> bool:
		return _melee_timer >= melee_cooldown and not _is_dodging and _attack_phase == AttackPhase.IDLE

	func can_melee_attack(target_position: Vector2) -> bool:
		if _melee_timer < melee_cooldown:
			return false
		if _is_dodging:
			return false
		if _attack_phase != AttackPhase.IDLE:
			return false
		var distance := _parent_position.distance_to(target_position)
		return distance <= melee_range

	func is_in_melee_range(target_position: Vector2) -> bool:
		return _parent_position.distance_to(target_position) <= melee_range

	func is_backstab_opportunity(player_position: Vector2, player_rotation: float) -> bool:
		var player_facing := Vector2.RIGHT.rotated(player_rotation)
		var player_to_enemy := (_parent_position - player_position).normalized()
		return player_facing.dot(player_to_enemy) < 0.0

	func get_backstab_approach_position(player_position: Vector2, player_rotation: float, approach_distance: float = 150.0) -> Vector2:
		var player_facing := Vector2.RIGHT.rotated(player_rotation)
		return player_position - player_facing * approach_distance

	func try_dodge(bullet_direction: Vector2) -> bool:
		if _is_dodging:
			return false
		if _dodge_timer < dodge_cooldown:
			return false
		_dodge_timer = 0.0
		_is_dodging = true
		_dodge_start = _parent_position
		_dodge_progress = 0.0
		var perp := Vector2(-bullet_direction.y, bullet_direction.x)
		_dodge_target = _parent_position + perp * dodge_distance
		return true

	func is_dodging() -> bool:
		return _is_dodging

	func get_dodge_velocity() -> Vector2:
		if not _is_dodging:
			return Vector2.ZERO
		var dodge_dir := (_dodge_target - _dodge_start).normalized()
		return dodge_dir * dodge_speed

	func get_sneak_speed(base_speed: float) -> float:
		return base_speed * sneak_speed_multiplier

	func configure_from_weapon_config(config: Dictionary) -> void:
		melee_range = config.get("melee_range", 80.0)
		melee_damage = config.get("melee_damage", 2)
		dodge_speed = config.get("dodge_speed", 400.0)
		dodge_distance = config.get("dodge_distance", 120.0)
		sneak_speed_multiplier = config.get("sneak_speed_multiplier", 0.6)

	## Start melee attack animation (Issue #595).
	func perform_melee_attack(target_position: Vector2) -> bool:
		if not can_melee_attack(target_position):
			return false
		_melee_timer = 0.0
		_damage_applied = false
		_set_attack_phase(AttackPhase.WINDUP)
		return true

	## Check if currently in an attack animation (Issue #595).
	func is_attacking() -> bool:
		return _attack_phase != AttackPhase.IDLE

	## Get the current attack phase (Issue #595).
	func get_attack_phase() -> int:
		return _attack_phase

	## Get the current weapon rotation offset (Issue #595).
	func get_weapon_rotation() -> float:
		return _weapon_rotation

	## Get the current arm position offset (Issue #595).
	func get_arm_offset() -> float:
		return _arm_offset

	## Process attack animation phases (Issue #595).
	func _process_attack_animation(delta: float) -> void:
		_attack_anim_timer += delta
		match _attack_phase:
			AttackPhase.WINDUP:
				var progress := clampf(_attack_anim_timer / WINDUP_DURATION, 0.0, 1.0)
				var eased := 1.0 - (1.0 - progress) * (1.0 - progress)
				_weapon_rotation = lerpf(0.0, WINDUP_ANGLE, eased)
				_arm_offset = lerpf(0.0, -4.0, eased)
				if _attack_anim_timer >= WINDUP_DURATION:
					_set_attack_phase(AttackPhase.PAUSE)
			AttackPhase.PAUSE:
				_weapon_rotation = WINDUP_ANGLE
				_arm_offset = -4.0
				if _attack_anim_timer >= PAUSE_DURATION:
					_set_attack_phase(AttackPhase.STRIKE)
			AttackPhase.STRIKE:
				var progress := clampf(_attack_anim_timer / STRIKE_DURATION, 0.0, 1.0)
				var eased := progress * progress
				_weapon_rotation = lerpf(WINDUP_ANGLE, STRIKE_END_ANGLE, eased)
				_arm_offset = lerpf(-4.0, 6.0, eased)
				if progress >= 0.5 and not _damage_applied:
					_damage_applied = true
				if _attack_anim_timer >= STRIKE_DURATION:
					_set_attack_phase(AttackPhase.RECOVERY)
			AttackPhase.RECOVERY:
				var progress := clampf(_attack_anim_timer / RECOVERY_DURATION, 0.0, 1.0)
				var eased := progress * progress * (3.0 - 2.0 * progress)
				_weapon_rotation = lerpf(STRIKE_END_ANGLE, 0.0, eased)
				_arm_offset = lerpf(6.0, 0.0, eased)
				if _attack_anim_timer >= RECOVERY_DURATION:
					_set_attack_phase(AttackPhase.IDLE)

	## Set the attack animation phase and reset the phase timer (Issue #595).
	func _set_attack_phase(phase: int) -> void:
		_attack_phase = phase
		_attack_anim_timer = 0.0
		if phase == AttackPhase.IDLE:
			_weapon_rotation = 0.0
			_arm_offset = 0.0


# ============================================================================
# Tests
# ============================================================================


var _component: MockMacheteComponent


func before_each() -> void:
	_component = MockMacheteComponent.new()
	_component._melee_timer = _component.melee_cooldown  # Ready to attack


# --- Melee Range Tests ---

func test_in_melee_range_when_close() -> void:
	_component.set_parent_position(Vector2(100, 100))
	assert_true(_component.is_in_melee_range(Vector2(150, 100)),
		"Should be in melee range when within 80px")


func test_not_in_melee_range_when_far() -> void:
	_component.set_parent_position(Vector2(100, 100))
	assert_false(_component.is_in_melee_range(Vector2(500, 100)),
		"Should NOT be in melee range when 400px away")


func test_melee_range_boundary() -> void:
	_component.set_parent_position(Vector2(0, 0))
	# Exactly at range
	assert_true(_component.is_in_melee_range(Vector2(80, 0)),
		"Should be in range at exactly 80px")
	# Just beyond range
	assert_false(_component.is_in_melee_range(Vector2(81, 0)),
		"Should NOT be in range at 81px")


# --- Attack Ready Tests ---

func test_is_attack_ready_when_cooldown_elapsed() -> void:
	assert_true(_component.is_attack_ready(),
		"Should be attack-ready when cooldown elapsed and not dodging")


func test_is_not_attack_ready_on_cooldown() -> void:
	_component._melee_timer = 0.0
	assert_false(_component.is_attack_ready(),
		"Should NOT be attack-ready when on cooldown")


func test_is_not_attack_ready_while_dodging() -> void:
	_component._is_dodging = true
	assert_false(_component.is_attack_ready(),
		"Should NOT be attack-ready while dodging")


func test_is_not_attack_ready_while_attacking() -> void:
	_component._attack_phase = MockMacheteComponent.AttackPhase.WINDUP
	assert_false(_component.is_attack_ready(),
		"Should NOT be attack-ready while in attack animation")


# --- Melee Attack Tests ---

func test_can_melee_attack_when_ready_and_in_range() -> void:
	_component.set_parent_position(Vector2(100, 100))
	assert_true(_component.can_melee_attack(Vector2(150, 100)),
		"Should be able to attack when cooldown elapsed and in range")


func test_cannot_melee_attack_on_cooldown() -> void:
	_component.set_parent_position(Vector2(100, 100))
	_component._melee_timer = 0.0  # Just attacked
	assert_false(_component.can_melee_attack(Vector2(150, 100)),
		"Should NOT attack when on cooldown")


func test_cannot_melee_attack_when_out_of_range() -> void:
	_component.set_parent_position(Vector2(100, 100))
	assert_false(_component.can_melee_attack(Vector2(500, 100)),
		"Should NOT attack when out of range")


func test_cannot_melee_attack_while_dodging() -> void:
	_component.set_parent_position(Vector2(100, 100))
	_component._is_dodging = true
	assert_false(_component.can_melee_attack(Vector2(150, 100)),
		"Should NOT attack while dodging")


func test_cannot_melee_attack_while_attacking() -> void:
	_component.set_parent_position(Vector2(100, 100))
	_component._attack_phase = MockMacheteComponent.AttackPhase.STRIKE
	assert_false(_component.can_melee_attack(Vector2(150, 100)),
		"Should NOT start new attack while attack animation is playing")


func test_melee_cooldown_resets_after_time() -> void:
	_component.set_parent_position(Vector2(100, 100))
	_component._melee_timer = 0.0
	assert_false(_component.can_melee_attack(Vector2(150, 100)),
		"Should NOT attack right after attacking")
	# Simulate time passing
	_component.update(1.5)
	assert_true(_component.can_melee_attack(Vector2(150, 100)),
		"Should be able to attack after cooldown elapsed")


# --- Attack Animation Tests (Issue #595) ---

func test_perform_melee_attack_starts_animation() -> void:
	_component.set_parent_position(Vector2(100, 100))
	var result := _component.perform_melee_attack(Vector2(150, 100))
	assert_true(result, "Attack should start successfully")
	assert_true(_component.is_attacking(), "Should be in attack animation")
	assert_eq(_component.get_attack_phase(), MockMacheteComponent.AttackPhase.WINDUP,
		"Should start in WINDUP phase")


func test_attack_animation_starts_with_windup() -> void:
	_component.set_parent_position(Vector2(100, 100))
	_component.perform_melee_attack(Vector2(150, 100))
	assert_eq(_component.get_attack_phase(), MockMacheteComponent.AttackPhase.WINDUP,
		"First phase should be WINDUP")


func test_attack_animation_windup_to_pause() -> void:
	_component.set_parent_position(Vector2(100, 100))
	_component.perform_melee_attack(Vector2(150, 100))
	# Simulate windup duration
	_component.update(MockMacheteComponent.WINDUP_DURATION + 0.01)
	assert_eq(_component.get_attack_phase(), MockMacheteComponent.AttackPhase.PAUSE,
		"Should transition from WINDUP to PAUSE")


func test_attack_animation_pause_to_strike() -> void:
	_component.set_parent_position(Vector2(100, 100))
	_component.perform_melee_attack(Vector2(150, 100))
	# Advance through windup
	_component.update(MockMacheteComponent.WINDUP_DURATION + 0.01)
	# Advance through pause
	_component.update(MockMacheteComponent.PAUSE_DURATION + 0.01)
	assert_eq(_component.get_attack_phase(), MockMacheteComponent.AttackPhase.STRIKE,
		"Should transition from PAUSE to STRIKE")


func test_attack_animation_strike_to_recovery() -> void:
	_component.set_parent_position(Vector2(100, 100))
	_component.perform_melee_attack(Vector2(150, 100))
	_component.update(MockMacheteComponent.WINDUP_DURATION + 0.01)
	_component.update(MockMacheteComponent.PAUSE_DURATION + 0.01)
	_component.update(MockMacheteComponent.STRIKE_DURATION + 0.01)
	assert_eq(_component.get_attack_phase(), MockMacheteComponent.AttackPhase.RECOVERY,
		"Should transition from STRIKE to RECOVERY")


func test_attack_animation_recovery_to_idle() -> void:
	_component.set_parent_position(Vector2(100, 100))
	_component.perform_melee_attack(Vector2(150, 100))
	_component.update(MockMacheteComponent.WINDUP_DURATION + 0.01)
	_component.update(MockMacheteComponent.PAUSE_DURATION + 0.01)
	_component.update(MockMacheteComponent.STRIKE_DURATION + 0.01)
	_component.update(MockMacheteComponent.RECOVERY_DURATION + 0.01)
	assert_eq(_component.get_attack_phase(), MockMacheteComponent.AttackPhase.IDLE,
		"Should return to IDLE after RECOVERY")
	assert_false(_component.is_attacking(), "Should NOT be attacking after full animation")


func test_attack_animation_full_duration() -> void:
	_component.set_parent_position(Vector2(100, 100))
	_component.perform_melee_attack(Vector2(150, 100))
	var total_duration := (MockMacheteComponent.WINDUP_DURATION +
		MockMacheteComponent.PAUSE_DURATION + MockMacheteComponent.STRIKE_DURATION +
		MockMacheteComponent.RECOVERY_DURATION)
	# Advance in small steps through entire animation
	var time_passed := 0.0
	var step := 0.05
	while time_passed < total_duration + step:
		_component.update(step)
		time_passed += step
	assert_false(_component.is_attacking(),
		"Should NOT be attacking after full animation duration (%.2fs)" % total_duration)


func test_weapon_rotation_during_windup() -> void:
	_component.set_parent_position(Vector2(100, 100))
	_component.perform_melee_attack(Vector2(150, 100))
	# Advance partway through windup
	_component.update(MockMacheteComponent.WINDUP_DURATION * 0.5)
	assert_lt(_component.get_weapon_rotation(), 0.0,
		"Weapon should rotate backward (negative) during windup")


func test_weapon_rotation_at_pause() -> void:
	_component.set_parent_position(Vector2(100, 100))
	_component.perform_melee_attack(Vector2(150, 100))
	_component.update(MockMacheteComponent.WINDUP_DURATION + 0.01)
	# Now in PAUSE phase, weapon should be at WINDUP_ANGLE
	assert_almost_eq(_component.get_weapon_rotation(), MockMacheteComponent.WINDUP_ANGLE, 0.01,
		"Weapon should be at windup angle during pause")


func test_weapon_rotation_during_strike() -> void:
	_component.set_parent_position(Vector2(100, 100))
	_component.perform_melee_attack(Vector2(150, 100))
	_component.update(MockMacheteComponent.WINDUP_DURATION + 0.01)
	_component.update(MockMacheteComponent.PAUSE_DURATION + 0.01)
	# Advance partway through strike
	_component.update(MockMacheteComponent.STRIKE_DURATION * 0.8)
	assert_gt(_component.get_weapon_rotation(), MockMacheteComponent.WINDUP_ANGLE,
		"Weapon should rotate forward during strike (greater than windup angle)")


func test_weapon_rotation_returns_to_zero_after_animation() -> void:
	_component.set_parent_position(Vector2(100, 100))
	_component.perform_melee_attack(Vector2(150, 100))
	_component.update(MockMacheteComponent.WINDUP_DURATION + 0.01)
	_component.update(MockMacheteComponent.PAUSE_DURATION + 0.01)
	_component.update(MockMacheteComponent.STRIKE_DURATION + 0.01)
	_component.update(MockMacheteComponent.RECOVERY_DURATION + 0.01)
	assert_almost_eq(_component.get_weapon_rotation(), 0.0, 0.01,
		"Weapon rotation should return to 0 after animation completes")


func test_arm_offset_during_windup() -> void:
	_component.set_parent_position(Vector2(100, 100))
	_component.perform_melee_attack(Vector2(150, 100))
	_component.update(MockMacheteComponent.WINDUP_DURATION + 0.01)
	# At pause, arm should be pulled back (negative offset)
	assert_lt(_component.get_arm_offset(), 0.0,
		"Arm should be pulled back (negative offset) during windup/pause")


func test_arm_offset_during_strike() -> void:
	_component.set_parent_position(Vector2(100, 100))
	_component.perform_melee_attack(Vector2(150, 100))
	_component.update(MockMacheteComponent.WINDUP_DURATION + 0.01)
	_component.update(MockMacheteComponent.PAUSE_DURATION + 0.01)
	_component.update(MockMacheteComponent.STRIKE_DURATION + 0.001)
	# At end of strike, arm should be pushed forward (positive offset)
	assert_gt(_component.get_arm_offset(), 0.0,
		"Arm should be pushed forward (positive offset) at end of strike")


func test_arm_offset_returns_to_zero_after_animation() -> void:
	_component.set_parent_position(Vector2(100, 100))
	_component.perform_melee_attack(Vector2(150, 100))
	_component.update(MockMacheteComponent.WINDUP_DURATION + 0.01)
	_component.update(MockMacheteComponent.PAUSE_DURATION + 0.01)
	_component.update(MockMacheteComponent.STRIKE_DURATION + 0.01)
	_component.update(MockMacheteComponent.RECOVERY_DURATION + 0.01)
	assert_almost_eq(_component.get_arm_offset(), 0.0, 0.01,
		"Arm offset should return to 0 after animation completes")


func test_damage_applied_during_strike_phase() -> void:
	_component.set_parent_position(Vector2(100, 100))
	_component.perform_melee_attack(Vector2(150, 100))
	assert_false(_component._damage_applied, "Damage should NOT be applied in WINDUP")
	_component.update(MockMacheteComponent.WINDUP_DURATION + 0.01)
	assert_false(_component._damage_applied, "Damage should NOT be applied in PAUSE")
	_component.update(MockMacheteComponent.PAUSE_DURATION + 0.01)
	# Advance past strike midpoint
	_component.update(MockMacheteComponent.STRIKE_DURATION * 0.6)
	assert_true(_component._damage_applied,
		"Damage should be applied at midpoint of STRIKE phase")


func test_cannot_start_second_attack_during_animation() -> void:
	_component.set_parent_position(Vector2(100, 100))
	_component.perform_melee_attack(Vector2(150, 100))
	# Try to start another attack during animation
	_component._melee_timer = _component.melee_cooldown  # Force cooldown ready
	var result := _component.perform_melee_attack(Vector2(150, 100))
	assert_false(result, "Should NOT start a second attack while animation is playing")


func test_weapon_rotation_zero_when_idle() -> void:
	assert_almost_eq(_component.get_weapon_rotation(), 0.0, 0.01,
		"Weapon rotation should be 0 when idle (no attack)")


func test_arm_offset_zero_when_idle() -> void:
	assert_almost_eq(_component.get_arm_offset(), 0.0, 0.01,
		"Arm offset should be 0 when idle (no attack)")


func test_attack_animation_durations_positive() -> void:
	assert_gt(MockMacheteComponent.WINDUP_DURATION, 0.0, "WINDUP_DURATION should be positive")
	assert_gt(MockMacheteComponent.PAUSE_DURATION, 0.0, "PAUSE_DURATION should be positive")
	assert_gt(MockMacheteComponent.STRIKE_DURATION, 0.0, "STRIKE_DURATION should be positive")
	assert_gt(MockMacheteComponent.RECOVERY_DURATION, 0.0, "RECOVERY_DURATION should be positive")


func test_strike_faster_than_windup() -> void:
	assert_lt(MockMacheteComponent.STRIKE_DURATION, MockMacheteComponent.WINDUP_DURATION,
		"STRIKE should be faster than WINDUP for aggressive feel")


# --- Backstab Detection Tests ---

func test_backstab_from_behind() -> void:
	# Enemy behind player (player facing right, enemy to the left)
	_component.set_parent_position(Vector2(0, 0))
	var player_pos := Vector2(100, 0)
	var player_rot := 0.0  # Facing right
	assert_true(_component.is_backstab_opportunity(player_pos, player_rot),
		"Enemy behind player should be a backstab opportunity")


func test_no_backstab_from_front() -> void:
	# Enemy in front of player (player facing right, enemy to the right)
	_component.set_parent_position(Vector2(200, 0))
	var player_pos := Vector2(100, 0)
	var player_rot := 0.0  # Facing right
	assert_false(_component.is_backstab_opportunity(player_pos, player_rot),
		"Enemy in front of player should NOT be a backstab opportunity")


func test_backstab_from_side_behind() -> void:
	# Enemy behind-left of player facing right
	_component.set_parent_position(Vector2(0, 50))
	var player_pos := Vector2(100, 0)
	var player_rot := 0.0  # Facing right
	assert_true(_component.is_backstab_opportunity(player_pos, player_rot),
		"Enemy behind-left should be a backstab opportunity")


func test_backstab_approach_position() -> void:
	var player_pos := Vector2(500, 500)
	var player_rot := 0.0  # Facing right
	var approach_pos := _component.get_backstab_approach_position(player_pos, player_rot, 150.0)
	# Should be behind the player (facing right, so behind = to the left)
	assert_lt(approach_pos.x, player_pos.x,
		"Backstab approach should be behind the player (lower x when facing right)")
	assert_almost_eq(approach_pos.y, player_pos.y, 1.0,
		"Backstab approach y should be similar to player y")


# --- Dodge Tests ---

func test_dodge_initiates_successfully() -> void:
	_component.set_parent_position(Vector2(100, 100))
	_component._dodge_timer = _component.dodge_cooldown  # Ready to dodge
	var result := _component.try_dodge(Vector2(1, 0))
	assert_true(result, "Dodge should initiate successfully")
	assert_true(_component.is_dodging(), "Should be in dodging state")


func test_dodge_direction_perpendicular() -> void:
	_component.set_parent_position(Vector2(100, 100))
	_component._dodge_timer = _component.dodge_cooldown
	_component.try_dodge(Vector2(1, 0))  # Bullet going right
	# Dodge should be perpendicular (up or down)
	var vel := _component.get_dodge_velocity()
	assert_almost_eq(abs(vel.x), 0.0, 1.0,
		"Dodge perpendicular to rightward bullet should have minimal x velocity")
	assert_gt(abs(vel.y), 0.0,
		"Dodge perpendicular to rightward bullet should have y velocity")


func test_cannot_dodge_while_dodging() -> void:
	_component.set_parent_position(Vector2(100, 100))
	_component._dodge_timer = _component.dodge_cooldown
	_component.try_dodge(Vector2(1, 0))
	var result := _component.try_dodge(Vector2(0, 1))
	assert_false(result, "Should NOT dodge while already dodging")


func test_cannot_dodge_on_cooldown() -> void:
	_component.set_parent_position(Vector2(100, 100))
	_component._dodge_timer = 0.0  # On cooldown
	var result := _component.try_dodge(Vector2(1, 0))
	assert_false(result, "Should NOT dodge when on cooldown")


func test_dodge_completes_after_time() -> void:
	_component.set_parent_position(Vector2(100, 100))
	_component._dodge_timer = _component.dodge_cooldown
	_component.try_dodge(Vector2(1, 0))
	assert_true(_component.is_dodging(), "Should be dodging after initiation")
	# Simulate enough time for dodge to complete
	var dodge_time := _component.dodge_distance / _component.dodge_speed
	_component.update(dodge_time + 0.01)
	assert_false(_component.is_dodging(), "Should NOT be dodging after completion")


func test_dodge_velocity_zero_when_not_dodging() -> void:
	var vel := _component.get_dodge_velocity()
	assert_eq(vel, Vector2.ZERO, "Dodge velocity should be zero when not dodging")


func test_dodge_velocity_magnitude() -> void:
	_component.set_parent_position(Vector2(100, 100))
	_component._dodge_timer = _component.dodge_cooldown
	_component.try_dodge(Vector2(1, 0))
	var vel := _component.get_dodge_velocity()
	assert_almost_eq(vel.length(), _component.dodge_speed, 1.0,
		"Dodge velocity should match dodge_speed")


# --- Sneak Speed Tests ---

func test_sneak_speed_reduction() -> void:
	var base_speed := 220.0
	var sneak_speed := _component.get_sneak_speed(base_speed)
	var expected := base_speed * 0.6
	assert_almost_eq(sneak_speed, expected, 0.01,
		"Sneak speed should be 60%% of base speed")


func test_sneak_speed_with_combat_speed() -> void:
	var combat_speed := 320.0
	var sneak_speed := _component.get_sneak_speed(combat_speed)
	assert_lt(sneak_speed, combat_speed,
		"Sneak speed should be less than combat speed")


# --- Configuration Tests ---

func test_configure_from_weapon_config() -> void:
	var config := {
		"melee_range": 100.0,
		"melee_damage": 3,
		"dodge_speed": 500.0,
		"dodge_distance": 150.0,
		"sneak_speed_multiplier": 0.5
	}
	_component.configure_from_weapon_config(config)
	assert_eq(_component.melee_range, 100.0, "melee_range should be configured")
	assert_eq(_component.melee_damage, 3, "melee_damage should be configured")
	assert_eq(_component.dodge_speed, 500.0, "dodge_speed should be configured")
	assert_eq(_component.dodge_distance, 150.0, "dodge_distance should be configured")
	assert_almost_eq(_component.sneak_speed_multiplier, 0.5, 0.01,
		"sneak_speed_multiplier should be configured")


func test_configure_with_missing_keys_uses_defaults() -> void:
	var config := {}  # Empty config
	_component.configure_from_weapon_config(config)
	assert_eq(_component.melee_range, 80.0, "Default melee_range should be 80")
	assert_eq(_component.melee_damage, 2, "Default melee_damage should be 2")


# --- Weapon Config Component Tests ---

func test_weapon_config_machete_exists() -> void:
	var config := WeaponConfigComponent.get_config(3)  # MACHETE
	assert_true(config.has("is_melee"), "MACHETE config should have is_melee flag")
	assert_true(config["is_melee"], "MACHETE should be a melee weapon")
	assert_eq(config["melee_range"], 80.0, "MACHETE melee range should be 80px")
	assert_eq(config["melee_damage"], 2, "MACHETE melee damage should be 2")


func test_weapon_config_machete_no_bullets() -> void:
	var config := WeaponConfigComponent.get_config(3)
	assert_eq(config["bullet_scene_path"], "", "MACHETE should have no bullet scene")
	assert_eq(config["casing_scene_path"], "", "MACHETE should have no casing scene")
	assert_eq(config["magazine_size"], 0, "MACHETE should have no magazine")


func test_weapon_config_type_name_machete() -> void:
	var name := WeaponConfigComponent.get_type_name(3)
	assert_eq(name, "MACHETE", "Weapon type 3 should be named MACHETE")


func test_weapon_config_machete_sprite_path() -> void:
	var config := WeaponConfigComponent.get_config(3)
	assert_eq(config["sprite_path"], "res://assets/sprites/weapons/machete_topdown.png",
		"MACHETE should have correct sprite path")


func test_weapon_config_non_melee_types() -> void:
	# Verify existing weapon types are NOT melee
	for wtype in [0, 1, 2]:  # RIFLE, SHOTGUN, UZI
		var config := WeaponConfigComponent.get_config(wtype)
		assert_false(config.get("is_melee", false),
			"Weapon type %d should NOT be melee" % wtype)


# --- Update Timer Tests ---

func test_update_increments_timers() -> void:
	_component._melee_timer = 0.0
	_component._dodge_timer = 0.0
	_component.update(0.5)
	assert_almost_eq(_component._melee_timer, 0.5, 0.01,
		"Melee timer should increment")
	assert_almost_eq(_component._dodge_timer, 0.5, 0.01,
		"Dodge timer should increment")


# --- Melee Damage Value Tests ---

func test_melee_damage_value() -> void:
	assert_eq(_component.melee_damage, 2,
		"Default melee damage should be 2 (higher than single bullet)")


func test_melee_range_value() -> void:
	assert_eq(_component.melee_range, 80.0,
		"Default melee range should be 80px")


# --- Machete Attack Animation Constants Tests (Issue #595) ---

func test_machete_shoot_cooldown() -> void:
	var config := WeaponConfigComponent.get_config(3)
	assert_eq(config["shoot_cooldown"], 1.5, "MACHETE shoot cooldown should be 1.5s")


func test_machete_bullet_speed_is_zero() -> void:
	var config := WeaponConfigComponent.get_config(3)
	assert_eq(config["bullet_speed"], 0.0, "MACHETE bullet speed should be 0")


func test_machete_magazine_size_is_zero() -> void:
	var config := WeaponConfigComponent.get_config(3)
	assert_eq(config["magazine_size"], 0, "MACHETE magazine size should be 0")


func test_machete_weapon_loudness() -> void:
	var config := WeaponConfigComponent.get_config(3)
	assert_eq(config["weapon_loudness"], 200.0, "MACHETE weapon loudness should be 200.0")


func test_machete_is_melee() -> void:
	var config := WeaponConfigComponent.get_config(3)
	assert_true(config["is_melee"], "MACHETE should be a melee weapon")
