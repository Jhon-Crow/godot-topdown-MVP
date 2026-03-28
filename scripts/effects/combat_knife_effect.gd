extends Node2D
## Combat Knife active item effect (Issue #1587).
##
## Implements an unlimited-use fan/arc melee attack for the player.
## When activated via Space key, the player performs a 120° fan attack.
## All enemies within the arc and within KNIFE_RANGE pixels receive KNIFE_DAMAGE damage.
##
## Visual: a symmetric expanding fan arc drawn via _draw(), centered on the player's AIM direction.
## The fan expands symmetrically from 0° to full 120° (±60°) during STRIKE, then fades in RECOVERY.
##
## Attack phases:
##   IDLE → WINDUP (0.15s, backswing hold) → STRIKE (0.08s, fast fan expand) → RECOVERY (0.12s, fade)
## Damage is applied once at the START of the STRIKE phase.
## No charges, no cooldown — the player can activate as fast as the animation allows.

## Attack animation phases.
enum AttackPhase {
	IDLE,     ## No attack in progress.
	WINDUP,   ## Backswing hold (0.15s) — anticipation pose.
	STRIKE,   ## Fan expands symmetrically from 0° to full 120° (0.08s) — damage applied.
	RECOVERY  ## Full arc fades out (0.12s).
}

## Maximum range of the knife attack in pixels (half of original 70px for a tighter feel).
const KNIFE_RANGE: float = 35.0

## Half-angle of the fan arc in radians (60° = 120° total fan).
const KNIFE_ARC_HALF: float = PI / 3.0

## Damage dealt to each enemy hit.
const KNIFE_DAMAGE: float = 7.0

## Duration of the windup phase in seconds (backswing hold).
const WINDUP_DURATION: float = 0.15

## Duration of the strike phase in seconds (fan expand).
const STRIKE_DURATION: float = 0.08

## Duration of the recovery phase in seconds (fade out).
const RECOVERY_DURATION: float = 0.12

## Number of polygon segments for the arc shape.
const ARC_SEGMENTS: int = 20

## Arc fill color (orange-yellow slash, semi-transparent).
const ARC_COLOR: Color = Color(1.0, 0.75, 0.1, 0.55)

## Arc edge color (bright white-yellow highlight).
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

## Fan expand progress during STRIKE (0.0 = no arc, 1.0 = full 120° arc).
## The arc grows symmetrically outward from aim center to ±KNIFE_ARC_HALF.
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
	FileLogger.info("[CombatKnife] Attack started — WINDUP (backswing hold)")
	return true


## Called every physics frame. Advances the attack animation state machine.
func _physics_process(delta: float) -> void:
	if _phase == AttackPhase.IDLE:
		return

	_phase_timer += delta

	match _phase:
		AttackPhase.WINDUP:
			# Backswing hold — show a dim line at aim direction (anticipation pose)
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
			# Fan expands symmetrically — arc grows from 0° to full ±KNIFE_ARC_HALF
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


## Draw the symmetric fan arc.
## WINDUP: dim line at aim direction (backswing anticipation).
## STRIKE: fan expands symmetrically from 0° to full ±60° around aim.
## RECOVERY: full arc fades out.
func _draw() -> void:
	if _player == null or not is_instance_valid(_player):
		return

	var aim_angle: float = _get_aim_angle()

	match _phase:
		AttackPhase.WINDUP:
			# Show a dim line in the aim direction (anticipation)
			var windup_col: Color = Color(WINDUP_COLOR.r, WINDUP_COLOR.g, WINDUP_COLOR.b, WINDUP_COLOR.a * _arc_alpha)
			var aim_vec: Vector2 = Vector2(cos(aim_angle), sin(aim_angle)) * KNIFE_RANGE
			draw_line(Vector2.ZERO, aim_vec, windup_col, 2.5, true)
			draw_circle(aim_vec, 2.5, windup_col)

		AttackPhase.STRIKE, AttackPhase.RECOVERY:
			if _arc_alpha <= 0.001:
				return
			# Symmetric fan: current half-angle grows from 0 to KNIFE_ARC_HALF
			var current_half: float = KNIFE_ARC_HALF * _sweep_progress
			if current_half <= 0.01:
				# Just draw the aim line when arc is still tiny
				var center_col: Color = Color(ARC_EDGE_COLOR.r, ARC_EDGE_COLOR.g, ARC_EDGE_COLOR.b, ARC_EDGE_COLOR.a * _arc_alpha)
				draw_line(Vector2.ZERO, Vector2(cos(aim_angle), sin(aim_angle)) * KNIFE_RANGE, center_col, 2.0, true)
				return

			var arc_start: float = aim_angle - current_half
			var arc_end: float = aim_angle + current_half
			var arc_span: float = arc_end - arc_start
			var step: float = arc_span / ARC_SEGMENTS

			# Build filled sector polygon: origin → outer arc → back to origin
			var points: PackedVector2Array = PackedVector2Array()
			var colors: PackedColorArray = PackedColorArray()

			# Center point (dimmer)
			points.append(Vector2.ZERO)
			colors.append(Color(ARC_COLOR.r, ARC_COLOR.g, ARC_COLOR.b, ARC_COLOR.a * _arc_alpha * 0.4))

			# Outer arc points from arc_start to arc_end
			for i in range(ARC_SEGMENTS + 1):
				var a: float = arc_start + step * i
				points.append(Vector2(cos(a), sin(a)) * KNIFE_RANGE)
				# Brighter near the edges, dimmer near the center
				var t: float = float(i) / float(ARC_SEGMENTS)
				var edge_factor: float = 1.0 - abs(t * 2.0 - 1.0)  # 0 at edges, 1 at center
				var alpha: float = _arc_alpha * (0.4 + 0.6 * edge_factor)
				colors.append(Color(ARC_COLOR.r, ARC_COLOR.g, ARC_COLOR.b, ARC_COLOR.a * alpha))

			draw_polygon(points, colors)

			# Draw bright edge lines on both sides of the fan
			var edge_col: Color = Color(ARC_EDGE_COLOR.r, ARC_EDGE_COLOR.g, ARC_EDGE_COLOR.b, ARC_EDGE_COLOR.a * _arc_alpha)
			draw_line(Vector2.ZERO, Vector2(cos(arc_start), sin(arc_start)) * KNIFE_RANGE, edge_col, 2.0, true)
			draw_line(Vector2.ZERO, Vector2(cos(arc_end), sin(arc_end)) * KNIFE_RANGE, edge_col, 2.0, true)


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
