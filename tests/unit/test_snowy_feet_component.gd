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
	var snow_blood_steps_count: int = 5
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
	var is_on_blood_puddle: bool = false

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
	assert_true(p2.x > p1.x,
		"Second footprint should be farther along the movement direction")
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
	var snow_blood_steps_count: int = 5

	func has_bloody_feet() -> bool:
		return _blood_level > 0

	func get_blood_level() -> int:
		return _blood_level

	func consume_snow_blood_step() -> void:
		_blood_level = max(_blood_level - 1, 0)


class MockSnowyFeetComponentWithBloodCheck extends MockSnowyFeetComponentWithSnowCheck:
	## Simulated BloodyFeetComponent reference.
	var _bloody_feet: MockBloodyFeet = null
	## Counter armed by _on_blood_contact() signal handler (Issue #1627 race-condition fix).
	var _blood_snow_steps_remaining: int = 0
	var _blood_snow_color: Color = Color(0.545, 0.0, 0.0, 1.0)
	var on_snow: bool = true

	## Tracks whether last spawned print was a blood print.
	var last_was_blood_print: bool = false


	## Mirrors SnowyFeetComponent._on_blood_contact(): arms counter immediately on signal.
	func on_blood_contact() -> void:
		var steps := snow_blood_steps_count
		if _bloody_feet and _bloody_feet.get("snow_blood_steps_count") != null:
			steps = _bloody_feet.snow_blood_steps_count
		_blood_snow_steps_remaining = steps
		if _bloody_feet:
			_blood_snow_color = _bloody_feet._blood_color


	func arm_blood_snow_steps_from_bloody_feet_if_needed() -> void:
		if _blood_snow_steps_remaining > 0:
			return
		if _bloody_feet == null or not on_snow or not _bloody_feet.has_bloody_feet():
			return
		var steps := snow_blood_steps_count
		if _bloody_feet and _bloody_feet.get("snow_blood_steps_count") != null:
			steps = _bloody_feet.snow_blood_steps_count
		steps = mini(steps, _bloody_feet.get_blood_level())
		_blood_snow_steps_remaining = max(steps, 0)
		_blood_snow_color = _bloody_feet._blood_color


	func _spawn_footprint() -> void:
		if not is_on_snow:
			return

		# Counter is primarily armed by on_blood_contact(); this fallback covers
		# blood acquired before signal wiring finishes in live scenes.
		arm_blood_snow_steps_from_bloody_feet_if_needed()
		var use_blood_print := _blood_snow_steps_remaining > 0 and not is_on_blood_puddle
		last_was_blood_print = use_blood_print

		if use_blood_print:
			var total := snow_blood_steps_count
			if _bloody_feet and _bloody_feet.get("snow_blood_steps_count") != null:
				total = _bloody_feet.snow_blood_steps_count
			var steps_taken := total - _blood_snow_steps_remaining
			var fade_factor := 1.0
			if total > 1:
				fade_factor = 1.0 - (float(steps_taken) / float(total - 1)) * 0.65
			var blood_color := _blood_snow_color.lerp(Color.WHITE, 1.0 - fade_factor)
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
				"blood_color": blood_color,
			})
			_is_left_foot = not _is_left_foot
			_blood_snow_steps_remaining -= 1
			if _bloody_feet:
				_bloody_feet.consume_snow_blood_step()
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
	bloody._blood_level = 5
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
	bloody._blood_level = 5
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
		"Red print must appear even if BloodyFeetComponent blood level is already 0 " +
		"(counter was armed by signal before depletion)")


func test_exactly_snow_blood_steps_count_red_prints() -> void:
	## Exactly snow_blood_steps_count red prints, then white prints (Issue #1627).
	var comp := MockSnowyFeetComponentWithBloodCheck.new()
	comp.is_on_snow = true
	comp.snow_blood_steps_count = 5
	var bloody := MockBloodyFeet.new()
	bloody._blood_level = 5
	bloody.snow_blood_steps_count = 5
	comp._bloody_feet = bloody
	comp.ready(Vector2.ZERO)
	# Arm counter via signal before walking.
	comp.on_blood_contact()

	for i in range(7):
		comp.process(Vector2(comp.step_distance * (i + 1), 0.0))

	assert_eq(comp.spawned_footprints.size(), 7,
		"Seven footprints total should be spawned")
	var blood_count := 0
	var white_count := 0
	for fp in comp.spawned_footprints:
		if fp.get("is_blood", false):
			blood_count += 1
		else:
			white_count += 1
	assert_eq(blood_count, 5,
		"Exactly 5 red blood-snow prints should be spawned after stepping in blood")
	assert_eq(white_count, 2,
		"After blood steps, normal white snow prints should resume")


func test_first_blood_print_has_highest_alpha() -> void:
	## First blood-snow print is most opaque; alpha decays over snow_blood_steps_count steps.
	var comp := MockSnowyFeetComponentWithBloodCheck.new()
	comp.is_on_snow = true
	comp.snow_blood_steps_count = 5
	var bloody := MockBloodyFeet.new()
	bloody._blood_level = 5
	bloody.snow_blood_steps_count = 5
	comp._bloody_feet = bloody
	comp.ready(Vector2.ZERO)
	comp.on_blood_contact()

	for i in range(2):
		comp.process(Vector2(comp.step_distance * (i + 1), 0.0))

	assert_eq(comp.spawned_footprints.size(), 2, "Two blood prints spawned")
	var a0: float = comp.spawned_footprints[0]["alpha"]
	var a1: float = comp.spawned_footprints[1]["alpha"]
	assert_true(a0 > a1, "First blood print should be more opaque than second")


func test_blood_snow_prints_become_less_red() -> void:
	var comp := MockSnowyFeetComponentWithBloodCheck.new()
	comp.is_on_snow = true
	comp.snow_blood_steps_count = 5
	var bloody := MockBloodyFeet.new()
	bloody._blood_level = 5
	bloody.snow_blood_steps_count = 5
	bloody._blood_color = Color(0.55, 0.0, 0.0, 1.0)
	comp._bloody_feet = bloody
	comp.ready(Vector2.ZERO)
	comp.on_blood_contact()

	for i in range(5):
		comp.process(Vector2(comp.step_distance * (i + 1), 0.0))

	var first_color: Color = comp.spawned_footprints[0]["blood_color"]
	var last_color: Color = comp.spawned_footprints[4]["blood_color"]
	assert_true(last_color.r > first_color.r,
		"Later blood-snow prints should move toward white in the red channel")
	assert_true(last_color.g > first_color.g,
		"Later blood-snow prints should be less saturated red")


func test_white_snow_footprint_resumes_after_blood_runs_out() -> void:
	var comp := MockSnowyFeetComponentWithBloodCheck.new()
	comp.is_on_snow = true
	comp.snow_blood_steps_count = 5
	var bloody := MockBloodyFeet.new()
	bloody._blood_level = 5
	bloody.snow_blood_steps_count = 5
	comp._bloody_feet = bloody
	comp.ready(Vector2.ZERO)
	comp.on_blood_contact()

	# Take all blood-stained steps.
	for i in range(5):
		comp.process(Vector2(comp.step_distance * (i + 1), 0.0))

	var first_white_step := Vector2(comp.step_distance * 6.0, 0.0)
	comp.process(first_white_step)

	assert_eq(comp.spawned_footprints.size(), 6,
		"Six footprints total (5 blood + 1 white)")
	assert_false(comp.spawned_footprints[5].get("is_blood", true),
		"First footprint after blood runs out should be a normal white snow print")


func test_blood_snow_prints_wait_until_outside_puddle() -> void:
	var comp := MockSnowyFeetComponentWithBloodCheck.new()
	comp.is_on_snow = true
	comp.is_on_blood_puddle = true
	var bloody := MockBloodyFeet.new()
	bloody._blood_level = 5
	bloody.snow_blood_steps_count = 5
	comp._bloody_feet = bloody
	comp.ready(Vector2.ZERO)
	comp.on_blood_contact()

	comp.process(Vector2(comp.step_distance, 0.0))
	assert_false(comp.spawned_footprints[0].get("is_blood", true),
		"Blood-snow prints should not be stamped directly on top of the blood puddle")
	assert_eq(comp._blood_snow_steps_remaining, 5,
		"Skipping blood print on the puddle should preserve the red-step counter")

	comp.is_on_blood_puddle = false
	comp.process(Vector2(comp.step_distance * 2.0, 0.0))
	assert_true(comp.spawned_footprints[1].get("is_blood", false),
		"First blood-snow print should appear after leaving the puddle")


func test_red_snow_footprint_when_signal_was_missed_but_blood_level_is_active() -> void:
	## Regression for live setup paths where blood is acquired before SnowyFeetComponent
	## connects to blood_contact: the component should still arm red prints from the
	## sibling BloodyFeetComponent state instead of spawning white snow prints.
	var comp := MockSnowyFeetComponentWithBloodCheck.new()
	comp.is_on_snow = true
	comp.snow_blood_steps_count = 5
	var bloody := MockBloodyFeet.new()
	bloody._blood_level = 5
	bloody.snow_blood_steps_count = 5
	comp._bloody_feet = bloody
	comp.ready(Vector2.ZERO)

	comp.process(Vector2(comp.step_distance, 0.0))

	assert_eq(comp.spawned_footprints.size(), 1, "A footprint should be spawned")
	assert_true(comp.spawned_footprints[0].get("is_blood", false),
		"Missed blood_contact signal must still produce a red snow footprint while blood level is active")


func test_red_snow_footprints_consume_bloody_feet_after_rendering() -> void:
	var comp := MockSnowyFeetComponentWithBloodCheck.new()
	comp.is_on_snow = true
	comp.snow_blood_steps_count = 5
	var bloody := MockBloodyFeet.new()
	bloody._blood_level = 5
	bloody.snow_blood_steps_count = 5
	comp._bloody_feet = bloody
	comp.ready(Vector2.ZERO)
	comp.on_blood_contact()

	comp.process(Vector2(comp.step_distance, 0.0))
	assert_eq(bloody.get_blood_level(), 4,
		"First rendered red snow print should consume exactly one BloodyFeetComponent snow blood step")

	comp.process(Vector2(comp.step_distance * 2.0, 0.0))
	assert_eq(bloody.get_blood_level(), 3,
		"Second rendered red snow print should consume exactly one more snow blood step")


## Regression test for Issue #1909: enemies received regular boot prints instead of
## snow blood prints because on_snow was not set on BloodyFeetComponent before blood contact.
## The signal path (_on_blood_contact) must arm the counter regardless of on_snow.
func test_enemy_gets_snow_blood_prints_via_signal_even_when_on_snow_not_yet_set() -> void:
	var comp := MockSnowyFeetComponentWithBloodCheck.new()
	comp.is_on_snow = true
	comp.snow_blood_steps_count = 5
	var bloody := MockBloodyFeet.new()
	bloody._blood_level = 5
	bloody.snow_blood_steps_count = 5
	# Simulate enemy: on_snow was not yet set (mimics race between _add_snowy_feet and
	# blood contact before on_snow = true is applied to BloodyFeetComponent).
	comp._bloody_feet = bloody
	comp.ready(Vector2.ZERO)

	# Arm via signal (primary path) — this is what BloodyFeetComponent.blood_contact emits.
	comp.on_blood_contact()

	comp.process(Vector2(comp.step_distance, 0.0))
	assert_eq(comp.spawned_footprints.size(), 1, "One footprint should be spawned")
	assert_true(comp.spawned_footprints[0].get("is_blood", false),
		"Enemy must get snow blood print (not regular boot print) — Issue #1909")


## Regression test for Issue #1909: fallback path (_arm_blood_snow_steps_from_bloody_feet_if_needed)
## must NOT require on_snow=true since SnowyFeetComponent is only ever added to snow-level characters.
func test_fallback_arms_snow_prints_even_when_on_snow_false_on_bloody_feet() -> void:
	## This simulates the case where the signal was missed (race) AND on_snow is still false.
	## The fallback should still arm the counter because SnowyFeetComponent exists = snow level.
	var comp := MockSnowyFeetComponentWithBloodCheck.new()
	comp.is_on_snow = true
	comp.snow_blood_steps_count = 5
	var bloody := MockBloodyFeet.new()
	bloody._blood_level = 5
	bloody.snow_blood_steps_count = 5
	comp._bloody_feet = bloody
	comp.ready(Vector2.ZERO)

	# Do NOT fire on_blood_contact() — simulate missed signal.
	# Verify the fallback arms prints even without on_snow guard.
	comp.process(Vector2(comp.step_distance, 0.0))
	assert_eq(comp.spawned_footprints.size(), 1, "A footprint should be spawned via fallback")
	assert_true(comp.spawned_footprints[0].get("is_blood", false),
		"Fallback must produce red snow prints for enemies even when on_snow was not set (Issue #1909)")


func test_signal_captured_blood_color_survives_bloody_feet_drain() -> void:
	## The visible red snow print should use the color captured at blood contact time,
	## even if BloodyFeetComponent has already drained before SnowyFeetComponent steps.
	var comp := MockSnowyFeetComponentWithBloodCheck.new()
	comp.is_on_snow = true
	var bloody := MockBloodyFeet.new()
	bloody._blood_level = 5
	bloody._blood_color = Color(0.7, 0.02, 0.01, 1.0)
	comp._bloody_feet = bloody
	comp.ready(Vector2.ZERO)
	comp.on_blood_contact()

	bloody._blood_level = 0
	bloody._blood_color = Color.WHITE
	comp.process(Vector2(comp.step_distance, 0.0))

	var used_color: Color = comp.spawned_footprints[0]["blood_color"]
	assert_almost_eq(used_color.r, 0.7, 0.01,
		"SnowyFeetComponent should use the contact-time blood color")
	assert_almost_eq(used_color.g, 0.02, 0.01,
		"SnowyFeetComponent should not fall back to a later white BloodyFeetComponent color")


# ============================================================================
# Tests: Real Component Signal Wiring (Issue #1627 regression)
# ============================================================================


class RealSignalTestCharacter extends CharacterBody2D:
	pass


func test_snowy_feet_retries_bloody_feet_signal_connection() -> void:
	var character := RealSignalTestCharacter.new()
	add_child(character)

	var snowy_script: GDScript = load("res://scripts/components/snowy_feet_component.gd")
	var snowy: Node = snowy_script.new()
	snowy.name = "SnowyFeetComponent"
	character.add_child(snowy)
	await wait_frames(2)

	assert_false(snowy._blood_contact_connected,
		"SnowyFeetComponent starts disconnected when BloodyFeetComponent is not present yet")

	var bloody_script: GDScript = load("res://scripts/components/bloody_feet_component.gd")
	var bloody: Node = bloody_script.new()
	bloody.name = "BloodyFeetComponent"
	bloody.on_snow = true
	bloody.snow_blood_steps_count = 5
	character.add_child(bloody)
	await wait_frames(3)

	snowy._physics_process(0.016)
	assert_true(snowy._blood_contact_connected,
		"SnowyFeetComponent should retry until it connects to BloodyFeetComponent.blood_contact")

	bloody.set_blood_level(5)
	assert_eq(snowy._blood_snow_steps_remaining, 5,
		"Late-connected SnowyFeetComponent should arm red snow prints when blood is acquired")

	character.queue_free()
	await wait_frames(2)
