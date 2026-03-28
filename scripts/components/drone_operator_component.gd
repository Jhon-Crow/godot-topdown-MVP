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

## Number of dash charges for evasion (Issue #1397, restored from develop).
const DASH_CHARGES: int = 4

## Dash cooldown duration (same as player Dash).
const DASH_COOLDOWN: float = 1.2

## Dash duration per dash — longer than player for a visible aggressive lunge.
const DASH_DURATION: float = 0.2

## Dash speed multiplier — higher than player for a long closing dash.
const DASH_SPEED_MULTIPLIER: float = 6.0

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

## EnemyTeleportComponent used for evasion in ACTIVE phase (Issue #1664).
## Same teleport logic as the teleport enemy — teleport to cover on first bullet, etc.
var _teleport_component: EnemyTeleportComponent = null

## Dash state variables (Issue #1397, restored from develop).
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


## Returns true if the operator is currently dashing.
func is_dashing() -> bool:
	return _dash_active


## Returns the current dash velocity for use by enemy physics (Issue #1397).
func get_dash_velocity(base_speed: float) -> Vector2:
	return _dash_direction * base_speed * DASH_SPEED_MULTIPLIER


## Returns true if the operator should override suppression with a dash (Issue #1397).
## Only in ACTIVE phase when dash charges are available or currently dashing.
## When charges are spent and on cooldown, fall back to normal suppression.
func should_dash_instead_of_suppress() -> bool:
	if _phase != Phase.ACTIVE:
		return false
	if _dash_active:
		return true  # Stay in dash — suppress the suppression state
	if _dash_charges <= 0 and _dash_cooldown_timer > 0.0:
		return false  # All charges spent and cooling down — allow suppression
	return true


## Calculate dash direction and attempt to dash toward the player (Issue #1397).
## Called from enemy._update_suppression() when bullets are in threat sphere.
func try_dash_from_threat(bullets_in_sphere: Array, player: Node2D, enemy_pos: Vector2) -> void:
	if player == null:
		return
	var to_player: Vector2 = (player.global_position - enemy_pos).normalized()
	FileLogger.info("[DroneOperator] Aggressive dash toward player: dir=(%.2f, %.2f)" % [
		to_player.x, to_player.y
	])
	try_dash(to_player)


## Attempt to activate a dash in a given direction. Returns true if dash started.
func try_dash(direction: Vector2) -> bool:
	if _phase != Phase.ACTIVE:
		return false
	if _dash_active:
		return false
	if _dash_charges <= 0 and _dash_cooldown_timer > 0.0:
		return false
	if direction == Vector2.ZERO:
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
	if _parent and "velocity" in _parent:
		var base_speed: float = _parent.get("combat_move_speed") if _parent.get("combat_move_speed") else 320.0
		_parent.velocity = _dash_direction * base_speed * DASH_SPEED_MULTIPLIER
	FileLogger.info("[DroneOperator] Dash activated! Dir: (%.2f, %.2f), charges left: %d/%d" % [
		_dash_direction.x, _dash_direction.y, _dash_charges, DASH_CHARGES
	])
	_spawn_afterimage()
	return true


## Returns true if the teleport is ready (off cooldown). ACTIVE phase only.
func is_teleport_ready() -> bool:
	if _phase != Phase.ACTIVE or _teleport_component == null:
		return false
	return _teleport_component.is_ready()


## Try to teleport to target position. Delegates to EnemyTeleportComponent logic.
## Returns true if teleport succeeded.
func try_teleport(target: Vector2) -> bool:
	if _phase != Phase.ACTIVE or _teleport_component == null:
		return false
	return _teleport_component.try_teleport(target)


## Try immediate damage-triggered teleport (first bullet). Tries cover first, then flank.
## Returns true if teleport succeeded.
func try_damage_teleport(cover_position: Vector2, flank_target: Vector2) -> bool:
	if _phase != Phase.ACTIVE or _teleport_component == null:
		return false
	return _teleport_component.try_damage_teleport(cover_position, flank_target)


## Advance teleport cooldown. Call from enemy._physics_process() in ACTIVE phase.
func update_teleport(delta: float) -> void:
	if _teleport_component != null:
		_teleport_component.update(delta)


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

	# Set up EnemyTeleportComponent for evasion (Issue #1664).
	# Same teleport behavior as the teleport enemy — teleport to cover on first bullet, etc.
	_setup_teleport_component()

	phase_changed.emit(Phase.ACTIVE)
	FileLogger.info("[DroneOperator] Phase: ACTIVE (silenced pistol + laser, teleport evasion)")


## Create and configure an EnemyTeleportComponent for evasion in ACTIVE phase (Issue #1664).
func _setup_teleport_component() -> void:
	if _teleport_component != null:
		return  # Already set up
	_teleport_component = EnemyTeleportComponent.new()
	_teleport_component.name = "TeleportComponent"
	# IMPORTANT: must be added to _parent (CharacterBody2D), not self (Node).
	# EnemyTeleportComponent._ready() does get_parent() as CharacterBody2D — if the parent
	# is DroneOperatorComponent (a plain Node), the cast returns null and _ready_flag stays
	# false, making is_ready() always return false so teleport never fires (Issue #1664).
	if _parent != null:
		_parent.add_child(_teleport_component)
	else:
		add_child(_teleport_component)
	FileLogger.info("[DroneOperator] Teleport component set up (teleport evasion, Issue #1664)")


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


## ACTIVE phase: normal combat + dash evasion + teleport evasion (Issue #1397, #1664).
func _update_active(delta: float) -> void:
	# Update laser sight pulse (Issue #1532)
	_update_laser_sight(delta)

	# Advance teleport cooldown (Issue #1664)
	update_teleport(delta)

	# Update dash cooldown (Issue #1397)
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
			if _dash_charges > 0 and _dash_charges < DASH_CHARGES:
				_dash_charges = 0
			if _dash_charges <= 0 and _dash_cooldown_timer <= 0.0:
				_dash_cooldown_timer = DASH_COOLDOWN
				FileLogger.info("[DroneOperator] Dash chain window expired, cooldown started: %.1fs" % DASH_COOLDOWN)

	# Update active dash
	if _dash_active:
		_update_dash(delta)


## Update active dash state (Issue #1397).
func _update_dash(delta: float) -> void:
	_dash_timer -= delta
	_afterimage_timer += delta
	if _afterimage_timer >= _afterimage_interval:
		_afterimage_timer -= _afterimage_interval
		_spawn_afterimage()
	if _parent and "velocity" in _parent:
		var base_speed: float = _parent.get("combat_move_speed") if _parent.get("combat_move_speed") else 320.0
		_parent.velocity = _dash_direction * base_speed * DASH_SPEED_MULTIPLIER
	if _dash_timer <= 0.0:
		_end_dash()


## End the current dash.
func _end_dash() -> void:
	_dash_active = false
	_dash_timer = 0.0
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
	ghost_container.modulate = Color(1.0, 0.4, 0.1, AFTERIMAGE_ALPHA)  # Orange-red tint
	var parent_node: Node = _parent.get_parent()
	if parent_node == null:
		ghost_container.queue_free()
		return
	parent_node.add_child(ghost_container)
	var tween: Tween = ghost_container.create_tween()
	tween.tween_property(ghost_container, "modulate:a", 0.0, AFTERIMAGE_LIFETIME)
	tween.tween_callback(ghost_container.queue_free)
