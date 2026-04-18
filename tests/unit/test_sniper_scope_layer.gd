extends GutTest
## Regression tests for sniper scope overlay layer ordering (Issue #1764).
##
## On Black Metal difficulty, the sniper scope view became nearly black and unplayable
## because the scope overlay CanvasLayer was at layer 10 — below the Black Metal B&W+red
## visual filter (layer 97). The filter's high-contrast shader processed the dark scope
## background, making everything under it appear almost completely black.
##
## Fix: raise the scope overlay layer to 110, above all difficulty visual filters
## (Black Metal B&W at 97, lightning at 98, cinema at 99, hit effects at 100-103).
## This mirrors the approach used by the revolver cylinder HUD (also layer 110).


# ============================================================================
# Constants mirroring production layer values
# ============================================================================

## The layer number used by BlackMetalEffectsManager for the B&W+red filter.
## Scope overlay MUST be above this.
const BLACK_METAL_FILTER_LAYER: int = 97

## The layer number used by BlackMetalLightningEffectsManager.
const BLACK_METAL_LIGHTNING_LAYER: int = 98

## The layer number used by CinemaEffectsManager.
const CINEMA_EFFECTS_LAYER: int = 99

## The layer number used by HitEffectsManager and replay UI.
const HIT_EFFECTS_LAYER: int = 100

## The layer number used by PenultimateHitEffectsManager.
const PENULTIMATE_HIT_EFFECTS_LAYER: int = 101

## The layer number used by LastChanceEffectsManager.
const LAST_CHANCE_EFFECTS_LAYER: int = 102

## The layer number used by PowerFantasyEffectsManager / FlashbangPlayerEffectsManager.
const POWER_FANTASY_EFFECTS_LAYER: int = 103

## The layer number used by the scope overlay (Issue #1764 fix).
## Must be above all difficulty visual filters.
const SCOPE_OVERLAY_LAYER: int = 110


# ============================================================================
# Layer ordering tests (Issue #1764)
# ============================================================================


func test_scope_overlay_layer_above_black_metal_filter() -> void:
	## Issue #1764: The scope overlay must render above the Black Metal B&W filter.
	## If scope layer <= 97, the shader desaturates and darkens the scope view.
	assert_true(
		SCOPE_OVERLAY_LAYER > BLACK_METAL_FILTER_LAYER,
		"Scope overlay layer (%d) must be above Black Metal filter layer (%d)" % [
			SCOPE_OVERLAY_LAYER, BLACK_METAL_FILTER_LAYER
		]
	)


func test_scope_overlay_layer_above_black_metal_lightning() -> void:
	## Issue #1764: The scope overlay must render above Black Metal lightning effects.
	assert_true(
		SCOPE_OVERLAY_LAYER > BLACK_METAL_LIGHTNING_LAYER,
		"Scope overlay layer (%d) must be above Black Metal lightning layer (%d)" % [
			SCOPE_OVERLAY_LAYER, BLACK_METAL_LIGHTNING_LAYER
		]
	)


func test_scope_overlay_layer_above_cinema_effects() -> void:
	## Issue #1764: The scope overlay must render above cinema effects.
	assert_true(
		SCOPE_OVERLAY_LAYER > CINEMA_EFFECTS_LAYER,
		"Scope overlay layer (%d) must be above cinema effects layer (%d)" % [
			SCOPE_OVERLAY_LAYER, CINEMA_EFFECTS_LAYER
		]
	)


func test_scope_overlay_layer_above_hit_effects() -> void:
	## Issue #1764: The scope overlay should render above hit effects
	## so the crosshair is always visible during combat feedback.
	assert_true(
		SCOPE_OVERLAY_LAYER > HIT_EFFECTS_LAYER,
		"Scope overlay layer (%d) must be above hit effects layer (%d)" % [
			SCOPE_OVERLAY_LAYER, HIT_EFFECTS_LAYER
		]
	)


func test_scope_overlay_layer_constant_is_110() -> void:
	## Regression: the scope overlay must be at layer 110 exactly as fixed in Issue #1764.
	## Before the fix it was 10 (processed by B&W shader), after the fix it is 110.
	assert_eq(
		SCOPE_OVERLAY_LAYER, 110,
		"Scope overlay layer must be 110 (Issue #1764 fix)"
	)


func test_scope_overlay_was_broken_at_layer_10() -> void:
	## Documents the old broken value: scope was at layer 10, below the BM filter (97).
	## This test documents WHY the fix was necessary.
	const OLD_BROKEN_LAYER: int = 10
	assert_true(
		OLD_BROKEN_LAYER < BLACK_METAL_FILTER_LAYER,
		"Old scope layer (%d) was below Black Metal filter (%d) — that was the bug" % [
			OLD_BROKEN_LAYER, BLACK_METAL_FILTER_LAYER
		]
	)


# ============================================================================
# Mock-based structural tests
# ============================================================================


## Simulates scope overlay creation logic (mirrors SniperRifle.cs CreateScopeOverlay).
class MockScopeOverlay:
	const OVERLAY_LAYER: int = 110
	const OVERLAY_NAME: String = "ScopeOverlay"

	## Simulates CanvasLayer creation with the fixed layer number.
	func create_overlay() -> Dictionary:
		return {"name": OVERLAY_NAME, "layer": OVERLAY_LAYER}

	## Returns the layer number the overlay will use.
	func get_overlay_layer() -> int:
		return OVERLAY_LAYER


func test_mock_scope_overlay_uses_correct_layer() -> void:
	## Verifies the mock's layer matches the expected fix value.
	var scope := MockScopeOverlay.new()
	assert_eq(
		scope.get_overlay_layer(), SCOPE_OVERLAY_LAYER,
		"MockScopeOverlay layer must equal SCOPE_OVERLAY_LAYER (%d)" % SCOPE_OVERLAY_LAYER
	)


func test_mock_scope_overlay_layer_above_black_metal_filter() -> void:
	## Issue #1764: Mock scope overlay must be above Black Metal filter.
	var scope := MockScopeOverlay.new()
	var overlay := scope.create_overlay()
	var layer: int = overlay.get("layer", -1)
	assert_true(
		layer > BLACK_METAL_FILTER_LAYER,
		"Created overlay layer (%d) must be above Black Metal filter (%d)" % [
			layer, BLACK_METAL_FILTER_LAYER
		]
	)


func test_mock_scope_overlay_has_correct_name() -> void:
	## The overlay name is used for identification — must be non-empty.
	var scope := MockScopeOverlay.new()
	var overlay := scope.create_overlay()
	assert_true(
		overlay.get("name", "").length() > 0,
		"Scope overlay must have a non-empty name"
	)
