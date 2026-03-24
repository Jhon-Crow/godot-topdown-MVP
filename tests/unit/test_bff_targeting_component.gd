extends GutTest
## Unit tests for BffTargetingComponent.
##
## Tests companion visibility tracking and target selection logic
## (player vs companion) for enemy AI targeting.


# ============================================================================
# Mock Classes
# ============================================================================


class MockNode2D:
	var global_position: Vector2 = Vector2.ZERO
	var _is_alive: bool = true

	func _init(pos: Vector2 = Vector2.ZERO) -> void:
		global_position = pos

	func get(property: String):
		if property == "_is_alive":
			return _is_alive
		return null


class MockBffTargetingComponent:
	var can_see_companion: bool = false
	var companion: MockNode2D = null
	var current_target: MockNode2D = null
	var _parent: MockNode2D = null

	func _init(parent: MockNode2D) -> void:
		_parent = parent

	func check_visibility_simple(
			is_blinded: bool,
			confusion_timer: float,
			detection_range: float,
			companion_ref: MockNode2D,
			companion_in_fov: bool,
			companion_visible: bool) -> void:
		can_see_companion = false
		companion = companion_ref

		if companion == null:
			return
		if is_blinded or confusion_timer > 0.0:
			return
		if companion._is_alive == false:
			return

		var dist: float = _parent.global_position.distance_to(companion.global_position)
		if detection_range > 0 and dist > detection_range:
			return
		if not companion_in_fov:
			return
		if companion_visible:
			can_see_companion = true

	func select_best_target(player: MockNode2D, can_see_player: bool) -> void:
		var has_player := player != null and can_see_player
		var has_companion := companion != null and can_see_companion

		if not has_player and not has_companion:
			current_target = player
			return

		if has_player and not has_companion:
			current_target = player
			return

		if has_companion and not has_player:
			current_target = companion
			return

		# Both visible — pick the closer one
		var dist_player := _parent.global_position.distance_to(player.global_position)
		var dist_companion := _parent.global_position.distance_to(companion.global_position)
		current_target = companion if dist_companion < dist_player else player


var component: MockBffTargetingComponent
var parent_enemy: MockNode2D
var player: MockNode2D
var companion: MockNode2D


func before_each() -> void:
	parent_enemy = MockNode2D.new(Vector2(100, 100))
	component = MockBffTargetingComponent.new(parent_enemy)
	player = MockNode2D.new(Vector2(200, 100))
	companion = MockNode2D.new(Vector2(300, 100))


func after_each() -> void:
	component = null
	parent_enemy = null
	player = null
	companion = null


# ============================================================================
# Companion Visibility Tests
# ============================================================================


func test_default_can_see_companion_false() -> void:
	assert_false(component.can_see_companion,
		"Should not see companion by default")


func test_companion_visible_when_in_fov_and_los() -> void:
	component.check_visibility_simple(false, 0.0, 1000.0, companion, true, true)

	assert_true(component.can_see_companion,
		"Should see companion when in FOV and has LOS")


func test_companion_not_visible_when_blinded() -> void:
	component.check_visibility_simple(true, 0.0, 1000.0, companion, true, true)

	assert_false(component.can_see_companion,
		"Should not see companion when blinded")


func test_companion_not_visible_when_confused() -> void:
	component.check_visibility_simple(false, 1.5, 1000.0, companion, true, true)

	assert_false(component.can_see_companion,
		"Should not see companion during confusion timer")


func test_companion_not_visible_when_dead() -> void:
	companion._is_alive = false

	component.check_visibility_simple(false, 0.0, 1000.0, companion, true, true)

	assert_false(component.can_see_companion,
		"Should not see dead companion")


func test_companion_not_visible_when_out_of_range() -> void:
	companion.global_position = Vector2(2000, 100)

	component.check_visibility_simple(false, 0.0, 500.0, companion, true, true)

	assert_false(component.can_see_companion,
		"Should not see companion beyond detection range")


func test_companion_not_visible_when_out_of_fov() -> void:
	component.check_visibility_simple(false, 0.0, 1000.0, companion, false, true)

	assert_false(component.can_see_companion,
		"Should not see companion outside FOV")


func test_companion_not_visible_when_no_los() -> void:
	component.check_visibility_simple(false, 0.0, 1000.0, companion, true, false)

	assert_false(component.can_see_companion,
		"Should not see companion without line of sight")


func test_companion_null_resets_visibility() -> void:
	component.check_visibility_simple(false, 0.0, 1000.0, null, true, true)

	assert_false(component.can_see_companion,
		"Should not see null companion")


func test_unlimited_detection_range() -> void:
	companion.global_position = Vector2(99999, 100)

	component.check_visibility_simple(false, 0.0, 0.0, companion, true, true)

	assert_true(component.can_see_companion,
		"Detection range 0 means unlimited")


# ============================================================================
# Target Selection Tests
# ============================================================================


func test_select_player_when_only_player_visible() -> void:
	component.can_see_companion = false

	component.select_best_target(player, true)

	assert_eq(component.current_target, player,
		"Should select player when only player is visible")


func test_select_companion_when_only_companion_visible() -> void:
	component.companion = companion
	component.can_see_companion = true

	component.select_best_target(player, false)

	assert_eq(component.current_target, companion,
		"Should select companion when only companion is visible")


func test_select_closer_target_when_both_visible_player_closer() -> void:
	parent_enemy.global_position = Vector2(100, 100)
	player.global_position = Vector2(150, 100)  # 50px away
	companion.global_position = Vector2(400, 100)  # 300px away

	component.companion = companion
	component.can_see_companion = true

	component.select_best_target(player, true)

	assert_eq(component.current_target, player,
		"Should select player when player is closer")


func test_select_closer_target_when_both_visible_companion_closer() -> void:
	parent_enemy.global_position = Vector2(100, 100)
	player.global_position = Vector2(500, 100)  # 400px away
	companion.global_position = Vector2(120, 100)  # 20px away

	component.companion = companion
	component.can_see_companion = true

	component.select_best_target(player, true)

	assert_eq(component.current_target, companion,
		"Should select companion when companion is closer")


func test_fallback_to_player_when_neither_visible() -> void:
	component.can_see_companion = false

	component.select_best_target(player, false)

	assert_eq(component.current_target, player,
		"Should fall back to player for memory-based pursuit when neither visible")


func test_fallback_to_null_player_when_neither_visible() -> void:
	component.can_see_companion = false

	component.select_best_target(null, false)

	assert_eq(component.current_target, null,
		"Should return null when player is null and neither visible")


func test_select_companion_when_player_null_and_companion_visible() -> void:
	component.companion = companion
	component.can_see_companion = true

	component.select_best_target(null, false)

	assert_eq(component.current_target, companion,
		"Should select companion when player is null but companion visible")
