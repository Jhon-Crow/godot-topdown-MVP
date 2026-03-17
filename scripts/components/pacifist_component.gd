class_name PacifistComponent
extends RefCounted
## Component handling pacifism state for enemies (Issue #959: Loudspeaker effect).
##
## A pacifist enemy:
## - Does not shoot anyone (unless attacked)
## - Moves to cover and stays there
## - Does not leave cover voluntarily
## - If damaged, temporarily attacks the attacker then returns to pacifist state

## Reference to the enemy this component belongs to.
var enemy: Node2D = null

## Whether this enemy is in permanent pacifist state.
var is_pacifist: bool = false

## Who damaged the pacifist (for retaliation).
var attacker: Node2D = null

## Timer for temporary retaliation mode.
var retaliation_timer: float = 0.0

## Whether this enemy is immune to pacifism (Level 6 feature).
var is_immune: bool = false

## How long pacifist retaliates after being hit.
const RETALIATION_DURATION: float = 3.0


func _init(enemy_ref: Node2D) -> void:
	enemy = enemy_ref


## Update the retaliation timer.
## Returns true if retaliation just ended (caller should transition back to pacifist state).
func update(delta: float) -> bool:
	if is_pacifist and retaliation_timer > 0.0:
		retaliation_timer -= delta
		if retaliation_timer <= 0.0:
			retaliation_timer = 0.0
			attacker = null
			return true  # Retaliation ended
	return false


## Start pacifist state. Returns false if immune.
func start_pacifism() -> bool:
	if is_immune:
		return false
	if is_pacifist:
		return false  # Already pacifist

	is_pacifist = true
	attacker = null
	retaliation_timer = 0.0
	return true


## Start retaliation after being hit.
func start_retaliation(attacker_node: Node2D) -> void:
	if is_pacifist:
		retaliation_timer = RETALIATION_DURATION
		attacker = attacker_node


## End retaliation and return to passive pacifist state.
func end_retaliation() -> void:
	retaliation_timer = 0.0
	attacker = null


## Check if currently in retaliation mode.
func is_retaliating() -> bool:
	return is_pacifist and retaliation_timer > 0.0


## Set immunity status (for Level 6 special enemy).
func set_immune(immune: bool) -> void:
	is_immune = immune


## Check if this enemy was attacked by the player (wounded/suppressed).
## Loudspeaker only affects enemies not yet engaged by the player.
func was_attacked_by_player() -> bool:
	if enemy == null:
		return false
	# Check if enemy has taken damage or been suppressed
	var hits: int = enemy.get("_hits_taken_in_encounter") if enemy.has_method("get") else 0
	var alarm: bool = enemy.get("_in_alarm_mode") if enemy.has_method("get") else false
	return hits > 0 or alarm


## Get debug info string.
func get_debug_info() -> String:
	if not is_pacifist:
		return ""
	if is_retaliating():
		return "PACIFIST (retaliating %.1fs)" % retaliation_timer
	return "PACIFIST"
