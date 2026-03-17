extends GutTest
## Unit tests for GameplaySettings autoload (Issue #1090).
##
## Tests blood amount multiplier management, clamping, and signal emission
## without requiring the Godot scene tree.


# ============================================================================
# Mock GameplaySettings for Logic Tests
# ============================================================================


class MockGameplaySettings:
	## Blood amount multiplier [0.0, 3.0]. Default is 1.0.
	var blood_amount: float = 1.0

	## Track emitted signals
	var settings_changed_count: int = 0

	## Minimum blood amount multiplier.
	const MIN_BLOOD_AMOUNT: float = 0.0

	## Maximum blood amount multiplier.
	const MAX_BLOOD_AMOUNT: float = 3.0

	func set_blood_amount(amount: float) -> void:
		amount = clamp(amount, MIN_BLOOD_AMOUNT, MAX_BLOOD_AMOUNT)
		if not is_equal_approx(blood_amount, amount):
			blood_amount = amount
			settings_changed_count += 1

	func get_blood_amount() -> float:
		return blood_amount


var settings: MockGameplaySettings


func before_each() -> void:
	settings = MockGameplaySettings.new()


func after_each() -> void:
	settings = null


# ============================================================================
# Default Values Tests
# ============================================================================


func test_default_blood_amount_is_one() -> void:
	assert_eq(settings.get_blood_amount(), 1.0,
		"Default blood amount should be 1.0 (100%)")


# ============================================================================
# Blood Amount Tests
# ============================================================================


func test_set_blood_amount_half() -> void:
	settings.set_blood_amount(0.5)
	assert_eq(settings.get_blood_amount(), 0.5,
		"Blood amount should be 0.5 after setting to 0.5")


func test_set_blood_amount_zero_disables_blood() -> void:
	settings.set_blood_amount(0.0)
	assert_eq(settings.get_blood_amount(), 0.0,
		"Blood amount of 0.0 should disable blood entirely")


func test_set_blood_amount_max() -> void:
	settings.set_blood_amount(3.0)
	assert_eq(settings.get_blood_amount(), 3.0,
		"Blood amount should reach maximum of 3.0")


func test_set_blood_amount_clamps_above_max() -> void:
	settings.set_blood_amount(5.0)
	assert_eq(settings.get_blood_amount(), 3.0,
		"Blood amount above 3.0 should be clamped to 3.0")


func test_set_blood_amount_clamps_below_min() -> void:
	settings.set_blood_amount(-1.0)
	assert_eq(settings.get_blood_amount(), 0.0,
		"Blood amount below 0.0 should be clamped to 0.0")


# ============================================================================
# Signal Tests
# ============================================================================


func test_set_blood_amount_emits_signal_on_change() -> void:
	settings.set_blood_amount(2.0)
	assert_eq(settings.settings_changed_count, 1,
		"settings_changed should fire once when blood amount changes")


func test_set_blood_amount_no_signal_when_same_value() -> void:
	settings.set_blood_amount(1.0)
	assert_eq(settings.settings_changed_count, 0,
		"settings_changed should not fire when value is unchanged")


func test_set_blood_amount_signal_fires_each_change() -> void:
	settings.set_blood_amount(0.5)
	settings.set_blood_amount(2.0)
	settings.set_blood_amount(1.0)
	assert_eq(settings.settings_changed_count, 3,
		"settings_changed should fire for each distinct value change")


# ============================================================================
# Multiplier Application Tests
# ============================================================================


func test_multiplier_scales_decal_count_correctly() -> void:
	var base_decals := 30
	settings.set_blood_amount(2.0)
	var expected := roundi(base_decals * settings.get_blood_amount())
	assert_eq(expected, 60,
		"2x multiplier on 30 decals should yield 60 decals")


func test_zero_multiplier_yields_no_decals() -> void:
	var base_decals := 30
	settings.set_blood_amount(0.0)
	var result := maxi(0, roundi(base_decals * settings.get_blood_amount()))
	assert_eq(result, 0,
		"0x multiplier should yield 0 decals")


func test_default_multiplier_preserves_base_decal_count() -> void:
	var base_decals := 30
	var result := roundi(base_decals * settings.get_blood_amount())
	assert_eq(result, 30,
		"Default 1.0 multiplier should preserve base decal count")


func test_half_multiplier_halves_decal_count() -> void:
	var base_decals := 30
	settings.set_blood_amount(0.5)
	var result := roundi(base_decals * settings.get_blood_amount())
	assert_eq(result, 15,
		"0.5x multiplier on 30 decals should yield 15 decals")
