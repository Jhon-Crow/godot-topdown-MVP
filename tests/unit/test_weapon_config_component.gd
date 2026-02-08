extends GutTest
## Unit tests for WeaponConfigComponent.
##
## Tests the static utility class for weapon type configurations including
## the WEAPON_CONFIGS constant dictionary, get_config() lookup, and
## get_type_name() label resolution.


# ============================================================================
# WEAPON_CONFIGS Constant - Structure Tests
# ============================================================================


func test_weapon_configs_has_six_entries() -> void:
	assert_eq(WeaponConfigComponent.WEAPON_CONFIGS.size(), 6,
		"WEAPON_CONFIGS should contain exactly 6 weapon types")


func test_weapon_configs_has_rifle_key() -> void:
	assert_true(WeaponConfigComponent.WEAPON_CONFIGS.has(0),
		"WEAPON_CONFIGS should have key 0 for RIFLE")


func test_weapon_configs_has_shotgun_key() -> void:
	assert_true(WeaponConfigComponent.WEAPON_CONFIGS.has(1),
		"WEAPON_CONFIGS should have key 1 for SHOTGUN")


func test_weapon_configs_has_uzi_key() -> void:
	assert_true(WeaponConfigComponent.WEAPON_CONFIGS.has(2),
		"WEAPON_CONFIGS should have key 2 for UZI")


func test_weapon_configs_has_machete_key() -> void:
	assert_true(WeaponConfigComponent.WEAPON_CONFIGS.has(3),
		"WEAPON_CONFIGS should have key 3 for MACHETE")


func test_weapon_configs_has_rpg_key() -> void:
	assert_true(WeaponConfigComponent.WEAPON_CONFIGS.has(4),
		"WEAPON_CONFIGS should have key 4 for RPG")


func test_weapon_configs_has_pm_key() -> void:
	assert_true(WeaponConfigComponent.WEAPON_CONFIGS.has(5),
		"WEAPON_CONFIGS should have key 5 for PM")


func test_weapon_configs_values_are_dictionaries() -> void:
	for key in WeaponConfigComponent.WEAPON_CONFIGS:
		assert_typeof(WeaponConfigComponent.WEAPON_CONFIGS[key], TYPE_DICTIONARY,
			"Each weapon config should be a Dictionary")


# ============================================================================
# RIFLE (Type 0) Config Values
# ============================================================================


func test_rifle_shoot_cooldown() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[0]
	assert_eq(config["shoot_cooldown"], 0.1,
		"RIFLE shoot_cooldown should be 0.1")


func test_rifle_bullet_speed() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[0]
	assert_eq(config["bullet_speed"], 2500.0,
		"RIFLE bullet_speed should be 2500.0")


func test_rifle_magazine_size() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[0]
	assert_eq(config["magazine_size"], 30,
		"RIFLE magazine_size should be 30")


func test_rifle_bullet_spawn_offset() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[0]
	assert_eq(config["bullet_spawn_offset"], 30.0,
		"RIFLE bullet_spawn_offset should be 30.0")


func test_rifle_weapon_loudness() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[0]
	assert_eq(config["weapon_loudness"], 1469.0,
		"RIFLE weapon_loudness should be 1469.0")


func test_rifle_is_not_shotgun() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[0]
	assert_false(config["is_shotgun"],
		"RIFLE is_shotgun should be false")


func test_rifle_spread_threshold() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[0]
	assert_eq(config["spread_threshold"], 3,
		"RIFLE spread_threshold should be 3")


func test_rifle_initial_spread() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[0]
	assert_eq(config["initial_spread"], 0.5,
		"RIFLE initial_spread should be 0.5")


func test_rifle_spread_increment() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[0]
	assert_eq(config["spread_increment"], 0.6,
		"RIFLE spread_increment should be 0.6")


func test_rifle_max_spread() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[0]
	assert_eq(config["max_spread"], 4.0,
		"RIFLE max_spread should be 4.0")


func test_rifle_spread_reset_time() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[0]
	assert_eq(config["spread_reset_time"], 0.25,
		"RIFLE spread_reset_time should be 0.25")


func test_rifle_pellet_count_min() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[0]
	assert_eq(config["pellet_count_min"], 1,
		"RIFLE pellet_count_min should be 1")


func test_rifle_pellet_count_max() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[0]
	assert_eq(config["pellet_count_max"], 1,
		"RIFLE pellet_count_max should be 1")


func test_rifle_spread_angle() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[0]
	assert_eq(config["spread_angle"], 0.0,
		"RIFLE spread_angle should be 0.0")


func test_rifle_bullet_scene_path() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[0]
	assert_eq(config["bullet_scene_path"], "res://scenes/projectiles/csharp/Bullet.tscn",
		"RIFLE bullet_scene_path should point to Bullet.tscn")


func test_rifle_casing_scene_path() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[0]
	assert_eq(config["casing_scene_path"], "res://scenes/effects/Casing.tscn",
		"RIFLE casing_scene_path should point to Casing.tscn")


func test_rifle_caliber_path() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[0]
	assert_eq(config["caliber_path"], "res://resources/calibers/caliber_545x39.tres",
		"RIFLE caliber_path should point to 5.45x39 caliber resource")


# ============================================================================
# SHOTGUN (Type 1) Config Values
# ============================================================================


func test_shotgun_shoot_cooldown() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[1]
	assert_eq(config["shoot_cooldown"], 0.8,
		"SHOTGUN shoot_cooldown should be 0.8")


func test_shotgun_bullet_speed() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[1]
	assert_eq(config["bullet_speed"], 1800.0,
		"SHOTGUN bullet_speed should be 1800.0")


func test_shotgun_magazine_size() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[1]
	assert_eq(config["magazine_size"], 8,
		"SHOTGUN magazine_size should be 8")


func test_shotgun_bullet_spawn_offset() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[1]
	assert_eq(config["bullet_spawn_offset"], 35.0,
		"SHOTGUN bullet_spawn_offset should be 35.0")


func test_shotgun_weapon_loudness() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[1]
	assert_eq(config["weapon_loudness"], 2000.0,
		"SHOTGUN weapon_loudness should be 2000.0")


func test_shotgun_is_shotgun_flag() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[1]
	assert_true(config["is_shotgun"],
		"SHOTGUN is_shotgun should be true")


func test_shotgun_pellet_count_min() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[1]
	assert_eq(config["pellet_count_min"], 6,
		"SHOTGUN pellet_count_min should be 6")


func test_shotgun_pellet_count_max() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[1]
	assert_eq(config["pellet_count_max"], 10,
		"SHOTGUN pellet_count_max should be 10")


func test_shotgun_spread_angle() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[1]
	assert_eq(config["spread_angle"], 15.0,
		"SHOTGUN spread_angle should be 15.0 degrees")


func test_shotgun_spread_threshold() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[1]
	assert_eq(config["spread_threshold"], 0,
		"SHOTGUN spread_threshold should be 0")


func test_shotgun_initial_spread() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[1]
	assert_eq(config["initial_spread"], 0.0,
		"SHOTGUN initial_spread should be 0.0 (uses pellet spread instead)")


func test_shotgun_spread_increment() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[1]
	assert_eq(config["spread_increment"], 0.0,
		"SHOTGUN spread_increment should be 0.0 (uses pellet spread instead)")


func test_shotgun_max_spread() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[1]
	assert_eq(config["max_spread"], 0.0,
		"SHOTGUN max_spread should be 0.0 (uses pellet spread instead)")


func test_shotgun_spread_reset_time() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[1]
	assert_eq(config["spread_reset_time"], 0.0,
		"SHOTGUN spread_reset_time should be 0.0 (uses pellet spread instead)")


func test_shotgun_bullet_scene_path() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[1]
	assert_eq(config["bullet_scene_path"], "res://scenes/projectiles/csharp/ShotgunPellet.tscn",
		"SHOTGUN bullet_scene_path should point to ShotgunPellet.tscn")


func test_shotgun_sprite_path() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[1]
	assert_eq(config["sprite_path"], "res://assets/sprites/weapons/shotgun_topdown.png",
		"SHOTGUN sprite_path should point to shotgun sprite")


func test_shotgun_caliber_path() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[1]
	assert_eq(config["caliber_path"], "res://resources/calibers/caliber_buckshot.tres",
		"SHOTGUN caliber_path should point to buckshot caliber resource")


# ============================================================================
# UZI (Type 2) Config Values
# ============================================================================


func test_uzi_shoot_cooldown() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[2]
	assert_eq(config["shoot_cooldown"], 0.06,
		"UZI shoot_cooldown should be 0.06")


func test_uzi_bullet_speed() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[2]
	assert_eq(config["bullet_speed"], 2200.0,
		"UZI bullet_speed should be 2200.0")


func test_uzi_magazine_size() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[2]
	assert_eq(config["magazine_size"], 32,
		"UZI magazine_size should be 32")


func test_uzi_bullet_spawn_offset() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[2]
	assert_eq(config["bullet_spawn_offset"], 25.0,
		"UZI bullet_spawn_offset should be 25.0")


func test_uzi_weapon_loudness() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[2]
	assert_eq(config["weapon_loudness"], 1200.0,
		"UZI weapon_loudness should be 1200.0")


func test_uzi_is_not_shotgun() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[2]
	assert_false(config["is_shotgun"],
		"UZI is_shotgun should be false")


func test_uzi_spread_threshold() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[2]
	assert_eq(config["spread_threshold"], 0,
		"UZI spread_threshold should be 0 (spread starts immediately)")


func test_uzi_initial_spread() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[2]
	assert_eq(config["initial_spread"], 6.0,
		"UZI initial_spread should be 6.0")


func test_uzi_spread_increment() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[2]
	assert_eq(config["spread_increment"], 5.4,
		"UZI spread_increment should be 5.4")


func test_uzi_max_spread() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[2]
	assert_eq(config["max_spread"], 60.0,
		"UZI max_spread should be 60.0")


func test_uzi_spread_reset_time() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[2]
	assert_eq(config["spread_reset_time"], 0.3,
		"UZI spread_reset_time should be 0.3")


func test_uzi_pellet_count_min() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[2]
	assert_eq(config["pellet_count_min"], 1,
		"UZI pellet_count_min should be 1")


func test_uzi_pellet_count_max() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[2]
	assert_eq(config["pellet_count_max"], 1,
		"UZI pellet_count_max should be 1")


func test_uzi_spread_angle() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[2]
	assert_eq(config["spread_angle"], 0.0,
		"UZI spread_angle should be 0.0")


func test_uzi_bullet_scene_path() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[2]
	assert_eq(config["bullet_scene_path"], "res://scenes/projectiles/Bullet9mm.tscn",
		"UZI bullet_scene_path should point to Bullet9mm.tscn")


func test_uzi_sprite_path() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[2]
	assert_eq(config["sprite_path"], "res://assets/sprites/weapons/mini_uzi_topdown.png",
		"UZI sprite_path should point to mini uzi sprite")


func test_uzi_caliber_path() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[2]
	assert_eq(config["caliber_path"], "res://resources/calibers/caliber_9x19.tres",
		"UZI caliber_path should point to 9x19 caliber resource")


# ============================================================================
# Config Key Consistency Tests
# ============================================================================


func test_all_configs_share_same_keys() -> void:
	var rifle_keys := WeaponConfigComponent.WEAPON_CONFIGS[0].keys()
	var shotgun_keys := WeaponConfigComponent.WEAPON_CONFIGS[1].keys()
	var uzi_keys := WeaponConfigComponent.WEAPON_CONFIGS[2].keys()

	rifle_keys.sort()
	shotgun_keys.sort()
	uzi_keys.sort()

	assert_eq(rifle_keys, shotgun_keys,
		"RIFLE and SHOTGUN configs should have the same keys")
	assert_eq(rifle_keys, uzi_keys,
		"RIFLE and UZI configs should have the same keys")


func test_all_configs_have_shoot_cooldown() -> void:
	for weapon_type in WeaponConfigComponent.WEAPON_CONFIGS:
		var config := WeaponConfigComponent.WEAPON_CONFIGS[weapon_type]
		assert_true(config.has("shoot_cooldown"),
			"Weapon type %d should have shoot_cooldown" % weapon_type)


func test_all_configs_have_bullet_speed() -> void:
	for weapon_type in WeaponConfigComponent.WEAPON_CONFIGS:
		var config := WeaponConfigComponent.WEAPON_CONFIGS[weapon_type]
		assert_true(config.has("bullet_speed"),
			"Weapon type %d should have bullet_speed" % weapon_type)


func test_all_configs_have_magazine_size() -> void:
	for weapon_type in WeaponConfigComponent.WEAPON_CONFIGS:
		var config := WeaponConfigComponent.WEAPON_CONFIGS[weapon_type]
		assert_true(config.has("magazine_size"),
			"Weapon type %d should have magazine_size" % weapon_type)


func test_all_configs_have_is_shotgun() -> void:
	for weapon_type in WeaponConfigComponent.WEAPON_CONFIGS:
		var config := WeaponConfigComponent.WEAPON_CONFIGS[weapon_type]
		assert_true(config.has("is_shotgun"),
			"Weapon type %d should have is_shotgun" % weapon_type)


func test_all_configs_have_weapon_loudness() -> void:
	for weapon_type in WeaponConfigComponent.WEAPON_CONFIGS:
		var config := WeaponConfigComponent.WEAPON_CONFIGS[weapon_type]
		assert_true(config.has("weapon_loudness"),
			"Weapon type %d should have weapon_loudness" % weapon_type)


func test_all_configs_have_bullet_spawn_offset() -> void:
	for weapon_type in WeaponConfigComponent.WEAPON_CONFIGS:
		var config := WeaponConfigComponent.WEAPON_CONFIGS[weapon_type]
		assert_true(config.has("bullet_spawn_offset"),
			"Weapon type %d should have bullet_spawn_offset" % weapon_type)


func test_all_configs_have_spread_fields() -> void:
	var spread_keys := ["spread_threshold", "initial_spread", "spread_increment",
		"max_spread", "spread_reset_time"]
	for weapon_type in WeaponConfigComponent.WEAPON_CONFIGS:
		var config := WeaponConfigComponent.WEAPON_CONFIGS[weapon_type]
		for key in spread_keys:
			assert_true(config.has(key),
				"Weapon type %d should have %s" % [weapon_type, key])


func test_all_configs_have_scene_paths() -> void:
	var scene_keys := ["bullet_scene_path", "casing_scene_path", "caliber_path", "sprite_path"]
	for weapon_type in WeaponConfigComponent.WEAPON_CONFIGS:
		var config := WeaponConfigComponent.WEAPON_CONFIGS[weapon_type]
		for key in scene_keys:
			assert_true(config.has(key),
				"Weapon type %d should have %s" % [weapon_type, key])


# ============================================================================
# Config Value Validity Tests
# ============================================================================


func test_all_shoot_cooldowns_are_positive() -> void:
	for weapon_type in WeaponConfigComponent.WEAPON_CONFIGS:
		var config := WeaponConfigComponent.WEAPON_CONFIGS[weapon_type]
		assert_true(config["shoot_cooldown"] > 0.0,
			"Weapon type %d shoot_cooldown should be positive" % weapon_type)


func test_all_bullet_speeds_are_positive() -> void:
	for weapon_type in WeaponConfigComponent.WEAPON_CONFIGS:
		var config := WeaponConfigComponent.WEAPON_CONFIGS[weapon_type]
		assert_true(config["bullet_speed"] > 0.0,
			"Weapon type %d bullet_speed should be positive" % weapon_type)


func test_all_magazine_sizes_are_positive() -> void:
	for weapon_type in WeaponConfigComponent.WEAPON_CONFIGS:
		var config := WeaponConfigComponent.WEAPON_CONFIGS[weapon_type]
		assert_true(config["magazine_size"] > 0,
			"Weapon type %d magazine_size should be positive" % weapon_type)


func test_all_bullet_spawn_offsets_are_positive() -> void:
	for weapon_type in WeaponConfigComponent.WEAPON_CONFIGS:
		var config := WeaponConfigComponent.WEAPON_CONFIGS[weapon_type]
		assert_true(config["bullet_spawn_offset"] > 0.0,
			"Weapon type %d bullet_spawn_offset should be positive" % weapon_type)


func test_all_weapon_loudness_values_are_positive() -> void:
	for weapon_type in WeaponConfigComponent.WEAPON_CONFIGS:
		var config := WeaponConfigComponent.WEAPON_CONFIGS[weapon_type]
		assert_true(config["weapon_loudness"] > 0.0,
			"Weapon type %d weapon_loudness should be positive" % weapon_type)


func test_all_spread_thresholds_are_non_negative() -> void:
	for weapon_type in WeaponConfigComponent.WEAPON_CONFIGS:
		var config := WeaponConfigComponent.WEAPON_CONFIGS[weapon_type]
		assert_true(config["spread_threshold"] >= 0,
			"Weapon type %d spread_threshold should be non-negative" % weapon_type)


func test_all_initial_spreads_are_non_negative() -> void:
	for weapon_type in WeaponConfigComponent.WEAPON_CONFIGS:
		var config := WeaponConfigComponent.WEAPON_CONFIGS[weapon_type]
		assert_true(config["initial_spread"] >= 0.0,
			"Weapon type %d initial_spread should be non-negative" % weapon_type)


func test_all_max_spreads_are_gte_initial_spread() -> void:
	for weapon_type in WeaponConfigComponent.WEAPON_CONFIGS:
		var config := WeaponConfigComponent.WEAPON_CONFIGS[weapon_type]
		assert_true(config["max_spread"] >= config["initial_spread"],
			"Weapon type %d max_spread should be >= initial_spread" % weapon_type)


func test_all_spread_reset_times_are_non_negative() -> void:
	for weapon_type in WeaponConfigComponent.WEAPON_CONFIGS:
		var config := WeaponConfigComponent.WEAPON_CONFIGS[weapon_type]
		assert_true(config["spread_reset_time"] >= 0.0,
			"Weapon type %d spread_reset_time should be non-negative" % weapon_type)


func test_shotgun_pellet_count_max_gte_min() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[1]
	assert_true(config["pellet_count_max"] >= config["pellet_count_min"],
		"SHOTGUN pellet_count_max should be >= pellet_count_min")


func test_only_shotgun_has_is_shotgun_true() -> void:
	assert_false(WeaponConfigComponent.WEAPON_CONFIGS[0]["is_shotgun"],
		"RIFLE should not be a shotgun")
	assert_true(WeaponConfigComponent.WEAPON_CONFIGS[1]["is_shotgun"],
		"SHOTGUN should be a shotgun")
	assert_false(WeaponConfigComponent.WEAPON_CONFIGS[2]["is_shotgun"],
		"UZI should not be a shotgun")


# ============================================================================
# Weapon Characteristics Comparison Tests
# ============================================================================


func test_shotgun_is_slowest_fire_rate() -> void:
	var rifle_cd := WeaponConfigComponent.WEAPON_CONFIGS[0]["shoot_cooldown"]
	var shotgun_cd := WeaponConfigComponent.WEAPON_CONFIGS[1]["shoot_cooldown"]
	var uzi_cd := WeaponConfigComponent.WEAPON_CONFIGS[2]["shoot_cooldown"]

	assert_true(shotgun_cd > rifle_cd,
		"SHOTGUN should have a longer cooldown than RIFLE")
	assert_true(shotgun_cd > uzi_cd,
		"SHOTGUN should have a longer cooldown than UZI")


func test_uzi_is_fastest_fire_rate() -> void:
	var rifle_cd := WeaponConfigComponent.WEAPON_CONFIGS[0]["shoot_cooldown"]
	var uzi_cd := WeaponConfigComponent.WEAPON_CONFIGS[2]["shoot_cooldown"]

	assert_true(uzi_cd < rifle_cd,
		"UZI should have a shorter cooldown than RIFLE")


func test_rifle_has_fastest_bullets() -> void:
	var rifle_speed := WeaponConfigComponent.WEAPON_CONFIGS[0]["bullet_speed"]
	var shotgun_speed := WeaponConfigComponent.WEAPON_CONFIGS[1]["bullet_speed"]
	var uzi_speed := WeaponConfigComponent.WEAPON_CONFIGS[2]["bullet_speed"]

	assert_true(rifle_speed > shotgun_speed,
		"RIFLE should have faster bullets than SHOTGUN")
	assert_true(rifle_speed > uzi_speed,
		"RIFLE should have faster bullets than UZI")


func test_shotgun_is_loudest() -> void:
	var rifle_loud := WeaponConfigComponent.WEAPON_CONFIGS[0]["weapon_loudness"]
	var shotgun_loud := WeaponConfigComponent.WEAPON_CONFIGS[1]["weapon_loudness"]
	var uzi_loud := WeaponConfigComponent.WEAPON_CONFIGS[2]["weapon_loudness"]

	assert_true(shotgun_loud > rifle_loud,
		"SHOTGUN should be louder than RIFLE")
	assert_true(shotgun_loud > uzi_loud,
		"SHOTGUN should be louder than UZI")


func test_shotgun_has_smallest_magazine() -> void:
	var rifle_mag := WeaponConfigComponent.WEAPON_CONFIGS[0]["magazine_size"]
	var shotgun_mag := WeaponConfigComponent.WEAPON_CONFIGS[1]["magazine_size"]
	var uzi_mag := WeaponConfigComponent.WEAPON_CONFIGS[2]["magazine_size"]

	assert_true(shotgun_mag < rifle_mag,
		"SHOTGUN should have a smaller magazine than RIFLE")
	assert_true(shotgun_mag < uzi_mag,
		"SHOTGUN should have a smaller magazine than UZI")


func test_only_shotgun_has_multiple_pellets() -> void:
	assert_eq(WeaponConfigComponent.WEAPON_CONFIGS[0]["pellet_count_min"], 1,
		"RIFLE should fire 1 pellet")
	assert_true(WeaponConfigComponent.WEAPON_CONFIGS[1]["pellet_count_min"] > 1,
		"SHOTGUN should fire multiple pellets")
	assert_eq(WeaponConfigComponent.WEAPON_CONFIGS[2]["pellet_count_min"], 1,
		"UZI should fire 1 pellet")


func test_only_shotgun_has_nonzero_spread_angle() -> void:
	assert_eq(WeaponConfigComponent.WEAPON_CONFIGS[0]["spread_angle"], 0.0,
		"RIFLE should have zero spread_angle")
	assert_true(WeaponConfigComponent.WEAPON_CONFIGS[1]["spread_angle"] > 0.0,
		"SHOTGUN should have positive spread_angle")
	assert_eq(WeaponConfigComponent.WEAPON_CONFIGS[2]["spread_angle"], 0.0,
		"UZI should have zero spread_angle")


# ============================================================================
# get_config() - Valid Weapon Types
# ============================================================================


func test_get_config_returns_rifle_for_type_0() -> void:
	var config := WeaponConfigComponent.get_config(0)
	assert_eq(config["shoot_cooldown"], 0.1,
		"get_config(0) should return RIFLE config")


func test_get_config_returns_shotgun_for_type_1() -> void:
	var config := WeaponConfigComponent.get_config(1)
	assert_eq(config["shoot_cooldown"], 0.8,
		"get_config(1) should return SHOTGUN config")


func test_get_config_returns_uzi_for_type_2() -> void:
	var config := WeaponConfigComponent.get_config(2)
	assert_eq(config["shoot_cooldown"], 0.06,
		"get_config(2) should return UZI config")


func test_get_config_returns_dictionary() -> void:
	for weapon_type in [0, 1, 2]:
		var config := WeaponConfigComponent.get_config(weapon_type)
		assert_typeof(config, TYPE_DICTIONARY,
			"get_config(%d) should return a Dictionary" % weapon_type)


func test_get_config_rifle_matches_constant() -> void:
	var config := WeaponConfigComponent.get_config(0)
	assert_eq(config, WeaponConfigComponent.WEAPON_CONFIGS[0],
		"get_config(0) should match WEAPON_CONFIGS[0]")


func test_get_config_shotgun_matches_constant() -> void:
	var config := WeaponConfigComponent.get_config(1)
	assert_eq(config, WeaponConfigComponent.WEAPON_CONFIGS[1],
		"get_config(1) should match WEAPON_CONFIGS[1]")


func test_get_config_uzi_matches_constant() -> void:
	var config := WeaponConfigComponent.get_config(2)
	assert_eq(config, WeaponConfigComponent.WEAPON_CONFIGS[2],
		"get_config(2) should match WEAPON_CONFIGS[2]")


# ============================================================================
# get_config() - Invalid/Unknown Weapon Types (Defaults to RIFLE)
# ============================================================================


func test_get_config_defaults_to_rifle_for_type_3() -> void:
	var config := WeaponConfigComponent.get_config(3)
	assert_eq(config, WeaponConfigComponent.WEAPON_CONFIGS[0],
		"get_config(3) should default to RIFLE config")


func test_get_config_defaults_to_rifle_for_type_negative_1() -> void:
	var config := WeaponConfigComponent.get_config(-1)
	assert_eq(config, WeaponConfigComponent.WEAPON_CONFIGS[0],
		"get_config(-1) should default to RIFLE config")


func test_get_config_defaults_to_rifle_for_type_99() -> void:
	var config := WeaponConfigComponent.get_config(99)
	assert_eq(config, WeaponConfigComponent.WEAPON_CONFIGS[0],
		"get_config(99) should default to RIFLE config")


func test_get_config_defaults_to_rifle_for_type_1000() -> void:
	var config := WeaponConfigComponent.get_config(1000)
	assert_eq(config, WeaponConfigComponent.WEAPON_CONFIGS[0],
		"get_config(1000) should default to RIFLE config")


func test_get_config_defaults_to_rifle_for_type_negative_100() -> void:
	var config := WeaponConfigComponent.get_config(-100)
	assert_eq(config, WeaponConfigComponent.WEAPON_CONFIGS[0],
		"get_config(-100) should default to RIFLE config")


func test_get_config_default_has_rifle_shoot_cooldown() -> void:
	var config := WeaponConfigComponent.get_config(999)
	assert_eq(config["shoot_cooldown"], 0.1,
		"Default config shoot_cooldown should match RIFLE")


func test_get_config_default_has_rifle_bullet_speed() -> void:
	var config := WeaponConfigComponent.get_config(999)
	assert_eq(config["bullet_speed"], 2500.0,
		"Default config bullet_speed should match RIFLE")


func test_get_config_default_is_not_shotgun() -> void:
	var config := WeaponConfigComponent.get_config(999)
	assert_false(config["is_shotgun"],
		"Default config should not be a shotgun")


# ============================================================================
# get_type_name() - Valid Weapon Types
# ============================================================================


func test_get_type_name_rifle() -> void:
	assert_eq(WeaponConfigComponent.get_type_name(0), "RIFLE",
		"get_type_name(0) should return RIFLE")


func test_get_type_name_shotgun() -> void:
	assert_eq(WeaponConfigComponent.get_type_name(1), "SHOTGUN",
		"get_type_name(1) should return SHOTGUN")


func test_get_type_name_uzi() -> void:
	assert_eq(WeaponConfigComponent.get_type_name(2), "UZI",
		"get_type_name(2) should return UZI")


func test_get_type_name_machete() -> void:
	assert_eq(WeaponConfigComponent.get_type_name(3), "MACHETE",
		"get_type_name(3) should return MACHETE")


func test_get_type_name_rpg() -> void:
	assert_eq(WeaponConfigComponent.get_type_name(4), "RPG",
		"get_type_name(4) should return RPG")


func test_get_type_name_pm() -> void:
	assert_eq(WeaponConfigComponent.get_type_name(5), "PM",
		"get_type_name(5) should return PM")


# ============================================================================
# get_type_name() - Invalid/Unknown Weapon Types
# ============================================================================


func test_get_type_name_unknown_for_type_negative_1() -> void:
	assert_eq(WeaponConfigComponent.get_type_name(-1), "UNKNOWN",
		"get_type_name(-1) should return UNKNOWN")


func test_get_type_name_unknown_for_type_99() -> void:
	assert_eq(WeaponConfigComponent.get_type_name(99), "UNKNOWN",
		"get_type_name(99) should return UNKNOWN")


func test_get_type_name_unknown_for_type_1000() -> void:
	assert_eq(WeaponConfigComponent.get_type_name(1000), "UNKNOWN",
		"get_type_name(1000) should return UNKNOWN")


func test_get_type_name_unknown_for_type_negative_100() -> void:
	assert_eq(WeaponConfigComponent.get_type_name(-100), "UNKNOWN",
		"get_type_name(-100) should return UNKNOWN")


func test_get_type_name_returns_string() -> void:
	for weapon_type in [0, 1, 2, 3, 4, 5, -1, 99]:
		var name := WeaponConfigComponent.get_type_name(weapon_type)
		assert_typeof(name, TYPE_STRING,
			"get_type_name(%d) should return a String" % weapon_type)


# ============================================================================
# Config Field Access Patterns
# ============================================================================


func test_access_config_field_via_get_config() -> void:
	var config := WeaponConfigComponent.get_config(0)
	var speed: float = config["bullet_speed"]
	assert_eq(speed, 2500.0,
		"Should be able to access bullet_speed from get_config result")


func test_access_config_field_via_get_method() -> void:
	var config := WeaponConfigComponent.get_config(1)
	var speed = config.get("bullet_speed", 0.0)
	assert_eq(speed, 1800.0,
		"Should be able to access bullet_speed via Dictionary.get()")


func test_access_config_field_with_default_for_missing_key() -> void:
	var config := WeaponConfigComponent.get_config(0)
	var missing = config.get("nonexistent_key", -1)
	assert_eq(missing, -1,
		"Dictionary.get() with missing key should return the default value")


func test_iterate_all_config_fields() -> void:
	var config := WeaponConfigComponent.get_config(0)
	var field_count := 0
	for key in config:
		field_count += 1
	assert_true(field_count > 0,
		"Config should have iterable fields")


func test_config_is_not_empty() -> void:
	for weapon_type in [0, 1, 2, 3]:
		var config := WeaponConfigComponent.get_config(weapon_type)
		assert_true(config.size() > 0,
			"Config for weapon type %d should not be empty" % weapon_type)


# ============================================================================
# Edge Case Tests
# ============================================================================


func test_get_config_and_get_type_name_consistency() -> void:
	# For all valid types, get_config should return a valid config and
	# get_type_name should return a non-UNKNOWN name
	for weapon_type in [0, 1, 2, 3]:
		var config := WeaponConfigComponent.get_config(weapon_type)
		var name := WeaponConfigComponent.get_type_name(weapon_type)
		assert_true(config.size() > 0,
			"get_config(%d) should return non-empty config" % weapon_type)
		assert_ne(name, "UNKNOWN",
			"get_type_name(%d) should not return UNKNOWN for valid type" % weapon_type)


func test_get_config_and_get_type_name_for_invalid_type() -> void:
	# For invalid types, get_config defaults to RIFLE but get_type_name returns UNKNOWN
	var config := WeaponConfigComponent.get_config(50)
	var name := WeaponConfigComponent.get_type_name(50)
	assert_eq(config, WeaponConfigComponent.WEAPON_CONFIGS[0],
		"get_config(50) should default to RIFLE")
	assert_eq(name, "UNKNOWN",
		"get_type_name(50) should return UNKNOWN")


func test_weapon_configs_is_not_empty() -> void:
	assert_true(WeaponConfigComponent.WEAPON_CONFIGS.size() > 0,
		"WEAPON_CONFIGS should not be empty")


func test_rifle_has_progressive_spread() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[0]
	assert_true(config["spread_threshold"] > 0,
		"RIFLE should have a non-zero spread_threshold for progressive spread")
	assert_true(config["spread_increment"] > 0.0,
		"RIFLE should have a positive spread_increment for progressive spread")


func test_uzi_has_immediate_spread() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[2]
	assert_eq(config["spread_threshold"], 0,
		"UZI should have zero spread_threshold (spread starts immediately)")
	assert_true(config["initial_spread"] > 0.0,
		"UZI should have positive initial_spread")


func test_shotgun_has_no_progressive_spread() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[1]
	assert_eq(config["initial_spread"], 0.0,
		"SHOTGUN should have zero initial_spread (uses pellet spread)")
	assert_eq(config["spread_increment"], 0.0,
		"SHOTGUN should have zero spread_increment (uses pellet spread)")
	assert_eq(config["max_spread"], 0.0,
		"SHOTGUN should have zero max_spread (uses pellet spread)")


# ============================================================================
# MACHETE (Type 3) Config Values
# ============================================================================


func test_machete_shoot_cooldown() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[3]
	assert_eq(config["shoot_cooldown"], 1.5,
		"MACHETE shoot_cooldown (attack cooldown) should be 1.5")


func test_machete_bullet_speed_is_zero() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[3]
	assert_eq(config["bullet_speed"], 0.0,
		"MACHETE bullet_speed should be 0.0 (no projectiles)")


func test_machete_magazine_size_is_zero() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[3]
	assert_eq(config["magazine_size"], 0,
		"MACHETE magazine_size should be 0 (no ammo needed)")


func test_machete_weapon_loudness() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[3]
	assert_eq(config["weapon_loudness"], 200.0,
		"MACHETE weapon_loudness should be 200.0 (quiet melee)")


func test_machete_is_not_shotgun() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[3]
	assert_false(config["is_shotgun"],
		"MACHETE is_shotgun should be false")


func test_machete_is_melee() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[3]
	assert_true(config["is_melee"],
		"MACHETE is_melee should be true")


func test_machete_melee_range() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[3]
	assert_eq(config["melee_range"], 80.0,
		"MACHETE melee_range should be 80.0")


func test_machete_melee_damage() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[3]
	assert_eq(config["melee_damage"], 2,
		"MACHETE melee_damage should be 2")


func test_machete_dodge_speed() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[3]
	assert_eq(config["dodge_speed"], 400.0,
		"MACHETE dodge_speed should be 400.0")


func test_machete_dodge_distance() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[3]
	assert_eq(config["dodge_distance"], 120.0,
		"MACHETE dodge_distance should be 120.0")


func test_machete_sneak_speed_multiplier() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[3]
	assert_eq(config["sneak_speed_multiplier"], 0.6,
		"MACHETE sneak_speed_multiplier should be 0.6")


func test_machete_no_bullet_scene() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[3]
	assert_eq(config["bullet_scene_path"], "",
		"MACHETE should have empty bullet_scene_path")


func test_machete_no_casing_scene() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[3]
	assert_eq(config["casing_scene_path"], "",
		"MACHETE should have empty casing_scene_path")


# ============================================================================
# RPG (Type 4) Config Values (Issue #583)
# ============================================================================


func test_rpg_shoot_cooldown() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[4]
	assert_eq(config["shoot_cooldown"], 2.0,
		"RPG shoot_cooldown should be 2.0")


func test_rpg_bullet_speed() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[4]
	assert_eq(config["bullet_speed"], 800.0,
		"RPG bullet_speed should be 800.0 (slow rocket)")


func test_rpg_magazine_size() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[4]
	assert_eq(config["magazine_size"], 1,
		"RPG magazine_size should be 1 (single shot)")


func test_rpg_weapon_loudness() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[4]
	assert_eq(config["weapon_loudness"], 2500.0,
		"RPG weapon_loudness should be 2500.0 (very loud)")


func test_rpg_is_not_shotgun() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[4]
	assert_false(config["is_shotgun"],
		"RPG is_shotgun should be false")


func test_rpg_is_rpg_flag() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[4]
	assert_true(config["is_rpg"],
		"RPG is_rpg should be true")


func test_rpg_explosion_radius() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[4]
	assert_eq(config["rpg_explosion_radius"], 150.0,
		"RPG rpg_explosion_radius should be 150.0")


func test_rpg_explosion_damage() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[4]
	assert_eq(config["rpg_explosion_damage"], 3,
		"RPG rpg_explosion_damage should be 3")


func test_rpg_switch_weapon_type() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[4]
	assert_eq(config["switch_weapon_type"], 5,
		"RPG switch_weapon_type should be 5 (PM pistol)")


func test_rpg_no_casing_scene() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[4]
	assert_eq(config["casing_scene_path"], "",
		"RPG should have empty casing_scene_path")


func test_rpg_bullet_scene_path() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[4]
	assert_eq(config["bullet_scene_path"], "res://scenes/projectiles/RpgRocket.tscn",
		"RPG bullet_scene_path should point to RpgRocket.tscn")


# ============================================================================
# PM (Type 5) Config Values (Issue #583)
# ============================================================================


func test_pm_shoot_cooldown() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[5]
	assert_eq(config["shoot_cooldown"], 0.3,
		"PM shoot_cooldown should be 0.3 (semi-auto)")


func test_pm_bullet_speed() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[5]
	assert_eq(config["bullet_speed"], 1000.0,
		"PM bullet_speed should be 1000.0")


func test_pm_magazine_size() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[5]
	assert_eq(config["magazine_size"], 9,
		"PM magazine_size should be 9")


func test_pm_weapon_loudness() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[5]
	assert_eq(config["weapon_loudness"], 1469.0,
		"PM weapon_loudness should be 1469.0")


func test_pm_is_not_shotgun() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[5]
	assert_false(config["is_shotgun"],
		"PM is_shotgun should be false")


func test_pm_has_no_rpg_flag() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[5]
	assert_false(config.has("is_rpg"),
		"PM should not have is_rpg flag")


func test_pm_bullet_scene_path() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[5]
	assert_eq(config["bullet_scene_path"], "res://scenes/projectiles/Bullet9mm.tscn",
		"PM bullet_scene_path should point to Bullet9mm.tscn")


func test_pm_caliber_path() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[5]
	assert_eq(config["caliber_path"], "res://resources/calibers/caliber_9x18.tres",
		"PM caliber_path should point to 9x18 caliber data")


func test_pm_casing_scene_path() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[5]
	assert_eq(config["casing_scene_path"], "res://scenes/effects/Casing.tscn",
		"PM should have Casing.tscn casing_scene_path")


func test_pm_spread_threshold() -> void:
	var config := WeaponConfigComponent.WEAPON_CONFIGS[5]
	assert_eq(config["spread_threshold"], 2,
		"PM spread_threshold should be 2")
