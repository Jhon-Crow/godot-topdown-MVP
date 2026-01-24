extends GutTest
## Unit tests for StatusEffectsManager autoload.
##
## Tests the status effects management functionality including blindness,
## stun effects, effect duration, and effect expiration.


# ============================================================================
# Mock Entity for Testing
# ============================================================================


class MockEntity:
	extends RefCounted

	var name: String = "TestEntity"
	var _is_blinded: bool = false
	var _is_stunned: bool = false
	var _instance_id: int

	func _init() -> void:
		_instance_id = randi()

	func get_instance_id() -> int:
		return _instance_id

	func set_blinded(value: bool) -> void:
		_is_blinded = value

	func set_stunned(value: bool) -> void:
		_is_stunned = value

	func is_blinded() -> bool:
		return _is_blinded

	func is_stunned() -> bool:
		return _is_stunned

	func has_method(method_name: String) -> bool:
		return method_name in ["set_blinded", "set_stunned"]


# ============================================================================
# Mock StatusEffectsManager for Logic Tests
# ============================================================================


class MockStatusEffectsManager:
	## Dictionary tracking active effects per entity.
	## Structure: { instance_id: { "blindness": float, "stun": float } }
	var _active_effects: Dictionary = {}

	## Track what effects were applied
	var blindness_applied: Array = []
	var stun_applied: Array = []
	var blindness_expired: Array = []
	var stun_expired: Array = []

	## Apply blindness effect to an entity.
	func apply_blindness(entity: Object, duration: float) -> void:
		if entity == null:
			return

		var entity_id: int = entity.get_instance_id()

		if not _active_effects.has(entity_id):
			_active_effects[entity_id] = {}

		var current_duration: float = _active_effects[entity_id].get("blindness", 0)
		_active_effects[entity_id]["blindness"] = maxf(current_duration, duration)

		if entity.has_method("set_blinded"):
			entity.set_blinded(true)

		blindness_applied.append({"entity_id": entity_id, "duration": duration})

	## Apply stun effect to an entity.
	func apply_stun(entity: Object, duration: float) -> void:
		if entity == null:
			return

		var entity_id: int = entity.get_instance_id()

		if not _active_effects.has(entity_id):
			_active_effects[entity_id] = {}

		var current_duration: float = _active_effects[entity_id].get("stun", 0)
		_active_effects[entity_id]["stun"] = maxf(current_duration, duration)

		if entity.has_method("set_stunned"):
			entity.set_stunned(true)

		stun_applied.append({"entity_id": entity_id, "duration": duration})

	## Update effects by reducing durations.
	func update_effects(delta: float, entities: Dictionary) -> void:
		var expired_entity_ids: Array = []

		for entity_id in _active_effects:
			var effects: Dictionary = _active_effects[entity_id]

			# Update blindness
			if effects.has("blindness") and effects["blindness"] > 0:
				effects["blindness"] -= delta
				if effects["blindness"] <= 0:
					effects["blindness"] = 0
					if entities.has(entity_id):
						_on_blindness_expired(entities[entity_id])

			# Update stun
			if effects.has("stun") and effects["stun"] > 0:
				effects["stun"] -= delta
				if effects["stun"] <= 0:
					effects["stun"] = 0
					if entities.has(entity_id):
						_on_stun_expired(entities[entity_id])

			# Check if all effects expired
			if effects.get("blindness", 0) <= 0 and effects.get("stun", 0) <= 0:
				expired_entity_ids.append(entity_id)

		# Clean up expired entities
		for entity_id in expired_entity_ids:
			_active_effects.erase(entity_id)

	## Called when blindness expires on an entity.
	func _on_blindness_expired(entity: Object) -> void:
		if entity == null:
			return

		if entity.has_method("set_blinded"):
			entity.set_blinded(false)

		blindness_expired.append(entity.get_instance_id())

	## Called when stun expires on an entity.
	func _on_stun_expired(entity: Object) -> void:
		if entity == null:
			return

		if entity.has_method("set_stunned"):
			entity.set_stunned(false)

		stun_expired.append(entity.get_instance_id())

	## Check if an entity is currently blinded.
	func is_blinded(entity: Object) -> bool:
		if entity == null:
			return false

		var entity_id: int = entity.get_instance_id()
		if _active_effects.has(entity_id):
			return _active_effects[entity_id].get("blindness", 0) > 0

		return false

	## Check if an entity is currently stunned.
	func is_stunned(entity: Object) -> bool:
		if entity == null:
			return false

		var entity_id: int = entity.get_instance_id()
		if _active_effects.has(entity_id):
			return _active_effects[entity_id].get("stun", 0) > 0

		return false

	## Get remaining blindness duration for an entity.
	func get_blindness_remaining(entity: Object) -> float:
		if entity == null:
			return 0.0

		var entity_id: int = entity.get_instance_id()
		if _active_effects.has(entity_id):
			return _active_effects[entity_id].get("blindness", 0)

		return 0.0

	## Get remaining stun duration for an entity.
	func get_stun_remaining(entity: Object) -> float:
		if entity == null:
			return 0.0

		var entity_id: int = entity.get_instance_id()
		if _active_effects.has(entity_id):
			return _active_effects[entity_id].get("stun", 0)

		return 0.0

	## Remove all effects from an entity.
	func clear_effects(entity: Object) -> void:
		if entity == null:
			return

		var entity_id: int = entity.get_instance_id()
		if _active_effects.has(entity_id):
			_active_effects.erase(entity_id)


var manager: MockStatusEffectsManager
var test_entity: MockEntity
var entities_by_id: Dictionary


func before_each() -> void:
	manager = MockStatusEffectsManager.new()
	test_entity = MockEntity.new()
	entities_by_id = {test_entity.get_instance_id(): test_entity}


func after_each() -> void:
	manager = null
	test_entity = null
	entities_by_id.clear()


# ============================================================================
# Initial State Tests
# ============================================================================


func test_no_active_effects_initially() -> void:
	assert_true(manager._active_effects.is_empty(),
		"Should have no active effects initially")


func test_entity_not_blinded_initially() -> void:
	assert_false(manager.is_blinded(test_entity),
		"Entity should not be blinded initially")


func test_entity_not_stunned_initially() -> void:
	assert_false(manager.is_stunned(test_entity),
		"Entity should not be stunned initially")


# ============================================================================
# Apply Blindness Tests
# ============================================================================


func test_apply_blindness_creates_effect() -> void:
	manager.apply_blindness(test_entity, 5.0)

	assert_true(manager.is_blinded(test_entity),
		"Entity should be blinded after applying blindness")


func test_apply_blindness_sets_correct_duration() -> void:
	manager.apply_blindness(test_entity, 5.0)

	assert_eq(manager.get_blindness_remaining(test_entity), 5.0,
		"Blindness duration should be set correctly")


func test_apply_blindness_calls_entity_method() -> void:
	manager.apply_blindness(test_entity, 5.0)

	assert_true(test_entity.is_blinded(),
		"Entity's set_blinded should be called")


func test_apply_blindness_extends_duration_if_longer() -> void:
	manager.apply_blindness(test_entity, 3.0)
	manager.apply_blindness(test_entity, 5.0)

	assert_eq(manager.get_blindness_remaining(test_entity), 5.0,
		"Longer blindness should extend duration")


func test_apply_blindness_does_not_reduce_duration_if_shorter() -> void:
	manager.apply_blindness(test_entity, 5.0)
	manager.apply_blindness(test_entity, 2.0)

	assert_eq(manager.get_blindness_remaining(test_entity), 5.0,
		"Shorter blindness should not reduce duration")


func test_apply_blindness_tracks_application() -> void:
	manager.apply_blindness(test_entity, 5.0)

	assert_eq(manager.blindness_applied.size(), 1)
	assert_eq(manager.blindness_applied[0]["duration"], 5.0)


func test_apply_blindness_null_entity_does_nothing() -> void:
	manager.apply_blindness(null, 5.0)

	assert_true(manager._active_effects.is_empty(),
		"Null entity should not create effects")


# ============================================================================
# Apply Stun Tests
# ============================================================================


func test_apply_stun_creates_effect() -> void:
	manager.apply_stun(test_entity, 3.0)

	assert_true(manager.is_stunned(test_entity),
		"Entity should be stunned after applying stun")


func test_apply_stun_sets_correct_duration() -> void:
	manager.apply_stun(test_entity, 3.0)

	assert_eq(manager.get_stun_remaining(test_entity), 3.0,
		"Stun duration should be set correctly")


func test_apply_stun_calls_entity_method() -> void:
	manager.apply_stun(test_entity, 3.0)

	assert_true(test_entity.is_stunned(),
		"Entity's set_stunned should be called")


func test_apply_stun_extends_duration_if_longer() -> void:
	manager.apply_stun(test_entity, 2.0)
	manager.apply_stun(test_entity, 4.0)

	assert_eq(manager.get_stun_remaining(test_entity), 4.0,
		"Longer stun should extend duration")


func test_apply_stun_does_not_reduce_duration_if_shorter() -> void:
	manager.apply_stun(test_entity, 4.0)
	manager.apply_stun(test_entity, 1.0)

	assert_eq(manager.get_stun_remaining(test_entity), 4.0,
		"Shorter stun should not reduce duration")


func test_apply_stun_null_entity_does_nothing() -> void:
	manager.apply_stun(null, 3.0)

	assert_true(manager._active_effects.is_empty(),
		"Null entity should not create effects")


# ============================================================================
# Multiple Effects Tests
# ============================================================================


func test_can_apply_both_blindness_and_stun() -> void:
	manager.apply_blindness(test_entity, 5.0)
	manager.apply_stun(test_entity, 3.0)

	assert_true(manager.is_blinded(test_entity))
	assert_true(manager.is_stunned(test_entity))


func test_both_effects_have_independent_durations() -> void:
	manager.apply_blindness(test_entity, 10.0)
	manager.apply_stun(test_entity, 5.0)

	assert_eq(manager.get_blindness_remaining(test_entity), 10.0)
	assert_eq(manager.get_stun_remaining(test_entity), 5.0)


# ============================================================================
# Effect Update Tests
# ============================================================================


func test_update_reduces_blindness_duration() -> void:
	manager.apply_blindness(test_entity, 5.0)
	manager.update_effects(1.0, entities_by_id)

	assert_eq(manager.get_blindness_remaining(test_entity), 4.0,
		"Blindness should be reduced by delta time")


func test_update_reduces_stun_duration() -> void:
	manager.apply_stun(test_entity, 3.0)
	manager.update_effects(1.0, entities_by_id)

	assert_eq(manager.get_stun_remaining(test_entity), 2.0,
		"Stun should be reduced by delta time")


func test_update_expires_blindness_at_zero() -> void:
	manager.apply_blindness(test_entity, 1.0)
	manager.update_effects(1.5, entities_by_id)

	assert_false(manager.is_blinded(test_entity),
		"Blindness should expire when duration reaches zero")


func test_update_expires_stun_at_zero() -> void:
	manager.apply_stun(test_entity, 1.0)
	manager.update_effects(1.5, entities_by_id)

	assert_false(manager.is_stunned(test_entity),
		"Stun should expire when duration reaches zero")


func test_blindness_expiration_calls_entity_method() -> void:
	manager.apply_blindness(test_entity, 1.0)
	manager.update_effects(1.5, entities_by_id)

	assert_false(test_entity.is_blinded(),
		"Entity's set_blinded(false) should be called on expiration")


func test_stun_expiration_calls_entity_method() -> void:
	manager.apply_stun(test_entity, 1.0)
	manager.update_effects(1.5, entities_by_id)

	assert_false(test_entity.is_stunned(),
		"Entity's set_stunned(false) should be called on expiration")


func test_update_tracks_blindness_expiration() -> void:
	manager.apply_blindness(test_entity, 1.0)
	manager.update_effects(1.5, entities_by_id)

	assert_eq(manager.blindness_expired.size(), 1)


func test_update_tracks_stun_expiration() -> void:
	manager.apply_stun(test_entity, 1.0)
	manager.update_effects(1.5, entities_by_id)

	assert_eq(manager.stun_expired.size(), 1)


func test_entity_removed_from_effects_when_all_expire() -> void:
	manager.apply_blindness(test_entity, 1.0)
	manager.update_effects(2.0, entities_by_id)

	assert_false(manager._active_effects.has(test_entity.get_instance_id()),
		"Entity should be removed from effects when all effects expire")


# ============================================================================
# Clear Effects Tests
# ============================================================================


func test_clear_effects_removes_all_effects() -> void:
	manager.apply_blindness(test_entity, 5.0)
	manager.apply_stun(test_entity, 3.0)
	manager.clear_effects(test_entity)

	assert_false(manager.is_blinded(test_entity))
	assert_false(manager.is_stunned(test_entity))


func test_clear_effects_removes_entity_from_tracking() -> void:
	manager.apply_blindness(test_entity, 5.0)
	manager.clear_effects(test_entity)

	assert_false(manager._active_effects.has(test_entity.get_instance_id()))


func test_clear_effects_null_entity_does_nothing() -> void:
	manager.apply_blindness(test_entity, 5.0)
	manager.clear_effects(null)

	# Should not crash and original effect should remain
	assert_true(manager.is_blinded(test_entity))


# ============================================================================
# Multiple Entities Tests
# ============================================================================


func test_effects_tracked_separately_per_entity() -> void:
	var entity2 := MockEntity.new()

	manager.apply_blindness(test_entity, 5.0)
	manager.apply_stun(entity2, 3.0)

	assert_true(manager.is_blinded(test_entity))
	assert_false(manager.is_stunned(test_entity))
	assert_false(manager.is_blinded(entity2))
	assert_true(manager.is_stunned(entity2))


func test_clearing_one_entity_does_not_affect_other() -> void:
	var entity2 := MockEntity.new()

	manager.apply_blindness(test_entity, 5.0)
	manager.apply_blindness(entity2, 5.0)
	manager.clear_effects(test_entity)

	assert_false(manager.is_blinded(test_entity))
	assert_true(manager.is_blinded(entity2))


# ============================================================================
# Edge Cases Tests
# ============================================================================


func test_get_remaining_duration_for_nonexistent_entity() -> void:
	var other_entity := MockEntity.new()

	assert_eq(manager.get_blindness_remaining(other_entity), 0.0)
	assert_eq(manager.get_stun_remaining(other_entity), 0.0)


func test_is_affected_for_nonexistent_entity() -> void:
	var other_entity := MockEntity.new()

	assert_false(manager.is_blinded(other_entity))
	assert_false(manager.is_stunned(other_entity))


func test_zero_duration_effect_immediately_expires() -> void:
	manager.apply_blindness(test_entity, 0.0)

	# Zero duration means not blinded
	assert_false(manager.is_blinded(test_entity),
		"Zero duration effect should not be active")


func test_very_small_delta_reduces_effect_correctly() -> void:
	manager.apply_blindness(test_entity, 1.0)
	manager.update_effects(0.001, entities_by_id)

	assert_almost_eq(manager.get_blindness_remaining(test_entity), 0.999, 0.0001,
		"Very small delta should reduce effect correctly")
