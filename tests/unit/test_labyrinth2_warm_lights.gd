extends GutTest
## Unit tests for warm ceiling lights in Labyrinth2Level (Issue #1291).
##
## Tests the warm room light placement system that adds PointLight2D nodes with
## warm yellow-orange color to each zone in the Лабиринт комплекс map, mirroring
## the same system already present in BuildingLevel (Здание).
##
## Lighting architecture:
## - Each zone has ONE PointLight2D with warm amber-orange color (1.0, 0.75, 0.3).
## - Smaller upper rooms get subtler lights (energy=0.7, scale=3.5).
## - Larger zones (corridors) get prominent lights (energy=0.85, scale=4.5).
## - Multiple lights cover the wide Central Corridor and Lower Labyrinth zones.


# ============================================================================
# Mock WarmLightManager for Logic Tests
# ============================================================================


class MockWarmLightManager:
	## Warm amber-orange light color (matches BuildingLevel).
	const LIGHT_COLOR: Color = Color(1.0, 0.75, 0.3, 1.0)

	## Energy for large zones.
	const ENERGY_LARGE: float = 0.85

	## Energy for small zones.
	const ENERGY_SMALL: float = 0.7

	## Texture scale for large zones.
	const SCALE_LARGE: float = 4.5

	## Texture scale for small zones.
	const SCALE_SMALL: float = 3.5

	## Labyrinth2Level map bounds.
	const MAP_LEFT: float = 64.0
	const MAP_RIGHT: float = 3264.0
	const MAP_TOP: float = 64.0
	const MAP_BOTTOM: float = 2464.0

	## Zone definitions: [label, left, top, right, bottom].
	const ZONES: Array = [
		["EntryHall",        80.0,   80.0,  588.0,  500.0],
		["WestWing",        612.0,   80.0, 1200.0,  500.0],
		["CentralHub",     1224.0,   80.0, 1800.0,  800.0],
		["NorthSector",    1824.0,   80.0, 2400.0,  500.0],
		["EastWing",       2424.0,   80.0, 3248.0,  500.0],
		["CentralCorridor",  80.0, 1224.0, 3248.0, 1800.0],
		["LowerLabyrinth",   80.0, 1824.0, 3248.0, 2448.0],
	]

	## Light configs: [position, energy, scale, label].
	## Mirrors the room_configs array in labyrinth2_level.gd.
	const LIGHT_CONFIGS: Array = [
		[Vector2(334,  290),  0.7,  3.5, "EntryHall"],
		[Vector2(906,  290),  0.7,  3.5, "WestWing"],
		[Vector2(1512, 440),  0.85, 4.5, "CentralHub"],
		[Vector2(2112, 290),  0.7,  3.5, "NorthSector"],
		[Vector2(2836, 290),  0.7,  3.5, "EastWing"],
		[Vector2(800,  1512), 0.85, 4.5, "CentralCorridor_W"],
		[Vector2(1664, 1512), 0.85, 4.5, "CentralCorridor_C"],
		[Vector2(2528, 1512), 0.85, 4.5, "CentralCorridor_E"],
		[Vector2(800,  2136), 0.85, 4.5, "LowerLabyrinth_W"],
		[Vector2(1664, 2136), 0.85, 4.5, "LowerLabyrinth_C"],
		[Vector2(2528, 2136), 0.85, 4.5, "LowerLabyrinth_E"],
	]

	## List of created warm lights.
	var _warm_lights: Array = []


	## Create warm lights matching the implementation.
	func setup_all_lights() -> void:
		_warm_lights.clear()
		for cfg in LIGHT_CONFIGS:
			_warm_lights.append({
				"position": cfg[0],
				"energy":   cfg[1],
				"scale":    cfg[2],
				"label":    cfg[3],
				"color":    LIGHT_COLOR,
				"shadow_enabled": true,
			})


	## Get all created warm lights.
	func get_lights() -> Array:
		return _warm_lights


	## Get warm light count.
	func get_light_count() -> int:
		return _warm_lights.size()


	## Check if a position is within the map bounds.
	func is_inside_map(pos: Vector2) -> bool:
		return (pos.x >= MAP_LEFT and pos.x <= MAP_RIGHT and
				pos.y >= MAP_TOP and pos.y <= MAP_BOTTOM)


	## Check if a position is inside any known zone bounding box.
	func is_inside_any_zone(pos: Vector2) -> bool:
		for zone in ZONES:
			var left: float = zone[1]
			var top: float = zone[2]
			var right: float = zone[3]
			var bottom: float = zone[4]
			if pos.x >= left and pos.x <= right and pos.y >= top and pos.y <= bottom:
				return true
		return false


var manager: MockWarmLightManager


func before_each() -> void:
	manager = MockWarmLightManager.new()
	manager.setup_all_lights()


func after_each() -> void:
	manager = null


# ============================================================================
# Light Count Tests
# ============================================================================


func test_has_expected_number_of_lights() -> void:
	assert_eq(manager.get_light_count(), 11,
		"Should have 11 warm lights (5 upper zones + 3 corridor + 3 lower)")


func test_all_zones_covered() -> void:
	# Each of the 7 zones should have at least one light
	var zones_covered := {}
	for light in manager.get_lights():
		var label: String = light["label"]
		# Normalize corridor/lower labels to zone name
		for zone in manager.ZONES:
			if label.begins_with(zone[0]):
				zones_covered[zone[0]] = true
				break

	for zone in manager.ZONES:
		assert_true(zones_covered.has(zone[0]),
			"Zone '%s' should have at least one warm light" % zone[0])


func test_wide_zones_have_multiple_lights() -> void:
	var corridor_lights := 0
	var lower_lights := 0
	for light in manager.get_lights():
		if (light["label"] as String).begins_with("CentralCorridor"):
			corridor_lights += 1
		if (light["label"] as String).begins_with("LowerLabyrinth"):
			lower_lights += 1

	assert_eq(corridor_lights, 3,
		"Central Corridor should have 3 lights to cover its full width")
	assert_eq(lower_lights, 3,
		"Lower Labyrinth should have 3 lights to cover its full width")


# ============================================================================
# Light Properties Tests
# ============================================================================


func test_light_color_is_warm() -> void:
	for light in manager.get_lights():
		var color: Color = light["color"]
		assert_true(color.r > color.b,
			"Warm light should be red-dominant (warm), got r=%.2f b=%.2f" % [color.r, color.b])
		assert_true(color.r > color.g,
			"Warm light should be red-dominant, got r=%.2f g=%.2f" % [color.r, color.g])


func test_light_shadows_enabled() -> void:
	for light in manager.get_lights():
		assert_true(light["shadow_enabled"],
			"Warm ceiling lights should have shadows enabled for natural depth")


func test_light_energy_within_range() -> void:
	for light in manager.get_lights():
		var energy: float = light["energy"]
		assert_true(energy > 0.0,
			"Light energy should be positive")
		assert_true(energy <= 1.0,
			"Light energy should be <= 1.0 (interior ceiling lamps, not blinding)")


func test_light_texture_scale_within_range() -> void:
	for light in manager.get_lights():
		var scale: float = light["scale"]
		assert_true(scale >= 3.0,
			"Texture scale should be >= 3.0 for adequate room coverage")
		assert_true(scale <= 6.0,
			"Texture scale should be <= 6.0 to avoid excessive bleed into adjacent rooms")


func test_large_zones_have_higher_energy() -> void:
	for light in manager.get_lights():
		var label: String = light["label"]
		var energy: float = light["energy"]
		if label.begins_with("CentralCorridor") or label.begins_with("LowerLabyrinth") or label == "CentralHub":
			assert_eq(energy, manager.ENERGY_LARGE,
				"Large zone '%s' should have energy %.2f" % [label, manager.ENERGY_LARGE])


func test_small_zones_have_lower_energy() -> void:
	var small_zones := ["EntryHall", "WestWing", "NorthSector", "EastWing"]
	for light in manager.get_lights():
		var label: String = light["label"]
		if label in small_zones:
			assert_eq(light["energy"], manager.ENERGY_SMALL,
				"Small zone '%s' should have energy %.2f" % [label, manager.ENERGY_SMALL])


# ============================================================================
# Light Position Tests
# ============================================================================


func test_all_lights_inside_map_bounds() -> void:
	for light in manager.get_lights():
		var pos: Vector2 = light["position"]
		assert_true(manager.is_inside_map(pos),
			"Light '%s' at %s should be inside map bounds" % [light["label"], str(pos)])


func test_all_lights_inside_a_zone() -> void:
	for light in manager.get_lights():
		var pos: Vector2 = light["position"]
		assert_true(manager.is_inside_any_zone(pos),
			"Light '%s' at %s should be inside a zone bounding box" % [light["label"], str(pos)])


func test_corridor_lights_evenly_spread() -> void:
	var corridor_x: Array = []
	for light in manager.get_lights():
		if (light["label"] as String).begins_with("CentralCorridor"):
			corridor_x.append(light["position"].x)

	corridor_x.sort()
	assert_eq(corridor_x.size(), 3, "Should have 3 corridor lights")

	# Verify they are spread across the corridor width (~80 to ~3248)
	assert_true(corridor_x[0] < 1000,
		"First corridor light should be in the west portion (x < 1000)")
	assert_true(corridor_x[2] > 2000,
		"Last corridor light should be in the east portion (x > 2000)")
	assert_true(corridor_x[1] > corridor_x[0] and corridor_x[1] < corridor_x[2],
		"Middle corridor light should be between the others")


# ============================================================================
# Matches BuildingLevel Style Tests
# ============================================================================


func test_matches_building_level_light_color() -> void:
	# BuildingLevel uses Color(1.0, 0.75, 0.3, 1.0) for warm amber-orange
	var expected_color := Color(1.0, 0.75, 0.3, 1.0)
	assert_eq(manager.LIGHT_COLOR, expected_color,
		"Warm light color should match BuildingLevel's amber-orange Color(1.0, 0.75, 0.3, 1.0)")


func test_energy_range_matches_building_level() -> void:
	# BuildingLevel uses 0.7 for small rooms and 0.85-0.9 for large rooms
	assert_true(manager.ENERGY_SMALL >= 0.65 and manager.ENERGY_SMALL <= 0.75,
		"Small zone energy should be ~0.7, matching BuildingLevel's Office rooms")
	assert_true(manager.ENERGY_LARGE >= 0.8 and manager.ENERGY_LARGE <= 0.95,
		"Large zone energy should be ~0.85, matching BuildingLevel's large rooms")
