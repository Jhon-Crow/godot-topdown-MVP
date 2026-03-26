class_name MachineGunnerZoneComponent
extends RefCounted
## Detects whether an enemy is inside the firing sector of an allied machine gunner (Issue #1552).
##
## Machine gunners suppress a corridor (a cone aimed at the player's last known position)
## and other enemies should avoid walking into that cone to prevent being caught in
## friendly cross-fire or obstructing the suppression.
##
## The component scans the "enemies" group each frame, finds any machine gunner that is
## actively suppressing a corridor (_machine_gunner_suppressing_corridor == true), and
## checks whether this enemy's position (or a candidate cover position) lies within
## the gunner's firing sector.
##
## Usage:
##   In enemy._ready():
##     _mg_zone = MachineGunnerZoneComponent.new(self)
##   Each physics frame (after updating state):
##     _mg_zone.update()
##   To check a specific position (e.g. in PursuitComponent):
##     MachineGunnerZoneComponent.is_position_in_any_mg_zone(enemy, candidate_pos)

## Half-angle (radians) of the machine gunner's suppression cone.
## Matches the ±5° corridor spread in _machine_gunner_fire_at_corridor plus a safety margin.
## A wider cone (±30°) ensures enemies avoid the full danger zone, not just the exact bullet path.
const MG_ZONE_HALF_ANGLE: float = deg_to_rad(30.0)

## Maximum range (pixels) of the machine gunner's suppressive fire sector.
## Beyond this distance the zone is not considered dangerous.
const MG_ZONE_MAX_RANGE: float = 700.0

## Penalty subtracted from a cover score when the position lies inside a MG firing sector.
## Large enough to strongly discourage routing through the zone (Issue #1552).
const MG_ZONE_COVER_PENALTY: float = 10.0

## Reference to the enemy node that owns this component.
var _enemy: Node2D = null

## True when this enemy is currently inside at least one machine gunner's firing sector.
var in_mg_firing_zone: bool = false


func _init(enemy_ref: Node2D) -> void:
	_enemy = enemy_ref


## Update the in_mg_firing_zone flag for this enemy's current position.
## Call this once per physics frame from the enemy's _physics_process.
func update() -> void:
	if _enemy == null or not is_instance_valid(_enemy):
		in_mg_firing_zone = false
		return
	in_mg_firing_zone = is_position_in_any_mg_zone(_enemy, _enemy.global_position)


## Check whether a world-space position is inside any active machine gunner's firing sector.
## Used by PursuitComponent to penalise candidate cover positions (Issue #1552).
##
## @param requesting_enemy  The enemy performing the check (excluded from self-check).
## @param pos               World-space position to test.
## @returns true if pos is within the firing cone of at least one suppressing machine gunner.
static func is_position_in_any_mg_zone(requesting_enemy: Node2D, pos: Vector2) -> bool:
	if requesting_enemy == null or not is_instance_valid(requesting_enemy):
		return false
	var enemies: Array = requesting_enemy.get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if e == requesting_enemy or not is_instance_valid(e):
			continue
		# Only active machine gunners in corridor-suppression mode count.
		if not e.get("_machine_gunner_suppressing_corridor"):
			continue
		var gunner_weapon = e.get("weapon_type")
		# WeaponType.MACHINE_GUN == 6 (enum index in enemy.gd)
		if gunner_weapon == null or gunner_weapon != 6:
			continue
		# PM fallback mode — gunner is no longer suppressing, skip.
		if e.get("_machine_gunner_pm_active"):
			continue
		# Determine where the gunner is currently aiming.
		var suppress_target: Vector2 = Vector2.ZERO
		var player_ref = e.get("_player")
		var can_see = e.get("_can_see_player")
		var last_known = e.get("_last_known_player_position")
		if can_see and player_ref != null and is_instance_valid(player_ref):
			suppress_target = player_ref.global_position
		elif last_known != null and last_known != Vector2.ZERO:
			suppress_target = last_known
		if suppress_target == Vector2.ZERO:
			continue
		# Build the suppression cone: origin = gunner, direction = toward suppress_target.
		var gunner_pos: Vector2 = e.global_position
		var cone_dir: Vector2 = (suppress_target - gunner_pos).normalized()
		if cone_dir == Vector2.ZERO:
			continue
		# Check if pos is within range.
		var to_pos: Vector2 = pos - gunner_pos
		var dist: float = to_pos.length()
		if dist > MG_ZONE_MAX_RANGE:
			continue
		# Check angular deviation from cone centre.
		var dir_to_pos: Vector2 = to_pos / dist if dist > 0.0 else Vector2.ZERO
		var dot: float = cone_dir.dot(dir_to_pos)
		if dot >= cos(MG_ZONE_HALF_ANGLE):
			return true
	return false
