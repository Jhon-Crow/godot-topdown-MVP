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

# ============================================================================
# Grenade System Configuration (Issue #363)
# ============================================================================

## Number of grenades this enemy carries. Set by DifficultyManager or per-enemy override.
## Default 0 means no grenades unless configured by difficulty/map settings.
@export var grenade_count: int = 0

## Grenade scene to instantiate when throwing.
@export var grenade_scene: PackedScene

## Enable/disable grenade throwing behavior.
@export var enable_grenade_throwing: bool = true

## Minimum cooldown between grenade throws (prevents spam).
@export var grenade_throw_cooldown: float = 15.0

## Maximum throw distance for grenades (pixels).
@export var grenade_max_throw_distance: float = 600.0

## Minimum throw distance for grenades (pixels) - prevents point-blank throws.
## Updated to 275.0 to account for frag grenade blast radius (225) + safety margin (50).
## Per issue #375: Enemy should not throw grenades that would damage itself.
@export var grenade_min_throw_distance: float = 275.0

## Safety margin to add to blast radius for safe grenade throws (pixels).
## Enemy must be at least (blast_radius + safety_margin) from target to throw safely.
## Per issue #375: Prevents enemy from being caught in own grenade blast.
@export var grenade_safety_margin: float = 50.0

## Inaccuracy spread when throwing grenades (radians).
@export var grenade_inaccuracy: float = 0.15

## Delay before throwing grenade (seconds) - allows animation/telegraph.
@export var grenade_throw_delay: float = 0.4

## Enable grenade debug logging (separate from general debug_logging).
@export var grenade_debug_logging: bool = false

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

## Timer for periodic turning to cover during FULL_HP retreat.
var _retreat_turn_timer: float = 0.0

## Duration to face cover during FULL_HP retreat turn (seconds).
const RETREAT_TURN_DURATION: float = 0.8

## Interval between turns toward cover in FULL_HP retreat (seconds).
const RETREAT_TURN_INTERVAL: float = 1.5

## Whether currently in the "turn to cover" phase of FULL_HP retreat.
var _retreat_turning_to_cover: bool = false

## Burst fire counter for ONE_HIT retreat mode.
var _retreat_burst_remaining: int = 0

## Timer for burst fire cooldown in ONE_HIT retreat.
var _retreat_burst_timer: float = 0.0

## Fast cooldown between burst shots (seconds).
const RETREAT_BURST_COOLDOWN: float = 0.06

## Whether burst fire phase is complete in ONE_HIT retreat.
var _retreat_burst_complete: bool = false

## Accuracy reduction during retreat (multiplier for inaccuracy angle spread).
const RETREAT_INACCURACY_SPREAD: float = 0.15

## Arc spread for ONE_HIT burst fire (radians, total spread).
const RETREAT_BURST_ARC: float = 0.4

## Current angle offset within burst arc.
var _retreat_burst_angle_offset: float = 0.0

## Alarm mode: was suppressed/retreating, persists until reaching cover or IDLE.
var _in_alarm_mode: bool = false

## Whether the enemy needs to fire a cover burst (when leaving cover while in alarm).
var _cover_burst_pending: bool = false

## --- Combat Cover Cycling (come out, shoot 2-3s, go back) ---
## Timer for how long the enemy has been shooting while out of cover.
var _combat_shoot_timer: float = 0.0

## Duration to shoot while out of cover (2-3 seconds, randomized).
var _combat_shoot_duration: float = 2.5

## Whether the enemy is currently in the "exposed shooting" phase of combat.
var _combat_exposed: bool = false

## Approaching player phase: moving toward player for direct contact.
var _combat_approaching: bool = false

## Timer for the approach phase of combat.
var _combat_approach_timer: float = 0.0

## Total COMBAT time this cycle (prevents thrashing on visibility flicker).
var _combat_state_timer: float = 0.0

## Maximum time to spend approaching player before starting to shoot (seconds).
const COMBAT_APPROACH_MAX_TIME: float = 2.0

## Distance at which enemy is considered "close enough" to start shooting phase.
const COMBAT_DIRECT_CONTACT_DISTANCE: float = 250.0

## Min COMBAT time before PURSUING (prevents thrashing at wall edges).
const COMBAT_MIN_DURATION_BEFORE_PURSUE: float = 0.5

## --- Pursuit State (cover-to-cover movement) ---
## Timer for waiting at cover during pursuit.
var _pursuit_cover_wait_timer: float = 0.0

## Duration to wait at each cover during pursuit (1-2 seconds, reduced for faster pursuit).
const PURSUIT_COVER_WAIT_DURATION: float = 1.5

## Current pursuit target cover position.
var _pursuit_next_cover: Vector2 = Vector2.ZERO

## Whether the enemy has a valid pursuit cover target.
var _has_pursuit_cover: bool = false

## Current cover obstacle collider (penalizes selecting same obstacle again).
var _current_cover_obstacle: Object = null
## Approach phase: at last cover, moving toward player with no better cover.
var _pursuit_approaching: bool = false

## Timer for approach phase during pursuit.
var _pursuit_approach_timer: float = 0.0

## Total PURSUING time this cycle (prevents thrashing on visibility flicker).
var _pursuing_state_timer: float = 0.0

## Maximum time to approach during pursuit before transitioning to COMBAT (seconds).
const PURSUIT_APPROACH_MAX_TIME: float = 3.0

## Min PURSUING time before COMBAT (prevents thrashing at wall edges).
const PURSUING_MIN_DURATION_BEFORE_COMBAT: float = 0.3
## Min progress fraction for valid pursuit cover (must get at least 10% closer).
const PURSUIT_MIN_PROGRESS_FRACTION: float = 0.10
## Penalty for same-obstacle cover (prevents shuffling along same wall).
const PURSUIT_SAME_OBSTACLE_PENALTY: float = 4.0

## --- Flanking State (cover-to-cover movement toward flank target) ---
## Timer for waiting at cover during flanking.
var _flank_cover_wait_timer: float = 0.0

## Duration to wait at each cover during flanking (seconds).
const FLANK_COVER_WAIT_DURATION: float = 0.8

## Current flank cover position to move to.
var _flank_next_cover: Vector2 = Vector2.ZERO

## Whether the enemy has a valid flank cover target.
var _has_flank_cover: bool = false

## The side to flank on (1.0 = right, -1.0 = left). Set once when entering FLANKING state.
var _flank_side: float = 1.0

## Whether flank side has been initialized for this flanking maneuver.
var _flank_side_initialized: bool = false

## Timer for total time spent in FLANKING state (for timeout detection).
var _flank_state_timer: float = 0.0

## Maximum time to spend in FLANKING state before giving up (seconds).
const FLANK_STATE_MAX_TIME: float = 5.0

## Last recorded position for progress tracking during flanking.
var _flank_last_position: Vector2 = Vector2.ZERO

## Timer for checking if stuck (no progress toward flank target).
var _flank_stuck_timer: float = 0.0

## Maximum time without progress before considering stuck (seconds).
const FLANK_STUCK_MAX_TIME: float = 2.0

## Minimum distance that counts as progress toward flank target.
const FLANK_PROGRESS_THRESHOLD: float = 10.0

## Counter for consecutive flanking failures (to prevent infinite loops).
var _flank_fail_count: int = 0

## Maximum number of consecutive flanking failures before disabling flanking temporarily.
const FLANK_FAIL_MAX_COUNT: int = 2

## Cooldown timer after flanking failures (prevents immediate retry).
var _flank_cooldown_timer: float = 0.0

## Duration to wait after flanking failures before allowing retry (seconds).
const FLANK_COOLDOWN_DURATION: float = 5.0

## Issue #367: Global position-based stuck detection for PURSUING/FLANKING states.
## If enemy stays near same position for too long without direct player contact, transition to SEARCHING.
var _global_stuck_timer: float = 0.0  ## Timer for position-based stuck detection
var _global_stuck_last_position: Vector2 = Vector2.ZERO  ## Last recorded position for stuck check
const GLOBAL_STUCK_MAX_TIME: float = 4.0  ## Max time in same area before forced transition
const GLOBAL_STUCK_DISTANCE_THRESHOLD: float = 30.0  ## Min distance to count as "moved"

## --- Assault State (coordinated multi-enemy rush) ---
## Timer for assault wait period (5 seconds before rushing).
var _assault_wait_timer: float = 0.0

## Duration to wait at cover before assault (5 seconds).
const ASSAULT_WAIT_DURATION: float = 5.0

## Whether the assault wait period is complete.
var _assault_ready: bool = false

## Whether this enemy is currently participating in an assault.
var _in_assault: bool = false

## Search State - Issue #322/#369: Coordinated search using SearchCoordinator autoload.
## Routes are now generated at iteration start and distributed among all searching enemies.
var _search_scan_timer: float = 0.0  ## Timer for scanning at waypoint.
const SEARCH_SCAN_DURATION: float = 1.0  ## Seconds to scan at each waypoint.
var _search_state_timer: float = 0.0  ## Total time in SEARCHING state.
const SEARCH_MAX_DURATION: float = 30.0  ## Max time searching before idle (patrol only).
const SEARCH_WAYPOINT_REACHED_DISTANCE: float = 20.0  ## Waypoint reached threshold.
var _search_moving_to_waypoint: bool = true  ## Moving (vs scanning).
var _coordinated_search_iteration: int = -1  ## Current search iteration ID from coordinator.

## Issue #354: Stuck detection for SEARCHING state.
var _search_stuck_timer: float = 0.0  ## Timer for no progress toward waypoint.
var _search_last_progress_position: Vector2 = Vector2.ZERO  ## Last progress position.
const SEARCH_STUCK_MAX_TIME: float = 2.0  ## Max time without progress before skip.
const SEARCH_PROGRESS_THRESHOLD: float = 10.0  ## Min distance counting as progress.

## Issue #330: Once enemy leaves IDLE, never returns - searches until finding player.
var _has_left_idle: bool = false

## Issue #369: Player position prediction for search state.
## Each enemy makes their own prediction based on time elapsed and nearby covers.
const PLAYER_SPEED_ESTIMATE: float = 300.0  ## Estimated player max speed (pixels/sec).
const PREDICTION_COVER_WEIGHT: float = 0.5  ## Weight for cover positions in prediction.
const PREDICTION_FLANK_WEIGHT: float = 0.3  ## Weight for flank positions in prediction.
const PREDICTION_RANDOM_WEIGHT: float = 0.2  ## Weight for random offset in prediction.
const PREDICTION_MIN_PROBABILITY: float = 0.3  ## Minimum probability to use prediction (0.0-1.0).
const PREDICTION_CHECK_DISTANCE: float = 500.0  ## Max distance to check for covers/flanks.

## Distance threshold for "close" vs "far" from player.
## Used to determine if enemy can engage from current position or needs to pursue.
const CLOSE_COMBAT_DISTANCE: float = 400.0

## GOAP world state for goal-oriented planning.
var _goap_world_state: Dictionary = {}

## Detection delay timer - tracks time since entering combat.
var _detection_timer: float = 0.0

## Whether the detection delay has elapsed.
var _detection_delay_elapsed: bool = false

## Continuous visibility timer - tracks how long the player has been continuously visible.
## Resets when line of sight is lost.
var _continuous_visibility_timer: float = 0.0

## Current visibility ratio of the player (0.0 to 1.0).
## Represents what fraction of the player's body is visible to the enemy.
## Used to determine if lead prediction should be enabled.
var _player_visibility_ratio: float = 0.0

## --- Clear Shot Movement (move out from cover to get clear shot) ---
## Target position to move to for getting a clear shot.
var _clear_shot_target: Vector2 = Vector2.ZERO

## Whether we're currently moving to find a clear shot position.
var _seeking_clear_shot: bool = false

## Timer for how long we've been trying to find a clear shot.
var _clear_shot_timer: float = 0.0

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

## --- Grenade System State (Issue #363) ---
## Current number of grenades remaining.
var _grenades_remaining: int = 0

## Time since last grenade throw (for cooldown).
var _grenade_cooldown_timer: float = 0.0

## Whether currently in the process of throwing a grenade.
var _is_throwing_grenade: bool = false

## Timer tracking how long player has been hidden after suppression (Trigger 1).
var _player_hidden_after_suppression_timer: float = 0.0

## Whether the enemy was suppressed before player hid (Trigger 1).
var _was_suppressed_before_hidden: bool = false

## Whether an ally was suppressed in view before player hid (Trigger 1).
var _saw_ally_suppressed: bool = false

## Previous player distance for approach detection (Trigger 2).
var _previous_player_distance: float = 0.0

## Number of ally deaths witnessed while player was visible (Trigger 3).
var _witnessed_kills_count: int = 0

## Timer to reset witnessed kill count (Trigger 3).
var _kill_witness_reset_timer: float = 0.0

## Whether a vulnerable sound (reload/empty click) was heard while player not visible (Trigger 4).
var _heard_vulnerable_sound: bool = false

## Position where vulnerable sound was heard (Trigger 4).
var _vulnerable_sound_position: Vector2 = Vector2.ZERO

## Timestamp when vulnerable sound was heard (Trigger 4).
var _vulnerable_sound_timestamp: float = 0.0

## Center of sustained fire zone (Trigger 5).
var _fire_zone_center: Vector2 = Vector2.ZERO

## Last gunshot time in fire zone (Trigger 5).
var _fire_zone_last_sound: float = 0.0

## Total duration of sustained fire in zone (Trigger 5).
var _fire_zone_total_duration: float = 0.0

## Whether fire zone tracking is active (Trigger 5).
var _fire_zone_valid: bool = false

## Constants for grenade trigger conditions.
const GRENADE_HIDDEN_THRESHOLD: float = 6.0  ## Seconds player must be hidden (Trigger 1)
const GRENADE_PURSUIT_SPEED_THRESHOLD: float = 50.0  ## Player approach speed (Trigger 2)
const GRENADE_KILL_THRESHOLD: int = 2  ## Kills to witness (Trigger 3)
const GRENADE_KILL_WITNESS_WINDOW: float = 30.0  ## Window to reset kill count (Trigger 3)
const GRENADE_SOUND_VALIDITY_WINDOW: float = 5.0  ## How long sound position is valid (Trigger 4)
const GRENADE_SUSTAINED_FIRE_THRESHOLD: float = 10.0  ## Seconds of sustained fire (Trigger 5)
const GRENADE_FIRE_GAP_TOLERANCE: float = 2.0  ## Max gap between shots (Trigger 5)
const GRENADE_VIEWPORT_ZONE_FRACTION: float = 6.0  ## Zone is 1/6 of viewport (Trigger 5)
const GRENADE_DESPERATION_HEALTH_THRESHOLD: int = 1  ## HP threshold (Trigger 6)

## Last hit direction (used for death animation).
var _last_hit_direction: Vector2 = Vector2.RIGHT

## Death animation component reference.
var _death_animation: Node = null

## Note: DeathAnimationComponent is available via class_name declaration.

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
	_initialize_grenade_system()

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
	if not _is_alive or _memory_reset_confusion_timer > 0.0:
		return
	var distance := global_position.distance_to(position)
	if sound_type == 3 and source_type == 0:  # RELOAD from PLAYER
		_log_debug("Heard player RELOAD (intensity=%.2f, distance=%.0f) at %s" % [intensity, distance, position])
		_log_to_file("Heard player RELOAD at %s, intensity=%.2f, distance=%.0f" % [position, intensity, distance])
		_goap_world_state["player_reloading"] = true
		_last_known_player_position = position
		_pursuing_vulnerability_sound = true
		_on_vulnerable_sound_heard_for_grenade(position)
		if _memory:
			_memory.update_position(position, SOUND_RELOAD_CONFIDENCE)
		if _current_state in [AIState.IDLE, AIState.IN_COVER, AIState.SUPPRESSED, AIState.RETREATING, AIState.SEEKING_COVER]:
			_log_to_file("Vulnerability sound triggered pursuit - transitioning from %s to PURSUING" % AIState.keys()[_current_state])
			_transition_to_pursuing()
		return
	if sound_type == 5 and source_type == 0:  # EMPTY_CLICK from PLAYER
		_log_debug("Heard player EMPTY_CLICK (intensity=%.2f, distance=%.0f) at %s" % [intensity, distance, position])
		_log_to_file("Heard player EMPTY_CLICK at %s, intensity=%.2f, distance=%.0f" % [position, intensity, distance])
		_goap_world_state["player_ammo_empty"] = true
		_last_known_player_position = position
		_pursuing_vulnerability_sound = true
		_on_vulnerable_sound_heard_for_grenade(position)
		if _memory:
			_memory.update_position(position, SOUND_EMPTY_CLICK_CONFIDENCE)
		if _current_state in [AIState.IDLE, AIState.IN_COVER, AIState.SUPPRESSED, AIState.RETREATING, AIState.SEEKING_COVER]:
			_log_to_file("Vulnerability sound triggered pursuit - transitioning from %s to PURSUING" % AIState.keys()[_current_state])
			_transition_to_pursuing()
		return
	if sound_type == 6 and source_type == 0:  # RELOAD_COMPLETE from PLAYER
		_log_debug("Heard player RELOAD_COMPLETE (intensity=%.2f, distance=%.0f) at %s" % [intensity, distance, position])
		_log_to_file("Heard player RELOAD_COMPLETE at %s, intensity=%.2f, distance=%.0f" % [position, intensity, distance])
		_goap_world_state["player_reloading"] = false
		_goap_world_state["player_ammo_empty"] = false
		_pursuing_vulnerability_sound = false
		if _current_state in [AIState.PURSUING, AIState.COMBAT, AIState.ASSAULT]:
			var state_before_delay := _current_state
			_log_to_file("Reload complete sound heard - waiting 200ms before cautious transition from %s" % AIState.keys()[_current_state])
			await get_tree().create_timer(0.2).timeout
			if not _is_alive:
				return
			if _current_state in [AIState.PURSUING, AIState.COMBAT, AIState.ASSAULT]:
				if _has_valid_cover:
					_log_to_file("Reload complete triggered retreat from %s" % AIState.keys()[state_before_delay])
					_transition_to_retreating()
				elif enable_cover:
					_log_to_file("Reload complete triggered cover seek from %s" % AIState.keys()[state_before_delay])
					_transition_to_seeking_cover()
		return
	if sound_type != 0:
		return
	var should_react := (_current_state == AIState.IDLE and intensity >= 0.01) or (_current_state in [AIState.FLANKING, AIState.RETREATING] and intensity >= 0.3)
	if not should_react:
		return
	_log_debug("Heard gunshot (intensity=%.2f, distance=%.0f) at %s, entering COMBAT" % [intensity, distance, position])
	_log_to_file("Heard gunshot at %s, source_type=%d, intensity=%.2f, distance=%.0f" % [position, source_type, intensity, distance])
	_on_gunshot_heard_for_grenade(position)
	_last_known_player_position = position
	if _memory:
		_memory.update_position(position, SOUND_GUNSHOT_CONFIDENCE)
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

## Issue #369: Check if this enemy is in SEARCHING state (for SearchCoordinator).
func is_searching() -> bool:
	return _current_state == AIState.SEARCHING

## Issue #369: Check if this enemy should join a coordinated search.
func should_join_search() -> bool:
	# Enemies that just lost sight of the player should join search
	return _current_state == AIState.PURSUING and not _can_see_player

## Issue #369: Mark a zone as visited via the SearchCoordinator.
func _mark_zone_visited_coordinated(pos: Vector2) -> void:
	var coordinator: Node = get_node_or_null("/root/SearchCoordinator")
	if coordinator:
		coordinator.mark_zone_visited(pos)

## Check if position is navigable via NavigationServer2D.
func _is_waypoint_navigable(pos: Vector2) -> bool:
	var nav_map := get_world_2d().navigation_map
	var closest := NavigationServer2D.map_get_closest_point(nav_map, pos)
	return pos.distance_to(closest) < 50.0

## Process SEARCHING state - Issue #369: Now uses coordinated search from SearchCoordinator.
## Routes are pre-planned at iteration start for all searching enemies.
## Issue #330: If enemy has ever left IDLE, they NEVER return to IDLE - search infinitely.
func _process_searching_state(delta: float) -> void:
	_search_state_timer += delta
	if _search_state_timer >= SEARCH_MAX_DURATION and not _has_left_idle:
		_log_to_file("SEARCHING timeout, returning to IDLE")
		_remove_from_coordinated_search()
		_transition_to_idle()
		return
	if _can_see_player:
		_log_to_file("SEARCHING: Player spotted!")
		_remove_from_coordinated_search()
		_transition_to_combat()
		return
	var coord: Node = get_node_or_null("/root/SearchCoordinator")
	if coord == null:
		_process_searching_state_fallback(delta)
		return
	var wp: Vector2 = coord.get_next_waypoint(self)
	if wp == Vector2.ZERO or coord.is_route_complete(self):
		if coord.expand_search():
			_log_to_file("SEARCHING: Expanding search radius")
			_search_state_timer = 0.0
		elif _has_left_idle:
			_coordinated_search_iteration = coord.start_coordinated_search(global_position, self)
			_log_to_file("SEARCHING: New search from %s" % global_position)
			_search_state_timer = 0.0
		else:
			_log_to_file("SEARCHING: Max radius, returning to IDLE")
			_remove_from_coordinated_search()
			_transition_to_idle()
		return
	if _search_moving_to_waypoint:
		if global_position.distance_to(wp) <= SEARCH_WAYPOINT_REACHED_DISTANCE:
			_search_moving_to_waypoint = false
			_search_scan_timer = 0.0
			_search_stuck_timer = 0.0
		else:
			_nav_agent.target_position = wp
			if _nav_agent.is_navigation_finished():
				_mark_zone_visited_coordinated(wp)
				coord.advance_waypoint(self)
				_search_moving_to_waypoint = true
				_search_stuck_timer = 0.0
			else:
				var next_pos := _nav_agent.get_next_path_position()
				var dir := (next_pos - global_position).normalized()
				velocity = dir * move_speed * 0.7
				move_and_slide()
				if global_position.distance_to(_search_last_progress_position) < SEARCH_PROGRESS_THRESHOLD:
					_search_stuck_timer += delta
					if _search_stuck_timer >= SEARCH_STUCK_MAX_TIME:
						_mark_zone_visited_coordinated(wp)
						coord.advance_waypoint(self)
						_search_moving_to_waypoint = true
						_search_stuck_timer = 0.0
						_search_last_progress_position = global_position
						return
				else:
					_search_stuck_timer = 0.0
					_search_last_progress_position = global_position
				if dir.length() > 0.1:
					rotation = lerp_angle(rotation, dir.angle(), 5.0 * delta)
					_process_corner_check(delta, dir, "SEARCHING")
	else:
		_search_scan_timer += delta
		rotation += delta * 1.5
		if _search_scan_timer >= SEARCH_SCAN_DURATION:
			_mark_zone_visited_coordinated(wp)
			var cref: Node = get_node_or_null("/root/SearchCoordinator")
			if cref:
				cref.advance_waypoint(self)
			_search_moving_to_waypoint = true

## Remove this enemy from coordinated search.
func _remove_from_coordinated_search() -> void:
	var coordinator: Node = get_node_or_null("/root/SearchCoordinator")
	if coordinator:
		coordinator.remove_enemy_from_search(self)
	_coordinated_search_iteration = -1

## Fallback search behavior when SearchCoordinator is not available.
func _process_searching_state_fallback(delta: float) -> void:
	# Simple fallback: rotate and move in small circle
	rotation += delta * 1.5
	var dir := Vector2.from_angle(rotation)
	velocity = dir * move_speed * 0.3
	move_and_slide()

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
## Issue #369: Now uses coordinated search via SearchCoordinator with Voronoi-like partitioning.
func _transition_to_searching(center_position: Vector2) -> void:
	_current_state = AIState.SEARCHING
	# Mark that enemy has left IDLE state (Issue #330)
	_has_left_idle = true

	# Issue #369: Use prediction for search center
	var predicted_center := _predict_player_position(center_position)

	# Initialize search state
	_search_state_timer = 0.0
	_search_scan_timer = 0.0
	_search_moving_to_waypoint = true
	_search_stuck_timer = 0.0
	_search_last_progress_position = global_position

	# Issue #369: Start or join coordinated search via SearchCoordinator
	var coordinator: Node = get_node_or_null("/root/SearchCoordinator")
	if coordinator:
		_coordinated_search_iteration = coordinator.start_coordinated_search(predicted_center, self)
		_log_to_file("SEARCHING started: coordinated iter=%d, center=%s (predicted from %s)" % [
			_coordinated_search_iteration, predicted_center, center_position
		])
	else:
		_coordinated_search_iteration = -1
		_log_to_file("SEARCHING started: center=%s (no coordinator, fallback mode)" % predicted_center)

## Issue #369: Predict where player might have moved based on time and environment.
func _predict_player_position(last_known_pos: Vector2) -> Vector2:
	if randf() > PREDICTION_MIN_PROBABILITY: return last_known_pos
	var time_elapsed := _memory.get_time_since_update() if _memory else 0.0
	if time_elapsed < 0.5: return last_known_pos
	var max_dist := minf(PLAYER_SPEED_ESTIMATE * time_elapsed, PREDICTION_CHECK_DISTANCE)
	var candidates: Array[Dictionary] = []
	var total_weight := 0.0
	for cover_pos in _find_prediction_covers(last_known_pos, max_dist):
		var w := PREDICTION_COVER_WEIGHT + randf() * 0.1
		candidates.append({"pos": cover_pos, "weight": w, "type": "cover"})
		total_weight += w
	for flank_pos in _get_prediction_flanks(last_known_pos, max_dist):
		var w := PREDICTION_FLANK_WEIGHT + randf() * 0.1
		candidates.append({"pos": flank_pos, "weight": w, "type": "flank"})
		total_weight += w
	var rand_pos := last_known_pos + Vector2.from_angle(randf() * TAU) * randf() * max_dist * 0.5
	if _is_waypoint_navigable(rand_pos):
		candidates.append({"pos": rand_pos, "weight": PREDICTION_RANDOM_WEIGHT, "type": "random"})
		total_weight += PREDICTION_RANDOM_WEIGHT
	candidates.append({"pos": last_known_pos, "weight": 0.1, "type": "last_known"})
	total_weight += 0.1
	if candidates.is_empty(): return last_known_pos
	var roll := randf() * total_weight
	var cumulative := 0.0
	for c in candidates:
		cumulative += c.weight
		if roll <= cumulative:
			_log_to_file("Prediction: %s at %s (t=%.1fs)" % [c.type, c.pos, time_elapsed])
			return c.pos
	return last_known_pos

## Issue #369: Find cover positions near a point for prediction.
func _find_prediction_covers(center: Vector2, max_dist: float) -> Array[Vector2]:
	var covers: Array[Vector2] = []
	var nav_map := get_world_2d().navigation_map
	for i in range(COVER_CHECK_COUNT):
		var raycast := _cover_raycasts[i]
		raycast.global_position = center
		raycast.target_position = Vector2.from_angle(float(i) / COVER_CHECK_COUNT * TAU) * minf(max_dist, COVER_CHECK_DISTANCE)
		raycast.force_raycast_update()
		if raycast.is_colliding():
			var cover_pos := raycast.get_collision_point() + raycast.get_collision_normal() * 35.0
			if center.distance_to(cover_pos) <= max_dist:
				var closest := NavigationServer2D.map_get_closest_point(nav_map, cover_pos)
				if cover_pos.distance_to(closest) < 50.0: covers.append(cover_pos)
		raycast.global_position = global_position
	return covers

## Issue #369: Calculate flank positions for prediction.
func _get_prediction_flanks(center: Vector2, max_dist: float) -> Array[Vector2]:
	var flanks: Array[Vector2] = []
	var to_center := (center - global_position).normalized()
	var flank_dist := minf(max_dist * 0.7, 200.0)
	var left := center + to_center.rotated(-PI / 2) * flank_dist
	var right := center + to_center.rotated(PI / 2) * flank_dist
	if _is_waypoint_navigable(left): flanks.append(left)
	if _is_waypoint_navigable(right): flanks.append(right)
	return flanks

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
## Check if PLAYER can see the ENEMY (inverse of _can_see_player). Checks multiple body points.
func _is_visible_from_player() -> bool:
	if _player == null: return false
	for point in _get_enemy_check_points(global_position):
		if _is_point_visible_from_player(point): return true
	return false

## Get center + 4 corner check points on enemy body (ENEMY_RADIUS=22, diagonal offset ~15.5).
func _get_enemy_check_points(center: Vector2) -> Array[Vector2]:
	const D := 15.554  # 22.0 * 0.707 (cos45)
	return [center, center + Vector2(D, D), center + Vector2(-D, D), center + Vector2(D, -D), center + Vector2(-D, -D)]

## Check if a single point is visible from the player's position via raycast.
func _is_point_visible_from_player(point: Vector2) -> bool:
	if _player == null: return false
	var player_pos := _player.global_position
	var query := PhysicsRayQueryParameters2D.new()
	query.from = player_pos; query.to = point; query.collision_mask = 4; query.exclude = []
	var result := get_world_2d().direct_space_state.intersect_ray(query)
	if result.is_empty(): return true
	return player_pos.distance_to(result["position"]) >= player_pos.distance_to(point) - 10.0

## Check if enemy at given position would be visible from player. Used for cover validation.
func _is_position_visible_from_player(pos: Vector2) -> bool:
	if _player == null: return true
	for point in _get_enemy_check_points(pos):
		if _is_point_visible_from_player(point): return true
	return false

## Check if target position is visible from enemy. Used for lead prediction validation.
func _is_position_visible_to_enemy(target_pos: Vector2) -> bool:
	var distance := global_position.distance_to(target_pos)
	var query := PhysicsRayQueryParameters2D.new()
	query.from = global_position; query.to = target_pos; query.collision_mask = 4; query.exclude = [get_rid()]
	var result := get_world_2d().direct_space_state.intersect_ray(query)
	if result.is_empty(): return true
	var dist_to_hit := global_position.distance_to(result["position"])
	if dist_to_hit < distance - 10.0:
		_log_debug("Position %s blocked at %.1f (target at %.1f)" % [target_pos, dist_to_hit, distance])
		return false
	return true

## Get center + 4 corner check points on the player's body (PLAYER_RADIUS=14, diagonal ~9.9).
func _get_player_check_points(center: Vector2) -> Array[Vector2]:
	const D := 9.898  # 14.0 * 0.707 (cos45)
	return [center, center + Vector2(D, D), center + Vector2(-D, D), center + Vector2(D, -D), center + Vector2(-D, -D)]

## Check if a single point on the player is visible (not blocked by obstacles).
func _is_player_point_visible_to_enemy(point: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.new()
	query.from = global_position; query.to = point; query.collision_mask = 4; query.exclude = [get_rid()]
	var result := get_world_2d().direct_space_state.intersect_ray(query)
	if result.is_empty(): return true
	return global_position.distance_to(result["position"]) >= global_position.distance_to(point) - 5.0

## Calculate what fraction of the player's body is visible (0.0-1.0).
func _calculate_player_visibility_ratio() -> float:
	if _player == null: return 0.0
	var points := _get_player_check_points(_player.global_position)
	var visible := 0
	for p in points:
		if _is_player_point_visible_to_enemy(p): visible += 1
	return float(visible) / float(points.size())

## Check if the line of fire is clear of other enemies (friendly fire avoidance).
func _is_firing_line_clear_of_friendlies(target_position: Vector2) -> bool:
	if not enable_friendly_fire_avoidance: return true
	var wf := _get_weapon_forward_direction()
	var muzzle := _get_bullet_spawn_position(wf)
	var dist := muzzle.distance_to(target_position)
	var query := PhysicsRayQueryParameters2D.new()
	query.from = muzzle; query.to = target_position; query.collision_mask = 2; query.exclude = [get_rid()]
	var result := get_world_2d().direct_space_state.intersect_ray(query)
	if result.is_empty(): return true
	var dist_hit := muzzle.distance_to(result["position"])
	if dist_hit < dist - 20.0:
		_log_debug("Friendly in firing line at distance %0.1f (target at %0.1f)" % [dist_hit, dist])
		return false
	return true

## Check if a bullet would be blocked by cover/obstacles.
func _is_shot_clear_of_cover(target_position: Vector2) -> bool:
	var wf := _get_weapon_forward_direction()
	var muzzle := _get_bullet_spawn_position(wf)
	var dist := muzzle.distance_to(target_position)
	var query := PhysicsRayQueryParameters2D.new()
	query.from = muzzle; query.to = target_position; query.collision_mask = 4
	var result := get_world_2d().direct_space_state.intersect_ray(query)
	if result.is_empty(): return true
	var dist_hit := muzzle.distance_to(result["position"])
	if dist_hit < dist - 10.0:
		_log_debug("Shot blocked by cover at distance %0.1f (target at %0.1f)" % [dist_hit, dist])
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

## Check wall ahead and return avoidance direction using 8 distance-weighted raycasts.
func _check_wall_ahead(direction: Vector2) -> Vector2:
	if _wall_raycasts.is_empty(): return Vector2.ZERO
	var avoidance := Vector2.ZERO
	var perp := Vector2(-direction.y, direction.x)
	var angles: Array[float] = [0.0, -0.35, -0.79, -1.22, 0.35, 0.79, 1.22, PI]
	for i: int in range(mini(WALL_CHECK_COUNT, _wall_raycasts.size())):
		var ang: float = angles[i] if i < angles.size() else 0.0
		var raycast: RayCast2D = _wall_raycasts[i]
		raycast.target_position = direction.rotated(ang) * (WALL_SLIDE_DISTANCE if i == 7 else WALL_CHECK_DISTANCE)
		raycast.force_raycast_update()
		if raycast.is_colliding():
			var wall_dist := global_position.distance_to(raycast.get_collision_point())
			var w := 1.0 - (wall_dist / WALL_CHECK_DISTANCE)
			if i == 7: avoidance += raycast.get_collision_normal() * 0.5
			elif i <= 3: avoidance += perp * w
			else: avoidance -= perp * w
	return avoidance.normalized() if avoidance.length() > 0 else Vector2.ZERO

## Apply wall avoidance to a movement direction.
func _apply_wall_avoidance(direction: Vector2) -> Vector2:
	var avoid := _check_wall_ahead(direction)
	if avoid == Vector2.ZERO: return direction
	var w := _get_wall_avoidance_weight(direction)
	return (direction * (1.0 - w) + avoid * w).normalized()

## Calculate wall avoidance weight based on distance to nearest wall.
func _get_wall_avoidance_weight(direction: Vector2) -> float:
	if _wall_raycasts.is_empty(): return WALL_AVOIDANCE_MAX_WEIGHT
	var dist := WALL_CHECK_DISTANCE
	if _wall_raycasts.size() > 0:
		var rc: RayCast2D = _wall_raycasts[0]
		rc.target_position = direction * WALL_CHECK_DISTANCE
		rc.force_raycast_update()
		if rc.is_colliding(): dist = global_position.distance_to(rc.get_collision_point())
	return lerpf(WALL_AVOIDANCE_MIN_WEIGHT, WALL_AVOIDANCE_MAX_WEIGHT, clampf(dist / WALL_CHECK_DISTANCE, 0.0, 1.0))

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

## Check player visibility using multi-point raycast. Updates visibility timer.
func _check_player_visibility() -> void:
	_can_see_player = false; _player_visibility_ratio = 0.0
	if _is_blinded or _memory_reset_confusion_timer > 0.0 or _player == null or not _raycast:
		_continuous_visibility_timer = 0.0; return
	if detection_range > 0 and global_position.distance_to(_player.global_position) > detection_range:
		_continuous_visibility_timer = 0.0; return
	if not _is_position_in_fov(_player.global_position):
		_continuous_visibility_timer = 0.0; return
	var pts := _get_player_check_points(_player.global_position)
	var visible := 0
	for p in pts:
		if _is_player_point_visible_to_enemy(p):
			visible += 1; _can_see_player = true
	if _can_see_player:
		_player_visibility_ratio = float(visible) / float(pts.size())
		_continuous_visibility_timer += get_physics_process_delta_time()
	else:
		_continuous_visibility_timer = 0.0; _player_visibility_ratio = 0.0

## Update enemy memory: visual detection, decay, and periodic intel sharing (Issue #297).
func _update_memory(delta: float) -> void:
	if _memory == null: return
	if _can_see_player and _player:
		_memory.update_position(_player.global_position, VISUAL_DETECTION_CONFIDENCE)
		_last_known_player_position = _player.global_position
	_memory.decay(delta)
	_intel_share_timer += delta
	if _intel_share_timer >= INTEL_SHARE_INTERVAL:
		_intel_share_timer = 0.0; _share_intel_with_nearby_enemies()

## Share intelligence with nearby enemies within 660px (LOS) or 300px (no LOS).
func _share_intel_with_nearby_enemies() -> void:
	if _memory == null or not _memory.has_target(): return
	for node in get_tree().get_nodes_in_group("enemies"):
		if node == self or not is_instance_valid(node): continue
		var other: Node2D = node as Node2D
		if other == null: continue
		var dist := global_position.distance_to(other.global_position)
		var can_share := dist <= INTEL_SHARE_RANGE_NO_LOS or (dist <= INTEL_SHARE_RANGE_LOS and _has_line_of_sight_to_position(other.global_position))
		if can_share and other.has_method("receive_intel_from_ally"):
			other.receive_intel_from_ally(_memory)

## Receive intelligence from an allied enemy (Issue #297).
func receive_intel_from_ally(ally_memory: EnemyMemory) -> void:
	if _memory == null or ally_memory == null: return
	if _memory.receive_intel(ally_memory, INTEL_SHARE_FACTOR):
		_log_debug("Received intel from ally: pos=%s, conf=%.2f" % [_memory.suspected_position, _memory.confidence])
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

## Shoot a bullet in barrel direction.
func _shoot() -> void:
	if bullet_scene == null or _player == null or not _can_shoot():
		return
	var target_position := _player.global_position
	if enable_lead_prediction:
		target_position = _calculate_lead_prediction()
	if not _should_shoot_at_target(target_position):
		return
	var weapon_forward := _get_weapon_forward_direction()
	var bullet_spawn_pos := _get_bullet_spawn_position(weapon_forward)
	var to_target := (target_position - global_position).normalized()
	var aim_dot := weapon_forward.dot(to_target)
	if aim_dot < AIM_TOLERANCE_DOT:
		if debug_logging:
			_log_debug("SHOOT BLOCKED: aim_dot=%.3f" % aim_dot)
		return
	var bullet := bullet_scene.instantiate()
	bullet.global_position = bullet_spawn_pos
	if debug_logging:
		_log_debug("SHOOT: pos=%v, target=%v, dir=%v" % [global_position, target_position, weapon_forward])
	bullet.direction = weapon_forward
	bullet.shooter_id = get_instance_id()
	bullet.shooter_position = bullet_spawn_pos
	get_tree().current_scene.add_child(bullet)
	_spawn_casing(weapon_forward, weapon_forward)
	var am: Node = get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_m16_shot"):
		am.play_m16_shot(global_position)
	var sp: Node = get_node_or_null("/root/SoundPropagation")
	if sp and sp.has_method("emit_sound"):
		sp.emit_sound(0, global_position, 1, self, weapon_loudness)
	_play_delayed_shell_sound()
	_current_ammo -= 1
	ammo_changed.emit(_current_ammo, _reserve_ammo)
	if _current_ammo <= 0 and _reserve_ammo > 0:
		_start_reload()

## Play shell casing sound with a delay to simulate the casing hitting the ground.
func _play_delayed_shell_sound() -> void:
	await get_tree().create_timer(0.15).timeout
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_shell_rifle"):
		audio_manager.play_shell_rifle(global_position)

## Spawn bullet casing with ejection physics.
func _spawn_casing(_shoot_direction: Vector2, weapon_forward: Vector2) -> void:
	if casing_scene == null: return
	var casing: RigidBody2D = casing_scene.instantiate()
	casing.global_position = global_position + weapon_forward * (bullet_spawn_offset * 0.5)
	var weapon_right := Vector2(-weapon_forward.y, weapon_forward.x)
	var eject_dir := weapon_right.rotated(randf_range(-0.3, 0.3)).rotated(randf_range(-0.1, 0.1))
	casing.linear_velocity = eject_dir * randf_range(300.0, 450.0)
	casing.angular_velocity = randf_range(-15.0, 15.0)
	var cal: Resource = load("res://resources/calibers/caliber_545x39.tres")
	if cal: casing.set("caliber_data", cal)
	get_tree().current_scene.add_child(casing)

## Calculate lead prediction - aims where the player will be based on velocity.
func _calculate_lead_prediction() -> Vector2:
	if _player == null: return global_position
	var player_pos := _player.global_position
	if _continuous_visibility_timer < lead_prediction_delay:
		_log_debug("Lead prediction disabled: visibility time %.2fs < %.2fs" % [_continuous_visibility_timer, lead_prediction_delay])
		return player_pos
	if _player_visibility_ratio < lead_prediction_visibility_threshold:
		_log_debug("Lead prediction disabled: visibility %.2f < %.2f" % [_player_visibility_ratio, lead_prediction_visibility_threshold])
		return player_pos
	var vel := _player.velocity if _player is CharacterBody2D else Vector2.ZERO
	if vel.length_squared() < 1.0: return player_pos
	var pred := player_pos
	var dist := global_position.distance_to(pred)
	for i in range(3):  # Iterate for convergence
		pred = player_pos + vel * (dist / bullet_speed)
		dist = global_position.distance_to(pred)
	if not _is_position_visible_to_enemy(pred):
		_log_debug("Lead prediction blocked: %s not visible" % pred)
		return player_pos
	_log_debug("Lead prediction: %s -> %s" % [player_pos, pred])
	return pred

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

## Calculates bullet spawn position at weapon muzzle. Uses direct aim when player visible (Issue #264).
func _get_bullet_spawn_position(_direction: Vector2) -> Vector2:
	const MUZZLE_OFFSET := 52.0  # Rifle muzzle offset from node
	if _weapon_sprite and _enemy_model:
		var wf: Vector2 = (_player.global_position - global_position).normalized() if (_player and is_instance_valid(_player) and _can_see_player) else _weapon_sprite.global_transform.x.normalized()
		var scaled := MUZZLE_OFFSET * enemy_model_scale
		var result := _weapon_sprite.global_position + wf * scaled
		if debug_logging:
			_log_debug("  muzzle=%v, weapon_pos=%v, offset=%.1f" % [result, _weapon_sprite.global_position, scaled])
		return result
	return global_position + _direction * bullet_spawn_offset

## Returns weapon's forward direction. Direct calc to player when visible (Issue #264).
func _get_weapon_forward_direction() -> Vector2:
	if _player and is_instance_valid(_player) and _can_see_player:
		return (_player.global_position - global_position).normalized()
	if _weapon_sprite: return _weapon_sprite.global_transform.x.normalized()
	if _enemy_model: return _enemy_model.global_transform.x.normalized()
	if _player and is_instance_valid(_player): return (_player.global_position - global_position).normalized()
	return Vector2.RIGHT

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
	_killed_by_ricochet = false
	_killed_by_penetration = false
	_initialize_health()
	_initialize_ammo()
	_update_health_visual()
	_initialize_goap_state()
	_enable_hit_area_collision()
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
	return AIState.keys()[state] if state >= 0 and state < AIState.size() else "UNKNOWN"

## Update the debug label with current AI state.
func _update_debug_label() -> void:
	if _debug_label == null:
		return
	_debug_label.visible = debug_label_enabled
	if not debug_label_enabled:
		return
	var st := _get_state_name(_current_state)
	if _current_state == AIState.RETREATING:
		st += "\n(%s)" % RetreatMode.keys()[_retreat_mode]
	elif _current_state == AIState.ASSAULT:
		st += "\n(RUSHING)" if _assault_ready else "\n(%.1fs)" % (ASSAULT_WAIT_DURATION - _assault_wait_timer)
	elif _current_state == AIState.COMBAT:
		if _combat_exposed:
			st += "\n(EXPOSED %.1fs)" % (_combat_shoot_duration - _combat_shoot_timer)
		elif _seeking_clear_shot:
			st += "\n(SEEK SHOT %.1fs)" % (CLEAR_SHOT_MAX_TIME - _clear_shot_timer)
		elif _combat_approaching:
			st += "\n(APPROACH)"
	elif _current_state == AIState.PURSUING:
		if _pursuit_approaching:
			st += "\n(APPROACH %.1fs)" % (PURSUIT_APPROACH_MAX_TIME - _pursuit_approach_timer)
		elif _has_valid_cover and not _has_pursuit_cover:
			st += "\n(WAIT %.1fs)" % (PURSUIT_COVER_WAIT_DURATION - _pursuit_cover_wait_timer)
		elif _has_pursuit_cover:
			st += "\n(MOVING)"
	elif _current_state == AIState.FLANKING:
		var s := "R" if _flank_side > 0 else "L"
		if _has_valid_cover and not _has_flank_cover:
			st += "\n(%s WAIT %.1fs)" % [s, FLANK_COVER_WAIT_DURATION - _flank_cover_wait_timer]
		elif _has_flank_cover:
			st += "\n(%s MOVING)" % s
		else:
			st += "\n(%s DIRECT)" % s
	if _memory and _memory.has_target():
		st += "\n[%.0f%% %s]" % [_memory.confidence * 100, _memory.get_behavior_mode().substr(0, 6)]
	_debug_label.text = st

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
func _draw() -> void:
	if not debug_label_enabled:
		return
	var exp_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	var fov_active := exp_settings != null and exp_settings.has_method("is_fov_enabled") and exp_settings.is_fov_enabled() and fov_enabled and fov_angle > 0.0
	if fov_angle > 0.0:
		var c := Color(0.2, 0.8, 0.2, 0.3) if fov_active else Color(0.5, 0.5, 0.5, 0.2)
		var e := Color(0.2, 0.8, 0.2, 0.8) if fov_active else Color(0.5, 0.5, 0.5, 0.5)
		_draw_fov_cone(c, e)
	if _can_see_player and _player:
		draw_line(Vector2.ZERO, _player.global_position - global_position, Color.RED, 1.5)
		var wf := _get_weapon_forward_direction()
		var sp := _get_bullet_spawn_position(wf) - global_position
		if _is_bullet_spawn_clear(wf):
			draw_circle(sp, 5.0, Color.GREEN)
		else:
			draw_line(sp + Vector2(-5, -5), sp + Vector2(5, 5), Color.RED, 2.0)
			draw_line(sp + Vector2(-5, 5), sp + Vector2(5, -5), Color.RED, 2.0)
	if _has_valid_cover:
		var tc := _cover_position - global_position
		draw_line(Vector2.ZERO, tc, Color.CYAN, 1.5)
		draw_circle(tc, 8.0, Color.CYAN)
	if _seeking_clear_shot and _clear_shot_target != Vector2.ZERO:
		var tt := _clear_shot_target - global_position
		draw_line(Vector2.ZERO, tt, Color.YELLOW, 2.0)
		draw_line(tt + Vector2(-6, 6), tt + Vector2(6, 6), Color.YELLOW, 2.0)
		draw_line(tt + Vector2(6, 6), tt + Vector2(0, -8), Color.YELLOW, 2.0)
		draw_line(tt + Vector2(0, -8), tt + Vector2(-6, 6), Color.YELLOW, 2.0)
	if _current_state == AIState.PURSUING and _has_pursuit_cover:
		var tp := _pursuit_next_cover - global_position
		draw_line(Vector2.ZERO, tp, Color.ORANGE, 2.0)
		draw_circle(tp, 8.0, Color.ORANGE)
	if _current_state == AIState.FLANKING:
		if _has_flank_cover:
			var tf := _flank_next_cover - global_position
			draw_line(Vector2.ZERO, tf, Color.MAGENTA, 2.0)
			draw_circle(tf, 8.0, Color.MAGENTA)
		elif _flank_target != Vector2.ZERO:
			var tf := _flank_target - global_position
			draw_line(Vector2.ZERO, tf, Color.MAGENTA, 1.5)
			draw_line(tf + Vector2(0, -8), tf + Vector2(8, 0), Color.MAGENTA, 2.0)
			draw_line(tf + Vector2(8, 0), tf + Vector2(0, 8), Color.MAGENTA, 2.0)
			draw_line(tf + Vector2(0, 8), tf + Vector2(-8, 0), Color.MAGENTA, 2.0)
			draw_line(tf + Vector2(-8, 0), tf + Vector2(0, -8), Color.MAGENTA, 2.0)
	if _memory and _memory.has_target():
		var ts := _memory.suspected_position - global_position
		var cc := Color.YELLOW.lerp(Color.ORANGE_RED, _memory.confidence)
		draw_line(Vector2.ZERO, ts, cc, 1.0)
		var ur := 10.0 + (1.0 - _memory.confidence) * 90.0
		for i in range(16):
			var a1 := (float(i) / 16) * TAU
			var a2 := (float(i + 1) / 16) * TAU
			draw_line(ts + Vector2(cos(a1), sin(a1)) * ur, ts + Vector2(cos(a2), sin(a2)) * ur, cc, 1.5)
		draw_circle(ts, 5.0, cc)

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

# ============================================================================
# Status Effects (Blindness, Stun)
# ============================================================================

## Set the blinded state (from flashbang grenade).
## When blinded, the enemy cannot see the player.
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

# ============================================================================
# Grenade System (Issue #363)
# ============================================================================

## Get the current map/scene name for DifficultyManager queries.
func _get_current_map_name() -> String:
	var current_scene := get_tree().current_scene
	if current_scene != null:
		return current_scene.name
	return ""

## Initialize the grenade system with configured grenade count.
## Called from _ready() and can also be called to reset grenades.
func _initialize_grenade_system() -> void:
	_grenade_cooldown_timer = 0.0
	_is_throwing_grenade = false

	# Reset all trigger condition states
	_player_hidden_after_suppression_timer = 0.0
	_was_suppressed_before_hidden = false
	_saw_ally_suppressed = false
	_previous_player_distance = 0.0
	_witnessed_kills_count = 0
	_kill_witness_reset_timer = 0.0
	_heard_vulnerable_sound = false
	_vulnerable_sound_position = Vector2.ZERO
	_vulnerable_sound_timestamp = 0.0
	_fire_zone_center = Vector2.ZERO
	_fire_zone_last_sound = 0.0
	_fire_zone_total_duration = 0.0
	_fire_zone_valid = false

	# Determine grenade count: use export value if set, otherwise query DifficultyManager
	if grenade_count > 0:
		# Use explicitly set grenade count from export
		_grenades_remaining = grenade_count
		_log_grenade("Using export grenade_count: %d" % grenade_count)
	else:
		# Query DifficultyManager for map-based grenade assignment
		var map_name := _get_current_map_name()
		if DifficultyManager.are_enemy_grenades_enabled(map_name):
			_grenades_remaining = DifficultyManager.get_enemy_grenade_count(map_name)
			if _grenades_remaining > 0:
				_log_grenade("DifficultyManager assigned %d grenades (map: %s)" % [_grenades_remaining, map_name])
		else:
			_grenades_remaining = 0

	# Load grenade scene if needed
	if grenade_scene == null and _grenades_remaining > 0:
		var map_name := _get_current_map_name()
		var scene_path := DifficultyManager.get_enemy_grenade_scene_path(map_name)
		grenade_scene = load(scene_path)
		if grenade_scene == null:
			# Fallback to default frag grenade
			grenade_scene = preload("res://scenes/projectiles/FragGrenade.tscn")
			push_warning("[Enemy] Failed to load grenade scene: %s, using default" % scene_path)

	if _grenades_remaining > 0:
		_log_grenade("Grenade system initialized: %d grenades" % _grenades_remaining)

## Log grenade-specific debug messages.
func _log_grenade(message: String) -> void:
	if grenade_debug_logging:
		print("[Enemy.Grenade] %s" % message)
	_log_to_file("[Grenade] %s" % message)

## Update grenade trigger conditions. Called every physics frame.
## This updates the world state flags for grenade-related decisions.
func _update_grenade_triggers(delta: float) -> void:
	if not enable_grenade_throwing or _grenades_remaining <= 0:
		return

	# Update grenade cooldown timer
	if _grenade_cooldown_timer > 0.0:
		_grenade_cooldown_timer -= delta

	# Update kill witness reset timer (Trigger 3)
	if _kill_witness_reset_timer > 0.0:
		_kill_witness_reset_timer -= delta
		if _kill_witness_reset_timer <= 0.0:
			_witnessed_kills_count = 0

	# Update player hidden timer (Trigger 1)
	_update_trigger_suppression_hidden(delta)

	# Update player approach tracking (Trigger 2)
	_update_trigger_pursuit(delta)

	# Update sustained fire tracking (Trigger 5)
	_update_trigger_sustained_fire(delta)

	# Update GOAP world state with trigger flags
	_update_grenade_world_state()

## Update Trigger 1: Player suppressed us/allies, then hid for 6 seconds.
func _update_trigger_suppression_hidden(delta: float) -> void:
	# Check if we're currently suppressed or saw an ally get suppressed
	if _under_fire:
		_was_suppressed_before_hidden = true

	# If player was suppressing us but is now hidden
	if _was_suppressed_before_hidden and not _can_see_player:
		_player_hidden_after_suppression_timer += delta
	else:
		# Player is visible or we weren't suppressed - reset
		if _can_see_player:
			_player_hidden_after_suppression_timer = 0.0
			_was_suppressed_before_hidden = false

## Update Trigger 2: Player is pursuing suppressed thrower.
func _update_trigger_pursuit(delta: float) -> void:
	if _player == null:
		return

	var current_distance := global_position.distance_to(_player.global_position)

	# Track if player is getting closer (pursuit detection)
	# Only update if we had a previous measurement
	if _previous_player_distance > 0.0:
		var distance_delta := _previous_player_distance - current_distance
		var approach_speed := distance_delta / delta if delta > 0 else 0.0

		# Store in world state for GOAP planning
		_goap_world_state["player_approaching_speed"] = approach_speed

	_previous_player_distance = current_distance

## Update Trigger 5: 10 seconds of sustained fire in 1/6 viewport zone.
func _update_trigger_sustained_fire(delta: float) -> void:
	if not _fire_zone_valid:
		return

	var current_time := Time.get_ticks_msec() / 1000.0
	var time_since_last := current_time - _fire_zone_last_sound

	# If gap too long, invalidate the zone
	if time_since_last > GRENADE_FIRE_GAP_TOLERANCE:
		_fire_zone_valid = false
		_fire_zone_total_duration = 0.0

## Calculate the zone radius for sustained fire detection.
func _get_grenade_zone_radius() -> float:
	var viewport := get_viewport()
	if viewport == null:
		return 200.0  # Default fallback

	var viewport_size := viewport.get_visible_rect().size
	var viewport_diagonal := sqrt(viewport_size.x ** 2 + viewport_size.y ** 2)
	return viewport_diagonal / GRENADE_VIEWPORT_ZONE_FRACTION / 2.0

## Handle gunshot sounds for sustained fire tracking (Trigger 5).
## Called from on_sound_heard_with_intensity when a gunshot is detected.
func _on_gunshot_heard_for_grenade(position: Vector2) -> void:
	if not enable_grenade_throwing or _grenades_remaining <= 0:
		return

	var zone_radius := _get_grenade_zone_radius()
	var current_time := Time.get_ticks_msec() / 1000.0

	if _fire_zone_valid:
		var distance_to_zone := position.distance_to(_fire_zone_center)
		var time_since_last := current_time - _fire_zone_last_sound

		if distance_to_zone <= zone_radius and time_since_last <= GRENADE_FIRE_GAP_TOLERANCE:
			# Same zone, continuous fire
			_fire_zone_total_duration += time_since_last
			_fire_zone_last_sound = current_time

			if grenade_debug_logging:
				_log_grenade("Sustained fire: %.1fs in zone at %s" % [_fire_zone_total_duration, position])
		else:
			# Different zone or gap too long, reset
			_start_new_fire_zone(position, current_time)
	else:
		_start_new_fire_zone(position, current_time)

## Start tracking a new fire zone.
func _start_new_fire_zone(position: Vector2, time: float) -> void:
	_fire_zone_center = position
	_fire_zone_last_sound = time
	_fire_zone_total_duration = 0.0
	_fire_zone_valid = true

## Handle reload/empty click sounds for grenade targeting (Trigger 4).
## Called from on_sound_heard_with_intensity.
func _on_vulnerable_sound_heard_for_grenade(position: Vector2) -> void:
	if not enable_grenade_throwing or _grenades_remaining <= 0:
		return

	# Only react if we can't see the player
	if not _can_see_player:
		_heard_vulnerable_sound = true
		_vulnerable_sound_position = position
		_vulnerable_sound_timestamp = Time.get_ticks_msec() / 1000.0
		_log_grenade("Heard vulnerable sound at %s - potential grenade target" % position)

## Called when an ally dies. Updates witnessed kill count (Trigger 3).
## Connect this to ally death signals.
func on_ally_died(ally_position: Vector2, killer_is_player: bool) -> void:
	if not killer_is_player:
		return

	if not enable_grenade_throwing or _grenades_remaining <= 0:
		return

	# Check if we can see where the ally died
	if _can_see_position(ally_position):
		_witnessed_kills_count += 1
		_kill_witness_reset_timer = GRENADE_KILL_WITNESS_WINDOW
		_log_grenade("Witnessed ally kill #%d at %s" % [_witnessed_kills_count, ally_position])

## Check if a position is visible to this enemy (line of sight).
func _can_see_position(pos: Vector2) -> bool:
	if _raycast == null:
		return false

	# Temporarily set raycast to check this position
	var original_target := _raycast.target_position
	_raycast.target_position = pos - global_position
	_raycast.force_raycast_update()

	var can_see := not _raycast.is_colliding()
	_raycast.target_position = original_target

	return can_see

## Update GOAP world state with grenade trigger conditions.
func _update_grenade_world_state() -> void:
	_goap_world_state["has_grenades"] = _grenades_remaining > 0
	_goap_world_state["grenades_remaining"] = _grenades_remaining
	_goap_world_state["grenade_cooldown_ready"] = _grenade_cooldown_timer <= 0.0
	var t1 := _should_trigger_suppression_grenade()
	var t2 := _should_trigger_pursuit_grenade()
	var t3 := _should_trigger_witness_grenade()
	var t4 := _should_trigger_sound_grenade()
	var t5 := _should_trigger_sustained_fire_grenade()
	var t6 := _should_trigger_desperation_grenade()
	_goap_world_state["trigger_1_suppression_hidden"] = t1
	_goap_world_state["trigger_2_pursuit"] = t2
	_goap_world_state["trigger_3_witness_kills"] = t3
	_goap_world_state["trigger_4_sound_based"] = t4
	_goap_world_state["trigger_5_sustained_fire"] = t5
	_goap_world_state["trigger_6_desperation"] = t6
	var was_ready: bool = _goap_world_state.get("ready_to_throw_grenade", false)
	_goap_world_state["ready_to_throw_grenade"] = _grenade_cooldown_timer <= 0.0 and _grenades_remaining > 0 and (t1 or t2 or t3 or t4 or t5 or t6)
	if _goap_world_state["ready_to_throw_grenade"] and not was_ready:
		var tr: PackedStringArray = []
		if t1: tr.append("T1")
		if t2: tr.append("T2")
		if t3: tr.append("T3")
		if t4: tr.append("T4")
		if t5: tr.append("T5")
		if t6: tr.append("T6")
		_log_grenade("TRIGGER: %s (grenades: %d)" % [", ".join(tr), _grenades_remaining])

func _should_trigger_suppression_grenade() -> bool:
	return _was_suppressed_before_hidden and not _can_see_player and _player_hidden_after_suppression_timer >= GRENADE_HIDDEN_THRESHOLD

func _should_trigger_pursuit_grenade() -> bool:
	return _under_fire and _goap_world_state.get("player_approaching_speed", 0.0) >= GRENADE_PURSUIT_SPEED_THRESHOLD

func _should_trigger_witness_grenade() -> bool:
	return _witnessed_kills_count >= GRENADE_KILL_THRESHOLD

func _should_trigger_sound_grenade() -> bool:
	if not _heard_vulnerable_sound:
		return false
	var age := Time.get_ticks_msec() / 1000.0 - _vulnerable_sound_timestamp
	if age > GRENADE_SOUND_VALIDITY_WINDOW:
		_heard_vulnerable_sound = false
		return false
	return not _can_see_player

func _should_trigger_sustained_fire_grenade() -> bool:
	return _fire_zone_valid and _fire_zone_total_duration >= GRENADE_SUSTAINED_FIRE_THRESHOLD

func _should_trigger_desperation_grenade() -> bool:
	return _current_health <= GRENADE_DESPERATION_HEALTH_THRESHOLD

## Get the best grenade target position based on active triggers.
## Returns Vector2.ZERO if no valid target.
func _get_grenade_target_position() -> Vector2:
	# Priority order from lowest cost (highest priority) to highest cost

	# Trigger 6: Desperation - throw at last known player position
	if _should_trigger_desperation_grenade():
		if _player != null:
			return _player.global_position
		if _memory and _memory.has_target():
			return _memory.suspected_position

	# Trigger 4: Sound-based - throw where sound came from
	if _should_trigger_sound_grenade():
		return _vulnerable_sound_position

	# Trigger 2: Pursuit - throw behind us to slow pursuer
	if _should_trigger_pursuit_grenade():
		if _player != null:
			# Throw between us and the player
			var direction_to_player := (_player.global_position - global_position).normalized()
			var throw_distance := minf(200.0, global_position.distance_to(_player.global_position) * 0.5)
			return global_position + direction_to_player * throw_distance

	# Trigger 3: Witness kills - throw at last known player position
	if _should_trigger_witness_grenade():
		if _player != null and _can_see_player:
			return _player.global_position
		if _memory and _memory.has_target():
			return _memory.suspected_position

	# Trigger 5: Sustained fire - throw at fire zone center
	if _should_trigger_sustained_fire_grenade():
		return _fire_zone_center

	# Trigger 1: Suppression hidden - throw at last known position
	if _should_trigger_suppression_grenade():
		if _memory and _memory.has_target():
			return _memory.suspected_position
		return _last_known_player_position

	# No valid target
	return Vector2.ZERO

## Get grenade blast radius (Issue #375). Instantiates grenade to query effect_radius.
func _get_grenade_blast_radius() -> float:
	if grenade_scene == null: return 225.0  # Default frag grenade radius
	var temp_grenade = grenade_scene.instantiate()
	if temp_grenade == null: return 225.0  # Fallback
	var radius := temp_grenade.effect_radius if temp_grenade.get("effect_radius") != null else 225.0
	temp_grenade.queue_free()
	return radius

## Check if the enemy can throw a grenade right now.
func _can_throw_grenade() -> bool:
	if not enable_grenade_throwing or _grenades_remaining <= 0 or _grenade_cooldown_timer > 0.0: return false
	if _is_throwing_grenade or not _is_alive or _is_stunned or _is_blinded: return false
	return _goap_world_state.get("ready_to_throw_grenade", false)

## Attempt to throw a grenade. Returns true if throw was initiated.
func try_throw_grenade() -> bool:
	if not _can_throw_grenade(): return false
	var target_position := _get_grenade_target_position()
	if target_position == Vector2.ZERO: return false
	var distance := global_position.distance_to(target_position)
	# Issue #375: Check safe distance based on blast radius
	var min_safe_distance := _get_grenade_blast_radius() + grenade_safety_margin
	if distance < min_safe_distance:
		_log_grenade("Unsafe throw (%.0f < %.0f safe)" % [distance, min_safe_distance]); return false
	if distance < grenade_min_throw_distance:
		_log_grenade("Target too close (%.0f < %.0f)" % [distance, grenade_min_throw_distance]); return false
	if distance > grenade_max_throw_distance:
		target_position = global_position + (target_position - global_position).normalized() * grenade_max_throw_distance
	if not _is_throw_path_clear(target_position):
		_log_grenade("Throw path blocked to %s" % target_position); return false
	_execute_grenade_throw(target_position); return true

## Check if the grenade throw path is clear.
func _is_throw_path_clear(target_position: Vector2) -> bool:
	var space_state := get_world_2d().direct_space_state
	if space_state == null:
		return true  # Assume clear if we can't check

	var query := PhysicsRayQueryParameters2D.create(global_position, target_position)
	query.collision_mask = 4  # Only check obstacles (layer 3)
	query.exclude = [self]

	var result := space_state.intersect_ray(query)

	# Path is clear if no collision, or collision is past halfway point
	if result.is_empty():
		return true

	var collision_distance := global_position.distance_to(result.position)
	var total_distance := global_position.distance_to(target_position)

	# Allow throw if collision is past 60% of the way (grenade can arc over)
	return collision_distance > total_distance * 0.6

## Execute the grenade throw.
func _execute_grenade_throw(target_position: Vector2) -> void:
	if grenade_scene == null:
		_log_grenade("ERROR: No grenade scene configured!")
		return

	_is_throwing_grenade = true

	# Add delay before throwing grenade (telegraph/wind-up animation)
	if grenade_throw_delay > 0.0:
		_log_grenade("Preparing throw (%.0fms delay)..." % (grenade_throw_delay * 1000))
		await get_tree().create_timer(grenade_throw_delay).timeout

	# Safety checks after delay - enemy may have died or been incapacitated
	if not _is_alive or _is_stunned or _is_blinded:
		_log_grenade("Throw cancelled - incapacitated during delay")
		_is_throwing_grenade = false
		return
	if not is_instance_valid(self):
		return

	# Calculate throw direction with inaccuracy
	var base_direction := (target_position - global_position).normalized()
	var inaccuracy_angle := randf_range(-grenade_inaccuracy, grenade_inaccuracy)
	var throw_direction := base_direction.rotated(inaccuracy_angle)

	# Calculate throw distance
	var distance := global_position.distance_to(target_position)

	# Instantiate grenade
	var grenade: Node2D = grenade_scene.instantiate()

	# Set initial position slightly in front of enemy
	var spawn_offset := 40.0
	grenade.global_position = global_position + throw_direction * spawn_offset

	# Add to scene tree
	var parent := get_tree().current_scene
	if parent:
		parent.add_child(grenade)
	else:
		get_parent().add_child(grenade)

	# Activate and throw the grenade
	if grenade.has_method("activate_timer"):
		grenade.activate_timer()

	# Calculate throw velocity - use similar formula to player grenades
	var throw_speed := clampf(distance * 1.5, 200.0, 800.0)

	if grenade.has_method("throw_grenade"):
		grenade.throw_grenade(throw_direction, distance)
	elif grenade is RigidBody2D:
		# Direct physics fallback
		grenade.freeze = false
		grenade.linear_velocity = throw_direction * throw_speed
		grenade.rotation = throw_direction.angle()

	# Log the throw
	var trigger_name := _get_active_trigger_name()
	_log_grenade("THROWN! Target: %s, Distance: %.0f, Trigger: %s" % [target_position, distance, trigger_name])
	_log_to_file("Grenade thrown at %s (distance=%.0f, trigger=%s)" % [target_position, distance, trigger_name])

	# Update state
	_grenades_remaining -= 1
	_grenade_cooldown_timer = grenade_throw_cooldown
	_is_throwing_grenade = false

	# Clear trigger states that have been acted on
	_clear_acted_triggers()

	# Emit signal
	grenade_thrown.emit(grenade, target_position)

## Get the name of the currently active trigger (for logging).
func _get_active_trigger_name() -> String:
	if _should_trigger_desperation_grenade():
		return "Trigger6_Desperation"
	elif _should_trigger_sound_grenade():
		return "Trigger4_Sound"
	elif _should_trigger_pursuit_grenade():
		return "Trigger2_Pursuit"
	elif _should_trigger_witness_grenade():
		return "Trigger3_WitnessKills"
	elif _should_trigger_sustained_fire_grenade():
		return "Trigger5_SustainedFire"
	elif _should_trigger_suppression_grenade():
		return "Trigger1_SuppressionHidden"
	return "Unknown"

## Clear trigger states after a grenade has been thrown.
func _clear_acted_triggers() -> void:
	# Clear Trigger 1 state
	_player_hidden_after_suppression_timer = 0.0
	_was_suppressed_before_hidden = false

	# Clear Trigger 3 state
	_witnessed_kills_count = 0

	# Clear Trigger 4 state
	_heard_vulnerable_sound = false

	# Clear Trigger 5 state
	_fire_zone_valid = false
	_fire_zone_total_duration = 0.0

## Get the number of grenades remaining.
func get_grenades_remaining() -> int:
	return _grenades_remaining

## Add grenades to the enemy's inventory.
func add_grenades(count: int) -> void:
	_grenades_remaining += count
	_log_grenade("Added %d grenades, now have %d" % [count, _grenades_remaining])
