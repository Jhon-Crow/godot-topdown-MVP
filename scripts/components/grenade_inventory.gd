class_name GrenadeInventory
extends Node
## Grenade inventory component for enemies.
##
## Tracks grenade types and counts for tactical throwing behavior.
## Grenades are only equipped based on map and difficulty settings.

## Grenade types available.
enum GrenadeType {
	NONE,       ## No grenade
	OFFENSIVE,  ## Frag/offensive grenade - high damage
	FLASHBANG,  ## Flashbang - blinds and stuns
	SMOKE       ## Smoke grenade - visual concealment (future)
}

## Number of offensive grenades carried.
@export var offensive_grenades: int = 0

## Number of flashbang grenades carried.
@export var flashbang_grenades: int = 0

## Number of smoke grenades carried.
@export var smoke_grenades: int = 0

## Maximum throw range in pixels.
@export var throw_range: float = 400.0

## Maximum throw deviation in degrees (±5° as per issue requirements).
@export var throw_accuracy_deviation: float = 5.0

## Signal emitted when grenade count changes.
signal grenade_count_changed(type: GrenadeType, count: int)

## Signal emitted when a grenade is thrown.
signal grenade_thrown(type: GrenadeType, target_position: Vector2)


## Check if the enemy has any grenades.
func has_any_grenade() -> bool:
	return offensive_grenades > 0 or flashbang_grenades > 0 or smoke_grenades > 0


## Check if the enemy has a specific grenade type.
func has_grenade(type: GrenadeType) -> bool:
	match type:
		GrenadeType.OFFENSIVE:
			return offensive_grenades > 0
		GrenadeType.FLASHBANG:
			return flashbang_grenades > 0
		GrenadeType.SMOKE:
			return smoke_grenades > 0
		GrenadeType.NONE:
			return has_any_grenade()
		_:
			return false


## Get the count of a specific grenade type.
func get_grenade_count(type: GrenadeType) -> int:
	match type:
		GrenadeType.OFFENSIVE:
			return offensive_grenades
		GrenadeType.FLASHBANG:
			return flashbang_grenades
		GrenadeType.SMOKE:
			return smoke_grenades
		_:
			return 0


## Get total grenade count.
func get_total_grenade_count() -> int:
	return offensive_grenades + flashbang_grenades + smoke_grenades


## Use one grenade of the specified type.
## Returns true if successfully used, false if none available.
func use_grenade(type: GrenadeType) -> bool:
	match type:
		GrenadeType.OFFENSIVE:
			if offensive_grenades > 0:
				offensive_grenades -= 1
				grenade_count_changed.emit(type, offensive_grenades)
				return true
		GrenadeType.FLASHBANG:
			if flashbang_grenades > 0:
				flashbang_grenades -= 1
				grenade_count_changed.emit(type, flashbang_grenades)
				return true
		GrenadeType.SMOKE:
			if smoke_grenades > 0:
				smoke_grenades -= 1
				grenade_count_changed.emit(type, smoke_grenades)
				return true
	return false


## Add grenades of the specified type.
func add_grenades(type: GrenadeType, count: int) -> void:
	match type:
		GrenadeType.OFFENSIVE:
			offensive_grenades += count
			grenade_count_changed.emit(type, offensive_grenades)
		GrenadeType.FLASHBANG:
			flashbang_grenades += count
			grenade_count_changed.emit(type, flashbang_grenades)
		GrenadeType.SMOKE:
			smoke_grenades += count
			grenade_count_changed.emit(type, smoke_grenades)


## Get the best grenade type for the current tactical situation.
## Prioritizes offensive grenades when player is in cover.
## Uses flashbangs when allies are near the target area.
func get_best_grenade_for_situation(player_in_cover: bool, allies_near_target: int) -> GrenadeType:
	# Prefer offensive when player in cover (flush them out)
	if player_in_cover and offensive_grenades > 0:
		return GrenadeType.OFFENSIVE

	# Use flashbang if allies are near target (safer for friendlies)
	if allies_near_target > 0 and flashbang_grenades > 0:
		return GrenadeType.FLASHBANG

	# Default: offensive if available, then flashbang
	if offensive_grenades > 0:
		return GrenadeType.OFFENSIVE
	if flashbang_grenades > 0:
		return GrenadeType.FLASHBANG
	if smoke_grenades > 0:
		return GrenadeType.SMOKE

	return GrenadeType.NONE


## Calculate throw position with random deviation.
## Returns the actual target position after applying ±deviation degrees.
func calculate_throw_with_deviation(throw_origin: Vector2, intended_target: Vector2) -> Vector2:
	var direction := (intended_target - throw_origin).normalized()
	var deviation_radians := deg_to_rad(randf_range(-throw_accuracy_deviation, throw_accuracy_deviation))
	var deviated_direction := direction.rotated(deviation_radians)
	var distance := throw_origin.distance_to(intended_target)
	return throw_origin + deviated_direction * distance


## Get the blast radius for a grenade type (for ally notification).
func get_blast_radius(type: GrenadeType) -> float:
	match type:
		GrenadeType.OFFENSIVE:
			return 225.0  # From frag_grenade.gd
		GrenadeType.FLASHBANG:
			return 400.0  # From flashbang_grenade.gd
		GrenadeType.SMOKE:
			return 300.0  # Estimated for smoke
		_:
			return 200.0
