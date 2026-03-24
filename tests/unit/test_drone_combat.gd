extends GutTest
## Unit tests for Drone combat AI (Issue #1417).
##
## Verifies:
## 1. Drone AI states: SEARCHING and COMBAT
## 2. Detection: 360° FOV, unlimited range, line-of-sight
## 3. Combat mode: 3x speed, drift mechanics, collision explosion
## 4. Explosion: RPG-strength (radius=150, damage=3), no wall penetration
## 5. Visual: LED color changes (green=searching, red=combat)
## 6. Audio: beeping in combat mode


# ============================================================================
# MockDroneComponent for state machine testing
# ============================================================================


class MockDroneCombat:
	## Simulates DroneComponent combat behavior for testing without scene tree.
	const DRONE_HP: int = 2
	const DRONE_SPEED: float = 150.0
	const COMBAT_SPEED_MULTIPLIER: float = 3.0
	const COMBAT_SPEED: float = DRONE_SPEED * COMBAT_SPEED_MULTIPLIER
	const EXPLOSION_RADIUS: float = 150.0
	const EXPLOSION_DAMAGE: int = 3
	const COLLISION_DISTANCE: float = 30.0
	const DRIFT_TURN_FACTOR: float = 0.03
	const DETECTION_DELAY: float = 0.3
	const BEEP_FREQUENCY: float = 880.0
	const BEEPS_PER_GROUP: int = 3

	enum DroneState { SEARCHING, COMBAT }

	var _hp: int = DRONE_HP
	var _is_alive: bool = true
	var _state: DroneState = DroneState.SEARCHING
	var _detection_timer: float = 0.0
	var _has_exploded: bool = false
	var _actual_direction: Vector2 = Vector2.RIGHT
	var _combat_entered_count: int = 0
	var _exploded_count: int = 0
	var _destroyed_count: int = 0

	func take_damage(amount: int = 1) -> bool:
		if not _is_alive:
			return false
		_hp -= amount
		if _hp <= 0:
			_is_alive = false
			_hp = 0
			_destroyed_count += 1
			return true
		return false

	func is_alive() -> bool:
		return _is_alive

	func get_hp() -> int:
		return _hp

	func get_state() -> DroneState:
		return _state

	func is_in_combat() -> bool:
		return _state == DroneState.COMBAT

	func transition_to_combat() -> void:
		_state = DroneState.COMBAT
		_combat_entered_count += 1

	func simulate_detection(delta: float, can_see: bool) -> void:
		if can_see:
			_detection_timer += delta
			if _detection_timer >= DETECTION_DELAY:
				transition_to_combat()
		else:
			_detection_timer = 0.0

	func simulate_drift(desired_dir: Vector2) -> Vector2:
		_actual_direction = _actual_direction.lerp(desired_dir, DRIFT_TURN_FACTOR).normalized()
		return _actual_direction

	func get_combat_speed() -> float:
		return COMBAT_SPEED

	func simulate_collision(distance: float) -> bool:
		if distance <= COLLISION_DISTANCE and _state == DroneState.COMBAT:
			_has_exploded = true
			_is_alive = false
			_hp = 0
			_exploded_count += 1
			return true
		return false

	func has_exploded() -> bool:
		return _has_exploded


var mock: MockDroneCombat


func before_each() -> void:
	mock = MockDroneCombat.new()


func after_each() -> void:
	mock = null


# ============================================================================
# State machine tests
# ============================================================================


func test_drone_starts_in_searching_state() -> void:
	assert_eq(mock.get_state(), MockDroneCombat.DroneState.SEARCHING,
		"Drone should start in SEARCHING state")


func test_drone_is_not_in_combat_initially() -> void:
	assert_false(mock.is_in_combat(),
		"Drone should not be in COMBAT initially")


func test_drone_transitions_to_combat() -> void:
	mock.transition_to_combat()
	assert_eq(mock.get_state(), MockDroneCombat.DroneState.COMBAT,
		"Drone should transition to COMBAT state")
	assert_true(mock.is_in_combat(),
		"is_in_combat() should return true after transition")


func test_combat_entered_signal_count() -> void:
	mock.transition_to_combat()
	assert_eq(mock._combat_entered_count, 1,
		"combat_entered should fire once on transition")


# ============================================================================
# Detection tests (360° FOV, unlimited range)
# ============================================================================


func test_detection_timer_accumulates_when_visible() -> void:
	mock.simulate_detection(0.1, true)
	assert_false(mock.is_in_combat(),
		"Should not enter combat after 0.1s (need 0.3s)")

	mock.simulate_detection(0.1, true)
	assert_false(mock.is_in_combat(),
		"Should not enter combat after 0.2s (need 0.3s)")

	mock.simulate_detection(0.1, true)
	assert_true(mock.is_in_combat(),
		"Should enter COMBAT after 0.3s of continuous visibility")


func test_detection_timer_resets_on_lost_sight() -> void:
	mock.simulate_detection(0.2, true)
	mock.simulate_detection(0.0, false)  # Lost sight
	mock.simulate_detection(0.2, true)
	assert_false(mock.is_in_combat(),
		"Detection timer should reset when sight is lost")


func test_detection_delay_matches_spec() -> void:
	assert_eq(mock.DETECTION_DELAY, 0.3,
		"Detection delay should be 0.3 seconds")


# ============================================================================
# Speed tests
# ============================================================================


func test_combat_speed_is_3x_search_speed() -> void:
	assert_eq(mock.COMBAT_SPEED, mock.DRONE_SPEED * 3.0,
		"Combat speed should be 3x the searching speed")
	assert_eq(mock.get_combat_speed(), 450.0,
		"Combat speed should be 450 px/s (150 * 3)")


func test_combat_speed_multiplier() -> void:
	assert_eq(mock.COMBAT_SPEED_MULTIPLIER, 3.0,
		"Combat speed multiplier should be 3x")


func test_search_speed() -> void:
	assert_eq(mock.DRONE_SPEED, 150.0,
		"Search speed should be 150 px/s")


# ============================================================================
# Drift mechanics tests
# ============================================================================


func test_drift_does_not_instantly_change_direction() -> void:
	mock._actual_direction = Vector2.RIGHT
	var new_dir := mock.simulate_drift(Vector2.UP)
	# After one frame of drift, direction should be mostly RIGHT still
	assert_gt(new_dir.x, 0.9,
		"Drift should keep most of the original direction after one frame")
	assert_true(new_dir.y > 0.0,
		"Drift should start turning toward desired direction")


func test_drift_gradually_turns() -> void:
	mock._actual_direction = Vector2.RIGHT
	# Simulate many frames of drift toward UP
	for i in range(100):
		mock.simulate_drift(Vector2.UP)
	# After 100 frames, should have turned significantly toward UP
	assert_gt(mock._actual_direction.y, 0.5,
		"After many frames, drift should significantly face the target direction")


func test_drift_turn_factor() -> void:
	assert_eq(mock.DRIFT_TURN_FACTOR, 0.03,
		"Drift turn factor should be 0.03 (slow turns = more drift)")


# ============================================================================
# Explosion tests
# ============================================================================


func test_explosion_radius_matches_rpg() -> void:
	assert_eq(mock.EXPLOSION_RADIUS, 150.0,
		"Explosion radius should match RPG rocket (150 px)")


func test_explosion_damage_matches_rpg() -> void:
	assert_eq(mock.EXPLOSION_DAMAGE, 3,
		"Explosion damage should match RPG rocket (3)")


func test_collision_triggers_explosion() -> void:
	mock.transition_to_combat()
	var exploded := mock.simulate_collision(25.0)  # Within collision distance
	assert_true(exploded,
		"Collision within distance should trigger explosion")
	assert_true(mock.has_exploded(),
		"Drone should be marked as exploded")
	assert_false(mock.is_alive(),
		"Drone should be dead after explosion")


func test_no_explosion_outside_collision_distance() -> void:
	mock.transition_to_combat()
	var exploded := mock.simulate_collision(50.0)  # Outside collision distance
	assert_false(exploded,
		"No explosion when outside collision distance")
	assert_false(mock.has_exploded(),
		"Drone should not be exploded")


func test_no_explosion_in_searching_state() -> void:
	var exploded := mock.simulate_collision(25.0)
	assert_false(exploded,
		"Drone should not explode on collision during SEARCHING")


func test_collision_distance() -> void:
	assert_eq(mock.COLLISION_DISTANCE, 30.0,
		"Collision distance should be 30 px")


# ============================================================================
# HP and damage tests
# ============================================================================


func test_drone_hp_unchanged_at_two() -> void:
	assert_eq(mock.get_hp(), 2,
		"Drone should still have 2 HP")


func test_drone_survives_one_hit() -> void:
	var destroyed := mock.take_damage(1)
	assert_false(destroyed, "Drone should survive 1 hit")
	assert_eq(mock.get_hp(), 1, "HP should be 1 after 1 hit")


func test_drone_destroyed_after_two_hits() -> void:
	mock.take_damage(1)
	var destroyed := mock.take_damage(1)
	assert_true(destroyed, "Drone should be destroyed after 2 hits")
	assert_false(mock.is_alive(), "Drone should be dead")
	assert_eq(mock.get_hp(), 0, "HP should be 0")


func test_no_damage_when_dead() -> void:
	mock.take_damage(2)
	var extra := mock.take_damage(1)
	assert_false(extra, "No further damage when already dead")


# ============================================================================
# Audio constants tests
# ============================================================================


func test_beep_frequency() -> void:
	assert_eq(mock.BEEP_FREQUENCY, 880.0,
		"Beep frequency should be 880 Hz (high-pitched alarm)")


func test_beeps_per_group() -> void:
	assert_eq(mock.BEEPS_PER_GROUP, 3,
		"Should play 3 short beeps then pause (morse-code feel)")


# ============================================================================
# Source file verification tests
# ============================================================================


func test_drone_component_has_searching_state() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/components/drone_component.gd")
	assert_true(source.contains("SEARCHING"),
		"DroneComponent should have SEARCHING state")


func test_drone_component_has_combat_state() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/components/drone_component.gd")
	assert_true(source.contains("COMBAT"),
		"DroneComponent should have COMBAT state")


func test_drone_component_has_explosion() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/components/drone_component.gd")
	assert_true(source.contains("_explode"),
		"DroneComponent should have _explode method")


func test_drone_component_has_drift() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/components/drone_component.gd")
	assert_true(source.contains("DRIFT_TURN_FACTOR"),
		"DroneComponent should have drift turn factor")


func test_drone_component_has_beep() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/components/drone_component.gd")
	assert_true(source.contains("_play_beep"),
		"DroneComponent should have _play_beep method")


func test_drone_component_has_360_vision() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/components/drone_component.gd")
	# 360° vision = no FOV angle check, only line-of-sight
	assert_true(source.contains("_check_player_visibility"),
		"DroneComponent should have player visibility check")
	assert_false(source.contains("_is_position_in_fov"),
		"DroneComponent should NOT use FOV cone (360° vision)")


func test_drone_component_no_wall_penetration() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/components/drone_component.gd")
	assert_false(source.contains("WallBreachHelper"),
		"DroneComponent should NOT use WallBreachHelper (no wall penetration)")
	assert_false(source.contains("open_wall_passage"),
		"DroneComponent explosion should NOT penetrate walls")


func test_drone_scene_has_navigation_agent() -> void:
	var source := FileAccess.get_file_as_string("res://scenes/objects/Drone.tscn")
	assert_true(source.contains("NavigationAgent2D"),
		"Drone scene should have NavigationAgent2D for obstacle avoidance")


func test_drone_scene_has_raycast() -> void:
	var source := FileAccess.get_file_as_string("res://scenes/objects/Drone.tscn")
	assert_true(source.contains("RayCast2D"),
		"Drone scene should have RayCast2D for line-of-sight checks")


func test_drone_gd_has_led_sprite() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/objects/drone.gd")
	assert_true(source.contains("_led_sprite"),
		"drone.gd should have LED sprite reference for color changes")


func test_drone_gd_has_combat_entered_handler() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/objects/drone.gd")
	assert_true(source.contains("_on_combat_entered"),
		"drone.gd should handle combat_entered signal")
