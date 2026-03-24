extends GutTest
## Unit tests for the enemy spawner in ExperimentalMenu (Issue #1342).
##
## Verifies that the spawner dropdown includes all eight enemy weapon types:
## RIFLE (0), SHOTGUN (1), UZI (2), MACHETE (3), RPG (4), PM (5),
## MACHINE_GUN (6), SNIPER_RIFLE (7) — plus the PATROL_RIFLE entry.
## The PM (Makarov pistol) type was missing before this fix.
##
## Also verifies special enemy types (Issue #1342):
## Teleporter, Armored Skin, Force Field, Grenadier, Invisible.


# ============================================================================
# Mock spawner types list — mirrors _setup_enemy_spawner() in experimental_menu.gd
# ============================================================================


class MockEnemySpawner:
	## All enemy types available in the spawner dropdown.
	## Each entry must have "name" (String), "weapon_type" (int), "behavior" (int).
	## Special entries may also have: "is_teleporter", "has_armored_skin",
	## "has_force_field", "is_grenadier", "start_invisible" (bool).
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
		{"name": "Teleporter (Rifle)", "weapon_type": 0, "behavior": 1, "is_teleporter": true},
		{"name": "Armored Skin (Rifle)", "weapon_type": 0, "behavior": 1, "has_armored_skin": true},
		{"name": "Force Field (Rifle)", "weapon_type": 0, "behavior": 1, "has_force_field": true},
		{"name": "Grenadier (Rifle)", "weapon_type": 0, "behavior": 1, "is_grenadier": true},
		{"name": "Invisible (Rifle)", "weapon_type": 0, "behavior": 1, "start_invisible": true},
		{"name": "Gas Mask Enemy", "weapon_type": 0, "behavior": 1, "is_gas_mask": true},
		{"name": "Drone Operator", "weapon_type": 0, "behavior": 1, "is_drone_operator": true, "scene": "res://scenes/objects/EnemyDroneOperator.tscn"},
	]

	## Return a list of all weapon_type values present in the spawner.
	func get_weapon_types() -> Array:
		var result: Array = []
		for t in TYPES:
			result.append(t["weapon_type"])
		return result

	## Return the entry for a given weapon_type, or empty dict if not found.
	func get_entry_by_weapon_type(wt: int) -> Dictionary:
		for t in TYPES:
			if t["weapon_type"] == wt:
				return t
		return {}

	## Return all entries that have a given special flag set to true.
	func get_entries_with_flag(flag: String) -> Array:
		var result: Array = []
		for t in TYPES:
			if t.get(flag, false):
				result.append(t)
		return result


var spawner: MockEnemySpawner


func before_each() -> void:
	spawner = MockEnemySpawner.new()


func after_each() -> void:
	spawner = null


# ============================================================================
# Coverage: all eight WeaponType enum values must be present (Issue #1342)
# ============================================================================


func test_spawner_contains_rifle_weapon_type_0() -> void:
	assert_true(0 in spawner.get_weapon_types(),
		"Spawner must include RIFLE (weapon_type 0)")


func test_spawner_contains_shotgun_weapon_type_1() -> void:
	assert_true(1 in spawner.get_weapon_types(),
		"Spawner must include SHOTGUN (weapon_type 1)")


func test_spawner_contains_uzi_weapon_type_2() -> void:
	assert_true(2 in spawner.get_weapon_types(),
		"Spawner must include UZI (weapon_type 2)")


func test_spawner_contains_machete_weapon_type_3() -> void:
	assert_true(3 in spawner.get_weapon_types(),
		"Spawner must include MACHETE (weapon_type 3)")


func test_spawner_contains_rpg_weapon_type_4() -> void:
	assert_true(4 in spawner.get_weapon_types(),
		"Spawner must include RPG (weapon_type 4)")


func test_spawner_contains_pm_weapon_type_5() -> void:
	## This was the missing entry fixed in Issue #1342.
	assert_true(5 in spawner.get_weapon_types(),
		"Spawner must include PM/Makarov pistol (weapon_type 5)")


func test_spawner_contains_machine_gun_weapon_type_6() -> void:
	assert_true(6 in spawner.get_weapon_types(),
		"Spawner must include MACHINE_GUN (weapon_type 6)")


func test_spawner_contains_sniper_rifle_weapon_type_7() -> void:
	assert_true(7 in spawner.get_weapon_types(),
		"Spawner must include SNIPER_RIFLE (weapon_type 7)")


# ============================================================================
# PM entry detail checks
# ============================================================================


func test_pm_entry_has_correct_name() -> void:
	var entry := spawner.get_entry_by_weapon_type(5)
	assert_false(entry.is_empty(),
		"PM entry should exist in the spawner types list")
	assert_true(entry.get("name", "").to_lower().contains("pm") or
		entry.get("name", "").to_lower().contains("makarov"),
		"PM entry name should mention 'PM' or 'Makarov'")


func test_pm_entry_has_guard_behavior() -> void:
	var entry := spawner.get_entry_by_weapon_type(5)
	assert_false(entry.is_empty(), "PM entry should exist")
	assert_eq(entry.get("behavior", -1), 1,
		"PM enemy should use GUARD behavior mode (1)")


# ============================================================================
# Structural checks
# ============================================================================


func test_spawner_has_at_least_sixteen_entries() -> void:
	## 8 weapon types + 1 patrol variant + 7 special enemy types = minimum 16 entries.
	assert_gte(MockEnemySpawner.TYPES.size(), 16,
		"Spawner should have at least 16 entries (8 weapon types + patrol + 7 special types)")


func test_all_entries_have_name_field() -> void:
	for entry in MockEnemySpawner.TYPES:
		assert_true(entry.has("name") and not (entry["name"] as String).is_empty(),
			"Every spawner entry must have a non-empty 'name' field")


func test_all_entries_have_weapon_type_field() -> void:
	for entry in MockEnemySpawner.TYPES:
		assert_true(entry.has("weapon_type"),
			"Every spawner entry must have a 'weapon_type' field")


func test_all_entries_have_behavior_field() -> void:
	for entry in MockEnemySpawner.TYPES:
		assert_true(entry.has("behavior"),
			"Every spawner entry must have a 'behavior' field")


func test_all_weapon_types_are_valid_enum_values() -> void:
	## Valid values: 0–8 (matching WeaponType enum in enemy.gd: RIFLE=0 .. REVOLVER=8).
	for entry in MockEnemySpawner.TYPES:
		var wt: int = entry.get("weapon_type", -1)
		assert_true(wt >= 0 and wt <= 8,
			"weapon_type %d is outside the valid range 0–8" % wt)


func test_spawner_source_contains_pm_entry() -> void:
	## Verify the actual source file includes the PM entry (Issue #1342).
	var file := FileAccess.open("res://scripts/ui/experimental_menu.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open experimental_menu.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains('"weapon_type": 5') or source.contains("weapon_type\": 5"),
		"experimental_menu.gd spawner list must contain weapon_type 5 (PM)")


# ============================================================================
# Special enemy types checks (Issue #1342)
# ============================================================================


func test_spawner_contains_teleporter_entry() -> void:
	var entries := spawner.get_entries_with_flag("is_teleporter")
	assert_gte(entries.size(), 1,
		"Spawner must include at least one Teleporter enemy entry")


func test_spawner_contains_armored_skin_entry() -> void:
	var entries := spawner.get_entries_with_flag("has_armored_skin")
	assert_gte(entries.size(), 1,
		"Spawner must include at least one Armored Skin enemy entry")


func test_spawner_contains_force_field_entry() -> void:
	var entries := spawner.get_entries_with_flag("has_force_field")
	assert_gte(entries.size(), 1,
		"Spawner must include at least one Force Field enemy entry")


func test_spawner_contains_grenadier_entry() -> void:
	var entries := spawner.get_entries_with_flag("is_grenadier")
	assert_gte(entries.size(), 1,
		"Spawner must include at least one Grenadier enemy entry")


func test_spawner_contains_invisible_entry() -> void:
	var entries := spawner.get_entries_with_flag("start_invisible")
	assert_gte(entries.size(), 1,
		"Spawner must include at least one Invisible enemy entry")


func test_teleporter_entry_has_valid_weapon_type() -> void:
	var entries := spawner.get_entries_with_flag("is_teleporter")
	assert_gte(entries.size(), 1, "Teleporter entry must exist")
	var wt: int = entries[0].get("weapon_type", -1)
	assert_true(wt >= 0 and wt <= 7,
		"Teleporter entry must have a valid weapon_type (0–7)")


func test_armored_skin_entry_has_valid_weapon_type() -> void:
	var entries := spawner.get_entries_with_flag("has_armored_skin")
	assert_gte(entries.size(), 1, "Armored Skin entry must exist")
	var wt: int = entries[0].get("weapon_type", -1)
	assert_true(wt >= 0 and wt <= 7,
		"Armored Skin entry must have a valid weapon_type (0–7)")


func test_force_field_entry_has_valid_weapon_type() -> void:
	var entries := spawner.get_entries_with_flag("has_force_field")
	assert_gte(entries.size(), 1, "Force Field entry must exist")
	var wt: int = entries[0].get("weapon_type", -1)
	assert_true(wt >= 0 and wt <= 7,
		"Force Field entry must have a valid weapon_type (0–7)")


func test_grenadier_entry_has_valid_weapon_type() -> void:
	var entries := spawner.get_entries_with_flag("is_grenadier")
	assert_gte(entries.size(), 1, "Grenadier entry must exist")
	var wt: int = entries[0].get("weapon_type", -1)
	assert_true(wt >= 0 and wt <= 7,
		"Grenadier entry must have a valid weapon_type (0–7)")


func test_invisible_entry_has_valid_weapon_type() -> void:
	var entries := spawner.get_entries_with_flag("start_invisible")
	assert_gte(entries.size(), 1, "Invisible entry must exist")
	var wt: int = entries[0].get("weapon_type", -1)
	assert_true(wt >= 0 and wt <= 7,
		"Invisible entry must have a valid weapon_type (0–7)")


func test_spawner_source_contains_teleporter_entry() -> void:
	var file := FileAccess.open("res://scripts/ui/experimental_menu.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open experimental_menu.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains("is_teleporter"),
		"experimental_menu.gd spawner list must contain an is_teleporter entry")


func test_spawner_source_contains_armored_skin_entry() -> void:
	var file := FileAccess.open("res://scripts/ui/experimental_menu.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open experimental_menu.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains("has_armored_skin"),
		"experimental_menu.gd spawner list must contain a has_armored_skin entry")


func test_spawner_source_contains_force_field_entry() -> void:
	var file := FileAccess.open("res://scripts/ui/experimental_menu.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open experimental_menu.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains("has_force_field"),
		"experimental_menu.gd spawner list must contain a has_force_field entry")


func test_spawner_source_contains_grenadier_entry() -> void:
	var file := FileAccess.open("res://scripts/ui/experimental_menu.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open experimental_menu.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains("is_grenadier"),
		"experimental_menu.gd spawner list must contain an is_grenadier entry")


func test_spawner_source_contains_invisible_entry() -> void:
	var file := FileAccess.open("res://scripts/ui/experimental_menu.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open experimental_menu.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains("start_invisible"),
		"experimental_menu.gd spawner list must contain a start_invisible entry")


# ============================================================================
# F8 spawn path in game_manager.gd must match experimental_menu.gd (Issue #1342)
# ============================================================================


func test_f8_spawn_source_contains_pm_entry() -> void:
	## Verify game_manager.gd F8 spawn list includes PM (weapon_type 5) (Issue #1342).
	var file := FileAccess.open("res://scripts/autoload/game_manager.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open game_manager.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains('"weapon_type": 5') or source.contains("weapon_type\": 5"),
		"game_manager.gd F8 spawn list must contain weapon_type 5 (PM)")


func test_f8_spawn_source_contains_teleporter_entry() -> void:
	var file := FileAccess.open("res://scripts/autoload/game_manager.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open game_manager.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains("is_teleporter"),
		"game_manager.gd F8 spawn list must contain an is_teleporter entry")


func test_f8_spawn_source_contains_armored_skin_entry() -> void:
	var file := FileAccess.open("res://scripts/autoload/game_manager.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open game_manager.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains("has_armored_skin"),
		"game_manager.gd F8 spawn list must contain a has_armored_skin entry")


func test_f8_spawn_source_contains_force_field_entry() -> void:
	var file := FileAccess.open("res://scripts/autoload/game_manager.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open game_manager.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains("has_force_field"),
		"game_manager.gd F8 spawn list must contain a has_force_field entry")


func test_f8_spawn_source_contains_grenadier_entry() -> void:
	var file := FileAccess.open("res://scripts/autoload/game_manager.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open game_manager.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains("is_grenadier"),
		"game_manager.gd F8 spawn list must contain an is_grenadier entry")


func test_f8_spawn_source_contains_invisible_entry() -> void:
	var file := FileAccess.open("res://scripts/autoload/game_manager.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open game_manager.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains("start_invisible"),
		"game_manager.gd F8 spawn list must contain a start_invisible entry")


func test_f8_spawn_source_applies_special_flags() -> void:
	## Verify game_manager.gd F8 spawn applies special flags to spawned enemies (Issue #1342).
	var file := FileAccess.open("res://scripts/autoload/game_manager.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open game_manager.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains('enemy.set("is_teleporter"') or source.contains("enemy.set(\"is_teleporter\""),
		"game_manager.gd F8 spawn must apply is_teleporter flag to enemy")


# ============================================================================
# Drone Operator spawner checks (Issue #1397)
# ============================================================================


func test_spawner_contains_drone_operator_entry() -> void:
	var entries := spawner.get_entries_with_flag("is_drone_operator")
	assert_gte(entries.size(), 1,
		"Spawner must include at least one Drone Operator enemy entry")


func test_spawner_source_contains_drone_operator_entry() -> void:
	var file := FileAccess.open("res://scripts/ui/experimental_menu.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open experimental_menu.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains("is_drone_operator"),
		"experimental_menu.gd spawner list must contain an is_drone_operator entry")


func test_f8_spawn_source_contains_drone_operator_entry() -> void:
	var file := FileAccess.open("res://scripts/autoload/game_manager.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open game_manager.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()
	assert_true(source.contains("is_drone_operator"),
		"game_manager.gd F8 spawn list must contain an is_drone_operator entry")
