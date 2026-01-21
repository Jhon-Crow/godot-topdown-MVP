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
## Normal: 0.2s - default reaction time
## Hard: 0.2s - same as normal (hard mode uses other mechanics)
func get_detection_delay() -> float:
	match current_difficulty:
		Difficulty.EASY:
			return 0.5
		Difficulty.NORMAL:
			return 0.2
		Difficulty.HARD:
			return 0.2
		_:
			return 0.2


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
