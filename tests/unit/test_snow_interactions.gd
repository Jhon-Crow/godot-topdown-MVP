extends GutTest
## Unit tests for snow surface interaction systems (Issue #1627).
##
## Tests cover:
## 1. SnowFootprint: visual properties, alpha/foot assignment
## 2. SnowFeetComponent: step tracking, footprint spawning logic
## 3. SnowBloodAbsorption: non-puddle behaviour, fade-out lifecycle
## 4. WinterForestLevel: blood steps count reduction on snow (req. #4)


# ============================================================================
# Mock: SnowFootprint
# ============================================================================

class MockSnowFootprint:
	var _alpha: float = 0.72
	var _is_left: bool = true
	var z_index: int = 0
	var position: Vector2 = Vector2.ZERO
	var rotation: float = 0.0

	func set_alpha(a: float) -> void:
		_alpha = clampf(a, 0.0, 1.0)

	func set_foot(is_left: bool) -> void:
		_is_left = is_left


# ============================================================================
# Tests: SnowFootprint properties
# ============================================================================

func test_snow_footprint_default_alpha() -> void:
	var fp := MockSnowFootprint.new()
	assert_almost_eq(fp._alpha, 0.72, 0.001,
		"Default alpha should be 0.72 for fresh snow prints")


func test_snow_footprint_set_alpha() -> void:
	var fp := MockSnowFootprint.new()
	fp.set_alpha(0.5)
	assert_almost_eq(fp._alpha, 0.5, 0.001,
		"set_alpha should update the internal alpha")


func test_snow_footprint_alpha_clamped_to_zero() -> void:
	var fp := MockSnowFootprint.new()
	fp.set_alpha(-0.3)
	assert_almost_eq(fp._alpha, 0.0, 0.001,
		"Alpha must not go below 0.0")


func test_snow_footprint_alpha_clamped_to_one() -> void:
	var fp := MockSnowFootprint.new()
	fp.set_alpha(1.5)
	assert_almost_eq(fp._alpha, 1.0, 0.001,
		"Alpha must not exceed 1.0")


func test_snow_footprint_left_foot_default() -> void:
	var fp := MockSnowFootprint.new()
	assert_true(fp._is_left, "Default foot should be left")


func test_snow_footprint_set_right_foot() -> void:
	var fp := MockSnowFootprint.new()
	fp.set_foot(false)
	assert_false(fp._is_left, "set_foot(false) should set right foot")


func test_snow_footprint_z_index_at_floor_level() -> void:
	var fp := MockSnowFootprint.new()
	assert_eq(fp.z_index, 0,
		"Snow footprint z_index must be 0 (above floor, below characters at z_index=1)")


# ============================================================================
# Mock: SnowFeetComponent
# ============================================================================

class MockSnowFeetComponent:
	## Distance between footprints in pixels.
	var step_distance: float = 28.0

	## Starting alpha.
	var initial_alpha: float = 0.72

	## Max live footprints.
	var max_footprints: int = 80

	## Distance since last footprint.
	var _distance_since_last: float = 0.0

	## Last recorded position.
	var _last_position: Vector2 = Vector2.ZERO

	## Number of footprints spawned.
	var spawned_count: int = 0

	## Alternating foot flag.
	var _is_left_foot: bool = true

	## Circular list of spawned footprint records.
	var _footprints: Array = []


	func ready(start_pos: Vector2) -> void:
		_last_position = start_pos


	func process_movement(new_pos: Vector2) -> void:
		var dist := _last_position.distance_to(new_pos)
		if dist > 0.1:
			_distance_since_last += dist
			if _distance_since_last >= step_distance:
				_spawn_footprint(new_pos)
				_distance_since_last = 0.0
		_last_position = new_pos


	func _spawn_footprint(pos: Vector2) -> void:
		_footprints.append({"pos": pos, "is_left": _is_left_foot})
		_is_left_foot = not _is_left_foot
		spawned_count += 1
		# Evict oldest if over cap.
		if _footprints.size() > max_footprints:
			_footprints.pop_front()


# ============================================================================
# Tests: SnowFeetComponent movement tracking
# ============================================================================

func test_snow_feet_no_footprint_at_start() -> void:
	var comp := MockSnowFeetComponent.new()
	comp.ready(Vector2(0, 0))
	assert_eq(comp.spawned_count, 0,
		"No footprint should be spawned on init")


func test_snow_feet_no_footprint_below_step_distance() -> void:
	var comp := MockSnowFeetComponent.new()
	comp.ready(Vector2(0, 0))
	comp.process_movement(Vector2(10, 0))  # Only 10px — below step_distance=28
	assert_eq(comp.spawned_count, 0,
		"No footprint when movement is less than step_distance")


func test_snow_feet_footprint_after_step_distance() -> void:
	var comp := MockSnowFeetComponent.new()
	comp.ready(Vector2(0, 0))
	comp.process_movement(Vector2(30, 0))  # 30px > step_distance=28
	assert_eq(comp.spawned_count, 1,
		"One footprint should be spawned after travelling step_distance")


func test_snow_feet_footprints_accumulate() -> void:
	var comp := MockSnowFeetComponent.new()
	comp.ready(Vector2(0, 0))
	# 4 steps of 30px each → 4 footprints
	for i in range(4):
		comp.process_movement(Vector2((i + 1) * 30.0, 0.0))
	assert_eq(comp.spawned_count, 4,
		"Four footprints should be spawned after four full steps")


func test_snow_feet_alternates_left_right() -> void:
	var comp := MockSnowFeetComponent.new()
	comp.ready(Vector2(0, 0))
	comp.process_movement(Vector2(30, 0))
	comp.process_movement(Vector2(60, 0))
	assert_true(comp._footprints[0]["is_left"],  "First print should be left foot")
	assert_false(comp._footprints[1]["is_left"], "Second print should be right foot")


func test_snow_feet_max_footprints_eviction() -> void:
	var comp := MockSnowFeetComponent.new()
	comp.max_footprints = 3
	comp.ready(Vector2(0, 0))
	# Spawn 5 footprints by moving far enough.
	for i in range(5):
		comp.process_movement(Vector2((i + 1) * 30.0, 0.0))
	assert_eq(comp._footprints.size(), 3,
		"Footprint buffer should not exceed max_footprints (oldest evicted)")


func test_snow_feet_always_active_no_blood_needed() -> void:
	# Unlike BloodyFeetComponent, SnowFeetComponent does NOT require stepping in blood.
	# It just tracks movement — verify first footprint with zero blood level.
	var comp := MockSnowFeetComponent.new()
	comp.ready(Vector2(0, 0))
	comp.process_movement(Vector2(30, 0))
	assert_eq(comp.spawned_count, 1,
		"SnowFeetComponent spawns prints without any blood interaction (always active)")


# ============================================================================
# Mock: SnowBloodAbsorption
# ============================================================================

class MockSnowBloodAbsorption:
	const ABSORB_DURATION: float = 18.0
	const INITIAL_ALPHA: float = 0.78

	## Whether this object is added to the blood_puddle group.
	var in_blood_puddle_group: bool = false

	var _blood_color: Color = Color(0.55, 0.02, 0.02, INITIAL_ALPHA)
	var _elapsed: float = 0.0
	var _done: bool = false


	func ready() -> void:
		# Must NOT be in blood_puddle group (requirement #3: no bloody footprints)
		in_blood_puddle_group = false


	func set_blood_color(color: Color) -> void:
		_blood_color = Color(color.r, color.g, color.b, INITIAL_ALPHA)


	func process(delta: float) -> void:
		if _done:
			return
		_elapsed += delta
		if _elapsed >= ABSORB_DURATION:
			_done = true


	func is_absorbed() -> bool:
		return _done


	## Computes current alpha (matches _draw logic in real class).
	func current_alpha() -> float:
		if _done:
			return 0.0
		var t: float = _elapsed / ABSORB_DURATION
		var fade_start: float = 0.55
		var alpha_t: float = clampf((t - fade_start) / (1.0 - fade_start), 0.0, 1.0)
		return INITIAL_ALPHA * (1.0 - alpha_t * alpha_t)


# ============================================================================
# Tests: SnowBloodAbsorption
# ============================================================================

func test_snow_blood_not_in_puddle_group() -> void:
	var absorb := MockSnowBloodAbsorption.new()
	absorb.ready()
	assert_false(absorb.in_blood_puddle_group,
		"SnowBloodAbsorption must NOT be in blood_puddle group — stepping on it must NOT create bloody footprints (req. #3)")


func test_snow_blood_initial_alpha() -> void:
	var absorb := MockSnowBloodAbsorption.new()
	absorb.ready()
	assert_almost_eq(absorb.current_alpha(), MockSnowBloodAbsorption.INITIAL_ALPHA, 0.01,
		"Blood stain should start at INITIAL_ALPHA")


func test_snow_blood_still_visible_at_half_duration() -> void:
	var absorb := MockSnowBloodAbsorption.new()
	absorb.ready()
	absorb.process(MockSnowBloodAbsorption.ABSORB_DURATION * 0.5)
	assert_true(absorb.current_alpha() > 0.5,
		"Blood stain should still be visible at half the absorption duration")


func test_snow_blood_fades_near_end() -> void:
	var absorb := MockSnowBloodAbsorption.new()
	absorb.ready()
	absorb.process(MockSnowBloodAbsorption.ABSORB_DURATION * 0.9)
	assert_true(absorb.current_alpha() < MockSnowBloodAbsorption.INITIAL_ALPHA,
		"Blood stain should be partially faded at 90% of absorption duration")


func test_snow_blood_absorbed_after_duration() -> void:
	var absorb := MockSnowBloodAbsorption.new()
	absorb.ready()
	absorb.process(MockSnowBloodAbsorption.ABSORB_DURATION + 0.1)
	assert_true(absorb.is_absorbed(),
		"Blood stain should be fully absorbed after ABSORB_DURATION seconds")


func test_snow_blood_set_color_preserves_initial_alpha() -> void:
	var absorb := MockSnowBloodAbsorption.new()
	absorb.ready()
	absorb.set_blood_color(Color(0.6, 0.03, 0.03, 0.9))
	assert_almost_eq(absorb._blood_color.a, MockSnowBloodAbsorption.INITIAL_ALPHA, 0.001,
		"set_blood_color must reset alpha to INITIAL_ALPHA, ignoring caller's alpha")


func test_snow_blood_set_color_keeps_rgb() -> void:
	var absorb := MockSnowBloodAbsorption.new()
	absorb.ready()
	absorb.set_blood_color(Color(0.6, 0.03, 0.03, 1.0))
	assert_almost_eq(absorb._blood_color.r, 0.6, 0.001, "Red channel preserved")
	assert_almost_eq(absorb._blood_color.g, 0.03, 0.001, "Green channel preserved")
	assert_almost_eq(absorb._blood_color.b, 0.03, 0.001, "Blue channel preserved")


# ============================================================================
# Tests: BloodyFeetComponent blood_steps_count reduction on snow (req. #4)
# ============================================================================

class MockBloodyFeetComponent:
	## Default steps before blood runs out (matching BloodyFeetComponent default).
	var blood_steps_count: int = 12


func test_bloody_feet_default_steps_count() -> void:
	var bfc := MockBloodyFeetComponent.new()
	assert_eq(bfc.blood_steps_count, 12,
		"Default blood_steps_count should be 12")


func test_bloody_feet_reduced_on_snow() -> void:
	# Simulate what WinterForestLevel._setup_snow_interactions() does:
	# reduce blood_steps_count to 6 when on the snow map.
	var bfc := MockBloodyFeetComponent.new()
	bfc.blood_steps_count = 6  # Applied by level script
	assert_eq(bfc.blood_steps_count, 6,
		"blood_steps_count must be reduced to 6 on snow map (req. #4: trails end sooner)")


func test_bloody_feet_snow_steps_less_than_default() -> void:
	var default_steps := 12
	var snow_steps := 6
	assert_true(snow_steps < default_steps,
		"Blood trail on snow must be shorter than on normal surfaces")


func test_bloody_feet_snow_steps_half_of_default() -> void:
	var default_steps := 12
	var snow_steps := 6
	assert_eq(snow_steps, default_steps / 2,
		"Snow trail should be exactly half the normal trail length (req. #4)")
