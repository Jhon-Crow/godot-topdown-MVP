extends CharacterBody2D
## Drone entity spawned by the Drone Operator enemy (Issue #1397, #1417).
##
## Scene script: handles visuals and hit forwarding to the DroneComponent child.
## All AI logic lives in DroneComponent (scripts/components/drone_component.gd).
##
## IMPORTANT: No typed DroneComponent references here — use duck typing only.
## In Godot 4 exported builds, class_name registration order is not guaranteed,
## so referencing a class_name at parse time can cause silent script load failures.

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

## Reference to the DroneComponent child (untyped to avoid class_name dependency).
var _drone_component = null

## Rotor angle for animation.
var _rotor_angle: float = 0.0

## Stored rotor sprites for animation.
var _rotor_sprites: Array = []

## Whether the drone is alive.
var _is_alive: bool = true

## LED indicator polygon (changes color: green=searching, red=combat).
var _led: Polygon2D = null

## PointLight2D for LED glow in combat mode.
var _led_light: PointLight2D = null


func _ready() -> void:
	add_to_group("enemies")
	FileLogger.info("[Drone] _ready started")

	# Get DroneComponent using duck typing (no class_name cast)
	_drone_component = get_node_or_null("DroneComponent")
	if _drone_component:
		FileLogger.info("[Drone] DroneComponent found")
		# Connect signals for death handling and combat visual updates
		if _drone_component.has_signal("drone_destroyed"):
			_drone_component.drone_destroyed.connect(_on_drone_destroyed)
		if _drone_component.has_signal("combat_activated"):
			_drone_component.combat_activated.connect(_on_combat_activated)
	else:
		FileLogger.info("[Drone] WARNING: DroneComponent child not found!")

	_setup_drone_visual()
	FileLogger.info("[Drone] _ready complete")


## Initialize the drone with operator reference (called by DroneOperatorComponent).
func initialize_drone(operator: Node2D) -> void:
	if _drone_component and _drone_component.has_method("initialize"):
		_drone_component.initialize(operator)
		FileLogger.info("[Drone] initialize_drone() forwarded to DroneComponent")
	else:
		FileLogger.info("[Drone] WARNING: DroneComponent.initialize() not available")


## Create the top-down drone visual using Polygon2D shapes.
func _setup_drone_visual() -> void:
	var model: Node2D = get_node_or_null("DroneModel")
	if model == null:
		return

	# Main body: dark gray square representing the drone chassis
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
	var arm_positions: Array = [
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
		rotor.color = Color(0.5, 0.5, 0.6, 0.3)
		rotor.z_index = 3
		model.add_child(rotor)
		_rotor_sprites.append(rotor)

	# LED indicator light (green = searching, switches to red in combat)
	_led = Polygon2D.new()
	_led.polygon = PackedVector2Array([
		Vector2(-2, -2),
		Vector2(2, -2),
		Vector2(2, 2),
		Vector2(-2, 2),
	])
	_led.color = Color(0.2, 0.8, 0.2, 0.9)  # Green = searching
	_led.z_index = 4
	model.add_child(_led)

	# Prepare PointLight2D for combat mode glow (hidden initially)
	_led_light = PointLight2D.new()
	_led_light.name = "LEDGlow"
	_led_light.color = Color(1.0, 0.1, 0.1, 1.0)
	_led_light.energy = 0.0  # Hidden initially
	_led_light.texture = _create_light_texture()
	_led_light.texture_scale = 0.3
	_led_light.z_index = 5
	model.add_child(_led_light)

	FileLogger.info("[Drone] Visual setup complete (quadcopter style, LED=green/searching)")


## Create a simple radial gradient texture for the LED glow light.
func _create_light_texture() -> ImageTexture:
	var size: int = 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	var radius: float = size / 2.0
	for x in range(size):
		for y in range(size):
			var dist := Vector2(x, y).distance_to(center)
			if dist <= radius:
				var alpha := 1.0 - (dist / radius)
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha * alpha))
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(image)


func _physics_process(delta: float) -> void:
	if not _is_alive:
		return

	# Animate rotors
	_rotor_angle += 20.0 * delta
	var is_combat: bool = _drone_component != null and _drone_component.has_method("is_in_combat") and _drone_component.is_in_combat()
	var speed_mult: float = 3.0 if is_combat else 1.0
	for rotor in _rotor_sprites:
		if is_instance_valid(rotor):
			rotor.color.a = 0.2 + 0.15 * abs(sin(_rotor_angle * speed_mult))

	# Pulse LED in combat mode
	if is_combat and _led_light:
		_led_light.energy = 2.0 + 1.5 * abs(sin(_rotor_angle * 2.0))
		if _led:
			_led.color.a = 0.7 + 0.3 * abs(sin(_rotor_angle * 2.0))


## Called when combat mode activates (signal from DroneComponent).
func _on_combat_activated() -> void:
	# Switch LED to red
	if _led:
		_led.color = Color(1.0, 0.1, 0.05, 0.95)
	if _led_light:
		_led_light.energy = 3.0
	FileLogger.info("[Drone] Combat visuals activated (LED=red)")


## Called when the drone is destroyed (signal from DroneComponent).
func _on_drone_destroyed() -> void:
	if not _is_alive:
		return
	_is_alive = false
	died.emit()
	died_with_info.emit(false, false, false)
	set_physics_process(false)
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)


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
func on_hit_with_info(_hit_direction: Vector2, _caliber_data: Resource) -> void:
	on_hit()


## Called when hit by a projectile with full bullet info.
func on_hit_with_bullet_info(_hit_direction: Vector2, _caliber_data: Resource, has_ricocheted: bool, has_penetrated: bool, bullet_damage: float = 1.0, is_from_player: bool = false) -> void:
	if not _is_alive:
		return
	hit.emit()
	if _drone_component and _drone_component.has_method("take_damage"):
		var dmg: int = maxi(int(round(bullet_damage)), 1)
		var destroyed: bool = _drone_component.take_damage(dmg)
		if destroyed:
			_die(has_ricocheted, has_penetrated, is_from_player)


## Handle drone death (shot down, not exploded).
func _die(is_ricochet_kill: bool, is_penetration_kill: bool, is_player_kill: bool) -> void:
	_is_alive = false
	died.emit()
	died_with_info.emit(is_ricochet_kill, is_penetration_kill, is_player_kill)
	FileLogger.info("[Drone] Died (ricochet=%s, penetration=%s, player=%s)" % [
		str(is_ricochet_kill), str(is_penetration_kill), str(is_player_kill)
	])
	set_physics_process(false)
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)


## Check if the drone is alive (used by collision system).
func is_alive() -> bool:
	return _is_alive


## Check if the drone is in combat mode (used by operator).
func is_in_combat() -> bool:
	if _drone_component and _drone_component.has_method("is_in_combat"):
		return _drone_component.is_in_combat()
	return false
