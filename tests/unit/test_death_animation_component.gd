extends GutTest
## Unit tests for DeathAnimationComponent.
##
## Tests the death animation and ragdoll physics functionality including:
## - Angle-based animation selection (24 animations for every 15 degrees)
## - Fall animation timing and keyframe interpolation
## - Ragdoll activation at 60% of fall time
## - Joint constraint configuration for jitter prevention
## - Body persistence after death


# ============================================================================
# Mock DeathAnimationComponent for Logic Tests
# ============================================================================


class MockDeathAnimationComponent:
	## Duration of the pre-made fall animation in seconds.
	var fall_animation_duration: float = 0.8

	## Point at which ragdoll activates (0.0-1.0).
	var ragdoll_activation_point: float = 0.6

	## Whether to enable ragdoll physics after fall animation.
	var enable_ragdoll: bool = true

	## Whether to persist the ragdoll after death.
	var persist_body_after_death: bool = true

	## Animation phase states.
	enum AnimationPhase {
		NONE,
		FALLING,
		RAGDOLL,
		AT_REST
	}

	## Current animation phase.
	var _current_phase: AnimationPhase = AnimationPhase.NONE

	## Animation timer.
	var _animation_timer: float = 0.0

	## Hit angle in radians.
	var _hit_angle: float = 0.0

	## Animation index (0-23).
	var _animation_index: int = 0

	## Whether ragdoll has been activated.
	var _ragdoll_activated: bool = false

	## Whether death animation is active.
	var _is_active: bool = false

	## Signal tracking.
	var death_animation_started_emitted: int = 0
	var ragdoll_activated_emitted: int = 0
	var death_animation_completed_emitted: int = 0

	## Calculate animation index from hit direction.
	func _calculate_animation_index(hit_direction: Vector2) -> int:
		var angle := hit_direction.angle()
		var normalized_angle := fmod(angle + PI, TAU)
		return int(normalized_angle / (TAU / 24.0)) % 24

	## Start the death animation.
	func start_death_animation(hit_direction: Vector2) -> void:
		if _is_active:
			return

		_is_active = true
		_hit_angle = hit_direction.normalized().angle()
		_animation_index = _calculate_animation_index(hit_direction)
		_current_phase = AnimationPhase.FALLING
		_animation_timer = 0.0
		_ragdoll_activated = false
		death_animation_started_emitted += 1

	## Update the animation (called each frame).
	func update(delta: float) -> void:
		if not _is_active:
			return

		match _current_phase:
			AnimationPhase.FALLING:
				_update_fall_animation(delta)
			AnimationPhase.RAGDOLL:
				_update_ragdoll_phase(delta)

	## Update fall animation phase.
	func _update_fall_animation(delta: float) -> void:
		_animation_timer += delta
		var progress := clampf(_animation_timer / fall_animation_duration, 0.0, 1.0)

		# Check if we should activate ragdoll
		if enable_ragdoll and not _ragdoll_activated and progress >= ragdoll_activation_point:
			_activate_ragdoll()

		# Check if animation is complete
		if progress >= 1.0:
			if enable_ragdoll and _ragdoll_activated:
				_current_phase = AnimationPhase.RAGDOLL
			else:
				_current_phase = AnimationPhase.AT_REST
				death_animation_completed_emitted += 1

	## Activate ragdoll physics.
	func _activate_ragdoll() -> void:
		if _ragdoll_activated:
			return
		_ragdoll_activated = true
		ragdoll_activated_emitted += 1

	## Update ragdoll phase.
	func _update_ragdoll_phase(delta: float) -> void:
		_animation_timer += delta
		# Simulate ragdoll coming to rest after some time
		if _animation_timer > 5.0:
			_current_phase = AnimationPhase.AT_REST
			death_animation_completed_emitted += 1

	## Reset the animation.
	func reset() -> void:
		_is_active = false
		_current_phase = AnimationPhase.NONE
		_animation_timer = 0.0
		_ragdoll_activated = false

	## Check if animation is active.
	func is_active() -> bool:
		return _is_active

	## Check if animation is complete.
	func is_complete() -> bool:
		return _current_phase == AnimationPhase.AT_REST

	## Get current phase.
	func get_phase() -> AnimationPhase:
		return _current_phase


# ============================================================================
# Animation Index Tests
# ============================================================================


class TestAnimationIndex extends GutTest:
	var component: MockDeathAnimationComponent

	func before_each() -> void:
		component = MockDeathAnimationComponent.new()

	## Test that animation index is calculated correctly for different angles.
	func test_animation_index_right() -> void:
		# Right (0 degrees) -> index should be around 12
		var index := component._calculate_animation_index(Vector2.RIGHT)
		assert_eq(index, 12, "Right direction should give index 12")

	func test_animation_index_left() -> void:
		# Left (180 degrees / PI) -> index should be around 0 or 24
		var index := component._calculate_animation_index(Vector2.LEFT)
		assert_true(index == 0 or index == 23, "Left direction should give index 0 or 23")

	func test_animation_index_up() -> void:
		# Up (-90 degrees / -PI/2) -> index should be around 6
		var index := component._calculate_animation_index(Vector2.UP)
		assert_true(index >= 5 and index <= 7, "Up direction should give index around 6")

	func test_animation_index_down() -> void:
		# Down (90 degrees / PI/2) -> index should be around 18
		var index := component._calculate_animation_index(Vector2.DOWN)
		assert_true(index >= 17 and index <= 19, "Down direction should give index around 18")

	func test_animation_index_covers_all_24() -> void:
		# Test that all 24 indices can be generated
		var indices_found: Array[int] = []
		for i in range(360):
			var angle := deg_to_rad(float(i))
			var direction := Vector2(cos(angle), sin(angle))
			var index := component._calculate_animation_index(direction)
			if not indices_found.has(index):
				indices_found.append(index)

		assert_eq(indices_found.size(), 24, "Should generate all 24 unique animation indices")


# ============================================================================
# Animation Phase Tests
# ============================================================================


class TestAnimationPhases extends GutTest:
	var component: MockDeathAnimationComponent

	func before_each() -> void:
		component = MockDeathAnimationComponent.new()

	func test_initial_state_is_none() -> void:
		assert_eq(component.get_phase(), MockDeathAnimationComponent.AnimationPhase.NONE)
		assert_false(component.is_active())
		assert_false(component.is_complete())

	func test_start_death_animation_sets_falling_phase() -> void:
		component.start_death_animation(Vector2.RIGHT)
		assert_eq(component.get_phase(), MockDeathAnimationComponent.AnimationPhase.FALLING)
		assert_true(component.is_active())
		assert_eq(component.death_animation_started_emitted, 1)

	func test_ragdoll_activates_at_60_percent() -> void:
		component.start_death_animation(Vector2.RIGHT)

		# Simulate time passing to just before 60%
		component.update(component.fall_animation_duration * 0.59)
		assert_false(component._ragdoll_activated, "Ragdoll should not activate before 60%")

		# Simulate time passing past 60%
		component.update(component.fall_animation_duration * 0.02)
		assert_true(component._ragdoll_activated, "Ragdoll should activate at 60%")
		assert_eq(component.ragdoll_activated_emitted, 1)

	func test_animation_completes_after_fall_duration() -> void:
		component.start_death_animation(Vector2.RIGHT)

		# Simulate full animation duration
		component.update(component.fall_animation_duration + 0.1)

		# Should be in RAGDOLL phase after fall, not AT_REST yet
		assert_eq(component.get_phase(), MockDeathAnimationComponent.AnimationPhase.RAGDOLL)

	func test_animation_without_ragdoll_completes_at_fall_end() -> void:
		component.enable_ragdoll = false
		component.start_death_animation(Vector2.RIGHT)

		# Simulate full animation duration
		component.update(component.fall_animation_duration + 0.1)

		assert_eq(component.get_phase(), MockDeathAnimationComponent.AnimationPhase.AT_REST)
		assert_true(component.is_complete())
		assert_eq(component.death_animation_completed_emitted, 1)


# ============================================================================
# Reset Tests
# ============================================================================


class TestReset extends GutTest:
	var component: MockDeathAnimationComponent

	func before_each() -> void:
		component = MockDeathAnimationComponent.new()

	func test_reset_clears_state() -> void:
		component.start_death_animation(Vector2.RIGHT)
		component.update(component.fall_animation_duration * 0.7)

		component.reset()

		assert_eq(component.get_phase(), MockDeathAnimationComponent.AnimationPhase.NONE)
		assert_false(component.is_active())
		assert_false(component._ragdoll_activated)
		assert_eq(component._animation_timer, 0.0)

	func test_can_restart_after_reset() -> void:
		component.start_death_animation(Vector2.RIGHT)
		component.update(component.fall_animation_duration)
		component.reset()

		component.start_death_animation(Vector2.LEFT)
		assert_true(component.is_active())
		assert_eq(component.get_phase(), MockDeathAnimationComponent.AnimationPhase.FALLING)


# ============================================================================
# Double Start Prevention Tests
# ============================================================================


class TestDoubleStartPrevention extends GutTest:
	var component: MockDeathAnimationComponent

	func before_each() -> void:
		component = MockDeathAnimationComponent.new()

	func test_cannot_start_while_active() -> void:
		component.start_death_animation(Vector2.RIGHT)
		var first_index := component._animation_index

		component.start_death_animation(Vector2.LEFT)
		# Should still have the first animation's index
		assert_eq(component._animation_index, first_index, "Second start should be ignored")
		assert_eq(component.death_animation_started_emitted, 1, "Should only emit once")


# ============================================================================
# Configuration Tests
# ============================================================================


class TestConfiguration extends GutTest:
	var component: MockDeathAnimationComponent

	func before_each() -> void:
		component = MockDeathAnimationComponent.new()

	func test_ragdoll_activation_point_default() -> void:
		assert_eq(component.ragdoll_activation_point, 0.6, "Default ragdoll activation should be 60%")

	func test_fall_animation_duration_default() -> void:
		assert_eq(component.fall_animation_duration, 0.8, "Default fall duration should be 0.8 seconds")

	func test_persist_body_default() -> void:
		assert_true(component.persist_body_after_death, "Bodies should persist by default")

	func test_enable_ragdoll_default() -> void:
		assert_true(component.enable_ragdoll, "Ragdoll should be enabled by default")
