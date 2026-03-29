extends Node
## DifficultyManager - Global difficulty settings manager.
##
## Provides a centralized way to manage game difficulty settings.
## By default, the game runs in "Normal" difficulty where the new features
## from this update (distraction attack, reduced ammo) are disabled.
## In "Hard" difficulty, enemies react immediately when the player looks away,
## and the player has less ammunition.

## Difficulty levels enumeration.
enum Difficulty {
	EASY,          ## Easy difficulty - longer enemy reaction delay
	NORMAL,        ## Default difficulty - classic behavior
	HARD,          ## Hard difficulty - enables distraction attack and reduced ammo
	POWER_FANTASY, ## Power Fantasy mode - player has 10 HP, special abilities
	BLACK_METAL,   ## Black Metal mode - 25% less HP, 25% faster movement, B&W+red visual filter
	GUNSLINGER     ## Gunslinger mode - 2x less HP, 4x ammo, no laser sights, kill last-chance effect
}

## Signal emitted when difficulty changes.
signal difficulty_changed(new_difficulty: Difficulty)

## Current difficulty level. Defaults to NORMAL.
var current_difficulty: Difficulty = Difficulty.NORMAL

## Settings file path for persistence.
const SETTINGS_PATH := "user://difficulty_settings.cfg"


func _ready() -> void:
	# Load saved difficulty on startup
	_load_settings()


## Set the game difficulty.
func set_difficulty(difficulty: Difficulty) -> void:
	if current_difficulty != difficulty:
		var old_name := get_difficulty_name()
		current_difficulty = difficulty
		# FIX for Issue #886: Log difficulty changes so session logs show difficulty state
		FileLogger.info("[DifficultyManager] Difficulty changed: %s -> %s" % [
			old_name, get_difficulty_name()
		])
		difficulty_changed.emit(difficulty)
		_save_settings()


## Get the current difficulty level.
func get_difficulty() -> Difficulty:
	return current_difficulty


## Check if the game is in hard mode.
func is_hard_mode() -> bool:
	return current_difficulty == Difficulty.HARD


## Check if the game is in normal mode.
func is_normal_mode() -> bool:
	return current_difficulty == Difficulty.NORMAL


## Check if the game is in easy mode.
func is_easy_mode() -> bool:
	return current_difficulty == Difficulty.EASY


## Check if the game is in power fantasy mode.
func is_power_fantasy_mode() -> bool:
	return current_difficulty == Difficulty.POWER_FANTASY


## Check if the game is in black metal mode.
func is_black_metal_mode() -> bool:
	return current_difficulty == Difficulty.BLACK_METAL


## Check if the game is in gunslinger mode.
func is_gunslinger_mode() -> bool:
	return current_difficulty == Difficulty.GUNSLINGER


## Get the display name of the current difficulty.
func get_difficulty_name() -> String:
	match current_difficulty:
		Difficulty.EASY:
			return "Easy"
		Difficulty.NORMAL:
			return "Normal"
		Difficulty.HARD:
			return "Hard"
		Difficulty.POWER_FANTASY:
			return "Power Fantasy"
		Difficulty.BLACK_METAL:
			return "Black Metal"
		Difficulty.GUNSLINGER:
			return "Gunslinger"
		_:
			return "Unknown"


## Get the names of all available difficulty modes.
## Use this as the single source of truth whenever iterating over all difficulties.
## @return: Array of all difficulty name strings in ascending order.
func get_all_difficulty_names() -> Array[String]:
	return ["Easy", "Normal", "Hard", "Power Fantasy", "Black Metal", "Gunslinger"]


## Get the display name for a specific difficulty level.
func get_difficulty_name_for(difficulty: Difficulty) -> String:
	match difficulty:
		Difficulty.EASY:
			return "Easy"
		Difficulty.NORMAL:
			return "Normal"
		Difficulty.HARD:
			return "Hard"
		Difficulty.POWER_FANTASY:
			return "Power Fantasy"
		Difficulty.BLACK_METAL:
			return "Black Metal"
		Difficulty.GUNSLINGER:
			return "Gunslinger"
		_:
			return "Unknown"


## Get max ammo based on difficulty.
## Easy/Normal: 90 bullets (3 magazines)
## Hard: 60 bullets (2 magazines)
## Power Fantasy: 270 bullets (9 magazines - 3x normal)
## Black Metal: 90 bullets (same as normal)
## Gunslinger: 360 bullets (4x normal ammo)
func get_max_ammo() -> int:
	match current_difficulty:
		Difficulty.EASY:
			return 90
		Difficulty.NORMAL:
			return 90
		Difficulty.HARD:
			return 60
		Difficulty.POWER_FANTASY:
			return 270  # 3x normal ammo
		Difficulty.BLACK_METAL:
			return 90  # Same as normal
		Difficulty.GUNSLINGER:
			return 360  # 4x normal ammo
		_:
			return 90


## Check if distraction attack is enabled.
## Only enabled in Hard mode.
func is_distraction_attack_enabled() -> bool:
	return current_difficulty == Difficulty.HARD


## Multiplier applied to detection delay in night mode (Issue #825).
## In night mode enemies need extra time to turn on flashlight and orient before shooting.
const NIGHT_MODE_REACTION_DELAY_MULTIPLIER: float = 1.3  # 30% longer reaction time

## Get the detection delay based on difficulty.
## This is the delay before enemies start shooting after spotting the player.
## Easy: 0.5s - gives player more time to react after peeking from cover
## Normal: 0.6s - slower reaction than easy, gives player even more time
## Hard: 0.2s - quick reaction (hard mode uses other mechanics too)
## Power Fantasy: 0.8s - enemies react slower
## Black Metal: 0.3s - fast reaction (hard mode feel without distraction)
## Gunslinger: 0.4s - slightly faster than normal (tense gunfight feel)
## In night mode, all delays are multiplied by 1.3 (30% longer) (Issue #825).
func get_detection_delay() -> float:
	var base_delay: float
	match current_difficulty:
		Difficulty.EASY:
			base_delay = 0.5
		Difficulty.NORMAL:
			base_delay = 0.6
		Difficulty.HARD:
			base_delay = 0.2
		Difficulty.POWER_FANTASY:
			base_delay = 0.8  # Enemies react slower in power fantasy
		Difficulty.BLACK_METAL:
			base_delay = 0.3  # Faster reaction - intense Black Metal atmosphere
		Difficulty.GUNSLINGER:
			base_delay = 0.4  # Slightly faster than normal - tense gunfight
		_:
			base_delay = 0.6
	# Issue #825: In night mode, enemies react 30% slower (flashlight orientation delay)
	if _is_night_mode_active():
		return base_delay * NIGHT_MODE_REACTION_DELAY_MULTIPLIER
	return base_delay


## Check if night mode (realistic visibility) is currently active (Issue #825).
func _is_night_mode_active() -> bool:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings and experimental_settings.has_method("is_realistic_visibility_enabled"):
		return experimental_settings.is_realistic_visibility_enabled()
	return false


# ============================================================================
# Grenade System Configuration (Issue #363)
# ============================================================================

## Map name to grenade configuration mapping.
## Each map can specify how many grenades enemies carry and which enemies get grenades.
## Format: "map_name": {"grenade_count": int, "enemy_probability": float, "grenade_type": String}
var _map_grenade_config: Dictionary = {
	# Tutorial levels - no grenades
	"TutorialLevel": {"grenade_count": 0, "enemy_probability": 0.0, "grenade_type": "frag"},
	"Tutorial": {"grenade_count": 0, "enemy_probability": 0.0, "grenade_type": "frag"},

	# Tier 1 - Easy maps - few grenades
	"Tier1": {"grenade_count": 1, "enemy_probability": 0.2, "grenade_type": "frag"},
	"Warehouse": {"grenade_count": 1, "enemy_probability": 0.25, "grenade_type": "frag"},

	# Tier 2 - Medium maps - moderate grenades
	"Tier2": {"grenade_count": 2, "enemy_probability": 0.3, "grenade_type": "frag"},
	"Factory": {"grenade_count": 2, "enemy_probability": 0.35, "grenade_type": "frag"},

	# Tier 3 - Hard maps - more grenades
	"Tier3": {"grenade_count": 2, "enemy_probability": 0.4, "grenade_type": "frag"},
	"Bunker": {"grenade_count": 3, "enemy_probability": 0.5, "grenade_type": "frag"},

	# Boss/Advanced maps - maximum grenades
	"BossLevel": {"grenade_count": 3, "enemy_probability": 0.6, "grenade_type": "frag"},

	# City/Building level - grenadier uses own bag, regular enemies get standard grenades (Issue #604)
	"BuildingLevel": {"grenade_count": 1, "enemy_probability": 0.15, "grenade_type": "frag"}
}

## Difficulty modifiers for grenade probability.
## Higher difficulty = more enemies get grenades.
func _get_grenade_difficulty_modifier() -> float:
	match current_difficulty:
		Difficulty.EASY:
			return 0.5  # 50% of normal probability
		Difficulty.NORMAL:
			return 1.0  # Normal probability
		Difficulty.HARD:
			return 1.5  # 150% of normal probability
		Difficulty.POWER_FANTASY:
			return 0.3  # 30% of normal probability - fewer grenades
		Difficulty.BLACK_METAL:
			return 1.0  # Normal probability
		Difficulty.GUNSLINGER:
			return 0.8  # Slightly fewer grenades - gunfight focus
		_:
			return 1.0


## Get the number of grenades an enemy should have for the current map.
## @param map_name: Name of the current map/level.
## @return: Number of grenades to assign to this enemy, or 0 if none.
func get_enemy_grenade_count(map_name: String) -> int:
	var config := _get_map_config(map_name)
	var base_count: int = config.get("grenade_count", 0)
	var probability: float = config.get("enemy_probability", 0.0)

	# Apply difficulty modifier to probability
	probability *= _get_grenade_difficulty_modifier()

	# Clamp probability to 0-1 range
	probability = clampf(probability, 0.0, 1.0)

	# Roll to see if this enemy gets grenades
	if randf() < probability:
		return base_count
	else:
		return 0


## Get the grenade type for the current map.
## @param map_name: Name of the current map/level.
## @return: Grenade type string ("frag" or "flashbang").
func get_enemy_grenade_type(map_name: String) -> String:
	var config := _get_map_config(map_name)
	return config.get("grenade_type", "frag")


## Get the grenade scene path for the current map.
## @param map_name: Name of the current map/level.
## @return: Resource path to grenade scene.
func get_enemy_grenade_scene_path(map_name: String) -> String:
	var grenade_type := get_enemy_grenade_type(map_name)
	match grenade_type:
		"flashbang":
			return "res://scenes/projectiles/FlashbangGrenade.tscn"
		"defensive":
			return "res://scenes/projectiles/DefensiveGrenade.tscn"
		"frag", _:
			return "res://scenes/projectiles/FragGrenade.tscn"


## Check if enemy grenades are enabled for the current map.
## @param map_name: Name of the current map/level.
## @return: True if enemies can throw grenades on this map.
func are_enemy_grenades_enabled(map_name: String) -> bool:
	var config := _get_map_config(map_name)
	return config.get("grenade_count", 0) > 0 and config.get("enemy_probability", 0.0) > 0.0


## Get configuration for a specific map, with fallback to default.
func _get_map_config(map_name: String) -> Dictionary:
	# Try exact match first
	if map_name in _map_grenade_config:
		return _map_grenade_config[map_name]

	# Try partial match (for scenes with full paths)
	for key in _map_grenade_config.keys():
		if map_name.contains(key) or key.contains(map_name):
			return _map_grenade_config[key]

	# Default configuration - moderate grenades
	return {"grenade_count": 1, "enemy_probability": 0.2, "grenade_type": "frag"}


## Set custom grenade configuration for a map.
## Can be called from level scripts to override defaults.
func set_map_grenade_config(map_name: String, grenade_count: int, probability: float, grenade_type: String = "frag") -> void:
	_map_grenade_config[map_name] = {
		"grenade_count": grenade_count,
		"enemy_probability": probability,
		"grenade_type": grenade_type
	}
	FileLogger.info("[DifficultyManager] Set grenade config for %s: count=%d, prob=%.2f, type=%s" % [
		map_name, grenade_count, probability, grenade_type
	])


## Save settings to file.
func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("difficulty", "level", current_difficulty)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("DifficultyManager: Failed to save settings: " + str(error))


## Load settings from file.
func _load_settings() -> void:
	var config := ConfigFile.new()
	var error := config.load(SETTINGS_PATH)
	if error == OK:
		var saved_difficulty = config.get_value("difficulty", "level", Difficulty.NORMAL)
		# Validate the saved value
		if saved_difficulty is int and saved_difficulty >= 0 and saved_difficulty <= Difficulty.GUNSLINGER:
			current_difficulty = saved_difficulty as Difficulty
		else:
			current_difficulty = Difficulty.NORMAL
	else:
		# File doesn't exist or failed to load - use default
		current_difficulty = Difficulty.NORMAL
	# FIX for Issue #886: Log loaded difficulty so it is traceable in session logs.
	# Previously, difficulty state was invisible in logs, making it impossible to
	# diagnose why PowerFantasy effects fired in some sessions but not others.
	FileLogger.info("[DifficultyManager] Loaded difficulty: %s (value: %d)" % [
		get_difficulty_name(), current_difficulty
	])


# ============================================================================
# Power Fantasy Mode Configuration (Issue #492)
# ============================================================================

## Get the player's max health for current difficulty.
## Power Fantasy mode: 10 HP (instead of the usual 4 HP).
## Black Metal mode: uses same random health as normal but multiplied by 0.75 (25% less).
## Gunslinger mode: 0.5 multiplier (2x less HP than normal).
func get_player_max_health() -> int:
	if current_difficulty == Difficulty.POWER_FANTASY:
		return 10
	# Default player health for other difficulties
	return 4


## Get the HP multiplier for current difficulty.
## Black Metal mode: 0.75 (25% less HP for both player and enemies).
## Gunslinger mode: 0.5 (2x less HP for the player).
## Other modes: 1.0 (no change).
func get_hp_multiplier() -> float:
	if current_difficulty == Difficulty.BLACK_METAL:
		return 0.75
	if current_difficulty == Difficulty.GUNSLINGER:
		return 0.5  # 2x less HP
	return 1.0


## Get the player speed multiplier for current difficulty.
## Black Metal mode: 1.25 (25% faster movement).
## Other modes: 1.0 (no change).
func get_player_speed_multiplier() -> float:
	if current_difficulty == Difficulty.BLACK_METAL:
		return 1.25
	return 1.0


## Check if ricochets should damage enemies.
## In Power Fantasy mode, ricochets DO damage enemies.
func do_ricochets_damage_enemies() -> bool:
	return true


## Check if ricochets should damage the player.
## In Power Fantasy mode, ricochets do NOT damage the player.
func do_ricochets_damage_player() -> bool:
	return current_difficulty != Difficulty.POWER_FANTASY


## Get weapon recoil multiplier.
## Power Fantasy mode has reduced recoil (0.3x).
func get_recoil_multiplier() -> float:
	if current_difficulty == Difficulty.POWER_FANTASY:
		return 0.3  # 70% reduction in recoil
	return 1.0


## Get ammo multiplier for weapons.
## Power Fantasy mode has 3x more ammo.
## Gunslinger mode has 4x more ammo.
func get_ammo_multiplier() -> int:
	if current_difficulty == Difficulty.POWER_FANTASY:
		return 3
	if current_difficulty == Difficulty.GUNSLINGER:
		return 4
	return 1


## Check if blue laser sight should be enabled for all weapons.
## Only enabled in Power Fantasy mode.
func should_force_blue_laser_sight() -> bool:
	return current_difficulty == Difficulty.POWER_FANTASY


## Check if laser sights should be disabled on all weapons.
## In Gunslinger mode, no weapon has a laser sight unless the Laser Sight item is equipped.
func should_disable_laser_sight() -> bool:
	return current_difficulty == Difficulty.GUNSLINGER


## Get blue laser sight color for Power Fantasy mode.
func get_power_fantasy_laser_color() -> Color:
	return Color(0.0, 0.5, 1.0, 0.6)  # Blue with some transparency


## Check if the kill-triggered last chance effect is active.
## In Power Fantasy and Gunslinger modes, killing an enemy triggers a brief slow-motion effect.
func is_kill_last_chance_enabled() -> bool:
	return current_difficulty == Difficulty.POWER_FANTASY or current_difficulty == Difficulty.GUNSLINGER


## Check if the special last chance effect (time stop) is disabled.
## In Gunslinger mode, the special time-stop last chance effect never triggers.
func is_special_last_chance_disabled() -> bool:
	return current_difficulty == Difficulty.GUNSLINGER


## Check if enemies should have a bright red glow effect.
## In Gunslinger mode, enemies are brighter and have a small red glow.
func should_apply_gunslinger_enemy_glow() -> bool:
	return current_difficulty == Difficulty.GUNSLINGER


## Duration (ms) of the last chance effect when player kills an enemy.
## Only in Power Fantasy mode.
const POWER_FANTASY_KILL_EFFECT_DURATION_MS: float = 600.0


## Duration (ms) of the special last chance effect when grenade explodes.
## Only in Power Fantasy mode.
const POWER_FANTASY_GRENADE_EFFECT_DURATION_MS: float = 400.0
