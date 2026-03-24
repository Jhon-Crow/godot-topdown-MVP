class_name LoudspeakerProgress
extends Node
## Tracks Loudspeaker active item progress through 7 development levels.
##
## Level progression is based on completing levels while using the loudspeaker:
## - Level 1: Starting level (2 charges, 2% effect chance after first use, 50% hostility)
## - Level 2: After completing 1 level with loudspeaker (3 charges, 5% chance)
## - Level 3: After completing 2 levels (6 charges, 7% chance, 40% hostility)
## - Level 4: After completing 3 levels (unlimited charges, 2s cooldown, 7% chance, 20% hostility)
## - Level 5: After completing 4 levels (unlimited, 0.5s cooldown, 11% chance, 0% hostility, pacifism spreads)
## - Level 6: After completing any level without kills (50% enemies start pacifist, 90% chance, 1 immune enemy)
## - Level 7: After killing the immune enemy (all enemies pacifist, victory message)
##
## Issue #959: Loudspeaker active item implementation

## Signal emitted when loudspeaker level changes.
signal level_changed(new_level: int)

## Signal emitted when first use in a level is triggered.
signal first_use_triggered

## Current loudspeaker development level (1-7).
var current_level: int = 1

## Number of levels completed with loudspeaker equipped.
var levels_completed_with_loudspeaker: int = 0

## Whether the player has completed a level without any kills.
var has_completed_pacifist_level: bool = false

## Whether the player has killed the immune enemy (level 6 requirement for level 7).
var has_killed_immune_enemy: bool = false

## Whether the loudspeaker has been used this level (for first-use 100% effect).
var used_this_level: bool = false

## Whether all charges were spent this level (required for level progression).
var all_charges_used_this_level: bool = false

## Number of charges remaining for current battle.
var charges_remaining: int = 2

## Cooldown timer for levels 4+ (seconds remaining).
var cooldown_timer: float = 0.0


## Get the maximum charges for current level.
func get_max_charges() -> int:
	match current_level:
		1:
			return 2
		2:
			return 3
		3:
			return 6
		_:
			return -1  # Unlimited


## Get the cooldown duration for current level (0 means no cooldown, uses charges).
func get_cooldown_duration() -> float:
	match current_level:
		4:
			return 2.0
		5, 6, 7:
			return 0.5
		_:
			return 0.0  # No cooldown, uses charges instead


## Get the effect chance for current level (0.0 - 1.0).
## Note: First use at level 1 is always 100% (handled separately).
func get_effect_chance() -> float:
	match current_level:
		1:
			return 0.02  # 2%
		2:
			return 0.05  # 5%
		3, 4:
			return 0.07  # 7%
		5:
			return 0.11  # 11%
		6, 7:
			return 0.90  # 90%
		_:
			return 0.02


## Get the hostility chance toward pacifists for current level (0.0 - 1.0).
func get_hostility_chance() -> float:
	match current_level:
		1, 2:
			return 0.50  # 50%
		3:
			return 0.40  # 40%
		4:
			return 0.20  # 20%
		_:
			return 0.0   # 0% at level 5+


## Whether pacifism spreads to enemies who see pacifists (level 5+ feature).
func can_pacifism_spread() -> bool:
	return current_level >= 5


## Whether 50% of enemies start as pacifists (level 6 feature).
func should_start_with_pacifists() -> bool:
	return current_level >= 6


## Whether all enemies start as pacifists (level 7 victory state).
func is_victory_state() -> bool:
	return current_level >= 7


## Whether there's an immune enemy on the map (level 6 feature).
func has_immune_enemy() -> bool:
	return current_level == 6


## Check if loudspeaker can be activated (has charges or cooldown ready).
func can_activate() -> bool:
	if cooldown_timer > 0.0:
		return false

	var max_charges := get_max_charges()
	if max_charges == -1:  # Unlimited
		return true

	return charges_remaining > 0


## Use the loudspeaker, consuming a charge or starting cooldown.
## Returns true if activation was successful.
func use() -> bool:
	if not can_activate():
		return false

	var is_first_use := not used_this_level
	used_this_level = true

	var max_charges := get_max_charges()
	if max_charges == -1:  # Unlimited, use cooldown
		cooldown_timer = get_cooldown_duration()
		# Unlimited charges count as "all used" once any charge is spent
		all_charges_used_this_level = true
	else:
		charges_remaining -= 1
		# Track when all charges have been exhausted this level
		if charges_remaining <= 0:
			all_charges_used_this_level = true

	if is_first_use:
		first_use_triggered.emit()

	return true


## Update cooldown timer. Call this every frame with delta time.
func update(delta: float) -> void:
	if cooldown_timer > 0.0:
		cooldown_timer = maxf(0.0, cooldown_timer - delta)


## Reset charges and per-run state on player respawn (death/restart within same level).
## Does NOT reset used_this_level — the first-use 100% only fires once per level map visit.
func reset_for_respawn() -> void:
	var max_charges := get_max_charges()
	charges_remaining = max_charges if max_charges != -1 else 0
	cooldown_timer = 0.0
	all_charges_used_this_level = false


## Reset the first-use flag when transitioning to a genuinely new level map.
## Call this after on_level_completed() so the next map starts fresh.
func reset_for_new_level() -> void:
	reset_for_respawn()
	used_this_level = false


## Called when a level is completed with loudspeaker equipped.
## @param had_kills: Whether the player killed any enemies (not pacifists).
## Note: Level progression only advances if all charges were spent this level (per issue spec).
func on_level_completed(had_kills: bool) -> void:
	# Level only counts toward progression if all charges were used in this run
	if all_charges_used_this_level:
		levels_completed_with_loudspeaker += 1

		if not had_kills:
			has_completed_pacifist_level = true

		_update_level()


## Called when the immune enemy is killed (level 6 special enemy).
func on_immune_enemy_killed() -> void:
	has_killed_immune_enemy = true
	_update_level()


## Update the current level based on progress.
func _update_level() -> void:
	var old_level := current_level

	# Level 7: After killing immune enemy
	if has_killed_immune_enemy:
		current_level = 7
	# Level 6: After completing any level without kills
	elif has_completed_pacifist_level:
		current_level = 6
	# Levels 2-5: Based on number of levels completed
	else:
		current_level = mini(5, 1 + levels_completed_with_loudspeaker)

	if current_level != old_level:
		level_changed.emit(current_level)


## Get a dictionary representation for saving.
func to_dict() -> Dictionary:
	return {
		"current_level": current_level,
		"levels_completed": levels_completed_with_loudspeaker,
		"pacifist_level_completed": has_completed_pacifist_level,
		"immune_enemy_killed": has_killed_immune_enemy
	}


## Load from a dictionary (for persistence).
func from_dict(data: Dictionary) -> void:
	current_level = data.get("current_level", 1)
	levels_completed_with_loudspeaker = data.get("levels_completed", 0)
	has_completed_pacifist_level = data.get("pacifist_level_completed", false)
	has_killed_immune_enemy = data.get("immune_enemy_killed", false)

	# Ensure level is recalculated based on loaded data
	_update_level()
	reset_for_new_level()


## Get debug info string.
func get_debug_info() -> String:
	var max_charges := get_max_charges()
	var charges_str := str(charges_remaining) + "/" + str(max_charges) if max_charges != -1 else "unlimited"
	return "Loudspeaker Lv%d | Charges: %s | Effect: %.0f%% | Hostility: %.0f%%" % [
		current_level,
		charges_str,
		get_effect_chance() * 100,
		get_hostility_chance() * 100
	]
