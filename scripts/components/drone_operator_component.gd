class_name DroneOperatorComponent
extends Node
## Drone Operator (Дроновод) component for the enemy AI (Issue #1397).
##
## Behavior phases:
## 1. DEPLOYING: After spawn, seek nearest cover and deploy a drone.
## 2. CONTROLLING: While drone is alive, operator is defenseless (no movement, no vision).
## 3. ACTIVE: After drone is destroyed, pull out silenced pistol with laser sight
##    and act as a normal enemy.
##
## Special mechanic: When bullets enter the operator's threat sphere (ACTIVE phase only),
## instead of being suppressed, the operator performs a Dash (like the player's Dash item)
## to evade. Can perform 4 consecutive dashes, then cooldown (same as player Dash: 1.2s).

## Operator behavior phases.
enum Phase {
	DEPLOYING,    ## Seeking cover and deploying drone
	CONTROLLING,  ## Controlling the drone (defenseless)
	ACTIVE        ## Drone destroyed, fighting with pistol
}

## Number of dash charges for evasion.
const DASH_CHARGES: int = 4

## Dash cooldown duration (same as player Dash).
const DASH_COOLDOWN: float = 1.2

## Dash duration per dash (same as player Dash).
const DASH_DURATION: float = 0.15

## Dash speed multiplier (same as player Dash).
const DASH_SPEED_MULTIPLIER: float = 4.0

## Chain window for consecutive dashes.
const DASH_CHAIN_WINDOW: float = 0.4

## Number of afterimage ghosts per dash.
const AFTERIMAGE_COUNT: int = 4

## Afterimage lifetime.
const AFTERIMAGE_LIFETIME: float = 0.4

## Afterimage initial alpha.
const AFTERIMAGE_ALPHA: float = 0.7

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

## Dash state variables.
var _dash_charges: int = DASH_CHARGES
var _dash_cooldown_timer: float = 0.0
var _dash_active: bool = false
var _dash_timer: float = 0.0
var _dash_direction: Vector2 = Vector2.ZERO
var _dash_chain_timer: float = 0.0

## Afterimage spawn timer.
var _afterimage_timer: float = 0.0
var _afterimage_interval: float = 0.0

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
	_dash_charges = DASH_CHARGES
	_drone_deployed = false
	_reached_cover = false
	_deploy_timer = 0.0
	_cover_seek_timer = 0.0
	_setup_vr_headset_visual()
	_setup_tablet_visual()
	_hide_weapon_show_tablet()
	FileLogger.info("[DroneOperator] Setup complete (dash_charges=%d, cooldown=%.1fs)" % [DASH_CHARGES, DASH_COOLDOWN])


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


## Returns true if the operator is currently dashing (immune to damage).
func is_dashing() -> bool:
	return _dash_active


## Returns true if the operator is in the defenseless controlling phase.
func is_controlling_drone() -> bool:
	return _phase == Phase.CONTROLLING


## Returns true if the operator should override suppression with dash.
## Only in ACTIVE phase when bullets are in threat sphere.
func should_dash_instead_of_suppress() -> bool:
	return _phase == Phase.ACTIVE and not _dash_active


## Calculate dash direction from threat and attempt to dash.
## Called from enemy._update_suppression() when bullets are in threat sphere.
func try_dash_from_threat(bullets_in_sphere: Array, player: Node2D, enemy_pos: Vector2) -> void:
	var dash_dir := Vector2.ZERO
	if not bullets_in_sphere.is_empty():
		var bullet = bullets_in_sphere[0]
		if is_instance_valid(bullet) and "velocity" in bullet:
			dash_dir = -bullet.velocity.normalized().rotated(PI / 4.0 * (1 if randf() > 0.5 else -1))
	if dash_dir == Vector2.ZERO and player:
		dash_dir = (enemy_pos - player.global_position).normalized()
	try_dash(dash_dir)


## Attempt to activate a dash in a given direction (called when bullets enter threat sphere).
## Returns true if dash started successfully.
func try_dash(direction: Vector2) -> bool:
	if _phase != Phase.ACTIVE:
		return false
	if _dash_active:
		return false
	if _dash_charges <= 0 and _dash_cooldown_timer > 0.0:
		return false

	if direction == Vector2.ZERO:
		# Dash away from the nearest bullet direction
		if _parent:
			direction = Vector2.RIGHT.rotated(_parent.rotation + PI)
		else:
			return false

	_dash_direction = direction.normalized()
	_dash_active = true
	_dash_timer = DASH_DURATION
	_dash_chain_timer = 0.0
	_afterimage_timer = 0.0
	_afterimage_interval = DASH_DURATION / float(AFTERIMAGE_COUNT) if AFTERIMAGE_COUNT > 0 else DASH_DURATION

	_dash_charges -= 1

	# Apply dash velocity
	if _parent and "velocity" in _parent:
		var base_speed: float = _parent.get("combat_move_speed") if _parent.get("combat_move_speed") else 320.0
		_parent.velocity = _dash_direction * base_speed * DASH_SPEED_MULTIPLIER

	FileLogger.info("[DroneOperator] Dash activated! Dir: (%.2f, %.2f), charges left: %d/%d" % [
		_dash_direction.x, _dash_direction.y, _dash_charges, DASH_CHARGES
	])

	# Spawn first afterimage immediately
	_spawn_afterimage()

	return true


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


## Transition to ACTIVE phase with silenced pistol.
func _transition_to_active() -> void:
	_phase = Phase.ACTIVE
	_dash_charges = DASH_CHARGES
	_dash_cooldown_timer = 0.0

	# Show weapon, hide tablet
	_show_weapon_hide_tablet()

	# Switch weapon to PM (type 5) — closest to silenced pistol with laser
	if _parent and _parent.has_method("switch_weapon"):
		_parent.switch_weapon(5)  # PM = WeaponType 5
	elif _parent and _parent.get("weapon_type") != null:
		_parent.set("weapon_type", 5)
		if _parent.has_method("_configure_weapon_type"):
			_parent._configure_weapon_type()
		if _parent.has_method("_initialize_ammo"):
			_parent._initialize_ammo()

	# Change VR headset lens to red = disconnected
	if _vr_headset:
		var lens: Polygon2D = _vr_headset.get_node_or_null("Lens") as Polygon2D
		if lens:
			lens.color = Color(0.8, 0.1, 0.1, 0.6)  # Red = disconnected

	# Force transition to COMBAT state
	if _parent and _parent.has_method("_transition_to_combat"):
		_parent._transition_to_combat()
	elif _parent and _parent.get("_current_state") != null:
		_parent._current_state = 1  # AIState.COMBAT

	phase_changed.emit(Phase.ACTIVE)
	FileLogger.info("[DroneOperator] Phase: ACTIVE (pistol drawn, dash evasion enabled)")


## ACTIVE phase: normal combat + dash evasion instead of suppression.
func _update_active(delta: float) -> void:
	# Update dash cooldown
	if _dash_cooldown_timer > 0.0:
		_dash_cooldown_timer -= delta
		if _dash_cooldown_timer <= 0.0:
			_dash_cooldown_timer = 0.0
			_dash_charges = DASH_CHARGES
			FileLogger.info("[DroneOperator] Dash cooldown finished, charges restored: %d" % DASH_CHARGES)

	# Update chain window timer
	if not _dash_active and _dash_chain_timer > 0.0:
		_dash_chain_timer -= delta
		if _dash_chain_timer <= 0.0:
			_dash_chain_timer = 0.0
			# Chain window expired — start cooldown if charges remain
			if _dash_charges > 0 and _dash_charges < DASH_CHARGES:
				_dash_charges = 0
			if _dash_charges <= 0 and _dash_cooldown_timer <= 0.0:
				_dash_cooldown_timer = DASH_COOLDOWN
				FileLogger.info("[DroneOperator] Dash chain window expired, cooldown started: %.1fs" % DASH_COOLDOWN)

	# Update active dash
	if _dash_active:
		_update_dash(delta)


## Update active dash state.
func _update_dash(delta: float) -> void:
	_dash_timer -= delta

	# Spawn afterimages at intervals
	_afterimage_timer += delta
	if _afterimage_timer >= _afterimage_interval:
		_afterimage_timer -= _afterimage_interval
		_spawn_afterimage()

	# Maintain dash velocity
	if _parent and "velocity" in _parent:
		var base_speed: float = _parent.get("combat_move_speed") if _parent.get("combat_move_speed") else 320.0
		_parent.velocity = _dash_direction * base_speed * DASH_SPEED_MULTIPLIER

	# End dash when timer expires
	if _dash_timer <= 0.0:
		_end_dash()


## End the current dash.
func _end_dash() -> void:
	_dash_active = false
	_dash_timer = 0.0

	# Reduce velocity smoothly
	if _parent and "velocity" in _parent:
		var base_speed: float = _parent.get("combat_move_speed") if _parent.get("combat_move_speed") else 320.0
		_parent.velocity = _dash_direction * base_speed * 0.5

	if _dash_charges <= 0:
		_dash_cooldown_timer = DASH_COOLDOWN
		FileLogger.info("[DroneOperator] Dash ended (all charges spent). Cooldown: %.1fs" % DASH_COOLDOWN)
	else:
		_dash_chain_timer = DASH_CHAIN_WINDOW
		FileLogger.info("[DroneOperator] Dash ended. %d charges left, chain window: %.1fs" % [_dash_charges, DASH_CHAIN_WINDOW])


## Spawn an afterimage at the operator's current position.
func _spawn_afterimage() -> void:
	if _parent == null or not is_instance_valid(_parent):
		return

	var model: Node2D = _parent.get_node_or_null("EnemyModel") as Node2D
	if model == null:
		return

	var ghost_container := Node2D.new()
	ghost_container.global_position = _parent.global_position
	ghost_container.z_index = _parent.z_index

	var sprites_added: int = 0
	for child in model.get_children():
		if child is Sprite2D and child.visible:
			var ghost_sprite := Sprite2D.new()
			ghost_sprite.texture = child.texture
			ghost_sprite.position = child.position
			ghost_sprite.rotation = child.rotation
			ghost_sprite.scale = child.scale
			ghost_sprite.flip_h = child.flip_h
			ghost_sprite.flip_v = child.flip_v
			ghost_sprite.offset = child.offset
			ghost_sprite.hframes = child.hframes
			ghost_sprite.vframes = child.vframes
			ghost_sprite.frame = child.frame
			ghost_sprite.region_enabled = child.region_enabled
			if child.region_enabled:
				ghost_sprite.region_rect = child.region_rect
			ghost_container.add_child(ghost_sprite)
			sprites_added += 1

	if sprites_added == 0:
		ghost_container.queue_free()
		return

	ghost_container.rotation = model.global_rotation

	# Orange-red tint for drone operator dash trail (distinct from player's cyan-blue)
	ghost_container.modulate = Color(1.0, 0.4, 0.1, AFTERIMAGE_ALPHA)

	var parent_node: Node = _parent.get_parent()
	if parent_node == null:
		ghost_container.queue_free()
		return
	parent_node.add_child(ghost_container)

	var tween: Tween = ghost_container.create_tween()
	tween.tween_property(ghost_container, "modulate:a", 0.0, AFTERIMAGE_LIFETIME)
	tween.tween_callback(ghost_container.queue_free)
