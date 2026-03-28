extends Area2D
## Bullet projectile that travels in a direction and handles collisions.
##
## The bullet moves at a constant speed in its rotation direction.
## It destroys itself when hitting walls or targets, and triggers
## target reactions on hit.
##
## Features a visual tracer trail effect for better visibility and
## realistic appearance during fast movement.
##
## Supports realistic ricochet mechanics based on caliber data:
## - Ricochet probability depends on impact angle (shallow = more likely)
## - Velocity and damage reduction after ricochet
## - Maximum ricochet count before destruction
## - Random angle deviation for realistic bounce behavior

## Speed of the bullet in pixels per second.
## Default is 2500 for faster projectiles that make combat more challenging.
@export var speed: float = 2500.0

## Maximum lifetime in seconds before auto-destruction.
@export var lifetime: float = 3.0

## Maximum number of trail points to maintain.
## Higher values create longer trails but use more memory.
@export var trail_length: int = 8

## Caliber data resource for ricochet and ballistic properties.
## If not set, default ricochet behavior is used.
@export var caliber_data: Resource = null

## Base damage dealt by this bullet.
## This can be set by the weapon when spawning the bullet.
## Default is 1.0, but weapons like the silenced pistol override this.
@export var damage: float = 1.0

## Direction the bullet travels (set by the shooter).
var direction: Vector2 = Vector2.RIGHT

## Instance ID of the node that shot this bullet.
## Used to prevent self-detection (e.g., enemies detecting their own bullets).
var shooter_id: int = -1

## Current damage multiplier (decreases with each ricochet).
var damage_multiplier: float = 1.0

## Timer tracking remaining lifetime.
var _time_alive: float = 0.0

## Reference to the trail Line2D node (if present).
var _trail: Line2D = null

## History of global positions for the trail effect.
var _position_history: Array[Vector2] = []

## Number of ricochets that have occurred.
var _ricochet_count: int = 0

## Default ricochet settings (used when caliber_data is not set).
## -1 means unlimited ricochets.
const DEFAULT_MAX_RICOCHETS: int = -1
const DEFAULT_MAX_RICOCHET_ANGLE: float = 90.0
const DEFAULT_BASE_RICOCHET_PROBABILITY: float = 1.0
const DEFAULT_VELOCITY_RETENTION: float = 0.85
const DEFAULT_RICOCHET_DAMAGE_MULTIPLIER: float = 0.5
const DEFAULT_RICOCHET_ANGLE_DEVIATION: float = 10.0

## Viewport size used for calculating post-ricochet lifetime.
## Bullets disappear after traveling this distance after ricochet.
var _viewport_diagonal: float = 0.0

## Whether this bullet has ricocheted at least once.
var _has_ricocheted: bool = false

## Distance traveled since the last ricochet (for viewport-based lifetime).
var _distance_since_ricochet: float = 0.0

## Position at the moment of the last ricochet.
var _ricochet_position: Vector2 = Vector2.ZERO

## Maximum travel distance after ricochet (based on viewport and ricochet angle).
var _max_post_ricochet_distance: float = 0.0

## Enable/disable debug logging for ricochet calculations.
var _debug_ricochet: bool = false

## Whether the bullet is currently penetrating through a wall.
var _is_penetrating: bool = false

## Distance traveled while penetrating through walls.
var _penetration_distance_traveled: float = 0.0

## Entry point into the current obstacle being penetrated.
var _penetration_entry_point: Vector2 = Vector2.ZERO

## The body currently being penetrated (for tracking exit).
var _penetrating_body: Node2D = null

## Whether the bullet has penetrated at least one wall (for damage reduction).
var _has_penetrated: bool = false

## Enable/disable debug logging for penetration calculations.
## Issue #969: Set to false by default — having this true in gameplay generates
## hundreds of file I/O operations per second during shootouts, causing FPS drops.
var _debug_penetration: bool = false

## Default penetration settings (used when caliber_data is not set).
const DEFAULT_CAN_PENETRATE: bool = true
const DEFAULT_MAX_PENETRATION_DISTANCE: float = 48.0
const DEFAULT_POST_PENETRATION_DAMAGE_MULTIPLIER: float = 0.9

## Distance-based penetration chance settings.
## At point-blank (0 distance): 100% penetration, ignores ricochet
## At 40% of viewport: normal ricochet rules apply (if not ricochet, then penetrate)
## At viewport distance: max 30% penetration chance for 5.45
const POINT_BLANK_DISTANCE_RATIO: float = 0.0  # 0% of viewport = point blank
const RICOCHET_RULES_DISTANCE_RATIO: float = 0.4  # 40% of viewport = ricochet rules apply
const MAX_PENETRATION_CHANCE_AT_DISTANCE: float = 0.3  # 30% max at viewport distance

## Shooter's position at the time of firing (for distance-based penetration).
var shooter_position: Vector2 = Vector2.ZERO

## Duration in seconds to stun enemies on hit (0 = no stun effect).
## Set by weapons like MakarovPM and SilencedPistol via Call("set_stun_duration", value).
var stun_duration: float = 0.0

## Whether this bullet has homing enabled (steers toward nearest enemy).
var homing_enabled: bool = false

## Maximum angle (in radians) the bullet can turn from its original direction.
## Default 110 degrees = ~1.92 radians.
var homing_max_turn_angle: float = deg_to_rad(110.0)

## Steering force for homing (radians per second of turning).
## Higher values make bullets turn faster.
var homing_steer_speed: float = 8.0

## The original firing direction (stored when homing is enabled).
## Used to limit total turn angle.
var _homing_original_direction: Vector2 = Vector2.ZERO

## Enable/disable debug logging for homing calculations.
var _debug_homing: bool = false

## Whether to use aim-line targeting (Issue #704, #781).
## When true, bullets home toward enemy nearest to shooter's crosshair instead of nearest to bullet.
var _use_aim_line_targeting: bool = false

## Shooter's position when firing (used for aim-line targeting).
var _homing_shooter_origin: Vector2 = Vector2.ZERO

## Shooter's aim direction when firing (used for aim-line targeting).
var _homing_aim_direction: Vector2 = Vector2.ZERO

## Whether this bullet uses breaker behavior (Issue #678).
## Breaker bullets explode 95px before hitting a wall or enemy, spawning shrapnel in a forward cone.
var is_breaker_bullet: bool = false

## Whether this bullet ignores walls (Issue #751).
## When true, the bullet passes through walls with full damage and no ricochet.
## Set via BaseWeapon.SpawnBullet() → bullet.Call("set_is_drilling_bullet", true).
var is_drilling_bullet: bool = false

## Whether this is an RPG rocket (Issue #583).
## When true, bullet explodes on any impact instead of ricocheting/penetrating.
## Enables realistic RPG-7 acceleration and area-of-effect explosion damage.
## MUST be @export so RpgRocket.tscn can set it to true (non-@export vars cannot be set from .tscn).
@export var is_rpg_rocket: bool = false

## RPG rocket: initial launch speed (pixels per second, like real RPG-7 initial charge).
@export var rpg_speed_initial: float = 600.0

## RPG rocket: cruise speed after acceleration phase (pixels per second).
@export var rpg_speed_max: float = 1800.0

## RPG rocket: distance over which rocket accelerates from initial to cruise speed (pixels).
@export var rpg_accel_distance: float = 800.0

## RPG rocket: explosion radius in pixels.
@export var rpg_explosion_radius: float = 150.0

## RPG rocket: number of damage hits applied to each entity in radius.
@export var rpg_explosion_damage: int = 3

## RPG rocket: seconds of spawn immunity (ignores all collisions, avoids immediate explosion).
@export var rpg_spawn_immunity: float = 0.15

## RPG rocket: hit points before the rocket is shot down (Issue #1133).
## Any damage source (bullet, shrapnel, explosion) reduces this.
## When it reaches 0 the rocket is destroyed without exploding.
## Set to 0 to disable interception (rocket cannot be shot down).
@export var rpg_health: int = 1

## RPG rocket internal state: current hit points remaining.
var _rpg_current_health: int = 0

## RPG rocket internal state: distance traveled so far.
var _rpg_distance_traveled: float = 0.0

## RPG rocket internal state: current speed (increases during acceleration phase).
var _rpg_current_speed: float = 0.0

## RPG rocket internal state: time since spawn (for spawn immunity).
var _rpg_time_alive: float = 0.0

## RPG rocket internal state: whether rocket has already exploded (prevent double-explosion).
var _rpg_has_exploded: bool = false

## RPG rocket internal state: position from the previous physics frame (for raycast hit detection).
var _rpg_prev_position: Vector2 = Vector2.ZERO

## RPG rocket internal state: StaticBody2D wall hit, stored for wall-passage creation (Issue #1131).
var _rpg_hit_wall: StaticBody2D = null

## RPG rocket internal state: precise world-space surface hit position for breach (Issue #1144).
## Set to the exact raycast intersection point on the wall surface (not rocket center position).
## Ensures WallBreachHelper.open_wall_passage carves the passage at the true impact point.
var _rpg_hit_position: Vector2 = Vector2.ZERO

## RPG rocket: weak homing — turning speed toward the player in radians/second (Issue #1135).
## A small value gives a subtle "guided missile" feel without making it unavoidable.
## Set to 0.0 to disable homing entirely.
@export var rpg_homing_steer_speed: float = 1.2

## RPG rocket: maximum total turn from the original firing direction (radians) (Issue #1135).
## Limits how far the rocket can veer — keeps it feeling like a light correction.
@export var rpg_homing_max_turn_angle: float = deg_to_rad(30.0)

## RPG rocket internal state: original firing direction for angle-limit check (Issue #1135).
var _rpg_homing_original_direction: Vector2 = Vector2.ZERO

## Whether this bullet penetrates through enemies (Issue #829).
## When true, the bullet deals damage to enemies but continues flying through them.
## Used by the RSh-12 revolver with its 12.7x55mm armor-piercing rounds.
var penetrates_enemies: bool = false

## Whether this is a phantom (illusion) bullet (Issue #1353).
## Phantom bullets only damage the player, not enemies or other illusions.
## Fired by IllusionEffect visual copies.
var is_phantom: bool = false

## Set of enemy bodies this bullet has already dealt damage to (Issue #829).
## Prevents the bullet from re-applying damage when _on_area_entered fires multiple times
## for the same enemy (e.g., multiple hit areas or re-entry signals).
## NOTE: Only populated by _on_area_entered AFTER damage is dealt.
var _penetrated_enemy_bodies: Array = []

## Set of enemy CharacterBody2D nodes the bullet has already passed through (Issue #829).
## Used exclusively in _on_body_entered to suppress physics re-entry signals.
## Kept separate from _penetrated_enemy_bodies so that _on_area_entered can still
## deal damage even after _on_body_entered has already allowed the bullet through.
var _passed_through_enemy_bodies: Array = []

## Distance in pixels ahead of the bullet at which to trigger breaker detonation.
const BREAKER_DETONATION_DISTANCE: float = 95.0

## Explosion damage radius for breaker bullet detonation (in pixels).
const BREAKER_EXPLOSION_RADIUS: float = 15.0

## Explosion damage dealt by breaker bullet detonation.
const BREAKER_EXPLOSION_DAMAGE: float = 1.0

## Half-angle of the shrapnel cone in degrees (total cone = 2 * half_angle).
const BREAKER_SHRAPNEL_HALF_ANGLE: float = 30.0

## Damage per breaker shrapnel piece.
const BREAKER_SHRAPNEL_DAMAGE: float = 0.1

## Multiplier for shrapnel count: shrapnel_count = bullet_damage * this multiplier.
const BREAKER_SHRAPNEL_COUNT_MULTIPLIER: float = 10.0

## Breaker shrapnel scene path.
const BREAKER_SHRAPNEL_SCENE_PATH: String = "res://scenes/projectiles/BreakerShrapnel.tscn"

## Cached breaker shrapnel scene (loaded once).
var _breaker_shrapnel_scene: PackedScene = null

## Enable/disable debug logging for breaker bullet behavior.
var _debug_breaker: bool = false


func _ready() -> void:
	# Connect to collision signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	area_entered.connect(_on_area_entered)

	# Get trail reference if it exists
	_trail = get_node_or_null("Trail")
	if _trail:
		_trail.clear_points()
		# Set trail to use global coordinates (not relative to bullet)
		_trail.top_level = true
		# Reset position to origin so points added are truly global
		# (when top_level becomes true, the Line2D's position becomes its global position,
		# so we need to reset it to (0,0) for added points to be at their true global positions)
		_trail.position = Vector2.ZERO

	# Load default caliber data if not set
	if caliber_data == null:
		caliber_data = _load_default_caliber_data()

	# Calculate viewport diagonal for post-ricochet lifetime
	_calculate_viewport_diagonal()

	# Set initial rotation based on direction
	_update_rotation()

	# Load breaker shrapnel scene if this is a breaker bullet
	if is_breaker_bullet:
		if ResourceLoader.exists(BREAKER_SHRAPNEL_SCENE_PATH):
			_breaker_shrapnel_scene = load(BREAKER_SHRAPNEL_SCENE_PATH)
		if _debug_breaker:
			FileLogger.info("[Bullet.Breaker] Breaker bullet initialized, shrapnel scene: %s" % (
				"loaded" if _breaker_shrapnel_scene else "MISSING"))

	# Initialize RPG rocket speed, health, and raycast tracking position
	if is_rpg_rocket:
		_rpg_current_speed = rpg_speed_initial
		_rpg_current_health = rpg_health
		_rpg_prev_position = global_position
		_rpg_homing_original_direction = direction.normalized()  # Store for angle-limit check (Issue #1135)
		add_to_group("rpg_rockets")  # Used by grenades to check blast interception (Issue #1133)
		FileLogger.info("[RpgRocket] Spawned: pos=%s dir=%s initial_speed=%.0f max_speed=%.0f health=%d" % [
			str(global_position), str(direction), rpg_speed_initial, rpg_speed_max, rpg_health])


## Calculates the viewport diagonal distance for post-ricochet lifetime.
func _calculate_viewport_diagonal() -> void:
	var viewport := get_viewport()
	if viewport:
		var size := viewport.get_visible_rect().size
		_viewport_diagonal = sqrt(size.x * size.x + size.y * size.y)
	else:
		# Fallback to a reasonable default (1920x1080 diagonal ~= 2203)
		_viewport_diagonal = 2203.0


## Loads the default 5.45x39mm caliber data.
func _load_default_caliber_data() -> Resource:
	var path := "res://resources/calibers/caliber_545x39.tres"
	if ResourceLoader.exists(path):
		return load(path)
	return null


## Updates the bullet rotation to match its travel direction.
func _update_rotation() -> void:
	rotation = direction.angle()


## Logs a penetration-related message to both console and file logger.
## @param message: The message to log.
func _log_penetration(message: String) -> void:
	if not _debug_penetration:
		return
	var full_message := "[Bullet] " + message
	print(full_message)
	# Also log to FileLogger if available
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info(full_message)


func _physics_process(delta: float) -> void:
	# Apply homing steering if enabled
	if homing_enabled:
		_apply_homing_steering(delta)

	# RPG rocket: weak homing toward the player (Issue #1135)
	if is_rpg_rocket and rpg_homing_steer_speed > 0.0:
		_apply_rpg_homing_steering(delta)

	# RPG rocket: update spawn immunity timer
	if is_rpg_rocket:
		_rpg_time_alive += delta

	# Calculate movement this frame (RPG uses accelerating speed, others use constant speed)
	var current_speed: float = speed
	if is_rpg_rocket:
		# Smooth ease-in acceleration: speed_initial → speed_max over accel_distance
		if _rpg_distance_traveled < rpg_accel_distance:
			var t := _rpg_distance_traveled / rpg_accel_distance  # 0.0 → 1.0
			_rpg_current_speed = lerpf(rpg_speed_initial, rpg_speed_max, t * t)
		else:
			_rpg_current_speed = rpg_speed_max
		current_speed = _rpg_current_speed
	var movement := direction * current_speed * delta

	# Move in the set direction
	position += movement

	# Track distance for RPG acceleration curve and keep sprite oriented toward travel direction
	if is_rpg_rocket:
		_rpg_distance_traveled += movement.length()
		rotation = direction.angle()  # Stay pointed in travel direction (direction set after _ready)
		# Raycast-based collision: detect wall/body hits that body_entered may miss (Issue #583).
		# Cast a ray from previous position to current position each frame as a reliable fallback.
		if _rpg_time_alive >= rpg_spawn_immunity and not _rpg_has_exploded and _rpg_prev_position != Vector2.ZERO:
			var space_state := get_world_2d().direct_space_state
			var ray := PhysicsRayQueryParameters2D.create(_rpg_prev_position, global_position)
			ray.collision_mask = 39  # same as rocket collision_mask: walls (4), enemies (2), player (1)
			ray.exclude = [self]
			var result := space_state.intersect_ray(ray)
			if not result.is_empty():
				FileLogger.info("[RpgRocket] Raycast impact on %s at %s after %.2fs dist=%.0fpx" % [
					result.collider.name, str(result.position), _rpg_time_alive, _rpg_distance_traveled])
				# Record wall for passage creation (Issue #1131, #1144)
				if result.collider is StaticBody2D:
					_rpg_hit_wall = result.collider as StaticBody2D
					# Use the precise raycast surface hit point, not rocket center (Issue #1144).
					# This matches how BreachingChargesEffect gets hit positions.
					_rpg_hit_position = result.position
				_rpg_explode()
				return
		_rpg_prev_position = global_position

	# Track distance traveled since last ricochet (for viewport-based lifetime)
	if _has_ricocheted:
		_distance_since_ricochet += movement.length()
		# Destroy bullet if it has traveled more than the viewport-based max distance
		if _distance_since_ricochet >= _max_post_ricochet_distance:
			if _debug_ricochet:
				print("[Bullet] Post-ricochet distance exceeded: ", _distance_since_ricochet, " >= ", _max_post_ricochet_distance)
			_destroy()
			return

	# Track penetration distance while inside a wall
	if _is_penetrating:
		_penetration_distance_traveled += movement.length()
		var max_pen_distance := _get_max_penetration_distance()

		# Check if we've exceeded max penetration distance
		if max_pen_distance > 0 and _penetration_distance_traveled >= max_pen_distance:
			_log_penetration("Max penetration distance exceeded: %s >= %s" % [_penetration_distance_traveled, max_pen_distance])
			# Bullet stopped inside the wall - destroy it
			# Visual effects disabled as per user request
			_destroy()
			return

		# Check if we've exited the obstacle (raycast forward to see if still inside)
		# Note: body_exited signal also triggers _exit_penetration for reliability
		if not _is_still_inside_obstacle():
			_exit_penetration()

	# Check for breaker detonation (raycast ahead for walls)
	if is_breaker_bullet and not _is_penetrating:
		if _check_breaker_detonation():
			return  # Bullet detonated and was freed

	# Update trail effect
	_update_trail()

	# Track lifetime and auto-destroy if exceeded
	_time_alive += delta
	if _time_alive >= lifetime:
		_destroy()


## Updates the visual trail effect by maintaining position history.
func _update_trail() -> void:
	if not _trail:
		return

	# Add current position to history
	_position_history.push_front(global_position)

	# Limit trail length
	while _position_history.size() > trail_length:
		_position_history.pop_back()

	# Update Line2D points
	_trail.clear_points()
	for pos in _position_history:
		_trail.add_point(pos)


func _on_body_entered(body: Node2D) -> void:
	# Issue #1334 Round 11: Guard against invalid colliders during physics callbacks.
	# When many physics bodies are created/destroyed in the same frame (ragdoll, casings,
	# bullets), the physics server may deliver callbacks for freed colliders.
	if not is_instance_valid(body): return
	if _is_pooled: return
	# RPG rocket: explode on any body after spawn immunity expires
	if is_rpg_rocket:
		if _rpg_has_exploded:
			return
		if _rpg_time_alive < rpg_spawn_immunity:
			return  # Spawn immunity - ignore until clear of shooter
		if shooter_id == body.get_instance_id():
			return  # Never hit the shooter
		if body.has_method("is_alive") and not body.is_alive():
			return  # Pass through dead entities
		FileLogger.info("[RpgRocket] Impact on %s (type: %s) after %.2fs dist=%.0fpx" % [
			body.name, body.get_class(), _rpg_time_alive, _rpg_distance_traveled])
		# Record wall for passage creation (Issue #1131, #1144)
		if body is StaticBody2D:
			_rpg_hit_wall = body as StaticBody2D
			# Get the precise wall surface hit position via back-raycast (Issue #1144).
			# body_entered fires when the Area2D overlaps the body, so global_position is
			# already inside the wall. Cast a ray from the previous frame position to find
			# the exact surface point, matching BreachingChargesEffect hit-position logic.
			if _rpg_prev_position != Vector2.ZERO:
				var space_state := get_world_2d().direct_space_state
				var surface_ray := PhysicsRayQueryParameters2D.create(_rpg_prev_position, global_position)
				surface_ray.collision_mask = 4  # Obstacle layer only
				surface_ray.exclude = [self]
				var surface_result := space_state.intersect_ray(surface_ray)
				if not surface_result.is_empty() and surface_result.collider == body:
					_rpg_hit_position = surface_result.position
				else:
					_rpg_hit_position = global_position  # Fallback: use rocket position
			else:
				_rpg_hit_position = global_position  # Fallback: use rocket position
		_rpg_explode()
		return

	# Check if this is the shooter - don't collide with own body
	if shooter_id == body.get_instance_id():
		return  # Pass through the shooter

	# Check if this is a dead enemy - bullets should pass through dead entities
	# This handles the CharacterBody2D collision (separate from HitArea collision)
	if body.has_method("is_alive") and not body.is_alive():
		return  # Pass through dead entities

	# Issue #1413: Pass through ragdoll body parts of dead enemies.
	# When an enemy dies, its death animation creates RigidBody2D ragdoll parts
	# marked with the "dead_enemy_ragdoll" group. These parts have collision_layer=32
	# which is included in the bullet's collision mask, causing bullets to stop on
	# dead enemy bodies. Bullets should pass through ragdoll parts freely.
	if body.is_in_group("dead_enemy_ragdoll"):
		return  # Pass through dead enemy ragdoll parts

	# Issue #829: If enemy penetration is enabled and this is an alive enemy CharacterBody2D,
	# allow the bullet to pass through without being destroyed.
	# The _on_area_entered handler takes care of dealing damage via the enemy's HitArea.
	# We track which enemy bodies we've already passed through (body-level) to suppress
	# physics re-entry signals, using a SEPARATE set from _penetrated_enemy_bodies so that
	# _on_area_entered can still deal damage on first entry.
	if penetrates_enemies and body.has_method("is_alive") and body.is_alive():
		if body not in _passed_through_enemy_bodies:
			_passed_through_enemy_bodies.append(body)
			if _debug_penetration:
				print("[Bullet]: Penetrating through enemy CharacterBody2D, bullet continues flying")
		return  # Don't destroy the bullet - it passes through the enemy body

	# If we're currently penetrating the same body, ignore re-entry
	if _is_penetrating and _penetrating_body == body:
		return

	# Check if bullet is inside an existing penetration hole - pass through without re-triggering
	if _is_inside_penetration_hole():
		_log_penetration("Inside existing penetration hole, passing through")
		return

	# Drilling bullets pass through walls completely (Issue #751)
	# StaticBody2D covers hand-crafted walls; TileMap/TileMapLayer cover tile-based levels
	if is_drilling_bullet and (body is StaticBody2D or body is TileMap or body is TileMapLayer):
		return  # Wall ignored — bullet continues with full damage

	# Hit a static body (wall or obstacle) or alive enemy body
	# Try to ricochet off static bodies (walls/obstacles)
	if body is StaticBody2D or body is TileMap:
		# Issue #1145: compute surface normal once and reuse it for both the dust effect
		# and ricochet calculation to avoid a duplicate physics raycast per wall hit.
		var cached_normal := _get_surface_normal(body)

		# Always spawn dust effect when hitting walls, regardless of ricochet
		_spawn_wall_hit_effect(body, cached_normal)

		# Calculate distance from shooter to determine penetration behavior
		var distance_to_wall := _get_distance_to_shooter()
		var distance_ratio := distance_to_wall / _viewport_diagonal if _viewport_diagonal > 0 else 1.0

		_log_penetration("Distance to wall: %s (%s%% of viewport)" % [distance_to_wall, distance_ratio * 100])

		# Point-blank shots (very close to shooter): 100% penetration, ignore ricochet
		if distance_ratio <= POINT_BLANK_DISTANCE_RATIO + 0.05:  # ~5% tolerance for "point blank"
			_log_penetration("Point-blank shot - 100% penetration, ignoring ricochet")
			if _try_penetration(body):
				return  # Bullet is penetrating
		# At 40% or less of viewport: normal ricochet rules apply
		elif distance_ratio <= RICOCHET_RULES_DISTANCE_RATIO:
			_log_penetration("Within ricochet range - trying ricochet first")
			# First try ricochet
			if _try_ricochet(body, cached_normal):
				return  # Bullet ricocheted, don't destroy
			# Ricochet failed - try penetration (if not ricochet, then penetrate)
			if _try_penetration(body):
				return  # Bullet is penetrating, don't destroy
		# Beyond 40% of viewport: distance-based penetration chance
		else:
			# First try ricochet (shallow angles still ricochet)
			if _try_ricochet(body, cached_normal):
				return  # Bullet ricocheted, don't destroy

			# Calculate penetration chance based on distance
			# At 40% distance: 100% chance (if ricochet failed)
			# At 100% (viewport) distance: 30% chance
			var penetration_chance := _calculate_distance_penetration_chance(distance_ratio)

			_log_penetration("Distance-based penetration chance: %s%%" % [penetration_chance * 100])

			# Roll for penetration
			if randf() <= penetration_chance:
				if _try_penetration(body):
					return  # Bullet is penetrating
			else:
				_log_penetration("Penetration failed (distance roll)")

	# Play wall impact sound and destroy bullet
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_bullet_wall_hit"):
		audio_manager.play_bullet_wall_hit(global_position)
	_destroy()


## Called when the bullet exits a body (wall).
## Used for detecting penetration exit via the physics system.
func _on_body_exited(body: Node2D) -> void:
	if not is_instance_valid(body): return  # Issue #1334 Round 11: guard freed collider
	# Only process if we're currently penetrating this specific body
	if not _is_penetrating or _penetrating_body != body:
		return

	# Log exit detection
	_log_penetration("Body exited signal received for penetrating body")

	# Call exit penetration
	_exit_penetration()


func _on_area_entered(area: Area2D) -> void:
	# Issue #1334 Round 11: Guard against invalid/pooled state during physics callbacks
	if not is_instance_valid(area): return
	if _is_pooled: return
	# RPG rocket: explode when hitting any hit-area (enemy/player HitArea)
	if is_rpg_rocket:
		if _rpg_has_exploded or _rpg_time_alive < rpg_spawn_immunity:
			return
		# Other projectiles on the projectiles collision layer (Issue #1133, #1307).
		# Bullets/shrapnel are on layer 5 (bit 16). When they overlap the rocket,
		# the rocket receives the area_entered signal (since rocket mask includes layer 5).
		# Treat incoming non-RPG projectiles as hits that damage this rocket.
		if area.collision_layer & 16:
			if area.get("is_rpg_rocket") or area is RpgRocket:
				return  # Skip other RPG rockets (avoid mutual destruction)
			# Incoming bullet/shrapnel hit — apply damage to this rocket (Issue #1307)
			on_hit()
			return
		if area.has_method("on_hit"):
			var parent: Node = area.get_parent()
			if parent and shooter_id == parent.get_instance_id():
				return  # Don't hit shooter
			FileLogger.info("[RpgRocket] Hit area %s - exploding" % area.name)
			_rpg_explode()
		return

	# Hit another area (like a target or hit detection area)
	# Only destroy bullet if the area has on_hit method (actual hit targets)
	# This allows bullets to pass through detection-only areas like ThreatSpheres
	if area.has_method("on_hit"):
		# Check if this is a HitArea - if so, check against parent's instance ID
		# This prevents the shooter from damaging themselves with direct shots
		# BUT ricocheted bullets CAN damage the shooter (realistic self-damage)
		var parent: Node = area.get_parent()
		if parent and shooter_id == parent.get_instance_id() and not _has_ricocheted:
			return  # Don't hit the shooter with direct shots

		# Issue #1353: Phantom (illusion) bullets only damage the player
		if is_phantom and parent and not parent.is_in_group("player"):
			return  # Phantom bullets pass through non-player targets

		# Force field protection: Block damage if target has active force field (Issue #676)
		if parent and parent.has_method("is_force_field_active"):
			if parent.is_force_field_active():
				return  # Bullet is reflected by force field, damage blocked

		# Power Fantasy mode: Ricocheted bullets do NOT damage the player
		if _has_ricocheted and parent and parent.is_in_group("player"):
			var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
			if difficulty_manager and difficulty_manager.has_method("do_ricochets_damage_player"):
				if not difficulty_manager.do_ricochets_damage_player():
					return  # Pass through player without damage in Power Fantasy mode

		# Check if the parent is dead - bullets should pass through dead entities
		# This is a fallback check in case the collision shape/layer disabling
		# doesn't take effect immediately (see Godot issues #62506, #100687)
		if parent and parent.has_method("is_alive") and not parent.is_alive():
			return  # Pass through dead entities

		# Issue #829: When penetrating enemies, only deal damage to each enemy once per pass-through.
		# The area_entered signal fires once on entry, but we guard against future re-entries
		# (e.g., if the enemy has multiple hit areas or the bullet passes through slowly).
		if penetrates_enemies and parent != null:
			if parent in _penetrated_enemy_bodies:
				return  # Already dealt damage to this enemy during this pass-through

		# Calculate effective damage (base damage × multiplier from ricochets/penetration)
		var effective_damage: float = damage * damage_multiplier

		# Call on_hit with extended parameters if supported, otherwise use basic call
		var from_player: bool = _is_player_bullet()  # Issue #1196: track kill source
		if area.has_method("on_hit_with_bullet_info_and_damage"):
			# Pass full bullet information including damage amount and player kill source
			area.on_hit_with_bullet_info_and_damage(direction, caliber_data, _has_ricocheted, _has_penetrated, effective_damage, from_player)
		elif area.has_method("on_hit_with_bullet_info"):
			# Legacy path - pass bullet info without explicit damage (will use default)
			area.on_hit_with_bullet_info(direction, caliber_data, _has_ricocheted, _has_penetrated, from_player)
		elif area.has_method("on_hit_with_info"):
			area.on_hit_with_info(direction, caliber_data)
		else:
			area.on_hit()

		# Apply stun effect if configured (e.g., MakarovPM, SilencedPistol)
		if stun_duration > 0 and parent:
			_apply_stun_effect(parent)

		# Trigger hit effects if this is a player bullet hitting an enemy
		if _is_player_bullet():
			_trigger_player_hit_effects()

		# Issue #829: If enemy penetration is enabled, bullet continues flying after hitting enemy.
		# This is used by the RSh-12 revolver with its 12.7x55mm armor-piercing rounds.
		if penetrates_enemies:
			if _debug_penetration:
				print("[Bullet]: Penetrating through enemy, bullet continues flying")
			# Track the enemy so we don't re-apply damage on subsequent area_entered calls
			if parent != null and parent not in _penetrated_enemy_bodies:
				_penetrated_enemy_bodies.append(parent)
			return  # Don't destroy the bullet - it passes through

		_destroy()


## Attempts to ricochet the bullet off a surface.
## Returns true if ricochet occurred, false if bullet should be destroyed.
## @param body: The body the bullet collided with.
## @param precomputed_normal: Pre-computed surface normal from _on_body_entered (Issue #1145).
##   Pass a non-zero vector to skip the internal raycast (avoids a duplicate intersect_ray call).
func _try_ricochet(body: Node2D, precomputed_normal: Vector2 = Vector2.ZERO) -> bool:
	# Check if we've exceeded maximum ricochets (-1 = unlimited)
	var max_ricochets := _get_max_ricochets()
	if max_ricochets >= 0 and _ricochet_count >= max_ricochets:
		if _debug_ricochet:
			print("[Bullet] Max ricochets reached: ", _ricochet_count)
		return false

	# Use pre-computed normal when available (Issue #1145: avoids duplicate raycast per wall hit)
	var surface_normal := precomputed_normal if precomputed_normal != Vector2.ZERO else _get_surface_normal(body)
	if surface_normal == Vector2.ZERO:
		if _debug_ricochet:
			print("[Bullet] Could not determine surface normal")
		return false

	# Calculate impact angle (angle between bullet direction and surface)
	# 0 degrees = parallel to surface (grazing shot)
	# 90 degrees = perpendicular to surface (direct hit)
	var impact_angle_rad := _calculate_impact_angle(surface_normal)
	var impact_angle_deg := rad_to_deg(impact_angle_rad)

	if _debug_ricochet:
		print("[Bullet] Impact angle: ", impact_angle_deg, " degrees")

	# Calculate ricochet probability based on impact angle
	var ricochet_probability := _calculate_ricochet_probability(impact_angle_deg)

	if _debug_ricochet:
		print("[Bullet] Ricochet probability: ", ricochet_probability * 100, "%")

	# Random roll to determine if ricochet occurs
	if randf() > ricochet_probability:
		if _debug_ricochet:
			print("[Bullet] Ricochet failed (random)")
		return false

	# Ricochet successful - calculate new direction
	_perform_ricochet(surface_normal)
	return true


## Gets the maximum number of ricochets allowed.
func _get_max_ricochets() -> int:
	if caliber_data and caliber_data.has_method("get") and "max_ricochets" in caliber_data:
		return caliber_data.max_ricochets
	return DEFAULT_MAX_RICOCHETS


## Gets the surface normal at the collision point.
## Uses raycasting to determine the exact collision point and normal.
func _get_surface_normal(body: Node2D) -> Vector2:
	# Create a raycast to find the exact collision point
	var space_state := get_world_2d().direct_space_state

	# Cast ray from slightly behind the bullet to current position
	var ray_start := global_position - direction * 50.0
	var ray_end := global_position + direction * 10.0

	var query := PhysicsRayQueryParameters2D.create(ray_start, ray_end)
	query.collision_mask = collision_mask
	query.exclude = [self]

	var result := space_state.intersect_ray(query)

	if result.is_empty():
		# Fallback: estimate normal based on bullet direction
		# Assume the surface is perpendicular to the approach
		return -direction.normalized()

	return result.normal


## Calculates the impact angle between bullet direction and surface.
## This returns the GRAZING angle (angle from the surface plane).
## Returns angle in radians (0 = grazing/parallel to surface, PI/2 = perpendicular/head-on).
func _calculate_impact_angle(surface_normal: Vector2) -> float:
	# We want the GRAZING angle (angle from the surface, not from the normal).
	# The grazing angle is 90° - (angle from normal).
	#
	# Using dot product with the normal:
	# dot(direction, -normal) = cos(angle_from_normal)
	#
	# The grazing angle = 90° - angle_from_normal
	# So: grazing_angle = asin(|dot(direction, normal)|)
	#
	# For grazing shots (parallel to surface): direction ⊥ normal, dot ≈ 0, grazing_angle ≈ 0°
	# For direct hits (perpendicular to surface): direction ∥ -normal, dot ≈ 1, grazing_angle ≈ 90°

	var dot := absf(direction.normalized().dot(surface_normal.normalized()))
	# Clamp to avoid numerical issues with asin
	dot = clampf(dot, 0.0, 1.0)
	return asin(dot)


## Calculates the ricochet probability based on impact angle.
## Uses a custom curve designed for realistic 5.45x39mm behavior:
## - 0-15°: ~100% (grazing shots always ricochet)
## - 45°: ~80% (moderate angles have good ricochet chance)
## - 90°: ~10% (perpendicular shots rarely ricochet)
## When Ricochet Points experimental setting is enabled (Issue #975),
## probability is increased by 20% at angles where ricochet is possible.
func _calculate_ricochet_probability(impact_angle_deg: float) -> float:
	var max_angle: float
	var base_probability: float

	if caliber_data:
		max_angle = caliber_data.max_ricochet_angle if "max_ricochet_angle" in caliber_data else DEFAULT_MAX_RICOCHET_ANGLE
		base_probability = caliber_data.base_ricochet_probability if "base_ricochet_probability" in caliber_data else DEFAULT_BASE_RICOCHET_PROBABILITY
	else:
		max_angle = DEFAULT_MAX_RICOCHET_ANGLE
		base_probability = DEFAULT_BASE_RICOCHET_PROBABILITY

	# No ricochet if angle exceeds maximum
	if impact_angle_deg > max_angle:
		return 0.0

	# Custom curve for realistic ricochet probability:
	# probability = base * (0.9 * (1 - (angle/90)^2.17) + 0.1)
	# This gives approximately:
	# - 0°: 100%, 15°: 98%, 45°: 80%, 90°: 10%
	var normalized_angle := impact_angle_deg / 90.0
	# Power of 2.17 creates a curve matching real-world ballistics
	var power_factor := pow(normalized_angle, 2.17)
	var angle_factor := (1.0 - power_factor) * 0.9 + 0.1
	var probability := base_probability * angle_factor

	# Issue #1028: Trajectory Glasses passive effect boosts ricochet chance by 30%
	# at angles where ricochet is possible (same condition as green trajectory ray).
	var active_item_manager: Node = get_node_or_null("/root/ActiveItemManager")
	if active_item_manager and active_item_manager.has_method("has_trajectory_glasses"):
		if active_item_manager.has_trajectory_glasses():
			probability = minf(probability + 0.3, 1.0)

	return probability


## Performs the ricochet: updates direction, speed, and damage.
## Also calculates the post-ricochet maximum travel distance based on viewport and angle.
func _perform_ricochet(surface_normal: Vector2) -> void:
	_ricochet_count += 1

	# Calculate the impact angle for determining post-ricochet distance
	var impact_angle_rad := _calculate_impact_angle(surface_normal)
	var impact_angle_deg := rad_to_deg(impact_angle_rad)

	# Calculate reflected direction
	# reflection = direction - 2 * dot(direction, normal) * normal
	var reflected := direction - 2.0 * direction.dot(surface_normal) * surface_normal
	reflected = reflected.normalized()

	# Add random deviation for realism
	var deviation := _get_ricochet_deviation()
	reflected = reflected.rotated(deviation)

	# Update direction
	direction = reflected
	_update_rotation()

	# Reduce velocity
	var velocity_retention := _get_velocity_retention()
	speed *= velocity_retention

	# Reduce damage multiplier
	var damage_mult := _get_ricochet_damage_multiplier()
	damage_multiplier *= damage_mult

	# Move bullet slightly away from surface to prevent immediate re-collision
	global_position += direction * 5.0

	# Mark bullet as having ricocheted and set viewport-based lifetime
	_has_ricocheted = true
	_ricochet_position = global_position
	_distance_since_ricochet = 0.0

	# Calculate max post-ricochet distance based on viewport and ricochet angle
	# Shallow angles (grazing) -> bullet travels longer after ricochet
	# Steeper angles -> bullet travels shorter distance (more energy lost)
	# Formula: max_distance = viewport_diagonal * (1 - angle/90)
	# At 0° (grazing): full viewport diagonal
	# At 90° (perpendicular): 0 distance (but this wouldn't ricochet anyway)
	var angle_factor := 1.0 - (impact_angle_deg / 90.0)
	angle_factor = clampf(angle_factor, 0.1, 1.0)  # Minimum 10% to prevent instant destruction
	_max_post_ricochet_distance = _viewport_diagonal * angle_factor

	# Clear trail history to avoid visual artifacts
	_position_history.clear()

	# Play ricochet sound
	_play_ricochet_sound()

	if _debug_ricochet:
		print("[Bullet] Ricochet #", _ricochet_count, " - New speed: ", speed, ", Damage mult: ", damage_multiplier, ", Max post-ricochet distance: ", _max_post_ricochet_distance)


## Gets the velocity retention factor for ricochet.
func _get_velocity_retention() -> float:
	if caliber_data and "velocity_retention" in caliber_data:
		return caliber_data.velocity_retention
	return DEFAULT_VELOCITY_RETENTION


## Gets the damage multiplier for ricochet.
func _get_ricochet_damage_multiplier() -> float:
	if caliber_data and "ricochet_damage_multiplier" in caliber_data:
		return caliber_data.ricochet_damage_multiplier
	return DEFAULT_RICOCHET_DAMAGE_MULTIPLIER


## Gets a random deviation angle for ricochet direction.
func _get_ricochet_deviation() -> float:
	var deviation_deg: float
	if caliber_data:
		if caliber_data.has_method("get_random_ricochet_deviation"):
			return caliber_data.get_random_ricochet_deviation()
		deviation_deg = caliber_data.ricochet_angle_deviation if "ricochet_angle_deviation" in caliber_data else DEFAULT_RICOCHET_ANGLE_DEVIATION
	else:
		deviation_deg = DEFAULT_RICOCHET_ANGLE_DEVIATION

	var deviation_rad := deg_to_rad(deviation_deg)
	return randf_range(-deviation_rad, deviation_rad)


## Plays the ricochet sound effect.
func _play_ricochet_sound() -> void:
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_bullet_ricochet"):
		audio_manager.play_bullet_ricochet(global_position)
	elif audio_manager and audio_manager.has_method("play_bullet_wall_hit"):
		# Fallback to wall hit sound if ricochet sound not available
		audio_manager.play_bullet_wall_hit(global_position)


## Checks if this bullet was fired by the player.
func _is_player_bullet() -> bool:
	if shooter_id == -1:
		return false

	var shooter: Object = instance_from_id(shooter_id)
	if shooter == null:
		return false

	# Use group membership for reliable player detection (works for both C# and GDScript players).
	# The "player" group is set on the Player node in the scene, consistently used across the codebase.
	# Note: script.resource_path.contains("player") would fail for C# Player (capital P).
	if shooter is Node and (shooter as Node).is_in_group("player"):
		return true

	return false


## Triggers hit effects via the HitEffectsManager autoload.
## Effects: time slowdown to 0.9 for 3 seconds, saturation boost for 400ms.
func _trigger_player_hit_effects() -> void:
	var hit_effects_manager: Node = get_node_or_null("/root/HitEffectsManager")
	if hit_effects_manager and hit_effects_manager.has_method("on_player_hit_enemy"):
		hit_effects_manager.on_player_hit_enemy()


## Applies stun effect to the hit enemy via StatusEffectsManager.
## Used by weapons like MakarovPM (100ms) and SilencedPistol (600ms).
func _apply_stun_effect(enemy: Node) -> void:
	if stun_duration <= 0:
		return
	if not enemy is Node2D:
		return
	var status_effects_manager: Node = get_node_or_null("/root/StatusEffectsManager")
	if status_effects_manager and status_effects_manager.has_method("apply_stun"):
		status_effects_manager.apply_stun(enemy, stun_duration)


## Returns the current ricochet count.
func get_ricochet_count() -> int:
	return _ricochet_count


## Returns the current damage multiplier (accounting for ricochets).
func get_damage_multiplier() -> float:
	return damage_multiplier


## Returns whether ricochet is enabled for this bullet.
func can_ricochet() -> bool:
	if caliber_data and "can_ricochet" in caliber_data:
		return caliber_data.can_ricochet
	return true  # Default to enabled


## Spawns dust/debris particles when bullet hits a wall or static body.
## @param body: The body that was hit (used to get surface normal if precomputed_normal is zero).
## @param precomputed_normal: Pre-computed surface normal from _on_body_entered (Issue #1145).
##   Pass a non-zero vector to skip the internal raycast (avoids a duplicate intersect_ray call).
func _spawn_wall_hit_effect(body: Node2D, precomputed_normal: Vector2 = Vector2.ZERO) -> void:
	var impact_manager: Node = get_node_or_null("/root/ImpactEffectsManager")
	if impact_manager == null or not impact_manager.has_method("spawn_dust_effect"):
		return

	# Use pre-computed normal when available (Issue #1145: avoids duplicate raycast per wall hit)
	var surface_normal := precomputed_normal if precomputed_normal != Vector2.ZERO else _get_surface_normal(body)

	# Spawn dust effect at hit position
	impact_manager.spawn_dust_effect(global_position, surface_normal, caliber_data)


# ============================================================================
# Distance-Based Penetration Helpers
# ============================================================================


## Gets the distance from the current bullet position to the shooter's original position.
func _get_distance_to_shooter() -> float:
	_log_penetration("_get_distance_to_shooter: shooter_position=%s, shooter_id=%s, bullet_pos=%s" % [shooter_position, shooter_id, global_position])

	if shooter_position == Vector2.ZERO:
		# Fallback: use shooter instance position if available
		if shooter_id != -1:
			var shooter: Object = instance_from_id(shooter_id)
			if shooter != null and shooter is Node2D:
				var dist := global_position.distance_to((shooter as Node2D).global_position)
				_log_penetration("Using shooter_id fallback, distance=%s" % dist)
				return dist
		# Unable to determine shooter position - assume close range
		_log_penetration("WARNING: Unable to determine shooter position, defaulting to bullet position distance from origin")

	var dist := global_position.distance_to(shooter_position)
	_log_penetration("Using shooter_position, distance=%s" % dist)
	return dist


## Calculates the penetration chance based on distance from shooter.
## @param distance_ratio: Distance as a ratio of viewport diagonal (0.0 to 1.0+).
## @return: Penetration chance (0.0 to 1.0).
func _calculate_distance_penetration_chance(distance_ratio: float) -> float:
	# At 40% (RICOCHET_RULES_DISTANCE_RATIO): 100% penetration chance
	# At 100% (viewport diagonal): MAX_PENETRATION_CHANCE_AT_DISTANCE (30%)
	# Beyond 100%: continues to decrease linearly

	if distance_ratio <= RICOCHET_RULES_DISTANCE_RATIO:
		return 1.0  # Full penetration chance within ricochet rules range

	# Linear interpolation from 100% at 40% to 30% at 100%
	# penetration_chance = 1.0 - (distance_ratio - 0.4) / 0.6 * 0.7
	var range_start := RICOCHET_RULES_DISTANCE_RATIO  # 0.4
	var range_end := 1.0  # viewport distance
	var range_span := range_end - range_start  # 0.6

	var position_in_range := (distance_ratio - range_start) / range_span
	position_in_range = clampf(position_in_range, 0.0, 1.0)

	# Interpolate from 1.0 to MAX_PENETRATION_CHANCE_AT_DISTANCE
	var penetration_chance := lerpf(1.0, MAX_PENETRATION_CHANCE_AT_DISTANCE, position_in_range)

	# Beyond viewport distance, continue decreasing (but clamp to minimum of 5%)
	if distance_ratio > 1.0:
		var beyond_viewport := distance_ratio - 1.0
		penetration_chance = maxf(MAX_PENETRATION_CHANCE_AT_DISTANCE - beyond_viewport * 0.2, 0.05)

	return penetration_chance


## Checks if the bullet is currently inside an existing penetration hole area.
## If so, the bullet should pass through without triggering new penetration.
func _is_inside_penetration_hole() -> bool:
	# Get overlapping areas
	var overlapping_areas := get_overlapping_areas()
	for area in overlapping_areas:
		# Check if this is a penetration hole (by script or name)
		if area.get_script() != null:
			var script_path: String = area.get_script().resource_path
			if script_path.contains("penetration_hole"):
				return true
		# Also check by node name as fallback
		if area.name.contains("PenetrationHole"):
			return true
	return false


# ============================================================================
# Wall Penetration System
# ============================================================================


## Attempts to penetrate through a wall when ricochet fails.
## Returns true if penetration started successfully.
## @param body: The static body (wall) to penetrate.
func _try_penetration(body: Node2D) -> bool:
	# Check if caliber allows penetration
	if not _can_penetrate():
		_log_penetration("Caliber cannot penetrate walls")
		return false

	# Don't start a new penetration if already penetrating
	if _is_penetrating:
		_log_penetration("Already penetrating, cannot start new penetration")
		return false

	_log_penetration("Starting wall penetration at %s" % global_position)

	# Mark as penetrating
	_is_penetrating = true
	_penetrating_body = body
	_penetration_entry_point = global_position
	_penetration_distance_traveled = 0.0

	# Spawn entry hole effect
	_spawn_penetration_hole_effect(body, global_position, true)

	# Move bullet slightly forward to avoid immediate re-collision
	global_position += direction * 5.0

	return true


## Checks if the bullet can penetrate walls based on caliber data.
func _can_penetrate() -> bool:
	if caliber_data and caliber_data.has_method("can_penetrate_walls"):
		return caliber_data.can_penetrate_walls()
	if caliber_data and "can_penetrate" in caliber_data:
		return caliber_data.can_penetrate
	return DEFAULT_CAN_PENETRATE


## Gets the maximum penetration distance from caliber data.
func _get_max_penetration_distance() -> float:
	if caliber_data and caliber_data.has_method("get_max_penetration_distance"):
		return caliber_data.get_max_penetration_distance()
	if caliber_data and "max_penetration_distance" in caliber_data:
		return caliber_data.max_penetration_distance
	return DEFAULT_MAX_PENETRATION_DISTANCE


## Gets the post-penetration damage multiplier from caliber data.
func _get_post_penetration_damage_multiplier() -> float:
	if caliber_data and "post_penetration_damage_multiplier" in caliber_data:
		return caliber_data.post_penetration_damage_multiplier
	return DEFAULT_POST_PENETRATION_DAMAGE_MULTIPLIER


## Checks if the bullet is still inside an obstacle using raycasting.
## Returns true if still inside, false if exited.
## Uses longer raycasts to account for high bullet speeds (2500 px/s = ~41 pixels/frame at 60 FPS).
func _is_still_inside_obstacle() -> bool:
	if _penetrating_body == null or not is_instance_valid(_penetrating_body):
		return false

	var space_state := get_world_2d().direct_space_state

	# Use longer raycasts to account for bullet speed
	# Cast forward ~50 pixels (slightly more than max penetration of 48)
	var ray_length := 50.0
	var ray_start := global_position
	var ray_end := global_position + direction * ray_length

	var query := PhysicsRayQueryParameters2D.create(ray_start, ray_end)
	query.collision_mask = collision_mask
	query.exclude = [self]

	var result := space_state.intersect_ray(query)

	# If we hit the same body in front, we're still inside
	if not result.is_empty() and result.collider == _penetrating_body:
		_log_penetration("Raycast forward hit penetrating body at distance %s" % ray_start.distance_to(result.position))
		return true

	# Also check backwards to see if we're still overlapping
	ray_end = global_position - direction * ray_length
	query = PhysicsRayQueryParameters2D.create(ray_start, ray_end)
	query.collision_mask = collision_mask
	query.exclude = [self]

	result = space_state.intersect_ray(query)
	if not result.is_empty() and result.collider == _penetrating_body:
		_log_penetration("Raycast backward hit penetrating body at distance %s" % ray_start.distance_to(result.position))
		return true

	_log_penetration("No longer inside obstacle - raycasts found no collision with penetrating body")
	return false


## Called when the bullet exits a penetrated wall.
func _exit_penetration() -> void:
	# Prevent double-calling (can happen from both body_exited and raycast check)
	if not _is_penetrating:
		return

	var exit_point := global_position

	_log_penetration("Exiting penetration at %s after traveling %s pixels through wall" % [exit_point, _penetration_distance_traveled])

	# Visual effects disabled as per user request
	# The entry/exit positions couldn't be properly anchored to wall surfaces

	# Apply damage reduction after penetration
	if not _has_penetrated:
		damage_multiplier *= _get_post_penetration_damage_multiplier()
		_has_penetrated = true

		_log_penetration("Damage multiplier after penetration: %s" % damage_multiplier)

	# Play penetration exit sound (use wall hit sound for now)
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_bullet_wall_hit"):
		audio_manager.play_bullet_wall_hit(exit_point)

	# Reset penetration state
	_is_penetrating = false
	_penetrating_body = null
	_penetration_distance_traveled = 0.0

	# Destroy bullet after successful penetration
	# Bullets don't continue flying after penetrating a wall
	_destroy()


## Spawns a visual hole effect at penetration entry or exit point.
## DISABLED: As per user request, all penetration visual effects are removed.
## The penetration functionality remains (bullet passes through thin walls),
## but no visual effects (dust, trails, holes) are spawned.
## @param body: The wall being penetrated.
## @param pos: Position of the hole.
## @param is_entry: True for entry hole, false for exit hole.
func _spawn_penetration_hole_effect(_body: Node2D, _pos: Vector2, _is_entry: bool) -> void:
	# All visual effects disabled as per user request
	# The entry/exit positions couldn't be properly anchored to wall surfaces
	pass


## Spawns a collision hole that creates an actual gap in wall collision.
## This allows other bullets and vision to pass through the hole.
## @param entry_point: Where the bullet entered the wall.
## @param exit_point: Where the bullet exited the wall.
func _spawn_collision_hole(entry_point: Vector2, exit_point: Vector2) -> void:
	var impact_manager: Node = get_node_or_null("/root/ImpactEffectsManager")
	if impact_manager == null:
		return

	if impact_manager.has_method("spawn_collision_hole"):
		impact_manager.spawn_collision_hole(entry_point, exit_point, direction, caliber_data)
		_log_penetration("Collision hole spawned from %s to %s" % [entry_point, exit_point])


## Returns whether the bullet has penetrated at least one wall.
func has_penetrated() -> bool:
	return _has_penetrated


## Returns whether the bullet is currently penetrating a wall.
func is_penetrating() -> bool:
	return _is_penetrating


## Returns the distance traveled through walls while penetrating.
func get_penetration_distance() -> float:
	return _penetration_distance_traveled


# ============================================================================
# C# Interop Setter Methods (Issue #781)
# ============================================================================
# GDScript non-@export variables cannot be set from C# via Node.Set() - it silently fails.
# These setter methods allow C# weapons to properly configure GDScript bullets via Call().
# Must be called BEFORE AddChild() so that _ready() uses the correct values.


## Sets the bullet travel direction and updates rotation.
## Called from C# weapons via Call("set_direction", dir).
func set_direction(dir: Vector2) -> void:
	direction = dir.normalized()
	_update_rotation()


## Sets the bullet speed.
func set_speed(spd: float) -> void:
	speed = spd


## Sets the bullet damage.
func set_damage(dmg: float) -> void:
	damage = dmg


## Sets the shooter instance ID for self-hit prevention.
func set_shooter_id(id: int) -> void:
	shooter_id = id


## Sets the shooter position for distance-based penetration calculations.
func set_shooter_position(pos: Vector2) -> void:
	shooter_position = pos


## Sets the stun duration applied to enemies on hit.
func set_stun_duration(duration: float) -> void:
	stun_duration = duration


## Sets whether this bullet uses breaker behavior.
## NOTE: Call this BEFORE AddChild() so _ready() loads the shrapnel scene.
func set_is_breaker_bullet(is_breaker: bool) -> void:
	is_breaker_bullet = is_breaker


## Sets whether this bullet ignores walls (Issue #751).
## Called by BaseWeapon.SpawnBullet() when DrillingBulletsRemaining > 0.
func set_is_drilling_bullet(drilling: bool) -> void:
	is_drilling_bullet = drilling


## Sets whether this bullet penetrates through enemies (Issue #829).
func set_penetrates_enemies(penetrate: bool) -> void:
	penetrates_enemies = penetrate


# ============================================================================
# Homing Bullet System (Issue #677)
# ============================================================================


## Enables homing on this bullet, storing the original direction.
func enable_homing() -> void:
	homing_enabled = true
	_homing_original_direction = direction.normalized()
	if _debug_homing:
		print("[Bullet] Homing enabled, original direction: ", _homing_original_direction)


## Enables homing with aim-line targeting (Issue #704, #781).
## Called when firing new bullets during homing activation.
## Targets the enemy closest to the player's line of fire, matching C# Bullet.cs behavior.
## @param shooter_pos: The player's position when firing.
## @param aim_dir: The player's aim direction when firing.
func enable_homing_with_aim_line(shooter_pos: Vector2, aim_dir: Vector2) -> void:
	homing_enabled = true
	_homing_original_direction = direction.normalized()
	_use_aim_line_targeting = true
	_homing_shooter_origin = shooter_pos
	_homing_aim_direction = aim_dir.normalized()
	if _debug_homing:
		print("[Bullet] Homing enabled with aim-line targeting, aim: ", _homing_aim_direction)


## Applies homing steering toward the nearest alive enemy.
## The bullet turns toward the nearest enemy but cannot exceed the max turn angle
## from its original firing direction (110 degrees each side).
func _apply_homing_steering(delta: float) -> void:
	# Only player bullets should home
	if not _is_player_bullet():
		return

	# Find nearest alive enemy
	var target_pos := _find_nearest_enemy_position()
	if target_pos == Vector2.ZERO:
		return  # No valid target found

	# Calculate desired direction toward target
	var to_target := (target_pos - global_position).normalized()

	# Calculate the angle difference between current direction and desired
	var angle_diff := direction.angle_to(to_target)

	# Limit per-frame steering (smooth turning)
	var max_steer_this_frame := homing_steer_speed * delta
	angle_diff = clampf(angle_diff, -max_steer_this_frame, max_steer_this_frame)

	# Calculate proposed new direction
	var new_direction := direction.rotated(angle_diff).normalized()

	# Check if the new direction would exceed the max turn angle from original
	var angle_from_original := _homing_original_direction.angle_to(new_direction)
	if absf(angle_from_original) > homing_max_turn_angle:
		if _debug_homing:
			print("[Bullet] Homing angle limit reached: ", rad_to_deg(absf(angle_from_original)), "°")
		return  # Don't steer further, angle limit reached

	# Apply the steering
	direction = new_direction
	_update_rotation()

	if _debug_homing:
		print("[Bullet] Homing steer: angle_diff=", rad_to_deg(angle_diff), "° total_turn=", rad_to_deg(absf(angle_from_original)), "°")


## Gently steers the RPG rocket toward the player (Issue #1135).
## Called every physics frame for enemy-fired RPG rockets.
## Uses angular clamping identical to _apply_homing_steering() but targets the player
## (not enemies) and is guarded by rpg_homing_max_turn_angle from the original firing direction.
func _apply_rpg_homing_steering(delta: float) -> void:
	var tree := get_tree()
	if tree == null:
		return

	# Find the player
	var players := tree.get_nodes_in_group("player")
	if players.is_empty():
		return
	var player: Node = players[0]
	if not player is Node2D:
		return
	# Skip dead player
	if player.has_method("is_alive") and not (player as Node).call("is_alive"):
		return

	var target_pos: Vector2 = (player as Node2D).global_position

	# Direction toward player from current rocket position
	var to_target := (target_pos - global_position).normalized()

	# Signed angle between current direction and desired direction
	var angle_diff := direction.angle_to(to_target)

	# Clamp per-frame turn (smooth steering)
	var max_steer_this_frame := rpg_homing_steer_speed * delta
	angle_diff = clampf(angle_diff, -max_steer_this_frame, max_steer_this_frame)

	# Candidate new direction
	var new_direction := direction.rotated(angle_diff).normalized()

	# Do not exceed total turn limit from original firing direction
	var angle_from_original := _rpg_homing_original_direction.angle_to(new_direction)
	if absf(angle_from_original) > rpg_homing_max_turn_angle:
		return

	# Apply steering — sprite rotation is handled by the RPG block in _physics_process
	direction = new_direction


## Finds the position of the best homing target enemy.
## When aim-line targeting is active (Issue #704, #781), finds the enemy closest
## to the player's line of fire. Otherwise, finds the nearest enemy to the bullet.
## Returns Vector2.ZERO if no enemies are found.
func _find_nearest_enemy_position() -> Vector2:
	var tree := get_tree()
	if tree == null:
		return Vector2.ZERO

	var enemies := tree.get_nodes_in_group("enemies")
	if enemies.is_empty():
		return Vector2.ZERO

	if _use_aim_line_targeting:
		return _find_enemy_nearest_to_aim_line(enemies)

	var nearest_pos := Vector2.ZERO
	var nearest_dist := INF

	for enemy in enemies:
		if not enemy is Node2D:
			continue
		# Skip dead enemies
		if enemy.has_method("is_alive") and not enemy.is_alive():
			continue
		# Skip enemies behind walls (Issue #709)
		if not _has_line_of_sight_to_target(enemy.global_position):
			if _debug_homing:
				print("[Bullet] Skipping enemy ", enemy.name, " - wall blocks line of sight")
			continue
		var dist := global_position.distance_squared_to(enemy.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_pos = enemy.global_position

	return nearest_pos


## Finds the enemy closest to the player's aim line (Issue #704, #781).
## Uses perpendicular distance from the aim ray to score enemies.
## Only considers enemies within max turn angle of the aim direction.
## Skips enemies blocked by walls (Issue #709).
## Returns Vector2.ZERO if no valid target found.
func _find_enemy_nearest_to_aim_line(enemies: Array[Node]) -> Vector2:
	var best_target := Vector2.ZERO
	var best_score := INF
	var max_perp_distance := 500.0

	for enemy in enemies:
		if not enemy is Node2D:
			continue
		if enemy.has_method("is_alive") and not enemy.is_alive():
			continue

		var to_enemy: Vector2 = enemy.global_position - _homing_shooter_origin
		var dist_to_enemy := to_enemy.length()
		if dist_to_enemy < 1.0:
			continue

		# Check angle from aim direction
		var angle := absf(_homing_aim_direction.angle_to(to_enemy.normalized()))
		if angle > homing_max_turn_angle:
			continue

		# Perpendicular distance from aim line (cross product magnitude)
		var perp_dist := absf(to_enemy.x * _homing_aim_direction.y - to_enemy.y * _homing_aim_direction.x)
		if perp_dist > max_perp_distance:
			continue

		# Skip enemies behind walls (Issue #709)
		if not _has_line_of_sight_to_target(enemy.global_position):
			if _debug_homing:
				print("[Bullet] Skipping enemy ", enemy.name, " - wall blocks line of sight (aim-line)")
			continue

		# Score: prioritize closeness to aim line, with distance as tiebreaker
		var score := perp_dist + dist_to_enemy * 0.1
		if score < best_score:
			best_score = score
			best_target = enemy.global_position

	return best_target


## Checks if there is clear line of sight from the bullet to a target position (Issue #709, #781).
## Uses a physics raycast against obstacles (collision layer 3 = mask 4) to detect walls.
## Returns false if a wall blocks the path, preventing bullets from turning into walls.
func _has_line_of_sight_to_target(target_pos: Vector2) -> bool:
	var space_state := get_world_2d().direct_space_state
	if space_state == null:
		return true  # Can't check, assume clear

	var query := PhysicsRayQueryParameters2D.create(global_position, target_pos)
	query.collision_mask = 4  # Layer 3 = obstacles/walls only
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [self]

	var result := space_state.intersect_ray(query)
	return result.is_empty()  # True if no wall in the way


# ============================================================================
# Breaker Bullet System (Issue #678)
# ============================================================================


## Checks if a wall is within BREAKER_DETONATION_DISTANCE ahead, or if an alive enemy
## is within the shrapnel cone sector (Issue #1634: proximity fuse should detonate early
## when an enemy enters the sector of future shrapnel to maximise shrapnel hit chance).
## @return: True if detonation occurred, false otherwise.
func _check_breaker_detonation() -> bool:
	var space_state := get_world_2d().direct_space_state
	if space_state == null:
		return false

	# 1. Raycast forward for wall detection (straight ahead only).
	var ray_start := global_position
	var ray_end := global_position + direction * BREAKER_DETONATION_DISTANCE

	var wall_query := PhysicsRayQueryParameters2D.create(ray_start, ray_end)
	wall_query.collision_mask = collision_mask
	wall_query.exclude = [self]

	var wall_result := space_state.intersect_ray(wall_query)

	if not wall_result.is_empty():
		var collider: Object = wall_result.collider
		if collider is StaticBody2D or collider is TileMap:
			# Wall detected within range — trigger detonation!
			if _debug_breaker:
				FileLogger.info("[Bullet.Breaker] Wall detected at distance %.1f, detonating" % [
					global_position.distance_to(wall_result.position)])
			_breaker_detonate(global_position)
			return true

	# 2. Cone sector check for enemies (Issue #1634).
	# Detonate when an alive enemy is inside the shrapnel cone sector:
	# distance <= BREAKER_DETONATION_DISTANCE AND angle from bullet direction <= BREAKER_SHRAPNEL_HALF_ANGLE.
	# This is a simple geometric check — no additional physics queries needed.
	if _check_enemy_in_shrapnel_cone():
		return true

	return false  # Nothing triggering detonation


## Returns true if any alive enemy is within the shrapnel cone sector ahead.
## The cone is defined by BREAKER_DETONATION_DISTANCE (radius) and
## BREAKER_SHRAPNEL_HALF_ANGLE (half-angle from the bullet's travel direction).
## Optimization: uses dot product comparison instead of acos for the angle check.
func _check_enemy_in_shrapnel_cone() -> bool:
	var cos_half_angle := cos(deg_to_rad(BREAKER_SHRAPNEL_HALF_ANGLE))
	var enemies := get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if not (enemy is Node2D):
			continue
		if not (enemy.has_method("is_alive") and enemy.is_alive()):
			continue
		var to_enemy := enemy.global_position - global_position
		var dist := to_enemy.length()
		if dist > BREAKER_DETONATION_DISTANCE:
			continue
		# Dot product of normalized vectors: equals cos(angle_between).
		# If cos(angle) >= cos(half_angle), the angle is within the cone.
		if dist > 0.0 and (to_enemy / dist).dot(direction) >= cos_half_angle:
			if _debug_breaker:
				FileLogger.info("[Bullet.Breaker] Enemy %s in shrapnel cone at distance %.1f, detonating" % [
					enemy.name, dist])
			_breaker_detonate(global_position)
			return true
	return false


## Triggers the breaker bullet detonation: explosion damage + shrapnel cone.
## @param detonation_pos: The position where the detonation occurs.
func _breaker_detonate(detonation_pos: Vector2) -> void:
	# 1. Apply explosion damage in radius
	_breaker_apply_explosion_damage(detonation_pos)

	# 2. Spawn visual explosion effect
	_breaker_spawn_explosion_effect(detonation_pos)

	# 3. Spawn shrapnel in a forward cone
	_breaker_spawn_shrapnel(detonation_pos)

	# 4. Play explosion sound
	_breaker_play_explosion_sound(detonation_pos)

	# 5. Destroy the bullet
	_destroy()


## Applies explosion damage to all enemies within BREAKER_EXPLOSION_RADIUS.
## @param center: Center of the explosion.
func _breaker_apply_explosion_damage(center: Vector2) -> void:
	# Find all enemies in the scene
	var enemies := get_tree().get_nodes_in_group("enemies")
	var players := get_tree().get_nodes_in_group("player")

	# Check enemies in radius
	for enemy in enemies:
		if enemy is Node2D and enemy.has_method("is_alive") and enemy.is_alive():
			var distance := center.distance_to(enemy.global_position)
			if distance <= BREAKER_EXPLOSION_RADIUS:
				# Check line of sight
				if _breaker_has_line_of_sight(center, enemy.global_position):
					_breaker_apply_damage_to(enemy, BREAKER_EXPLOSION_DAMAGE)

	# Also check player (breaker explosion can hurt the player at close range)
	for player in players:
		if player is Node2D:
			# Don't damage the shooter
			if shooter_id == player.get_instance_id():
				continue
			var distance := center.distance_to(player.global_position)
			if distance <= BREAKER_EXPLOSION_RADIUS:
				if _breaker_has_line_of_sight(center, player.global_position):
					_breaker_apply_damage_to(player, BREAKER_EXPLOSION_DAMAGE)


## Applies damage to a target.
func _breaker_apply_damage_to(target: Node2D, amount: float) -> void:
	var hit_direction := (target.global_position - global_position).normalized()
	var from_player: bool = _is_player_bullet()  # Issue #1196: track kill source for unlock conditions

	if target.has_method("on_hit_with_bullet_info_and_damage"):
		target.on_hit_with_bullet_info_and_damage(hit_direction, null, false, false, amount, from_player)
	elif target.has_method("on_hit_with_info"):
		target.on_hit_with_info(hit_direction, null)
	elif target.has_method("on_hit"):
		target.on_hit()

	if _debug_breaker:
		FileLogger.info("[Bullet.Breaker] Explosion damage %.1f applied to %s" % [amount, target.name])


## Checks line of sight from a position to a target position.
func _breaker_has_line_of_sight(from: Vector2, to: Vector2) -> bool:
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collision_mask = 4  # Only check against obstacles
	query.exclude = [self]
	var result := space_state.intersect_ray(query)
	return result.is_empty()


## Spawns a small visual explosion effect at the detonation point.
func _breaker_spawn_explosion_effect(center: Vector2) -> void:
	var impact_manager: Node = get_node_or_null("/root/ImpactEffectsManager")

	if impact_manager and impact_manager.has_method("spawn_explosion_effect"):
		impact_manager.spawn_explosion_effect(center, BREAKER_EXPLOSION_RADIUS)
	else:
		# Fallback: create simple flash
		_breaker_create_simple_flash(center)


## Plays a small explosion sound at the detonation point.
func _breaker_play_explosion_sound(center: Vector2) -> void:
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_bullet_wall_hit"):
		# Use wall hit sound as explosion (small detonation)
		audio_manager.play_bullet_wall_hit(center)

	# Emit sound for AI awareness
	var sound_propagation: Node = get_node_or_null("/root/SoundPropagation")
	if sound_propagation and sound_propagation.has_method("emit_sound"):
		# Small explosion — use shorter range than grenade
		sound_propagation.emit_sound(1, center, 0, self, 500.0)  # 1 = EXPLOSION, 0 = PLAYER


## Creates a simple explosion flash if no manager is available.
func _breaker_create_simple_flash(center: Vector2) -> void:
	var flash := Sprite2D.new()
	var size := int(BREAKER_EXPLOSION_RADIUS) * 2
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var img_center := Vector2(BREAKER_EXPLOSION_RADIUS, BREAKER_EXPLOSION_RADIUS)

	for x in range(size):
		for y in range(size):
			var pos := Vector2(x, y)
			var dist := pos.distance_to(img_center)
			if dist <= BREAKER_EXPLOSION_RADIUS:
				var alpha := 1.0 - (dist / BREAKER_EXPLOSION_RADIUS)
				image.set_pixel(x, y, Color(1.0, 0.8, 0.4, alpha))
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))

	flash.texture = ImageTexture.create_from_image(image)
	flash.global_position = center
	flash.modulate = Color(1.0, 0.7, 0.3, 0.9)
	flash.z_index = 100

	var scene := get_tree().current_scene
	if scene:
		scene.add_child(flash)
		var tween := get_tree().create_tween()
		tween.tween_property(flash, "modulate:a", 0.0, 0.15)
		tween.tween_callback(flash.queue_free)


## Maximum shrapnel pieces per single detonation (performance cap, Issue #678 optimization).
## This prevents FPS drops when many pellets detonate simultaneously (e.g. shotgun).
const BREAKER_MAX_SHRAPNEL_PER_DETONATION: int = 10

## Maximum total concurrent breaker shrapnel in the scene (global cap).
## If exceeded, new shrapnel spawning is skipped to maintain FPS.
const BREAKER_MAX_CONCURRENT_SHRAPNEL: int = 60


## Checks if a position is inside a wall or obstacle (Issue #740).
## Used to prevent spawning shrapnel inside walls.
## @param pos: The position to check.
## @return: true if position is inside a wall, false otherwise.
func _is_position_inside_wall(pos: Vector2) -> bool:
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.position = pos
	query.collision_mask = 4  # Layer 3 (obstacles/walls)
	var result := space_state.intersect_point(query, 1)
	return not result.is_empty()


## Spawns breaker shrapnel pieces in a forward cone.
## Shrapnel count is capped for performance (Issue #678 optimization).
## Validates spawn positions to prevent shrapnel spawning behind walls (Issue #740).
func _breaker_spawn_shrapnel(center: Vector2) -> void:
	if _breaker_shrapnel_scene == null:
		if _debug_breaker:
			FileLogger.info("[Bullet.Breaker] Cannot spawn shrapnel: scene is null")
		return

	# Check global concurrent shrapnel limit
	var existing_shrapnel := get_tree().get_nodes_in_group("breaker_shrapnel")
	if existing_shrapnel.size() >= BREAKER_MAX_CONCURRENT_SHRAPNEL:
		if _debug_breaker:
			FileLogger.info("[Bullet.Breaker] Skipping shrapnel spawn: global limit %d reached" % BREAKER_MAX_CONCURRENT_SHRAPNEL)
		return

	# Calculate shrapnel count based on bullet damage, capped for performance
	var effective_damage := damage * damage_multiplier
	var shrapnel_count := int(effective_damage * BREAKER_SHRAPNEL_COUNT_MULTIPLIER)
	shrapnel_count = clampi(shrapnel_count, 1, BREAKER_MAX_SHRAPNEL_PER_DETONATION)

	# Further reduce if approaching global limit
	var remaining_budget := BREAKER_MAX_CONCURRENT_SHRAPNEL - existing_shrapnel.size()
	shrapnel_count = mini(shrapnel_count, remaining_budget)

	var half_angle_rad := deg_to_rad(BREAKER_SHRAPNEL_HALF_ANGLE)

	var scene := get_tree().current_scene
	if scene == null:
		return

	var spawned_count := 0
	var skipped_count := 0

	for i in range(shrapnel_count):
		# Random angle within the forward cone
		var random_angle := randf_range(-half_angle_rad, half_angle_rad)
		var shrapnel_direction := direction.rotated(random_angle)

		# Calculate potential spawn position (Issue #740 fix)
		var spawn_offset := 5.0
		var spawn_pos := center + shrapnel_direction * spawn_offset

		# Check if spawn position is inside a wall (Issue #740 fix)
		if _is_position_inside_wall(spawn_pos):
			if _debug_breaker:
				FileLogger.info("[Bullet.Breaker] Skipping shrapnel #%d: spawn position inside wall at %s" % [i, spawn_pos])
			skipped_count += 1
			continue

		# Try pooled breaker shrapnel first for performance (Issue #724)
		var shrapnel: Node = null
		var pool_manager: Node = get_node_or_null("/root/ProjectilePoolManager")

		if pool_manager and pool_manager.has_method("get_breaker_shrapnel"):
			shrapnel = pool_manager.get_breaker_shrapnel()
			if shrapnel and shrapnel.has_method("pool_activate"):
				shrapnel.pool_activate(spawn_pos, shrapnel_direction, shooter_id)
				shrapnel.damage = BREAKER_SHRAPNEL_DAMAGE
				shrapnel.speed = randf_range(1400.0, 2200.0)
				spawned_count += 1
				continue  # Shrapnel is ready, skip to next

		# Fallback to instantiation
		shrapnel = _breaker_shrapnel_scene.instantiate()
		if shrapnel == null:
			continue

		# Set shrapnel properties
		shrapnel.global_position = spawn_pos
		shrapnel.direction = shrapnel_direction
		shrapnel.source_id = shooter_id  # Prevent self-damage using original shooter
		shrapnel.damage = BREAKER_SHRAPNEL_DAMAGE

		# Vary speed slightly for natural spread
		shrapnel.speed = randf_range(1400.0, 2200.0)

		# Add to scene using call_deferred to batch scene tree changes (Issue #678 optimization)
		scene.call_deferred("add_child", shrapnel)
		spawned_count += 1

	if _debug_breaker:
		FileLogger.info("[Bullet.Breaker] Spawned %d shrapnel pieces (%d skipped, budget: %d) in %.0f-degree cone" % [
			spawned_count, skipped_count, remaining_budget, BREAKER_SHRAPNEL_HALF_ANGLE * 2])


# ============================================================================
# Object Pooling Support (Issue #724)
# ============================================================================


## Whether this bullet is currently pooled (inactive).
var _is_pooled: bool = false

## Original speed value for reset.
var _original_speed: float = 2500.0


## Activates the bullet from the pool with the given parameters.
## Call this instead of setting properties directly after getting from pool.
## @param pos: Global position to spawn at.
## @param dir: Direction of travel.
## @param shooter: Instance ID of the shooter (for self-damage prevention).
## @param caliber: Optional caliber data resource.
func pool_activate(pos: Vector2, dir: Vector2, shooter: int, caliber: Resource = null) -> void:
	# Reset all state to defaults
	_reset_state()

	# Set activation parameters
	global_position = pos
	direction = dir.normalized()
	shooter_id = shooter
	shooter_position = pos
	caliber_data = caliber if caliber else _load_default_caliber_data()

	# Update rotation to match direction
	_update_rotation()

	# Re-enable processing and visibility
	visible = true
	set_physics_process(true)
	set_process(true)

	# Issue #1334 Round 11: Defer collision re-enable to avoid "flushing queries" error.
	# Setting monitoring=true during physics processing can corrupt the physics server's
	# internal collision pair list when many bullets are pooled/recycled in the same frame.
	set_deferred("monitoring", true)
	set_deferred("monitorable", true)

	_is_pooled = false


## Deactivates the bullet and prepares it for return to the pool.
## Call this instead of queue_free() when using pooling.
func pool_deactivate() -> void:
	if _is_pooled:
		return

	_is_pooled = true

	# Disable processing
	set_physics_process(false)
	set_process(false)

	# Hide bullet
	visible = false

	# Issue #1334 Round 11: Defer collision disable to avoid "flushing queries" corruption
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)

	# Clear trail
	if _trail:
		_trail.clear_points()
	_position_history.clear()

	# Return to pool manager
	var pool_manager: Node = get_node_or_null("/root/ProjectilePoolManager")
	if pool_manager and pool_manager.has_method("return_bullet"):
		pool_manager.return_bullet(self)


## Resets all bullet state to defaults for reuse.
func _reset_state() -> void:
	# Reset core properties
	speed = _original_speed
	damage = 1.0
	damage_multiplier = 1.0
	_time_alive = 0.0
	direction = Vector2.RIGHT
	shooter_id = -1
	shooter_position = Vector2.ZERO

	# Reset ricochet state
	_ricochet_count = 0
	_has_ricocheted = false
	_distance_since_ricochet = 0.0
	_ricochet_position = Vector2.ZERO
	_max_post_ricochet_distance = 0.0

	# Reset penetration state
	_is_penetrating = false
	_penetration_distance_traveled = 0.0
	_penetration_entry_point = Vector2.ZERO
	_penetrating_body = null
	_has_penetrated = false

	# Reset homing state
	homing_enabled = false
	_homing_original_direction = Vector2.ZERO

	# Reset breaker state
	is_breaker_bullet = false
	_breaker_shrapnel_scene = null

	# Reset stun
	stun_duration = 0.0

	# Clear position history
	_position_history.clear()

	# Clear trail
	if _trail:
		_trail.clear_points()


## Returns whether this bullet is currently pooled (inactive).
func is_pooled() -> bool:
	return _is_pooled


## Destroys the bullet using pooling when available, otherwise queue_free.
## This method should be used instead of direct queue_free() calls for proper pooling.
func _destroy() -> void:
	if _is_pooled:
		return  # Already pooled

	# Try to use pooling if pool manager is available
	var pool_manager: Node = get_node_or_null("/root/ProjectilePoolManager")
	if pool_manager:
		pool_deactivate()
	else:
		queue_free()


## Override queue_free to use pooling when available.
## This allows existing code to continue using queue_free() without changes.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# If we're being deleted and pool manager exists, this might be an error
		# The pool system should use pool_deactivate instead
		pass


## Convenience method to get a bullet from the pool.
## Returns null if pool manager not available, in which case use instantiate().
static func from_pool() -> Node:
	var pool_manager: Node = Engine.get_singleton("ProjectilePoolManager") if Engine.has_singleton("ProjectilePoolManager") else null
	if pool_manager == null:
		# Try alternative path
		var tree := Engine.get_main_loop() as SceneTree
		if tree:
			pool_manager = tree.root.get_node_or_null("ProjectilePoolManager")
	if pool_manager and pool_manager.has_method("get_bullet"):
		return pool_manager.get_bullet()
	return null


## RPG rocket explosion (Issue #583).
## Called instead of normal bullet destruction when is_rpg_rocket = true.
func _rpg_explode() -> void:
	if _rpg_has_exploded:
		return
	_rpg_has_exploded = true

	FileLogger.info("[RpgRocket] Exploded at pos=%s after %.2fs, dist=%.0fpx" % [
		str(global_position), _rpg_time_alive, _rpg_distance_traveled])

	# Carve a wall passage when the rocket hits a StaticBody2D wall (Issue #1131, #1144).
	# Uses WallBreachHelper — same 120 px passage as the "Breaching Charges" active item.
	# Uses the precise surface hit position (_rpg_hit_position) instead of rocket center
	# (global_position) so the breach is centered at the true impact point (Issue #1144).
	var directly_hit_wall: StaticBody2D = null
	if _rpg_hit_wall != null and is_instance_valid(_rpg_hit_wall):
		directly_hit_wall = _rpg_hit_wall
		var breach_pos: Vector2 = _rpg_hit_position if _rpg_hit_position != Vector2.ZERO else global_position
		FileLogger.info("[RpgRocket] Creating wall passage in '%s' at %s" % [directly_hit_wall.name, str(breach_pos)])
		WallBreachHelper.open_wall_passage(directly_hit_wall, breach_pos)
		_rpg_hit_wall = null
		_rpg_hit_position = Vector2.ZERO

	# Destroy all StaticBody2D obstacles within explosion radius (Issue #1144).
	# Piercing Charges destroy walls at the placement point; RPG should destroy all
	# obstacles in the blast area, not just the one directly hit.
	_rpg_breach_obstacles_in_radius(directly_hit_wall)

	# Stop exhaust particles
	var exhaust: Node = get_node_or_null("ExhaustParticles")
	if exhaust and exhaust.has_method("set"):
		exhaust.set("emitting", false)

	# Power Fantasy rocket explosion effect
	var power_fantasy_manager: Node = get_node_or_null("/root/PowerFantasyEffectsManager")
	if power_fantasy_manager and power_fantasy_manager.has_method("on_grenade_exploded"):
		power_fantasy_manager.on_grenade_exploded()

	# Explosion sound via AudioManager
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_offensive_grenade_explosion"):
		audio_manager.play_offensive_grenade_explosion(global_position)

	# Sound propagation
	var sound_propagation: Node = get_node_or_null("/root/SoundPropagation")
	if sound_propagation and sound_propagation.has_method("emit_sound"):
		var viewport := get_viewport()
		var vp_diagonal := 1469.0
		if viewport:
			var sz := viewport.get_visible_rect().size
			vp_diagonal = sqrt(sz.x * sz.x + sz.y * sz.y)
		sound_propagation.emit_sound(1, global_position, 1, self, vp_diagonal * 2.0)

	# Damage all entities in explosion radius
	_rpg_damage_in_radius()

	# Spawn visual explosion effect
	var impact_manager: Node = get_node_or_null("/root/ImpactEffectsManager")
	if impact_manager and impact_manager.has_method("spawn_explosion_effect"):
		impact_manager.spawn_explosion_effect(global_position, rpg_explosion_radius)
	else:
		_rpg_simple_explosion_flash()

	# Destroy after brief delay for visual effect
	await get_tree().create_timer(0.1).timeout
	_destroy()


## RPG rocket: apply explosion damage to all entities in radius.
func _rpg_damage_in_radius() -> void:
	var space_state := get_world_2d().direct_space_state
	var enemies := get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy is Node2D and _rpg_in_radius(enemy.global_position) and _rpg_has_los(space_state, enemy.global_position):
			_rpg_apply_damage(enemy)
	var players := get_tree().get_nodes_in_group("player")
	for player in players:
		if player is Node2D and _rpg_in_radius(player.global_position) and _rpg_has_los(space_state, player.global_position):
			_rpg_apply_damage(player)
	# Intercept other RPG rockets in the blast radius (Issue #1133)
	var rockets := get_tree().get_nodes_in_group("rpg_rockets")
	for rocket in rockets:
		if rocket != self and rocket is Node2D and _rpg_in_radius(rocket.global_position):
			if rocket.has_method("on_hit"):
				rocket.on_hit()


func _rpg_in_radius(pos: Vector2) -> bool:
	return global_position.distance_to(pos) <= rpg_explosion_radius


func _rpg_has_los(space_state: PhysicsDirectSpaceState2D, target_pos: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(global_position, target_pos)
	query.collision_mask = 4
	query.exclude = [self]
	return space_state.intersect_ray(query).is_empty()


func _rpg_apply_damage(entity: Node2D) -> void:
	var hit_dir := (entity.global_position - global_position).normalized()
	if entity.has_method("on_hit_with_info"):
		for i in range(rpg_explosion_damage):
			entity.on_hit_with_info(hit_dir, null)
	elif entity.has_method("on_hit"):
		for i in range(rpg_explosion_damage):
			entity.on_hit()


## RPG rocket: breach (destroy) all StaticBody2D obstacles within explosion radius (Issue #1144).
##
## Piercing Charges destroy only the one wall they are placed on.
## The RPG rocket explodes with a 150px radius blast, so ALL obstacles within that
## radius should be destroyed/breached — not just the one the rocket body touched.
##
## For each StaticBody2D on the obstacle collision layer (4) within explosion_radius:
## - If it is not already the directly-hit wall (handled separately above), breach it.
## - Use the closest point on the obstacle's bounding area as the breach position.
## - Skips non-StaticBody2D bodies (enemies, player, other rockets).
## @param already_hit_wall: The StaticBody2D already breached by direct hit (skip it here).
func _rpg_breach_obstacles_in_radius(already_hit_wall: StaticBody2D) -> void:
	if not is_inside_tree():
		return
	var space_state := get_world_2d().direct_space_state

	# Use a circle shape query to find all physics bodies in the explosion radius.
	var circle_shape := CircleShape2D.new()
	circle_shape.radius = rpg_explosion_radius

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle_shape
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = 4  # Obstacle layer only
	query.exclude = [self]

	var results := space_state.intersect_shape(query)

	var breached_count := 0
	for hit in results:
		var body: Object = hit.get("collider", null)
		if body == null or not (body is StaticBody2D):
			continue
		var wall: StaticBody2D = body as StaticBody2D
		# Skip the wall already breached by the direct hit above.
		if wall == already_hit_wall:
			continue
		# Use rocket impact position as the breach center for nearby obstacles.
		# This is approximate but correct for blast-radius destruction.
		WallBreachHelper.open_wall_passage(wall, global_position)
		breached_count += 1

	if breached_count > 0:
		FileLogger.info("[RpgRocket] Breached %d obstacle(s) in explosion radius" % breached_count)


## RPG rocket: simple orange explosion flash when ImpactEffectsManager unavailable.
func _rpg_simple_explosion_flash() -> void:
	if not is_inside_tree():
		return
	var flash := ColorRect.new()
	flash.size = Vector2(rpg_explosion_radius * 2, rpg_explosion_radius * 2)
	flash.position = global_position - Vector2(rpg_explosion_radius, rpg_explosion_radius)
	flash.color = Color(1.0, 0.5, 0.1, 0.7)
	flash.z_index = 100
	get_tree().current_scene.add_child(flash)
	var tween := get_tree().create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 0.3)
	tween.tween_callback(flash.queue_free)


## RPG rocket: receive incoming damage from bullets, shrapnel, or explosions (Issue #1133, #1307).
## When health drops to 0 the rocket explodes (full AOE explosion).
## Ignored if rpg_health == 0 (interception disabled) or rocket already destroyed.
func on_hit() -> void:
	if not is_rpg_rocket or _rpg_has_exploded:
		return
	if rpg_health <= 0:
		return  # Interception disabled for this rocket
	_rpg_current_health -= 1
	FileLogger.info("[RpgRocket] Hit! remaining_health=%d pos=%s" % [_rpg_current_health, str(global_position)])
	if _rpg_current_health <= 0:
		FileLogger.info("[RpgRocket] Shot down by hit — exploding at pos=%s" % str(global_position))
		_rpg_explode()


## RPG rocket: variant accepting hit direction and caliber data (Issue #1133).
func on_hit_with_info(_hit_direction: Vector2, _caliber: Resource) -> void:
	on_hit()


## RPG rocket: variant accepting full bullet info including damage amount (Issue #1133).
func on_hit_with_bullet_info_and_damage(_hit_direction: Vector2, _caliber: Resource,
		_ricocheted: bool, _penetrated: bool, _dmg: float) -> void:
	on_hit()


## RPG rocket: destroy the rocket after being shot down — no explosion (Issue #1133).
## A small flash indicates the intercept point.
func _rpg_intercept() -> void:
	if _rpg_has_exploded:
		return
	_rpg_has_exploded = true  # Prevent double-processing

	FileLogger.info("[RpgRocket] Shot down at pos=%s after %.2fs dist=%.0fpx" % [
		str(global_position), _rpg_time_alive, _rpg_distance_traveled])

	# Stop exhaust particles
	var exhaust: Node = get_node_or_null("ExhaustParticles")
	if exhaust:
		exhaust.set("emitting", false)

	# Small white flash to indicate intercept (no explosion AOE)
	if is_inside_tree():
		var flash := ColorRect.new()
		var flash_size := 30.0
		flash.size = Vector2(flash_size * 2, flash_size * 2)
		flash.position = global_position - Vector2(flash_size, flash_size)
		flash.color = Color(1.0, 1.0, 1.0, 0.8)
		flash.z_index = 100
		get_tree().current_scene.add_child(flash)
		var tween := get_tree().create_tween()
		tween.tween_property(flash, "modulate:a", 0.0, 0.2)
		tween.tween_callback(flash.queue_free)

	_destroy()
