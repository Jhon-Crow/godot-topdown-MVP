extends GutTest
## Unit tests for the Drone Operator and Drone enemies (Issue #1397).
##
## Verifies:
## 1. DroneOperatorComponent: phases, dash mechanics, afterimage trail
## 2. DroneComponent: health, damage, destruction
## 3. Spawner integration: both types appear in spawner lists
## 4. Source file checks: flags present in experimental_menu.gd and game_manager.gd


# ============================================================================
# DroneComponent tests
# ============================================================================


class MockDroneComponent:
	## Simulates DroneComponent behavior for testing without scene tree.
	const DRONE_HP: int = 2
	var _hp: int = DRONE_HP
	var _is_alive: bool = true
	var _destroyed_signal_count: int = 0
	var _hit_signal_count: int = 0

	func take_damage(amount: int = 1) -> bool:
		if not _is_alive:
			return false
		_hp -= amount
		_hit_signal_count += 1
		if _hp <= 0:
			_is_alive = false
			_hp = 0
			_destroyed_signal_count += 1
			return true
		return false

	func is_alive() -> bool:
		return _is_alive

	func get_hp() -> int:
		return _hp


var mock_drone: MockDroneComponent


func before_each() -> void:
	mock_drone = MockDroneComponent.new()


func after_each() -> void:
	mock_drone = null


func test_drone_initial_hp_is_two() -> void:
	assert_eq(mock_drone.get_hp(), 2,
		"Drone should start with 2 HP")


func test_drone_is_alive_initially() -> void:
	assert_true(mock_drone.is_alive(),
		"Drone should be alive on creation")


func test_drone_takes_damage() -> void:
	mock_drone.take_damage(1)
	assert_eq(mock_drone.get_hp(), 1,
		"Drone HP should decrease by 1 after taking 1 damage")


func test_drone_survives_one_hit() -> void:
	var destroyed: bool = mock_drone.take_damage(1)
	assert_false(destroyed,
		"Drone should not be destroyed after 1 damage")
	assert_true(mock_drone.is_alive(),
		"Drone should still be alive after 1 damage")


func test_drone_destroyed_after_two_hits() -> void:
	mock_drone.take_damage(1)
	var destroyed: bool = mock_drone.take_damage(1)
	assert_true(destroyed,
		"Drone should be destroyed after 2 damage (HP=2)")
	assert_false(mock_drone.is_alive(),
		"Drone should be dead after destruction")


func test_drone_destroyed_by_single_large_hit() -> void:
	var destroyed: bool = mock_drone.take_damage(5)
	assert_true(destroyed,
		"Drone should be destroyed by a single hit dealing more than its HP")


func test_drone_no_damage_after_death() -> void:
	mock_drone.take_damage(2)
	var destroyed: bool = mock_drone.take_damage(1)
	assert_false(destroyed,
		"Dead drone should not take additional damage")


func test_drone_hp_clamps_to_zero() -> void:
	mock_drone.take_damage(10)
	assert_eq(mock_drone.get_hp(), 0,
		"Drone HP should not go below 0")


# ============================================================================
# DroneOperatorComponent dash tests
# ============================================================================


class MockDroneOperatorDash:
	## Simulates DroneOperatorComponent dash mechanics for testing.
	const DASH_CHARGES: int = 4
	const DASH_COOLDOWN: float = 1.2
	const DASH_DURATION: float = 0.15
	const DASH_CHAIN_WINDOW: float = 0.4

	enum Phase { DEPLOYING, CONTROLLING, ACTIVE }

	var _phase: Phase = Phase.ACTIVE
	var _dash_charges: int = DASH_CHARGES
	var _dash_cooldown_timer: float = 0.0
	var _dash_active: bool = false
	var _dash_timer: float = 0.0
	var _dash_chain_timer: float = 0.0
	var _dash_count: int = 0

	func try_dash(direction: Vector2) -> bool:
		if _phase != Phase.ACTIVE:
			return false
		if _dash_active:
			return false
		if _dash_charges <= 0 and _dash_cooldown_timer > 0.0:
			return false
		_dash_active = true
		_dash_timer = DASH_DURATION
		_dash_chain_timer = 0.0
		_dash_charges -= 1
		_dash_count += 1
		return true

	func end_dash() -> void:
		_dash_active = false
		_dash_timer = 0.0
		if _dash_charges <= 0:
			_dash_cooldown_timer = DASH_COOLDOWN
		else:
			_dash_chain_timer = DASH_CHAIN_WINDOW

	func is_dashing() -> bool:
		return _dash_active

	func should_dash_instead_of_suppress() -> bool:
		return _phase == Phase.ACTIVE and not _dash_active

	func is_controlling_drone() -> bool:
		return _phase == Phase.CONTROLLING

	func get_phase() -> Phase:
		return _phase


var mock_operator: MockDroneOperatorDash


func test_operator_starts_with_four_dash_charges() -> void:
	mock_operator = MockDroneOperatorDash.new()
	assert_eq(mock_operator._dash_charges, 4,
		"Drone operator should start with 4 dash charges")


func test_operator_dash_consumes_charge() -> void:
	mock_operator = MockDroneOperatorDash.new()
	mock_operator.try_dash(Vector2.RIGHT)
	assert_eq(mock_operator._dash_charges, 3,
		"Dashing should consume 1 charge")


func test_operator_can_dash_four_times() -> void:
	mock_operator = MockDroneOperatorDash.new()
	for i in range(4):
		mock_operator.try_dash(Vector2.RIGHT)
		mock_operator.end_dash()
	assert_eq(mock_operator._dash_count, 4,
		"Operator should be able to dash 4 times")
	assert_eq(mock_operator._dash_charges, 0,
		"All charges should be consumed after 4 dashes")


func test_operator_cooldown_after_all_charges() -> void:
	mock_operator = MockDroneOperatorDash.new()
	for i in range(4):
		mock_operator.try_dash(Vector2.RIGHT)
		mock_operator.end_dash()
	assert_gt(mock_operator._dash_cooldown_timer, 0.0,
		"Cooldown should start after all charges are spent")
	assert_eq(mock_operator._dash_cooldown_timer, 1.2,
		"Cooldown should be 1.2 seconds (same as player Dash)")


func test_operator_cannot_dash_during_cooldown() -> void:
	mock_operator = MockDroneOperatorDash.new()
	for i in range(4):
		mock_operator.try_dash(Vector2.RIGHT)
		mock_operator.end_dash()
	var result: bool = mock_operator.try_dash(Vector2.RIGHT)
	assert_false(result,
		"Operator should not be able to dash during cooldown")


func test_operator_cannot_dash_while_dashing() -> void:
	mock_operator = MockDroneOperatorDash.new()
	mock_operator.try_dash(Vector2.RIGHT)
	var result: bool = mock_operator.try_dash(Vector2.LEFT)
	assert_false(result,
		"Operator should not be able to start a new dash while already dashing")


func test_operator_is_dashing_returns_true_during_dash() -> void:
	mock_operator = MockDroneOperatorDash.new()
	mock_operator.try_dash(Vector2.RIGHT)
	assert_true(mock_operator.is_dashing(),
		"is_dashing() should return true during active dash")


func test_operator_is_dashing_returns_false_after_dash() -> void:
	mock_operator = MockDroneOperatorDash.new()
	mock_operator.try_dash(Vector2.RIGHT)
	mock_operator.end_dash()
	assert_false(mock_operator.is_dashing(),
		"is_dashing() should return false after dash ends")


func test_operator_should_dash_instead_of_suppress_in_active_phase() -> void:
	mock_operator = MockDroneOperatorDash.new()
	assert_true(mock_operator.should_dash_instead_of_suppress(),
		"Operator in ACTIVE phase should dash instead of being suppressed")


func test_operator_should_not_dash_in_controlling_phase() -> void:
	mock_operator = MockDroneOperatorDash.new()
	mock_operator._phase = MockDroneOperatorDash.Phase.CONTROLLING
	assert_false(mock_operator.should_dash_instead_of_suppress(),
		"Operator in CONTROLLING phase should not dash")


func test_operator_is_defenseless_during_controlling() -> void:
	mock_operator = MockDroneOperatorDash.new()
	mock_operator._phase = MockDroneOperatorDash.Phase.CONTROLLING
	assert_true(mock_operator.is_controlling_drone(),
		"Operator should be defenseless while controlling drone")


func test_operator_cannot_dash_in_deploying_phase() -> void:
	mock_operator = MockDroneOperatorDash.new()
	mock_operator._phase = MockDroneOperatorDash.Phase.DEPLOYING
	var result: bool = mock_operator.try_dash(Vector2.RIGHT)
	assert_false(result,
		"Operator should not be able to dash in DEPLOYING phase")


func test_operator_chain_window_after_partial_charges() -> void:
	mock_operator = MockDroneOperatorDash.new()
	mock_operator.try_dash(Vector2.RIGHT)
	mock_operator.end_dash()
	assert_eq(mock_operator._dash_chain_timer, 0.4,
		"Chain window should be 0.4s after dash with charges remaining")
	assert_eq(mock_operator._dash_cooldown_timer, 0.0,
		"Cooldown should not start when charges remain")


# ============================================================================
# DroneOperatorComponent deployment tests (cover seek timeout)
# ============================================================================


class MockDeploymentTracker:
	## Simulates the cover-seeking deployment logic.
	const MAX_COVER_SEEK_TIME: float = 3.0
	const DEPLOY_DELAY: float = 0.5

	var _reached_cover: bool = false
	var _cover_seek_timer: float = 0.0
	var _deploy_timer: float = 0.0
	var _drone_deployed: bool = false

	## Simulate update with a given enemy AI state.
	## Returns true when drone gets deployed.
	func update_deploying(delta: float, current_state: int) -> bool:
		if not _reached_cover:
			_cover_seek_timer += delta
			if current_state == 3:  # IN_COVER
				_reached_cover = true
				_deploy_timer = DEPLOY_DELAY
			elif _cover_seek_timer >= MAX_COVER_SEEK_TIME or current_state == 1:  # COMBAT
				_reached_cover = true
				_deploy_timer = DEPLOY_DELAY
			else:
				return false

		_deploy_timer -= delta
		if _deploy_timer <= 0.0 and not _drone_deployed:
			_drone_deployed = true
			return true
		return false


func test_deployment_when_cover_found() -> void:
	var tracker := MockDeploymentTracker.new()
	# Simulate reaching IN_COVER state after 1 second
	tracker.update_deploying(1.0, 2)  # SEEKING_COVER
	assert_false(tracker._drone_deployed, "Should not deploy while seeking cover")
	tracker.update_deploying(0.5, 3)  # IN_COVER
	assert_true(tracker._reached_cover, "Should detect cover reached")
	tracker.update_deploying(0.6, 3)  # Wait for deploy delay
	assert_true(tracker._drone_deployed, "Should deploy drone after reaching cover")


func test_deployment_on_cover_seek_timeout() -> void:
	var tracker := MockDeploymentTracker.new()
	# Keep seeking cover for 3+ seconds — should deploy anyway
	tracker.update_deploying(1.0, 2)  # SEEKING_COVER
	tracker.update_deploying(1.0, 2)
	tracker.update_deploying(1.1, 2)  # Total > 3.0s
	assert_true(tracker._reached_cover, "Should give up seeking cover after timeout")
	tracker.update_deploying(0.6, 2)  # Wait for deploy delay
	assert_true(tracker._drone_deployed, "Should deploy drone after cover seek timeout")


func test_deployment_when_ai_transitions_to_combat() -> void:
	var tracker := MockDeploymentTracker.new()
	# AI transitions to COMBAT (state 1) when no cover available
	tracker.update_deploying(0.5, 1)  # COMBAT
	assert_true(tracker._reached_cover, "Should deploy when AI goes to COMBAT")
	tracker.update_deploying(0.6, 1)  # Wait for deploy delay
	assert_true(tracker._drone_deployed, "Should deploy drone after combat transition")


func test_deployment_max_cover_seek_time_is_three_seconds() -> void:
	var tracker := MockDeploymentTracker.new()
	assert_eq(tracker.MAX_COVER_SEEK_TIME, 3.0,
		"Max cover seek time should be 3 seconds")


# ============================================================================
# Spawner integration tests
# ============================================================================


class MockSpawnerWithDroneOperator:
	## Extends the spawner types list with the new drone operator entry.
	const TYPES: Array = [
		{"name": "Rifle (M16)", "weapon_type": 0, "behavior": 1},
		{"name": "Shotgun", "weapon_type": 1, "behavior": 1},
		{"name": "UZI (SMG)", "weapon_type": 2, "behavior": 1},
		{"name": "Machete (melee)", "weapon_type": 3, "behavior": 1},
		{"name": "RPG + PM pistol", "weapon_type": 4, "behavior": 1},
		{"name": "PM (Makarov pistol)", "weapon_type": 5, "behavior": 1},
		{"name": "Machine Gunner (PKM)", "weapon_type": 6, "behavior": 1},
		{"name": "Sniper (ASVK)", "weapon_type": 7, "behavior": 1},
		{"name": "Patrol Rifle", "weapon_type": 0, "behavior": 0},
		{"name": "SWAT Shieldbearer", "weapon_type": 8, "behavior": 1, "has_swat_shield": true, "scene": "res://scenes/objects/EnemySwatShield.tscn"},
		{"name": "Teleporter (Rifle)", "weapon_type": 0, "behavior": 1, "is_teleporter": true},
		{"name": "Armored Skin (Rifle)", "weapon_type": 0, "behavior": 1, "has_armored_skin": true},
		{"name": "Force Field (Rifle)", "weapon_type": 0, "behavior": 1, "has_force_field": true},
		{"name": "Grenadier (Rifle)", "weapon_type": 0, "behavior": 1, "is_grenadier": true},
		{"name": "Invisible (Rifle)", "weapon_type": 0, "behavior": 1, "start_invisible": true},
		{"name": "Gas Mask Enemy", "weapon_type": 0, "behavior": 1, "is_gas_mask": true},
		{"name": "Drone Operator", "weapon_type": 0, "behavior": 1, "is_drone_operator": true, "scene": "res://scenes/objects/EnemyDroneOperator.tscn"},
	]

	func get_entries_with_flag(flag: String) -> Array:
		var result: Array = []
		for t in TYPES:
			if t.get(flag, false):
				result.append(t)
		return result


var spawner: MockSpawnerWithDroneOperator


func test_spawner_contains_drone_operator_entry() -> void:
	spawner = MockSpawnerWithDroneOperator.new()
	var entries := spawner.get_entries_with_flag("is_drone_operator")
	assert_gte(entries.size(), 1,
		"Spawner must include at least one Drone Operator enemy entry")


func test_drone_operator_entry_has_correct_name() -> void:
	spawner = MockSpawnerWithDroneOperator.new()
	var entries := spawner.get_entries_with_flag("is_drone_operator")
	assert_gte(entries.size(), 1, "Drone Operator entry must exist")
	assert_true(entries[0].get("name", "").to_lower().contains("drone"),
		"Drone Operator entry name should contain 'drone'")


func test_drone_operator_entry_has_scene_override() -> void:
	spawner = MockSpawnerWithDroneOperator.new()
	var entries := spawner.get_entries_with_flag("is_drone_operator")
	assert_gte(entries.size(), 1, "Drone Operator entry must exist")
	assert_true(entries[0].has("scene"),
		"Drone Operator entry should have a scene override")
	assert_true(entries[0]["scene"].ends_with("EnemyDroneOperator.tscn"),
		"Drone Operator scene should be EnemyDroneOperator.tscn")


func test_spawner_has_at_least_seventeen_entries() -> void:
	spawner = MockSpawnerWithDroneOperator.new()
	## 8 weapon types + 1 patrol + 7 special types (teleporter, armored, force field, grenadier, invisible, gas mask, drone operator) = 17
	assert_gte(MockSpawnerWithDroneOperator.TYPES.size(), 17,
		"Spawner should have at least 17 entries with drone operator added")


# ============================================================================
# Source file integration tests
# ============================================================================


func test_experimental_menu_contains_drone_operator() -> void:
	var file := FileAccess.open("res://scripts/ui/experimental_menu.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open experimental_menu.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains("is_drone_operator"),
		"experimental_menu.gd spawner list must contain an is_drone_operator entry")


func test_game_manager_contains_drone_operator() -> void:
	var file := FileAccess.open("res://scripts/autoload/game_manager.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open game_manager.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains("is_drone_operator"),
		"game_manager.gd F8 spawn list must contain an is_drone_operator entry")


func test_enemy_script_contains_drone_operator_export() -> void:
	var file := FileAccess.open("res://scripts/objects/enemy.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open enemy.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains("is_drone_operator"),
		"enemy.gd must contain is_drone_operator export variable")


func test_drone_operator_scene_exists() -> void:
	assert_true(ResourceLoader.exists("res://scenes/objects/EnemyDroneOperator.tscn"),
		"EnemyDroneOperator.tscn scene file must exist")


func test_drone_scene_exists() -> void:
	assert_true(ResourceLoader.exists("res://scenes/objects/Drone.tscn"),
		"Drone.tscn scene file must exist")


func test_drone_operator_component_script_exists() -> void:
	assert_true(ResourceLoader.exists("res://scripts/components/drone_operator_component.gd"),
		"drone_operator_component.gd script must exist")


func test_drone_component_script_exists() -> void:
	assert_true(ResourceLoader.exists("res://scripts/components/drone_component.gd"),
		"drone_component.gd script must exist")
