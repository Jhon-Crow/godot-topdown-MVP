extends CharacterBody2D
## Enemy AI with tactical behaviors including patrol, guard, cover, and flanking.
##
## Supports multiple behavior modes:
## - PATROL: Moves between patrol points
## - GUARD: Stands in place watching for the player
##
## Tactical features:
## - Uses cover when under fire (suppression)
## - Attempts to flank the player from the sides
## - Coordinates with other enemies (optional)
## - GOAP foundation for goal-oriented planning

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
	ASSAULT     ## Coordinated multi-enemy assault (rush player after 5s wait)
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

## Rotation speed in radians per second for gradual turning.
## Default is 15 rad/sec for challenging but fair combat.
@export var rotation_speed: float = 15.0

## Detection range for spotting the player.
## Set to 0 or negative to allow unlimited detection range (line-of-sight only).
## This allows enemies to see the player even outside the viewport if no obstacles block view.
@export var detection_range: float = 0.0

## Time between shots in seconds.
## Default matches assault rifle fire rate (10 shots/second = 0.1s cooldown).
@export var shoot_cooldown: float = 0.1

## Bullet scene to instantiate when shooting.
@export var bullet_scene: PackedScene

## Offset from enemy center for bullet spawn position.
@export var bullet_spawn_offset: float = 30.0

## Patrol points as offsets from the initial position.
## Only used when behavior_mode is PATROL.
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

## Delay (in seconds) before reacting to bullets in the threat sphere.
## This prevents instant reactions to nearby gunfire, giving the player more time.
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

## Bullet speed for lead prediction calculation.
## Should match the actual bullet speed (default is 2500 for assault rifle).
@export var bullet_speed: float = 2500.0

## Ammunition system - magazine size (bullets per magazine).
@export var magazine_size: int = 30

## Ammunition system - number of magazines the enemy carries.
@export var total_magazines: int = 5

## Ammunition system - time to reload in seconds.
@export var reload_time: float = 3.0

## Delay (in seconds) between spotting player and starting to shoot.
## Gives player a brief reaction time when entering enemy line of sight.
## This delay "recharges" each time the player breaks direct contact with the enemy.
@export var detection_delay: float = 0.2

## Minimum time (in seconds) the player must be continuously visible before
## lead prediction is enabled. This prevents enemies from predicting player
## position immediately when they emerge from cover.
@export var lead_prediction_delay: float = 0.3

## Minimum visibility ratio (0.0 to 1.0) of player body that must be visible
## before lead prediction is enabled. At 1.0, the player's entire body must be
## visible. At 0.5, at least half of the check points must be visible.
## This prevents pre-firing at players who are at cover edges.
@export var lead_prediction_visibility_threshold: float = 0.6

## Signal emitted when the enemy is hit.
signal hit

## Signal emitted when the enemy dies.
signal died

## Signal emitted when AI state changes.
signal state_changed(new_state: AIState)

## Signal emitted when ammunition changes.
signal ammo_changed(current_ammo: int, reserve_ammo: int)

## Signal emitted when reloading starts.
signal reload_started

## Signal emitted when reloading finishes.
signal reload_finished

## Signal emitted when all ammunition is depleted.
signal ammo_depleted

## Reference to the sprite for color changes.
@onready var _sprite: Sprite2D = $Sprite2D

## RayCast2D for line of sight detection.
@onready var _raycast: RayCast2D = $RayCast2D

## Debug label for showing current AI state above the enemy.
@onready var _debug_label: Label = $DebugLabel

## Wall detection raycasts for obstacle avoidance (created at runtime).
var _wall_raycasts: Array[RayCast2D] = []

## Distance to check for walls ahead.
const WALL_CHECK_DISTANCE: float = 40.0

## Number of raycasts for wall detection (spread around the enemy).
const WALL_CHECK_COUNT: int = 3

## Cover detection raycasts (created at runtime).
var _cover_raycasts: Array[RayCast2D] = []

## Number of raycasts for cover detection.
const COVER_CHECK_COUNT: int = 16

## Distance to check for cover.
const COVER_CHECK_DISTANCE: float = 300.0

## Current health of the enemy.
var _current_health: int = 0

## Maximum health of the enemy (set at spawn).
var _max_health: int = 0

## Whether the enemy is alive.
var _is_alive: bool = true

## Reference to the player (found at runtime).
var _player: Node2D = null

## Time since last shot.
var _shoot_timer: float = 0.0

## Current ammo in the magazine.
var _current_ammo: int = 0

## Reserve ammo (ammo in remaining magazines).
var _reserve_ammo: int = 0

## Whether the enemy is currently reloading.
var _is_reloading: bool = false

## Timer for reload progress.
var _reload_timer: float = 0.0

## Patrol state variables.
var _patrol_points: Array[Vector2] = []
var _current_patrol_index: int = 0
var _is_waiting_at_patrol_point: bool = false
var _patrol_wait_timer: float = 0.0
var _initial_position: Vector2

## Whether the enemy can currently see the player.
var _can_see_player: bool = false

## Current AI state.
var _current_state: AIState = AIState.IDLE

## Current cover position (if any).
var _cover_position: Vector2 = Vector2.ZERO

## Is currently in a valid cover position.
var _has_valid_cover: bool = false

## Timer for suppression cooldown.
var _suppression_timer: float = 0.0

## Whether enemy is currently under fire (bullets in threat sphere).
var _under_fire: bool = false

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

## Memory of bullets that have passed through the threat sphere recently.
## This allows the enemy to react even after fast-moving bullets have exited.
var _threat_memory_timer: float = 0.0

## Duration to remember that a bullet passed through the threat sphere.
## This should be longer than the reaction delay to ensure enemies can complete
## their reaction even after bullets have passed through quickly.
const THREAT_MEMORY_DURATION: float = 0.5

## Current retreat mode determined by damage taken.
var _retreat_mode: RetreatMode = RetreatMode.FULL_HP

## Number of hits taken during the current retreat/combat encounter.
## Resets when enemy enters IDLE state or finishes retreating.
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

## Whether enemy is in "alarm" mode (was suppressed/retreating and hasn't calmed down).
## This persists until the enemy reaches safety in cover or returns to idle.
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

## Whether the enemy is in the "approaching player" phase of combat.
## In this phase, the enemy moves toward the player to get into direct contact.
var _combat_approaching: bool = false

## Timer for the approach phase of combat.
var _combat_approach_timer: float = 0.0

## Maximum time to spend approaching player before starting to shoot (seconds).
const COMBAT_APPROACH_MAX_TIME: float = 2.0

## Distance at which enemy is considered "close enough" to start shooting phase.
const COMBAT_DIRECT_CONTACT_DISTANCE: float = 250.0

## --- Pursuit State (cover-to-cover movement) ---
## Timer for waiting at cover during pursuit.
var _pursuit_cover_wait_timer: float = 0.0

## Duration to wait at each cover during pursuit (1-2 seconds, reduced for faster pursuit).
const PURSUIT_COVER_WAIT_DURATION: float = 1.5

## Current pursuit target cover position.
var _pursuit_next_cover: Vector2 = Vector2.ZERO

## Whether the enemy has a valid pursuit cover target.
var _has_pursuit_cover: bool = false

## --- Flanking State (cover-to-cover movement toward flank target) ---
## Timer for waiting at cover during flanking.
var _flank_cover_wait_timer: float = 0.0

## Duration to wait at each cover during flanking (seconds).
const FLANK_COVER_WAIT_DURATION: float = 0.8

## Current flank cover position to move to.
var _flank_next_cover: Vector2 = Vector2.ZERO

## Whether the enemy has a valid flank cover target.
var _has_flank_cover: bool = false

## --- Assault State (coordinated multi-enemy rush) ---
## Timer for assault wait period (5 seconds before rushing).
var _assault_wait_timer: float = 0.0

## Duration to wait at cover before assault (5 seconds).
const ASSAULT_WAIT_DURATION: float = 5.0

## Whether the assault wait period is complete.
var _assault_ready: bool = false

## Whether this enemy is currently participating in an assault.
var _in_assault: bool = false

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



func _ready() -> void:
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
	_connect_debug_mode_signal()
	_update_debug_label()

	# Log that this enemy is ready (use call_deferred to ensure FileLogger is loaded)
	call_deferred("_log_spawn_info")

	# Preload bullet scene if not set in inspector
	if bullet_scene == null:
		bullet_scene = preload("res://scenes/projectiles/Bullet.tscn")


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
		"enemies_in_combat": 0
	}


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

	# Check for player visibility and try to find player if not found
	if _player == null:
		_find_player()

	_check_player_visibility()
	_update_goap_state()
	_update_suppression(delta)

	# Process AI state machine
	_process_ai_state(delta)

	# Update debug label if enabled
	_update_debug_label()

	# Request redraw for debug visualization
	if debug_label_enabled:
		queue_redraw()

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
	var previous_state := _current_state

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

	# Execute idle behavior
	match behavior_mode:
		BehaviorMode.PATROL:
			_process_patrol(delta)
		BehaviorMode.GUARD:
			_process_guard(delta)


## Process COMBAT state - approach player for direct contact, shoot for 2-3 seconds, return to cover.
## Implements the combat cycling behavior: exit cover -> exposed shooting -> return to cover.
## Phase 0 (seeking clear shot): If bullet spawn blocked, move out from cover to find clear shot.
## Phase 1 (approaching): Move toward player to get into direct contact range.
## Phase 2 (exposed): Stand and shoot for 2-3 seconds.
## Phase 3: Return to cover via SEEKING_COVER state.
func _process_combat_state(delta: float) -> void:
	# Check for suppression - transition to retreating behavior
	if _under_fire and enable_cover:
		_combat_exposed = false
		_combat_approaching = false
		_seeking_clear_shot = false
		_transition_to_retreating()
		return

	# Check if multiple enemies are in combat - transition to assault state
	var enemies_in_combat := _count_enemies_in_combat()
	if enemies_in_combat >= 2:
		_log_debug("Multiple enemies in combat (%d), transitioning to ASSAULT" % enemies_in_combat)
		_combat_exposed = false
		_combat_approaching = false
		_seeking_clear_shot = false
		_transition_to_assault()
		return

	# If can't see player, pursue them (move cover-to-cover toward player)
	if not _can_see_player:
		_combat_exposed = false
		_combat_approaching = false
		_seeking_clear_shot = false
		_log_debug("Lost sight of player in COMBAT, transitioning to PURSUING")
		_transition_to_pursuing()
		return

	# Update detection delay timer
	if not _detection_delay_elapsed:
		_detection_timer += delta
		if _detection_timer >= detection_delay:
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
			if enable_flanking:
				_transition_to_flanking()
			else:
				_transition_to_pursuing()
			return

		# Move toward the clear shot target position
		var distance_to_target := global_position.distance_to(_clear_shot_target)
		if distance_to_target > 15.0:
			var move_direction := (_clear_shot_target - global_position).normalized()

			# Apply wall avoidance
			var avoidance := _check_wall_ahead(move_direction)
			if avoidance != Vector2.ZERO:
				move_direction = (move_direction * 0.5 + avoidance * 0.5).normalized()

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

		# Apply wall avoidance
		var avoidance := _check_wall_ahead(move_direction)
		if avoidance != Vector2.ZERO:
			move_direction = (move_direction * 0.5 + avoidance * 0.5).normalized()

		velocity = move_direction * combat_move_speed
		rotation = direction_to_player.angle()  # Always face player

		# Can shoot while approaching (only after detection delay and if have clear shot)
		if has_clear_shot and _detection_delay_elapsed and _shoot_timer >= shoot_cooldown:
			_aim_at_player()
			_shoot()
			_shoot_timer = 0.0


## Calculate a target position to exit cover and get a clear shot.
## Returns a position that should allow the bullet spawn point to be unobstructed.
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
	var direction := (_cover_position - global_position).normalized()
	var distance := global_position.distance_to(_cover_position)

	if distance < 10.0:
		# Reached the cover position, but still visible - try to find better cover
		if _is_visible_from_player():
			_has_valid_cover = false
			_find_cover_position()
			if not _has_valid_cover:
				# No better cover found, stay in combat
				_transition_to_combat()
				return

	# Apply wall avoidance
	var avoidance := _check_wall_ahead(direction)
	if avoidance != Vector2.ZERO:
		direction = (direction * 0.5 + avoidance * 0.5).normalized()

	velocity = direction * combat_move_speed
	rotation = direction.angle()

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

	# Check if multiple enemies are in combat - transition to assault state
	var enemies_in_combat := _count_enemies_in_combat()
	if enemies_in_combat >= 2:
		_log_debug("Multiple enemies detected (%d), transitioning to ASSAULT" % enemies_in_combat)
		_transition_to_assault()
		return

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


## Process FLANKING state - attempting to flank the player using cover-to-cover movement.
## Uses intermediate cover positions to navigate around obstacles instead of walking
## directly toward the flank target.
func _process_flanking_state(delta: float) -> void:
	# If under fire, retreat with shooting behavior
	if _under_fire and enable_cover:
		_transition_to_retreating()
		return

	# If can see player, engage in combat
	if _can_see_player:
		_transition_to_combat()
		return

	if _player == null:
		_transition_to_idle()
		return

	# Recalculate flank position (player may have moved)
	_calculate_flank_position()

	var distance_to_flank := global_position.distance_to(_flank_target)

	# Check if we've reached the flank target
	if distance_to_flank < 30.0:
		_log_debug("Reached flank position, engaging")
		_transition_to_combat()
		return

	# Check if we have direct line of sight to flank target (no obstacles)
	if _has_clear_path_to(_flank_target):
		# Direct path is clear - move directly toward flank target
		var direction := (_flank_target - global_position).normalized()
		var avoidance := _check_wall_ahead(direction)
		if avoidance != Vector2.ZERO:
			direction = (direction * 0.5 + avoidance * 0.5).normalized()
		velocity = direction * combat_move_speed
		rotation = direction.angle()
		_has_flank_cover = false
		return

	# Path is blocked - use cover-to-cover movement

	# If we're at a cover position, wait briefly before moving to next
	if _has_valid_cover and not _has_flank_cover:
		_flank_cover_wait_timer += delta
		velocity = Vector2.ZERO

		if _flank_cover_wait_timer >= FLANK_COVER_WAIT_DURATION:
			# Done waiting, find next cover toward flank target
			_find_flank_cover_toward_target()
			if not _has_flank_cover:
				_log_debug("No flank cover found, attempting direct movement")
				# No cover found - try direct movement with enhanced wall avoidance
				var direction := (_flank_target - global_position).normalized()
				var avoidance := _check_wall_ahead(direction)
				if avoidance != Vector2.ZERO:
					direction = (direction * 0.5 + avoidance * 0.5).normalized()
				velocity = direction * combat_move_speed
				rotation = direction.angle()
				# Invalidate current cover to trigger new search next frame
				_has_valid_cover = false
		return

	# If we have a flank cover target, move toward it
	if _has_flank_cover:
		var direction := (_flank_next_cover - global_position).normalized()
		var distance := global_position.distance_to(_flank_next_cover)

		# Check if we've reached the flank cover
		if distance < 15.0:
			_log_debug("Reached flank cover at distance %.1f" % distance)
			_has_flank_cover = false
			_flank_cover_wait_timer = 0.0
			_cover_position = _flank_next_cover
			_has_valid_cover = true
			# Start waiting at this cover
			return

		# Apply wall avoidance
		var avoidance := _check_wall_ahead(direction)
		if avoidance != Vector2.ZERO:
			direction = (direction * 0.5 + avoidance * 0.5).normalized()

		velocity = direction * combat_move_speed
		rotation = direction.angle()
		return

	# No cover and no flank cover target - find initial flank cover
	_find_flank_cover_toward_target()
	if not _has_flank_cover:
		# Can't find cover, try direct movement with wall avoidance
		var direction := (_flank_target - global_position).normalized()
		var avoidance := _check_wall_ahead(direction)
		if avoidance != Vector2.ZERO:
			direction = (direction * 0.5 + avoidance * 0.5).normalized()
		velocity = direction * combat_move_speed
		rotation = direction.angle()


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


## Process FULL_HP retreat: walk backwards facing player, shoot with reduced accuracy,
## periodically turn toward cover.
func _process_retreat_full_hp(delta: float, direction_to_cover: Vector2) -> void:
	_retreat_turn_timer += delta

	if _retreat_turning_to_cover:
		# Turning to face cover, don't shoot
		if _retreat_turn_timer >= RETREAT_TURN_DURATION:
			_retreat_turning_to_cover = false
			_retreat_turn_timer = 0.0

		# Face cover and move toward it
		rotation = direction_to_cover.angle()
		var avoidance := _check_wall_ahead(direction_to_cover)
		if avoidance != Vector2.ZERO:
			direction_to_cover = (direction_to_cover * 0.5 + avoidance * 0.5).normalized()
		velocity = direction_to_cover * combat_move_speed
	else:
		# Face player and back up (walk backwards)
		if _retreat_turn_timer >= RETREAT_TURN_INTERVAL:
			_retreat_turning_to_cover = true
			_retreat_turn_timer = 0.0
			_log_debug("FULL_HP retreat: turning to check cover")

		if _player:
			# Face the player
			var direction_to_player := (_player.global_position - global_position).normalized()
			_aim_at_player()

			# Move backwards (opposite of player direction = toward cover generally)
			# Use the negative of the direction we're facing for "backing up"
			var move_direction := -direction_to_player

			# Apply wall avoidance
			var avoidance := _check_wall_ahead(move_direction)
			if avoidance != Vector2.ZERO:
				move_direction = (move_direction * 0.5 + avoidance * 0.5).normalized()

			velocity = move_direction * combat_move_speed * 0.7  # Slower when backing up

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
			var direction_to_player := (_player.global_position - global_position).normalized()
			var target_angle: float

			# Interpolate rotation from player direction to cover direction
			var burst_progress := 1.0 - (float(_retreat_burst_remaining) / 4.0)
			var player_angle := direction_to_player.angle()
			var cover_angle := direction_to_cover.angle()
			target_angle = lerp_angle(player_angle, cover_angle, burst_progress * 0.7)
			rotation = target_angle

		# Move toward cover (slower during burst)
		var avoidance := _check_wall_ahead(direction_to_cover)
		if avoidance != Vector2.ZERO:
			direction_to_cover = (direction_to_cover * 0.5 + avoidance * 0.5).normalized()
		velocity = direction_to_cover * combat_move_speed * 0.5

		# Check if burst is complete
		if _retreat_burst_remaining <= 0:
			_retreat_burst_complete = true
			_log_debug("ONE_HIT retreat: burst complete, now running to cover")
	else:
		# After burst, run to cover without shooting
		rotation = direction_to_cover.angle()
		var avoidance := _check_wall_ahead(direction_to_cover)
		if avoidance != Vector2.ZERO:
			direction_to_cover = (direction_to_cover * 0.5 + avoidance * 0.5).normalized()
		velocity = direction_to_cover * combat_move_speed


## Process MULTIPLE_HITS retreat: quick burst of 2-4 shots then run to cover (same as ONE_HIT).
func _process_retreat_multiple_hits(delta: float, direction_to_cover: Vector2) -> void:
	# Same behavior as ONE_HIT - quick burst then escape
	_process_retreat_one_hit(delta, direction_to_cover)


## Process PURSUING state - move cover-to-cover toward player.
## Enemy moves between covers, waiting 1-2 seconds at each cover,
## until they can see and hit the player.
func _process_pursuing_state(delta: float) -> void:
	# Check for suppression - transition to retreating behavior
	if _under_fire and enable_cover:
		_transition_to_retreating()
		return

	# Check if multiple enemies are in combat - transition to assault state
	var enemies_in_combat := _count_enemies_in_combat()
	if enemies_in_combat >= 2:
		_log_debug("Multiple enemies detected during pursuit (%d), transitioning to ASSAULT" % enemies_in_combat)
		_transition_to_assault()
		return

	# If can see player and can hit them from current position, engage
	if _can_see_player and _player:
		var can_hit := _can_hit_player_from_current_position()
		if can_hit:
			_log_debug("Can see and hit player from pursuit, transitioning to COMBAT")
			_has_pursuit_cover = false
			_transition_to_combat()
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
				# No pursuit cover found - fallback behavior
				_log_debug("No pursuit cover found, checking fallback options")
				# If we can now see the player, engage directly
				if _can_see_player:
					_log_debug("Can see player, transitioning to COMBAT")
					_transition_to_combat()
					return
				# Try flanking
				if enable_flanking and _player:
					_log_debug("Attempting flanking maneuver")
					_transition_to_flanking()
					return
				# Last resort: move directly toward player
				_log_debug("No cover options, moving directly toward player")
				_transition_to_combat()
				return
		return

	# If we have a pursuit cover target, move toward it
	if _has_pursuit_cover:
		var direction := (_pursuit_next_cover - global_position).normalized()
		var distance := global_position.distance_to(_pursuit_next_cover)

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

		# Apply wall avoidance
		var avoidance := _check_wall_ahead(direction)
		if avoidance != Vector2.ZERO:
			direction = (direction * 0.5 + avoidance * 0.5).normalized()

		velocity = direction * combat_move_speed
		rotation = direction.angle()
		return

	# No cover and no pursuit target - find initial pursuit cover
	_find_pursuit_cover_toward_player()
	if not _has_pursuit_cover:
		# Can't find cover to pursue, try flanking or combat
		if enable_flanking and _player:
			_transition_to_flanking()
		else:
			_transition_to_combat()


## Process ASSAULT state - coordinated multi-enemy rush.
## Wait at cover for 5 seconds, then all enemies rush the player simultaneously.
func _process_assault_state(delta: float) -> void:
	# Check for suppression - transition to retreating behavior
	if _under_fire and enable_cover and not _assault_ready:
		_in_assault = false
		_transition_to_retreating()
		return

	# Check if we're the only enemy left in assault - switch back to combat
	var enemies_in_combat := _count_enemies_in_combat()
	if enemies_in_combat < 2 and not _assault_ready:
		_log_debug("Not enough enemies for assault, switching to COMBAT")
		_in_assault = false
		_transition_to_combat()
		return

	# Find closest cover to player if we don't have one
	if not _has_valid_cover:
		_find_cover_closest_to_player()
		if _has_valid_cover:
			_log_debug("Found assault cover at %s" % _cover_position)

	# Move to cover position first
	if _has_valid_cover and not _in_assault:
		var distance_to_cover := global_position.distance_to(_cover_position)
		if distance_to_cover > 15.0 and _is_visible_from_player():
			# Still need to reach cover
			var direction := (_cover_position - global_position).normalized()
			var avoidance := _check_wall_ahead(direction)
			if avoidance != Vector2.ZERO:
				direction = (direction * 0.5 + avoidance * 0.5).normalized()
			velocity = direction * combat_move_speed
			rotation = direction.angle()
			return

	# At cover, wait for assault timer
	if not _assault_ready:
		velocity = Vector2.ZERO
		_assault_wait_timer += delta

		# Check if all assault enemies are ready (synchronized assault)
		if _assault_wait_timer >= ASSAULT_WAIT_DURATION:
			# Check if situation has changed - player might have moved
			if _player and _is_player_close():
				_assault_ready = true
				_in_assault = true
				_log_debug("ASSAULT ready - rushing player!")
			else:
				# Player moved away, reset timer and check if we should pursue
				_log_debug("Player moved away during assault wait, resetting")
				_assault_wait_timer = 0.0
				_in_assault = false
				_transition_to_pursuing()
				return
		return

	# Assault phase - rush the player while shooting
	if _assault_ready and _player:
		var direction_to_player := (_player.global_position - global_position).normalized()
		var distance_to_player := global_position.distance_to(_player.global_position)

		# Apply wall avoidance
		var avoidance := _check_wall_ahead(direction_to_player)
		if avoidance != Vector2.ZERO:
			direction_to_player = (direction_to_player * 0.5 + avoidance * 0.5).normalized()

		# Rush at full speed
		velocity = direction_to_player * combat_move_speed
		rotation = direction_to_player.angle()

		# Update detection delay timer
		if not _detection_delay_elapsed:
			_detection_timer += delta
			if _detection_timer >= detection_delay:
				_detection_delay_elapsed = true

		# Shoot while rushing (only after detection delay)
		if _can_see_player and _detection_delay_elapsed and _shoot_timer >= shoot_cooldown:
			_aim_at_player()
			_shoot()
			_shoot_timer = 0.0

		# If very close to player, stay in combat
		if distance_to_player < 50.0:
			_log_debug("Assault complete - reached player")
			_assault_ready = false
			_in_assault = false
			_transition_to_combat()


## Shoot with reduced accuracy for retreat mode.
func _shoot_with_inaccuracy() -> void:
	if bullet_scene == null or _player == null:
		return

	if not _can_shoot():
		return

	var target_position := _player.global_position

	# Check if the shot should be taken
	if not _should_shoot_at_target(target_position):
		return

	var direction := (target_position - global_position).normalized()

	# Add inaccuracy spread
	var inaccuracy_angle := randf_range(-RETREAT_INACCURACY_SPREAD, RETREAT_INACCURACY_SPREAD)
	direction = direction.rotated(inaccuracy_angle)

	# Check if the inaccurate shot direction would hit a wall
	if not _is_bullet_spawn_clear(direction):
		_log_debug("Inaccurate shot blocked: wall in path after rotation")
		return

	# Create and fire bullet
	var bullet := bullet_scene.instantiate()
	bullet.global_position = global_position + direction * bullet_spawn_offset
	bullet.direction = direction
	bullet.shooter_id = get_instance_id()
	get_tree().current_scene.add_child(bullet)

	# Play sounds
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_m16_shot"):
		audio_manager.play_m16_shot(global_position)
	_play_delayed_shell_sound()

	# Consume ammo
	_current_ammo -= 1
	ammo_changed.emit(_current_ammo, _reserve_ammo)

	if _current_ammo <= 0 and _reserve_ammo > 0:
		_start_reload()


## Shoot a burst shot with arc spread for ONE_HIT retreat.
func _shoot_burst_shot() -> void:
	if bullet_scene == null or _player == null:
		return

	if not _can_shoot():
		return

	var target_position := _player.global_position
	var direction := (target_position - global_position).normalized()

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
	bullet.global_position = global_position + direction * bullet_spawn_offset
	bullet.direction = direction
	bullet.shooter_id = get_instance_id()
	get_tree().current_scene.add_child(bullet)

	# Play sounds
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_m16_shot"):
		audio_manager.play_m16_shot(global_position)
	_play_delayed_shell_sound()

	# Consume ammo
	_current_ammo -= 1
	ammo_changed.emit(_current_ammo, _reserve_ammo)

	if _current_ammo <= 0 and _reserve_ammo > 0:
		_start_reload()


## Transition to IDLE state.
func _transition_to_idle() -> void:
	_current_state = AIState.IDLE
	# Reset encounter hit tracking when returning to idle
	_hits_taken_in_encounter = 0
	# Reset alarm mode when returning to idle
	_in_alarm_mode = false
	_cover_burst_pending = false


## Transition to COMBAT state.
func _transition_to_combat() -> void:
	_current_state = AIState.COMBAT
	# Reset detection delay timer when entering combat
	_detection_timer = 0.0
	_detection_delay_elapsed = false
	# Reset combat phase variables
	_combat_exposed = false
	_combat_approaching = false
	_combat_shoot_timer = 0.0
	_combat_approach_timer = 0.0
	# Reset clear shot seeking variables
	_seeking_clear_shot = false
	_clear_shot_timer = 0.0
	_clear_shot_target = Vector2.ZERO


## Transition to SEEKING_COVER state.
func _transition_to_seeking_cover() -> void:
	_current_state = AIState.SEEKING_COVER
	_find_cover_position()


## Transition to IN_COVER state.
func _transition_to_in_cover() -> void:
	_current_state = AIState.IN_COVER


## Transition to FLANKING state.
func _transition_to_flanking() -> void:
	_current_state = AIState.FLANKING
	_calculate_flank_position()
	_flank_cover_wait_timer = 0.0
	_has_flank_cover = false
	_has_valid_cover = false


## Transition to SUPPRESSED state.
func _transition_to_suppressed() -> void:
	_current_state = AIState.SUPPRESSED
	# Enter alarm mode when suppressed
	_in_alarm_mode = true


## Transition to PURSUING state.
func _transition_to_pursuing() -> void:
	_current_state = AIState.PURSUING
	_pursuit_cover_wait_timer = 0.0
	_has_pursuit_cover = false
	# Reset detection delay for new engagement
	_detection_timer = 0.0
	_detection_delay_elapsed = false


## Transition to ASSAULT state.
func _transition_to_assault() -> void:
	_current_state = AIState.ASSAULT
	_assault_wait_timer = 0.0
	_assault_ready = false
	_in_assault = false
	# Reset detection delay for new engagement
	_detection_timer = 0.0
	_detection_delay_elapsed = false
	# Find closest cover to player for assault position
	_find_cover_closest_to_player()


## Transition to RETREATING state with appropriate retreat mode.
func _transition_to_retreating() -> void:
	_current_state = AIState.RETREATING
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

	var direction := (target_position - global_position).normalized()
	var distance := global_position.distance_to(target_position)

	# Use direct space state to check if any enemies are in the firing line
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.new()
	query.from = global_position + direction * bullet_spawn_offset  # Start from bullet spawn point
	query.to = target_position
	query.collision_mask = 2  # Only check enemies (layer 2)
	query.exclude = [get_rid()]  # Exclude self using RID

	var result := space_state.intersect_ray(query)

	if result.is_empty():
		return true  # No enemies in the way

	# Check if the hit position is before the target
	var hit_position: Vector2 = result["position"]
	var distance_to_hit := global_position.distance_to(hit_position)

	if distance_to_hit < distance - 20.0:  # 20 pixel tolerance
		_log_debug("Friendly in firing line at distance %0.1f (target at %0.1f)" % [distance_to_hit, distance])
		return false

	return true


## Check if a bullet fired at the target position would be blocked by cover/obstacles.
## Returns true if the shot would likely hit the target, false if blocked by cover.
func _is_shot_clear_of_cover(target_position: Vector2) -> bool:
	var direction := (target_position - global_position).normalized()
	var distance := global_position.distance_to(target_position)

	# Use direct space state to check if obstacles block the shot
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.new()
	query.from = global_position + direction * bullet_spawn_offset  # Start from bullet spawn point
	query.to = target_position
	query.collision_mask = 4  # Only check obstacles (layer 3)

	var result := space_state.intersect_ray(query)

	if result.is_empty():
		return true  # No obstacles in the way

	# Check if the obstacle is before the target position
	var hit_position: Vector2 = result["position"]
	var distance_to_hit := global_position.distance_to(hit_position)

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


## Find a sidestep direction that would lead to a clear shot position.
## Checks perpendicular directions to the player and returns the first one
## that would allow the bullet spawn point to be clear.
## Returns Vector2.ZERO if no clear direction is found.
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


## Check if the enemy should shoot at the current target.
## Validates bullet spawn clearance, friendly fire avoidance, and cover blocking.
func _should_shoot_at_target(target_position: Vector2) -> bool:
	# Check if the immediate path to bullet spawn is clear
	# This prevents shooting into walls the enemy is flush against
	var direction := (target_position - global_position).normalized()
	if not _is_bullet_spawn_clear(direction):
		return false

	# Check if friendlies are in the way
	if not _is_firing_line_clear_of_friendlies(target_position):
		return false

	# Check if cover blocks the shot
	if not _is_shot_clear_of_cover(target_position):
		return false

	return true


## Check if the player is "close" (within CLOSE_COMBAT_DISTANCE).
## Used to determine if the enemy should engage directly or pursue.
func _is_player_close() -> bool:
	if _player == null:
		return false
	return global_position.distance_to(_player.global_position) <= CLOSE_COMBAT_DISTANCE


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
func _find_pursuit_cover_toward_player() -> void:
	if _player == null:
		_has_pursuit_cover = false
		return

	var player_pos := _player.global_position
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

			# For pursuit, we want cover that is:
			# 1. Closer to the player than we currently are
			# 2. Hidden from the player (or mostly hidden)
			# 3. Not too far from our current position

			var my_distance_to_player := global_position.distance_to(player_pos)
			var cover_distance_to_player := cover_pos.distance_to(player_pos)
			var cover_distance_from_me := global_position.distance_to(cover_pos)

			# Skip covers that don't bring us closer to player
			if cover_distance_to_player >= my_distance_to_player:
				continue

			# Skip covers that are too close to current position (would cause looping)
			# Must be at least 30 pixels away to be a meaningful movement
			if cover_distance_from_me < 30.0:
				continue

			# Check if this position is hidden from player
			var is_hidden := not _is_position_visible_from_player(cover_pos)

			# Score calculation:
			# Higher score for positions that are:
			# - Hidden from player (priority)
			# - Closer to player
			# - Not too far from current position
			var hidden_score: float = 5.0 if is_hidden else 0.0
			var approach_score: float = (my_distance_to_player - cover_distance_to_player) / CLOSE_COMBAT_DISTANCE
			var distance_penalty: float = cover_distance_from_me / COVER_CHECK_DISTANCE

			var total_score: float = hidden_score + approach_score * 2.0 - distance_penalty

			if total_score > best_score:
				best_score = total_score
				best_cover = cover_pos
				found_valid_cover = true

	if found_valid_cover:
		_pursuit_next_cover = best_cover
		_has_pursuit_cover = true
		_log_debug("Found pursuit cover at %s (score: %.2f)" % [_pursuit_next_cover, best_score])
	else:
		_has_pursuit_cover = false


## Find cover position closest to the player for assault positioning.
## Used during ASSAULT state to take the nearest safe cover to the player.
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


## Calculate flank position based on player location.
func _calculate_flank_position() -> void:
	if _player == null:
		return

	var player_pos := _player.global_position
	var player_to_enemy := (global_position - player_pos).normalized()

	# Choose left or right flank based on current position
	var flank_side := 1.0 if randf() > 0.5 else -1.0
	var flank_direction := player_to_enemy.rotated(flank_angle * flank_side)

	_flank_target = player_pos + flank_direction * flank_distance
	_log_debug("Flank target: %s" % _flank_target)


## Check if there's a clear path (no obstacles) to the target position.
## Uses a raycast to check for walls/obstacles between current position and target.
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


## Find cover position closer to the flank target.
## Used during FLANKING state to move cover-to-cover toward the flank position.
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
func _check_wall_ahead(direction: Vector2) -> Vector2:
	if _wall_raycasts.is_empty():
		return Vector2.ZERO

	var avoidance := Vector2.ZERO
	var perpendicular := Vector2(-direction.y, direction.x)  # 90 degrees rotation

	# Check center, left, and right raycasts
	for i in range(WALL_CHECK_COUNT):
		var angle_offset := (i - 1) * 0.5  # -0.5, 0, 0.5 radians (~-28, 0, 28 degrees)
		var check_direction := direction.rotated(angle_offset)

		var raycast := _wall_raycasts[i]
		raycast.target_position = check_direction * WALL_CHECK_DISTANCE
		raycast.force_raycast_update()

		if raycast.is_colliding():
			# Calculate avoidance based on which raycast hit
			if i == 0:  # Left raycast hit
				avoidance += perpendicular  # Steer right
			elif i == 1:  # Center raycast hit
				avoidance += perpendicular if randf() > 0.5 else -perpendicular  # Random steer
			elif i == 2:  # Right raycast hit
				avoidance -= perpendicular  # Steer left

	return avoidance.normalized() if avoidance.length() > 0 else Vector2.ZERO


## Check if the player is visible using raycast.
## If detection_range is 0 or negative, uses unlimited detection range (line-of-sight only).
## This allows the enemy to see the player even outside the viewport if there's no obstacle.
## Also updates the continuous visibility timer and visibility ratio for lead prediction control.
func _check_player_visibility() -> void:
	var was_visible := _can_see_player
	_can_see_player = false
	_player_visibility_ratio = 0.0

	if _player == null or not _raycast:
		_continuous_visibility_timer = 0.0
		return

	var distance_to_player := global_position.distance_to(_player.global_position)

	# Check if player is within detection range (only if detection_range is positive)
	# If detection_range <= 0, detection is unlimited (line-of-sight only)
	if detection_range > 0 and distance_to_player > detection_range:
		_continuous_visibility_timer = 0.0
		return

	# Point raycast at player - use actual distance to player for the raycast length
	var direction_to_player := (_player.global_position - global_position).normalized()
	var raycast_length := distance_to_player + 10.0  # Add small buffer to ensure we reach player
	_raycast.target_position = direction_to_player * raycast_length
	_raycast.force_raycast_update()

	# Check if raycast hit something
	if _raycast.is_colliding():
		var collider := _raycast.get_collider()
		# If we hit the player, we can see them
		if collider == _player:
			_can_see_player = true
		# If we hit a wall/obstacle before the player, we can't see them
	else:
		# No collision between us and player - we have clear line of sight
		_can_see_player = true

	# Update continuous visibility timer and visibility ratio
	if _can_see_player:
		_continuous_visibility_timer += get_physics_process_delta_time()
		# Calculate what fraction of the player's body is visible
		# This is used to determine if lead prediction should be enabled
		_player_visibility_ratio = _calculate_player_visibility_ratio()
	else:
		# Lost line of sight - reset the timer and visibility ratio
		_continuous_visibility_timer = 0.0
		_player_visibility_ratio = 0.0


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


## Shoot a bullet towards the player.
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

	var direction := (target_position - global_position).normalized()

	# Create bullet instance
	var bullet := bullet_scene.instantiate()

	# Set bullet position with offset in shoot direction
	bullet.global_position = global_position + direction * bullet_spawn_offset

	# Set bullet direction
	bullet.direction = direction

	# Set shooter ID to identify this enemy as the source
	# This prevents enemies from detecting their own bullets in the threat sphere
	bullet.shooter_id = get_instance_id()

	# Add bullet to the scene tree
	get_tree().current_scene.add_child(bullet)

	# Play shooting sound
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_m16_shot"):
		audio_manager.play_m16_shot(global_position)

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


## Calculate lead prediction - aims where the player will be, not where they are.
## Uses iterative approach for better accuracy with moving targets.
## Only applies lead prediction if:
## 1. The player has been continuously visible for at least lead_prediction_delay seconds
## 2. At least lead_prediction_visibility_threshold of the player's body is visible
## 3. The predicted position is also visible to the enemy (not behind cover)
## This prevents enemies from "knowing" where the player will emerge from cover.
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


## Process patrol behavior - move between patrol points.
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
		# Reached patrol point, start waiting
		_is_waiting_at_patrol_point = true
		velocity = Vector2.ZERO
	else:
		# Check for walls and apply avoidance
		var avoidance := _check_wall_ahead(direction)
		if avoidance != Vector2.ZERO:
			# Blend movement direction with avoidance
			direction = (direction * 0.5 + avoidance * 0.5).normalized()

		velocity = direction * move_speed
		# Face movement direction when patrolling
		rotation = direction.angle()


## Process guard behavior - stand still and look around.
func _process_guard(_delta: float) -> void:
	velocity = Vector2.ZERO
	# In guard mode, enemy doesn't move but can still aim at player when visible


## Called when a bullet enters the threat sphere.
func _on_threat_area_entered(area: Area2D) -> void:
	# Check if bullet has shooter_id property and if it's from this enemy
	# This prevents enemies from being suppressed by their own bullets
	if "shooter_id" in area and area.shooter_id == get_instance_id():
		return  # Ignore own bullets

	_bullets_in_threat_sphere.append(area)
	# Set threat memory timer so enemy can react even after fast bullets exit
	# This allows the reaction delay to complete even if bullets pass through quickly
	_threat_memory_timer = THREAT_MEMORY_DURATION
	# Note: _under_fire is now set in _update_suppression after threat_reaction_delay
	# This gives the player more time before the enemy reacts to nearby gunfire
	_log_debug("Bullet entered threat sphere, starting reaction delay...")


## Called when a bullet exits the threat sphere.
func _on_threat_area_exited(area: Area2D) -> void:
	_bullets_in_threat_sphere.erase(area)


## Called when the enemy is hit (by bullet.gd).
func on_hit() -> void:
	if not _is_alive:
		return

	hit.emit()

	# Track hits for retreat behavior
	_hits_taken_in_encounter += 1
	_log_debug("Hit taken! Total hits in encounter: %d" % _hits_taken_in_encounter)
	_log_to_file("Hit taken, health: %d/%d" % [_current_health - 1, _max_health])

	# Show hit flash effect
	_show_hit_flash()

	# Apply damage
	_current_health -= 1

	# Play appropriate hit sound
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if _current_health <= 0:
		# Play lethal hit sound
		if audio_manager and audio_manager.has_method("play_hit_lethal"):
			audio_manager.play_hit_lethal(global_position)
		_on_death()
	else:
		# Play non-lethal hit sound
		if audio_manager and audio_manager.has_method("play_hit_non_lethal"):
			audio_manager.play_hit_non_lethal(global_position)
		_update_health_visual()


## Shows a brief flash effect when hit.
func _show_hit_flash() -> void:
	if not _sprite:
		return

	_sprite.modulate = hit_flash_color

	await get_tree().create_timer(hit_flash_duration).timeout

	# Restore color based on current health (if still alive)
	if _is_alive:
		_update_health_visual()


## Updates the sprite color based on current health percentage.
func _update_health_visual() -> void:
	if not _sprite:
		return

	# Interpolate color based on health percentage
	var health_percent := _get_health_percent()
	_sprite.modulate = full_health_color.lerp(low_health_color, 1.0 - health_percent)


## Returns the current health as a percentage (0.0 to 1.0).
func _get_health_percent() -> float:
	if _max_health <= 0:
		return 0.0
	return float(_current_health) / float(_max_health)


## Called when the enemy dies.
func _on_death() -> void:
	_is_alive = false
	_log_to_file("Enemy died")
	died.emit()

	if destroy_on_death:
		await get_tree().create_timer(respawn_delay).timeout
		queue_free()
	else:
		await get_tree().create_timer(respawn_delay).timeout
		_reset()


## Resets the enemy to its initial state.
func _reset() -> void:
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
	# Reset pursuit state variables
	_pursuit_cover_wait_timer = 0.0
	_pursuit_next_cover = Vector2.ZERO
	_has_pursuit_cover = false
	# Reset assault state variables
	_assault_wait_timer = 0.0
	_assault_ready = false
	_in_assault = false
	# Reset flank state variables
	_flank_cover_wait_timer = 0.0
	_flank_next_cover = Vector2.ZERO
	_has_flank_cover = false
	_initialize_health()
	_initialize_ammo()
	_update_health_visual()
	_initialize_goap_state()


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
		if _has_valid_cover and not _has_pursuit_cover:
			var time_left := PURSUIT_COVER_WAIT_DURATION - _pursuit_cover_wait_timer
			state_text += "\n(WAIT %.1fs)" % time_left
		elif _has_pursuit_cover:
			state_text += "\n(MOVING)"

	# Add flanking phase info if flanking
	if _current_state == AIState.FLANKING:
		if _has_valid_cover and not _has_flank_cover:
			var time_left := FLANK_COVER_WAIT_DURATION - _flank_cover_wait_timer
			state_text += "\n(WAIT %.1fs)" % time_left
		elif _has_flank_cover:
			state_text += "\n(MOVING)"
		else:
			state_text += "\n(DIRECT)"

	_debug_label.text = state_text


## Get current AI state (for external access/debugging).
func get_current_state() -> AIState:
	return _current_state


## Get GOAP world state (for GOAP planner).
func get_goap_world_state() -> Dictionary:
	return _goap_world_state.duplicate()


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

	# Draw line to player if visible
	if _can_see_player and _player:
		var to_player := _player.global_position - global_position
		draw_line(Vector2.ZERO, to_player, color_to_player, 1.5)

		# Draw bullet spawn point and check if blocked
		var direction_to_player := to_player.normalized()
		var spawn_point := direction_to_player * bullet_spawn_offset
		if _is_bullet_spawn_clear(direction_to_player):
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
