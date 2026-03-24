extends GutTest
## Unit tests for SoundVisualizer autoload.
##
## Tests event lifetime constants, event aging logic,
## MAX_EVENTS limit, and color coding by source type.


# ============================================================================
# Mock SoundVisualizer
# ============================================================================


class MockSoundEvent:
	var position: Vector2
	var max_radius: float
	var color: Color
	var age: float
	var label: String

	func _init(pos: Vector2, radius: float, col: Color, lbl: String) -> void:
		position = pos
		max_radius = radius
		color = col
		age = 0.0
		label = lbl


class MockSoundVisualizer:
	## Timing constants (mirrors the actual values).
	const RIPPLE_TRAVEL_DURATION: float = 1.2
	const RIPPLE_INTERVAL: float = 0.35
	const BOUNDARY_LIFETIME: float = 2.2
	const DOT_LIFETIME: float = 1.8
	const EVENT_LIFETIME: float = BOUNDARY_LIFETIME

	## Appearance constants.
	const RIPPLE_WIDTH: float = 2.5
	const BOUNDARY_WIDTH: float = 4.0
	const ORIGIN_DOT_RADIUS: float = 7.0
	const ARC_SEGMENTS: int = 80
	const MAX_EVENTS: int = 20
	const RIPPLE_COUNT: int = 3

	var _events: Array = []

	## Simulates adding a sound event.
	func add_event(position: Vector2, propagation_distance: float,
			source_type: int, sound_type: int) -> void:
		if _events.size() >= MAX_EVENTS:
			_events.remove_at(0)

		var color: Color
		match source_type:
			1:  color = Color(1.0, 0.3, 0.3, 1.0)   # Red - enemy
			0:  color = Color(0.35, 0.65, 1.0, 1.0)  # Blue - player
			_:  color = Color(0.9, 0.9, 0.9, 1.0)    # White - neutral

		var label := _sound_type_name(sound_type)
		var ev := MockSoundEvent.new(position, propagation_distance, color, label)
		_events.append(ev)

	## Simulates _process aging.
	func process(delta: float) -> void:
		for ev in _events:
			ev.age += delta
		_events = _events.filter(func(e): return e.age < EVENT_LIFETIME)

	## Returns the number of active events.
	func get_event_count() -> int:
		return _events.size()

	## Returns a specific event.
	func get_event(index: int) -> MockSoundEvent:
		return _events[index]

	## Matches the source sound_type_name logic.
	func _sound_type_name(sound_type: int) -> String:
		match sound_type:
			0: return "GUNSHOT"
			1: return "EXPLOSION"
			2: return "FOOTSTEP"
			3: return "RELOAD"
			4: return "IMPACT"
			5: return "EMPTY_CLICK"
			6: return "RELOAD_COMPLETE"
			7: return "GRENADE_LANDING"
			8: return "CASING_KICK"
			_: return "SOUND_%d" % sound_type
		return ""


var visualizer: MockSoundVisualizer


func before_each() -> void:
	visualizer = MockSoundVisualizer.new()


func after_each() -> void:
	visualizer = null


# ============================================================================
# Event Lifetime Constant Tests
# ============================================================================


func test_ripple_travel_duration() -> void:
	assert_almost_eq(MockSoundVisualizer.RIPPLE_TRAVEL_DURATION, 1.2, 0.001,
		"RIPPLE_TRAVEL_DURATION should be 1.2 seconds")


func test_ripple_interval() -> void:
	assert_almost_eq(MockSoundVisualizer.RIPPLE_INTERVAL, 0.35, 0.001,
		"RIPPLE_INTERVAL should be 0.35 seconds")


func test_boundary_lifetime() -> void:
	assert_almost_eq(MockSoundVisualizer.BOUNDARY_LIFETIME, 2.2, 0.001,
		"BOUNDARY_LIFETIME should be 2.2 seconds")


func test_dot_lifetime() -> void:
	assert_almost_eq(MockSoundVisualizer.DOT_LIFETIME, 1.8, 0.001,
		"DOT_LIFETIME should be 1.8 seconds")


func test_event_lifetime_equals_boundary_lifetime() -> void:
	assert_almost_eq(MockSoundVisualizer.EVENT_LIFETIME, MockSoundVisualizer.BOUNDARY_LIFETIME, 0.001,
		"EVENT_LIFETIME should equal BOUNDARY_LIFETIME")


func test_max_events_is_20() -> void:
	assert_eq(MockSoundVisualizer.MAX_EVENTS, 20,
		"MAX_EVENTS should be 20")


func test_ripple_count_is_3() -> void:
	assert_eq(MockSoundVisualizer.RIPPLE_COUNT, 3,
		"RIPPLE_COUNT should be 3")


# ============================================================================
# Event Aging Tests
# ============================================================================


func test_new_event_age_is_zero() -> void:
	visualizer.add_event(Vector2(100, 200), 500.0, 0, 0)

	assert_almost_eq(visualizer.get_event(0).age, 0.0, 0.001,
		"New event age should be 0.0")


func test_event_ages_with_process() -> void:
	visualizer.add_event(Vector2(100, 200), 500.0, 0, 0)

	visualizer.process(0.5)

	assert_almost_eq(visualizer.get_event(0).age, 0.5, 0.001,
		"Event should age by delta amount")


func test_event_removed_after_lifetime() -> void:
	visualizer.add_event(Vector2(100, 200), 500.0, 0, 0)

	visualizer.process(2.5)  # Exceeds EVENT_LIFETIME (2.2)

	assert_eq(visualizer.get_event_count(), 0,
		"Event should be removed after exceeding lifetime")


func test_event_alive_just_before_lifetime() -> void:
	visualizer.add_event(Vector2(100, 200), 500.0, 0, 0)

	visualizer.process(2.1)  # Just under EVENT_LIFETIME (2.2)

	assert_eq(visualizer.get_event_count(), 1,
		"Event should still be alive just before lifetime expires")


func test_multiple_events_age_independently() -> void:
	visualizer.add_event(Vector2(100, 200), 500.0, 0, 0)
	visualizer.process(1.0)

	visualizer.add_event(Vector2(300, 400), 300.0, 1, 1)
	visualizer.process(1.0)

	# First event: age 2.0, second event: age 1.0
	assert_eq(visualizer.get_event_count(), 2, "Both events should be alive")
	assert_almost_eq(visualizer.get_event(0).age, 2.0, 0.001, "First event age should be 2.0")
	assert_almost_eq(visualizer.get_event(1).age, 1.0, 0.001, "Second event age should be 1.0")


func test_older_event_removed_first() -> void:
	visualizer.add_event(Vector2(100, 200), 500.0, 0, 0)
	visualizer.process(1.5)

	visualizer.add_event(Vector2(300, 400), 300.0, 1, 1)
	visualizer.process(1.0)

	# First event age 2.5 (expired), second event age 1.0 (alive)
	assert_eq(visualizer.get_event_count(), 1,
		"Only the younger event should remain")


# ============================================================================
# MAX_EVENTS Limit Tests
# ============================================================================


func test_max_events_limit_enforced() -> void:
	for i in range(25):
		visualizer.add_event(Vector2(i * 10, 0), 100.0, 0, 0)

	assert_eq(visualizer.get_event_count(), 20,
		"Event count should not exceed MAX_EVENTS (20)")


func test_oldest_event_removed_when_limit_reached() -> void:
	for i in range(20):
		visualizer.add_event(Vector2(i * 10, 0), 100.0, 0, i % 9)

	# 21st event should remove the first one
	visualizer.add_event(Vector2(999, 999), 100.0, 0, 0)

	assert_eq(visualizer.get_event_count(), 20,
		"Count should remain at MAX_EVENTS")
	assert_eq(visualizer.get_event(19).position, Vector2(999, 999),
		"Newest event should be at the end")


# ============================================================================
# Color Coding Tests
# ============================================================================


func test_player_source_color_is_blue() -> void:
	visualizer.add_event(Vector2.ZERO, 100.0, 0, 0)  # source_type = 0 (player)

	var color := visualizer.get_event(0).color
	assert_almost_eq(color.r, 0.35, 0.01, "Player color red should be 0.35")
	assert_almost_eq(color.g, 0.65, 0.01, "Player color green should be 0.65")
	assert_almost_eq(color.b, 1.0, 0.01, "Player color blue should be 1.0")


func test_enemy_source_color_is_red() -> void:
	visualizer.add_event(Vector2.ZERO, 100.0, 1, 0)  # source_type = 1 (enemy)

	var color := visualizer.get_event(0).color
	assert_almost_eq(color.r, 1.0, 0.01, "Enemy color red should be 1.0")
	assert_almost_eq(color.g, 0.3, 0.01, "Enemy color green should be 0.3")
	assert_almost_eq(color.b, 0.3, 0.01, "Enemy color blue should be 0.3")


func test_neutral_source_color_is_white() -> void:
	visualizer.add_event(Vector2.ZERO, 100.0, 2, 0)  # source_type = 2 (neutral)

	var color := visualizer.get_event(0).color
	assert_almost_eq(color.r, 0.9, 0.01, "Neutral color red should be 0.9")
	assert_almost_eq(color.g, 0.9, 0.01, "Neutral color green should be 0.9")
	assert_almost_eq(color.b, 0.9, 0.01, "Neutral color blue should be 0.9")


func test_unknown_source_type_defaults_to_white() -> void:
	visualizer.add_event(Vector2.ZERO, 100.0, 99, 0)  # unknown source_type

	var color := visualizer.get_event(0).color
	assert_almost_eq(color.r, 0.9, 0.01, "Unknown source should default to white (r=0.9)")
	assert_almost_eq(color.g, 0.9, 0.01, "Unknown source should default to white (g=0.9)")


# ============================================================================
# Sound Type Label Tests
# ============================================================================


func test_sound_type_gunshot_label() -> void:
	visualizer.add_event(Vector2.ZERO, 100.0, 0, 0)
	assert_eq(visualizer.get_event(0).label, "GUNSHOT", "Sound type 0 should be GUNSHOT")


func test_sound_type_explosion_label() -> void:
	visualizer.add_event(Vector2.ZERO, 100.0, 0, 1)
	assert_eq(visualizer.get_event(0).label, "EXPLOSION", "Sound type 1 should be EXPLOSION")


func test_sound_type_unknown_label() -> void:
	visualizer.add_event(Vector2.ZERO, 100.0, 0, 42)
	assert_eq(visualizer.get_event(0).label, "SOUND_42", "Unknown sound type should be SOUND_42")
