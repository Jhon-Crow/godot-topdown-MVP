class_name PacifistState
extends EnemyState
## Pacifist state - enemy refuses to fight, hides in cover.
##
## A pacifist enemy:
## - Does not shoot anyone (unless attacked)
## - Moves to cover and stays there
## - Does not leave cover voluntarily
## - If damaged, temporarily attacks the attacker (handled by enemy.gd)
##
## Pacifists are counted as "killed" for level completion purposes.
## Issue #959: Loudspeaker active item - pacifism effect


## Whether this pacifist is currently in cover.
var _in_cover: bool = false

## Target cover position to move to.
var _target_cover: Vector2 = Vector2.ZERO

## Whether a valid cover position was found.
var _has_cover_target: bool = false

## Timer for periodically rechecking cover availability.
var _cover_check_timer: float = 0.0

## Interval between cover checks (seconds).
const COVER_CHECK_INTERVAL: float = 2.0

## Distance threshold to consider "at cover".
const COVER_REACHED_DISTANCE: float = 20.0


func _init(enemy_ref: Node2D) -> void:
	super._init(enemy_ref)
	state_name = "pacifist"


func enter() -> void:
	# Stop any current movement
	enemy.velocity = Vector2.ZERO
	_in_cover = false
	_has_cover_target = false
	_cover_check_timer = 0.0

	# Try to find cover immediately
	_find_nearest_cover()

	# Log state entry
	if enemy.debug_logging:
		print("[Enemy] Entered PACIFIST state")


func exit() -> void:
	# Clean up when leaving pacifist state
	_in_cover = false
	_has_cover_target = false


func process(delta: float) -> EnemyState:
	# Pacifists don't shoot
	# (Damage response is handled in enemy.gd - temporarily exits pacifist to retaliate)

	# Update cover check timer
	_cover_check_timer += delta

	# If we have a cover target, move toward it
	if _has_cover_target and not _in_cover:
		_move_to_cover(delta)
	elif not _has_cover_target:
		# Periodically try to find cover if we don't have one
		if _cover_check_timer >= COVER_CHECK_INTERVAL:
			_cover_check_timer = 0.0
			_find_nearest_cover()

		# If still no cover, just stay in place
		enemy.velocity = Vector2.ZERO
	else:
		# In cover - stay still
		enemy.velocity = Vector2.ZERO

	return null  # Stay in pacifist state


## Find the nearest cover position and set it as target.
func _find_nearest_cover() -> void:
	if not enemy.has_method("_find_nearest_cover_position"):
		# Fallback: use current position as "cover"
		_target_cover = enemy.global_position
		_has_cover_target = true
		_in_cover = true
		return

	# Try to find cover position (uses enemy's cover detection system)
	var cover_pos: Variant = null
	if enemy.has_method("_get_nearest_cover_from_player"):
		cover_pos = enemy._get_nearest_cover_from_player()
	elif enemy.has_method("_find_cover_position"):
		cover_pos = enemy._find_cover_position()

	if cover_pos != null and cover_pos is Vector2:
		_target_cover = cover_pos
		_has_cover_target = true
		_in_cover = false

		if enemy.debug_logging:
			print("[Enemy/Pacifist] Found cover at %s" % _target_cover)
	else:
		# No cover found - stay in place
		_target_cover = enemy.global_position
		_has_cover_target = true
		_in_cover = true

		if enemy.debug_logging:
			print("[Enemy/Pacifist] No cover found, staying in place")


## Move toward the target cover position.
func _move_to_cover(_delta: float) -> void:
	var distance := enemy.global_position.distance_to(_target_cover)

	if distance < COVER_REACHED_DISTANCE:
		# Reached cover
		_in_cover = true
		enemy.velocity = Vector2.ZERO

		if enemy.debug_logging:
			print("[Enemy/Pacifist] Reached cover at %s" % _target_cover)
		return

	# Move toward cover
	var direction: Vector2 = (_target_cover - enemy.global_position).normalized()

	# Apply wall avoidance if available
	if enemy.has_method("_apply_wall_avoidance"):
		direction = enemy._apply_wall_avoidance(direction)

	# Use normal move speed (not combat speed - pacifists don't run aggressively)
	enemy.velocity = direction * enemy.move_speed


## Check if the pacifist is currently in cover.
func is_in_cover() -> bool:
	return _in_cover


## Get display name for debug visualization.
func get_display_name() -> String:
	if _in_cover:
		return "pacifist (in cover)"
	elif _has_cover_target:
		return "pacifist (seeking cover)"
	else:
		return "pacifist"
