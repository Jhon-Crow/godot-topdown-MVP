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
## builds. This implementation uses a custom overlay drawn via draw_polygon so
## it works in exported (release) builds as well.
##
## Issue #1187: Added as part of AI navigation debugging tools.
## Issue #1224: Fixed to read baked polygon data (get_polygon/get_vertices) instead of
##              raw input outlines (get_outline), and to refresh after bake_finished.

## Color for the nav mesh polygon fill.
const NAV_MESH_FILL_COLOR := Color(0.0, 0.5, 1.0, 0.25)
## Color for the nav mesh polygon outline.
const NAV_MESH_OUTLINE_COLOR := Color(0.0, 0.8, 1.0, 0.85)
## Delay after a NavigationRegion2D is added before refreshing.
## Increased to 1.0s to ensure bake_navigation_polygon(false) completes
## before the fallback timer reads polygon data.
const BAKE_WAIT_SECONDS := 1.0

## The overlay node used for custom drawing.
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
## Issue #1392: add as child of this autoload (like FpsMonitor does) rather than
## get_tree().root — ensures the CanvasLayer stays in the scene tree across
## scene changes and renders correctly in exported builds.
func _ensure_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		return
	_overlay = _NavMeshOverlay.new()
	_overlay.fill_color = NAV_MESH_FILL_COLOR
	_overlay.outline_color = NAV_MESH_OUTLINE_COLOR
	add_child(_overlay)
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


## Inner class: a CanvasLayer that draws all NavigationRegion2D polygons.
## Using a CanvasLayer ensures the overlay renders above the game world
## and is not affected by the camera transform.
class _NavMeshOverlay extends CanvasLayer:
	var fill_color: Color = Color(0.0, 0.5, 1.0, 0.25)
	var outline_color: Color = Color(0.0, 0.8, 1.0, 0.85)
	## The Node2D child that does the actual drawing.
	## Initialized in _init() so it is available immediately after .new(),
	## before _ready() fires (which is deferred to the next frame by add_child).
	var _draw_node: _NavMeshDrawNode = null
	## Issue #1392: diagnostic label to verify CanvasLayer renders at all.
	var _diag_label: Label = null

	func _init() -> void:
		# Issue #1392: render above all visual effects (layers 97-103).
		layer = 150
		# Follow the viewport camera so world-space coordinates in _draw() align correctly.
		follow_viewport_enabled = true
		_draw_node = _NavMeshDrawNode.new()
		_draw_node.fill_color = fill_color
		_draw_node.outline_color = outline_color
		add_child(_draw_node)
		# Issue #1392: diagnostic label — if this text is visible but polygons aren't,
		# the issue is in _draw(), not in CanvasLayer rendering.
		_diag_label = Label.new()
		_diag_label.text = "[NavMesh overlay active]"
		_diag_label.position = Vector2(10, 30)
		_diag_label.add_theme_color_override("font_color", Color(0, 1, 1, 1))
		_diag_label.add_theme_font_size_override("font_size", 14)
		add_child(_diag_label)

	## Return the number of polygons currently drawn (for logging).
	func get_polygon_count() -> int:
		if _draw_node == null:
			return 0
		return _draw_node._polygons.size()

	## Collect all NavigationRegion2D nodes and pass their baked polygons to the draw node.
	## Reads triangulated baked data (get_polygon_count / get_polygon / get_vertices)
	## which reflects the actual walkable area after walls are carved out — not the raw
	## input outlines which only show the floor boundary.
	func refresh() -> void:
		if _draw_node == null:
			_log_inner("refresh: _draw_node is null, skipping")
			return
		var polygons: Array = []
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree == null:
			_log_inner("refresh: SceneTree is null, skipping")
			return
		# Search all NavigationRegion2D nodes in the current scene
		var nav_regions: Array = _find_nav_regions(tree.root)
		_log_inner("refresh started: found %d NavigationRegion2D node(s)" % nav_regions.size())
		var baked_count: int = 0
		var outline_count_total: int = 0
		for region in nav_regions:
			if not is_instance_valid(region):
				_log_inner("refresh: region is invalid, skipping")
				continue
			var nav_poly: NavigationPolygon = region.navigation_polygon
			if nav_poly == null:
				_log_inner("refresh: region '%s' has null navigation_polygon" % region.name)
				continue
			# Read baked triangulated polygon data (set by bake_navigation_polygon).
			# This reflects the actual walkable area with walls carved out.
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
					polygons.append({
						"vertices": verts,
						"global_transform": region.global_transform
					})
				baked_count += poly_count
			else:
				# Fall back to outlines if no baked data yet (bake not completed)
				var outline_count: int = nav_poly.get_outline_count()
				for i in range(outline_count):
					var outline: PackedVector2Array = nav_poly.get_outline(i)
					if outline.size() >= 3:
						polygons.append({
							"vertices": outline,
							"global_transform": region.global_transform
						})
				outline_count_total += outline_count
		_draw_node.set_polygons(polygons)
		_log_inner("refresh done: %d region(s), %d baked poly(s), %d outline(s), %d draw polys" % [
			nav_regions.size(), baked_count, outline_count_total, polygons.size()])

	## Log a message (inner class helper — accesses FileLogger via absolute path).
	## Issue #1293: print() fallback gated to debug builds to avoid FPS drops.
	func _log_inner(message: String) -> void:
		# Use /root/FileLogger absolute path — same as the outer class _log() method
		# to ensure consistent logging regardless of inner class context.
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


## Inner draw node: performs the actual draw calls each frame.
class _NavMeshDrawNode extends Node2D:
	var fill_color: Color = Color(0.0, 0.5, 1.0, 0.25)
	var outline_color: Color = Color(0.0, 0.8, 1.0, 0.85)
	var _polygons: Array = []
	## Issue #1392: diagnostic counter.
	var _draw_call_count: int = 0
	var _logged_first_draw: bool = false

	func set_polygons(polygons: Array) -> void:
		_polygons = polygons
		queue_redraw()

	func _draw() -> void:
		_draw_call_count += 1
		# Issue #1392: log first draw call with coordinate info for debugging.
		if not _logged_first_draw and _polygons.size() > 0:
			_logged_first_draw = true
			var first_poly: Dictionary = _polygons[0]
			var verts: PackedVector2Array = first_poly["vertices"]
			var xform: Transform2D = first_poly["global_transform"]
			var first_world: Vector2 = xform * verts[0] if verts.size() > 0 else Vector2.ZERO
			var tree: SceneTree = Engine.get_main_loop() as SceneTree
			if tree != null:
				var fl: Node = tree.root.get_node_or_null("/root/FileLogger")
				if fl and fl.has_method("log_info"):
					fl.log_info("[NavMeshMonitor] _draw() called: polys=%d, first_vert_world=%s, draw_count=%d, is_visible=%s, parent_layer=%s" % [
						_polygons.size(), str(first_world), _draw_call_count,
						str(is_visible_in_tree()),
						str(get_parent().layer if get_parent() is CanvasLayer else "N/A")])
		# Draw a bright test rectangle at screen origin to verify rendering works.
		draw_rect(Rect2(0, 0, 50, 50), Color(1, 0, 0, 0.8))
		for poly_data in _polygons:
			var verts: PackedVector2Array = poly_data["vertices"]
			var xform: Transform2D = poly_data["global_transform"]
			# Transform vertices from NavigationRegion2D local space to world space,
			# then to this node's local space (identity since it's at root level)
			var world_verts: PackedVector2Array = PackedVector2Array()
			for v in verts:
				world_verts.append(xform * v)
			# Colors array for draw_polygon (one per vertex)
			var colors: PackedColorArray = PackedColorArray()
			colors.resize(world_verts.size())
			colors.fill(fill_color)
			draw_polygon(world_verts, colors)
			# Draw outline
			draw_polyline(world_verts, outline_color, 1.5)
			# Close the outline loop
			if world_verts.size() >= 2:
				draw_line(world_verts[world_verts.size() - 1], world_verts[0], outline_color, 1.5)
