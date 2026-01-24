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


## Apply visual effect for blindness.
func _apply_blindness_visual(entity: Node2D) -> void:
	# Add a yellow/white overlay to indicate blindness
	if not entity.has_meta("_blindness_tint"):
		var sprite: Sprite2D = entity.get_node_or_null("Sprite2D")
		if sprite:
			entity.set_meta("_original_modulate", sprite.modulate)
			sprite.modulate = Color(1.0, 1.0, 0.5, 1.0)  # Yellow tint
			entity.set_meta("_blindness_tint", true)


## Remove visual effect for blindness.
func _remove_blindness_visual(entity: Object) -> void:
	if not is_instance_valid(entity) or not entity is Node2D:
		return

	if entity.has_meta("_blindness_tint"):
		var sprite: Sprite2D = entity.get_node_or_null("Sprite2D")
		if sprite and entity.has_meta("_original_modulate"):
			# Only restore if not still stunned
			if not is_stunned(entity):
				sprite.modulate = entity.get_meta("_original_modulate")
		entity.remove_meta("_blindness_tint")


## Apply visual effect for stun.
func _apply_stun_visual(entity: Node2D) -> void:
	# Add a blue overlay to indicate stun
	if not entity.has_meta("_stun_tint"):
		var sprite: Sprite2D = entity.get_node_or_null("Sprite2D")
		if sprite:
			if not entity.has_meta("_original_modulate"):
				entity.set_meta("_original_modulate", sprite.modulate)
			sprite.modulate = Color(0.5, 0.5, 1.0, 1.0)  # Blue tint
			entity.set_meta("_stun_tint", true)


## Remove visual effect for stun.
func _remove_stun_visual(entity: Object) -> void:
	if not is_instance_valid(entity) or not entity is Node2D:
		return

	if entity.has_meta("_stun_tint"):
		var sprite: Sprite2D = entity.get_node_or_null("Sprite2D")
		if sprite and entity.has_meta("_original_modulate"):
			# Only restore if not still blinded
			if not is_blinded(entity):
				sprite.modulate = entity.get_meta("_original_modulate")
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


## Remove all effects from an entity (used when entity dies or is removed).
func clear_effects(entity: Object) -> void:
	if not is_instance_valid(entity):
		return

	var entity_id := entity.get_instance_id()
	if _active_effects.has(entity_id):
		_remove_blindness_visual(entity)
		_remove_stun_visual(entity)
		_active_effects.erase(entity_id)
