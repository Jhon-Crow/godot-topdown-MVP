extends Node2D
## Combat Knife active item effect (Issue #1587).
##
## Implements an unlimited-use fan/arc melee attack for the player.
## When activated via Space key, the player performs a 120° sweeping slash.
## All enemies within the arc and within KNIFE_RANGE pixels receive KNIFE_DAMAGE damage.
##
## Visual: a sweeping blade arc drawn via _draw(), centered on the player's AIM direction.
## The attack animates like a real knife swing:
##   WINDUP  — backswing: a thin line is held at the START edge of the arc (anticipation)
##   STRIKE  — fast sweep: the arc sweeps from start edge to end edge in one quick motion
##   RECOVERY — arc fades out held at the end position
##
## Attack phases:
##   IDLE → WINDUP (0.2s, backswing held) → STRIKE (0.08s, fast sweep) → RECOVERY (0.15s, fade)
## Damage is applied once at the START of the STRIKE phase.
## No charges, no cooldown — the player can activate as fast as the animation allows.

## Attack animation phases.
enum AttackPhase {
	IDLE,     ## No attack in progress.
	WINDUP,   ## Backswing held at start edge (0.2s) — anticipation.
	STRIKE,   ## Fast sweep from start edge to end edge (0.08s) — damage applied.
	RECOVERY  ## Arc fades out at end position (0.15s).
}

## Maximum range of the knife attack in pixels.
const KNIFE_RANGE: float = 70.0

## Half-angle of the fan arc in radians (60° = 120° total fan).
const KNIFE_ARC_HALF: float = PI / 3.0

## Damage dealt to each enemy hit.
const KNIFE_DAMAGE: float = 7.0

## Duration of the windup phase in seconds (backswing held).
const WINDUP_DURATION: float = 0.2

## Duration of the strike phase in seconds (fast sweep).
const STRIKE_DURATION: float = 0.08

## Duration of the recovery phase in seconds (fade out).
const RECOVERY_DURATION: float = 0.15

## Number of polygon segments for the arc shape.
const ARC_SEGMENTS: int = 20

## Arc fill color (orange-yellow slash, semi-transparent).
const ARC_COLOR: Color = Color(1.0, 0.75, 0.1, 0.55)

## Arc leading edge color (bright white-yellow highlight).
const ARC_EDGE_COLOR: Color = Color(1.0, 0.95, 0.6, 0.9)

## Windup line color (dim indicator showing backswing position).
const WINDUP_COLOR: Color = Color(1.0, 0.85, 0.3, 0.5)

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

## Reference to the player model node (used for aim direction).
## This rotates to face the mouse cursor.
var _player_model: Node2D = null

## Sweep progress during STRIKE (0.0 = at start edge, 1.0 = full arc reached end edge).
## The arc grows from the backswing side (aim - KNIFE_ARC_HALF) to the follow-through side (aim + KNIFE_ARC_HALF).
var _sweep_progress: float = 0.0

## Arc alpha for fade-out during RECOVERY (1.0 = full, 0.0 = gone).
var _arc_alpha: float = 0.0

## Whether the knife is currently in an attack animation (attack is blocking).
var is_attacking: bool = false


## Initialize with a reference to the player node and player model node.
## @param player: The player CharacterBody2D.
## @param player_model: The PlayerModel Node2D that rotates toward the mouse cursor.
func initialize(player: Node2D, player_model: Node2D = null) -> void:
	_player = player
	_player_model = player_model
	FileLogger.info("[CombatKnife] Initialized — unlimited uses, 7 damage, 120° arc, %.0fpx range" % KNIFE_RANGE)


## Attempt to activate the knife attack.
## Returns true if an attack was started (i.e., not already attacking).
func activate() -> bool:
	if _phase != AttackPhase.IDLE:
		return false  # Already mid-animation; wait for recovery to finish

	_phase = AttackPhase.WINDUP
	_phase_timer = 0.0
	_damage_applied = false
	_sweep_progress = 0.0
	_arc_alpha = 0.0
	is_attacking = true
	FileLogger.info("[CombatKnife] Attack started — WINDUP (backswing held)")
	return true


## Called every physics frame. Advances the attack animation state machine.
func _physics_process(delta: float) -> void:
	if _phase == AttackPhase.IDLE:
		return

	_phase_timer += delta

	match _phase:
		AttackPhase.WINDUP:
			# Backswing held — show a thin line at start edge (anticipation pose)
			_sweep_progress = 0.0
			_arc_alpha = 1.0
			if _phase_timer >= WINDUP_DURATION:
				_phase = AttackPhase.STRIKE
				_phase_timer = 0.0
				# Apply damage immediately at start of strike
				if not _damage_applied:
					_apply_damage()
					_damage_applied = true
				FileLogger.info("[CombatKnife] Attack phase: STRIKE")

		AttackPhase.STRIKE:
			# Fast sweep — arc sweeps from start edge to full 120° (end edge)
			var t: float = clamp(_phase_timer / STRIKE_DURATION, 0.0, 1.0)
			_sweep_progress = t
			_arc_alpha = 1.0
			if _phase_timer >= STRIKE_DURATION:
				_phase = AttackPhase.RECOVERY
				_phase_timer = 0.0
				_sweep_progress = 1.0
				FileLogger.info("[CombatKnife] Attack phase: RECOVERY")

		AttackPhase.RECOVERY:
			# Arc fades out at end position
			var t: float = clamp(_phase_timer / RECOVERY_DURATION, 0.0, 1.0)
			_sweep_progress = 1.0
			_arc_alpha = 1.0 - t
			if _phase_timer >= RECOVERY_DURATION:
				_phase = AttackPhase.IDLE
				_phase_timer = 0.0
				_sweep_progress = 0.0
				_arc_alpha = 0.0
				is_attacking = false
				FileLogger.info("[CombatKnife] Attack complete — IDLE")

	queue_redraw()


## Get the current aim angle (radians) from the player model (faces mouse cursor).
## Falls back to player body rotation if model is not set.
func _get_aim_angle() -> float:
	if _player_model != null and is_instance_valid(_player_model):
		return _player_model.global_rotation
	if _player != null and is_instance_valid(_player):
		return _player.rotation
	return 0.0


## Draw the directional slash arc.
## WINDUP: thin backswing line at the start edge (aim - 60°).
## STRIKE: arc sweeps from start edge to current sweep position.
## RECOVERY: full arc at end position, fading out.
func _draw() -> void:
	if _player == null or not is_instance_valid(_player):
		return

	var aim_angle: float = _get_aim_angle()
	# Start of swing (backswing edge): aim - KNIFE_ARC_HALF
	# End of swing (follow-through edge): aim + KNIFE_ARC_HALF
	var swing_start: float = aim_angle - KNIFE_ARC_HALF
	var swing_end: float = aim_angle + KNIFE_ARC_HALF

	match _phase:
		AttackPhase.WINDUP:
			# Show a dim backswing line at the start edge (anticipation)
			var windup_col: Color = Color(WINDUP_COLOR.r, WINDUP_COLOR.g, WINDUP_COLOR.b, WINDUP_COLOR.a * _arc_alpha)
			var start_vec: Vector2 = Vector2(cos(swing_start), sin(swing_start)) * KNIFE_RANGE
			draw_line(Vector2.ZERO, start_vec, windup_col, 2.5, true)
			# Small indicator dot at the start edge tip
			draw_circle(start_vec, 3.0, windup_col)

		AttackPhase.STRIKE, AttackPhase.RECOVERY:
			if _arc_alpha <= 0.001:
				return
			# Arc goes from swing_start to current sweep position
			var current_end: float = swing_start + (swing_end - swing_start) * _sweep_progress
			var arc_span: float = current_end - swing_start

			if arc_span <= 0.01:
				# Just draw the start line when sweep hasn't progressed yet
				var edge_col_start: Color = Color(ARC_EDGE_COLOR.r, ARC_EDGE_COLOR.g, ARC_EDGE_COLOR.b, ARC_EDGE_COLOR.a * _arc_alpha)
				draw_line(Vector2.ZERO, Vector2(cos(swing_start), sin(swing_start)) * KNIFE_RANGE, edge_col_start, 2.0, true)
				return

			var step: float = arc_span / ARC_SEGMENTS

			# Build filled sector polygon: origin → outer arc → back to origin
			var points: PackedVector2Array = PackedVector2Array()
			var colors: PackedColorArray = PackedColorArray()

			# Center point
			points.append(Vector2.ZERO)
			var center_col: Color = Color(ARC_COLOR.r, ARC_COLOR.g, ARC_COLOR.b, ARC_COLOR.a * _arc_alpha * 0.4)
			colors.append(center_col)

			# Outer arc points from start edge to current sweep end
			for i in range(ARC_SEGMENTS + 1):
				var a: float = swing_start + step * i
				points.append(Vector2(cos(a), sin(a)) * KNIFE_RANGE)
				# Brighter at the leading edge (current_end side)
				var edge_factor: float = float(i) / float(ARC_SEGMENTS)
				var edge_alpha: float = _arc_alpha * (0.3 + 0.7 * edge_factor)
				colors.append(Color(ARC_COLOR.r, ARC_COLOR.g, ARC_COLOR.b, ARC_COLOR.a * edge_alpha))

			draw_polygon(points, colors)

			# Draw bright leading edge line (the cutting edge sweeping forward)
			var leading_edge_col: Color = Color(ARC_EDGE_COLOR.r, ARC_EDGE_COLOR.g, ARC_EDGE_COLOR.b, ARC_EDGE_COLOR.a * _arc_alpha)
			var trailing_edge_col: Color = Color(ARC_EDGE_COLOR.r, ARC_EDGE_COLOR.g, ARC_EDGE_COLOR.b, ARC_EDGE_COLOR.a * _arc_alpha * 0.4)
			var start_vec: Vector2 = Vector2(cos(swing_start), sin(swing_start)) * KNIFE_RANGE
			var end_vec: Vector2 = Vector2(cos(current_end), sin(current_end)) * KNIFE_RANGE
			# Trailing edge (dim)
			draw_line(Vector2.ZERO, start_vec, trailing_edge_col, 1.5, true)
			# Leading edge (bright — the blade tip)
			draw_line(Vector2.ZERO, end_vec, leading_edge_col, 2.5, true)


## Apply damage to all enemies within the knife arc.
func _apply_damage() -> void:
	if _player == null or not is_instance_valid(_player):
		return

	# Determine facing direction from aim angle (mouse direction)
	var aim_angle: float = _get_aim_angle()
	var player_facing: Vector2 = Vector2(cos(aim_angle), sin(aim_angle))

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
