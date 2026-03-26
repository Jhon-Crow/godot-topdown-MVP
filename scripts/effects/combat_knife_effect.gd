extends Node
## Combat Knife active item effect (Issue #1587).
##
## When activated via Space key, the player performs a melee fan/sweep attack
## in the direction the weapon is facing (toward the mouse cursor).
## Any enemy caught in the arc takes 7 damage.
## Unlimited uses — no charges, no cooldown.

## Damage dealt per strike.
const KNIFE_DAMAGE: int = 7

## Attack range in pixels (how far the arc reaches).
const KNIFE_RANGE: float = 80.0

## Half-angle of the attack arc in degrees (full arc = 2 * this).
const KNIFE_ARC_HALF_ANGLE_DEG: float = 60.0

## Animation phases for the knife swing.
enum SwingPhase {
	IDLE,      ## No attack active
	WINDUP,    ## Arm pulls back
	PAUSE,     ## Brief anticipation hold
	STRIKE,    ## Fast forward swing (damage applied mid-strike)
	RECOVERY   ## Return to neutral
}

## Duration of each phase in seconds.
const WINDUP_DURATION: float = 0.12
const PAUSE_DURATION: float = 0.06
const STRIKE_DURATION: float = 0.10
const RECOVERY_DURATION: float = 0.18

## Reference to the player node.
var _player: CharacterBody2D = null

## Current swing phase.
var _phase: SwingPhase = SwingPhase.IDLE

## Timer within the current phase.
var _phase_timer: float = 0.0

## Direction of the current strike (unit vector, toward mouse at activation).
var _strike_direction: Vector2 = Vector2.RIGHT

## Whether damage was already applied in this strike.
var _damage_applied: bool = false

## Signal emitted when the knife swing starts.
signal swing_started

## Signal emitted when the knife swing ends.
signal swing_ended


## Initialize with a reference to the player node.
func initialize(player: CharacterBody2D) -> void:
	_player = player
	FileLogger.info("[CombatKnife] Initialized — unlimited uses, %.0f range, %.0f° arc, %d damage" % [
		KNIFE_RANGE, KNIFE_ARC_HALF_ANGLE_DEG * 2.0, KNIFE_DAMAGE
	])


## Attempt to activate the knife attack.
## @param direction: Direction to strike in (toward mouse cursor, normalized).
## Returns true if the attack was started.
func activate(direction: Vector2) -> bool:
	if _phase != SwingPhase.IDLE:
		return false  # Already mid-swing

	if direction == Vector2.ZERO:
		if _player != null:
			direction = (_player.get_global_mouse_position() - _player.global_position).normalized()
		else:
			return false

	_strike_direction = direction.normalized()
	_damage_applied = false
	_set_phase(SwingPhase.WINDUP)

	FileLogger.info("[CombatKnife] Attack activated, dir=(%.2f,%.2f)" % [_strike_direction.x, _strike_direction.y])
	swing_started.emit()
	return true


## Check if the knife attack animation is currently playing.
func is_attacking() -> bool:
	return _phase != SwingPhase.IDLE


func _physics_process(delta: float) -> void:
	if _phase == SwingPhase.IDLE:
		return

	_phase_timer += delta

	match _phase:
		SwingPhase.WINDUP:
			if _phase_timer >= WINDUP_DURATION:
				_set_phase(SwingPhase.PAUSE)

		SwingPhase.PAUSE:
			if _phase_timer >= PAUSE_DURATION:
				_set_phase(SwingPhase.STRIKE)

		SwingPhase.STRIKE:
			# Apply damage at the midpoint of the strike
			if _phase_timer >= STRIKE_DURATION * 0.5 and not _damage_applied:
				_apply_damage()
			if _phase_timer >= STRIKE_DURATION:
				_set_phase(SwingPhase.RECOVERY)

		SwingPhase.RECOVERY:
			if _phase_timer >= RECOVERY_DURATION:
				_set_phase(SwingPhase.IDLE)
				swing_ended.emit()


## Set the current phase and reset the phase timer.
func _set_phase(phase: SwingPhase) -> void:
	_phase = phase
	_phase_timer = 0.0
	FileLogger.info("[CombatKnife] Phase: %s" % SwingPhase.keys()[phase])


## Apply damage to all enemies within the attack arc.
func _apply_damage() -> void:
	_damage_applied = true
	if _player == null or not is_instance_valid(_player):
		return

	var origin: Vector2 = _player.global_position
	var arc_cos: float = cos(deg_to_rad(KNIFE_ARC_HALF_ANGLE_DEG))

	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	var hit_count: int = 0

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		var to_enemy: Vector2 = enemy.global_position - origin
		var dist: float = to_enemy.length()

		# Distance check
		if dist > KNIFE_RANGE:
			continue

		# Arc check (dot product with strike direction)
		if dist > 0.0 and to_enemy.normalized().dot(_strike_direction) < arc_cos:
			continue

		# Wall-block check: skip enemies behind walls
		if not _is_path_clear(origin, enemy.global_position):
			continue

		# Deal damage
		if enemy.has_method("take_damage"):
			enemy.take_damage(KNIFE_DAMAGE)
		elif enemy.has_method("TakeDamage"):
			enemy.TakeDamage(KNIFE_DAMAGE)
		elif enemy.has_method("on_hit_with_bullet_info"):
			enemy.on_hit_with_bullet_info(_strike_direction, null, false, false, float(KNIFE_DAMAGE), true)

		hit_count += 1

	FileLogger.info("[CombatKnife] Strike hit %d enemy(ies) for %d damage each" % [hit_count, KNIFE_DAMAGE])

	# Play a melee hit sound if any enemy was struck
	if hit_count > 0:
		var audio: Node = get_node_or_null("/root/AudioManager")
		if audio and audio.has_method("play_hit_non_lethal"):
			audio.play_hit_non_lethal(origin)

	# Emit sound propagation (melee swing is audible but quiet)
	var sp: Node = get_node_or_null("/root/SoundPropagation")
	if sp and sp.has_method("emit_sound"):
		sp.emit_sound(0, origin, 1, _player, 150.0)


## Check if the line between two positions is clear of walls.
## Returns true when no wall obstacle is between origin and target.
func _is_path_clear(from_pos: Vector2, to_pos: Vector2) -> bool:
	if _player == null:
		return true
	var world_2d := _player.get_world_2d()
	if world_2d == null:
		return true
	var space_state := world_2d.direct_space_state
	if space_state == null:
		return true
	var query := PhysicsRayQueryParameters2D.new()
	query.from = from_pos
	query.to = to_pos
	query.collision_mask = 4  # obstacles layer only
	query.exclude = [_player.get_rid()]
	var result := space_state.intersect_ray(query)
	return result.is_empty()
