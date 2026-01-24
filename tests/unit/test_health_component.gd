extends GutTest
## Unit tests for HealthComponent.
##
## Tests the health management functionality including damage, healing,
## death handling, visual feedback, and health percentage calculations.


# ============================================================================
# Mock HealthComponent for Logic Tests
# ============================================================================


class MockHealthComponent:
	## Minimum health value (for random initialization)
	var min_health: int = 2

	## Maximum health value (for random initialization)
	var max_health: int = 4

	## Whether to randomize health between min and max on ready
	var randomize_on_ready: bool = true

	## Color when at full health
	var full_health_color: Color = Color(0.9, 0.2, 0.2, 1.0)

	## Color when at low health
	var low_health_color: Color = Color(0.3, 0.1, 0.1, 1.0)

	## Color to flash when hit
	var hit_flash_color: Color = Color(1.0, 1.0, 1.0, 1.0)

	## Duration of hit flash effect in seconds
	var hit_flash_duration: float = 0.1

	## Current health
	var _current_health: int = 0

	## Maximum health (set at initialization)
	var _max_health: int = 0

	## Whether the entity is alive
	var _is_alive: bool = true

	## Signal tracking
	var hit_emitted: int = 0
	var health_changed_emitted: Array = []
	var died_emitted: int = 0

	## Initialize health with random value between min and max
	func initialize_health() -> void:
		_max_health = randi_range(min_health, max_health)
		_current_health = _max_health
		_is_alive = true

	## Initialize health with specific value
	func set_max_health(value: int) -> void:
		_max_health = value
		_current_health = value
		_is_alive = true

	## Apply damage to the entity
	func take_damage(amount: int = 1) -> void:
		take_damage_with_info(amount, Vector2.RIGHT, null)

	## Apply damage to the entity with extended hit information
	func take_damage_with_info(amount: int, _hit_direction: Vector2, _caliber_data: Resource) -> void:
		if not _is_alive:
			return

		hit_emitted += 1

		_current_health -= amount
		health_changed_emitted.append({"current": _current_health, "max": _max_health})

		if _current_health <= 0:
			_current_health = 0
			_on_death()

	## Heal the entity
	func heal(amount: int) -> void:
		if not _is_alive:
			return

		_current_health = mini(_current_health + amount, _max_health)
		health_changed_emitted.append({"current": _current_health, "max": _max_health})

	## Handle death
	func _on_death() -> void:
		_is_alive = false
		died_emitted += 1

	## Reset health to max (for respawn)
	func reset() -> void:
		initialize_health()

	## Get current health
	func get_current_health() -> int:
		return _current_health

	## Get maximum health
	func get_max_health() -> int:
		return _max_health

	## Get health as percentage (0.0 to 1.0)
	func get_health_percent() -> float:
		if _max_health <= 0:
			return 0.0
		return float(_current_health) / float(_max_health)

	## Check if alive
	func is_alive() -> bool:
		return _is_alive


var health: MockHealthComponent


func before_each() -> void:
	health = MockHealthComponent.new()


func after_each() -> void:
	health = null


# ============================================================================
# Initialization Tests
# ============================================================================


func test_default_min_health() -> void:
	assert_eq(health.min_health, 2,
		"Default min health should be 2")


func test_default_max_health() -> void:
	assert_eq(health.max_health, 4,
		"Default max health should be 4")


func test_initialize_health_sets_current_to_max() -> void:
	health.set_max_health(5)

	assert_eq(health.get_current_health(), 5)
	assert_eq(health.get_max_health(), 5)


func test_initialize_health_sets_alive_true() -> void:
	health.set_max_health(5)

	assert_true(health.is_alive())


func test_set_max_health_specific_value() -> void:
	health.set_max_health(10)

	assert_eq(health.get_max_health(), 10)
	assert_eq(health.get_current_health(), 10)


func test_random_health_within_range() -> void:
	# Test multiple times to ensure randomization stays in range
	for _i in range(20):
		health.initialize_health()
		assert_true(health.get_max_health() >= 2,
			"Random health should be >= min_health")
		assert_true(health.get_max_health() <= 4,
			"Random health should be <= max_health")


# ============================================================================
# Damage Tests
# ============================================================================


func test_take_damage_reduces_health() -> void:
	health.set_max_health(5)
	health.take_damage(1)

	assert_eq(health.get_current_health(), 4)


func test_take_damage_emits_hit_signal() -> void:
	health.set_max_health(5)
	health.take_damage(1)

	assert_eq(health.hit_emitted, 1)


func test_take_damage_emits_health_changed() -> void:
	health.set_max_health(5)
	health.take_damage(1)

	assert_eq(health.health_changed_emitted.size(), 1)
	assert_eq(health.health_changed_emitted[0]["current"], 4)
	assert_eq(health.health_changed_emitted[0]["max"], 5)


func test_take_damage_multiple_times() -> void:
	health.set_max_health(5)
	health.take_damage(1)
	health.take_damage(2)

	assert_eq(health.get_current_health(), 2)
	assert_eq(health.hit_emitted, 2)


func test_take_damage_cannot_go_below_zero() -> void:
	health.set_max_health(3)
	health.take_damage(10)

	assert_eq(health.get_current_health(), 0)


func test_take_damage_kills_when_reaches_zero() -> void:
	health.set_max_health(3)
	health.take_damage(3)

	assert_false(health.is_alive())
	assert_eq(health.died_emitted, 1)


func test_take_damage_does_nothing_when_dead() -> void:
	health.set_max_health(3)
	health.take_damage(3)  # Dies

	var hit_count_before := health.hit_emitted
	health.take_damage(1)  # Should do nothing

	assert_eq(health.hit_emitted, hit_count_before,
		"Should not emit hit when already dead")


func test_take_damage_with_info_uses_direction() -> void:
	health.set_max_health(5)
	health.take_damage_with_info(1, Vector2.LEFT, null)

	assert_eq(health.get_current_health(), 4)


# ============================================================================
# Healing Tests
# ============================================================================


func test_heal_increases_health() -> void:
	health.set_max_health(5)
	health.take_damage(2)
	health.heal(1)

	assert_eq(health.get_current_health(), 4)


func test_heal_cannot_exceed_max() -> void:
	health.set_max_health(5)
	health.take_damage(1)
	health.heal(10)

	assert_eq(health.get_current_health(), 5)


func test_heal_emits_health_changed() -> void:
	health.set_max_health(5)
	health.take_damage(2)

	var count_before := health.health_changed_emitted.size()
	health.heal(1)

	assert_eq(health.health_changed_emitted.size(), count_before + 1)


func test_heal_does_nothing_when_dead() -> void:
	health.set_max_health(3)
	health.take_damage(3)  # Dies

	health.heal(5)

	assert_eq(health.get_current_health(), 0,
		"Should not heal when dead")
	assert_false(health.is_alive())


func test_heal_at_full_health() -> void:
	health.set_max_health(5)
	health.heal(5)

	assert_eq(health.get_current_health(), 5,
		"Health should stay at max when healing at full")


# ============================================================================
# Health Percentage Tests
# ============================================================================


func test_health_percent_full() -> void:
	health.set_max_health(5)

	assert_eq(health.get_health_percent(), 1.0)


func test_health_percent_half() -> void:
	health.set_max_health(10)
	health.take_damage(5)

	assert_eq(health.get_health_percent(), 0.5)


func test_health_percent_empty() -> void:
	health.set_max_health(5)
	health.take_damage(5)

	assert_eq(health.get_health_percent(), 0.0)


func test_health_percent_zero_max_health() -> void:
	# Edge case: max health is 0
	health._max_health = 0
	health._current_health = 0

	assert_eq(health.get_health_percent(), 0.0,
		"Should return 0 when max health is 0 (avoid division by zero)")


func test_health_percent_partial() -> void:
	health.set_max_health(4)
	health.take_damage(1)

	assert_eq(health.get_health_percent(), 0.75)


# ============================================================================
# Reset Tests
# ============================================================================


func test_reset_restores_health() -> void:
	health.set_max_health(5)
	health.take_damage(3)
	health.reset()

	# After reset, health should be randomized within min/max range
	assert_true(health.get_current_health() >= health.min_health)
	assert_true(health.get_current_health() <= health.max_health)


func test_reset_revives_dead_entity() -> void:
	health.set_max_health(3)
	health.take_damage(3)  # Dies

	assert_false(health.is_alive())

	health.reset()

	assert_true(health.is_alive())


# ============================================================================
# Death Tests
# ============================================================================


func test_death_at_exactly_zero() -> void:
	health.set_max_health(3)
	health.take_damage(3)

	assert_false(health.is_alive())
	assert_eq(health.get_current_health(), 0)


func test_death_emits_died_signal() -> void:
	health.set_max_health(3)
	health.take_damage(5)

	assert_eq(health.died_emitted, 1)


func test_overkill_damage_only_dies_once() -> void:
	health.set_max_health(3)
	health.take_damage(100)

	assert_eq(health.died_emitted, 1,
		"Should only die once even with massive damage")


# ============================================================================
# Color Constants Tests
# ============================================================================


func test_full_health_color_default() -> void:
	assert_eq(health.full_health_color, Color(0.9, 0.2, 0.2, 1.0))


func test_low_health_color_default() -> void:
	assert_eq(health.low_health_color, Color(0.3, 0.1, 0.1, 1.0))


func test_hit_flash_color_default() -> void:
	assert_eq(health.hit_flash_color, Color(1.0, 1.0, 1.0, 1.0))


func test_hit_flash_duration_default() -> void:
	assert_eq(health.hit_flash_duration, 0.1)


# ============================================================================
# Edge Cases Tests
# ============================================================================


func test_damage_amount_zero() -> void:
	health.set_max_health(5)
	health.take_damage(0)

	assert_eq(health.get_current_health(), 5,
		"Zero damage should not reduce health")


func test_heal_amount_zero() -> void:
	health.set_max_health(5)
	health.take_damage(2)
	health.heal(0)

	assert_eq(health.get_current_health(), 3,
		"Zero heal should not change health")


func test_negative_damage_treated_as_damage() -> void:
	# Note: This is testing current implementation behavior
	# Negative damage would actually heal, but take_damage should
	# probably validate input in a real implementation
	health.set_max_health(5)
	health.take_damage(-2)

	# Current implementation would increase health
	assert_eq(health.get_current_health(), 7,
		"Negative damage increases health (edge case)")


func test_very_large_damage() -> void:
	health.set_max_health(5)
	health.take_damage(999999)

	assert_eq(health.get_current_health(), 0)
	assert_false(health.is_alive())


func test_very_large_heal() -> void:
	health.set_max_health(5)
	health.take_damage(2)
	health.heal(999999)

	assert_eq(health.get_current_health(), 5,
		"Heal should cap at max health")
