extends CharacterBody2D
## Drone entity spawned by the Drone Operator enemy (Issue #1397, #1417).
##
## Flying kamikaze drone with two AI phases:
## - SEARCHING: patrols with 360° vision, green LED
## - COMBAT: red LED, beeping sound, charges at player at 3x speed, explodes on contact
##
## Uses DroneComponent for all behavior logic.
## Includes on_hit methods so the HitArea can forward bullet damage.

## Signals matching the standard enemy interface for level tracking.
signal hit
signal died
signal died_with_info(is_ricochet_kill: bool, is_penetration_kill: bool, is_player_kill: bool)

## Visual size of the drone body polygon.
const DRONE_BODY_SIZE: float = 10.0

## Rotor arm length from center.
const ROTOR_ARM_LENGTH: float = 12.0

## Rotor radius.
const ROTOR_RADIUS: float = 4.0

## Rotor rotation speed (radians/sec).
const ROTOR_SPEED: float = 20.0

var _drone_component: Node = null  # DroneComponent (use Node type to avoid class_name load issues)
var _rotor_angle: float = 0.0
var _rotor_sprites: Array[Polygon2D] = []
var _is_alive: bool = true
var _led_sprite: Polygon2D = null


func _ready() -> void:
	FileLogger.info("[Drone] _ready started at %s" % str(global_position))
	add_to_group("enemies")

	# Get component using duck typing to avoid class_name resolution issues
	var comp_node: Node = get_node_or_null("DroneComponent")
	if comp_node:
		_drone_component = comp_node
		var comp_script: Script = comp_node.get_script() as Script
		FileLogger.info("[Drone] DroneComponent found: script=%s" % str(comp_script != null))
	else:
		FileLogger.info("[Drone] ERROR: DroneComponent node not found!")

	_setup_drone_visual()

	# Connect combat mode signals using duck typing
	if _drone_component:
		if _drone_component.has_signal("combat_entered"):
			_drone_component.combat_entered.connect(_on_combat_entered)
		if _drone_component.has_signal("drone_destroyed"):
			_drone_component.drone_destroyed.connect(_on_drone_destroyed)
		if _drone_component.has_signal("drone_exploded"):
			_drone_component.drone_exploded.connect(_on_drone_exploded)
	FileLogger.info("[Drone] _ready complete, component=%s" % str(_drone_component != null))


## Called when drone is destroyed (shot down).
func _on_drone_destroyed() -> void:
	_is_alive = false


## Called when drone explodes on contact.
func _on_drone_exploded() -> void:
	_is_alive = false


## Create the top-down drone visual using Polygon2D shapes.
func _setup_drone_visual() -> void:
	var model: Node2D = $DroneModel
	if model == null:
		return

	# Main body: dark gray square/circle representing the drone chassis
	var body_poly := Polygon2D.new()
	body_poly.polygon = PackedVector2Array([
		Vector2(-DRONE_BODY_SIZE, -DRONE_BODY_SIZE),
		Vector2(DRONE_BODY_SIZE, -DRONE_BODY_SIZE),
		Vector2(DRONE_BODY_SIZE, DRONE_BODY_SIZE),
		Vector2(-DRONE_BODY_SIZE, DRONE_BODY_SIZE),
	])
	body_poly.color = Color(0.2, 0.2, 0.25, 0.9)
	body_poly.z_index = 1
	model.add_child(body_poly)

	# Camera lens on front
	var lens := Polygon2D.new()
	lens.polygon = PackedVector2Array([
		Vector2(DRONE_BODY_SIZE - 2, -3),
		Vector2(DRONE_BODY_SIZE + 3, -3),
		Vector2(DRONE_BODY_SIZE + 3, 3),
		Vector2(DRONE_BODY_SIZE - 2, 3),
	])
	lens.color = Color(0.1, 0.5, 0.9, 0.9)  # Blue camera lens
	lens.z_index = 2
	model.add_child(lens)

	# Four rotor arms + rotor circles (quadcopter layout)
	var arm_positions: Array[Vector2] = [
		Vector2(ROTOR_ARM_LENGTH, ROTOR_ARM_LENGTH),
		Vector2(ROTOR_ARM_LENGTH, -ROTOR_ARM_LENGTH),
		Vector2(-ROTOR_ARM_LENGTH, ROTOR_ARM_LENGTH),
		Vector2(-ROTOR_ARM_LENGTH, -ROTOR_ARM_LENGTH),
	]
	for pos in arm_positions:
		# Arm line
		var arm := Polygon2D.new()
		arm.polygon = PackedVector2Array([
			Vector2(-1, -1) + pos * 0.2,
			Vector2(1, -1) + pos * 0.2,
			Vector2(1, 1) + pos,
			Vector2(-1, 1) + pos,
		])
		arm.color = Color(0.3, 0.3, 0.35, 0.8)
		model.add_child(arm)

		# Rotor disc (semi-transparent circle approximation)
		var rotor := Polygon2D.new()
		var points: PackedVector2Array = PackedVector2Array()
		for i in range(8):
			var angle: float = i * TAU / 8.0
			points.append(pos + Vector2(cos(angle), sin(angle)) * ROTOR_RADIUS)
		rotor.polygon = points
		rotor.color = Color(0.5, 0.5, 0.6, 0.3)  # Semi-transparent rotor disc
		rotor.z_index = 3
		model.add_child(rotor)
		_rotor_sprites.append(rotor)

	# LED indicator light (starts green for SEARCHING)
	_led_sprite = Polygon2D.new()
	_led_sprite.polygon = PackedVector2Array([
		Vector2(-2, -2),
		Vector2(2, -2),
		Vector2(2, 2),
		Vector2(-2, 2),
	])
	_led_sprite.color = Color(0.2, 0.9, 0.2, 0.9)  # Green LED = searching
	_led_sprite.z_index = 4
	model.add_child(_led_sprite)

	FileLogger.info("[Drone] Visual setup complete (quadcopter style, green LED)")


func _physics_process(_delta: float) -> void:
	# Animate rotor rotation (just modulate alpha for spinning effect)
	_rotor_angle += 20.0 * _delta
	for rotor in _rotor_sprites:
		if is_instance_valid(rotor):
			rotor.color.a = 0.2 + 0.15 * abs(sin(_rotor_angle))

	# Pulse LED in combat mode for dramatic effect
	if _drone_component and _drone_component.has_method("is_in_combat") and _drone_component.is_in_combat() and _led_sprite:
		var pulse := 0.6 + 0.4 * abs(sin(_rotor_angle * 2.0))
		_led_sprite.color = Color(1.0, 0.0, 0.0, pulse)


## Called when drone enters COMBAT mode — switch LED to red.
func _on_combat_entered() -> void:
	if _led_sprite:
		_led_sprite.color = Color(1.0, 0.0, 0.0, 0.9)  # Red LED = combat
	FileLogger.info("[Drone] LED switched to RED (combat mode)")


## Called when hit by a projectile (basic).
func on_hit() -> void:
	if not _is_alive:
		return
	hit.emit()
	if _drone_component and _drone_component.has_method("take_damage"):
		var destroyed: bool = _drone_component.take_damage(1)
		if destroyed:
			_die(false, false, false)


## Called when hit by a projectile with direction and caliber info.
func on_hit_with_info(hit_direction: Vector2, _caliber_data: Resource) -> void:
	on_hit()


## Called when hit by a projectile with full bullet info.
func on_hit_with_bullet_info(hit_direction: Vector2, caliber_data: Resource, has_ricocheted: bool, has_penetrated: bool, bullet_damage: float = 1.0, is_from_player: bool = false) -> void:
	if not _is_alive:
		return
	hit.emit()
	if _drone_component and _drone_component.has_method("take_damage"):
		var destroyed: bool = _drone_component.take_damage(maxi(int(round(bullet_damage)), 1))
		if destroyed:
			_die(has_ricocheted, has_penetrated, is_from_player)


## Handle drone death.
func _die(is_ricochet_kill: bool, is_penetration_kill: bool, is_player_kill: bool) -> void:
	_is_alive = false
	died.emit()
	died_with_info.emit(is_ricochet_kill, is_penetration_kill, is_player_kill)
	FileLogger.info("[Drone] Died (ricochet=%s, penetration=%s, player=%s)" % [
		str(is_ricochet_kill), str(is_penetration_kill), str(is_player_kill)
	])
