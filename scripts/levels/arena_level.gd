extends Node2D
## Arena Mode level — endless wave survival.
##
## Features:
## - Wave-based enemy spawning: each wave spawns more enemies with increasing
##   health, varied weapon types, and mix of GUARD/PATROL behaviors.
## - Pickups spawn between waves at fixed spawn points:
##     Health pack   — restores 1 HP to the player (green)
##     Ammo pack     — adds 2 magazines worth of ammo to the active weapon (yellow)
##     Weapon pickup — swaps the player's weapon for a random unlocked weapon (cyan)
## - Score shown immediately on player death (no exit zone needed).
## - Wave counter, enemy counter, and pickup labels in the UI.
## - Quick restart with Q key (via GameManager).
##
## Issue #1063.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Duration of saturation effect in seconds (on kill).
const SATURATION_DURATION: float = 0.15

## Saturation effect intensity (alpha).
const SATURATION_INTENSITY: float = 0.25

## Seconds to wait between waves (pickup window).
const INTER_WAVE_DELAY: float = 30.0

## Seconds before the first wave starts.
const FIRST_WAVE_DELAY: float = 2.0

## Base number of enemies in wave 1. Each wave adds ENEMIES_PER_WAVE_INCREMENT.
const BASE_ENEMIES_PER_WAVE: int = 3

## Additional enemies added per wave.
const ENEMIES_PER_WAVE_INCREMENT: int = 2

## Maximum enemies that can be active on the map at once.
const MAX_CONCURRENT_ENEMIES: int = 12

## How long pickups persist before auto-despawn.
## Set to match INTER_WAVE_DELAY so pickups survive the full between-wave window.
const PICKUP_LIFETIME: float = 60.0

## Radius around pickup spawn points within which pickups are placed randomly.
const PICKUP_SPAWN_SCATTER: float = 30.0

## Number of health pickups to spawn between waves.
const HEALTH_PICKUPS_PER_WAVE: int = 4

## Number of ammo pickups to spawn between waves.
const AMMO_PICKUPS_PER_WAVE: int = 4

## Number of grenade pickups to spawn between waves (F-1 grenades).
const GRENADE_PICKUPS_PER_WAVE: int = 2

## Whether a weapon pickup spawns between waves (every other wave).
const WEAPON_PICKUP_WAVE_INTERVAL: int = 2

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

## Reference to the player node.
var _player: Node2D = null

## Current wave number (1-indexed).
var _wave_number: int = 0

## Total enemies target for the current wave.
var _wave_enemy_target: int = 0

## Enemies still alive in the current wave.
var _enemies_alive: int = 0

## Total enemies spawned so far in the current wave.
var _enemies_spawned: int = 0

## Whether a wave is currently active.
var _wave_in_progress: bool = false

## Whether the level is active (false after player death).
var _level_active: bool = true

## Whether the score screen has been shown.
var _score_shown: bool = false

## All enemies currently tracked in the scene.
var _enemies: Array = []

## Active pickup nodes (health, ammo, weapon).
var _pickups: Array = []

## Spawn points for enemies (Vector2 positions).
var _enemy_spawn_points: Array[Vector2] = []

## Spawn points for pickups (Vector2 positions).
var _pickup_spawn_points: Array[Vector2] = []

## Timer for inter-wave delay.
var _wave_timer: float = 0.0

## Whether waiting between waves.
var _between_waves: bool = false

## Countdown timer label shown between waves.
var _wave_countdown_label: Label = null

## Reference to the enemy count label.
var _enemy_count_label: Label = null

## Reference to the wave label.
var _wave_label: Label = null

## Reference to the ammo count label.
var _ammo_label: Label = null

## Reference to the difficulty label.
var _difficulty_label: Label = null

## Reference to the magazines label.
var _magazines_label: Label = null

## Reference to the ColorRect for saturation effect.
var _saturation_overlay: ColorRect = null

## Reference to the combo label.
var _combo_label: Label = null

## Reference to the health label.
var _health_label: Label = null

## Cached reference to the ReplayManager autoload.
var _replay_manager: Node = null

## Enemy scene reference.
var _enemy_scene: PackedScene = null

# ---------------------------------------------------------------------------
# Ready / Process
# ---------------------------------------------------------------------------

func _get_or_create_replay_manager() -> Node:
	if _replay_manager != null and is_instance_valid(_replay_manager):
		return _replay_manager
	_replay_manager = get_node_or_null("/root/ReplayManager")
	if _replay_manager != null:
		if _replay_manager.has_method("StartRecording"):
			_log_to_file("ReplayManager found as C# autoload - verified OK")
		else:
			_log_to_file("WARNING: ReplayManager exists but has no StartRecording method")
	else:
		_log_to_file("ERROR: ReplayManager autoload not found")
	return _replay_manager


func _ready() -> void:
	print("[ArenaLevel] Arena Mode loaded — survive as many waves as you can!")
	print("[ArenaLevel] Press Q to restart.")

	# Pre-load the enemy scene for runtime instantiation.
	_enemy_scene = load("res://scenes/objects/Enemy.tscn")
	if _enemy_scene == null:
		push_error("[ArenaLevel] Could not load Enemy.tscn!")

	# Setup navigation mesh.
	_setup_navigation()

	# Find and setup player.
	_setup_player_tracking()

	# Restrict camera so the border walls are never visible (Issue #1682).
	_configure_camera()

	# Setup UI.
	_setup_ui()

	# Setup saturation overlay.
	_setup_saturation_overlay()

	# Define spawn zones.
	_setup_spawn_points()

	# Connect GameManager signals.
	if GameManager:
		GameManager.enemy_killed.connect(_on_game_manager_enemy_killed)
		GameManager.stats_updated.connect(_update_debug_ui)

	# Initialize ScoreManager — use 0 as "total enemies" (arena is endless).
	_initialize_score_manager()

	# Start replay recording.
	_start_replay_recording()

	# Begin the first wave after a short delay.
	_wave_timer = FIRST_WAVE_DELAY
	_between_waves = true
	_wave_countdown_label.text = "Волна начинается через %d..." % int(_wave_timer)


func _process(delta: float) -> void:
	if not _level_active:
		return

	# Update countdown/inter-wave timer.
	if _between_waves:
		_wave_timer -= delta
		if _wave_timer <= 0.0:
			_between_waves = false
			_start_wave()
		else:
			if _wave_countdown_label:
				_wave_countdown_label.text = "Волна %d начинается через %d..." % [
					_wave_number + 1,
					int(ceil(_wave_timer))
				]
		return

	# Update ScoreManager enemy positions.
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager and score_manager.has_method("update_enemy_positions"):
		score_manager.update_enemy_positions(_enemies)

# ---------------------------------------------------------------------------
# Wave Management
# ---------------------------------------------------------------------------

## Start the next wave.
func _start_wave() -> void:
	_wave_number += 1
	_wave_enemy_target = BASE_ENEMIES_PER_WAVE + (_wave_number - 1) * ENEMIES_PER_WAVE_INCREMENT
	_enemies_alive = 0
	_enemies_spawned = 0
	_wave_in_progress = true

	if _wave_countdown_label:
		_wave_countdown_label.text = ""

	_update_wave_label()
	_update_enemy_count_label()

	print("[ArenaLevel] Wave %d started — spawning %d enemies" % [_wave_number, _wave_enemy_target])
	_log_to_file("Wave %d started: %d enemies" % [_wave_number, _wave_enemy_target])

	# Spawn enemies in batches (respect MAX_CONCURRENT_ENEMIES).
	_spawn_wave_enemies()


## Spawn all enemies for the current wave, respecting the concurrent cap.
func _spawn_wave_enemies() -> void:
	var to_spawn: int = mini(_wave_enemy_target, MAX_CONCURRENT_ENEMIES)
	for i in range(to_spawn):
		_spawn_enemy()


## Called when an enemy dies during a wave.
func _on_enemy_died() -> void:
	# Guard: only process enemy deaths while a wave is in progress.
	# Without this guard, enemies that die during the inter-wave cooldown (or
	# from previous waves whose signals are still connected) would decrement
	# _enemies_alive below zero and trigger _end_wave() multiple times, which
	# caused _spawn_wave_pickups() to be called 7+ times per wave.
	if not _wave_in_progress:
		return

	_enemies_alive -= 1
	_update_enemy_count_label()

	# If more enemies still need to be spawned, spawn the next one.
	if _enemies_spawned < _wave_enemy_target:
		_spawn_enemy()

	# Check if wave is complete.
	if _enemies_alive <= 0 and _enemies_spawned >= _wave_enemy_target:
		_end_wave()


## Called when an enemy dies with special kill info.
func _on_enemy_died_with_info(is_ricochet_kill: bool, is_penetration_kill: bool, is_player_kill: bool = true) -> void:
	# Register kill with GameManager (Issue #1196: pass player kill flag to count only player kills).
	if GameManager:
		GameManager.register_kill(is_player_kill, is_penetration_kill)
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager and score_manager.has_method("register_kill"):
		score_manager.register_kill(is_ricochet_kill, is_penetration_kill)


## End the current wave and begin the inter-wave cooldown.
func _end_wave() -> void:
	_wave_in_progress = false
	print("[ArenaLevel] Wave %d complete!" % _wave_number)
	_log_to_file("Wave %d complete" % _wave_number)

	# Clear dead enemies from tracking.
	_enemies = _enemies.filter(func(e): return is_instance_valid(e) and e.has_method("is_alive") and e.is_alive())

	# Spawn pickups.
	_spawn_wave_pickups()

	# Start cooldown before next wave.
	_wave_timer = INTER_WAVE_DELAY
	_between_waves = true

	if _wave_countdown_label:
		_wave_countdown_label.text = "Волна %d начинается через %d..." % [
			_wave_number + 1,
			int(INTER_WAVE_DELAY)
		]

# ---------------------------------------------------------------------------
# Enemy Spawning
# ---------------------------------------------------------------------------

## Spawn a single enemy at a random spawn point.
func _spawn_enemy() -> void:
	if _enemy_scene == null:
		return

	var enemy: Node2D = _enemy_scene.instantiate()

	# Choose a random spawn point.
	var spawn_pos: Vector2 = _pick_random_enemy_spawn()
	enemy.global_position = spawn_pos

	# Scale difficulty with wave number.
	_configure_enemy_for_wave(enemy, _wave_number)

	# Arena enemies must be destroyed on death, not respawned.
	# Enemy.gd exports destroy_on_death (default false) — when false, enemies
	# respawn after respawn_delay seconds via _reset(). Setting it to true
	# ensures they are permanently removed once killed.
	enemy.set("destroy_on_death", true)

	# Add to scene.
	var entities := get_node_or_null("Entities/Enemies")
	if entities:
		entities.add_child(enemy)
	else:
		add_child(enemy)

	# Connect signals.
	if enemy.has_signal("died"):
		enemy.died.connect(_on_enemy_died)
	if enemy.has_signal("died_with_info"):
		enemy.died_with_info.connect(_on_enemy_died_with_info)
	if enemy.has_signal("hit"):
		enemy.hit.connect(_on_enemy_hit)

	_enemies.append(enemy)
	_enemies_spawned += 1
	_enemies_alive += 1
	_update_enemy_count_label()

	# Force enemy into SEARCHING state immediately after spawn so it actively
	# hunts the player instead of standing idle staring at the wall.
	# Use call_deferred so the enemy's _ready() runs first and all components
	# are initialized before we transition state.
	if _player != null and is_instance_valid(_player):
		var search_center: Vector2 = _player.global_position
		enemy.call_deferred("_transition_to_searching", search_center)


## Configure enemy properties based on wave number.
## Difficulty scaling:
##   Wave 1:   1HP, RIFLE (slow shoot 0.5s cooldown = PM-like pistol)
##   Wave 2-3: 1-2HP, RIFLE (normal 0.1s cooldown), no cover/flanking
##   Wave 4-5: 2-3HP, RIFLE + SHOTGUN mix, cover enabled
##   Wave 6+:  3+HP, RIFLE / SHOTGUN / UZI mix, cover + flanking
func _configure_enemy_for_wave(enemy: Node, wave: int) -> void:
	var weapon_roll: float = randf()

	if wave == 1:
		# Wave 1: weakest enemies — 1HP, Makarov PM pistol.
		enemy.set("weapon_type", 5)  # PM (Makarov pistol, added in Issue #583)
		enemy.set("min_health", 1)
		enemy.set("max_health", 1)
		enemy.set("enable_cover", false)
		enemy.set("enable_flanking", false)
		enemy.set("behavior_mode", 0)  # GUARD
	elif wave <= 3:
		# Wave 2-3: normal rifle speed, still low HP, no tactics.
		enemy.set("weapon_type", 0)  # RIFLE
		enemy.set("shoot_cooldown", 0.1)
		enemy.set("min_health", 1)
		enemy.set("max_health", 2)
		enemy.set("enable_cover", false)
		enemy.set("enable_flanking", false)
		enemy.set("behavior_mode", 0)  # GUARD
	elif wave <= 5:
		# Wave 4-5: rifle + shotgun mix, cover enabled, medium HP.
		if weapon_roll < 0.6:
			enemy.set("weapon_type", 0)  # RIFLE
		else:
			enemy.set("weapon_type", 1)  # SHOTGUN
		enemy.set("shoot_cooldown", 0.1)
		enemy.set("min_health", 2)
		enemy.set("max_health", 3)
		enemy.set("enable_cover", true)
		enemy.set("enable_flanking", false)
		var behavior_roll: float = randf()
		if behavior_roll < 0.25:
			enemy.set("behavior_mode", 1)  # PATROL
		else:
			enemy.set("behavior_mode", 0)  # GUARD
	else:
		# Wave 6+: full mix, cover + flanking, scaling HP.
		if weapon_roll < 0.4:
			enemy.set("weapon_type", 0)  # RIFLE
		elif weapon_roll < 0.7:
			enemy.set("weapon_type", 2)  # UZI
		else:
			enemy.set("weapon_type", 1)  # SHOTGUN
		enemy.set("shoot_cooldown", 0.1)
		var extra_hp: int = (wave - 5) / 2  # +1HP every 2 waves beyond wave 5
		enemy.set("min_health", 2 + extra_hp)
		enemy.set("max_health", 4 + extra_hp)
		enemy.set("enable_cover", true)
		enemy.set("enable_flanking", true)
		var behavior_roll: float = randf()
		if behavior_roll < 0.35:
			enemy.set("behavior_mode", 1)  # PATROL
		else:
			enemy.set("behavior_mode", 0)  # GUARD


## Return a random enemy spawn position distributed along the arena walls.
## Picks randomly from the top half of spawn points sorted by distance from player,
## so enemies spread out rather than all clustering at the single farthest corner.
func _pick_random_enemy_spawn() -> Vector2:
	if _enemy_spawn_points.is_empty():
		return Vector2(960, 540)

	if _player != null and is_instance_valid(_player):
		var player_pos: Vector2 = _player.global_position
		# Sort spawn points by distance from player (farthest first).
		var sorted: Array = _enemy_spawn_points.duplicate()
		sorted.sort_custom(func(a, b): return a.distance_to(player_pos) > b.distance_to(player_pos))
		# Pick randomly from the farthest half to distribute around walls.
		var pool_size: int = max(1, sorted.size() / 2)
		var chosen: Vector2 = sorted[randi() % pool_size]
		return chosen + Vector2(randf_range(-40, 40), randf_range(-40, 40))

	return _enemy_spawn_points[randi() % _enemy_spawn_points.size()]

# ---------------------------------------------------------------------------
# Pickup Spawning
# ---------------------------------------------------------------------------

## Spawn pickups after a wave ends.
func _spawn_wave_pickups() -> void:
	# Clear any expired pickups.
	_pickups = _pickups.filter(func(p): return is_instance_valid(p))

	# Spawn health pickups.
	for i in range(HEALTH_PICKUPS_PER_WAVE):
		_spawn_pickup("health")

	# Spawn ammo pickups.
	for i in range(AMMO_PICKUPS_PER_WAVE):
		_spawn_pickup("ammo")

	# Spawn grenade pickups.
	for i in range(GRENADE_PICKUPS_PER_WAVE):
		_spawn_pickup("grenade")

	# Spawn weapon pickup every WEAPON_PICKUP_WAVE_INTERVAL waves.
	if _wave_number % WEAPON_PICKUP_WAVE_INTERVAL == 0:
		_spawn_pickup("weapon")

	# Spawn active item charge pickup if the player has a charge-based active item.
	_maybe_spawn_active_item_charge_pickup()

	_log_to_file("Spawned pickups for wave %d" % _wave_number)
	print("[ArenaLevel] Spawned pickups for wave %d" % _wave_number)


## Spawn active item charge pickups — always 1 per wave regardless of active item type.
## They spawn rarer than health packs (1 vs 4 per wave) so the player has
## a meaningful but not overwhelming supply of charges.
## ActiveItemType.NONE = 0 — skip if no active item is equipped.
func _maybe_spawn_active_item_charge_pickup() -> void:
	if ActiveItemManager == null:
		return
	var item_type: int = ActiveItemManager.current_active_item
	if item_type == 0:
		# No active item equipped; skip.
		return
	_spawn_pickup("active_item_charge")


## Create and place a pickup of the given type.
## @param pickup_type: "health", "ammo", "weapon", "grenade", or "active_item_charge"
func _spawn_pickup(pickup_type: String) -> void:
	if _pickup_spawn_points.is_empty():
		return

	# Pick a random pickup spawn point with scatter.
	var base_pos: Vector2 = _pickup_spawn_points[randi() % _pickup_spawn_points.size()]
	var pos: Vector2 = base_pos + Vector2(
		randf_range(-PICKUP_SPAWN_SCATTER, PICKUP_SPAWN_SCATTER),
		randf_range(-PICKUP_SPAWN_SCATTER, PICKUP_SPAWN_SCATTER)
	)

	# Build the pickup node.
	# collision_layer=0 (pickups do not need to be detected by others),
	# collision_mask=1 so the Area2D detects the player's CharacterBody2D (layer 1).
	# NOTE: global_position must be set AFTER add_child() in Godot 4; we use
	# position (local) here since the root node's transform is identity.
	var pickup := Area2D.new()
	pickup.name = "Pickup_%s_%d" % [pickup_type, randi()]
	pickup.collision_layer = 0
	pickup.collision_mask = 1  # Detect player CharacterBody2D (layer 1)
	pickup.monitoring = true
	pickup.monitorable = false
	pickup.position = pos  # Use local position (identity parent transform = same as global)

	# Add collision shape.
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 28.0
	col.shape = shape
	pickup.add_child(col)

	# Add visual rectangle.
	var visual := ColorRect.new()
	visual.size = Vector2(28, 28)
	visual.position = Vector2(-14, -14)
	match pickup_type:
		"health":
			visual.color = Color(0.1, 0.9, 0.2, 0.85)
		"ammo":
			visual.color = Color(0.95, 0.85, 0.1, 0.85)
		"weapon":
			visual.color = Color(0.1, 0.8, 0.95, 0.85)
		"grenade":
			visual.color = Color(0.9, 0.3, 0.1, 0.85)
		"active_item_charge":
			visual.color = Color(0.8, 0.2, 0.9, 0.85)
	pickup.add_child(visual)

	# Add label.
	var lbl := Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size = Vector2(50, 20)
	lbl.position = Vector2(-25, -28)
	lbl.add_theme_font_size_override("font_size", 11)
	match pickup_type:
		"health":
			lbl.text = "+HP"
			lbl.add_theme_color_override("font_color", Color(0.1, 1.0, 0.2, 1.0))
		"ammo":
			lbl.text = "+AMM"
			lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.1, 1.0))
		"weapon":
			lbl.text = "+WPN"
			lbl.add_theme_color_override("font_color", Color(0.1, 0.9, 1.0, 1.0))
		"grenade":
			lbl.text = "+GRN"
			lbl.add_theme_color_override("font_color", Color(1.0, 0.5, 0.1, 1.0))
		"active_item_charge":
			lbl.text = "+CHG"
			lbl.add_theme_color_override("font_color", Color(0.9, 0.4, 1.0, 1.0))
	pickup.add_child(lbl)

	# Store the type for use in the signal callback.
	pickup.set_meta("pickup_type", pickup_type)

	# Connect signal — use body_entered so CharacterBody2D (player) triggers it.
	pickup.body_entered.connect(_on_pickup_body_entered.bind(pickup))

	# Add to scene root (not Environment) so the Area2D's global_position is
	# unaffected by any parent transform and physics works correctly.
	add_child(pickup)

	_pickups.append(pickup)

	# Auto-despawn after PICKUP_LIFETIME seconds.
	var timer := get_tree().create_timer(PICKUP_LIFETIME)
	timer.timeout.connect(func():
		if is_instance_valid(pickup):
			pickup.queue_free()
	)


## Called when a body enters a pickup area.
## NOTE: body_entered emits (body) as first arg; .bind(pickup) appends pickup as
## the SECOND argument. So the correct signature is (body, pickup), not (pickup, body).
func _on_pickup_body_entered(body: Node2D, pickup: Area2D) -> void:
	# Only the player should collect pickups.
	# The C# Player is a CharacterBody2D named "Player" and is in group "player".
	if body.name != "Player" and not body.is_in_group("player"):
		return

	if not is_instance_valid(pickup):
		return

	var pickup_type: String = pickup.get_meta("pickup_type", "")
	print("[ArenaLevel] Pickup collected: %s by %s" % [pickup_type, body.name])
	_log_to_file("Pickup collected: %s by %s" % [pickup_type, body.name])
	match pickup_type:
		"health":
			_apply_health_pickup(body)
		"ammo":
			_apply_ammo_pickup(body)
		"weapon":
			_apply_weapon_pickup(body)
		"grenade":
			_apply_grenade_pickup(body)
		"active_item_charge":
			_apply_active_item_charge_pickup(body)

	pickup.queue_free()
	_pickups = _pickups.filter(func(p): return is_instance_valid(p))


## Restore 1 HP to the player via HealthComponent.Heal().
func _apply_health_pickup(player: Node2D) -> void:
	# C# Player exposes Heal() via BaseCharacter.
	if player.has_method("Heal"):
		player.Heal(1.0)
		print("[ArenaLevel] Health pickup collected: +1 HP")
		_log_to_file("Health pickup collected")
	elif player.has_method("heal"):
		player.heal(1.0)
	else:
		# Fallback: directly access HealthComponent child.
		var hc := player.get_node_or_null("HealthComponent")
		if hc and hc.has_method("Heal"):
			hc.Heal(1.0)
			print("[ArenaLevel] Health pickup applied via HealthComponent")


## Add ammo to the player's active weapon.
## For AK+GL (AKGL): also restores the underbarrel grenade launcher round.
func _apply_ammo_pickup(player: Node2D) -> void:
	# Find the active weapon on the player.
	var weapon := _find_player_weapon(player)
	if weapon == null:
		print("[ArenaLevel] Ammo pickup: no weapon found on player")
		_log_to_file("Ammo pickup: no weapon found on player")
		return

	# Add 2 magazines worth of ammo.
	if weapon.has_method("AddAmmo"):
		var mag_size: int = weapon.get("MagazineSize") if weapon.get("MagazineSize") != null else 30
		if mag_size <= 0:
			mag_size = 30
		weapon.AddAmmo(mag_size * 2)
		print("[ArenaLevel] Ammo pickup collected: +%d rounds" % (mag_size * 2))
		_log_to_file("Ammo pickup collected: +%d" % (mag_size * 2))
	else:
		push_warning("[ArenaLevel] Ammo pickup: weapon has no AddAmmo method")

	# For AK+GL: ammo pickup also restores the underbarrel grenade launcher.
	# The launcher holds 1 VOG-25 grenade; picking up ammo replenishes it.
	if weapon.name == "AKGL" and weapon.get("GrenadeAvailable") == false:
		weapon.set("GrenadeAvailable", true)
		print("[ArenaLevel] Ammo pickup: AKGL grenade launcher restored")
		_log_to_file("Ammo pickup: AKGL grenade launcher restored")


## Add grenades to the player (F-1 frag grenades for throwing).
func _apply_grenade_pickup(player: Node2D) -> void:
	# C# Player exposes AddGrenades(int) for programmatic grenade refills.
	if player.has_method("AddGrenades"):
		player.AddGrenades(1)
		print("[ArenaLevel] Grenade pickup collected: +1 grenade")
		_log_to_file("Grenade pickup collected: +1")
	elif player.has_method("add_grenades"):
		player.add_grenades(1)
	else:
		push_warning("[ArenaLevel] Grenade pickup: player has no AddGrenades method")


## Restore one charge to the player's current active item (charge-based items only).
func _apply_active_item_charge_pickup(player: Node2D) -> void:
	if ActiveItemManager == null:
		return
	var item_type: int = ActiveItemManager.current_active_item

	match item_type:
		2:  # HOMING_BULLETS — restore via player field
			var current: int = player.get("_homingCharges") if player.get("_homingCharges") != null else 0
			var max_val: int = player.get("MaxHomingCharges") if player.get("MaxHomingCharges") != null else 2
			if current < max_val:
				player.set("_homingCharges", min(current + 1, max_val))
				print("[ArenaLevel] Active item charge pickup: homing +1")
				_log_to_file("Active item charge pickup: homing +1")
		3:  # TELEPORT_BRACERS
			var current: int = player.get("_teleportCharges") if player.get("_teleportCharges") != null else 0
			var max_val: int = player.get("MaxTeleportCharges") if player.get("MaxTeleportCharges") != null else 6
			if current < max_val:
				player.set("_teleportCharges", min(current + 1, max_val))
				print("[ArenaLevel] Active item charge pickup: teleport +1")
				_log_to_file("Active item charge pickup: teleport +1")
		5:  # INVISIBILITY_SUIT — managed by the effect node
			var effect := player.get_node_or_null("InvisibilitySuitEffect")
			if effect and effect.has_method("add_charge"):
				effect.add_charge(1)
				print("[ArenaLevel] Active item charge pickup: invisibility +1")
				_log_to_file("Active item charge pickup: invisibility +1")
		8:  # TRAJECTORY_GLASSES
			var effect := player.get_node_or_null("TrajectoryGlassesEffect")
			if effect and effect.has_method("add_charge"):
				effect.add_charge(1)
				print("[ArenaLevel] Active item charge pickup: trajectory +1")
				_log_to_file("Active item charge pickup: trajectory +1")
		10: # LOUDSPEAKER — charges managed via LoudspeakerProgress node
			var loudspeaker_progress := player.get_node_or_null("LoudspeakerProgress")
			if loudspeaker_progress:
				var current: int = loudspeaker_progress.get("charges_remaining") if loudspeaker_progress.get("charges_remaining") != null else 0
				var max_val: int = loudspeaker_progress.call("get_max_charges") if loudspeaker_progress.has_method("get_max_charges") else 2
				if max_val > 0 and current < max_val:
					loudspeaker_progress.set("charges_remaining", min(current + 1, max_val))
					print("[ArenaLevel] Active item charge pickup: loudspeaker +1")
					_log_to_file("Active item charge pickup: loudspeaker +1")
		11: # BREACHING_CHARGES — restore via player field
			var current: int = player.get("_breachingChargesRemaining") if player.get("_breachingChargesRemaining") != null else 0
			var max_val: int = 2
			if current < max_val:
				player.set("_breachingChargesRemaining", min(current + 1, max_val))
				print("[ArenaLevel] Active item charge pickup: breaching charges +1")
				_log_to_file("Active item charge pickup: breaching charges +1")
		_:
			print("[ArenaLevel] Active item charge pickup: item %d has no charge system" % item_type)


## Swap the player's weapon for a random unlocked weapon.
func _apply_weapon_pickup(player: Node2D) -> void:
	if GameManager == null:
		return

	# Gather unlocked weapon IDs (excluding current).
	var current_weapon_id: String = GameManager.get_selected_weapon()
	var available: Array = []
	for weapon_id in GameManager.WEAPON_SCENES.keys():
		if weapon_id != current_weapon_id and GameManager.is_weapon_unlocked(weapon_id):
			available.append(weapon_id)

	if available.is_empty():
		print("[ArenaLevel] Weapon pickup: no other weapons available")
		return

	var new_weapon_id: String = available[randi() % available.size()]
	GameManager.set_selected_weapon(new_weapon_id)

	# Equip the new weapon on the C# player.
	if player.has_method("ApplySelectedWeaponFromGameManager"):
		player.ApplySelectedWeaponFromGameManager()
	else:
		# Fallback: reconnect signals for the new weapon.
		_reconnect_weapon_signals(player)

	print("[ArenaLevel] Weapon pickup collected: switched to %s" % new_weapon_id)
	_log_to_file("Weapon pickup collected: %s" % new_weapon_id)


## Find the currently active weapon node on the player.
## Prefers the C# Player's CurrentWeapon property to avoid returning a stale
## first weapon when the player has been equipped with a different weapon since
## construction (e.g. after ApplySelectedWeaponFromGameManager replaced MakarovPM
## with AKGL — searching by name would still find any renamed duplicate "AKGL2").
func _find_player_weapon(player: Node2D) -> Node:
	# Primary: use the C# Player.CurrentWeapon property (always the active weapon).
	var current := player.get("CurrentWeapon")
	if current != null and is_instance_valid(current):
		return current

	# Fallback: search child nodes by known weapon names.
	var weapon_names: Array[String] = [
		"AssaultRifle", "Shotgun", "MiniUzi", "SilencedPistol",
		"SniperRifle", "AKGL", "Revolver", "MakarovPM"
	]
	for wname in weapon_names:
		var w := player.get_node_or_null(wname)
		if w != null:
			return w
	return null


## Re-connect weapon ammo/fire signals after a weapon swap.
func _reconnect_weapon_signals(player: Node2D) -> void:
	# Use deferred reconnect so the new weapon node is fully initialized.
	call_deferred("_connect_weapon_signals_deferred")

# ---------------------------------------------------------------------------
# Setup Functions
# ---------------------------------------------------------------------------

## Bake NavigationRegion2D for enemy pathfinding.
## Clamps the camera so the outer border walls are never visible (Issue #1682).
##
## ArenaLevel map: 1920x1080 px playfield framed by 32 px walls.
##   WallTop    (960,   32), h=32  → bottom edge y=64   → limit_top    = 64
##   WallBottom (960, 1048), h=32  → top edge   y=1016  → limit_bottom = 1016
##   WallLeft   ( 32,  540), w=32  → right edge x=64    → limit_left   = 64
##   WallRight  (1888, 540), w=32  → left edge  x=1856  → limit_right  = 1856
func _configure_camera() -> void:
	if _player == null:
		return
	var camera: Camera2D = _player.get_node_or_null("Camera2D")
	if camera == null:
		push_warning("[ArenaLevel] Camera2D not found on player — cannot set camera limits")
		return
	const LIMIT_TOP: int    =   64   # WallTop bottom edge
	const LIMIT_BOTTOM: int = 1016   # WallBottom top edge
	const LIMIT_LEFT: int   =   64   # WallLeft right edge
	const LIMIT_RIGHT: int  = 1856   # WallRight left edge
	camera.limit_top    = LIMIT_TOP
	camera.limit_bottom = LIMIT_BOTTOM
	camera.limit_left   = LIMIT_LEFT
	camera.limit_right  = LIMIT_RIGHT
	_log_to_file("Camera2D limits set — top=%d bottom=%d left=%d right=%d — Issue #1682" % [
		LIMIT_TOP, LIMIT_BOTTOM, LIMIT_LEFT, LIMIT_RIGHT
	])


## Issue #1289: use explicit parse+bake API so all obstacle StaticBody2D nodes are
## reliably found and carved out of the walkable area (bake_navigation_polygon can
## miss dynamic/runtime geometry when called from _ready()).
func _setup_navigation() -> void:
	var nav_region: NavigationRegion2D = get_node_or_null("NavigationRegion2D")
	if nav_region == null:
		push_warning("[ArenaLevel] NavigationRegion2D not found")
		return
	var nav_poly: NavigationPolygon = nav_region.navigation_polygon
	if nav_poly == null:
		push_warning("[ArenaLevel] NavigationPolygon not found")
		return
	# Issue #1289: wait for physics frame so CollisionShape2D nodes are registered
	# with PhysicsServer2D before parsing source geometry for navmesh carving.
	await get_tree().physics_frame
	print("[ArenaLevel] Baking navigation mesh...")
	var source_geometry: NavigationMeshSourceGeometryData2D = NavigationMeshSourceGeometryData2D.new()
	NavigationServer2D.parse_source_geometry_data(nav_poly, source_geometry, self)
	NavigationServer2D.bake_from_source_geometry_data(nav_poly, source_geometry)
	# Issue #1289: push updated polygon back into the NavigationServer's live map.
	# Without this reassignment, agents still use the pre-bake (uncarved) navmesh.
	nav_region.navigation_polygon = nav_poly
	nav_region.emit_signal("bake_finished")
	print("[ArenaLevel] Navigation mesh baked")


## Setup player tracking and connect weapon signals.
func _setup_player_tracking() -> void:
	_player = get_node_or_null("Entities/Player")
	if _player == null:
		push_warning("[ArenaLevel] Player node not found at Entities/Player")
		return

	# Add realistic visibility component.
	_setup_realistic_visibility()

	# NOTE: Do NOT call _player.ApplySelectedWeaponFromGameManager() here.
	# The C# Player._Ready() already calls it, so a second call would create a
	# duplicate weapon node (e.g. "AKGL2") because Godot auto-renames nodes with
	# the same name. _find_player_weapon would then find the stale first node,
	# and AmmoChanged / Fired signals would be connected to the wrong weapon,
	# causing all counters (ammo, magazines) to never update for non-PM weapons.
	# See labyrinth_level.gd for the same fix (comment at line 1447).

	# Register player with GameManager.
	if GameManager:
		GameManager.set_player(_player)

	# Connect to player death signal.
	if _player.has_signal("Died"):
		_player.Died.connect(_on_player_died)
	elif _player.has_signal("died"):
		_player.died.connect(_on_player_died)

	# Connect health signals for real-time HP counter updates.
	# Using call_deferred so the C# HealthComponent is fully initialized.
	call_deferred("_connect_health_signals_deferred")

	# Connect weapon signals after a deferred frame so the C# Player has finished
	# its own _ready and ApplySelectedWeaponFromGameManager — otherwise we may
	# connect to the old default weapon node that gets replaced on the next frame.
	call_deferred("_connect_weapon_signals_deferred")

	print("[ArenaLevel] Player tracking setup complete")


## Connect player health signals for real-time HP label updates.
## The C# Healed and Damaged signals fire immediately when HP changes, so the
## arena HP counter updates without waiting for the next enemy count poll.
func _connect_health_signals_deferred() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if _player.has_signal("Healed"):
		if not _player.Healed.is_connected(_on_player_healed):
			_player.Healed.connect(_on_player_healed)
	if _player.has_signal("Damaged"):
		if not _player.Damaged.is_connected(_on_player_damaged):
			_player.Damaged.connect(_on_player_damaged)
	_update_health_label()
	print("[ArenaLevel] Health signals connected")


## Connect weapon signals after a deferred frame so the C# Player has finished
## its own _ready and swapped in the correct weapon node.
## This fixes the counters (ammo, magazines) not updating in arena mode.
func _connect_weapon_signals_deferred() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var weapon := _find_player_weapon(_player)
	if weapon == null:
		push_warning("[ArenaLevel] _connect_weapon_signals_deferred: no weapon found")
		return
	if weapon.has_signal("AmmoChanged"):
		if not weapon.AmmoChanged.is_connected(_on_weapon_ammo_changed):
			weapon.AmmoChanged.connect(_on_weapon_ammo_changed)
	if weapon.has_signal("MagazinesChanged"):
		if not weapon.MagazinesChanged.is_connected(_on_magazines_changed):
			weapon.MagazinesChanged.connect(_on_magazines_changed)
	if weapon.has_signal("Fired"):
		if not weapon.Fired.is_connected(_on_shot_fired):
			weapon.Fired.connect(_on_shot_fired)
	if weapon.has_signal("ShellCountChanged"):
		if not weapon.ShellCountChanged.is_connected(_on_shell_count_changed):
			weapon.ShellCountChanged.connect(_on_shell_count_changed)
	# Refresh initial display values.
	if weapon.get("CurrentAmmo") != null and weapon.get("ReserveAmmo") != null:
		_update_ammo_label_magazine(weapon.CurrentAmmo, weapon.ReserveAmmo)
	if weapon.has_method("GetMagazineAmmoCounts"):
		_update_magazines_label(weapon.GetMagazineAmmoCounts())
	_update_health_label()
	print("[ArenaLevel] Weapon signals connected: %s" % weapon.name)


## Add realistic visibility component to player.
func _setup_realistic_visibility() -> void:
	if _player == null:
		return
	var visibility_script = load("res://scripts/components/realistic_visibility_component.gd")
	if visibility_script == null:
		return
	var comp := Node.new()
	comp.name = "RealisticVisibilityComponent"
	comp.set_script(visibility_script)
	_player.add_child(comp)


## Initialize ScoreManager.
func _initialize_score_manager() -> void:
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager == null:
		return
	# Use 0 as total enemy count — arena is endless.
	score_manager.start_level(0)
	if _player:
		score_manager.set_player(_player)
	if not score_manager.combo_changed.is_connected(_on_combo_changed):
		score_manager.combo_changed.connect(_on_combo_changed)


## Start replay recording.
func _start_replay_recording() -> void:
	var replay_manager: Node = _get_or_create_replay_manager()
	if replay_manager == null:
		return
	if replay_manager.has_method("ClearReplay"):
		replay_manager.ClearReplay()
	if replay_manager.has_method("StartRecording"):
		replay_manager.StartRecording(self, _player, _enemies)
		print("[ArenaLevel] Replay recording started")


## Define enemy and pickup spawn points around the arena.
func _setup_spawn_points() -> void:
	# Arena is 1920x1080, walls at x=64/1856, y=64/1016.
	# Player starts near the center-left.
	# Enemy spawns: four sides.
	_enemy_spawn_points = [
		# Top side
		Vector2(400, 150),
		Vector2(800, 150),
		Vector2(1200, 150),
		Vector2(1600, 150),
		# Bottom side
		Vector2(400, 930),
		Vector2(800, 930),
		Vector2(1200, 930),
		Vector2(1600, 930),
		# Left side
		Vector2(160, 350),
		Vector2(160, 600),
		Vector2(160, 800),
		# Right side
		Vector2(1800, 350),
		Vector2(1800, 600),
		Vector2(1800, 800),
	]

	# Pickup spawns: clear open floor areas, away from all cover objects.
	# Cover positions: CoverA1(400,400), CoverA2(960,300), CoverA3(1520,400),
	#                  CoverB1(600,680), CoverB2(960,780), CoverB3(1320,680).
	# These points are placed in the open corridors between covers.
	_pickup_spawn_points = [
		Vector2(200, 540),    # Far left center corridor
		Vector2(700, 200),    # Top-left open area
		Vector2(1200, 200),   # Top-right open area
		Vector2(1750, 540),   # Far right center corridor
		Vector2(700, 900),    # Bottom-left open area
		Vector2(1200, 900),   # Bottom-right open area
		Vector2(960, 540),    # Center (between all covers)
		Vector2(400, 200),    # Top-left corner open
		Vector2(1550, 850),   # Bottom-right corner open
	]

# ---------------------------------------------------------------------------
# UI Setup
# ---------------------------------------------------------------------------

## Build all UI elements programmatically.
func _setup_ui() -> void:
	var ui: Node = get_node_or_null("CanvasLayer/UI")
	if ui == null:
		push_warning("[ArenaLevel] CanvasLayer/UI not found — UI not created")
		return

	# Enemy count label (top-right).
	_enemy_count_label = Label.new()
	_enemy_count_label.name = "EnemyCountLabel"
	_enemy_count_label.text = "Враги: 0"
	_enemy_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_enemy_count_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_enemy_count_label.offset_left = -220
	_enemy_count_label.offset_right = -10
	_enemy_count_label.offset_top = 10
	_enemy_count_label.offset_bottom = 45
	_enemy_count_label.add_theme_font_size_override("font_size", 20)
	ui.add_child(_enemy_count_label)

	# Wave label (top-right, below enemy count).
	_wave_label = Label.new()
	_wave_label.name = "WaveLabel"
	_wave_label.text = "Волна: 0"
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_wave_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_wave_label.offset_left = -220
	_wave_label.offset_right = -10
	_wave_label.offset_top = 45
	_wave_label.offset_bottom = 80
	_wave_label.add_theme_font_size_override("font_size", 18)
	_wave_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
	ui.add_child(_wave_label)

	# Wave countdown label (center screen).
	_wave_countdown_label = Label.new()
	_wave_countdown_label.name = "WaveCountdownLabel"
	_wave_countdown_label.text = ""
	_wave_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_countdown_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_wave_countdown_label.offset_left = -300
	_wave_countdown_label.offset_right = 300
	_wave_countdown_label.offset_top = 60
	_wave_countdown_label.offset_bottom = 100
	_wave_countdown_label.add_theme_font_size_override("font_size", 24)
	_wave_countdown_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.5, 1.0))
	ui.add_child(_wave_countdown_label)

	# Ammo label (top-left).
	_ammo_label = Label.new()
	_ammo_label.name = "AmmoLabel"
	_ammo_label.text = "Патроны: -"
	_ammo_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_ammo_label.offset_left = 10
	_ammo_label.offset_top = 10
	_ammo_label.offset_right = 300
	_ammo_label.offset_bottom = 42
	_ammo_label.add_theme_font_size_override("font_size", 18)
	ui.add_child(_ammo_label)

	# Health label (top-left, below ammo).
	_health_label = Label.new()
	_health_label.name = "HealthLabel"
	_health_label.text = "Здоровье: -"
	_health_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_health_label.offset_left = 10
	_health_label.offset_top = 42
	_health_label.offset_right = 300
	_health_label.offset_bottom = 72
	_health_label.add_theme_font_size_override("font_size", 16)
	_health_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4, 1.0))
	ui.add_child(_health_label)

	# Difficulty label.
	_difficulty_label = Label.new()
	_difficulty_label.name = "DifficultyLabel"
	_difficulty_label.text = "Difficulty: " + DifficultyManager.get_difficulty_name()
	_difficulty_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_difficulty_label.offset_left = 10
	_difficulty_label.offset_top = 80
	_difficulty_label.offset_right = 250
	_difficulty_label.offset_bottom = 110
	ui.add_child(_difficulty_label)

	# Magazines label.
	_magazines_label = Label.new()
	_magazines_label.name = "MagazinesLabel"
	_magazines_label.text = "Магазины: -"
	_magazines_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_magazines_label.offset_left = 10
	_magazines_label.offset_top = 132
	_magazines_label.offset_right = 450
	_magazines_label.offset_bottom = 162
	ui.add_child(_magazines_label)

	# Combo label (top-right).
	_combo_label = Label.new()
	_combo_label.name = "ComboLabel"
	_combo_label.text = ""
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combo_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_combo_label.offset_left = -500
	_combo_label.offset_right = -10
	_combo_label.offset_top = 90
	_combo_label.offset_bottom = 120
	_combo_label.add_theme_font_size_override("font_size", 28)
	_combo_label.add_theme_constant_override("line_spacing", 0)
	_combo_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2, 1.0))
	_combo_label.add_theme_font_override("font", load("res://assets/fonts/gothic_bitmap.fnt"))
	_combo_label.visible = false
	ui.add_child(_combo_label)

	# Pickup hint label (bottom-center).
	var pickup_hint := Label.new()
	pickup_hint.name = "PickupHintLabel"
	pickup_hint.text = "Подбирай аптечки, патроны и оружие между волнами!"
	pickup_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pickup_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	pickup_hint.offset_top = -40
	pickup_hint.offset_bottom = -10
	pickup_hint.add_theme_font_size_override("font_size", 13)
	pickup_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.7))
	ui.add_child(pickup_hint)


## Setup saturation overlay.
func _setup_saturation_overlay() -> void:
	var canvas_layer := get_node_or_null("CanvasLayer")
	if canvas_layer == null:
		return
	_saturation_overlay = ColorRect.new()
	_saturation_overlay.name = "SaturationOverlay"
	_saturation_overlay.color = Color(1.0, 0.9, 0.3, 0.0)
	_saturation_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_saturation_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas_layer.add_child(_saturation_overlay)
	canvas_layer.move_child(_saturation_overlay, canvas_layer.get_child_count() - 1)

# ---------------------------------------------------------------------------
# Signal Handlers
# ---------------------------------------------------------------------------

## Called by GameManager.enemy_killed (for saturation flash).
func _on_game_manager_enemy_killed() -> void:
	if _saturation_overlay == null:
		return
	_saturation_overlay.color.a = SATURATION_INTENSITY
	var tween := create_tween()
	tween.tween_property(_saturation_overlay, "color:a", 0.0, SATURATION_DURATION)


## Called when an enemy is hit (accuracy tracking).
func _on_enemy_hit() -> void:
	if GameManager:
		GameManager.register_hit()


## Called when a shot is fired.
func _on_shot_fired() -> void:
	if GameManager:
		GameManager.register_shot()


## Called when the player takes damage (C# Damaged signal: amount, currentHealth).
func _on_player_damaged(_amount: float, current_health: float) -> void:
	if _health_label == null:
		return
	var max_health: float = 0.0
	if _player:
		var hc := _player.get_node_or_null("HealthComponent")
		if hc:
			max_health = hc.get("MaxHealth") if hc.get("MaxHealth") != null else 0.0
	_health_label.text = "Здоровье: %d/%d" % [int(current_health), int(max_health)]


## Called when the player heals (C# Healed signal: amount, currentHealth).
func _on_player_healed(_amount: float, current_health: float) -> void:
	if _health_label == null:
		return
	var max_health: float = 0.0
	if _player:
		var hc := _player.get_node_or_null("HealthComponent")
		if hc:
			max_health = hc.get("MaxHealth") if hc.get("MaxHealth") != null else 0.0
	_health_label.text = "Здоровье: %d/%d" % [int(current_health), int(max_health)]


## Called when player ammo changes (C# weapon).
func _on_weapon_ammo_changed(current_ammo: int, reserve_ammo: int) -> void:
	_update_ammo_label_magazine(current_ammo, reserve_ammo)


## Called when magazine inventory changes.
func _on_magazines_changed(magazine_ammo_counts: Array) -> void:
	_update_magazines_label(magazine_ammo_counts)


## Called when shotgun shell count changes.
func _on_shell_count_changed(shell_count: int, _capacity: int) -> void:
	var reserve_ammo: int = 0
	if _player:
		var weapon := _player.get_node_or_null("Shotgun")
		if weapon != null and weapon.get("ReserveAmmo") != null:
			reserve_ammo = weapon.ReserveAmmo
	_update_ammo_label_magazine(shell_count, reserve_ammo)


## Called when combo changes.
func _on_combo_changed(combo: int, points: int) -> void:
	if _combo_label == null:
		return
	if combo > 0:
		_combo_label.text = "x%d COMBO\n+%d" % [combo, points]
		_combo_label.visible = true
		# Combo pop animation: scale bounce + fade in, then fade out
		_combo_label.scale = Vector2(0.7, 0.7)
		_combo_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(_combo_label, "scale", Vector2(1.0, 1.0), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(_combo_label, "modulate:a", 1.0, 0.1)
		tween.set_parallel(false)
		tween.tween_interval(1.0)
		tween.tween_property(_combo_label, "modulate:a", 0.0, 0.3)
	else:
		_combo_label.visible = false


## Called when the player dies.
func _on_player_died() -> void:
	if not _level_active:
		return
	_level_active = false

	print("[ArenaLevel] Player died on wave %d" % _wave_number)
	_log_to_file("Player died on wave %d" % _wave_number)

	# Stop replay recording.
	var replay_manager: Node = _get_or_create_replay_manager()
	if replay_manager and replay_manager.has_method("StopRecording"):
		replay_manager.StopRecording()

	# Show score screen.
	call_deferred("_complete_level_with_score")

# ---------------------------------------------------------------------------
# UI Update Helpers
# ---------------------------------------------------------------------------

func _update_enemy_count_label() -> void:
	if _enemy_count_label:
		_enemy_count_label.text = "Враги: %d" % _enemies_alive

	# Update health label whenever we check enemies (player data may have changed).
	_update_health_label()


func _update_wave_label() -> void:
	if _wave_label:
		_wave_label.text = "Волна: %d" % _wave_number


func _update_health_label() -> void:
	if _health_label == null or _player == null:
		return
	var hc := _player.get_node_or_null("HealthComponent")
	if hc:
		_health_label.text = "Здоровье: %d/%d" % [int(hc.CurrentHealth), int(hc.MaxHealth)]
	elif _player.get("_current_health") != null:
		_health_label.text = "Здоровье: %d/%d" % [_player._current_health, _player.max_health]


func _update_debug_ui() -> void:
	if GameManager == null:
		return
	if _difficulty_label:
		_difficulty_label.text = "Difficulty: " + DifficultyManager.get_difficulty_name()
	_update_health_label()


func _update_ammo_label_magazine(current_ammo: int, reserve_ammo: int) -> void:
	if _ammo_label:
		_ammo_label.text = "Патроны: %d / %d" % [current_ammo, reserve_ammo]
		if current_ammo <= 5:
			_ammo_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0))
		elif current_ammo <= 10:
			_ammo_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2, 1.0))
		else:
			_ammo_label.remove_theme_color_override("font_color")


func _update_magazines_label(magazine_ammo_counts: Array) -> void:
	if _magazines_label == null:
		return
	# Find equipped weapon
	var _weapon_for_caps: Node = null
	if _player != null:
		for _wn in ["MakarovPM", "Shotgun", "AssaultRifle", "AKGL", "Revolver", "SilencedPistol", "SniperRifle", "MiniUzi"]:
			_weapon_for_caps = _player.get_node_or_null(_wn)
			if _weapon_for_caps != null:
				break
	if _weapon_for_caps != null and _weapon_for_caps.get("UsesTubeMagazine") == true:
		_magazines_label.visible = false
		return
	if _weapon_for_caps != null and _weapon_for_caps.has_signal("CylinderStateChanged"):
		_magazines_label.visible = false
		return
	_magazines_label.visible = true
	if magazine_ammo_counts.is_empty():
		_magazines_label.text = "Магазины: -"
		return
	# Get magazine capacities to distinguish full vs partial spares
	var mag_max_counts: Array = []
	if _weapon_for_caps != null and _weapon_for_caps.has_method("GetMagazineMaxCounts"):
		mag_max_counts = Array(_weapon_for_caps.GetMagazineMaxCounts())

	var parts: Array[String] = []
	# Current magazine always shown first
	parts.append(str(magazine_ammo_counts[0]))

	# Spare magazines: skip empty, show partial individually, abbreviate full as + xN
	var full_spare_count: int = 0
	for i in range(1, magazine_ammo_counts.size()):
		var ammo: int = magazine_ammo_counts[i]
		if ammo <= 0:
			continue
		var cap: int = mag_max_counts[i] if i < mag_max_counts.size() else 0
		if cap > 0 and ammo >= cap:
			full_spare_count += 1
		else:
			parts.append(str(ammo))

	if full_spare_count > 0:
		parts.append("+ x%d" % full_spare_count)

	_magazines_label.text = "Магазины: [%s]" % " | ".join(parts)

# ---------------------------------------------------------------------------
# Level Completion (on player death)
# ---------------------------------------------------------------------------

func _complete_level_with_score() -> void:
	if _score_shown:
		return
	_score_shown = true

	# Disable player controls.
	if _player != null and is_instance_valid(_player):
		_player.set_physics_process(false)
		_player.set_process(false)
		_player.set_process_input(false)
		_player.set_process_unhandled_input(false)

	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager and score_manager.has_method("complete_level"):
		# Inject arena-specific data before showing score.
		var score_data: Dictionary = score_manager.complete_level()
		# Add wave number to score data for display.
		score_data["wave_reached"] = _wave_number
		_show_score_screen(score_data)
	else:
		_show_victory_message()


## Show the animated score screen.
func _show_score_screen(score_data: Dictionary) -> void:
	var ui: Node = get_node_or_null("CanvasLayer/UI")
	if ui == null:
		_show_victory_message()
		return

	var animated_score_screen_script = load("res://scripts/ui/animated_score_screen.gd")
	if animated_score_screen_script:
		var score_screen = animated_score_screen_script.new()
		score_screen.name = "AnimatedScoreScreen"
		ui.add_child(score_screen)
		if score_screen.has_method("show_animated_score"):
			score_screen.show_animated_score(ui, score_data)
	else:
		_show_victory_message()

	# Save progress for this arena run.
	var progress_manager: Node = get_node_or_null("/root/ProgressManager")
	if progress_manager and progress_manager.has_method("save_level_result"):
		progress_manager.save_level_result(
			"res://scenes/levels/ArenaLevel.tscn",
			score_data.get("rank", "F")
		)


## Fallback: show a simple victory/death message.
func _show_victory_message() -> void:
	var ui: Node = get_node_or_null("CanvasLayer/UI")
	if ui == null:
		return
	var msg := Label.new()
	msg.name = "VictoryLabel"
	msg.text = "Волна %d — Игра окончена!\nНажмите Q для рестарта." % _wave_number
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	msg.add_theme_font_size_override("font_size", 36)
	msg.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 1.0))
	ui.add_child(msg)

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

func _log_to_file(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[ArenaLevel] " + message)
	else:
		print("[ArenaLevel] " + message)
