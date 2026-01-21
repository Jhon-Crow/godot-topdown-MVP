class_name PursuingState
extends EnemyState
## Pursuing state - enemy moves cover-to-cover toward the player.
##
## Used when the enemy is far from the player and cannot engage from
## their current position. Moves tactically using cover positions.


func _init(enemy_ref: Node2D) -> void:
	super._init(enemy_ref)
	state_name = "pursuing"


func enter() -> void:
	enemy._pursuing_state_timer = 0.0
	enemy._pursuit_approaching = false
	enemy._pursuit_approach_timer = 0.0
	enemy._pursuit_cover_wait_timer = 0.0
	enemy._has_pursuit_cover = false

	# Find initial cover toward player
	if enemy.has_method("_find_pursuit_cover_toward_player"):
		enemy._find_pursuit_cover_toward_player()


func exit() -> void:
	enemy._pursuit_approaching = false


func process(delta: float) -> EnemyState:
	enemy._pursuing_state_timer += delta

	# If we can see the player and have been pursuing long enough, transition to combat
	if enemy._can_see_player and enemy._pursuing_state_timer >= enemy.PURSUING_MIN_DURATION_BEFORE_COMBAT:
		return null  # Signal transition to combat

	# If under fire, transition to retreating or seeking cover
	if enemy._under_fire and enemy._threat_reaction_delay_elapsed:
		return null  # Signal transition to retreating/seeking cover

	# Process pursuit logic
	if enemy._pursuit_approaching:
		_process_approach_phase(delta)
	elif enemy._has_pursuit_cover:
		_process_cover_movement(delta)
	else:
		_find_next_cover()

	return null


## Process the approach phase (no cover available, moving directly toward player).
func _process_approach_phase(delta: float) -> void:
	enemy._pursuit_approach_timer += delta

	if enemy._pursuit_approach_timer >= enemy.PURSUIT_APPROACH_MAX_TIME:
		# Timeout - try to find cover or transition to combat
		enemy._pursuit_approaching = false
		return

	# Move toward player
	if enemy._player:
		var direction := (enemy._player.global_position - enemy.global_position).normalized()

		# Apply wall avoidance
		if enemy.has_method("_apply_wall_avoidance"):
			direction = enemy._apply_wall_avoidance(direction)

		enemy.velocity = direction * enemy.combat_move_speed

		# Aim at player while moving
		if enemy.has_method("_aim_at_player"):
			enemy._aim_at_player()


## Process movement toward cover position.
func _process_cover_movement(delta: float) -> void:
	var distance_to_cover := enemy.global_position.distance_to(enemy._pursuit_next_cover)

	if distance_to_cover < 20.0:
		# Reached cover - wait briefly then find next
		enemy._pursuit_cover_wait_timer += delta
		enemy.velocity = Vector2.ZERO

		if enemy._pursuit_cover_wait_timer >= enemy.PURSUIT_COVER_WAIT_DURATION:
			enemy._pursuit_cover_wait_timer = 0.0
			enemy._has_pursuit_cover = false
			_find_next_cover()
	else:
		# Move toward cover
		var direction := (enemy._pursuit_next_cover - enemy.global_position).normalized()

		# Apply wall avoidance
		if enemy.has_method("_apply_wall_avoidance"):
			direction = enemy._apply_wall_avoidance(direction)

		enemy.velocity = direction * enemy.combat_move_speed

		# Aim at player while moving
		if enemy.has_method("_aim_at_player"):
			enemy._aim_at_player()


## Find the next cover position toward the player.
func _find_next_cover() -> void:
	if enemy.has_method("_find_pursuit_cover_toward_player"):
		enemy._find_pursuit_cover_toward_player()

	# If no cover found, enter approach phase
	if not enemy._has_pursuit_cover:
		enemy._pursuit_approaching = true
		enemy._pursuit_approach_timer = 0.0
