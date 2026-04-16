extends GutTest
## Unit tests for RPG rocket exploding when hit by bullets (Issue #1307).
##
## Tests that incoming bullets trigger on_hit() which causes the rocket to
## explode (full AOE explosion), not silently self-destruct.
## Uses a mock that mirrors the on_hit → _rpg_explode logic in bullet.gd.


# ============================================================================
# Mock RPG Rocket — mirrors bullet.gd on_hit / explosion logic (Issue #1307)
# ============================================================================


class MockRpgRocket:
	## Whether the rocket has been flagged as RPG.
	var is_rpg_rocket: bool = true

	## Health points — when 0, next on_hit triggers explosion.
	var rpg_health: int = 1

	## Current health (decremented on each on_hit call).
	var _rpg_current_health: int = 1

	## Whether the rocket has exploded (prevents double-processing).
	var _rpg_has_exploded: bool = false

	## Whether _rpg_explode was called (for assertions).
	var exploded: bool = false

	## Whether _rpg_intercept was called (should NOT happen with fix).
	var intercepted: bool = false

	## Global position for logging.
	var global_position: Vector2 = Vector2(100.0, 200.0)

	## Collision layer (layer 5 = bit 16).
	var collision_layer: int = 16


	func _init(health: int = 1) -> void:
		rpg_health = health
		_rpg_current_health = health


	## Mirrors bullet.gd on_hit() — Issue #1307 fix: calls _rpg_explode.
	func on_hit() -> void:
		if not is_rpg_rocket or _rpg_has_exploded:
			return
		if rpg_health <= 0:
			return
		_rpg_current_health -= 1
		if _rpg_current_health <= 0:
			_rpg_explode()


	## Mirrors bullet.gd on_hit_with_info.
	func on_hit_with_info(_hit_direction: Vector2, _caliber: Resource) -> void:
		on_hit()


	## Mirrors bullet.gd on_hit_with_bullet_info_and_damage.
	func on_hit_with_bullet_info_and_damage(_hit_direction: Vector2, _caliber: Resource,
			_ricocheted: bool, _penetrated: bool, _dmg: float, _from_player: bool = false,
			_attacker_node: Node2D = null) -> void:
		on_hit()


	## Full explosion (Issue #1307 fix — replaces _rpg_intercept).
	func _rpg_explode() -> void:
		if _rpg_has_exploded:
			return
		_rpg_has_exploded = true
		exploded = true


	## Old behavior — silent destruction (should NOT be called after fix).
	func _rpg_intercept() -> void:
		if _rpg_has_exploded:
			return
		_rpg_has_exploded = true
		intercepted = true


class MockBullet:
	## Simulates a regular bullet (not RPG).
	var is_rpg_rocket: bool = false
	var collision_layer: int = 16


class MockRpgRocketOther:
	## Simulates another RPG rocket.
	var is_rpg_rocket: bool = true
	var collision_layer: int = 16


# ============================================================================
# Tests: on_hit triggers explosion (Issue #1307)
# ============================================================================


func test_on_hit_triggers_explosion() -> void:
	var rocket := MockRpgRocket.new(1)
	rocket.on_hit()
	assert_true(rocket.exploded, "Rocket should explode when hit (health=1)")
	assert_false(rocket.intercepted, "Rocket should NOT be silently intercepted")
	assert_true(rocket._rpg_has_exploded, "Rocket should be marked as exploded")


func test_on_hit_multi_health_requires_multiple_hits() -> void:
	var rocket := MockRpgRocket.new(3)
	rocket.on_hit()
	assert_false(rocket.exploded, "Rocket should NOT explode after 1 hit (health=3)")
	assert_eq(rocket._rpg_current_health, 2, "Health should decrease to 2")

	rocket.on_hit()
	assert_false(rocket.exploded, "Rocket should NOT explode after 2 hits (health=3)")
	assert_eq(rocket._rpg_current_health, 1, "Health should decrease to 1")

	rocket.on_hit()
	assert_true(rocket.exploded, "Rocket should explode after 3 hits (health=3)")
	assert_eq(rocket._rpg_current_health, 0, "Health should be 0")


func test_on_hit_ignored_when_already_exploded() -> void:
	var rocket := MockRpgRocket.new(1)
	rocket.on_hit()  # First hit — explodes
	assert_true(rocket.exploded, "Should explode on first hit")

	# Reset flag to check double-call protection
	rocket.exploded = false
	rocket.on_hit()  # Second hit — should be ignored
	assert_false(rocket.exploded, "Should NOT process on_hit after already exploded")


func test_on_hit_ignored_when_health_zero() -> void:
	var rocket := MockRpgRocket.new(1)
	rocket.rpg_health = 0  # Interception disabled
	rocket.on_hit()
	assert_false(rocket.exploded, "Should NOT explode when rpg_health=0 (interception disabled)")


func test_on_hit_ignored_when_not_rpg() -> void:
	var rocket := MockRpgRocket.new(1)
	rocket.is_rpg_rocket = false
	rocket.on_hit()
	assert_false(rocket.exploded, "Should NOT process on_hit for non-RPG bullets")


func test_on_hit_with_info_delegates_to_on_hit() -> void:
	var rocket := MockRpgRocket.new(1)
	rocket.on_hit_with_info(Vector2.RIGHT, null)
	assert_true(rocket.exploded, "on_hit_with_info should trigger explosion via on_hit")


func test_on_hit_with_bullet_info_and_damage_delegates_to_on_hit() -> void:
	var rocket := MockRpgRocket.new(1)
	rocket.on_hit_with_bullet_info_and_damage(Vector2.RIGHT, null, false, false, 1.0)
	assert_true(rocket.exploded, "on_hit_with_bullet_info_and_damage should trigger explosion via on_hit")


# ============================================================================
# Tests: area_entered collision filtering (Issue #1307)
# ============================================================================


## Simulates the _on_area_entered logic for RPG rockets from bullet.gd.
## Returns: "hit" if on_hit was called, "skip" if skipped, "explode" if direct explode.
func _simulate_area_entered(rocket: MockRpgRocket, area_collision_layer: int, area_is_rpg: bool) -> String:
	# Mirrors bullet.gd _on_area_entered RPG path
	if rocket._rpg_has_exploded:
		return "skip"

	if area_collision_layer & 16:
		if area_is_rpg:
			return "skip"  # Skip other RPG rockets
		# Incoming bullet/shrapnel hit
		rocket.on_hit()
		return "hit"

	return "other"


func test_area_entered_bullet_triggers_hit() -> void:
	var rocket := MockRpgRocket.new(1)
	var result := _simulate_area_entered(rocket, 16, false)
	assert_eq(result, "hit", "Bullet on layer 5 should trigger on_hit")
	assert_true(rocket.exploded, "Rocket should explode from bullet hit")


func test_area_entered_other_rpg_rocket_skipped() -> void:
	var rocket := MockRpgRocket.new(1)
	var result := _simulate_area_entered(rocket, 16, true)
	assert_eq(result, "skip", "Other RPG rockets should be skipped")
	assert_false(rocket.exploded, "Rocket should NOT explode from other RPG rocket")


func test_area_entered_non_projectile_area_not_processed_as_hit() -> void:
	var rocket := MockRpgRocket.new(1)
	var result := _simulate_area_entered(rocket, 4, false)
	assert_eq(result, "other", "Non-projectile areas (e.g. obstacle layer) should not trigger hit")
	assert_false(rocket.exploded, "Rocket should NOT explode from non-projectile area")


func test_area_entered_already_exploded_skipped() -> void:
	var rocket := MockRpgRocket.new(1)
	rocket._rpg_has_exploded = true
	var result := _simulate_area_entered(rocket, 16, false)
	assert_eq(result, "skip", "Already-exploded rocket should skip all area_entered")
