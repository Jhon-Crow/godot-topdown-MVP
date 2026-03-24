extends GutTest
## Tests for EnemyShieldComponent (Issue #1242).
##
## Validates shield HP, stun/stagger constants, sniper penetration threshold,
## speed/rotation multipliers, and shield break/raise logic.

const ShieldComponent := preload("res://scripts/components/enemy_shield_component.gd")


## Mock caliber data resource for testing sniper penetration.
class MockCaliberData extends Resource:
	var penetration_power: float = 0.0
	var _can_penetrate: bool = false

	func can_penetrate_walls() -> bool:
		return _can_penetrate


## Mock parent enemy with velocity and knockback support.
class MockShieldEnemy extends Node2D:
	var velocity: Vector2 = Vector2.ZERO
	var _flashbang_blind: float = 0.0
	var _flashbang_stun: float = 0.0
	var _stunned: bool = false
	var _blinded: bool = false

	func apply_knockback(impulse: Vector2) -> void:
		velocity += impulse

	func apply_flashbang_effect(blind_dur: float, stun_dur: float) -> void:
		_flashbang_blind = blind_dur
		_flashbang_stun = stun_dur

	func set_stunned(val: bool) -> void:
		_stunned = val

	func set_blinded(val: bool) -> void:
		_blinded = val


# =============================================================================
# Constants
# =============================================================================

func test_shield_hp_constant() -> void:
	assert_eq(ShieldComponent.SHIELD_HP, 20, "SHIELD_HP should be 20")


func test_stun_duration_constant() -> void:
	assert_eq(ShieldComponent.STUN_DURATION, 1.0, "STUN_DURATION should be 1.0 seconds")


func test_stagger_impulse_constant() -> void:
	assert_eq(ShieldComponent.STAGGER_IMPULSE, 200.0, "STAGGER_IMPULSE should be 200.0")


func test_sniper_penetration_threshold_constant() -> void:
	assert_eq(ShieldComponent.SNIPER_PENETRATION_THRESHOLD, 80.0,
		"SNIPER_PENETRATION_THRESHOLD should be 80.0")


func test_shield_speed_multiplier_constant() -> void:
	assert_eq(ShieldComponent.SHIELD_SPEED_MULTIPLIER, 0.5,
		"SHIELD_SPEED_MULTIPLIER should be 0.5")


func test_shield_rotation_multiplier_constant() -> void:
	assert_eq(ShieldComponent.SHIELD_ROTATION_MULTIPLIER, 0.15,
		"SHIELD_ROTATION_MULTIPLIER should be 0.15")


func test_formation_radius_constant() -> void:
	assert_eq(ShieldComponent.FORMATION_RADIUS, 350.0,
		"FORMATION_RADIUS should be 350.0")


func test_formation_offset_constant() -> void:
	assert_eq(ShieldComponent.FORMATION_OFFSET, 80.0,
		"FORMATION_OFFSET should be 80.0")


# =============================================================================
# Initial State
# =============================================================================

func test_initial_state_shield_up() -> void:
	var comp := ShieldComponent.new()
	var parent := MockShieldEnemy.new()
	parent.add_child(comp)
	add_child_autofree(parent)

	assert_true(comp._shield_up, "Shield should start up")
	assert_eq(comp._shield_current_hp, ShieldComponent.SHIELD_HP,
		"Shield HP should start at SHIELD_HP")
	assert_false(comp._recovering, "Should not be recovering initially")
	assert_eq(comp._stun_timer, 0.0, "Stun timer should be 0.0 initially")


# =============================================================================
# Speed / Rotation Multipliers
# =============================================================================

func test_speed_multiplier_shield_up() -> void:
	var comp := ShieldComponent.new()
	var parent := MockShieldEnemy.new()
	parent.add_child(comp)
	add_child_autofree(parent)

	comp._shield_up = true
	assert_eq(comp.get_speed_multiplier(), ShieldComponent.SHIELD_SPEED_MULTIPLIER,
		"Speed multiplier should be SHIELD_SPEED_MULTIPLIER when shield is up")


func test_speed_multiplier_shield_down() -> void:
	var comp := ShieldComponent.new()
	var parent := MockShieldEnemy.new()
	parent.add_child(comp)
	add_child_autofree(parent)

	comp._shield_up = false
	assert_eq(comp.get_speed_multiplier(), 1.0,
		"Speed multiplier should be 1.0 when shield is down")


func test_rotation_multiplier_shield_up() -> void:
	var comp := ShieldComponent.new()
	var parent := MockShieldEnemy.new()
	parent.add_child(comp)
	add_child_autofree(parent)

	comp._shield_up = true
	assert_eq(comp.get_rotation_multiplier(), ShieldComponent.SHIELD_ROTATION_MULTIPLIER,
		"Rotation multiplier should be SHIELD_ROTATION_MULTIPLIER when shield is up")


func test_rotation_multiplier_shield_down() -> void:
	var comp := ShieldComponent.new()
	var parent := MockShieldEnemy.new()
	parent.add_child(comp)
	add_child_autofree(parent)

	comp._shield_up = false
	assert_eq(comp.get_rotation_multiplier(), 1.0,
		"Rotation multiplier should be 1.0 when shield is down")


# =============================================================================
# is_active
# =============================================================================

func test_is_active_when_shield_up() -> void:
	var comp := ShieldComponent.new()
	var parent := MockShieldEnemy.new()
	parent.add_child(comp)
	add_child_autofree(parent)

	comp._shield_up = true
	assert_true(comp.is_active(), "is_active should return true when shield is up")


func test_is_active_when_shield_down() -> void:
	var comp := ShieldComponent.new()
	var parent := MockShieldEnemy.new()
	parent.add_child(comp)
	add_child_autofree(parent)

	comp._shield_up = false
	assert_false(comp.is_active(), "is_active should return false when shield is down")


# =============================================================================
# Shield Break Logic
# =============================================================================

func test_break_shield_sets_recovering_state() -> void:
	var comp := ShieldComponent.new()
	var parent := MockShieldEnemy.new()
	parent.add_child(comp)
	add_child_autofree(parent)
	comp._parent = parent

	comp._break_shield(Vector2.RIGHT)

	assert_false(comp._shield_up, "Shield should be down after break")
	assert_eq(comp._shield_current_hp, 0, "Shield HP should be 0 after break")
	assert_true(comp._recovering, "Should be recovering after break")
	assert_eq(comp._stun_timer, ShieldComponent.STUN_DURATION,
		"Stun timer should be set to STUN_DURATION")


func test_break_shield_applies_knockback() -> void:
	var comp := ShieldComponent.new()
	var parent := MockShieldEnemy.new()
	parent.add_child(comp)
	add_child_autofree(parent)
	comp._parent = parent

	comp._break_shield(Vector2.RIGHT)

	assert_ne(parent.velocity, Vector2.ZERO,
		"Knockback should be applied to parent velocity")


func test_break_shield_applies_flashbang_effect() -> void:
	var comp := ShieldComponent.new()
	var parent := MockShieldEnemy.new()
	parent.add_child(comp)
	add_child_autofree(parent)
	comp._parent = parent

	comp._break_shield(Vector2.RIGHT)

	assert_eq(parent._flashbang_blind, ShieldComponent.STUN_DURATION,
		"Flashbang blind should be set to STUN_DURATION")
	assert_eq(parent._flashbang_stun, ShieldComponent.STUN_DURATION,
		"Flashbang stun should be set to STUN_DURATION")


# =============================================================================
# Shield Raise After Recovery
# =============================================================================

func test_update_recovers_shield_after_stun_timer() -> void:
	var comp := ShieldComponent.new()
	var parent := MockShieldEnemy.new()
	parent.add_child(comp)
	add_child_autofree(parent)
	comp._parent = parent

	comp._shield_up = false
	comp._recovering = true
	comp._stun_timer = 0.5

	# Tick past stun timer
	comp.update(1.0)

	assert_true(comp._shield_up, "Shield should be raised after stun expires")
	assert_false(comp._recovering, "Should no longer be recovering")
	assert_eq(comp._shield_current_hp, ShieldComponent.SHIELD_HP,
		"Shield HP should reset to SHIELD_HP after raise")


func test_update_stun_timer_decrements() -> void:
	var comp := ShieldComponent.new()
	var parent := MockShieldEnemy.new()
	parent.add_child(comp)
	add_child_autofree(parent)
	comp._parent = parent

	comp._recovering = true
	comp._stun_timer = 1.0

	comp.update(0.3)

	assert_almost_eq(comp._stun_timer, 0.7, 0.01,
		"Stun timer should decrement by delta")
	assert_true(comp._recovering, "Should still be recovering")


# =============================================================================
# Sniper Penetration
# =============================================================================

func test_sniper_round_bypasses_shield() -> void:
	var comp := ShieldComponent.new()
	var parent := MockShieldEnemy.new()
	parent.add_child(comp)
	add_child_autofree(parent)
	comp._parent = parent

	var caliber := MockCaliberData.new()
	caliber.penetration_power = 100.0
	caliber._can_penetrate = true

	var blocked := comp.try_intercept_hit(caliber, 50.0, Vector2.RIGHT)
	assert_false(blocked, "Sniper round should bypass shield (penetration >= threshold)")


func test_regular_round_blocked_by_shield() -> void:
	var comp := ShieldComponent.new()
	var parent := MockShieldEnemy.new()
	parent.add_child(comp)
	add_child_autofree(parent)
	comp._parent = parent

	var caliber := MockCaliberData.new()
	caliber.penetration_power = 20.0
	caliber._can_penetrate = false

	var blocked := comp.try_intercept_hit(caliber, 5.0, Vector2.RIGHT)
	assert_true(blocked, "Regular round should be blocked by shield")


func test_intercept_reduces_shield_hp() -> void:
	var comp := ShieldComponent.new()
	var parent := MockShieldEnemy.new()
	parent.add_child(comp)
	add_child_autofree(parent)
	comp._parent = parent

	var caliber := MockCaliberData.new()
	caliber.penetration_power = 10.0
	caliber._can_penetrate = false

	var hp_before := comp._shield_current_hp
	comp.try_intercept_hit(caliber, 5.0, Vector2.RIGHT)

	assert_lt(comp._shield_current_hp, hp_before,
		"Shield HP should decrease after absorbing a hit")


func test_intercept_breaks_shield_when_hp_depleted() -> void:
	var comp := ShieldComponent.new()
	var parent := MockShieldEnemy.new()
	parent.add_child(comp)
	add_child_autofree(parent)
	comp._parent = parent

	var caliber := MockCaliberData.new()
	caliber.penetration_power = 10.0
	caliber._can_penetrate = false

	comp._shield_current_hp = 3
	comp.try_intercept_hit(caliber, 5.0, Vector2.RIGHT)

	assert_false(comp._shield_up, "Shield should break when HP depleted")
	assert_true(comp._recovering, "Should start recovering after break")


func test_intercept_fails_when_shield_down() -> void:
	var comp := ShieldComponent.new()
	var parent := MockShieldEnemy.new()
	parent.add_child(comp)
	add_child_autofree(parent)
	comp._parent = parent

	comp._shield_up = false

	var caliber := MockCaliberData.new()
	caliber.penetration_power = 10.0

	var blocked := comp.try_intercept_hit(caliber, 5.0, Vector2.RIGHT)
	assert_false(blocked, "Should not intercept when shield is down")


func test_null_caliber_does_not_bypass_shield() -> void:
	var comp := ShieldComponent.new()
	var parent := MockShieldEnemy.new()
	parent.add_child(comp)
	add_child_autofree(parent)
	comp._parent = parent

	var blocked := comp.try_intercept_hit(null, 5.0, Vector2.RIGHT)
	assert_true(blocked, "Null caliber should not bypass shield (treated as non-sniper)")
