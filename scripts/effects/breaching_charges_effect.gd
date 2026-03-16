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

## Current number of charges remaining.
var charges: int = MAX_CHARGES

## Whether a charge is currently placed on a wall (waiting for detonation).
var has_placed_charge: bool = false

## The wall node that has a charge placed on it.
var _charged_wall: Node = null

## World position where the charge was placed.
var _charge_position: Vector2 = Vector2.ZERO

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
	FileLogger.info("[BreachingCharges] Initialized with player: %s, charges: %d/%d" % [
		player.name, charges, MAX_CHARGES
	])


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
	var wall := _find_nearest_wall()
	if wall == null:
		FileLogger.info("[BreachingCharges] No wall found within %.0f px" % PLACEMENT_RADIUS)
		return false

	# Attach charge to the wall
	charges -= 1
	has_placed_charge = true
	_charged_wall = wall
	_charge_position = _player.global_position

	FileLogger.info("[BreachingCharges] Charge placed on wall '%s' at %s. Charges remaining: %d/%d" % [
		wall.name, str(_charge_position), charges, MAX_CHARGES
	])

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
	var wall := _charged_wall

	# Clear state before applying effects (prevent double-detonation)
	has_placed_charge = false
	_charged_wall = null
	_charge_position = Vector2.ZERO

	FileLogger.info("[BreachingCharges] Detonating at %s" % str(det_pos))

	# Disable the wall's collision to create a passage
	_open_wall_passage(wall)

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
## Returns null if none found.
func _find_nearest_wall() -> Node:
	if _player == null:
		return null

	var space_state := _player.get_world_2d().direct_space_state
	if space_state == null:
		FileLogger.info("[BreachingCharges] WARNING: Could not get physics space state")
		return null

	# Cast a short ray in each cardinal + diagonal direction to find a wall surface
	var directions := [
		Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN,
		Vector2(1, 1).normalized(), Vector2(-1, 1).normalized(),
		Vector2(1, -1).normalized(), Vector2(-1, -1).normalized()
	]

	var player_pos := _player.global_position
	var nearest_wall: Node = null
	var nearest_dist: float = PLACEMENT_RADIUS + 1.0

	for dir in directions:
		var query := PhysicsRayQueryParameters2D.create(
			player_pos,
			player_pos + dir * PLACEMENT_RADIUS,
			1 << (WALL_COLLISION_LAYER - 1)  # Layer 4 = bit 3
		)
		query.exclude = [_player.get_rid()]
		var result := space_state.intersect_ray(query)

		if result.size() > 0 and result.has("collider"):
			var collider: Node = result["collider"]
			var dist: float = player_pos.distance_to(result["position"])
			if dist < nearest_dist:
				nearest_dist = dist
				nearest_wall = collider

	return nearest_wall


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
