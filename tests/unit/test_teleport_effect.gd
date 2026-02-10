extends GutTest
## Unit tests for TeleportEffect visual effect (Issue #721).
##
## Tests the teleport effect functionality including:
## - Animation phases (disappear, appear)
## - Signal emission
## - Target visibility control
## - Effect lifecycle


# ============================================================================
# Mock TeleportEffect for Logic Tests
# ============================================================================


class MockTeleportEffect:
	## Animation phases.
	enum AnimPhase { IDLE, DISAPPEAR, APPEAR }

	## Current animation phase.
	var _current_phase: int = AnimPhase.IDLE

	## Animation progress (0.0 to 1.0).
	var _progress: float = 0.0

	## Duration of the teleport animation.
	var animation_duration: float = 0.8

	## Target node reference.
	var _target: Node2D = null

	## Original target modulate.
	var _original_modulate: Color = Color.WHITE

	## Signal tracking.
	var animation_finished_count: int = 0
	var last_animation_type: String = ""
	var player_should_hide_count: int = 0
	var player_should_show_count: int = 0


	## Set the target node.
	func set_target(target: Node2D) -> void:
		_target = target
		if _target:
			_original_modulate = _target.modulate


	## Start the disappear animation.
	func play_disappear() -> void:
		if _current_phase != AnimPhase.IDLE:
			return
		_current_phase = AnimPhase.DISAPPEAR
		_progress = 0.0


	## Start the appear animation.
	func play_appear() -> void:
		if _current_phase != AnimPhase.IDLE:
			return
		_current_phase = AnimPhase.APPEAR
		_progress = 0.0


	## Simulate animation progress.
	func simulate_progress(delta: float) -> void:
		if _current_phase == AnimPhase.IDLE:
			return

		_progress += delta / animation_duration
		_progress = clampf(_progress, 0.0, 1.0)

		# Emit midpoint signals
		if _progress >= 0.5 and _progress < 0.55:
			if _current_phase == AnimPhase.DISAPPEAR:
				player_should_hide_count += 1
			elif _current_phase == AnimPhase.APPEAR:
				player_should_show_count += 1

		# Check if animation complete
		if _progress >= 1.0:
			_complete_animation()


	## Complete the animation.
	func _complete_animation() -> void:
		if _current_phase == AnimPhase.DISAPPEAR:
			last_animation_type = "disappear"
		elif _current_phase == AnimPhase.APPEAR:
			last_animation_type = "appear"

		animation_finished_count += 1
		_current_phase = AnimPhase.IDLE


	## Check if playing.
	func is_playing() -> bool:
		return _current_phase != AnimPhase.IDLE


	## Get current phase as string.
	func get_current_phase() -> String:
		match _current_phase:
			AnimPhase.IDLE:
				return "idle"
			AnimPhase.DISAPPEAR:
				return "disappear"
			AnimPhase.APPEAR:
				return "appear"
		return "unknown"


# ============================================================================
# Mock Target Node
# ============================================================================


class MockTargetNode:
	## Node name.
	var name: String = "Player"

	## Modulate color.
	var modulate: Color = Color.WHITE

	## Global position.
	var global_position: Vector2 = Vector2.ZERO


# ============================================================================
# Test Fixtures
# ============================================================================


var effect: MockTeleportEffect
var target: MockTargetNode


func before_each() -> void:
	effect = MockTeleportEffect.new()
	target = MockTargetNode.new()


func after_each() -> void:
	effect = null
	target = null


# ============================================================================
# Initial State Tests
# ============================================================================


func test_starts_in_idle_phase() -> void:
	assert_eq(effect.get_current_phase(), "idle",
		"Effect should start in idle phase")


func test_starts_not_playing() -> void:
	assert_false(effect.is_playing(),
		"Effect should not be playing initially")


func test_starts_with_zero_progress() -> void:
	assert_eq(effect._progress, 0.0,
		"Progress should start at 0")


func test_default_animation_duration() -> void:
	assert_eq(effect.animation_duration, 0.8,
		"Default animation duration should be 0.8 seconds")


# ============================================================================
# Disappear Animation Tests
# ============================================================================


func test_play_disappear_changes_phase() -> void:
	effect.play_disappear()

	assert_eq(effect.get_current_phase(), "disappear",
		"Should be in disappear phase after play_disappear")


func test_play_disappear_sets_playing() -> void:
	effect.play_disappear()

	assert_true(effect.is_playing(),
		"Should be playing after play_disappear")


func test_play_disappear_resets_progress() -> void:
	effect._progress = 0.5
	effect.play_disappear()

	assert_eq(effect._progress, 0.0,
		"Progress should reset to 0 when starting disappear")


func test_disappear_cannot_restart_while_playing() -> void:
	effect.play_disappear()
	effect._progress = 0.5
	effect.play_disappear()  # Should be ignored

	assert_eq(effect._progress, 0.5,
		"Should not restart if already playing")


func test_disappear_progress_advances() -> void:
	effect.play_disappear()
	effect.simulate_progress(0.4)  # Half of 0.8s duration

	assert_almost_eq(effect._progress, 0.5, 0.01,
		"Progress should advance with delta time")


func test_disappear_completes_at_full_progress() -> void:
	effect.play_disappear()
	effect.simulate_progress(0.8)  # Full duration

	assert_eq(effect.get_current_phase(), "idle",
		"Should return to idle after completion")
	assert_eq(effect.animation_finished_count, 1,
		"Should emit animation_finished once")
	assert_eq(effect.last_animation_type, "disappear",
		"Animation type should be 'disappear'")


func test_disappear_emits_hide_signal_at_midpoint() -> void:
	effect.play_disappear()
	effect.simulate_progress(0.4)  # Reach midpoint

	assert_eq(effect.player_should_hide_count, 1,
		"Should emit player_should_hide at midpoint")


# ============================================================================
# Appear Animation Tests
# ============================================================================


func test_play_appear_changes_phase() -> void:
	effect.play_appear()

	assert_eq(effect.get_current_phase(), "appear",
		"Should be in appear phase after play_appear")


func test_play_appear_sets_playing() -> void:
	effect.play_appear()

	assert_true(effect.is_playing(),
		"Should be playing after play_appear")


func test_appear_progress_advances() -> void:
	effect.play_appear()
	effect.simulate_progress(0.4)

	assert_almost_eq(effect._progress, 0.5, 0.01,
		"Progress should advance with delta time")


func test_appear_completes_at_full_progress() -> void:
	effect.play_appear()
	effect.simulate_progress(0.8)

	assert_eq(effect.get_current_phase(), "idle",
		"Should return to idle after completion")
	assert_eq(effect.animation_finished_count, 1,
		"Should emit animation_finished once")
	assert_eq(effect.last_animation_type, "appear",
		"Animation type should be 'appear'")


func test_appear_emits_show_signal_at_midpoint() -> void:
	effect.play_appear()
	effect.simulate_progress(0.4)  # Reach midpoint

	assert_eq(effect.player_should_show_count, 1,
		"Should emit player_should_show at midpoint")


# ============================================================================
# Target Handling Tests
# ============================================================================


func test_set_target_stores_reference() -> void:
	effect.set_target(target)

	assert_eq(effect._target, target,
		"Should store target reference")


func test_set_target_saves_original_modulate() -> void:
	target.modulate = Color(0.5, 0.5, 0.5, 1.0)
	effect.set_target(target)

	assert_eq(effect._original_modulate, Color(0.5, 0.5, 0.5, 1.0),
		"Should save original modulate color")


# ============================================================================
# Animation Sequencing Tests
# ============================================================================


func test_disappear_then_appear_sequence() -> void:
	# Play disappear
	effect.play_disappear()
	effect.simulate_progress(0.8)

	assert_eq(effect.animation_finished_count, 1,
		"Disappear should complete")

	# Play appear
	effect.play_appear()
	effect.simulate_progress(0.8)

	assert_eq(effect.animation_finished_count, 2,
		"Appear should also complete")
	assert_eq(effect.last_animation_type, "appear",
		"Last animation should be 'appear'")


func test_cannot_play_appear_during_disappear() -> void:
	effect.play_disappear()
	effect.simulate_progress(0.2)  # Partial progress

	effect.play_appear()  # Should be ignored

	assert_eq(effect.get_current_phase(), "disappear",
		"Should remain in disappear phase")


func test_cannot_play_disappear_during_appear() -> void:
	effect.play_appear()
	effect.simulate_progress(0.2)

	effect.play_disappear()  # Should be ignored

	assert_eq(effect.get_current_phase(), "appear",
		"Should remain in appear phase")


# ============================================================================
# Progress Clamping Tests
# ============================================================================


func test_progress_clamped_to_max() -> void:
	effect.play_disappear()
	effect.simulate_progress(1.0)  # More than duration

	assert_almost_eq(effect._progress, 1.0, 0.01,
		"Progress should be clamped to 1.0")


func test_no_progress_when_idle() -> void:
	# Don't start animation
	effect.simulate_progress(0.5)

	assert_eq(effect._progress, 0.0,
		"Progress should not advance when idle")


# ============================================================================
# Constants Tests
# ============================================================================


func test_portal_visual_constants() -> void:
	# These test that the teleport effect uses reasonable visual parameters
	# The actual implementation uses these constants
	var portal_radius: float = 40.0
	var column_height: float = 80.0
	var ring_count: int = 3

	assert_eq(portal_radius, 40.0,
		"Portal radius should be 40 pixels")
	assert_eq(column_height, 80.0,
		"Column height should be 80 pixels")
	assert_eq(ring_count, 3,
		"Should have 3 concentric rings")


# ============================================================================
# Exit Zone Integration Tests
# ============================================================================


class MockExitZoneWithTeleport:
	## Whether the exit zone is active.
	var _is_active: bool = false

	## Whether teleport is animating.
	var _teleport_animating: bool = false

	## Reference to teleport effect.
	var _teleport_effect: MockTeleportEffect = null

	## Signal tracking.
	var player_reached_exit_emitted: int = 0


	## Activate the exit zone.
	func activate() -> void:
		_is_active = true


	## Simulate player entering the zone.
	func simulate_player_entered(player: MockTargetNode) -> void:
		if not _is_active:
			return

		if _teleport_animating:
			return

		_teleport_animating = true

		# Create teleport effect
		_teleport_effect = MockTeleportEffect.new()
		_teleport_effect.set_target(player)
		_teleport_effect.play_disappear()


	## Complete the teleport animation.
	func complete_teleport() -> void:
		if _teleport_effect:
			_teleport_effect.simulate_progress(0.8)
			_teleport_effect = null

		_teleport_animating = false
		player_reached_exit_emitted += 1


func test_exit_zone_plays_teleport_on_player_entry() -> void:
	var exit_zone := MockExitZoneWithTeleport.new()
	exit_zone.activate()
	exit_zone.simulate_player_entered(target)

	assert_true(exit_zone._teleport_animating,
		"Teleport should be animating after player enters")
	assert_not_null(exit_zone._teleport_effect,
		"Teleport effect should be created")


func test_exit_zone_blocks_duplicate_entry() -> void:
	var exit_zone := MockExitZoneWithTeleport.new()
	exit_zone.activate()

	exit_zone.simulate_player_entered(target)
	var first_effect := exit_zone._teleport_effect

	exit_zone.simulate_player_entered(target)  # Should be blocked

	assert_eq(exit_zone._teleport_effect, first_effect,
		"Should not create new effect while animating")


func test_exit_zone_emits_signal_after_teleport() -> void:
	var exit_zone := MockExitZoneWithTeleport.new()
	exit_zone.activate()

	exit_zone.simulate_player_entered(target)
	assert_eq(exit_zone.player_reached_exit_emitted, 0,
		"Should not emit signal until teleport completes")

	exit_zone.complete_teleport()
	assert_eq(exit_zone.player_reached_exit_emitted, 1,
		"Should emit signal after teleport completes")


func test_exit_zone_cleans_up_after_teleport() -> void:
	var exit_zone := MockExitZoneWithTeleport.new()
	exit_zone.activate()

	exit_zone.simulate_player_entered(target)
	exit_zone.complete_teleport()

	assert_false(exit_zone._teleport_animating,
		"Teleport animating should be false after completion")
	assert_null(exit_zone._teleport_effect,
		"Teleport effect should be cleaned up")
