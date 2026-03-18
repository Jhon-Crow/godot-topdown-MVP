extends GutTest
## Unit tests for sniper enemy fixes (Issue #1161).
##
## Regression tests for three bugs in ContainerYardA_Sniper:
## 1. Burst firing - sniper should not burst-fire (bolt-action, one shot at a time).
## 2. Ammo count - sniper should have 70 total rounds.
## 3. Bolt-action animation - sniper should cycle bolt after each shot.


# ============================================================================
# Mock WeaponConfigComponent (minimal, for config value tests)
# ============================================================================


class MockWeaponConfig:
	## Weapon type values matching enemy.gd enum
	const RIFLE = 0
	const SHOTGUN = 1
	const UZI = 2
	const MACHETE = 3
	const RPG = 4
	const PM = 5
	const MACHINE_GUN = 6
	const SNIPER_RIFLE = 7

	## Returns config for SNIPER_RIFLE weapon type
	func get_sniper_config() -> Dictionary:
		return WeaponConfigComponent.WEAPON_CONFIGS[SNIPER_RIFLE]


var _config: MockWeaponConfig


func before_each() -> void:
	_config = MockWeaponConfig.new()


func after_each() -> void:
	_config = null


# ============================================================================
# Bug #1: Burst Firing — Sniper should NOT burst-fire (Issue #1161)
# ============================================================================


func test_sniper_shoot_cooldown_is_3_seconds() -> void:
	# Sniper bolt-action = 3 seconds between shots minimum.
	# RETREAT_BURST_COOLDOWN is 0.06s (60ms), which would be used for burst fire.
	# The sniper's shoot_cooldown should be 3.0s, NOT 0.06s.
	var config := _config.get_sniper_config()
	assert_eq(config["shoot_cooldown"], 3.0,
		"SNIPER_RIFLE shoot_cooldown must be 3.0s (bolt-action, not burst fire)")


func test_sniper_shoot_cooldown_much_greater_than_burst_cooldown() -> void:
	# RETREAT_BURST_COOLDOWN = 0.06s; sniper must never fire that fast
	var config := _config.get_sniper_config()
	var burst_cooldown: float = 0.06
	assert_true(config["shoot_cooldown"] > burst_cooldown * 10,
		"SNIPER_RIFLE shoot_cooldown must be much greater than burst interval (0.06s)")


func test_sniper_is_not_automatic() -> void:
	# Sniper rifle is bolt-action (semi-auto), never automatic.
	# WeaponConfigComponent does not have IsAutomatic, but we verify via shoot_cooldown.
	var config := _config.get_sniper_config()
	assert_true(config["shoot_cooldown"] >= 1.0,
		"SNIPER_RIFLE shoot_cooldown >= 1.0 (not automatic fire)")


# ============================================================================
# Bug #2: Ammo Count — Sniper should have 70 total rounds (Issue #1161)
# ============================================================================


func test_sniper_total_magazines_is_14() -> void:
	var config := _config.get_sniper_config()
	assert_eq(config["total_magazines"], 14,
		"SNIPER_RIFLE total_magazines should be 14 (Issue #1161: 70 total rounds)")


func test_sniper_magazine_size_is_5() -> void:
	var config := _config.get_sniper_config()
	assert_eq(config["magazine_size"], 5,
		"SNIPER_RIFLE magazine_size should be 5 (5-round magazine)")


func test_sniper_total_ammo_is_70() -> void:
	# Total ammo = total_magazines * magazine_size
	var config := _config.get_sniper_config()
	var magazine_size: int = config["magazine_size"]
	var total_magazines: int = config["total_magazines"]
	var total_ammo: int = magazine_size * total_magazines
	assert_eq(total_ammo, 70,
		"SNIPER_RIFLE total ammo must be exactly 70 (Issue #1161)")


func test_sniper_total_ammo_not_old_value_15() -> void:
	# Old value was total_magazines=3 → 15 total. Regression check.
	var config := _config.get_sniper_config()
	var old_total: int = 5 * 3  # old: magazine_size=5, total_magazines=3
	var actual_total: int = config["magazine_size"] * config["total_magazines"]
	assert_ne(actual_total, old_total,
		"SNIPER_RIFLE total ammo must NOT be old value of 15 (Issue #1161 regression)")


func test_sniper_has_more_ammo_than_machine_gun_magazine() -> void:
	# Sniper rifle's reserve (65 rounds) is more meaningful than a basic check.
	var config := _config.get_sniper_config()
	var reserve_ammo: int = (config["total_magazines"] - 1) * config["magazine_size"]
	assert_true(reserve_ammo >= 60,
		"SNIPER_RIFLE reserve ammo should be at least 60 rounds (Issue #1161)")


# ============================================================================
# Bug #3: Bolt-Action Animation — Constants and Config (Issue #1161)
# ============================================================================


func test_sniper_bullet_scene_path_is_enemy_specific() -> void:
	# Enemy sniper uses SniperBulletEnemy.tscn (not SniperBullet.tscn for player)
	var config := _config.get_sniper_config()
	assert_eq(config["bullet_scene_path"], "res://scenes/projectiles/csharp/SniperBulletEnemy.tscn",
		"SNIPER_RIFLE enemy bullet scene should be SniperBulletEnemy.tscn")


func test_sniper_has_no_progressive_spread() -> void:
	# Sniper rifle is perfectly accurate — no spread (bolt-action precision)
	var config := _config.get_sniper_config()
	assert_eq(config["initial_spread"], 0.0,
		"SNIPER_RIFLE initial_spread should be 0.0 (perfect accuracy)")
	assert_eq(config["spread_increment"], 0.0,
		"SNIPER_RIFLE spread_increment should be 0.0 (bolt-action = no spray)")
	assert_eq(config["max_spread"], 0.0,
		"SNIPER_RIFLE max_spread should be 0.0 (perfect accuracy)")


# ============================================================================
# Regression: WeaponConfigComponent file-level checks (Issue #1161)
# ============================================================================


func test_sniper_config_loaded_from_weapon_config_component() -> void:
	# WeaponConfigComponent should have SNIPER_RIFLE config at key 7
	assert_true(WeaponConfigComponent.WEAPON_CONFIGS.has(7),
		"WeaponConfigComponent must have SNIPER_RIFLE config at key 7")


func test_sniper_get_config_returns_correct_magazine_size() -> void:
	var config := WeaponConfigComponent.get_config(7)
	assert_eq(config["magazine_size"], 5,
		"get_config(7) should return magazine_size=5 for SNIPER_RIFLE")


func test_sniper_get_config_returns_correct_total_magazines() -> void:
	var config := WeaponConfigComponent.get_config(7)
	assert_eq(config["total_magazines"], 14,
		"get_config(7) should return total_magazines=14 for SNIPER_RIFLE (Issue #1161)")


func test_sniper_get_type_name_returns_sniper_rifle() -> void:
	assert_eq(WeaponConfigComponent.get_type_name(7), "SNIPER_RIFLE",
		"get_type_name(7) should return SNIPER_RIFLE")


# ============================================================================
# Bug #4: Sniper misses visible stationary player — process_pursuing (Issue #1161)
# ============================================================================


class MockNode2D:
	var global_position: Vector2 = Vector2(400.0, 2200.0)


class MockEnemySniperComponent extends EnemySniperComponent:
	var shoot_called: bool = false
	var fire_at_called: bool = false
	var last_fire_at_pos: Vector2 = Vector2.ZERO

	class MockEnemy:
		var global_position: Vector2 = Vector2(4500.0, 444.0)
		var velocity: Vector2 = Vector2.ZERO
		var shoot_cooldown: float = 3.0
		var _shoot_timer: float = 10.0
		var _can_shoot_result: bool = true
		func _can_shoot() -> bool: return _can_shoot_result
		func _shoot() -> void: pass

	func _init() -> void:
		enemy = MockEnemy.new()

	func fire_at_predicted_position(target_pos: Vector2) -> void:
		fire_at_called = true
		last_fire_at_pos = target_pos


func test_process_pursuing_returns_false_when_player_visible_and_at_safe_range() -> void:
	# When player is visible and at safe range (>= MIN_DISTANCE = 350px),
	# process_pursuing should return false so normal PURSUING code can transition to COMBAT.
	var component := MockEnemySniperComponent.new()
	var player := MockNode2D.new()
	# Distance ~4145px (sniper at 4500,444 → player at 400,2200) >> MIN_DISTANCE=350
	var result := component.process_pursuing(0.1, true, player, player.global_position, null)
	assert_false(result,
		"process_pursuing must return false when player visible at safe range (Issue #1161: sniper should engage, not blind-fire)")


func test_process_pursuing_returns_false_when_player_visible_too_close() -> void:
	# When player is visible but too close, sniper should also return false to let
	# retreat logic handle it (not blind-fire at close range).
	var component := MockEnemySniperComponent.new()
	var player := MockNode2D.new()
	player.global_position = Vector2(4500.0, 644.0)  # 200px away (< MIN_DISTANCE=350)
	var result := component.process_pursuing(0.1, true, player, player.global_position, null)
	assert_false(result,
		"process_pursuing must return false when player is too close (retreat, not blind-fire)")


func test_process_pursuing_holds_position_and_blindfires_when_player_not_visible() -> void:
	# When player is NOT visible: sniper holds position (returns true) and may blind-fire.
	var component := MockEnemySniperComponent.new()
	var last_known := Vector2(400.0, 2200.0)
	# Distance from sniper(4500,444) to last_known(400,2200) is ~4145px > MIN_DISTANCE
	var result := component.process_pursuing(0.1, false, null, last_known, null)
	assert_true(result,
		"process_pursuing must return true (hold position) when player NOT visible (Issue #1161)")


func test_process_pursuing_does_not_blindfire_when_player_visible() -> void:
	# When player IS visible, no blind-fire should happen.
	var component := MockEnemySniperComponent.new()
	component.blind_fire_timer = 999.0  # Force timer to exceed cooldown
	var player := MockNode2D.new()
	component.process_pursuing(0.1, true, player, player.global_position, null)
	assert_false(component.fire_at_called,
		"process_pursuing must NOT call fire_at_predicted_position when player is visible (Issue #1161)")
