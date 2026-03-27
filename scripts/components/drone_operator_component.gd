class_name DroneOperatorComponent
extends Node
## Drone Operator (Дроновод) component for the enemy AI (Issue #1397).
##
## Behavior phases:
## 1. DEPLOYING: After spawn, seek nearest cover and deploy a drone.
## 2. CONTROLLING: While drone is alive, operator is defenseless (no movement, no vision).
## 3. ACTIVE: After drone is destroyed, pull out silenced pistol with laser sight
##    and act as a normal enemy. Dodges bullets perpendicular (same as machete enemy).

## Operator behavior phases.
enum Phase {
	DEPLOYING,    ## Seeking cover and deploying drone
	CONTROLLING,  ## Controlling the drone (defenseless)
	ACTIVE        ## Drone destroyed, fighting with pistol
}

## Time to wait at cover before deploying drone (seconds).
const DEPLOY_DELAY: float = 0.5

## Maximum time to spend seeking cover before deploying drone anyway (seconds).
const MAX_COVER_SEEK_TIME: float = 3.0

## Drone scene path.
const DRONE_SCENE_PATH: String = "res://scenes/objects/Drone.tscn"

## Drone spawn offset from operator.
const DRONE_SPAWN_OFFSET: Vector2 = Vector2(0, -40)

## Current phase.
var _phase: Phase = Phase.DEPLOYING

## Reference to the parent enemy.
var _parent: Node2D = null

## Reference to the spawned drone.
var _drone: Node2D = null

## Whether the drone has been deployed.
var _drone_deployed: bool = false

## Deploy delay timer.
var _deploy_timer: float = 0.0

## Whether we've reached initial cover.
var _reached_cover: bool = false

## Timer for how long we've been seeking cover (deploy anyway if exceeded).
var _cover_seek_timer: float = 0.0

## MacheteComponent instance used for bullet dodging in ACTIVE phase (Issue #1540).
## Same dodge logic as the machete enemy — perpendicular lateral dodge, no dash.
var _dodge_component: MacheteComponent = null

## Number of dodges performed in the current burst (Issue #1664).
var _dodge_burst_count: int = 0

## Maximum dodges allowed per burst before the long cooldown kicks in (Issue #1664).
const DODGE_BURST_MAX: int = 4

## Cooldown in seconds after exhausting the burst before dodging is allowed again (Issue #1664).
const DODGE_BURST_COOLDOWN: float = 4.0

## Timer counting down the burst cooldown (Issue #1664).
var _dodge_burst_cooldown_timer: float = 0.0

## VR headset visual node.
var _vr_headset: Node2D = null

## Tablet visual node (shown during DEPLOYING/CONTROLLING phases).
var _tablet: Node2D = null

## Cached reference to weapon mount for hide/show.
var _weapon_mount: Node2D = null

## Signal when drone is destroyed and operator switches to active.
signal phase_changed(new_phase: Phase)


func _ready() -> void:
	_parent = get_parent() as Node2D


## Set up the component. Called from enemy._ready().
func setup() -> void:
	_phase = Phase.DEPLOYING
	_drone_deployed = false
	_reached_cover = false
	_deploy_timer = 0.0
	_cover_seek_timer = 0.0
	_setup_vr_headset_visual()
	_setup_tablet_visual()
	_hide_weapon_show_tablet()
	FileLogger.info("[DroneOperator] Setup complete")


## Create VR headset visual on the enemy head.
func _setup_vr_headset_visual() -> void:
	if _parent == null:
		return
	var model: Node = _parent.get_node_or_null("EnemyModel")
	if model == null:
		return
	var head: Sprite2D = model.get_node_or_null("Head") as Sprite2D
	if head == null:
		return

	# VR headset: a horizontal band across the face (enemy sprites face right)
	_vr_headset = Node2D.new()
	_vr_headset.name = "VRHeadset"
	_vr_headset.z_index = 5  # Above head sprite

	var visor := Polygon2D.new()
	visor.polygon = PackedVector2Array([
		Vector2(-5, -2),
		Vector2(5, -2),
		Vector2(5, 2),
		Vector2(-5, 2),
	])
	visor.color = Color(0.1, 0.1, 0.15, 0.95)  # Dark visor
	_vr_headset.add_child(visor)

	# Glowing lens strip across the front
	var lens := Polygon2D.new()
	lens.name = "Lens"
	lens.polygon = PackedVector2Array([
		Vector2(-4, -1),
		Vector2(4, -1),
		Vector2(4, 1),
		Vector2(-4, 1),
	])
	lens.color = Color(0.2, 0.8, 0.3, 0.8)  # Green glow = controlling
	_vr_headset.add_child(lens)

	head.add_child(_vr_headset)
	FileLogger.info("[DroneOperator] VR headset visual created")


## Create tablet visual on the weapon mount (shown during DEPLOYING/CONTROLLING).
func _setup_tablet_visual() -> void:
	if _parent == null:
		return
	_weapon_mount = _parent.get_node_or_null("EnemyModel/WeaponMount") as Node2D
	if _weapon_mount == null:
		return

	_tablet = Node2D.new()
	_tablet.name = "Tablet"
	_tablet.z_index = 2

	# Tablet body — dark rectangle held in hands
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-6, -8),
		Vector2(6, -8),
		Vector2(6, 8),
		Vector2(-6, 8),
	])
	body.color = Color(0.15, 0.15, 0.2, 0.95)  # Dark tablet body
	_tablet.add_child(body)

	# Tablet screen — glowing green
	var screen := Polygon2D.new()
	screen.polygon = PackedVector2Array([
		Vector2(-4, -6),
		Vector2(4, -6),
		Vector2(4, 6),
		Vector2(-4, 6),
	])
	screen.color = Color(0.1, 0.6, 0.2, 0.8)  # Green screen
	_tablet.add_child(screen)

	_tablet.position = Vector2(10, 0)  # Held in front
	_weapon_mount.add_child(_tablet)
	_tablet.visible = true
	FileLogger.info("[DroneOperator] Tablet visual created")


## Hide the weapon sprite and show the tablet (DEPLOYING/CONTROLLING phases).
func _hide_weapon_show_tablet() -> void:
	if _weapon_mount:
		var weapon_sprite: Sprite2D = _weapon_mount.get_node_or_null("WeaponSprite") as Sprite2D
		if weapon_sprite:
			weapon_sprite.visible = false
	if _tablet:
		_tablet.visible = true


## Show the weapon sprite and hide the tablet (ACTIVE phase).
func _show_weapon_hide_tablet() -> void:
	if _weapon_mount:
		var weapon_sprite: Sprite2D = _weapon_mount.get_node_or_null("WeaponSprite") as Sprite2D
		if weapon_sprite:
			weapon_sprite.visible = true
	if _tablet:
		_tablet.visible = false


## Update called each physics frame from enemy._physics_process().
func update(delta: float) -> void:
	match _phase:
		Phase.DEPLOYING:
			_update_deploying(delta)
		Phase.CONTROLLING:
			_update_controlling(delta)
		Phase.ACTIVE:
			_update_active(delta)


## Returns the current phase.
func get_phase() -> Phase:
	return _phase


## Returns true if the operator is in the defenseless controlling phase.
func is_controlling_drone() -> bool:
	return _phase == Phase.CONTROLLING


## Returns true if the operator is currently dodging a bullet (ACTIVE phase only).
func is_dodging() -> bool:
	if _dodge_component == null:
		return false
	return _dodge_component.is_dodging()


## Try to dodge a bullet. Delegates to MacheteComponent logic.
## bullet_direction: normalized direction the bullet is traveling.
## Allows up to DODGE_BURST_MAX dodges per burst, then waits DODGE_BURST_COOLDOWN seconds (Issue #1664).
func try_dodge(bullet_direction: Vector2) -> bool:
	if _phase != Phase.ACTIVE or _dodge_component == null:
		return false
	# Burst cooldown: exhausted the allowed burst, wait before dodging again (Issue #1664)
	if _dodge_burst_cooldown_timer > 0.0:
		return false
	# Burst limit reached: start the long cooldown (Issue #1664)
	if _dodge_burst_count >= DODGE_BURST_MAX:
		_dodge_burst_cooldown_timer = DODGE_BURST_COOLDOWN
		_dodge_burst_count = 0
		FileLogger.info("[DroneOperator] Dodge burst exhausted, cooldown %.1fs" % DODGE_BURST_COOLDOWN)
		return false
	var started: bool = _dodge_component.try_dodge(bullet_direction)
	if started:
		_dodge_burst_count += 1
		FileLogger.info("[DroneOperator] Dodge %d/%d in burst" % [_dodge_burst_count, DODGE_BURST_MAX])
	return started


## Get current dodge velocity. Returns Vector2.ZERO if not dodging.
func get_dodge_velocity() -> Vector2:
	if _dodge_component == null:
		return Vector2.ZERO
	return _dodge_component.get_dodge_velocity()


## DEPLOYING phase: seek cover and deploy drone.
func _update_deploying(delta: float) -> void:
	if _parent == null:
		return

	# Check if we've arrived at cover position
	if not _reached_cover:
		_cover_seek_timer += delta

		var current_state: int = -1
		if _parent.has_method("get_current_state"):
			current_state = _parent.get_current_state()
		elif _parent.get("_current_state") != null:
			current_state = _parent._current_state

		# AIState.IN_COVER = 3, AIState.COMBAT = 1
		if current_state == 3:  # IN_COVER — found cover
			_reached_cover = true
			_deploy_timer = DEPLOY_DELAY
			FileLogger.info("[DroneOperator] Reached cover, deploying drone in %.1fs" % DEPLOY_DELAY)
		elif _cover_seek_timer >= MAX_COVER_SEEK_TIME or current_state == 1:
			# Timed out seeking cover or AI gave up and went to COMBAT — deploy at current position
			_reached_cover = true
			_deploy_timer = DEPLOY_DELAY
			FileLogger.info("[DroneOperator] Cover seek timeout (%.1fs) or state=%d, deploying drone at current position" % [_cover_seek_timer, current_state])
		else:
			return

	# Wait for deploy delay
	_deploy_timer -= delta
	if _deploy_timer <= 0.0 and not _drone_deployed:
		_deploy_drone()


## Deploy the drone.
func _deploy_drone() -> void:
	_drone_deployed = true

	# Try to load and instantiate the drone scene
	if ResourceLoader.exists(DRONE_SCENE_PATH):
		var drone_scene: PackedScene = load(DRONE_SCENE_PATH)
		if drone_scene:
			_drone = drone_scene.instantiate()
			_drone.global_position = _parent.global_position + DRONE_SPAWN_OFFSET
			# Add drone to the same parent as the operator
			var enemies_node: Node = _parent.get_parent()
			if enemies_node:
				enemies_node.add_child(_drone)
			else:
				_parent.get_tree().current_scene.add_child(_drone)

			# Initialize drone and connect destruction signal using duck typing
			# (drone.gd handles all AI directly — no DroneComponent class cast needed)
			var drone_script: GDScript = _drone.get_script() as GDScript
			FileLogger.info("[DroneOperator] Drone node created, script=%s" % (drone_script.resource_path if drone_script else "NONE"))
			if _drone.has_method("initialize_drone"):
				_drone.initialize_drone(_parent)
				FileLogger.info("[DroneOperator] Drone initialized via initialize_drone()")
			else:
				FileLogger.info("[DroneOperator] WARNING: Drone has no initialize_drone() method! Script may have failed to load.")
			if _drone.has_signal("died"):
				_drone.died.connect(_on_drone_destroyed)
				FileLogger.info("[DroneOperator] Connected to drone.died signal")
			else:
				FileLogger.info("[DroneOperator] WARNING: Drone has no 'died' signal! Script may have failed to load.")
			FileLogger.info("[DroneOperator] Drone deployed at (%d, %d)" % [int(_drone.global_position.x), int(_drone.global_position.y)])
	else:
		FileLogger.info("[DroneOperator] WARNING: Drone scene not found at %s, skipping deployment" % DRONE_SCENE_PATH)
		# If no drone scene, go directly to active mode
		_transition_to_active()
		return

	_transition_to_controlling()


## Transition to CONTROLLING phase.
func _transition_to_controlling() -> void:
	_phase = Phase.CONTROLLING
	# Set VR headset lens to bright green = actively controlling
	if _vr_headset:
		var lens: Polygon2D = _vr_headset.get_node_or_null("Lens") as Polygon2D
		if lens:
			lens.color = Color(0.0, 1.0, 0.2, 0.9)  # Bright green = actively controlling
	phase_changed.emit(Phase.CONTROLLING)
	FileLogger.info("[DroneOperator] Phase: CONTROLLING (defenseless)")


## CONTROLLING phase: defenseless while drone is alive.
func _update_controlling(_delta: float) -> void:
	if _parent == null:
		return

	# Force the operator to stay still and not shoot
	if "velocity" in _parent:
		_parent.velocity = Vector2.ZERO

	# Check if drone is still alive
	if _drone == null or not is_instance_valid(_drone):
		_on_drone_destroyed()


## Called when the drone is destroyed.
func _on_drone_destroyed() -> void:
	if _phase != Phase.CONTROLLING:
		return
	_drone = null
	FileLogger.info("[DroneOperator] Drone destroyed! Transitioning to ACTIVE")
	_transition_to_active()


## Laser sight Line2D node (shown during ACTIVE phase).
var _laser_sight: Line2D = null

## Transition to ACTIVE phase with silenced pistol.
func _transition_to_active() -> void:
	_phase = Phase.ACTIVE

	# Show weapon, hide tablet
	_show_weapon_hide_tablet()

	# Switch weapon to SILENCED_PISTOL (type 9) — Issue #1532
	if _parent and _parent.get("weapon_type") != null:
		_parent.set("weapon_type", 9)  # WeaponType.SILENCED_PISTOL
		if _parent.has_method("_configure_weapon_type"):
			_parent._configure_weapon_type()
		if _parent.has_method("_initialize_ammo"):
			_parent._initialize_ammo()

	# Scale the weapon sprite down — silenced pistol is a compact sidearm (Issue #1532 fix #1)
	if _weapon_mount:
		var weapon_sprite: Sprite2D = _weapon_mount.get_node_or_null("WeaponSprite") as Sprite2D
		if weapon_sprite:
			weapon_sprite.scale = Vector2(0.65, 0.65)  # Smaller than the default rifle-sized weapon

	# Add laser sight visual to weapon mount (Issue #1532)
	_setup_laser_sight()

	# Change VR headset lens to RED = drone destroyed / disconnected (Issue #1532)
	if _vr_headset:
		var lens: Polygon2D = _vr_headset.get_node_or_null("Lens") as Polygon2D
		if lens:
			lens.color = Color(1.0, 0.05, 0.05, 1.0)  # Bright red = disconnected (Issue #1532)

	# Force transition to COMBAT state
	if _parent and _parent.has_method("_transition_to_combat"):
		_parent._transition_to_combat()
	elif _parent and _parent.get("_current_state") != null:
		_parent._current_state = 1  # AIState.COMBAT

	# Set up MacheteComponent for bullet dodging (Issue #1540).
	# Reuses the same perpendicular-dodge logic as the machete enemy — no dash, just a lateral
	# sidestep when a bullet enters the threat sphere.
	_setup_dodge_component()

	phase_changed.emit(Phase.ACTIVE)
	FileLogger.info("[DroneOperator] Phase: ACTIVE (silenced pistol + laser, machete-style dodge)")


## Create and configure a MacheteComponent for bullet dodging in ACTIVE phase (Issue #1540).
func _setup_dodge_component() -> void:
	if _dodge_component != null:
		return  # Already set up
	_dodge_component = MacheteComponent.new()
	_dodge_component.name = "DodgeComponent"
	# Configure dodge parameters (same as machete defaults)
	_dodge_component.dodge_speed = 400.0
	_dodge_component.dodge_distance = 120.0
	_dodge_component.dodge_cooldown = 1.2
	_dodge_component.debug_logging = false
	add_child(_dodge_component)
	FileLogger.info("[DroneOperator] Dodge component set up (machete-style, speed=400, distance=120)")


## Create a laser sight Line2D on the weapon mount (Issue #1532).
func _setup_laser_sight() -> void:
	if _weapon_mount == null or _laser_sight != null:
		return
	_laser_sight = Line2D.new()
	_laser_sight.name = "LaserSight"
	_laser_sight.default_color = Color(1.0, 0.0, 0.0, 0.6)  # Red laser, semi-transparent
	_laser_sight.width = 1.0
	# Render BEHIND the weapon sprite and arm — z_as_relative=true means z_index is relative
	# to parent WeaponMount, so -2 puts it under the weapon/arm sprites (Issue #1532 fix #2)
	_laser_sight.z_as_relative = true
	_laser_sight.z_index = -2
	# Start from under the pistol body (not at the muzzle tip), extends forward
	_laser_sight.add_point(Vector2(0, 0))    # origin at weapon mount pivot
	_laser_sight.add_point(Vector2(180, 0))  # extends forward from under the barrel
	_weapon_mount.add_child(_laser_sight)
	FileLogger.info("[DroneOperator] Laser sight visual added to weapon mount (z_index=-2, under arm)")


## Update laser sight length each active frame (fade when suppressed).
func _update_laser_sight(_delta: float) -> void:
	if _laser_sight == null or not is_instance_valid(_laser_sight):
		return
	# Pulse the laser alpha slightly for a realistic effect
	var pulse: float = 0.5 + 0.15 * sin(Time.get_ticks_msec() * 0.006)
	_laser_sight.default_color = Color(1.0, 0.0, 0.0, pulse)


## ACTIVE phase: normal combat + bullet dodging (same as machete enemy).
func _update_active(delta: float) -> void:
	# Update laser sight pulse (Issue #1532)
	_update_laser_sight(delta)

	# Tick burst cooldown timer (Issue #1664)
	if _dodge_burst_cooldown_timer > 0.0:
		_dodge_burst_cooldown_timer -= delta
		if _dodge_burst_cooldown_timer <= 0.0:
			_dodge_burst_cooldown_timer = 0.0
			FileLogger.info("[DroneOperator] Dodge burst cooldown expired, ready to dodge again")

	# Update dodge component
	if _dodge_component != null:
		_dodge_component.update(delta)
