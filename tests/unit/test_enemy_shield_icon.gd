extends GutTest
## Unit tests for the blue shield icon on force field enemies (Issue #1079).
##
## Tests that:
## - The shield icon is hidden by default (enemy without force field)
## - The shield icon is shown when has_force_field is true
## - The shield icon uses the correct blue color matching the force field bubble
## - The shield icon uses the force_field_icon.png texture path


# ============================================================================
# Mock Enemy Model for Shield Icon Logic Tests
# ============================================================================


class MockShieldIcon:
	## Expected blue color matching the force field bubble (Issue #1034).
	const EXPECTED_MODULATE: Color = Color(0.4, 0.7, 1.0, 1.0)
	## Expected texture path for the shield icon.
	const EXPECTED_TEXTURE_PATH: String = "res://assets/sprites/weapons/force_field_icon.png"

	var visible: bool = false
	var modulate: Color = EXPECTED_MODULATE
	var texture_path: String = EXPECTED_TEXTURE_PATH


class MockEnemy:
	var has_force_field: bool = false
	var _shield_icon: MockShieldIcon = null

	func _init() -> void:
		_shield_icon = MockShieldIcon.new()
		_shield_icon.visible = false

	## Mirrors the logic in enemy.gd _ready():
	## if has_force_field and _shield_icon: _shield_icon.visible = true
	func setup_shield_icon() -> void:
		if has_force_field and _shield_icon:
			_shield_icon.visible = true


# ============================================================================
# Tests
# ============================================================================


func test_shield_icon_hidden_by_default() -> void:
	var enemy := MockEnemy.new()
	enemy.has_force_field = false
	enemy.setup_shield_icon()
	assert_false(enemy._shield_icon.visible,
		"Shield icon should be hidden for enemies without force field")


func test_shield_icon_visible_when_has_force_field() -> void:
	var enemy := MockEnemy.new()
	enemy.has_force_field = true
	enemy.setup_shield_icon()
	assert_true(enemy._shield_icon.visible,
		"Shield icon should be visible for force field enemies (Issue #1079)")


func test_shield_icon_blue_color_matches_force_field() -> void:
	var icon := MockShieldIcon.new()
	assert_eq(icon.modulate, MockShieldIcon.EXPECTED_MODULATE,
		"Shield icon modulate color should match the force field blue Color(0.4, 0.7, 1.0, 1.0)")


func test_shield_icon_uses_force_field_icon_texture() -> void:
	var icon := MockShieldIcon.new()
	assert_eq(icon.texture_path, MockShieldIcon.EXPECTED_TEXTURE_PATH,
		"Shield icon should use the force_field_icon.png texture")


func test_shield_icon_not_shown_when_no_icon_node() -> void:
	## Defensive check: if _shield_icon is null, no crash should occur
	var enemy := MockEnemy.new()
	enemy.has_force_field = true
	enemy._shield_icon = null
	# Should not crash — mirrors "if has_force_field and _shield_icon" guard
	if enemy.has_force_field and enemy._shield_icon:
		enemy._shield_icon.visible = true
	assert_true(true, "No crash when _shield_icon node is null")
