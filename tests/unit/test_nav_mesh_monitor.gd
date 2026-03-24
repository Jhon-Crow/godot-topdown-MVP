extends GutTest
## Unit tests for NavMeshMonitor autoload.
##
## Tests the navigation mesh debug overlay that draws the AI
## navigation mesh on screen for level designers.


# ============================================================================
# Mock NavMeshMonitor for Logic Tests
# ============================================================================


class MockNavMeshMonitor:
	## Color constants
	const NAV_MESH_FILL_COLOR: Color = Color(0.0, 0.5, 1.0, 0.25)
	const NAV_MESH_OUTLINE_COLOR: Color = Color(0.0, 0.8, 1.0, 0.85)
	const BAKE_WAIT_SECONDS: float = 1.0

	var _overlay_visible: bool = false
	var _overlay_created: bool = false

	func set_overlay_visible(visible: bool) -> void:
		if visible and not _overlay_created:
			_overlay_created = true
		_overlay_visible = visible

	func is_overlay_visible() -> bool:
		return _overlay_visible

	func is_overlay_created() -> bool:
		return _overlay_created


# ============================================================================
# Color Constants Tests
# ============================================================================


func test_fill_color_alpha() -> void:
	var fill := MockNavMeshMonitor.NAV_MESH_FILL_COLOR
	assert_almost_eq(fill.a, 0.25, 0.001, "Fill color should be semi-transparent (0.25 alpha)")


func test_fill_color_is_blue() -> void:
	var fill := MockNavMeshMonitor.NAV_MESH_FILL_COLOR
	assert_almost_eq(fill.r, 0.0, 0.001, "Fill should have no red")
	assert_almost_eq(fill.b, 1.0, 0.001, "Fill should have full blue")


func test_outline_color_alpha() -> void:
	var outline := MockNavMeshMonitor.NAV_MESH_OUTLINE_COLOR
	assert_almost_eq(outline.a, 0.85, 0.001, "Outline should be mostly opaque (0.85 alpha)")


func test_outline_color_is_cyan() -> void:
	var outline := MockNavMeshMonitor.NAV_MESH_OUTLINE_COLOR
	assert_almost_eq(outline.r, 0.0, 0.001, "Outline should have no red")
	assert_almost_eq(outline.g, 0.8, 0.001, "Outline should have green at 0.8")
	assert_almost_eq(outline.b, 1.0, 0.001, "Outline should have full blue")


# ============================================================================
# Bake Wait Constants Tests
# ============================================================================


func test_bake_wait_seconds() -> void:
	assert_eq(MockNavMeshMonitor.BAKE_WAIT_SECONDS, 1.0, "Bake wait should be 1.0 seconds")


# ============================================================================
# Overlay State Tests
# ============================================================================


func test_overlay_not_visible_by_default() -> void:
	var monitor := MockNavMeshMonitor.new()
	assert_false(monitor.is_overlay_visible(), "Overlay should not be visible by default")


func test_overlay_not_created_by_default() -> void:
	var monitor := MockNavMeshMonitor.new()
	assert_false(monitor.is_overlay_created(), "Overlay should not be created by default")


func test_show_overlay_creates_it() -> void:
	var monitor := MockNavMeshMonitor.new()
	monitor.set_overlay_visible(true)
	assert_true(monitor.is_overlay_created(), "Showing overlay should create it")
	assert_true(monitor.is_overlay_visible(), "Overlay should be visible after show")


func test_hide_overlay() -> void:
	var monitor := MockNavMeshMonitor.new()
	monitor.set_overlay_visible(true)
	monitor.set_overlay_visible(false)
	assert_false(monitor.is_overlay_visible(), "Overlay should be hidden")
	assert_true(monitor.is_overlay_created(), "Overlay should still exist after hiding")


func test_toggle_overlay() -> void:
	var monitor := MockNavMeshMonitor.new()
	monitor.set_overlay_visible(true)
	assert_true(monitor.is_overlay_visible(), "Should be visible")
	monitor.set_overlay_visible(false)
	assert_false(monitor.is_overlay_visible(), "Should be hidden")
	monitor.set_overlay_visible(true)
	assert_true(monitor.is_overlay_visible(), "Should be visible again")
