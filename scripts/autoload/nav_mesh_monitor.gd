extends Node
## NavMeshMonitor - Toggles navigation mesh debug rendering at runtime.
##
## Controlled by ExperimentalSettings:
##   - nav_mesh_visible_enabled: show navigation mesh overlay (default: off)
##
## When enabled, the AI navigation mesh polygon is drawn on screen so level
## designers can see where enemies can walk and verify the mesh is correct.
##
## NOTE: NavigationServer2D.set_debug_enabled() only works in Godot editor/debug
## builds. This implementation uses Polygon2D and Line2D scene nodes so
## it works reliably in exported (release) builds with gl_compatibility renderer.
##
## Issue #1187: Added as part of AI navigation debugging tools.
## Issue #1224: Fixed to read baked polygon data (get_polygon/get_vertices) instead of
##              raw input outlines (get_outline), and to refresh after bake_finished.
## Issue #1392: Replaced Node2D._draw() with Polygon2D/Line2D scene nodes to fix
##              invisible overlays in gl_compatibility exported builds.

## Color for the nav mesh polygon fill.
const NAV_MESH_FILL_COLOR := Color(0.0, 0.5, 1.0, 0.25)
## Color for the nav mesh polygon outline.
const NAV_MESH_OUTLINE_COLOR := Color(0.0, 0.8, 1.0, 0.85)
## Delay after a NavigationRegion2D is added before refreshing.
## Increased to 1.0s to ensure bake_navigation_polygon(false) completes
## before the fallback timer reads polygon data.
const BAKE_WAIT_SECONDS := 1.0

## The overlay node used for rendering.
var _overlay: _NavMeshOverlay = null


func _ready() -> void:
	_log("NavMeshMonitor ready")
	# Sync debug rendering with current settings
	_apply_settings()
	# Connect to settings changes so toggle takes effect immediately
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings and experimental_settings.has_signal("settings_changed"):
		experimental_settings.settings_changed.connect(_apply_settings)
	# Re-apply on scene change (nav regions change between levels)
	get_tree().node_added.connect(_on_node_added)


## Apply current nav mesh debug visibility setting.
func _apply_settings() -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings == null:
		return
	var show_nav_mesh: bool = experimental_settings.has_method("is_nav_mesh_visible_enabled") and \
		experimental_settings.is_nav_mesh_visible_enabled()
	_set_overlay_visible(show_nav_mesh)


## Show or hide the custom nav mesh overlay.
func _set_overlay_visible(visible: bool) -> void:
	if visible:
		_ensure_overlay()
		if _overlay != null:
			_overlay.refresh()
			_overlay.show()
			_log("Overlay shown with %d polygon(s)" % _overlay.get_polygon_count())
	else:
		if _overlay != null:
			_overlay.hide()
			_log("Overlay hidden")


## Create the overlay node if it doesn't exist yet.
func _ensure_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		return
	_overlay = _NavMeshOverlay.new()
	_overlay.fill_color = NAV_MESH_FILL_COLOR
	_overlay.outline_color = NAV_MESH_OUTLINE_COLOR
	get_tree().root.add_child(_overlay)
	_log("Overlay node created")


## Re-apply after a new NavigationRegion2D is added (e.g. after scene load).
## Connects to bake_finished signal for accurate post-bake refresh, with a
## timer fallback in case the bake was not triggered or already completed.
func _on_node_added(node: Node) -> void:
	if node is NavigationRegion2D:
		_log("NavigationRegion2D added: %s" % node.name)
		# Connect to bake_finished so the overlay refreshes after walls are carved.
		if not node.bake_finished.is_connected(_deferred_refresh):
			node.bake_finished.connect(_deferred_refresh)
		# Also schedule a timer refresh as fallback (covers pre-baked navmesh data).
		get_tree().create_timer(BAKE_WAIT_SECONDS).timeout.connect(_deferred_refresh)


func _deferred_refresh() -> void:
	_apply_settings()
	if _overlay != null and is_instance_valid(_overlay) and _overlay.visible:
		_overlay.refresh()
		_log("Overlay refreshed with %d polygon(s)" % _overlay.get_polygon_count())


## Log a message with the NavMeshMonitor prefix via FileLogger if available.
## Issue #1293: print() fallback gated to debug builds to avoid FPS drops.
func _log(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[NavMeshMonitor] " + message)
	elif OS.is_debug_build():
		print("[NavMeshMonitor] " + message)


## Inner class: a CanvasLayer that renders NavigationRegion2D polygons using
## Polygon2D and Line2D scene nodes instead of custom _draw() calls.
## Issue #1392: Node2D._draw() is unreliable in gl_compatibility exported builds;
## Polygon2D/Line2D scene nodes use Godot's built-in rendering pipeline reliably.
class _NavMeshOverlay extends CanvasLayer:
	var fill_color: Color = Color(0.0, 0.5, 1.0, 0.25)
	var outline_color: Color = Color(0.0, 0.8, 1.0, 0.85)
	## Container node for all polygon/line child nodes.
	var _container: Node2D = null
	## Number of polygons currently displayed.
	var _polygon_count: int = 0

	func _init() -> void:
		# Render above all game world elements but below cinema effects (layer 99).
		layer = 50
		# Follow the viewport camera so world-space coordinates align correctly.
		follow_viewport_enabled = true
		# Container holds all Polygon2D/Line2D children.
		_container = Node2D.new()
		_container.name = "NavMeshContainer"
		add_child(_container)

	## Return the number of polygons currently drawn (for logging).
	func get_polygon_count() -> int:
		return _polygon_count

	## Collect all NavigationRegion2D nodes and create Polygon2D/Line2D nodes.
	func refresh() -> void:
		if _container == null:
			return
		# Clear previous polygon/line nodes
		for child in _container.get_children():
			child.queue_free()
		_polygon_count = 0

		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree == null:
			return
		var nav_regions: Array = _find_nav_regions(tree.root)
		_log_inner("refresh started: found %d NavigationRegion2D node(s)" % nav_regions.size())
		var baked_count: int = 0
		var outline_count_total: int = 0
		for region in nav_regions:
			if not is_instance_valid(region):
				continue
			var nav_poly: NavigationPolygon = region.navigation_polygon
			if nav_poly == null:
				continue
			var poly_count: int = nav_poly.get_polygon_count()
			var vertex_count: int = nav_poly.get_vertices().size()
			_log_inner("refresh: region '%s' poly_count=%d vertex_count=%d outline_count=%d" % [
				region.name, poly_count, vertex_count, nav_poly.get_outline_count()])
			if poly_count > 0:
				var all_vertices: PackedVector2Array = nav_poly.get_vertices()
				for i in range(poly_count):
					var indices: PackedInt32Array = nav_poly.get_polygon(i)
					if indices.size() < 3:
						continue
					var verts: PackedVector2Array = PackedVector2Array()
					for idx in indices:
						verts.append(all_vertices[idx])
					_add_polygon(verts, region.global_transform)
				baked_count += poly_count
			else:
				var outline_count: int = nav_poly.get_outline_count()
				for i in range(outline_count):
					var outline: PackedVector2Array = nav_poly.get_outline(i)
					if outline.size() >= 3:
						_add_polygon(outline, region.global_transform)
				outline_count_total += outline_count
		_log_inner("refresh done: %d region(s), %d baked poly(s), %d outline(s), %d draw polys" % [
			nav_regions.size(), baked_count, outline_count_total, _polygon_count])

	## Create a Polygon2D (fill) and Line2D (outline) for one polygon.
	func _add_polygon(verts: PackedVector2Array, xform: Transform2D) -> void:
		# Transform vertices to world space
		var world_verts: PackedVector2Array = PackedVector2Array()
		for v in verts:
			world_verts.append(xform * v)

		# Filled polygon
		var poly := Polygon2D.new()
		poly.polygon = world_verts
		poly.color = fill_color
		_container.add_child(poly)

		# Outline using Line2D (closed loop)
		var line := Line2D.new()
		var outline_pts := PackedVector2Array(world_verts)
		if outline_pts.size() >= 2:
			outline_pts.append(outline_pts[0])  # Close the loop
		line.points = outline_pts
		line.default_color = outline_color
		line.width = 1.5
		_container.add_child(line)

		_polygon_count += 1

	## Log a message (inner class helper).
	func _log_inner(message: String) -> void:
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree == null:
			if OS.is_debug_build():
				print("[NavMeshMonitor] " + message)
			return
		var file_logger: Node = tree.root.get_node_or_null("/root/FileLogger")
		if file_logger and file_logger.has_method("log_info"):
			file_logger.log_info("[NavMeshMonitor] " + message)
		elif OS.is_debug_build():
			print("[NavMeshMonitor] " + message)

	## Recursively find all NavigationRegion2D nodes under root.
	func _find_nav_regions(node: Node) -> Array:
		var result: Array = []
		if node is NavigationRegion2D:
			result.append(node)
		for child in node.get_children():
			result.append_array(_find_nav_regions(child))
		return result
