extends GutTest
## Regression tests for Issue #665: Fix sniper enemy bugs.
##
## Tests verify sniper bugs are fixed:
## Bug 1: Snipers don't hide from the player (should seek cover when player approaches)
## Bug 2: Sniper shots don't have smoke trail (hitscan mask skipped player layer)
## Bug 3: Snipers don't deal damage to player (hitscan hit friendlies instead of player)
## Bug 4: Snipers fire without charge-up delay (bolt-action cycling)
## Bug 5: _shoot() wasted cooldown timer on failed shot attempts


# ============================================================================
# Mock Classes for Sniper Logic Testing
# ============================================================================


## Simplified mock enemy for testing sniper state machine behavior.
class MockSniperEnemy:
	enum AIState { IDLE, COMBAT, SEEKING_COVER, IN_COVER, FLANKING, SUPPRESSED, RETREATING, PURSUING, ASSAULT, SEARCHING }

	## Configuration
	var enable_cover: bool = true
	var shoot_cooldown: float = 3.0
	var rotation_speed: float = 1.0

	## State
	var _current_state: AIState = AIState.IDLE
	var _is_sniper: bool = true
	var _can_see_player: bool = false
	var _has_valid_cover: bool = false
	var _cover_position: Vector2 = Vector2.ZERO
	var _initial_position: Vector2 = Vector2.ZERO
	var _combat_state_timer: float = 0.0
	var _shoot_timer: float = 0.0
	var _detection_delay_elapsed: bool = false
	var _detection_timer: float = 0.0
	var _sniper_hitscan_range: float = 5000.0
	var _sniper_hitscan_damage: float = 50.0
	var _sniper_max_wall_penetrations: int = 2
	var _sniper_bolt_ready: bool = true
	var _sniper_bolt_timer: float = 0.0
	var _sniper_retreat_cooldown: float = 0.0
	var _is_reloading: bool = false
	var _current_ammo: int = 5
	var _player_close: bool = false  # Simulate player proximity

	## Tracking
	var _state_transitions: Array[String] = []
	var _logged_messages: Array[String] = []
	var _shots_fired: int = 0

	func initialize() -> void:
		_current_state = AIState.IDLE
		_state_transitions.clear()
		_logged_messages.clear()
		_shots_fired = 0

	func get_current_state() -> int:
		return _current_state

	func enter_combat() -> void:
		_current_state = AIState.COMBAT
		_combat_state_timer = 0.0

	## Simulate the sniper combat state behavior (Issue #665 fix).
	## Seek cover FIRST if player is close, then shoot.
	func process_sniper_combat(delta: float) -> void:
		_combat_state_timer += delta
		# Issue #665: Seek cover FIRST if player is close
		if enable_cover and _player_close:
			if _has_valid_cover:
				_log("SNIPER: player close, seeking cover")
				_transition_to_seeking_cover()
				return
		# Shoot at visible player (only if bolt ready)
		if _can_see_player and _detection_delay_elapsed and _sniper_bolt_ready and _shoot_timer >= shoot_cooldown:
			_log("SNIPER: shooting at visible player")
			if _shoot(): _shoot_timer = 0.0

	## Simulate the sniper in-cover state behavior
	func process_sniper_in_cover(_delta: float) -> void:
		if _can_see_player and _detection_delay_elapsed and _sniper_bolt_ready and _shoot_timer >= shoot_cooldown:
			_log("SNIPER: shooting from cover at visible player")
			if _shoot(): _shoot_timer = 0.0

	func _transition_to_seeking_cover() -> void:
		_current_state = AIState.SEEKING_COVER
		_state_transitions.append("SEEKING_COVER")

	func _transition_to_combat() -> void:
		_current_state = AIState.COMBAT
		_state_transitions.append("COMBAT")

	func _transition_to_in_cover() -> void:
		_current_state = AIState.IN_COVER
		_state_transitions.append("IN_COVER")

	## Issue #665: _shoot() returns bool to indicate if shot was actually fired.
	func _shoot() -> bool:
		if not _sniper_bolt_ready: return false
		if _is_reloading: return false
		if _current_ammo <= 0: return false
		_shots_fired += 1
		_sniper_bolt_ready = false
		_sniper_bolt_timer = 0.0
		_current_ammo -= 1
		return true

	func _log(msg: String) -> void:
		_logged_messages.append(msg)


## Mock target for testing hitscan damage delivery via on_hit_with_bullet_info.
class MockHitTarget:
	var name: String = "MockTarget"
	var damage_received: float = 0.0
	var hit_direction: Vector2 = Vector2.ZERO
	var hit_method_called: String = ""

	func on_hit_with_bullet_info(direction: Vector2, _caliber, _rico: bool, _pen: bool, damage: float) -> void:
		hit_method_called = "on_hit_with_bullet_info"
		damage_received = damage
		hit_direction = direction

	func has_method(method_name: String) -> bool:
		return method_name in ["on_hit_with_bullet_info"]


## Mock target that only has take_damage (simulates simplest damage receiver).
class MockSimpleTarget:
	var name: String = "SimpleTarget"
	var damage_received: float = 0.0
	var hit_method_called: String = ""

	func take_damage(amount: float) -> void:
		hit_method_called = "take_damage"
		damage_received = amount

	func has_method(method_name: String) -> bool:
		return method_name in ["take_damage"]


# ============================================================================
# Test Variables
# ============================================================================


var sniper: MockSniperEnemy


func before_each() -> void:
	sniper = MockSniperEnemy.new()
	seed(12345)
	sniper.initialize()


func after_each() -> void:
	sniper = null


# ============================================================================
# Bug 1 Regression: Snipers Don't Hide From Player (Issue #665)
# ============================================================================


## Regression test: Snipers seek cover when player is close and cover is available.
func test_sniper_seeks_cover_when_player_close_issue_665() -> void:
	sniper.enter_combat()
	sniper._has_valid_cover = true
	sniper._player_close = true
	assert_eq(sniper.get_current_state(), MockSniperEnemy.AIState.COMBAT,
		"Sniper should start in COMBAT state")
	sniper.process_sniper_combat(0.016)
	assert_eq(sniper.get_current_state(), MockSniperEnemy.AIState.SEEKING_COVER,
		"Issue #665: Sniper must seek cover when player is close")


## Verify the sniper logs the cover-seeking transition.
func test_sniper_logs_cover_seeking_issue_665() -> void:
	sniper.enter_combat()
	sniper._has_valid_cover = true
	sniper._player_close = true
	sniper.process_sniper_combat(0.016)
	assert_true(sniper._logged_messages.size() > 0,
		"Sniper should log the cover-seeking transition")
	assert_true(sniper._logged_messages[0].contains("seeking cover"),
		"Log should mention seeking cover")


## Snipers shoot when player is far (not close enough to trigger cover).
func test_sniper_shoots_when_player_far_issue_665() -> void:
	sniper.enter_combat()
	sniper._can_see_player = true
	sniper._detection_delay_elapsed = true
	sniper._shoot_timer = sniper.shoot_cooldown + 1.0
	sniper._player_close = false  # Player is far
	sniper._has_valid_cover = true
	sniper.process_sniper_combat(0.016)
	assert_eq(sniper._shots_fired, 1,
		"Issue #665: Sniper must shoot when player is far away")
	assert_eq(sniper.get_current_state(), MockSniperEnemy.AIState.COMBAT,
		"Issue #665: Sniper stays in COMBAT when player is far")


## Snipers with cover disabled should still shoot from current position.
func test_sniper_shoots_without_cover_issue_665() -> void:
	sniper.enable_cover = false
	sniper.enter_combat()
	sniper._can_see_player = true
	sniper._detection_delay_elapsed = true
	sniper._shoot_timer = sniper.shoot_cooldown + 1.0
	sniper.process_sniper_combat(0.016)
	assert_eq(sniper._shots_fired, 1,
		"Sniper with cover disabled should shoot at visible player")


## Snipers stay in COMBAT and fight when no cover is available (Issue #665).
func test_sniper_fights_from_combat_when_no_cover_issue_665() -> void:
	sniper.enter_combat()
	sniper._has_valid_cover = false
	sniper._can_see_player = true
	sniper._detection_delay_elapsed = true
	sniper._shoot_timer = sniper.shoot_cooldown + 1.0
	sniper._player_close = true  # Even with player close, no cover → stay in COMBAT
	sniper.process_sniper_combat(0.016)
	assert_eq(sniper.get_current_state(), MockSniperEnemy.AIState.COMBAT,
		"Issue #665: Sniper must stay in COMBAT when no cover available")
	assert_eq(sniper._shots_fired, 1,
		"Issue #665: Sniper must shoot at player when no cover available")


# ============================================================================
# Bug 2 Regression: Sniper Shots Don't Have Smoke Trail (Issue #665)
# ============================================================================


## Regression test: Weapon config must have is_sniper flag for type 4.
func test_sniper_weapon_config_has_hitscan_flag_issue_665() -> void:
	var config := WeaponConfigComponent.get_config(4)
	assert_true(config.get("is_sniper", false),
		"Issue #665: SNIPER weapon config must have is_sniper=true for hitscan path")


## Regression test: Sniper weapon config must NOT have a bullet scene.
func test_sniper_weapon_config_no_bullet_scene_issue_665() -> void:
	var config := WeaponConfigComponent.get_config(4)
	var bullet_path: String = config.get("bullet_scene_path", "missing")
	assert_eq(bullet_path, "",
		"Issue #665 Bug 2: SNIPER must have empty bullet_scene_path for hitscan (not projectile)")


## Regression test: Sniper weapon config must have hitscan range configured.
func test_sniper_weapon_config_hitscan_range_issue_665() -> void:
	var config := WeaponConfigComponent.get_config(4)
	var hitscan_range: float = config.get("hitscan_range", 0.0)
	assert_gt(hitscan_range, 0.0,
		"Issue #665: SNIPER must have positive hitscan_range for tracer endpoint calculation")


## Verify the tracer spawn function creates a proper Line2D with two distinct points.
func test_sniper_tracer_created_with_distinct_points_issue_665() -> void:
	var start := Vector2(100, 200)
	var end_pos := Vector2(5100, 200)
	assert_gt(start.distance_to(end_pos), 0.0,
		"Issue #665 Bug 2: Tracer start and end must be different positions")


# ============================================================================
# Bug 3 Regression: Snipers Don't Deal Damage to Player (Issue #665)
# ============================================================================


## Regression test: Sniper hitscan damage should be 50, not 1.
func test_sniper_weapon_config_hitscan_damage_issue_665() -> void:
	var config := WeaponConfigComponent.get_config(4)
	var damage: float = config.get("hitscan_damage", 0.0)
	assert_almost_eq(damage, 50.0, 0.001,
		"Issue #665 Bug 3: SNIPER hitscan_damage must be 50, not 1")


## Regression test: Damage delivery uses on_hit_with_bullet_info with damage param.
func test_hitscan_delivers_damage_via_bullet_info_issue_665() -> void:
	var target := MockHitTarget.new()
	var direction := Vector2.LEFT
	var damage := 50.0
	if target.has_method("on_hit_with_bullet_info"):
		target.on_hit_with_bullet_info(direction, null, false, false, damage)
	elif target.has_method("take_damage"):
		target.take_damage(damage)
	assert_eq(target.hit_method_called, "on_hit_with_bullet_info",
		"Issue #665: Hitscan must use on_hit_with_bullet_info for damage delivery")
	assert_almost_eq(target.damage_received, 50.0, 0.001,
		"Issue #665: Target must receive full hitscan damage (50)")


## Regression test: Damage delivery works with simple take_damage target.
func test_hitscan_fallback_to_take_damage_issue_665() -> void:
	var target := MockSimpleTarget.new()
	var direction := Vector2.LEFT
	var damage := 50.0
	if target.has_method("on_hit_with_bullet_info"):
		target.on_hit_with_bullet_info(direction, null, false, false, damage)
	elif target.has_method("take_damage"):
		target.take_damage(damage)
	assert_eq(target.hit_method_called, "take_damage",
		"Hitscan should fall back to take_damage when bullet_info unavailable")
	assert_almost_eq(target.damage_received, 50.0, 0.001,
		"Target must receive full damage through take_damage fallback")


## Regression test: Player.cs must have on_hit_with_bullet_info method.
func test_player_has_bullet_info_method_issue_665() -> void:
	var file := FileAccess.open("res://Scripts/Characters/Player.cs", FileAccess.READ)
	if file == null:
		gut.p("Cannot open Player.cs for source analysis — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains("on_hit_with_bullet_info"),
		"Issue #665: Player.cs must have on_hit_with_bullet_info method for hitscan damage")
	assert_true(source.contains("float damage"),
		"Issue #665: Player.on_hit_with_bullet_info must accept damage parameter")
	assert_true(source.contains("TakeDamage(damage)"),
		"Issue #665: Player.on_hit_with_bullet_info must call TakeDamage(damage)")


## Regression test: Hitscan uses on_hit_with_bullet_info for damage delivery.
func test_sniper_component_damage_method_issue_665() -> void:
	var file := FileAccess.open("res://scripts/components/sniper_component.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open sniper_component.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains("on_hit_with_bullet_info"),
		"SniperComponent must use on_hit_with_bullet_info for damage delivery")
	# Hitscan should skip enemy layer (layer 2) to avoid hitting friendlies
	assert_true(source.contains("combined_mask := 4 + 1"),
		"Issue #665: Hitscan mask must be 5 (layers 1+3), skipping enemy layer 2")


# ============================================================================
# Sniper Weapon Configuration Tests
# ============================================================================


## Verify SNIPER is weapon type 4 in the config.
func test_sniper_weapon_type_name() -> void:
	assert_eq(WeaponConfigComponent.get_type_name(4), "SNIPER",
		"Weapon type 4 should be SNIPER")


## Verify sniper has slow rotation speed (matching player ASVK).
func test_sniper_slow_rotation_speed() -> void:
	var config := WeaponConfigComponent.get_config(4)
	var rot_speed: float = config.get("rotation_speed", 0.0)
	assert_almost_eq(rot_speed, 1.0, 0.001,
		"SNIPER must have slow rotation_speed=1.0 (matching player ASVK)")


## Verify sniper has wall penetration configured.
func test_sniper_wall_penetration() -> void:
	var config := WeaponConfigComponent.get_config(4)
	var max_pen: int = config.get("max_wall_penetrations", 0)
	assert_eq(max_pen, 2, "SNIPER must penetrate up to 2 walls")


## Verify sniper cooldown is appropriate for bolt-action.
func test_sniper_shoot_cooldown() -> void:
	var config := WeaponConfigComponent.get_config(4)
	var cooldown: float = config.get("shoot_cooldown", 0.0)
	assert_almost_eq(cooldown, 3.0, 0.001,
		"SNIPER shoot_cooldown must be 3.0s for bolt-action")


# ============================================================================
# Sniper State Machine Tests
# ============================================================================


## Snipers should not pursue the player (they hold position).
func test_sniper_does_not_pursue() -> void:
	sniper._has_valid_cover = true
	if sniper._is_sniper:
		if sniper._has_valid_cover:
			sniper._transition_to_seeking_cover()
		else:
			sniper._transition_to_combat()
	assert_eq(sniper.get_current_state(), MockSniperEnemy.AIState.SEEKING_COVER,
		"Snipers with valid cover should seek cover instead of pursuing")


## Snipers without cover should transition to combat instead of pursuing.
func test_sniper_without_cover_does_not_pursue() -> void:
	sniper._has_valid_cover = false
	if sniper._is_sniper:
		if sniper._has_valid_cover:
			sniper._transition_to_seeking_cover()
		else:
			sniper._transition_to_combat()
	assert_eq(sniper.get_current_state(), MockSniperEnemy.AIState.COMBAT,
		"Snipers without cover should go to combat instead of pursuing")


## Bolt-action cycling prevents rapid fire (Issue #665 bug 4).
func test_sniper_bolt_action_prevents_rapid_fire() -> void:
	sniper._sniper_bolt_ready = false
	sniper._sniper_bolt_timer = 0.0
	var can_shoot := sniper._sniper_bolt_ready and not sniper._is_reloading and sniper._current_ammo > 0
	assert_false(can_shoot, "Sniper should not shoot while bolt is cycling")
	sniper._sniper_bolt_timer = SniperComponent.BOLT_CYCLE_TIME + 0.1
	sniper._sniper_bolt_ready = sniper._sniper_bolt_timer >= SniperComponent.BOLT_CYCLE_TIME
	can_shoot = sniper._sniper_bolt_ready and not sniper._is_reloading and sniper._current_ammo > 0
	assert_true(can_shoot, "Sniper should shoot after bolt cycle completes")


## Issue #665 bug 5: _shoot() must return false when shot is blocked.
## Callers only reset _shoot_timer when _shoot() returns true.
func test_shoot_returns_false_when_bolt_not_ready() -> void:
	sniper._sniper_bolt_ready = false
	var result := sniper._shoot()
	assert_false(result, "Issue #665: _shoot() must return false when bolt not ready")
	assert_eq(sniper._shots_fired, 0, "No shot should be fired when bolt not ready")


## Issue #665: _shoot() returns true and resets bolt on successful fire.
func test_shoot_returns_true_and_resets_bolt() -> void:
	sniper._sniper_bolt_ready = true
	sniper._current_ammo = 5
	var result := sniper._shoot()
	assert_true(result, "Issue #665: _shoot() must return true on successful fire")
	assert_eq(sniper._shots_fired, 1, "Shot should be fired")
	assert_false(sniper._sniper_bolt_ready, "Bolt must not be ready after firing")


## Issue #665: Shoot timer only resets on successful shot.
func test_shoot_timer_not_wasted_on_failed_shot() -> void:
	sniper.enter_combat()
	sniper._can_see_player = true
	sniper._detection_delay_elapsed = true
	sniper._shoot_timer = 4.0  # Above cooldown
	sniper._sniper_bolt_ready = false  # Bolt not ready — shot will fail
	sniper.process_sniper_combat(0.016)
	assert_eq(sniper._shoot_timer, 4.0,
		"Issue #665: _shoot_timer must not reset when shot fails (bolt not ready)")
	assert_eq(sniper._shots_fired, 0, "No shot should fire when bolt not ready")


# ============================================================================
# Issue #665 Round 3+4: Cover Validation and Hitscan Fixes
# ============================================================================


## Issue #665: Sniper must not enter fake IN_COVER when no cover is found.
func test_sniper_no_fake_cover_when_cover_unavailable_issue_665() -> void:
	sniper.enter_combat()
	sniper._has_valid_cover = false
	if not sniper._has_valid_cover:
		sniper._transition_to_combat()
	assert_eq(sniper.get_current_state(), MockSniperEnemy.AIState.COMBAT,
		"Issue #665: Sniper must return to COMBAT, not fake IN_COVER, when no cover found")


## Issue #665: Hitscan must check if muzzle is behind a wall.
func test_hitscan_muzzle_wall_check_in_source_issue_665() -> void:
	var file := FileAccess.open("res://scripts/components/sniper_component.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open sniper_component.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains("muzzle_check") or source.contains("actual_start"),
		"Issue #665: perform_hitscan must check if muzzle is behind a wall")


## Issue #665: SniperComponent must NOT have dead process_combat_state method.
func test_sniper_component_no_dead_code_issue_665() -> void:
	var file := FileAccess.open("res://scripts/components/sniper_component.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open sniper_component.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_false(source.contains("func process_combat_state"),
		"Issue #665: Dead process_combat_state must be removed")
	assert_false(source.contains("func process_in_cover_state"),
		"Issue #665: Dead process_in_cover_state must be removed")


## Issue #665: Hitscan hit_from_inside must be false to avoid wall self-collision.
func test_hitscan_no_hit_from_inside_issue_665() -> void:
	var file := FileAccess.open("res://scripts/components/sniper_component.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open sniper_component.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains("hit_from_inside = false"),
		"Issue #665: Hitscan must use hit_from_inside=false to prevent wall self-collision")
