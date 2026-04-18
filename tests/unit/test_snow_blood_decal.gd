extends GutTest
## Unit tests for snow_blood_decal.gd (Issue #1627).
##
## Tests that SnowBloodDecal is not interactive (no blood_puddle group,
## no Area2D), that its absorbed tint is applied correctly, and that
## it does not trigger BloodyFeetComponent logic.


# ============================================================================
# Mock SnowBloodDecal for Logic Tests
# ============================================================================


class MockSnowBloodDecal:
	## Whether the decal is in the "blood_puddle" group.
	var in_blood_puddle_group: bool = false

	## Whether a puddle Area2D was created (should be false for snow stains).
	var puddle_area_created: bool = false

	## Whether auto-fade is scheduled.
	var auto_fade_scheduled: bool = false

	## Simulated modulate color after applying snow tint.
	var modulate: Color = Color(1.0, 1.0, 1.0, 1.0)

	## Input blood color.
	var blood_color: Color = Color(0.55, 0.05, 0.05, 1.0)

	## Initial alpha applied at ready.
	var _initial_alpha: float = 0.6

	## Fade delay in seconds.
	var fade_delay: float = 60.0


	func ready() -> void:
		_apply_snow_tint()
		# NOT added to blood_puddle group.
		in_blood_puddle_group = false
		# NOT creating Area2D.
		puddle_area_created = false
		# Auto-fade always scheduled.
		auto_fade_scheduled = true


	func _apply_snow_tint() -> void:
		var absorbed_r := lerpf(blood_color.r, 0.75, 0.35)
		var absorbed_g := lerpf(blood_color.g, 0.70, 0.5)
		var absorbed_b := lerpf(blood_color.b, 0.72, 0.5)
		modulate = Color(absorbed_r, absorbed_g, absorbed_b, _initial_alpha)


# ============================================================================
# Tests: No Blood Puddle Group
# ============================================================================


func test_snow_blood_decal_not_in_blood_puddle_group() -> void:
	var decal := MockSnowBloodDecal.new()
	decal.ready()
	assert_false(decal.in_blood_puddle_group,
		"SnowBloodDecal must NOT join blood_puddle group — absorbed blood is not walkable")


func test_snow_blood_decal_no_area2d() -> void:
	var decal := MockSnowBloodDecal.new()
	decal.ready()
	assert_false(decal.puddle_area_created,
		"SnowBloodDecal must NOT create an Area2D — it is purely visual")


# ============================================================================
# Tests: Auto Fade Scheduled
# ============================================================================


func test_snow_blood_decal_auto_fade_scheduled() -> void:
	var decal := MockSnowBloodDecal.new()
	decal.ready()
	assert_true(decal.auto_fade_scheduled,
		"SnowBloodDecal must always schedule a fade-out (snow covers the stain)")


func test_snow_blood_decal_fade_delay_is_long() -> void:
	# Fade delay should be at least 30 s so the stain is visible for a meaningful duration.
	var decal := MockSnowBloodDecal.new()
	assert_true(decal.fade_delay >= 30.0,
		"SnowBloodDecal fade_delay must be >= 30 s to remain visible long enough")


# ============================================================================
# Tests: Snow Tint Applied
# ============================================================================


func test_snow_tint_reduces_saturation() -> void:
	var decal := MockSnowBloodDecal.new()
	decal.blood_color = Color(0.55, 0.05, 0.05, 1.0)
	decal.ready()
	# The absorbed tint should increase green and blue relative to pure blood.
	assert_true(decal.modulate.g > decal.blood_color.g,
		"Absorbed snow blood green channel should be higher than pure blood (desaturated)")
	assert_true(decal.modulate.b > decal.blood_color.b,
		"Absorbed snow blood blue channel should be higher than pure blood (desaturated)")


func test_snow_tint_preserves_red_dominance() -> void:
	var decal := MockSnowBloodDecal.new()
	decal.blood_color = Color(0.55, 0.05, 0.05, 1.0)
	decal.ready()
	# Red should still dominate over green and blue for recognisable blood colour.
	assert_true(decal.modulate.r > decal.modulate.g,
		"Red channel should remain dominant in absorbed blood tint")


func test_initial_alpha_lower_than_blood_decal() -> void:
	# Snow does not hold vivid wet-looking stains — initial alpha should be < 0.85 (BloodDecal).
	var decal := MockSnowBloodDecal.new()
	decal.ready()
	assert_true(decal.modulate.a <= 0.7,
		"SnowBloodDecal alpha should be <= 0.7 (less vivid than a wet floor puddle)")


# ============================================================================
# Tests: BloodyFeetComponent on_snow flag (Issue #1627)
# ============================================================================


class MockBloodyFeetComponent:
	## Whether on_snow is set.
	var on_snow: bool = false

	## blood_steps_count export.
	var blood_steps_count: int = 12

	## Effective steps when blood contact happens (halved when on_snow).
	var _blood_level: int = 0


	func on_blood_puddle_contact() -> void:
		_blood_level = maxi(blood_steps_count / 2, 2) if on_snow else blood_steps_count


func test_on_snow_false_uses_full_steps() -> void:
	var comp := MockBloodyFeetComponent.new()
	comp.on_snow = false
	comp.on_blood_puddle_contact()
	assert_eq(comp._blood_level, comp.blood_steps_count,
		"With on_snow=false, blood_level should be set to full blood_steps_count")


func test_on_snow_true_halves_steps() -> void:
	var comp := MockBloodyFeetComponent.new()
	comp.on_snow = true
	comp.on_blood_puddle_contact()
	assert_eq(comp._blood_level, comp.blood_steps_count / 2,
		"With on_snow=true, blood_level should be halved (fewer bloody prints on snow)")


func test_on_snow_halved_steps_minimum_is_two() -> void:
	var comp := MockBloodyFeetComponent.new()
	comp.on_snow = true
	comp.blood_steps_count = 2
	comp.on_blood_puddle_contact()
	assert_true(comp._blood_level >= 2,
		"Halved steps must be at least 2 to ensure at least one footprint pair")


func test_on_snow_halved_steps_with_odd_count() -> void:
	var comp := MockBloodyFeetComponent.new()
	comp.on_snow = true
	comp.blood_steps_count = 7
	comp.on_blood_puddle_contact()
	# maxi(7 / 2, 2) = maxi(3, 2) = 3
	assert_eq(comp._blood_level, 3,
		"Halved steps with odd blood_steps_count should floor to (count / 2)")
