extends Node
## Breaching charges active item effect controller (Issues #1043, #1087, #1093).
##
## Manages the breaching charge placement and detonation mechanics.
## The player holds Space near a wall to attach a charge; releasing Space
## attaches it. Pressing Space again detonates all placed charges, opening
## a passage in the wall and stunning/blinding nearby enemies.
##
## Gameplay rules:
## - 2 charges per battle (resets on level restart)
## - Hold Space near a wall → charge attaches to the nearest wall surface
## - Once a charge is placed, press Space to detonate
## - Detonation carves a BREACH_PASSAGE_WIDTH passage in the wall (Issue #1087 item 5)
##   — long walls are split into two segments with a gap; thin/short walls become fully
##   passable but are faded (alpha 0.25) rather than removed, so they remain visible
## - Enemies within STUN_RADIUS on the far side of the wall are stunned + blinded for 3 s
## - Issue #1093: charges placed at wall corners now open passages in both adjacent walls
##
## Visual features (Issues #1043, #1087):
## - While holding Space: breaching charge sprite appears in player's hands
## - After placement: realistic C4-like composite marker with blinking LED (Issue #1087 item 2)
## - On detonation: directional cone explosion toward the wall (Issue #1087 item 1)

## Maximum charges per battle.
const MAX_CHARGES: int = 2

## Radius to search for a wall when placing a charge (pixels).
const PLACEMENT_RADIUS: float = 40.0

## Width of the passage carved through a wall (pixels).
## Restoring to 120 px so the breach is large enough to walk through comfortably.
## Walls whose minor axis is smaller than this threshold are treated as "thin" —
## their collision is disabled and their visual is faded rather than split.
const BREACH_PASSAGE_WIDTH: float = 120.0

## Stun/blind radius from detonation point (pixels).
const STUN_RADIUS: float = 150.0

## Duration of stun and blind effects on enemies (seconds).
const STUN_DURATION: float = 3.0

## Collision layer for obstacles/walls (layer 4 = bit 8).
const WALL_COLLISION_LAYER: int = 4

## Path to the breaching charge placement sound.
const PLACE_SOUND_PATH: String = "res://assets/audio/breaching_charge_place.wav"

## Path to the breaching charge detonation sound.
## Uses the F-1 (defensive) grenade explosion sound as requested in Issue #1087.
const DETONATE_SOUND_PATH: String = "res://assets/audio/взрыв оборонительной гранаты.wav"

## Volume in dB for breaching charge sounds.
const SOUND_VOLUME_DB: float = 0.0

## Offset of the held-charge sprite relative to player center (in hand position).
const HELD_CHARGE_OFFSET: Vector2 = Vector2(14, -4)

## Scale of the held-charge sprite.
const HELD_CHARGE_SCALE: Vector2 = Vector2(0.4, 0.4)

## Scale of the placed-charge marker sprite.
const PLACED_CHARGE_SCALE: Vector2 = Vector2(0.3, 0.3)

## Current number of charges remaining.
var charges: int = MAX_CHARGES

## Whether a charge is currently placed on a wall (waiting for detonation).
var has_placed_charge: bool = false

## The wall nodes that have a charge placed on them (supports corners with two walls).
var _charged_walls: Array = []

## World position where the charge was placed (wall surface hit point).
var _charge_position: Vector2 = Vector2.ZERO

## Direction from player toward wall (used for explosion cone).
var _charge_wall_direction: Vector2 = Vector2.ZERO

## Whether Space is currently held (for placement detection).
var _space_held: bool = false

## Whether a charge is being held (Space held, looking for wall).
var _holding_for_placement: bool = false

## Reference to the player node.
var _player: Node2D = null

## AudioStreamPlayer for placement sound.
var _place_audio_player: AudioStreamPlayer = null

## AudioStreamPlayer for detonation sound.
var _detonate_audio_player: AudioStreamPlayer = null

## Sprite2D shown in player's hands while holding Space.
var _held_charge_sprite: Sprite2D = null

## Sprite2D marker placed on the wall after charge placement.
var _placed_charge_marker: Sprite2D = null

## Whether the weapon node has been hidden for the held-charge visual.
var _weapon_hidden: bool = false

## Cached reference to the weapon mount node (to hide/show weapon).
var _weapon_mount: Node2D = null

## Signal emitted when a charge is placed.
signal charge_placed(charges_remaining: int)

## Signal emitted when charges are detonated.
signal charges_detonated(position: Vector2)

## Signal emitted when charges change.
signal charges_changed(current: int, maximum: int)


func _ready() -> void:
	_setup_audio()


## Initialize with a reference to the player node.
func initialize(player: Node2D) -> void:
	_player = player
	# Cache the weapon mount for hide/show during charge holding
	var player_model: Node2D = player.get_node_or_null("PlayerModel")
	if player_model != null:
		_weapon_mount = player_model.get_node_or_null("WeaponMount")
	FileLogger.info("[BreachingCharges] Initialized with player: %s, charges: %d/%d" % [
		player.name, charges, MAX_CHARGES
	])


## Called by Player.cs when the player starts or stops holding Space.
## Shows or hides the charge sprite in the player's hands.
func set_holding_for_placement(holding: bool) -> void:
	if holding == _holding_for_placement:
		return

	_holding_for_placement = holding

	if holding:
		_show_charge_in_hands()
	else:
		_hide_charge_in_hands()


## Called by player._handle_breaching_charges_input() when Space is held.
## Looks for a nearby wall and attaches a charge to it.
func try_place_charge() -> bool:
	if charges <= 0:
		FileLogger.info("[BreachingCharges] No charges remaining")
		return false

	if has_placed_charge:
		FileLogger.info("[BreachingCharges] Charge already placed — press Space to detonate")
		return false

	if _player == null:
		return false

	# Search for all wall bodies within placement radius (supports corners with two walls)
	var wall_results := _find_walls_with_hits()
	if wall_results.is_empty():
		FileLogger.info("[BreachingCharges] No wall found within %.0f px" % PLACEMENT_RADIUS)
		return false

	# Use the primary (nearest) wall's hit position and direction for the charge marker
	var primary: Dictionary = wall_results[0]
	var hit_pos: Vector2 = primary["hit_pos"]
	var hit_dir: Vector2 = primary["direction"]

	# Attach charge to all found walls (may be two walls at a corner)
	charges -= 1
	has_placed_charge = true
	_charged_walls = wall_results
	_charge_position = hit_pos
	_charge_wall_direction = hit_dir

	var wall_names: Array = []
	for wr in wall_results:
		wall_names.append(wr["wall"].name)
	FileLogger.info("[BreachingCharges] Charge placed on wall(s) %s at %s. Charges remaining: %d/%d" % [
		str(wall_names), str(_charge_position), charges, MAX_CHARGES
	])

	# Hide held-charge sprite and show placed-charge marker on wall
	_hide_charge_in_hands()
	_spawn_placed_charge_marker(hit_pos, hit_dir)

	_play_place_sound()
	charge_placed.emit(charges)
	charges_changed.emit(charges, MAX_CHARGES)
	return true


## Detonate all placed charges.
## Disables the charged wall's collision and stuns/blinds nearby enemies.
func detonate() -> bool:
	if not has_placed_charge:
		FileLogger.info("[BreachingCharges] No charge placed to detonate")
		return false

	var det_pos := _charge_position
	var det_dir := _charge_wall_direction
	var walls := _charged_walls.duplicate()

	# Clear state before applying effects (prevent double-detonation)
	has_placed_charge = false
	_charged_walls = []
	_charge_position = Vector2.ZERO
	_charge_wall_direction = Vector2.ZERO

	FileLogger.info("[BreachingCharges] Detonating at %s" % str(det_pos))

	# Remove the placed charge marker
	_remove_placed_charge_marker()

	# Open a passage in each charged wall using each wall's own hit position.
	# This is critical at corners: the primary hit_pos is on the nearest wall,
	# but secondary walls at the corner must be breached at THEIR own hit point
	# so the passage is carved at the correct end of that wall.
	for wall_result in walls:
		_open_wall_passage(wall_result["wall"], wall_result["hit_pos"])

	# Spawn dust/debris cloud at the breach site (Issue #1099)
	_spawn_wall_dust_effect(det_pos, det_dir)

	# Spawn directional explosion cone effect
	_spawn_explosion_effect(det_pos, det_dir)

	# Stun and blind enemies near the blast
	_apply_blast_effects(det_pos)

	_play_detonate_sound()
	_emit_explosion_sound_event(det_pos)
	charges_detonated.emit(det_pos)
	charges_changed.emit(charges, MAX_CHARGES)
	return true


## Get remaining charges.
func get_charges() -> int:
	return charges


## Find all unique StaticBody2D walls within PLACEMENT_RADIUS of the player.
## Returns an empty array if none found, or an Array of {"wall": Node, "hit_pos": Vector2,
## "direction": Vector2} dictionaries sorted by distance (nearest first).
## Issue #1093: returns all walls so that charges placed at corners affect both adjacent walls.
## When a thin corner fill piece is hit, performs a second-pass ray cast excluding that piece
## to find the adjacent walls that connect at the corner.
func _find_walls_with_hits() -> Array:
	if _player == null:
		return []

	var space_state := _player.get_world_2d().direct_space_state
	if space_state == null:
		FileLogger.info("[BreachingCharges] WARNING: Could not get physics space state")
		return []

	# Cast a short ray in each cardinal + diagonal direction to find wall surfaces
	var directions := [
		Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN,
		Vector2(1, 1).normalized(), Vector2(-1, 1).normalized(),
		Vector2(1, -1).normalized(), Vector2(-1, -1).normalized()
	]

	var player_pos := _player.global_position

	# Collect the nearest hit per unique wall node
	var walls_by_node: Dictionary = {}  # Node -> {hit_pos, direction, dist}

	for dir in directions:
		var query := PhysicsRayQueryParameters2D.create(
			player_pos,
			player_pos + dir * PLACEMENT_RADIUS,
			WALL_COLLISION_LAYER  # bitmask value 4 matches collision_layer = 4 on wall bodies
		)
		query.exclude = [_player.get_rid()]
		var result := space_state.intersect_ray(query)

		if result.size() > 0 and result.has("collider"):
			var collider: Node = result["collider"]
			var dist: float = player_pos.distance_to(result["position"])

			# Keep only the closest hit for each unique wall node
			if not walls_by_node.has(collider) or dist < walls_by_node[collider]["dist"]:
				walls_by_node[collider] = {
					"wall": collider,
					"hit_pos": result["position"],
					"direction": dir,
					"dist": dist
				}

	# Second pass: for any thin corner-fill pieces found (small in both axes),
	# re-cast the same rays excluding those pieces to find the actual adjacent walls
	# they would otherwise occlude. Corner fills are typically square and smaller than
	# BREACH_PASSAGE_WIDTH — their presence at a corner blocks rays from reaching
	# the larger walls on both sides of the junction.
	var corner_fill_rids: Array = []
	for node in walls_by_node.keys():
		if _is_corner_fill(node):
			corner_fill_rids.append(node.get_rid())
			FileLogger.info("[BreachingCharges] Corner fill detected: '%s' — scanning for adjacent walls" % node.name)

	if not corner_fill_rids.is_empty():
		var exclude_list: Array = [_player.get_rid()] + corner_fill_rids
		# Use a slightly larger radius so rays reach walls behind the corner fill
		var extended_radius: float = PLACEMENT_RADIUS * 1.5
		for dir in directions:
			var query2 := PhysicsRayQueryParameters2D.create(
				player_pos,
				player_pos + dir * extended_radius,
				WALL_COLLISION_LAYER
			)
			query2.exclude = exclude_list
			var result2 := space_state.intersect_ray(query2)

			if result2.size() > 0 and result2.has("collider"):
				var collider: Node = result2["collider"]
				var dist: float = player_pos.distance_to(result2["position"])

				if not walls_by_node.has(collider) or dist < walls_by_node[collider]["dist"]:
					walls_by_node[collider] = {
						"wall": collider,
						"hit_pos": result2["position"],
						"direction": dir,
						"dist": dist
					}

	if walls_by_node.is_empty():
		return []

	# Convert to array and sort by distance (nearest first)
	var found: Array = walls_by_node.values()
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["dist"] < b["dist"]
	)

	var wall_names: Array = []
	for entry in found:
		wall_names.append(entry["wall"].name)
	FileLogger.info("[BreachingCharges] Found %d wall(s) within %.0f px: %s" % [
		found.size(), PLACEMENT_RADIUS, str(wall_names)
	])

	return found


## Returns true if the wall node is a thin corner-fill piece (small in both dimensions).
## Corner fills are square blocks used to close gaps at wall junctions; they are too small
## to split (both axes < BREACH_PASSAGE_WIDTH) and their presence occludes adjacent walls.
func _is_corner_fill(wall: Node) -> bool:
	for child in wall.get_children():
		if child is CollisionShape2D and (child as CollisionShape2D).shape is RectangleShape2D:
			var size: Vector2 = ((child as CollisionShape2D).shape as RectangleShape2D).size
			# A corner fill is small in BOTH dimensions (unlike a wall that is long in one axis)
			return size.x < BREACH_PASSAGE_WIDTH and size.y < BREACH_PASSAGE_WIDTH
	return false


## Carve a passage through the wall at the breach position.
## Delegates to WallBreachHelper (Issue #1131) for shared logic with RPG rockets.
## For long walls this splits the wall into two collision segments with a gap.
## For thin/short walls (smaller than BREACH_PASSAGE_WIDTH in the split axis) the
## collision is disabled entirely and the visual is faded (alpha 0.25) — the wall
## remains visible but is passable, fulfilling Issue #1087 item 5.
## breach_world_pos: the world-space hit position where the charge was placed.
## Issue #1093: when the hit is near the wall's end (corner placement), the passage
## is snapped to the end so both walls at the corner are visibly broken.
func _open_wall_passage(wall: Node, breach_world_pos: Vector2) -> void:
	WallBreachHelper.open_wall_passage(wall, breach_world_pos)


## Apply stun and blind effects to enemies near the detonation point.
func _apply_blast_effects(det_pos: Vector2) -> void:
	var enemies := _get_enemies_in_radius(det_pos, STUN_RADIUS)
	var affected := 0

	for enemy in enemies:
		# Use apply_flashbang_effect if available (same stun/blind system as grenades)
		if enemy.has_method("apply_flashbang_effect"):
			enemy.apply_flashbang_effect(STUN_DURATION, STUN_DURATION)
			affected += 1
		else:
			# Fallback: individual stun/blind setters
			if enemy.has_method("set_stunned"):
				enemy.set_stunned(true)
				affected += 1
			if enemy.has_method("set_blinded"):
				enemy.set_blinded(true)

	FileLogger.info("[BreachingCharges] Blast stunned/blinded %d enemies within %.0f px" % [
		affected, STUN_RADIUS
	])


## Return all nodes in the "enemies" group within radius of a point.
func _get_enemies_in_radius(center: Vector2, radius: float) -> Array:
	var result: Array = []
	if _player == null:
		return result

	var all_enemies := _player.get_tree().get_nodes_in_group("enemies")
	for enemy in all_enemies:
		if enemy is Node2D:
			var dist: float = center.distance_to((enemy as Node2D).global_position)
			if dist <= radius:
				result.append(enemy)

	return result


## Show the breaching charge sprite in the player's hands (Space held).
## Hides the weapon mount so the charge replaces the weapon visually.
func _show_charge_in_hands() -> void:
	if _player == null:
		return

	if _held_charge_sprite != null and is_instance_valid(_held_charge_sprite):
		_held_charge_sprite.visible = true
		return

	# Load the icon texture as the held sprite
	var texture: Texture2D = load("res://assets/sprites/weapons/breaching_charges_icon.png")
	if texture == null:
		FileLogger.info("[BreachingCharges] WARNING: Could not load breaching_charges_icon.png for held sprite")
		return

	_held_charge_sprite = Sprite2D.new()
	_held_charge_sprite.texture = texture
	_held_charge_sprite.position = HELD_CHARGE_OFFSET
	_held_charge_sprite.scale = HELD_CHARGE_SCALE
	_held_charge_sprite.z_index = 5
	_player.add_child(_held_charge_sprite)

	# Hide the weapon mount so the charge appears in the hands instead
	if _weapon_mount != null and is_instance_valid(_weapon_mount):
		_weapon_mount.visible = false
		_weapon_hidden = true

	FileLogger.info("[BreachingCharges] Charge sprite shown in player's hands")


## Hide the in-hand charge sprite and restore the weapon.
func _hide_charge_in_hands() -> void:
	if _held_charge_sprite != null and is_instance_valid(_held_charge_sprite):
		_held_charge_sprite.queue_free()
		_held_charge_sprite = null

	# Restore weapon mount visibility
	if _weapon_hidden and _weapon_mount != null and is_instance_valid(_weapon_mount):
		_weapon_mount.visible = true
		_weapon_hidden = false

	FileLogger.info("[BreachingCharges] Charge sprite hidden, weapon restored")


## Spawn a marker representing a placed breaching charge on the wall surface.
## Issue #1087 item 2: more realistic model — draws a C4-like block with straps and detonator.
func _spawn_placed_charge_marker(hit_pos: Vector2, direction: Vector2) -> void:
	if _player == null:
		return

	# Root node for the charge assembly, rotated so +X points away from wall
	var root := Node2D.new()
	root.global_position = hit_pos
	# Rotate so the charge faces out from the wall (direction points toward wall, flip it)
	root.rotation = direction.angle() + PI

	root.z_index = 4

	# --- Explosive block body (sandy/beige like C4/PE4) ---
	var body := ColorRect.new()
	body.size = Vector2(18.0, 12.0)
	body.position = Vector2(-9.0, -6.0)  # centered
	body.color = Color(0.85, 0.78, 0.60, 1.0)  # sandy beige
	root.add_child(body)

	# --- Dark grey housing/frame around the block ---
	var frame := ColorRect.new()
	frame.size = Vector2(20.0, 14.0)
	frame.position = Vector2(-10.0, -7.0)
	frame.color = Color(0.25, 0.22, 0.18, 1.0)
	frame.z_index = -1  # render behind body
	root.add_child(frame)

	# --- Strap / band across the middle ---
	var strap := ColorRect.new()
	strap.size = Vector2(20.0, 3.0)
	strap.position = Vector2(-10.0, -1.5)
	strap.color = Color(0.20, 0.20, 0.20, 1.0)
	root.add_child(strap)

	# --- Small detonator cylinder on top-right corner ---
	var det := ColorRect.new()
	det.size = Vector2(3.0, 7.0)
	det.position = Vector2(6.0, -10.0)
	det.color = Color(0.40, 0.40, 0.44, 1.0)  # metallic grey
	root.add_child(det)

	# --- Blinking red LED indicator (small red dot) ---
	var led := ColorRect.new()
	led.size = Vector2(3.0, 3.0)
	led.position = Vector2(-4.0, -5.5)
	led.color = Color(1.0, 0.08, 0.08, 1.0)
	root.add_child(led)

	# Animate the LED: blink every 0.5 s using a Tween
	var tween: Tween = root.create_tween()
	tween.set_loops()
	tween.tween_property(led, "modulate:a", 0.0, 0.4)
	tween.tween_property(led, "modulate:a", 1.0, 0.1)
	tween.tween_interval(0.4)

	_placed_charge_marker = root
	_player.get_tree().current_scene.add_child(root)

	FileLogger.info("[BreachingCharges] Placed charge marker spawned at %s" % str(hit_pos))


## Remove the placed charge marker (called on detonation).
func _remove_placed_charge_marker() -> void:
	if _placed_charge_marker != null and is_instance_valid(_placed_charge_marker):
		_placed_charge_marker.queue_free()
		_placed_charge_marker = null


## Offset to push dust spawn point to the far side of the wall (past the wall thickness).
## Typical walls in this game are 32 px thick; 40 px ensures the dust origin clears
## the wall body regardless of exact geometry.
const DUST_WALL_PASS_OFFSET: float = 40.0

## Spawn a dust/debris cloud at the breach site immediately after wall destruction (Issue #1099).
## Reuses ImpactEffectsManager.spawn_dust_effect which uses the existing DustEffect.tscn
## (GPUParticles2D, 25 particles, one-shot, auto-cleanup) — negligible performance cost.
## Three puffs are spawned on the OPPOSITE side of the wall from the charge (as if the
## explosion was directional and blew through the wall).  Each puff billows further away
## from the charge in the same direction, simulating debris flying out of the breach.
func _spawn_wall_dust_effect(det_pos: Vector2, direction: Vector2) -> void:
	if _player == null:
		return

	var impact_manager: Node = _player.get_node_or_null("/root/ImpactEffectsManager")
	if impact_manager == null or not impact_manager.has_method("spawn_dust_effect"):
		FileLogger.info("[BreachingCharges] ImpactEffectsManager not available, skipping dust effect")
		return

	# Dust spawns on the far side of the wall: shift origin past the wall in the charge direction.
	var far_pos: Vector2 = det_pos + direction * DUST_WALL_PASS_OFFSET

	# Surface normal: particles billow in the same direction as the charge (away from the charge,
	# through the breach) — simulating directional blast pushing debris to the opposite side.
	var surface_normal: Vector2 = direction

	# Perpendicular axis along the wall face (used for side offset positions)
	var perp: Vector2 = Vector2(-direction.y, direction.x)
	var side_offset: float = BREACH_PASSAGE_WIDTH / 3.0

	# Center puff (largest — spawned first for visual priority)
	impact_manager.call("spawn_dust_effect", far_pos, surface_normal, null)

	# Side puffs at ±side_offset along the wall face
	impact_manager.call("spawn_dust_effect", far_pos + perp * side_offset, surface_normal, null)
	impact_manager.call("spawn_dust_effect", far_pos - perp * side_offset, surface_normal, null)

	FileLogger.info("[BreachingCharges] Dust effect spawned on far side at %s (3 puffs)" % str(far_pos))


## Spawn a cone-shaped explosion effect directed toward the wall.
## Uses the existing ExplosionFlash scene with a directional particle tweak.
func _spawn_explosion_effect(det_pos: Vector2, direction: Vector2) -> void:
	if _player == null:
		return

	var scene_path := "res://scenes/effects/ExplosionFlash.tscn"
	if not ResourceLoader.exists(scene_path):
		FileLogger.info("[BreachingCharges] ExplosionFlash.tscn not found, skipping visual")
		return

	var scene: PackedScene = load(scene_path)
	if scene == null:
		return

	var effect: Node2D = scene.instantiate() as Node2D
	if effect == null:
		return

	effect.global_position = det_pos

	# Set explosion type to FRAG (orange/red, value 1) for a breaching charge look
	effect.set("explosion_type", 1)
	effect.set("effect_radius", 80.0)

	_player.get_tree().current_scene.add_child(effect)

	# After adding to tree, rotate the particles to form a cone toward the wall
	_apply_cone_direction(effect, direction)

	FileLogger.info("[BreachingCharges] Directional explosion effect spawned at %s toward %s" % [
		str(det_pos), str(direction)
	])

	# Spawn a second smaller effect slightly inside the wall for a breach look
	var effect2: Node2D = scene.instantiate() as Node2D
	if effect2 != null:
		effect2.global_position = det_pos + direction * 20.0
		effect2.set("explosion_type", 1)
		effect2.set("effect_radius", 50.0)
		_player.get_tree().current_scene.add_child(effect2)
		_apply_cone_direction(effect2, direction)


## Adjust particle direction on the explosion flash to create a directional cone toward the wall.
## Issue #1087: explosion should be directed toward the wall like a flashlight beam but wider.
func _apply_cone_direction(effect: Node2D, direction: Vector2) -> void:
	# Rotate the entire effect node so particles spray toward the wall
	effect.rotation = direction.angle()

	# Narrow the particle spread to simulate a directional cone toward the wall
	var particles: GPUParticles2D = effect.get_node_or_null("GPUParticles2D")
	if particles == null:
		return

	var mat = particles.process_material
	if mat == null or not (mat is ParticleProcessMaterial):
		return

	# Duplicate the material to avoid modifying the shared resource used by other explosions
	var pmat: ParticleProcessMaterial = mat.duplicate() as ParticleProcessMaterial
	particles.process_material = pmat

	# Direction: forward along local +X axis (effect node is already rotated toward wall)
	pmat.direction = Vector3(1, 0, 0)
	# Issue #1087: wider sector than flashlight — 90° spread creates a ~180° total cone,
	# wider than a flashlight but still clearly directional toward the wall
	pmat.spread = 90.0
	# Increase velocity for a more dramatic breach effect
	pmat.initial_velocity_min = 100.0
	pmat.initial_velocity_max = 250.0


## Set up audio players for place and detonate sounds.
func _setup_audio() -> void:
	if ResourceLoader.exists(PLACE_SOUND_PATH):
		var stream = load(PLACE_SOUND_PATH)
		if stream:
			_place_audio_player = AudioStreamPlayer.new()
			_place_audio_player.stream = stream
			_place_audio_player.volume_db = SOUND_VOLUME_DB
			add_child(_place_audio_player)
			FileLogger.info("[BreachingCharges] Place sound loaded")
	else:
		FileLogger.info("[BreachingCharges] Place sound not found (non-critical): %s" % PLACE_SOUND_PATH)

	if ResourceLoader.exists(DETONATE_SOUND_PATH):
		var stream = load(DETONATE_SOUND_PATH)
		if stream:
			_detonate_audio_player = AudioStreamPlayer.new()
			_detonate_audio_player.stream = stream
			_detonate_audio_player.volume_db = SOUND_VOLUME_DB
			add_child(_detonate_audio_player)
			FileLogger.info("[BreachingCharges] Detonate sound loaded")
	else:
		FileLogger.info("[BreachingCharges] Detonate sound not found (non-critical): %s" % DETONATE_SOUND_PATH)


## Play the charge placement sound.
func _play_place_sound() -> void:
	if _place_audio_player and is_instance_valid(_place_audio_player):
		_place_audio_player.play()


## Play the detonation sound.
## Uses AudioManager to play the F-1 (defensive) grenade explosion sound (Issue #1087).
## Also emits an EXPLOSION sound event via SoundPropagation so enemies hear the blast
## and react, matching the F-1 grenade behaviour (Issue #1103).
func _play_detonate_sound() -> void:
	# Prefer AudioManager for consistent spatial audio (same as F-1 grenade)
	var audio_manager: Node = Engine.get_singleton("AudioManager") if Engine.has_singleton("AudioManager") else null
	if audio_manager == null and _player != null:
		audio_manager = _player.get_node_or_null("/root/AudioManager")
	if audio_manager != null and audio_manager.has_method("play_defensive_grenade_explosion"):
		var pos := _player.global_position if _player != null else Vector2.ZERO
		audio_manager.play_defensive_grenade_explosion(pos)
		FileLogger.info("[BreachingCharges] Played F-1 explosion sound via AudioManager")
		return
	# Fallback: use local audio player
	if _detonate_audio_player and is_instance_valid(_detonate_audio_player):
		_detonate_audio_player.play()


## Emit an explosion sound event so enemies hear the breaching charge detonation
## and react, just as they react to F-1 grenade explosions (Issue #1103).
func _emit_explosion_sound_event(det_pos: Vector2) -> void:
	if _player == null:
		return

	var sound_propagation: Node = _player.get_node_or_null("/root/SoundPropagation")
	if sound_propagation == null or not sound_propagation.has_method("emit_sound"):
		FileLogger.info("[BreachingCharges] SoundPropagation not available, enemies will not hear blast")
		return

	# SoundType.EXPLOSION = 1, SourceType.PLAYER = 0
	# Use default EXPLOSION propagation distance (2200 px) — same loudness as grenade explosions.
	sound_propagation.emit_sound(1, det_pos, 0, _player)
	FileLogger.info("[BreachingCharges] Explosion sound event emitted at %s for enemy awareness" % str(det_pos))
