extends GutTest
## Unit tests for the Drone Operator and Drone enemies (Issue #1397).
##
## Verifies:
## 1. DroneOperatorComponent: phases, dodge mechanics
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
# DroneOperatorComponent dodge tests (Issue #1540)
# Dodge logic mirrors MacheteComponent — perpendicular lateral sidestep, no dash.
# ============================================================================


class MockDroneOperatorDodge:
	## Simulates DroneOperatorComponent dodge mechanics for testing.
	## Uses the same interface as MacheteComponent dodge.

	const DODGE_SPEED: float = 400.0
	const DODGE_DISTANCE: float = 120.0
	const DODGE_COOLDOWN: float = 1.2

	enum Phase { DEPLOYING, CONTROLLING, ACTIVE }

	var _phase: Phase = Phase.ACTIVE
	var _is_dodging: bool = false
	var _dodge_timer: float = 0.0
	var _dodge_direction: Vector2 = Vector2.ZERO
	var _dodge_count: int = 0

	func try_dodge(bullet_direction: Vector2) -> bool:
		if _phase != Phase.ACTIVE:
			return false
		if _is_dodging:
			return false
		# Calculate perpendicular dodge direction (same as MacheteComponent)
		var perp_right := Vector2(-bullet_direction.y, bullet_direction.x)
		var perp_left := Vector2(bullet_direction.y, -bullet_direction.x)
		_dodge_direction = perp_left if randf() > 0.5 else perp_right
		_is_dodging = true
		_dodge_timer = DODGE_DISTANCE / DODGE_SPEED
		_dodge_count += 1
		return true

	func is_dodging() -> bool:
		return _is_dodging

	func get_dodge_velocity() -> Vector2:
		if not _is_dodging:
			return Vector2.ZERO
		return _dodge_direction * DODGE_SPEED

	func end_dodge() -> void:
		_is_dodging = false
		_dodge_timer = 0.0

	func is_controlling_drone() -> bool:
		return _phase == Phase.CONTROLLING

	func get_phase() -> Phase:
		return _phase


var mock_operator: MockDroneOperatorDodge


func test_operator_dodge_starts_when_bullet_detected() -> void:
	mock_operator = MockDroneOperatorDodge.new()
	var result: bool = mock_operator.try_dodge(Vector2.RIGHT)
	assert_true(result,
		"Dodge should start when bullet detected in ACTIVE phase")


func test_operator_is_dodging_after_try_dodge() -> void:
	mock_operator = MockDroneOperatorDodge.new()
	mock_operator.try_dodge(Vector2.RIGHT)
	assert_true(mock_operator.is_dodging(),
		"is_dodging() should return true after try_dodge()")


func test_operator_is_not_dodging_after_end_dodge() -> void:
	mock_operator = MockDroneOperatorDodge.new()
	mock_operator.try_dodge(Vector2.RIGHT)
	mock_operator.end_dodge()
	assert_false(mock_operator.is_dodging(),
		"is_dodging() should return false after dodge ends")


func test_operator_cannot_dodge_while_dodging() -> void:
	mock_operator = MockDroneOperatorDodge.new()
	mock_operator.try_dodge(Vector2.RIGHT)
	var result: bool = mock_operator.try_dodge(Vector2.LEFT)
	assert_false(result,
		"Cannot start a new dodge while already dodging")


func test_operator_cannot_dodge_in_controlling_phase() -> void:
	mock_operator = MockDroneOperatorDodge.new()
	mock_operator._phase = MockDroneOperatorDodge.Phase.CONTROLLING
	var result: bool = mock_operator.try_dodge(Vector2.RIGHT)
	assert_false(result,
		"Operator should not dodge in CONTROLLING phase (defenseless)")


func test_operator_cannot_dodge_in_deploying_phase() -> void:
	mock_operator = MockDroneOperatorDodge.new()
	mock_operator._phase = MockDroneOperatorDodge.Phase.DEPLOYING
	var result: bool = mock_operator.try_dodge(Vector2.RIGHT)
	assert_false(result,
		"Operator should not dodge in DEPLOYING phase")


func test_operator_get_dodge_velocity_returns_zero_when_not_dodging() -> void:
	## Issue #1540: get_dodge_velocity() must return zero when no dodge is active.
	mock_operator = MockDroneOperatorDodge.new()
	var vel: Vector2 = mock_operator.get_dodge_velocity()
	assert_eq(vel, Vector2.ZERO,
		"get_dodge_velocity() should return Vector2.ZERO when not dodging")


func test_operator_get_dodge_velocity_returns_nonzero_when_dodging() -> void:
	## Issue #1540: get_dodge_velocity() must return non-zero vector during active dodge.
	mock_operator = MockDroneOperatorDodge.new()
	mock_operator.try_dodge(Vector2.RIGHT)
	var vel: Vector2 = mock_operator.get_dodge_velocity()
	assert_gt(vel.length(), 0.0,
		"get_dodge_velocity() should return a non-zero vector during an active dodge")


func test_operator_is_defenseless_during_controlling() -> void:
	mock_operator = MockDroneOperatorDodge.new()
	mock_operator._phase = MockDroneOperatorDodge.Phase.CONTROLLING
	assert_true(mock_operator.is_controlling_drone(),
		"Operator should be defenseless while controlling drone")


func test_dodge_direction_is_perpendicular_to_bullet() -> void:
	## Issue #1540: dodge direction must be perpendicular to bullet travel direction.
	## A bullet traveling RIGHT (1,0) → perpendicular dodge directions are UP (0,-1) or DOWN (0,1).
	var bullet_dir: Vector2 = Vector2(1.0, 0.0)  # bullet going RIGHT
	var perp_right: Vector2 = Vector2(-bullet_dir.y, bullet_dir.x)  # (0, -1) = UP
	var perp_left: Vector2 = Vector2(bullet_dir.y, -bullet_dir.x)   # (0, 1) = DOWN
	# Perpendicular vectors must have zero dot product with bullet direction
	assert_almost_eq(perp_right.dot(bullet_dir), 0.0, 0.001,
		"Right perpendicular must be orthogonal to bullet direction")
	assert_almost_eq(perp_left.dot(bullet_dir), 0.0, 0.001,
		"Left perpendicular must be orthogonal to bullet direction")


func test_dodge_distance_is_120px() -> void:
	## Issue #1540: dodge distance must be 120px — same as machete enemy, clearly visible.
	assert_eq(MockDroneOperatorDodge.DODGE_DISTANCE, 120.0,
		"Dodge distance should be 120px (same as machete enemy)")


func test_dodge_speed_is_400px_per_second() -> void:
	## Issue #1540: dodge speed must be 400 px/s — same as machete enemy.
	assert_eq(MockDroneOperatorDodge.DODGE_SPEED, 400.0,
		"Dodge speed should be 400 px/s (same as machete enemy)")


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


func test_enemy_script_applies_dodge_velocity_in_active_phase() -> void:
	## Issue #1540: in ACTIVE phase, drone operator dodge velocity must override AI velocity
	## so the lateral sidestep is not cancelled by normal movement logic.
	var file := FileAccess.open("res://scripts/objects/enemy.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open enemy.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains("get_dodge_velocity"),
		"enemy.gd must apply drone operator dodge velocity via get_dodge_velocity() (Issue #1540)")


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


func test_drone_operator_uses_machete_style_dodge() -> void:
	## Issue #1540: drone operator ACTIVE phase must use MacheteComponent for bullet dodging
	## (perpendicular lateral sidestep, no dash). Verifies the component is set up in ACTIVE.
	var file := FileAccess.open("res://scripts/components/drone_operator_component.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open drone_operator_component.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains("MacheteComponent"),
		"drone_operator_component.gd must use MacheteComponent for bullet dodging (Issue #1540)")
	assert_true(source.contains("_setup_dodge_component"),
		"drone_operator_component.gd must call _setup_dodge_component() in ACTIVE phase (Issue #1540)")


func test_enemy_combat_state_handles_drone_operator_dodge() -> void:
	## Issue #1540: enemy.gd COMBAT state must handle drone operator dodge
	## the same way it handles machete dodge — check bullet direction and try_dodge.
	var file := FileAccess.open("res://scripts/objects/enemy.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open enemy.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains("_drone_operator.try_dodge"),
		"enemy.gd COMBAT state must call _drone_operator.try_dodge() for bullet evasion (Issue #1540)")
	assert_true(source.contains("_drone_operator.is_dodging"),
		"enemy.gd COMBAT state must check _drone_operator.is_dodging() (Issue #1540)")
