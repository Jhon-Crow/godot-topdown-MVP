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

## Color for the nav mesh polygon fill.
const NAV_MESH_FILL_COLOR := Color(0.0, 0.5, 1.0, 0.25)
## Color for the nav mesh polygon outline.
const NAV_MESH_OUTLINE_COLOR := Color(0.0, 0.8, 1.0, 0.85)

## The overlay node used for custom drawing.
var _overlay: _NavMeshOverlay = null


func _ready() -> void:
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
	else:
		if _overlay != null:
			_overlay.hide()


## Create the overlay node if it doesn't exist yet.
func _ensure_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		return
	_overlay = _NavMeshOverlay.new()
	_overlay.fill_color = NAV_MESH_FILL_COLOR
	_overlay.outline_color = NAV_MESH_OUTLINE_COLOR
	get_tree().root.add_child(_overlay)


## Re-apply after a new NavigationRegion2D is added (e.g. after scene load).
func _on_node_added(node: Node) -> void:
	if node is NavigationRegion2D:
		# Connect to the region's bake_finished signal so we refresh after the bake completes,
		# not before. Navmesh bake is async (uses await), so call_deferred would fire too early.
		if not node.is_connected("bake_finished", _deferred_refresh):
			node.bake_finished.connect(_deferred_refresh)
		# Also connect to the polygon resource's changed signal to catch runtime rebakes.
		var nav_poly: NavigationPolygon = node.navigation_polygon
		if nav_poly != null and not nav_poly.is_connected("changed", _deferred_refresh):
			nav_poly.changed.connect(_deferred_refresh)
		# Defer an initial refresh (catches pre-baked polygons from the .tscn file).
		call_deferred("_deferred_refresh")


func _deferred_refresh() -> void:
	_apply_settings()
	if _overlay != null and is_instance_valid(_overlay) and _overlay.visible:
		_overlay.refresh()


## Inner class: a CanvasLayer that draws all NavigationRegion2D polygons.
## Using a CanvasLayer ensures the overlay renders above the game world
## and is not affected by the camera transform.
class _NavMeshOverlay extends CanvasLayer:
	var fill_color: Color = Color(0.0, 0.5, 1.0, 0.25)
	var outline_color: Color = Color(0.0, 0.8, 1.0, 0.85)
	## The Node2D child that does the actual drawing.
	var _draw_node: _NavMeshDrawNode = null

	func _ready() -> void:
		# Render above game world (layer 10) but below UI (layer 100+)
		layer = 10
		# Follow the viewport camera so world-space coordinates in _draw() align correctly
		follow_viewport_enabled = true
		_draw_node = _NavMeshDrawNode.new()
		_draw_node.fill_color = fill_color
		_draw_node.outline_color = outline_color
		add_child(_draw_node)

	## Collect all NavigationRegion2D nodes and pass their polygons to the draw node.
	func refresh() -> void:
		if _draw_node == null:
			return
		var polygons: Array = []
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree == null:
			return
		# Search all NavigationRegion2D nodes in the current scene
		var nav_regions: Array = _find_nav_regions(tree.root)
		for region in nav_regions:
			var nav_poly: NavigationPolygon = region.navigation_polygon
			if nav_poly == null:
				continue
			# Prefer baked polygon triangles (vertices + polygons array) over outlines.
			# get_outline() returns the INPUT boundaries (floor + obstacle holes) — it does NOT
			# change after baking and cannot show wall cutouts. The baked walkable triangles are
			# stored in get_vertices() + get_polygon(), which do reflect the carved navmesh.
			var polygon_count: int = nav_poly.get_polygon_count()
			if polygon_count > 0:
				var all_vertices: PackedVector2Array = nav_poly.get_vertices()
				for i in range(polygon_count):
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
			else:
				# No baked data yet — fall back to input outlines (floor boundary pre-bake).
				var outline_count: int = nav_poly.get_outline_count()
				for i in range(outline_count):
					var outline: PackedVector2Array = nav_poly.get_outline(i)
					if outline.size() >= 3:
						polygons.append({
							"vertices": outline,
							"global_transform": region.global_transform
						})
		_draw_node.set_polygons(polygons)

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

	func set_polygons(polygons: Array) -> void:
		_polygons = polygons
		queue_redraw()

	func _draw() -> void:
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
