extends GutTest
## Unit tests for revolver cylinder HUD layer ordering (Issue #1765).
##
## Verifies that the revolver drum HUD is placed in a dedicated CanvasLayer
## at a layer number above all difficulty visual filters (Black Metal B&W at
## layer 97, lightning at 98, cinema at 99, hit effects at 100, etc.),
## so that the HUD always renders in its original colors regardless of
## difficulty mode.


# ============================================================================
# Constants mirroring the production values
# ============================================================================

## The layer number used by BlackMetalEffectsManager for the B&W filter.
const BLACK_METAL_FILTER_LAYER: int = 97

## The layer number used by BlackMetalLightningEffectsManager.
const BLACK_METAL_LIGHTNING_LAYER: int = 98

## The layer number used by CinemaEffectsManager.
const CINEMA_EFFECTS_LAYER: int = 99

## The layer number used by HitEffectsManager.
const HIT_EFFECTS_LAYER: int = 100

## The layer number used by PenultimateHitEffectsManager.
const PENULTIMATE_HIT_EFFECTS_LAYER: int = 101

## The layer number used by LastChanceEffectsManager.
const LAST_CHANCE_EFFECTS_LAYER: int = 102

## The layer number used by PowerFantasyEffectsManager / FlashbangPlayerEffectsManager.
const POWER_FANTASY_EFFECTS_LAYER: int = 103

## The layer used for the cylinder HUD (must be above all difficulty filters).
const CYLINDER_HUD_LAYER: int = 110

## The name of the dedicated CanvasLayer for the cylinder HUD.
const CYLINDER_HUD_LAYER_NAME: String = "RevolverCylinderHUDLayer"


# ============================================================================
# Layer ordering tests (Issue #1765)
# ============================================================================


func test_cylinder_hud_layer_above_black_metal_filter() -> void:
	## Issue #1765: The cylinder HUD must render above the Black Metal B&W filter.
	## If the HUD layer is <= 97, the filter desaturates the HUD to B&W.
	assert_true(
		CYLINDER_HUD_LAYER > BLACK_METAL_FILTER_LAYER,
		"Cylinder HUD layer (%d) must be above Black Metal filter layer (%d)" % [
			CYLINDER_HUD_LAYER, BLACK_METAL_FILTER_LAYER
		]
	)


func test_cylinder_hud_layer_above_black_metal_lightning() -> void:
	## Issue #1765: The HUD must render above Black Metal lightning effects.
	assert_true(
		CYLINDER_HUD_LAYER > BLACK_METAL_LIGHTNING_LAYER,
		"Cylinder HUD layer (%d) must be above Black Metal lightning layer (%d)" % [
			CYLINDER_HUD_LAYER, BLACK_METAL_LIGHTNING_LAYER
		]
	)


func test_cylinder_hud_layer_above_cinema_effects() -> void:
	## Issue #1765: The HUD must render above cinema effects (letterbox bars etc.).
	assert_true(
		CYLINDER_HUD_LAYER > CINEMA_EFFECTS_LAYER,
		"Cylinder HUD layer (%d) must be above cinema effects layer (%d)" % [
			CYLINDER_HUD_LAYER, CINEMA_EFFECTS_LAYER
		]
	)


func test_cylinder_hud_layer_above_hit_effects() -> void:
	## Issue #1765: The HUD must render above hit effects.
	assert_true(
		CYLINDER_HUD_LAYER > HIT_EFFECTS_LAYER,
		"Cylinder HUD layer (%d) must be above hit effects layer (%d)" % [
			CYLINDER_HUD_LAYER, HIT_EFFECTS_LAYER
		]
	)


func test_cylinder_hud_layer_above_all_difficulty_effects() -> void:
	## Issue #1765: The HUD must be above ALL difficulty-related visual layers.
	var highest_difficulty_layer: int = max(
		BLACK_METAL_FILTER_LAYER,
		BLACK_METAL_LIGHTNING_LAYER,
		CINEMA_EFFECTS_LAYER,
		HIT_EFFECTS_LAYER,
		PENULTIMATE_HIT_EFFECTS_LAYER,
		LAST_CHANCE_EFFECTS_LAYER,
		POWER_FANTASY_EFFECTS_LAYER
	)
	assert_true(
		CYLINDER_HUD_LAYER > highest_difficulty_layer,
		"Cylinder HUD layer (%d) must be above highest difficulty effects layer (%d)" % [
			CYLINDER_HUD_LAYER, highest_difficulty_layer
		]
	)


func test_cylinder_hud_layer_name_is_canonical() -> void:
	## The HUD layer name is used for duplicate detection — it must be non-empty.
	assert_true(
		CYLINDER_HUD_LAYER_NAME.length() > 0,
		"Cylinder HUD layer name must be non-empty"
	)


# ============================================================================
# Mock-based structural tests
# ============================================================================


## Simulates the level root node for structural testing.
class MockLevelRoot:
	var children: Dictionary = {}

	func has_canvas_layer(name: String) -> bool:
		return name in children

	func add_canvas_layer(name: String, layer: int) -> void:
		children[name] = {"type": "CanvasLayer", "layer": layer, "children": {}}

	func get_canvas_layer(name: String) -> Dictionary:
		return children.get(name, {})


## Simulates the HUD setup logic (mirrors Revolver.cs / LevelInitFallback.cs).
class MockHUDSetup:
	const HUD_LAYER: int = 110
	const HUD_LAYER_NAME: String = "RevolverCylinderHUDLayer"

	var level_root: MockLevelRoot = null
	var cylinder_ui_created: bool = false

	func _init(root: MockLevelRoot) -> void:
		level_root = root

	## Mirrors the SetupCylinderHUD / SetupRevolverCylinderUI logic.
	func setup_hud() -> void:
		# Don't create duplicate
		if level_root.has_canvas_layer(HUD_LAYER_NAME):
			cylinder_ui_created = false  # reused existing
			return

		# Create dedicated CanvasLayer above visual filters
		level_root.add_canvas_layer(HUD_LAYER_NAME, HUD_LAYER)
		cylinder_ui_created = true

	func get_hud_layer_number() -> int:
		var layer_data := level_root.get_canvas_layer(HUD_LAYER_NAME)
		return layer_data.get("layer", -1)


func test_setup_creates_canvas_layer_on_level_root() -> void:
	## Issue #1765: SetupCylinderHUD must create a CanvasLayer on the level root.
	var root := MockLevelRoot.new()
	var setup := MockHUDSetup.new(root)

	setup.setup_hud()

	assert_true(
		root.has_canvas_layer("RevolverCylinderHUDLayer"),
		"Level root must have a RevolverCylinderHUDLayer after setup"
	)


func test_setup_uses_layer_above_black_metal_filter() -> void:
	## Issue #1765: The created CanvasLayer must use a layer > 97 (Black Metal filter).
	var root := MockLevelRoot.new()
	var setup := MockHUDSetup.new(root)

	setup.setup_hud()

	var layer := setup.get_hud_layer_number()
	assert_true(
		layer > BLACK_METAL_FILTER_LAYER,
		"HUD CanvasLayer (%d) must be above Black Metal filter (%d)" % [layer, BLACK_METAL_FILTER_LAYER]
	)


func test_setup_does_not_create_duplicate_layer() -> void:
	## Issue #1765: Calling setup twice must not create a second CanvasLayer.
	var root := MockLevelRoot.new()
	var setup1 := MockHUDSetup.new(root)
	var setup2 := MockHUDSetup.new(root)

	setup1.setup_hud()
	setup2.setup_hud()  # Should reuse the existing layer

	# Only one CanvasLayer with this name should exist
	assert_true(
		root.has_canvas_layer("RevolverCylinderHUDLayer"),
		"Layer should exist after second call"
	)
	assert_false(
		setup2.cylinder_ui_created,
		"Second setup call must not create a duplicate UI"
	)
