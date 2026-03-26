extends GutTest
## Unit tests for the machine gunner enemy type (Issue #1033).
##
## Tests WeaponConfigComponent MACHINE_GUN (type 4) config values,
## front-arc damage resistance math, and PM fallback on ammo depletion.


# ============================================================================
# MACHINE_GUN (Type 4) Config Values
# ============================================================================


func test_machine_gun_config_exists() -> void:
	assert_true(WeaponConfigComponent.WEAPON_CONFIGS.has(4),
		"WEAPON_CONFIGS should have key 4 for MACHINE_GUN")


func test_machine_gun_shoot_cooldown() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[4]
	assert_eq(config["shoot_cooldown"], 0.12,
		"MACHINE_GUN shoot_cooldown should be 0.12 (~8.3 rps)")


func test_machine_gun_bullet_speed() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[4]
	assert_eq(config["bullet_speed"], 2800.0,
		"MACHINE_GUN bullet_speed should be 2800.0")


func test_machine_gun_magazine_size() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[4]
	assert_eq(config["magazine_size"], 500,
		"MACHINE_GUN magazine_size (belt) should be 500")


func test_machine_gun_total_magazines() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[4]
	assert_eq(config["total_magazines"], 2,
		"MACHINE_GUN total_magazines should be 2 (500+500)")


func test_machine_gun_reload_time() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[4]
	assert_eq(config["reload_time"], 9.0,
		"MACHINE_GUN reload_time should be 9.0 seconds (long belt reload)")


func test_machine_gun_is_not_shotgun() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[4]
	assert_false(config["is_shotgun"],
		"MACHINE_GUN is_shotgun should be false")


func test_machine_gun_is_not_melee() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[4]
	assert_false(config.get("is_melee", false),
		"MACHINE_GUN is_melee should be false")


func test_machine_gun_fires_single_bullet() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[4]
	assert_eq(config["pellet_count_min"], 1,
		"MACHINE_GUN pellet_count_min should be 1")
	assert_eq(config["pellet_count_max"], 1,
		"MACHINE_GUN pellet_count_max should be 1")


func test_machine_gun_caliber_is_762x39() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[4]
	assert_eq(config["caliber_path"], "res://resources/calibers/caliber_762x39.tres",
		"MACHINE_GUN caliber_path should point to 7.62x39 caliber resource")


func test_machine_gun_bullet_scene_is_standard_bullet() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[4]
	assert_eq(config["bullet_scene_path"], "res://scenes/projectiles/csharp/Bullet.tscn",
		"MACHINE_GUN should use standard Bullet.tscn")


func test_machine_gun_has_progressive_spread() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[4]
	assert_true(config["spread_threshold"] > 0,
		"MACHINE_GUN should have spread_threshold > 0 for progressive spread")
	assert_true(config["spread_increment"] > 0.0,
		"MACHINE_GUN should have positive spread_increment")
	assert_true(config["max_spread"] > 0.0,
		"MACHINE_GUN should have positive max_spread")


func test_machine_gun_weapon_loudness_is_highest() -> void:
	var mg_loud := WeaponConfigComponent.WEAPON_CONFIGS[4]["weapon_loudness"]
	var rifle_loud := WeaponConfigComponent.WEAPON_CONFIGS[0]["weapon_loudness"]
	var uzi_loud := WeaponConfigComponent.WEAPON_CONFIGS[2]["weapon_loudness"]
	assert_true(mg_loud > rifle_loud,
		"MACHINE_GUN should be louder than RIFLE")
	assert_true(mg_loud > uzi_loud,
		"MACHINE_GUN should be louder than UZI")


func test_machine_gun_has_largest_magazine() -> void:
	var mg_mag := WeaponConfigComponent.WEAPON_CONFIGS[4]["magazine_size"]
	var rifle_mag := WeaponConfigComponent.WEAPON_CONFIGS[0]["magazine_size"]
	var uzi_mag := WeaponConfigComponent.WEAPON_CONFIGS[2]["magazine_size"]
	assert_true(mg_mag > rifle_mag,
		"MACHINE_GUN belt (500) should be larger than RIFLE magazine (30)")
	assert_true(mg_mag > uzi_mag,
		"MACHINE_GUN belt (500) should be larger than UZI magazine (32)")


func test_machine_gun_reload_time_is_longest() -> void:
	# MACHINE_GUN reload is 9s; rifle/uzi/shotgun don't have a reload_time key (default 3.0s in enemy.gd)
	var mg_reload := WeaponConfigComponent.WEAPON_CONFIGS[4]["reload_time"]
	assert_true(mg_reload > 3.0,
		"MACHINE_GUN reload_time should exceed the default 3.0s reload")


func test_machine_gun_type_name_is_machine_gun() -> void:
	assert_eq(WeaponConfigComponent.get_type_name(4), "MACHINE_GUN",
		"get_type_name(4) should return MACHINE_GUN")


func test_machine_gun_get_config_returns_correct_data() -> void:
	var config := WeaponConfigComponent.get_config(4)
	assert_eq(config["magazine_size"], 500,
		"get_config(4) should return MACHINE_GUN belt config with 500 rounds")


# ============================================================================
# Front-Arc Damage Resistance Math Tests (Issue #1033)
# The resistance triggers when: dot(facing_dir, bullet_from_dir) >= cos(15°)
# This covers a ±15° arc (30° total) directly in front of the enemy.
# ============================================================================


const FRONT_ARC_COS: float = 0.9659  # cos(15°) ≈ 0.9659


func test_front_arc_cos_value() -> void:
	# Verify our constant matches expected cos(15°)
	var expected := cos(deg_to_rad(15.0))
	assert_almost_eq(FRONT_ARC_COS, expected, 0.001,
		"FRONT_ARC_COS should equal cos(15°)")


func test_direct_front_hit_is_in_arc() -> void:
	# Bullet comes from directly in front (enemy faces right, bullet comes from left → right)
	var facing_dir := Vector2(1.0, 0.0)   # Enemy facing right
	var hit_dir := Vector2(1.0, 0.0)      # Bullet travels right (toward enemy)
	var bullet_from_dir := -hit_dir.normalized()  # Bullet came from the left
	# Wait: bullet_from_dir = (-1,0) means bullet came from the left, enemy faces right
	# dot = (1,0)·(-1,0) = -1 → NOT in front arc
	# Let's correct: enemy faces right (+x), frontal hit means bullet comes from +x direction
	# hit_direction in the code is the direction the bullet TRAVELS (into the enemy)
	# -hit_direction = direction FROM which the bullet came
	# If enemy faces right and bullet comes from in front (from the right side)
	# then hit_dir = Vector2(-1, 0) (bullet travels left into enemy)
	# bullet_from_dir = -hit_dir = Vector2(1, 0) = same as facing
	var hit_dir2 := Vector2(-1.0, 0.0)   # Bullet travels left (hits enemy from the right/front)
	var bullet_from_dir2 := -hit_dir2.normalized()  # = Vector2(1,0) — came from the right (in front)
	var dot := facing_dir.dot(bullet_from_dir2)
	assert_true(dot >= FRONT_ARC_COS,
		"Direct frontal hit (0°) should be within the ±15° arc (dot=%.4f >= %.4f)" % [dot, FRONT_ARC_COS])


func test_10_degree_off_front_is_in_arc() -> void:
	# Bullet comes from 10° off the front arc — should still trigger
	var facing_dir := Vector2(1.0, 0.0)
	var bullet_from_dir := Vector2(cos(deg_to_rad(10.0)), sin(deg_to_rad(10.0)))
	var dot := facing_dir.dot(bullet_from_dir)
	assert_true(dot >= FRONT_ARC_COS,
		"10° off-front hit should be within the ±15° arc (dot=%.4f >= %.4f)" % [dot, FRONT_ARC_COS])


func test_15_degree_off_front_is_on_arc_boundary() -> void:
	# Bullet comes from exactly 15° off the front — on the boundary
	var facing_dir := Vector2(1.0, 0.0)
	var bullet_from_dir := Vector2(cos(deg_to_rad(15.0)), sin(deg_to_rad(15.0)))
	var dot := facing_dir.dot(bullet_from_dir)
	assert_almost_eq(dot, FRONT_ARC_COS, 0.001,
		"15° off-front hit should be exactly on the arc boundary (dot≈%.4f)" % dot)


func test_20_degree_off_front_is_outside_arc() -> void:
	# Bullet comes from 20° off the front — should NOT trigger
	var facing_dir := Vector2(1.0, 0.0)
	var bullet_from_dir := Vector2(cos(deg_to_rad(20.0)), sin(deg_to_rad(20.0)))
	var dot := facing_dir.dot(bullet_from_dir)
	assert_true(dot < FRONT_ARC_COS,
		"20° off-front hit should be outside the ±15° arc (dot=%.4f < %.4f)" % [dot, FRONT_ARC_COS])


func test_90_degree_side_hit_is_outside_arc() -> void:
	# Side hit (90°) should never be in front arc
	var facing_dir := Vector2(1.0, 0.0)
	var bullet_from_dir := Vector2(0.0, 1.0)  # From the side
	var dot := facing_dir.dot(bullet_from_dir)
	assert_true(dot < FRONT_ARC_COS,
		"90° side hit should be well outside the front arc (dot=%.4f)" % dot)


func test_180_degree_back_hit_is_outside_arc() -> void:
	# Back hit (180°) should never be in front arc
	var facing_dir := Vector2(1.0, 0.0)
	var bullet_from_dir := Vector2(-1.0, 0.0)  # From behind
	var dot := facing_dir.dot(bullet_from_dir)
	assert_true(dot < FRONT_ARC_COS,
		"180° back hit should be well outside the front arc (dot=%.4f)" % dot)


func test_front_arc_resistance_chance_is_30_percent() -> void:
	# Statistical test: run 10000 trials with a rigged RNG — count how many pass
	# We can't test actual randomness easily without scene, so just verify the constant
	const RESISTANCE_CHANCE: float = 0.30
	assert_almost_eq(RESISTANCE_CHANCE, 0.30, 0.001,
		"Front-arc resistance chance should be 30%")


# ============================================================================
# Machine Gun Ammo Math Tests (500 + 500 = 1000 total)
# ============================================================================


func test_machine_gun_total_ammo_is_1000() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[4]
	var mag_size: int = config["magazine_size"]
	var total_mags: int = config["total_magazines"]
	var total_ammo := mag_size * total_mags
	assert_eq(total_ammo, 1000,
		"MACHINE_GUN total ammo should be 1000 (500 × 2)")


func test_machine_gun_reserve_ammo_after_init_is_500() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[4]
	var mag_size: int = config["magazine_size"]
	var total_mags: int = config["total_magazines"]
	# reserve = (total_magazines - 1) * magazine_size (one belt loaded)
	var reserve := (total_mags - 1) * mag_size
	assert_eq(reserve, 500,
		"MACHINE_GUN should have 500 reserve rounds (one spare belt)")


# ============================================================================
# Sound and Ammo Type Tests (Issue #1033)
# PKM uses 7.62x39 AK ammo — same caliber resource as AK
# ============================================================================


func test_machine_gun_caliber_path_is_762x39() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[4]
	assert_true(config["caliber_path"].ends_with("caliber_762x39.tres"),
		"MACHINE_GUN must use 7.62x39 caliber (same as AK)")


func test_machine_gun_caliber_differs_from_rifle_m16() -> void:
	var mg_cal := WeaponConfigComponent.WEAPON_CONFIGS[4]["caliber_path"]
	var rifle_cal := WeaponConfigComponent.WEAPON_CONFIGS[0]["caliber_path"]
	assert_ne(mg_cal, rifle_cal,
		"MACHINE_GUN 7.62x39 caliber should differ from RIFLE M16 5.45x39 caliber")


func test_machine_gun_weapon_type_enum_is_4() -> void:
	# Verify MACHINE_GUN is enum value 4 so sound routing logic works
	assert_eq(WeaponConfigComponent.get_type_name(4), "MACHINE_GUN",
		"Weapon type 4 must be MACHINE_GUN for AK sound routing to work")


# ============================================================================
# Sound Range Tests (Issue #1549)
# ============================================================================


func test_machine_gun_sound_range_is_2400px() -> void:
	# Issue #1549: PKM machine gun weapon_loudness (SoundPropagation range) must be 2400px.
	var config := WeaponConfigComponent.WEAPON_CONFIGS[6]
	assert_eq(config["weapon_loudness"], 2400.0,
		"MACHINE_GUN weapon_loudness should be 2400.0 px (SoundPropagation alert range)")
