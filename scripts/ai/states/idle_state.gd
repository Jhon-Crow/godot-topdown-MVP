class_name IdleState
extends EnemyState
## Idle state - enemy patrols or guards depending on behavior mode.
##
## In PATROL mode: Moves between patrol points.
## In GUARD mode: Stands in place watching for the player.


func _init(enemy_ref: Node2D) -> void:
	super._init(enemy_ref)
	state_name = "idle"


func enter() -> void:
	# Reset alarm mode when returning to idle
	if enemy.has_method("_reset_alarm_mode"):
		enemy._reset_alarm_mode()

	# Reset encounter hits
	if enemy.has_method("_reset_encounter_hits"):
		enemy._reset_encounter_hits()


func process(delta: float) -> EnemyState:
	# Check for transitions to other states
	if enemy._can_see_player:
		return null  # Signal to transition to combat

	if enemy._under_fire and enemy._threat_reaction_delay_elapsed:
		return null  # Signal to transition to seeking cover or suppressed

	# Process patrol or guard behavior
	if enemy.behavior_mode == enemy.BehaviorMode.PATROL:
		_process_patrol(delta)
	else:
		_process_guard(delta)

	return null


## Process patrol movement between points.
func _process_patrol(delta: float) -> void:
	if enemy._patrol_points.is_empty():
		return

	# If waiting at a patrol point
	if enemy._is_waiting_at_patrol_point:
		enemy._patrol_wait_timer += delta
		if enemy._patrol_wait_timer >= enemy.patrol_wait_time:
			enemy._is_waiting_at_patrol_point = false
			enemy._patrol_wait_timer = 0.0
			# Move to next patrol point
			enemy._current_patrol_index = (enemy._current_patrol_index + 1) % enemy._patrol_points.size()
		return

	# Move toward current patrol point
	var target := enemy._patrol_points[enemy._current_patrol_index]
	var direction := (target - enemy.global_position).normalized()

	# Check if reached patrol point
	if enemy.global_position.distance_to(target) < 10.0:
		enemy._is_waiting_at_patrol_point = true
		enemy._patrol_wait_timer = 0.0
		enemy.velocity = Vector2.ZERO
		return

	# Apply wall avoidance and movement
	if enemy.has_method("_apply_wall_avoidance"):
		direction = enemy._apply_wall_avoidance(direction)

	enemy.velocity = direction * enemy.move_speed


## Process guard behavior (stay in place, watch for threats).
func _process_guard(_delta: float) -> void:
	enemy.velocity = Vector2.ZERO
