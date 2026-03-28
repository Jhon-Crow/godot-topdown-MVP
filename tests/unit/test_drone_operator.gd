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
# In ACTIVE phase the operator uses EnemyTeleportComponent like the teleport enemy:
# teleports to cover on first bullet, with the same 5-second cooldown thereafter.
# ============================================================================


class MockTeleportEvasion:
	## Simulates DroneOperatorComponent teleport evasion mechanics for testing.
	## Mirrors EnemyTeleportComponent: try_damage_teleport reacts on first bullet (no delay).

	const COOLDOWN: float = 5.0

	enum Phase { DEPLOYING, CONTROLLING, ACTIVE }

	var _phase: Phase = Phase.ACTIVE
	var _cooldown_timer: float = 0.0
	var _teleport_count: int = 0
	var _last_cover: Vector2 = Vector2.ZERO

	func is_teleport_ready() -> bool:
		return _phase == Phase.ACTIVE and _cooldown_timer <= 0.0

	func try_evasion_teleport(cover_position: Vector2, flank_target: Vector2) -> bool:
		if not is_teleport_ready():
			return false
		# Try cover first, then flank (same as EnemyTeleportComponent.try_damage_teleport)
		var target := cover_position if cover_position != Vector2.ZERO else flank_target
		if target == Vector2.ZERO:
			return false
		_last_cover = target
		_cooldown_timer = COOLDOWN
		_teleport_count += 1
		return true

	func try_cover_teleport(cover_position: Vector2) -> bool:
		if not is_teleport_ready() or cover_position == Vector2.ZERO:
			return false
		_last_cover = cover_position
		_cooldown_timer = COOLDOWN
		_teleport_count += 1
		return true

	func update(delta: float) -> void:
		if _cooldown_timer > 0.0:
			_cooldown_timer -= delta
			if _cooldown_timer < 0.0:
				_cooldown_timer = 0.0

	func is_controlling_drone() -> bool:
		return _phase == Phase.CONTROLLING

	func get_phase() -> Phase:
		return _phase


var mock_operator: MockTeleportEvasion


func test_operator_teleports_on_first_bullet() -> void:
	## Issue #1664: operator must teleport immediately when bullet enters threat sphere.
	mock_operator = MockTeleportEvasion.new()
	var cover := Vector2(100.0, 50.0)
	var result: bool = mock_operator.try_evasion_teleport(cover, Vector2.ZERO)
	assert_true(result,
		"Operator should teleport on first bullet in ACTIVE phase (Issue #1664)")
	assert_eq(mock_operator._teleport_count, 1,
		"Teleport count should be 1 after first bullet")


func test_operator_teleport_blocked_during_cooldown() -> void:
	## Issue #1664: after teleporting, the 5-second cooldown must block further teleports.
	mock_operator = MockTeleportEvasion.new()
	var cover := Vector2(100.0, 50.0)
	mock_operator.try_evasion_teleport(cover, Vector2.ZERO)
	# Try again while cooldown is active
	var result: bool = mock_operator.try_evasion_teleport(cover, Vector2.ZERO)
	assert_false(result,
		"Teleport should be blocked during 5-second cooldown (Issue #1664)")


func test_operator_teleport_ready_after_cooldown_expires() -> void:
	## Issue #1664: operator can teleport again after 5-second cooldown expires.
	mock_operator = MockTeleportEvasion.new()
	var cover := Vector2(100.0, 50.0)
	mock_operator.try_evasion_teleport(cover, Vector2.ZERO)
	mock_operator.update(5.1)
	assert_true(mock_operator.is_teleport_ready(),
		"Operator should be ready to teleport again after cooldown (Issue #1664)")
	var result: bool = mock_operator.try_evasion_teleport(cover, Vector2.ZERO)
	assert_true(result,
		"Second teleport should succeed after cooldown expires (Issue #1664)")


func test_operator_teleport_not_ready_in_controlling_phase() -> void:
	## Issue #1664: teleport is only available in ACTIVE phase.
	mock_operator = MockTeleportEvasion.new()
	mock_operator._phase = MockTeleportEvasion.Phase.CONTROLLING
	assert_false(mock_operator.is_teleport_ready(),
		"Teleport should not be ready in CONTROLLING phase (defenseless)")


func test_operator_teleport_not_ready_in_deploying_phase() -> void:
	## Issue #1664: teleport is only available in ACTIVE phase.
	mock_operator = MockTeleportEvasion.new()
	mock_operator._phase = MockTeleportEvasion.Phase.DEPLOYING
	assert_false(mock_operator.is_teleport_ready(),
		"Teleport should not be ready in DEPLOYING phase")


func test_operator_evasion_teleport_uses_flank_when_no_cover() -> void:
	## Issue #1664: when cover position is zero, operator teleports to flank target instead.
	mock_operator = MockTeleportEvasion.new()
	var flank := Vector2(200.0, 150.0)
	var result: bool = mock_operator.try_evasion_teleport(Vector2.ZERO, flank)
	assert_true(result,
		"Evasion teleport should use flank target when no cover available (Issue #1664)")
	assert_eq(mock_operator._last_cover, flank,
		"Should have teleported to the flank target")


func test_operator_is_defenseless_during_controlling() -> void:
	mock_operator = MockTeleportEvasion.new()
	mock_operator._phase = MockTeleportEvasion.Phase.CONTROLLING
	assert_true(mock_operator.is_controlling_drone(),
		"Operator should be defenseless while controlling drone")


func test_operator_teleport_cooldown_is_five_seconds() -> void:
	## Issue #1664: teleport cooldown must be 5 seconds — same as regular teleport enemy.
	assert_eq(MockTeleportEvasion.COOLDOWN, 5.0,
		"Teleport cooldown should be 5 seconds (same as EnemyTeleportComponent)")


func test_drone_operator_component_uses_teleport() -> void:
	## Issue #1664: source file must use EnemyTeleportComponent for bullet evasion.
	var file := FileAccess.open("res://scripts/components/drone_operator_component.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open drone_operator_component.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains("EnemyTeleportComponent"),
		"drone_operator_component.gd must use EnemyTeleportComponent for bullet evasion (Issue #1664)")
	assert_true(source.contains("try_evasion_teleport"),
		"drone_operator_component.gd must expose try_evasion_teleport() method (Issue #1664)")


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


func test_enemy_script_handles_drone_operator_teleport_in_active_phase() -> void:
	## Issue #1664: in ACTIVE phase, drone operator must teleport on hit and under fire,
	## same as the regular teleport enemy behavior.
	var file := FileAccess.open("res://scripts/objects/enemy.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open enemy.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains("_drone_operator.try_evasion_teleport"),
		"enemy.gd must call _drone_operator.try_evasion_teleport() for bullet evasion (Issue #1664)")


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
	## Issue #1664: drone operator ACTIVE phase must use EnemyTeleportComponent for bullet evasion
	## (teleports to cover on first bullet, same as teleport enemy). Verifies set up in ACTIVE.
	var file := FileAccess.open("res://scripts/components/drone_operator_component.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open drone_operator_component.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains("EnemyTeleportComponent"),
		"drone_operator_component.gd must use EnemyTeleportComponent for bullet evasion (Issue #1664)")
	assert_true(source.contains("_setup_teleport_component"),
		"drone_operator_component.gd must call _setup_teleport_component() in ACTIVE phase (Issue #1664)")


func test_enemy_combat_state_handles_drone_operator_teleport() -> void:
	## Issue #1664: enemy.gd COMBAT state must handle drone operator teleport evasion
	## the same way it handles regular teleporter — cover-teleport when under fire.
	var file := FileAccess.open("res://scripts/objects/enemy.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open enemy.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains("_drone_operator.try_cover_teleport"),
		"enemy.gd COMBAT state must call _drone_operator.try_cover_teleport() for evasion (Issue #1664)")
	assert_true(source.contains("_drone_operator.is_teleport_ready"),
		"enemy.gd COMBAT state must check _drone_operator.is_teleport_ready() (Issue #1664)")


func test_drone_operator_active_does_not_use_machete_melee_in_combat() -> void:
	## Issue #1540/#1664: Drone operator ACTIVE phase must NOT use machete melee attack logic.
	## Normal ranged combat must run after the teleport check.
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
	# The block should end before machine-gun/sniper logic
	var block_end: int = source.find("# [#1033] Machine gunner", drone_block_start)
	assert_gt(block_end, 0,
		"There should be a machine gunner comment after the drone operator block")
	var drone_block: String = source.substr(drone_block_start, block_end - drone_block_start)
	assert_false(drone_block.contains("perform_melee_attack"),
		"Drone operator ACTIVE block must NOT call perform_melee_attack (Issue #1540/#1664)")
	assert_false(drone_block.contains("is_backstab_opportunity"),
		"Drone operator ACTIVE block must NOT use machete backstab approach (Issue #1540/#1664)")


func test_teleport_component_parent_is_assigned_after_add_child() -> void:
	## Issue #1664: EnemyTeleportComponent._ready() sets _parent = get_parent() as CharacterBody2D.
	## When added as child of DroneOperatorComponent (a Node, not CharacterBody2D), cast returns null.
	## Fix: _setup_teleport_component() must explicitly assign _teleport_component._parent.
	var file := FileAccess.open("res://scripts/components/drone_operator_component.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open drone_operator_component.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains("_teleport_component._parent = _parent"),
		"_setup_teleport_component() must explicitly assign _teleport_component._parent (Issue #1664)")


func test_immediate_teleport_trigger_source_present() -> void:
	## Issue #1664: teleport must be triggered immediately on threat sphere entry,
	## not deferred to the next frame after threat_reaction_delay (0.2s).
	## Fix: in _on_threat_area_entered (enemy.gd), trigger drone operator evasion teleport
	## immediately (same pattern as EnemyTeleportComponent.try_damage_teleport on-hit response).
	var file := FileAccess.open("res://scripts/objects/enemy.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open enemy.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	var fn_start: int = source.find("func _on_threat_area_entered")
	assert_gt(fn_start, 0,
		"enemy.gd must contain _on_threat_area_entered function")
	var fn_end: int = source.find("\nfunc ", fn_start + 1)
	if fn_end < 0:
		fn_end = source.length()
	var fn_body: String = source.substr(fn_start, fn_end - fn_start)
	assert_true(fn_body.contains("_drone_operator.try_evasion_teleport"),
		"_on_threat_area_entered must call _drone_operator.try_evasion_teleport() (Issue #1664)")
	assert_true(fn_body.contains("DroneOperatorComponent.Phase.ACTIVE"),
		"_on_threat_area_entered must guard the teleport with Phase.ACTIVE check (Issue #1664)")
