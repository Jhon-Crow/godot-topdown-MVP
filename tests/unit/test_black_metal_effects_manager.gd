extends GutTest
## Unit tests for BlackMetalEffectsManager autoload.
##
## Tests the activation delay frame counting, enable/disable toggling,
## and delayed activation logic.


# ============================================================================
# Mock BlackMetalEffectsManager
# ============================================================================


class MockBlackMetalEffectsManager:
	## Number of frames to wait after a scene transition before showing the filter.
	const ACTIVATION_DELAY_FRAMES: int = 3

	## Whether the filter should be visible (logical state).
	var _is_active: bool = false

	## Whether we're waiting for delayed activation after a scene change.
	var _waiting_for_activation: bool = false

	## Frame counter for delayed activation.
	var _activation_frame_counter: int = 0

	## Simulates the filter rect visibility.
	var filter_visible: bool = false

	## Enables the Black Metal visual filter.
	func enable_filter() -> void:
		_is_active = true
		_start_delayed_activation()

	## Disables the Black Metal visual filter.
	func disable_filter() -> void:
		_is_active = false
		_waiting_for_activation = false
		filter_visible = false

	## Returns whether the filter is currently active (logical state).
	func is_filter_active() -> bool:
		return _is_active

	## Returns whether filter is visually showing.
	func is_filter_visible() -> bool:
		return filter_visible

	## Simulates _process() for delayed activation.
	func process_frame() -> void:
		if _waiting_for_activation:
			_activation_frame_counter += 1
			if _activation_frame_counter >= ACTIVATION_DELAY_FRAMES:
				_waiting_for_activation = false
				if _is_active:
					filter_visible = true

	## Starts the delayed activation (hides overlay, resets counter).
	func _start_delayed_activation() -> void:
		filter_visible = false
		_waiting_for_activation = true
		_activation_frame_counter = 0

	## Simulates a scene transition (re-triggers delayed activation).
	func on_scene_changed() -> void:
		if _is_active:
			_start_delayed_activation()


var manager: MockBlackMetalEffectsManager


func before_each() -> void:
	manager = MockBlackMetalEffectsManager.new()


func after_each() -> void:
	manager = null


# ============================================================================
# Constant Tests
# ============================================================================


func test_activation_delay_frames_is_3() -> void:
	assert_eq(MockBlackMetalEffectsManager.ACTIVATION_DELAY_FRAMES, 3,
		"ACTIVATION_DELAY_FRAMES should be 3")


# ============================================================================
# Initial State Tests
# ============================================================================


func test_initial_filter_not_active() -> void:
	assert_false(manager.is_filter_active(),
		"Filter should not be active initially")


func test_initial_filter_not_visible() -> void:
	assert_false(manager.is_filter_visible(),
		"Filter should not be visible initially")


# ============================================================================
# Enable/Disable Toggling Tests
# ============================================================================


func test_enable_filter_sets_active() -> void:
	manager.enable_filter()

	assert_true(manager.is_filter_active(),
		"Filter should be active after enable_filter()")


func test_enable_filter_not_immediately_visible() -> void:
	manager.enable_filter()

	assert_false(manager.is_filter_visible(),
		"Filter should not be immediately visible (delayed activation)")


func test_disable_filter_clears_active() -> void:
	manager.enable_filter()
	manager.disable_filter()

	assert_false(manager.is_filter_active(),
		"Filter should not be active after disable_filter()")


func test_disable_filter_hides_visible() -> void:
	manager.enable_filter()
	# Process enough frames to make it visible
	for i in range(3):
		manager.process_frame()
	assert_true(manager.is_filter_visible(), "Should be visible after delay")

	manager.disable_filter()

	assert_false(manager.is_filter_visible(),
		"Filter should not be visible after disable_filter()")


func test_enable_disable_enable_cycle() -> void:
	manager.enable_filter()
	assert_true(manager.is_filter_active())

	manager.disable_filter()
	assert_false(manager.is_filter_active())

	manager.enable_filter()
	assert_true(manager.is_filter_active())


# ============================================================================
# Delayed Activation Frame Counting Tests
# ============================================================================


func test_filter_not_visible_after_1_frame() -> void:
	manager.enable_filter()

	manager.process_frame()

	assert_false(manager.is_filter_visible(),
		"Filter should not be visible after 1 frame (need 3)")


func test_filter_not_visible_after_2_frames() -> void:
	manager.enable_filter()

	manager.process_frame()
	manager.process_frame()

	assert_false(manager.is_filter_visible(),
		"Filter should not be visible after 2 frames (need 3)")


func test_filter_visible_after_3_frames() -> void:
	manager.enable_filter()

	manager.process_frame()
	manager.process_frame()
	manager.process_frame()

	assert_true(manager.is_filter_visible(),
		"Filter should be visible after 3 frames (ACTIVATION_DELAY_FRAMES)")


func test_filter_stays_visible_after_more_frames() -> void:
	manager.enable_filter()

	for i in range(10):
		manager.process_frame()

	assert_true(manager.is_filter_visible(),
		"Filter should stay visible after exceeding delay frames")


func test_disable_during_delay_prevents_visibility() -> void:
	manager.enable_filter()
	manager.process_frame()
	manager.process_frame()

	manager.disable_filter()
	manager.process_frame()

	assert_false(manager.is_filter_visible(),
		"Disabling during delay should prevent filter from becoming visible")


# ============================================================================
# Scene Transition Tests
# ============================================================================


func test_scene_change_restarts_delayed_activation() -> void:
	manager.enable_filter()

	# Make visible
	for i in range(3):
		manager.process_frame()
	assert_true(manager.is_filter_visible(), "Should be visible before scene change")

	# Scene changes, should restart delay
	manager.on_scene_changed()

	assert_false(manager.is_filter_visible(),
		"Filter should be hidden during scene transition re-activation")

	# Need 3 more frames
	manager.process_frame()
	manager.process_frame()
	assert_false(manager.is_filter_visible(), "Still waiting for delay")

	manager.process_frame()
	assert_true(manager.is_filter_visible(),
		"Filter should be visible again after delay completes")


func test_scene_change_when_inactive_does_nothing() -> void:
	manager.on_scene_changed()

	for i in range(5):
		manager.process_frame()

	assert_false(manager.is_filter_visible(),
		"Scene change when inactive should not show filter")
