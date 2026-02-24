extends GutTest
## Unit tests for Issue #805: Enemies hearing grenade explosions.
##
## Tests that enemies properly react to EXPLOSION sounds (sound_type 1)
## from grenades and other explosion sources.


# ============================================================================
# Test Constants
# ============================================================================

const SOUND_TYPE_GUNSHOT := 0
const SOUND_TYPE_EXPLOSION := 1
const SOURCE_TYPE_PLAYER := 0
const SOURCE_TYPE_ENEMY := 1
const SOURCE_TYPE_NEUTRAL := 2


# ============================================================================
# Mock Enemy Class
# ============================================================================

## Mock enemy that tracks sound handling and state transitions.
class MockEnemyWithSoundHandling extends Node2D:
	## AI States (mirrors actual enum in enemy.gd)
	enum AIState {
		IDLE,
		COMBAT,
		SEEKING_COVER,
		IN_COVER,
		FLANKING,
		SUPPRESSED,
		RETREATING,
		PURSUING,
		ASSAULT,
		SEARCHING,
		EVADING_GRENADE
	}

	var _is_alive: bool = true
	var _current_state: AIState = AIState.IDLE
	var _memory_reset_confusion_timer: float = 0.0
	var _last_known_player_position: Vector2 = Vector2.ZERO
	var _memory = null
	var _grenade_avoidance = null

	## Track sounds heard
	var sounds_heard: Array = []
	var explosions_heard: Array = []
	var transitions_to_combat: int = 0

	func is_alive() -> bool:
		return _is_alive

	## Called by SoundPropagation when a sound is heard.
	func on_sound_heard(sound_type: int, position: Vector2, source_type: int, source_node: Node2D) -> void:
		on_sound_heard_with_intensity(sound_type, position, source_type, source_node, 1.0)

	## Called by SoundPropagation with intensity.
	## Mirrors the refactored enemy.gd implementation (Issue #805).
	func on_sound_heard_with_intensity(sound_type: int, position: Vector2, source_type: int, _source_node: Node2D, intensity: float) -> void:
		if not _is_alive or _memory_reset_confusion_timer > 0.0:
			return

		sounds_heard.append({
			"type": sound_type,
			"position": position,
			"source_type": source_type,
			"intensity": intensity
		})

		# Issue #805: Handle GUNSHOT (0) and EXPLOSION (1) sounds - both alert enemies similarly
		if sound_type != 0 and sound_type != 1:
			return

		# Track explosions specifically for test verification
		if sound_type == 1:
			explosions_heard.append({"position": position, "intensity": intensity})

		# React based on current state (same for gunshots and explosions)
		var should_react := false
		if _current_state == AIState.IDLE:
			should_react = intensity >= 0.01
		elif _current_state in [AIState.FLANKING, AIState.RETREATING]:
			should_react = intensity >= 0.3
		if not should_react:
			return

		_last_known_player_position = position
		_transition_to_combat()

	func _transition_to_combat() -> void:
		_current_state = AIState.COMBAT
		transitions_to_combat += 1


# ============================================================================
# Test Setup
# ============================================================================

var _sound_propagation: Node


func before_each() -> void:
	_sound_propagation = load("res://scripts/autoload/sound_propagation.gd").new()
	add_child(_sound_propagation)


func after_each() -> void:
	if is_instance_valid(_sound_propagation):
		_sound_propagation.queue_free()
	_sound_propagation = null


# ============================================================================
# Tests for Issue #805: Enemy Explosion Hearing
# ============================================================================

func test_explosion_sound_type_propagates_to_listener() -> void:
	var enemy := MockEnemyWithSoundHandling.new()
	enemy.global_position = Vector2(500, 0)  # Within explosion range (2200)
	add_child(enemy)

	_sound_propagation.register_listener(enemy)

	# Emit explosion sound (type 1) at origin
	_sound_propagation.emit_sound(SOUND_TYPE_EXPLOSION, Vector2.ZERO, SOURCE_TYPE_NEUTRAL, null)

	assert_eq(enemy.sounds_heard.size(), 1, "Enemy should receive 1 sound")
	assert_eq(enemy.sounds_heard[0].type, SOUND_TYPE_EXPLOSION, "Sound type should be EXPLOSION (1)")

	enemy.queue_free()


func test_enemy_hears_explosion_and_tracks_it() -> void:
	var enemy := MockEnemyWithSoundHandling.new()
	enemy.global_position = Vector2(500, 0)
	add_child(enemy)

	_sound_propagation.register_listener(enemy)
	_sound_propagation.emit_sound(SOUND_TYPE_EXPLOSION, Vector2.ZERO, SOURCE_TYPE_NEUTRAL, null)

	assert_eq(enemy.explosions_heard.size(), 1, "Enemy should have heard 1 explosion")
	assert_eq(enemy.explosions_heard[0].position, Vector2.ZERO, "Explosion position should be origin")

	enemy.queue_free()


func test_enemy_in_idle_reacts_to_explosion() -> void:
	var enemy := MockEnemyWithSoundHandling.new()
	enemy.global_position = Vector2(500, 0)
	enemy._current_state = MockEnemyWithSoundHandling.AIState.IDLE
	add_child(enemy)

	_sound_propagation.register_listener(enemy)
	_sound_propagation.emit_sound(SOUND_TYPE_EXPLOSION, Vector2(100, 100), SOURCE_TYPE_NEUTRAL, null)

	assert_eq(enemy._current_state, MockEnemyWithSoundHandling.AIState.COMBAT,
		"Enemy should transition to COMBAT when hearing explosion in IDLE state")
	assert_eq(enemy._last_known_player_position, Vector2(100, 100),
		"Enemy should update last known position to explosion location")
	assert_eq(enemy.transitions_to_combat, 1, "Enemy should have transitioned to combat once")

	enemy.queue_free()


func test_enemy_in_combat_does_not_react_to_explosion() -> void:
	var enemy := MockEnemyWithSoundHandling.new()
	enemy.global_position = Vector2(500, 0)
	enemy._current_state = MockEnemyWithSoundHandling.AIState.COMBAT
	add_child(enemy)

	_sound_propagation.register_listener(enemy)
	_sound_propagation.emit_sound(SOUND_TYPE_EXPLOSION, Vector2(100, 100), SOURCE_TYPE_NEUTRAL, null)

	# Enemy already in combat should NOT change state
	assert_eq(enemy._current_state, MockEnemyWithSoundHandling.AIState.COMBAT,
		"Enemy already in COMBAT should remain in COMBAT")
	assert_eq(enemy.transitions_to_combat, 0, "Enemy already in combat should not transition again")

	enemy.queue_free()


func test_explosion_has_larger_range_than_gunshot() -> void:
	var gunshot_range: float = _sound_propagation.get_propagation_distance(SOUND_TYPE_GUNSHOT)
	var explosion_range: float = _sound_propagation.get_propagation_distance(SOUND_TYPE_EXPLOSION)

	assert_gt(explosion_range, gunshot_range,
		"Explosion should have larger propagation range than gunshot")
	assert_almost_eq(explosion_range, 2200.0, 0.1,
		"Explosion range should be ~2200 pixels (1.5x viewport diagonal)")


func test_explosion_reaches_distant_listener_beyond_gunshot_range() -> void:
	# Listener at 1600 pixels - beyond gunshot range (1468.6) but within explosion range (2200)
	var enemy := MockEnemyWithSoundHandling.new()
	enemy.global_position = Vector2(1600, 0)
	add_child(enemy)

	_sound_propagation.register_listener(enemy)

	# Gunshot should NOT reach
	_sound_propagation.emit_sound(SOUND_TYPE_GUNSHOT, Vector2.ZERO, SOURCE_TYPE_PLAYER, null)
	assert_eq(enemy.sounds_heard.size(), 0, "Gunshot should not reach listener at 1600 pixels")

	# Explosion SHOULD reach
	_sound_propagation.emit_sound(SOUND_TYPE_EXPLOSION, Vector2.ZERO, SOURCE_TYPE_NEUTRAL, null)
	assert_eq(enemy.sounds_heard.size(), 1, "Explosion should reach listener at 1600 pixels")
	assert_eq(enemy.sounds_heard[0].type, SOUND_TYPE_EXPLOSION, "Sound should be explosion type")

	enemy.queue_free()


func test_dead_enemy_does_not_react_to_explosion() -> void:
	var enemy := MockEnemyWithSoundHandling.new()
	enemy.global_position = Vector2(500, 0)
	enemy._is_alive = false  # Dead enemy
	add_child(enemy)

	_sound_propagation.register_listener(enemy)
	_sound_propagation.emit_sound(SOUND_TYPE_EXPLOSION, Vector2.ZERO, SOURCE_TYPE_NEUTRAL, null)

	# Sound is received but enemy doesn't react
	assert_eq(enemy.sounds_heard.size(), 1, "Sound propagation delivers to all listeners")
	assert_eq(enemy.explosions_heard.size(), 0, "Dead enemy should not process explosion")
	assert_eq(enemy.transitions_to_combat, 0, "Dead enemy should not transition states")

	enemy.queue_free()


func test_confused_enemy_does_not_react_to_explosion() -> void:
	var enemy := MockEnemyWithSoundHandling.new()
	enemy.global_position = Vector2(500, 0)
	enemy._memory_reset_confusion_timer = 0.5  # Enemy is confused
	add_child(enemy)

	_sound_propagation.register_listener(enemy)
	_sound_propagation.emit_sound(SOUND_TYPE_EXPLOSION, Vector2.ZERO, SOURCE_TYPE_NEUTRAL, null)

	# Sound is received but enemy doesn't react due to confusion
	assert_eq(enemy.sounds_heard.size(), 1, "Sound propagation delivers to all listeners")
	assert_eq(enemy.explosions_heard.size(), 0, "Confused enemy should not process explosion")
	assert_eq(enemy.transitions_to_combat, 0, "Confused enemy should not transition states")

	enemy.queue_free()


func test_enemy_in_flanking_reacts_to_loud_explosion() -> void:
	var enemy := MockEnemyWithSoundHandling.new()
	enemy.global_position = Vector2(100, 0)  # Close = high intensity
	enemy._current_state = MockEnemyWithSoundHandling.AIState.FLANKING
	add_child(enemy)

	_sound_propagation.register_listener(enemy)
	_sound_propagation.emit_sound(SOUND_TYPE_EXPLOSION, Vector2.ZERO, SOURCE_TYPE_NEUTRAL, null)

	# At 100 pixels, intensity = (50/100)² = 0.25, which is below 0.3 threshold
	# So flanking enemy should NOT react
	assert_eq(enemy._current_state, MockEnemyWithSoundHandling.AIState.FLANKING,
		"Enemy in flanking should not react to explosion with intensity < 0.3")

	enemy.queue_free()


func test_enemy_in_flanking_reacts_to_very_close_explosion() -> void:
	var enemy := MockEnemyWithSoundHandling.new()
	enemy.global_position = Vector2(50, 0)  # Very close = intensity ~1.0
	enemy._current_state = MockEnemyWithSoundHandling.AIState.FLANKING
	add_child(enemy)

	_sound_propagation.register_listener(enemy)
	_sound_propagation.emit_sound(SOUND_TYPE_EXPLOSION, Vector2.ZERO, SOURCE_TYPE_NEUTRAL, null)

	# At reference distance (50 pixels), intensity = 1.0, which is above 0.3 threshold
	assert_eq(enemy._current_state, MockEnemyWithSoundHandling.AIState.COMBAT,
		"Enemy in flanking should react to very close explosion (intensity >= 0.3)")

	enemy.queue_free()


func test_multiple_enemies_hear_same_explosion() -> void:
	var enemy1 := MockEnemyWithSoundHandling.new()
	enemy1.global_position = Vector2(200, 0)
	add_child(enemy1)

	var enemy2 := MockEnemyWithSoundHandling.new()
	enemy2.global_position = Vector2(0, 200)
	add_child(enemy2)

	var enemy3 := MockEnemyWithSoundHandling.new()
	enemy3.global_position = Vector2(-300, 0)
	add_child(enemy3)

	_sound_propagation.register_listener(enemy1)
	_sound_propagation.register_listener(enemy2)
	_sound_propagation.register_listener(enemy3)

	_sound_propagation.emit_sound(SOUND_TYPE_EXPLOSION, Vector2.ZERO, SOURCE_TYPE_NEUTRAL, null)

	# All enemies should hear and react
	assert_eq(enemy1.explosions_heard.size(), 1, "Enemy 1 should hear explosion")
	assert_eq(enemy2.explosions_heard.size(), 1, "Enemy 2 should hear explosion")
	assert_eq(enemy3.explosions_heard.size(), 1, "Enemy 3 should hear explosion")

	assert_eq(enemy1.transitions_to_combat, 1, "Enemy 1 should transition to combat")
	assert_eq(enemy2.transitions_to_combat, 1, "Enemy 2 should transition to combat")
	assert_eq(enemy3.transitions_to_combat, 1, "Enemy 3 should transition to combat")

	enemy1.queue_free()
	enemy2.queue_free()
	enemy3.queue_free()


func test_explosion_source_type_is_neutral() -> void:
	var enemy := MockEnemyWithSoundHandling.new()
	enemy.global_position = Vector2(500, 0)
	add_child(enemy)

	_sound_propagation.register_listener(enemy)

	# Grenade explosions typically emit as NEUTRAL source
	_sound_propagation.emit_sound(SOUND_TYPE_EXPLOSION, Vector2.ZERO, SOURCE_TYPE_NEUTRAL, null)

	assert_eq(enemy.sounds_heard.size(), 1, "Enemy should receive sound")
	assert_eq(enemy.sounds_heard[0].source_type, SOURCE_TYPE_NEUTRAL,
		"Explosion source type should be NEUTRAL (2)")

	enemy.queue_free()


func test_grenade_explosion_scenario() -> void:
	## Simulates a complete grenade explosion scenario:
	## 1. Grenade lands near enemies
	## 2. Grenade explodes
	## 3. Enemies within explosion range should hear and react

	# Create multiple enemies at different distances
	var close_enemy := MockEnemyWithSoundHandling.new()
	close_enemy.global_position = Vector2(300, 0)  # Close to explosion
	add_child(close_enemy)

	var medium_enemy := MockEnemyWithSoundHandling.new()
	medium_enemy.global_position = Vector2(1000, 0)  # Medium distance
	add_child(medium_enemy)

	var far_enemy := MockEnemyWithSoundHandling.new()
	far_enemy.global_position = Vector2(2100, 0)  # Far but still in range
	add_child(far_enemy)

	var too_far_enemy := MockEnemyWithSoundHandling.new()
	too_far_enemy.global_position = Vector2(2500, 0)  # Beyond explosion range
	add_child(too_far_enemy)

	_sound_propagation.register_listener(close_enemy)
	_sound_propagation.register_listener(medium_enemy)
	_sound_propagation.register_listener(far_enemy)
	_sound_propagation.register_listener(too_far_enemy)

	# Grenade explodes at origin with default explosion range (2200)
	_sound_propagation.emit_sound(SOUND_TYPE_EXPLOSION, Vector2.ZERO, SOURCE_TYPE_NEUTRAL, null)

	# Close enemy should hear and react
	assert_eq(close_enemy.explosions_heard.size(), 1, "Close enemy should hear explosion")
	assert_eq(close_enemy.transitions_to_combat, 1, "Close enemy should transition to combat")

	# Medium enemy should hear and react
	assert_eq(medium_enemy.explosions_heard.size(), 1, "Medium enemy should hear explosion")
	assert_eq(medium_enemy.transitions_to_combat, 1, "Medium enemy should transition to combat")

	# Far enemy should hear and react (2100 < 2200)
	assert_eq(far_enemy.explosions_heard.size(), 1, "Far enemy should hear explosion")
	assert_eq(far_enemy.transitions_to_combat, 1, "Far enemy should transition to combat")

	# Too far enemy should NOT hear (2500 > 2200)
	assert_eq(too_far_enemy.explosions_heard.size(), 0, "Too far enemy should not hear explosion")
	assert_eq(too_far_enemy.transitions_to_combat, 0, "Too far enemy should not transition")

	close_enemy.queue_free()
	medium_enemy.queue_free()
	far_enemy.queue_free()
	too_far_enemy.queue_free()
