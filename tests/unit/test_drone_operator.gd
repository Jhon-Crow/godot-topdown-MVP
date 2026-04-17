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
# DroneOperatorComponent teleport evasion tests (Issue #1664)
# In ACTIVE phase the operator uses EnemyTeleportComponent — same behavior as
# the teleport enemy: teleport to cover under fire, teleport on first bullet, etc.
# ============================================================================


class MockDroneOperatorTeleport:
	## Simulates DroneOperatorComponent teleport evasion for testing (Issue #1664).
	## Mirrors EnemyTeleportComponent interface as used by the drone operator.

	const TELEPORT_COOLDOWN: float = 5.0
	const MIN_DISTANCE: float = 10.0

	enum Phase { DEPLOYING, CONTROLLING, ACTIVE }

	var _phase: Phase = Phase.ACTIVE
	var _cooldown_timer: float = 0.0
	var _teleport_count: int = 0
	var _last_target: Vector2 = Vector2.ZERO

	func is_teleport_ready() -> bool:
		return _phase == Phase.ACTIVE and _cooldown_timer <= 0.0

	func try_teleport(target: Vector2) -> bool:
		if not is_teleport_ready():
			return false
		if target == Vector2.ZERO:
			return false
		if target.length() < MIN_DISTANCE:
			return false
		_last_target = target
		_cooldown_timer = TELEPORT_COOLDOWN
		_teleport_count += 1
		return true

	func try_damage_teleport(cover_position: Vector2, flank_target: Vector2) -> bool:
		if not is_teleport_ready():
			return false
		if cover_position != Vector2.ZERO and try_teleport(cover_position):
			return true
		if flank_target != Vector2.ZERO and try_teleport(flank_target):
			return true
		return false

	func update_teleport(delta: float) -> void:
		if _cooldown_timer > 0.0:
			_cooldown_timer -= delta

	func is_controlling_drone() -> bool:
		return _phase == Phase.CONTROLLING

	func get_phase() -> Phase:
		return _phase


var mock_operator: MockDroneOperatorTeleport


func test_operator_teleport_ready_in_active_phase() -> void:
	## Issue #1664: teleport must be available in ACTIVE phase when off cooldown.
	mock_operator = MockDroneOperatorTeleport.new()
	assert_true(mock_operator.is_teleport_ready(),
		"Teleport should be ready in ACTIVE phase when off cooldown")


func test_operator_teleport_succeeds_to_valid_target() -> void:
	## Issue #1664: try_teleport() must succeed when target is valid and teleport is ready.
	mock_operator = MockDroneOperatorTeleport.new()
	var result: bool = mock_operator.try_teleport(Vector2(200, 100))
	assert_true(result,
		"try_teleport() should succeed with a valid target in ACTIVE phase")


func test_operator_teleport_goes_on_cooldown_after_use() -> void:
	## Issue #1664: after teleporting, teleport must be on cooldown.
	mock_operator = MockDroneOperatorTeleport.new()
	mock_operator.try_teleport(Vector2(200, 100))
	assert_false(mock_operator.is_teleport_ready(),
		"Teleport should be on cooldown after use")


func test_operator_teleport_cooldown_expires_after_time() -> void:
	## Issue #1664: teleport cooldown must expire after TELEPORT_COOLDOWN seconds.
	mock_operator = MockDroneOperatorTeleport.new()
	mock_operator.try_teleport(Vector2(200, 100))
	mock_operator.update_teleport(MockDroneOperatorTeleport.TELEPORT_COOLDOWN + 0.1)
	assert_true(mock_operator.is_teleport_ready(),
		"Teleport should be ready again after cooldown expires")


func test_operator_cannot_teleport_while_on_cooldown() -> void:
	## Issue #1664: second teleport attempt must fail while on cooldown.
	mock_operator = MockDroneOperatorTeleport.new()
	mock_operator.try_teleport(Vector2(200, 100))
	var second_result: bool = mock_operator.try_teleport(Vector2(300, 200))
	assert_false(second_result,
		"Cannot teleport while on cooldown")


func test_operator_cannot_teleport_in_controlling_phase() -> void:
	## Issue #1664: operator must not teleport in CONTROLLING phase (defenseless).
	mock_operator = MockDroneOperatorTeleport.new()
	mock_operator._phase = MockDroneOperatorTeleport.Phase.CONTROLLING
	var result: bool = mock_operator.try_teleport(Vector2(200, 100))
	assert_false(result,
		"Operator should not teleport in CONTROLLING phase (defenseless)")


func test_operator_cannot_teleport_in_deploying_phase() -> void:
	## Issue #1664: operator must not teleport in DEPLOYING phase.
	mock_operator = MockDroneOperatorTeleport.new()
	mock_operator._phase = MockDroneOperatorTeleport.Phase.DEPLOYING
	var result: bool = mock_operator.try_teleport(Vector2(200, 100))
	assert_false(result,
		"Operator should not teleport in DEPLOYING phase")


func test_operator_damage_teleport_uses_cover_first() -> void:
	## Issue #1664: try_damage_teleport must prefer cover_position over flank_target.
	mock_operator = MockDroneOperatorTeleport.new()
	var cover := Vector2(150, 0)
	var flank := Vector2(300, 0)
	var result: bool = mock_operator.try_damage_teleport(cover, flank)
	assert_true(result,
		"Damage teleport should succeed when cover position is valid")
	assert_eq(mock_operator._last_target, cover,
		"Damage teleport should prefer cover position over flank target")


func test_operator_damage_teleport_uses_flank_if_no_cover() -> void:
	## Issue #1664: try_damage_teleport must fall back to flank_target if cover is zero.
	mock_operator = MockDroneOperatorTeleport.new()
	var flank := Vector2(300, 0)
	var result: bool = mock_operator.try_damage_teleport(Vector2.ZERO, flank)
	assert_true(result,
		"Damage teleport should use flank target when cover position is zero")
	assert_eq(mock_operator._last_target, flank,
		"Damage teleport should fall back to flank target")


func test_operator_damage_teleport_fails_if_both_zero() -> void:
	## Issue #1664: try_damage_teleport must fail when both positions are zero.
	mock_operator = MockDroneOperatorTeleport.new()
	var result: bool = mock_operator.try_damage_teleport(Vector2.ZERO, Vector2.ZERO)
	assert_false(result,
		"Damage teleport should fail when both cover and flank are zero")


func test_operator_is_defenseless_during_controlling() -> void:
	mock_operator = MockDroneOperatorTeleport.new()
	mock_operator._phase = MockDroneOperatorTeleport.Phase.CONTROLLING
	assert_true(mock_operator.is_controlling_drone(),
		"Operator should be defenseless while controlling drone")


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


func test_enemy_script_applies_teleport_in_active_phase() -> void:
	## Issue #1664: in ACTIVE phase, drone operator must try to teleport to cover under fire.
	var file := FileAccess.open("res://scripts/objects/enemy.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open enemy.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains("try_damage_teleport") and source.contains("_drone_operator"),
		"enemy.gd must call _drone_operator.try_damage_teleport() for bullet evasion (Issue #1664)")


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


func test_drone_operator_uses_teleport_evasion() -> void:
	## Issue #1664: drone operator ACTIVE phase must use EnemyTeleportComponent for evasion.
	var file := FileAccess.open("res://scripts/components/drone_operator_component.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open drone_operator_component.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains("EnemyTeleportComponent"),
		"drone_operator_component.gd must use EnemyTeleportComponent for evasion (Issue #1664)")
	assert_true(source.contains("_setup_teleport_component"),
		"drone_operator_component.gd must call _setup_teleport_component() in ACTIVE phase (Issue #1664)")


func test_enemy_combat_state_handles_drone_operator_teleport() -> void:
	## Issue #1664: enemy.gd COMBAT state must handle drone operator teleport evasion
	## the same way it handles normal teleporter — teleport to cover under fire.
	var file := FileAccess.open("res://scripts/objects/enemy.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open enemy.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains("_drone_operator.try_teleport"),
		"enemy.gd COMBAT state must call _drone_operator.try_teleport() for evasion (Issue #1664)")
	assert_true(source.contains("_drone_operator.is_teleport_ready"),
		"enemy.gd COMBAT state must check _drone_operator.is_teleport_ready() (Issue #1664)")


func test_teleport_component_added_to_parent_not_self() -> void:
	## Issue #1664 regression: EnemyTeleportComponent must be added as a child of _parent
	## (the CharacterBody2D enemy), NOT of the DroneOperatorComponent (Node).
	##
	## Root cause of "не телепортируется" bug (2026-03-28 game log):
	##   EnemyTeleportComponent._ready() resolves its reference via:
	##       _parent = get_parent() as CharacterBody2D
	##   If the parent is DroneOperatorComponent (a plain Node), the cast returns null,
	##   _ready_flag = false, and is_ready() always returns false — teleport never fires.
	##
	## This test verifies that _setup_teleport_component() adds the child to _parent.
	var file := FileAccess.open("res://scripts/components/drone_operator_component.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open drone_operator_component.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	# The fix is: _parent.add_child(_teleport_component) NOT add_child(_teleport_component)
	# Find the _setup_teleport_component function body
	var func_start: int = source.find("func _setup_teleport_component()")
	assert_gt(func_start, 0, "_setup_teleport_component() function must exist")
	var func_end: int = source.find("\nfunc ", func_start + 1)
	var func_body: String = source.substr(func_start, func_end - func_start) if func_end > 0 else source.substr(func_start)
	assert_true(func_body.contains("_parent.add_child"),
		"_setup_teleport_component() must add teleport component to _parent (CharacterBody2D), not to self (DroneOperatorComponent). " +
		"Regression: adding to self causes get_parent() as CharacterBody2D to return null → _ready_flag=false → teleport never fires (Issue #1664 game log 2026-03-28).")


func test_drone_operator_active_does_not_use_machete_melee_in_combat() -> void:
	## Issue #1664: Drone operator ACTIVE phase must NOT use machete melee attack logic.
	var file := FileAccess.open("res://scripts/objects/enemy.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open enemy.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	# Find the drone operator ACTIVE block
	var drone_block_start: int = source.find("# Issue #1664: Drone operator ACTIVE")
	assert_gt(drone_block_start, 0,
		"enemy.gd must contain the Issue #1664 drone operator ACTIVE block")
	var block_end: int = source.find("# Issue #1667", drone_block_start)
	assert_gt(block_end, 0,
		"There should be an Issue #1667 comment after the drone operator block")
	var drone_block: String = source.substr(drone_block_start, block_end - drone_block_start)
	assert_false(drone_block.contains("perform_melee_attack"),
		"Drone operator ACTIVE block must NOT call perform_melee_attack (Issue #1664)")
	assert_false(drone_block.contains("is_backstab_opportunity"),
		"Drone operator ACTIVE block must NOT use machete backstab approach (Issue #1664)")


# ============================================================================
# Issue #1744: Pacifist drone operator must not switch to COMBAT on drone death
# ============================================================================


class MockPacifistDroneOperator:
	## Simulates the drone destruction → active phase transition logic, with pacifist guard.
	## Mirrors the fix in drone_operator_component.gd _transition_to_active() (Issue #1744).

	enum Phase { DEPLOYING, CONTROLLING, ACTIVE }
	const COMBAT_STATE: int = 1
	const PACIFIST_STATE: int = 15

	var _phase: Phase = Phase.CONTROLLING
	var _parent_state: int = PACIFIST_STATE  # starts pacifist
	var _parent_is_pacifist: bool = true

	## Fixed version: checks pacifist status before forcing COMBAT (Issue #1744).
	func on_drone_destroyed() -> void:
		_phase = Phase.ACTIVE
		if not _parent_is_pacifist:
			_parent_state = COMBAT_STATE

	## Buggy version: always forces COMBAT (pre-fix behavior).
	func on_drone_destroyed_buggy() -> void:
		_phase = Phase.ACTIVE
		_parent_state = COMBAT_STATE  # Bug: no pacifist check


func test_pacifist_operator_stays_pacifist_when_drone_destroyed() -> void:
	## Issue #1744: pacifist drone operator must NOT transition to COMBAT when drone dies.
	var op := MockPacifistDroneOperator.new()
	op._parent_is_pacifist = true
	op._parent_state = MockPacifistDroneOperator.PACIFIST_STATE
	op.on_drone_destroyed()
	assert_ne(op._parent_state, MockPacifistDroneOperator.COMBAT_STATE,
		"Pacifist drone operator must NOT enter COMBAT when drone is destroyed (Issue #1744)")
	assert_eq(op._phase, MockPacifistDroneOperator.Phase.ACTIVE,
		"Phase must switch to ACTIVE even when pacifist (no more drone)")


func test_non_pacifist_operator_enters_combat_when_drone_destroyed() -> void:
	## Non-pacifist operator should still enter COMBAT when drone is destroyed.
	var op := MockPacifistDroneOperator.new()
	op._parent_is_pacifist = false
	op._parent_state = 0  # some non-pacifist state
	op.on_drone_destroyed()
	assert_eq(op._parent_state, MockPacifistDroneOperator.COMBAT_STATE,
		"Non-pacifist drone operator must enter COMBAT when drone is destroyed")


func test_buggy_operator_wrongly_forces_combat_on_pacifist() -> void:
	## Regression test: the buggy version (before fix) would override pacifist state.
	var op := MockPacifistDroneOperator.new()
	op._parent_is_pacifist = true
	op._parent_state = MockPacifistDroneOperator.PACIFIST_STATE
	op.on_drone_destroyed_buggy()
	## Assert that the BUG occurs — documents the pre-fix behavior.
	assert_eq(op._parent_state, MockPacifistDroneOperator.COMBAT_STATE,
		"Buggy version forces COMBAT even on pacifist (this is the pre-fix bug we fixed)")


func test_drone_operator_pacifist_guard_in_source() -> void:
	## Issue #1744: _transition_to_active() must check is_pacifist() before forcing COMBAT.
	var file := FileAccess.open("res://scripts/components/drone_operator_component.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open drone_operator_component.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains("is_pacifist"),
		"drone_operator_component.gd must check is_pacifist() before forcing COMBAT in _transition_to_active() (Issue #1744)")
	assert_true(source.contains("1744"),
		"drone_operator_component.gd must reference Issue #1744 in the pacifist guard comment")


func test_drone_operator_update_returns_early_when_parent_is_pacifist() -> void:
	## Issue #1868: level-7 pacifist operators must not deploy drones or keep controlling them.
	var file := FileAccess.open("res://scripts/components/drone_operator_component.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open drone_operator_component.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	var update_start: int = source.find("func update(delta: float) -> void:")
	assert_gt(update_start, 0, "drone_operator_component.gd must define update()")
	var next_func: int = source.find("func get_phase()", update_start)
	assert_gt(next_func, update_start, "get_phase() should follow update()")
	var update_body: String = source.substr(update_start, next_func - update_start)
	assert_true(update_body.contains("_parent_is_pacifist()"),
		"DroneOperatorComponent.update() must check parent pacifism before phase updates")
	assert_true(update_body.contains("return"),
		"DroneOperatorComponent.update() must return early for pacifist operators")
	assert_true(source.contains("Issue #1868"),
		"DroneOperatorComponent must document the Issue #1868 pacifist operator guard")


func test_enemy_physics_blocks_pacifist_operator_phase_control_before_deploying() -> void:
	## Issue #1868: enemy.gd must not run the normal DEPLOYING/CONTROLLING branch for pacifist operators.
	var file := FileAccess.open("res://scripts/objects/enemy.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open enemy.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	var pacifist_guard: int = source.find("Issue #1868: pacifist operators")
	var phase_control: int = source.find("Issue #1397: drone operator phase control")
	assert_gt(pacifist_guard, 0,
		"enemy.gd must contain a pacifist drone-operator guard for Issue #1868")
	assert_gt(phase_control, pacifist_guard,
		"The Issue #1868 pacifist guard must run before normal drone-operator phase control")
	assert_true(source.contains("_aggression.set_aggressive(false)"),
		"Pacifist transition must clear aggression so pacifists cannot keep aggressive behavior")


func test_enemy_pacifist_retaliation_uses_attacker_node() -> void:
	## Issue #1744 follow-up: when another enemy hits a pacifist, retaliation targets that enemy, not the player.
	var file := FileAccess.open("res://scripts/objects/enemy.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open enemy.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains("attacker_node: Node2D = null"),
		"enemy.gd hit handler must accept the actual attacker node")
	assert_true(source.contains("var retaliation_target: Node2D = attacker_node"),
		"pacifist retaliation must prefer the actual attacker node over _player")
	assert_false(source.contains("_pacifist.start_retaliation(_player);"),
		"pacifist retaliation must not always target the player")


func test_projectile_hit_forwarding_passes_shooter_node() -> void:
	## Enemy bullets carry shooter_id; hit forwarding must preserve the shooter node for pacifist retaliation.
	var file := FileAccess.open("res://scripts/projectiles/bullet.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open bullet.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains("func _get_shooter_node() -> Node2D"),
		"bullet.gd must resolve shooter_id to a Node2D")
	assert_true(source.contains("var attacker_node := _get_shooter_node()"),
		"bullet.gd must pass shooter node through hit callbacks")
	assert_true(source.contains("effective_damage, from_player, attacker_node"),
		"bullet.gd damage hit path must include attacker_node")
	assert_false(source.contains("1.0, from_player, attacker_node"),
		"bullet.gd legacy bullet-info path must not hardcode damage before source data")
	assert_true(source.contains("_has_penetrated, effective_damage, from_player, attacker_node"),
		"bullet.gd legacy bullet-info path must pass effective_damage before source data so player damage is not false/0")
	assert_true(source.contains("func _supports_explicit_bullet_damage"),
		"bullet.gd must distinguish damage-aware direct targets from legacy six-argument hit areas")
	assert_true(source.contains("_has_penetrated, from_player, attacker_node"),
		"bullet.gd must keep legacy hit-area calls in the old six-argument source-data shape")


func test_hit_areas_forward_attacker_node() -> void:
	## Hit areas sit between bullets and enemies, so both normal and shield hit areas must forward attacker_node.
	for path in ["res://scripts/objects/hit_area.gd", "res://scripts/components/shield_hit_area.gd"]:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			gut.p("Cannot open %s — skipping (export build)" % path)
			pass_test("Skipped in export build")
			continue
		var source := file.get_as_text()
		file.close()
		assert_true(source.contains("attacker_node: Node2D = null"),
			"%s must accept optional attacker_node" % path)
		assert_true(source.contains("is_from_player, attacker_node"),
			"%s must forward attacker_node with hit source data" % path)


func test_attacker_node_signature_compatibility_for_existing_targets() -> void:
	## Issue #1744 follow-up: every bullet-info receiver must tolerate the new optional attacker_node.
	var expected_signatures := {
		"res://scripts/characters/player.gd": "_attacker_node: Node2D = null",
		"res://scripts/objects/drone.gd": "_attacker_node: Node2D = null",
		"res://scripts/effects/illusion_hit_area.gd": "_attacker_node: Node2D = null",
		"res://scripts/projectiles/rpg_rocket.gd": "_attacker_node: Node2D = null",
		"res://scripts/projectiles/bullet.gd": "_attacker_node: Node2D = null"
	}
	for path in expected_signatures.keys():
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			gut.p("Cannot open %s — skipping (export build)" % path)
			pass_test("Skipped in export build")
			continue
		var source := file.get_as_text()
		file.close()
		assert_true(source.contains(expected_signatures[path]),
			"%s bullet-info receiver must accept optional attacker_node so enemy bullets still damage the player and other targets" % path)


func test_csharp_player_accepts_attacker_node_bullet_info_overload() -> void:
	## Issue #1744 follow-up: GDScript bullet.gd calls Player with seven args after attacker forwarding.
	var file := FileAccess.open("res://Scripts/Characters/Player.cs", FileAccess.READ)
	if file == null:
		gut.p("Cannot open Player.cs — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains("float damage, bool isFromPlayer, Node2D? attackerNode"),
		"C# Player must expose the seven-argument bullet-info overload used by GDScript bullet.gd")
	assert_true(source.contains("damage, isFromPlayer);"),
		"seven-argument Player overload should preserve explicit damage and delegate to the existing damage path")
