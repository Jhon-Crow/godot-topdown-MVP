extends CharacterBody2D
## Enemy AI with tactical behaviors: patrol, guard, cover, flanking, GOAP.

## AI States for tactical behavior.
enum AIState {
	IDLE,       ## Default idle state (patrol or guard)
	COMBAT,     ## Actively engaging the player (coming out of cover, shooting 2-3s, returning)
	SEEKING_COVER,  ## Moving to cover position
	IN_COVER,   ## Taking cover from player fire
	FLANKING,   ## Attempting to flank the player
	SUPPRESSED, ## Under fire, staying in cover
	RETREATING, ## Retreating to cover while possibly shooting
	PURSUING,   ## Moving cover-to-cover toward player (when far and can't hit)
	ASSAULT,    ## Coordinated multi-enemy assault (rush player after 5s wait)
	SEARCHING   ## Methodically searching area where player was last seen (Issue #322)
}

## Retreat behavior modes based on damage taken.
enum RetreatMode {
	FULL_HP,        ## No damage - retreat backwards while shooting, periodically turn to cover
	ONE_HIT,        ## One hit taken - quick burst then retreat without shooting
	MULTIPLE_HITS   ## Multiple hits - quick burst then retreat without shooting (same as ONE_HIT)
}

## Behavior modes for the enemy.
enum BehaviorMode {
	PATROL,  ## Moves between patrol points
	GUARD    ## Stands in one place
}

## Current behavior mode.
@export var behavior_mode: BehaviorMode = BehaviorMode.GUARD

## Maximum movement speed in pixels per second.
@export var move_speed: float = 220.0

## Combat movement speed (faster when flanking/seeking cover).
@export var combat_move_speed: float = 320.0

## Rotation speed in rad/sec (25 for aim-before-shoot per issue #254).
@export var rotation_speed: float = 25.0
## Detection range (0=unlimited, line-of-sight only).
@export var detection_range: float = 0.0

## Field of view angle in degrees (cone centered on facing dir). 0 or negative = 360° vision. Default 100° per issue #66.
@export var fov_angle: float = 100.0

## FOV enabled for this enemy (combined with ExperimentalSettings.fov_enabled, both must be true).
@export var fov_enabled: bool = true

## Time between shots (0.1s = 10 rounds/sec).
@export var shoot_cooldown: float = 0.1

## Bullet scene to instantiate when shooting.
@export var bullet_scene: PackedScene

## Casing scene to instantiate when firing (for ejected bullet casings).
@export var casing_scene: PackedScene

## Offset from enemy center for bullet spawn position.
@export var bullet_spawn_offset: float = 30.0

## Weapon loudness for alerting enemies (viewport diagonal ~1469 for AR).
@export var weapon_loudness: float = 1469.0
## Patrol point offsets from initial position (PATROL mode only).
@export var patrol_offsets: Array[Vector2] = [Vector2(100, 0), Vector2(-100, 0)]

## Wait time at each patrol point in seconds.
@export var patrol_wait_time: float = 1.5

## Color when at full health.
@export var full_health_color: Color = Color(0.9, 0.2, 0.2, 1.0)

## Color when at low health (interpolates based on health percentage).
@export var low_health_color: Color = Color(0.3, 0.1, 0.1, 1.0)

## Color to flash when hit.
@export var hit_flash_color: Color = Color(1.0, 1.0, 1.0, 1.0)

## Duration of hit flash effect in seconds.
@export var hit_flash_duration: float = 0.1

## Whether to destroy the enemy after death.
@export var destroy_on_death: bool = false

## Delay before respawning or destroying (in seconds).
@export var respawn_delay: float = 2.0

## Minimum random health.
@export var min_health: int = 2

## Maximum random health.
@export var max_health: int = 4

## Threat sphere radius - bullets within this radius trigger suppression.
@export var threat_sphere_radius: float = 100.0

## Time to stay suppressed after bullets leave threat sphere.
@export var suppression_cooldown: float = 2.0

## Delay before reacting to threats (gives player reaction time).
@export var threat_reaction_delay: float = 0.2

## Flank angle from player's facing direction (radians).
@export var flank_angle: float = PI / 3.0  # 60 degrees

## Distance to maintain while flanking.
@export var flank_distance: float = 200.0

## Enable/disable flanking behavior.
@export var enable_flanking: bool = true

## Enable/disable cover behavior.
@export var enable_cover: bool = true

## Enable/disable debug logging.
@export var debug_logging: bool = false

## Enable/disable debug label above enemy showing current AI state.
@export var debug_label_enabled: bool = false

## Enable/disable friendly fire avoidance (don't shoot if other enemies are in the way).
@export var enable_friendly_fire_avoidance: bool = true

## Enable/disable lead prediction (shooting ahead of moving targets).
@export var enable_lead_prediction: bool = true

## Bullet speed for lead prediction (2500 for AR).
@export var bullet_speed: float = 2500.0

## Ammunition system - magazine size (bullets per magazine).
@export var magazine_size: int = 30

## Ammunition system - number of magazines the enemy carries.
@export var total_magazines: int = 5

## Ammunition system - time to reload in seconds.
@export var reload_time: float = 3.0

## Delay between spotting player and shooting (gives reaction time).
@export var detection_delay: float = 0.2
## Min visibility time before enabling lead prediction.
@export var lead_prediction_delay: float = 0.3
## Min visibility ratio (0-1) for lead prediction (prevents pre-firing at cover edges).
@export var lead_prediction_visibility_threshold: float = 0.6

## Walking animation speed multiplier - higher = faster leg cycle.
@export var walk_anim_speed: float = 12.0

## Walking animation intensity - higher = more pronounced movement.
@export var walk_anim_intensity: float = 1.0

## Scale multiplier for enemy model (1.3 matches player size).
@export var enemy_model_scale: float = 1.3

# Grenade System Configuration (Issue #363, #375)
@export var grenade_count: int = 0  ## Grenades carried (0 = use DifficultyManager)
@export var grenade_scene: PackedScene  ## Grenade scene to throw
@export var enable_grenade_throwing: bool = true  ## Enable grenade throwing
@export var grenade_throw_cooldown: float = 15.0  ## Cooldown between throws (sec)
@export var grenade_max_throw_distance: float = 600.0  ## Max throw distance (px)
@export var grenade_min_throw_distance: float = 275.0  ## Min safe distance (blast_radius:225 + margin:50, Issue #375)
@export var grenade_safety_margin: float = 50.0  ## Safety margin added to blast radius (Issue #375)
@export var grenade_inaccuracy: float = 0.15  ## Throw inaccuracy (radians)
@export var grenade_throw_delay: float = 0.4  ## Delay before throw (sec)
@export var grenade_debug_logging: bool = false  ## Grenade debug logging


signal hit  ## Enemy hit
signal died  ## Enemy died
signal died_with_info(is_ricochet_kill: bool, is_penetration_kill: bool)  ## Death with kill info
signal state_changed(new_state: AIState)  ## AI state changed
signal ammo_changed(current_ammo: int, reserve_ammo: int)  ## Ammo changed
signal reload_started  ## Reload started
signal reload_finished  ## Reload finished
signal ammo_depleted  ## All ammo depleted
signal death_animation_completed  ## Death animation done
signal grenade_thrown(grenade: Node, target_position: Vector2)  ## Grenade thrown (Issue #363)

const PLAYER_DISTRACTION_ANGLE: float = 0.4014  ## ~23° - player distracted threshold
const AIM_TOLERANCE_DOT: float = 0.866  ## cos(30°) - aim tolerance (issue #254/#264)

@onready var _enemy_model: Node2D = $EnemyModel  ## Model node with all sprites
@onready var _body_sprite: Sprite2D = $EnemyModel/Body  ## Body sprite
@onready var _head_sprite: Sprite2D = $EnemyModel/Head  ## Head sprite
@onready var _left_arm_sprite: Sprite2D = $EnemyModel/LeftArm  ## Left arm sprite
@onready var _right_arm_sprite: Sprite2D = $EnemyModel/RightArm  ## Right arm sprite
@onready var _sprite: Sprite2D = $EnemyModel/Body  ## Legacy ref (body)
@onready var _weapon_sprite: Sprite2D = $EnemyModel/WeaponMount/WeaponSprite  ## Weapon sprite
@onready var _weapon_mount: Node2D = $EnemyModel/WeaponMount  ## Weapon mount
@onready var _raycast: RayCast2D = $RayCast2D  ## Line of sight raycast
@onready var _debug_label: Label = $DebugLabel  ## Debug state label
@onready var _nav_agent: NavigationAgent2D = $NavigationAgent2D  ## Pathfinding

## HitArea for bullet collision detection (disabled on death).
@onready var _hit_area: Area2D = $HitArea
## HitCollisionShape for disabling collision on death (more reliable than toggling monitorable).
@onready var _hit_collision_shape: CollisionShape2D = $HitArea/HitCollisionShape

var _original_hit_area_layer: int = 0  ## Original collision layer (restore on respawn)
var _original_hit_area_mask: int = 0

var _walk_anim_time: float = 0.0  ## Walking animation accumulator
var _is_walking: bool = false  ## Currently walking (for anim)
var _target_model_rotation: float = 0.0  ## Target rotation for smooth interpolation
var _model_facing_left: bool = false  ## Model flipped for left-facing direction
const MODEL_ROTATION_SPEED: float = 3.0  ## Max model rotation speed (3.0 rad/s = 172 deg/s)
var _idle_scan_timer: float = 0.0  ## IDLE scanning state for GUARD enemies
var _idle_scan_target_index: int = 0
var _idle_scan_targets: Array[float] = []
const IDLE_SCAN_INTERVAL: float = 10.0
var _base_body_pos: Vector2 = Vector2.ZERO  ## Base positions for animation
var _base_head_pos: Vector2 = Vector2.ZERO
var _base_left_arm_pos: Vector2 = Vector2.ZERO
var _base_right_arm_pos: Vector2 = Vector2.ZERO
var _wall_raycasts: Array[RayCast2D] = []  ## Wall detection raycasts
const WALL_CHECK_DISTANCE: float = 60.0  ## Wall check distance
const WALL_CHECK_COUNT: int = 8  ## Number of wall raycasts
const WALL_AVOIDANCE_MIN_WEIGHT: float = 0.7  ## Min avoidance (close)
const WALL_AVOIDANCE_MAX_WEIGHT: float = 0.3  ## Max avoidance (far)
const WALL_SLIDE_DISTANCE: float = 30.0  ## Wall slide threshold
var _cover_raycasts: Array[RayCast2D] = []  ## Cover detection raycasts
const COVER_CHECK_COUNT: int = 16  ## Number of cover raycasts
const COVER_CHECK_DISTANCE: float = 300.0  ## Cover check distance
var _current_health: int = 0  ## Current health
var _max_health: int = 0  ## Max health (set at spawn)
var _is_alive: bool = true  ## Is alive
var _player: Node2D = null  ## Player reference
var _shoot_timer: float = 0.0  ## Time since last shot
var _current_ammo: int = 0  ## Ammo in magazine
var _reserve_ammo: int = 0  ## Reserve ammo
var _is_reloading: bool = false  ## Currently reloading
var _reload_timer: float = 0.0  ## Reload progress
var _patrol_points: Array[Vector2] = []  ## Patrol state
var _current_patrol_index: int = 0
var _is_waiting_at_patrol_point: bool = false
var _patrol_wait_timer: float = 0.0
var _corner_check_angle: float = 0.0  ## Angle to look toward when checking a corner
var _corner_check_timer: float = 0.0  ## Timer for corner check duration
const CORNER_CHECK_DURATION: float = 0.3  ## How long to look at a corner (seconds)
const CORNER_CHECK_DISTANCE: float = 150.0  ## Max distance to detect openings
var _initial_position: Vector2
var _can_see_player: bool = false  ## Can see player
var _current_state: AIState = AIState.IDLE  ## AI state
var _cover_position: Vector2 = Vector2.ZERO  ## Cover position
var _has_valid_cover: bool = false  ## Has valid cover
var _suppression_timer: float = 0.0  ## Suppression cooldown
var _under_fire: bool = false  ## Under fire (bullets in threat sphere)

## Flank target position.
var _flank_target: Vector2 = Vector2.ZERO

## Threat sphere Area2D for detecting nearby bullets.
var _threat_sphere: Area2D = null

## Bullets currently in threat sphere.
var _bullets_in_threat_sphere: Array = []

## Timer for threat reaction delay - time since first bullet entered threat sphere.
var _threat_reaction_timer: float = 0.0

## Whether the threat reaction delay has elapsed (enemy can react to bullets).
var _threat_reaction_delay_elapsed: bool = false

## Memory timer for bullets that passed through threat sphere (allows reaction after fast bullets exit).
var _threat_memory_timer: float = 0.0
## Duration to remember bullet passage (longer than reaction delay for complete reaction).
const THREAT_MEMORY_DURATION: float = 0.5

## Current retreat mode determined by damage taken.
var _retreat_mode: RetreatMode = RetreatMode.FULL_HP

## Hits taken this retreat/combat encounter. Resets on IDLE or retreat completion.
var _hits_taken_in_encounter: int = 0

var _retreat_turn_timer: float = 0.0  ## Periodic cover turn timer
const RETREAT_TURN_DURATION: float = 0.8  ## Duration to face cover (sec)
const RETREAT_TURN_INTERVAL: float = 1.5  ## Turn interval (sec)
var _retreat_turning_to_cover: bool = false  ## In turn-to-cover phase
var _retreat_burst_remaining: int = 0  ## ONE_HIT burst counter
var _retreat_burst_timer: float = 0.0  ## Burst cooldown timer
const RETREAT_BURST_COOLDOWN: float = 0.06  ## Burst shot interval (sec)
var _retreat_burst_complete: bool = false  ## Burst phase done
const RETREAT_INACCURACY_SPREAD: float = 0.15  ## Retreat accuracy penalty
const RETREAT_BURST_ARC: float = 0.4  ## ONE_HIT burst arc (rad)
var _retreat_burst_angle_offset: float = 0.0  ## Current burst angle offset
var _in_alarm_mode: bool = false  ## Suppressed/retreating alarm mode
var _cover_burst_pending: bool = false  ## Fire cover burst when leaving cover
# --- Combat Cover Cycling ---
var _combat_shoot_timer: float = 0.0  ## Exposed shooting timer
var _combat_shoot_duration: float = 2.5  ## Shoot duration out of cover
var _combat_exposed: bool = false  ## In exposed shooting phase
var _combat_approaching: bool = false  ## Approaching player phase
var _combat_approach_timer: float = 0.0  ## Approach phase timer
var _combat_state_timer: float = 0.0  ## Total COMBAT time this cycle
const COMBAT_APPROACH_MAX_TIME: float = 2.0  ## Max approach time (sec)
const COMBAT_DIRECT_CONTACT_DISTANCE: float = 250.0  ## Close enough to shoot
const COMBAT_MIN_DURATION_BEFORE_PURSUE: float = 0.5  ## Min COMBAT before PURSUING
# --- Pursuit State ---
var _pursuit_cover_wait_timer: float = 0.0  ## Cover wait timer
const PURSUIT_COVER_WAIT_DURATION: float = 1.5  ## Wait at cover (sec)
var _pursuit_next_cover: Vector2 = Vector2.ZERO  ## Next cover position
var _has_pursuit_cover: bool = false  ## Has valid pursuit cover
var _current_cover_obstacle: Object = null  ## Current cover obstacle
var _pursuit_approaching: bool = false  ## Approaching with no cover
var _pursuit_approach_timer: float = 0.0  ## Approach phase timer
var _pursuing_state_timer: float = 0.0  ## Total PURSUING time
const PURSUIT_APPROACH_MAX_TIME: float = 3.0  ## Max approach time (sec)
const PURSUING_MIN_DURATION_BEFORE_COMBAT: float = 0.3  ## Min before COMBAT
const PURSUIT_MIN_PROGRESS_FRACTION: float = 0.10  ## Min progress fraction
const PURSUIT_SAME_OBSTACLE_PENALTY: float = 4.0  ## Penalty for same cover
# --- Flanking State ---
var _flank_cover_wait_timer: float = 0.0  ## Wait at cover timer
const FLANK_COVER_WAIT_DURATION: float = 0.8  ## Cover wait time (sec)
var _flank_next_cover: Vector2 = Vector2.ZERO  ## Next cover position
var _has_flank_cover: bool = false  ## Has valid flank cover
var _flank_side: float = 1.0  ## Flank side (1=right, -1=left)
var _flank_side_initialized: bool = false  ## Flank side set
var _flank_state_timer: float = 0.0  ## Total flanking time
const FLANK_STATE_MAX_TIME: float = 5.0  ## Max flanking time (sec)
var _flank_last_position: Vector2 = Vector2.ZERO  ## Last pos for progress
var _flank_stuck_timer: float = 0.0  ## Stuck check timer
const FLANK_STUCK_MAX_TIME: float = 2.0  ## Max time without progress
const FLANK_PROGRESS_THRESHOLD: float = 10.0  ## Min progress distance
var _flank_fail_count: int = 0  ## Consecutive flank failures
const FLANK_FAIL_MAX_COUNT: int = 2  ## Max failures before cooldown
var _flank_cooldown_timer: float = 0.0  ## Cooldown after failures
const FLANK_COOLDOWN_DURATION: float = 5.0  ## Failure cooldown (sec)
# Issue #367: Global stuck detection
var _global_stuck_timer: float = 0.0  ## Stuck timer
var _global_stuck_last_position: Vector2 = Vector2.ZERO  ## Last position
const GLOBAL_STUCK_MAX_TIME: float = 4.0  ## Max stuck time
const GLOBAL_STUCK_DISTANCE_THRESHOLD: float = 30.0  ## Min move distance
# --- Assault State ---
var _assault_wait_timer: float = 0.0  ## Assault wait timer
const ASSAULT_WAIT_DURATION: float = 5.0  ## Pre-assault wait (sec)
var _assault_ready: bool = false  ## Assault wait complete
var _in_assault: bool = false  ## In assault
# Search State - Issue #322
var _search_center: Vector2 = Vector2.ZERO  ## Search center
var _search_radius: float = 100.0  ## Current radius
const SEARCH_INITIAL_RADIUS: float = 100.0  ## Initial radius
const SEARCH_RADIUS_EXPANSION: float = 75.0  ## Radius expansion
const SEARCH_MAX_RADIUS: float = 400.0  ## Max radius
var _search_waypoints: Array[Vector2] = []  ## Search waypoints
var _search_current_waypoint_index: int = 0  ## Current waypoint index
var _search_scan_timer: float = 0.0  ## Timer for scanning at waypoint
const SEARCH_SCAN_DURATION: float = 1.0  ## Seconds to scan at each waypoint
var _search_state_timer: float = 0.0  ## Total time in SEARCHING state
const SEARCH_MAX_DURATION: float = 30.0  ## Max time searching before idle
var _search_direction: int = 0  ## Direction: 0=N, 1=E, 2=S, 3=W
var _search_leg_length: float = 50.0  ## Current leg length for spiral
var _search_legs_completed: int = 0  ## Legs completed in pattern
const SEARCH_WAYPOINT_REACHED_DISTANCE: float = 20.0  ## Waypoint reached threshold
var _search_moving_to_waypoint: bool = true  ## Moving (vs scanning)
const SEARCH_WAYPOINT_SPACING: float = 75.0  ## Spacing between waypoints
var _search_visited_zones: Dictionary = {}  ## Tracks visited positions (key=snapped pos, val=true)
const SEARCH_ZONE_SNAP_SIZE: float = 50.0  ## Grid size for snapping positions to zones

# Issue #354: Stuck detection for SEARCHING
var _search_stuck_timer: float = 0.0  ## Stuck timer
var _search_last_progress_position: Vector2 = Vector2.ZERO  ## Last progress pos
const SEARCH_STUCK_MAX_TIME: float = 2.0  ## Max stuck time
const SEARCH_PROGRESS_THRESHOLD: float = 10.0  ## Min progress distance
var _has_left_idle: bool = false  ## Issue #330: Never returns to IDLE
const CLOSE_COMBAT_DISTANCE: float = 400.0  ## Close combat threshold
var _goap_world_state: Dictionary = {}  ## GOAP world state
var _detection_timer: float = 0.0  ## Combat detection timer
var _detection_delay_elapsed: bool = false  ## Detection delay done
var _continuous_visibility_timer: float = 0.0  ## Continuous visibility timer
var _player_visibility_ratio: float = 0.0  ## Player visibility (0-1)
# --- Clear Shot Movement ---
var _clear_shot_target: Vector2 = Vector2.ZERO  ## Clear shot target
var _seeking_clear_shot: bool = false  ## Moving to clear shot
var _clear_shot_timer: float = 0.0  ## Clear shot attempt timer

## Maximum time to spend finding a clear shot before giving up (seconds).
const CLEAR_SHOT_MAX_TIME: float = 3.0

## Distance to move when exiting cover to find a clear shot.
const CLEAR_SHOT_EXIT_DISTANCE: float = 60.0

## --- Sound-Based Detection ---
## Last known sound source position (for investigation when player not visible).
var _last_known_player_position: Vector2 = Vector2.ZERO
## Pursuing vulnerability sound (reload/empty click) without line of sight.
var _pursuing_vulnerability_sound: bool = false

## --- Enemy Memory System (Issue #297) ---
## Tracks suspected player position with confidence (0.0=none, 1.0=visual contact).
## The memory influences AI behavior:
## - High confidence (>0.8): Direct pursuit to suspected position
## - Medium confidence (0.5-0.8): Cautious approach with cover checks
## - Low confidence (<0.5): Return to patrol/guard behavior
var _memory: EnemyMemory = null

## Confidence values for different detection sources.
const VISUAL_DETECTION_CONFIDENCE: float = 1.0
const SOUND_GUNSHOT_CONFIDENCE: float = 0.7
const SOUND_RELOAD_CONFIDENCE: float = 0.6
const SOUND_EMPTY_CLICK_CONFIDENCE: float = 0.6
const INTEL_SHARE_FACTOR: float = 0.9  ## Confidence reduction when sharing intel

## Communication range for enemy-to-enemy information sharing.
## 660px with direct line of sight, 300px without line of sight.
const INTEL_SHARE_RANGE_LOS: float = 660.0
const INTEL_SHARE_RANGE_NO_LOS: float = 300.0

## Timer for periodic intel sharing (to avoid per-frame overhead).
var _intel_share_timer: float = 0.0
const INTEL_SHARE_INTERVAL: float = 0.5  ## Share intel every 0.5 seconds

## Memory reset confusion timer (Issue #318): blocks visibility after teleport.
var _memory_reset_confusion_timer: float = 0.0
const MEMORY_RESET_CONFUSION_DURATION: float = 2.0  ## Extended to 2s for better player escape window

## --- Score Tracking ---
## Whether the last hit that killed this enemy was from a ricocheted bullet.
var _killed_by_ricochet: bool = false

## Whether the last hit that killed this enemy was from a bullet that penetrated a wall.
var _killed_by_penetration: bool = false

## --- Status Effects ---
## Whether the enemy is currently blinded (cannot see the player).
var _is_blinded: bool = false

## Whether the enemy is currently stunned (cannot move or act).
var _is_stunned: bool = false

## --- Grenade System (Issue #363) ---
## Grenade throwing logic is handled by EnemyGrenadeComponent (extracted for Issue #377 CI fix).

## Last hit direction (used for death animation).
var _last_hit_direction: Vector2 = Vector2.RIGHT

## Death animation component reference.
var _death_animation: Node = null

## Grenade component for handling grenade throwing (extracted for Issue #377 CI fix).
var _grenade_component: EnemyGrenadeComponent = null

## Note: DeathAnimationComponent and EnemyGrenadeComponent are available via class_name declarations.

func _ready() -> void:
	# Add to enemies group for grenade targeting
	add_to_group("enemies")

	_initial_position = global_position
	_initialize_health()
	_initialize_ammo()
	_update_health_visual()
	_setup_patrol_points()
	_find_player()
	_setup_wall_detection()
	_setup_cover_detection()
	_setup_threat_sphere()
	_initialize_goap_state()
	_initialize_memory()
	_connect_debug_mode_signal()
	_update_debug_label()
	_register_sound_listener()
	_setup_grenade_component()

	# Store original collision layers for HitArea (to restore on respawn)
	if _hit_area:
		_original_hit_area_layer = _hit_area.collision_layer
		_original_hit_area_mask = _hit_area.collision_mask

	# Log that this enemy is ready (use call_deferred to ensure FileLogger is loaded)
	call_deferred("_log_spawn_info")

	# Preload bullet scene if not set in inspector
	if bullet_scene == null:
		bullet_scene = preload("res://scenes/projectiles/Bullet.tscn")

	# Preload casing scene if not set in inspector
	if casing_scene == null:
		casing_scene = preload("res://scenes/effects/Casing.tscn")

	# Initialize walking animation base positions
	if _body_sprite:
		_base_body_pos = _body_sprite.position
	if _head_sprite:
		_base_head_pos = _head_sprite.position
	if _left_arm_sprite:
		_base_left_arm_pos = _left_arm_sprite.position
	if _right_arm_sprite:
		_base_right_arm_pos = _right_arm_sprite.position

	# Apply scale to enemy model for larger appearance (same as player)
	if _enemy_model:
		_enemy_model.scale = Vector2(enemy_model_scale, enemy_model_scale)

	# Initialize death animation component
	_init_death_animation()

## Initialize health with random value between min and max.
func _initialize_health() -> void:
	_max_health = randi_range(min_health, max_health)
	_current_health = _max_health
	_is_alive = true

## Initialize ammunition with full magazine and reserve ammo.
func _initialize_ammo() -> void:
	_current_ammo = magazine_size
	# Reserve ammo is (total_magazines - 1) * magazine_size since one magazine is loaded
	_reserve_ammo = (total_magazines - 1) * magazine_size
	_is_reloading = false
	_reload_timer = 0.0

## Setup patrol points based on patrol offsets from initial position.
func _setup_patrol_points() -> void:
	_patrol_points.clear()
	_patrol_points.append(_initial_position)
	for offset in patrol_offsets:
		_patrol_points.append(_initial_position + offset)

## Setup wall detection raycasts for obstacle avoidance.
func _setup_wall_detection() -> void:
	# Create multiple raycasts spread in front of the enemy
	for i in range(WALL_CHECK_COUNT):
		var raycast := RayCast2D.new()
		raycast.enabled = true
		raycast.collision_mask = 4  # Only detect obstacles (layer 3)
		raycast.exclude_parent = true
		add_child(raycast)
		_wall_raycasts.append(raycast)

## Setup cover detection raycasts for finding cover positions.
func _setup_cover_detection() -> void:
	for i in range(COVER_CHECK_COUNT):
		var raycast := RayCast2D.new()
		raycast.enabled = true
		raycast.collision_mask = 4  # Only detect obstacles (layer 3)
		raycast.exclude_parent = true
		add_child(raycast)
		_cover_raycasts.append(raycast)

## Setup threat sphere for detecting nearby bullets.
func _setup_threat_sphere() -> void:
	_threat_sphere = Area2D.new()
	_threat_sphere.name = "ThreatSphere"
	_threat_sphere.collision_layer = 0
	_threat_sphere.collision_mask = 16  # Detect projectiles (layer 5)

	var collision_shape := CollisionShape2D.new()
	var circle_shape := CircleShape2D.new()
	circle_shape.radius = threat_sphere_radius
	collision_shape.shape = circle_shape
	_threat_sphere.add_child(collision_shape)

	add_child(_threat_sphere)

	# Connect signals
	_threat_sphere.area_entered.connect(_on_threat_area_entered)
	_threat_sphere.area_exited.connect(_on_threat_area_exited)

## Register this enemy as a listener for in-game sound propagation.
## This allows the enemy to react to sounds like gunshots even when not in direct combat.
## Uses call_deferred to ensure SoundPropagation autoload is fully initialized.
func _register_sound_listener() -> void:
	call_deferred("_deferred_register_sound_listener")

## Deferred registration to ensure SoundPropagation is ready.
func _deferred_register_sound_listener() -> void:
	var sound_propagation: Node = get_node_or_null("/root/SoundPropagation")
	if sound_propagation and sound_propagation.has_method("register_listener"):
		sound_propagation.register_listener(self)
		_log_debug("Registered as sound listener")
		_log_to_file("Registered as sound listener")
	else:
		_log_to_file("WARNING: Could not register as sound listener (SoundPropagation not found)")
		push_warning("[%s] Could not register as sound listener - SoundPropagation not found" % name)

## Unregister this enemy from sound propagation when dying or being destroyed.
func _unregister_sound_listener() -> void:
	var sound_propagation: Node = get_node_or_null("/root/SoundPropagation")
	if sound_propagation and sound_propagation.has_method("unregister_listener"):
		sound_propagation.unregister_listener(self)

## Called by SoundPropagation when a sound is heard. Delegates to on_sound_heard_with_intensity.
func on_sound_heard(sound_type: int, position: Vector2, source_type: int, source_node: Node2D) -> void:
	# Default to full intensity if called without intensity parameter
	on_sound_heard_with_intensity(sound_type, position, source_type, source_node, 1.0)

## Called by SoundPropagation with intensity. Reacts to reload/empty_click/gunshot sounds.
func on_sound_heard_with_intensity(sound_type: int, position: Vector2, source_type: int, source_node: Node2D, intensity: float) -> void:
	# Only react if alive and not confused from memory reset (Issue #318 - block sounds during confusion)
	if not _is_alive or _memory_reset_confusion_timer > 0.0:
		return
	# Calculate distance to sound for logging
	var distance := global_position.distance_to(position)

	# Handle reload sound (sound_type 3 = RELOAD) - player is vulnerable!
	# This sound propagates through walls and alerts enemies even behind cover.
	if sound_type == 3 and source_type == 0:  # RELOAD from PLAYER
		_log_debug("Heard player RELOAD (intensity=%.2f, distance=%.0f) at %s" % [
			intensity, distance, position
		])
		_log_to_file("Heard player RELOAD at %s, intensity=%.2f, distance=%.0f" % [
			position, intensity, distance
		])

		# Set player vulnerability state - reloading
		_goap_world_state["player_reloading"] = true
		_last_known_player_position = position
		# Set flag to pursue to sound position even without line of sight
		_pursuing_vulnerability_sound = true

		# Issue #363: Notify grenade system of vulnerable sound for Trigger 4
		_on_vulnerable_sound_heard_for_grenade(position)

		# Update memory system with sound-based detection (Issue #297)
		if _memory:
			_memory.update_position(position, SOUND_RELOAD_CONFIDENCE)

		# React to vulnerable player sound - transition to combat/pursuing
		# All enemies in hearing range should pursue the vulnerable player!
		# This makes reload sounds a high-risk action when enemies are nearby.
		if _current_state in [AIState.IDLE, AIState.IN_COVER, AIState.SUPPRESSED, AIState.RETREATING, AIState.SEEKING_COVER]:
			# Leave cover/defensive state to attack vulnerable player
			_log_to_file("Vulnerability sound triggered pursuit - transitioning from %s to PURSUING" % AIState.keys()[_current_state])
			_transition_to_pursuing()
		# For COMBAT, PURSUING, FLANKING states: the flag is set and they'll use it
		# (COMBAT/PURSUING now check _pursuing_vulnerability_sound before retreating)
		return

	# Handle empty click sound (sound_type 5 = EMPTY_CLICK) - player is vulnerable!
	# This sound has shorter range than reload but still propagates through walls.
	if sound_type == 5 and source_type == 0:  # EMPTY_CLICK from PLAYER
		_log_debug("Heard player EMPTY_CLICK (intensity=%.2f, distance=%.0f) at %s" % [
			intensity, distance, position
		])
		_log_to_file("Heard player EMPTY_CLICK at %s, intensity=%.2f, distance=%.0f" % [
			position, intensity, distance
		])

		# Set player vulnerability state - out of ammo
		_goap_world_state["player_ammo_empty"] = true
		_last_known_player_position = position
		# Set flag to pursue to sound position even without line of sight
		_pursuing_vulnerability_sound = true

		# Issue #363: Notify grenade system of vulnerable sound for Trigger 4
		_on_vulnerable_sound_heard_for_grenade(position)

		# Update memory system with sound-based detection (Issue #297)
		if _memory:
			_memory.update_position(position, SOUND_EMPTY_CLICK_CONFIDENCE)

		# React to vulnerable player sound - transition to combat/pursuing
		# All enemies in hearing range should pursue the vulnerable player!
		# This makes empty click sounds a high-risk action when enemies are nearby.
		if _current_state in [AIState.IDLE, AIState.IN_COVER, AIState.SUPPRESSED, AIState.RETREATING, AIState.SEEKING_COVER]:
			# Leave cover/defensive state to attack vulnerable player
			_log_to_file("Vulnerability sound triggered pursuit - transitioning from %s to PURSUING" % AIState.keys()[_current_state])
			_transition_to_pursuing()
		# For COMBAT, PURSUING, FLANKING states: the flag is set and they'll use it
		# (COMBAT/PURSUING now check _pursuing_vulnerability_sound before retreating)
		return

	# Handle reload complete sound (sound_type 6 = RELOAD_COMPLETE) - player is NO LONGER vulnerable!
	# This sound propagates through walls and signals enemies to become cautious.
	if sound_type == 6 and source_type == 0:  # RELOAD_COMPLETE from PLAYER
		_log_debug("Heard player RELOAD_COMPLETE (intensity=%.2f, distance=%.0f) at %s" % [
			intensity, distance, position
		])
		_log_to_file("Heard player RELOAD_COMPLETE at %s, intensity=%.2f, distance=%.0f" % [
			position, intensity, distance
		])

		# Clear player vulnerability state - reload finished, player is armed again
		_goap_world_state["player_reloading"] = false
		_goap_world_state["player_ammo_empty"] = false
		# Clear the aggressive pursuit flag - no longer pursuing vulnerable player
		_pursuing_vulnerability_sound = false

		# React to reload completion - transition to cautious/defensive mode after a short delay.
		# The 200ms delay gives enemies a brief reaction time before becoming cautious,
		# making the transition feel more natural and giving player a small window.
		# Enemies who were pursuing the vulnerable player should now become more cautious.
		# This makes completing reload a way to "reset" aggressive enemy behavior.
		if _current_state in [AIState.PURSUING, AIState.COMBAT, AIState.ASSAULT]:
			var state_before_delay := _current_state
			_log_to_file("Reload complete sound heard - waiting 200ms before cautious transition from %s" % AIState.keys()[_current_state])
			await get_tree().create_timer(0.2).timeout
			# After delay, check if still alive and in an aggressive state
			if not _is_alive:
				return
			# Only transition if still in an aggressive state (state might have changed during delay)
			if _current_state in [AIState.PURSUING, AIState.COMBAT, AIState.ASSAULT]:
				# Return to cover/defensive state since player is no longer vulnerable
				if _has_valid_cover:
					_log_to_file("Reload complete sound triggered retreat - transitioning from %s to RETREATING (delayed from %s)" % [AIState.keys()[_current_state], AIState.keys()[state_before_delay]])
					_transition_to_retreating()
				elif enable_cover:
					_log_to_file("Reload complete sound triggered cover seek - transitioning from %s to SEEKING_COVER (delayed from %s)" % [AIState.keys()[_current_state], AIState.keys()[state_before_delay]])
					_transition_to_seeking_cover()
				# If no cover available, stay in current state but with cleared vulnerability flags
		return

	# Handle gunshot sounds (sound_type 0 = GUNSHOT)
	if sound_type != 0:
		return

	# React based on current state:
	# - IDLE: Always react to loud sounds
	# - Other states: Only react to very loud, close sounds (intensity > 0.5)
	var should_react := false

	if _current_state == AIState.IDLE:
		# In IDLE state, always investigate sounds above minimal threshold
		should_react = intensity >= 0.01
	elif _current_state in [AIState.FLANKING, AIState.RETREATING]:
		# In tactical movement states, react to loud nearby sounds
		should_react = intensity >= 0.3
	else:
		# In combat-related states, only react to very loud sounds
		# This prevents enemies from being distracted during active combat
		should_react = false

	if not should_react:
		return

	# React to sounds: transition to combat mode to investigate
	_log_debug("Heard gunshot (intensity=%.2f, distance=%.0f) from %s at %s, entering COMBAT" % [
		intensity,
		distance,
		"player" if source_type == 0 else ("enemy" if source_type == 1 else "neutral"),
		position
	])
	_log_to_file("Heard gunshot at %s, source_type=%d, intensity=%.2f, distance=%.0f" % [
		position, source_type, intensity, distance
	])

	# Issue #363: Track gunshots for sustained fire detection (Trigger 5)
	_on_gunshot_heard_for_grenade(position)

	# Store the position of the sound as a point of interest
	# The enemy will investigate this location
	_last_known_player_position = position

	# Update memory system with sound-based detection (Issue #297)
	if _memory:
		_memory.update_position(position, SOUND_GUNSHOT_CONFIDENCE)

	# Transition to combat mode to investigate the sound
	_transition_to_combat()

## Initialize GOAP world state.
func _initialize_goap_state() -> void:
	_goap_world_state = {
		"player_visible": false,
		"has_cover": false,
		"in_cover": false,
		"under_fire": false,
		"health_low": false,
		"can_flank": false,
		"at_flank_position": false,
		"is_retreating": false,
		"hits_taken": 0,
		"is_pursuing": false,
		"is_assaulting": false,
		"can_hit_from_cover": false,
		"player_close": false,
		"enemies_in_combat": 0,
		"player_distracted": false,
		"player_reloading": false,
		"player_ammo_empty": false,
		# Memory system states (Issue #297)
		"has_suspected_position": false,
		"position_confidence": 0.0,
		"confidence_high": false,
		"confidence_medium": false,
		"confidence_low": false
	}

## Initialize the enemy memory system (Issue #297).
func _initialize_memory() -> void:
	_memory = EnemyMemory.new()

## Connect to GameManager's debug mode signal for F7 toggle.
func _connect_debug_mode_signal() -> void:
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager:
		# Connect to debug mode toggle signal
		if game_manager.has_signal("debug_mode_toggled"):
			game_manager.debug_mode_toggled.connect(_on_debug_mode_toggled)
		# Sync with current debug mode state
		if game_manager.has_method("is_debug_mode_enabled"):
			debug_label_enabled = game_manager.is_debug_mode_enabled()

## Called when debug mode is toggled via F7 key.
func _on_debug_mode_toggled(enabled: bool) -> void:
	debug_label_enabled = enabled
	_update_debug_label()
	queue_redraw()  # Redraw to show/hide FOV cone

## Find the player node in the scene tree.
func _find_player() -> void:
	# Try to find the player by group first
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]
		return

	# Fallback: search for player by node name or type
	var root := get_tree().current_scene
	if root:
		_player = _find_player_recursive(root)

## Recursively search for a player node.
func _find_player_recursive(node: Node) -> Node2D:
	if node.name == "Player" and node is Node2D:
		return node
	for child in node.get_children():
		var result := _find_player_recursive(child)
		if result:
			return result
	return null

func _physics_process(delta: float) -> void:
	if not _is_alive:
		return

	# Update shoot cooldown timer
	_shoot_timer += delta

	# Update reload timer
	_update_reload(delta)

	# Update flank cooldown timer (allows flanking to re-enable after failures)
	if _flank_cooldown_timer > 0.0:
		_flank_cooldown_timer -= delta
		if _flank_cooldown_timer <= 0.0:
			_flank_cooldown_timer = 0.0
			# Reset failure count when cooldown expires
			_flank_fail_count = 0

	# Update memory reset confusion timer (Issue #318)
	if _memory_reset_confusion_timer > 0.0:
		_memory_reset_confusion_timer = maxf(0.0, _memory_reset_confusion_timer - delta)

	# Issue #367: Global position-based stuck detection for PURSUING/FLANKING states.
	# If enemy stays in same position for too long without direct player contact, force SEARCHING.
	if _current_state == AIState.PURSUING or _current_state == AIState.FLANKING:
		var moved_distance := global_position.distance_to(_global_stuck_last_position)
		if moved_distance < GLOBAL_STUCK_DISTANCE_THRESHOLD:
			# Not making significant progress - increment stuck timer
			# Only count if NOT in direct player contact (can't see and shoot player)
			if not (_can_see_player and _can_hit_player_from_current_position()):
				_global_stuck_timer += delta
				if _global_stuck_timer >= GLOBAL_STUCK_MAX_TIME:
					_log_to_file("GLOBAL STUCK: pos=%s for %.1fs without player contact, State: %s -> SEARCHING" % [global_position, _global_stuck_timer, AIState.keys()[_current_state]])
					_global_stuck_timer = 0.0
					_global_stuck_last_position = global_position
					# Reset flanking state if applicable
					if _current_state == AIState.FLANKING:
						_flank_side_initialized = false
						_flank_fail_count += 1
						_flank_cooldown_timer = FLANK_COOLDOWN_DURATION
					_transition_to_searching(global_position)
					return  # Skip rest of physics process this frame
		else:
			# Making progress - reset stuck timer and update position
			_global_stuck_timer = 0.0
			_global_stuck_last_position = global_position
	else:
		# Not in PURSUING/FLANKING - reset stuck detection
		_global_stuck_timer = 0.0
		_global_stuck_last_position = global_position

	# Check for player visibility and try to find player if not found
	if _player == null:
		_find_player()

	_check_player_visibility()
	_update_memory(delta)
	_update_goap_state()
	_update_suppression(delta)
	_update_grenade_triggers(delta)

	# Update enemy model rotation BEFORE processing AI state (which may shoot).
	# This ensures the weapon is correctly positioned when bullets are created.
	# Note: We don't call _update_weapon_sprite_rotation() anymore because:
	# 1. The EnemyModel rotation already rotates the weapon correctly
	# 2. The previous _update_weapon_sprite_rotation() was using the Enemy's rotation
	#    instead of EnemyModel's rotation, causing the weapon to be offset by 90 degrees
	_update_enemy_model_rotation()

	# Process AI state machine (may trigger shooting)
	_process_ai_state(delta)

	# Update debug label if enabled
	_update_debug_label()

	# Request redraw for debug visualization
	if debug_label_enabled:
		queue_redraw()

	# Update walking animation based on movement
	_update_walk_animation(delta)

	move_and_slide()

## Update GOAP world state based on current conditions.
func _update_goap_state() -> void:
	_goap_world_state["player_visible"] = _can_see_player
	_goap_world_state["under_fire"] = _under_fire
	_goap_world_state["health_low"] = _get_health_percent() < 0.5
	_goap_world_state["in_cover"] = _current_state == AIState.IN_COVER
	_goap_world_state["has_cover"] = _has_valid_cover
	_goap_world_state["is_retreating"] = _current_state == AIState.RETREATING
	_goap_world_state["hits_taken"] = _hits_taken_in_encounter
	_goap_world_state["is_pursuing"] = _current_state == AIState.PURSUING
	_goap_world_state["is_assaulting"] = _current_state == AIState.ASSAULT
	_goap_world_state["player_close"] = _is_player_close()
	_goap_world_state["can_hit_from_cover"] = _can_hit_player_from_current_position()
	_goap_world_state["enemies_in_combat"] = _count_enemies_in_combat()
	_goap_world_state["player_distracted"] = _is_player_distracted()

	# Memory system states (Issue #297)
	if _memory:
		_goap_world_state["has_suspected_position"] = _memory.has_target()
		_goap_world_state["position_confidence"] = _memory.confidence
		_goap_world_state["confidence_high"] = _memory.is_high_confidence()
		_goap_world_state["confidence_medium"] = _memory.is_medium_confidence()
		_goap_world_state["confidence_low"] = _memory.is_low_confidence()

## Updates model rotation smoothly (#347). Priority: player > corner check > velocity > idle scan.
func _update_enemy_model_rotation() -> void:
	if not _enemy_model:
		return
	var target_angle: float
	var has_target := false
	if _player != null and _can_see_player:
		target_angle = (_player.global_position - global_position).normalized().angle()
		has_target = true
	elif _corner_check_timer > 0:
		target_angle = _corner_check_angle  # Corner check: smooth rotation (Issue #347)
		has_target = true
	elif velocity.length_squared() > 1.0:
		target_angle = velocity.normalized().angle()
		has_target = true
	elif _current_state == AIState.IDLE and _idle_scan_targets.size() > 0:
		target_angle = _idle_scan_targets[_idle_scan_target_index]
		has_target = true
	if not has_target:
		return
	# Smooth rotation for visual polish (Issue #347)
	var delta := get_physics_process_delta_time()
	var current_rot := _enemy_model.global_rotation
	var angle_diff := wrapf(target_angle - current_rot, -PI, PI)
	if abs(angle_diff) <= MODEL_ROTATION_SPEED * delta:
		_enemy_model.global_rotation = target_angle
	elif angle_diff > 0:
		_enemy_model.global_rotation = current_rot + MODEL_ROTATION_SPEED * delta
	else:
		_enemy_model.global_rotation = current_rot - MODEL_ROTATION_SPEED * delta
	var aiming_left := absf(_enemy_model.global_rotation) > PI / 2
	_model_facing_left = aiming_left
	if aiming_left:
		_enemy_model.scale = Vector2(enemy_model_scale, -enemy_model_scale)
	else:
		_enemy_model.scale = Vector2(enemy_model_scale, enemy_model_scale)

## Forces the enemy model to face a specific direction immediately.
## Used for priority attacks where we need to aim and shoot in the same frame.
##
## Unlike _update_enemy_model_rotation(), this function:
## 1. Takes a specific direction to face (doesn't derive it from player position)
## 2. Is called immediately before shooting in priority attack code
##
## This ensures the weapon sprite's transform matches the intended aim direction
## so that _get_weapon_forward_direction() returns the correct vector for aim checks.
##
## @param direction: The direction to face (normalized).
func _force_model_to_face_direction(direction: Vector2) -> void:
	if not _enemy_model:
		return

	var target_angle := direction.angle()
	var aiming_left := absf(target_angle) > PI / 2

	# Same fix as _update_enemy_model_rotation() - don't negate angle when flipped
	if aiming_left:
		_enemy_model.global_rotation = target_angle
		_enemy_model.scale = Vector2(enemy_model_scale, -enemy_model_scale)
	else:
		_enemy_model.global_rotation = target_angle
		_enemy_model.scale = Vector2(enemy_model_scale, enemy_model_scale)

## Updates the walking animation based on enemy movement state.
## Creates a natural bobbing motion for body parts during movement.
## @param delta: Time since last frame.
func _update_walk_animation(delta: float) -> void:
	var is_moving := velocity.length() > 10.0

	if is_moving:
		# Accumulate animation time based on movement speed
		# Use combat_move_speed as max for faster walk animation during combat
		var max_speed := maxf(move_speed, combat_move_speed)
		var speed_factor := velocity.length() / max_speed
		_walk_anim_time += delta * walk_anim_speed * speed_factor
		_is_walking = true

		# Calculate animation offsets using sine waves
		# Body bobs up and down (frequency = 2x for double step)
		var body_bob := sin(_walk_anim_time * 2.0) * 1.5 * walk_anim_intensity

		# Head bobs slightly less than body (dampened)
		var head_bob := sin(_walk_anim_time * 2.0) * 0.8 * walk_anim_intensity

		# Arms swing opposite to each other (alternating)
		var arm_swing := sin(_walk_anim_time) * 3.0 * walk_anim_intensity

		# Apply offsets to sprites
		if _body_sprite:
			_body_sprite.position = _base_body_pos + Vector2(0, body_bob)

		if _head_sprite:
			_head_sprite.position = _base_head_pos + Vector2(0, head_bob)

		if _left_arm_sprite:
			# Left arm swings forward/back (y-axis in top-down)
			_left_arm_sprite.position = _base_left_arm_pos + Vector2(arm_swing, 0)

		if _right_arm_sprite:
			# Right arm swings opposite to left arm
			_right_arm_sprite.position = _base_right_arm_pos + Vector2(-arm_swing, 0)
	else:
		# Return to idle pose smoothly
		if _is_walking:
			_is_walking = false
			_walk_anim_time = 0.0

		# Interpolate back to base positions
		var lerp_speed := 10.0 * delta
		if _body_sprite:
			_body_sprite.position = _body_sprite.position.lerp(_base_body_pos, lerp_speed)
		if _head_sprite:
			_head_sprite.position = _head_sprite.position.lerp(_base_head_pos, lerp_speed)
		if _left_arm_sprite:
			_left_arm_sprite.position = _left_arm_sprite.position.lerp(_base_left_arm_pos, lerp_speed)
		if _right_arm_sprite:
			_right_arm_sprite.position = _right_arm_sprite.position.lerp(_base_right_arm_pos, lerp_speed)

## Update suppression state.
func _update_suppression(delta: float) -> void:
	# Clean up destroyed bullets from tracking
	_bullets_in_threat_sphere = _bullets_in_threat_sphere.filter(func(b): return is_instance_valid(b))

	# Determine if there's an active threat (bullets in sphere OR recent threat memory)
	var has_active_threat := not _bullets_in_threat_sphere.is_empty() or _threat_memory_timer > 0.0

	if not has_active_threat:
		if _under_fire:
			_suppression_timer += delta
			if _suppression_timer >= suppression_cooldown:
				_under_fire = false
				_suppression_timer = 0.0
				_log_debug("Suppression ended")
		# Reset threat reaction timer when no bullets are in threat sphere and no threat memory
		_threat_reaction_timer = 0.0
		_threat_reaction_delay_elapsed = false
	else:
		# Decrement threat memory timer if no bullets currently in sphere
		if _bullets_in_threat_sphere.is_empty() and _threat_memory_timer > 0.0:
			_threat_memory_timer -= delta

		# Update threat reaction timer
		if not _threat_reaction_delay_elapsed:
			_threat_reaction_timer += delta
			if _threat_reaction_timer >= threat_reaction_delay:
				_threat_reaction_delay_elapsed = true
				_log_debug("Threat reaction delay elapsed, now reacting to bullets")

		# Only set under_fire after the reaction delay has elapsed
		if _threat_reaction_delay_elapsed:
			_under_fire = true
			_suppression_timer = 0.0

## Update reload state.
func _update_reload(delta: float) -> void:
	if not _is_reloading:
		return

	_reload_timer += delta
	if _reload_timer >= reload_time:
		_finish_reload()

## Start reloading the weapon.
func _start_reload() -> void:
	# Can't reload if already reloading or no reserve ammo
	if _is_reloading or _reserve_ammo <= 0:
		return

	_is_reloading = true
	_reload_timer = 0.0
	reload_started.emit()
	_log_debug("Reloading... (%d reserve ammo)" % _reserve_ammo)

## Finish the reload process.
func _finish_reload() -> void:
	_is_reloading = false
	_reload_timer = 0.0

	# Calculate how many rounds to load
	var ammo_needed := magazine_size - _current_ammo
	var ammo_to_load := mini(ammo_needed, _reserve_ammo)

	_reserve_ammo -= ammo_to_load
	_current_ammo += ammo_to_load

	# Play reload complete sound
	AudioManager.play_reload_full(global_position)

	reload_finished.emit()
	ammo_changed.emit(_current_ammo, _reserve_ammo)
	_log_debug("Reload complete. Magazine: %d/%d, Reserve: %d" % [_current_ammo, magazine_size, _reserve_ammo])

## Check if the enemy can shoot (has ammo and not reloading).
func _can_shoot() -> bool:
	# Can't shoot if reloading
	if _is_reloading:
		return false

	# Can't shoot if no ammo in magazine
	if _current_ammo <= 0:
		# Try to start reload if we have reserve ammo
		if _reserve_ammo > 0:
			_start_reload()
		else:
			# No ammo at all - emit depleted signal once
			if not _goap_world_state.get("ammo_depleted", false):
				_goap_world_state["ammo_depleted"] = true
				ammo_depleted.emit()
				_log_debug("All ammunition depleted!")
		return false

	return true

## Process the AI state machine.
func _process_ai_state(delta: float) -> void:
	# If stunned, stop all movement and actions - do nothing
	if _is_stunned:
		velocity = Vector2.ZERO
		return

	var previous_state := _current_state

	# HIGHEST PRIORITY: Player distracted (aim > 23° away) - shoot immediately (Hard mode only)
	# NOTE: Disabled during memory reset confusion period (Issue #318)
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	var is_distraction_enabled: bool = difficulty_manager != null and difficulty_manager.is_distraction_attack_enabled()
	var is_confused: bool = _memory_reset_confusion_timer > 0.0
	if is_distraction_enabled and not is_confused and _goap_world_state.get("player_distracted", false) and _can_see_player and _player:
		# Check if we have a clear shot (no wall blocking bullet spawn)
		var direction_to_player := (_player.global_position - global_position).normalized()
		var has_clear_shot := _is_bullet_spawn_clear(direction_to_player)

		if has_clear_shot and _can_shoot() and _shoot_timer >= shoot_cooldown:
			_log_to_file("Player distracted - priority attack triggered")
			rotation = direction_to_player.angle()
			_force_model_to_face_direction(direction_to_player)  # Fix issue #264: ensure correct aim
			_shoot()
			_shoot_timer = 0.0
			_detection_delay_elapsed = true
			if _current_state == AIState.IDLE:
				_transition_to_combat()
				_detection_delay_elapsed = true

			# Return early - we've taken the highest priority action
			# The state machine will continue normally in the next frame
			return

	# HIGHEST PRIORITY: If player is reloading or tried to shoot with empty weapon,
	# and enemy is close to the player, immediately attack with maximum priority.
	# This exploits the player's vulnerability during reload or when out of ammo.
	var player_reloading: bool = _goap_world_state.get("player_reloading", false)
	var player_ammo_empty: bool = _goap_world_state.get("player_ammo_empty", false)
	var player_is_vulnerable: bool = player_reloading or player_ammo_empty
	var player_close: bool = _is_player_close()

	# Debug log when player is vulnerable (but not every frame - only when conditions change)
	if player_is_vulnerable and _player:
		var distance_to_player := global_position.distance_to(_player.global_position)
		_log_debug("Vulnerable check: reloading=%s, ammo_empty=%s, can_see=%s, close=%s (dist=%.0f)" % [player_reloading, player_ammo_empty, _can_see_player, player_close, distance_to_player])

	# Log vulnerability conditions when player is vulnerable but we can't attack
	# This helps diagnose why priority attacks might not be triggering
	if player_is_vulnerable and _player and not (player_close and _can_see_player):
		var distance_to_player := global_position.distance_to(_player.global_position)
		# Only log once per vulnerability state change to avoid spam
		var vuln_key := "last_vuln_log_frame"
		var current_frame := Engine.get_physics_frames()
		var last_log_frame: int = _goap_world_state.get(vuln_key, -100)
		if current_frame - last_log_frame > 30:  # Log at most every 30 frames (~0.5s)
			_goap_world_state[vuln_key] = current_frame
			var reason: String = "reloading" if player_reloading else "ammo_empty"
			_log_to_file("Player vulnerable (%s) but cannot attack: close=%s (dist=%.0f), can_see=%s" % [reason, player_close, distance_to_player, _can_see_player])

	# Issue #318: Also block vulnerability attacks during confusion period
	if player_is_vulnerable and not is_confused and _can_see_player and _player and player_close:
		# Check if we have a clear shot (no wall blocking bullet spawn)
		var direction_to_player := (_player.global_position - global_position).normalized()
		var has_clear_shot := _is_bullet_spawn_clear(direction_to_player)

		if has_clear_shot and _can_shoot() and _shoot_timer >= shoot_cooldown:
			# Log the vulnerability attack
			var reason: String = "reloading" if player_reloading else "empty ammo"
			_log_to_file("Player %s - priority attack triggered" % reason)

			# Aim at player immediately - both body rotation and model rotation
			rotation = direction_to_player.angle()
			# CRITICAL: Force the model to face the player immediately so that
			# _get_weapon_forward_direction() returns the correct aim direction.
			# Without this, the weapon transform would still reflect the old direction
			# and _shoot() would fail the aim tolerance check. (Fix for issue #264)
			_force_model_to_face_direction(direction_to_player)

			# Shoot with priority - still respects weapon fire rate cooldown
			# The weapon cannot physically fire faster than its fire rate
			_shoot()
			_shoot_timer = 0.0  # Reset shoot timer after vulnerability shot

			# Ensure detection delay is bypassed for any subsequent normal shots
			_detection_delay_elapsed = true

			# Transition to COMBAT if not already in a combat-related state
			if _current_state == AIState.IDLE:
				_transition_to_combat()
				_detection_delay_elapsed = true  # Re-set after transition resets it

			# Return early - we've taken the highest priority action
			return

	# SECOND PRIORITY: If player is vulnerable but NOT close, pursue them aggressively
	# This makes enemies rush toward vulnerable players to exploit the weakness
	if player_is_vulnerable and _can_see_player and _player and not player_close:
		var distance_to_player := global_position.distance_to(_player.global_position)
		# Only log once per pursuit decision to avoid spam
		var pursue_key := "last_pursue_vuln_frame"
		var current_frame := Engine.get_physics_frames()
		var last_pursue_frame: int = _goap_world_state.get(pursue_key, -100)
		if current_frame - last_pursue_frame > 60:  # Log at most every ~1 second
			_goap_world_state[pursue_key] = current_frame
			var reason: String = "reloading" if player_reloading else "ammo_empty"
			_log_to_file("Player vulnerable (%s) - pursuing to attack (dist=%.0f)" % [reason, distance_to_player])

		# Transition to PURSUING state to rush toward the player
		if _current_state != AIState.PURSUING and _current_state != AIState.ASSAULT:
			_transition_to_pursuing()
			# Don't return - let the state machine continue to process the PURSUING state

	# GRENADE THROW PRIORITY (Issue #363): Check if we should throw a grenade.
	# Grenades are thrown based on 6 trigger conditions (see trigger-conditions.md).
	# This takes priority over normal state actions when conditions are met.
	if _goap_world_state.get("ready_to_throw_grenade", false):
		if try_throw_grenade():
			# Grenade was thrown - return early to skip normal state processing this frame
			return

	# State transitions based on conditions
	match _current_state:
		AIState.IDLE:
			_process_idle_state(delta)
		AIState.COMBAT:
			_process_combat_state(delta)
		AIState.SEEKING_COVER:
			_process_seeking_cover_state(delta)
		AIState.IN_COVER:
			_process_in_cover_state(delta)
		AIState.FLANKING:
			_process_flanking_state(delta)
		AIState.SUPPRESSED:
			_process_suppressed_state(delta)
		AIState.RETREATING:
			_process_retreating_state(delta)
		AIState.PURSUING:
			_process_pursuing_state(delta)
		AIState.ASSAULT:
			_process_assault_state(delta)
		AIState.SEARCHING:
			_process_searching_state(delta)

	if previous_state != _current_state:
		state_changed.emit(_current_state)
		_log_debug("State changed: %s -> %s" % [AIState.keys()[previous_state], AIState.keys()[_current_state]])
		# Also log to file for exported build debugging
		_log_to_file("State: %s -> %s" % [AIState.keys()[previous_state], AIState.keys()[_current_state]])

## Process IDLE state - patrol or guard behavior.
func _process_idle_state(delta: float) -> void:
	# Transition to combat if player is visible
	if _can_see_player and _player:
		_transition_to_combat()
		return

	# Check memory system for suspected player position (Issue #297)
	# If we have high/medium confidence about player location, investigate
	if _memory and _memory.has_target():
		if _memory.is_high_confidence():
			# High confidence: Go investigate directly
			_log_debug("High confidence (%.0f%%) - investigating suspected position" % (_memory.confidence * 100))
			_log_to_file("Memory: high confidence (%.2f) - transitioning to PURSUING" % _memory.confidence)
			_transition_to_pursuing()
			return
		elif _memory.is_medium_confidence():
			# Medium confidence: Investigate cautiously (also use pursuing with cover-to-cover)
			_log_debug("Medium confidence (%.0f%%) - cautiously investigating" % (_memory.confidence * 100))
			_log_to_file("Memory: medium confidence (%.2f) - transitioning to PURSUING" % _memory.confidence)
			_transition_to_pursuing()
			return
		# Low confidence: Continue normal patrol but may wander toward suspected area

	# Execute idle behavior
	match behavior_mode:
		BehaviorMode.PATROL:
			_process_patrol(delta)
		BehaviorMode.GUARD:
			_process_guard(delta)

## Process COMBAT state - combat cycle: exit cover -> exposed shooting -> return to cover.
## Phase 1 (approaching): Move toward player to get into direct contact range.
## Phase 2 (exposed): Stand and shoot for 2-3 seconds.
## Phase 3: Return to cover via SEEKING_COVER state.
func _process_combat_state(delta: float) -> void:
	# Track time in COMBAT state (for preventing rapid state thrashing)
	_combat_state_timer += delta

	# Check for suppression - transition to retreating behavior
	# BUT: When pursuing a vulnerability sound (player reloading/out of ammo),
	# ignore suppression and continue the attack - this is the best time to strike!
	if _under_fire and enable_cover and not _pursuing_vulnerability_sound:
		_combat_exposed = false
		_combat_approaching = false
		_seeking_clear_shot = false
		_transition_to_retreating()
		return

	# NOTE: ASSAULT state transition removed per issue #169
	# Enemies now stay in COMBAT instead of transitioning to coordinated assault

	# If can't see player, pursue them (move cover-to-cover toward player)
	# But only after minimum time has elapsed to prevent rapid state thrashing
	# when visibility flickers at wall/obstacle edges
	if not _can_see_player:
		if _combat_state_timer >= COMBAT_MIN_DURATION_BEFORE_PURSUE:
			_combat_exposed = false
			_combat_approaching = false
			_seeking_clear_shot = false
			_log_debug("Lost sight of player in COMBAT (%.2fs), transitioning to PURSUING" % _combat_state_timer)
			_transition_to_pursuing()
			return
		# If minimum time hasn't elapsed, stay in COMBAT and wait
		# This prevents rapid COMBAT<->PURSUING thrashing

	# Update detection delay timer
	if not _detection_delay_elapsed:
		_detection_timer += delta
		if _detection_timer >= _get_effective_detection_delay():
			_detection_delay_elapsed = true

	# If we don't have cover, find some first (needed for returning later)
	if not _has_valid_cover and enable_cover:
		_find_cover_position()
		if _has_valid_cover:
			_log_debug("Found cover at %s for combat cycling" % _cover_position)

	# Check player distance for approach/exposed phase decisions
	var distance_to_player := INF
	if _player:
		distance_to_player = global_position.distance_to(_player.global_position)

	# Check if we have a clear shot (no wall blocking bullet spawn)
	var direction_to_player := Vector2.ZERO
	var has_clear_shot := true
	if _player:
		direction_to_player = (_player.global_position - global_position).normalized()
		has_clear_shot = _is_bullet_spawn_clear(direction_to_player)

	# If already exposed (shooting phase), handle shooting and timer
	if _combat_exposed:
		_combat_shoot_timer += delta

		# Check if exposure time is complete - go back to cover
		if _combat_shoot_timer >= _combat_shoot_duration and _has_valid_cover:
			_log_debug("Combat exposure time complete (%.1fs), returning to cover" % _combat_shoot_duration)
			_combat_exposed = false
			_combat_approaching = false
			_combat_shoot_timer = 0.0
			_transition_to_seeking_cover()
			return

		# Check if we still have a clear shot - if not, move sideways to find one
		if _player and not has_clear_shot:
			# Bullet spawn is blocked - move sideways to find a clear shot position
			var sidestep_dir := _find_sidestep_direction_for_clear_shot(direction_to_player)
			if sidestep_dir != Vector2.ZERO:
				velocity = sidestep_dir * combat_move_speed * 0.7
				rotation = direction_to_player.angle()  # Keep facing player while sidestepping
				_log_debug("COMBAT exposed: sidestepping to maintain clear shot")
			else:
				# No sidestep works - stay still, the shot might clear up
				velocity = Vector2.ZERO
			return

		# In exposed phase with clear shot, stand still and shoot
		velocity = Vector2.ZERO

		# Aim and shoot at player (only shoot after detection delay)
		if _player:
			_aim_at_player()
			if _detection_delay_elapsed and _shoot_timer >= shoot_cooldown:
				_shoot()
				_shoot_timer = 0.0
		return

	# --- CLEAR SHOT SEEKING PHASE ---
	# If bullet spawn is blocked and we're not already exposed, we need to move out from cover
	if not has_clear_shot and _player:
		# Start seeking clear shot if not already doing so
		if not _seeking_clear_shot:
			_seeking_clear_shot = true
			_clear_shot_timer = 0.0
			# Calculate target position: move perpendicular to player direction (around cover edge)
			_clear_shot_target = _calculate_clear_shot_exit_position(direction_to_player)
			_log_debug("COMBAT: bullet spawn blocked, seeking clear shot at %s" % _clear_shot_target)

		_clear_shot_timer += delta

		# Check if we've exceeded the max time trying to find a clear shot
		if _clear_shot_timer >= CLEAR_SHOT_MAX_TIME:
			_log_debug("COMBAT: clear shot timeout, trying flanking")
			_seeking_clear_shot = false
			_clear_shot_timer = 0.0
			# Try flanking to get around the obstacle
			if _can_attempt_flanking():
				_transition_to_flanking()
			else:
				_transition_to_pursuing()
			return

		# Move toward the clear shot target position
		var distance_to_target := global_position.distance_to(_clear_shot_target)
		if distance_to_target > 15.0:
			var move_direction := (_clear_shot_target - global_position).normalized()

			# Apply enhanced wall avoidance with dynamic weighting
			move_direction = _apply_wall_avoidance(move_direction)

			velocity = move_direction * combat_move_speed
			rotation = direction_to_player.angle()  # Keep facing player

			# Check if the new position now has a clear shot
			if _is_bullet_spawn_clear(direction_to_player):
				_log_debug("COMBAT: found clear shot position while moving")
				_seeking_clear_shot = false
				_clear_shot_timer = 0.0
				# Continue to exposed phase check below
			else:
				return  # Keep moving toward target
		else:
			# Reached target but still no clear shot - recalculate target
			_log_debug("COMBAT: reached target but no clear shot, recalculating")
			_clear_shot_target = _calculate_clear_shot_exit_position(direction_to_player)
			return

	# Reset seeking state if we now have a clear shot
	if _seeking_clear_shot and has_clear_shot:
		_log_debug("COMBAT: clear shot acquired")
		_seeking_clear_shot = false
		_clear_shot_timer = 0.0

	# Determine if we should be in approach phase or exposed shooting phase
	var in_direct_contact := distance_to_player <= COMBAT_DIRECT_CONTACT_DISTANCE

	# Enter exposed phase if we have a clear shot and are either close enough or have approached long enough
	if has_clear_shot and (in_direct_contact or _combat_approach_timer >= COMBAT_APPROACH_MAX_TIME):
		# Close enough AND have clear shot - start exposed shooting phase
		_combat_exposed = true
		_combat_approaching = false
		_combat_shoot_timer = 0.0
		_combat_approach_timer = 0.0
		# Randomize exposure duration between 2-3 seconds
		_combat_shoot_duration = randf_range(2.0, 3.0)
		_log_debug("COMBAT exposed phase started (distance: %.0f), will shoot for %.1fs" % [distance_to_player, _combat_shoot_duration])
		return

	# Need to approach player - move toward them
	if not _combat_approaching:
		_combat_approaching = true
		_combat_approach_timer = 0.0
		_log_debug("COMBAT approach phase started, moving toward player")

	_combat_approach_timer += delta

	# Move toward player while approaching
	if _player:
		var move_direction := direction_to_player

		# Apply enhanced wall avoidance with dynamic weighting
		move_direction = _apply_wall_avoidance(move_direction)

		velocity = move_direction * combat_move_speed
		rotation = direction_to_player.angle()  # Always face player

		# Can shoot while approaching (only after detection delay and if have clear shot)
		if has_clear_shot and _detection_delay_elapsed and _shoot_timer >= shoot_cooldown:
			_aim_at_player()
			_shoot()
			_shoot_timer = 0.0

## Calculate a position to exit cover and get a clear shot at the player.
func _calculate_clear_shot_exit_position(direction_to_player: Vector2) -> Vector2:
	# Calculate perpendicular directions to the player
	var perpendicular := Vector2(-direction_to_player.y, direction_to_player.x)

	# Try both perpendicular directions and pick the one that's more likely to work
	# Also blend with forward movement toward player to help navigate around cover
	var best_position := global_position
	var best_score := -1.0

	for side_multiplier: float in [1.0, -1.0]:
		var sidestep_dir: Vector2 = perpendicular * side_multiplier
		# Blend sidestep with forward movement for better cover navigation
		var exit_dir: Vector2 = (sidestep_dir * 0.7 + direction_to_player * 0.3).normalized()
		var test_position: Vector2 = global_position + exit_dir * CLEAR_SHOT_EXIT_DISTANCE

		# Score this position based on:
		# 1. Does it have a clear path? (no walls in the way)
		# 2. Would the bullet spawn be clear from there?
		var score: float = 0.0

		# Check if we can move to this position
		if _has_clear_path_to(test_position):
			score += 1.0

		# Check if bullet spawn would be clear from this position
		# This is a rough estimate - we check from the test position toward player
		var world_2d := get_world_2d()
		if world_2d != null:
			var space_state := world_2d.direct_space_state
			if space_state != null:
				var check_distance := bullet_spawn_offset + 5.0
				var query := PhysicsRayQueryParameters2D.new()
				query.from = test_position
				query.to = test_position + direction_to_player * check_distance
				query.collision_mask = 4  # Only check obstacles
				query.exclude = [get_rid()]
				var result := space_state.intersect_ray(query)
				if result.is_empty():
					score += 2.0  # Higher score for clear bullet spawn

		if score > best_score:
			best_score = score
			best_position = test_position

	# If no good position found, just move forward toward player
	if best_score < 0.5:
		best_position = global_position + direction_to_player * CLEAR_SHOT_EXIT_DISTANCE

	return best_position

## Process SEEKING_COVER state - moving to cover position.
func _process_seeking_cover_state(_delta: float) -> void:
	if not _has_valid_cover:
		# Try to find cover
		_find_cover_position()
		if not _has_valid_cover:
			# No cover found, stay in combat
			_transition_to_combat()
			return

	# Check if we're already hidden from the player (the main goal)
	if not _is_visible_from_player():
		_transition_to_in_cover()
		_log_debug("Hidden from player, entering cover state")
		return

	# Move towards cover
	var distance: float = global_position.distance_to(_cover_position)

	if distance < 10.0:
		# Reached the cover position, but still visible - try to find better cover
		if _is_visible_from_player():
			_has_valid_cover = false
			_find_cover_position()
			if not _has_valid_cover:
				# No better cover found, stay in combat
				_transition_to_combat()
				return

	# Use navigation-based pathfinding to move toward cover
	_move_to_target_nav(_cover_position, combat_move_speed)

	# Can still shoot while moving to cover (only after detection delay)
	if _can_see_player and _player and _detection_delay_elapsed and _shoot_timer >= shoot_cooldown:
		_aim_at_player()
		_shoot()
		_shoot_timer = 0.0

## Process IN_COVER state - taking cover from enemy fire.
## Decides next action based on:
## 1. If under fire -> suppressed
## 2. If player is close (can exit cover for direct contact) -> COMBAT
## 3. If player is far but can hit from current position -> COMBAT (stay and shoot)
## 4. If player is far and can't hit -> PURSUING (move cover-to-cover)
func _process_in_cover_state(delta: float) -> void:
	velocity = Vector2.ZERO

	# If still under fire, stay suppressed
	if _under_fire:
		_transition_to_suppressed()
		return

	# Check if player has flanked us - if we're now visible from player's position,
	# we need to find new cover
	if _is_visible_from_player():
		# If in alarm mode and can see player, fire a burst before escaping
		if _in_alarm_mode and _can_see_player and _player:
			if not _cover_burst_pending:
				# Start the cover burst
				_cover_burst_pending = true
				_retreat_burst_remaining = randi_range(2, 4)
				_retreat_burst_timer = 0.0
				_retreat_burst_angle_offset = -RETREAT_BURST_ARC / 2.0
				_log_debug("IN_COVER alarm: starting burst before escaping (%d shots)" % _retreat_burst_remaining)

			# Fire the burst
			if _retreat_burst_remaining > 0:
				_retreat_burst_timer += delta
				if _retreat_burst_timer >= RETREAT_BURST_COOLDOWN:
					_aim_at_player()
					_shoot_burst_shot()
					_retreat_burst_remaining -= 1
					_retreat_burst_timer = 0.0
					if _retreat_burst_remaining > 0:
						_retreat_burst_angle_offset += RETREAT_BURST_ARC / 3.0
				return  # Stay in cover while firing burst

		# Burst complete or not in alarm mode, seek new cover
		_log_debug("Player flanked our cover position, seeking new cover")
		_has_valid_cover = false  # Invalidate current cover
		_cover_burst_pending = false
		_transition_to_seeking_cover()
		return

	# NOTE: ASSAULT state transition removed per issue #169
	# Enemies now stay in IN_COVER instead of transitioning to coordinated assault

	# Decision making based on player distance and visibility
	if _player:
		var player_close := _is_player_close()
		var can_hit := _can_hit_player_from_current_position()

		if _can_see_player:
			if player_close:
				# Player is close - engage in combat (come out, shoot, go back)
				_log_debug("Player is close, transitioning to COMBAT")
				_transition_to_combat()
				return
			else:
				# Player is far
				if can_hit:
					# Can hit from current position - come out and shoot
					# (Don't pursue, just transition to combat which will handle the cycling)
					_log_debug("Player is far but can hit from here, transitioning to COMBAT")
					_transition_to_combat()
					return
				else:
					# Can't hit from here - need to pursue (move cover-to-cover)
					_log_debug("Player is far and can't hit, transitioning to PURSUING")
					_transition_to_pursuing()
					return

	# If not under fire and can see player, engage (only shoot after detection delay)
	if _can_see_player and _player:
		_aim_at_player()
		if _detection_delay_elapsed and _shoot_timer >= shoot_cooldown:
			_shoot()
			_shoot_timer = 0.0

	# If player is no longer visible and not under fire, try pursuing
	if not _can_see_player and not _under_fire:
		_log_debug("Lost sight of player from cover, transitioning to PURSUING")
		_transition_to_pursuing()

## Process FLANKING state - flank player using cover-to-cover movement.
func _process_flanking_state(delta: float) -> void:
	_flank_state_timer += delta

	if _flank_state_timer >= FLANK_STATE_MAX_TIME:
		_log_to_file("FLANKING timeout (%.1fs), target=%s, pos=%s" % [_flank_state_timer, _flank_target, global_position])
		_flank_side_initialized = false
		if _can_see_player: _transition_to_combat()
		else: _transition_to_pursuing()
		return

	var distance_moved := global_position.distance_to(_flank_last_position)
	if distance_moved < FLANK_PROGRESS_THRESHOLD:
		_flank_stuck_timer += delta
		if _flank_stuck_timer >= FLANK_STUCK_MAX_TIME:
			_log_to_file("FLANKING stuck (%.1fs), pos=%s, fail=%d" % [_flank_stuck_timer, global_position, _flank_fail_count + 1])
			_flank_side_initialized = false
			_flank_fail_count += 1
			_flank_cooldown_timer = FLANK_COOLDOWN_DURATION
			if _flank_fail_count >= FLANK_FAIL_MAX_COUNT:
				_log_to_file("FLANKING disabled after %d failures" % _flank_fail_count)
				_transition_to_combat()
				return
			if _can_see_player: _transition_to_combat()
			else: _transition_to_pursuing()
			return
	else:
		_flank_stuck_timer = 0.0
		_flank_last_position = global_position
		if _flank_fail_count > 0:
			_flank_fail_count = 0

	if _under_fire and enable_cover:
		_flank_side_initialized = false
		_transition_to_retreating()
		return

	# Only transition to combat if we can ACTUALLY HIT the player (not just see)
	if _can_see_player and _can_hit_player_from_current_position():
		_flank_side_initialized = false
		_transition_to_combat()
		return

	if _player == null:
		_flank_side_initialized = false
		if _has_left_idle:  # Issue #330: search instead of idle
			_transition_to_searching(global_position)
		else:
			_transition_to_idle()
		return

	_calculate_flank_position()  # Recalculate (player may have moved)

	if global_position.distance_to(_flank_target) < 30.0:
		_flank_side_initialized = false
		_transition_to_combat()
		return

	_move_to_target_nav(_flank_target, combat_move_speed)
	# Corner checking during FLANKING movement (Issue #332)
	if velocity.length_squared() > 1.0:
		_process_corner_check(delta, velocity.normalized(), "FLANKING")

## Process SUPPRESSED state - staying in cover under fire.
func _process_suppressed_state(delta: float) -> void:
	velocity = Vector2.ZERO

	# Check if player has flanked us - if we're now visible from player's position,
	# we need to find new cover even while suppressed
	if _is_visible_from_player():
		# In suppressed state we're always in alarm mode - fire a burst before escaping if we can see player
		if _can_see_player and _player:
			if not _cover_burst_pending:
				# Start the cover burst
				_cover_burst_pending = true
				_retreat_burst_remaining = randi_range(2, 4)
				_retreat_burst_timer = 0.0
				_retreat_burst_angle_offset = -RETREAT_BURST_ARC / 2.0
				_log_debug("SUPPRESSED alarm: starting burst before escaping (%d shots)" % _retreat_burst_remaining)

			# Fire the burst
			if _retreat_burst_remaining > 0:
				_retreat_burst_timer += delta
				if _retreat_burst_timer >= RETREAT_BURST_COOLDOWN:
					_aim_at_player()
					_shoot_burst_shot()
					_retreat_burst_remaining -= 1
					_retreat_burst_timer = 0.0
					if _retreat_burst_remaining > 0:
						_retreat_burst_angle_offset += RETREAT_BURST_ARC / 3.0
				return  # Stay suppressed while firing burst

		# Burst complete or can't see player, seek new cover
		_log_debug("Player flanked our cover position while suppressed, seeking new cover")
		_has_valid_cover = false  # Invalidate current cover
		_cover_burst_pending = false
		_transition_to_seeking_cover()
		return

	# Can still shoot while suppressed (only after detection delay)
	if _can_see_player and _player:
		_aim_at_player()
		if _detection_delay_elapsed and _shoot_timer >= shoot_cooldown:
			_shoot()
			_shoot_timer = 0.0

	# If no longer under fire, exit suppression
	if not _under_fire:
		_transition_to_in_cover()

## Process RETREATING state - moving to cover with behavior based on damage taken.
func _process_retreating_state(delta: float) -> void:
	if not _has_valid_cover:
		# Try to find cover
		_find_cover_position()
		if not _has_valid_cover:
			# No cover found, transition to combat or suppressed
			if _under_fire:
				_transition_to_suppressed()
			else:
				_transition_to_combat()
			return

	# Check if we've reached cover and are hidden from player
	if not _is_visible_from_player():
		_log_debug("Reached cover during retreat")
		# Reset encounter hits when successfully reaching cover
		_hits_taken_in_encounter = 0
		_transition_to_in_cover()
		return

	# Calculate direction to cover
	var direction_to_cover := (_cover_position - global_position).normalized()
	var distance_to_cover := global_position.distance_to(_cover_position)

	# Check if reached cover position
	if distance_to_cover < 10.0:
		if _is_visible_from_player():
			# Still visible, find better cover
			_has_valid_cover = false
			_find_cover_position()
			if not _has_valid_cover:
				if _under_fire:
					_transition_to_suppressed()
				else:
					_transition_to_combat()
			return

	# Apply retreat behavior based on mode
	match _retreat_mode:
		RetreatMode.FULL_HP:
			_process_retreat_full_hp(delta, direction_to_cover)
		RetreatMode.ONE_HIT:
			_process_retreat_one_hit(delta, direction_to_cover)
		RetreatMode.MULTIPLE_HITS:
			_process_retreat_multiple_hits(delta, direction_to_cover)

## Process FULL_HP retreat: walk backwards facing player, shoot with reduced accuracy.
func _process_retreat_full_hp(delta: float, _direction_to_cover: Vector2) -> void:
	_retreat_turn_timer += delta

	if _retreat_turning_to_cover:
		# Turning to face cover, don't shoot
		if _retreat_turn_timer >= RETREAT_TURN_DURATION:
			_retreat_turning_to_cover = false
			_retreat_turn_timer = 0.0

		# Use navigation to move toward cover
		_move_to_target_nav(_cover_position, combat_move_speed)
	else:
		# Face player and back up (walk backwards)
		if _retreat_turn_timer >= RETREAT_TURN_INTERVAL:
			_retreat_turning_to_cover = true
			_retreat_turn_timer = 0.0
			_log_debug("FULL_HP retreat: turning to check cover")

		if _player:
			# Face the player
			_aim_at_player()

			# Use navigation to move toward cover but keep facing player
			var nav_direction: Vector2 = _get_nav_direction_to(_cover_position)
			if nav_direction != Vector2.ZERO:
				nav_direction = _apply_wall_avoidance(nav_direction)
				velocity = nav_direction * combat_move_speed * 0.7  # Slower when backing up
			else:
				velocity = Vector2.ZERO

			# Shoot with reduced accuracy (only after detection delay)
			if _can_see_player and _detection_delay_elapsed and _shoot_timer >= shoot_cooldown:
				_shoot_with_inaccuracy()
				_shoot_timer = 0.0

## Process ONE_HIT retreat: quick burst of 2-4 shots in an arc while turning, then face cover.
func _process_retreat_one_hit(delta: float, direction_to_cover: Vector2) -> void:
	if not _retreat_burst_complete:
		# During burst phase
		_retreat_burst_timer += delta

		if _player and _retreat_burst_remaining > 0 and _retreat_burst_timer >= RETREAT_BURST_COOLDOWN:
			# Fire a burst shot with arc spread
			_shoot_burst_shot()
			_retreat_burst_remaining -= 1
			_retreat_burst_timer = 0.0

			# Progress through the arc
			if _retreat_burst_remaining > 0:
				_retreat_burst_angle_offset += RETREAT_BURST_ARC / 3.0  # Spread across 4 shots max

		# Gradually turn from player to cover during burst
		if _player:
			var direction_to_player: Vector2 = (_player.global_position - global_position).normalized()
			var target_angle: float

			# Interpolate rotation from player direction to cover direction
			var burst_progress: float = 1.0 - (float(_retreat_burst_remaining) / 4.0)
			var player_angle: float = direction_to_player.angle()
			var cover_direction: Vector2 = (_cover_position - global_position).normalized()
			var cover_angle: float = cover_direction.angle()
			target_angle = lerp_angle(player_angle, cover_angle, burst_progress * 0.7)
			rotation = target_angle

		# Use navigation to move toward cover (slower during burst)
		var nav_direction: Vector2 = _get_nav_direction_to(_cover_position)
		if nav_direction != Vector2.ZERO:
			nav_direction = _apply_wall_avoidance(nav_direction)
			velocity = nav_direction * combat_move_speed * 0.5

		# Check if burst is complete
		if _retreat_burst_remaining <= 0:
			_retreat_burst_complete = true
			_log_debug("ONE_HIT retreat: burst complete, now running to cover")
	else:
		# After burst, run to cover without shooting using navigation
		_move_to_target_nav(_cover_position, combat_move_speed)

## Process MULTIPLE_HITS retreat: quick burst of 2-4 shots then run to cover (same as ONE_HIT).
func _process_retreat_multiple_hits(delta: float, direction_to_cover: Vector2) -> void:
	# Same behavior as ONE_HIT - quick burst then escape
	_process_retreat_one_hit(delta, direction_to_cover)

## Process PURSUING state - move cover-to-cover toward player or vulnerability sound.
func _process_pursuing_state(delta: float) -> void:
	# Track time in PURSUING state (for preventing rapid state thrashing)
	_pursuing_state_timer += delta

	# Check for suppression - transition to retreating behavior
	# BUT: When pursuing a vulnerability sound (player reloading/out of ammo),
	# ignore suppression and continue the attack - this is the best time to strike!
	if _under_fire and enable_cover and not _pursuing_vulnerability_sound:
		_pursuit_approaching = false
		_transition_to_retreating()
		return

	# NOTE: ASSAULT state transition removed per issue #169
	# Enemies now stay in PURSUING instead of transitioning to coordinated assault

	# If can see player and can hit them from current position, engage
	# But only after minimum time has elapsed to prevent rapid state thrashing
	# when visibility flickers at wall/obstacle edges
	if _can_see_player and _player:
		var can_hit := _can_hit_player_from_current_position()
		if can_hit and _pursuing_state_timer >= PURSUING_MIN_DURATION_BEFORE_COMBAT:
			_log_debug("Can see and hit player from pursuit (%.2fs), transitioning to COMBAT" % _pursuing_state_timer)
			_has_pursuit_cover = false
			_pursuit_approaching = false
			_pursuing_vulnerability_sound = false
			_transition_to_combat()
			return

	# VULNERABILITY SOUND PURSUIT: When we heard a reload/empty click sound,
	# move directly toward the sound position using navigation (goes around walls).
	# This is a direct pursuit without cover-to-cover movement.
	if _pursuing_vulnerability_sound and _last_known_player_position != Vector2.ZERO:
		var distance_to_sound := global_position.distance_to(_last_known_player_position)

		# If we reached the sound position
		if distance_to_sound < 50.0:
			_log_debug("Reached vulnerability sound position (dist=%.0f)" % distance_to_sound)
			# If we can see the player now, attack
			if _can_see_player and _player:
				_log_debug("Can see player at sound position, transitioning to COMBAT")
				_pursuing_vulnerability_sound = false
				_transition_to_combat()
				return
			# If player moved or we still can't see them, clear the flag and use normal pursuit
			_log_debug("Player not visible at sound position, switching to normal pursuit")
			_pursuing_vulnerability_sound = false
			# Fall through to normal pursuit behavior

		else:
			# Keep moving toward the sound position using navigation
			_move_to_target_nav(_last_known_player_position, combat_move_speed)
			# Log progress periodically
			var vuln_pursuit_key := "last_vuln_pursuit_log"
			var current_frame := Engine.get_physics_frames()
			var last_log_frame: int = _goap_world_state.get(vuln_pursuit_key, -100)
			if current_frame - last_log_frame > 60:
				_goap_world_state[vuln_pursuit_key] = current_frame
				_log_to_file("Pursuing vulnerability sound at %s, distance=%.0f" % [_last_known_player_position, distance_to_sound])
			return

	# Process approach phase - moving directly toward player when no better cover exists
	if _pursuit_approaching:
		if _player:
			var direction := (_player.global_position - global_position).normalized()
			var can_hit := _can_hit_player_from_current_position()

			_pursuit_approach_timer += delta

			# If we can now hit the player, transition to combat
			if can_hit:
				_log_debug("Can now hit player after approach (%.1fs), transitioning to COMBAT" % _pursuit_approach_timer)
				_pursuit_approaching = false
				_transition_to_combat()
				return

			# If approach timer expired, give up and engage in combat anyway
			if _pursuit_approach_timer >= PURSUIT_APPROACH_MAX_TIME:
				_log_debug("Approach timer expired (%.1fs), transitioning to COMBAT" % _pursuit_approach_timer)
				_pursuit_approaching = false
				_transition_to_combat()
				return

			# If we found a new cover opportunity while approaching, take it
			if not _has_pursuit_cover:
				_find_pursuit_cover_toward_player()
				if _has_pursuit_cover:
					_log_debug("Found cover while approaching, switching to cover movement")
					_pursuit_approaching = false
					return

			# Use navigation to move toward target position (Issue #318)
			var target_pos := _get_target_position()
			if target_pos != global_position:
				_move_to_target_nav(target_pos, combat_move_speed)
			else:
				_pursuit_approaching = false
				# Issue #330: If enemy has left IDLE, start searching instead of returning to IDLE
				if _has_left_idle:
					_log_to_file("PURSUING: No valid target, starting search (engaged enemy)")
					_transition_to_searching(global_position)
				else:
					_transition_to_idle()  # No valid target
		return

	# Check if we're waiting at cover
	if _has_valid_cover and not _has_pursuit_cover:
		# Currently at cover, wait for 1-2 seconds before moving to next cover
		_pursuit_cover_wait_timer += delta
		velocity = Vector2.ZERO

		if _pursuit_cover_wait_timer >= PURSUIT_COVER_WAIT_DURATION:
			# Done waiting, find next cover closer to player
			_log_debug("Pursuit wait complete, finding next cover")
			_pursuit_cover_wait_timer = 0.0
			_find_pursuit_cover_toward_player()
			if _has_pursuit_cover:
				_log_debug("Found pursuit cover at %s" % _pursuit_next_cover)
			else:
				# No pursuit cover found - start approach phase if we can see player
				_log_debug("No pursuit cover found, checking fallback options")
				if _can_see_player and _player:
					# Can see but can't hit (at last cover) - start approach phase
					_log_debug("Can see player but can't hit, starting approach phase")
					_pursuit_approaching = true
					_pursuit_approach_timer = 0.0
					return
				# Try flanking if player not visible
				if _can_attempt_flanking() and _player:
					_log_debug("Attempting flanking maneuver")
					_transition_to_flanking()
					return
				# Last resort: move directly toward player
				_log_debug("No cover options, transitioning to COMBAT")
				_transition_to_combat()
				return
		return

	# If we have a pursuit cover target, move toward it
	if _has_pursuit_cover:
		var distance: float = global_position.distance_to(_pursuit_next_cover)

		# Check if we've reached the pursuit cover
		# Note: We only check distance here, NOT visibility from player.
		# If we checked visibility, the enemy would immediately consider themselves
		# "at cover" even before moving, since they start hidden from player.
		if distance < 15.0:
			_log_debug("Reached pursuit cover at distance %.1f" % distance)
			_has_pursuit_cover = false
			_pursuit_cover_wait_timer = 0.0
			_cover_position = _pursuit_next_cover
			_has_valid_cover = true
			# Start waiting at this cover
			return

		# Use navigation-based pathfinding to move toward pursuit cover
		_move_to_target_nav(_pursuit_next_cover, combat_move_speed)
		# Corner checking during PURSUING (Issue #332)
		if velocity.length_squared() > 1.0:
			_process_corner_check(delta, velocity.normalized(), "PURSUING")
		return

	# No cover and no pursuit target - find initial pursuit cover
	_find_pursuit_cover_toward_player()
	if not _has_pursuit_cover:
		# Check if we should investigate memory-based target (Issue #297)
		if _memory and _memory.has_target() and not _can_see_player:
			var target_pos := _memory.suspected_position
			var distance_to_target := global_position.distance_to(target_pos)

			# If we're close to the suspected position but haven't found the player
			if distance_to_target < 100.0:
				# We've investigated but player isn't here - reduce confidence
				_memory.decay(0.3)  # Significant confidence reduction
				_log_debug("Reached suspected position but player not found - reducing confidence")

				# If confidence is now low, start searching or return to idle
				if not _memory.has_target() or _memory.is_low_confidence():
					# Issue #330: If enemy has left IDLE, start searching instead of returning to IDLE
					if _has_left_idle:
						_log_to_file("Memory confidence too low - starting search (engaged enemy)")
						_transition_to_searching(target_pos)
					else:
						_log_to_file("Memory confidence too low after investigation - returning to IDLE")
						_transition_to_idle()
					return

			# Otherwise, continue moving toward suspected position
			_move_to_target_nav(target_pos, combat_move_speed)
			# Corner checking during pursuit to suspected position (Issue #332)
			if velocity.length_squared() > 1.0:
				_process_corner_check(delta, velocity.normalized(), "PURSUING_MEMORY")
			return

		# Can't find cover to pursue, try flanking or combat
		if _can_attempt_flanking() and _player:
			_transition_to_flanking()
		else:
			_transition_to_combat()

## Process ASSAULT state - disabled per issue #169. Immediately transitions to COMBAT.
func _process_assault_state(_delta: float) -> void:
	# ASSAULT state is disabled per issue #169
	# Immediately transition to COMBAT state
	_log_debug("ASSAULT state disabled (issue #169), transitioning to COMBAT")
	_in_assault = false
	_assault_ready = false
	_transition_to_combat()

## Generate search waypoints in expanding square spiral (Issue #322). Skips visited zones.
func _generate_search_waypoints() -> void:
	_search_waypoints.clear()
	_search_current_waypoint_index = 0
	_search_direction = 0
	_search_leg_length = SEARCH_WAYPOINT_SPACING
	_search_legs_completed = 0
	if not _is_zone_visited(_search_center):
		_search_waypoints.append(_search_center)
	var current_pos := _search_center
	var waypoints_generated := _search_waypoints.size()
	var iters := 0
	while waypoints_generated < 20 and _search_leg_length <= _search_radius * 2 and iters < 100:
		iters += 1
		var offset := Vector2.ZERO
		match _search_direction:
			0: offset = Vector2(0, -_search_leg_length)
			1: offset = Vector2(_search_leg_length, 0)
			2: offset = Vector2(0, _search_leg_length)
			3: offset = Vector2(-_search_leg_length, 0)
		var next_pos := current_pos + offset
		if _is_waypoint_navigable(next_pos) and not _is_zone_visited(next_pos):
			_search_waypoints.append(next_pos)
			waypoints_generated += 1
		current_pos = next_pos
		_search_legs_completed += 1
		_search_direction = (_search_direction + 1) % 4
		if _search_legs_completed % 2 == 0:
			_search_leg_length += SEARCH_WAYPOINT_SPACING
	_log_debug("Generated %d unvisited waypoints (radius=%.0f, visited=%d)" % [_search_waypoints.size(), _search_radius, _search_visited_zones.size()])

## Check if position is navigable via NavigationServer2D.
func _is_waypoint_navigable(pos: Vector2) -> bool:
	var nav_map := get_world_2d().navigation_map
	var closest := NavigationServer2D.map_get_closest_point(nav_map, pos)
	return pos.distance_to(closest) < 50.0

## Zone tracking helpers for visited areas (Issue #322): snaps to 50px grid.
func _get_zone_key(pos: Vector2) -> String:
	return "%d,%d" % [int(pos.x / SEARCH_ZONE_SNAP_SIZE) * int(SEARCH_ZONE_SNAP_SIZE), int(pos.y / SEARCH_ZONE_SNAP_SIZE) * int(SEARCH_ZONE_SNAP_SIZE)]
func _is_zone_visited(pos: Vector2) -> bool: return _search_visited_zones.has(_get_zone_key(pos))
func _mark_zone_visited(pos: Vector2) -> void:
	var k := _get_zone_key(pos)
	if not _search_visited_zones.has(k): _search_visited_zones[k] = true; _log_debug("SEARCHING: Marked zone %s as visited (total: %d)" % [k, _search_visited_zones.size()])

## Process SEARCHING state - move through waypoints, scan at each (Issue #322).
## Issue #330: If enemy has ever left IDLE, they NEVER return to IDLE - search infinitely.
func _process_searching_state(delta: float) -> void:
	_search_state_timer += delta
	# Issue #330: Only timeout if enemy has never engaged (still in patrol mode)
	# Once an enemy has left IDLE, they search infinitely until finding player
	if _search_state_timer >= SEARCH_MAX_DURATION and not _has_left_idle:
		_log_to_file("SEARCHING timeout after %.1fs, returning to IDLE (patrol enemy)" % _search_state_timer)
		_transition_to_idle()
		return
	if _can_see_player:
		_log_to_file("SEARCHING: Player spotted! Transitioning to COMBAT")
		_transition_to_combat()
		return
	if _search_current_waypoint_index >= _search_waypoints.size() or _search_waypoints.is_empty():
		if _search_radius < SEARCH_MAX_RADIUS:
			_search_radius += SEARCH_RADIUS_EXPANSION
			_generate_search_waypoints()
			_log_to_file("SEARCHING: Expand outer ring r=%.0f wps=%d" % [_search_radius, _search_waypoints.size()])
			if _search_waypoints.is_empty() and _search_radius < SEARCH_MAX_RADIUS:
				return
		else:
			# Issue #330: If enemy has left IDLE, reset search and keep searching
			if _has_left_idle:
				# Move search center to current position (so enemy explores new area)
				var old_center := _search_center
				_search_center = global_position
				_search_radius = SEARCH_INITIAL_RADIUS
				_search_state_timer = 0.0
				# Keep visited zones to avoid re-visiting same spots
				_generate_search_waypoints()
				_log_to_file("SEARCHING: Max radius reached, moved center from %s to %s (engaged enemy, wps=%d)" % [old_center, _search_center, _search_waypoints.size()])
				return
			else:
				_log_to_file("SEARCHING: Max radius, returning to IDLE (patrol enemy)")
				_transition_to_idle()
				return
	if _search_waypoints.is_empty():
		# Issue #330: If enemy has left IDLE, regenerate waypoints from new position
		if _has_left_idle:
			var old_center := _search_center
			_search_center = global_position
			_search_radius = SEARCH_INITIAL_RADIUS
			_generate_search_waypoints()
			_log_to_file("SEARCHING: No waypoints, moved center from %s to %s (engaged enemy, wps=%d)" % [old_center, _search_center, _search_waypoints.size()])
			return
		_transition_to_idle()
		return
	var target_waypoint := _search_waypoints[_search_current_waypoint_index]
	var dist := global_position.distance_to(target_waypoint)
	if _search_moving_to_waypoint:
		if dist <= SEARCH_WAYPOINT_REACHED_DISTANCE:
			_search_moving_to_waypoint = false
			_search_scan_timer = 0.0
			_search_stuck_timer = 0.0  # Issue #354: Reset stuck timer on waypoint reached
			_log_debug("SEARCHING: Reached waypoint %d, scanning..." % _search_current_waypoint_index)
		else:
			_nav_agent.target_position = target_waypoint
			if _nav_agent.is_navigation_finished():
				_mark_zone_visited(target_waypoint)
				_search_current_waypoint_index += 1
				_search_moving_to_waypoint = true
				_search_stuck_timer = 0.0  # Issue #354: Reset stuck timer
			else:
				var next_pos := _nav_agent.get_next_path_position()
				var dir := (next_pos - global_position).normalized()
				velocity = dir * move_speed * 0.7
				move_and_slide()

				# Issue #354: Stuck detection - check if making progress toward waypoint
				var progress := global_position.distance_to(_search_last_progress_position)
				if progress < SEARCH_PROGRESS_THRESHOLD:
					_search_stuck_timer += delta
					if _search_stuck_timer >= SEARCH_STUCK_MAX_TIME:
						# Stuck for too long - skip to next waypoint
						_log_to_file("SEARCHING: Stuck at waypoint %d (no progress for %.1fs), skipping" % [_search_current_waypoint_index, _search_stuck_timer])
						_mark_zone_visited(target_waypoint)
						_search_current_waypoint_index += 1
						_search_moving_to_waypoint = true
						_search_stuck_timer = 0.0
						_search_last_progress_position = global_position
						return
				else:
					# Making progress - reset stuck timer and update position
					_search_stuck_timer = 0.0
					_search_last_progress_position = global_position

				if dir.length() > 0.1:
					rotation = lerp_angle(rotation, dir.angle(), 5.0 * delta)
					# Corner checking during SEARCHING movement (Issue #332)
					_process_corner_check(delta, dir, "SEARCHING")
	else:
		_search_scan_timer += delta
		rotation += delta * 1.5
		if _search_scan_timer >= SEARCH_SCAN_DURATION:
			_mark_zone_visited(target_waypoint)
			_search_current_waypoint_index += 1
			_search_moving_to_waypoint = true
			_log_debug("SEARCHING: Scan done, next wp %d" % _search_current_waypoint_index)

## Shoot with reduced accuracy for retreat mode (bullets fly in barrel direction with spread).
func _shoot_with_inaccuracy() -> void:
	if bullet_scene == null or _player == null:
		return

	if not _can_shoot():
		return

	var target_position := _player.global_position

	# Check if the shot should be taken
	if not _should_shoot_at_target(target_position):
		return

	# Calculate bullet spawn position at weapon muzzle first
	var weapon_forward := _get_weapon_forward_direction()
	var bullet_spawn_pos := _get_bullet_spawn_position(weapon_forward)

	# Use enemy center (not muzzle) for aim check to fix close-range issues (Issue #344)
	var to_target := (target_position - global_position).normalized()

	# Check if weapon is aimed at target (within tolerance)
	# Bullets fly in barrel direction, so we only shoot when properly aimed (issue #254)
	var aim_dot := weapon_forward.dot(to_target)
	if aim_dot < AIM_TOLERANCE_DOT:
		if debug_logging:
			var aim_angle_deg := rad_to_deg(acos(clampf(aim_dot, -1.0, 1.0)))
			_log_debug("INACCURATE SHOOT BLOCKED: Not aimed at target. aim_dot=%.3f (%.1f deg off)" % [aim_dot, aim_angle_deg])
		return

	# Bullet direction is the weapon's forward direction (realistic barrel direction)
	# with added inaccuracy spread for retreat shooting
	var direction := weapon_forward

	# Add inaccuracy spread to barrel direction
	var inaccuracy_angle := randf_range(-RETREAT_INACCURACY_SPREAD, RETREAT_INACCURACY_SPREAD)
	direction = direction.rotated(inaccuracy_angle)

	# Check if the inaccurate shot direction would hit a wall
	if not _is_bullet_spawn_clear(direction):
		_log_debug("Inaccurate shot blocked: wall in path after rotation")
		return

	# Create and fire bullet
	var bullet := bullet_scene.instantiate()
	bullet.global_position = bullet_spawn_pos
	bullet.direction = direction
	bullet.shooter_id = get_instance_id()
	# Set shooter position for distance-based penetration calculation
	bullet.shooter_position = bullet_spawn_pos
	get_tree().current_scene.add_child(bullet)

	# Play sounds
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_m16_shot"):
		audio_manager.play_m16_shot(global_position)

	# Emit gunshot sound for in-game sound propagation (alerts other enemies)
	# Uses weapon_loudness to determine propagation range
	var sound_propagation: Node = get_node_or_null("/root/SoundPropagation")
	if sound_propagation and sound_propagation.has_method("emit_sound"):
		sound_propagation.emit_sound(0, global_position, 1, self, weapon_loudness)  # 0 = GUNSHOT, 1 = ENEMY

	_play_delayed_shell_sound()

	# Consume ammo
	_current_ammo -= 1
	ammo_changed.emit(_current_ammo, _reserve_ammo)

	if _current_ammo <= 0 and _reserve_ammo > 0:
		_start_reload()

## Shoot a burst shot with arc spread for ONE_HIT retreat.
## Bullets fly in barrel direction with added arc spread.
## Enemy must be properly aimed before shooting (within AIM_TOLERANCE_DOT).
func _shoot_burst_shot() -> void:
	if bullet_scene == null or _player == null:
		return

	if not _can_shoot():
		return

	var target_position := _player.global_position

	# Calculate bullet spawn position at weapon muzzle first
	var weapon_forward := _get_weapon_forward_direction()
	var bullet_spawn_pos := _get_bullet_spawn_position(weapon_forward)

	# Use enemy center (not muzzle) for aim check to fix close-range issues (Issue #344)
	var to_target := (target_position - global_position).normalized()

	# Check if weapon is aimed at target (within tolerance)
	# Bullets fly in barrel direction, so we only shoot when properly aimed (issue #254)
	var aim_dot := weapon_forward.dot(to_target)
	if aim_dot < AIM_TOLERANCE_DOT:
		if debug_logging:
			var aim_angle_deg := rad_to_deg(acos(clampf(aim_dot, -1.0, 1.0)))
			_log_debug("BURST SHOOT BLOCKED: Not aimed at target. aim_dot=%.3f (%.1f deg off)" % [aim_dot, aim_angle_deg])
		return

	# Bullet direction is the weapon's forward direction (realistic barrel direction)
	var direction := weapon_forward

	# Apply arc offset for burst spread
	direction = direction.rotated(_retreat_burst_angle_offset)

	# Also add some random inaccuracy on top of the arc
	var inaccuracy_angle := randf_range(-RETREAT_INACCURACY_SPREAD * 0.5, RETREAT_INACCURACY_SPREAD * 0.5)
	direction = direction.rotated(inaccuracy_angle)

	# Check if the burst shot direction would hit a wall
	if not _is_bullet_spawn_clear(direction):
		_log_debug("Burst shot blocked: wall in path after rotation")
		return

	# Create and fire bullet
	var bullet := bullet_scene.instantiate()
	bullet.global_position = bullet_spawn_pos
	bullet.direction = direction
	bullet.shooter_id = get_instance_id()
	# Set shooter position for distance-based penetration calculation
	bullet.shooter_position = bullet_spawn_pos
	get_tree().current_scene.add_child(bullet)

	# Play sounds
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_m16_shot"):
		audio_manager.play_m16_shot(global_position)

	# Emit gunshot sound for in-game sound propagation (alerts other enemies)
	# Uses weapon_loudness to determine propagation range
	var sound_propagation: Node = get_node_or_null("/root/SoundPropagation")
	if sound_propagation and sound_propagation.has_method("emit_sound"):
		sound_propagation.emit_sound(0, global_position, 1, self, weapon_loudness)  # 0 = GUNSHOT, 1 = ENEMY

	_play_delayed_shell_sound()

	# Consume ammo
	_current_ammo -= 1
	ammo_changed.emit(_current_ammo, _reserve_ammo)

	if _current_ammo <= 0 and _reserve_ammo > 0:
		_start_reload()

## Transition to IDLE state.
func _transition_to_idle() -> void:
	_current_state = AIState.IDLE
	# Reset various state tracking when returning to idle
	_hits_taken_in_encounter = 0; _in_alarm_mode = false; _cover_burst_pending = false
	_idle_scan_timer = 0.0; _idle_scan_targets.clear()  # Will be re-initialized in _process_guard

## Transition to COMBAT state.
func _transition_to_combat() -> void:
	_current_state = AIState.COMBAT
	_has_left_idle = true  # Issue #330
	_detection_timer = 0.0; _detection_delay_elapsed = false
	_combat_exposed = false; _combat_approaching = false
	_combat_shoot_timer = 0.0; _combat_approach_timer = 0.0; _combat_state_timer = 0.0
	_seeking_clear_shot = false; _clear_shot_timer = 0.0; _clear_shot_target = Vector2.ZERO
	_pursuing_vulnerability_sound = false

## Transition to SEEKING_COVER state.
func _transition_to_seeking_cover() -> void:
	_current_state = AIState.SEEKING_COVER
	# Mark that enemy has left IDLE state (Issue #330)
	_has_left_idle = true
	_find_cover_position()

## Transition to IN_COVER state.
func _transition_to_in_cover() -> void:
	_current_state = AIState.IN_COVER
	# Mark that enemy has left IDLE state (Issue #330)
	_has_left_idle = true

## Check if flanking is available (not on cooldown from failures).
func _can_attempt_flanking() -> bool:
	# Check if flanking is enabled
	if not enable_flanking:
		return false
	# Check if we're on cooldown from failures
	if _flank_cooldown_timer > 0.0:
		_log_debug("Flanking on cooldown (%.1fs remaining)" % _flank_cooldown_timer)
		return false
	# Check if we've hit the failure limit
	if _flank_fail_count >= FLANK_FAIL_MAX_COUNT:
		_log_debug("Flanking disabled due to %d failures" % _flank_fail_count)
		return false
	return true

## Transition to FLANKING state. Returns true if transition succeeded.
func _transition_to_flanking() -> bool:
	# Check if flanking is available
	if not _can_attempt_flanking():
		_log_debug("Cannot transition to FLANKING - disabled or on cooldown")
		# Fallback to combat instead
		_transition_to_combat()
		return false

	_current_state = AIState.FLANKING
	# Mark that enemy has left IDLE state (Issue #330)
	_has_left_idle = true
	# Clear vulnerability sound pursuit flag
	_pursuing_vulnerability_sound = false
	# Initialize flank side only once per flanking maneuver
	# Choose the side based on which direction has fewer obstacles
	_flank_side = _choose_best_flank_side()
	_flank_side_initialized = true
	_calculate_flank_position()

	# Validate that the flank target is reachable via navigation
	if not _is_flank_target_reachable():
		var msg := "Flank target unreachable via navigation, skipping flanking"
		_log_debug(msg)
		_log_to_file(msg)
		_flank_fail_count += 1
		_flank_cooldown_timer = FLANK_COOLDOWN_DURATION / 2.0  # Shorter cooldown for path check
		# Fallback to combat
		_transition_to_combat()
		return false

	_flank_cover_wait_timer = 0.0
	_has_flank_cover = false
	_has_valid_cover = false
	# Initialize timeout and progress tracking for stuck detection (Issue #367)
	_flank_state_timer = 0.0
	_flank_stuck_timer = 0.0
	_flank_last_position = global_position
	# Reset global stuck detection
	_global_stuck_timer = 0.0
	_global_stuck_last_position = global_position
	var msg := "FLANKING started: target=%s, side=%s, pos=%s" % [_flank_target, "right" if _flank_side > 0 else "left", global_position]
	_log_debug(msg)
	_log_to_file(msg)
	return true

## Check if the current flank target is reachable via navigation mesh.
func _is_flank_target_reachable() -> bool:
	if _nav_agent == null:
		return true  # Assume reachable if no nav agent

	# Set target and check if path exists
	_nav_agent.target_position = _flank_target

	# If navigation says we're already finished, the target might be unreachable
	# or we're already there. Check distance to determine.
	if _nav_agent.is_navigation_finished():
		var distance: float = global_position.distance_to(_flank_target)
		# If we're far from target but navigation is "finished", it's unreachable
		if distance > 50.0:
			return false

	# Check if the path distance is reasonable (not excessively long)
	var path_distance: float = _nav_agent.distance_to_target()
	var straight_distance: float = global_position.distance_to(_flank_target)

	# If path distance is more than 3x the straight line distance, consider it blocked
	if path_distance > straight_distance * 3.0 and path_distance > 500.0:
		_log_debug("Flank path too long: %.0f vs straight %.0f" % [path_distance, straight_distance])
		return false

	return true

## Transition to SUPPRESSED state.
func _transition_to_suppressed() -> void:
	_current_state = AIState.SUPPRESSED
	# Mark that enemy has left IDLE state (Issue #330)
	_has_left_idle = true
	# Enter alarm mode when suppressed
	_in_alarm_mode = true

## Transition to PURSUING state.
func _transition_to_pursuing() -> void:
	_current_state = AIState.PURSUING
	# Mark that enemy has left IDLE state (Issue #330)
	_has_left_idle = true
	_pursuit_cover_wait_timer = 0.0
	_has_pursuit_cover = false
	_pursuit_approaching = false
	_pursuit_approach_timer = 0.0
	_current_cover_obstacle = null
	# Reset state duration timer (prevents rapid state thrashing)
	_pursuing_state_timer = 0.0
	# Reset global stuck detection (Issue #367)
	_global_stuck_timer = 0.0
	_global_stuck_last_position = global_position
	# Reset detection delay for new engagement
	_detection_timer = 0.0
	_detection_delay_elapsed = false

## Transition to ASSAULT state.
func _transition_to_assault() -> void:
	_current_state = AIState.ASSAULT
	# Mark that enemy has left IDLE state (Issue #330)
	_has_left_idle = true
	_assault_wait_timer = 0.0
	_assault_ready = false
	_in_assault = false
	# Reset detection delay for new engagement
	_detection_timer = 0.0
	_detection_delay_elapsed = false
	# Find closest cover to player for assault position
	_find_cover_closest_to_player()

## Transition to SEARCHING state - methodical search around last known player position (Issue #322).
func _transition_to_searching(center_position: Vector2) -> void:
	_current_state = AIState.SEARCHING
	# Mark that enemy has left IDLE state (Issue #330)
	_has_left_idle = true
	_search_center = center_position; _search_radius = SEARCH_INITIAL_RADIUS
	_search_state_timer = 0.0; _search_scan_timer = 0.0; _search_current_waypoint_index = 0
	_search_direction = 0; _search_leg_length = SEARCH_WAYPOINT_SPACING; _search_legs_completed = 0
	_search_moving_to_waypoint = true; _search_visited_zones.clear()
	# Issue #354: Initialize stuck detection
	_search_stuck_timer = 0.0; _search_last_progress_position = global_position
	_generate_search_waypoints()
	var msg := "SEARCHING started: center=%s, radius=%.0f, waypoints=%d" % [_search_center, _search_radius, _search_waypoints.size()]
	_log_debug(msg); _log_to_file(msg)

## Transition to RETREATING state with appropriate retreat mode.
func _transition_to_retreating() -> void:
	_current_state = AIState.RETREATING
	# Mark that enemy has left IDLE state (Issue #330)
	_has_left_idle = true
	# Enter alarm mode when retreating
	_in_alarm_mode = true

	# Determine retreat mode based on hits taken
	if _hits_taken_in_encounter == 0:
		_retreat_mode = RetreatMode.FULL_HP
		_retreat_turn_timer = 0.0
		_retreat_turning_to_cover = false
		_log_debug("Entering RETREATING state: FULL_HP mode (shoot while backing up)")
	elif _hits_taken_in_encounter == 1:
		_retreat_mode = RetreatMode.ONE_HIT
		_retreat_burst_remaining = randi_range(2, 4)  # Random 2-4 bullets
		_retreat_burst_timer = 0.0
		_retreat_burst_complete = false
		# Calculate arc spread: shots will be distributed across the arc
		_retreat_burst_angle_offset = -RETREAT_BURST_ARC / 2.0
		_log_debug("Entering RETREATING state: ONE_HIT mode (burst of %d shots)" % _retreat_burst_remaining)
	else:
		_retreat_mode = RetreatMode.MULTIPLE_HITS
		# Multiple hits also gets burst fire (same as ONE_HIT)
		_retreat_burst_remaining = randi_range(2, 4)  # Random 2-4 bullets
		_retreat_burst_timer = 0.0
		_retreat_burst_complete = false
		_retreat_burst_angle_offset = -RETREAT_BURST_ARC / 2.0
		_log_debug("Entering RETREATING state: MULTIPLE_HITS mode (burst of %d shots)" % _retreat_burst_remaining)

	# Find cover position for retreating
	_find_cover_position()

## Check if the enemy is visible from the player's position.
## Uses raycasting from player to enemy to determine if there are obstacles blocking line of sight.
## This is the inverse of _can_see_player - it checks if the PLAYER can see the ENEMY.
## Checks multiple points on the enemy body (center and corners) to account for enemy size.
func _is_visible_from_player() -> bool:
	if _player == null:
		return false

	# Check visibility to multiple points on the enemy body
	# This accounts for the enemy's size - corners can stick out from cover
	var check_points := _get_enemy_check_points(global_position)

	for point in check_points:
		if _is_point_visible_from_player(point):
			return true

	return false

## Get multiple check points on the enemy body for visibility testing.
## Returns center and 4 corner points offset by the enemy's radius.
func _get_enemy_check_points(center: Vector2) -> Array[Vector2]:
	# Enemy collision radius is 24, sprite is 48x48
	# Use a slightly smaller radius to avoid edge cases
	const ENEMY_RADIUS: float = 22.0

	var points: Array[Vector2] = []
	points.append(center)  # Center point

	# 4 corner points (diagonal directions)
	var diagonal_offset := ENEMY_RADIUS * 0.707  # cos(45°) ≈ 0.707
	points.append(center + Vector2(diagonal_offset, diagonal_offset))
	points.append(center + Vector2(-diagonal_offset, diagonal_offset))
	points.append(center + Vector2(diagonal_offset, -diagonal_offset))
	points.append(center + Vector2(-diagonal_offset, -diagonal_offset))

	return points

## Check if a single point is visible from the player's position.
func _is_point_visible_from_player(point: Vector2) -> bool:
	if _player == null:
		return false

	var player_pos := _player.global_position
	var distance := player_pos.distance_to(point)

	# Use direct space state to check line of sight from player to point
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.new()
	query.from = player_pos
	query.to = point
	query.collision_mask = 4  # Only check obstacles (layer 3)
	query.exclude = []

	var result := space_state.intersect_ray(query)

	if result.is_empty():
		# No obstacle between player and point - point is visible
		return true
	else:
		# Check if we hit an obstacle before reaching the point
		var hit_position: Vector2 = result["position"]
		var distance_to_hit := player_pos.distance_to(hit_position)

		# If we hit something closer than the point, the point is hidden
		if distance_to_hit < distance - 10.0:  # 10 pixel tolerance
			return false
		else:
			return true

## Check if a specific position would make the enemy visible from the player's position.
## Checks all enemy body points (center and corners) to account for enemy size.
## Used to validate cover positions before moving to them.
func _is_position_visible_from_player(pos: Vector2) -> bool:
	if _player == null:
		return true  # Assume visible if no player

	# Check visibility for all enemy body points at the given position
	var check_points := _get_enemy_check_points(pos)

	for point in check_points:
		if _is_point_visible_from_player(point):
			return true

	return false

## Check if a target position is visible from the enemy's perspective.
## Uses raycast to verify there are no obstacles between enemy and the target position.
## This is used to validate lead prediction targets - enemies should only aim at
## positions they can actually see.
func _is_position_visible_to_enemy(target_pos: Vector2) -> bool:
	var distance := global_position.distance_to(target_pos)

	# Use direct space state to check line of sight from enemy to target
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.new()
	query.from = global_position
	query.to = target_pos
	query.collision_mask = 4  # Only check obstacles (layer 3)
	query.exclude = [get_rid()]  # Exclude self

	var result := space_state.intersect_ray(query)

	if result.is_empty():
		# No obstacle between enemy and target - position is visible
		return true

	# Check if we hit an obstacle before reaching the target
	var hit_position: Vector2 = result["position"]
	var distance_to_hit := global_position.distance_to(hit_position)

	if distance_to_hit < distance - 10.0:  # 10 pixel tolerance
		# Hit obstacle before target - position is NOT visible
		_log_debug("Position %s blocked by obstacle at distance %.1f (target at %.1f)" % [target_pos, distance_to_hit, distance])
		return false

	return true

## Get multiple check points on the player's body for visibility testing.
## Returns center and 4 corner points offset by the player's radius.
## The player has a collision radius of 16 pixels (from Player.tscn).
func _get_player_check_points(center: Vector2) -> Array[Vector2]:
	# Player collision radius is 16, sprite is 32x32
	# Use a slightly smaller radius to be conservative
	const PLAYER_RADIUS: float = 14.0

	var points: Array[Vector2] = []
	points.append(center)  # Center point

	# 4 corner points (diagonal directions)
	var diagonal_offset := PLAYER_RADIUS * 0.707  # cos(45°) ≈ 0.707
	points.append(center + Vector2(diagonal_offset, diagonal_offset))
	points.append(center + Vector2(-diagonal_offset, diagonal_offset))
	points.append(center + Vector2(diagonal_offset, -diagonal_offset))
	points.append(center + Vector2(-diagonal_offset, -diagonal_offset))

	return points

## Check if a single point on the player is visible from the enemy's position.
## Uses direct space state query to check for obstacles blocking line of sight.
func _is_player_point_visible_to_enemy(point: Vector2) -> bool:
	var distance := global_position.distance_to(point)

	# Use direct space state to check line of sight from enemy to point
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.new()
	query.from = global_position
	query.to = point
	query.collision_mask = 4  # Only check obstacles (layer 3)
	query.exclude = [get_rid()]  # Exclude self

	var result := space_state.intersect_ray(query)

	if result.is_empty():
		# No obstacle between enemy and point - point is visible
		return true

	# Check if we hit an obstacle before reaching the point
	var hit_position: Vector2 = result["position"]
	var distance_to_hit := global_position.distance_to(hit_position)

	# If we hit something before the point, the point is blocked
	if distance_to_hit < distance - 5.0:  # 5 pixel tolerance
		return false

	return true

## Calculate what fraction of the player's body is visible to the enemy.
## Returns a value from 0.0 (completely hidden) to 1.0 (fully visible).
## Checks multiple points on the player's body (center + corners).
func _calculate_player_visibility_ratio() -> float:
	if _player == null:
		return 0.0

	var check_points := _get_player_check_points(_player.global_position)
	var visible_count := 0

	for point in check_points:
		if _is_player_point_visible_to_enemy(point):
			visible_count += 1

	return float(visible_count) / float(check_points.size())

## Check if the line of fire to the target position is clear of other enemies.
## Returns true if no other enemies would be hit by a bullet traveling to the target.
func _is_firing_line_clear_of_friendlies(target_position: Vector2) -> bool:
	if not enable_friendly_fire_avoidance:
		return true

	# Get actual muzzle position for accurate raycast
	var weapon_forward := _get_weapon_forward_direction()
	var muzzle_pos := _get_bullet_spawn_position(weapon_forward)
	var distance := muzzle_pos.distance_to(target_position)

	# Use direct space state to check if any enemies are in the firing line
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.new()
	query.from = muzzle_pos  # Start from actual muzzle position
	query.to = target_position
	query.collision_mask = 2  # Only check enemies (layer 2)
	query.exclude = [get_rid()]  # Exclude self using RID

	var result := space_state.intersect_ray(query)

	if result.is_empty():
		return true  # No enemies in the way

	# Check if the hit position is before the target
	var hit_position: Vector2 = result["position"]
	var distance_to_hit := muzzle_pos.distance_to(hit_position)

	if distance_to_hit < distance - 20.0:  # 20 pixel tolerance
		_log_debug("Friendly in firing line at distance %0.1f (target at %0.1f)" % [distance_to_hit, distance])
		return false

	return true

## Check if a bullet fired at the target position would be blocked by cover/obstacles.
## Returns true if the shot would likely hit the target, false if blocked by cover.
func _is_shot_clear_of_cover(target_position: Vector2) -> bool:
	# Get actual muzzle position for accurate raycast
	var weapon_forward := _get_weapon_forward_direction()
	var muzzle_pos := _get_bullet_spawn_position(weapon_forward)
	var distance := muzzle_pos.distance_to(target_position)

	# Use direct space state to check if obstacles block the shot
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.new()
	query.from = muzzle_pos  # Start from actual muzzle position
	query.to = target_position
	query.collision_mask = 4  # Only check obstacles (layer 3)

	var result := space_state.intersect_ray(query)

	if result.is_empty():
		return true  # No obstacles in the way

	# Check if the obstacle is before the target position
	var hit_position: Vector2 = result["position"]
	var distance_to_hit := muzzle_pos.distance_to(hit_position)

	if distance_to_hit < distance - 10.0:  # 10 pixel tolerance
		_log_debug("Shot blocked by cover at distance %0.1f (target at %0.1f)" % [distance_to_hit, distance])
		return false

	return true

## Check if there's an obstacle immediately in front of the enemy that would block bullets.
## This prevents shooting into walls that the enemy is flush against or very close to.
## Uses a single raycast from enemy center to the bullet spawn position.
func _is_bullet_spawn_clear(direction: Vector2) -> bool:
	# Fail-open: allow shooting if physics is not ready
	var world_2d := get_world_2d()
	if world_2d == null:
		return true
	var space_state := world_2d.direct_space_state
	if space_state == null:
		return true

	# Check from enemy center to bullet spawn position plus a small buffer
	var check_distance := bullet_spawn_offset + 5.0

	var query := PhysicsRayQueryParameters2D.new()
	query.from = global_position
	query.to = global_position + direction * check_distance
	query.collision_mask = 4  # Only check obstacles (layer 3)
	query.exclude = [get_rid()]

	var result := space_state.intersect_ray(query)
	if not result.is_empty():
		_log_debug("Bullet spawn blocked: wall at distance %.1f" % [
			global_position.distance_to(result["position"])])
		return false

	return true

## Find a sidestep direction for a clear shot. Returns Vector2.ZERO if none found.
func _find_sidestep_direction_for_clear_shot(direction_to_player: Vector2) -> Vector2:
	# Fail-safe: allow normal behavior if physics is not ready
	var world_2d := get_world_2d()
	if world_2d == null:
		return Vector2.ZERO
	var space_state := world_2d.direct_space_state
	if space_state == null:
		return Vector2.ZERO

	# Check perpendicular directions (left and right of the player direction)
	var perpendicular := Vector2(-direction_to_player.y, direction_to_player.x)

	# Check both sidestep directions and pick the one that leads to clear shot faster
	var check_distance := 50.0  # Check if moving 50 pixels in this direction would help
	var bullet_check_distance := bullet_spawn_offset + 5.0

	for side_multiplier: float in [1.0, -1.0]:  # Try both sides
		var sidestep_dir: Vector2 = perpendicular * side_multiplier

		# First check if we can actually move in this direction (no wall blocking movement)
		var move_query := PhysicsRayQueryParameters2D.new()
		move_query.from = global_position
		move_query.to = global_position + sidestep_dir * 30.0
		move_query.collision_mask = 4  # Only check obstacles
		move_query.exclude = [get_rid()]

		var move_result := space_state.intersect_ray(move_query)
		if not move_result.is_empty():
			continue  # Can't move this way, wall is blocking

		# Check if after sidestepping, we'd have a clear shot
		var test_position: Vector2 = global_position + sidestep_dir * check_distance
		var shot_query := PhysicsRayQueryParameters2D.new()
		shot_query.from = test_position
		shot_query.to = test_position + direction_to_player * bullet_check_distance
		shot_query.collision_mask = 4
		shot_query.exclude = [get_rid()]

		var shot_result := space_state.intersect_ray(shot_query)
		if shot_result.is_empty():
			# Found a direction that leads to a clear shot
			_log_debug("Found sidestep direction: %s" % sidestep_dir)
			return sidestep_dir

	return Vector2.ZERO  # No clear sidestep direction found

## Check if the enemy should shoot at the target (bullet spawn, friendly fire, cover).
func _should_shoot_at_target(target_position: Vector2) -> bool:
	# Check if the immediate path to bullet spawn is clear
	# This prevents shooting into walls the enemy is flush against
	# Use weapon forward direction since that's where bullets actually spawn and travel
	var weapon_direction := _get_weapon_forward_direction()
	if not _is_bullet_spawn_clear(weapon_direction):
		return false

	# Check if friendlies are in the way
	if not _is_firing_line_clear_of_friendlies(target_position):
		return false

	# Check if cover blocks the shot
	if not _is_shot_clear_of_cover(target_position):
		return false

	return true

## Check if the player is close (within CLOSE_COMBAT_DISTANCE).
func _is_player_close() -> bool:
	if _player == null:
		return false
	return global_position.distance_to(_player.global_position) <= CLOSE_COMBAT_DISTANCE

## Get target position: visible player > memory > last known > stay in place (Issue #297, #318).
func _get_target_position() -> Vector2:
	if _can_see_player and _player:
		return _player.global_position
	if _memory and _memory.has_target():
		return _memory.suspected_position
	if _last_known_player_position != Vector2.ZERO:
		return _last_known_player_position
	return global_position  # No valid target - stay in place

## Check if the enemy can hit the player from their current position.
## Returns true if there's a clear line of fire to the player.
func _can_hit_player_from_current_position() -> bool:
	if _player == null:
		return false

	# Check if we can see the player
	if not _can_see_player:
		return false

	# Check if the shot would be blocked by cover
	return _is_shot_clear_of_cover(_player.global_position)

## Count the number of enemies currently in combat-related states.
## Includes COMBAT, PURSUING, ASSAULT, IN_COVER (if can see player).
## Used to determine if multi-enemy assault should be triggered.
func _count_enemies_in_combat() -> int:
	var count := 0
	var enemies := get_tree().get_nodes_in_group("enemies")

	for enemy in enemies:
		if enemy == self:
			continue
		if not enemy.has_method("get_current_state"):
			continue

		var state: AIState = enemy.get_current_state()
		# Count enemies in combat-related states
		if state in [AIState.COMBAT, AIState.ASSAULT, AIState.IN_COVER, AIState.SEEKING_COVER, AIState.PURSUING]:
			# For IN_COVER, only count if they can see the player
			if state == AIState.IN_COVER:
				if enemy.has_method("is_in_combat_engagement") and enemy.is_in_combat_engagement():
					count += 1
			else:
				count += 1

	# Count self if in a combat-related state
	if _current_state in [AIState.COMBAT, AIState.ASSAULT, AIState.IN_COVER, AIState.SEEKING_COVER, AIState.PURSUING]:
		count += 1

	return count

## Check if this enemy is engaged in combat (can see player and in combat state).
func is_in_combat_engagement() -> bool:
	return _can_see_player and _current_state in [AIState.COMBAT, AIState.IN_COVER, AIState.ASSAULT]

## Find cover position closer to the player for pursuit.
## Used during PURSUING state to move cover-to-cover toward the player.
## Improvements for issue #93:
## - Penalizes covers on the same obstacle to avoid shuffling along walls
## - Requires minimum progress toward player to skip insignificant moves
## - Verifies the path to cover is clear (no walls blocking)
func _find_pursuit_cover_toward_player() -> void:
	# Use memory-based target position instead of direct player position (Issue #297)
	# This allows pursuing toward a suspected position even when player is not visible
	var target_pos := _get_target_position()

	# If no valid target and no player, can't pursue
	if target_pos == global_position and _player == null:
		_has_pursuit_cover = false
		return

	var player_pos := target_pos
	var best_cover: Vector2 = Vector2.ZERO
	var best_score: float = -INF
	var best_obstacle: Object = null
	var found_valid_cover: bool = false

	var my_distance_to_player := global_position.distance_to(player_pos)
	# Calculate minimum required progress (must get at least this much closer)
	var min_required_progress := my_distance_to_player * PURSUIT_MIN_PROGRESS_FRACTION

	# Cast rays in all directions to find obstacles
	for i in range(COVER_CHECK_COUNT):
		var angle := (float(i) / COVER_CHECK_COUNT) * TAU
		var direction := Vector2.from_angle(angle)

		var raycast := _cover_raycasts[i]
		raycast.target_position = direction * COVER_CHECK_DISTANCE
		raycast.force_raycast_update()

		if raycast.is_colliding():
			var collision_point := raycast.get_collision_point()
			var collision_normal := raycast.get_collision_normal()
			var collider := raycast.get_collider()

			# Cover position is offset from collision point along normal
			var cover_pos := collision_point + collision_normal * 35.0

			# For pursuit, we want cover that is:
			# 1. Closer to the player than we currently are (with minimum progress)
			# 2. Hidden from the player (or mostly hidden)
			# 3. Not too far from our current position
			# 4. Preferably on a different obstacle than current cover
			# 5. Reachable (no walls blocking the path)

			var cover_distance_to_player := cover_pos.distance_to(player_pos)
			var cover_distance_from_me := global_position.distance_to(cover_pos)
			var progress := my_distance_to_player - cover_distance_to_player

			# Skip covers that don't bring us closer to player
			if cover_distance_to_player >= my_distance_to_player:
				continue

			# Skip covers that don't make enough progress (issue #93 fix)
			# This prevents stopping repeatedly along the same long wall
			if progress < min_required_progress:
				continue

			# Skip covers that are too close to current position (would cause looping)
			# Must be at least 30 pixels away to be a meaningful movement
			if cover_distance_from_me < 30.0:
				continue

			# Verify we can actually reach this cover position (no wall blocking path)
			if not _can_reach_position(cover_pos):
				continue

			# Check if this position is hidden from player
			var is_hidden := not _is_position_visible_from_player(cover_pos)

			# Check if this is the same obstacle as our current cover (issue #93 fix)
			var same_obstacle_penalty: float = 0.0
			if _current_cover_obstacle != null and collider == _current_cover_obstacle:
				same_obstacle_penalty = PURSUIT_SAME_OBSTACLE_PENALTY

			# Score calculation:
			# Higher score for positions that are:
			# - Hidden from player (priority)
			# - Closer to player
			# - Not too far from current position
			# - On a different obstacle than current cover
			var hidden_score: float = 5.0 if is_hidden else 0.0
			var approach_score: float = progress / CLOSE_COMBAT_DISTANCE
			var distance_penalty: float = cover_distance_from_me / COVER_CHECK_DISTANCE

			var total_score: float = hidden_score + approach_score * 2.0 - distance_penalty - same_obstacle_penalty

			if total_score > best_score:
				best_score = total_score
				best_cover = cover_pos
				best_obstacle = collider
				found_valid_cover = true

	if found_valid_cover:
		_pursuit_next_cover = best_cover
		_has_pursuit_cover = true
		_current_cover_obstacle = best_obstacle
		_log_debug("Found pursuit cover at %s (score: %.2f)" % [_pursuit_next_cover, best_score])
	else:
		_has_pursuit_cover = false

## Check if there's a clear path to a position (no walls blocking).
func _can_reach_position(target: Vector2) -> bool:
	var world_2d := get_world_2d()
	if world_2d == null:
		return true  # Fail-open

	var space_state := world_2d.direct_space_state
	if space_state == null:
		return true  # Fail-open

	var query := PhysicsRayQueryParameters2D.new()
	query.from = global_position
	query.to = target
	query.collision_mask = 4  # Obstacles only (layer 3)
	query.exclude = [get_rid()]

	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return true  # No obstacle in the way

	# Check if obstacle is beyond the target position (acceptable)
	var hit_distance := global_position.distance_to(result["position"])
	var target_distance := global_position.distance_to(target)
	return hit_distance >= target_distance - 10.0  # 10 pixel tolerance

## Find cover position closest to the player for assault positioning.
func _find_cover_closest_to_player() -> void:
	if _player == null:
		_has_valid_cover = false
		return

	var player_pos := _player.global_position
	var best_cover: Vector2 = Vector2.ZERO
	var best_distance: float = INF
	var found_cover: bool = false

	# Cast rays in all directions to find obstacles
	for i in range(COVER_CHECK_COUNT):
		var angle := (float(i) / COVER_CHECK_COUNT) * TAU
		var direction := Vector2.from_angle(angle)

		var raycast := _cover_raycasts[i]
		raycast.target_position = direction * COVER_CHECK_DISTANCE
		raycast.force_raycast_update()

		if raycast.is_colliding():
			var collision_point := raycast.get_collision_point()
			var collision_normal := raycast.get_collision_normal()

			# Cover position is offset from collision point along normal
			var cover_pos := collision_point + collision_normal * 35.0

			# CRITICAL: Verify we can actually reach this cover position
			# This prevents selecting cover positions on the opposite side of walls
			if not _can_reach_position(cover_pos):
				continue

			# Check if this position is hidden from player (safe cover)
			var is_hidden := not _is_position_visible_from_player(cover_pos)

			if is_hidden:
				# Calculate distance from this cover to the player
				var distance_to_player := cover_pos.distance_to(player_pos)

				# We want the cover closest to the player
				if distance_to_player < best_distance:
					best_distance = distance_to_player
					best_cover = cover_pos
					found_cover = true

	if found_cover:
		_cover_position = best_cover
		_has_valid_cover = true
		_log_debug("Found assault cover at %s (distance to player: %.1f)" % [_cover_position, best_distance])
	else:
		# Fall back to normal cover finding
		_find_cover_position()

## Find a valid cover position relative to the player.
## The cover position must be hidden from the player's line of sight.
## Enhanced: Now validates that the cover position is reachable (no walls blocking path).
func _find_cover_position() -> void:
	if _player == null:
		_has_valid_cover = false
		return

	var player_pos := _player.global_position
	var best_cover: Vector2 = Vector2.ZERO
	var best_score: float = -INF
	var found_hidden_cover: bool = false

	# Cast rays in all directions to find obstacles
	for i in range(COVER_CHECK_COUNT):
		var angle := (float(i) / COVER_CHECK_COUNT) * TAU
		var direction := Vector2.from_angle(angle)

		var raycast := _cover_raycasts[i]
		raycast.target_position = direction * COVER_CHECK_DISTANCE
		raycast.force_raycast_update()

		if raycast.is_colliding():
			var collision_point := raycast.get_collision_point()
			var collision_normal := raycast.get_collision_normal()

			# Cover position is on the opposite side of the obstacle from player
			var direction_from_player := (collision_point - player_pos).normalized()

			# Position behind cover (offset from collision point along normal)
			# Offset must be large enough to hide the entire enemy body (radius ~24 pixels)
			# Using 35 pixels to provide some margin for the enemy's collision shape
			var cover_pos := collision_point + collision_normal * 35.0

			# CRITICAL: Verify we can actually reach this cover position
			# This prevents selecting cover positions on the opposite side of walls
			if not _can_reach_position(cover_pos):
				continue

			# First priority: Check if this position is actually hidden from player
			var is_hidden := not _is_position_visible_from_player(cover_pos)

			# Only consider hidden positions unless we have no choice
			if is_hidden or not found_hidden_cover:
				# Score based on:
				# 1. Whether position is hidden (highest priority)
				# 2. Distance from enemy (closer is better)
				# 3. Position relative to player (behind cover from player's view)
				var hidden_score: float = 10.0 if is_hidden else 0.0  # Heavy weight for hidden positions

				var distance_score := 1.0 - (global_position.distance_to(cover_pos) / COVER_CHECK_DISTANCE)

				# Check if this position is on the far side of obstacle from player
				var cover_direction := (cover_pos - player_pos).normalized()
				var dot_product := direction_from_player.dot(cover_direction)
				var blocking_score: float = maxf(0.0, dot_product)

				var total_score: float = hidden_score + distance_score * 0.3 + blocking_score * 0.7

				# If we find a hidden position, only accept other hidden positions
				if is_hidden and not found_hidden_cover:
					found_hidden_cover = true
					best_score = total_score
					best_cover = cover_pos
				elif (is_hidden or not found_hidden_cover) and total_score > best_score:
					best_score = total_score
					best_cover = cover_pos

	if best_score > 0:
		_cover_position = best_cover
		_has_valid_cover = true
		_log_debug("Found cover at: %s (hidden: %s)" % [_cover_position, found_hidden_cover])
	else:
		_has_valid_cover = false

## Calculate flank position based on player location and stored _flank_side.
func _calculate_flank_position() -> void:
	if _player == null:
		return

	var player_pos := _player.global_position
	var player_to_enemy := (global_position - player_pos).normalized()

	# Use the stored flank side (initialized in _transition_to_flanking)
	var flank_direction := player_to_enemy.rotated(flank_angle * _flank_side)

	_flank_target = player_pos + flank_direction * flank_distance
	_log_debug("Flank target: %s (side: %s)" % [_flank_target, "right" if _flank_side > 0 else "left"])

## Choose the best flank side (1.0=right, -1.0=left) based on obstacle presence.
## Issue #367: Also checks if the flank position has line-of-sight to the player,
## to avoid choosing positions behind walls relative to the player.
func _choose_best_flank_side() -> float:
	if _player == null:
		return 1.0 if randf() > 0.5 else -1.0

	var player_pos := _player.global_position
	var player_to_enemy := (global_position - player_pos).normalized()

	# Calculate potential flank positions for both sides
	var right_flank_dir := player_to_enemy.rotated(flank_angle * 1.0)
	var left_flank_dir := player_to_enemy.rotated(flank_angle * -1.0)

	var right_flank_pos := player_pos + right_flank_dir * flank_distance
	var left_flank_pos := player_pos + left_flank_dir * flank_distance

	# Check if paths are clear for both sides (from enemy to flank position)
	var right_path_clear := _has_clear_path_to(right_flank_pos)
	var left_path_clear := _has_clear_path_to(left_flank_pos)

	# Issue #367: Check LOS to player and combine with path checks
	var right_valid := right_path_clear and _flank_position_has_los_to_player(right_flank_pos, player_pos)
	var left_valid := left_path_clear and _flank_position_has_los_to_player(left_flank_pos, player_pos)

	if right_valid and not left_valid:
		return 1.0
	elif left_valid and not right_valid:
		return -1.0

	# Issue #367: If neither valid, try reduced distance (50%)
	if not right_valid and not left_valid:
		var rd := flank_distance * 0.5
		var rr := player_pos + right_flank_dir * rd
		var lr := player_pos + left_flank_dir * rd
		var rrv := _has_clear_path_to(rr) and _flank_position_has_los_to_player(rr, player_pos)
		var lrv := _has_clear_path_to(lr) and _flank_position_has_los_to_player(lr, player_pos)
		if rrv and not lrv:
			return 1.0
		elif lrv and not rrv:
			return -1.0
		if not rrv and not lrv:
			_log_to_file("Warning: No valid flank position (both sides behind walls)")

	# Choose closer side
	return 1.0 if global_position.distance_squared_to(right_flank_pos) < global_position.distance_squared_to(left_flank_pos) else -1.0

## Check if flank position has LOS to player (Issue #367).
func _flank_position_has_los_to_player(flank_pos: Vector2, player_pos: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(flank_pos, player_pos)
	query.collision_mask = 0b100  # Walls only
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()

## Check if there's a clear path (no obstacles) to the target position.
func _has_clear_path_to(target: Vector2) -> bool:
	if _raycast == null:
		return true  # Assume clear if no raycast available

	var direction := (target - global_position).normalized()
	var distance := global_position.distance_to(target)

	_raycast.target_position = direction * distance
	_raycast.force_raycast_update()

	# If we hit something, path is blocked
	if _raycast.is_colliding():
		var collision_point := _raycast.get_collision_point()
		var collision_distance := global_position.distance_to(collision_point)
		# Only consider it blocked if the collision is before the target
		return collision_distance >= distance - 10.0

	return true

## Find cover position closer to the flank target for cover-to-cover movement.
func _find_flank_cover_toward_target() -> void:
	var best_cover: Vector2 = Vector2.ZERO
	var best_score: float = -INF
	var found_valid_cover: bool = false

	# Cast rays in all directions to find obstacles
	for i in range(COVER_CHECK_COUNT):
		var angle := (float(i) / COVER_CHECK_COUNT) * TAU
		var direction := Vector2.from_angle(angle)

		var raycast := _cover_raycasts[i]
		raycast.target_position = direction * COVER_CHECK_DISTANCE
		raycast.force_raycast_update()

		if raycast.is_colliding():
			var collision_point := raycast.get_collision_point()
			var collision_normal := raycast.get_collision_normal()

			# Cover position is offset from collision point along normal
			var cover_pos := collision_point + collision_normal * 35.0

			# For flanking, we want cover that is:
			# 1. Closer to the flank target than we currently are
			# 2. Not too far from our current position
			# 3. Reachable (has clear path)

			var my_distance_to_target := global_position.distance_to(_flank_target)
			var cover_distance_to_target := cover_pos.distance_to(_flank_target)
			var cover_distance_from_me := global_position.distance_to(cover_pos)

			# Skip covers that don't bring us closer to flank target
			if cover_distance_to_target >= my_distance_to_target:
				continue

			# Skip covers that are too close to current position (would cause looping)
			# Must be at least 30 pixels away to be a meaningful movement
			if cover_distance_from_me < 30.0:
				continue

			# Check if we can reach this cover (has clear path)
			if not _has_clear_path_to(cover_pos):
				# Even if direct path is blocked, we might be able to reach
				# via another intermediate cover, but skip for now
				continue

			# Score calculation:
			# Higher score for positions that are:
			# - Closer to flank target (priority)
			# - Not too far from current position
			var approach_score: float = (my_distance_to_target - cover_distance_to_target) / flank_distance
			var distance_penalty: float = cover_distance_from_me / COVER_CHECK_DISTANCE

			var total_score: float = approach_score * 2.0 - distance_penalty

			if total_score > best_score:
				best_score = total_score
				best_cover = cover_pos
				found_valid_cover = true

	if found_valid_cover:
		_flank_next_cover = best_cover
		_has_flank_cover = true
		_log_debug("Found flank cover at %s (score: %.2f)" % [_flank_next_cover, best_score])
	else:
		_has_flank_cover = false

## Check if there's a wall ahead in the given direction and return avoidance direction.
## Returns Vector2.ZERO if no wall detected, otherwise returns a vector to avoid the wall.
## Enhanced version uses 8 raycasts with distance-weighted avoidance for better navigation.
func _check_wall_ahead(direction: Vector2) -> Vector2:
	if _wall_raycasts.is_empty():
		return Vector2.ZERO

	var avoidance := Vector2.ZERO
	var perpendicular := Vector2(-direction.y, direction.x)  # 90 degrees rotation
	var closest_wall_distance: float = WALL_CHECK_DISTANCE
	var hit_count: int = 0

	# Raycast angles: spread from -90 to +90 degrees relative to movement direction
	# Index 0: center (0°)
	# Index 1-3: left side (-20°, -45°, -70°)
	# Index 4-6: right side (+20°, +45°, +70°)
	# Index 7: rear check for wall sliding (-180°)
	# IMPORTANT: Use explicit Array[float] type to avoid type inference errors
	var angles: Array[float] = [0.0, -0.35, -0.79, -1.22, 0.35, 0.79, 1.22, PI]

	var raycast_count: int = mini(WALL_CHECK_COUNT, _wall_raycasts.size())
	for i: int in range(raycast_count):
		# IMPORTANT: Use explicit float type to avoid type inference error
		var angle_offset: float = angles[i] if i < angles.size() else 0.0
		var check_direction: Vector2 = direction.rotated(angle_offset)

		var raycast: RayCast2D = _wall_raycasts[i]
		# Use shorter distance for rear check (wall sliding detection)
		var check_distance: float = WALL_SLIDE_DISTANCE if i == 7 else WALL_CHECK_DISTANCE
		raycast.target_position = check_direction * check_distance
		raycast.force_raycast_update()

		if raycast.is_colliding():
			hit_count += 1
			var collision_point: Vector2 = raycast.get_collision_point()
			var wall_distance: float = global_position.distance_to(collision_point)
			var collision_normal: Vector2 = raycast.get_collision_normal()

			# Track closest wall for weight calculation
			if wall_distance < closest_wall_distance:
				closest_wall_distance = wall_distance

			# Calculate avoidance based on which raycast hit
			# For better wall sliding, use collision normal when available
			if i == 7:  # Rear raycast - wall sliding mode
				# When touching wall from behind, slide along it
				avoidance += collision_normal * 0.5
			elif i <= 3:  # Left side raycasts (indices 0-3)
				# Steer right, weighted by distance
				var weight: float = 1.0 - (wall_distance / WALL_CHECK_DISTANCE)
				avoidance += perpendicular * weight
			else:  # Right side raycasts (indices 4-6)
				# Steer left, weighted by distance
				var weight: float = 1.0 - (wall_distance / WALL_CHECK_DISTANCE)
				avoidance -= perpendicular * weight

	return avoidance.normalized() if avoidance.length() > 0 else Vector2.ZERO

## Apply wall avoidance to a movement direction. Returns adjusted direction.
func _apply_wall_avoidance(direction: Vector2) -> Vector2:
	var avoidance: Vector2 = _check_wall_ahead(direction)
	if avoidance == Vector2.ZERO:
		return direction

	var weight: float = _get_wall_avoidance_weight(direction)
	# Blend original direction with avoidance, stronger avoidance when close to walls
	return (direction * (1.0 - weight) + avoidance * weight).normalized()

## Calculate wall avoidance weight based on distance to nearest wall.
func _get_wall_avoidance_weight(direction: Vector2) -> float:
	if _wall_raycasts.is_empty():
		return WALL_AVOIDANCE_MAX_WEIGHT

	var closest_distance: float = WALL_CHECK_DISTANCE

	# Check the center raycast for distance
	if _wall_raycasts.size() > 0:
		var raycast: RayCast2D = _wall_raycasts[0]
		raycast.target_position = direction * WALL_CHECK_DISTANCE
		raycast.force_raycast_update()

		if raycast.is_colliding():
			var collision_point: Vector2 = raycast.get_collision_point()
			closest_distance = global_position.distance_to(collision_point)

	# Interpolate between min and max weight based on distance
	var normalized_distance: float = clampf(closest_distance / WALL_CHECK_DISTANCE, 0.0, 1.0)
	return lerpf(WALL_AVOIDANCE_MIN_WEIGHT, WALL_AVOIDANCE_MAX_WEIGHT, normalized_distance)

## Check if target is within FOV cone. FOV uses _enemy_model.global_rotation for facing.
func _is_position_in_fov(target_pos: Vector2) -> bool:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	var global_fov_enabled: bool = experimental_settings != null and experimental_settings.has_method("is_fov_enabled") and experimental_settings.is_fov_enabled()
	if not global_fov_enabled or not fov_enabled or fov_angle <= 0.0:
		return true  # FOV disabled - 360 degree vision
	var facing_angle := _enemy_model.global_rotation if _enemy_model else rotation
	var dir_to_target := (target_pos - global_position).normalized()
	var dot := Vector2.from_angle(facing_angle).dot(dir_to_target)
	var angle_to_target := rad_to_deg(acos(clampf(dot, -1.0, 1.0)))
	var in_fov := angle_to_target <= fov_angle / 2.0
	return in_fov

## Check if the player is visible using multi-point raycast. Updates visibility timer.
func _check_player_visibility() -> void:
	var was_visible := _can_see_player
	_can_see_player = false
	_player_visibility_ratio = 0.0

	# If blinded, cannot see player at all
	if _is_blinded:
		_continuous_visibility_timer = 0.0
		return

	# If confused from memory reset, cannot see player (Issue #318)
	if _memory_reset_confusion_timer > 0.0:
		_continuous_visibility_timer = 0.0
		return

	if _player == null or not _raycast:
		_continuous_visibility_timer = 0.0
		return

	var distance_to_player := global_position.distance_to(_player.global_position)

	# Check if player is within detection range (only if detection_range is positive)
	# If detection_range <= 0, detection is unlimited (line-of-sight only)
	if detection_range > 0 and distance_to_player > detection_range:
		_continuous_visibility_timer = 0.0
		return

	# Check FOV angle (if FOV is enabled via ExperimentalSettings)
	if not _is_position_in_fov(_player.global_position):
		_continuous_visibility_timer = 0.0
		return

	# Check multiple points on the player's body (center + corners) to handle
	# cases where player is near a wall corner. A single raycast to the center
	# might hit the wall, but parts of the player's body could still be visible.
	# This fixes the issue where enemies couldn't see players standing close to
	# walls in narrow passages (issue #264).
	var check_points := _get_player_check_points(_player.global_position)
	var visible_count := 0

	for point in check_points:
		if _is_player_point_visible_to_enemy(point):
			visible_count += 1
			# If any part of the player is visible, we can see them
			_can_see_player = true
			# Continue checking to calculate visibility ratio

	# Calculate visibility ratio based on how many points are visible
	if _can_see_player:
		_player_visibility_ratio = float(visible_count) / float(check_points.size())
		_continuous_visibility_timer += get_physics_process_delta_time()
	else:
		# Lost line of sight - reset the timer and visibility ratio
		_continuous_visibility_timer = 0.0
		_player_visibility_ratio = 0.0

## Update enemy memory: visual detection, decay, and periodic intel sharing (Issue #297).
func _update_memory(delta: float) -> void:
	if _memory == null:
		return

	# Visual detection: Update memory with player position at full confidence
	if _can_see_player and _player:
		_memory.update_position(_player.global_position, VISUAL_DETECTION_CONFIDENCE)
		# Also update the legacy _last_known_player_position for compatibility
		_last_known_player_position = _player.global_position

	# Apply confidence decay over time
	_memory.decay(delta)

	# Periodic intel sharing with nearby enemies
	_intel_share_timer += delta
	if _intel_share_timer >= INTEL_SHARE_INTERVAL:
		_intel_share_timer = 0.0
		_share_intel_with_nearby_enemies()

## Share intelligence with nearby enemies within 660px (LOS) or 300px (no LOS).
func _share_intel_with_nearby_enemies() -> void:
	if _memory == null or not _memory.has_target():
		return

	var enemies := get_tree().get_nodes_in_group("enemies")
	for node in enemies:
		if node == self or not is_instance_valid(node):
			continue

		var other_enemy: Node2D = node as Node2D
		if other_enemy == null:
			continue

		var distance := global_position.distance_to(other_enemy.global_position)

		# Check if within communication range
		var can_share := false
		if distance <= INTEL_SHARE_RANGE_NO_LOS:
			# Close enough to share without LOS
			can_share = true
		elif distance <= INTEL_SHARE_RANGE_LOS:
			# Need to check LOS for longer range
			can_share = _has_line_of_sight_to_position(other_enemy.global_position)

		if can_share and other_enemy.has_method("receive_intel_from_ally"):
			other_enemy.receive_intel_from_ally(_memory)

## Receive intelligence from an allied enemy (Issue #297).
## Called by other enemies when they share intel.
func receive_intel_from_ally(ally_memory: EnemyMemory) -> void:
	if _memory == null or ally_memory == null:
		return

	# Only update if ally has better or newer information
	if _memory.receive_intel(ally_memory, INTEL_SHARE_FACTOR):
		_log_debug("Received intel from ally: suspected pos=%s, conf=%.2f" % [
			_memory.suspected_position, _memory.confidence
		])
		_last_known_player_position = _memory.suspected_position

## Reset enemy memory for last chance teleport effect (Issue #318). Preserves old position.
func reset_memory() -> void:
	# Save old position before resetting - enemies will search here
	var old_position := _memory.suspected_position if _memory != null and _memory.has_target() else Vector2.ZERO
	var had_target := old_position != Vector2.ZERO
	# Reset visibility, detection states, and apply confusion timer (blocks vision AND sounds)
	_can_see_player = false
	_continuous_visibility_timer = 0.0
	_intel_share_timer = 0.0
	_pursuing_vulnerability_sound = false
	_memory_reset_confusion_timer = MEMORY_RESET_CONFUSION_DURATION
	_log_to_file("Memory reset: confusion=%.1fs, had_target=%s" % [MEMORY_RESET_CONFUSION_DURATION, had_target])
	if had_target:
		# Set LOW confidence (0.35) - puts enemy in search mode at old position
		if _memory != null:
			_memory.suspected_position = old_position
			_memory.confidence = 0.35
			_memory.last_updated = Time.get_ticks_msec()
		_last_known_player_position = old_position
		_log_to_file("Search mode: %s -> SEARCHING at %s" % [AIState.keys()[_current_state], old_position])
		_transition_to_searching(old_position)
	else:
		if _memory != null:
			_memory.reset()
		_last_known_player_position = Vector2.ZERO
		if _current_state in [AIState.PURSUING, AIState.COMBAT, AIState.ASSAULT, AIState.FLANKING]:
			# Issue #330: If enemy has left IDLE, start searching instead of returning to IDLE
			if _has_left_idle:
				_log_to_file("State reset: %s -> SEARCHING (engaged enemy, no target)" % AIState.keys()[_current_state])
				_transition_to_searching(global_position)
			else:
				_log_to_file("State reset: %s -> IDLE (no target)" % AIState.keys()[_current_state])
				_transition_to_idle()

## Check if there is a clear line of sight to a position (enemy-to-enemy comms).
func _has_line_of_sight_to_position(target_pos: Vector2) -> bool:
	if _raycast == null:
		return false

	# Save current raycast state
	var original_target := _raycast.target_position
	var original_enabled := _raycast.enabled

	# Configure raycast to check LOS
	var direction := target_pos - global_position
	_raycast.target_position = direction
	_raycast.enabled = true
	_raycast.force_raycast_update()

	# Check if anything blocks the path
	var has_los := not _raycast.is_colliding()

	# If something is in the way, check if it's the target position or beyond
	if _raycast.is_colliding():
		var collision_point := _raycast.get_collision_point()
		var distance_to_target := global_position.distance_to(target_pos)
		var distance_to_collision := global_position.distance_to(collision_point)
		# Has LOS if collision is at or beyond target
		has_los = distance_to_collision >= distance_to_target - 10.0

	# Restore raycast state
	_raycast.target_position = original_target
	_raycast.enabled = original_enabled

	return has_los

## Aim the enemy sprite/direction at the player using gradual rotation.
func _aim_at_player() -> void:
	if _player == null:
		return
	var direction := (_player.global_position - global_position).normalized()
	var target_angle := direction.angle()

	# Calculate the shortest rotation direction
	var angle_diff := wrapf(target_angle - rotation, -PI, PI)

	# Get the delta time from the current physics process
	var delta := get_physics_process_delta_time()

	# Apply gradual rotation based on rotation_speed
	if abs(angle_diff) <= rotation_speed * delta:
		# Close enough to snap to target
		rotation = target_angle
	elif angle_diff > 0:
		rotation += rotation_speed * delta
	else:
		rotation -= rotation_speed * delta

## Shoot a bullet in barrel direction. Enemy must be aimed within AIM_TOLERANCE_DOT.
func _shoot() -> void:
	if bullet_scene == null or _player == null:
		return

	# Check if we can shoot (have ammo and not reloading)
	if not _can_shoot():
		return

	var target_position := _player.global_position

	# Apply lead prediction if enabled
	if enable_lead_prediction:
		target_position = _calculate_lead_prediction()

	# Check if the shot should be taken (friendly fire and cover checks)
	if not _should_shoot_at_target(target_position):
		return

	# Calculate bullet spawn position at weapon muzzle first
	# We need this to calculate the correct bullet direction
	var weapon_forward := _get_weapon_forward_direction()
	var bullet_spawn_pos := _get_bullet_spawn_position(weapon_forward)

	# Use enemy center (not muzzle) for aim check to fix close-range issues (Issue #344)
	var to_target := (target_position - global_position).normalized()

	# Check if weapon is aimed at target (within tolerance)
	# Bullets fly in barrel direction, so we only shoot when properly aimed (issue #254)
	var aim_dot := weapon_forward.dot(to_target)
	if aim_dot < AIM_TOLERANCE_DOT:
		if debug_logging:
			var aim_angle_deg := rad_to_deg(acos(clampf(aim_dot, -1.0, 1.0)))
			_log_debug("SHOOT BLOCKED: Not aimed at target. aim_dot=%.3f (%.1f deg off)" % [aim_dot, aim_angle_deg])
		return

	# Bullet direction is the weapon's forward direction (realistic barrel direction)
	# This ensures bullets fly where the barrel is pointing, not toward the target
	var direction := weapon_forward

	# Create bullet instance
	var bullet := bullet_scene.instantiate()
	bullet.global_position = bullet_spawn_pos

	# Debug logging for weapon geometry analysis
	if debug_logging:
		var weapon_visual_pos := _weapon_sprite.global_position if _weapon_sprite else Vector2.ZERO
		var model_rot := _enemy_model.rotation if _enemy_model else 0.0
		var model_scale := _enemy_model.scale if _enemy_model else Vector2.ONE
		_log_debug("SHOOT: enemy_pos=%v, target_pos=%v" % [global_position, target_position])
		_log_debug("  model_rotation=%.2f rad (%.1f deg), model_scale=%v" % [model_rot, rad_to_deg(model_rot), model_scale])
		_log_debug("  weapon_node_pos=%v, muzzle=%v" % [weapon_visual_pos, bullet_spawn_pos])
		_log_debug("  direction=%v (angle=%.1f deg) - BARREL DIRECTION (realistic)" % [direction, rad_to_deg(direction.angle())])

	# Set bullet direction (barrel direction for realistic behavior)
	bullet.direction = direction

	# Set shooter ID to identify this enemy as the source
	# This prevents enemies from detecting their own bullets in the threat sphere
	bullet.shooter_id = get_instance_id()
	# Set shooter position for distance-based penetration calculation
	# Use the bullet spawn position (weapon muzzle) for accurate distance calculation
	bullet.shooter_position = bullet_spawn_pos

	# Add bullet to the scene tree
	get_tree().current_scene.add_child(bullet)

	# Spawn casing if casing scene is set
	_spawn_casing(direction, weapon_forward)

	# Play shooting sound
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_m16_shot"):
		audio_manager.play_m16_shot(global_position)

	# Emit gunshot sound for in-game sound propagation (alerts other enemies)
	# Uses weapon_loudness to determine propagation range
	var sound_propagation: Node = get_node_or_null("/root/SoundPropagation")
	if sound_propagation and sound_propagation.has_method("emit_sound"):
		sound_propagation.emit_sound(0, global_position, 1, self, weapon_loudness)  # 0 = GUNSHOT, 1 = ENEMY

	# Play shell casing sound with a small delay
	_play_delayed_shell_sound()

	# Consume ammo
	_current_ammo -= 1
	ammo_changed.emit(_current_ammo, _reserve_ammo)

	# Auto-reload when magazine is empty
	if _current_ammo <= 0 and _reserve_ammo > 0:
		_start_reload()

## Play shell casing sound with a delay to simulate the casing hitting the ground.
func _play_delayed_shell_sound() -> void:
	await get_tree().create_timer(0.15).timeout
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_shell_rifle"):
		audio_manager.play_shell_rifle(global_position)

## Spawn bullet casing (based on BaseWeapon.cs for visual consistency with player).
func _spawn_casing(shoot_direction: Vector2, weapon_forward: Vector2) -> void:
	if casing_scene == null:
		return

	# Calculate casing spawn position (near the weapon, slightly offset)
	# Use 50% of bullet spawn offset to position casing near weapon muzzle
	var casing_spawn_position: Vector2 = global_position + weapon_forward * (bullet_spawn_offset * 0.5)

	var casing: RigidBody2D = casing_scene.instantiate()
	casing.global_position = casing_spawn_position

	# Calculate ejection direction to the right of the weapon
	# In a top-down view with Y increasing downward:
	# - If weapon points right (1, 0), right side of weapon is DOWN (0, 1)
	# - If weapon points up (0, -1), right side of weapon is RIGHT (1, 0)
	# This is a 90 degree counter-clockwise rotation (perpendicular to shooting direction)
	var weapon_right: Vector2 = Vector2(-weapon_forward.y, weapon_forward.x)

	# Eject to the right with some randomness
	var random_angle: float = randf_range(-0.3, 0.3)  # ±0.3 radians (~±17 degrees)
	var ejection_direction: Vector2 = weapon_right.rotated(random_angle)

	# Add some upward component for realistic ejection
	ejection_direction = ejection_direction.rotated(randf_range(-0.1, 0.1))

	# Set initial velocity for the casing (increased for faster ejection animation)
	var ejection_speed: float = randf_range(300.0, 450.0)  # Random speed between 300-450 pixels/sec
	casing.linear_velocity = ejection_direction * ejection_speed

	# Add some initial spin for realism
	casing.angular_velocity = randf_range(-15.0, 15.0)

	# Set caliber data on the casing for appearance
	# Load the 5.45x39mm caliber data for M16 rifle
	var caliber_data: Resource = load("res://resources/calibers/caliber_545x39.tres")
	if caliber_data:
		casing.set("caliber_data", caliber_data)

	get_tree().current_scene.add_child(casing)

## Calculate lead prediction - aims where the player will be based on velocity.
func _calculate_lead_prediction() -> Vector2:
	if _player == null:
		return global_position

	var player_pos := _player.global_position

	# Only use lead prediction if the player has been continuously visible
	# for long enough. This prevents enemies from predicting player position
	# immediately when they emerge from cover.
	if _continuous_visibility_timer < lead_prediction_delay:
		_log_debug("Lead prediction disabled: visibility time %.2fs < %.2fs required" % [_continuous_visibility_timer, lead_prediction_delay])
		return player_pos

	# Only use lead prediction if enough of the player's body is visible.
	# This prevents pre-firing when the player is at the edge of cover with only
	# a small part of their body visible. The player must be significantly exposed
	# before the enemy can predict their movement.
	if _player_visibility_ratio < lead_prediction_visibility_threshold:
		_log_debug("Lead prediction disabled: visibility ratio %.2f < %.2f required (player at cover edge)" % [_player_visibility_ratio, lead_prediction_visibility_threshold])
		return player_pos

	var player_velocity := Vector2.ZERO

	# Get player velocity if they are a CharacterBody2D
	if _player is CharacterBody2D:
		player_velocity = _player.velocity

	# If player is stationary, no need for prediction
	if player_velocity.length_squared() < 1.0:
		return player_pos

	# Iterative lead prediction for better accuracy
	# Start with player's current position
	var predicted_pos := player_pos
	var distance := global_position.distance_to(predicted_pos)

	# Iterate 2-3 times for convergence
	for i in range(3):
		# Time for bullet to reach the predicted position
		var time_to_target := distance / bullet_speed

		# Predict where player will be at that time
		predicted_pos = player_pos + player_velocity * time_to_target

		# Update distance for next iteration
		distance = global_position.distance_to(predicted_pos)

	# CRITICAL: Validate that the predicted position is actually visible to the enemy.
	# If the predicted position is behind cover (e.g., player is running toward cover exit),
	# we should NOT aim there - it would feel like the enemy is "cheating" by knowing
	# where the player will emerge. Fall back to player's current visible position.
	if not _is_position_visible_to_enemy(predicted_pos):
		_log_debug("Lead prediction blocked: predicted position %s is not visible, using current position %s" % [predicted_pos, player_pos])
		return player_pos

	_log_debug("Lead prediction: player at %s moving %s, aiming at %s" % [player_pos, player_velocity, predicted_pos])

	return predicted_pos

## Process patrol behavior - move between patrol points with corner checking.
func _process_patrol(delta: float) -> void:
	if _patrol_points.is_empty():
		return

	# Handle waiting at patrol point
	if _is_waiting_at_patrol_point:
		_patrol_wait_timer += delta
		if _patrol_wait_timer >= patrol_wait_time:
			_is_waiting_at_patrol_point = false
			_patrol_wait_timer = 0.0
			_current_patrol_index = (_current_patrol_index + 1) % _patrol_points.size()
		velocity = Vector2.ZERO
		return

	# Move towards current patrol point
	var target_point := _patrol_points[_current_patrol_index]
	var direction := (target_point - global_position).normalized()
	var distance := global_position.distance_to(target_point)

	if distance < 5.0:
		_is_waiting_at_patrol_point = true
		velocity = Vector2.ZERO
	else:
		direction = _apply_wall_avoidance(direction)
		velocity = direction * move_speed
		rotation = direction.angle()
		# Check for corners/openings perpendicular to movement direction
		_process_corner_check(get_physics_process_delta_time(), direction, "PATROL")

## Detect openings perpendicular to movement (for corner checking). Issue #347: smooth rotation.
func _detect_perpendicular_opening(move_dir: Vector2) -> bool:
	var space_state := get_world_2d().direct_space_state
	for side in [-1.0, 1.0]:
		var perp_dir := move_dir.rotated(side * PI / 2)
		var query := PhysicsRayQueryParameters2D.create(global_position, global_position + perp_dir * CORNER_CHECK_DISTANCE)
		query.collision_mask = 0b100
		query.exclude = [self]
		if space_state.intersect_ray(query).is_empty():
			_corner_check_angle = perp_dir.angle()  # Issue #347: smooth rotation via _update_enemy_model_rotation()
			return true
	return false

## Handle corner checking during movement (Issue #332). Issue #347: smooth rotation.
func _process_corner_check(delta: float, move_dir: Vector2, state_name: String) -> void:
	if _corner_check_timer > 0:
		_corner_check_timer -= delta  # #347: rotation via _update_enemy_model_rotation()
	elif _detect_perpendicular_opening(move_dir):
		_corner_check_timer = CORNER_CHECK_DURATION
		_log_to_file("%s corner check: angle %.1f°" % [state_name, rad_to_deg(_corner_check_angle)])

## Process guard behavior - scan for threats every IDLE_SCAN_INTERVAL seconds.
func _process_guard(delta: float) -> void:
	velocity = Vector2.ZERO
	if _idle_scan_targets.is_empty():
		_initialize_idle_scan_targets()
	_idle_scan_timer += delta
	if _idle_scan_timer >= IDLE_SCAN_INTERVAL:
		_idle_scan_timer = 0.0
		if _idle_scan_targets.size() > 0:
			_idle_scan_target_index = (_idle_scan_target_index + 1) % _idle_scan_targets.size()

## Initialize scan targets - detects passages using raycasts.
func _initialize_idle_scan_targets() -> void:
	_idle_scan_targets.clear()
	var space_state := get_world_2d().direct_space_state
	var opening_angles: Array[float] = []
	for i in range(16):
		var angle := (float(i) / 16.0) * TAU
		var query := PhysicsRayQueryParameters2D.create(global_position, global_position + Vector2.from_angle(angle) * 500.0)
		query.collision_mask = 0b100
		query.exclude = [self]
		var result := space_state.intersect_ray(query)
		if result.is_empty() or global_position.distance_to(result.position) > 200.0:
			opening_angles.append(angle)
	if opening_angles.size() > 0:
		var clusters: Array[Array] = []
		opening_angles.sort()
		for angle in opening_angles:
			var found := false
			for cluster in clusters:
				var avg: float = 0.0
				for a in cluster: avg += a
				avg /= cluster.size()
				if abs(wrapf(angle - avg, -PI, PI)) < deg_to_rad(30.0):
					cluster.append(angle)
					found = true
					break
			if not found: clusters.append([angle])
		for cluster in clusters:
			var avg: float = 0.0
			for a in cluster: avg += a
			_idle_scan_targets.append(avg / cluster.size())
	if _idle_scan_targets.size() < 2:
		_idle_scan_targets = [0.0, PI]
	_idle_scan_target_index = randi() % _idle_scan_targets.size()

## Called when a bullet enters the threat sphere.
func _on_threat_area_entered(area: Area2D) -> void:
	if "shooter_id" in area and area.shooter_id == get_instance_id():
		return
	_bullets_in_threat_sphere.append(area)
	_threat_memory_timer = THREAT_MEMORY_DURATION
	_log_debug("Bullet entered threat sphere, starting reaction delay...")

## Called when a bullet exits the threat sphere.
func _on_threat_area_exited(area: Area2D) -> void:
	_bullets_in_threat_sphere.erase(area)

## Called when the enemy is hit (by bullet.gd).
func on_hit() -> void:
	on_hit_with_info(Vector2.RIGHT, null)

## Called when the enemy is hit with extended hit information.
func on_hit_with_info(hit_direction: Vector2, caliber_data: Resource) -> void:
	on_hit_with_bullet_info(hit_direction, caliber_data, false, false)

## Called when the enemy is hit with full bullet information.
func on_hit_with_bullet_info(hit_direction: Vector2, caliber_data: Resource, has_ricocheted: bool, has_penetrated: bool) -> void:
	if not _is_alive:
		return

	hit.emit()

	# Store hit direction for death animation
	_last_hit_direction = hit_direction

	# Turn toward attacker: the attacker is in the opposite direction of the bullet travel
	# This makes the enemy face where the shot came from
	var attacker_direction := -hit_direction.normalized()
	if attacker_direction.length_squared() > 0.01:
		_force_model_to_face_direction(attacker_direction)
		_log_debug("Hit reaction: turning toward attacker (direction: %s)" % attacker_direction)

	# Track hits for retreat behavior
	_hits_taken_in_encounter += 1
	_log_debug("Hit taken! Total hits in encounter: %d" % _hits_taken_in_encounter)
	_log_to_file("Hit taken, health: %d/%d" % [_current_health - 1, _max_health])

	# Show hit flash effect
	_show_hit_flash()

	# Apply damage
	_current_health -= 1

	# Play appropriate hit sound and spawn visual effects
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	var impact_manager: Node = get_node_or_null("/root/ImpactEffectsManager")

	# Log blood effect call for diagnostics
	if impact_manager:
		_log_to_file("ImpactEffectsManager found, calling spawn_blood_effect")
	else:
		_log_to_file("WARNING: ImpactEffectsManager not found at /root/ImpactEffectsManager")
		# Debug: List all autoload children of /root for diagnostics
		var root_node := get_node_or_null("/root")
		if root_node:
			var autoload_names: Array = []
			for child in root_node.get_children():
				if child.name != get_tree().current_scene.name if get_tree().current_scene else true:
					autoload_names.append(child.name)
			_log_to_file("Available autoloads: " + ", ".join(autoload_names))

	if _current_health <= 0:
		# Track special kill info before death
		_killed_by_ricochet = has_ricocheted
		_killed_by_penetration = has_penetrated

		# Play lethal hit sound
		if audio_manager and audio_manager.has_method("play_hit_lethal"):
			audio_manager.play_hit_lethal(global_position)
		# Spawn blood splatter effect for lethal hit (with decal)
		if impact_manager and impact_manager.has_method("spawn_blood_effect"):
			impact_manager.spawn_blood_effect(global_position, hit_direction, caliber_data, true)
		_on_death()
	else:
		# Play non-lethal hit sound
		if audio_manager and audio_manager.has_method("play_hit_non_lethal"):
			audio_manager.play_hit_non_lethal(global_position)
		# Spawn blood effect for non-lethal hit (smaller, no decal)
		if impact_manager and impact_manager.has_method("spawn_blood_effect"):
			impact_manager.spawn_blood_effect(global_position, hit_direction, caliber_data, false)
		_update_health_visual()

## Shows a brief flash effect when hit.
func _show_hit_flash() -> void:
	if not _enemy_model:
		return

	_set_all_sprites_modulate(hit_flash_color)

	await get_tree().create_timer(hit_flash_duration).timeout

	# Restore color based on current health (if still alive)
	if _is_alive:
		_update_health_visual()

## Updates the sprite color based on current health percentage.
func _update_health_visual() -> void:
	# Interpolate color based on health percentage
	var health_percent := _get_health_percent()
	var color := full_health_color.lerp(low_health_color, 1.0 - health_percent)
	_set_all_sprites_modulate(color)

## Sets the modulate color on all enemy sprite parts.
func _set_all_sprites_modulate(color: Color) -> void:
	if _body_sprite:
		_body_sprite.modulate = color
	if _head_sprite:
		_head_sprite.modulate = color
	if _left_arm_sprite:
		_left_arm_sprite.modulate = color
	if _right_arm_sprite:
		_right_arm_sprite.modulate = color

## Returns the current health as a percentage (0.0 to 1.0).
func _get_health_percent() -> float:
	if _max_health <= 0:
		return 0.0
	return float(_current_health) / float(_max_health)

## Calculates the bullet spawn position at the weapon's muzzle.
## The muzzle is positioned relative to the weapon mount, offset in the weapon's forward direction.
##
## IMPORTANT FIX (Issue #264 - Session 4):
## Similar to _get_weapon_forward_direction(), we need to calculate the muzzle position
## based on the intended aim direction when the player is visible, not from the stale
## global_transform which may not have updated yet in the same physics frame.
##
## @param _direction: The normalized direction the bullet will travel (used for fallback only).
## @return: The global position where the bullet should spawn.
func _get_bullet_spawn_position(_direction: Vector2) -> Vector2:
	# The rifle sprite (m16_rifle_topdown.png) is 64px long with offset (20, 0).
	# The muzzle (right edge in local space) is at: offset.x + sprite_width/2 = 20 + 32 = 52px
	# from the WeaponSprite node position.
	var muzzle_local_offset := 52.0  # Distance from node to muzzle in local +X direction
	if _weapon_sprite and _enemy_model:
		var weapon_forward: Vector2

		# When player is visible, calculate direction directly to avoid transform delay.
		# This matches the fix in _get_weapon_forward_direction().
		if _player and is_instance_valid(_player) and _can_see_player:
			weapon_forward = (_player.global_position - global_position).normalized()
		else:
			# Fallback to transform-based direction when player is not visible.
			# Get the weapon's VISUAL forward direction from global_transform.
			# IMPORTANT: We use global_transform.x because it correctly accounts for the
			# vertical flip (scale.y negative) that happens when aiming left. The flip
			# affects where the muzzle visually appears, so we need the transformed direction.
			# Using Vector2.from_angle(_enemy_model.rotation) would give incorrect results
			# because it doesn't account for the scale flip.
			weapon_forward = _weapon_sprite.global_transform.x.normalized()

		# Calculate muzzle offset accounting for enemy model scale
		var scaled_muzzle_offset := muzzle_local_offset * enemy_model_scale
		# Use weapon sprite's global position as base, then offset to reach the muzzle
		var result := _weapon_sprite.global_position + weapon_forward * scaled_muzzle_offset
		if debug_logging:
			var angle_forward := Vector2.from_angle(_enemy_model.rotation)
			_log_debug("  _get_bullet_spawn_position: weapon_forward=%v vs angle_forward=%v" % [weapon_forward, angle_forward])
			_log_debug("  muzzle_position=%v, weapon_pos=%v, offset=%.1f" % [result, _weapon_sprite.global_position, scaled_muzzle_offset])
		return result
	else:
		# Fallback to old behavior if weapon sprite or enemy model not found
		return global_position + _direction * bullet_spawn_offset

## Returns the weapon's forward direction (normalized). Uses direct calculation to player
## when visible to avoid transform delay (Issue #264).
func _get_weapon_forward_direction() -> Vector2:
	# When we can see the player, calculate direction directly to avoid transform delay.
	# This is the same calculation used in _update_enemy_model_rotation(), ensuring
	# consistency between the visual aim and the actual bullet direction.
	if _player and is_instance_valid(_player) and _can_see_player:
		return (_player.global_position - global_position).normalized()

	# Fallback to transform-based direction when player is not visible.
	# In this case, the transform should have had time to update across frames.
	if _weapon_sprite:
		# Use the weapon sprite's global_transform.x for the true visual forward direction.
		# This correctly handles the vertical flip case (scale.y negative) because
		# global_transform includes all parent transforms including scale.
		return _weapon_sprite.global_transform.x.normalized()
	elif _enemy_model:
		# Fallback to enemy model's transform if weapon sprite not available
		return _enemy_model.global_transform.x.normalized()
	else:
		# Fallback: calculate direction to player
		if _player and is_instance_valid(_player):
			return (_player.global_position - global_position).normalized()
		return Vector2.RIGHT  # Default fallback

## Updates the weapon sprite rotation to match shooting direction with vertical flip handling.
func _update_weapon_sprite_rotation() -> void:
	if not _weapon_sprite:
		return

	# Calculate the direction the weapon should point (same as shooting direction)
	# This matches the logic in _shoot() to ensure visual consistency
	var aim_angle: float = rotation  # Default to body rotation

	if _player and is_instance_valid(_player):
		# Calculate direction to player (or predicted position if lead prediction is enabled)
		var target_position := _player.global_position
		if enable_lead_prediction and _can_see_player:
			target_position = _calculate_lead_prediction()

		var direction := (target_position - global_position).normalized()
		aim_angle = direction.angle()

	# Set the weapon sprite LOCAL rotation relative to parent.
	# The weapon sprite is a child of the enemy body, so we need to subtract the parent's
	# rotation to get the correct world-space orientation.
	# Without this, the rotation would be doubled (parent rotation + own rotation).
	_weapon_sprite.rotation = aim_angle - rotation

	# Flip the sprite vertically when aiming left (to avoid upside-down rifle)
	# This happens when the angle is greater than 90 degrees or less than -90 degrees
	var aiming_left := absf(aim_angle) > PI / 2.0
	_weapon_sprite.flip_v = aiming_left

## Returns the effective detection delay based on difficulty setting.
func _get_effective_detection_delay() -> float:
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager and difficulty_manager.has_method("get_detection_delay"):
		return difficulty_manager.get_detection_delay()
	# Fall back to export variable if DifficultyManager is not available
	return detection_delay

## Called when the enemy dies.
func _on_death() -> void:
	_is_alive = false
	_log_to_file("Enemy died (ricochet: %s, penetration: %s)" % [_killed_by_ricochet, _killed_by_penetration])
	died.emit()
	died_with_info.emit(_killed_by_ricochet, _killed_by_penetration)

	# Disable hit area collision so bullets pass through dead enemies
	_disable_hit_area_collision()

	# Unregister from sound propagation when dying
	_unregister_sound_listener()

	# Start death animation with the hit direction
	if _death_animation and _death_animation.has_method("start_death_animation"):
		_death_animation.start_death_animation(_last_hit_direction)
		_log_to_file("Death animation started with hit direction: %s" % str(_last_hit_direction))

	if destroy_on_death:
		# Wait for death animation to complete before destroying
		await get_tree().create_timer(respawn_delay).timeout
		# Clean up death animation ragdoll bodies before destroying
		if _death_animation and _death_animation.has_method("reset"):
			_death_animation.reset()
		queue_free()
	else:
		await get_tree().create_timer(respawn_delay).timeout
		_reset()

## Resets the enemy to its initial state.
func _reset() -> void:
	# Reset death animation first (restores sprites to character model)
	if _death_animation and _death_animation.has_method("reset"):
		_death_animation.reset()

	global_position = _initial_position
	rotation = 0.0
	_current_patrol_index = 0
	_is_waiting_at_patrol_point = false
	_patrol_wait_timer = 0.0
	_current_state = AIState.IDLE
	_has_valid_cover = false
	_under_fire = false
	_suppression_timer = 0.0
	_detection_timer = 0.0
	_detection_delay_elapsed = false
	_continuous_visibility_timer = 0.0
	_player_visibility_ratio = 0.0
	_threat_reaction_timer = 0.0
	_threat_reaction_delay_elapsed = false
	_threat_memory_timer = 0.0
	_bullets_in_threat_sphere.clear()
	# Reset retreat state variables
	_hits_taken_in_encounter = 0
	_retreat_mode = RetreatMode.FULL_HP
	_retreat_turn_timer = 0.0
	_retreat_turning_to_cover = false
	_retreat_burst_remaining = 0
	_retreat_burst_timer = 0.0
	_retreat_burst_complete = false
	_retreat_burst_angle_offset = 0.0
	_in_alarm_mode = false
	_cover_burst_pending = false
	# Reset combat state variables
	_combat_shoot_timer = 0.0
	_combat_shoot_duration = 2.5
	_combat_exposed = false
	_combat_approaching = false
	_combat_approach_timer = 0.0
	_combat_state_timer = 0.0
	# Reset pursuit state variables
	_pursuit_cover_wait_timer = 0.0
	_pursuit_next_cover = Vector2.ZERO
	_has_pursuit_cover = false
	_current_cover_obstacle = null
	_pursuit_approaching = false
	_pursuit_approach_timer = 0.0
	_pursuing_state_timer = 0.0
	# Reset global stuck detection (Issue #367)
	_global_stuck_timer = 0.0
	_global_stuck_last_position = Vector2.ZERO
	# Reset assault state variables
	_assault_wait_timer = 0.0
	_assault_ready = false
	_in_assault = false
	# Reset flank state variables
	_flank_cover_wait_timer = 0.0
	_flank_next_cover = Vector2.ZERO
	_has_flank_cover = false
	_flank_state_timer = 0.0
	_flank_stuck_timer = 0.0
	_flank_last_position = Vector2.ZERO
	_flank_fail_count = 0
	_flank_cooldown_timer = 0.0
	# Reset sound detection state
	_last_known_player_position = Vector2.ZERO
	_pursuing_vulnerability_sound = false
	# Reset score tracking state
	_killed_by_ricochet = false
	_killed_by_penetration = false
	_initialize_health()
	_initialize_ammo()
	_update_health_visual()
	_initialize_goap_state()
	# Re-enable hit area collision after respawning
	_enable_hit_area_collision()
	# Re-register for sound propagation after respawning
	_register_sound_listener()

## Disables hit area collision so bullets pass through dead enemies.
## Uses multiple approaches due to Godot engine limitations with Area2D collision toggling.
func _disable_hit_area_collision() -> void:
	# Approach 1: Disable the CollisionShape2D itself
	# This is the most reliable way to prevent collision detection
	if _hit_collision_shape:
		_hit_collision_shape.set_deferred("disabled", true)

	# Approach 2: Move to unused collision layers
	# This prevents any interaction even if shape disabling fails
	if _hit_area:
		_hit_area.set_deferred("collision_layer", 0)
		_hit_area.set_deferred("collision_mask", 0)

	# Approach 3: Disable monitorable/monitoring (original approach)
	# Kept as additional safety measure
	if _hit_area:
		_hit_area.set_deferred("monitorable", false)
		_hit_area.set_deferred("monitoring", false)

## Re-enables hit area collision after respawning.
## Restores all collision properties to their original values.
func _enable_hit_area_collision() -> void:
	# Re-enable CollisionShape2D
	if _hit_collision_shape:
		_hit_collision_shape.disabled = false

	# Restore original collision layers
	if _hit_area:
		_hit_area.collision_layer = _original_hit_area_layer
		_hit_area.collision_mask = _original_hit_area_mask

	# Re-enable monitorable/monitoring
	if _hit_area:
		_hit_area.monitorable = true
		_hit_area.monitoring = true

## Returns whether this enemy is currently alive.
## Used by bullets to check if they should pass through or hit.
func is_alive() -> bool:
	return _is_alive

## Initialize the death animation component.
func _init_death_animation() -> void:
	# Create death animation component as a child node
	_death_animation = DeathAnimationComponent.new()
	_death_animation.name = "DeathAnimation"
	add_child(_death_animation)

	# Initialize with sprite references
	_death_animation.initialize(
		_body_sprite,
		_head_sprite,
		_left_arm_sprite,
		_right_arm_sprite,
		_enemy_model
	)

	# Connect signals
	_death_animation.death_animation_completed.connect(_on_death_animation_completed)
	_death_animation.ragdoll_activated.connect(_on_ragdoll_activated)

	_log_to_file("Death animation component initialized")

## Called when death animation completes (body at rest).
func _on_death_animation_completed() -> void:
	_log_to_file("Death animation completed")
	death_animation_completed.emit()

## Called when ragdoll physics activates.
func _on_ragdoll_activated() -> void:
	_log_to_file("Ragdoll activated")

## Log debug message if debug_logging is enabled.
func _log_debug(message: String) -> void:
	if debug_logging:
		print("[Enemy %s] %s" % [name, message])

## Log a message to the file logger (always logs, regardless of debug_logging setting).
## Use for important events like spawning, dying, or critical state changes.
func _log_to_file(message: String) -> void:
	if not is_inside_tree():
		return
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_enemy"):
		file_logger.log_enemy(name, message)

## Log spawn info (called via call_deferred to ensure FileLogger is loaded).
func _log_spawn_info() -> void:
	_log_to_file("Enemy spawned at %s, health: %d, behavior: %s, player_found: %s" % [
		global_position, _max_health, BehaviorMode.keys()[behavior_mode],
		"yes" if _player != null else "no"])

## Get AI state name as a human-readable string.
func _get_state_name(state: AIState) -> String:
	match state:
		AIState.IDLE:
			return "IDLE"
		AIState.COMBAT:
			return "COMBAT"
		AIState.SEEKING_COVER:
			return "SEEKING_COVER"
		AIState.IN_COVER:
			return "IN_COVER"
		AIState.FLANKING:
			return "FLANKING"
		AIState.SUPPRESSED:
			return "SUPPRESSED"
		AIState.RETREATING:
			return "RETREATING"
		AIState.PURSUING:
			return "PURSUING"
		AIState.ASSAULT:
			return "ASSAULT"
		AIState.SEARCHING:
			return "SEARCHING"
		_:
			return "UNKNOWN"

## Update the debug label with current AI state.
func _update_debug_label() -> void:
	if _debug_label == null:
		return

	_debug_label.visible = debug_label_enabled
	if not debug_label_enabled:
		return

	var state_text := _get_state_name(_current_state)

	# Add retreat mode info if retreating
	if _current_state == AIState.RETREATING:
		match _retreat_mode:
			RetreatMode.FULL_HP:
				state_text += "\n(FULL_HP)"
			RetreatMode.ONE_HIT:
				state_text += "\n(ONE_HIT)"
			RetreatMode.MULTIPLE_HITS:
				state_text += "\n(MULTI_HITS)"

	# Add assault timer info if in assault state
	if _current_state == AIState.ASSAULT:
		if _assault_ready:
			state_text += "\n(RUSHING)"
		else:
			var time_left := ASSAULT_WAIT_DURATION - _assault_wait_timer
			state_text += "\n(%.1fs)" % time_left

	# Add combat phase info if in combat
	if _current_state == AIState.COMBAT:
		if _combat_exposed:
			var time_left := _combat_shoot_duration - _combat_shoot_timer
			state_text += "\n(EXPOSED %.1fs)" % time_left
		elif _seeking_clear_shot:
			var time_left := CLEAR_SHOT_MAX_TIME - _clear_shot_timer
			state_text += "\n(SEEK SHOT %.1fs)" % time_left
		elif _combat_approaching:
			state_text += "\n(APPROACH)"

	# Add pursuit timer info if pursuing and waiting at cover
	if _current_state == AIState.PURSUING:
		if _pursuit_approaching:
			var time_left := PURSUIT_APPROACH_MAX_TIME - _pursuit_approach_timer
			state_text += "\n(APPROACH %.1fs)" % time_left
		elif _has_valid_cover and not _has_pursuit_cover:
			var time_left := PURSUIT_COVER_WAIT_DURATION - _pursuit_cover_wait_timer
			state_text += "\n(WAIT %.1fs)" % time_left
		elif _has_pursuit_cover:
			state_text += "\n(MOVING)"

	# Add flanking phase info if flanking
	if _current_state == AIState.FLANKING:
		var side_label := "R" if _flank_side > 0 else "L"
		if _has_valid_cover and not _has_flank_cover:
			var time_left := FLANK_COVER_WAIT_DURATION - _flank_cover_wait_timer
			state_text += "\n(%s WAIT %.1fs)" % [side_label, time_left]
		elif _has_flank_cover:
			state_text += "\n(%s MOVING)" % side_label
		else:
			state_text += "\n(%s DIRECT)" % side_label

	# Add memory confidence info (Issue #297)
	if _memory and _memory.has_target():
		var mode := _memory.get_behavior_mode()
		state_text += "\n[%.0f%% %s]" % [_memory.confidence * 100, mode.substr(0, 6)]

	_debug_label.text = state_text

## Get current AI state (for external access/debugging).
func get_current_state() -> AIState:
	return _current_state

## Get GOAP world state (for GOAP planner).
func get_goap_world_state() -> Dictionary:
	return _goap_world_state.duplicate()

## Set player reloading state. Called by level when player starts/finishes reload.
## When player starts reloading near an enemy, the enemy will attack with maximum priority.
func set_player_reloading(is_reloading: bool) -> void:
	var old_value: bool = _goap_world_state.get("player_reloading", false)
	_goap_world_state["player_reloading"] = is_reloading
	if is_reloading != old_value:
		_log_to_file("Player reloading state changed: %s -> %s" % [old_value, is_reloading])

## Set player ammo empty state. Called by level when player tries to shoot with empty weapon.
## When player tries to shoot with no ammo, the enemy will attack with maximum priority.
func set_player_ammo_empty(is_empty: bool) -> void:
	var old_value: bool = _goap_world_state.get("player_ammo_empty", false)
	_goap_world_state["player_ammo_empty"] = is_empty
	if is_empty != old_value:
		_log_to_file("Player ammo empty state changed: %s -> %s" % [old_value, is_empty])

## Check if enemy is currently under fire.
func is_under_fire() -> bool:
	return _under_fire

## Check if enemy is in cover.
func is_in_cover() -> bool:
	return _current_state == AIState.IN_COVER or _current_state == AIState.SUPPRESSED

## Get current ammo in magazine.
func get_current_ammo() -> int:
	return _current_ammo

## Get reserve ammo.
func get_reserve_ammo() -> int:
	return _reserve_ammo

## Get total ammo (current + reserve).
func get_total_ammo() -> int:
	return _current_ammo + _reserve_ammo

## Check if enemy is currently reloading.
func is_reloading() -> bool:
	return _is_reloading

## Check if enemy has any ammo left.
func has_ammo() -> bool:
	return _current_ammo > 0 or _reserve_ammo > 0

## Get current player visibility ratio (for debugging).
## Returns 0.0 if player is completely hidden, 1.0 if fully visible.
func get_player_visibility_ratio() -> float:
	return _player_visibility_ratio

## Draw debug visualization when debug mode is enabled.
## Shows: line to target (cover, clear shot, player), bullet spawn point status.
func _draw() -> void:
	if not debug_label_enabled:
		return

	# Colors for different debug elements
	var color_to_cover := Color.CYAN  # Line to cover position
	var color_to_player := Color.RED  # Line to player (when visible)
	var color_clear_shot := Color.YELLOW  # Line to clear shot target
	var color_pursuit := Color.ORANGE  # Line to pursuit cover
	var color_flank := Color.MAGENTA  # Line to flank position
	var color_bullet_spawn := Color.GREEN  # Bullet spawn point indicator
	var color_blocked := Color.RED  # Blocked path indicator

	# Draw FOV cone in debug mode - always visible to show FOV configuration
	# Color indicates whether FOV is actually active (green) or just visualization (gray)
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	var global_fov_enabled := false
	if experimental_settings and experimental_settings.has_method("is_fov_enabled"):
		global_fov_enabled = experimental_settings.is_fov_enabled()

	# Determine if FOV is actually active for this enemy
	var fov_active := global_fov_enabled and fov_enabled and fov_angle > 0.0

	# Choose color based on whether FOV is active
	# Green = FOV is active (100 degree vision)
	# Gray = FOV is disabled (360 degree vision, but showing what the cone would be)
	var color_fov: Color
	var color_fov_edge: Color
	if fov_active:
		color_fov = Color(0.2, 0.8, 0.2, 0.3)  # Semi-transparent green (active)
		color_fov_edge = Color(0.2, 0.8, 0.2, 0.8)  # Bright green edge (active)
	else:
		color_fov = Color(0.5, 0.5, 0.5, 0.2)  # Semi-transparent gray (inactive)
		color_fov_edge = Color(0.5, 0.5, 0.5, 0.5)  # Gray edge (inactive)

	# Always draw FOV cone in debug mode (if fov_angle is set)
	if fov_angle > 0.0:
		_draw_fov_cone(color_fov, color_fov_edge)

	# Draw line to player if visible
	if _can_see_player and _player:
		var to_player := _player.global_position - global_position
		draw_line(Vector2.ZERO, to_player, color_to_player, 1.5)

		# Draw bullet spawn point (actual muzzle position) and check if blocked
		var weapon_forward := _get_weapon_forward_direction()
		var muzzle_global := _get_bullet_spawn_position(weapon_forward)
		var spawn_point := muzzle_global - global_position  # Convert to local coordinates for draw
		if _is_bullet_spawn_clear(weapon_forward):
			draw_circle(spawn_point, 5.0, color_bullet_spawn)
		else:
			# Draw X for blocked spawn point
			draw_line(spawn_point + Vector2(-5, -5), spawn_point + Vector2(5, 5), color_blocked, 2.0)
			draw_line(spawn_point + Vector2(-5, 5), spawn_point + Vector2(5, -5), color_blocked, 2.0)

	# Draw line to cover position if we have one
	if _has_valid_cover:
		var to_cover := _cover_position - global_position
		draw_line(Vector2.ZERO, to_cover, color_to_cover, 1.5)
		# Draw small circle at cover position
		draw_circle(to_cover, 8.0, color_to_cover)

	# Draw line to clear shot target if seeking clear shot
	if _seeking_clear_shot and _clear_shot_target != Vector2.ZERO:
		var to_target := _clear_shot_target - global_position
		draw_line(Vector2.ZERO, to_target, color_clear_shot, 2.0)
		# Draw triangle at target position
		var target_pos := to_target
		draw_line(target_pos + Vector2(-6, 6), target_pos + Vector2(6, 6), color_clear_shot, 2.0)
		draw_line(target_pos + Vector2(6, 6), target_pos + Vector2(0, -8), color_clear_shot, 2.0)
		draw_line(target_pos + Vector2(0, -8), target_pos + Vector2(-6, 6), color_clear_shot, 2.0)

	# Draw line to pursuit cover if pursuing
	if _current_state == AIState.PURSUING and _has_pursuit_cover:
		var to_pursuit := _pursuit_next_cover - global_position
		draw_line(Vector2.ZERO, to_pursuit, color_pursuit, 2.0)
		draw_circle(to_pursuit, 8.0, color_pursuit)

	# Draw line to flank target if flanking
	if _current_state == AIState.FLANKING:
		if _has_flank_cover:
			var to_flank_cover := _flank_next_cover - global_position
			draw_line(Vector2.ZERO, to_flank_cover, color_flank, 2.0)
			draw_circle(to_flank_cover, 8.0, color_flank)
		elif _flank_target != Vector2.ZERO:
			var to_flank := _flank_target - global_position
			draw_line(Vector2.ZERO, to_flank, color_flank, 1.5)
			# Draw diamond at flank target
			var flank_pos := to_flank
			draw_line(flank_pos + Vector2(0, -8), flank_pos + Vector2(8, 0), color_flank, 2.0)
			draw_line(flank_pos + Vector2(8, 0), flank_pos + Vector2(0, 8), color_flank, 2.0)
			draw_line(flank_pos + Vector2(0, 8), flank_pos + Vector2(-8, 0), color_flank, 2.0)
			draw_line(flank_pos + Vector2(-8, 0), flank_pos + Vector2(0, -8), color_flank, 2.0)

	# Draw suspected position from memory system (Issue #297)
	# The circle radius is inversely proportional to confidence (larger = less certain)
	if _memory and _memory.has_target():
		var to_suspected := _memory.suspected_position - global_position
		# Color varies from yellow (low confidence) to orange (high confidence)
		var confidence_color := Color.YELLOW.lerp(Color.ORANGE_RED, _memory.confidence)
		# Draw dashed line to suspected position
		draw_line(Vector2.ZERO, to_suspected, confidence_color, 1.0)
		# Draw uncertainty circle - radius is inversely proportional to confidence
		# At confidence 1.0: radius = 10px (certain)
		# At confidence 0.1: radius = 100px (uncertain)
		var uncertainty_radius := 10.0 + (1.0 - _memory.confidence) * 90.0
		# Draw circle outline by drawing multiple line segments
		var segments := 16
		for i in range(segments):
			var angle1 := (float(i) / segments) * TAU
			var angle2 := (float(i + 1) / segments) * TAU
			var p1 := to_suspected + Vector2(cos(angle1), sin(angle1)) * uncertainty_radius
			var p2 := to_suspected + Vector2(cos(angle2), sin(angle2)) * uncertainty_radius
			draw_line(p1, p2, confidence_color, 1.5)
		# Draw small filled circle at center
		draw_circle(to_suspected, 5.0, confidence_color)

## Draw FOV cone with obstacle occlusion. Follows model rotation, rays stop at walls.
func _draw_fov_cone(fill_color: Color, edge_color: Color) -> void:
	var half_fov := deg_to_rad(fov_angle / 2.0)
	var global_facing := _enemy_model.global_rotation if _enemy_model else global_rotation
	var local_facing := global_facing - global_rotation  # Convert to local space for drawing
	var space_state := get_world_2d().direct_space_state
	var cone_points: PackedVector2Array = [Vector2.ZERO]
	var ray_endpoints: Array[Vector2] = []
	for i in range(33):  # 32 segments + 1
		var t := float(i) / 32.0
		var angle := local_facing - half_fov + t * 2 * half_fov
		var ray_dir := Vector2.from_angle(angle)
		var global_ray_end := global_position + Vector2.from_angle(global_facing - half_fov + t * 2 * half_fov) * 400.0
		var query := PhysicsRayQueryParameters2D.create(global_position, global_ray_end)
		query.collision_mask = 0b100
		query.exclude = [self]
		var result := space_state.intersect_ray(query)
		var end_local := ray_dir * (global_position.distance_to(result.position) if not result.is_empty() else 400.0)
		cone_points.append(end_local)
		ray_endpoints.append(end_local)
	draw_colored_polygon(cone_points, fill_color)
	if ray_endpoints.size() > 0:
		draw_line(Vector2.ZERO, ray_endpoints[0], edge_color, 2.0)
		draw_line(Vector2.ZERO, ray_endpoints[ray_endpoints.size() - 1], edge_color, 2.0)
	for i in range(ray_endpoints.size() - 1):
		draw_line(ray_endpoints[i], ray_endpoints[i + 1], edge_color, 1.5)

## Check if player is distracted (aim >23° away from this enemy). Used for priority attacks.
func _is_player_distracted() -> bool:
	if not _can_see_player or _player == null:
		return false
	var player_viewport: Viewport = _player.get_viewport()
	if player_viewport == null:
		return false
	var player_pos := _player.global_position
	var mouse_pos := player_viewport.get_mouse_position()
	var global_mouse_pos := player_viewport.get_canvas_transform().affine_inverse() * mouse_pos
	var dir_to_enemy := (global_position - player_pos).normalized()
	var aim_direction := (global_mouse_pos - player_pos).normalized()
	var angle := acos(clampf(dir_to_enemy.dot(aim_direction), -1.0, 1.0))
	var is_distracted := angle > PLAYER_DISTRACTION_ANGLE
	if is_distracted:
		_log_debug("Player distracted: aim angle %.1f° > %.1f° threshold" % [rad_to_deg(angle), rad_to_deg(PLAYER_DISTRACTION_ANGLE)])
	return is_distracted

## Set a navigation target and get the direction to follow the path.
## Uses NavigationAgent2D for proper pathfinding around obstacles.
## Returns the direction to move, or Vector2.ZERO if navigation is not available.
func _get_nav_direction_to(target_pos: Vector2) -> Vector2:
	if _nav_agent == null:
		# Fall back to direct movement if no navigation agent
		return (target_pos - global_position).normalized()

	# Set the target for navigation
	_nav_agent.target_position = target_pos

	# Check if navigation is finished
	if _nav_agent.is_navigation_finished():
		return Vector2.ZERO

	# Get the next position in the path
	var next_pos: Vector2 = _nav_agent.get_next_path_position()

	# Calculate direction to next path position
	var direction: Vector2 = (next_pos - global_position).normalized()
	return direction

## Move toward a target position using NavigationAgent2D pathfinding.
## This is the primary movement function that should be used instead of direct velocity assignment.
## Returns true if movement was applied, false if target was reached or navigation unavailable.
func _move_to_target_nav(target_pos: Vector2, speed: float) -> bool:
	var direction: Vector2 = _get_nav_direction_to(target_pos)

	if direction == Vector2.ZERO:
		velocity = Vector2.ZERO
		return false

	# Apply additional wall avoidance on top of navigation path for tight corners
	direction = _apply_wall_avoidance(direction)

	velocity = direction * speed
	rotation = direction.angle()
	return true

## Check if the navigation agent has a valid path to the target.
func _has_nav_path_to(target_pos: Vector2) -> bool:
	if _nav_agent == null:
		return false

	_nav_agent.target_position = target_pos
	return not _nav_agent.is_navigation_finished()

## Get distance to target along the navigation path (more accurate than straight-line).
func _get_nav_path_distance(target_pos: Vector2) -> float:
	if _nav_agent == null:
		return global_position.distance_to(target_pos)

	_nav_agent.target_position = target_pos
	return _nav_agent.distance_to_target()

# Status Effects (Blindness, Stun)

## Set blinded state (from flashbang). When blinded, enemy cannot see player.
func set_blinded(blinded: bool) -> void:
	var was_blinded := _is_blinded
	_is_blinded = blinded

	if blinded and not was_blinded:
		_log_debug("Enemy is now BLINDED - cannot see player")
		_log_to_file("Status effect: BLINDED applied")
		# Force lose sight of player
		_can_see_player = false
		_continuous_visibility_timer = 0.0
	elif not blinded and was_blinded:
		_log_debug("Enemy is no longer blinded")
		_log_to_file("Status effect: BLINDED removed")

## Set the stunned state (from flashbang grenade).
## When stunned, the enemy cannot move or take actions.
func set_stunned(stunned: bool) -> void:
	var was_stunned := _is_stunned
	_is_stunned = stunned

	if stunned and not was_stunned:
		_log_debug("Enemy is now STUNNED - cannot move")
		_log_to_file("Status effect: STUNNED applied")
		# Stop all movement
		velocity = Vector2.ZERO
	elif not stunned and was_stunned:
		_log_debug("Enemy is no longer stunned")
		_log_to_file("Status effect: STUNNED removed")

## Check if the enemy is currently blinded.
func is_blinded() -> bool:
	return _is_blinded

## Check if the enemy is currently stunned.
func is_stunned() -> bool:
	return _is_stunned

# Grenade System (Issue #363) - Component-based (extracted for Issue #377)

## Setup the grenade component. Called from _ready().
func _setup_grenade_component() -> void:
	if not enable_grenade_throwing:
		return

	_grenade_component = EnemyGrenadeComponent.new()
	_grenade_component.name = "GrenadeComponent"
	_grenade_component.grenade_count = grenade_count
	_grenade_component.grenade_scene = grenade_scene
	_grenade_component.enabled = enable_grenade_throwing
	_grenade_component.throw_cooldown = grenade_throw_cooldown
	_grenade_component.max_throw_distance = grenade_max_throw_distance
	_grenade_component.min_throw_distance = grenade_min_throw_distance
	_grenade_component.safety_margin = grenade_safety_margin
	_grenade_component.inaccuracy = grenade_inaccuracy
	_grenade_component.throw_delay = grenade_throw_delay
	_grenade_component.debug_logging = grenade_debug_logging
	add_child(_grenade_component)
	_grenade_component.initialize()

## Update grenade component each frame. Called from _physics_process.
func _update_grenade_triggers(delta: float) -> void:
	if _grenade_component == null:
		return
	_grenade_component.update(delta, _can_see_player, _under_fire, _player, _current_health)
	_update_grenade_world_state()

## Notify grenade component of gunshots for sustained fire tracking (Trigger 5).
func _on_gunshot_heard_for_grenade(position: Vector2) -> void:
	if _grenade_component:
		_grenade_component.on_gunshot(position)

## Notify grenade component of vulnerable sounds (Trigger 4).
func _on_vulnerable_sound_heard_for_grenade(position: Vector2) -> void:
	if _grenade_component:
		_grenade_component.on_vulnerable_sound(position, _can_see_player)

## Called when an ally dies. Updates witnessed kill count (Trigger 3).
func on_ally_died(ally_position: Vector2, killer_is_player: bool) -> void:
	if _grenade_component:
		_grenade_component.on_ally_died(ally_position, killer_is_player, _can_see_position(ally_position))

## Check if a position is visible to this enemy (line of sight).
func _can_see_position(pos: Vector2) -> bool:
	if _raycast == null:
		return false
	var original_target := _raycast.target_position
	_raycast.target_position = pos - global_position
	_raycast.force_raycast_update()
	var can_see := not _raycast.is_colliding()
	_raycast.target_position = original_target
	return can_see

## Update GOAP world state with grenade trigger conditions.
func _update_grenade_world_state() -> void:
	if _grenade_component == null:
		_goap_world_state["has_grenades"] = false
		_goap_world_state["grenades_remaining"] = 0
		_goap_world_state["ready_to_throw_grenade"] = false
		return
	var g := _grenade_component
	_goap_world_state["has_grenades"] = g.grenades_remaining > 0
	_goap_world_state["grenades_remaining"] = g.grenades_remaining
	_goap_world_state["ready_to_throw_grenade"] = g.is_ready(_can_see_player, _under_fire, _current_health)


## Attempt to throw a grenade. Returns true if throw was initiated.
func try_throw_grenade() -> bool:
	if _grenade_component == null:
		return false
	var memory_pos := _memory.suspected_position if _memory and _memory.has_target() else _last_known_player_position
	var target := _grenade_component.get_target(_can_see_player, _under_fire, _current_health, _player, _last_known_player_position, memory_pos)
	if target == Vector2.ZERO:
		return false
	var result := _grenade_component.try_throw(target, _is_alive, _is_stunned, _is_blinded)
	if result:
		grenade_thrown.emit(null, target)  # Signal with target; actual grenade emitted by component
	return result


## Get the number of grenades remaining.
func get_grenades_remaining() -> int:
	if _grenade_component:
		return _grenade_component.grenades_remaining
	return 0

## Add grenades to the enemy's inventory.
func add_grenades(count: int) -> void:
	if _grenade_component:
		_grenade_component.add_grenades(count)
