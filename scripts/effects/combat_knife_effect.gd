extends Node2D
## Combat Knife active item effect (Issue #1587).
##
## Implements an unlimited-use fan/arc melee attack for the player.
## When activated via Space key, the player performs a 120° sweeping slash.
## All enemies within the arc and within KNIFE_RANGE pixels receive KNIFE_DAMAGE damage.
##
## Visual: a sweeping fan arc drawn via _draw(), like a blade sweep animation.
## The arc sweeps from WINDUP_ANGLE to STRIKE_END_ANGLE during the STRIKE phase
## and fades out during RECOVERY.
##
## Attack phases (adapted from MacheteComponent, Issue #595):
##   IDLE → WINDUP (0.1s) → STRIKE (0.12s) → RECOVERY (0.18s)
## Damage is applied once at the midpoint of the STRIKE phase.
## No charges, no cooldown — the player can activate as fast as the animation allows.

## Attack animation phases.
enum AttackPhase {
	IDLE,     ## No attack in progress.
	WINDUP,   ## Quick pull-back (0.1s).
	STRIKE,   ## Fast forward sweep (0.12s) — damage mid-phase; arc visible.
	RECOVERY  ## Return to idle (0.18s) — arc fades out.
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

## Number of polygon segments for the arc shape.
const ARC_SEGMENTS: int = 20

## Arc fill color (orange-yellow slash, semi-transparent).
const ARC_COLOR: Color = Color(1.0, 0.75, 0.1, 0.55)

## Arc leading edge color (bright white-yellow highlight).
const ARC_EDGE_COLOR: Color = Color(1.0, 0.95, 0.6, 0.85)

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

## Current visual arc sweep angle (leading edge angle relative to player facing, radians).
## During STRIKE: sweeps from WINDUP_ANGLE to STRIKE_END_ANGLE.
## During RECOVERY: held at STRIKE_END_ANGLE (fading).
var _arc_sweep_angle: float = 0.0

## Arc alpha for fade-out during RECOVERY (1.0 = full, 0.0 = gone).
var _arc_alpha: float = 0.0

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
	_arc_sweep_angle = WINDUP_ANGLE
	_arc_alpha = 0.0
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
			# Lerp knife backward — no arc visible yet
			var t: float = clamp(_phase_timer / WINDUP_DURATION, 0.0, 1.0)
			_knife_rotation = lerp(0.0, WINDUP_ANGLE, t)
			_arc_sweep_angle = WINDUP_ANGLE
			_arc_alpha = 0.0
			if _phase_timer >= WINDUP_DURATION:
				_phase = AttackPhase.STRIKE
				_phase_timer = 0.0
				FileLogger.info("[CombatKnife] Attack phase: STRIKE")

		AttackPhase.STRIKE:
			# Sweep forward — arc sweeps from WINDUP_ANGLE to STRIKE_END_ANGLE
			var t: float = clamp(_phase_timer / STRIKE_DURATION, 0.0, 1.0)
			_knife_rotation = lerp(WINDUP_ANGLE, STRIKE_END_ANGLE, t)
			_arc_sweep_angle = _knife_rotation
			_arc_alpha = 1.0
			if not _damage_applied and _phase_timer >= STRIKE_DURATION * 0.5:
				_apply_damage()
				_damage_applied = true
			if _phase_timer >= STRIKE_DURATION:
				_phase = AttackPhase.RECOVERY
				_phase_timer = 0.0
				_arc_sweep_angle = STRIKE_END_ANGLE
				FileLogger.info("[CombatKnife] Attack phase: RECOVERY")

		AttackPhase.RECOVERY:
			# Arc fades out as arm returns to idle
			var t: float = clamp(_phase_timer / RECOVERY_DURATION, 0.0, 1.0)
			_knife_rotation = lerp(STRIKE_END_ANGLE, 0.0, t)
			_arc_alpha = 1.0 - t
			if _phase_timer >= RECOVERY_DURATION:
				_phase = AttackPhase.IDLE
				_phase_timer = 0.0
				_knife_rotation = 0.0
				_arc_sweep_angle = 0.0
				_arc_alpha = 0.0
				is_attacking = false
				FileLogger.info("[CombatKnife] Attack complete — IDLE")

	queue_redraw()


## Draw the fan arc sweep visual centered on the player facing direction.
func _draw() -> void:
	if _arc_alpha <= 0.001 or _player == null or not is_instance_valid(_player):
		return

	# Arc spans from WINDUP_ANGLE to _arc_sweep_angle (current sweep progress),
	# offset by the player's facing direction.
	var player_facing_angle: float = _player.rotation
	var arc_start: float = player_facing_angle + WINDUP_ANGLE
	var arc_end: float = player_facing_angle + _arc_sweep_angle

	# Ensure arc_start < arc_end; if they are equal or reversed, skip drawing
	if arc_end <= arc_start + 0.01:
		return

	var arc_span: float = arc_end - arc_start
	var step: float = arc_span / ARC_SEGMENTS

	# Build a filled sector polygon: origin → outer arc → back to origin
	var points: PackedVector2Array = PackedVector2Array()
	var colors: PackedColorArray = PackedColorArray()

	# Center point (player position in local coords = Vector2.ZERO because we are a child)
	points.append(Vector2.ZERO)
	var center_col: Color = Color(ARC_COLOR.r, ARC_COLOR.g, ARC_COLOR.b, ARC_COLOR.a * _arc_alpha * 0.4)
	colors.append(center_col)

	# Outer arc points
	for i in range(ARC_SEGMENTS + 1):
		var a: float = arc_start + step * i
		points.append(Vector2(cos(a), sin(a)) * KNIFE_RANGE)
		var edge_factor: float = float(i) / float(ARC_SEGMENTS)
		# Fade edges of arc for swept look
		var edge_alpha: float = _arc_alpha * (0.5 + 0.5 * sin(edge_factor * PI))
		colors.append(Color(ARC_COLOR.r, ARC_COLOR.g, ARC_COLOR.b, ARC_COLOR.a * edge_alpha))

	draw_polygon(points, colors)

	# Draw a bright leading edge line at the current sweep front
	var leading_angle: float = player_facing_angle + _arc_sweep_angle
	var edge_start: Vector2 = Vector2.ZERO
	var edge_end: Vector2 = Vector2(cos(leading_angle), sin(leading_angle)) * KNIFE_RANGE
	var edge_col: Color = Color(ARC_EDGE_COLOR.r, ARC_EDGE_COLOR.g, ARC_EDGE_COLOR.b, ARC_EDGE_COLOR.a * _arc_alpha)
	draw_line(edge_start, edge_end, edge_col, 2.0, true)


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
