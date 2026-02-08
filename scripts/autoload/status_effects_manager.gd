extends Node
## Manages status effects applied to game entities.
##
## Currently supports:
## - Blindness: Target cannot see the player
## - Stun: Target cannot move
##
## Effects are tracked per-entity and automatically expire after duration.

## Dictionary tracking active effects per entity.
## Structure: { instance_id: { "blindness": float, "stun": float } }
var _active_effects: Dictionary = {}


func _physics_process(delta: float) -> void:
	_update_effects(delta)


## Update all active effects, reducing durations and removing expired ones.
func _update_effects(delta: float) -> void:
	var expired_entities: Array = []

	for entity_id in _active_effects:
		var effects: Dictionary = _active_effects[entity_id]
		var entity: Object = instance_from_id(entity_id)

		# Check if entity still exists
		if not is_instance_valid(entity):
			expired_entities.append(entity_id)
			continue

		# Update blindness
		if effects.has("blindness") and effects["blindness"] > 0:
			effects["blindness"] -= delta
			if effects["blindness"] <= 0:
				effects["blindness"] = 0
				_on_blindness_expired(entity)

		# Update stun
		if effects.has("stun") and effects["stun"] > 0:
			effects["stun"] -= delta
			if effects["stun"] <= 0:
				effects["stun"] = 0
				_on_stun_expired(entity)

		# Check if all effects expired
		if effects.get("blindness", 0) <= 0 and effects.get("stun", 0) <= 0:
			expired_entities.append(entity_id)

	# Clean up expired entities
	for entity_id in expired_entities:
		_active_effects.erase(entity_id)


## Apply blindness effect to an entity.
## @param entity: The entity to blind (typically an enemy).
## @param duration: Duration of the blindness in seconds.
func apply_blindness(entity: Node2D, duration: float) -> void:
	if not is_instance_valid(entity):
		return

	var entity_id := entity.get_instance_id()

	# Initialize effects dictionary if needed
	if not _active_effects.has(entity_id):
		_active_effects[entity_id] = {}

	# Set or extend blindness duration (take the longer one)
	var current_duration: float = _active_effects[entity_id].get("blindness", 0)
	_active_effects[entity_id]["blindness"] = maxf(current_duration, duration)

	# Apply the visual effect to the entity
	_apply_blindness_visual(entity)

	# Notify the entity of blindness
	if entity.has_method("set_blinded"):
		entity.set_blinded(true)
	elif entity.has_meta("_can_see_player"):
		entity.set_meta("_original_can_see", entity.get("_can_see_player"))
		entity.set("_can_see_player", false)

	print("[StatusEffectsManager] Applied blindness to %s for %.1fs" % [entity.name, duration])


## Apply stun effect to an entity.
## @param entity: The entity to stun (typically an enemy).
## @param duration: Duration of the stun in seconds.
func apply_stun(entity: Node2D, duration: float) -> void:
	if not is_instance_valid(entity):
		return

	var entity_id := entity.get_instance_id()

	# Initialize effects dictionary if needed
	if not _active_effects.has(entity_id):
		_active_effects[entity_id] = {}

	# Set or extend stun duration (take the longer one)
	var current_duration: float = _active_effects[entity_id].get("stun", 0)
	_active_effects[entity_id]["stun"] = maxf(current_duration, duration)

	# Apply the visual effect to the entity
	_apply_stun_visual(entity)

	# Notify the entity of stun
	if entity.has_method("set_stunned"):
		entity.set_stunned(true)

	print("[StatusEffectsManager] Applied stun to %s for %.1fs" % [entity.name, duration])


## Called when blindness expires on an entity.
func _on_blindness_expired(entity: Object) -> void:
	if not is_instance_valid(entity):
		return

	# Restore visual
	_remove_blindness_visual(entity)

	# Notify the entity
	if entity.has_method("set_blinded"):
		entity.set_blinded(false)

	print("[StatusEffectsManager] Blindness expired on %s" % [entity.name if entity is Node else str(entity)])


## Called when stun expires on an entity.
func _on_stun_expired(entity: Object) -> void:
	if not is_instance_valid(entity):
		return

	# Restore visual
	_remove_stun_visual(entity)

	# Notify the entity
	if entity.has_method("set_stunned"):
		entity.set_stunned(false)

	print("[StatusEffectsManager] Stun expired on %s" % [entity.name if entity is Node else str(entity)])


## Apply tint color to entity, supporting both single-sprite and modular-sprite entities.
## Entities with _set_all_sprites_modulate() (e.g. enemies with Body/Head/Arms) use that method.
## Fallback: uses _find_sprite() to locate a single sprite.
func _apply_tint(entity: Node2D, color: Color) -> void:
	if entity.has_method("_set_all_sprites_modulate"):
		entity._set_all_sprites_modulate(color)
	else:
		var sprite: Sprite2D = _find_sprite(entity)
		if sprite:
			sprite.modulate = color


## Save the current modulate color before applying status tints.
func _save_original_modulate(entity: Node2D) -> void:
	if not entity.has_meta("_original_modulate"):
		if entity.has_method("_set_all_sprites_modulate"):
			# For modular sprites, read from body sprite
			var body: Sprite2D = entity.get_node_or_null("EnemyModel/Body")
			if body:
				entity.set_meta("_original_modulate", body.modulate)
		else:
			var sprite: Sprite2D = _find_sprite(entity)
			if sprite:
				entity.set_meta("_original_modulate", sprite.modulate)


## Restore original modulate color on entity.
func _restore_original_modulate(entity: Node2D) -> void:
	if entity.has_meta("_original_modulate"):
		_apply_tint(entity, entity.get_meta("_original_modulate"))


## Apply visual effect for blindness.
func _apply_blindness_visual(entity: Node2D) -> void:
	if not entity.has_meta("_blindness_tint"):
		_save_original_modulate(entity)
		_apply_tint(entity, Color(1.0, 1.0, 0.5, 1.0))  # Yellow tint
		entity.set_meta("_blindness_tint", true)


## Remove visual effect for blindness.
func _remove_blindness_visual(entity: Object) -> void:
	if not is_instance_valid(entity) or not entity is Node2D:
		return

	if entity.has_meta("_blindness_tint"):
		if not is_stunned(entity):
			_restore_original_modulate(entity)
		entity.remove_meta("_blindness_tint")


## Apply visual effect for stun.
func _apply_stun_visual(entity: Node2D) -> void:
	if not entity.has_meta("_stun_tint"):
		_save_original_modulate(entity)
		_apply_tint(entity, Color(0.5, 0.5, 1.0, 1.0))  # Blue tint
		entity.set_meta("_stun_tint", true)


## Remove visual effect for stun.
func _remove_stun_visual(entity: Object) -> void:
	if not is_instance_valid(entity) or not entity is Node2D:
		return

	if entity.has_meta("_stun_tint"):
		if not is_blinded(entity):
			_restore_original_modulate(entity)
		entity.remove_meta("_stun_tint")


## Check if an entity is currently blinded.
func is_blinded(entity: Object) -> bool:
	if not is_instance_valid(entity):
		return false

	var entity_id := entity.get_instance_id()
	if _active_effects.has(entity_id):
		return _active_effects[entity_id].get("blindness", 0) > 0

	return false


## Check if an entity is currently stunned.
func is_stunned(entity: Object) -> bool:
	if not is_instance_valid(entity):
		return false

	var entity_id := entity.get_instance_id()
	if _active_effects.has(entity_id):
		return _active_effects[entity_id].get("stun", 0) > 0

	return false


## Get remaining blindness duration for an entity.
func get_blindness_remaining(entity: Object) -> float:
	if not is_instance_valid(entity):
		return 0.0

	var entity_id := entity.get_instance_id()
	if _active_effects.has(entity_id):
		return _active_effects[entity_id].get("blindness", 0)

	return 0.0


## Get remaining stun duration for an entity.
func get_stun_remaining(entity: Object) -> float:
	if not is_instance_valid(entity):
		return 0.0

	var entity_id := entity.get_instance_id()
	if _active_effects.has(entity_id):
		return _active_effects[entity_id].get("stun", 0)

	return 0.0


## Find the main body sprite on an entity.
## Enemies use EnemyModel/Body structure instead of a direct Sprite2D child.
func _find_sprite(entity: Node) -> Sprite2D:
	if not is_instance_valid(entity):
		return null
	# Try direct Sprite2D child first (generic entities)
	var sprite: Sprite2D = entity.get_node_or_null("Sprite2D")
	if sprite:
		return sprite
	# Try EnemyModel/Body (enemy structure)
	sprite = entity.get_node_or_null("EnemyModel/Body")
	if sprite:
		return sprite
	return null


## Remove all effects from an entity (used when entity dies or is removed).
func clear_effects(entity: Object) -> void:
	if not is_instance_valid(entity):
		return

	var entity_id := entity.get_instance_id()
	if _active_effects.has(entity_id):
		_remove_blindness_visual(entity)
		_remove_stun_visual(entity)
		_active_effects.erase(entity_id)
