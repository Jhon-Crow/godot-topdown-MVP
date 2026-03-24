extends CharacterBody2D
## Drone entity spawned by the Drone Operator enemy (Issue #1397).
##
## Minimal implementation: a small flying drone that moves toward the player
## and can be destroyed. Uses DroneComponent for behavior logic.
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

var _drone_component: DroneComponent = null
var _rotor_angle: float = 0.0
var _rotor_sprites: Array[Polygon2D] = []
var _is_alive: bool = true


func _ready() -> void:
	add_to_group("enemies")
	_drone_component = $DroneComponent as DroneComponent
	_setup_drone_visual()


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

	# LED indicator light
	var led := Polygon2D.new()
	led.polygon = PackedVector2Array([
		Vector2(-2, -2),
		Vector2(2, -2),
		Vector2(2, 2),
		Vector2(-2, 2),
	])
	led.color = Color(1.0, 0.0, 0.0, 0.9)  # Red LED
	led.z_index = 4
	model.add_child(led)

	FileLogger.info("[Drone] Visual setup complete (quadcopter style)")


func _physics_process(_delta: float) -> void:
	# Animate rotor rotation (just modulate alpha for spinning effect)
	_rotor_angle += 20.0 * _delta
	for rotor in _rotor_sprites:
		if is_instance_valid(rotor):
			rotor.color.a = 0.2 + 0.15 * abs(sin(_rotor_angle))


## Called when hit by a projectile (basic).
func on_hit() -> void:
	if not _is_alive:
		return
	hit.emit()
	if _drone_component:
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
	if _drone_component:
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
