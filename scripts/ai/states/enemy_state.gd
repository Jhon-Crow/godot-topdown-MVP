class_name EnemyState
extends RefCounted
## Base class for enemy AI states.
##
## States encapsulate behavior for specific enemy situations like idle,
## combat, seeking cover, etc. Each state handles its own logic and
## transitions to other states.

## Reference to the enemy this state belongs to.
var enemy: Node2D = null

## Name of this state for debugging.
var state_name: String = "base"


func _init(enemy_ref: Node2D) -> void:
	enemy = enemy_ref


## Called when entering this state.
func enter() -> void:
	pass


## Called when exiting this state.
func exit() -> void:
	pass


## Called every physics frame while in this state.
## Returns the next state to transition to, or null to stay in current state.
func process(delta: float) -> EnemyState:
	return null


## Get the display name for debug purposes.
func get_display_name() -> String:
	return state_name
