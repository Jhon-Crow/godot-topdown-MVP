extends GutTest
## Unit tests for decadence_level.gd level script.
##
## Tests saturation constants, exit zone configuration, and level initialization
## for the Hotline Miami "Chapter Three: Decadence" nightclub level.


# ============================================================================
# Mock Classes
# ============================================================================


class MockDecadenceLevel:
	## Saturation effect constants (must match decadence_level.gd).
	const SATURATION_DURATION: float = 0.15
	const SATURATION_INTENSITY: float = 0.25

	## Level state variables.
	var _initial_enemy_count: int = 0
	var _current_enemy_count: int = 0
	var _level_cleared: bool = false
	var _level_completed: bool = false
	var _game_over_shown: bool = false
	var _score_shown: bool = false
	var _enemies: Array = []

	## Exit zone configuration.
	var exit_zone_position: Vector2 = Vector2(120, 1800)
	var exit_zone_width: float = 60.0
	var exit_zone_height: float = 100.0

	## Track state changes.
	var exit_zone_activated: bool = false

	## Level name for identification.
	var level_name: String = "DecadenceLevel"

	## Nightclub dimensions (~2400x2000 pixels).
	var map_width: int = 2400
	var map_height: int = 2000
	var _ammo_label_text: String = ""

	## Initialize with enemies.
	func initialize(enemy_count: int) -> void:
		_enemies.clear()
		for i in range(enemy_count):
			_enemies.append("NightclubEnemy%d" % (i + 1))
		_initial_enemy_count = _enemies.size()
		_current_enemy_count = _initial_enemy_count

	## Called when an enemy dies.
	func on_enemy_died() -> void:
		_current_enemy_count -= 1
		if _current_enemy_count <= 0:
			_level_cleared = true
			exit_zone_activated = true

	## Called when player reaches exit after clearing.
	func on_player_reached_exit() -> void:
		if not _level_cleared or _level_completed:
			return
		_level_completed = true

	func update_ammo_label_magazine(current_mag: int, reserve: int) -> void:
		_ammo_label_text = "AMMO: %d/%d" % [current_mag, reserve]

	func _get_weapon_display_current_ammo(weapon: Dictionary) -> Variant:
		if weapon.get("name") == "Shotgun" and weapon.get("ShellsInTube") != null:
			return weapon.get("ShellsInTube")
		return weapon.get("CurrentAmmo")

	func refresh_weapon_hud(weapon: Dictionary) -> void:
		var displayed_current = _get_weapon_display_current_ammo(weapon)
		var reserve = weapon.get("ReserveAmmo")
		if displayed_current != null and reserve != null:
			update_ammo_label_magazine(displayed_current, reserve)

	func choose_current_weapon(current_weapon: Dictionary, selected_weapon: Dictionary, stale_first_child: Dictionary) -> Dictionary:
		if not current_weapon.is_empty():
			return current_weapon
		if not selected_weapon.is_empty():
			return selected_weapon
		return stale_first_child

	func simulate_deferred_weapon_refresh(stale_first_child: Dictionary, final_current_weapon: Dictionary) -> void:
		refresh_weapon_hud(choose_current_weapon({}, {}, stale_first_child))
		refresh_weapon_hud(choose_current_weapon(final_current_weapon, {}, stale_first_child))


var level: MockDecadenceLevel


func before_each() -> void:
	level = MockDecadenceLevel.new()


func after_each() -> void:
	level = null


# ============================================================================
# Saturation Constants Tests
# ============================================================================


func test_saturation_duration() -> void:
	assert_eq(level.SATURATION_DURATION, 0.15,
		"SATURATION_DURATION should be 0.15 seconds")


func test_saturation_intensity() -> void:
	assert_eq(level.SATURATION_INTENSITY, 0.25,
		"SATURATION_INTENSITY should be 0.25")


# ============================================================================
# Exit Zone Tests
# ============================================================================


func test_exit_zone_position() -> void:
	assert_eq(level.exit_zone_position, Vector2(120, 1800),
		"Decadence level exit zone should be at (120, 1800)")


func test_exit_zone_dimensions() -> void:
	assert_eq(level.exit_zone_width, 60.0,
		"Exit zone width should be 60.0")
	assert_eq(level.exit_zone_height, 100.0,
		"Exit zone height should be 100.0")


# ============================================================================
# Level Initialization Tests
# ============================================================================


func test_level_starts_not_cleared() -> void:
	level.initialize(6)
	assert_false(level._level_cleared,
		"Level should not be cleared at start")
	assert_false(level._level_completed,
		"Level should not be completed at start")


func test_enemy_count_tracking() -> void:
	level.initialize(10)
	assert_eq(level._initial_enemy_count, 10,
		"Initial enemy count should match")
	assert_eq(level._current_enemy_count, 10,
		"Current enemy count should match initial")


func test_level_cleared_when_all_enemies_dead() -> void:
	level.initialize(4)
	for i in range(3):
		level.on_enemy_died()
	assert_false(level._level_cleared, "Not cleared with 1 enemy remaining")
	level.on_enemy_died()
	assert_true(level._level_cleared, "Level should be cleared when all enemies dead")
	assert_true(level.exit_zone_activated, "Exit zone should activate on clear")


func test_player_exit_completes_level() -> void:
	level.initialize(2)
	level.on_enemy_died()
	level.on_enemy_died()
	level.on_player_reached_exit()
	assert_true(level._level_completed,
		"Level should complete when player reaches exit after clearing")


func test_player_exit_blocked_before_clear() -> void:
	level.initialize(3)
	level.on_player_reached_exit()
	assert_false(level._level_completed,
		"Level should not complete if enemies remain")


func test_map_dimensions() -> void:
	assert_eq(level.map_width, 2400, "Decadence map width should be 2400")
	assert_eq(level.map_height, 2000, "Decadence map height should be 2000")


# ============================================================================
# Ammo HUD Tests
# ============================================================================


func test_deferred_weapon_refresh_replaces_stale_makarov_hud_with_m16() -> void:
	var stale_makarov := {"name": "MakarovPM", "CurrentAmmo": 9, "ReserveAmmo": 81}
	var equipped_m16 := {"name": "AssaultRifle", "CurrentAmmo": 30, "ReserveAmmo": 60}

	level.simulate_deferred_weapon_refresh(stale_makarov, equipped_m16)

	assert_eq(level._ammo_label_text, "AMMO: 30/60",
		"Decadence HUD should refresh from startup Makarov ammo to the deferred selected weapon")


func test_source_refreshes_hud_from_player_current_weapon_after_deferred_equip() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/levels/decadence_level.gd")

	assert_string_contains(source, "var current_weapon = _player.get(\"CurrentWeapon\")",
		"Decadence should prefer Player.CurrentWeapon over stale child weapons")
	assert_string_contains(source, "call_deferred(\"_refresh_current_weapon_tracking\", \"deferred selected weapon\")",
		"Decadence should refresh ammo tracking after C# deferred weapon selection")
