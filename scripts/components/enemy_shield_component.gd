class_name EnemyShieldComponent
extends Node
## SWAT shield component for the shieldbearer enemy (Issue #1242).
## Extracted as a component following the EnemyForceFieldComponent pattern.
##
## Mechanics:
## - Shield blocks all incoming bullets except sniper rounds (penetration_power >= SNIPER_PENETRATION_THRESHOLD).
## - Shield absorbs up to SHIELD_HP damage before it breaks temporarily.
## - When shield breaks: enemy staggers back, shield drops, enemy is stunned+blinded for STUN_DURATION seconds.
## - After stun ends: shield rises again automatically.
## - While shield is raised: enemy move_speed is halved.
## - Nearby allied enemies (within FORMATION_RADIUS px) are notified so they can
##   walk behind the shielded enemy using it as cover (formation logic).

## Damage the shield absorbs before breaking.
const SHIELD_HP: int = 20

## Stun and blind duration when shield breaks (seconds).
const STUN_DURATION: float = 1.0

## Knockback impulse applied to the enemy when shield breaks (pixels/sec).
const STAGGER_IMPULSE: float = 200.0

## Penetration power threshold above which bullets pass through the shield.
## Sniper calibers have penetration_power >= 80 (revolver 80, ASVK 100).
## Regular bullets have penetration_power < 80 (AK 5.45mm: 20, 9mm Makarov: 8, etc.).
## Per issue #1242: only sniper shots penetrate. Set threshold to 80 so that
## the ASVK anti-materiel rifle (100) and only that passes through.
const SNIPER_PENETRATION_THRESHOLD: float = 80.0

## Radius within which nearby enemies follow behind the shieldbearer (Issue #1242).
const FORMATION_RADIUS: float = 350.0

## Offset behind the shielder where allies position themselves.
const FORMATION_OFFSET: float = 80.0

## Speed multiplier applied to the enemy while shield is raised.
const SHIELD_SPEED_MULTIPLIER: float = 0.5

## Current shield HP (resets to SHIELD_HP when shield raises again).
var _shield_current_hp: int = SHIELD_HP

## Whether the shield is currently raised (active).
var _shield_up: bool = true

## Whether the shield is regenerating (waiting for stun to finish).
var _recovering: bool = false

## Stun timer countdown.
var _stun_timer: float = 0.0

## Visual shield sprite node (a Sprite2D added to EnemyModel).
var _shield_sprite: Node2D = null

## Reference to parent enemy node.
var _parent: Node2D = null


func _ready() -> void:
	_parent = get_parent() as Node2D


## Set up the shield visual and Area2D. Called from enemy _ready().
func setup() -> void:
	_shield_current_hp = SHIELD_HP
	_shield_up = true
	_recovering = false
	_stun_timer = 0.0
	_setup_shield_visual()
	FileLogger.info("[EnemyShield] Setup complete (shield_hp=%d, stun=%.1fs)" % [SHIELD_HP, STUN_DURATION])


## Returns true if the shield is currently blocking bullets.
func is_active() -> bool:
	return _shield_up


## Returns the speed multiplier to apply to the enemy's movement.
## Returns SHIELD_SPEED_MULTIPLIER while shield is up, 1.0 otherwise.
func get_speed_multiplier() -> float:
	return SHIELD_SPEED_MULTIPLIER if _shield_up else 1.0


## Called each physics frame from enemy _physics_process().
func update(delta: float) -> void:
	if _recovering:
		_stun_timer -= delta
		if _stun_timer <= 0.0:
			_stun_timer = 0.0
			_recovering = false
			_raise_shield()
	_update_formation(delta)


## Attempt to intercept a bullet hit before it reaches the enemy's HitArea.
## @param caliber_data: The bullet's caliber data resource (may be null).
## @param damage: The damage the bullet would deal.
## @param hit_direction: The direction the bullet is travelling.
## @return true if the shield blocked the hit (enemy takes no damage), false if bullet passes through.
func try_intercept_hit(caliber_data: Resource, damage: float, hit_direction: Vector2) -> bool:
	if not _shield_up:
		return false

	# Sniper-grade rounds (very high penetration power) pass through the shield.
	if _is_sniper_round(caliber_data):
		FileLogger.info("[EnemyShield] Sniper round bypassed shield (penetration_power >= %.0f)" % SNIPER_PENETRATION_THRESHOLD)
		return false

	# Check if bullet is coming from the front (within 90° arc of shield facing).
	# Shield only blocks hits from the front half.
	if not _is_hit_from_front(hit_direction):
		FileLogger.info("[EnemyShield] Hit from behind - shield not blocking")
		return false

	# Absorb damage.
	var absorbed: int = maxi(int(round(damage)), 1)
	_shield_current_hp -= absorbed
	FileLogger.info("[EnemyShield] Absorbed %d dmg (shield_hp=%d/%d)" % [absorbed, _shield_current_hp, SHIELD_HP])

	if _shield_current_hp <= 0:
		_break_shield(hit_direction)
	else:
		_flash_shield()

	return true  # Hit was intercepted, enemy takes no damage.


## Check if the bullet came from the front (shield covers the forward arc).
func _is_hit_from_front(hit_direction: Vector2) -> bool:
	if _parent == null:
		return true
	# hit_direction is bullet travel direction; -hit_direction is the direction FROM the shooter.
	# Enemy "forward" is the direction it's facing (its rotation).
	var enemy_forward := Vector2.from_angle(_parent.rotation)
	# dot > 0 means hit_direction points somewhat in the same direction as enemy forward
	# i.e. bullet is coming from in front of the enemy.
	var dot: float = enemy_forward.dot(hit_direction.normalized())
	return dot > 0.0  # Shield covers the front hemisphere


## Check whether a caliber qualifies as sniper-grade (bypasses shield).
func _is_sniper_round(caliber_data: Resource) -> bool:
	if caliber_data == null:
		return false
	if caliber_data.has_method("can_penetrate_walls"):
		if not caliber_data.can_penetrate_walls():
			return false
	var pen_power: float = 0.0
	if "penetration_power" in caliber_data:
		pen_power = caliber_data.penetration_power
	return pen_power >= SNIPER_PENETRATION_THRESHOLD


## Drop the shield and apply stagger + stun to the enemy.
func _break_shield(hit_direction: Vector2) -> void:
	_shield_up = false
	_shield_current_hp = 0
	_recovering = true
	_stun_timer = STUN_DURATION

	if _shield_sprite:
		_shield_sprite.visible = false

	# Apply stagger (knockback impulse).
	if _parent and _parent.has_method("apply_knockback"):
		_parent.apply_knockback(-hit_direction.normalized() * STAGGER_IMPULSE)
	elif _parent and "velocity" in _parent:
		# Direct velocity push as fallback.
		_parent.velocity += -hit_direction.normalized() * STAGGER_IMPULSE

	# Apply stun + blind for STUN_DURATION seconds.
	if _parent and _parent.has_method("apply_flashbang_effect"):
		_parent.apply_flashbang_effect(STUN_DURATION, STUN_DURATION)

	FileLogger.info("[EnemyShield] Shield broken! Stun=%.1fs, stagger applied" % STUN_DURATION)


## Raise the shield again after recovery.
func _raise_shield() -> void:
	_shield_up = true
	_shield_current_hp = SHIELD_HP
	if _shield_sprite:
		_shield_sprite.visible = true
	# Clear stun/blind state (should already be cleared by timer, but be explicit).
	if _parent and _parent.has_method("set_stunned"):
		_parent.set_stunned(false)
	if _parent and _parent.has_method("set_blinded"):
		_parent.set_blinded(false)
	FileLogger.info("[EnemyShield] Shield raised again (hp=%d)" % SHIELD_HP)


## Flash the shield sprite briefly when it absorbs a hit.
func _flash_shield() -> void:
	if _shield_sprite == null:
		return
	var original_color: Color = _shield_sprite.modulate
	_shield_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
	await _parent.get_tree().create_timer(0.08).timeout
	if is_instance_valid(_shield_sprite):
		_shield_sprite.modulate = original_color


## Create the SWAT riot shield visual (a Polygon2D rectangle with viewport window, attached to EnemyModel).
## Draws a tall rectangular ballistic shield like a real SWAT/police riot shield.
func _setup_shield_visual() -> void:
	if _parent == null:
		return
	var model: Node = _parent.get_node_or_null("EnemyModel")
	if model == null:
		FileLogger.info("[EnemyShield] WARNING: EnemyModel not found, skipping shield visual")
		return

	# Create a container node for the whole shield assembly.
	var shield_node := Node2D.new()
	shield_node.name = "ShieldSprite"
	shield_node.position = Vector2(20, 0)  # In front of enemy (facing direction is +X in top-down)
	shield_node.z_index = 6  # Above weapon sprite (z=2)

	# Main shield body: tall dark rectangle (SWAT ballistic shield shape).
	# In top-down view, the shield appears as a wide rectangle perpendicular to facing direction.
	# X = forward/back, Y = left/right in enemy-local space.
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([Vector2(-4, -18), Vector2(4, -18), Vector2(4, 18), Vector2(-4, 18)])
	body.color = Color(0.15, 0.15, 0.18, 0.95)  # Dark charcoal (like real SWAT shield)
	shield_node.add_child(body)

	# Shield edge/frame: slightly larger outline for depth.
	var frame := Polygon2D.new()
	frame.polygon = PackedVector2Array([Vector2(-5, -19), Vector2(5, -19), Vector2(5, 19), Vector2(-5, 19)])
	frame.color = Color(0.1, 0.1, 0.12, 0.9)  # Darker frame edge
	frame.z_index = -1  # Behind the body
	shield_node.add_child(frame)

	# Viewport window: small transparent rectangle near top of shield.
	var viewport_window := Polygon2D.new()
	viewport_window.polygon = PackedVector2Array([Vector2(-2, -13), Vector2(2, -13), Vector2(2, -8), Vector2(-2, -8)])
	viewport_window.color = Color(0.5, 0.6, 0.7, 0.6)  # Semi-transparent blue-grey glass
	shield_node.add_child(viewport_window)

	# Handle grip hint: small dark bar at bottom-center (where hand holds).
	var grip := Polygon2D.new()
	grip.polygon = PackedVector2Array([Vector2(-2, 10), Vector2(2, 10), Vector2(2, 14), Vector2(-2, 14)])
	grip.color = Color(0.08, 0.08, 0.1, 0.8)  # Very dark grip
	shield_node.add_child(grip)

	model.add_child(shield_node)
	_shield_sprite = shield_node
	FileLogger.info("[EnemyShield] SWAT riot shield visual created")


## Update formation: notify nearby allied enemies to follow behind this shielded enemy.
## Called each physics frame; uses a simple positional signal approach.
func _update_formation(_delta: float) -> void:
	if not _shield_up or _parent == null:
		return

	# Get all enemies in the scene.
	var enemies: Array = _parent.get_tree().get_nodes_in_group("enemies")
	var enemy_forward := Vector2.from_angle(_parent.rotation)
	var shield_back_pos: Vector2 = _parent.global_position - enemy_forward * FORMATION_OFFSET

	for e in enemies:
		if e == _parent:
			continue
		if not is_instance_valid(e):
			continue
		var dist: float = _parent.global_position.distance_to(e.global_position)
		if dist > FORMATION_RADIUS:
			continue
		# Notify the ally of the formation position so it can navigate there.
		if e.has_method("set_formation_follow_target"):
			e.set_formation_follow_target(_parent, shield_back_pos)
