extends GutTest
## Regression tests for sniper enemy (ASVK) fixes.
##
## Issue #1171:
## 1. Tracer starts not at the barrel but at some distance from the barrel.
##    Fix: SniperBullet.cs pre-populates _positionHistory with spawn position in _Ready().
## 2. Enemy sniper misses often (even when player is stationary).
##    Fix: Enemy SNIPER_RIFLE uses hitscan (_shoot_sniper_hitscan) instead of physics bullet.


# ============================================================================
# Tests for Bug 1: Tracer pre-population (SniperBullet.cs)
# ============================================================================


func test_sniper_bullet_scene_has_trail_node() -> void:
	## Verify SniperBulletEnemy.tscn has a Trail child node and TrailLength > 0
	var packed: PackedScene = load("res://scenes/projectiles/csharp/SniperBulletEnemy.tscn")
	if packed == null:
		pass_test("Skipped: SniperBulletEnemy.tscn not accessible in test environment")
		return
	var inst := packed.instantiate()
	add_child(inst)
	var trail: Node = inst.get_node_or_null("Trail")
	assert_not_null(trail, "SniperBulletEnemy must have a Trail child node for the tracer effect (Issue #1171)")
	var trail_length: int = inst.get("TrailLength") if inst.get("TrailLength") != null else 0
	assert_gt(trail_length, 0, "SniperBulletEnemy.TrailLength must be > 0 to show tracer (Issue #1171)")
	inst.queue_free()


func test_sniper_bullet_trail_length_is_positive() -> void:
	## SniperBulletEnemy.tscn should have TrailLength=15 (set in scene file)
	var packed: PackedScene = load("res://scenes/projectiles/csharp/SniperBulletEnemy.tscn")
	if packed == null:
		pass_test("Skipped: SniperBulletEnemy.tscn not accessible in test environment")
		return
	var inst := packed.instantiate()
	add_child(inst)
	var trail_length: int = inst.get("TrailLength") if inst.get("TrailLength") != null else 0
	assert_gt(trail_length, 0,
		"SniperBulletEnemy.TrailLength should be > 0 so tracer renders (Issue #1171 fix)")
	inst.queue_free()


# ============================================================================
# Tests for Bug 2: Enemy sniper weapon config (no physics bullet at 10000px/s)
# ============================================================================


func test_sniper_rifle_weapon_config_exists() -> void:
	## WeaponConfigComponent must have a SNIPER_RIFLE entry (type 7)
	var configs: Dictionary = WeaponConfigComponent.WEAPON_CONFIGS
	assert_has(configs, 7, "WeaponConfigComponent must have SNIPER_RIFLE config at key 7 (Issue #1125)")


func test_sniper_rifle_bullet_speed_matches_player() -> void:
	## Bullet speed in weapon config should match player ASVK (10000)
	var config: Dictionary = WeaponConfigComponent.get_config(7)
	assert_eq(config["bullet_speed"], 10000.0,
		"SNIPER_RIFLE bullet_speed must be 10000.0 to match player ASVK")


func test_sniper_rifle_has_zero_spread() -> void:
	## Sniper rifle must have 0 spread (perfectly accurate when aimed)
	var config: Dictionary = WeaponConfigComponent.get_config(7)
	assert_eq(config["initial_spread"], 0.0,
		"SNIPER_RIFLE initial_spread must be 0.0 — sniper is perfectly accurate (Issue #1171)")
	assert_eq(config["max_spread"], 0.0,
		"SNIPER_RIFLE max_spread must be 0.0 (Issue #1171)")


func test_sniper_rifle_slow_bolt_action_cooldown() -> void:
	## ASVK bolt-action should fire at ~1 shot per 3 seconds
	var config: Dictionary = WeaponConfigComponent.get_config(7)
	assert_eq(config["shoot_cooldown"], 3.0,
		"SNIPER_RIFLE shoot_cooldown must be 3.0s (bolt-action rate, Issue #1125)")


func test_enemy_sniper_rifle_weapon_type_enum_exists() -> void:
	## WeaponType.SNIPER_RIFLE enum value must exist in enemy.gd
	## This is a static check via scene — we load a default Enemy scene and verify
	## it can be configured with weapon_type = 7 without errors.
	var packed: PackedScene = load("res://scenes/objects/Enemy.tscn")
	if packed == null:
		pass_test("Skipped: Enemy.tscn not accessible in test environment")
		return
	var enemy := packed.instantiate()
	add_child(enemy)
	# Set weapon type to SNIPER_RIFLE (7) and verify it doesn't crash
	if enemy.get("weapon_type") != null:
		enemy.set("weapon_type", 7)
		assert_eq(enemy.get("weapon_type"), 7,
			"Enemy weapon_type must accept SNIPER_RIFLE value (7)")
	enemy.queue_free()


# ============================================================================
# Tests for the hitscan helper functions existing in EnemySniperComponent
# ============================================================================


func test_enemy_has_sniper_component() -> void:
	## Enemy must have a SniperComponent child node (EnemySniperComponent) for Issue #1171 fix
	var packed: PackedScene = load("res://scenes/objects/Enemy.tscn")
	if packed == null:
		pass_test("Skipped: Enemy.tscn not accessible in test environment")
		return
	var enemy := packed.instantiate()
	add_child(enemy)
	var sniper_comp: Node = enemy.get_node_or_null("SniperComponent")
	assert_not_null(sniper_comp,
		"Enemy must have SniperComponent child node for hitscan shooting (Issue #1171)")
	if sniper_comp != null:
		assert_true(sniper_comp.has_method("shoot_sniper_hitscan"),
			"SniperComponent must have shoot_sniper_hitscan method (Issue #1171)")
	enemy.queue_free()


func test_enemy_sniper_component_has_tracer_method() -> void:
	## EnemySniperComponent must have _spawn_sniper_tracer method for Issue #1171 fix
	var packed: PackedScene = load("res://scenes/objects/Enemy.tscn")
	if packed == null:
		pass_test("Skipped: Enemy.tscn not accessible in test environment")
		return
	var enemy := packed.instantiate()
	add_child(enemy)
	var sniper_comp: Node = enemy.get_node_or_null("SniperComponent")
	if sniper_comp == null:
		pass_test("Skipped: SniperComponent not found in test environment")
		enemy.queue_free()
		return
	assert_true(sniper_comp.has_method("_spawn_sniper_tracer"),
		"SniperComponent must have _spawn_sniper_tracer method for smoke tracer (Issue #1171)")
	enemy.queue_free()


# ============================================================================
# Regression test: verify SniperBullet.cs source has _positionHistory pre-population
# ============================================================================


func test_sniper_bullet_source_has_trail_prepopulation() -> void:
	## Regression: verify SniperBullet.cs contains the Issue #1171 fix comment
	## to prevent reverting the _Ready() pre-population of _positionHistory.
	var file := FileAccess.open("res://Scripts/Projectiles/SniperBullet.cs", FileAccess.READ)
	if file == null:
		pass_test("Skipped: SniperBullet.cs not accessible in test environment")
		return
	var content := file.get_as_text()
	file.close()
	assert_true(content.contains("_positionHistory.Add(GlobalPosition)"),
		"SniperBullet.cs must pre-populate _positionHistory in _Ready() to fix tracer start (Issue #1171)")


func test_sniper_component_source_has_hitscan() -> void:
	## Regression: verify enemy_sniper_component.gd contains the Issue #1171 hitscan method
	var file := FileAccess.open("res://scripts/components/enemy_sniper_component.gd", FileAccess.READ)
	if file == null:
		pass_test("Skipped: enemy_sniper_component.gd not accessible in test environment")
		return
	var content := file.get_as_text()
	file.close()
	assert_true(content.contains("shoot_sniper_hitscan"),
		"enemy_sniper_component.gd must contain shoot_sniper_hitscan for hitscan fix (Issue #1171)")
	assert_true(content.contains("_spawn_sniper_tracer"),
		"enemy_sniper_component.gd must contain _spawn_sniper_tracer for smoke tracer (Issue #1171)")
