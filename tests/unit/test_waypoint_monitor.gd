extends GutTest
## Unit tests for WaypointMonitor autoload.
##
## Tests color assignment for passage and search waypoints,
## and the circle radius used for drawing.


# ============================================================================
# Mock WaypointMonitor
# ============================================================================


class MockWaypointMonitor:
	## Color for passage waypoints (green).
	const PASSAGE_COLOR := Color(0.2, 1.0, 0.3, 0.85)

	## Color for search path waypoints (yellow).
	const SEARCH_COLOR := Color(1.0, 0.85, 0.1, 0.85)

	## Circle radius for waypoint markers (pixels).
	const CIRCLE_RADIUS: float = 12.0

	## Simulates collecting waypoint data.
	func build_waypoint_data(group: String, name: String, pos: Vector2) -> Dictionary:
		var color: Color
		if group == "passage_waypoints":
			color = PASSAGE_COLOR
		elif group == "search_path_waypoints":
			color = SEARCH_COLOR
		else:
			color = Color.WHITE
		return {"pos": pos, "name": name, "color": color}


var monitor: MockWaypointMonitor


func before_each() -> void:
	monitor = MockWaypointMonitor.new()


func after_each() -> void:
	monitor = null


# ============================================================================
# Color Assignment Tests
# ============================================================================


func test_passage_waypoint_color_is_green() -> void:
	var data := monitor.build_waypoint_data("passage_waypoints", "Door1", Vector2(100, 200))

	assert_almost_eq(data["color"].r, 0.2, 0.01,
		"Passage waypoint red channel should be 0.2")
	assert_almost_eq(data["color"].g, 1.0, 0.01,
		"Passage waypoint green channel should be 1.0")
	assert_almost_eq(data["color"].b, 0.3, 0.01,
		"Passage waypoint blue channel should be 0.3")
	assert_almost_eq(data["color"].a, 0.85, 0.01,
		"Passage waypoint alpha should be 0.85")


func test_search_path_waypoint_color_is_yellow() -> void:
	var data := monitor.build_waypoint_data("search_path_waypoints", "Search1", Vector2(300, 400))

	assert_almost_eq(data["color"].r, 1.0, 0.01,
		"Search waypoint red channel should be 1.0")
	assert_almost_eq(data["color"].g, 0.85, 0.01,
		"Search waypoint green channel should be 0.85")
	assert_almost_eq(data["color"].b, 0.1, 0.01,
		"Search waypoint blue channel should be 0.1")
	assert_almost_eq(data["color"].a, 0.85, 0.01,
		"Search waypoint alpha should be 0.85")


func test_passage_and_search_colors_differ() -> void:
	var passage := monitor.build_waypoint_data("passage_waypoints", "P1", Vector2.ZERO)
	var search := monitor.build_waypoint_data("search_path_waypoints", "S1", Vector2.ZERO)

	assert_ne(passage["color"], search["color"],
		"Passage and search waypoint colors should be different")


# ============================================================================
# Circle Radius Tests
# ============================================================================


func test_circle_radius_is_12_pixels() -> void:
	assert_almost_eq(MockWaypointMonitor.CIRCLE_RADIUS, 12.0, 0.001,
		"Circle radius should be 12 pixels")


# ============================================================================
# Waypoint Data Tests
# ============================================================================


func test_waypoint_data_contains_position() -> void:
	var pos := Vector2(150, 250)
	var data := monitor.build_waypoint_data("passage_waypoints", "TestWP", pos)

	assert_eq(data["pos"], pos,
		"Waypoint data should contain the correct position")


func test_waypoint_data_contains_name() -> void:
	var data := monitor.build_waypoint_data("passage_waypoints", "MyDoor", Vector2.ZERO)

	assert_eq(data["name"], "MyDoor",
		"Waypoint data should contain the correct name")


func test_unknown_group_defaults_to_white() -> void:
	var data := monitor.build_waypoint_data("unknown_group", "Mystery", Vector2.ZERO)

	assert_eq(data["color"], Color.WHITE,
		"Unknown group should default to white color")
