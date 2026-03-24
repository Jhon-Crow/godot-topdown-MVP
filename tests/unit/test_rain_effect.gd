extends GutTest
## Unit tests for rain_effect.gd HM2-style precipitation system (Issue #1394).
##
## Tests rain episode scheduling, exclusion zone logic, and state transitions.
## The actual RainEffect extends Node2D with two child GPUParticles2D layers
## (vertical streaks + splash ripples). Uses a mock to test logic without
## requiring GPUParticles2D rendering.


# ============================================================================
# Mock RainEffect for Logic Tests
# ============================================================================


class MockRainEffect:
	## Minimum seconds between rain episodes.
	var min_interval: float = 15.0

	## Maximum seconds between rain episodes.
	var max_interval: float = 45.0

	## Minimum duration of a rain episode in seconds.
	var min_duration: float = 15.0

	## Maximum duration of a rain episode in seconds.
	var max_duration: float = 40.0

	## Whether rain starts immediately.
	var start_raining: bool = true

	## Seconds before the very first rain episode.
	var initial_delay: float = 0.0

	## Indoor exclusion zones.
	var exclusion_zones: Array = []

	## Whether currently emitting particles.
	var emitting: bool = false

	## Whether rain episode is active.
	var _episode_active: bool = false

	## Whether inside an exclusion zone.
	var _inside_exclusion: bool = false

	## Whether schedule timer was started.
	var schedule_timer_started: bool = false

	## Whether duration timer was started.
	var duration_timer_started: bool = false

	## Last schedule wait time.
	var last_schedule_wait: float = -1.0

	## Last duration time.
	var last_duration_time: float = -1.0


	func ready() -> void:
		emitting = false
		if start_raining:
			_start_rain_episode()
		else:
			_schedule_next_episode()


	func add_exclusion_zone(rect: Rect2) -> void:
		exclusion_zones.append(rect)


	func clear_exclusion_zones() -> void:
		exclusion_zones.clear()


	func is_raining() -> bool:
		return _episode_active and not _inside_exclusion


	func _is_point_in_exclusion_zone(point: Vector2) -> bool:
		for zone in exclusion_zones:
			if zone.has_point(point):
				return true
		return false


	func _schedule_next_episode() -> void:
		var wait_time := randf_range(min_interval, max_interval)
		last_schedule_wait = wait_time
		schedule_timer_started = true


	func _start_rain_episode() -> void:
		_episode_active = true
		if not _inside_exclusion:
			emitting = true
		var duration := randf_range(min_duration, max_duration)
		last_duration_time = duration
		duration_timer_started = true
		schedule_timer_started = false


	func _stop_rain_episode() -> void:
		_episode_active = false
		emitting = false
		_schedule_next_episode()


	func simulate_camera_move(camera_center: Vector2) -> void:
		var was_inside := _inside_exclusion
		_inside_exclusion = _is_point_in_exclusion_zone(camera_center)
		if _episode_active:
			if _inside_exclusion and not was_inside:
				emitting = false
			elif not _inside_exclusion and was_inside:
				emitting = true


# ============================================================================
# Tests
# ============================================================================


func test_initial_state_not_emitting() -> void:
	var rain := MockRainEffect.new()
	rain.start_raining = false
	rain.ready()
	assert_false(rain.emitting, "Rain should not emit initially when start_raining is false")
	assert_false(rain._episode_active, "No episode should be active initially when start_raining is false")


func test_start_raining_flag() -> void:
	var rain := MockRainEffect.new()
	rain.ready()
	assert_true(rain.emitting, "Rain should emit when start_raining is true (default)")
	assert_true(rain._episode_active, "Episode should be active when start_raining is true (default)")


func test_schedule_timer_started_on_ready() -> void:
	var rain := MockRainEffect.new()
	rain.start_raining = false
	rain.ready()
	assert_true(rain.schedule_timer_started, "Schedule timer should start on ready when start_raining is false")


func test_schedule_wait_within_range() -> void:
	var rain := MockRainEffect.new()
	rain.start_raining = false
	rain.min_interval = 10.0
	rain.max_interval = 20.0
	rain.ready()
	assert_gte(rain.last_schedule_wait, 10.0, "Wait should be >= min_interval")
	assert_lte(rain.last_schedule_wait, 20.0, "Wait should be <= max_interval")


func test_start_episode_enables_emitting() -> void:
	var rain := MockRainEffect.new()
	rain.start_raining = false
	rain.ready()
	rain._start_rain_episode()
	assert_true(rain.emitting, "Rain should emit during episode")
	assert_true(rain._episode_active, "Episode should be active")
	assert_true(rain.duration_timer_started, "Duration timer should start")


func test_stop_episode_disables_emitting() -> void:
	var rain := MockRainEffect.new()
	rain.start_raining = false
	rain.ready()
	rain._start_rain_episode()
	rain._stop_rain_episode()
	assert_false(rain.emitting, "Rain should not emit after episode ends")
	assert_false(rain._episode_active, "Episode should not be active after stop")
	assert_true(rain.schedule_timer_started, "Schedule timer should restart after episode")


func test_duration_within_range() -> void:
	var rain := MockRainEffect.new()
	rain.start_raining = false
	rain.min_duration = 5.0
	rain.max_duration = 15.0
	rain.ready()
	rain._start_rain_episode()
	assert_gte(rain.last_duration_time, 5.0, "Duration should be >= min_duration")
	assert_lte(rain.last_duration_time, 15.0, "Duration should be <= max_duration")


func test_add_exclusion_zone() -> void:
	var rain := MockRainEffect.new()
	rain.add_exclusion_zone(Rect2(100, 100, 200, 200))
	assert_eq(rain.exclusion_zones.size(), 1, "Should have 1 exclusion zone")


func test_clear_exclusion_zones() -> void:
	var rain := MockRainEffect.new()
	rain.add_exclusion_zone(Rect2(100, 100, 200, 200))
	rain.add_exclusion_zone(Rect2(500, 500, 300, 300))
	rain.clear_exclusion_zones()
	assert_eq(rain.exclusion_zones.size(), 0, "All exclusion zones should be cleared")


func test_point_inside_exclusion_zone() -> void:
	var rain := MockRainEffect.new()
	rain.add_exclusion_zone(Rect2(100, 100, 200, 200))
	assert_true(rain._is_point_in_exclusion_zone(Vector2(150, 150)),
		"Point inside zone should be detected")


func test_point_outside_exclusion_zone() -> void:
	var rain := MockRainEffect.new()
	rain.add_exclusion_zone(Rect2(100, 100, 200, 200))
	assert_false(rain._is_point_in_exclusion_zone(Vector2(50, 50)),
		"Point outside zone should not be detected")


func test_point_on_zone_boundary() -> void:
	var rain := MockRainEffect.new()
	rain.add_exclusion_zone(Rect2(100, 100, 200, 200))
	assert_true(rain._is_point_in_exclusion_zone(Vector2(100, 100)),
		"Point on zone boundary (top-left) should be inside")


func test_multiple_exclusion_zones() -> void:
	var rain := MockRainEffect.new()
	rain.add_exclusion_zone(Rect2(100, 100, 200, 200))
	rain.add_exclusion_zone(Rect2(500, 500, 300, 300))
	assert_true(rain._is_point_in_exclusion_zone(Vector2(600, 600)),
		"Point in second zone should be detected")
	assert_false(rain._is_point_in_exclusion_zone(Vector2(400, 400)),
		"Point between zones should not be detected")


func test_rain_stops_when_entering_building() -> void:
	var rain := MockRainEffect.new()
	rain.ready()
	assert_true(rain.emitting, "Rain should emit outside buildings")

	# Move camera into exclusion zone
	rain.add_exclusion_zone(Rect2(100, 100, 200, 200))
	rain.simulate_camera_move(Vector2(150, 150))
	assert_false(rain.emitting, "Rain should stop inside building")
	assert_true(rain._episode_active, "Episode should still be active inside building")


func test_rain_resumes_when_leaving_building() -> void:
	var rain := MockRainEffect.new()
	rain.add_exclusion_zone(Rect2(100, 100, 200, 200))
	rain.ready()

	# Enter building
	rain.simulate_camera_move(Vector2(150, 150))
	assert_false(rain.emitting, "Rain should stop inside building")

	# Leave building
	rain.simulate_camera_move(Vector2(50, 50))
	assert_true(rain.emitting, "Rain should resume after leaving building")


func test_is_raining_returns_false_when_no_episode() -> void:
	var rain := MockRainEffect.new()
	rain.start_raining = false
	rain.ready()
	assert_false(rain.is_raining(), "is_raining should be false when no episode")


func test_is_raining_returns_true_during_episode_outside() -> void:
	var rain := MockRainEffect.new()
	rain.ready()
	assert_true(rain.is_raining(), "is_raining should be true during episode outside (starts immediately)")


func test_is_raining_returns_false_during_episode_inside_building() -> void:
	var rain := MockRainEffect.new()
	rain.add_exclusion_zone(Rect2(100, 100, 200, 200))
	rain.ready()
	rain.simulate_camera_move(Vector2(150, 150))
	assert_false(rain.is_raining(), "is_raining should be false inside building during episode")


func test_episode_does_not_emit_when_starting_inside_building() -> void:
	var rain := MockRainEffect.new()
	rain.add_exclusion_zone(Rect2(100, 100, 200, 200))
	rain._inside_exclusion = true
	rain.ready()
	rain._start_rain_episode()
	assert_false(rain.emitting, "Should not emit when starting episode inside building")
	assert_true(rain._episode_active, "Episode should still be active")


func test_warehouse_a_exclusion_zone() -> void:
	var rain := MockRainEffect.new()
	# WarehouseA: position (400, 1800), walls extend ±270x, ±320y
	var warehouse_a := Rect2(400 - 270, 1800 - 320, 540, 640)
	rain.add_exclusion_zone(warehouse_a)

	# Center of WarehouseA
	assert_true(rain._is_point_in_exclusion_zone(Vector2(400, 1800)),
		"Center of WarehouseA should be in zone")
	# Outside WarehouseA
	assert_false(rain._is_point_in_exclusion_zone(Vector2(800, 1800)),
		"Point east of WarehouseA should not be in zone")


func test_warehouse_b_exclusion_zone() -> void:
	var rain := MockRainEffect.new()
	# WarehouseB: position (4400, 2800), walls extend ±370x, ±420y
	var warehouse_b := Rect2(4400 - 370, 2800 - 420, 740, 840)
	rain.add_exclusion_zone(warehouse_b)

	# Center of WarehouseB
	assert_true(rain._is_point_in_exclusion_zone(Vector2(4400, 2800)),
		"Center of WarehouseB should be in zone")
	# Outside WarehouseB
	assert_false(rain._is_point_in_exclusion_zone(Vector2(3900, 2800)),
		"Point west of WarehouseB should not be in zone")


func test_episode_cycle() -> void:
	var rain := MockRainEffect.new()
	rain.start_raining = false
	rain.ready()
	assert_false(rain._episode_active, "Initially no episode")
	assert_true(rain.schedule_timer_started, "Schedule started")

	# Simulate schedule timeout
	rain._start_rain_episode()
	assert_true(rain._episode_active, "Episode active after schedule timeout")
	assert_true(rain.emitting, "Emitting during episode")

	# Simulate duration timeout
	rain._stop_rain_episode()
	assert_false(rain._episode_active, "Episode ended after duration timeout")
	assert_false(rain.emitting, "Not emitting after episode ends")
	assert_true(rain.schedule_timer_started, "Schedule restarted for next episode")
