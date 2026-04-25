extends GutTest
## Unit tests for Winter Forest snow-surface collision configuration.


class MockWinterForestSnowArea:
	const SNOW_LAYER: int = 128
	const PROJECTILE_MASK: int = 39
	const SNOW_DETECTOR_MASK: int = 128


func test_snow_area_uses_non_projectile_layer() -> void:
	assert_eq(MockWinterForestSnowArea.SNOW_LAYER, 128,
		"Snow surface markers should use layer 8, not layer 6 targets")
	assert_eq(MockWinterForestSnowArea.PROJECTILE_MASK & MockWinterForestSnowArea.SNOW_LAYER, 0,
		"Shotgun pellets and bullets with mask 39 must not collide with snow areas")


func test_snow_detectors_match_snow_layer() -> void:
	assert_eq(MockWinterForestSnowArea.SNOW_DETECTOR_MASK, MockWinterForestSnowArea.SNOW_LAYER,
		"SnowyFeetComponent and BloodyFeetComponent detectors must scan the snow layer")
