extends Node
## Breaching charges active item effect controller (Issue #1043).
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
## - Detonation disables the wall's collision (creates passage) in a small radius
## - Enemies within STUN_RADIUS on the far side of the wall are stunned + blinded for 3 s
##
## Visual features (Issue #1043):
## - While holding Space: breaching charge sprite appears in player's hands
## - After placement: charge marker remains on the wall surface
## - On detonation: cone-shaped explosion toward the wall

## Maximum charges per battle.
const MAX_CHARGES: int = 2

## Radius to search for a wall when placing a charge (pixels).
const PLACEMENT_RADIUS: float = 40.0

## Stun/blind radius from detonation point (pixels).
const STUN_RADIUS: float = 150.0

## Duration of stun and blind effects on enemies (seconds).
const STUN_DURATION: float = 3.0

## Collision layer for obstacles/walls (layer 4 = bit 8).
const WALL_COLLISION_LAYER: int = 4

## Path to the breaching charge placement sound.
const PLACE_SOUND_PATH: String = "res://assets/audio/breaching_charge_place.wav"

## Path to the breaching charge detonation sound.
const DETONATE_SOUND_PATH: String = "res://assets/audio/breaching_charge_detonate.wav"

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

## The wall node that has a charge placed on it.
var _charged_wall: Node = null

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

	# Search for the nearest wall body within placement radius
	var wall_result := _find_nearest_wall_with_hit()
	if wall_result.is_empty():
		FileLogger.info("[BreachingCharges] No wall found within %.0f px" % PLACEMENT_RADIUS)
		return false

	var wall: Node = wall_result["wall"]
	var hit_pos: Vector2 = wall_result["hit_pos"]
	var hit_dir: Vector2 = wall_result["direction"]

	# Attach charge to the wall
	charges -= 1
	has_placed_charge = true
	_charged_wall = wall
	_charge_position = hit_pos
	_charge_wall_direction = hit_dir

	FileLogger.info("[BreachingCharges] Charge placed on wall '%s' at %s. Charges remaining: %d/%d" % [
		wall.name, str(_charge_position), charges, MAX_CHARGES
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
	var wall := _charged_wall

	# Clear state before applying effects (prevent double-detonation)
	has_placed_charge = false
	_charged_wall = null
	_charge_position = Vector2.ZERO
	_charge_wall_direction = Vector2.ZERO

	FileLogger.info("[BreachingCharges] Detonating at %s" % str(det_pos))

	# Remove the placed charge marker
	_remove_placed_charge_marker()

	# Disable the wall's collision to create a passage
	_open_wall_passage(wall)

	# Spawn directional explosion cone effect
	_spawn_explosion_effect(det_pos, det_dir)

	# Stun and blind enemies near the blast
	_apply_blast_effects(det_pos)

	_play_detonate_sound()
	charges_detonated.emit(det_pos)
	charges_changed.emit(charges, MAX_CHARGES)
	return true


## Get remaining charges.
func get_charges() -> int:
	return charges


## Find the nearest StaticBody2D wall within PLACEMENT_RADIUS of the player.
## Returns an empty dict if none found, or {"wall": Node, "hit_pos": Vector2, "direction": Vector2}.
func _find_nearest_wall_with_hit() -> Dictionary:
	if _player == null:
		return {}

	var space_state := _player.get_world_2d().direct_space_state
	if space_state == null:
		FileLogger.info("[BreachingCharges] WARNING: Could not get physics space state")
		return {}

	# Cast a short ray in each cardinal + diagonal direction to find a wall surface
	var directions := [
		Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN,
		Vector2(1, 1).normalized(), Vector2(-1, 1).normalized(),
		Vector2(1, -1).normalized(), Vector2(-1, -1).normalized()
	]

	var player_pos := _player.global_position
	var nearest_wall: Node = null
	var nearest_hit_pos: Vector2 = Vector2.ZERO
	var nearest_dir: Vector2 = Vector2.ZERO
	var nearest_dist: float = PLACEMENT_RADIUS + 1.0

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
			if dist < nearest_dist:
				nearest_dist = dist
				nearest_wall = collider
				nearest_hit_pos = result["position"]
				nearest_dir = dir

	if nearest_wall == null:
		return {}

	return {"wall": nearest_wall, "hit_pos": nearest_hit_pos, "direction": nearest_dir}


## Disable the wall node's collision shape to create a passable opening.
func _open_wall_passage(wall: Node) -> void:
	if wall == null or not is_instance_valid(wall):
		FileLogger.info("[BreachingCharges] WARNING: Wall reference invalid at detonation")
		return

	# Disable all CollisionShape2D children of the wall StaticBody2D
	var disabled_count := 0
	for child in wall.get_children():
		if child is CollisionShape2D:
			(child as CollisionShape2D).disabled = true
			disabled_count += 1
		elif child is CollisionPolygon2D:
			(child as CollisionPolygon2D).disabled = true
			disabled_count += 1

	if disabled_count > 0:
		FileLogger.info("[BreachingCharges] Opened passage: disabled %d collision shape(s) on '%s'" % [
			disabled_count, wall.name
		])
	else:
		FileLogger.info("[BreachingCharges] WARNING: No collision shapes found on wall '%s'" % wall.name)

	# Also hide any Sprite2D / Polygon2D visuals on the wall for visual feedback
	for child in wall.get_children():
		if child is CanvasItem:
			(child as CanvasItem).visible = false


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


## Spawn a marker sprite on the wall surface at the placement position.
func _spawn_placed_charge_marker(hit_pos: Vector2, direction: Vector2) -> void:
	if _player == null:
		return

	var texture: Texture2D = load("res://assets/sprites/weapons/breaching_charges_icon.png")
	if texture == null:
		FileLogger.info("[BreachingCharges] WARNING: Could not load icon for placed charge marker")
		return

	_placed_charge_marker = Sprite2D.new()
	_placed_charge_marker.texture = texture
	_placed_charge_marker.scale = PLACED_CHARGE_SCALE
	_placed_charge_marker.z_index = 4
	# Rotate the marker to face the wall (point inward)
	_placed_charge_marker.rotation = direction.angle()
	_placed_charge_marker.modulate = Color(1.0, 0.8, 0.2, 1.0)  # Yellow-orange tint for visibility
	_placed_charge_marker.global_position = hit_pos

	# Add to the scene root so it stays at the wall position even if player moves
	_player.get_tree().current_scene.add_child(_placed_charge_marker)

	FileLogger.info("[BreachingCharges] Placed charge marker spawned at %s" % str(hit_pos))


## Remove the placed charge marker (called on detonation).
func _remove_placed_charge_marker() -> void:
	if _placed_charge_marker != null and is_instance_valid(_placed_charge_marker):
		_placed_charge_marker.queue_free()
		_placed_charge_marker = null


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


## Adjust particle direction on the explosion flash to create a cone toward the wall.
func _apply_cone_direction(effect: Node2D, direction: Vector2) -> void:
	# Rotate the entire effect node so particles spray toward the wall
	effect.rotation = direction.angle()

	# Narrow the particle spread to simulate a directional cone
	var particles: GPUParticles2D = effect.get_node_or_null("GPUParticles2D")
	if particles == null:
		return

	var mat = particles.process_material
	if mat == null or not (mat is ParticleProcessMaterial):
		return

	var pmat: ParticleProcessMaterial = mat as ParticleProcessMaterial
	# Direction: forward (local +X after rotation becomes world direction)
	pmat.direction = Vector3(1, 0, 0)
	# Narrow spread to 45 degrees for a directional cone
	pmat.spread = 45.0
	# Increase velocity for a more dramatic breach effect
	pmat.initial_velocity_min = 80.0
	pmat.initial_velocity_max = 200.0


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
func _play_detonate_sound() -> void:
	if _detonate_audio_player and is_instance_valid(_detonate_audio_player):
		_detonate_audio_player.play()
