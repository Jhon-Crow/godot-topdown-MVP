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

## Rotation speed multiplier while shield is raised (slower turning with heavy shield).
## Issue #1242 feedback: enemy should turn even slower with the shield.
const SHIELD_ROTATION_MULTIPLIER: float = 0.15

## Current shield HP (resets to SHIELD_HP when shield raises again).
var _shield_current_hp: int = SHIELD_HP

## Whether the shield is currently raised (active).
var _shield_up: bool = true

## Whether the shield is regenerating (waiting for stun to finish).
var _recovering: bool = false

## Stun timer countdown.
var _stun_timer: float = 0.0

## Physics frame when the shield last intercepted a hit (prevents double-hit in same frame).
var _last_intercept_frame: int = -1

## Visual shield sprite node (a Sprite2D added to EnemyModel).
var _shield_sprite: Node2D = null

## Shield Area2D for collision-based bullet detection (Issue #1242 feedback).
var _shield_area: Area2D = null

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


## Returns true if the shield intercepted a hit during the current physics frame.
## Used to prevent double-damage when both shield Area2D and body HitArea overlap.
func did_intercept_this_frame() -> bool:
	return _last_intercept_frame == Engine.get_physics_frames()


## Returns the speed multiplier to apply to the enemy's movement.
## Returns SHIELD_SPEED_MULTIPLIER while shield is up, 1.0 otherwise.
func get_speed_multiplier() -> float:
	return SHIELD_SPEED_MULTIPLIER if _shield_up else 1.0


## Returns the rotation speed multiplier while shield is raised.
## Shield makes the enemy turn slower due to weight and bulk.
func get_rotation_multiplier() -> float:
	return SHIELD_ROTATION_MULTIPLIER if _shield_up else 1.0


## Called each physics frame from enemy _physics_process().
func update(delta: float) -> void:
	if _recovering:
		_stun_timer -= delta
		if _stun_timer <= 0.0:
			_stun_timer = 0.0
			_recovering = false
			_raise_shield()
	_update_formation(delta)


## Attempt to intercept a bullet hit that has collided with the shield's Area2D.
## Called by ShieldHitArea when a bullet physically hits the shield model.
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

	# No angle check needed — the bullet physically hit the shield's collision shape.
	# Damage is only blocked when the bullet hits the shield model (Issue #1242 feedback).

	# Absorb damage.
	var absorbed: int = maxi(int(round(damage)), 1)
	_shield_current_hp -= absorbed
	_last_intercept_frame = Engine.get_physics_frames()
	FileLogger.info("[EnemyShield] Absorbed %d dmg (shield_hp=%d/%d)" % [absorbed, _shield_current_hp, SHIELD_HP])

	if _shield_current_hp <= 0:
		_break_shield(hit_direction)
	else:
		_flash_shield()

	return true  # Hit was intercepted, enemy takes no damage.


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
	if _shield_area:
		_shield_area.set_deferred("monitorable", false)

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
	if _shield_area:
		_shield_area.set_deferred("monitorable", true)
	# Clear stun/blind state (should already be cleared by timer, but be explicit).
	if _parent and _parent.has_method("set_stunned"):
		_parent.set_stunned(false)
	if _parent and _parent.has_method("set_blinded"):
		_parent.set_blinded(false)
	FileLogger.info("[EnemyShield] Shield raised again (hp=%d)" % SHIELD_HP)


## Flash the shield sprite briefly when it absorbs a hit (Issue #1242 feedback: flash shield, not enemy).
func _flash_shield() -> void:
	if _shield_sprite == null:
		return
	var original_color: Color = _shield_sprite.modulate
	_shield_sprite.modulate = Color(2.0, 2.0, 2.0, 1.0)  # Bright white flash (HDR overbright for visibility)
	await _parent.get_tree().create_timer(0.1).timeout
	if is_instance_valid(_shield_sprite):
		_shield_sprite.modulate = original_color


## Create the SWAT riot shield visual as seen from top-down (attached to EnemyModel).
## From above, a riot shield looks like a wide curved bar held in front of the body.
## In enemy-local space: +X = forward (facing), Y = left/right.
func _setup_shield_visual() -> void:
	if _parent == null:
		return
	var model: Node = _parent.get_node_or_null("EnemyModel")
	if model == null:
		FileLogger.info("[EnemyShield] WARNING: EnemyModel not found, skipping shield visual")
		return

	# Container positioned in front of enemy.
	var shield_node := Node2D.new()
	shield_node.name = "ShieldSprite"
	shield_node.position = Vector2(18, 0)  # In front of enemy (+X = forward)
	shield_node.z_index = 6  # Above weapon sprite

	# Top-down riot shield: a slightly curved wide bar.
	# The shield is wide left-right (Y axis) and thin front-back (X axis),
	# with a slight forward bulge in the center (convex toward the threat).
	# Issue #1242 feedback: reduced Y-span from ±14 to ±10 so side shots hit the body, not the shield.
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(3, -10),   # Front-right edge
		Vector2(5, -6),    # Front bulge right
		Vector2(6, 0),     # Front center (closest to threat)
		Vector2(5, 6),     # Front bulge left
		Vector2(3, 10),    # Front-left edge
		Vector2(-1, 10),   # Back-left edge
		Vector2(-1, -10),  # Back-right edge
	])
	body.color = Color(0.15, 0.15, 0.18, 0.95)  # Dark charcoal
	shield_node.add_child(body)

	# Frame outline: slightly larger for depth.
	# Issue #1242 feedback: reduced Y-span from ±15 to ±11 (matches smaller hitbox).
	var frame := Polygon2D.new()
	frame.polygon = PackedVector2Array([
		Vector2(4, -11),
		Vector2(6, -6),
		Vector2(7, 0),
		Vector2(6, 6),
		Vector2(4, 11),
		Vector2(-2, 11),
		Vector2(-2, -11),
	])
	frame.color = Color(0.1, 0.1, 0.12, 0.9)
	frame.z_index = -1  # Behind body
	shield_node.add_child(frame)

	# Viewport window centered on the shield (top-down: Y=0 is center, X is front-back).
	# Matches real SWAT riot shield where the window is centered horizontally.
	var viewport_window := Polygon2D.new()
	viewport_window.polygon = PackedVector2Array([
		Vector2(2, -4),
		Vector2(5, -4),
		Vector2(5, 4),
		Vector2(2, 4),
	])
	viewport_window.color = Color(0.5, 0.6, 0.7, 0.5)  # Semi-transparent glass
	shield_node.add_child(viewport_window)

	# Grip: small dark bar on the back side (inner face).
	var grip := Polygon2D.new()
	grip.polygon = PackedVector2Array([
		Vector2(-2, -3),
		Vector2(0, -3),
		Vector2(0, 3),
		Vector2(-2, 3),
	])
	grip.color = Color(0.08, 0.08, 0.1, 0.8)
	shield_node.add_child(grip)

	# Add Area2D for collision-based bullet detection (Issue #1242 feedback).
	# Bullets that physically hit the shield model are intercepted; side/back shots bypass it.
	var shield_area := Area2D.new()
	shield_area.name = "ShieldHitArea"
	shield_area.collision_layer = 2  # Same layer as enemy HitArea so bullets detect it
	shield_area.collision_mask = 16  # Same mask as enemy HitArea (bullet layer)
	var shield_hit_area_script = load("res://scripts/components/shield_hit_area.gd")
	shield_area.set_script(shield_hit_area_script)
	shield_area.shield_component = self
	shield_area.enemy = _parent
	# Collision shape matching the shield frame outline.
	# Issue #1242 feedback: reduced Y-span from ±15 to ±11 to stop intercepting side-body hits.
	var collision_shape := CollisionPolygon2D.new()
	collision_shape.polygon = PackedVector2Array([
		Vector2(4, -11),
		Vector2(6, -6),
		Vector2(7, 0),
		Vector2(6, 6),
		Vector2(4, 11),
		Vector2(-2, 11),
		Vector2(-2, -11),
	])
	shield_area.add_child(collision_shape)
	shield_node.add_child(shield_area)
	_shield_area = shield_area

	model.add_child(shield_node)
	_shield_sprite = shield_node
	FileLogger.info("[EnemyShield] SWAT riot shield visual created with collision area (top-down view)")


## Update formation: notify nearby allied enemies to follow behind this shielded enemy.
## Called each physics frame; uses a simple positional signal approach.
func _update_formation(_delta: float) -> void:
	if not _shield_up or _parent == null:
		return

	# Get all enemies in the scene.
	var enemies: Array = _parent.get_tree().get_nodes_in_group("enemies")
	var model: Node2D = _parent.get_node_or_null("EnemyModel") as Node2D
	var facing_rotation: float = model.global_rotation if model else _parent.rotation
	var enemy_forward := Vector2.from_angle(facing_rotation)
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
