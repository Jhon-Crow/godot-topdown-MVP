extends GutTest
## Unit tests for snowy_feet_component.gd (Issue #1627).
##
## Tests that snow footprints are spawned as characters walk, that alpha
## decreases with each step, that fade-out is scheduled, and that the
## component correctly uses facing direction for footprint rotation.


# ============================================================================
# Mock SnowyFeetComponent for Logic Tests
# ============================================================================


class MockSnowyFeetComponent:
	## Configuration (mirrors exports).
	var snow_steps_count: int = 8
	var step_distance: float = 30.0
	var initial_alpha: float = 0.55
	var alpha_decay_rate: float = 0.06
	var footprint_scale: float = 1.0

	## Internal state.
	var _distance_since_last_footprint: float = 0.0
	var _last_position: Vector2 = Vector2.ZERO
	var _last_move_direction: Vector2 = Vector2.RIGHT
	var _is_left_foot: bool = true
	var _step_index: int = 0

	## Spawned footprints recorded for assertions.
	var spawned_footprints: Array = []

	## Simulated character position.
	var character_position: Vector2 = Vector2.ZERO

	## Simulated facing direction (no model — use movement direction).
	var _character_model: Object = null


	func ready(initial_pos: Vector2) -> void:
		_last_position = initial_pos
		character_position = initial_pos


	func process(new_pos: Vector2) -> void:
		var movement := new_pos - _last_position
		var distance := movement.length()
		character_position = new_pos

		if distance > 0.1:
			_last_move_direction = movement.normalized()
			_distance_since_last_footprint += distance

			if _distance_since_last_footprint >= step_distance:
				_spawn_footprint()
				_distance_since_last_footprint = 0.0

		_last_position = new_pos


	func _spawn_footprint() -> void:
		var steps_taken := _step_index % snow_steps_count
		var alpha := initial_alpha - steps_taken * alpha_decay_rate
		alpha = maxf(alpha, 0.05)

		var facing := _get_facing_direction()
		var perpendicular := facing.rotated(PI / 2.0)
		var foot_offset := 4.0 if _is_left_foot else -4.0
		var pos := character_position + perpendicular * foot_offset

		spawned_footprints.append({
			"position": pos,
			"rotation": facing.angle() + PI / 2.0,
			"alpha": alpha,
			"is_left": _is_left_foot,
		})

		_is_left_foot = not _is_left_foot
		_step_index += 1


	func _get_facing_direction() -> Vector2:
		return _last_move_direction


# ============================================================================
# Tests: Initial State
# ============================================================================


func test_no_footprints_at_start() -> void:
	var comp := MockSnowyFeetComponent.new()
	comp.ready(Vector2.ZERO)
	assert_eq(comp.spawned_footprints.size(), 0,
		"No footprints should be spawned at start (character has not moved)")


func test_distance_counter_zero_at_start() -> void:
	var comp := MockSnowyFeetComponent.new()
	comp.ready(Vector2(100, 200))
	assert_almost_eq(comp._distance_since_last_footprint, 0.0, 0.001,
		"Distance counter should be 0.0 before any movement")


# ============================================================================
# Tests: Footprint Spawning on Movement
# ============================================================================


func test_footprint_spawned_after_step_distance() -> void:
	var comp := MockSnowyFeetComponent.new()
	comp.ready(Vector2.ZERO)
	# Walk exactly step_distance pixels to the right.
	comp.process(Vector2(comp.step_distance, 0.0))
	assert_eq(comp.spawned_footprints.size(), 1,
		"One footprint should be spawned after walking step_distance pixels")


func test_no_footprint_before_step_distance() -> void:
	var comp := MockSnowyFeetComponent.new()
	comp.ready(Vector2.ZERO)
	comp.process(Vector2(comp.step_distance * 0.9, 0.0))
	assert_eq(comp.spawned_footprints.size(), 0,
		"No footprint before step_distance is reached")


func test_two_footprints_after_two_steps() -> void:
	var comp := MockSnowyFeetComponent.new()
	comp.ready(Vector2.ZERO)
	comp.process(Vector2(comp.step_distance, 0.0))
	comp.process(Vector2(comp.step_distance * 2.0, 0.0))
	assert_eq(comp.spawned_footprints.size(), 2,
		"Two footprints should be spawned after walking two step_distance increments")


func test_footprints_alternate_feet() -> void:
	var comp := MockSnowyFeetComponent.new()
	comp.ready(Vector2.ZERO)
	comp.process(Vector2(comp.step_distance, 0.0))
	comp.process(Vector2(comp.step_distance * 2.0, 0.0))
	var first_is_left: bool = comp.spawned_footprints[0]["is_left"]
	var second_is_left: bool = comp.spawned_footprints[1]["is_left"]
	assert_ne(first_is_left, second_is_left,
		"Consecutive footprints must alternate between left and right foot")


# ============================================================================
# Tests: Alpha Decay
# ============================================================================


func test_first_footprint_has_initial_alpha() -> void:
	var comp := MockSnowyFeetComponent.new()
	comp.ready(Vector2.ZERO)
	comp.process(Vector2(comp.step_distance, 0.0))
	assert_almost_eq(comp.spawned_footprints[0]["alpha"], comp.initial_alpha, 0.001,
		"First footprint alpha should equal initial_alpha")


func test_alpha_decreases_with_each_step() -> void:
	var comp := MockSnowyFeetComponent.new()
	comp.ready(Vector2.ZERO)
	for i in range(3):
		comp.process(Vector2(comp.step_distance * (i + 1), 0.0))
	var a0: float = comp.spawned_footprints[0]["alpha"]
	var a1: float = comp.spawned_footprints[1]["alpha"]
	var a2: float = comp.spawned_footprints[2]["alpha"]
	assert_true(a0 > a1, "Second footprint must be less opaque than the first")
	assert_true(a1 > a2, "Third footprint must be less opaque than the second")


func test_alpha_never_below_minimum() -> void:
	var comp := MockSnowyFeetComponent.new()
	comp.snow_steps_count = 4
	comp.initial_alpha = 0.2
	comp.alpha_decay_rate = 0.1
	comp.ready(Vector2.ZERO)
	for i in range(10):
		comp.process(Vector2(comp.step_distance * (i + 1), 0.0))
	for fp in comp.spawned_footprints:
		assert_true(fp["alpha"] >= 0.05,
			"Footprint alpha must never drop below the minimum of 0.05")


func test_alpha_wraps_at_snow_steps_count() -> void:
	# After snow_steps_count steps, alpha resets to initial_alpha (step_index wraps mod snow_steps_count).
	var comp := MockSnowyFeetComponent.new()
	comp.snow_steps_count = 4
	comp.ready(Vector2.ZERO)
	for i in range(5):
		comp.process(Vector2(comp.step_distance * (i + 1), 0.0))
	# Step index 4 wraps to 0 → same alpha as step index 0 (first footprint).
	var alpha_first: float = comp.spawned_footprints[0]["alpha"]
	var alpha_wrap: float = comp.spawned_footprints[4]["alpha"]
	assert_almost_eq(alpha_first, alpha_wrap, 0.001,
		"Alpha at step 4 (index 0 mod 4) should match the first footprint alpha")


# ============================================================================
# Tests: Foot Offset (Left / Right Lateral Offset)
# ============================================================================


func test_left_and_right_footprints_are_laterally_offset() -> void:
	var comp := MockSnowyFeetComponent.new()
	comp.ready(Vector2.ZERO)
	comp.process(Vector2(comp.step_distance, 0.0))
	comp.process(Vector2(comp.step_distance * 2.0, 0.0))
	var p1: Vector2 = comp.spawned_footprints[0]["position"]
	var p2: Vector2 = comp.spawned_footprints[1]["position"]
	# Both footprints should have the same X (moving right) but different Y.
	assert_almost_eq(p1.x, p2.x, 1.0,
		"Both footprints should be at roughly the same forward position")
	assert_ne(p1.y, p2.y,
		"Left and right footprints must be laterally offset from each other")


# ============================================================================
# Tests: Footprint Scale and Rotation
# ============================================================================


func test_footprint_rotation_aligns_with_movement() -> void:
	var comp := MockSnowyFeetComponent.new()
	comp.ready(Vector2.ZERO)
	# Walk downward (positive Y).
	comp.process(Vector2(0.0, comp.step_distance))
	var rotation: float = comp.spawned_footprints[0]["rotation"]
	# Facing direction is (0, 1) → angle = PI/2 → rotation = PI/2 + PI/2 = PI.
	assert_almost_eq(rotation, PI, 0.01,
		"Footprint rotation should align with movement direction + PI/2 offset")


# ============================================================================
# Tests: Stationary Character (No Footprints)
# ============================================================================


func test_no_footprint_when_stationary() -> void:
	var comp := MockSnowyFeetComponent.new()
	comp.ready(Vector2(100, 100))
	# Call process multiple times with the same position.
	for _i in range(5):
		comp.process(Vector2(100, 100))
	assert_eq(comp.spawned_footprints.size(), 0,
		"No footprints should appear when the character is not moving")


# ============================================================================
# Tests: Snow Surface Restriction (Issue #1627 fix)
# ============================================================================


class MockSnowyFeetComponentWithSnowCheck extends MockSnowyFeetComponent:
	## Simulated snow-surface state (true = on snow, false = on trail/non-snow).
	var is_on_snow: bool = true


	func _spawn_footprint() -> void:
		# Mirror the new guard added to SnowyFeetComponent._spawn_footprint().
		if not is_on_snow:
			return
		super._spawn_footprint()


func test_no_footprint_when_not_on_snow() -> void:
	var comp := MockSnowyFeetComponentWithSnowCheck.new()
	comp.is_on_snow = false
	comp.ready(Vector2.ZERO)
	comp.process(Vector2(comp.step_distance, 0.0))
	assert_eq(comp.spawned_footprints.size(), 0,
		"No snow footprint should be spawned when character is NOT on a snow surface")


func test_footprint_spawned_when_on_snow() -> void:
	var comp := MockSnowyFeetComponentWithSnowCheck.new()
	comp.is_on_snow = true
	comp.ready(Vector2.ZERO)
	comp.process(Vector2(comp.step_distance, 0.0))
	assert_eq(comp.spawned_footprints.size(), 1,
		"Snow footprint should be spawned when character IS on a snow surface")


func test_footprints_stop_when_leaving_snow() -> void:
	var comp := MockSnowyFeetComponentWithSnowCheck.new()
	comp.is_on_snow = true
	comp.ready(Vector2.ZERO)
	# Walk one step on snow.
	comp.process(Vector2(comp.step_distance, 0.0))
	assert_eq(comp.spawned_footprints.size(), 1, "One footprint on snow")

	# Character steps off snow onto trail.
	comp.is_on_snow = false
	comp.process(Vector2(comp.step_distance * 2.0, 0.0))
	assert_eq(comp.spawned_footprints.size(), 1,
		"No additional footprint after leaving snow surface")


func test_footprints_resume_when_re_entering_snow() -> void:
	var comp := MockSnowyFeetComponentWithSnowCheck.new()
	comp.is_on_snow = false
	comp.ready(Vector2.ZERO)
	comp.process(Vector2(comp.step_distance, 0.0))
	assert_eq(comp.spawned_footprints.size(), 0, "No footprint while off snow")

	comp.is_on_snow = true
	comp.process(Vector2(comp.step_distance * 2.0, 0.0))
	assert_eq(comp.spawned_footprints.size(), 1,
		"Footprint resumes once character returns to snow surface")


# ============================================================================
# Tests: Red Blood-Snow Footprints After Stepping in Blood (Issue #1627)
# ============================================================================


## Minimal mock for BloodyFeetComponent blood-level / blood-color query.
## Also emulates the blood_contact signal by exposing a notify_blood_contact()
## helper that tests can call to simulate the signal (Issue #1627 race-condition fix).
class MockBloodyFeet:
	var _blood_level: int = 0
	var _blood_color: Color = Color(0.545, 0.0, 0.0, 1.0)
	var snow_blood_steps_count: int = 4

	func has_bloody_feet() -> bool:
		return _blood_level > 0


class MockSnowyFeetComponentWithBloodCheck extends MockSnowyFeetComponentWithSnowCheck:
	## Simulated BloodyFeetComponent reference.
	var _bloody_feet: MockBloodyFeet = null
	var snow_blood_steps_count: int = 4
	## Counter armed by _on_blood_contact() signal handler (Issue #1627 race-condition fix).
	var _blood_snow_steps_remaining: int = 0

	## Tracks whether last spawned print was a blood print.
	var last_was_blood_print: bool = false


	## Mirrors SnowyFeetComponent._on_blood_contact(): arms counter immediately on signal.
	func on_blood_contact() -> void:
		var steps := snow_blood_steps_count
		if _bloody_feet and _bloody_feet.get("snow_blood_steps_count") != null:
			steps = _bloody_feet.snow_blood_steps_count
		_blood_snow_steps_remaining = steps


	func _spawn_footprint() -> void:
		if not is_on_snow:
			return

		# Counter is armed by on_blood_contact() — no lazy poll here (Issue #1627).
		var use_blood_print := _blood_snow_steps_remaining > 0
		last_was_blood_print = use_blood_print

		if use_blood_print:
			var total := snow_blood_steps_count
			if _bloody_feet and _bloody_feet.get("snow_blood_steps_count") != null:
				total = _bloody_feet.snow_blood_steps_count
			var steps_taken := total - _blood_snow_steps_remaining
			var alpha := initial_alpha - steps_taken * alpha_decay_rate
			alpha = maxf(alpha, 0.05)
			var facing := _get_facing_direction()
			var perpendicular := facing.rotated(PI / 2.0)
			var foot_offset := 4.0 if _is_left_foot else -4.0
			var pos := character_position + perpendicular * foot_offset
			spawned_footprints.append({
				"position": pos,
				"rotation": facing.angle() + PI / 2.0,
				"alpha": alpha,
				"is_left": _is_left_foot,
				"is_blood": true,
			})
			_is_left_foot = not _is_left_foot
			_blood_snow_steps_remaining -= 1
		else:
			# Normal white print.
			var steps_taken_white := _step_index % snow_steps_count
			var alpha := initial_alpha - steps_taken_white * alpha_decay_rate
			alpha = maxf(alpha, 0.05)
			var facing := _get_facing_direction()
			var perpendicular := facing.rotated(PI / 2.0)
			var foot_offset := 4.0 if _is_left_foot else -4.0
			var pos := character_position + perpendicular * foot_offset
			spawned_footprints.append({
				"position": pos,
				"rotation": facing.angle() + PI / 2.0,
				"alpha": alpha,
				"is_left": _is_left_foot,
				"is_blood": false,
			})
			_is_left_foot = not _is_left_foot
			_step_index += 1


func test_red_snow_footprint_when_character_has_blood() -> void:
	## After stepping in blood the next footprint on snow should be a blood print (Issue #1627).
	## The counter is armed via on_blood_contact() (signal), NOT lazily in _spawn_footprint().
	var comp := MockSnowyFeetComponentWithBloodCheck.new()
	comp.is_on_snow = true
	var bloody := MockBloodyFeet.new()
	bloody._blood_level = 4
	comp._bloody_feet = bloody
	comp.ready(Vector2.ZERO)
	# Simulate signal: blood contact fires before any step is taken.
	comp.on_blood_contact()
	comp.process(Vector2(comp.step_distance, 0.0))
	assert_eq(comp.spawned_footprints.size(), 1,
		"A footprint should be spawned when character has bloody feet on snow")
	assert_true(comp.spawned_footprints[0].get("is_blood", false),
		"The footprint should be a blood-snow print (red), not a plain white snow print")


func test_red_snow_footprint_even_when_blood_level_already_drained() -> void:
	## Regression test for the race condition (Issue #1627): red prints should appear
	## even if BloodyFeetComponent's _blood_level has been decremented to 0 before
	## SnowyFeetComponent's step fires, because the counter is armed by the signal.
	var comp := MockSnowyFeetComponentWithBloodCheck.new()
	comp.is_on_snow = true
	var bloody := MockBloodyFeet.new()
	bloody._blood_level = 4
	comp._bloody_feet = bloody
	comp.ready(Vector2.ZERO)
	# Arm counter via signal (before BloodyFeet drains its level).
	comp.on_blood_contact()
	# Simulate BloodyFeetComponent draining _blood_level to 0 before SnowyFeet steps.
	bloody._blood_level = 0
	# SnowyFeet step should still produce a red print because counter was armed.
	comp.process(Vector2(comp.step_distance, 0.0))
	assert_eq(comp.spawned_footprints.size(), 1, "A footprint should be spawned")
	assert_true(comp.spawned_footprints[0].get("is_blood", false),
		"Red print must appear even if BloodyFeetComponent blood level is already 0 "
		"(counter was armed by signal before depletion)")


func test_exactly_snow_blood_steps_count_red_prints() -> void:
	## Exactly snow_blood_steps_count (4) red prints, then white prints (Issue #1627).
	var comp := MockSnowyFeetComponentWithBloodCheck.new()
	comp.is_on_snow = true
	comp.snow_blood_steps_count = 4
	var bloody := MockBloodyFeet.new()
	bloody._blood_level = 4
	comp._bloody_feet = bloody
	comp.ready(Vector2.ZERO)
	# Arm counter via signal before walking.
	comp.on_blood_contact()

	for i in range(6):
		comp.process(Vector2(comp.step_distance * (i + 1), 0.0))

	assert_eq(comp.spawned_footprints.size(), 6,
		"Six footprints total should be spawned")
	var blood_count := 0
	var white_count := 0
	for fp in comp.spawned_footprints:
		if fp.get("is_blood", false):
			blood_count += 1
		else:
			white_count += 1
	assert_eq(blood_count, 4,
		"Exactly 4 red blood-snow prints should be spawned after stepping in blood")
	assert_eq(white_count, 2,
		"After 4 blood steps, normal white snow prints should resume")


func test_first_blood_print_has_highest_alpha() -> void:
	## First blood-snow print is most opaque; alpha decays over snow_blood_steps_count steps.
	var comp := MockSnowyFeetComponentWithBloodCheck.new()
	comp.is_on_snow = true
	comp.snow_blood_steps_count = 4
	var bloody := MockBloodyFeet.new()
	bloody._blood_level = 4
	comp._bloody_feet = bloody
	comp.ready(Vector2.ZERO)
	comp.on_blood_contact()

	for i in range(4):
		comp.process(Vector2(comp.step_distance * (i + 1), 0.0))

	assert_eq(comp.spawned_footprints.size(), 4, "Four blood prints spawned")
	var a0: float = comp.spawned_footprints[0]["alpha"]
	var a1: float = comp.spawned_footprints[1]["alpha"]
	var a2: float = comp.spawned_footprints[2]["alpha"]
	var a3: float = comp.spawned_footprints[3]["alpha"]
	assert_true(a0 > a1, "First blood print should be more opaque than second")
	assert_true(a1 > a2, "Second blood print should be more opaque than third")
	assert_true(a2 > a3, "Third blood print should be more opaque than fourth")


func test_white_snow_footprint_resumes_after_blood_runs_out() -> void:
	var comp := MockSnowyFeetComponentWithBloodCheck.new()
	comp.is_on_snow = true
	comp.snow_blood_steps_count = 4
	var bloody := MockBloodyFeet.new()
	bloody._blood_level = 4
	comp._bloody_feet = bloody
	comp.ready(Vector2.ZERO)
	comp.on_blood_contact()

	# Take 4 blood-stained steps.
	for i in range(4):
		comp.process(Vector2(comp.step_distance * (i + 1), 0.0))

	var step5 := Vector2(comp.step_distance * 5.0, 0.0)
	comp.process(step5)

	assert_eq(comp.spawned_footprints.size(), 5,
		"Five footprints total (4 blood + 1 white)")
	assert_false(comp.spawned_footprints[4].get("is_blood", true),
		"Fifth footprint should be a normal white snow print after blood runs out")
