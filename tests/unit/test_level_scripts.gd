extends GutTest
## Unit tests for building_level.gd, castle_level.gd, test_tier.gd, and beach_level.gd level scripts.
##
## Tests enemy counting, kill tracking, level completion detection,
## game-over conditions, combo color logic, rank colors, and score integration.


# ============================================================================
# Mock Level Base (Shared Logic for All Level Scripts)
# ============================================================================


class MockLevelBase:
	## Total enemy count at start.
	var _initial_enemy_count: int = 0

	## Current enemy count.
	var _current_enemy_count: int = 0

	## Whether game over has been shown.
	var _game_over_shown: bool = false

	## Whether the level has been cleared (all enemies eliminated).
	var _level_cleared: bool = false

	## Whether the level completion sequence has been triggered.
	var _level_completed: bool = false

	## Duration of saturation effect in seconds.
	const SATURATION_DURATION: float = 0.15

	## Saturation effect intensity (alpha).
	const SATURATION_INTENSITY: float = 0.25

	## List of enemy nodes (simulated).
	var _enemies: Array = []

	## Kill count (tracked externally, simulated here).
	var _kills: int = 0

	## Shots fired (for accuracy tracking).
	var _shots_fired: int = 0

	## Hits registered (for accuracy tracking).
	var _hits: int = 0

	## Track if exit zone was activated.
	var exit_zone_activated: bool = false

	## Track if score screen was shown.
	var score_screen_shown: bool = false

	## Track if victory message was shown.
	var victory_message_shown: bool = false

	## Track if death message was shown.
	var death_message_shown: bool = false

	## Track if game over message was shown.
	var game_over_message_shown: bool = false

	## Setup enemy tracking from a list of enemy names.
	func setup_enemy_tracking(enemy_names: Array) -> void:
		_enemies.clear()
		for enemy_name in enemy_names:
			_enemies.append(enemy_name)
		_initial_enemy_count = _enemies.size()
		_current_enemy_count = _initial_enemy_count

	## Called when an enemy dies.
	func on_enemy_died() -> void:
		_current_enemy_count -= 1
		_kills += 1

		if _current_enemy_count <= 0:
			_level_cleared = true
			_activate_exit_zone()

	## Activate the exit zone after all enemies are eliminated.
	func _activate_exit_zone() -> void:
		exit_zone_activated = true

	## Called when player reaches exit after clearing the level.
	func on_player_reached_exit() -> void:
		if not _level_cleared:
			return
		if _level_completed:
			return
		complete_level_with_score()

	## Complete the level and show the score screen.
	func complete_level_with_score() -> void:
		if _level_completed:
			return
		_level_completed = true
		score_screen_shown = true

	## Check if the level is complete (all enemies dead).
	func is_level_complete() -> bool:
		return _kills >= _initial_enemy_count and _initial_enemy_count > 0

	## Register a shot fired.
	func register_shot() -> void:
		_shots_fired += 1

	## Register a hit.
	func register_hit() -> void:
		_hits += 1

	## Get accuracy as a percentage.
	func get_accuracy() -> float:
		if _shots_fired <= 0:
			return 0.0
		return (float(_hits) / float(_shots_fired)) * 100.0

	## Check if game over should be shown (out of ammo with enemies remaining).
	func should_show_game_over(current_ammo: int, reserve_ammo: int) -> bool:
		if _game_over_shown:
			return false
		if _current_enemy_count <= 0:
			return false
		return current_ammo <= 0 and reserve_ammo <= 0

	## Show game over message.
	func show_game_over_message() -> void:
		_game_over_shown = true
		game_over_message_shown = true

	## Show death message.
	func show_death_message() -> void:
		if _game_over_shown:
			return
		_game_over_shown = true
		death_message_shown = true

	## Show victory message.
	func show_victory_message() -> void:
		victory_message_shown = true

	## Format enemy count label.
	func format_enemy_count() -> String:
		return "Enemies: %d" % _current_enemy_count

	## Get combo color based on combo count.
	## Shared across building_level.gd, castle_level.gd, and test_tier.gd.
	func get_combo_color(combo: int) -> Color:
		if combo >= 10:
			return Color(1.0, 0.0, 1.0, 1.0)   # Magenta
		elif combo >= 7:
			return Color(1.0, 0.0, 0.3, 1.0)   # Hot pink
		elif combo >= 5:
			return Color(1.0, 0.1, 0.1, 1.0)   # Bright red
		elif combo >= 4:
			return Color(1.0, 0.2, 0.0, 1.0)   # Red-orange
		elif combo >= 3:
			return Color(1.0, 0.4, 0.0, 1.0)   # Hot orange
		elif combo >= 2:
			return Color(1.0, 0.6, 0.1, 1.0)   # Orange
		else:
			return Color(1.0, 0.8, 0.2, 1.0)   # Gold (combo 1)

	## Get rank color based on rank string.
	## Shared across building_level.gd and castle_level.gd.
	func get_rank_color(rank: String) -> Color:
		match rank:
			"S":
				return Color(1.0, 0.84, 0.0, 1.0)   # Gold
			"A+":
				return Color(0.0, 1.0, 0.5, 1.0)    # Bright green
			"A":
				return Color(0.2, 0.8, 0.2, 1.0)    # Green
			"B":
				return Color(0.3, 0.7, 1.0, 1.0)    # Blue
			"C":
				return Color(1.0, 1.0, 1.0, 1.0)    # White
			"D":
				return Color(1.0, 0.6, 0.2, 1.0)    # Orange
			"F":
				return Color(1.0, 0.2, 0.2, 1.0)    # Red
			_:
				return Color(1.0, 1.0, 1.0, 1.0)    # Default white


# ============================================================================
# Mock BuildingLevel for Testing
# ============================================================================


class MockBuildingLevel extends MockLevelBase:
	## Building-specific constants.
	var level_name: String = "BuildingLevel"

	## Building dimensions (~2400x2000 pixels).
	var map_width: int = 2400
	var map_height: int = 2000

	## Default enemy count for building level.
	var default_enemy_count: int = 10

	## Makarov PM weapon ammo multiplier (2.5x, Issue #636).
	var pm_ammo_multiplier: float = 2.5

	## Calculate 2.5x ammo for MakarovPM.
	func get_pm_magazine_count(starting_magazines: int) -> int:
		return int(round(starting_magazines * pm_ammo_multiplier))

	## Whether the score screen is currently shown (for W key shortcut).
	var _score_shown: bool = false

	## Next level path for building level.
	var _next_level_path: String = "res://scenes/levels/TestTier.tscn"

	## Level ordering (matching LevelsMenu.LEVELS) — Labyrinth Complex is last.
	var _level_paths: Array[String] = [
		"res://scenes/levels/LabyrinthLevel.tscn",
		"res://scenes/levels/BuildingLevel.tscn",
		"res://scenes/levels/TestTier.tscn",
		"res://scenes/levels/CastleLevel.tscn",
		"res://scenes/levels/RevolverLevel.tscn",
		"res://scenes/levels/CityLevel.tscn",
		"res://scenes/levels/BeachLevel.tscn",
		"res://scenes/levels/DocksLevel.tscn",
		"res://scenes/levels/FactoryLevel.tscn",
		"res://scenes/levels/DecadenceLevel.tscn",
		"res://scenes/levels/Labyrinth2Level.tscn",
	]

	## Initialize with default enemy configuration.
	func initialize() -> void:
		var enemies: Array = []
		for i in range(default_enemy_count):
			enemies.append("Enemy%d" % (i + 1))
		setup_enemy_tracking(enemies)

	## Get the next level path.
	func get_next_level_path(current_scene_path: String) -> String:
		for i in range(_level_paths.size()):
			if _level_paths[i] == current_scene_path:
				if i + 1 < _level_paths.size():
					return _level_paths[i + 1]
				return ""  # Last level
		return ""  # Not found

	# -------------------------------------------------------------------------
	# Ammo label simulation (Issue #1259)
	# -------------------------------------------------------------------------

	## Simulated ammo label text (null means label not yet initialized).
	var _ammo_label_text: Variant = null  # null = not initialized, String = initialized

	## Simulated equipped C# weapon ammo state.
	var _weapon_current_ammo: int = 0
	var _weapon_reserve_ammo: int = 0

	## Initialize ammo label before weapon setup (mirrors the fix in _setup_player_tracking).
	func init_ammo_label() -> void:
		_ammo_label_text = "AMMO: 0/0"

	## Simulate updating the ammo label (mirrors _update_ammo_label_magazine).
	## Returns true if update succeeded (label was initialized), false if label was null.
	func update_ammo_label_magazine(current_mag: int, reserve: int) -> bool:
		if _ammo_label_text == null:
			return false
		_ammo_label_text = "AMMO: %d/%d" % [current_mag, reserve]
		return true

	## Simulate the full player setup sequence, optionally initializing ammo label first.
	## ammo_label_before_weapon: if true, mimics the FIXED order (label init before weapon setup).
	## ammo_label_before_weapon: if false, mimics the BUGGY order (label init after weapon setup).
	func simulate_player_setup(current_mag: int, reserve: int, ammo_label_before_weapon: bool) -> void:
		if ammo_label_before_weapon:
			init_ammo_label()
		# Weapon setup calls update_ammo_label_magazine during _apply_building_ammo_config
		update_ammo_label_magazine(current_mag, reserve)
		if not ammo_label_before_weapon:
			init_ammo_label()

	## Simulate shotgun startup ammo display.
	## Before the fix, the level read CurrentAmmo which remains 0 for shotgun startup UI.
	## After the fix, startup and later HUD refreshes must pick ShellsInTube automatically.
	func _get_weapon_display_current_ammo(weapon: Dictionary) -> Variant:
		if weapon.get("name") == "Shotgun" and weapon.get("ShellsInTube") != null:
			return weapon.get("ShellsInTube")
		return weapon.get("CurrentAmmo")

	func simulate_weapon_display_update(weapon: Dictionary) -> void:
		init_ammo_label()
		refresh_weapon_hud(weapon)

	func refresh_weapon_hud(weapon: Dictionary) -> void:
		var displayed_current = _get_weapon_display_current_ammo(weapon)
		var reserve = weapon.get("ReserveAmmo")
		if displayed_current != null and reserve != null:
			update_ammo_label_magazine(displayed_current, reserve)

	func simulate_csharp_pre_equipped_weapon_setup(weapon: Dictionary) -> void:
		init_ammo_label()
		refresh_weapon_hud(weapon)

	func choose_current_weapon(current_weapon: Dictionary, selected_weapon: Dictionary, stale_first_child: Dictionary) -> Dictionary:
		if not current_weapon.is_empty():
			return current_weapon
		if not selected_weapon.is_empty():
			return selected_weapon
		return stale_first_child

	# -------------------------------------------------------------------------
	# Player death simulation (Issue #1259)
	# -------------------------------------------------------------------------

	## Simulate player dying: triggers death message (mirrors _on_player_died → _show_death_screen).
	func on_player_died() -> void:
		show_death_message()

	## Simulate the C# player ammo-depleted path from BuildingLevel._on_player_ammo_depleted().
	func on_player_ammo_depleted_for_csharp_weapon(current_ammo: int, reserve_ammo: int) -> void:
		_weapon_current_ammo = current_ammo
		_weapon_reserve_ammo = reserve_ammo
		if _current_enemy_count > 0 and not _game_over_shown and current_ammo <= 0 and reserve_ammo <= 0:
			show_game_over_message()


class MockLevelInitFallback:
	var _current_enemy_count: int = 0
	var _game_over_shown: bool = false
	var game_over_message_shown: bool = false

	func show_game_over_message() -> void:
		_game_over_shown = true
		game_over_message_shown = true

	func on_player_ammo_depleted_for_current_weapon(current_ammo: int, reserve_ammo: int) -> void:
		if _current_enemy_count > 0 and not _game_over_shown and current_ammo <= 0 and reserve_ammo <= 0:
			show_game_over_message()


# ============================================================================
# Mock CastleLevel for Testing
# ============================================================================


class MockCastleLevel extends MockLevelBase:
	## Castle-specific constants.
	var level_name: String = "CastleLevel"

	## Castle dimensions (~6000x2560 pixels).
	var map_width: int = 6000
	var map_height: int = 2560

	## Default enemy count for castle level (13 enemies: shotguns, uzis, patrols, lower).
	var default_enemy_count: int = 13

	## Castle-specific weapon ammo multiplier (2x for all weapons).
	var ammo_multiplier: int = 2

	## Makarov PM weapon ammo multiplier (2.5x, Issue #636).
	var pm_ammo_multiplier: float = 2.5

	## Calculate 2.5x ammo for MakarovPM.
	func get_pm_magazine_count(starting_magazines: int) -> int:
		return int(round(starting_magazines * pm_ammo_multiplier))

	## Level ordering — Labyrinth Complex is last.
	var _level_paths: Array[String] = [
		"res://scenes/levels/LabyrinthLevel.tscn",
		"res://scenes/levels/BuildingLevel.tscn",
		"res://scenes/levels/TestTier.tscn",
		"res://scenes/levels/CastleLevel.tscn",
		"res://scenes/levels/RevolverLevel.tscn",
		"res://scenes/levels/CityLevel.tscn",
		"res://scenes/levels/BeachLevel.tscn",
		"res://scenes/levels/DocksLevel.tscn",
		"res://scenes/levels/FactoryLevel.tscn",
		"res://scenes/levels/DecadenceLevel.tscn",
		"res://scenes/levels/Labyrinth2Level.tscn",
	]

	## Initialize with default enemy configuration.
	func initialize() -> void:
		var enemies: Array = []
		for i in range(default_enemy_count):
			enemies.append("CastleEnemy%d" % (i + 1))
		setup_enemy_tracking(enemies)

	## Calculate double ammo for castle level.
	func get_castle_magazine_count(starting_magazines: int) -> int:
		return starting_magazines * ammo_multiplier

	## Get the next level path.
	func get_next_level_path(current_scene_path: String) -> String:
		for i in range(_level_paths.size()):
			if _level_paths[i] == current_scene_path:
				if i + 1 < _level_paths.size():
					return _level_paths[i + 1]
				return ""  # Last level
		return ""  # Not found


# ============================================================================
# Mock TestTier for Testing
# ============================================================================


class MockTestTier extends MockLevelBase:
	## TestTier-specific constants.
	var level_name: String = "TestTier"

	## Map dimensions (4000x2960 playable area).
	var map_width: int = 4000
	var map_height: int = 2960

	## Makarov PM weapon ammo multiplier (2.5x, Issue #636).
	var pm_ammo_multiplier: float = 2.5

	## Calculate 2.5x ammo for MakarovPM.
	func get_pm_magazine_count(starting_magazines: int) -> int:
		return int(round(starting_magazines * pm_ammo_multiplier))

	## Default enemy count for test tier (12 enemies: 6 guards, 4 patrols, 2 RPG).
	var default_enemy_count: int = 12

	## Simulated ammo label text (null means label not yet initialized).
	var _ammo_label_text: Variant = null

	## Whether the score screen is currently shown (for W key shortcut).
	var _score_shown: bool = false

	## Level ordering — Labyrinth Complex is last.
	var _level_paths: Array[String] = [
		"res://scenes/levels/LabyrinthLevel.tscn",
		"res://scenes/levels/BuildingLevel.tscn",
		"res://scenes/levels/TestTier.tscn",
		"res://scenes/levels/CastleLevel.tscn",
		"res://scenes/levels/RevolverLevel.tscn",
		"res://scenes/levels/CityLevel.tscn",
		"res://scenes/levels/BeachLevel.tscn",
		"res://scenes/levels/DocksLevel.tscn",
		"res://scenes/levels/FactoryLevel.tscn",
		"res://scenes/levels/DecadenceLevel.tscn",
		"res://scenes/levels/Labyrinth2Level.tscn",
	]

	## Initialize with default enemy configuration.
	func initialize() -> void:
		var enemies: Array = []
		for i in range(default_enemy_count):
			enemies.append("TestEnemy%d" % (i + 1))
		setup_enemy_tracking(enemies)

	func init_ammo_label() -> void:
		_ammo_label_text = "AMMO: 0/0"

	func update_ammo_label_magazine(current_mag: int, reserve: int) -> bool:
		if _ammo_label_text == null:
			return false
		_ammo_label_text = "AMMO: %d/%d" % [current_mag, reserve]
		return true

	func _get_weapon_display_current_ammo(weapon: Dictionary) -> Variant:
		if weapon.get("name") == "Shotgun" and weapon.get("ShellsInTube") != null:
			return weapon.get("ShellsInTube")
		return weapon.get("CurrentAmmo")

	func simulate_weapon_display_update(weapon: Dictionary) -> void:
		init_ammo_label()
		refresh_weapon_hud(weapon)

	func refresh_weapon_hud(weapon: Dictionary) -> void:
		var displayed_current = _get_weapon_display_current_ammo(weapon)
		var reserve = weapon.get("ReserveAmmo")
		if displayed_current != null and reserve != null:
			update_ammo_label_magazine(displayed_current, reserve)

	func simulate_csharp_pre_equipped_weapon_setup(weapon: Dictionary) -> void:
		init_ammo_label()
		refresh_weapon_hud(weapon)

	func choose_current_weapon(current_weapon: Dictionary, selected_weapon: Dictionary, stale_first_child: Dictionary) -> Dictionary:
		if not current_weapon.is_empty():
			return current_weapon
		if not selected_weapon.is_empty():
			return selected_weapon
		return stale_first_child

	## Get the next level path.
	func get_next_level_path(current_scene_path: String) -> String:
		for i in range(_level_paths.size()):
			if _level_paths[i] == current_scene_path:
				if i + 1 < _level_paths.size():
					return _level_paths[i + 1]
				return ""  # Last level
		return ""  # Not found


class MockLabyrinth2Level extends MockLevelBase:
	## Simulated ammo label text (null means label not yet initialized).
	var _ammo_label_text: Variant = null

	func init_ammo_label() -> void:
		_ammo_label_text = "AMMO: 0/0"

	func update_ammo_label_magazine(current_mag: int, reserve: int) -> bool:
		if _ammo_label_text == null:
			return false
		_ammo_label_text = "AMMO: %d/%d" % [current_mag, reserve]
		return true

	func _get_weapon_display_current_ammo(weapon: Dictionary) -> Variant:
		if weapon.get("name") == "Shotgun" and weapon.get("ShellsInTube") != null:
			return weapon.get("ShellsInTube")
		return weapon.get("CurrentAmmo")

	func simulate_weapon_display_update(weapon: Dictionary) -> void:
		init_ammo_label()
		refresh_weapon_hud(weapon)

	func refresh_weapon_hud(weapon: Dictionary) -> void:
		var displayed_current = _get_weapon_display_current_ammo(weapon)
		var reserve = weapon.get("ReserveAmmo")
		if displayed_current != null and reserve != null:
			update_ammo_label_magazine(displayed_current, reserve)

	func simulate_csharp_pre_equipped_weapon_setup(weapon: Dictionary) -> void:
		init_ammo_label()
		refresh_weapon_hud(weapon)

	func choose_current_weapon(current_weapon: Dictionary, selected_weapon: Dictionary, stale_first_child: Dictionary) -> Dictionary:
		if not current_weapon.is_empty():
			return current_weapon
		if not selected_weapon.is_empty():
			return selected_weapon
		return stale_first_child


# ============================================================================
# Mock BeachLevel for Testing
# ============================================================================


class MockBeachLevel extends MockLevelBase:
	var level_name: String = "BeachLevel"

	## Map dimensions (~2400x2000 playable area).
	var map_width: int = 2400
	var map_height: int = 2000

	## Default enemy count for beach level (8 enemies).
	var default_enemy_count: int = 8

	## Makarov PM weapon ammo multiplier (2.5x, Issue #636).
	var pm_ammo_multiplier: float = 2.5

	## Calculate 2.5x ammo for MakarovPM.
	func get_pm_magazine_count(starting_magazines: int) -> int:
		return int(round(starting_magazines * pm_ammo_multiplier))

	## Whether the score screen is currently shown.
	var _score_shown: bool = false

	## Sunlight configuration (Issue #1234).
	## The sun is placed off-screen in the top-right corner to simulate outdoor daylight.
	var sunlight_position: Vector2 = Vector2(2700, -200)
	var sunlight_color: Color = Color(1.0, 0.95, 0.5, 1.0)
	var sunlight_energy: float = 1.2
	var sunlight_texture_scale: float = 14.0
	var sunlight_shadow_enabled: bool = true

	## Level ordering — Labyrinth Complex is last.
	var _level_paths: Array[String] = [
		"res://scenes/levels/LabyrinthLevel.tscn",
		"res://scenes/levels/BuildingLevel.tscn",
		"res://scenes/levels/TestTier.tscn",
		"res://scenes/levels/CastleLevel.tscn",
		"res://scenes/levels/RevolverLevel.tscn",
		"res://scenes/levels/CityLevel.tscn",
		"res://scenes/levels/BeachLevel.tscn",
		"res://scenes/levels/DocksLevel.tscn",
		"res://scenes/levels/FactoryLevel.tscn",
		"res://scenes/levels/DecadenceLevel.tscn",
		"res://scenes/levels/Labyrinth2Level.tscn",
	]

	## Initialize with default enemy configuration.
	func initialize() -> void:
		var enemies: Array = []
		for i in range(default_enemy_count):
			enemies.append("BeachEnemy%d" % (i + 1))
		setup_enemy_tracking(enemies)

	## Get the next level path.
	func get_next_level_path(current_scene_path: String) -> String:
		for i in range(_level_paths.size()):
			if _level_paths[i] == current_scene_path:
				if i + 1 < _level_paths.size():
					return _level_paths[i + 1]
				return ""  # Last level
		return ""  # Not found


class MockLabyrinthLevel extends MockLevelBase:
	## Laboratory / starting level (Issue #808: weapon-dependent tutorial hints).
	var level_name: String = "LabyrinthLevel"

	## Default enemy count for labyrinth (5 enemies).
	var default_enemy_count: int = 5

	## Laboratory-specific rank thresholds (Issue #823).
	## Shifted one step down so that the old A score gives S.
	const LABYRINTH_RANK_THRESHOLDS: Dictionary = {
		"S": 0.70,
		"A+": 0.55,
		"A": 0.38,
		"B": 0.22,
		"C": 0.12,
		"D": 0.06,
		"F": 0.0
	}

	## Tutorial hint tracking (Issue #808): weapon-dependent, mirrors tutorial_level.gd.
	var _tutorial_hints: Dictionary = {}

	## Tutorial state machine (mirrors labyrinth_level.gd TutorialStep).
	enum TutorialStep { RELOAD, THROW_GRENADE, COMPLETED }
	var _tutorial_step: int = TutorialStep.RELOAD

	## Weapon type flags.
	var _tutorial_has_shotgun: bool = false
	var _tutorial_has_sniper_rifle: bool = false
	var _tutorial_has_revolver: bool = false
	var _tutorial_has_makarov_pm: bool = false

	## State tracking.
	var _tutorial_has_reloaded: bool = false
	var _tutorial_has_thrown_grenade: bool = false

	## Hint keys.
	const HINT_RELOAD := "reload"
	const HINT_GRENADE := "grenade"
	const HINT_HAMMER_COCK := "hammer_cock"
	const HINT_BOLT_CYCLE := "bolt_cycle"

	## Setup weapon-dependent tutorial hints at level start (Issue #808).
	func setup_tutorial_hints() -> void:
		_tutorial_step = TutorialStep.RELOAD
		_add_reload_hints()

	## Add weapon-dependent reload hints plus grenade hint.
	func _add_reload_hints() -> void:
		if _tutorial_has_shotgun:
			_tutorial_hints[HINT_RELOAD] = "[ПКМ↑ открыть] [СКМ+ПКМ↓ x8] [ПКМ↓ закрыть]"
		elif _tutorial_has_sniper_rifle:
			_tutorial_hints[HINT_RELOAD] = "[R] [F] [R] Перезарядись"
			_tutorial_hints[HINT_BOLT_CYCLE] = "[←↓↑→] Передёрни затвор"
		elif _tutorial_has_revolver:
			_tutorial_hints[HINT_RELOAD] = "[R открыть] [ПКМ↑ патрон] [скролл] [R закрыть]"
			_tutorial_hints[HINT_HAMMER_COCK] = "[ПКМ] Взведи курок"
		elif _tutorial_has_makarov_pm:
			_tutorial_hints[HINT_RELOAD] = "[R] [R] Перезарядись"
		else:
			_tutorial_hints[HINT_RELOAD] = "[R] [F] [R] Перезарядись"
		if not _tutorial_hints.has(HINT_GRENADE):
			_tutorial_hints[HINT_GRENADE] = "[G+ПКМ вправо] [G+ПКМ→отпусти G] [ПКМ бросок]"

	## Called when hammer is cocked — dismisses hammer hint.
	func on_hammer_cocked() -> void:
		_tutorial_hints.erase(HINT_HAMMER_COCK)

	## Called when reload completes.
	func on_reload_completed() -> void:
		if _tutorial_step != TutorialStep.RELOAD:
			return
		if not _tutorial_has_reloaded:
			_tutorial_has_reloaded = true
			_tutorial_hints.erase(HINT_RELOAD)
			_tutorial_hints.erase(HINT_HAMMER_COCK)
			if _tutorial_has_thrown_grenade:
				_tutorial_step = TutorialStep.COMPLETED
				_tutorial_hints.clear()
			else:
				_tutorial_step = TutorialStep.THROW_GRENADE

	## Called when grenade is thrown.
	func on_grenade_thrown() -> void:
		if _tutorial_step != TutorialStep.THROW_GRENADE and _tutorial_step != TutorialStep.RELOAD:
			return
		if not _tutorial_has_thrown_grenade:
			_tutorial_has_thrown_grenade = true
			_tutorial_hints.erase(HINT_GRENADE)
			if _tutorial_step == TutorialStep.THROW_GRENADE:
				_tutorial_step = TutorialStep.COMPLETED
				_tutorial_hints.clear()

	## Check if a tutorial hint is currently active.
	func is_tutorial_hint_active(hint_key: String) -> bool:
		return _tutorial_hints.has(hint_key)

	## Check if all tutorial hints are dismissed.
	func are_all_hints_dismissed() -> bool:
		return _tutorial_hints.is_empty()

	## Check if tutorial is complete.
	func is_tutorial_complete() -> bool:
		return _tutorial_step == TutorialStep.COMPLETED

	## Initialize with default enemy configuration.
	func initialize() -> void:
		var enemies: Array = []
		for i in range(default_enemy_count):
			enemies.append("LabyrinthEnemy%d" % (i + 1))
		setup_enemy_tracking(enemies)
		setup_tutorial_hints()


var building_level: MockBuildingLevel
var castle_level: MockCastleLevel
var level_init_fallback: MockLevelInitFallback
var test_tier: MockTestTier
var beach_level: MockBeachLevel
var labyrinth_level: MockLabyrinthLevel
var labyrinth2_level: MockLabyrinth2Level


func before_each() -> void:
	building_level = MockBuildingLevel.new()
	castle_level = MockCastleLevel.new()
	level_init_fallback = MockLevelInitFallback.new()
	test_tier = MockTestTier.new()
	beach_level = MockBeachLevel.new()
	labyrinth_level = MockLabyrinthLevel.new()
	labyrinth2_level = MockLabyrinth2Level.new()


func after_each() -> void:
	building_level = null
	castle_level = null
	test_tier = null
	beach_level = null
	labyrinth_level = null
	labyrinth2_level = null


# ============================================================================
# Building Level Default Configuration Tests
# ============================================================================


func test_building_level_name() -> void:
	assert_eq(building_level.level_name, "BuildingLevel",
		"Building level name should be BuildingLevel")


func test_building_level_map_dimensions() -> void:
	assert_eq(building_level.map_width, 2400,
		"Building map width should be 2400")
	assert_eq(building_level.map_height, 2000,
		"Building map height should be 2000")


func test_building_level_default_enemy_count() -> void:
	assert_eq(building_level.default_enemy_count, 10,
		"Building level should have 10 enemies by default")


func test_building_level_initial_state() -> void:
	assert_eq(building_level._initial_enemy_count, 0,
		"Initial enemy count should be 0 before setup")
	assert_eq(building_level._current_enemy_count, 0,
		"Current enemy count should be 0 before setup")
	assert_false(building_level._game_over_shown,
		"Game over should not be shown initially")
	assert_false(building_level._level_cleared,
		"Level should not be cleared initially")
	assert_false(building_level._level_completed,
		"Level should not be completed initially")


# ============================================================================
# Building Level Enemy Tracking Tests
# ============================================================================


func test_building_level_initialize_sets_enemy_count() -> void:
	building_level.initialize()

	assert_eq(building_level._initial_enemy_count, 10,
		"Should track 10 enemies after initialization")
	assert_eq(building_level._current_enemy_count, 10,
		"Current enemy count should match initial count")


func test_building_level_enemy_tracking_custom() -> void:
	building_level.setup_enemy_tracking(["A", "B", "C", "D", "E"])

	assert_eq(building_level._initial_enemy_count, 5,
		"Should track 5 enemies")
	assert_eq(building_level._current_enemy_count, 5,
		"Current count should be 5")


func test_building_level_enemy_died_decrements_count() -> void:
	building_level.initialize()
	building_level.on_enemy_died()

	assert_eq(building_level._current_enemy_count, 9,
		"Current enemy count should decrease by 1")
	assert_eq(building_level._kills, 1,
		"Kill count should increment by 1")


func test_building_level_multiple_enemy_deaths() -> void:
	building_level.initialize()

	for i in range(5):
		building_level.on_enemy_died()

	assert_eq(building_level._current_enemy_count, 5,
		"Current enemy count should be 5 after killing 5 of 10")
	assert_eq(building_level._kills, 5,
		"Kill count should be 5")


func test_building_level_all_enemies_killed() -> void:
	building_level.initialize()

	for i in range(10):
		building_level.on_enemy_died()

	assert_eq(building_level._current_enemy_count, 0,
		"Current enemy count should be 0 after all killed")
	assert_eq(building_level._kills, 10,
		"Kill count should match initial count")
	assert_true(building_level._level_cleared,
		"Level should be marked as cleared")
	assert_true(building_level.exit_zone_activated,
		"Exit zone should be activated")


func test_building_level_is_level_complete() -> void:
	building_level.initialize()

	assert_false(building_level.is_level_complete(),
		"Level should NOT be complete at start")

	for i in range(10):
		building_level.on_enemy_died()

	assert_true(building_level.is_level_complete(),
		"Level should be complete when kills >= initial enemy count")


# ============================================================================
# Building Level Level Completion Tests
# ============================================================================


func test_building_level_exit_triggers_score_screen() -> void:
	building_level.initialize()

	# Kill all enemies first
	for i in range(10):
		building_level.on_enemy_died()

	# Player reaches exit
	building_level.on_player_reached_exit()

	assert_true(building_level._level_completed,
		"Level should be marked as completed")
	assert_true(building_level.score_screen_shown,
		"Score screen should be shown")


func test_building_level_exit_without_clearing_does_nothing() -> void:
	building_level.initialize()

	# Kill only some enemies
	for i in range(5):
		building_level.on_enemy_died()

	# Player reaches exit (but level not cleared)
	building_level.on_player_reached_exit()

	assert_false(building_level._level_completed,
		"Level should NOT be completed when enemies remain")
	assert_false(building_level.score_screen_shown,
		"Score screen should NOT be shown")


func test_building_level_prevents_duplicate_completion() -> void:
	building_level.initialize()

	for i in range(10):
		building_level.on_enemy_died()

	building_level.on_player_reached_exit()
	var first_completed := building_level._level_completed

	# Second call should be a no-op
	building_level.score_screen_shown = false
	building_level.on_player_reached_exit()

	assert_true(first_completed,
		"First completion should succeed")
	assert_false(building_level.score_screen_shown,
		"Second completion call should not re-show score screen")


# ============================================================================
# Building Level Next Level Path Tests
# ============================================================================


func test_building_level_next_is_testtier() -> void:
	var next := building_level.get_next_level_path("res://scenes/levels/BuildingLevel.tscn")

	assert_eq(next, "res://scenes/levels/TestTier.tscn",
		"Next level after BuildingLevel should be TestTier (Labyrinth Complex is now last)")


func test_building_level_unknown_scene_returns_empty() -> void:
	var next := building_level.get_next_level_path("res://scenes/levels/Unknown.tscn")

	assert_eq(next, "",
		"Unknown scene path should return empty string")


# ============================================================================
# Castle Level Default Configuration Tests
# ============================================================================


func test_castle_level_name() -> void:
	assert_eq(castle_level.level_name, "CastleLevel",
		"Castle level name should be CastleLevel")


func test_castle_level_map_dimensions() -> void:
	assert_eq(castle_level.map_width, 6000,
		"Castle map width should be 6000")
	assert_eq(castle_level.map_height, 2560,
		"Castle map height should be 2560")


func test_castle_level_map_larger_than_building() -> void:
	assert_gt(castle_level.map_width, building_level.map_width,
		"Castle should be wider than building")
	assert_gt(castle_level.map_height, building_level.map_height,
		"Castle should be taller than building")


func test_castle_level_default_enemy_count() -> void:
	assert_eq(castle_level.default_enemy_count, 13,
		"Castle level should have 13 enemies by default")


func test_castle_level_more_enemies_than_building() -> void:
	assert_gt(castle_level.default_enemy_count, building_level.default_enemy_count,
		"Castle should have more enemies than building")


# ============================================================================
# Castle Level Enemy Tracking Tests
# ============================================================================


func test_castle_level_initialize_sets_enemy_count() -> void:
	castle_level.initialize()

	assert_eq(castle_level._initial_enemy_count, 13,
		"Should track 13 enemies after initialization")
	assert_eq(castle_level._current_enemy_count, 13,
		"Current enemy count should match initial count")


func test_castle_level_all_enemies_killed() -> void:
	castle_level.initialize()

	for i in range(13):
		castle_level.on_enemy_died()

	assert_eq(castle_level._current_enemy_count, 0,
		"Current enemy count should be 0 after all killed")
	assert_true(castle_level._level_cleared,
		"Level should be marked as cleared")
	assert_true(castle_level.exit_zone_activated,
		"Exit zone should be activated")


func test_castle_level_partial_kills() -> void:
	castle_level.initialize()

	for i in range(7):
		castle_level.on_enemy_died()

	assert_eq(castle_level._current_enemy_count, 6,
		"6 enemies should remain after killing 7 of 13")
	assert_false(castle_level._level_cleared,
		"Level should NOT be cleared with enemies remaining")


# ============================================================================
# Castle Level Ammo Multiplier Tests
# ============================================================================


func test_castle_ammo_multiplier() -> void:
	assert_eq(castle_level.ammo_multiplier, 2,
		"Castle ammo multiplier should be 2x")


func test_castle_double_magazines_from_4() -> void:
	var result := castle_level.get_castle_magazine_count(4)

	assert_eq(result, 8,
		"4 starting magazines * 2 = 8 magazines for castle")


func test_castle_double_magazines_from_2() -> void:
	var result := castle_level.get_castle_magazine_count(2)

	assert_eq(result, 4,
		"2 starting magazines * 2 = 4 magazines for castle")


func test_castle_double_magazines_from_1() -> void:
	var result := castle_level.get_castle_magazine_count(1)

	assert_eq(result, 2,
		"1 starting magazine * 2 = 2 magazines for castle")


# ============================================================================
# Makarov PM 2.5x Ammo Multiplier Tests (Issue #636)
# ============================================================================


func test_pm_ammo_multiplier_building() -> void:
	assert_almost_eq(building_level.pm_ammo_multiplier, 2.5, 0.01,
		"Building level PM ammo multiplier should be 2.5x")


func test_pm_ammo_multiplier_castle() -> void:
	assert_almost_eq(castle_level.pm_ammo_multiplier, 2.5, 0.01,
		"Castle level PM ammo multiplier should be 2.5x")


func test_pm_ammo_multiplier_test_tier() -> void:
	assert_almost_eq(test_tier.pm_ammo_multiplier, 2.5, 0.01,
		"TestTier PM ammo multiplier should be 2.5x")


func test_pm_ammo_multiplier_beach() -> void:
	assert_almost_eq(beach_level.pm_ammo_multiplier, 2.5, 0.01,
		"BeachLevel PM ammo multiplier should be 2.5x")


func test_pm_magazines_from_4() -> void:
	var result := building_level.get_pm_magazine_count(4)

	assert_eq(result, 10,
		"4 starting magazines * 2.5 = 10 magazines for MakarovPM")


func test_pm_magazines_from_2() -> void:
	var result := building_level.get_pm_magazine_count(2)

	assert_eq(result, 5,
		"2 starting magazines * 2.5 = 5 magazines for MakarovPM")


func test_pm_magazines_from_1() -> void:
	var result := building_level.get_pm_magazine_count(1)

	assert_true(result == 2 or result == 3,
		"1 starting magazine * 2.5 = 2 or 3 (rounded) magazines for MakarovPM")


func test_pm_multiplier_consistent_across_levels() -> void:
	var pm_count_4: int = building_level.get_pm_magazine_count(4)
	assert_eq(pm_count_4, castle_level.get_pm_magazine_count(4),
		"Building and Castle PM magazine count should match for 4 starting mags")
	assert_eq(pm_count_4, test_tier.get_pm_magazine_count(4),
		"Building and TestTier PM magazine count should match for 4 starting mags")
	assert_eq(pm_count_4, beach_level.get_pm_magazine_count(4),
		"Building and Beach PM magazine count should match for 4 starting mags")


func test_pm_multiplier_greater_than_castle_base() -> void:
	var pm_mags: int = castle_level.get_pm_magazine_count(4)
	var castle_mags: int = castle_level.get_castle_magazine_count(4)

	assert_gt(pm_mags, castle_mags,
		"PM 2.5x magazines (%d) should be more than Castle 2x (%d)" % [pm_mags, castle_mags])


# ============================================================================
# Castle Level Next Level Path Tests
# ============================================================================


func test_castle_level_is_last_level() -> void:
	var next := castle_level.get_next_level_path("res://scenes/levels/CastleLevel.tscn")

	assert_eq(next, "",
		"Castle is the last level, next should be empty")


func test_castle_level_test_tier_next_is_castle() -> void:
	var next := castle_level.get_next_level_path("res://scenes/levels/TestTier.tscn")

	assert_eq(next, "res://scenes/levels/CastleLevel.tscn",
		"Next level after TestTier should be CastleLevel")


# ============================================================================
# TestTier Default Configuration Tests
# ============================================================================


func test_test_tier_name() -> void:
	assert_eq(test_tier.level_name, "TestTier",
		"Test tier level name should be TestTier")


func test_test_tier_map_dimensions() -> void:
	assert_eq(test_tier.map_width, 4000,
		"TestTier map width should be 4000")
	assert_eq(test_tier.map_height, 2960,
		"TestTier map height should be 2960")


func test_test_tier_default_enemy_count() -> void:
	assert_eq(test_tier.default_enemy_count, 12,
		"TestTier should have 12 enemies by default")


func test_test_tier_more_enemies_than_building() -> void:
	assert_gt(test_tier.default_enemy_count, building_level.default_enemy_count,
		"TestTier should have more enemies than Building (12 vs 10, includes RPG enemies)")


# ============================================================================
# TestTier Enemy Tracking Tests
# ============================================================================


func test_test_tier_initialize_sets_enemy_count() -> void:
	test_tier.initialize()

	assert_eq(test_tier._initial_enemy_count, 12,
		"Should track 12 enemies after initialization")


func test_test_tier_all_enemies_killed_clears_level() -> void:
	test_tier.initialize()

	for i in range(12):
		test_tier.on_enemy_died()

	assert_eq(test_tier._current_enemy_count, 0,
		"Current enemy count should be 0")
	assert_true(test_tier._level_cleared,
		"Level should be marked as cleared")
	assert_true(test_tier.exit_zone_activated,
		"Exit zone should be activated")


func test_test_tier_kill_tracking() -> void:
	test_tier.initialize()

	test_tier.on_enemy_died()
	test_tier.on_enemy_died()
	test_tier.on_enemy_died()

	assert_eq(test_tier._kills, 3,
		"Kill count should be 3 after 3 enemy deaths")
	assert_eq(test_tier._current_enemy_count, 9,
		"9 enemies should remain")


# ============================================================================
# TestTier Next Level Path Tests
# ============================================================================


func test_test_tier_next_is_castle() -> void:
	var next := test_tier.get_next_level_path("res://scenes/levels/TestTier.tscn")

	assert_eq(next, "res://scenes/levels/CastleLevel.tscn",
		"Next level after TestTier should be CastleLevel")


# ============================================================================
# Shared Saturation Effect Tests (All Levels)
# ============================================================================


func test_saturation_duration_constant() -> void:
	assert_eq(MockLevelBase.SATURATION_DURATION, 0.15,
		"Saturation duration should be 0.15 seconds")


func test_saturation_intensity_constant() -> void:
	assert_eq(MockLevelBase.SATURATION_INTENSITY, 0.25,
		"Saturation intensity should be 0.25")


func test_saturation_flash_in_time() -> void:
	var expected := MockLevelBase.SATURATION_DURATION * 0.3
	assert_almost_eq(expected, 0.045, 0.001,
		"Flash in should be 30% of duration (0.045s)")


func test_saturation_flash_out_time() -> void:
	var expected := MockLevelBase.SATURATION_DURATION * 0.7
	assert_almost_eq(expected, 0.105, 0.001,
		"Flash out should be 70% of duration (0.105s)")


func test_saturation_flash_in_plus_out_equals_duration() -> void:
	var flash_in := MockLevelBase.SATURATION_DURATION * 0.3
	var flash_out := MockLevelBase.SATURATION_DURATION * 0.7
	assert_almost_eq(flash_in + flash_out, MockLevelBase.SATURATION_DURATION, 0.001,
		"Flash in + flash out should equal total duration")


# ============================================================================
# Shared Combo Color Tests (All Levels)
# ============================================================================


func test_combo_color_gold_at_combo_1() -> void:
	var color := building_level.get_combo_color(1)
	assert_eq(color, Color(1.0, 0.8, 0.2, 1.0),
		"Combo 1 should be gold")


func test_combo_color_orange_at_combo_2() -> void:
	var color := building_level.get_combo_color(2)
	assert_eq(color, Color(1.0, 0.6, 0.1, 1.0),
		"Combo 2 should be orange")


func test_combo_color_hot_orange_at_combo_3() -> void:
	var color := building_level.get_combo_color(3)
	assert_eq(color, Color(1.0, 0.4, 0.0, 1.0),
		"Combo 3 should be hot orange")


func test_combo_color_red_orange_at_combo_4() -> void:
	var color := building_level.get_combo_color(4)
	assert_eq(color, Color(1.0, 0.2, 0.0, 1.0),
		"Combo 4 should be red-orange")


func test_combo_color_bright_red_at_combo_5() -> void:
	var color := building_level.get_combo_color(5)
	assert_eq(color, Color(1.0, 0.1, 0.1, 1.0),
		"Combo 5 should be bright red")


func test_combo_color_hot_pink_at_combo_7() -> void:
	var color := building_level.get_combo_color(7)
	assert_eq(color, Color(1.0, 0.0, 0.3, 1.0),
		"Combo 7 should be hot pink")


func test_combo_color_magenta_at_combo_10() -> void:
	var color := building_level.get_combo_color(10)
	assert_eq(color, Color(1.0, 0.0, 1.0, 1.0),
		"Combo 10 should be magenta")


func test_combo_color_magenta_at_combo_15() -> void:
	var color := building_level.get_combo_color(15)
	assert_eq(color, Color(1.0, 0.0, 1.0, 1.0),
		"Combo 15 (above 10) should still be magenta")


func test_combo_colors_consistent_across_levels() -> void:
	# All three levels should produce the same combo colors
	for combo in [1, 2, 3, 4, 5, 7, 10]:
		var building_color := building_level.get_combo_color(combo)
		var castle_color := castle_level.get_combo_color(combo)
		var tier_color := test_tier.get_combo_color(combo)

		assert_eq(building_color, castle_color,
			"Building and Castle combo color should match at combo %d" % combo)
		assert_eq(castle_color, tier_color,
			"Castle and TestTier combo color should match at combo %d" % combo)


func test_combo_colors_get_hotter_with_higher_combo() -> void:
	# Higher combos should have lower green/blue values (hotter colors)
	var color_1 := building_level.get_combo_color(1)
	var color_5 := building_level.get_combo_color(5)
	var color_10 := building_level.get_combo_color(10)

	assert_true(color_5.g < color_1.g,
		"Combo 5 green channel should be less than combo 1 (hotter)")
	# Combo 10 magenta has higher blue than combo 5 red, so test green channel
	assert_true(color_10.g < color_1.g,
		"Combo 10 green channel should be less than combo 1 (hottest)")


# ============================================================================
# Shared Rank Color Tests (Building/Castle Levels)
# ============================================================================


func test_rank_color_s_is_gold() -> void:
	var color := building_level.get_rank_color("S")
	assert_eq(color, Color(1.0, 0.84, 0.0, 1.0),
		"S rank should be gold")


func test_rank_color_a_plus_is_bright_green() -> void:
	var color := building_level.get_rank_color("A+")
	assert_eq(color, Color(0.0, 1.0, 0.5, 1.0),
		"A+ rank should be bright green")


func test_rank_color_a_is_green() -> void:
	var color := building_level.get_rank_color("A")
	assert_eq(color, Color(0.2, 0.8, 0.2, 1.0),
		"A rank should be green")


func test_rank_color_b_is_blue() -> void:
	var color := building_level.get_rank_color("B")
	assert_eq(color, Color(0.3, 0.7, 1.0, 1.0),
		"B rank should be blue")


func test_rank_color_c_is_white() -> void:
	var color := building_level.get_rank_color("C")
	assert_eq(color, Color(1.0, 1.0, 1.0, 1.0),
		"C rank should be white")


func test_rank_color_d_is_orange() -> void:
	var color := building_level.get_rank_color("D")
	assert_eq(color, Color(1.0, 0.6, 0.2, 1.0),
		"D rank should be orange")


func test_rank_color_f_is_red() -> void:
	var color := building_level.get_rank_color("F")
	assert_eq(color, Color(1.0, 0.2, 0.2, 1.0),
		"F rank should be red")


func test_rank_color_unknown_is_white() -> void:
	var color := building_level.get_rank_color("X")
	assert_eq(color, Color(1.0, 1.0, 1.0, 1.0),
		"Unknown rank should default to white")


func test_rank_colors_consistent_between_building_and_castle() -> void:
	for rank in ["S", "A+", "A", "B", "C", "D", "F"]:
		var building_color := building_level.get_rank_color(rank)
		var castle_color := castle_level.get_rank_color(rank)

		assert_eq(building_color, castle_color,
			"Building and Castle rank color should match for rank %s" % rank)


# ============================================================================
# Shared Accuracy Tracking Tests (All Levels)
# ============================================================================


func test_accuracy_zero_shots() -> void:
	assert_eq(building_level.get_accuracy(), 0.0,
		"Accuracy with no shots should be 0.0%")


func test_accuracy_all_hits() -> void:
	building_level.register_shot()
	building_level.register_shot()
	building_level.register_shot()
	building_level.register_hit()
	building_level.register_hit()
	building_level.register_hit()

	assert_almost_eq(building_level.get_accuracy(), 100.0, 0.01,
		"Accuracy should be 100% when all shots hit")


func test_accuracy_half_hits() -> void:
	for i in range(10):
		building_level.register_shot()
	for i in range(5):
		building_level.register_hit()

	assert_almost_eq(building_level.get_accuracy(), 50.0, 0.01,
		"Accuracy should be 50% with 5 hits in 10 shots")


func test_accuracy_one_hit_many_shots() -> void:
	for i in range(100):
		building_level.register_shot()
	building_level.register_hit()

	assert_almost_eq(building_level.get_accuracy(), 1.0, 0.01,
		"Accuracy should be 1% with 1 hit in 100 shots")


# ============================================================================
# Shared Game Over Condition Tests (All Levels)
# ============================================================================


func test_game_over_no_ammo_with_enemies() -> void:
	building_level.initialize()

	assert_true(building_level.should_show_game_over(0, 0),
		"Should show game over with no ammo and enemies remaining")


func test_game_over_not_with_current_ammo() -> void:
	building_level.initialize()

	assert_false(building_level.should_show_game_over(10, 0),
		"Should NOT show game over with current ammo")


func test_game_over_not_with_reserve_ammo() -> void:
	building_level.initialize()

	assert_false(building_level.should_show_game_over(0, 30),
		"Should NOT show game over with reserve ammo")


func test_game_over_not_when_no_enemies() -> void:
	building_level.initialize()
	for i in range(10):
		building_level.on_enemy_died()

	assert_false(building_level.should_show_game_over(0, 0),
		"Should NOT show game over when all enemies are dead (victory instead)")


func test_game_over_not_shown_twice() -> void:
	building_level.initialize()

	building_level.show_game_over_message()
	assert_true(building_level._game_over_shown,
		"Game over should be shown")

	assert_false(building_level.should_show_game_over(0, 0),
		"Should NOT show game over again")


func test_death_message_not_shown_after_game_over() -> void:
	building_level.initialize()

	building_level.show_game_over_message()
	building_level.show_death_message()

	assert_true(building_level.game_over_message_shown,
		"Game over message should be shown")
	assert_false(building_level.death_message_shown,
		"Death message should NOT be shown after game over already shown")


# ============================================================================
# Shared Enemy Count Label Format Tests
# ============================================================================


func test_format_enemy_count_initial() -> void:
	building_level.initialize()
	var label := building_level.format_enemy_count()

	assert_eq(label, "Enemies: 10",
		"Enemy count label should show initial count")


func test_format_enemy_count_after_kills() -> void:
	building_level.initialize()
	building_level.on_enemy_died()
	building_level.on_enemy_died()
	building_level.on_enemy_died()
	var label := building_level.format_enemy_count()

	assert_eq(label, "Enemies: 7",
		"Enemy count label should show remaining enemies")


func test_format_enemy_count_zero() -> void:
	building_level.initialize()
	for i in range(10):
		building_level.on_enemy_died()
	var label := building_level.format_enemy_count()

	assert_eq(label, "Enemies: 0",
		"Enemy count label should show 0 when all killed")


# ============================================================================
# Full Level Completion Flow Tests
# ============================================================================


func test_building_level_full_flow() -> void:
	building_level.initialize()

	# Kill all enemies
	for i in range(10):
		building_level.on_enemy_died()

	assert_true(building_level._level_cleared, "Level should be cleared")
	assert_true(building_level.exit_zone_activated, "Exit zone should be activated")

	# Player reaches exit
	building_level.on_player_reached_exit()

	assert_true(building_level._level_completed, "Level should be completed")
	assert_true(building_level.score_screen_shown, "Score screen should be shown")


func test_castle_level_full_flow() -> void:
	castle_level.initialize()

	# Kill all enemies
	for i in range(13):
		castle_level.on_enemy_died()

	assert_true(castle_level._level_cleared, "Level should be cleared")
	assert_true(castle_level.exit_zone_activated, "Exit zone should be activated")

	# Player reaches exit
	castle_level.on_player_reached_exit()

	assert_true(castle_level._level_completed, "Level should be completed")
	assert_true(castle_level.score_screen_shown, "Score screen should be shown")


func test_test_tier_full_flow() -> void:
	test_tier.initialize()

	# Kill all enemies
	for i in range(12):
		test_tier.on_enemy_died()

	assert_true(test_tier._level_cleared, "Level should be cleared")
	assert_true(test_tier.exit_zone_activated, "Exit zone should be activated")

	# Player reaches exit
	test_tier.on_player_reached_exit()

	assert_true(test_tier._level_completed, "Level should be completed")
	assert_true(test_tier.score_screen_shown, "Score screen should be shown")


# ============================================================================
# Score Integration Tests
# ============================================================================


func test_level_complete_with_accuracy_tracking() -> void:
	test_tier.initialize()

	# Simulate combat: 15 shots, 12 hits, 12 kills
	for i in range(15):
		test_tier.register_shot()
	for i in range(12):
		test_tier.register_hit()
		test_tier.on_enemy_died()

	assert_true(test_tier.is_level_complete(),
		"Level should be complete")
	assert_almost_eq(test_tier.get_accuracy(), 80.0, 0.1,
		"Accuracy should be ~80.0%")
	assert_eq(test_tier._kills, 12,
		"Kill count should be 12")


func test_all_levels_track_accuracy_consistently() -> void:
	# Setup all levels
	building_level.initialize()
	castle_level.initialize()
	test_tier.initialize()

	# Same actions on all levels
	for level in [building_level, castle_level, test_tier]:
		level.register_shot()
		level.register_shot()
		level.register_hit()

	assert_almost_eq(building_level.get_accuracy(), 50.0, 0.01)
	assert_almost_eq(castle_level.get_accuracy(), 50.0, 0.01)
	assert_almost_eq(test_tier.get_accuracy(), 50.0, 0.01)


# ============================================================================
# Level Ordering / Progression Tests
# ============================================================================


func test_level_order_building_to_testtier_to_castle_to_revolver_labyrinth2_is_last() -> void:
	var first := building_level.get_next_level_path("res://scenes/levels/BuildingLevel.tscn")
	assert_eq(first, "res://scenes/levels/TestTier.tscn",
		"BuildingLevel -> TestTier (Labyrinth Complex moved to last)")

	var second := test_tier.get_next_level_path("res://scenes/levels/TestTier.tscn")
	assert_eq(second, "res://scenes/levels/CastleLevel.tscn",
		"TestTier -> CastleLevel")

	var third := castle_level.get_next_level_path("res://scenes/levels/CastleLevel.tscn")
	assert_eq(third, "res://scenes/levels/RevolverLevel.tscn",
		"CastleLevel -> Double Corridor (RevolverLevel) — Issue #952")

	var last := building_level.get_next_level_path("res://scenes/levels/DecadenceLevel.tscn")
	assert_eq(last, "res://scenes/levels/Labyrinth2Level.tscn",
		"DecadenceLevel -> Labyrinth2Level (Labyrinth Complex is last in progression)")


# ============================================================================
# Edge Case Tests
# ============================================================================


func test_enemy_died_with_no_enemies_tracked() -> void:
	# Don't initialize - no enemies set up
	building_level.on_enemy_died()

	assert_eq(building_level._current_enemy_count, -1,
		"Current count goes negative with no setup (defensive check)")
	assert_eq(building_level._kills, 1,
		"Kill count still increments")


func test_is_level_complete_with_zero_initial_enemies() -> void:
	# Level with no enemies
	building_level.setup_enemy_tracking([])

	assert_false(building_level.is_level_complete(),
		"Level with 0 initial enemies should not register as complete")


func test_accuracy_with_no_hits() -> void:
	building_level.register_shot()
	building_level.register_shot()
	building_level.register_shot()

	assert_almost_eq(building_level.get_accuracy(), 0.0, 0.01,
		"Accuracy should be 0% with no hits")


func test_exit_zone_not_activated_before_clear() -> void:
	building_level.initialize()

	for i in range(9):
		building_level.on_enemy_died()

	assert_false(building_level.exit_zone_activated,
		"Exit zone should NOT be activated with 1 enemy remaining")
	assert_false(building_level._level_cleared,
		"Level should NOT be cleared with 1 enemy remaining")

	# Kill the last enemy
	building_level.on_enemy_died()

	assert_true(building_level.exit_zone_activated,
		"Exit zone should be activated after last enemy killed")
	assert_true(building_level._level_cleared,
		"Level should be cleared after last enemy killed")


# ============================================================================
# BeachLevel Default Configuration Tests
# ============================================================================


func test_beach_level_name() -> void:
	assert_eq(beach_level.level_name, "BeachLevel",
		"Beach level name should be BeachLevel")


func test_beach_level_map_dimensions() -> void:
	assert_eq(beach_level.map_width, 2400,
		"BeachLevel map width should be 2400")
	assert_eq(beach_level.map_height, 2000,
		"BeachLevel map height should be 2000")


func test_beach_level_default_enemy_count() -> void:
	assert_eq(beach_level.default_enemy_count, 8,
		"BeachLevel should have 8 enemies by default")


# ============================================================================
# BeachLevel Enemy Tracking Tests
# ============================================================================


func test_beach_level_initialize_sets_enemy_count() -> void:
	beach_level.initialize()
	assert_eq(beach_level._initial_enemy_count, 8,
		"After initialization, beach level should track 8 enemies")
	assert_eq(beach_level._current_enemy_count, 8,
		"Current enemy count should match initial count")


func test_beach_level_enemy_kill_decrements_count() -> void:
	beach_level.initialize()
	beach_level.on_enemy_died()
	assert_eq(beach_level._current_enemy_count, 7,
		"After one kill, beach level should have 7 enemies remaining")


func test_beach_level_cleared_when_all_enemies_killed() -> void:
	beach_level.initialize()
	for i in range(8):
		beach_level.on_enemy_died()
	assert_true(beach_level._level_cleared,
		"Beach level should be cleared after all 8 enemies killed")
	assert_true(beach_level.exit_zone_activated,
		"Exit zone should activate after clearing beach level")


func test_beach_level_not_cleared_with_enemies_remaining() -> void:
	beach_level.initialize()
	for i in range(7):
		beach_level.on_enemy_died()
	assert_false(beach_level._level_cleared,
		"Beach level should NOT be cleared with 1 enemy remaining")


# ============================================================================
# BeachLevel Saturation Effect Tests
# ============================================================================


func test_beach_level_saturation_constants() -> void:
	assert_eq(beach_level.SATURATION_DURATION, 0.15,
		"Beach level saturation duration should be 0.15 seconds")
	assert_eq(beach_level.SATURATION_INTENSITY, 0.25,
		"Beach level saturation intensity should be 0.25")


# ============================================================================
# BeachLevel Sunlight Tests (Issue #1234)
# ============================================================================


func test_beach_level_sunlight_position_is_offscreen_top_right() -> void:
	## Sunlight must be off-screen in the top-right corner (outside map bounds 64–2464 x, 64–2064 y).
	assert_true(beach_level.sunlight_position.x > 2464,
		"Sunlight x position should be outside right map boundary (>2464)")
	assert_true(beach_level.sunlight_position.y < 64,
		"Sunlight y position should be above top map boundary (<64)")


func test_beach_level_sunlight_color_is_warm() -> void:
	## Sunlight should be warm (golden-yellow), not cold blue.
	assert_almost_eq(beach_level.sunlight_color.r, 1.0, 0.01,
		"Sunlight red channel should be 1.0 (full)")
	assert_true(beach_level.sunlight_color.g > 0.85,
		"Sunlight green channel should be high (warm golden)")
	assert_true(beach_level.sunlight_color.b < 0.85,
		"Sunlight blue channel should be lower than green (warm, not cold)")


func test_beach_level_sunlight_energy_is_bright() -> void:
	## Sunlight must be bright enough to illuminate the whole outdoor scene.
	assert_true(beach_level.sunlight_energy >= 1.0,
		"Sunlight energy should be at least 1.0 for outdoor daylight")


func test_beach_level_sunlight_covers_whole_map() -> void:
	## texture_scale * 256 must reach the farthest map corner from the sun position.
	## Bottom-left corner of the map is approximately (64, 2064).
	var far_corner := Vector2(64, 2064)
	var dist := beach_level.sunlight_position.distance_to(far_corner)
	var light_radius := beach_level.sunlight_texture_scale * 256.0
	assert_true(light_radius >= dist,
		"Sunlight radius (scale*256=%.0f) must reach farthest corner (dist=%.0f)" % [light_radius, dist])


func test_beach_level_sunlight_shadows_enabled() -> void:
	## Shadows must be enabled so obstacles (rocks, huts) block the sunlight.
	assert_true(beach_level.sunlight_shadow_enabled,
		"Sunlight shadows must be enabled for obstacles to cast shadows")


# ============================================================================
# BeachLevel Combo Color Tests
# ============================================================================


func test_beach_level_combo_colors_match_other_levels() -> void:
	for combo in [1, 3, 5, 7, 10]:
		assert_eq(beach_level.get_combo_color(combo), building_level.get_combo_color(combo),
			"Beach and Building combo color should match at combo %d" % combo)


# ============================================================================
# BeachLevel Full Flow Tests (Issue #596 - Ammo Counter Fix)
# ============================================================================


func test_beach_level_full_flow() -> void:
	beach_level.initialize()

	# Kill all enemies
	for i in range(8):
		beach_level.on_enemy_died()

	assert_true(beach_level._level_cleared, "Level should be cleared")
	assert_true(beach_level.exit_zone_activated, "Exit zone should be activated")

	# Player reaches exit
	beach_level.on_player_reached_exit()

	assert_true(beach_level._level_completed, "Level should be completed")
	assert_true(beach_level.score_screen_shown, "Score screen should be shown")


func test_beach_level_exit_without_clearing_does_nothing() -> void:
	beach_level.initialize()

	# Kill only some enemies
	for i in range(4):
		beach_level.on_enemy_died()

	# Player reaches exit (but level not cleared)
	beach_level.on_player_reached_exit()

	assert_false(beach_level._level_completed,
		"Level should NOT be completed when enemies remain")
	assert_false(beach_level.score_screen_shown,
		"Score screen should NOT be shown")


func test_beach_level_prevents_duplicate_completion() -> void:
	beach_level.initialize()

	for i in range(8):
		beach_level.on_enemy_died()

	beach_level.on_player_reached_exit()
	var first_completed := beach_level._level_completed

	# Second call should be a no-op
	beach_level.score_screen_shown = false
	beach_level.on_player_reached_exit()

	assert_true(first_completed,
		"First completion should succeed")
	assert_false(beach_level.score_screen_shown,
		"Second completion call should not re-show score screen")


# ============================================================================
# BeachLevel Ammo / Game Over Tests (Issue #596)
# ============================================================================


func test_beach_level_game_over_no_ammo_with_enemies() -> void:
	beach_level.initialize()

	assert_true(beach_level.should_show_game_over(0, 0),
		"Beach level should show game over with no ammo and enemies remaining")


func test_beach_level_game_over_not_with_current_ammo() -> void:
	beach_level.initialize()

	assert_false(beach_level.should_show_game_over(8, 0),
		"Beach level should NOT show game over with current ammo")


func test_beach_level_game_over_not_with_reserve_ammo() -> void:
	beach_level.initialize()

	assert_false(beach_level.should_show_game_over(0, 16),
		"Beach level should NOT show game over with reserve ammo")


func test_beach_level_game_over_not_when_cleared() -> void:
	beach_level.initialize()
	for i in range(8):
		beach_level.on_enemy_died()

	assert_false(beach_level.should_show_game_over(0, 0),
		"Beach level should NOT show game over when all enemies are dead")


func test_beach_level_game_over_not_shown_twice() -> void:
	beach_level.initialize()

	beach_level.show_game_over_message()
	assert_true(beach_level._game_over_shown,
		"Game over should be shown")

	assert_false(beach_level.should_show_game_over(0, 0),
		"Beach level should NOT show game over again")


func test_beach_level_death_message_not_shown_after_game_over() -> void:
	beach_level.initialize()

	beach_level.show_game_over_message()
	beach_level.show_death_message()

	assert_true(beach_level.game_over_message_shown,
		"Game over message should be shown")
	assert_false(beach_level.death_message_shown,
		"Death message should NOT be shown after game over already shown")


# ============================================================================
# BeachLevel Accuracy Tracking Tests (Issue #596)
# ============================================================================


func test_beach_level_accuracy_zero_shots() -> void:
	assert_eq(beach_level.get_accuracy(), 0.0,
		"Beach level accuracy with no shots should be 0.0%")


func test_beach_level_accuracy_all_hits() -> void:
	beach_level.register_shot()
	beach_level.register_shot()
	beach_level.register_hit()
	beach_level.register_hit()

	assert_almost_eq(beach_level.get_accuracy(), 100.0, 0.01,
		"Beach level accuracy should be 100% when all shots hit")


func test_beach_level_accuracy_consistent_with_other_levels() -> void:
	building_level.initialize()
	beach_level.initialize()

	for level in [building_level, beach_level]:
		level.register_shot()
		level.register_shot()
		level.register_hit()

	assert_almost_eq(building_level.get_accuracy(), beach_level.get_accuracy(), 0.01,
		"Beach and Building accuracy should be consistent for same inputs")


# ============================================================================
# BeachLevel Rank Color Tests (Issue #596)
# ============================================================================


func test_beach_level_rank_colors_match_other_levels() -> void:
	for rank in ["S", "A+", "A", "B", "C", "D", "F"]:
		var beach_color := beach_level.get_rank_color(rank)
		var building_color := building_level.get_rank_color(rank)

		assert_eq(beach_color, building_color,
			"Beach and Building rank color should match for rank %s" % rank)


# ============================================================================
# BeachLevel Next Level Path Tests (Issue #596)
# ============================================================================


func test_beach_level_is_last_in_ordering() -> void:
	var next := beach_level.get_next_level_path("res://scenes/levels/BeachLevel.tscn")

	assert_eq(next, "",
		"BeachLevel should be the last level (no next)")


func test_beach_level_after_castle() -> void:
	var next := beach_level.get_next_level_path("res://scenes/levels/CastleLevel.tscn")

	assert_eq(next, "res://scenes/levels/BeachLevel.tscn",
		"Next level after CastleLevel should be BeachLevel")


# ============================================================================
# BeachLevel Level Complete with Accuracy (Issue #596)
# ============================================================================


func test_beach_level_complete_with_accuracy_tracking() -> void:
	beach_level.initialize()

	# Simulate combat: 12 shots, 8 hits, 8 kills
	for i in range(12):
		beach_level.register_shot()
	for i in range(8):
		beach_level.register_hit()
		beach_level.on_enemy_died()

	assert_true(beach_level.is_level_complete(),
		"Beach level should be complete")
	assert_almost_eq(beach_level.get_accuracy(), 66.67, 0.1,
		"Beach level accuracy should be ~66.67%")
	assert_eq(beach_level._kills, 8,
		"Beach level kill count should be 8")


# ============================================================================
# LabyrinthLevel Tutorial Hints Tests (Issue #808)
# Weapon-dependent hints, same as Tutorial level — no walk/shoot hints.
# ============================================================================


func test_labyrinth_five_default_enemies() -> void:
	labyrinth_level.initialize()

	assert_eq(labyrinth_level._initial_enemy_count, 5,
		"Labyrinth should have 5 enemies by default")


func test_labyrinth_tutorial_shows_reload_and_grenade_at_start() -> void:
	labyrinth_level.initialize()

	assert_true(labyrinth_level.is_tutorial_hint_active(MockLabyrinthLevel.HINT_RELOAD),
		"Reload hint should be shown at start")
	assert_true(labyrinth_level.is_tutorial_hint_active(MockLabyrinthLevel.HINT_GRENADE),
		"Grenade hint should be shown at start alongside reload (Issue #808)")


func test_labyrinth_tutorial_no_walk_or_shoot_hints() -> void:
	labyrinth_level.initialize()

	assert_false(labyrinth_level.is_tutorial_hint_active("move"),
		"No movement hint in Lab tutorial (owner request)")
	assert_false(labyrinth_level.is_tutorial_hint_active("shoot"),
		"No shoot hint in Lab tutorial (owner request)")


func test_labyrinth_reload_dismisses_reload_hint_grenade_remains() -> void:
	labyrinth_level.initialize()

	labyrinth_level.on_reload_completed()

	assert_false(labyrinth_level.is_tutorial_hint_active(MockLabyrinthLevel.HINT_RELOAD),
		"Reload hint should be dismissed after reload")
	assert_true(labyrinth_level.is_tutorial_hint_active(MockLabyrinthLevel.HINT_GRENADE),
		"Grenade hint should remain after reload (Issue #808)")


func test_labyrinth_grenade_thrown_completes_after_reload() -> void:
	labyrinth_level.initialize()

	labyrinth_level.on_reload_completed()
	labyrinth_level.on_grenade_thrown()

	assert_true(labyrinth_level.is_tutorial_complete(),
		"Tutorial should complete after reload then grenade")
	assert_true(labyrinth_level.are_all_hints_dismissed(),
		"All hints dismissed after tutorial complete")


func test_labyrinth_grenade_before_reload_dismisses_grenade_hint() -> void:
	labyrinth_level.initialize()

	labyrinth_level.on_grenade_thrown()

	assert_false(labyrinth_level.is_tutorial_hint_active(MockLabyrinthLevel.HINT_GRENADE),
		"Grenade hint dismissed even when thrown before reload")
	assert_true(labyrinth_level.is_tutorial_hint_active(MockLabyrinthLevel.HINT_RELOAD),
		"Reload hint still visible when grenade thrown early")


func test_labyrinth_reload_after_early_grenade_completes_tutorial() -> void:
	labyrinth_level.initialize()

	labyrinth_level.on_grenade_thrown()  # Grenade first
	labyrinth_level.on_reload_completed()  # Then reload

	assert_true(labyrinth_level.is_tutorial_complete(),
		"Tutorial completes when reload done after early grenade")
	assert_true(labyrinth_level.are_all_hints_dismissed(),
		"No hints remain after tutorial completes")


func test_labyrinth_revolver_shows_hammer_cock_hint() -> void:
	labyrinth_level._tutorial_has_revolver = true
	labyrinth_level.initialize()

	assert_true(labyrinth_level.is_tutorial_hint_active(MockLabyrinthLevel.HINT_HAMMER_COCK),
		"Revolver should show hammer cock hint (Issue #808)")
	assert_true(labyrinth_level.is_tutorial_hint_active(MockLabyrinthLevel.HINT_RELOAD),
		"Revolver should show reload hint")
	assert_true(labyrinth_level.is_tutorial_hint_active(MockLabyrinthLevel.HINT_GRENADE),
		"Revolver should show grenade hint simultaneously")


func test_labyrinth_hammer_cocked_dismisses_hammer_hint() -> void:
	labyrinth_level._tutorial_has_revolver = true
	labyrinth_level.initialize()

	labyrinth_level.on_hammer_cocked()

	assert_false(labyrinth_level.is_tutorial_hint_active(MockLabyrinthLevel.HINT_HAMMER_COCK),
		"Hammer hint dismissed when hammer is cocked (Issue #808)")
	assert_true(labyrinth_level.is_tutorial_hint_active(MockLabyrinthLevel.HINT_RELOAD),
		"Reload hint still visible after hammer cocked")


func test_labyrinth_shotgun_no_hammer_hint() -> void:
	labyrinth_level._tutorial_has_shotgun = true
	labyrinth_level.initialize()

	assert_false(labyrinth_level.is_tutorial_hint_active(MockLabyrinthLevel.HINT_HAMMER_COCK),
		"Shotgun should not show hammer hint")
	assert_true(labyrinth_level.is_tutorial_hint_active(MockLabyrinthLevel.HINT_RELOAD),
		"Shotgun should show reload hint")


# ============================================================================
# LabyrinthLevel Rank Threshold Tests (Issue #823)
# Shifted thresholds: score that previously gave A now gives S.
# ============================================================================


func test_labyrinth_rank_thresholds_exist() -> void:
	assert_true(MockLabyrinthLevel.LABYRINTH_RANK_THRESHOLDS.has("S"),
		"Labyrinth thresholds should have S")
	assert_true(MockLabyrinthLevel.LABYRINTH_RANK_THRESHOLDS.has("A+"),
		"Labyrinth thresholds should have A+")
	assert_true(MockLabyrinthLevel.LABYRINTH_RANK_THRESHOLDS.has("A"),
		"Labyrinth thresholds should have A")
	assert_true(MockLabyrinthLevel.LABYRINTH_RANK_THRESHOLDS.has("B"),
		"Labyrinth thresholds should have B")
	assert_true(MockLabyrinthLevel.LABYRINTH_RANK_THRESHOLDS.has("C"),
		"Labyrinth thresholds should have C")
	assert_true(MockLabyrinthLevel.LABYRINTH_RANK_THRESHOLDS.has("D"),
		"Labyrinth thresholds should have D")
	assert_true(MockLabyrinthLevel.LABYRINTH_RANK_THRESHOLDS.has("F"),
		"Labyrinth thresholds should have F")


func test_labyrinth_s_threshold_equals_old_a_threshold() -> void:
	## Key requirement of Issue #823: S threshold is 0.70 (the old default A threshold).
	assert_almost_eq(MockLabyrinthLevel.LABYRINTH_RANK_THRESHOLDS["S"], 0.70, 0.001,
		"Laboratory S threshold should be 0.70 (same as default A threshold)")


func test_labyrinth_a_plus_threshold_equals_old_b_threshold() -> void:
	assert_almost_eq(MockLabyrinthLevel.LABYRINTH_RANK_THRESHOLDS["A+"], 0.55, 0.001,
		"Laboratory A+ threshold should be 0.55 (same as default B threshold)")


func test_labyrinth_a_threshold_equals_old_c_threshold() -> void:
	assert_almost_eq(MockLabyrinthLevel.LABYRINTH_RANK_THRESHOLDS["A"], 0.38, 0.001,
		"Laboratory A threshold should be 0.38 (same as default C threshold)")


func test_labyrinth_b_threshold_equals_old_d_threshold() -> void:
	assert_almost_eq(MockLabyrinthLevel.LABYRINTH_RANK_THRESHOLDS["B"], 0.22, 0.001,
		"Laboratory B threshold should be 0.22 (same as default D threshold)")


func test_labyrinth_thresholds_are_lower_than_defaults() -> void:
	## All non-F thresholds should be lower than or equal to their default equivalents.
	assert_true(MockLabyrinthLevel.LABYRINTH_RANK_THRESHOLDS["S"] < 1.0,
		"Laboratory S threshold should be lower than default (1.0)")
	assert_true(MockLabyrinthLevel.LABYRINTH_RANK_THRESHOLDS["A+"] < 0.85,
		"Laboratory A+ threshold should be lower than default (0.85)")
	assert_true(MockLabyrinthLevel.LABYRINTH_RANK_THRESHOLDS["A"] < 0.70,
		"Laboratory A threshold should be lower than default (0.70)")
	assert_true(MockLabyrinthLevel.LABYRINTH_RANK_THRESHOLDS["B"] < 0.55,
		"Laboratory B threshold should be lower than default (0.55)")


func test_labyrinth_thresholds_descending_order() -> void:
	var t := MockLabyrinthLevel.LABYRINTH_RANK_THRESHOLDS
	assert_true(t["S"] > t["A+"], "S threshold must be greater than A+")
	assert_true(t["A+"] > t["A"], "A+ threshold must be greater than A")
	assert_true(t["A"] > t["B"], "A threshold must be greater than B")
	assert_true(t["B"] > t["C"], "B threshold must be greater than C")
	assert_true(t["C"] > t["D"], "C threshold must be greater than D")
	assert_true(t["D"] > t["F"], "D threshold must be greater than F")


# ============================================================================
# Building Level Player Death Tests (Issue #1259)
# ============================================================================


func test_building_player_death_shows_death_message() -> void:
	## When player dies, the death message ("YOU DIED") must be shown.
	building_level.initialize()

	building_level.on_player_died()

	assert_true(building_level.death_message_shown,
		"Player death should trigger the death message (Issue #1259)")


func test_building_player_death_sets_game_over() -> void:
	## Player death sets _game_over_shown so no further death/game-over messages fire.
	building_level.initialize()

	building_level.on_player_died()

	assert_true(building_level._game_over_shown,
		"Player death should mark _game_over_shown to prevent duplicate messages (Issue #1259)")


func test_building_player_death_does_not_show_game_over_message() -> void:
	## on_player_died uses show_death_message, NOT show_game_over_message.
	building_level.initialize()

	building_level.on_player_died()

	assert_false(building_level.game_over_message_shown,
		"Player death should not trigger game-over-message (only death message)")


func test_building_player_second_death_ignored() -> void:
	## Dying twice should not re-show the death message.
	building_level.initialize()

	building_level.on_player_died()
	building_level.death_message_shown = false  # Reset flag to detect second trigger
	building_level.on_player_died()

	assert_false(building_level.death_message_shown,
		"Second player death call should be ignored after _game_over_shown is true (Issue #1259)")


# ============================================================================
# Building Level Ammo Counter Tests (Issue #1259)
# ============================================================================


func test_building_ammo_label_initialized_before_weapon_setup() -> void:
	## In the FIXED code, _ammo_label is initialized before _setup_selected_weapon,
	## so the first ammo update call during weapon setup succeeds.
	# Simulate the fixed order: label initialized BEFORE weapon setup runs
	building_level.simulate_player_setup(30, 60, true)  # ammo_label_before = true (fixed order)

	assert_true(building_level._ammo_label_text != null,
		"Ammo label must be initialized before weapon setup (Issue #1259)")
	assert_eq(building_level._ammo_label_text, "AMMO: 30/60",
		"Ammo label must show weapon ammo after weapon setup (Issue #1259)")


func test_building_csharp_ammo_depleted_shows_game_over_when_no_ammo_left() -> void:
	## BuildingLevel must show the out-of-ammo label when the C# player emits AmmoDepleted
	## and the active weapon has neither loaded nor reserve ammo left (Issue #1821).
	building_level.initialize()

	building_level.on_player_ammo_depleted_for_csharp_weapon(0, 0)

	assert_true(building_level.game_over_message_shown,
		"C# AmmoDepleted with 0/0 ammo must show the game-over message on BuildingLevel")


func test_building_csharp_ammo_depleted_does_not_show_game_over_when_reserve_remains() -> void:
	## Empty-clicks with reserve ammo remaining must not end the run.
	building_level.initialize()

	building_level.on_player_ammo_depleted_for_csharp_weapon(0, 12)

	assert_false(building_level.game_over_message_shown,
		"C# AmmoDepleted with reserve ammo remaining must not show the game-over message")


func test_level_init_fallback_csharp_ammo_depleted_shows_game_over_when_no_ammo_left() -> void:
	## The C# fallback path must mirror BuildingLevel.gd when the project skips the
	## GDScript setup and LevelInitFallback handles the map state (Issue #1821).
	level_init_fallback._current_enemy_count = 10

	level_init_fallback.on_player_ammo_depleted_for_current_weapon(0, 0)

	assert_true(level_init_fallback.game_over_message_shown,
		"LevelInitFallback must show the game-over message when CurrentWeapon ammo is 0/0")


func test_level_init_fallback_csharp_ammo_depleted_ignores_empty_click_with_reserve() -> void:
	level_init_fallback._current_enemy_count = 10

	level_init_fallback.on_player_ammo_depleted_for_current_weapon(0, 30)

	assert_false(level_init_fallback.game_over_message_shown,
		"LevelInitFallback must not show the game-over message when reserve ammo remains")


func test_building_ammo_label_buggy_order_misses_initial_update() -> void:
	## In the BUGGY code (before fix), _ammo_label was null when weapon setup called
	## _update_ammo_label_magazine, so the initial ammo display was skipped.
	# Simulate buggy order: label initialized AFTER weapon setup
	building_level.simulate_player_setup(30, 60, false)

	# The label is initialized after, but the ammo update during weapon setup was lost
	assert_true(building_level._ammo_label_text != null,
		"Label gets initialized eventually even in buggy order")
	# In buggy order the weapon setup update call returns false (label was null then)
	# We verify this by directly simulating the buggy sequence
	var buggy_level := MockBuildingLevel.new()
	# Weapon setup fires: label still null → update returns false
	var update_succeeded := buggy_level.update_ammo_label_magazine(30, 60)
	# Label initialized afterwards
	buggy_level.init_ammo_label()

	assert_false(update_succeeded,
		"Ammo update during weapon setup fails when label is not yet initialized (bug proof)")
	assert_eq(buggy_level._ammo_label_text, "AMMO: 0/0",
		"After buggy init, label shows default 0/0 instead of actual ammo (bug proof)")


func test_building_ammo_label_update_reflects_magazine_ammo() -> void:
	## Ammo counter must display current/reserve ammo correctly.
	building_level.init_ammo_label()

	var updated := building_level.update_ammo_label_magazine(15, 30)

	assert_true(updated, "Ammo label update should succeed when label is initialized")
	assert_eq(building_level._ammo_label_text, "AMMO: 15/30",
		"Ammo label should show 'AMMO: current/reserve'")


func test_building_ammo_label_update_empty_magazine() -> void:
	## When magazine is empty, counter should show 0.
	building_level.init_ammo_label()

	building_level.update_ammo_label_magazine(0, 30)

	assert_eq(building_level._ammo_label_text, "AMMO: 0/30",
		"Ammo label should show 0 in magazine when empty")


func test_building_ammo_label_update_fails_when_not_initialized() -> void:
	## If label is not initialized, update is silently skipped (null guard in real code).
	var updated := building_level.update_ammo_label_magazine(30, 60)

	assert_false(updated,
		"Ammo update must be skipped when label is null (Issue #1259 root cause)")
	assert_null(building_level._ammo_label_text,
		"Ammo label text must remain null when not initialized")


func test_building_shotgun_startup_uses_shell_count_not_current_ammo() -> void:
	## Issue #1808: shotgun startup HUD must show loaded shells before the first shot.
	building_level.simulate_weapon_display_update({
		"name": "Shotgun",
		"CurrentAmmo": 0,
		"ShellsInTube": 8,
		"ReserveAmmo": 8,
	})
	assert_eq(building_level._ammo_label_text, "AMMO: 8/8",
		"Shotgun startup must use ShellsInTube for the initial HUD state")

	building_level.simulate_weapon_display_update({
		"name": "MiniUzi",
		"CurrentAmmo": 24,
		"ShellsInTube": 8,
		"ReserveAmmo": 64,
	})
	assert_eq(building_level._ammo_label_text, "AMMO: 24/64",
		"Non-shotgun startup must keep using CurrentAmmo")


func test_labyrinth_shotgun_startup_uses_shell_count_not_current_ammo() -> void:
	## Labyrinth has the same shotgun startup bug as Building (Issue #1808).
	labyrinth_level.simulate_weapon_display_update({
		"name": "Shotgun",
		"CurrentAmmo": 0,
		"ShellsInTube": 8,
		"ReserveAmmo": 8,
	})
	assert_eq(labyrinth_level._ammo_label_text, "AMMO: 8/8",
		"Labyrinth startup must use ShellsInTube for the initial HUD state")


func test_labyrinth2_shotgun_startup_uses_shell_count_not_current_ammo() -> void:
	labyrinth2_level.simulate_weapon_display_update({
		"name": "Shotgun",
		"CurrentAmmo": 0,
		"ShellsInTube": 8,
		"ReserveAmmo": 8,
	})
	assert_eq(labyrinth2_level._ammo_label_text, "AMMO: 8/8",
		"Labyrinth2 startup must use ShellsInTube for the initial HUD state")

	labyrinth2_level.simulate_weapon_display_update({
		"name": "Revolver",
		"CurrentAmmo": 5,
		"ShellsInTube": 8,
		"ReserveAmmo": 20,
	})
	assert_eq(labyrinth2_level._ammo_label_text, "AMMO: 5/20",
		"Labyrinth2 non-shotgun startup must keep using CurrentAmmo")


func test_building_hud_binds_to_current_weapon_before_stale_child() -> void:
	## Regression: child-node probing can pick a stale weapon before the equipped C# CurrentWeapon.
	var equipped_shotgun := {
		"name": "Shotgun",
		"CurrentAmmo": 0,
		"ShellsInTube": 8,
		"ReserveAmmo": 8,
	}
	var stale_revolver := {
		"name": "Revolver",
		"CurrentAmmo": 0,
		"ReserveAmmo": 20,
	}

	var chosen := building_level.choose_current_weapon(equipped_shotgun, {}, stale_revolver)
	building_level.simulate_weapon_display_update(chosen)
	assert_eq(building_level._ammo_label_text, "AMMO: 8/8",
		"Building HUD must use the equipped CurrentWeapon, not an arbitrary stale child")


func test_building_csharp_pre_equipped_shotgun_refreshes_post_config_hud() -> void:
	## Regression from owner log 2026-04-16 10:19: C# equips Shotgun as CurrentAmmo 0,
	## then Building returns early after level config. The post-config path must still
	## push ShellsInTube to the HUD before the first shot.
	building_level.simulate_csharp_pre_equipped_weapon_setup({
		"name": "Shotgun",
		"CurrentAmmo": 0,
		"ShellsInTube": 8,
		"ReserveAmmo": 8,
	})
	assert_eq(building_level._ammo_label_text, "AMMO: 8/8",
		"Building C# pre-equipped shotgun setup must refresh HUD from ShellsInTube")


func test_labyrinth2_hud_binds_to_current_weapon_before_stale_child() -> void:
	## Owner feedback showed Labyrinth Complex HUD counters regressed after stale-node selection.
	var equipped_revolver := {
		"name": "Revolver",
		"CurrentAmmo": 5,
		"ReserveAmmo": 20,
	}
	var stale_shotgun := {
		"name": "Shotgun",
		"CurrentAmmo": 0,
		"ShellsInTube": 0,
		"ReserveAmmo": 8,
	}

	var chosen := labyrinth2_level.choose_current_weapon(equipped_revolver, {}, stale_shotgun)
	labyrinth2_level.simulate_weapon_display_update(chosen)
	assert_eq(labyrinth2_level._ammo_label_text, "AMMO: 5/20",
		"Labyrinth2 HUD must use the equipped CurrentWeapon so stale shotgun nodes cannot break counters")


func test_labyrinth_csharp_pre_equipped_shotgun_refreshes_post_config_hud() -> void:
	## Labyrinth startup can auto-redirect, but it still runs the same C# pre-equipped path first.
	labyrinth_level.simulate_csharp_pre_equipped_weapon_setup({
		"name": "Shotgun",
		"CurrentAmmo": 0,
		"ShellsInTube": 8,
		"ReserveAmmo": 8,
	})
	assert_eq(labyrinth_level._ammo_label_text, "AMMO: 8/8",
		"Labyrinth C# pre-equipped shotgun setup must refresh HUD from ShellsInTube")


func test_labyrinth2_csharp_pre_equipped_shotgun_refreshes_post_config_hud() -> void:
	## Labyrinth Complex uses its own level script and needs the same post-config HUD refresh.
	labyrinth2_level.simulate_csharp_pre_equipped_weapon_setup({
		"name": "Shotgun",
		"CurrentAmmo": 0,
		"ShellsInTube": 8,
		"ReserveAmmo": 8,
	})
	assert_eq(labyrinth2_level._ammo_label_text, "AMMO: 8/8",
		"Labyrinth2 C# pre-equipped shotgun setup must refresh HUD from ShellsInTube")


func test_testtier_shotgun_startup_uses_shell_count_not_current_ammo() -> void:
	## PersistManager can redirect startup into TestTier, so that level must also display shotgun shells.
	test_tier.simulate_weapon_display_update({
		"name": "Shotgun",
		"CurrentAmmo": 0,
		"ShellsInTube": 8,
		"ReserveAmmo": 8,
	})
	assert_eq(test_tier._ammo_label_text, "AMMO: 8/8",
		"TestTier startup must use ShellsInTube for the initial HUD state")

	test_tier.simulate_weapon_display_update({
		"name": "Revolver",
		"CurrentAmmo": 5,
		"ShellsInTube": 8,
		"ReserveAmmo": 20,
	})
	assert_eq(test_tier._ammo_label_text, "AMMO: 5/20",
		"TestTier non-shotgun startup must keep using CurrentAmmo")
