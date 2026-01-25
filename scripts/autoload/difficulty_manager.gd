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
	EASY,    ## Easy difficulty - longer enemy reaction delay
	NORMAL,  ## Default difficulty - classic behavior
	HARD     ## Hard difficulty - enables distraction attack and reduced ammo
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
		current_difficulty = difficulty
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


## Get the display name of the current difficulty.
func get_difficulty_name() -> String:
	match current_difficulty:
		Difficulty.EASY:
			return "Easy"
		Difficulty.NORMAL:
			return "Normal"
		Difficulty.HARD:
			return "Hard"
		_:
			return "Unknown"


## Get the display name for a specific difficulty level.
func get_difficulty_name_for(difficulty: Difficulty) -> String:
	match difficulty:
		Difficulty.EASY:
			return "Easy"
		Difficulty.NORMAL:
			return "Normal"
		Difficulty.HARD:
			return "Hard"
		_:
			return "Unknown"


## Get max ammo based on difficulty.
## Easy/Normal: 90 bullets (3 magazines)
## Hard: 60 bullets (2 magazines)
func get_max_ammo() -> int:
	match current_difficulty:
		Difficulty.EASY:
			return 90
		Difficulty.NORMAL:
			return 90
		Difficulty.HARD:
			return 60
		_:
			return 90


## Check if distraction attack is enabled.
## Only enabled in Hard mode.
func is_distraction_attack_enabled() -> bool:
	return current_difficulty == Difficulty.HARD


## Get the detection delay based on difficulty.
## This is the delay before enemies start shooting after spotting the player.
## Easy: 0.5s - gives player more time to react after peeking from cover
## Normal: 0.6s - slower reaction than easy, gives player even more time
## Hard: 0.2s - quick reaction (hard mode uses other mechanics too)
func get_detection_delay() -> float:
	match current_difficulty:
		Difficulty.EASY:
			return 0.5
		Difficulty.NORMAL:
			return 0.6
		Difficulty.HARD:
			return 0.2
		_:
			return 0.6


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
	"BossLevel": {"grenade_count": 3, "enemy_probability": 0.6, "grenade_type": "frag"}
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
		if saved_difficulty is int and saved_difficulty >= 0 and saved_difficulty <= Difficulty.HARD:
			current_difficulty = saved_difficulty as Difficulty
		else:
			current_difficulty = Difficulty.NORMAL
	else:
		# File doesn't exist or failed to load - use default
		current_difficulty = Difficulty.NORMAL
