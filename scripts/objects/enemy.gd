extends CharacterBody2D
## Enemy AI with tactical behaviors: patrol, guard, cover, flanking, GOAP. AI States for tactical behavior.
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
	SEARCHING,  ## Methodically searching area where player was last seen (Issue #322)
	EVADING_GRENADE,  ## Fleeing from grenade danger zone (Issue #407)
	PACIFIST    ## Refuses to fight, hides in cover (Issue #959: Loudspeaker effect)
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

## Weapon types: RIFLE (M16), SHOTGUN (slow/powerful), UZI (fast SMG), MACHETE (melee, Issue #579), RPG (rocket+pistol, Issue #583), PM (Makarov, Issue #583), MACHINE_GUN (PKM belt-fed, #1033), SNIPER_RIFLE (ASVK, #1125), REVOLVER (RSh-12, #1242).
enum WeaponType { RIFLE, SHOTGUN, UZI, MACHETE, RPG, PM, MACHINE_GUN, SNIPER_RIFLE, REVOLVER }

@export var behavior_mode: BehaviorMode = BehaviorMode.GUARD  ## Current behavior mode.
@export var weapon_type: WeaponType = WeaponType.RIFLE  ## Weapon type for this enemy.
@export var move_speed: float = 220.0  ## Maximum movement speed (px/s).
@export var combat_move_speed: float = 320.0  ## Combat movement speed (flanking/cover).
@export var rotation_speed: float = 25.0  ## Rotation speed (rad/s, 25 for aim-before-shoot #254).
@export var detection_range: float = 0.0  ## Detection range (0=unlimited, line-of-sight only).
@export var fov_angle: float = 100.0  ## FOV angle (deg). 0/negative = 360°. Default 100° per #66.
@export var fov_enabled: bool = true  ## FOV enabled (combined with ExperimentalSettings).
@export var shoot_cooldown: float = 0.1  ## Time between shots (0.1s = 10 rounds/sec).
@export var bullet_damage_multiplier: float = 1.0  ## Damage multiplier applied to each bullet (Issue #1244).
@export var bullet_scene: PackedScene  ## Bullet scene to instantiate when shooting.
@export var casing_scene: PackedScene  ## Casing scene for ejected bullet casings.
@export var bullet_spawn_offset: float = 30.0  ## Offset from center for bullet spawn.
@export var weapon_loudness: float = 1469.0  ## Weapon loudness for alerting enemies.
@export var patrol_offsets: Array[Vector2] = [Vector2(100, 0), Vector2(-100, 0)]  ## Patrol points.
@export var patrol_wait_time: float = 1.5  ## Wait time at each patrol point (seconds).
@export var full_health_color: Color = Color(0.9, 0.2, 0.2, 1.0)  ## Color at full health.
@export var low_health_color: Color = Color(0.3, 0.1, 0.1, 1.0)  ## Color at low health.
@export var hit_flash_color: Color = Color(1.0, 1.0, 1.0, 1.0)  ## Color to flash when hit.
@export var hit_flash_duration: float = 0.1  ## Hit flash duration (seconds).
@export var destroy_on_death: bool = false  ## Destroy enemy after death.
@export var respawn_delay: float = 2.0  ## Delay before respawn/destroy (seconds).
@export var min_health: int = 2  ## Minimum random health.
@export var max_health: int = 4  ## Maximum random health.
@export var threat_sphere_radius: float = 100.0  ## Bullets within radius trigger suppression.
@export var suppression_cooldown: float = 2.0  ## Time suppressed after bullets leave.
@export var threat_reaction_delay: float = 0.2  ## Delay before reacting to threats.
@export var flank_angle: float = PI / 3.0  ## Flank angle from player facing (60 deg).
@export var flank_distance: float = 200.0  ## Distance to maintain while flanking.
@export var enable_flanking: bool = true  ## Enable flanking behavior.
@export var enable_cover: bool = true  ## Enable cover behavior.
@export var debug_logging: bool = false  ## Enable debug logging.
@export var debug_label_enabled: bool = false  ## Enable debug label above enemy.
@export var enable_friendly_fire_avoidance: bool = true  ## Don't shoot if allies in way.
@export var enable_lead_prediction: bool = true  ## Shoot ahead of moving targets.
@export var bullet_speed: float = 2500.0  ## Bullet speed for lead prediction.
@export var magazine_size: int = 30  ## Bullets per magazine.
@export var total_magazines: int = 5  ## Number of magazines carried.
@export var reload_time: float = 3.0  ## Time to reload in seconds.
@export var detection_delay: float = 0.2  ## Delay between spotting player and shooting (reaction time).
@export var lead_prediction_delay: float = 0.3  ## Min visibility time before enabling lead prediction.
@export var lead_prediction_visibility_threshold: float = 0.6  ## Min visibility ratio for lead prediction.
@export var walk_anim_speed: float = 12.0  ## Walking animation speed multiplier.
@export var walk_anim_intensity: float = 1.0  ## Walking animation intensity.
@export var enemy_model_scale: float = 1.3  ## Scale multiplier for enemy model (1.3 matches player).
@export var is_grenadier: bool = false  ## Whether this enemy is a grenadier type (Issue #604).
@export var is_teleporter: bool = false  ## Whether this enemy can teleport (Issue #752).
@export var has_force_field: bool = false  ## Whether this enemy has a Force Field (Issue #1034).
@export var start_invisible: bool = false  ## Start with invisibility cloak, reveal only when shooting/throwing grenade (Issue #1121).
@export var initial_state: AIState = AIState.IDLE  ## Initial AI state on spawn (Issue #1121). SEARCHING starts enemy in search mode.
@export var has_armored_skin: bool = false  ## Whether this enemy has Armored Skin passive item (Issue #1123).
@export var has_swat_shield: bool = false  ## Whether this enemy is a SWAT shieldbearer with a blocking shield (Issue #1242).
@export var is_gas_mask: bool = false  ## Gas Mask type with chemical grenades (Issue #1353).
@export var is_drone_operator: bool = false  ## Drone Operator with dash evasion (Issue #1397).
@export var search_path_node: NodePath = NodePath("")  ## SearchPathWaypoints node path; when set, uses pre-planned waypoints in SEARCHING instead of spiral (Issue #1225).
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
signal died_with_info(is_ricochet_kill: bool, is_penetration_kill: bool, is_player_kill: bool)  ## Death with kill info (Issue #1196: is_player_kill distinguishes player kills from other kills)
signal state_changed(new_state: AIState)  ## AI state changed
signal ammo_changed(current_ammo: int, reserve_ammo: int)  ## Ammo changed
signal reload_started  ## Reload started
signal reload_finished  ## Reload finished
signal ammo_depleted  ## All ammo depleted
signal death_animation_completed  ## Death animation done
signal grenade_thrown(grenade: Node, target_position: Vector2)  ## Grenade thrown (Issue #363)
signal became_pacifist  ## Enemy became pacifist (Issue #959: counts as killed for level completion)

const PLAYER_DISTRACTION_ANGLE: float = 0.4014  ## ~23° - player distracted threshold
const AIM_TOLERANCE_DOT: float = 0.866  ## cos(30°) - aim tolerance (issue #254/#264)
@onready var _enemy_model: Node2D = $EnemyModel  ## Model node with all sprites
@onready var _body_sprite: Sprite2D = $EnemyModel/Body  ## Body sprite
@onready var _head_sprite: Sprite2D = $EnemyModel/Head  ## Head sprite
@onready var _left_arm_sprite: Sprite2D = $EnemyModel/LeftArm  ## Left arm sprite
@onready var _right_arm_sprite: Sprite2D = $EnemyModel/RightArm  ## Right arm sprite
@onready var _weapon_sprite: Sprite2D = $EnemyModel/WeaponMount/WeaponSprite  ## Weapon sprite
@onready var _weapon_mount: Node2D = $EnemyModel/WeaponMount  ## Weapon mount
@onready var _shield_icon: Sprite2D = $EnemyModel/WeaponMount/ShieldIcon  ## Blue shield icon shown on force field enemies (Issue #1079)
@onready var _raycast: RayCast2D = $RayCast2D  ## Line of sight raycast
@onready var _debug_label: Label = $DebugLabel  ## Debug state label
@onready var _nav_agent: NavigationAgent2D = $NavigationAgent2D  ## Pathfinding
## HitArea for bullet collision detection (disabled on death).
@onready var _hit_area: Area2D = $HitArea
@onready var _hit_collision_shape: CollisionShape2D = $HitArea/HitCollisionShape  ## Collision on death
@onready var _casing_pusher: Area2D = $CasingPusher  ## Casing pusher Area2D (Issue #438)
var _original_hit_area_layer: int = 0  ## Original collision layer (restore on respawn)
var _original_hit_area_mask: int = 0
var _overlapping_casings: Array[RigidBody2D] = []  ## Casings in CasingPusher (Issue #438)
var _walk_anim_time: float = 0.0  ## Walking animation accumulator
var _is_walking: bool = false  ## Currently walking (for anim)
var _target_model_rotation: float = 0.0  ## Target rotation for smooth interpolation
var _model_facing_left: bool = false  ## Model flipped for left-facing direction
const MODEL_ROTATION_SPEED: float = 3.0  ## Max model rotation speed (3.0 rad/s = 172 deg/s)
var _idle_scan_timer: float = 0.0  ## IDLE scanning state for GUARD enemies
var _idle_scan_target_index: int = 0
var _idle_scan_targets: Array[float] = []
const IDLE_SCAN_INTERVAL: float = 10.0 / 3.0
var _base_body_pos: Vector2 = Vector2.ZERO; var _base_head_pos: Vector2 = Vector2.ZERO  ## Base positions for animation
var _base_left_arm_pos: Vector2 = Vector2.ZERO; var _base_right_arm_pos: Vector2 = Vector2.ZERO
var _wall_raycasts: Array[RayCast2D] = []  ## Wall detection raycasts
const WALL_CHECK_DISTANCE: float = 60.0  ## Wall check distance
const WALL_CHECK_COUNT: int = 8  ## Number of wall raycasts
const WALL_AVOIDANCE_MIN_WEIGHT: float = 0.7  ## Min avoidance (close)
const WALL_AVOIDANCE_MAX_WEIGHT: float = 0.3  ## Max avoidance (far)
const WALL_SLIDE_DISTANCE: float = 30.0  ## Wall slide threshold
## Issue #1146: Enemy-enemy separation steering constants.
const SEPARATION_RADIUS: float = 60.0  ## Distance within which separation force is applied (px)
const SEPARATION_STRENGTH: float = 280.0  ## Maximum separation impulse magnitude (px/s²)
var _avoidance_velocity: Vector2 = Vector2.ZERO  ## Issue #1146: ORCA-computed safe velocity
var _cover_raycasts: Array[RayCast2D] = []  ## Cover detection raycasts
const COVER_CHECK_COUNT: int = 120  ## Number of cover raycasts (Issue #1338: 120 rays = 3° apart for dense coverage)
const COVER_CHECK_DISTANCE: float = 300.0  ## Cover check distance (default, used when infinite rays disabled)
const COVER_INFINITE_RAY_DISTANCE: float = 10000.0  ## Extended ray distance for infinite rays (Issue #1378)
const COVER_SECTOR_HALF_ANGLE: float = 50.0 * PI / 180.0  ## 50° half-angle = 100° total cone (Issue #1378)
const COVER_SECTOR_RAY_COUNT: int = 120  ## Number of rays in sector mode (Issue #1378)
var _current_health: int = 0; var _max_health: int = 0  ## Current / max health (set at spawn)
var _is_alive: bool = true  ## Is alive
var _player: Node2D = null  ## Player reference
var _shoot_timer: float = 0.0  ## Time since last shot
## Issue #969: throttle constants/trackers — prevent raycast floods with 20+ active enemies
const ENEMY_GUNSHOT_PROPAGATION_COOLDOWN: float = 0.5; var _last_gunshot_propagation_time: float = -999.0
const COVER_SEARCH_COOLDOWN: float = 0.3; var _last_cover_search_time: float = -999.0
const SUPPRESSED_MIN_DURATION: float = 0.5; var _suppressed_entry_time: float = -999.0  ## RCA-11: prevent SUPPRESSED→SEEKING_COVER cycling
const POST_SUPPRESSION_COVER_DURATION: float = 3.0; var _post_suppression_timer: float = 0.0  ## Issue #1338: stay in cover after being suppressed
const SEEKING_COVER_MIN_DURATION: float = 0.3; var _seeking_cover_entry_time: float = -999.0  ## Issue #997 RCA-17
const RETREATING_MIN_DURATION: float = 0.3; var _retreating_entry_time: float = -999.0  ## Issue #997 RCA-17
const IN_COVER_MIN_DURATION: float = 0.3; var _in_cover_entry_time: float = -999.0  ## Issue #997 RCA-18: prevent instant IN_COVER→SUPPRESSED cycling
var _cached_visible_from_player: bool = false; var _visible_from_player_cache_frame: int = -1
var _visibility_cache: Dictionary = {}; var _visibility_cache_frame: int = -1  ## Issue #1411: per-frame visibility cache
var _last_distant_cover_search_time: float = -999.0; var _last_closest_cover_search_time: float = -999.0  ## Issue #1411: throttle timers
const COVER_MAX_CANDIDATES: int = 8  ## Issue #1411: early termination threshold for cover candidate search
var _current_ammo: int = 0  ## Ammo in magazine
var _reserve_ammo: int = 0  ## Reserve ammo
var _is_reloading: bool = false  ## Currently reloading
var _reload_timer: float = 0.0  ## Reload progress
## Weapon configuration for player-like weapons (Issue #417 PR feedback).
var _is_shotgun_weapon: bool = false  ## Whether weapon fires multiple pellets
var _pellet_count_min: int = 1  ## Minimum pellets per shot (for shotgun)
var _pellet_count_max: int = 1  ## Maximum pellets per shot (for shotgun)
var _spread_angle: float = 0.0  ## Spread angle in degrees (for shotgun)
var _spread_threshold: int = 3; var _initial_spread: float = 0.5; var _spread_increment: float = 0.6; var _max_spread: float = 4.0; var _spread_reset_time: float = 0.25; var _shot_count: int = 0; var _spread_timer: float = 0.0  ## Issue #516: progressive spread
var _caliber_data: Resource = null  ## Caliber data for casings
var _patrol_points: Array[Vector2] = []  ## Patrol state
var _current_patrol_index: int = 0
var _is_waiting_at_patrol_point: bool = false
var _patrol_wait_timer: float = 0.0
var _patrol_stuck_timer: float = 0.0; var _patrol_stuck_last_position: Vector2 = Vector2.ZERO  ## #1119: patrol stuck detection
const PATROL_STUCK_MAX_TIME: float = 1.5; const PATROL_STUCK_DISTANCE_THRESHOLD: float = 20.0  ## #1119: stuck thresholds
var _patrol_points_snapped: bool = false  ## #1216: tracks whether patrol points were snapped to the navmesh
var _spawn_physics_frame: int = 0  ## #1216: physics frame at spawn, used to delay navmesh snap by 1 frame
var _corner_check_angle: float = 0.0  ## Angle to look toward when checking a corner
var _corner_check_timer: float = 0.0  ## Timer for corner check duration
var _hit_reaction_angle: float = 0.0; var _hit_reaction_timer: float = 0.0; const HIT_REACTION_DURATION: float = 0.8  ## Issue #1242: shield enemy slow rotation toward attacker on hit
var _shield_tracking_angle: float = 0.0; var _shield_tracking_timer: float = 0.0  ## Issue #1242: delayed player tracking — shield enemy updates facing direction periodically, not continuously
const SHIELD_TRACKING_INTERVAL: float = 1.5  ## Seconds between player-direction updates while shield is up (allows flanking)
var _last_rotation_reason: String = ""  ## Issue #397 debug: track rotation priority changes
const CORNER_CHECK_DURATION: float = 0.3  ## How long to look at a corner (seconds)
const CORNER_CHECK_DISTANCE: float = 150.0  ## Max distance to detect openings
var _initial_position: Vector2
var _can_see_player: bool = false  ## Can see player
var _bff_targeting: BffTargetingComponent = null  ## Issue #934: companion targeting
var _companion: Node2D = null  ## BFF companion reference (Issue #934, alias for _bff_targeting.companion)
var _can_see_companion: bool = false  ## Can see BFF companion (Issue #934)
var _current_target: Node2D = null  ## Best current target: player or companion (Issue #934)
var _current_state: AIState = AIState.IDLE  ## AI state
var _cover_position: Vector2 = Vector2.ZERO  ## Cover position
var _has_valid_cover: bool = false  ## Has valid cover
var _last_cover_search_rays: Array = []  ## Issue #1338: cached ray data for debug visualization (rays from player)
var _suppression_timer: float = 0.0  ## Suppression cooldown
var _under_fire: bool = false  ## Under fire (bullets in threat sphere)
var _flank_target: Vector2 = Vector2.ZERO  ## Flank target position
var _threat_sphere: Area2D = null  ## Threat sphere Area2D for detecting nearby bullets
var _bullets_in_threat_sphere: Array = []  ## Bullets currently in threat sphere
var _threat_reaction_timer: float = 0.0  ## Time since first bullet entered threat sphere
var _threat_reaction_delay_elapsed: bool = false  ## Whether enemy can react to bullets
var _threat_memory_timer: float = 0.0  ## Memory timer for bullets that passed through threat sphere
const THREAT_MEMORY_DURATION: float = 0.5  ## Duration to remember bullet passage
var _retreat_mode: RetreatMode = RetreatMode.FULL_HP  ## Current retreat mode determined by damage taken
var _hits_taken_in_encounter: int = 0  ## Hits taken this encounter, resets on IDLE or retreat completion
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
var _combat_shoot_timer: float = 0.0  ## Exposed shooting timer (Combat Cover Cycling)
var _combat_shoot_duration: float = 2.5  ## Shoot duration out of cover
var _combat_exposed: bool = false  ## In exposed shooting phase
var _combat_approaching: bool = false  ## Approaching player phase
var _combat_approach_timer: float = 0.0  ## Approach phase timer
var _combat_state_timer: float = 0.0  ## Total COMBAT time this cycle
const COMBAT_APPROACH_MAX_TIME: float = 2.0  ## Max approach time (sec)
const COMBAT_DIRECT_CONTACT_DISTANCE: float = 250.0  ## Close enough to shoot
const COMBAT_MIN_DURATION_BEFORE_PURSUE: float = 0.5  ## Min COMBAT before PURSUING
var _pursuit_cover_wait_timer: float = 0.0  ## Cover wait timer (Pursuit State)
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
const PURSUIT_PATH_DESIRED_DISTANCE: float = PursuitComponent.PURSUIT_PATH_DESIRED_DISTANCE  ## Issue #1289: enlarged nav step length while pursuing (from PursuitComponent)
var _nav_default_path_desired_distance: float = 40.0  ## Issue #1289: saved default path_desired_distance
var _flank_cover_wait_timer: float = 0.0  ## Wait at cover timer (Flanking State)
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
var _flank_fail_count: int = 0; const FLANK_FAIL_MAX_COUNT: int = 2  ## Consecutive flank failures / max before cooldown
var _flank_cooldown_timer: float = 0.0; const FLANK_COOLDOWN_DURATION: float = 5.0  ## Cooldown timer / duration (sec) after failures
var _global_stuck_timer: float = 0.0; var _global_stuck_last_position: Vector2 = Vector2.ZERO  ## Stuck timer (Issue #367) / last position
const GLOBAL_STUCK_MAX_TIME: float = 4.0; const GLOBAL_STUCK_DISTANCE_THRESHOLD: float = 30.0  ## Max stuck time / min move distance  ## Issue #1173: restored 1.5→4.0; machete wall-escape is handled by MACHETE_COMBAT_STUCK_MAX_TIME
var _machete_combat_stuck_timer: float = 0.0; var _machete_combat_stuck_last_pos: Vector2 = Vector2.ZERO  ## Issue #1107: Stuck detection for machete COMBAT state
const MACHETE_COMBAT_STUCK_MAX_TIME: float = 0.8; const MACHETE_COMBAT_STUCK_DIST_THRESHOLD: float = 20.0  ## Reroute after 0.8s stuck within 20px
var _debug_draw_timer: float = 0.0; const DEBUG_DRAW_INTERVAL: float = 0.1  ## Issue #1220: throttle F7 debug redraw to 10 Hz to reduce FOV raycast overhead
var _assault_wait_timer: float = 0.0; const ASSAULT_WAIT_DURATION: float = 5.0  ## Assault wait timer / pre-assault wait (sec)
var _assault_ready: bool = false; var _in_assault: bool = false  ## Assault wait complete / in assault flag
var _search_center: Vector2 = Vector2.ZERO; var _search_radius: float = 100.0  ## Search center / current radius (Search State - Issue #322)
const SEARCH_INITIAL_RADIUS: float = 100.0; const SEARCH_RADIUS_EXPANSION: float = 75.0  ## Initial radius / radius expansion
const SEARCH_MAX_RADIUS: float = 2000.0  ## Max radius before relocating center (Issue #405: search continues indefinitely)
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
var _search_stuck_timer: float = 0.0  ## Stuck timer (Issue #354: Stuck detection for SEARCHING)
var _search_last_progress_position: Vector2 = Vector2.ZERO  ## Last progress pos
const SEARCH_STUCK_MAX_TIME: float = 0.8  ## Max stuck time (#1249: 2.0→0.8 s, faster skip of blocked search waypoints)
const SEARCH_PROGRESS_THRESHOLD: float = 10.0  ## Min progress distance
var _has_left_idle: bool = false  ## Issue #330: Never returns to IDLE
var _search_path_node: Node2D = null  ## SearchPathWaypoints node cache (Issue #1225)
var _using_predefined_search_path: bool = false  ## Using predefined path instead of spiral (Issue #1225)
const CLOSE_COMBAT_DISTANCE: float = 400.0  ## Close combat threshold
var _goap_world_state: Dictionary = {}  ## GOAP world state
var _detection_timer: float = 0.0  ## Combat detection timer
var _detection_delay_elapsed: bool = false  ## Detection delay done
var _continuous_visibility_timer: float = 0.0  ## Continuous visibility timer
var _player_visibility_ratio: float = 0.0  ## Player visibility (0-1)
## Issue #883: Stagger vision raycasts; each enemy checks once every VISION_CHECK_INTERVAL frames.
var _vision_frame_counter: int = 0; var _vision_frame_offset: int = 0  ## Frame stagger (set in _ready)
const VISION_CHECK_INTERVAL: int = 6  ## Check vision every N frames (~10 fps at 60 fps physics)
var _clear_shot_target: Vector2 = Vector2.ZERO  ## Clear shot target (Clear Shot Movement)
var _seeking_clear_shot: bool = false  ## Moving to clear shot
var _clear_shot_timer: float = 0.0  ## Clear shot attempt timer
const CLEAR_SHOT_MAX_TIME: float = 3.0  ## Max time to find clear shot (seconds)
const CLEAR_SHOT_EXIT_DISTANCE: float = 60.0  ## Distance to move when exiting cover to find clear shot
var _last_known_player_position: Vector2 = Vector2.ZERO  ## Last known player position (for sound-based detection)
var _pursuing_vulnerability_sound: bool = false  ## Pursuing vulnerability sound without LOS
var _passage_waypoints: Array = []  ## Cached passage waypoints (populated after _ready via deferred call)
var _suppressive_fire: SuppressiveFireComponent = null  ## Issue #910: Suppressive fire component.
var _memory: EnemyMemory = null  ## [#297] Suspected player pos: high>0.8=pursue, med=cautious, low=patrol
## Confidence values for different detection sources.
const VISUAL_DETECTION_CONFIDENCE: float = 1.0
const SOUND_GUNSHOT_CONFIDENCE: float = 0.7
const SOUND_RELOAD_CONFIDENCE: float = 0.6
const SOUND_EMPTY_CLICK_CONFIDENCE: float = 0.6
const SOUND_CASING_KICK_CONFIDENCE: float = 0.5  ## Issue #693: Casing kick - lower than reload
const INTEL_SHARE_FACTOR: float = 0.9  ## Confidence reduction when sharing intel
const INTEL_SHARE_RANGE_LOS: float = 660.0  ## Intel range with LOS (px)
const INTEL_SHARE_RANGE_NO_LOS: float = 300.0  ## Intel range without LOS (px)
var _intel_share_timer: float = 0.0; const INTEL_SHARE_INTERVAL: float = 0.5  ## Share intel every 0.5s
var _memory_reset_confusion_timer: float = 0.0  ## Issue #318: blocks visibility after teleport
const MEMORY_RESET_CONFUSION_DURATION: float = 2.0  ## 2s confusion for better player escape window
## [#409] SEARCHING on ally death; estimates player pos from bullet direction.
const ALLY_DEATH_OBSERVE_RANGE: float = 500.0  ## Max distance to observe ally death (px)
const ALLY_DEATH_CONFIDENCE: float = 0.6  ## Medium confidence when observing death
var _suspected_directions: Array[Vector2] = []  ## Up to 3 estimated player directions
var _witnessed_ally_death: bool = false  ## Flag for GOAP action trigger
var _killed_by_ricochet: bool = false  ## [Score] Killed by ricochet
var _killed_by_penetration: bool = false  ## [Score] Killed by penetration
var _killed_by_player: bool = false  ## [Score/Issue #1196] Killed directly by player (no laser sight)
## [Status Effects] Component handles blindness and stun (Issue #432, #328)
var _flashbang_status: FlashbangStatusComponent = null
var _is_blinded: bool = false
var _is_stunned: bool = false
var _status_effect_anim: StatusEffectAnimationComponent = null  ## [Issue #602] Status effect visual animations
var _aggression: AggressionComponent = null  ## [Issue #675] Aggression gas component.
## [Pacifism - Issue #959] Loudspeaker effect component
var _pacifist: PacifistComponent = null  ## Pacifism state management
var _evaluated_pacifists: Array = []  ## Pacifists already evaluated for spread (Level 5+), prevents re-rolling
var _force_field_component: EnemyForceFieldComponent = null  ## [Issue #1034] Force field component
var _armored_skin_component: EnemyArmoredSkinComponent = null  ## [Issue #1123] Armored skin component
var _shield_component: EnemyShieldComponent = null; var _formation_shielder: Node2D = null; var _formation_target_pos: Vector2 = Vector2.ZERO  ## [Issue #1242] SWAT shield + formation
var _revolver_cocking: bool = false  ## [Issue #1242] True while hammer is being cocked before revolver shot
var _revolver_component: EnemyRevolverComponent = null  ## [Issue #1242] Revolver reload/casing component
var _knockback_velocity: Vector2 = Vector2.ZERO  ## [Issue #1242] Knockback impulse that decays over time
## [Grenade Avoidance - Issue #407] Component handles avoidance logic
var _grenade_avoidance: GrenadeAvoidanceComponent = null
var _grenade_evasion_timer: float = 0.0  ## Timer for evasion to prevent stuck
const GRENADE_EVASION_MAX_TIME: float = 4.0  ## Max evasion time before giving up
var _pre_evasion_state: AIState = AIState.IDLE  ## State to return to after grenade evasion
var _prediction: PlayerPredictionComponent = null  ## [Issue #298] Player position prediction.
var _was_player_visible: bool = false  ## [Issue #298] Tracks sight-loss transitions.
var _flashlight_detection: FlashlightDetectionComponent = null  ## [Issue #574] Flashlight detection component — detects player flashlight beam.
var _enemy_flashlight: EnemyFlashlightComponent = null  ## [Issue #824] Enemy flashlight for night mode.
var _is_pre_attack_flashing: bool = false  ## [Issue #824] Pre-attack flash phase.
var _last_hit_direction: Vector2 = Vector2.RIGHT  ## Last hit direction (used for death animation).
var _death_animation: Node = null  ## Death animation component reference.
var _grenade_component: EnemyGrenadeComponent = null  ## Grenade component (extracted for Issue #377 CI fix).
var _machete: MacheteComponent = null  ## Machete melee component (Issue #579).
var _teleport_component: EnemyTeleportComponent = null  ## Teleport component (Issue #752).
var _sniper_component: EnemySniperComponent = null  ## Sniper AI + hitscan component (Issues #1163, #1171).
var _is_melee_weapon: bool = false  ## Whether this enemy uses melee weapon.
var _is_rpg_weapon: bool = false  ## Whether this enemy starts with RPG (Issue #583).
var _rpg_fired: bool = false  ## Whether the RPG shot has been fired (Issue #583).
var _machine_gunner_pm_active: bool = false  ## [#1033] True after MACHINE_GUN belt empties and PM fallback activates.
var _machine_gunner_suppressing_corridor: bool = false  ## [#1033] True while MG suppresses last-seen corridor instead of pursuing.
## [#1177] Sniper bolt-action 4-step cycle state/timer/step/delays (matching player SniperRifle.cs).
var _is_bolt_cycling: bool = false; var _bolt_cycle_timer: float = 0.0; var _bolt_cycle_step: int = 0
const SNIPER_BOLT_CYCLE_DELAY: float = 0.5  ## Legacy: kept for compatibility.
const SNIPER_BOLT_STEP_DELAYS: Array = [0.3, 0.5, 0.4, 0.3]  ## Per-step delays (audio cadence).
var _waiting_for_grenadier: bool = false  ## Issue #604: Waiting for grenadier's grenade.
var _grenadier_wait_timer: float = 0.0  ## Issue #604: Safety timeout for grenadier wait.
var _grenade_throw_facing_direction: Vector2 = Vector2.ZERO  ## Issue #712: Facing direction for grenade throw.
var _is_facing_for_grenade_throw: bool = false  ## Issue #712: Whether forcing rotation for throw.
var _invisibility: EnemyInvisibilityComponent = null  ## Issue #1121: Invisibility cloak component.
var _gas_mask_grenade: GasMaskGrenadeComponent = null; var _drone_operator: DroneOperatorComponent = null  ## Issues #1353, #1397
var _tactical_movement: TacticalMovementComponent = null  ## Issue #1249: Tactical movement coordination in narrow passages.
var _tactical_group: TacticalGroupComponent = null  ## Issue #1287: Tactical group movement — enemies within 500 px spread around the player.
var _pursuit_component: PursuitComponent = null  ## Issue #1289: Cover-finding logic for PURSUING state.

func _ready() -> void:
	add_to_group("enemies")
	# Issue #883: Stagger vision checks across enemies so they don't all raycast on the same frame.
	_vision_frame_offset = get_instance_id() % VISION_CHECK_INTERVAL
	_spawn_physics_frame = Engine.get_physics_frames()  # #1216: delay navmesh snap by 1 physics frame

	# Issue #934: Initialize BFF companion targeting component
	_bff_targeting = BffTargetingComponent.new(self)

	_configure_weapon_type()  # Configure weapon parameters before ammo init
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
	_connect_debug_mode_signal(); (func(): var _es := get_node_or_null("/root/ExperimentalSettings"); var _wp_on: bool = (_es == null or not _es.has_method("is_passage_waypoints_enabled") or _es.is_passage_waypoints_enabled()); _passage_waypoints = get_tree().get_nodes_in_group("passage_waypoints") if _wp_on else []).call_deferred()  ## #1226: cache once after ready; #1267: skip if passage waypoints disabled
	_update_debug_label()
	_register_sound_listener()
	_setup_flashbang_status()
	_setup_grenade_component()
	_setup_grenade_avoidance()
	_setup_aggression_component(); _suppressive_fire = SuppressiveFireComponent.new(); add_child(_suppressive_fire)  # Issue #675, #910
	_pacifist = PacifistComponent.new(self)  # Issue #959
	_setup_machete_component(); if has_force_field: _force_field_component = EnemyForceFieldComponent.new(); _force_field_component.name = "ForceFieldComponent"; add_child(_force_field_component); _force_field_component.setup(); if _shield_icon: _shield_icon.visible = true  # Issue #579, #1034, #1079
	_sniper_component = EnemySniperComponent.new(); _sniper_component.enemy = self; _sniper_component.log_to_file_fn = _log_to_file; _sniper_component.name = "SniperComponent"; add_child(_sniper_component)  # Issues #1171, #1163
	if has_armored_skin: _armored_skin_component = EnemyArmoredSkinComponent.new(); _armored_skin_component.name = "ArmoredSkinComponent"; add_child(_armored_skin_component); _current_health += 1; _max_health += 1; _update_health_visual()  # Issue #1123: +1 HP bonus from Armored Skin
	if has_swat_shield: _shield_component = EnemyShieldComponent.new(); _shield_component.name = "ShieldComponent"; add_child(_shield_component); _shield_component.setup()  # Issue #1242: SWAT shieldbearer
	if weapon_type == WeaponType.REVOLVER: _revolver_component = EnemyRevolverComponent.new(); _revolver_component.enemy = self; _revolver_component.name = "RevolverComponent"; add_child(_revolver_component)  # Issue #1242: revolver reload
	if is_teleporter: _teleport_component = EnemyTeleportComponent.new(); _teleport_component.name = "TeleportComponent"; add_child(_teleport_component); EnemyTeleportComponent.add_backpack(_enemy_model)  # Issue #752
	_setup_enemy_flashlight()  # Issue #824
	_connect_casing_pusher_signals()  # Issue #438
	if _is_melee_weapon and _weapon_sprite: _weapon_sprite.visible = true  # Issue #595: show machete
	if _hit_area:  # Store original collision layers for respawn
		_original_hit_area_layer = _hit_area.collision_layer
		_original_hit_area_mask = _hit_area.collision_mask

	# Issue #1146: Hook ORCA avoidance velocity so NavigationAgent2D steers enemies apart.
	if _nav_agent and _nav_agent.avoidance_enabled:
		_nav_agent.velocity_computed.connect(_on_avoidance_velocity_computed)
	if _nav_agent: _nav_default_path_desired_distance = _nav_agent.path_desired_distance  # Issue #1289: save default path_desired_distance for PURSUING state

	_tactical_movement = TacticalMovementComponent.new(self)  # Issue #1249: narrow passage queuing
	_tactical_group = TacticalGroupComponent.new(self)  # Issue #1287: tactical group encirclement
	_pursuit_component = PursuitComponent.new(self)  # Issue #1289: pursuit cover-finding component

	call_deferred("_log_spawn_info")  # Log spawn info after FileLogger loads
	if bullet_scene == null:  # Preload bullet scene if not set in inspector
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

	_init_death_animation()
	_status_effect_anim = StatusEffectAnimationComponent.new(); _status_effect_anim.name = "StatusEffectAnim"; _enemy_model.add_child(_status_effect_anim)  # Issue #602
	if _head_sprite: _status_effect_anim.head_offset = _head_sprite.position
	if initial_state == AIState.SEARCHING: _has_left_idle = true; _transition_to_searching(global_position)  # Issue #1121
	elif initial_state != AIState.IDLE: _current_state = initial_state  # Issue #1121: initial state override
	else: _transition_to_idle()  # Issue #1202: honor IDLE disable at spawn (redirects to SEARCHING if IDLE is disabled)
	if start_invisible: _invisibility = EnemyInvisibilityComponent.new(); _invisibility.name = "InvisibilityComponent"; add_child(_invisibility); _invisibility.initialize(_enemy_model)  # Issue #1121
	if is_gas_mask:  # Issue #1353: chemical grenades with illusion copies
		_gas_mask_grenade = GasMaskGrenadeComponent.new(); _gas_mask_grenade.name = "GasMaskGrenadeComponent"; add_child(_gas_mask_grenade)
		if _head_sprite: var _gm_tex := load("res://assets/sprites/characters/enemy/gas_mask_head.png"); if _gm_tex: _head_sprite.texture = _gm_tex; _head_sprite.rotation_degrees = -90.0  # Issue #1363: sprite drawn facing up, rotate to face right
	if is_drone_operator: _drone_operator = DroneOperatorComponent.new(); _drone_operator.name = "DroneOperatorComponent"; add_child(_drone_operator); _drone_operator.setup(); if _weapon_sprite: _weapon_sprite.visible = false; if initial_state == AIState.IDLE: _transition_to_seeking_cover()  # Issue #1397
## Initialize health with random value between min and max. Black Metal mode (#958) reduces HP by 25%.
func _initialize_health() -> void:
	_max_health = 2 if is_grenadier else randi_range(min_health, max_health)  # Issue #604: Grenadiers always 2 HP
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager and difficulty_manager.has_method("get_hp_multiplier"):  # #958: Black Metal HP mult
		var hp_mult: float = difficulty_manager.get_hp_multiplier()
		_max_health = maxi(1, int(_max_health * hp_mult))
	_current_health = _max_health
	_is_alive = true

## Initialize ammunition with full magazine and reserve ammo.
func _initialize_ammo() -> void:
	_current_ammo = magazine_size
	_reserve_ammo = (total_magazines - 1) * magazine_size  # (total_magazines - 1) since one is loaded
	_is_reloading = false
	_reload_timer = 0.0

## Configure weapon type from WeaponConfigComponent (bullet scenes, caliber; #417).
func _configure_weapon_type() -> void:
	var c := WeaponConfigComponent.get_config(weapon_type)
	shoot_cooldown = c["shoot_cooldown"]; bullet_speed = c["bullet_speed"]; magazine_size = c["magazine_size"]
	bullet_spawn_offset = c["bullet_spawn_offset"]; weapon_loudness = c["weapon_loudness"]
	if c["sprite_path"] != "" and _weapon_sprite:
		var tex := load(c["sprite_path"]) as Texture2D
		if tex: _weapon_sprite.texture = tex
	# Load bullet/casing scenes and caliber data for player-like projectiles
	if c.get("bullet_scene_path", "") != "":
		var s := load(c["bullet_scene_path"]) as PackedScene
		if s: bullet_scene = s
	if c.get("casing_scene_path", "") != "":
		var s := load(c["casing_scene_path"]) as PackedScene
		if s: casing_scene = s
	if c.get("caliber_path", "") != "": _caliber_data = load(c["caliber_path"])
	# Shotgun config
	_is_shotgun_weapon = c.get("is_shotgun", false)
	_pellet_count_min = c.get("pellet_count_min", 1)
	_pellet_count_max = c.get("pellet_count_max", 1)
	_spread_angle = c.get("spread_angle", 0.0)
	_spread_threshold = c.get("spread_threshold", 3); _initial_spread = c.get("initial_spread", 0.5); _spread_increment = c.get("spread_increment", 0.6); _max_spread = c.get("max_spread", 4.0); _spread_reset_time = c.get("spread_reset_time", 0.25)
	_is_melee_weapon = c.get("is_melee", false); _is_rpg_weapon = c.get("is_rpg", false)  # Issue #579 #583
	if c.has("total_magazines"): total_magazines = c["total_magazines"]  # #1033
	if c.has("reload_time"): reload_time = c["reload_time"]  # #1033
	if OS.is_debug_build(): print("[Enemy] Weapon: %s%s" % [WeaponConfigComponent.get_type_name(weapon_type), " (pellets=%d-%d)" % [_pellet_count_min, _pellet_count_max] if _is_shotgun_weapon else ""])

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

## Setup cover detection raycasts. Issue #1411: disabled by default, force_raycast_update() used on demand.
func _setup_cover_detection() -> void:
	for i in range(COVER_CHECK_COUNT):
		var raycast := RayCast2D.new()
		raycast.enabled = false  ## Issue #1411: avoids per-frame physics overhead
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

	_threat_sphere.area_entered.connect(_on_threat_area_entered)
	_threat_sphere.area_exited.connect(_on_threat_area_exited)

## Register as sound propagation listener (call_deferred for autoload init).
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

func _combat_waypoint(t: Vector2, r: bool = false) -> Vector2:  ## Issue #1227: nearest pre-defined combat path waypoint.
	var c: CombatPathComponent = get_tree().get_first_node_in_group("combat_path_components"); return (c.get_nearest_retreat_waypoint(global_position, t) if r else c.get_nearest_attacking_waypoint(global_position, t)) if c else Vector2.ZERO
## Unregister this enemy from sound propagation when dying or being destroyed.
func _unregister_sound_listener() -> void:
	var sound_propagation: Node = get_node_or_null("/root/SoundPropagation")
	if sound_propagation and sound_propagation.has_method("unregister_listener"):
		sound_propagation.unregister_listener(self)

## Unregister from SoundPropagation on scene change / node removal (Issue #1163: FPS fix). Prevents stale listener accumulation across level reloads.
func _exit_tree() -> void:
	_unregister_sound_listener()

## Called by SoundPropagation when a sound is heard. Delegates to on_sound_heard_with_intensity.
func on_sound_heard(sound_type: int, position: Vector2, source_type: int, source_node: Node2D) -> void:
	# Default to full intensity if called without intensity parameter
	on_sound_heard_with_intensity(sound_type, position, source_type, source_node, 1.0)

## Called by SoundPropagation with intensity. Reacts to reload/empty_click/gunshot sounds.
func on_sound_heard_with_intensity(sound_type: int, position: Vector2, source_type: int, source_node: Node2D, intensity: float) -> void:
	if not _is_alive: return
	var is_player_gunshot := sound_type == 0 and source_type == 0  # GUNSHOT from PLAYER (#910)
	if _memory_reset_confusion_timer > 0.0 and not is_player_gunshot: return  # #318 + #910: allow gunshots during confusion
	var distance := global_position.distance_to(position)

	# Handle reload sound (sound_type 3 = RELOAD) - player is vulnerable, propagates through walls.
	if sound_type == 3 and source_type == 0:  # RELOAD from PLAYER
		_log_debug("Heard player RELOAD (intensity=%.2f, distance=%.0f) at %s" % [intensity, distance, position])
		_log_to_file("Heard player RELOAD at %s, intensity=%.2f, distance=%.0f" % [position, intensity, distance])
		_goap_world_state["player_reloading"] = true
		_last_known_player_position = position
		_pursuing_vulnerability_sound = true
		_on_vulnerable_sound_heard_for_grenade(position)  # Issue #363
		if _memory: _memory.update_position(position, SOUND_RELOAD_CONFIDENCE)  # Issue #297
		if _current_state in [AIState.IDLE, AIState.IN_COVER, AIState.SUPPRESSED, AIState.RETREATING, AIState.SEEKING_COVER, AIState.SEARCHING]:  # Issue #921
			_log_to_file("Vulnerability sound triggered pursuit - transitioning from %s to PURSUING" % AIState.keys()[_current_state])
			_transition_to_pursuing()
		if _suppressive_fire: _suppressive_fire.try_shoot_on_sound(_player, position, "RELOAD")  # Issue #910
		return

	# Handle empty click sound (sound_type 5 = EMPTY_CLICK) - player is vulnerable, propagates through walls.
	if sound_type == 5 and source_type == 0:  # EMPTY_CLICK from PLAYER
		_log_debug("Heard player EMPTY_CLICK (intensity=%.2f, distance=%.0f) at %s" % [intensity, distance, position])
		_log_to_file("Heard player EMPTY_CLICK at %s, intensity=%.2f, distance=%.0f" % [position, intensity, distance])
		_goap_world_state["player_ammo_empty"] = true
		_last_known_player_position = position
		_pursuing_vulnerability_sound = true
		_on_vulnerable_sound_heard_for_grenade(position)  # Issue #363
		if _memory: _memory.update_position(position, SOUND_EMPTY_CLICK_CONFIDENCE)  # Issue #297
		if _current_state in [AIState.IDLE, AIState.IN_COVER, AIState.SUPPRESSED, AIState.RETREATING, AIState.SEEKING_COVER, AIState.SEARCHING]:  # Issue #921
			_log_to_file("Vulnerability sound triggered pursuit - transitioning from %s to PURSUING" % AIState.keys()[_current_state])
			_transition_to_pursuing()
		if _suppressive_fire: _suppressive_fire.try_shoot_on_sound(_player, position, "EMPTY_CLICK")  # Issue #910
		return

	# Issue #426: Handle grenade landing sound (GRENADE_LANDING) - evade if heard nearby
	if sound_type == 7 and _current_state != AIState.EVADING_GRENADE and _grenade_avoidance:
		_log_to_file("Heard GRENADE_LANDING at %s, intensity=%.2f" % [position, intensity])
		if _grenade_avoidance.trigger_evasion_from_sound(position, source_node):
			_pre_evasion_state = _current_state; _current_state = AIState.EVADING_GRENADE
			_has_left_idle = true; _grenade_evasion_timer = 0.0
			_log_to_file("EVADING_GRENADE (from sound): escaping from %s" % position)
		return

	# Issue #693: Casing kick sound (CASING_KICK = 8) - same range as reload (900px)
	if sound_type == 8:
		_log_to_file("Heard CASING_KICK at %s, intensity=%.2f, dist=%.0f" % [position, intensity, distance])
		_last_known_player_position = position
		if _memory: _memory.update_position(position, SOUND_CASING_KICK_CONFIDENCE)
		if _current_state == AIState.IDLE and _has_left_idle: _transition_to_pursuing()  # #1216: only re-pursue if previously engaged
		if _suppressive_fire: _suppressive_fire.try_shoot_on_sound(_player, position, "CASING_KICK")  # Issue #910
		return

	# Handle reload complete sound (sound_type 6 = RELOAD_COMPLETE) - player no longer vulnerable.
	if sound_type == 6 and source_type == 0:  # RELOAD_COMPLETE from PLAYER
		_log_debug("Heard player RELOAD_COMPLETE (intensity=%.2f, dist=%.0f) at %s" % [intensity, distance, position])
		_log_to_file("Heard player RELOAD_COMPLETE at %s, intensity=%.2f, dist=%.0f" % [position, intensity, distance])
		_goap_world_state["player_reloading"] = false
		_goap_world_state["player_ammo_empty"] = false
		_pursuing_vulnerability_sound = false
		# React with 200ms delay to give player a brief window, then transition cautious/defensive.
		if _current_state in [AIState.PURSUING, AIState.COMBAT, AIState.ASSAULT]:
			var state_before_delay := _current_state
			_log_to_file("Reload complete sound heard - waiting 200ms before cautious transition from %s" % AIState.keys()[_current_state])
			await get_tree().create_timer(0.2).timeout
			if not is_inside_tree() or not _is_alive: return  # Issue #1334 Round 11: guard freed node
			if _current_state in [AIState.PURSUING, AIState.COMBAT, AIState.ASSAULT]:
				if _shield_component and _shield_component.is_active(): pass  # Issue #1242: no retreat with shield up
				elif _has_valid_cover:
					_log_to_file("Reload complete sound triggered retreat - transitioning from %s to RETREATING (delayed from %s)" % [AIState.keys()[_current_state], AIState.keys()[state_before_delay]])
					_transition_to_retreating()
				elif enable_cover:
					_log_to_file("Reload complete sound triggered cover seek - transitioning from %s to SEEKING_COVER (delayed from %s)" % [AIState.keys()[_current_state], AIState.keys()[state_before_delay]])
					_transition_to_seeking_cover()
		return

	# Issue #805: Handle GUNSHOT (0) and EXPLOSION (1) sounds - both alert enemies similarly
	if sound_type != 0 and sound_type != 1:
		return

	# React based on current state (#910, #1261: intensity must not gate reaction — propagation_distance is the authoritative range check).
	var should_react := (_current_state == AIState.IDLE) or (_current_state in [AIState.FLANKING, AIState.RETREATING] and intensity >= 0.3)
	if is_player_gunshot and _current_state in [AIState.SEARCHING, AIState.PURSUING, AIState.IN_COVER, AIState.COMBAT]: should_react = true
	if not should_react: return

	var sound_name := "EXPLOSION" if sound_type == 1 else "gunshot"
	_log_debug("Heard %s (intensity=%.2f, distance=%.0f) at %s" % [sound_name, intensity, distance, position])
	_log_to_file("Heard %s at %s, intensity=%.2f, distance=%.0f" % [sound_name, position, intensity, distance])

	if sound_type == 0: _on_gunshot_heard_for_grenade(position)  # #363: sustained fire detection

	_last_known_player_position = position
	if _memory:
		_memory.update_position(position, SOUND_GUNSHOT_CONFIDENCE)
	if sound_type == 0 and source_type == 0 and _prediction and source_node and is_instance_valid(source_node):
		var sd := (position - source_node.global_position).normalized()
		_prediction.record_player_shot(sd)
		_memory.update_shot_direction(sd)
	_transition_to_combat()
	if sound_type == 0 and source_type == 0 and _suppressive_fire: _suppressive_fire.try_shoot_on_sound(_player, position, "GUNSHOT")  # Issue #910
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
		"confidence_low": false,
		# Grenade avoidance state (Issue #407)
		"in_grenade_danger_zone": false,
		# Ally death observation state (Issue #409)
		"witnessed_ally_death": false,
		"has_prediction": false, "prediction_confidence": 0.0,  # [#298]
		# Flashlight detection states (Issue #574)
		"flashlight_detected": false,
		"passage_lit_by_flashlight": false,
		"grenadier_throw_ready": false  # Issue #657: Grenadier GOAP throw
	}

## Initialize the enemy memory, prediction, and flashlight detection systems (Issue #297, #298, #574).
func _initialize_memory() -> void:
	_memory = EnemyMemory.new()
	var es: Node = get_node_or_null("/root/ExperimentalSettings")
	if es and es.has_method("is_ai_prediction_enabled") and es.is_ai_prediction_enabled():
		_prediction = PlayerPredictionComponent.new()
		_prediction.debug_logging = debug_logging
	# [Issue #574] Initialize flashlight detection component
	_flashlight_detection = FlashlightDetectionComponent.new()
	_flashlight_detection.debug_logging = debug_logging

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

## Update BFF companion reference and select best target — delegates to BffTargetingComponent (#934).
func _find_companion() -> void:
	_bff_targeting.find_companion()
	_companion = _bff_targeting.companion
func _select_best_target() -> void:
	_bff_targeting.select_best_target(_player, _can_see_player)
	_current_target = _bff_targeting.current_target

func _physics_process(delta: float) -> void:
	if not _is_alive:
		return

	# Issue #1334 Round 8-9: Freeze all enemy AI when player is dead or freed to prevent
	# native crashes from physics queries on dead/freed player nodes.
	var _gm_r9: Node = get_node_or_null("/root/GameManager")
	if _gm_r9 and not _gm_r9.player_alive: return
	if _player and not is_instance_valid(_player): _player = null; return

	# Issue #1186: performance toggles - skip AI if disabled; per-state filter applied below
	var _perf_settings: Node = get_node_or_null("/root/PerformanceSettings")
	if _perf_settings and not _perf_settings.is_ai_enabled(): return
	if _drone_operator and _drone_operator.get_phase() != DroneOperatorComponent.Phase.ACTIVE:  # Issue #1397: drone operator phase control
		_drone_operator.update(delta)
		if _drone_operator.is_controlling_drone(): velocity = Vector2.ZERO; move_and_slide(); return  # CONTROLLING: fully frozen
		if _current_state == AIState.SEEKING_COVER: _process_seeking_cover_state(delta)  # DEPLOYING: seek cover only, no combat
		elif _current_state != AIState.IN_COVER: _transition_to_seeking_cover()
		move_and_slide(); return
	if _flashbang_status: _flashbang_status.update(delta)  # Issue #432
	if _pacifist and _pacifist.update(delta): _log_to_file("[#959] Pacifist retaliation ended"); if _current_state != AIState.PACIFIST: _transition_to_pacifist(false)  # Issue #959
	if _invisibility: _invisibility.update(delta)  # Issue #1121: tick re-cloak timer
	_shoot_timer += delta
	if _is_bolt_cycling:  # [#1177] 4-step sniper bolt cycle
		_bolt_cycle_timer += delta
		if _bolt_cycle_timer >= (SNIPER_BOLT_STEP_DELAYS[_bolt_cycle_step - 1] if _bolt_cycle_step >= 1 and _bolt_cycle_step <= 4 else SNIPER_BOLT_CYCLE_DELAY):
			_bolt_cycle_timer = 0.0; var audio: Node = get_node_or_null("/root/AudioManager")
			if audio and audio.has_method("play_asvk_bolt_step"): audio.play_asvk_bolt_step(_bolt_cycle_step)
			if _bolt_cycle_step >= 4: _is_bolt_cycling = false; _bolt_cycle_step = 0
			else: _bolt_cycle_step += 1
	_spread_timer += delta; if _spread_timer >= _spread_reset_time and _spread_reset_time > 0.0: _shot_count = 0  # Issue #516
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

	# Issue #367: Stuck detection for PURSUING/FLANKING — force SEARCHING if no progress.
	# Skip when in direct contact (can hit player) or intentionally yielding (#1249).
	if _current_state == AIState.PURSUING or _current_state == AIState.FLANKING:
		var moved_distance := global_position.distance_to(_global_stuck_last_position)
		if moved_distance < GLOBAL_STUCK_DISTANCE_THRESHOLD:
			if not (_can_see_player and _can_hit_player_from_current_position()) \
					and not (_tactical_movement and _tactical_movement.is_yielding):
				_global_stuck_timer += delta
				var _experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
				var _effective_stuck_max_time: float = GLOBAL_STUCK_MAX_TIME
				if _experimental_settings != null and _experimental_settings.has_method("get_global_stuck_max_time"):
					_effective_stuck_max_time = _experimental_settings.get_global_stuck_max_time()
				if _global_stuck_timer >= _effective_stuck_max_time:
					_log_to_file("GLOBAL STUCK: pos=%s for %.1fs without player contact, State: %s -> SEARCHING" % [global_position, _global_stuck_timer, AIState.keys()[_current_state]])
					_global_stuck_timer = 0.0
					_global_stuck_last_position = global_position
					# Reset flanking state if applicable
					if _current_state == AIState.FLANKING:
						_flank_side_initialized = false
						_flank_fail_count += 1
						_flank_cooldown_timer = FLANK_COOLDOWN_DURATION
					# #1249 session 4: search from last known player position, not the stuck position.
					# When stuck while pursuing, the enemy may be far from the player; searching from
					# the stuck spot wastes time. Use the last known player position instead if available.
					var _search_start := global_position
					if _last_known_player_position != Vector2.ZERO:
						_search_start = _last_known_player_position
					_transition_to_searching(_search_start)
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
	# Issue #934: Check BFF companion as secondary threat target
	_find_companion()
	_check_companion_visibility()
	_select_best_target()
	_update_memory(delta)
	_update_goap_state()
	_update_suppression(delta); if _force_field_component: _force_field_component.update(delta, (_can_see_player and _player != null) or (_can_see_companion and _companion != null)); if _shield_component: _shield_component.update(delta); if _drone_operator: _drone_operator.update(delta)  # Issues #1034, #1242, #1397
	if _hit_reaction_timer > 0: _hit_reaction_timer -= delta  # Issue #1242: decay hit reaction rotation timer
	# Issue #1242: delayed player tracking for shield enemy — update facing angle periodically, not continuously
	if _shield_component and _shield_component.is_active():
		_shield_tracking_timer -= delta
		if _shield_tracking_timer <= 0.0 and _current_target and is_instance_valid(_current_target):
			_shield_tracking_angle = (_current_target.global_position - global_position).normalized().angle()
			_shield_tracking_timer = SHIELD_TRACKING_INTERVAL
			_log_to_file("SHIELD_TRACK: updated facing to %.1f° (interval=%.1fs)" % [rad_to_deg(_shield_tracking_angle), SHIELD_TRACKING_INTERVAL])
	_update_grenade_triggers(delta)
	_update_grenade_danger_detection()  # Issue #407: Check for nearby grenades
	if _teleport_component: _teleport_component.update(delta)  # Issue #752: Advance teleport cooldown
	if _machete: _machete.update(delta)  # Issue #579: Update machete component
	_check_pacifism_spread()  # Issue #959: Level 5+ — spread pacifism on first sight of a pacifist

	if _waiting_for_grenadier:  # Issue #604: Allies wait for grenadier's grenade
		_grenadier_wait_timer -= delta
		if _grenadier_wait_timer <= 0.0: _stop_waiting_for_grenadier()
	_update_enemy_model_rotation()
	if _waiting_for_grenadier:  # Issue #604: Skip AI while waiting
		velocity = Vector2.ZERO; _update_debug_label(); _update_walk_animation(delta)
		_apply_machete_attack_animation(); move_and_slide(); _push_casings()
		if debug_label_enabled:
			_debug_draw_timer += delta
			if _debug_draw_timer >= DEBUG_DRAW_INTERVAL: _debug_draw_timer = 0.0; queue_redraw()  # Issue #1220: throttle to 10 Hz
		return
	_process_ai_state(delta)

	_update_debug_label()
	if debug_label_enabled:  # Issue #1220: throttle FOV cone redraws to 10 Hz (was every frame → 33 raycasts/enemy/frame at 60 fps)
		_debug_draw_timer += delta
		if _debug_draw_timer >= DEBUG_DRAW_INTERVAL: _debug_draw_timer = 0.0; queue_redraw()

	_update_walk_animation(delta)  # Update walking animation based on movement
	_apply_machete_attack_animation()  # Issue #595: machete swing animation
	# Issue #1146: Apply separation force to prevent enemies from overlapping each other.
	if _is_alive:
		velocity = _apply_separation_force(velocity, delta)
		if _shield_component: velocity *= _shield_component.get_speed_multiplier()  # Issue #1242: shield halves speed
	if _knockback_velocity.length() > 1.0: velocity += _knockback_velocity; _knockback_velocity *= exp(-8.0 * delta)  # Issue #1242: knockback decay
	elif _knockback_velocity != Vector2.ZERO: _knockback_velocity = Vector2.ZERO
	move_and_slide()

	# Push any casings we collided with (Issue #341)
	_push_casings()

## Update GOAP world state based on current conditions.
func _update_goap_state() -> void:
	# Issue #934: player_visible/player_close/can_hit_from_cover reflect the best target
	# (either the main player or the BFF companion, whichever is more accessible).
	_goap_world_state["player_visible"] = _can_see_player or _can_see_companion
	_goap_world_state["under_fire"] = _under_fire
	_goap_world_state["health_low"] = _get_health_percent() < 0.5
	_goap_world_state["in_cover"] = _current_state == AIState.IN_COVER
	_goap_world_state["has_cover"] = _has_valid_cover
	_goap_world_state["is_retreating"] = _current_state == AIState.RETREATING
	_goap_world_state["hits_taken"] = _hits_taken_in_encounter
	_goap_world_state["is_pursuing"] = _current_state == AIState.PURSUING
	_goap_world_state["is_assaulting"] = _current_state == AIState.ASSAULT
	_goap_world_state["player_close"] = _is_target_close()
	_goap_world_state["can_hit_from_cover"] = _can_hit_target_from_current_position()
	_goap_world_state["enemies_in_combat"] = _count_enemies_in_combat()
	_goap_world_state["player_distracted"] = _is_player_distracted()

	# Memory system states (Issue #297)
	if _memory:
		_goap_world_state["has_suspected_position"] = _memory.has_target()
		_goap_world_state["position_confidence"] = _memory.confidence
		_goap_world_state["confidence_high"] = _memory.is_high_confidence()
		_goap_world_state["confidence_medium"] = _memory.is_medium_confidence()
		_goap_world_state["confidence_low"] = _memory.is_low_confidence()

	# Grenade avoidance state (Issue #407)
	_goap_world_state["in_grenade_danger_zone"] = _grenade_avoidance.in_danger_zone if _grenade_avoidance else false

	# Ally death observation state (Issue #409)
	_goap_world_state["witnessed_ally_death"] = _witnessed_ally_death
	if _prediction:  # [#298]
		_goap_world_state["has_prediction"] = _prediction.has_predictions; _goap_world_state["prediction_confidence"] = _prediction.get_prediction_confidence()

	# Flashlight detection states (Issue #574)
	if _flashlight_detection:
		_goap_world_state["flashlight_detected"] = _flashlight_detection.detected
		# Check if the next navigation waypoint is lit by the flashlight
		_goap_world_state["passage_lit_by_flashlight"] = _flashlight_detection.is_next_waypoint_lit(_nav_agent, _player, _raycast) if _player else false
## Update model rotation (#347, #386, #397): priority player > combat/pursuit > corner > velocity > idle.
func _update_enemy_model_rotation() -> void:
	if not _enemy_model:
		return
	var target_angle: float
	var has_target := false
	var rotation_reason := ""  # Issue #397 debug: track which priority was used
	if _is_facing_for_grenade_throw and _grenade_throw_facing_direction != Vector2.ZERO:  # P0: Issue #712
		target_angle = _grenade_throw_facing_direction.angle(); has_target = true; rotation_reason = "P0:grenade_throw"
	elif _hit_reaction_timer > 0:  # P0.5: Issue #1242 — shield enemy slowly turns toward attacker after hit
		target_angle = _hit_reaction_angle; has_target = true; rotation_reason = "P0.5:hit_reaction"
	elif _current_target != null and (_can_see_player or _can_see_companion):  # P1: Face best target if visible
		if _shield_component and _shield_component.is_active():  # Issue #1242: delayed tracking — only update facing periodically, allowing flanking
			target_angle = _shield_tracking_angle; has_target = true; rotation_reason = "P1:shield_delayed"
		else:
			target_angle = (_current_target.global_position - global_position).normalized().angle(); has_target = true; rotation_reason = "P1:visible"
	elif _current_state in [AIState.COMBAT, AIState.PURSUING, AIState.FLANKING, AIState.SEARCHING, AIState.ASSAULT] and _current_target != null:  # P2: Combat states (#386, #397)
		if _shield_component and _shield_component.is_active():  # Issue #1242: delayed tracking in combat states too
			target_angle = _shield_tracking_angle; has_target = true; rotation_reason = "P2:shield_delayed"
		else:
			target_angle = (_current_target.global_position - global_position).normalized().angle(); has_target = true; rotation_reason = "P2:combat_state"
	elif _corner_check_timer > 0:  # P3: Corner check (#347)
		target_angle = _corner_check_angle; has_target = true; rotation_reason = "P3:corner"
	elif velocity.length_squared() > 1.0:
		if _shield_component and _shield_component.is_active():  # Issue #1242: shield uses delayed tracking angle while moving
			target_angle = _shield_tracking_angle; has_target = true; rotation_reason = "P4:shield_delayed"
		else: target_angle = velocity.normalized().angle(); has_target = true; rotation_reason = "P4:velocity"
	elif _current_state == AIState.IDLE and _idle_scan_targets.size() > 0:
		target_angle = _idle_scan_targets[_idle_scan_target_index]; has_target = true; rotation_reason = "P5:idle_scan"
	if not has_target:
		return
	# Issue #397 debug: Log rotation priority changes
	if rotation_reason != _last_rotation_reason:
		var ppos := "(%d,%d)" % [int(_player.global_position.x), int(_player.global_position.y)] if _player else "null"
		_log_to_file("ROT_CHANGE: %s -> %s, state=%s, target=%.1f°, current=%.1f°, player=%s, corner_timer=%.2f%s" % [_last_rotation_reason if _last_rotation_reason != "" else "none", rotation_reason, AIState.keys()[_current_state], rad_to_deg(target_angle), rad_to_deg(_enemy_model.global_rotation), ppos, _corner_check_timer, " [->companion]" if _current_target == _companion else ""])
		_last_rotation_reason = rotation_reason
	# Smooth rotation for visual polish (Issue #347)
	var delta := get_physics_process_delta_time()
	var current_rot := _enemy_model.global_rotation
	var angle_diff := wrapf(target_angle - current_rot, -PI, PI)
	var rot_speed := MODEL_ROTATION_SPEED * (_shield_component.get_rotation_multiplier() if _shield_component else 1.0)  # Issue #1242: shield slows turning
	if abs(angle_diff) <= rot_speed * delta:
		_enemy_model.global_rotation = target_angle
	elif angle_diff > 0:
		_enemy_model.global_rotation = current_rot + rot_speed * delta
	else: _enemy_model.global_rotation = current_rot - rot_speed * delta
	var aiming_left := absf(_enemy_model.global_rotation) > PI / 2
	_model_facing_left = aiming_left
	if aiming_left:
		_enemy_model.scale = Vector2(enemy_model_scale, -enemy_model_scale)
	else: _enemy_model.scale = Vector2(enemy_model_scale, enemy_model_scale)

## Forces model to face direction immediately; ensures weapon sprite matches intended aim direction.
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

## Issue #1242: Set hit reaction rotation target for shield enemy (slow turn toward attacker).
func _set_hit_reaction_target(dir: Vector2) -> void:
	if dir.length_squared() < 0.01: return
	_hit_reaction_angle = dir.angle(); _hit_reaction_timer = HIT_REACTION_DURATION
	# Issue #1242: also refresh delayed tracking angle on hit — enemy learns attacker direction
	if _shield_component and _shield_component.is_active():
		_shield_tracking_angle = _hit_reaction_angle; _shield_tracking_timer = SHIELD_TRACKING_INTERVAL
	_log_to_file("HIT_REACTION: target=%.1f°, timer=%.2fs" % [rad_to_deg(_hit_reaction_angle), _hit_reaction_timer])
## Issue #1242: Smooth body rotation respecting shield multiplier. Replaces instant `rotation = angle` for shield enemies.
func _rotate_body_toward(target_angle: float, delta: float) -> void:
	var spd := rotation_speed * (_shield_component.get_rotation_multiplier() if _shield_component and _shield_component.is_active() else 1.0)
	var diff := wrapf(target_angle - rotation, -PI, PI)
	if abs(diff) <= spd * delta: rotation = target_angle
	elif diff > 0: rotation += spd * delta
	else: rotation -= spd * delta
## Updates walking animation (bobbing motion for body parts). @param delta: Time since last frame.
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

## Push casings using Area2D detection (Issue #438, pattern from player Issue #392).
const CASING_PUSH_FORCE: float = 20.0  # Reduced from 50.0 for Issue #424

func _push_casings() -> void:
	if _casing_pusher == null or velocity.length_squared() < 1.0: return
	# Combine signal-tracked casings and polled bodies for reliable detection (Issue #438)
	var casings_to_push: Array[RigidBody2D] = []
	for casing in _overlapping_casings:
		if is_instance_valid(casing) and casing not in casings_to_push: casings_to_push.append(casing)
	for body in _casing_pusher.get_overlapping_bodies():
		if body is RigidBody2D and body.has_method("receive_kick") and body not in casings_to_push:
			casings_to_push.append(body)
	# Push casings away from enemy center (Issue #424)
	for casing: RigidBody2D in casings_to_push:
		var push_dir := (casing.global_position - global_position).normalized()
		casing.receive_kick(push_dir * velocity.length() * CASING_PUSH_FORCE / 100.0)

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
		# Only set under_fire after delay; Issues #1034, #1397: ignore if force field active; drone operator dashes instead.
		if _threat_reaction_delay_elapsed and not (_force_field_component and _force_field_component.is_active()):
			if _drone_operator and _drone_operator.should_dash_instead_of_suppress(): _drone_operator.try_dash_from_threat(_bullets_in_threat_sphere, _player, global_position)
			else: _under_fire = true; _suppression_timer = 0.0

## Update reload state.
func _update_reload(delta: float) -> void:
	if not _is_reloading: return
	if _revolver_component and _revolver_component.is_reloading_coroutine(): return  # [#1242] Revolver uses coroutine, not timer
	_reload_timer += delta
	if _reload_timer >= reload_time: _finish_reload()

## Start reloading the weapon.
func _start_reload() -> void:
	if _is_reloading or _reserve_ammo <= 0: return
	_is_reloading = true; _reload_timer = 0.0; reload_started.emit()
	_log_debug("Reloading... (%d reserve ammo)" % _reserve_ammo)
	if weapon_type == WeaponType.REVOLVER and enable_cover and _current_state not in [AIState.IN_COVER, AIState.SEEKING_COVER, AIState.EVADING_GRENADE]: _transition_to_seeking_cover()  # Issue #1242: revolver reloads in cover
	if _revolver_component and not _revolver_component.is_reloading_coroutine(): _revolver_component.start_reload_sequence()  # [#1242] Multi-step reload

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

## Check if the enemy can shoot (has ammo and not reloading). Machete: melee cooldown (Issue #579).
func _can_shoot() -> bool:
	if _drone_operator and _drone_operator.get_phase() != DroneOperatorComponent.Phase.ACTIVE: return false  # Issue #1397: no shooting during DEPLOYING/CONTROLLING
	if _is_melee_weapon: return _machete != null and _machete.is_attack_ready()
	if _is_reloading: return false

	if _current_ammo <= 0:
		if _reserve_ammo > 0: _start_reload()
		else:
			if not _goap_world_state.get("ammo_depleted", false):
				_goap_world_state["ammo_depleted"] = true; ammo_depleted.emit(); _log_debug("All ammunition depleted!")
				if weapon_type == WeaponType.MACHINE_GUN and not _machine_gunner_pm_active: _activate_machine_gunner_pm_fallback()  # #1033
		return false
	return true
## [#1033] Machine gunner corridor suppression: burst into corridor where player was last seen (no LOS needed).
func _machine_gunner_fire_at_corridor(target_pos: Vector2) -> void:
	if bullet_scene == null: return
	# Issue #1334 Round 5: Don't shoot at a dead player
	var _gm3 := get_node_or_null("/root/GameManager")
	if _gm3 and not _gm3.player_alive: return
	var to_target := (target_pos - global_position).normalized()
	if to_target == Vector2.ZERO: return
	# Face toward the corridor
	if _enemy_model: _enemy_model.global_rotation = to_target.angle()
	_rotate_body_toward(to_target.angle(), get_physics_process_delta_time())
	var spawn_pos := _get_bullet_spawn_position(to_target)
	# Small spread (±5°) to simulate suppressive corridor fire
	var spread := deg_to_rad(randf_range(-5.0, 5.0))
	var direction := to_target.rotated(spread)
	if not _is_bullet_spawn_clear(direction): return
	_spawn_projectile(direction, spawn_pos)
	_spawn_muzzle_flash(spawn_pos, direction)
	_spawn_casing(direction, to_target)
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play_ak_shot"): audio.play_ak_shot(global_position)
	var sp: Node = get_node_or_null("/root/SoundPropagation")
	var _now_mg := Time.get_ticks_msec() / 1000.0
	if sp and sp.has_method("emit_sound") and _now_mg - _last_gunshot_propagation_time >= ENEMY_GUNSHOT_PROPAGATION_COOLDOWN:
		sp.emit_sound(0, global_position, 1, self, weapon_loudness)
		_last_gunshot_propagation_time = _now_mg
	_play_delayed_shell_sound()
	_shoot_timer = 0.0
	_current_ammo -= 1; _shot_count += 1
	ammo_changed.emit(_current_ammo, _reserve_ammo)
	_log_to_file("[#1033] MG corridor suppression: fired at passage %s, ammo=%d" % [target_pos, _current_ammo])
	if _current_ammo <= 0 and _reserve_ammo > 0: _start_reload()
	elif _current_ammo <= 0 and _reserve_ammo <= 0 and not _machine_gunner_pm_active: _activate_machine_gunner_pm_fallback()

## [#1033] Machine gunner PM fallback: switch to RIFLE-config sidearm and retreat to distant cover.
func _activate_machine_gunner_pm_fallback() -> void:
	_machine_gunner_pm_active = true; _machine_gunner_suppressing_corridor = false
	weapon_type = WeaponType.RIFLE; _configure_weapon_type()
	magazine_size = 8; total_magazines = 2; _current_ammo = magazine_size; _reserve_ammo = magazine_size
	_is_reloading = false; _reload_timer = 0.0; _goap_world_state["ammo_depleted"] = false
	_find_distant_cover_position()  # [#1033] Retreat to DISTANT cover, not closest
	_log_to_file("[#1033] Machine gunner belts empty — switched to PM, retreating to distant cover"); _transition_to_retreating()

## [#1033] Find cover far from player for machine gunner PM fallback (prefers hidden + far, opposite of normal).
func _find_distant_cover_position() -> void:
	if _player == null: _has_valid_cover = false; return
	var current_time := Time.get_ticks_msec() / 1000.0  ## Issue #1411: throttle
	if current_time - _last_distant_cover_search_time < COVER_SEARCH_COOLDOWN: return  ## Issue #1411: cooldown applies even without valid cover
	_last_distant_cover_search_time = current_time; var player_pos := _player.global_position
	var best_cover: Vector2 = Vector2.ZERO; var best_score: float = -INF; var found_hidden: bool = false
	for i in range(COVER_CHECK_COUNT):
		var raycast := _cover_raycasts[i]
		raycast.target_position = Vector2.from_angle((float(i) / COVER_CHECK_COUNT) * TAU) * COVER_CHECK_DISTANCE
		raycast.force_raycast_update()
		if not raycast.is_colliding(): continue
		var cover_pos := raycast.get_collision_point() + raycast.get_collision_normal() * 35.0
		if is_teleporter and global_position.distance_to(cover_pos) < 10.0: continue  # Issue #1355
		if not _can_reach_position(cover_pos): continue
		var is_hidden := not _is_position_visible_from_player(cover_pos)
		if not is_hidden and found_hidden: continue
		var dist_to_player := cover_pos.distance_to(player_pos)
		var total_score := (10.0 if is_hidden else 0.0) + dist_to_player / COVER_CHECK_DISTANCE
		if is_hidden and not found_hidden: found_hidden = true; best_score = total_score; best_cover = cover_pos
		elif (is_hidden or not found_hidden) and total_score > best_score: best_score = total_score; best_cover = cover_pos
	if best_score > 0:
		_cover_position = best_cover; _has_valid_cover = true
		_log_to_file("[#1033] Distant cover found at %s (dist_to_player=%.0f)" % [best_cover, best_cover.distance_to(player_pos)])
	else:
		_find_cover_position()  # Fallback to normal cover search

## Process the AI state machine.
func _process_ai_state(delta: float) -> void:
	# If stunned, stop all movement and actions - do nothing
	if _is_stunned:
		velocity = Vector2.ZERO
		return
	if _formation_shielder != null and (not is_instance_valid(_formation_shielder) or not _formation_shielder.has_method("is_shield_active") or not _formation_shielder.is_shield_active()): _formation_shielder = null  # Issue #1242
	if _formation_shielder != null: _move_to_target_nav(_formation_target_pos, move_speed); return
	var previous_state := _current_state

	# ABSOLUTE HIGHEST PRIORITY: Grenade danger zone evasion (Issue #407)
	var in_grenade_danger := _grenade_avoidance.in_danger_zone if _grenade_avoidance else false
	if in_grenade_danger and _current_state != AIState.EVADING_GRENADE:
		_log_to_file("GRENADE DANGER: Entering EVADING_GRENADE state from %s" % AIState.keys()[_current_state])
		_transition_to_evading_grenade()
		return

	if _aggression and _aggression.process_aggression_tick(delta, rotation_speed, shoot_cooldown, combat_move_speed): return  # [Issue #675,#919]

	# Issue #1305: Check if COMBAT state is enabled — if disabled, skip all priority attack paths
	# (distracted, vulnerable, etc.) so enemies truly stop attacking the player.
	var _ps_ai := get_node_or_null("/root/PerformanceSettings")
	var _combat_allowed: bool = _ps_ai == null or _ps_ai.is_ai_state_combat_enabled()

	# HIGHEST PRIORITY: Player distracted (aim > 23° off) → shoot (Hard only; Issue #318: off during confusion).
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	var is_distraction_enabled: bool = difficulty_manager != null and difficulty_manager.is_distraction_attack_enabled()
	var is_confused: bool = _memory_reset_confusion_timer > 0.0
	if _combat_allowed and is_distraction_enabled and not is_confused and not (_pacifist and _pacifist.is_pacifist) and _goap_world_state.get("player_distracted", false) and _can_see_player and _player and is_instance_valid(_player):
		# Check if we have a clear shot (no wall blocking bullet spawn)
		var direction_to_player := (_player.global_position - global_position).normalized()
		var has_clear_shot := _is_bullet_spawn_clear(direction_to_player)
		if has_clear_shot and _can_shoot() and _shoot_timer >= shoot_cooldown:
			_log_to_file("Player distracted - priority attack triggered")
			_rotate_body_toward(direction_to_player.angle(), delta)  # Issue #1242: shield respects rotation modifier
			if _shield_component and _shield_component.get_rotation_multiplier() < 1.0: _set_hit_reaction_target(direction_to_player)  # Issue #1242: shield enemy slowly aims
			else: _force_model_to_face_direction(direction_to_player)  # Fix issue #264: ensure correct aim
			_shoot()
			_shoot_timer = 0.0
			_detection_delay_elapsed = true
			if _current_state == AIState.IDLE:
				_transition_to_combat()
				_detection_delay_elapsed = true

			# Return early - we've taken the highest priority action
			# The state machine will continue normally in the next frame
			return

	# HIGHEST PRIORITY: Attack immediately if player is reloading or out of ammo (Issue #318)
	var player_reloading: bool = _goap_world_state.get("player_reloading", false)
	var player_ammo_empty: bool = _goap_world_state.get("player_ammo_empty", false)
	var player_is_vulnerable: bool = player_reloading or player_ammo_empty
	var player_close: bool = _is_player_close()

	# Debug log when player is vulnerable (but not every frame - only when conditions change)
	if player_is_vulnerable and _player:
		var distance_to_player := global_position.distance_to(_player.global_position)
		_log_debug("Vulnerable check: reloading=%s, ammo_empty=%s, can_see=%s, close=%s (dist=%.0f)" % [player_reloading, player_ammo_empty, _can_see_player, player_close, distance_to_player])

	if player_is_vulnerable and _player and not (player_close and _can_see_player):
		var distance_to_player := global_position.distance_to(_player.global_position)
		var vuln_key := "last_vuln_log_frame"
		var current_frame := Engine.get_physics_frames()
		var last_log_frame: int = _goap_world_state.get(vuln_key, -100)
		if current_frame - last_log_frame > 30:  # Log at most every 30 frames (~0.5s)
			_goap_world_state[vuln_key] = current_frame
			var reason: String = "reloading" if player_reloading else "ammo_empty"
			_log_to_file("Player vulnerable (%s) but cannot attack: close=%s (dist=%.0f), can_see=%s" % [reason, player_close, distance_to_player, _can_see_player])

	# Issue #318: block during confusion; Issue #959: pacifists skip; Issue #1305: respect combat toggle
	if _combat_allowed and player_is_vulnerable and not is_confused and not (_pacifist and _pacifist.is_pacifist) and _can_see_player and _player and player_close:
		var direction_to_player := (_player.global_position - global_position).normalized()
		var has_clear_shot := _is_bullet_spawn_clear(direction_to_player)
		if has_clear_shot and _can_shoot() and _shoot_timer >= shoot_cooldown:
			var reason: String = "reloading" if player_reloading else "empty ammo"
			_log_to_file("Player %s - priority attack triggered" % reason)

			_rotate_body_toward(direction_to_player.angle(), delta)  # Issue #1242: shield respects rotation modifier
			if _shield_component and _shield_component.get_rotation_multiplier() < 1.0: _set_hit_reaction_target(direction_to_player)  # Issue #1242: shield slowly aims
			else: _force_model_to_face_direction(direction_to_player)  # Issue #264: correct aim direction
			_shoot(); _shoot_timer = 0.0
			_detection_delay_elapsed = true
			if _current_state == AIState.IDLE:
				_transition_to_combat()
				_detection_delay_elapsed = true
			return

	# SECOND PRIORITY: pursue vulnerable player who is not close (Issue #1305: respect combat toggle)
	if _combat_allowed and player_is_vulnerable and _can_see_player and _player and not player_close:
		var distance_to_player := global_position.distance_to(_player.global_position)
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
	if _teleport_component and _teleport_component.is_ready() and _under_fire and _current_state != AIState.IN_COVER:  # #752: cover-teleport
		if not _has_valid_cover: _find_cover_position()
		if _has_valid_cover and _teleport_component.try_teleport(_cover_position): _transition_to_in_cover(); return
	if _teleport_component and _teleport_component.is_ready() and not _can_see_player and _current_state == AIState.FLANKING: _teleport_component.try_teleport(_flank_target)  # #752: flank-teleport
	# GRENADE THROW PRIORITY (Issue #363, #959, #1305): Non-pacifists check grenade triggers; respect combat toggle.
	if _combat_allowed and _goap_world_state.get("ready_to_throw_grenade", false) and not (_pacifist and _pacifist.is_pacifist):
		if try_throw_grenade():
			return

	# State transitions based on conditions
	match _current_state:
		AIState.IDLE: _process_idle_state(delta)
		AIState.COMBAT: _process_combat_state(delta)
		AIState.SEEKING_COVER: _process_seeking_cover_state(delta)
		AIState.IN_COVER: _process_in_cover_state(delta)
		AIState.FLANKING: _process_flanking_state(delta)
		AIState.SUPPRESSED: _process_suppressed_state(delta)
		AIState.RETREATING: _process_retreating_state(delta)
		AIState.PURSUING: _process_pursuing_state(delta)
		AIState.ASSAULT: _process_assault_state(delta)
		AIState.SEARCHING: _process_searching_state(delta)
		AIState.EVADING_GRENADE: _process_evading_grenade_state(delta)
		AIState.PACIFIST: _process_pacifist_state(delta)
	if previous_state != _current_state:
		state_changed.emit(_current_state)
		_log_debug("State changed: %s -> %s" % [AIState.keys()[previous_state], AIState.keys()[_current_state]])
		# Also log to file for exported build debugging
		_log_to_file("State: %s -> %s" % [AIState.keys()[previous_state], AIState.keys()[_current_state]])

## Process IDLE state - patrol or guard behavior.
func _process_idle_state(delta: float) -> void:
	# Issue #934: also enter combat when companion is visible
	if (_can_see_player and _player) or (_can_see_companion and _companion != null):
		if _is_melee_weapon: _transition_to_pursuing()  # Issue #579: machete sneaks first
		else: _transition_to_combat()
		return

	# Issue #297/#1216: re-pursue from memory only if enemy has previously engaged (gate on _has_left_idle).
	if _has_left_idle and _memory and _memory.has_target():
		if _memory.is_high_confidence():
			_log_debug("High confidence (%.0f%%) - investigating suspected position" % (_memory.confidence * 100))
			_log_to_file("Memory: high confidence (%.2f) - transitioning to PURSUING" % _memory.confidence)
			_transition_to_pursuing(); return
		elif _memory.is_medium_confidence():
			_log_debug("Medium confidence (%.0f%%) - cautiously investigating" % (_memory.confidence * 100))
			_log_to_file("Memory: medium confidence (%.2f) - transitioning to PURSUING" % _memory.confidence)
			_transition_to_pursuing(); return
		# Low confidence: Continue normal patrol
	# Execute idle behavior
	match behavior_mode:
		BehaviorMode.PATROL: _process_patrol(delta)
		BehaviorMode.GUARD: _process_guard(delta)

## Process COMBAT state - cycle: approach->exposed shooting (2-3s)->return to cover via SEEKING_COVER.
func _process_combat_state(delta: float) -> void:
	_combat_state_timer += delta
	# Issue #579/#595: Machete melee combat with attack animation
	if _is_melee_weapon and _machete and _player:
		if _machete.is_attacking(): return  # Issue #595: Hold position during attack animation
		if _under_fire and _bullets_in_threat_sphere.size() > 0 and not _machete.is_dodging():
			var b = _bullets_in_threat_sphere[0]
			if is_instance_valid(b):
				var bd: Vector2 = b.get("direction") if b.get("direction") != null else Vector2.RIGHT.rotated(b.rotation)
				_machete.try_dodge(bd)
		if _machete.is_dodging(): velocity = _machete.get_dodge_velocity(); return
		if _machete.is_in_melee_range(_player) and _shoot_timer >= shoot_cooldown and _machete.is_melee_path_clear(_player):  # Issue #1083: block melee through walls
			_machete.perform_melee_attack(_player); _shoot_timer = 0.0; _machete_combat_stuck_timer = 0.0; _machete_combat_stuck_last_pos = global_position; return
		var tp := _player.global_position
		if _machete.is_backstab_opportunity(_player) or _machete.is_player_under_fire(_player): tp = _machete.get_backstab_approach_position(_player, 60.0)
		_move_to_target_nav(tp, combat_move_speed)
		if global_position.distance_to(_machete_combat_stuck_last_pos) < MACHETE_COMBAT_STUCK_DIST_THRESHOLD:  # Issue #1107: Wall-stuck detection
			_machete_combat_stuck_timer += delta
			if _machete_combat_stuck_timer >= MACHETE_COMBAT_STUCK_MAX_TIME:
				_log_to_file("[#1107] Machete COMBAT stuck (%.1fs), rerouting" % _machete_combat_stuck_timer)
				_machete_combat_stuck_timer = 0.0; _machete_combat_stuck_last_pos = global_position; _transition_to_pursuing()
		else: _machete_combat_stuck_timer = 0.0; _machete_combat_stuck_last_pos = global_position
		return
	# [#1033] Machine gunner: suppress corridor (fire at last-known pos regardless of LOS/under-fire).
	if weapon_type == WeaponType.MACHINE_GUN and not _machine_gunner_pm_active:
		var suppress_target := _player.global_position if (_can_see_player and _player != null) else _last_known_player_position
		if suppress_target != Vector2.ZERO:
			_machine_gunner_suppressing_corridor = true
			if not _is_reloading and _shoot_timer >= shoot_cooldown and _can_shoot():
				_machine_gunner_fire_at_corridor(suppress_target)
			return  # Hold position; belt depletion triggers PM fallback + retreat
		_machine_gunner_suppressing_corridor = false

	if weapon_type == WeaponType.SNIPER_RIFLE and _sniper_component != null:  # [#1163] Standoff + blind-fire through cover.
		_sniper_component.process_combat(delta, _can_see_player, _player, _last_known_player_position, _prediction); return
	# RCA-19: Add minimum combat duration before retreating to prevent rapid COMBAT→RETREATING cycling
	if _under_fire and enable_cover and not _pursuing_vulnerability_sound and not (_shield_component and _shield_component.is_active()):  # Issue #1242: no retreat with shield up
		if _combat_state_timer >= 0.15:  # Brief minimum (0.15s) to prevent instant cycling
			_combat_exposed = false
			_combat_approaching = false
			_seeking_clear_shot = false
			_transition_to_retreating()
		return

	# If can't see player, pursue (after min duration to prevent rapid thrashing) - Issue #169
	if not _can_see_player:
		if _combat_state_timer >= COMBAT_MIN_DURATION_BEFORE_PURSUE:
			_combat_exposed = false
			_combat_approaching = false
			_seeking_clear_shot = false
			_log_debug("Lost sight of player in COMBAT (%.2fs), transitioning to PURSUING" % _combat_state_timer)
			_transition_to_pursuing()
			return
		if _suppressive_fire: _suppressive_fire.try_suppress_pursuing(_can_see_player, _last_known_player_position, _is_melee_weapon, _player, _is_reloading, _shoot_timer, shoot_cooldown)  # Issue #910

	# Issue #1353: Gas mask enemy continuously tries to throw chemical grenades during combat
	if is_gas_mask and _gas_mask_grenade and _gas_mask_grenade.has_grenades() and _player and not _gas_mask_grenade.is_throwing():
		_gas_mask_grenade.try_throw(_player.global_position)

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
				_rotate_body_toward(direction_to_player.angle(), delta)  # Issue #1242: shield respects rotation modifier
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
			_rotate_body_toward(direction_to_player.angle(), delta)  # Issue #1242: shield respects rotation modifier

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

	if _is_rpg_weapon and not _rpg_fired and has_clear_shot:  # Issue #583: RPG fires immediately at max range (no approach, no detection delay)
		_aim_at_player()
		if _shoot_timer >= shoot_cooldown: _log_debug("RPG: firing rocket (dist=%.0f)" % distance_to_player); _shoot(); _shoot_timer = 0.0  # reset only after shot
		return

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
		_rotate_body_toward(direction_to_player.angle(), delta)  # Issue #1242: shield respects rotation modifier

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

		# Score: clear path + clear bullet spawn
		var score: float = 0.0
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
	var time_in_state := Time.get_ticks_msec() / 1000.0 - _seeking_cover_entry_time  # Issue #997 RCA-17
	if not _has_valid_cover:
		_find_cover_position()
		if not _has_valid_cover:
			if time_in_state >= SEEKING_COVER_MIN_DURATION: _transition_to_combat()  # RCA-17: min duration
			return

	# RCA-19: Only transition after minimum duration to prevent rapid cycling; also main goal: hidden.
	if not _is_visible_from_player():
		if time_in_state >= SEEKING_COVER_MIN_DURATION:
			_transition_to_in_cover()
			_log_debug("Hidden from player, entering cover state")
		return

	# Move towards cover
	var distance: float = global_position.distance_to(_cover_position)

	if distance < 10.0:
		# Reached the cover position, but still visible - try to find better cover
		## Issue #1411: don't invalidate current cover before searching — keep it as fallback
		## if the cooldown-throttled search doesn't find a new one yet
		_find_cover_position()
		if not _has_valid_cover:
			if time_in_state >= SEEKING_COVER_MIN_DURATION: _transition_to_combat()  # RCA-17
			return

	# Use navigation-based pathfinding to move toward cover
	_move_to_target_nav(_cover_position, combat_move_speed)

	# Can still shoot while moving to cover (only after detection delay)
	# Issue #934: also shoot at companion if visible
	if ((_can_see_player and _player) or (_can_see_companion and _companion != null)) and _detection_delay_elapsed and _shoot_timer >= shoot_cooldown:
		_aim_at_player()
		_shoot()
		_shoot_timer = 0.0

## Process IN_COVER state. Under fire->suppressed, close->COMBAT, far+can hit->stay and shoot, far+can't hit->PURSUING.
func _process_in_cover_state(delta: float) -> void:
	velocity = Vector2.ZERO
	var time_in_state := Time.get_ticks_msec() / 1000.0 - _in_cover_entry_time  # Issue #997 RCA-18

	# If still under fire, transition to suppressed (with minimum duration check)
	if _under_fire:
		if time_in_state >= IN_COVER_MIN_DURATION:  # RCA-18: prevent instant IN_COVER→SUPPRESSED
			_transition_to_suppressed()
		return

	# Check if player has flanked us - if we're now visible from player's position,
	# we need to find new cover
	if _is_visible_from_player():
		# If in alarm mode and can see player, fire a burst before escaping
		# [#1161] Sniper rifle is bolt-action: no burst fire (flee immediately)
		# [#1242] Revolver is single-action: no burst fire
		if _in_alarm_mode and _can_see_player and _player and weapon_type != WeaponType.SNIPER_RIFLE and weapon_type != WeaponType.REVOLVER:
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
		# RCA-19: Check minimum duration before transitioning to prevent rapid cycling
		if time_in_state >= IN_COVER_MIN_DURATION:
			_log_debug("Player flanked our cover position, seeking new cover")
			_has_valid_cover = false  # Invalidate current cover
			_cover_burst_pending = false
			_transition_to_seeking_cover()
		return

	# Decision making (#934): ASSAULT removed per #169; use distance+visibility
	var can_see_target := _can_see_player or _can_see_companion
	var has_target := (_player != null) or (_companion != null and _can_see_companion)
	if has_target:
		var target_close := _is_target_close()
		var can_hit := _can_hit_target_from_current_position()
		if can_see_target:
			# RCA-19: Check minimum duration before transitioning to COMBAT
			if time_in_state < IN_COVER_MIN_DURATION:
				return
			if target_close:  # Target is close - engage in combat
				_log_debug("Target is close, transitioning to COMBAT")
				_transition_to_combat()
				return
			elif can_hit:  # Target is far but can hit from current position
				_log_debug("Target is far but can hit from here, transitioning to COMBAT")
				_transition_to_combat()
				return
			else:  # Can't hit from here - need to pursue (move cover-to-cover)
				_log_debug("Target is far and can't hit, transitioning to PURSUING")
				_transition_to_pursuing()
				return

	# If not under fire and can see player or companion, engage (only shoot after detection delay)
	# Issue #934: also shoot at companion if visible
	if (_can_see_player and _player) or (_can_see_companion and _companion != null):
		_aim_at_player()
		if _detection_delay_elapsed and _shoot_timer >= shoot_cooldown:
			_shoot()
			_shoot_timer = 0.0

	# If player (or companion) lost and not under fire, try suppressive fire then pursuing (Issue #934, #910).
	if not (_can_see_player or _can_see_companion) and not _under_fire and not (_suppressive_fire and _suppressive_fire.try_suppress_cover(_player, _last_known_player_position, _is_melee_weapon, _is_reloading, _shoot_timer, shoot_cooldown)):
		_log_debug("Lost sight of player from cover, transitioning to PURSUING")
		_transition_to_pursuing()

## Process FLANKING state - flank player using cover-to-cover movement.
func _process_flanking_state(delta: float) -> void:
	_flank_state_timer += delta

	if _flank_state_timer >= FLANK_STATE_MAX_TIME:
		_log_to_file("FLANKING timeout (%.1fs), target=%s, pos=%s" % [_flank_state_timer, _flank_target, global_position])
		_flank_side_initialized = false
		if _can_see_player or _can_see_companion: _transition_to_combat()  # #934: incl. companion
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
			if _can_see_player or _can_see_companion: _transition_to_combat()  # #934: incl. companion
			else: _transition_to_pursuing()
			return
	else:
		_flank_stuck_timer = 0.0
		_flank_last_position = global_position
		if _flank_fail_count > 0:
			_flank_fail_count = 0

	if _under_fire and enable_cover and not (_shield_component and _shield_component.is_active()):  # Issue #1242: no retreat with shield up
		_flank_side_initialized = false; _transition_to_retreating(); return

	# Only transition to combat if we can ACTUALLY HIT the target (#934: incl. companion)
	if (_can_see_player or _can_see_companion) and _can_hit_target_from_current_position():
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

## Process SUPPRESSED state - staying in cover under fire. Issue #1338: actively seek cover.
func _process_suppressed_state(delta: float) -> void:
	if not _has_valid_cover:
		_find_cover_position()
	if _is_visible_from_player():
		# Fire burst before escaping if visible (#934 companion, #1161/#1242 skip bolt/single-action)
		if ((_can_see_player and _player) or (_can_see_companion and _companion != null)) and weapon_type != WeaponType.SNIPER_RIFLE and weapon_type != WeaponType.REVOLVER:
			if not _cover_burst_pending:
				_cover_burst_pending = true
				_retreat_burst_remaining = randi_range(2, 4)
				_retreat_burst_timer = 0.0
				_retreat_burst_angle_offset = -RETREAT_BURST_ARC / 2.0
				_log_debug("SUPPRESSED alarm: starting burst before escaping (%d shots)" % _retreat_burst_remaining)
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
		if Time.get_ticks_msec() / 1000.0 - _suppressed_entry_time < SUPPRESSED_MIN_DURATION: return
		_log_debug("Player flanked our cover position while suppressed, seeking new cover")
		_has_valid_cover = false
		_cover_burst_pending = false
		_transition_to_seeking_cover()
		return
	# Issue #1338: move toward cover while suppressed
	## Issue #1411: when hidden from player (cover is working), do NOT recalculate cover position.
	## The cover was found at suppression time and should be kept until the situation changes.
	if _has_valid_cover:
		var distance_to_cover := global_position.distance_to(_cover_position)
		if distance_to_cover < 10.0:
			velocity = Vector2.ZERO  ## Issue #1411: at cover and hidden — stay put, no recalculation
		else: _move_to_target_nav(_cover_position, combat_move_speed)
	else:
		_find_cover_position()  ## Only search when we truly have no cover
		if _has_valid_cover: _move_to_target_nav(_cover_position, combat_move_speed)
		else: velocity = Vector2.ZERO
	if (_can_see_player and _player) or (_can_see_companion and _companion != null):
		_aim_at_player()
		if _detection_delay_elapsed and _shoot_timer >= shoot_cooldown:
			_shoot()
			_shoot_timer = 0.0
	if not _under_fire:
		if Time.get_ticks_msec() / 1000.0 - _suppressed_entry_time >= SUPPRESSED_MIN_DURATION:
			if not _is_visible_from_player():
				_post_suppression_timer = POST_SUPPRESSION_COVER_DURATION
				_transition_to_in_cover()
			else:
				_post_suppression_timer = POST_SUPPRESSION_COVER_DURATION
				_transition_to_seeking_cover()

## Process RETREATING state - moving to cover with behavior based on damage taken.
func _process_retreating_state(delta: float) -> void:
	var time_in_state := Time.get_ticks_msec() / 1000.0 - _retreating_entry_time  # Issue #997 RCA-17
	if not _has_valid_cover:
		_find_cover_position()
		if not _has_valid_cover:
			if time_in_state >= RETREATING_MIN_DURATION:  # RCA-17: min duration before transition
				if _under_fire: _transition_to_suppressed()
				else: _transition_to_combat()
			return

	# Check if we've reached cover and are hidden from player
	# RCA-19: Add minimum duration check even for successful cover reach
	if not _is_visible_from_player():
		if time_in_state >= RETREATING_MIN_DURATION:
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
			## Issue #1411: don't invalidate current cover before searching — cooldown-throttled
			_find_cover_position()
			if not _has_valid_cover:
				if time_in_state >= RETREATING_MIN_DURATION:  # RCA-17
					if _under_fire: _transition_to_suppressed()
					else: _transition_to_combat()
			return

	# Apply retreat behavior based on mode
	match _retreat_mode:
		RetreatMode.FULL_HP: _process_retreat_full_hp(delta, direction_to_cover)
		RetreatMode.ONE_HIT: _process_retreat_one_hit(delta, direction_to_cover)
		RetreatMode.MULTIPLE_HITS: _process_retreat_multiple_hits(delta, direction_to_cover)

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
			# Issue #934: also shoot at companion if visible
			if (_can_see_player or _can_see_companion) and _detection_delay_elapsed and _shoot_timer >= shoot_cooldown:
				_shoot_with_inaccuracy()
				_shoot_timer = 0.0

## Process ONE_HIT retreat: quick burst of 2-4 shots in an arc while turning, then face cover.
func _process_retreat_one_hit(delta: float, direction_to_cover: Vector2) -> void:
	# [#1161] Sniper rifle is bolt-action: skip burst phase and run to cover immediately
	# [#1242] Revolver is single-action: no burst fire (same as sniper)
	if weapon_type == WeaponType.SNIPER_RIFLE or weapon_type == WeaponType.REVOLVER:
		_retreat_burst_complete = true
		_move_to_target_nav(_cover_position, combat_move_speed)
		return
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
			_rotate_body_toward(target_angle, delta)

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
	_pursuing_state_timer += delta
	# Issue #579: Machete enemies dodge bullets and sneak cover-to-cover
	if _is_melee_weapon and _machete:
		if _under_fire and _bullets_in_threat_sphere.size() > 0 and not _machete.is_dodging():
			var b = _bullets_in_threat_sphere[0]
			if is_instance_valid(b):
				var bd: Vector2 = b.get("direction") if b.get("direction") != null else Vector2.RIGHT.rotated(b.rotation)
				_machete.try_dodge(bd)
		if _machete.is_dodging(): velocity = _machete.get_dodge_velocity(); return
		# Issue #934: also consider companion for melee engagement
		if ((_can_see_player and _player and global_position.distance_to(_player.global_position) <= CLOSE_COMBAT_DISTANCE) or
				(_can_see_companion and _companion != null and global_position.distance_to(_companion.global_position) <= CLOSE_COMBAT_DISTANCE)):
			_transition_to_combat(); return
	# [#1163] Sniper holds position and blind-fires; returns false when too close (fall through to reposition).
	# [#1161] Pass can_see_player so sniper falls through to COMBAT when player is visible.
	if weapon_type == WeaponType.SNIPER_RIFLE and _sniper_component != null and _sniper_component.process_pursuing(delta, _can_see_player, _player, _last_known_player_position, _prediction):
		return

	if _under_fire and enable_cover and not _pursuing_vulnerability_sound and not _is_melee_weapon and not (_shield_component and _shield_component.is_active()):  # Issue #1242: no retreat with shield up
		_pursuit_approaching = false; _transition_to_retreating(); return

	# Issue #604: Grenadier proactive passage throw - throw before entering passage/cover
	if is_grenadier and _grenade_component is GrenadierGrenadeComponent and _nav_agent and not _nav_agent.is_navigation_finished():
		var wp := _nav_agent.get_next_path_position()
		var ss := get_world_2d().direct_space_state
		if ss and (_grenade_component as GrenadierGrenadeComponent).try_passage_throw(global_position, wp, ss, _is_alive, _is_stunned, _is_blinded):
			velocity = Vector2.ZERO; return  # Wait for grenade to explode
	# Issue #657: Non-grenadier allies wait for nearby grenadier to throw before advancing
	if not is_grenadier and _should_wait_for_nearby_grenadier(): velocity = Vector2.ZERO; return

	# If can see player/companion and can hit them, engage (after min time to prevent thrash) #934
	if (_can_see_player and _player) or (_can_see_companion and _companion != null):
		var can_hit := _can_hit_target_from_current_position()
		if can_hit and _pursuing_state_timer >= PURSUING_MIN_DURATION_BEFORE_COMBAT:
			_log_debug("Can see and hit target from pursuit (%.2fs), transitioning to COMBAT" % _pursuing_state_timer)
			_has_pursuit_cover = false
			_pursuit_approaching = false
			_pursuing_vulnerability_sound = false
			_transition_to_combat()
			return

	if _suppressive_fire: _suppressive_fire.try_suppress_pursuing(_can_see_player, _last_known_player_position, _is_melee_weapon, _player, _is_reloading, _shoot_timer, shoot_cooldown)  # Issue #910
	# VULNERABILITY SOUND PURSUIT: pursue reload/empty click sound position
	if _pursuing_vulnerability_sound and _last_known_player_position != Vector2.ZERO:
		var distance_to_sound := global_position.distance_to(_last_known_player_position)

		if distance_to_sound < 50.0:  # Reached the sound position
			_log_debug("Reached vulnerability sound position (dist=%.0f)" % distance_to_sound)
			# If we can see the player/companion now, attack (#934)
			if (_can_see_player and _player) or (_can_see_companion and _companion != null):
				_log_debug("Can see target at sound position, transitioning to COMBAT")
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

	# [Issue #574] Check if the current path goes through a lit passage
	# If the flashlight illuminates the next waypoint, try flanking to find an alternate route
	if _flashlight_detection and _player and not _pursuit_approaching:
		if _flashlight_detection.is_next_waypoint_lit(_nav_agent, _player, _raycast):
			if _can_attempt_flanking():
				_log_to_file("[#574] Next waypoint lit by flashlight, attempting flank to avoid lit passage")
				if _transition_to_flanking():
					return

	# Process approach phase - moving directly toward target (player or companion) #934
	if _pursuit_approaching:
		var approach_target := _current_target if _current_target != null else _player
		if approach_target:
			var direction := (approach_target.global_position - global_position).normalized()
			var can_hit := _can_hit_target_from_current_position()

			_pursuit_approach_timer += delta

			# If we can now hit the target, transition to combat
			if can_hit:
				_log_debug("Can now hit target after approach (%.1fs), transitioning to COMBAT" % _pursuit_approach_timer)
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
				# No pursuit cover found - start approach phase if we can see player/companion
				# Issue #934: also consider companion visibility
				_log_debug("No pursuit cover found, checking fallback options")
				if (_can_see_player and _player) or (_can_see_companion and _companion != null):
					# Can see but can't hit (at last cover) - start approach phase
					_log_debug("Can see target but can't hit, starting approach phase")
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

		# Check if we've reached the pursuit cover (distance only, not visibility)
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
		# Issue #1357: Fast corner escape — if stuck >2s while pursuing cover, apply escape velocity or abandon cover
		if _global_stuck_timer > 2.0 and distance > 30.0:
			var _n: Vector2 = Vector2.ZERO
			for _i: int in range(get_slide_collision_count()): _n += get_slide_collision(_i).get_normal()
			_global_stuck_timer = 0.0; _global_stuck_last_position = global_position
			if _n.length_squared() > 0.01: velocity = _n.normalized() * combat_move_speed * 2.0
			else: _has_pursuit_cover = false
		# Corner checking during PURSUING (Issue #332)
		if velocity.length_squared() > 1.0:
			_process_corner_check(delta, velocity.normalized(), "PURSUING")
		return

	# No cover and no pursuit target - find initial pursuit cover
	_find_pursuit_cover_toward_player()
	if not _has_pursuit_cover:
		if _prediction and not _can_see_player:  # [#298] Prediction-based pursuit
			var pt := _prediction.get_pursuit_target(global_position)
			if pt != Vector2.ZERO:
				_move_to_target_nav(pt, combat_move_speed)
				if velocity.length_squared() > 1.0: _process_corner_check(delta, velocity.normalized(), "PURSUING_PREDICTION")
				return
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

## Load predefined search waypoints from SearchPathWaypoints node (Issue #1225). Returns true if loaded.
func _load_predefined_search_path(_near_pos: Vector2) -> bool:
	if _search_path_node == null or not is_instance_valid(_search_path_node):
		if search_path_node != NodePath(""): _search_path_node = get_node_or_null(search_path_node)
		if _search_path_node == null:
			var found := get_tree().get_nodes_in_group("search_path_waypoints")
			if found.size() > 0: _search_path_node = found[0]
	if _search_path_node == null: return false
	var wps: Array[Vector2] = []
	for c in _search_path_node.get_children():
		if c is Marker2D: wps.append(c.global_position)
	if wps.is_empty(): return false
	var si := 0; var md := INF
	for i in range(wps.size()):
		var d := global_position.distance_to(wps[i])
		if d < md: md = d; si = i
	_search_waypoints.clear(); _search_current_waypoint_index = 0
	for i in range(wps.size()): _search_waypoints.append(wps[(si + i) % wps.size()])
	_log_debug("SEARCHING: Loaded %d predefined waypoints (start=%d)" % [_search_waypoints.size(), si])
	return true

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

## Process SEARCHING state - waypoint scanning (#322, #330: engaged enemies search infinitely).
func _process_searching_state(delta: float) -> void:
	_search_state_timer += delta
	# Issue #330: Only timeout for patrol enemies; engaged enemies search infinitely
	if _search_state_timer >= SEARCH_MAX_DURATION and not _has_left_idle:
		_log_to_file("SEARCHING timeout after %.1fs, returning to IDLE (patrol enemy)" % _search_state_timer)
		_transition_to_idle()
		return
	if _can_see_player:
		_log_to_file("SEARCHING: Player spotted! Transitioning to COMBAT")
		_transition_to_combat()
		return
	if _search_current_waypoint_index >= _search_waypoints.size() or _search_waypoints.is_empty():
		if _using_predefined_search_path and not _search_waypoints.is_empty():  # Issue #1225: loop predefined path
			_search_current_waypoint_index = 0; _search_moving_to_waypoint = true; return
		if _search_radius < SEARCH_MAX_RADIUS:
			_search_radius += SEARCH_RADIUS_EXPANSION
			_generate_search_waypoints()
			_log_to_file("SEARCHING: Expand outer ring r=%.0f wps=%d" % [_search_radius, _search_waypoints.size()])
			if _search_waypoints.is_empty() and _search_radius < SEARCH_MAX_RADIUS:
				return
		else:
			if _has_left_idle:  # Issue #330/#405: Engaged enemy - move center, clear old zones, continue searching
				var old_center := _search_center; _search_center = global_position
				_search_radius = SEARCH_INITIAL_RADIUS; _search_state_timer = 0.0
				# Issue #405: Clear visited zones to allow exploring new areas
				_search_visited_zones.clear()
				_generate_search_waypoints()
				_log_to_file("SEARCHING: Max radius reached, relocated center %s->%s, cleared zones (wps=%d)" % [old_center, _search_center, _search_waypoints.size()])
				return
			_log_to_file("SEARCHING: Max radius, returning to IDLE (patrol enemy)")
			_transition_to_idle(); return
	if _search_waypoints.is_empty():
		if _using_predefined_search_path:  # Issue #1225: reload predefined path
			_using_predefined_search_path = _load_predefined_search_path(_search_center)
			if _using_predefined_search_path: return
		if _has_left_idle:  # Issue #330/#405: Regenerate from current position, clear old zones
			var old := _search_center; _search_center = global_position; _search_radius = SEARCH_INITIAL_RADIUS
			# Issue #405: Clear visited zones to allow exploring new areas
			_search_visited_zones.clear()
			_generate_search_waypoints()
			_log_to_file("SEARCHING: No waypoints, relocated center %s->%s, cleared zones (wps=%d)" % [old, _search_center, _search_waypoints.size()])
			return
		_transition_to_idle(); return
	var target_waypoint := _search_waypoints[_search_current_waypoint_index]
	var dist := global_position.distance_to(target_waypoint)
	if _search_moving_to_waypoint:
		if dist <= SEARCH_WAYPOINT_REACHED_DISTANCE:
			_search_moving_to_waypoint = false; _search_scan_timer = 0.0; _search_stuck_timer = 0.0
			_log_debug("SEARCHING: Reached waypoint %d, scanning..." % _search_current_waypoint_index)
		else:
			_nav_agent.target_position = target_waypoint
			if _nav_agent.is_navigation_finished():
				_mark_zone_visited(target_waypoint); _search_current_waypoint_index += 1
				_search_moving_to_waypoint = true; _search_stuck_timer = 0.0
			else:
				var next_pos := _nav_agent.get_next_path_position()
				var dir := (next_pos - global_position).normalized()
				if _tactical_movement and _tactical_movement.check_and_yield(target_waypoint, move_speed * 0.7, get_physics_process_delta_time()):  # #1249: yield in SEARCHING too
					velocity = Vector2.ZERO; move_and_slide(); _push_casings(); _search_stuck_timer = 0.0; _search_last_progress_position = global_position; return
				var _sv := dir * move_speed * 0.7; if _nav_agent and _nav_agent.avoidance_enabled: _nav_agent.set_velocity(_sv)  # #1249: ORCA for searching
				velocity = (_avoidance_velocity if _avoidance_velocity.length_squared() > 0.01 else _sv) if (_nav_agent and _nav_agent.avoidance_enabled) else _sv
				move_and_slide(); _push_casings()  # Issue #341
				var progress := global_position.distance_to(_search_last_progress_position)  # #354: Stuck detection
				if progress < SEARCH_PROGRESS_THRESHOLD:
					_search_stuck_timer += delta
					if _search_stuck_timer >= SEARCH_STUCK_MAX_TIME:  # Stuck - skip waypoint
						_log_to_file("SEARCHING: Stuck at wp %d, skipping" % _search_current_waypoint_index)
						_mark_zone_visited(target_waypoint); _search_current_waypoint_index += 1
						_search_moving_to_waypoint = true; _search_stuck_timer = 0.0; _search_last_progress_position = global_position; return
				else: _search_stuck_timer = 0.0; _search_last_progress_position = global_position
				if dir.length() > 0.1:
					_rotate_body_toward(dir.angle(), delta)
					_process_corner_check(delta, dir, "SEARCHING")  # Issue #332
	else:
		_search_scan_timer += delta; rotation += delta * 1.5 * (_shield_component.get_rotation_multiplier() if _shield_component and _shield_component.is_active() else 1.0)
		if _search_scan_timer >= SEARCH_SCAN_DURATION:
			_mark_zone_visited(target_waypoint); _search_current_waypoint_index += 1
			_search_moving_to_waypoint = true
			_log_debug("SEARCHING: Scan done, next wp %d" % _search_current_waypoint_index)

## Process EVADING_GRENADE state - flee to guaranteed safe distance (Issue #407, #426).
func _process_evading_grenade_state(delta: float) -> void:
	_grenade_evasion_timer += delta
	_update_grenade_danger_detection()  # Update component state
	var in_danger := _grenade_avoidance.in_danger_zone if _grenade_avoidance else false
	var evasion_target := _grenade_avoidance.evasion_target if _grenade_avoidance else Vector2.ZERO
	var at_safe_distance := _grenade_avoidance.is_at_safe_distance() if _grenade_avoidance else true

	# Issue #426: Return only if at safe distance and not in danger; timeout after max time
	if not in_danger and at_safe_distance:
		_log_to_file("EVADING_GRENADE: Escaped to safe distance"); _return_from_grenade_evasion(); return
	if _grenade_evasion_timer >= GRENADE_EVASION_MAX_TIME:
		_log_to_file("EVADING_GRENADE: Timeout after %.1fs" % _grenade_evasion_timer); _return_from_grenade_evasion(); return
	# Calculate evasion target from remembered position if needed
	if evasion_target == Vector2.ZERO and _grenade_avoidance:
		var grenade_pos := _grenade_avoidance.get_remembered_grenade_position()
		if grenade_pos == Vector2.ZERO and _grenade_avoidance.most_dangerous_grenade:
			grenade_pos = _grenade_avoidance.most_dangerous_grenade.global_position
		if grenade_pos != Vector2.ZERO:
			var escape_dir := (global_position - grenade_pos).normalized()
			if escape_dir.length() < 0.1: escape_dir = Vector2.RIGHT.rotated(randf() * TAU)
			evasion_target = grenade_pos + escape_dir * _grenade_avoidance.get_safe_distance()
			_grenade_avoidance.evasion_target = evasion_target

	# Move toward evasion target at combat speed
	if evasion_target != Vector2.ZERO:
		var distance_to_target := global_position.distance_to(evasion_target)
		if distance_to_target < 20.0:
			if at_safe_distance: _return_from_grenade_evasion(); return
			else: _calculate_grenade_evasion_target()
		else:
			_nav_agent.target_position = evasion_target
			if not _nav_agent.is_navigation_finished():
				var next_pos := _nav_agent.get_next_path_position()
				var direction := (next_pos - global_position).normalized()
				velocity = direction * combat_move_speed
				move_and_slide(); _push_casings()
				if direction.length() > 0.1: _rotate_body_toward(direction.angle(), delta)
			else:
				velocity = (evasion_target - global_position).normalized() * combat_move_speed
				move_and_slide(); _push_casings()

## Return from grenade evasion to the appropriate state.
func _return_from_grenade_evasion() -> void:
	_grenade_evasion_timer = 0.0
	if _grenade_avoidance: _grenade_avoidance.reset()  # Clears position memory too (Issue #426)
	match _pre_evasion_state:
		AIState.IDLE: _transition_to_idle()
		AIState.COMBAT: _transition_to_combat()
		AIState.IN_COVER: _transition_to_in_cover() if _has_valid_cover else _transition_to_combat()
		AIState.SEEKING_COVER: _transition_to_seeking_cover()
		AIState.FLANKING: _transition_to_flanking()
		AIState.SUPPRESSED: _transition_to_suppressed() if _has_valid_cover else _transition_to_combat()
		AIState.RETREATING: _transition_to_retreating()
		AIState.PURSUING: _transition_to_pursuing()
		AIState.ASSAULT: _transition_to_assault()
		AIState.SEARCHING: _transition_to_searching(global_position)
		AIState.PACIFIST: _transition_to_pacifist(false)
		_: _transition_to_combat() if _can_see_player else _transition_to_idle()
func _process_pacifist_state(_d: float) -> void:  ## PACIFIST: hide in cover / retaliate vs attacker (#959)
	if _pacifist and _pacifist.is_retaliating():  ## Issue #959: pursue+shoot attacker; stay PACIFIST
		var tgt: Node2D = _pacifist.attacker if _pacifist.attacker != null else _player
		if tgt == null: velocity = Vector2.ZERO; return
		velocity = _apply_wall_avoidance((tgt.global_position - global_position).normalized()) * combat_move_speed if global_position.distance_to(tgt.global_position) > 80.0 else Vector2.ZERO
		if _shoot_timer >= shoot_cooldown and _can_shoot() and (tgt.global_position - global_position).normalized().dot(_get_weapon_forward_direction()) > AIM_TOLERANCE_DOT: _shoot()
		return
	if not _has_valid_cover: _find_cover_position()
	if not _has_valid_cover: velocity = Vector2.ZERO; return
	if global_position.distance_to(_cover_position) > 20.0: velocity = _apply_wall_avoidance((_cover_position - global_position).normalized()) * move_speed
	else: velocity = Vector2.ZERO

## Shoot with reduced accuracy for retreat mode (bullets fly in barrel direction with spread).
func _shoot_with_inaccuracy() -> void:
	if bullet_scene == null or _player == null:
		return
	# Issue #1334 Round 5: Don't shoot at a dead player
	var _gm2 := get_node_or_null("/root/GameManager")
	if _gm2 and not _gm2.player_alive: return

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

	# Fire bullet using _spawn_projectile (handles C# add_child-before-props, Issue #516, #550)
	_spawn_projectile(direction, bullet_spawn_pos)
	_spawn_muzzle_flash(bullet_spawn_pos, direction)
	# Play sounds
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_m16_shot"):
		audio_manager.play_m16_shot(global_position)
	# Emit gunshot sound (alerts other enemies); Issue #969: throttled
	var sound_propagation: Node = get_node_or_null("/root/SoundPropagation")
	var _now := Time.get_ticks_msec() / 1000.0
	if sound_propagation and sound_propagation.has_method("emit_sound") and _now - _last_gunshot_propagation_time >= ENEMY_GUNSHOT_PROPAGATION_COOLDOWN:
		sound_propagation.emit_sound(0, global_position, 1, self, weapon_loudness)  # 0 = GUNSHOT, 1 = ENEMY
		_last_gunshot_propagation_time = _now
	_play_delayed_shell_sound()
	_current_ammo -= 1; _shot_count += 1; _spread_timer = 0.0  # Issue #516: spread tracking
	ammo_changed.emit(_current_ammo, _reserve_ammo)
	if _current_ammo <= 0 and _reserve_ammo > 0: _start_reload()

## Shoot a burst shot with arc spread for ONE_HIT retreat.
func _shoot_burst_shot() -> void:
	if bullet_scene == null or _player == null:
		return

	# [#1161] Sniper rifle is bolt-action: no burst fire allowed
	if weapon_type == WeaponType.SNIPER_RIFLE:
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

	# Fire bullet using _spawn_projectile (handles C# add_child-before-props, Issue #516, #550)
	_spawn_projectile(direction, bullet_spawn_pos)
	_spawn_muzzle_flash(bullet_spawn_pos, direction)

	# Play sounds
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_m16_shot"):
		audio_manager.play_m16_shot(global_position)

	# Emit gunshot sound for in-game sound propagation (Issue #969: throttled per-enemy)
	var sound_propagation: Node = get_node_or_null("/root/SoundPropagation")
	var _now2 := Time.get_ticks_msec() / 1000.0
	if sound_propagation and sound_propagation.has_method("emit_sound") and _now2 - _last_gunshot_propagation_time >= ENEMY_GUNSHOT_PROPAGATION_COOLDOWN:
		sound_propagation.emit_sound(0, global_position, 1, self, weapon_loudness)  # 0 = GUNSHOT, 1 = ENEMY
		_last_gunshot_propagation_time = _now2

	_play_delayed_shell_sound()

	_current_ammo -= 1; _shot_count += 1; _spread_timer = 0.0  # Issue #516: spread tracking
	ammo_changed.emit(_current_ammo, _reserve_ammo)
	if _current_ammo <= 0 and _reserve_ammo > 0: _start_reload()

func _transition_to_idle() -> void:
	var _ps := get_node_or_null("/root/PerformanceSettings")
	if _ps and not _ps.is_ai_state_idle_enabled():  # Issue #1186: IDLE disabled -> stay in SEARCHING
		_current_state = AIState.SEARCHING; _search_center = global_position; _search_radius = SEARCH_INITIAL_RADIUS; _search_state_timer = 0.0; _search_scan_timer = 0.0; _search_current_waypoint_index = 0; _search_direction = 0; _search_leg_length = SEARCH_WAYPOINT_SPACING; _search_legs_completed = 0; _search_moving_to_waypoint = true; _search_visited_zones.clear(); _search_stuck_timer = 0.0; _search_last_progress_position = global_position; _generate_search_waypoints(); return
	_current_state = AIState.IDLE
	# Reset various state tracking when returning to idle
	_hits_taken_in_encounter = 0; _in_alarm_mode = false; _cover_burst_pending = false
	_idle_scan_timer = 0.0; _idle_scan_targets.clear()  # Will be re-initialized in _process_guard
	if _nav_agent: _nav_agent.path_desired_distance = _nav_default_path_desired_distance  # #1289

func _transition_to_combat() -> void:
	var _ps := get_node_or_null("/root/PerformanceSettings"); if _ps and not _ps.is_ai_state_combat_enabled(): _transition_to_idle(); return  # Issue #1186
	_current_state = AIState.COMBAT
	_has_left_idle = true  # Issue #330
	_detection_timer = 0.0; _detection_delay_elapsed = false
	_combat_exposed = false; _combat_approaching = false
	_combat_shoot_timer = 0.0; _combat_approach_timer = 0.0; _combat_state_timer = 0.0
	_seeking_clear_shot = false; _clear_shot_timer = 0.0; _clear_shot_target = Vector2.ZERO
	# Issue #409: Clear witnessed ally death flag when engaging player
	_witnessed_ally_death = false; _suspected_directions.clear()
	_pursuing_vulnerability_sound = false; _machete_combat_stuck_timer = 0.0; _machete_combat_stuck_last_pos = global_position  # Issue #1107
	if _is_rpg_weapon and not _rpg_fired: _shoot_timer = shoot_cooldown  # Issue #583
	if _tactical_movement: _tactical_movement.reset_yield()  # Issue #1249: clear yield on state entry
	if _nav_agent: _nav_agent.path_desired_distance = _nav_default_path_desired_distance  # #1289
	if is_gas_mask and _gas_mask_grenade and _gas_mask_grenade.has_grenades() and _player:  # Issue #1353: throw chemical grenade before shooting
		_gas_mask_grenade.try_throw(_player.global_position)

func _transition_to_seeking_cover() -> void:
	var _ps := get_node_or_null("/root/PerformanceSettings"); if _ps and not _ps.is_ai_state_seeking_cover_enabled(): _transition_to_idle(); return  # Issue #1186
	_current_state = AIState.SEEKING_COVER
	# Mark that enemy has left IDLE state (Issue #330)
	_has_left_idle = true
	_seeking_cover_entry_time = Time.get_ticks_msec() / 1000.0  # Issue #997 RCA-17
	if _nav_agent: _nav_agent.path_desired_distance = _nav_default_path_desired_distance  # #1289
	_find_cover_position()

func _transition_to_in_cover() -> void:
	var _ps := get_node_or_null("/root/PerformanceSettings"); if _ps and not _ps.is_ai_state_in_cover_enabled(): _transition_to_idle(); return  # Issue #1186
	_current_state = AIState.IN_COVER
	# Mark that enemy has left IDLE state (Issue #330)
	_has_left_idle = true
	_in_cover_entry_time = Time.get_ticks_msec() / 1000.0  # Issue #997 RCA-18
	if _nav_agent: _nav_agent.path_desired_distance = _nav_default_path_desired_distance  # #1289

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

func _transition_to_flanking() -> bool:
	var _ps := get_node_or_null("/root/PerformanceSettings"); if _ps and not _ps.is_ai_state_flanking_enabled(): _transition_to_idle(); return false  # Issue #1186
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
	if _tactical_movement: _tactical_movement.reset_yield()  # Issue #1249: clear yield on state entry
	if _nav_agent: _nav_agent.path_desired_distance = _nav_default_path_desired_distance  # #1289
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

func _transition_to_suppressed() -> void:
	var _ps := get_node_or_null("/root/PerformanceSettings"); if _ps and not _ps.is_ai_state_suppressed_enabled(): _transition_to_idle(); return  # Issue #1186
	var _prev_state := _current_state  ## Issue #1411: remember previous state
	_current_state = AIState.SUPPRESSED
	_has_left_idle = true; _in_alarm_mode = true  # Issue #330
	_suppressed_entry_time = Time.get_ticks_msec() / 1000.0  # Issue #969 RCA-11
	## Issue #1411: only force new cover search if NOT coming from a cover-related state.
	## When transitioning from IN_COVER/SEEKING_COVER, the enemy already has a valid cover position
	## and re-searching every frame causes massive performance drops (6-10 FPS with 4+ enemies).
	if _prev_state not in [AIState.IN_COVER, AIState.SEEKING_COVER, AIState.RETREATING]:
		_has_valid_cover = false; _last_cover_search_time = -999.0  # Issue #1338: force new cover search
	if _nav_agent: _nav_agent.path_desired_distance = _nav_default_path_desired_distance  # #1289
func _transition_to_pursuing() -> void:
	var _ps := get_node_or_null("/root/PerformanceSettings"); if _ps and not _ps.is_ai_state_pursuing_enabled(): _transition_to_idle(); return  # Issue #1186
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
	if _tactical_movement: _tactical_movement.reset_yield()  # Issue #1249: clear yield on state entry
	if _nav_agent: _nav_agent.path_desired_distance = PURSUIT_PATH_DESIRED_DISTANCE  # Issue #1289: larger nav step while pursuing

func _transition_to_assault() -> void:
	var _ps := get_node_or_null("/root/PerformanceSettings"); if _ps and not _ps.is_ai_state_assault_enabled(): _transition_to_idle(); return  # Issue #1186
	_current_state = AIState.ASSAULT
	# Mark that enemy has left IDLE state (Issue #330)
	_has_left_idle = true
	_assault_wait_timer = 0.0
	_assault_ready = false
	_in_assault = false
	# Reset detection delay for new engagement
	_detection_timer = 0.0
	_detection_delay_elapsed = false
	if _nav_agent: _nav_agent.path_desired_distance = _nav_default_path_desired_distance  # #1289
	# Find closest cover to player for assault position
	_find_cover_closest_to_player()

func _transition_to_searching(center_position: Vector2) -> void:
	var _ps := get_node_or_null("/root/PerformanceSettings"); if _ps and not _ps.is_ai_state_searching_enabled(): _transition_to_idle(); return  # Issue #1186
	_current_state = AIState.SEARCHING
	if _nav_agent: _nav_agent.path_desired_distance = _nav_default_path_desired_distance  # #1289
	# Issue #921: Do NOT set _has_left_idle = true here; let it retain whatever value it had.
	# Combat enemies already have it true (search indefinitely); patrol enemies have it false (timeout).
	_search_center = center_position; _search_radius = SEARCH_INITIAL_RADIUS
	_search_state_timer = 0.0; _search_scan_timer = 0.0; _search_current_waypoint_index = 0
	_search_direction = 0; _search_leg_length = SEARCH_WAYPOINT_SPACING; _search_legs_completed = 0
	_search_moving_to_waypoint = true; _search_visited_zones.clear()
	# Issue #354: Initialize stuck detection. #1249: clear yield on SEARCHING entry.
	_search_stuck_timer = 0.0; _search_last_progress_position = global_position; if _tactical_movement: _tactical_movement.reset_yield()
	_using_predefined_search_path = _load_predefined_search_path(center_position)  # Issue #1225
	if not _using_predefined_search_path: _generate_search_waypoints()
	var msg := "SEARCHING started (%s): center=%s, radius=%.0f, waypoints=%d" % ["predefined" if _using_predefined_search_path else "spiral", _search_center, _search_radius, _search_waypoints.size()]
	_log_debug(msg); _log_to_file(msg)

## Transition to EVADING_GRENADE state - flee from grenade danger zone (Issue #407).
func _transition_to_evading_grenade() -> void:
	_pre_evasion_state = _current_state
	_current_state = AIState.EVADING_GRENADE
	if _nav_agent: _nav_agent.path_desired_distance = _nav_default_path_desired_distance  # #1289
	_has_left_idle = true  # Mark that enemy has left IDLE state (Issue #330)
	_grenade_evasion_timer = 0.0
	_calculate_grenade_evasion_target()  # Calculate escape target via component
	var grenade_pos := _grenade_avoidance.most_dangerous_grenade.global_position if _grenade_avoidance and _grenade_avoidance.most_dangerous_grenade else Vector2.ZERO
	var evasion_target := _grenade_avoidance.evasion_target if _grenade_avoidance else Vector2.ZERO
	_log_debug("EVADING_GRENADE: Fleeing from grenade at %s, target=%s" % [str(grenade_pos), str(evasion_target)])
	_log_to_file("EVADING_GRENADE started: escaping to %s" % str(evasion_target))

func _transition_to_retreating() -> void:
	var _ps := get_node_or_null("/root/PerformanceSettings"); if _ps and not _ps.is_ai_state_retreating_enabled(): _transition_to_idle(); return  # Issue #1186
	_current_state = AIState.RETREATING
	# Mark that enemy has left IDLE state (Issue #330)
	_has_left_idle = true
	# Enter alarm mode when retreating
	_in_alarm_mode = true
	_retreating_entry_time = Time.get_ticks_msec() / 1000.0  # Issue #997 RCA-17
	if _nav_agent: _nav_agent.path_desired_distance = _nav_default_path_desired_distance  # #1289

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
## Transition to PACIFIST state (Issue #959). @param emit_signal: emit became_pacifist on first transition
func _transition_to_pacifist(emit_signal: bool = true) -> void:
	if _pacifist and _pacifist.is_immune: _log_to_file("Cannot become pacifist - immune"); return
	var was := _pacifist.is_pacifist if _pacifist else false
	_current_state = AIState.PACIFIST; _has_left_idle = true; velocity = Vector2.ZERO
	if _nav_agent: _nav_agent.path_desired_distance = _nav_default_path_desired_distance  # #1289
	if _pacifist: _pacifist.start_pacifism()
	_log_to_file("Transitioned to PACIFIST"); if emit_signal and not was: became_pacifist.emit()
## Make this enemy a pacifist via loudspeaker. Returns true if successful.
func apply_pacifism(hc: float = 0.5) -> bool:
	if not _pacifist or _pacifist.is_immune or _pacifist.is_pacifist or not _is_alive: return false
	_transition_to_pacifist()
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != self and e.has_method("on_new_pacifist_created") and e.has_method("is_alive") and e.is_alive(): e.on_new_pacifist_created(self, hc)
	return true

func was_attacked_by_player() -> bool: return _hits_taken_in_encounter > 0 or _in_alarm_mode
func was_hit_by_player() -> bool: return _hits_taken_in_encounter > 0  ## Issue #959: hits only, ignores alarm mode (used by loudspeaker level 6+)
func is_pacifist() -> bool: return _pacifist.is_pacifist if _pacifist else false
func is_retaliating() -> bool: return _pacifist != null and _pacifist.is_retaliating()  ## True if pacifist is temporarily retaliating (#959)
func is_immune_to_pacifism() -> bool: return _pacifist.is_immune if _pacifist else false
func set_immune_to_pacifism(immune: bool) -> void:
	if _pacifist: _pacifist.set_immune(immune); if immune: _log_to_file("Enemy immune to pacifism")
## Issue #959: On new pacifist created nearby, roll hostility; if hostile, pursue pacifist.
func on_new_pacifist_created(p: Node2D, hc: float) -> void:
	if not _is_alive or (_pacifist and _pacifist.is_pacifist) or hc <= 0.0 or randf() >= hc: return
	_last_known_player_position = p.global_position; _in_alarm_mode = true
	if _current_state != AIState.COMBAT: _transition_to_combat()
	_log_to_file("[#959] Hostile toward pacifist at %s" % p.global_position)

## Issue #959: Level 5+ pacifism spread — on first LoS to a pacifist, roll to become pacifist.
func _check_pacifism_spread() -> void:
	if not _is_alive or (_pacifist and _pacifist.is_pacifist): return
	var aim: Node = get_node_or_null("/root/ActiveItemManager")
	if aim == null or not aim.has_loudspeaker(): return
	var lp: LoudspeakerProgress = aim.get("loudspeaker_progress")
	if lp == null or not lp.can_pacifism_spread(): return
	var sc: float = lp.get_effect_chance()
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or e == self or not e.has_method("is_pacifist") or not e.is_pacifist() or e in _evaluated_pacifists: continue
		_evaluated_pacifists.append(e)
		var ray := PhysicsRayQueryParameters2D.create(global_position, e.global_position, 4, [self])
		if not get_world_2d().direct_space_state.intersect_ray(ray).is_empty() or randf() >= sc: continue
		_log_to_file("[#959] Pacifism spread from %s" % e.global_position); apply_pacifism(0.0)

## Alert this enemy that the loudspeaker was used — all enemies hear the player (#959).
func alert_from_loudspeaker(sound_position: Vector2) -> void:
	if not _is_alive: return
	if _pacifist and _pacifist.is_pacifist: return  # Pacifists already neutralized
	_last_known_player_position = sound_position
	if _current_state in [AIState.IDLE, AIState.IN_COVER, AIState.SUPPRESSED, AIState.RETREATING, AIState.SEEKING_COVER, AIState.SEARCHING]:
		_transition_to_pursuing()
	_log_to_file("Alerted by loudspeaker from position %s" % sound_position)
func _is_visible_from_player() -> bool:  ## PLAYER can see ENEMY (checks center + corners)
	return _is_position_visible_from_player(global_position) if _player else false
func _get_enemy_check_points(c: Vector2) -> Array[Vector2]:  ## center + 4 corners for visibility
	var d := 22.0 * 0.707; return [c, c + Vector2(d, d), c + Vector2(-d, d), c + Vector2(d, -d), c + Vector2(-d, -d)]
func _is_point_visible_from_player(pt: Vector2) -> bool:  ## Single point visible from player
	if not _player: return false
	var q := PhysicsRayQueryParameters2D.new(); q.from = _player.global_position; q.to = pt; q.collision_mask = 4
	var r := get_world_2d().direct_space_state.intersect_ray(q)
	return r.is_empty() or _player.global_position.distance_to(r["position"]) >= _player.global_position.distance_to(pt) - 10.0
func _is_position_visible_from_player(pos: Vector2) -> bool:  ## Enemy at pos visible to player (Issue #1411: per-frame cache)
	if not _player: return true
	var frame := Engine.get_physics_frames()
	if frame != _visibility_cache_frame: _visibility_cache.clear(); _visibility_cache_frame = frame
	var key := Vector2i(roundi(pos.x), roundi(pos.y))
	if _visibility_cache.has(key): return _visibility_cache[key]
	var vis := false
	for pt in _get_enemy_check_points(pos):
		if _is_point_visible_from_player(pt): vis = true; break
	_visibility_cache[key] = vis; return vis

## Check if target is visible from enemy (raycast for LOS). For lead prediction validation.
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

## Get center + 4 corner points on player body (16px radius) for visibility testing.
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

## Check if a single point is visible from the enemy (no blocking obstacles).
func _is_player_point_visible_to_enemy(point: Vector2) -> bool:
	var distance := global_position.distance_to(point)
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.new()
	query.from = global_position; query.to = point
	query.collision_mask = 4; query.exclude = [get_rid()]
	var result := space_state.intersect_ray(query)
	if result.is_empty(): return true
	var distance_to_hit := global_position.distance_to(result["position"])
	return distance_to_hit >= distance - 5.0  # 5 pixel tolerance

## Calculate player body visibility fraction (0.0=hidden, 1.0=visible) using multi-point checks.
func _calculate_player_visibility_ratio() -> float:
	if _player == null:
		return 0.0

	var check_points := _get_player_check_points(_player.global_position)
	var visible_count := 0

	for point in check_points:
		if _is_player_point_visible_to_enemy(point):
			visible_count += 1

	return float(visible_count) / float(check_points.size())

## Check if firing line to target is clear of friendly enemies.
func _is_firing_line_clear_of_friendlies(target_position: Vector2) -> bool:
	if not enable_friendly_fire_avoidance: return true
	var weapon_forward := _get_weapon_forward_direction()
	var muzzle_pos := _get_bullet_spawn_position(weapon_forward)
	var distance := muzzle_pos.distance_to(target_position)
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.new()
	query.from = muzzle_pos; query.to = target_position
	query.collision_mask = 2; query.exclude = [get_rid()]
	var result := space_state.intersect_ray(query)
	if result.is_empty(): return true
	var distance_to_hit := muzzle_pos.distance_to(result["position"])
	if distance_to_hit < distance - 20.0:  # 20 pixel tolerance
		_log_debug("Friendly in firing line at distance %0.1f (target at %0.1f)" % [distance_to_hit, distance])
		return false
	return true

## Check if shot to target is blocked by cover. Returns true if clear.
func _is_shot_clear_of_cover(target_position: Vector2) -> bool:
	var weapon_forward := _get_weapon_forward_direction()
	var muzzle_pos := _get_bullet_spawn_position(weapon_forward)
	var distance := muzzle_pos.distance_to(target_position)
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.new()
	query.from = muzzle_pos; query.to = target_position
	query.collision_mask = 4  # Only check obstacles (layer 3)
	var result := space_state.intersect_ray(query)
	if result.is_empty(): return true
	var distance_to_hit := muzzle_pos.distance_to(result["position"])
	if distance_to_hit < distance - 10.0:  # 10 pixel tolerance
		_log_debug("Shot blocked by cover at distance %0.1f (target at %0.1f)" % [distance_to_hit, distance])
		return false
	return true

## Check if bullet spawn point is clear. [#954 v3] Uses intersect_point() at muzzle + center→muzzle raycast.
func _is_bullet_spawn_clear(direction: Vector2) -> bool:
	var world_2d := get_world_2d()
	if world_2d == null: return true
	var space_state := world_2d.direct_space_state
	if space_state == null: return true
	var muzzle_pos := _get_bullet_spawn_position(direction)
	var pq := PhysicsPointQueryParameters2D.new()  # [#954 v3] point test at muzzle — intersect_point detects inside-wall even when origin is inside collider
	pq.position = muzzle_pos; pq.collision_mask = 4; pq.exclude = [get_rid()]
	if not space_state.intersect_point(pq, 1).is_empty():
		_log_debug("Bullet spawn blocked: muzzle at %.0f,%.0f is inside wall" % [muzzle_pos.x, muzzle_pos.y]); return false
	var rq := PhysicsRayQueryParameters2D.new()  # secondary raycast center→muzzle catches walls between them
	rq.from = global_position; rq.to = muzzle_pos; rq.collision_mask = 4; rq.exclude = [get_rid()]
	var rr := space_state.intersect_ray(rq)
	if not rr.is_empty():
		_log_debug("Bullet spawn blocked: wall at distance %.1f (muzzle at %.1f)" % [
			global_position.distance_to(rr["position"]), global_position.distance_to(muzzle_pos)]); return false
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
	# Check path to bullet spawn is clear (prevents shooting into walls; uses weapon forward)
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

## Check if best target (player or companion) is close (Issue #934).
func _is_target_close() -> bool:
	var t := _current_target if _current_target != null else _player
	return t != null and global_position.distance_to(t.global_position) <= CLOSE_COMBAT_DISTANCE

## Get target position: visible player/companion > memory > last known > stay in place (Issue #297, #318, #934).
func _get_target_position() -> Vector2:
	# Issue #934: also consider companion visibility
	if _can_see_player and _player:
		return _player.global_position
	if _can_see_companion and _companion != null:
		return _companion.global_position
	if _memory and _memory.has_target():
		return _memory.suspected_position
	if _last_known_player_position != Vector2.ZERO:
		return _last_known_player_position
	return global_position  # No valid target - stay in place

## Check if the enemy can hit the player from their current position.
func _can_hit_player_from_current_position() -> bool:
	return _player != null and _can_see_player and _is_shot_clear_of_cover(_player.global_position)

## Check if enemy can hit best target (player or companion) (Issue #934).
func _can_hit_target_from_current_position() -> bool:
	if _current_target == null: return _can_hit_player_from_current_position()
	var can_see := _can_see_player if _current_target == _player else _can_see_companion
	return can_see and _is_shot_clear_of_cover(_current_target.global_position)

## Count enemies in combat states (COMBAT/PURSUING/ASSAULT/IN_COVER) for assault trigger.
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

## Find pursuit cover toward player — delegates to PursuitComponent (Issue #1289).
## Selects nearest navmesh-valid cover that: advances toward player, is hidden, avoids
## occupied spots (enemy spread), avoids flashlight beam, and differs from current obstacle.
func _find_pursuit_cover_toward_player() -> void:
	var result := _pursuit_component.find_cover()
	_has_pursuit_cover = result.found
	if result.found:
		_pursuit_next_cover      = result.cover
		_current_cover_obstacle  = result.obstacle

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
	var current_time := Time.get_ticks_msec() / 1000.0  ## Issue #1411: throttle
	if current_time - _last_closest_cover_search_time < COVER_SEARCH_COOLDOWN: return  ## Issue #1411: cooldown applies even without valid cover
	_last_closest_cover_search_time = current_time; var wp_a := _combat_waypoint(_player.global_position)  # Issue #1227
	if wp_a != Vector2.ZERO: _cover_position = wp_a; _has_valid_cover = true; return
	var player_pos := _player.global_position
	var best_cover: Vector2 = Vector2.ZERO; var best_distance: float = INF; var found_cover: bool = false
	for i in range(COVER_CHECK_COUNT):  # Cast rays in all directions to find obstacles
		var raycast := _cover_raycasts[i]
		raycast.target_position = Vector2.from_angle((float(i) / COVER_CHECK_COUNT) * TAU) * COVER_CHECK_DISTANCE
		raycast.force_raycast_update()
		if not raycast.is_colliding(): continue
		var cover_pos := raycast.get_collision_point() + raycast.get_collision_normal() * 35.0
		if not _can_reach_position(cover_pos): continue  # Can't reach = opposite side of wall
		if not _is_position_visible_from_player(cover_pos):  # Hidden from player = safe cover
			var distance_to_player := cover_pos.distance_to(player_pos)
			if distance_to_player < best_distance:
				best_distance = distance_to_player; best_cover = cover_pos; found_cover = true
	if found_cover:
		_cover_position = best_cover
		_has_valid_cover = true
		_log_debug("Found assault cover at %s (distance to player: %.1f)" % [_cover_position, best_distance])
	else:
		# Fall back to normal cover finding
		_find_cover_position()

## Shared helper: cast rays from player position, find hidden cover candidates. Issue #1338/1378.
## If store_debug_rays is true, updates _last_cover_search_rays for visualization (Issue #1359).
func _get_hidden_cover_candidates(store_debug_rays: bool) -> Array[Vector2]:
	var candidates: Array[Vector2] = []
	if _player == null: return candidates
	var player_pos := _player.global_position
	var space_state := get_world_2d().direct_space_state
	var nav_map: RID = _nav_agent.get_navigation_map() if _nav_agent else RID()
	var has_nav := nav_map.is_valid()
	var exp_s: Node = get_node_or_null("/root/ExperimentalSettings")
	var inf_rays: bool = exp_s != null and exp_s.has_method("is_cover_infinite_rays_enabled") and exp_s.is_cover_infinite_rays_enabled()
	var sec_rays: bool = exp_s != null and exp_s.has_method("is_cover_sector_rays_enabled") and exp_s.is_cover_sector_rays_enabled()
	var ray_dist: float = COVER_INFINITE_RAY_DISTANCE if inf_rays else COVER_CHECK_DISTANCE
	var ray_count: int = COVER_SECTOR_RAY_COUNT if sec_rays else COVER_CHECK_COUNT
	var sec_ctr: Vector2 = (global_position - player_pos).normalized() if sec_rays else Vector2.ZERO
	if store_debug_rays: _last_cover_search_rays.clear()
	for i in range(ray_count):
		var direction: Vector2
		if sec_rays:
			var frac := float(i) / float(ray_count - 1) if ray_count > 1 else 0.5
			direction = Vector2.from_angle(sec_ctr.angle() + (frac - 0.5) * 2.0 * COVER_SECTOR_HALF_ANGLE)
		else: direction = Vector2.from_angle((float(i) / float(ray_count)) * TAU)
		var ray_end := player_pos + direction * ray_dist
		var query := PhysicsRayQueryParameters2D.new()
		query.from = player_pos; query.to = ray_end; query.collision_mask = 4
		var result := space_state.intersect_ray(query)
		if store_debug_rays:
			var ray_info := {"origin": player_pos, "target": ray_end, "colliding": not result.is_empty()}
			if not result.is_empty(): ray_info["point"] = result["position"]; ray_info["normal"] = result["normal"]
			_last_cover_search_rays.append(ray_info)
		if result.is_empty(): continue
		var cover_pos := _get_far_side_cover(player_pos, result["position"], direction, space_state, ray_dist)
		if is_teleporter and global_position.distance_to(cover_pos) < 10.0: continue
		if has_nav: cover_pos = NavigationServer2D.map_get_closest_point(nav_map, cover_pos)
		if not _is_position_visible_from_player(cover_pos): candidates.append(cover_pos)
		if candidates.size() >= COVER_MAX_CANDIDATES and not store_debug_rays: break  ## Issue #1411: early exit
	return candidates

## Find cover hidden from player. Issue #969: throttled. Issue #1338/1378: rays from player.
func _find_cover_position() -> void:
	if _player == null: _has_valid_cover = false; return
	var current_time := Time.get_ticks_msec() / 1000.0
	if current_time - _last_cover_search_time < COVER_SEARCH_COOLDOWN: return  ## Issue #1411: cooldown applies even without valid cover to prevent frame-burst searches
	_last_cover_search_time = current_time
	var candidates := _get_hidden_cover_candidates(true)
	if candidates.is_empty():
		_has_valid_cover = false
		_log_to_file("No valid cover found (player at %s, enemy at %s)" % [_player.global_position, global_position])
		return
	var best_cover := candidates[0]
	var best_dist := global_position.distance_to(best_cover)
	for c in candidates:
		var d := global_position.distance_to(c)
		if d < best_dist: best_dist = d; best_cover = c
	_cover_position = best_cover; _has_valid_cover = true
	_log_to_file("Found cover at %s (distance: %.1f, player at %s)" % [_cover_position, best_dist, _player.global_position])

## Get far-side cover behind obstacle (Issue #1338/1378). Probes outward with intersect_point().
func _get_far_side_cover(player_pos: Vector2, collision_point: Vector2, direction: Vector2, space_state: PhysicsDirectSpaceState2D, effective_ray_dist: float = 300.0) -> Vector2:
	var near_dist := collision_point.distance_to(player_pos)
	var step_size := 45.0; var max_probe_dist := effective_ray_dist * 2.0  ## Issue #1411: was 30/3x
	var probe_dist := near_dist + 5.0; var was_inside := false; var iterations := 0
	var point_query := PhysicsPointQueryParameters2D.new()
	point_query.collision_mask = 4; point_query.collide_with_areas = false; point_query.collide_with_bodies = true
	while probe_dist < max_probe_dist and iterations < 15:  ## Issue #1411: cap iterations
		iterations += 1
		var probe_point := player_pos + direction * probe_dist
		point_query.position = probe_point
		if space_state.intersect_point(point_query, 1).is_empty():
			if was_inside: return probe_point + direction * 35.0
			var rev_q := PhysicsRayQueryParameters2D.new()
			rev_q.from = probe_point; rev_q.to = player_pos; rev_q.collision_mask = 4
			var rev_r := space_state.intersect_ray(rev_q)
			if not rev_r.is_empty() and rev_r["position"].distance_to(player_pos) > near_dist + 5.0:
				return rev_r["position"] + direction * 35.0
			return probe_point + direction * 35.0
		else: was_inside = true
		probe_dist += step_size
	return collision_point + direction * 35.0

## Calculate flank position based on player location and stored _flank_side.
func _calculate_flank_position() -> void:
	if _player == null: return
	var _fp := _player.global_position + (global_position - _player.global_position).normalized().rotated(flank_angle * _flank_side) * flank_distance
	# Issue #1107: Snap to nearest valid navmesh point — prevents flanking to wall corners
	if _nav_agent: _flank_target = NavigationServer2D.map_get_closest_point(_nav_agent.get_navigation_map(), _fp)
	else: _flank_target = _fp
	_log_debug("Flank target: %s (side: %s)" % [_flank_target, "right" if _flank_side > 0 else "left"])

## Choose best flank side (1.0=right, -1.0=left) — prefers LoS to player, avoids walls (#367).
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

	# [Issue #574] When both sides are valid, prefer the side NOT lit by the flashlight
	if right_valid and left_valid and _flashlight_detection and _player:
		var right_lit := _flashlight_detection.is_position_lit(right_flank_pos, _player, _raycast)
		var left_lit := _flashlight_detection.is_position_lit(left_flank_pos, _player, _raycast)
		if right_lit and not left_lit:
			_log_to_file("[#574] Choosing left flank — right side lit by flashlight")
			return -1.0
		elif left_lit and not right_lit:
			_log_to_file("[#574] Choosing right flank — left side lit by flashlight")
			return 1.0

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
	var wp_f := _combat_waypoint(_flank_target)  # Issue #1227
	if wp_f != Vector2.ZERO: _flank_next_cover = wp_f; _has_flank_cover = true; return
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

			# For flanking: closer to flank target, not too far from us, reachable
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

			# Score: closer to flank target (priority), not too far from current position
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

## Check for wall ahead and return avoidance direction (Vector2.ZERO if clear). Uses 8 distance-weighted raycasts.
func _check_wall_ahead(direction: Vector2) -> Vector2:
	if _wall_raycasts.is_empty():
		return Vector2.ZERO

	var avoidance := Vector2.ZERO
	var perpendicular := Vector2(-direction.y, direction.x)  # 90 degrees rotation
	var closest_wall_distance: float = WALL_CHECK_DISTANCE
	var hit_count: int = 0

	# Raycast angles: center, left(-20°,-45°,-70°), right(+20°,+45°,+70°), rear(180°)
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
	# Issue #883: Only run the expensive multi-point raycast every VISION_CHECK_INTERVAL frames.
	# Cheap blocking checks (blinded, invisible, null) still run every frame for responsiveness.
	_vision_frame_counter += 1
	var is_vision_check_frame := (_vision_frame_counter % VISION_CHECK_INTERVAL) == _vision_frame_offset

	# Fast-path: clear visibility immediately on blocking conditions (no raycasts needed).
	if _is_blinded or _memory_reset_confusion_timer > 0.0 or _player == null or not is_instance_valid(_player) or not _raycast \
			or (_player.has_method("is_invisible") and _player.is_invisible()):
		_can_see_player = false; _player_visibility_ratio = 0.0; _continuous_visibility_timer = 0.0
		return

	# On non-check frames reuse last result; only accumulate timer if still visible (Issue #883).
	if not is_vision_check_frame:
		if _can_see_player: _continuous_visibility_timer += get_physics_process_delta_time()
		return

	# --- Full vision check (runs every VISION_CHECK_INTERVAL frames) ---
	_can_see_player = false; _player_visibility_ratio = 0.0
	var distance_to_player := global_position.distance_to(_player.global_position)

	# Check if player is within detection range (only if detection_range is positive)
	# If detection_range <= 0, detection is unlimited (line-of-sight only)
	if detection_range > 0 and distance_to_player > detection_range:
		_continuous_visibility_timer = 0.0; return

	# Check FOV angle (if FOV is enabled via ExperimentalSettings)
	if not _is_position_in_fov(_player.global_position):
		_continuous_visibility_timer = 0.0; return

	# Check multiple points on the player's body to handle wall corner cases (#264).
	var check_points := _get_player_check_points(_player.global_position)
	var visible_count := 0
	for point in check_points:
		if _is_player_point_visible_to_enemy(point):
			visible_count += 1; _can_see_player = true  # Continue to calculate ratio

	# Calculate visibility ratio based on how many points are visible
	if _can_see_player:
		_player_visibility_ratio = float(visible_count) / float(check_points.size())
		_continuous_visibility_timer += get_physics_process_delta_time()
	else:
		_continuous_visibility_timer = 0.0; _player_visibility_ratio = 0.0

## Check if the BFF companion is visible (Issue #934). Delegates to BffTargetingComponent.
func _check_companion_visibility() -> void:
	_bff_targeting.check_visibility(_is_blinded, _memory_reset_confusion_timer, detection_range,
		_raycast, _get_player_check_points, _is_player_point_visible_to_enemy, _is_position_in_fov)
	_can_see_companion = _bff_targeting.can_see_companion

## Update enemy memory (visual, decay, prediction, flashlight, intel sharing — #297/#298/#574).
func _update_memory(delta: float) -> void:
	if _memory == null:
		return

	# Visual detection: Update memory with player position at full confidence
	if _can_see_player and _player:
		_memory.update_position(_player.global_position, VISUAL_DETECTION_CONFIDENCE)
		# Also update the legacy _last_known_player_position for compatibility
		_last_known_player_position = _player.global_position
	if _prediction:  # [#298]
		var f := Vector2.RIGHT.rotated(_enemy_model.global_rotation) if _enemy_model else Vector2.RIGHT
		_prediction.process_frame(_can_see_player, _was_player_visible, _player.global_position if _player else Vector2.ZERO, global_position, f, delta, _memory)
	_was_player_visible = _can_see_player

	# [Issue #574] Flashlight beam detection: enemy detects beam when any part of it falls within their FOV
	if _flashlight_detection and _player and not _can_see_player and not _is_blinded and _memory_reset_confusion_timer <= 0.0:
		var _es: Node = get_node_or_null("/root/ExperimentalSettings")
		var _fov_on: bool = fov_enabled and _es != null and _es.has_method("is_fov_enabled") and _es.is_fov_enabled()
		var flashlight_detected := _flashlight_detection.check_flashlight(global_position, _enemy_model.global_rotation if _enemy_model else rotation, fov_angle, _fov_on, _player, _raycast, delta)
		if flashlight_detected:
			# Update memory with flashlight-based detection
			_memory.update_position(_flashlight_detection.estimated_player_position, FlashlightDetectionComponent.FLASHLIGHT_DETECTION_CONFIDENCE)
			_last_known_player_position = _flashlight_detection.estimated_player_position
			_log_to_file("[#574] Flashlight detected: estimated_pos=%s, beam_dir=%s" % [
				_flashlight_detection.estimated_player_position, _flashlight_detection.beam_direction
			])
			# If in IDLE state, react to flashlight detection by investigating
			if _current_state == AIState.IDLE:
				_log_to_file("[#574] Flashlight triggered pursuit from IDLE")
				_transition_to_pursuing()
	elif _flashlight_detection and (_can_see_player or _is_blinded or _memory_reset_confusion_timer > 0.0):
		# Reset flashlight detection when player is directly visible or enemy is blinded/confused
		_flashlight_detection.reset()

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

		if can_share:
			if other_enemy.has_method("receive_intel_from_ally"):
				other_enemy.receive_intel_from_ally(_memory)
			if _prediction and _prediction.has_predictions and other_enemy.has_method("receive_prediction_from_ally"):  # [#298]
				var bh := _prediction.get_best_hypothesis(); if bh: other_enemy.receive_prediction_from_ally(bh)

## Receive intelligence from an allied enemy (Issue #297). Called by other enemies when they share intel.
func receive_intel_from_ally(ally_memory: EnemyMemory) -> void:
	if _memory == null or ally_memory == null:
		return

	# Only update if ally has better or newer information
	if _memory.receive_intel(ally_memory, INTEL_SHARE_FACTOR):
		_log_debug("Received intel from ally: suspected pos=%s, conf=%.2f" % [
			_memory.suspected_position, _memory.confidence
		])
		_last_known_player_position = _memory.suspected_position

func receive_prediction_from_ally(hypothesis: PlayerPredictionComponent.Hypothesis) -> void:  ## [#298]
	if _prediction and hypothesis: _prediction.receive_prediction_intel(hypothesis, INTEL_SHARE_FACTOR)

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
	if _prediction: _prediction.reset()  # [#298]
	_log_to_file("Memory reset: confusion=%.1fs, had_target=%s" % [MEMORY_RESET_CONFUSION_DURATION, had_target])
	if had_target:
		# Issue #1419: Only transition to SEARCHING if enemy has previously engaged the player.
		# Enemies that never left IDLE (e.g. received intel via ally-share only) must not enter
		# SEARCHING on teleport — they have never personally seen or heard the player.
		if _has_left_idle:
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
			_log_to_file("Memory reset: %s -> IDLE (never engaged, had target via intel only)" % AIState.keys()[_current_state])
			_transition_to_idle()
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

## Aim at best target (player or companion #934) using gradual rotation.
func _aim_at_player() -> void:
	var aim_at: Node2D = _current_target if _current_target != null else _player
	if aim_at == null:
		return
	var direction := (aim_at.global_position - global_position).normalized()
	var target_angle := direction.angle()

	# Calculate the shortest rotation direction
	var angle_diff := wrapf(target_angle - rotation, -PI, PI)

	# Get the delta time from the current physics process
	var delta := get_physics_process_delta_time()

	# Apply gradual rotation based on rotation_speed; Issue #1242: shield slows all rotations
	var aim_speed := rotation_speed * (_shield_component.get_rotation_multiplier() if _shield_component and _shield_component.is_active() else 1.0)
	if abs(angle_diff) <= aim_speed * delta:
		rotation = target_angle
	elif angle_diff > 0:
		rotation += aim_speed * delta
	else:
		rotation -= aim_speed * delta

## Shoot a bullet or perform melee attack (Issue #579: MACHETE, Issue #824: night mode flash).
func _shoot() -> void:
	if _is_melee_weapon and _machete: var _mt := (_aggression.get_target() if _aggression and _aggression.is_aggressive() and _aggression.get_target() else _player) as Node2D; if _mt: _machete.perform_melee_attack(_mt); return  # [#858] target enemy when aggressive
	var _agg := _aggression != null and _aggression.is_aggressive()  # [Issue #675]
	if _agg and (_aggression.get_target() == null): return  # [Issue #954] no fallback to shooting player
	var _aiming_companion := (_current_target == _companion and _can_see_companion)  # Issue #934
	if bullet_scene == null or not (_player != null or _aiming_companion or (_agg and _aggression.get_target() != null)): return
	if not _can_shoot(): return
	# Issue #934: aggression target > companion > player
	var target_position := _aggression.get_target_position() if _agg and _aggression.get_target() != null else (_companion.global_position if _aiming_companion else (_player.global_position if _player else global_position))
	if enable_lead_prediction and not _agg and not _is_rpg_weapon and _player and not _aiming_companion: target_position = _calculate_lead_prediction()  # Issue #583: no lead prediction for RPG
	if _agg:
		# [Issue #954] Check both 35px center ray AND real muzzle-to-target path (passage-edge wall bug fix)
		if not _is_bullet_spawn_clear(_get_weapon_forward_direction()): return
		if not _is_shot_clear_of_cover(_aggression.get_target_position()): return
	elif not _aiming_companion and not _should_shoot_at_target(target_position): return
	if _enemy_flashlight:  # Issue #824/#825: block shooting while flashlight flash is in progress
		if not _is_pre_attack_flashing: _is_pre_attack_flashing = true; _enemy_flashlight.start_pre_attack_flash(target_position, _execute_shoot.bind(target_position))
		return  # Callback fires the shot after flash completes
	_execute_shoot(target_position)
func _execute_shoot(target_position: Vector2) -> void:  ## Issue #824: shooting callback.
	_is_pre_attack_flashing = false
	# Issue #1334 Round 11: Guard against freed node during deferred shoot callbacks
	if not is_inside_tree() or not _is_alive: return
	# Issue #1334 Round 5: Don't shoot at a dead player — prevents crash from same-frame hitscan/damage
	var _gm := get_node_or_null("/root/GameManager")
	if _gm and not _gm.player_alive: return
	# [Issue #1242] Revolver hammer cocking: 0.15s delay with cock sound before each shot (same as player Revolver.cs)
	if weapon_type == WeaponType.REVOLVER and not _revolver_cocking:
		_revolver_cocking = true
		var audio_hc: Node = get_node_or_null("/root/AudioManager")
		if audio_hc and audio_hc.has_method("play_revolver_hammer_cock"): audio_hc.play_revolver_hammer_cock(global_position)
		await get_tree().create_timer(0.15).timeout
		_revolver_cocking = false
		if not is_inside_tree() or not is_instance_valid(self) or not _is_alive: return  # Issue #1334 Round 11: guard freed node after await
	if _invisibility: _invisibility.reveal()  # Issue #1121: briefly reveal cloaked enemy when shooting
	# Calculate bullet spawn position at weapon muzzle first
	# We need this to calculate the correct bullet direction
	var weapon_forward := _get_weapon_forward_direction()
	var bullet_spawn_pos := _get_bullet_spawn_position(weapon_forward)
	var to_target := (target_position - global_position).normalized()
	# Bullets fly in barrel direction, only shoot when properly aimed (issue #254, #344)
	var aim_dot := weapon_forward.dot(to_target)
	if aim_dot < AIM_TOLERANCE_DOT:
		if debug_logging:
			var aim_angle_deg := rad_to_deg(acos(clampf(aim_dot, -1.0, 1.0)))
			_log_debug("SHOOT BLOCKED: Not aimed at target. aim_dot=%.3f (%.1f deg off)" % [aim_dot, aim_angle_deg])
		return
	var direction := weapon_forward
	if _is_rpg_weapon and not _rpg_fired: _fire_rpg_rocket(direction, bullet_spawn_pos)  # Issue #583
	elif _is_shotgun_weapon: _shoot_shotgun_pellets(direction, bullet_spawn_pos)
	elif weapon_type == WeaponType.SNIPER_RIFLE: _sniper_component.shoot_sniper_hitscan(direction, bullet_spawn_pos)  # [#1171] Hitscan avoids physics tunneling at 10000px/s
	else: _shoot_single_bullet(direction, bullet_spawn_pos)
	_spawn_muzzle_flash(bullet_spawn_pos, direction)
	if not _is_rpg_weapon and weapon_type != WeaponType.REVOLVER: _spawn_casing(direction, weapon_forward)  # Issue #583: no casing for RPG; #1242: revolver ejects casings on reload, not per shot
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio:
		if _is_shotgun_weapon and audio.has_method("play_shotgun_shot"): audio.play_shotgun_shot(global_position)
		elif weapon_type == WeaponType.MACHINE_GUN and audio.has_method("play_ak_shot"): audio.play_ak_shot(global_position)  # [#1033] PKM uses AK 7.62x39 sound
		elif weapon_type == WeaponType.SNIPER_RIFLE and audio.has_method("play_asvk_shot"): audio.play_asvk_shot()  # [#1125] ASVK sniper rifle sound (non-positional, like player SniperRifle.cs)
		elif weapon_type == WeaponType.REVOLVER and audio.has_method("play_revolver_shot"): audio.play_revolver_shot(global_position)  # [#1242] RSh-12 revolver shot sound
		elif audio.has_method("play_m16_shot"): audio.play_m16_shot(global_position)
	var sp: Node = get_node_or_null("/root/SoundPropagation")
	var _now3 := Time.get_ticks_msec() / 1000.0
	if sp and sp.has_method("emit_sound") and _now3 - _last_gunshot_propagation_time >= ENEMY_GUNSHOT_PROPAGATION_COOLDOWN:
		sp.emit_sound(0, global_position, 1, self, weapon_loudness)
		_last_gunshot_propagation_time = _now3
	if not _is_rpg_weapon: _play_delayed_shell_sound()  # Issue #583: no shell sound for RPG
	if weapon_type == WeaponType.SNIPER_RIFLE:  # [#1177] Trigger 4-step bolt-action cycle
		_is_bolt_cycling = true; _bolt_cycle_timer = 0.0; _bolt_cycle_step = 1
	_current_ammo -= 1; _shot_count += 1; _spread_timer = 0.0  # Issue #516: spread tracking
	if _revolver_component: _revolver_component.track_round_fired()  # [#1242] Track for casing ejection
	ammo_changed.emit(_current_ammo, _reserve_ammo)
	if _is_rpg_weapon and not _rpg_fired: _rpg_fired = true; _switch_to_secondary_weapon(); return  # Issue #583
	if _current_ammo <= 0 and _reserve_ammo > 0: _start_reload()

## Spawn projectile. Pool first (Issue #724), fallback instantiate (Issue #516, #550).
func _spawn_projectile(dir: Vector2, pos: Vector2) -> void:
	# Issue #1334 Round 11: Guard against spawning projectiles when scene tree is unavailable
	if not is_inside_tree(): return
	var current_scene := get_tree().current_scene
	if current_scene == null: return
	var sid := get_instance_id(); var pm: Node = get_node_or_null("/root/ProjectilePoolManager")
	if pm and pm.has_method("get_bullet"):
		var p = pm.get_bullet()
		if p and p.has_method("pool_activate"): p.pool_activate(pos, dir, sid, null); if p.get("shooter_position") != null: p.shooter_position = pos; return
	var p := bullet_scene.instantiate(); p.global_position = pos; current_scene.add_child(p)
	if p.has_method("SetDirection"): p.SetDirection(dir)
	elif p.get("direction") != null: p.direction = dir
	elif p.get("Direction") != null: p.Direction = dir
	if p.has_method("SetShooterId"): p.SetShooterId(sid)
	elif p.get("shooter_id") != null: p.shooter_id = sid
	elif p.get("ShooterId") != null: p.ShooterId = sid
	if p.has_method("SetShooterPosition"): p.SetShooterPosition(pos)
	elif p.get("shooter_position") != null: p.shooter_position = pos
	elif p.get("ShooterPosition") != null: p.ShooterPosition = pos
	if bullet_damage_multiplier != 1.0 and p.get("damage") != null: p.damage *= bullet_damage_multiplier  # Issue #1244

## Fire RPG rocket (Issue #583). RigidBody2D + linear_velocity after add_child (VOGGrenade pattern).
func _fire_rpg_rocket(dir: Vector2, pos: Vector2) -> void:
	if not is_inside_tree(): return  # Issue #1334 Round 11: guard freed node
	var rocket: Node2D = (preload("res://scenes/projectiles/RpgRocket.tscn") as PackedScene).instantiate() as Node2D
	if rocket == null: _log_to_file("[RPG] ERROR: RpgRocket instantiate failed!"); return
	var current_scene := get_tree().current_scene
	if current_scene == null: _log_to_file("[RPG] ERROR: No current scene!"); return
	var rocket_dir: Vector2 = dir.normalized() if dir.length() > 0.0 else Vector2.RIGHT
	rocket.set("direction", rocket_dir); rocket.set("shooter_id", get_instance_id()); rocket.set("shooter_position", pos); rocket.global_position = pos
	current_scene.add_child(rocket)
	_log_to_file("[RPG] Rocket launched at %s dir=%s" % [str(pos), str(rocket_dir)])

## Shoot a single bullet (rifle/UZI) with progressive spread (Issue #516).
func _shoot_single_bullet(direction: Vector2, spawn_pos: Vector2) -> void:
	var spread := _initial_spread if _shot_count <= _spread_threshold else minf(_initial_spread + (_shot_count - _spread_threshold) * _spread_increment, _max_spread)
	if spread > 0.0: direction = direction.rotated(randf_range(-deg_to_rad(spread), deg_to_rad(spread)))
	_spawn_projectile(direction, spawn_pos)

## Shoot multiple pellets with spread (shotgun - like player's Shotgun.cs).
func _shoot_shotgun_pellets(base_direction: Vector2, spawn_pos: Vector2) -> void:
	var count: int = randi_range(_pellet_count_min, _pellet_count_max)
	var spread_rad: float = deg_to_rad(_spread_angle)
	var half: float = spread_rad / 2.0
	if debug_logging: _log_debug("SHOTGUN: %d pellets, %.1f° spread" % [count, _spread_angle])  # Issue #457

	for i in range(count):
		var angle: float = 0.0
		if count > 1:
			angle = lerp(-half, half, float(i) / float(count - 1)) + randf_range(-spread_rad * 0.15, spread_rad * 0.15)
		_spawn_projectile(base_direction.rotated(angle), spawn_pos)
func _spawn_muzzle_flash(p: Vector2, d: Vector2) -> void:
	var m = get_node_or_null("/root/ImpactEffectsManager")
	if m: m.spawn_muzzle_flash(p, d)
## Play shell casing sound with a delay to simulate the casing hitting the ground.
func _play_delayed_shell_sound() -> void:
	# Issue #1334 Round 11: Guard against freed node after await.
	if not is_inside_tree(): return
	await get_tree().create_timer(0.15).timeout
	if not is_inside_tree() or not _is_alive: return
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_shell_rifle"):
		audio_manager.play_shell_rifle(global_position)

## Spawn bullet casing (based on BaseWeapon.cs for visual consistency with player).
func _spawn_casing(shoot_direction: Vector2, weapon_forward: Vector2) -> void:
	if casing_scene == null: return
	if not is_inside_tree(): return  # Issue #1334 Round 11: guard freed node
	var current_scene := get_tree().current_scene
	if current_scene == null: return
	var casing_spawn_position: Vector2 = global_position + weapon_forward * (bullet_spawn_offset * 0.5)
	var casing: RigidBody2D = casing_scene.instantiate()
	casing.global_position = casing_spawn_position
	# Eject to the right (90° CCW rotation = perpendicular to barrel) with randomness
	var weapon_right: Vector2 = Vector2(-weapon_forward.y, weapon_forward.x)
	var ejection_direction: Vector2 = weapon_right.rotated(randf_range(-0.3, 0.3)).rotated(randf_range(-0.1, 0.1))
	casing.linear_velocity = ejection_direction * randf_range(120.0, 180.0)  # reduced 2.5x for Issue #424
	casing.angular_velocity = randf_range(-15.0, 15.0)
	if _caliber_data:
		casing.set("caliber_data", _caliber_data)
	else:
		var fallback_caliber: Resource = load("res://resources/calibers/caliber_545x39.tres")
		if fallback_caliber: casing.set("caliber_data", fallback_caliber)
	current_scene.add_child(casing)

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

	# Validate predicted position is visible; fall back to current position if behind cover.
	if not _is_position_visible_to_enemy(predicted_pos):
		_log_debug("Lead prediction blocked: predicted position %s is not visible, using current position %s" % [predicted_pos, player_pos])
		return player_pos

	_log_debug("Lead prediction: player at %s moving %s, aiming at %s" % [player_pos, player_velocity, predicted_pos])

	return predicted_pos

## Process patrol behavior - move between patrol points with corner checking.
func _process_patrol(delta: float) -> void:
	# Issue #1119: NavigationAgent2D routing replaces direct direction+wall avoidance (wall-rubbing fix).
	if _patrol_points.is_empty(): return
	# Issue #1216: Snap patrol points after 1 physics frame; only if within agent_radius*2 (avoid cross-wall snap).
	if not _patrol_points_snapped and _nav_agent != null and Engine.get_physics_frames() > _spawn_physics_frame:
		var nav_map: RID = _nav_agent.get_navigation_map()
		if nav_map.is_valid():
			var snap_thr := ((_nav_agent.path_desired_distance if _nav_agent.path_desired_distance > 0.0 else 50.0) * 2.0)
			for i in range(_patrol_points.size()):
				var snapped := NavigationServer2D.map_get_closest_point(nav_map, _patrol_points[i])
				if _patrol_points[i].distance_to(snapped) <= snap_thr: _patrol_points[i] = snapped
			_patrol_points_snapped = true; _log_to_file("Patrol points snapped to navmesh (Issue #1216)")
	if _is_waiting_at_patrol_point:
		_patrol_wait_timer += delta
		if _patrol_wait_timer >= patrol_wait_time:
			_is_waiting_at_patrol_point = false; _patrol_wait_timer = 0.0
			_current_patrol_index = (_current_patrol_index + 1) % _patrol_points.size()
		velocity = Vector2.ZERO; return
	var target_point := _patrol_points[_current_patrol_index]
	if _nav_agent == null:  # Fallback if nav agent unavailable
		if global_position.distance_to(target_point) < 5.0: _is_waiting_at_patrol_point = true; velocity = Vector2.ZERO; return
		var d := (target_point - global_position).normalized(); velocity = d * move_speed; _rotate_body_toward(d.angle(), get_physics_process_delta_time()); return
	# Issue #1220: use _move_to_target_nav so patrol gets the same wall-avoidance + ORCA +
	# slide-collision corner-escape used by PURSUING/FLANKING, preventing wall-pressing.
	if not _move_to_target_nav(target_point, move_speed):
		_is_waiting_at_patrol_point = true; _patrol_stuck_timer = 0.0; _patrol_stuck_last_position = global_position; velocity = Vector2.ZERO; return
	var dir := velocity.normalized()
	if dir.length() > 0.1: _process_corner_check(delta, dir, "PATROL")
	var moved := global_position.distance_to(_patrol_stuck_last_position)  # Stuck detection
	if moved < PATROL_STUCK_DISTANCE_THRESHOLD:
		_patrol_stuck_timer += delta
		if _patrol_stuck_timer >= PATROL_STUCK_MAX_TIME:
			_log_to_file("PATROL STUCK: pos=%s for %.1fs, advancing to next point" % [global_position, _patrol_stuck_timer])
			_patrol_stuck_timer = 0.0; _patrol_stuck_last_position = global_position; _current_patrol_index = (_current_patrol_index + 1) % _patrol_points.size()  # #1216: skip stuck point
			_is_waiting_at_patrol_point = true; _patrol_wait_timer = 0.0; velocity = Vector2.ZERO
	else: _patrol_stuck_timer = 0.0; _patrol_stuck_last_position = global_position

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
## Issue #1311: removed _is_position_visible_to_enemy — suppression works through cover.
## Issue #1228: only player bullets suppress. #1311: fix ulong→int overflow for C# bullets.
func _on_threat_area_entered(area: Area2D) -> void:
	var raw_id = area.get("shooter_id"); if raw_id == null: raw_id = area.get("ShooterId")
	if raw_id == null: return  # Unknown area — no suppression
	# #1311: C# ulong may overflow to negative int64; reject only unset defaults (0, -1).
	var sid: int = int(raw_id); if sid == 0 or sid == -1: return
	var shooter: Object = instance_from_id(sid); if shooter == null: return
	if not (shooter as Node).is_in_group("player"): return  # #1228: only player bullets
	_log_to_file("[#1311] Player bullet entered threat sphere — suppression triggered")
	_bullets_in_threat_sphere.append(area); _threat_memory_timer = THREAT_MEMORY_DURATION

## Called when a bullet exits the threat sphere.
func _on_threat_area_exited(area: Area2D) -> void:
	_bullets_in_threat_sphere.erase(area)

## Apply damage to the enemy (IDamageable interface for C# Bullet). Primary entry point for C# bullets.
func take_damage(amount: float) -> void:
	on_hit_with_bullet_info(Vector2.RIGHT, null, false, false, amount)

## Called when the enemy is hit (by bullet.gd). Default damage = 1.
func on_hit() -> void:
	on_hit_with_info(Vector2.RIGHT, null)

## Called when the enemy is hit with extended hit information.
func on_hit_with_info(hit_direction: Vector2, caliber_data: Resource) -> void:
	on_hit_with_bullet_info(hit_direction, caliber_data, false, false, 1.0)

## Called when enemy is hit with full bullet information. @param damage: Damage amount (default 1.0). @param is_from_player: Whether the hit came from the player (Issue #1196).
func on_hit_with_bullet_info(hit_direction: Vector2, caliber_data: Resource, has_ricocheted: bool, has_penetrated: bool, damage: float = 1.0, is_from_player: bool = false) -> void:
	if not _is_alive:
		return
	if (_force_field_component and _force_field_component.is_active()) or (_drone_operator and _drone_operator.is_dashing()): _log_to_file("Hit blocked by force field/dash"); return  # Issues #1034, #1397
	# Issue #1242: Shield blocking — collision-based + direction fallback; shield enemy slowly turns toward attacker.
	if _shield_component and _shield_component.did_intercept_this_frame(): _set_hit_reaction_target(-hit_direction.normalized()); return
	if _shield_component and _shield_component.is_active() and _enemy_model and Vector2.from_angle(_enemy_model.global_rotation).dot(-hit_direction.normalized()) > 0.5:
		if _shield_component.try_intercept_hit(caliber_data, damage, hit_direction): _set_hit_reaction_target(-hit_direction.normalized()); return
	if _armored_skin_component and _armored_skin_component.try_spawn_shards(_current_health, maxi(int(round(damage)), 1)): hit.emit(); _show_hit_flash(); _log_to_file("[ArmoredSkin] Triggering hit absorbed — damage ignored (Issue #1143, #1300)"); return  # Issue #1143: absorb the triggering hit's damage; Issue #1300: also absorb lethal hits from high-damage weapons
	# [#1033] Machine gunner: 30% frontal damage resistance (±15° arc, cos15°=0.9659).
	if weapon_type == WeaponType.MACHINE_GUN and not _machine_gunner_pm_active and Vector2.from_angle(_enemy_model.global_rotation if _enemy_model else rotation).dot(-hit_direction.normalized()) >= 0.9659 and randf() < 0.30:
		_log_to_file("[#1033] Machine gunner front-arc hit ignored"); hit.emit(); _show_hit_flash(); return

	hit.emit()
	_last_hit_direction = hit_direction  # Store hit direction for death animation
	var attacker_direction := -hit_direction.normalized()
	if attacker_direction.length_squared() > 0.01:  # Issue #1242: shield enemy slowly turns; normal enemies snap-rotate
		if _shield_component and _shield_component.get_rotation_multiplier() < 1.0: _set_hit_reaction_target(attacker_direction)
		else: _force_model_to_face_direction(attacker_direction)
	_hits_taken_in_encounter += 1
	var actual_damage: int = maxi(int(round(damage)), 1)
	_log_to_file("Hit: dmg=%d, hp=%d/%d->%d/%d" % [actual_damage, _current_health, _max_health, _current_health - actual_damage, _max_health])
	_show_hit_flash()
	_current_health -= actual_damage  # Apply damage

	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	var impact_manager: Node = get_node_or_null("/root/ImpactEffectsManager")
	if _current_health <= 0:
		_killed_by_ricochet = has_ricocheted; _killed_by_penetration = has_penetrated; _killed_by_player = is_from_player  # Issue #1196: track kill source
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
		_update_health_visual()  # [Issue #919] check_retaliation removed: aggression must not propagate to hit enemies
		# Issue #959: Pacifist stays in PACIFIST state when hit; only attacks the attacker temporarily.
		if _pacifist and _pacifist.is_pacifist and _current_state == AIState.PACIFIST:
			_pacifist.start_retaliation(_player); var est_pos := global_position + attacker_direction * 300.0; _last_known_player_position = est_pos
			if _memory: _memory.update_position(est_pos, 0.8); _memory_reset_confusion_timer = 0.0
			_log_to_file("[#959] Pacifist hit - retaliates in PACIFIST state (attacker only)"); return
		# Issue #910: When hit in non-combat state, transition to COMBAT and fire back
		if _current_state in [AIState.IDLE, AIState.SEARCHING, AIState.RETREATING, AIState.SEEKING_COVER]:
			var est_pos := global_position + attacker_direction * 300.0; _last_known_player_position = est_pos
			if _memory: _memory.update_position(est_pos, 0.6); _memory_reset_confusion_timer = 0.0
			_log_to_file("[#910] Hit triggered COMBAT from %s" % AIState.keys()[_current_state]); _transition_to_combat()
			# Issue #1305: Only fire back if combat transition succeeded (not redirected to IDLE by PerformanceSettings)
			if _current_state == AIState.COMBAT and _suppressive_fire and _player and _player.has_method("is_invisible") and _player.is_invisible(): _suppressive_fire.shoot(est_pos)
		# Issue #1355: Teleporter enemies teleport immediately on first damage.
		if _teleport_component and _teleport_component.is_ready():
			if not _has_valid_cover: _find_cover_position()
			if _teleport_component.try_damage_teleport(_cover_position, _flank_target):
				_log_to_file("[#1355] Damage-triggered teleport succeeded"); _transition_to_in_cover()

## Shows a brief flash effect when hit.
func _show_hit_flash() -> void:
	if not _enemy_model:
		return

	_set_all_sprites_modulate(hit_flash_color)

	await get_tree().create_timer(hit_flash_duration).timeout
	if not is_inside_tree(): return  # Issue #1334 Round 11: guard freed node after await

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

## Bullet spawn position at muzzle; uses intended aim dir when player visible to avoid transform delay (#264).
func _get_bullet_spawn_position(_direction: Vector2) -> Vector2:
	var muzzle_local_offset := 52.0  # Rifle: offset.x(20) + sprite_width/2(32) = 52px
	if _weapon_sprite and _enemy_model:
		var weapon_forward: Vector2

		# Direct calc to player when visible to avoid transform delay (#264)
		if _player and is_instance_valid(_player) and _can_see_player:
			weapon_forward = (_player.global_position - global_position).normalized()
		else:
			# Use global_transform.x (accounts for scale flip when aiming left)
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

## Returns the weapon's forward direction (normalized, Issue #264).
func _get_weapon_forward_direction() -> Vector2:
	# Direct calc to player when visible to avoid transform delay
	if _player and is_instance_valid(_player) and _can_see_player:
		return (_player.global_position - global_position).normalized()
	# Fallback to transform-based direction
	if _weapon_sprite:
		return _weapon_sprite.global_transform.x.normalized()
	elif _enemy_model:
		return _enemy_model.global_transform.x.normalized()
	elif _player and is_instance_valid(_player):
		return (_player.global_position - global_position).normalized()
	return Vector2.RIGHT

## Updates weapon sprite rotation to match shooting direction with vertical flip handling.
func _update_weapon_sprite_rotation() -> void:
	if not _weapon_sprite:
		return
	var aim_angle: float = rotation
	if _player and is_instance_valid(_player):
		var target_position := _player.global_position
		if enable_lead_prediction and _can_see_player:
			target_position = _calculate_lead_prediction()
		aim_angle = (target_position - global_position).normalized().angle()
	# Local rotation relative to parent (subtract parent rotation to avoid doubling)
	_weapon_sprite.rotation = aim_angle - rotation
	_weapon_sprite.flip_v = absf(aim_angle) > PI / 2.0

## Returns the effective detection delay based on difficulty setting.
func _get_effective_detection_delay() -> float:
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager and difficulty_manager.has_method("get_detection_delay"):
		return difficulty_manager.get_detection_delay()
	# Fall back to export variable if DifficultyManager is not available
	return detection_delay

## Issue #409: Notify nearby enemies of this death so they can observe and enter SEARCHING.
func _notify_nearby_enemies_of_death() -> void:
	var notified := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or not e.has_method("on_ally_died") or not e.has_method("is_alive"): continue
		if not e.is_alive() or e.global_position.distance_to(global_position) > ALLY_DEATH_OBSERVE_RANGE: continue
		e.on_ally_died(global_position, true, _last_hit_direction); notified += 1
	if notified > 0: _log_to_file("[AllyDeath] Notified %d enemies" % notified)

## Called when the enemy dies.
func _on_death() -> void:
	_is_alive = false
	if _invisibility and _invisibility.is_cloaked: _invisibility.remove()  # Issue #1121: reveal enemy on death
	_log_to_file("Enemy died (ricochet: %s, penetration: %s, player_kill: %s)" % [_killed_by_ricochet, _killed_by_penetration, _killed_by_player])
	died.emit()
	died_with_info.emit(_killed_by_ricochet, _killed_by_penetration, _killed_by_player)  # Issue #1196: pass player kill info

	# Issue #959: Immune enemy killed → triggers Level 7
	if _pacifist and _pacifist.is_immune:
		var aim: Node = get_node_or_null("/root/ActiveItemManager")
		var lp: LoudspeakerProgress = aim.get("loudspeaker_progress") if (aim and aim.has_loudspeaker()) else null
		if lp: lp.on_immune_enemy_killed(); _log_to_file("[#959] Immune enemy killed → Level %d" % lp.current_level)
	var pfm = get_node_or_null("/root/PowerFantasyEffectsManager")  # Issue #492: Power Fantasy effect
	if pfm and pfm.has_method("on_enemy_killed"): pfm.on_enemy_killed()
	_notify_nearby_enemies_of_death()  # Issue #409
	_disable_hit_area_collision()  # Disable collision so bullets pass through dead enemies

	# Unregister from sound propagation when dying
	_unregister_sound_listener()

	# Start death animation with the hit direction
	if _death_animation and _death_animation.has_method("start_death_animation"):
		_death_animation.start_death_animation(_last_hit_direction)
		_log_to_file("Death animation started with hit direction: %s" % str(_last_hit_direction))

	if destroy_on_death:
		# Wait for death animation to complete before destroying
		await get_tree().create_timer(respawn_delay).timeout
		if not is_inside_tree(): return  # Issue #1334 Round 11: guard freed node after await
		# Clean up death animation ragdoll bodies before destroying
		if _death_animation and _death_animation.has_method("reset"):
			_death_animation.reset()
		queue_free()
	else:
		await get_tree().create_timer(respawn_delay).timeout
		if not is_inside_tree(): return  # Issue #1334 Round 11: guard freed node after await
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
	_patrol_stuck_timer = 0.0; _patrol_stuck_last_position = Vector2.ZERO
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
	_combat_shoot_timer = 0.0
	_combat_shoot_duration = 2.5
	_combat_exposed = false
	_combat_approaching = false
	_combat_approach_timer = 0.0
	_combat_state_timer = 0.0
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
	_assault_wait_timer = 0.0
	_assault_ready = false
	_in_assault = false
	_flank_cover_wait_timer = 0.0
	_flank_next_cover = Vector2.ZERO
	_has_flank_cover = false
	_flank_state_timer = 0.0
	_flank_stuck_timer = 0.0
	_flank_last_position = Vector2.ZERO
	_flank_fail_count = 0
	_flank_cooldown_timer = 0.0
	_last_known_player_position = Vector2.ZERO
	_pursuing_vulnerability_sound = false
	# Reset ally death observation state (Issue #409)
	_witnessed_ally_death = false
	_suspected_directions.clear()
	_has_left_idle = false  # Issue #921: reset so respawned patrol enemies can timeout from SEARCHING
	_killed_by_ricochet = false; _killed_by_penetration = false; _killed_by_player = false  # Issue #1196
	_initialize_health()
	_initialize_ammo()
	_update_health_visual()
	_initialize_goap_state()
	_enable_hit_area_collision()
	_register_sound_listener()

## Disables hit area collision so bullets pass through dead enemies (multiple approaches due to Godot Area2D limits).
func _disable_hit_area_collision() -> void:
	if _hit_collision_shape:
		_hit_collision_shape.set_deferred("disabled", true)
	if _hit_area:
		_hit_area.set_deferred("collision_layer", 0)
		_hit_area.set_deferred("collision_mask", 0)
		_hit_area.set_deferred("monitorable", false)
		_hit_area.set_deferred("monitoring", false)

## Re-enables hit area collision after respawning (restores all collision properties).
func _enable_hit_area_collision() -> void:
	if _hit_collision_shape: _hit_collision_shape.disabled = false
	if _hit_area:
		_hit_area.collision_layer = _original_hit_area_layer; _hit_area.collision_mask = _original_hit_area_mask
		_hit_area.monitorable = true; _hit_area.monitoring = true

## Returns whether this enemy is currently alive (used by bullets to check pass-through).
func is_alive() -> bool:
	return _is_alive

## Initialize the death animation component.
func _init_death_animation() -> void:
	_death_animation = DeathAnimationComponent.new(); _death_animation.name = "DeathAnimation"; add_child(_death_animation)
	_death_animation.initialize(_body_sprite, _head_sprite, _left_arm_sprite, _right_arm_sprite, _enemy_model)
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

func _log_debug(message: String) -> void:
	if debug_logging: print("[Enemy %s] %s" % [name, message])
func _log_to_file(message: String) -> void:
	if not is_inside_tree(): return
	var fl := get_node_or_null("/root/FileLogger")
	if fl and fl.has_method("log_enemy"): fl.log_enemy(name, message)
func _log_spawn_info() -> void:
	_log_to_file("Spawned at %s, hp: %d, behavior: %s" % [global_position, _max_health, BehaviorMode.keys()[behavior_mode]])
func _get_state_name(state: AIState) -> String:
	return AIState.keys()[state] if state >= 0 and state < AIState.size() else "UNKNOWN"

func _update_debug_label() -> void:
	if _debug_label == null: return
	_debug_label.visible = debug_label_enabled
	if not debug_label_enabled: return
	var t := _get_state_name(_current_state)
	match _current_state:
		AIState.RETREATING: t += "\n(%s)" % RetreatMode.keys()[_retreat_mode]
		AIState.ASSAULT: t += "\n(RUSHING)" if _assault_ready else "\n(%.1fs)" % (ASSAULT_WAIT_DURATION - _assault_wait_timer)
		AIState.COMBAT:
			if _combat_exposed: t += "\n(EXPOSED %.1fs)" % (_combat_shoot_duration - _combat_shoot_timer)
			elif _seeking_clear_shot: t += "\n(SEEK SHOT %.1fs)" % (CLEAR_SHOT_MAX_TIME - _clear_shot_timer)
			elif _combat_approaching: t += "\n(APPROACH)"
		AIState.PURSUING:
			if _pursuit_approaching: t += "\n(APPROACH %.1fs)" % (PURSUIT_APPROACH_MAX_TIME - _pursuit_approach_timer)
			elif _has_valid_cover and not _has_pursuit_cover: t += "\n(WAIT %.1fs)" % (PURSUIT_COVER_WAIT_DURATION - _pursuit_cover_wait_timer)
			elif _has_pursuit_cover: t += "\n(MOVING)"
		AIState.FLANKING:
			var s := "R" if _flank_side > 0 else "L"
			if _has_valid_cover and not _has_flank_cover: t += "\n(%s WAIT %.1fs)" % [s, FLANK_COVER_WAIT_DURATION - _flank_cover_wait_timer]
			elif _has_flank_cover: t += "\n(%s MOVING)" % s
			else: t += "\n(%s DIRECT)" % s
	if _memory and _memory.has_target(): t += "\n[%.0f%% %s]" % [_memory.confidence * 100, _memory.get_behavior_mode().substr(0, 6)]
	if _prediction: t += _prediction.get_debug_text()
	if _is_blinded or _is_stunned: t += "\n{%s}" % ("BLINDED + STUNNED" if _is_blinded and _is_stunned else "BLINDED" if _is_blinded else "STUNNED")
	if _aggression: t += _aggression.get_debug_text()
	if _tactical_movement: var _tm_info := _tactical_movement.get_debug_info(); if _tm_info != "": t += "\n" + _tm_info  # Issue #1249
	if _tactical_group: var _tg_info := _tactical_group.get_debug_info(); if _tg_info != "": t += "\n" + _tg_info  # Issue #1287
	_debug_label.text = t

func get_current_state() -> AIState: return _current_state
func get_goap_world_state() -> Dictionary: return _goap_world_state.duplicate()
## Returns a copy of the active search waypoints (Issue #1251: used by SearchPathMonitor for visualization).
func get_search_waypoints() -> Array[Vector2]: return _search_waypoints.duplicate()
## Returns the current search waypoint index (Issue #1251: used by SearchPathMonitor for visualization).
func get_search_current_waypoint_index() -> int: return _search_current_waypoint_index
## Returns the current NavigationAgent2D computed path in global coordinates (Issue #1277: used by EnemyPathMonitor for visualization).
## Returns an empty array if the navigation agent is unavailable or no path is computed.
func get_nav_path() -> PackedVector2Array:
	if _nav_agent == null: return PackedVector2Array()
	return _nav_agent.get_current_navigation_path()

## Returns cover raycast collision data for debug visualization (Issue #1359: CoverRaycastMonitor).
func get_cover_raycast_data() -> Array:
	return _last_cover_search_rays

## Returns the current cover position and whether it is valid (Issue #1359: CoverRaycastMonitor).
func get_cover_info() -> Dictionary:
	return { "position": _cover_position, "valid": _has_valid_cover }

func set_player_reloading(is_reloading: bool) -> void:
	var old: bool = _goap_world_state.get("player_reloading", false)
	_goap_world_state["player_reloading"] = is_reloading
	if is_reloading != old: _log_to_file("Player reloading: %s -> %s" % [old, is_reloading])
func set_player_ammo_empty(is_empty: bool) -> void:
	var old: bool = _goap_world_state.get("player_ammo_empty", false)
	_goap_world_state["player_ammo_empty"] = is_empty
	if is_empty != old: _log_to_file("Player ammo empty: %s -> %s" % [old, is_empty])
func is_under_fire() -> bool: return _under_fire
func is_in_cover() -> bool: return _current_state == AIState.IN_COVER or _current_state == AIState.SUPPRESSED
func get_current_ammo() -> int: return _current_ammo
func get_reserve_ammo() -> int: return _reserve_ammo
func get_total_ammo() -> int: return _current_ammo + _reserve_ammo
func is_reloading() -> bool: return _is_reloading
func has_ammo() -> bool: return _current_ammo > 0 or _reserve_ammo > 0
func get_player_visibility_ratio() -> float: return _player_visibility_ratio

## Draw debug visualization when debug mode is enabled.
func _draw() -> void:
	if not debug_label_enabled:
		return

	var color_to_cover := Color.CYAN; var color_to_player := Color.RED
	var color_clear_shot := Color.YELLOW; var color_pursuit := Color.ORANGE
	var color_flank := Color.MAGENTA; var color_bullet_spawn := Color.GREEN; var color_blocked := Color.RED
	# FOV cone: green=active, gray=disabled
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	var global_fov_enabled := false
	if experimental_settings and experimental_settings.has_method("is_fov_enabled"):
		global_fov_enabled = experimental_settings.is_fov_enabled()
	var fov_active := global_fov_enabled and fov_enabled and fov_angle > 0.0
	var color_fov: Color; var color_fov_edge: Color
	if fov_active:
		color_fov = Color(0.2, 0.8, 0.2, 0.3); color_fov_edge = Color(0.2, 0.8, 0.2, 0.8)
	else:
		color_fov = Color(0.5, 0.5, 0.5, 0.2); color_fov_edge = Color(0.5, 0.5, 0.5, 0.5)
	if fov_angle > 0.0:
		_draw_fov_cone(color_fov, color_fov_edge)
	if _can_see_player and _player:
		draw_line(Vector2.ZERO, _player.global_position - global_position, color_to_player, 1.5)
	if _can_see_companion and _companion != null:  # Issue #934
		draw_line(Vector2.ZERO, _companion.global_position - global_position, Color.ORANGE, 1.5)
		var weapon_forward := _get_weapon_forward_direction()
		var spawn_point := _get_bullet_spawn_position(weapon_forward) - global_position
		if _is_bullet_spawn_clear(weapon_forward):
			draw_circle(spawn_point, 5.0, color_bullet_spawn)
		else:
			draw_line(spawn_point + Vector2(-5, -5), spawn_point + Vector2(5, 5), color_blocked, 2.0)
			draw_line(spawn_point + Vector2(-5, 5), spawn_point + Vector2(5, -5), color_blocked, 2.0)
	if _has_valid_cover:
		var to_cover := _cover_position - global_position
		draw_line(Vector2.ZERO, to_cover, color_to_cover, 1.5); draw_circle(to_cover, 8.0, color_to_cover)
	if _seeking_clear_shot and _clear_shot_target != Vector2.ZERO:
		var to_target := _clear_shot_target - global_position
		draw_line(Vector2.ZERO, to_target, color_clear_shot, 2.0)
		draw_line(to_target + Vector2(-6, 6), to_target + Vector2(6, 6), color_clear_shot, 2.0)
		draw_line(to_target + Vector2(6, 6), to_target + Vector2(0, -8), color_clear_shot, 2.0)
		draw_line(to_target + Vector2(0, -8), to_target + Vector2(-6, 6), color_clear_shot, 2.0)
	if _current_state == AIState.PURSUING and _has_pursuit_cover:
		var to_pursuit := _pursuit_next_cover - global_position
		draw_line(Vector2.ZERO, to_pursuit, color_pursuit, 2.0); draw_circle(to_pursuit, 8.0, color_pursuit)
	if _current_state == AIState.FLANKING:
		if _has_flank_cover:
			var to_flank_cover := _flank_next_cover - global_position
			draw_line(Vector2.ZERO, to_flank_cover, color_flank, 2.0); draw_circle(to_flank_cover, 8.0, color_flank)
		elif _flank_target != Vector2.ZERO:
			var to_flank := _flank_target - global_position
			draw_line(Vector2.ZERO, to_flank, color_flank, 1.5)
			draw_line(to_flank + Vector2(0, -8), to_flank + Vector2(8, 0), color_flank, 2.0)
			draw_line(to_flank + Vector2(8, 0), to_flank + Vector2(0, 8), color_flank, 2.0)
			draw_line(to_flank + Vector2(0, 8), to_flank + Vector2(-8, 0), color_flank, 2.0)
			draw_line(to_flank + Vector2(-8, 0), to_flank + Vector2(0, -8), color_flank, 2.0)
	# Issue #297: Draw suspected pos from memory — uncertainty circle radius ∝ 1/confidence (10–100px).
	if _memory and _memory.has_target():
		var to_suspected := _memory.suspected_position - global_position
		var confidence_color := Color.YELLOW.lerp(Color.ORANGE_RED, _memory.confidence)
		draw_line(Vector2.ZERO, to_suspected, confidence_color, 1.0)
		var uncertainty_radius := 10.0 + (1.0 - _memory.confidence) * 90.0
		var segments := 16
		for i in range(segments):
			var angle1 := (float(i) / segments) * TAU; var angle2 := (float(i + 1) / segments) * TAU
			draw_line(to_suspected + Vector2(cos(angle1), sin(angle1)) * uncertainty_radius, to_suspected + Vector2(cos(angle2), sin(angle2)) * uncertainty_radius, confidence_color, 1.5)
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

## Get direction to follow NavigationAgent2D path toward target_pos. Returns Vector2.ZERO if finished.
func _get_nav_direction_to(target_pos: Vector2) -> Vector2:
	if _nav_agent == null: return (target_pos - global_position).normalized()
	_nav_agent.target_position = target_pos
	if _nav_agent.is_navigation_finished(): return Vector2.ZERO
	return (_nav_agent.get_next_path_position() - global_position).normalized()

## Move toward target_pos using NavigationAgent2D. Returns true if moving, false if reached or unavailable.
func _move_to_target_nav(target_pos: Vector2, speed: float) -> bool:
	# Issue #1249: Tactical yielding — let closest enemy pass first. Skip in FLANKING (#1249 s4).
	if _tactical_movement and _current_state in [AIState.PURSUING, AIState.COMBAT]:
		if _tactical_movement.check_and_yield(target_pos, speed, get_physics_process_delta_time()):
			var _wp: Vector2 = _tactical_movement.get_yield_position()
			if _wp != Vector2.ZERO and global_position.distance_to(_wp) > 20.0:
				var _wd := _apply_wall_avoidance((_wp - global_position).normalized())
				velocity = _wd * speed * 0.6; if velocity.length_squared() > 0.01: _rotate_body_toward(velocity.angle(), get_physics_process_delta_time())
			else: velocity = Vector2.ZERO
			return true
	# Issue #1287: Tactical group encirclement — offset approach target so enemies spread around the player.
	if _tactical_group and _current_state in [AIState.PURSUING, AIState.COMBAT, AIState.ASSAULT]:
		target_pos = _tactical_group.get_adjusted_target(target_pos, get_physics_process_delta_time())
	var direction: Vector2 = _get_nav_direction_to(target_pos)
	if direction == Vector2.ZERO: velocity = Vector2.ZERO; return false
	direction = _apply_wall_avoidance(direction)
	# Issue #1107: Corner escape — use escape-dominant weight (1.5) when wall opposes nav dir
	var _esc: Vector2 = Vector2.ZERO
	for _si: int in range(get_slide_collision_count()): _esc += get_slide_collision(_si).get_normal()
	if _esc.length_squared() > 0.01: var _en := _esc.normalized(); direction = (direction + _en * (1.5 if _en.dot(direction) < -0.5 else 0.6)).normalized()
	elif velocity.length_squared() < 1.0:
		var _p := move_and_collide(direction * 2.0, true); if _p: direction = (direction + _p.get_normal() * 0.8).normalized()
	var intended_vel: Vector2 = direction * speed
	# Issue #1146: Feed intended velocity to NavigationAgent2D ORCA so it can steer us away from other agents.
	if _nav_agent and _nav_agent.avoidance_enabled:
		_nav_agent.set_velocity(intended_vel)
		# _avoidance_velocity is set asynchronously via _on_avoidance_velocity_computed.
		# Fall back to intended_vel on the first frame before the callback fires.
		velocity = _avoidance_velocity if _avoidance_velocity.length_squared() > 0.01 else intended_vel
	else:
		velocity = intended_vel
	if velocity.length_squared() > 0.01: _rotate_body_toward(velocity.angle(), get_physics_process_delta_time())
	return true

## Issue #1146: Called by NavigationAgent2D when ORCA computes a safe avoidance velocity.
func _on_avoidance_velocity_computed(safe_velocity: Vector2) -> void:
	_avoidance_velocity = safe_velocity

## Issue #1146: Separation steering — push away from nearby allies.
## Issue #1249: Skip separation while yielding so the passing enemy isn't pushed aside.
func _apply_separation_force(vel: Vector2, delta: float) -> Vector2:
	if _tactical_movement and _tactical_movement.is_yielding: return vel  # #1249: yielding — don't push
	var sep_force: Vector2 = Vector2.ZERO
	for body in get_tree().get_nodes_in_group("enemies"):
		if body == self or not is_instance_valid(body): continue
		var diff: Vector2 = global_position - (body as Node2D).global_position
		var dist: float = diff.length()
		if dist < SEPARATION_RADIUS and dist > 0.1: sep_force += diff.normalized() * (SEPARATION_RADIUS - dist) / SEPARATION_RADIUS
	if sep_force != Vector2.ZERO: vel += sep_force * SEPARATION_STRENGTH * delta
	return vel

## Check if the navigation agent has a valid path to the target.
func _has_nav_path_to(target_pos: Vector2) -> bool:
	if _nav_agent == null: return false
	_nav_agent.target_position = target_pos
	return not _nav_agent.is_navigation_finished()
## Get distance to target along the navigation path (more accurate than straight-line).
func _get_nav_path_distance(target_pos: Vector2) -> float:
	if _nav_agent == null: return global_position.distance_to(target_pos)
	_nav_agent.target_position = target_pos
	return _nav_agent.distance_to_target()

# Status Effects (Blindness, Stun) - delegated to FlashbangStatusComponent (Issue #328)
func _setup_flashbang_status() -> void:
	_flashbang_status = FlashbangStatusComponent.new()
	_flashbang_status.name = "FlashbangStatusComponent"
	_flashbang_status.blinded_changed.connect(_on_blinded_changed)
	_flashbang_status.stunned_changed.connect(_on_stunned_changed)
	add_child(_flashbang_status)

func _on_blinded_changed(blinded: bool) -> void:
	_is_blinded = blinded
	if _status_effect_anim: _status_effect_anim.set_blinded(blinded)
	if blinded: _can_see_player = false; _continuous_visibility_timer = 0.0
func _on_stunned_changed(stunned: bool) -> void:
	_is_stunned = stunned
	if _status_effect_anim: _status_effect_anim.set_stunned(stunned)
	if stunned: velocity = Vector2.ZERO

func set_blinded(blinded: bool) -> void:
	if _flashbang_status: _flashbang_status.set_blinded(blinded)
func set_stunned(stunned: bool) -> void:
	if _flashbang_status: _flashbang_status.set_stunned(stunned)
func is_blinded() -> bool: return _is_blinded
func is_stunned() -> bool: return _is_stunned
func _setup_aggression_component() -> void:  ## [Issue #675]
	_aggression = AggressionComponent.new(); _aggression.name = "AggressionComponent"; add_child(_aggression)
	_aggression.aggression_changed.connect(func(a): if _status_effect_anim: _status_effect_anim.set_aggressive(a); if a and _current_state in [AIState.IDLE, AIState.IN_COVER]: _transition_to_combat())
func set_aggressive(a: bool) -> void: if _aggression: _aggression.set_aggressive(a)
func is_aggressive() -> bool: return _aggression != null and _aggression.is_aggressive()
## Apply flashbang effect (Issue #432). Called by C# GrenadeTimer.
func apply_flashbang_effect(blindness_duration: float, stun_duration: float) -> void:
	if _flashbang_status: _flashbang_status.apply_flashbang_effect(blindness_duration, stun_duration)
func is_shield_active() -> bool: return _shield_component != null and _shield_component.is_active()  ## Issue #1242
func apply_knockback(impulse: Vector2) -> void: _knockback_velocity = impulse  ## Issue #1242: shield break stagger
func set_formation_follow_target(shielder: Node2D, pos: Vector2) -> void: _formation_shielder = shielder; _formation_target_pos = pos  ## Issue #1242
# Grenade System (Issue #363) - Component-based (extracted for Issue #377)
## Setup the grenade component. Called from _ready(). Grenadiers use GrenadierGrenadeComponent (Issue #604).
func _setup_grenade_component() -> void:
	if not enable_grenade_throwing: return
	if is_grenadier:
		_grenade_component = GrenadierGrenadeComponent.new(); _grenade_component.enabled = true
	else:
		_grenade_component = EnemyGrenadeComponent.new()
		_grenade_component.grenade_count = grenade_count; _grenade_component.grenade_scene = grenade_scene; _grenade_component.enabled = enable_grenade_throwing
	_grenade_component.name = "GrenadeComponent"; _grenade_component.throw_cooldown = grenade_throw_cooldown
	_grenade_component.inaccuracy = grenade_inaccuracy; _grenade_component.max_throw_distance = grenade_max_throw_distance
	_grenade_component.throw_delay = grenade_throw_delay; _grenade_component.min_throw_distance = grenade_min_throw_distance
	_grenade_component.debug_logging = grenade_debug_logging; _grenade_component.safety_margin = grenade_safety_margin
	add_child(_grenade_component); _grenade_component.initialize()
	_grenade_component.face_throw_direction.connect(_on_grenade_face_throw_direction)  # Issue #712: pre-throw rotation
	_grenade_component.grenade_thrown.connect(_on_grenade_component_thrown)  # Issue #712: clear facing after throw
	if is_grenadier:  # Connect grenadier signals + vest visual (Issue #604)
		var gc := _grenade_component as GrenadierGrenadeComponent
		gc.grenade_incoming.connect(_on_grenadier_grenade_incoming); gc.grenade_exploded_safe.connect(_on_grenadier_grenade_exploded)
		if _enemy_model:  # Add grenade vest overlay sprite
			var vest := Sprite2D.new(); vest.texture = load("res://assets/sprites/characters/enemy/grenadier_vest.png")
			vest.name = "GrenadierVest"; vest.z_index = 2; vest.position = Vector2(-4, 0); _enemy_model.add_child(vest)
func _update_grenade_triggers(delta: float) -> void:
	if _grenade_component == null: return
	# Issue #934: pass best target (player or companion) to grenade component
	var grenade_target := _current_target if _current_target != null else _player
	var can_see_target := _can_see_player or _can_see_companion
	_grenade_component.update(delta, can_see_target, _under_fire, grenade_target, _current_health, _memory)
	_update_grenade_world_state()

func _on_gunshot_heard_for_grenade(position: Vector2) -> void:
	if _grenade_component: _grenade_component.on_gunshot(position)
func _on_vulnerable_sound_heard_for_grenade(position: Vector2) -> void:
	if _grenade_component: _grenade_component.on_vulnerable_sound(position, _can_see_player)
## Issue #712: Grenade throw facing - set direction before throw, clear after throw completes.
func _on_grenade_face_throw_direction(target_direction: Vector2) -> void:
	if target_direction == Vector2.ZERO: return
	_grenade_throw_facing_direction = target_direction; _is_facing_for_grenade_throw = true
func _on_grenade_component_thrown(_grenade: Node, _target_position: Vector2) -> void:
	_grenade_throw_facing_direction = Vector2.ZERO; _is_facing_for_grenade_throw = false
## Called when ally dies. Handles grenade awareness (#407) and death observation (#409).
func on_ally_died(ally_position: Vector2, killer_is_player: bool, hit_direction: Vector2 = Vector2.ZERO) -> void:
	if _grenade_component: _grenade_component.on_ally_died(ally_position, killer_is_player, _is_position_in_fov(ally_position) and _can_see_position(ally_position))
	if not _is_alive: return
	if _current_state in [AIState.COMBAT, AIState.SUPPRESSED, AIState.RETREATING]: return
	var distance := global_position.distance_to(ally_position)
	if distance > ALLY_DEATH_OBSERVE_RANGE or not _is_position_in_fov(ally_position) or not _can_see_position(ally_position): return
	_calculate_suspected_directions(ally_position, hit_direction)
	_witnessed_ally_death = true; _goap_world_state["witnessed_ally_death"] = true
	if hit_direction != Vector2.ZERO and _memory:
		var susp_dir := -hit_direction.normalized()
		_memory.update_position(ally_position + susp_dir * 200.0, ALLY_DEATH_CONFIDENCE)
	_log_to_file("[AllyDeath] Witnessed at %s, entering SEARCHING" % ally_position)
	_transition_to_searching(ally_position)
## Calculate suspected directions from bullet hit direction (Issue #409).
func _calculate_suspected_directions(death_position: Vector2, hit_direction: Vector2) -> void:
	_suspected_directions.clear()
	if hit_direction == Vector2.ZERO:
		_suspected_directions.append((global_position - death_position).normalized()); return
	var primary := -hit_direction.normalized()
	_suspected_directions.append(primary)
	_suspected_directions.append(Vector2(-primary.y, primary.x))  # perp left
	_suspected_directions.append(Vector2(primary.y, -primary.x))  # perp right
func _can_see_position(pos: Vector2) -> bool:
	if _raycast == null: return false
	var orig := _raycast.target_position
	_raycast.target_position = pos - global_position
	_raycast.force_raycast_update()
	var result := not _raycast.is_colliding()
	_raycast.target_position = orig; return result
func _update_grenade_world_state() -> void:
	if _grenade_component == null:
		_goap_world_state["has_grenades"] = false; _goap_world_state["grenades_remaining"] = 0
		_goap_world_state["ready_to_throw_grenade"] = false; _goap_world_state["grenadier_throw_ready"] = false; return
	var rdy := _grenade_component.is_ready(_can_see_player, _under_fire, _current_health)
	_goap_world_state["has_grenades"] = _grenade_component.grenades_remaining > 0
	_goap_world_state["grenades_remaining"] = _grenade_component.grenades_remaining
	_goap_world_state["ready_to_throw_grenade"] = rdy; _goap_world_state["grenadier_throw_ready"] = is_grenadier and rdy
## Attempt to throw a grenade (Issue #824: night mode flash). Returns true if throw initiated.
func try_throw_grenade() -> bool:
	if _grenade_component == null: return false
	var mem_pos := _memory.suspected_position if _memory and _memory.has_target() else _last_known_player_position
	var tgt := _grenade_component.get_target(_can_see_player, _under_fire, _current_health, _player, _last_known_player_position, mem_pos)
	if tgt == Vector2.ZERO: return false
	if _enemy_flashlight:  # Issue #824/#825: block throw while flashlight flash is in progress
		if not _is_pre_attack_flashing: _is_pre_attack_flashing = true; _enemy_flashlight.start_pre_attack_flash(tgt, _execute_grenade_throw.bind(tgt))
		return true  # Callback fires the throw after flash completes
	return _execute_grenade_throw(tgt)
func _execute_grenade_throw(tgt: Vector2) -> bool:  ## Issue #824: grenade throw callback.
	_is_pre_attack_flashing = false; if _invisibility: _invisibility.reveal()  # Issue #1121: reveal on grenade throw
	var result := _grenade_component.try_throw(tgt, _is_alive, _is_stunned, _is_blinded)
	if result: grenade_thrown.emit(null, tgt)
	return result
# Grenade Avoidance (Issue #407) - uses GrenadeAvoidanceComponent
func _setup_grenade_avoidance() -> void:
	_grenade_avoidance = GrenadeAvoidanceComponent.new()
	_grenade_avoidance.name = "GrenadeAvoidance"
	add_child(_grenade_avoidance)
	if _raycast: _grenade_avoidance.set_raycast(_raycast)  # Issue #426: LOS check (enemies only react to visible grenades)
	if _enemy_model: _grenade_avoidance.set_fov_parameters(_enemy_model, fov_angle, fov_enabled)  # Issue #426: FOV cone filter
func _update_grenade_danger_detection() -> void:
	if _grenade_avoidance: _grenade_avoidance.update()
func _calculate_grenade_evasion_target() -> void:
	if _grenade_avoidance: _grenade_avoidance.calculate_evasion_target(_nav_agent)
func get_grenades_remaining() -> int: return _grenade_component.grenades_remaining if _grenade_component else 0
func add_grenades(count: int) -> void:
	if _grenade_component: _grenade_component.add_grenades(count)
# Grenadier Coordination (Issue #604)
func _on_grenadier_grenade_incoming(grenade_pos: Vector2, effect_radius: float, fuse_time: float) -> void:
	var parent := get_parent()
	if parent == null: return
	for ally in parent.get_children():
		if ally == self or not is_instance_valid(ally): continue
		if ally.has_method("_start_waiting_for_grenadier") and ally.global_position.distance_to(grenade_pos) < effect_radius * 1.5 + 200.0:
			ally._start_waiting_for_grenadier(fuse_time + 1.0)
func _on_grenadier_grenade_exploded() -> void:
	var parent := get_parent()
	if parent == null: return
	for ally in parent.get_children():
		if ally == self or not is_instance_valid(ally): continue
		if ally.has_method("_stop_waiting_for_grenadier"): ally._stop_waiting_for_grenadier()
func _start_waiting_for_grenadier(wt: float) -> void: _waiting_for_grenadier = true; _grenadier_wait_timer = min(wt, 8.0)
func _stop_waiting_for_grenadier() -> void: _waiting_for_grenadier = false; _grenadier_wait_timer = 0.0
func get_is_grenadier() -> bool: return is_grenadier
func is_waiting_for_grenade() -> bool: return _waiting_for_grenadier
## Issue #657: Non-idle allies near a pursuing grenadier with grenades wait for it to throw.
func _should_wait_for_nearby_grenadier() -> bool:
	if is_grenadier or _current_state == AIState.IDLE: return false
	var parent := get_parent(); if parent == null: return false
	for ally in parent.get_children():
		if ally == self or not is_instance_valid(ally): continue
		if not (ally.has_method("get_is_grenadier") and ally.get_is_grenadier()): continue
		if not (ally.has_method("get_grenades_remaining") and ally.get_grenades_remaining() > 0): continue
		if global_position.distance_to(ally.global_position) >= 400.0: continue
		if ally.has_method("is_blocking_passage_grenade") and ally.is_blocking_passage_grenade(): return true
		if ally.get("_current_state") == AIState.PURSUING: _start_waiting_for_grenadier(3.0); return true
	return false
func is_blocking_passage_grenade() -> bool: return _grenade_component is GrenadierGrenadeComponent and (_grenade_component as GrenadierGrenadeComponent).is_blocking_passage()  ## Issue #657: coordination
## Setup machete melee component (Issue #579).
func _setup_machete_component() -> void:
	if not _is_melee_weapon: return
	_machete = MacheteComponent.new(); _machete.name = "MacheteComponent"; _machete.debug_logging = debug_logging
	_machete.configure_from_weapon_config(WeaponConfigComponent.get_config(weapon_type)); add_child(_machete)
	_current_ammo = 0; _reserve_ammo = 0; _is_reloading = false
	full_health_color = Color(0.7, 0.15, 0.15, 1.0); _update_health_visual()
## Switch from RPG to secondary weapon (PM pistol) after firing rocket (Issue #583).
func _switch_to_secondary_weapon() -> void:
	var sc := WeaponConfigComponent.get_config(WeaponConfigComponent.get_config(weapon_type).get("switch_weapon_type", 0))
	shoot_cooldown = sc["shoot_cooldown"]; bullet_speed = sc["bullet_speed"]; magazine_size = sc["magazine_size"]; bullet_spawn_offset = sc["bullet_spawn_offset"]; weapon_loudness = sc["weapon_loudness"]
	if sc.get("bullet_scene_path", "") != "": var s := load(sc["bullet_scene_path"]) as PackedScene; if s: bullet_scene = s
	if sc.get("casing_scene_path", "") != "": var s2 := load(sc["casing_scene_path"]) as PackedScene; if s2: casing_scene = s2
	if sc.get("caliber_path", "") != "": _caliber_data = load(sc["caliber_path"])
	_is_shotgun_weapon = sc.get("is_shotgun", false); _is_rpg_weapon = false; _spread_threshold = sc.get("spread_threshold", 3); _initial_spread = sc.get("initial_spread", 0.5)
	_spread_increment = sc.get("spread_increment", 0.6); _max_spread = sc.get("max_spread", 4.0); _spread_reset_time = sc.get("spread_reset_time", 0.25); _shot_count = 0; _spread_timer = 0.0
	_current_ammo = magazine_size; _reserve_ammo = (total_magazines - 1) * magazine_size; _is_reloading = false; _reload_timer = 0.0
	if sc.get("sprite_path", "") != "" and _weapon_sprite:  # Issue #583: update weapon sprite to PM
		var tex := load(sc["sprite_path"]) as Texture2D; if tex: _weapon_sprite.texture = tex
	if OS.is_debug_build(): print("[Enemy] RPG fired, switched to secondary weapon (PM)")
## Setup enemy flashlight for night mode (Issue #824).
func _setup_enemy_flashlight() -> void:
	_enemy_flashlight = EnemyFlashlightComponent.new(); _enemy_flashlight.debug_logging = debug_logging; add_child(_enemy_flashlight)
## Apply machete attack animation to weapon mount and arms (Issue #595).
func _apply_machete_attack_animation() -> void:
	if not _is_melee_weapon or _machete == null: return
	if _weapon_mount: _weapon_mount.rotation = _machete.get_weapon_rotation() if _machete.is_attacking() else 0.0
	if _machete.is_attacking() and _right_arm_sprite: _right_arm_sprite.position.x += _machete.get_arm_offset()
## Connect CasingPusher Area2D signals (Issue #438, same pattern as player Issue #392).
func _connect_casing_pusher_signals() -> void:
	if _casing_pusher == null: return
	if not _casing_pusher.body_entered.is_connected(_on_casing_pusher_body_entered): _casing_pusher.body_entered.connect(_on_casing_pusher_body_entered)
	if not _casing_pusher.body_exited.is_connected(_on_casing_pusher_body_exited): _casing_pusher.body_exited.connect(_on_casing_pusher_body_exited)
func _on_casing_pusher_body_entered(body: Node2D) -> void:
	if body is RigidBody2D and body.has_method("receive_kick") and body not in _overlapping_casings: _overlapping_casings.append(body)
func _on_casing_pusher_body_exited(body: Node2D) -> void:
	if body is RigidBody2D:
		var idx := _overlapping_casings.find(body); if idx >= 0: _overlapping_casings.remove_at(idx)
