extends GutTest
## Integration tests for Target behavior.
##
## Tests hit detection and state management.


const TargetScript = preload("res://scripts/objects/target.gd")


var target: Area2D
var sprite: Sprite2D


func before_each() -> void:
	# Create a target with a sprite child
	target = Area2D.new()
	target.set_script(TargetScript)

	sprite = Sprite2D.new()
	sprite.name = "Sprite2D"
	target.add_child(sprite)

	add_child_autoqfree(target)

	# Manually call _ready since we added the sprite before the script expects it
	# In test context, the @onready won't trigger automatically
	target.sprite = sprite
	target._ready()


func after_each() -> void:
	target = null
	sprite = null


# ============================================================================
# Initialization Tests
# ============================================================================


func test_default_hit_color() -> void:
	assert_eq(target.hit_color, Color(0.2, 0.8, 0.2, 1.0), "Default hit color should be green")


func test_default_normal_color() -> void:
	assert_eq(target.normal_color, Color(0.9, 0.2, 0.2, 1.0), "Default normal color should be red")


func test_default_destroy_on_hit() -> void:
	assert_false(target.destroy_on_hit, "Should not destroy on hit by default")


func test_default_respawn_delay() -> void:
	assert_eq(target.respawn_delay, 2.0, "Default respawn delay should be 2 seconds")


func test_initial_state_not_hit() -> void:
	assert_false(target._is_hit, "Target should not be hit initially")


func test_initial_sprite_color() -> void:
	assert_eq(sprite.modulate, target.normal_color, "Sprite should have normal color initially")


# ============================================================================
# Hit Detection Tests
# ============================================================================


func test_on_hit_sets_hit_state() -> void:
	target.on_hit()

	assert_true(target._is_hit, "Target should be in hit state after on_hit()")


func test_on_hit_changes_sprite_color() -> void:
	target.on_hit()

	assert_eq(sprite.modulate, target.hit_color, "Sprite should change to hit color")


func test_on_hit_ignores_second_hit() -> void:
	target.on_hit()
	var first_hit_color := sprite.modulate

	# Change hit color to test that second hit is ignored
	target.hit_color = Color.BLUE
	target.on_hit()

	assert_eq(sprite.modulate, first_hit_color, "Second hit should be ignored")


# ============================================================================
# Custom Color Tests
# ============================================================================


func test_custom_hit_color() -> void:
	target.hit_color = Color.YELLOW
	target.on_hit()

	assert_eq(sprite.modulate, Color.YELLOW, "Should use custom hit color")


func test_custom_normal_color() -> void:
	target.normal_color = Color.PURPLE
	target._ready()

	assert_eq(sprite.modulate, Color.PURPLE, "Should use custom normal color")


# ============================================================================
# Reset Tests
# ============================================================================


func test_reset_clears_hit_state() -> void:
	target._is_hit = true
	target._reset()

	assert_false(target._is_hit, "Reset should clear hit state")


func test_reset_restores_normal_color() -> void:
	target.on_hit()
	target._reset()

	assert_eq(sprite.modulate, target.normal_color, "Reset should restore normal color")


# ============================================================================
# Export Property Tests
# ============================================================================


func test_destroy_on_hit_can_be_enabled() -> void:
	target.destroy_on_hit = true

	assert_true(target.destroy_on_hit, "destroy_on_hit should be settable")


func test_custom_respawn_delay() -> void:
	target.respawn_delay = 5.0

	assert_eq(target.respawn_delay, 5.0, "respawn_delay should be settable")


# ============================================================================
# Edge Cases
# ============================================================================


func test_on_hit_without_sprite() -> void:
	# Create target without sprite
	var no_sprite_target := Area2D.new()
	no_sprite_target.set_script(TargetScript)
	add_child_autoqfree(no_sprite_target)
	no_sprite_target.sprite = null

	# Should not crash
	no_sprite_target.on_hit()

	assert_true(no_sprite_target._is_hit, "Hit state should be set even without sprite")


func test_reset_without_sprite() -> void:
	# Create target without sprite
	var no_sprite_target := Area2D.new()
	no_sprite_target.set_script(TargetScript)
	add_child_autoqfree(no_sprite_target)
	no_sprite_target.sprite = null
	no_sprite_target._is_hit = true

	# Should not crash
	no_sprite_target._reset()

	assert_false(no_sprite_target._is_hit, "Reset should work even without sprite")


func test_multiple_resets() -> void:
	target.on_hit()
	target._reset()
	target._reset()
	target._reset()

	assert_false(target._is_hit, "Multiple resets should not cause issues")
	assert_eq(sprite.modulate, target.normal_color, "Color should remain normal after multiple resets")


func test_hit_reset_hit_cycle() -> void:
	# First hit
	target.on_hit()
	assert_true(target._is_hit, "Should be hit")
	assert_eq(sprite.modulate, target.hit_color, "Should have hit color")

	# Reset
	target._reset()
	assert_false(target._is_hit, "Should not be hit after reset")
	assert_eq(sprite.modulate, target.normal_color, "Should have normal color")

	# Second hit
	target.on_hit()
	assert_true(target._is_hit, "Should be hit again")
	assert_eq(sprite.modulate, target.hit_color, "Should have hit color again")
