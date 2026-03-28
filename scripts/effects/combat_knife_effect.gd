extends Node2D
## Combat Knife active item effect (Issue #1587).
##
## Implements an unlimited-use fan/arc melee attack for the player.
## When activated via Space key, the player performs a 120° fan attack.
## All enemies within the arc and within KNIFE_RANGE pixels receive KNIFE_DAMAGE damage.
##
## Visual: a knife-shaped polygon (wide at hilt, tapering to a sharp point) sweeping
##         from one edge to the other (aim - 60° → aim + 60°).
## WINDUP: knife held at backswing position (aim - 60°, dim).
## STRIKE: knife sweeps from aim - 60° to aim + 60° in one direction (fast).
## RECOVERY: knife fades out at final position (aim + 60°).
##
## Attack phases:
##   IDLE → WINDUP (0.15s, backswing hold) → STRIKE (0.1s, knife sweep edge to edge) → RECOVERY (0.12s, fade)
## Damage is applied once at the START of the STRIKE phase.
## No charges, no cooldown — the player can activate as fast as the animation allows.

## Attack animation phases.
enum AttackPhase {
	IDLE,     ## No attack in progress.
	WINDUP,   ## Backswing hold (0.15s) — knife at start edge.
	STRIKE,   ## Knife sweeps from start edge to end edge (0.1s) — damage applied.
	RECOVERY  ## Knife fades out at end edge (0.12s).
}

## Maximum range of the knife attack in pixels (35px * 1.8 = 63px per owner feedback).
const KNIFE_RANGE: float = 63.0

## Half-angle of the fan arc in radians (60° = 120° total fan).
const KNIFE_ARC_HALF: float = PI / 3.0

## Damage dealt to each enemy hit.
const KNIFE_DAMAGE: float = 7.0

## Duration of the windup phase in seconds (backswing hold).
const WINDUP_DURATION: float = 0.15

## Duration of the strike phase in seconds (knife sweep edge to edge).
const STRIKE_DURATION: float = 0.10

## Duration of the recovery phase in seconds (fade out).
const RECOVERY_DURATION: float = 0.12

## Number of polygon segments for the arc shape.
const ARC_SEGMENTS: int = 20

## Trail color behind the sweeping knife (faint white ghost trail).
const ARC_COLOR: Color = Color(1.0, 1.0, 1.0, 0.25)

## Knife blade color — bright white sharp line.
const ARC_EDGE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.95)

## Windup line color (dim white backswing indicator).
const WINDUP_COLOR: Color = Color(0.85, 0.85, 0.85, 0.45)

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

## Sweep progress during STRIKE (0.0 = at start edge aim-60°, 1.0 = at end edge aim+60°).
## The knife line sweeps from one edge to the other.
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
	FileLogger.info("[CombatKnife] Initialized — unlimited uses, 7 damage, 120° arc, %.0fpx range (white sharp blade)" % KNIFE_RANGE)


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
	FileLogger.info("[CombatKnife] Attack started — WINDUP (knife at backswing edge)")
	return true


## Called every physics frame. Advances the attack animation state machine.
func _physics_process(delta: float) -> void:
	if _phase == AttackPhase.IDLE:
		return

	_phase_timer += delta

	match _phase:
		AttackPhase.WINDUP:
			# Backswing hold — knife held at start edge (aim - 60°), anticipation pose
			_sweep_progress = 0.0
			_arc_alpha = 1.0
			if _phase_timer >= WINDUP_DURATION:
				_phase = AttackPhase.STRIKE
				_phase_timer = 0.0
				# Apply damage immediately at start of strike
				if not _damage_applied:
					_apply_damage()
					_damage_applied = true
				FileLogger.info("[CombatKnife] Attack phase: STRIKE (knife sweeping)")

		AttackPhase.STRIKE:
			# Knife sweeps from start edge to end edge
			var t: float = clamp(_phase_timer / STRIKE_DURATION, 0.0, 1.0)
			_sweep_progress = t
			_arc_alpha = 1.0
			if _phase_timer >= STRIKE_DURATION:
				_phase = AttackPhase.RECOVERY
				_phase_timer = 0.0
				_sweep_progress = 1.0
				FileLogger.info("[CombatKnife] Attack phase: RECOVERY")

		AttackPhase.RECOVERY:
			# Full arc fades out
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


## Draw a knife-shaped polygon at the given angle with the given alpha.
## The blade is wide at the hilt (base) and tapers to a sharp point at the tip.
## Visual length is half of KNIFE_RANGE so the animation looks compact (not sword-like).
## @param angle: direction angle (radians) the knife is pointing.
## @param alpha: opacity multiplier (0.0 = invisible, 1.0 = full).
## @param base_color: base Color to apply (alpha is multiplied on top).
func _draw_knife_at(angle: float, alpha: float, base_color: Color) -> void:
	if alpha <= 0.001:
		return

	var col: Color = Color(base_color.r, base_color.g, base_color.b, base_color.a * alpha)

	# Knife visual parameters (half the damage range so it looks compact)
	var visual_length: float = KNIFE_RANGE * 0.5  # 2x shorter than damage range
	var blade_width: float = 5.0   # width at hilt (thicker than before)
	var guard_width: float = 7.0   # guard flare at base of blade
	var guard_length: float = visual_length * 0.18  # how far the guard extends

	# Direction vectors along and perpendicular to blade
	var dir: Vector2 = Vector2(cos(angle), sin(angle))
	var perp: Vector2 = Vector2(-sin(angle), cos(angle))

	# Blade tip (sharp point at the far end)
	var tip: Vector2 = dir * visual_length

	# Blade base (hilt/guard position)
	var base: Vector2 = dir * guard_length

	# Guard corners (wide at hilt for a realistic knife silhouette)
	var guard_left: Vector2 = base - perp * guard_width
	var guard_right: Vector2 = base + perp * guard_width

	# Mid-blade corners (narrow tapering toward tip)
	var mid_left: Vector2 = (base + tip * 0.3) - perp * (blade_width * 0.5)
	var mid_right: Vector2 = (base + tip * 0.3) + perp * (blade_width * 0.5)

	# Draw blade as a polygon: guard_left → mid_left → tip → mid_right → guard_right
	draw_colored_polygon(
		PackedVector2Array([guard_left, mid_left, tip, mid_right, guard_right]),
		PackedColorArray([col, col, col, col, col])
	)

	# Draw a handle stub (short rectangle behind the guard, pointing back)
	var handle_end: Vector2 = -dir * (visual_length * 0.12)
	var handle_left: Vector2 = handle_end - perp * (blade_width * 0.45)
	var handle_right: Vector2 = handle_end + perp * (blade_width * 0.45)
	var handle_col: Color = Color(col.r * 0.6, col.g * 0.5, col.b * 0.4, col.a * 0.9)
	draw_colored_polygon(
		PackedVector2Array([guard_left, guard_right, handle_right, handle_left]),
		PackedColorArray([handle_col, handle_col, handle_col, handle_col])
	)


## Draw the knife as a sweeping knife-shaped polygon.
## WINDUP: dim knife at the start edge (aim - 60°), held as backswing.
## STRIKE: bright knife sweeps from start edge (aim - 60°) to end edge (aim + 60°).
## RECOVERY: knife fades out at the end edge position.
func _draw() -> void:
	if _player == null or not is_instance_valid(_player):
		return

	var aim_angle: float = _get_aim_angle()
	# Knife sweeps from aim - KNIFE_ARC_HALF to aim + KNIFE_ARC_HALF
	var start_angle: float = aim_angle - KNIFE_ARC_HALF
	var end_angle: float = aim_angle + KNIFE_ARC_HALF

	match _phase:
		AttackPhase.WINDUP:
			# Knife held at backswing (start edge), dim anticipation pose
			_draw_knife_at(start_angle, WINDUP_COLOR.a * _arc_alpha, WINDUP_COLOR)

		AttackPhase.STRIKE:
			if _arc_alpha <= 0.001:
				return
			# Knife sweeps: current angle interpolates from start to end
			var current_angle: float = start_angle + (end_angle - start_angle) * _sweep_progress
			# Faint ghost trail arc showing the swept path
			var trail_col: Color = Color(ARC_COLOR.r, ARC_COLOR.g, ARC_COLOR.b, ARC_COLOR.a * _arc_alpha)
			var arc_span: float = current_angle - start_angle
			if arc_span > 0.01:
				var step: float = arc_span / ARC_SEGMENTS
				for i in range(ARC_SEGMENTS):
					var a0: float = start_angle + step * i
					var a1: float = start_angle + step * (i + 1)
					var fade: float = float(i) / float(ARC_SEGMENTS)
					var t_col: Color = Color(trail_col.r, trail_col.g, trail_col.b, trail_col.a * fade)
					draw_line(
						Vector2(cos(a0), sin(a0)) * (KNIFE_RANGE * 0.5),
						Vector2(cos(a1), sin(a1)) * (KNIFE_RANGE * 0.5),
						t_col, 1.5
					)
			# Main knife shape at current sweep position
			_draw_knife_at(current_angle, ARC_EDGE_COLOR.a * _arc_alpha, ARC_EDGE_COLOR)

		AttackPhase.RECOVERY:
			if _arc_alpha <= 0.001:
				return
			# Knife fades out at final position (end edge)
			_draw_knife_at(end_angle, ARC_EDGE_COLOR.a * _arc_alpha * _arc_alpha, ARC_EDGE_COLOR)


## Apply damage to all enemies within the knife arc.
## Uses on_hit_with_bullet_info with is_from_player=true so kills count
## toward the close-range kill unlock condition (Issue #1587).
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
		# Apply damage — use on_hit_with_bullet_info with is_from_player=true so the kill
		# is counted toward the close-range kill unlock condition via register_kill.
		var hit_dir: Vector2 = -player_facing  # damage comes from player direction
		if enemy.has_method("on_hit_with_bullet_info"):
			enemy.on_hit_with_bullet_info(hit_dir, null, false, false, KNIFE_DAMAGE, true)
		elif enemy.has_method("take_damage"):
			enemy.take_damage(KNIFE_DAMAGE)
		elif enemy.has_method("TakeDamage"):
			enemy.TakeDamage(KNIFE_DAMAGE)
		hit_count += 1
		FileLogger.info("[CombatKnife] Hit enemy '%s' for %.0f damage (dist=%.1f, angle=%.1f°)" % [
			enemy.name, KNIFE_DAMAGE, dist, rad_to_deg(abs(angle))
		])

	knife_struck.emit()
	FileLogger.info("[CombatKnife] Damage applied — %d enemies hit" % hit_count)
