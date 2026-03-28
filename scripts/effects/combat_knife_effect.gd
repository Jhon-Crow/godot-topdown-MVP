extends Node
## Combat Knife active item effect (Issue #1587).
##
## Implements an unlimited-use fan/arc melee attack for the player.
## When activated via Space key, the player performs a 120° sweeping slash.
## All enemies within the arc and within KNIFE_RANGE pixels receive KNIFE_DAMAGE damage.
##
## Attack phases (adapted from MacheteComponent, Issue #595):
##   IDLE → WINDUP (0.1s) → STRIKE (0.12s) → RECOVERY (0.18s)
## Damage is applied once at the midpoint of the STRIKE phase.
## No charges, no cooldown — the player can activate as fast as the animation allows.

## Attack animation phases.
enum AttackPhase {
	IDLE,     ## No attack in progress.
	WINDUP,   ## Quick pull-back (0.1s).
	STRIKE,   ## Fast forward sweep (0.12s) — damage mid-phase.
	RECOVERY  ## Return to idle (0.18s).
}

## Maximum range of the knife attack in pixels.
const KNIFE_RANGE: float = 70.0

## Half-angle of the fan arc in radians (60° = 120° total fan).
const KNIFE_ARC_HALF: float = PI / 3.0

## Damage dealt to each enemy hit.
const KNIFE_DAMAGE: float = 7.0

## Duration of the windup phase in seconds.
const WINDUP_DURATION: float = 0.10

## Duration of the strike phase in seconds.
const STRIKE_DURATION: float = 0.12

## Duration of the recovery phase in seconds.
const RECOVERY_DURATION: float = 0.18

## Knife rotation during windup (radians, backward pull).
const WINDUP_ANGLE: float = -PI / 2.5

## Knife rotation at end of strike (radians, forward swing).
const STRIKE_END_ANGLE: float = PI / 2.5

## Emitted when the knife strikes (at the damage moment).
signal knife_struck

## Current attack phase.
var _phase: AttackPhase = AttackPhase.IDLE

## Timer within the current phase.
var _phase_timer: float = 0.0

## Whether damage has been applied in this attack.
var _damage_applied: bool = false

## Reference to the player node.
var _player: Node2D = null

## Current visual knife rotation (radians), used by the player sprite overlay.
var _knife_rotation: float = 0.0

## Whether the knife is currently in an attack animation (attack is blocking).
var is_attacking: bool = false


## Initialize with a reference to the player node.
## @param player: The player CharacterBody2D.
func initialize(player: Node2D) -> void:
	_player = player
	FileLogger.info("[CombatKnife] Initialized — unlimited uses, 7 damage, 120° arc, %.0fpx range" % KNIFE_RANGE)


## Attempt to activate the knife attack.
## Returns true if an attack was started (i.e., not already attacking).
func activate() -> bool:
	if _phase != AttackPhase.IDLE:
		return false  # Already mid-animation; wait for recovery to finish

	_phase = AttackPhase.WINDUP
	_phase_timer = 0.0
	_damage_applied = false
	_knife_rotation = 0.0
	is_attacking = true
	FileLogger.info("[CombatKnife] Attack started — WINDUP")
	return true


## Returns the current knife rotation angle for the visual overlay (radians).
func get_knife_rotation() -> float:
	return _knife_rotation


## Called every physics frame. Advances the attack animation state machine.
func _physics_process(delta: float) -> void:
	if _phase == AttackPhase.IDLE:
		return

	_phase_timer += delta

	match _phase:
		AttackPhase.WINDUP:
			# Lerp knife backward
			var t: float = clamp(_phase_timer / WINDUP_DURATION, 0.0, 1.0)
			_knife_rotation = lerp(0.0, WINDUP_ANGLE, t)
			if _phase_timer >= WINDUP_DURATION:
				_phase = AttackPhase.STRIKE
				_phase_timer = 0.0
				FileLogger.info("[CombatKnife] Attack phase: STRIKE")

		AttackPhase.STRIKE:
			# Sweep forward — apply damage at mid-point
			var t: float = clamp(_phase_timer / STRIKE_DURATION, 0.0, 1.0)
			_knife_rotation = lerp(WINDUP_ANGLE, STRIKE_END_ANGLE, t)
			if not _damage_applied and _phase_timer >= STRIKE_DURATION * 0.5:
				_apply_damage()
				_damage_applied = true
			if _phase_timer >= STRIKE_DURATION:
				_phase = AttackPhase.RECOVERY
				_phase_timer = 0.0
				FileLogger.info("[CombatKnife] Attack phase: RECOVERY")

		AttackPhase.RECOVERY:
			# Return to idle position
			var t: float = clamp(_phase_timer / RECOVERY_DURATION, 0.0, 1.0)
			_knife_rotation = lerp(STRIKE_END_ANGLE, 0.0, t)
			if _phase_timer >= RECOVERY_DURATION:
				_phase = AttackPhase.IDLE
				_phase_timer = 0.0
				_knife_rotation = 0.0
				is_attacking = false
				FileLogger.info("[CombatKnife] Attack complete — IDLE")


## Apply damage to all enemies within the knife arc.
func _apply_damage() -> void:
	if _player == null or not is_instance_valid(_player):
		return

	# Determine facing direction from player rotation
	var player_facing: Vector2 = Vector2.RIGHT.rotated(_player.rotation)

	var hit_count: int = 0
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var dist: float = _player.global_position.distance_to(enemy.global_position)
		if dist > KNIFE_RANGE:
			continue
		# Angle check: is enemy within the fan arc?
		var to_enemy: Vector2 = (enemy.global_position - _player.global_position).normalized()
		var angle: float = player_facing.angle_to(to_enemy)
		if abs(angle) > KNIFE_ARC_HALF:
			continue
		# Apply damage
		if enemy.has_method("take_damage"):
			enemy.take_damage(KNIFE_DAMAGE)
		elif enemy.has_method("TakeDamage"):
			enemy.TakeDamage(KNIFE_DAMAGE)
		hit_count += 1
		FileLogger.info("[CombatKnife] Hit enemy '%s' for %.0f damage (dist=%.1f, angle=%.1f°)" % [
			enemy.name, KNIFE_DAMAGE, dist, rad_to_deg(abs(angle))
		])

	knife_struck.emit()
	FileLogger.info("[CombatKnife] Damage applied — %d enemies hit" % hit_count)
