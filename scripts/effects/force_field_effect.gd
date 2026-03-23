extends Node2D
## Force field effect controller (Issue #676, #906, #912, #930, #932).
##
## Creates a glowing energy bubble shield around the player that traps projectiles.
## Activated by holding Space key with a depletable 8-second charge.
##
## Gameplay rules:
## - Hold Space to activate, release to deactivate
## - 8 second total charge (usable in portions: 8×1s, 2×4s, etc.)
## - 100% projectile trapping (bullets, shrapnel stop on contact)
## - Trapped bullets snap to and stay on the field boundary ring (Issue #932)
## - Trapped bullets scatter outward when field deactivates (Issue #932)
## - Frag grenades bounce WITHOUT detonating on contact
## - Full damage protection while active
## - Visual warning when charge is low (last 2 seconds)

## Maximum charge duration in seconds.
const MAX_CHARGE: float = 8.0

## Radius of the force field protection area (pixels).
## Player collision radius is 16px; field should be slightly larger.
const FIELD_RADIUS: float = 35.0

## Shield visual scale.
## Texture is 256x256 (128px radius at scale 1.0).
## At 0.28 scale the visible radius ≈ 36px, just slightly bigger than the player.
const SHIELD_SCALE: float = 0.28

## Reflection velocity boost multiplier for grenades.
const GRENADE_REFLECTION_BOOST: float = 1.2

## Duration to disable grenade impact detection after bounce (seconds).
const GRENADE_BOUNCE_IMMUNITY_TIME: float = 0.15

## Low charge warning threshold (seconds).
const LOW_CHARGE_WARNING: float = 2.0

## Flash frequency when charge is low (Hz).
const WARNING_FLASH_FREQUENCY: float = 3.0

## Speed at which trapped bullets are released when field deactivates (pixels/sec).
const BULLET_RELEASE_SPEED: float = 800.0

## Speed at which trapped shrapnel is released when field deactivates (pixels/sec).
const SHRAPNEL_RELEASE_SPEED: float = 600.0

## Path to the force field shader.
const SHADER_PATH: String = "res://scripts/shaders/force_field.gdshader"

## Remaining charge in seconds.
var remaining_charge: float = MAX_CHARGE

## Whether this force field is owned by the player (true) or an enemy (false).
## When false, the field traps player projectiles and ignores enemy projectiles.
## Set to false by EnemyForceFieldComponent after instantiation (Issue #1034).
var owner_is_player: bool = true

## Whether the force field is currently active.
var is_active: bool = false

## Reference to the visual shield sprite (Sprite2D or similar).
var _shield_sprite: Sprite2D = null

## Reference to the Area2D for projectile detection.
var _area2d: Area2D = null

## Reference to the CollisionShape2D.
var _collision_shape: CollisionShape2D = null

## Shader material for the glowing effect.
var _shader_material: ShaderMaterial = null

## Warning flash timer.
var _warning_flash_timer: float = 0.0

## Array of trapped bullets (Area2D nodes with physics process disabled).
var _trapped_bullets: Array = []

## Array of trapped shrapnel (Area2D nodes with physics process disabled).
var _trapped_shrapnel: Array = []

## Maps trapped projectile → boundary angle (radians) from field center.
## Used to keep trapped projectiles glued to the field boundary ring as the player moves.
var _trapped_boundary_angles: Dictionary = {}

## Signal emitted when force field is activated.
signal force_field_activated()

## Signal emitted when force field is deactivated.
signal force_field_deactivated()

## Signal emitted when charge changes.
signal charge_changed(current: float, maximum: float)

## Signal emitted when charge is depleted.
signal charge_depleted()


func _ready() -> void:
	_setup_area2d()
	_setup_shield_visual()
	_set_field_active(false)
	FileLogger.info("[ForceFieldEffect] Initialized with %.1fs charge" % MAX_CHARGE)


## Set up the Area2D for projectile detection.
func _setup_area2d() -> void:
	_area2d = Area2D.new()
	_area2d.name = "ForceFieldArea"
	_area2d.collision_layer = 0   # Don't register on any layer
	# Layer 5 (value 16) = "projectiles" — bullets and shrapnel (Area2D)
	# Layer 6 (value 32) = "targets"    — grenades (RigidBody2D, collision_layer=32)
	_area2d.collision_mask = 16 | 32  # = 48
	add_child(_area2d)

	# Create circular collision shape
	var shape := CircleShape2D.new()
	shape.radius = FIELD_RADIUS
	_collision_shape = CollisionShape2D.new()
	_collision_shape.shape = shape
	_area2d.add_child(_collision_shape)

	# Connect area entered signal for projectile trapping (bullets, shrapnel — Area2D)
	_area2d.area_entered.connect(_on_projectile_entered)

	# Connect body entered signal for grenade reflection (grenades are RigidBody2D)
	_area2d.body_entered.connect(_on_body_entered)

	FileLogger.info("[ForceFieldEffect] Area2D setup with radius %.0fpx" % FIELD_RADIUS)


## Set up the shield visual (bubble sprite with translucent-fill texture).
## Uses a programmatic bubble texture as the primary visual so it works in exported
## games without relying on runtime shader compilation.
## The shader is applied as an optional enhancement for animated pulse/shimmer effects.
## The base texture already shows a true bubble (semi-transparent interior + glowing rim)
## matching the force bubble look required by Issue #930.
func _setup_shield_visual() -> void:
	_shield_sprite = Sprite2D.new()
	_shield_sprite.name = "ShieldVisual"
	_shield_sprite.scale = Vector2(SHIELD_SCALE, SHIELD_SCALE)
	_shield_sprite.z_index = 10  # Draw above player
	add_child(_shield_sprite)

	# Always use the bubble texture as the primary visual.
	# This works reliably in both editor and exported games (no shader compilation needed).
	# The bubble texture has a semi-transparent interior (frosted-glass look) + bright glowing
	# rim — matching the "force bubble" aesthetic required by Issues #906 and #930.
	_shield_sprite.texture = _create_ring_texture()

	# Optionally load and apply shader as enhancement (e.g. pulse animation, iridescence).
	# If the shader fails to load, the ring texture still provides correct bubble look.
	if ResourceLoader.exists(SHADER_PATH):
		var shader = load(SHADER_PATH)
		if shader:
			_shader_material = ShaderMaterial.new()
			_shader_material.shader = shader
			_shield_sprite.material = _shader_material
			FileLogger.info("[ForceFieldEffect] Shader loaded successfully (ring texture used as base)")
		else:
			FileLogger.info("[ForceFieldEffect] WARNING: Failed to load shader — ring texture only")
	else:
		FileLogger.info("[ForceFieldEffect] WARNING: Shader not found: %s — ring texture only" % SHADER_PATH)


## Create a plain white 256x256 texture.
## The shader controls all colors/alpha — the texture just provides UV coordinates.
func _create_white_texture() -> ImageTexture:
	var image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 1.0))
	return ImageTexture.create_from_image(image)


## Create a bubble texture — translucent interior + bright glowing rim (Issue #930).
## Used as the primary visual so the force field looks like a force bubble
## (not just a ring outline) even without shader support in exported games.
##
## The texture has:
## - Transparent exterior (outside the circle)
## - Semi-transparent interior fill (alpha ~0.15) for frosted-glass bubble look
## - Bright blue rim at ~84–100% radius (bell curve alpha, peak ~0.9)
func _create_ring_texture() -> ImageTexture:
	var size := 256
	var center := Vector2(size * 0.5, size * 0.5)
	var outer_r := size * 0.5        # 128px
	var rim_start := outer_r * 0.84  # inner edge of bright rim
	var fill_color := Color(0.4, 0.7, 1.0)  # Base blue color

	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)

	for y in range(size):
		for x in range(size):
			var dist := Vector2(x, y).distance_to(center)
			if dist > outer_r:
				# Outside the circle — fully transparent
				image.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
			elif dist >= rim_start:
				# Bright rim: bell curve alpha, peak 0.9
				var t := (dist - rim_start) / (outer_r - rim_start)  # 0→1
				var alpha := sin(t * PI) * 0.9
				image.set_pixel(x, y, Color(fill_color.r, fill_color.g, fill_color.b, alpha))
			else:
				# Interior fill: soft translucent bubble interior (Issue #930)
				# Alpha ramps up from 0 at center to ~0.15 near the rim, like frosted glass.
				var r := dist / outer_r  # normalized 0→1
				var alpha := pow(r, 1.5) * 0.15
				image.set_pixel(x, y, Color(fill_color.r, fill_color.g, fill_color.b, alpha))

	return ImageTexture.create_from_image(image)


## Activate the force field.
func activate() -> bool:
	if is_active:
		return false  # Already active

	if remaining_charge <= 0.0:
		FileLogger.info("[ForceFieldEffect] No charge remaining")
		return false

	is_active = true
	_set_field_active(true)
	FileLogger.info("[ForceFieldEffect] Activated! Charge: %.1fs/%.1fs" % [remaining_charge, MAX_CHARGE])
	force_field_activated.emit()
	return true


## Deactivate the force field and release any trapped bullets.
func deactivate() -> void:
	if not is_active:
		return

	is_active = false
	_set_field_active(false)

	# Release all trapped projectiles outward
	_release_trapped_projectiles()

	FileLogger.info("[ForceFieldEffect] Deactivated. Charge remaining: %.1fs" % remaining_charge)
	force_field_deactivated.emit()


## Set the force field visual and collision active state.
func _set_field_active(active: bool) -> void:
	if _shield_sprite:
		_shield_sprite.visible = active
	if _collision_shape:
		_collision_shape.disabled = not active


func _process(delta: float) -> void:
	if not is_active:
		return

	# Deplete charge while active
	remaining_charge -= delta
	if remaining_charge <= 0.0:
		remaining_charge = 0.0
		deactivate()
		charge_depleted.emit()
		FileLogger.info("[ForceFieldEffect] Charge depleted")

	charge_changed.emit(remaining_charge, MAX_CHARGE)

	# Visual warning when charge is low
	if remaining_charge <= LOW_CHARGE_WARNING:
		_warning_flash_timer += delta
		var flash_period = 1.0 / WARNING_FLASH_FREQUENCY
		var flash_on = fmod(_warning_flash_timer, flash_period) < (flash_period * 0.5)
		if _shield_sprite:
			_shield_sprite.modulate.a = 1.0 if flash_on else 0.5

	# Keep trapped projectiles glued to the field boundary as the player moves (Issue #932).
	# The force field node moves with the player, so we update each trapped projectile's
	# global_position every frame to stay on the boundary ring.
	_update_trapped_positions()


## Update global positions of all trapped projectiles to keep them on the boundary ring.
## Called every frame while the field is active so projectiles follow the player (Issue #932).
func _update_trapped_positions() -> void:
	for projectile in _trapped_bullets:
		if is_instance_valid(projectile) and projectile in _trapped_boundary_angles:
			var angle: float = _trapped_boundary_angles[projectile]
			projectile.global_position = global_position + Vector2(cos(angle), sin(angle)) * FIELD_RADIUS
	for projectile in _trapped_shrapnel:
		if is_instance_valid(projectile) and projectile in _trapped_boundary_angles:
			var angle: float = _trapped_boundary_angles[projectile]
			projectile.global_position = global_position + Vector2(cos(angle), sin(angle)) * FIELD_RADIUS


## Check if the player is currently protected by the force field.
func is_protecting() -> bool:
	return is_active


## Get the remaining charge in seconds.
func get_remaining_charge() -> float:
	return remaining_charge


## Handle projectile entering the force field area.
## In Godot 4 bullets and shrapnel are Area2D nodes themselves, so `area` IS the projectile.
## Grenades are RigidBody2D and appear via body_entered instead (handled separately).
##
## IMPORTANT (Issue #912): C# bullets call QueueFree() in their own OnAreaEntered handler.
## The IsForceFieldArea() check in Bullet.cs and ShotgunPellet.cs prevents this when the
## force field area is detected — but only when the project is built from source (not a
## pre-compiled .exe). Without that C# fix, the bullet gets queued-for-free in the same
## physics frame and is removed at frame end even if we successfully disable its processing.
func _on_projectile_entered(area: Area2D) -> void:
	if not is_active:
		return

	if not is_instance_valid(area):
		return

	# Bullets and shrapnel are Area2D nodes; the area itself is the projectile.
	# Identify by script name since groups are not set via scene files.
	var script = area.get_script()
	if script == null:
		FileLogger.info("[ForceFieldEffect] Area entered but has no script: %s" % area.name)
		return

	var script_path: String = script.resource_path
	FileLogger.info("[ForceFieldEffect] Area entered: %s (script: %s)" % [area.name, script_path])

	# Identify projectile type by script path.
	# Bullets: bullet.gd  or Bullet.cs
	# Shotgun pellets: ShotgunPellet.cs — trapped same as bullets (have direction/speed)
	# Shrapnel: shrapnel.gd, BreakerShrapnel.gd
	var lower_path := script_path.to_lower()
	if "bullet" in lower_path or "shotgunpellet" in lower_path or "pellet" in lower_path:
		_trap_bullet(area)
		# Deferred validity check: if the bullet was freed by C# OnAreaEntered in the same
		# frame (pre-compiled .exe without IsForceFieldArea fix), log a diagnostic message.
		# This confirms whether C# rebuild is needed.
		_check_trapped_bullet_validity.call_deferred(area)
	elif "shrapnel" in lower_path:
		_trap_shrapnel(area)
	else:
		FileLogger.info("[ForceFieldEffect] Unknown projectile type, script path: %s" % script_path)


## Deferred validity check after trapping a bullet.
## Logs whether the bullet survived the trap attempt (i.e., C# did not call QueueFree).
## DIAGNOSTIC: If this logs "freed by C#", rebuild the project from source to apply the
## IsForceFieldArea() fix in Bullet.cs / ShotgunPellet.cs (Issue #912).
func _check_trapped_bullet_validity(bullet: Area2D) -> void:
	if not is_instance_valid(bullet):
		FileLogger.info("[ForceFieldEffect] DIAGNOSTIC: Bullet was freed by C# after trap attempt — rebuild from source to apply Issue #912 fix (Bullet.cs IsForceFieldArea check)")
	else:
		FileLogger.info("[ForceFieldEffect] DIAGNOSTIC: Bullet survived trap — C# fix is active")


## Handle grenade (RigidBody2D) entering the force field area.
func _on_body_entered(body: Node2D) -> void:
	if not is_active:
		return

	if not is_instance_valid(body):
		return

	# Only handle grenades (RigidBody2D projectiles)
	if body is RigidBody2D:
		var script = body.get_script()
		if script == null:
			return
		var script_path: String = script.resource_path
		if "grenade" in script_path.to_lower():
			_reflect_grenade(body)


# ===========================================================================
# C#/GDScript-compatible property helpers (Issue #932)
#
# Problem: GDScript .get("direction") works for:
#   - GDScript variables ("direction" snake_case var in bullet.gd)
#   - Properties explicitly written with Set("direction", ...) from C#
# But NOT for C# [Export] properties set via direct C# property assignment
#   (e.g. csBullet.Direction = v in BaseWeapon.cs), which are stored under
#   the PascalCase name and require .get("Direction").
#
# Solution: try snake_case first (GDScript), fall back to PascalCase (C#).
# This is the same pattern used in enemy.gd _spawn_projectile().
# ===========================================================================

## Read the direction property from a projectile.
## Tries "direction" (GDScript bullets / pellets set via Set()) first,
## then "Direction" (C# Bullet/ShotgunPellet set via direct C# property assignment).
func _get_direction(projectile: Node2D):
	var d = projectile.get("direction")
	if d != null:
		return d
	return projectile.get("Direction")


## Read the speed property from a projectile (snake_case → PascalCase fallback).
func _get_speed(projectile: Node2D):
	var s = projectile.get("speed")
	if s != null:
		return s
	return projectile.get("Speed")


## Read the shooter ID from a projectile (snake_case → PascalCase → source_id fallback).
## GDScript bullets: "shooter_id" (snake_case int var, default -1)
## C# Bullet/ShotgunPellet: "ShooterId" (PascalCase ulong [Export], default 0)
## Shrapnel: "source_id" (snake_case int var)
func _get_shooter_id(projectile: Node2D):
	var id = projectile.get("shooter_id")
	if id != null:
		return id
	id = projectile.get("ShooterId")
	if id != null:
		return id
	return projectile.get("source_id")


## Clear the tracer trail of a trapped projectile to remove the frozen-tail artifact (Issue #982).
##
## When a bullet or shrapnel is frozen by the force field its _physics_process stops,
## so _update_trail() / _update_smoky_trail() are never called again.  The Line2D child
## node (top_level=true) keeps the last world-space points that were recorded, leaving
## a visible "tail" hanging in space at the bullet's stopping position.
##
## Supports both GDScript projectiles (snake_case "_trail", "_position_history") and
## C# projectiles (PascalCase "_trail" or "Trail" child node).
func _clear_projectile_trail(projectile: Node2D) -> void:
	# Try GDScript-style: read "_position_history" array and clear it.
	var history = projectile.get("_position_history")
	if history != null:
		projectile.set("_position_history", [])

	# Try GDScript-style: read "_trail" node reference and clear its points.
	var trail_node = projectile.get("_trail")
	if trail_node != null and trail_node is Line2D:
		(trail_node as Line2D).clear_points()
		return

	# Fallback: look for a child node named "Trail" (works for both GDScript and C# scenes).
	var trail_child: Node = projectile.get_node_or_null("Trail")
	if trail_child != null and trail_child is Line2D:
		(trail_child as Line2D).clear_points()


## Snap a projectile to the force field boundary ring and record its boundary angle.
## Moves the projectile to the surface of the field (at FIELD_RADIUS distance from center)
## so that all trapped projectiles visually hover at the field edge — like time stopped.
## The boundary angle is stored in _trapped_boundary_angles so _process() can keep the
## projectile glued to the boundary ring even as the player (and field) moves.
func _snap_to_boundary(projectile: Node2D) -> void:
	var from_center := projectile.global_position - global_position
	var direction_to_proj := from_center.normalized()
	# If projectile is at or very near center, use its travel direction as placement direction.
	# Use _get_direction() for C#/GDScript-compatible property read (Issue #932).
	if from_center.length_squared() < 1.0:
		var proj_dir = _get_direction(projectile)
		if proj_dir != null:
			direction_to_proj = (proj_dir as Vector2).normalized()
	# Place at boundary ring
	projectile.global_position = global_position + direction_to_proj * FIELD_RADIUS
	# Store boundary angle for continuous tracking in _process()
	_trapped_boundary_angles[projectile] = direction_to_proj.angle()


## Check if a projectile was fired by the player (issue #932).
## The force field should only trap ENEMY bullets, not the player's own projectiles.
## Uses _get_shooter_id() to look up the shooter node and checks group membership —
## the same strategy used in bullet.gd _is_player_bullet().
## Returns true if the projectile was fired by the player and should NOT be trapped.
func _is_player_projectile(projectile: Node2D) -> bool:
	# Read shooter ID with C#/GDScript-compatible helper (Issue #932):
	# GDScript bullets: "shooter_id" (snake_case, default -1)
	# C# Bullet/ShotgunPellet: "ShooterId" (PascalCase [Export], default 0)
	# Shrapnel: "source_id" (snake_case)
	var raw_shooter_id = _get_shooter_id(projectile)

	if raw_shooter_id == null:
		return false  # No shooter info — assume enemy, allow trapping

	# GDScript bullets default to -1 when no shooter is set; C# bullets default to 0.
	var shooter_id_int: int = int(raw_shooter_id)
	if shooter_id_int <= 0:
		return false  # No valid shooter — assume enemy, allow trapping

	# Look up the shooter node by instance ID
	var shooter: Object = instance_from_id(shooter_id_int)
	if shooter == null or not shooter is Node:
		return false  # Shooter no longer in scene — allow trapping

	# Check group membership: player nodes are in the "player" group (set in Player.tscn).
	# This works for both C# Player and GDScript players.
	return (shooter as Node).is_in_group("player")


## Trap a bullet in the force field — stop its movement and snap it to the field boundary.
## The bullet is stored in _trapped_bullets and will be released when the field deactivates.
func _trap_bullet(bullet: Node2D) -> void:
	# Use _get_direction()/_get_speed() to check property existence — handles BOTH:
	#   GDScript bullets: "direction"/"speed" (snake_case vars)
	#   C# Bullet/ShotgunPellet: "Direction"/"Speed" (PascalCase [Export] set via direct C# assignment)
	# The old .get("direction") ONLY worked for GDScript bullets; C# bullets required .get("Direction").
	# See Issue #932 for full root-cause analysis.
	var bullet_dir = _get_direction(bullet)
	var bullet_spd = _get_speed(bullet)
	var has_direction := bullet_dir != null
	var has_speed := bullet_spd != null
	if not has_direction or not has_speed:
		FileLogger.info("[ForceFieldEffect] Bullet missing properties — has_direction=%s has_speed=%s class=%s — skipping trap" % [
			has_direction, has_speed, bullet.get_class()])
		return

	# Skip bullets that belong to the same team as the force field owner (Issue #1034).
	# Player force field (owner_is_player=true): skip player bullets, trap enemy bullets.
	# Enemy force field (owner_is_player=false): skip enemy bullets, trap player bullets.
	var is_player_proj := _is_player_projectile(bullet)
	var same_team := (owner_is_player and is_player_proj) or (not owner_is_player and not is_player_proj)
	if same_team:
		FileLogger.info("[ForceFieldEffect] Skipping same-team bullet (owner_is_player=%s, class=%s)" % [owner_is_player, bullet.get_class()])
		return

	# Already trapped? Skip.
	if bullet in _trapped_bullets:
		return

	# Freeze bullet movement by disabling its physics process.
	# For GDScript bullets: stops _physics_process (direction*speed*delta movement).
	# For C# bullets: stops _PhysicsProcess (Direction*Speed*(float)delta movement).
	bullet.set_physics_process(false)
	bullet.set_process(false)

	# Clear the tracer trail so it does not remain as a visual artifact (Issue #982).
	# The trail Line2D uses top_level=true and stores absolute world positions.
	# When physics stops, _update_trail() is no longer called, leaving the last
	# drawn trail frozen at the stopping point. Clearing trail + history fixes this.
	_clear_projectile_trail(bullet)

	# Snap to field boundary so bullets visually stick to the edge of the shield
	# (like time stopped — bullets frozen at the field boundary ring, Issue #932).
	_snap_to_boundary(bullet)

	# Make bullet dimly visible to show it's trapped
	if bullet is CanvasItem:
		(bullet as CanvasItem).modulate = Color(0.6, 0.8, 1.0, 0.7)

	# Reset shooter ID so released bullet can damage anyone (not just enemies).
	# Try snake_case first (GDScript), then PascalCase (C#) for compatible write.
	if bullet.get("shooter_id") != null:
		bullet.set("shooter_id", -1)
	elif bullet.get("ShooterId") != null:
		bullet.set("ShooterId", 0)

	_trapped_bullets.append(bullet)

	FileLogger.info("[ForceFieldEffect] Bullet trapped at boundary (class=%s). Total trapped: %d" % [
		bullet.get_class(), _trapped_bullets.size()])


## Trap shrapnel in the force field — stop its movement and snap it to the field boundary.
func _trap_shrapnel(shrapnel: Node2D) -> void:
	# Use _get_direction() for C#/GDScript-compatible property check (Issue #932).
	if _get_direction(shrapnel) == null:
		return

	# Skip shrapnel from the same team as the force field owner (Issue #1034).
	# Same logic as bullets: player field skips player shrapnel, enemy field skips enemy shrapnel.
	var is_player_proj := _is_player_projectile(shrapnel)
	var same_team := (owner_is_player and is_player_proj) or (not owner_is_player and not is_player_proj)
	if same_team:
		FileLogger.info("[ForceFieldEffect] Skipping same-team shrapnel (owner_is_player=%s, class=%s)" % [owner_is_player, shrapnel.get_class()])
		return

	# Already trapped? Skip.
	if shrapnel in _trapped_shrapnel:
		return

	# Freeze shrapnel movement
	shrapnel.set_physics_process(false)
	shrapnel.set_process(false)

	# Clear the tracer trail so it does not remain as a visual artifact (Issue #982).
	# Same fix as for bullets: the trail Line2D keeps world-space points from
	# _update_trail() / _update_smoky_trail() after physics is stopped, leaving
	# a frozen "tail" at the stopping position. Clearing it removes this artifact.
	_clear_projectile_trail(shrapnel)

	# Snap to field boundary so shrapnel visually sticks to the edge of the shield
	# (like time stopped — shrapnel frozen at the field boundary ring, Issue #932).
	_snap_to_boundary(shrapnel)

	# Make shrapnel dimly visible to show it's trapped
	if shrapnel is CanvasItem:
		(shrapnel as CanvasItem).modulate = Color(0.6, 0.8, 1.0, 0.7)

	# Reset source ID so released shrapnel can damage anyone
	if shrapnel.get("source_id") != null:
		shrapnel.set("source_id", -1)

	_trapped_shrapnel.append(shrapnel)

	FileLogger.info("[ForceFieldEffect] Shrapnel trapped at boundary. Total trapped: %d" % _trapped_shrapnel.size())


## Release all trapped projectiles outward when the force field deactivates.
## Each bullet/shrapnel flies away from the player's position.
func _release_trapped_projectiles() -> void:
	var total_released := 0

	# Release trapped bullets
	for bullet in _trapped_bullets:
		if not is_instance_valid(bullet):
			continue
		_release_projectile(bullet, BULLET_RELEASE_SPEED)
		total_released += 1

	# Release trapped shrapnel
	for shrapnel in _trapped_shrapnel:
		if not is_instance_valid(shrapnel):
			continue
		_release_projectile(shrapnel, SHRAPNEL_RELEASE_SPEED)
		total_released += 1

	_trapped_bullets.clear()
	_trapped_shrapnel.clear()
	_trapped_boundary_angles.clear()

	FileLogger.info("[ForceFieldEffect] Released %d trapped projectiles" % total_released)


## Release a single trapped projectile outward from the force field center.
## @param projectile: The trapped bullet or shrapnel node.
## @param release_speed: Speed to give the projectile when released.
func _release_projectile(projectile: Node2D, release_speed: float) -> void:
	# Use stored boundary angle for reliable outward direction (Issue #932).
	# Since bullets are kept at the boundary ring, from_center is also reliable,
	# but the stored angle avoids floating-point drift from _update_trapped_positions.
	var outward_dir: Vector2
	if projectile in _trapped_boundary_angles:
		var angle: float = _trapped_boundary_angles[projectile]
		outward_dir = Vector2(cos(angle), sin(angle))
	else:
		# Fallback: compute from current position
		var from_center := projectile.global_position - global_position
		outward_dir = from_center.normalized()
		# If projectile is at center (unlikely), pick a random direction
		if from_center.length_squared() < 1.0:
			var random_angle := randf_range(0.0, TAU)
			outward_dir = Vector2(cos(random_angle), sin(random_angle))

	# Set new direction and speed — use _get_direction()/_get_speed() for C#/GDScript compatibility.
	# For writing: try snake_case first (GDScript), fall back to PascalCase (C#).
	if projectile.get("direction") != null:
		projectile.set("direction", outward_dir)
	elif projectile.get("Direction") != null:
		projectile.set("Direction", outward_dir)
	if projectile.get("speed") != null:
		projectile.set("speed", release_speed)
	elif projectile.get("Speed") != null:
		projectile.set("Speed", release_speed)

	# Restore normal color
	if projectile is CanvasItem:
		(projectile as CanvasItem).modulate = Color(1.0, 1.0, 1.0, 1.0)

	# Re-enable physics and processing
	projectile.set_physics_process(true)
	projectile.set_process(true)

	# Update rotation to match new direction
	if projectile.has_method("_update_rotation"):
		projectile.call("_update_rotation")
	elif projectile.has_method("UpdateRotation"):
		projectile.call("UpdateRotation")
	elif _get_direction(projectile) != null:
		# Fallback: set rotation to match direction angle
		projectile.rotation = outward_dir.angle()

	FileLogger.info("[ForceFieldEffect] Released projectile at angle %.1f°" % rad_to_deg(outward_dir.angle()))


## Reflect a grenade off the force field.
## Grenades are RigidBody2D nodes and use `linear_velocity` for movement.
func _reflect_grenade(grenade: Node2D) -> void:
	if not grenade is RigidBody2D:
		return

	var rb := grenade as RigidBody2D
	var velocity: Vector2 = rb.linear_velocity
	if velocity.length_squared() < 0.01:
		return

	# Calculate reflection using surface normal
	var to_grenade := grenade.global_position - global_position
	var normal := to_grenade.normalized()

	# Reflection formula: R = V - 2(V·N)N with boost
	var dot := velocity.dot(normal)
	var reflected := (velocity - 2.0 * dot * normal) * GRENADE_REFLECTION_BOOST

	rb.linear_velocity = reflected

	# For frag/offensive grenades: temporarily disable impact detection
	# so they don't detonate on the force field surface
	if grenade.has_method("set_impact_detection_enabled"):
		grenade.set_impact_detection_enabled(false)
		# Re-enable after grenade clears the field
		get_tree().create_timer(GRENADE_BOUNCE_IMMUNITY_TIME).timeout.connect(
			func():
				if is_instance_valid(grenade) and grenade.has_method("set_impact_detection_enabled"):
					grenade.set_impact_detection_enabled(true)
		)

	FileLogger.info("[ForceFieldEffect] Grenade reflected: %.1f°" % rad_to_deg(reflected.angle()))
