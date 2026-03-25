extends Node2D
## Spring-column water surface simulation (Issue #1495).
##
## Divides the water surface into evenly-spaced vertical columns, each modeled
## as a damped harmonic oscillator. Disturbances (splashes) propagate as waves
## across the surface. Rendered via Polygon2D updated every frame.
##
## The simulation runs in _physics_process for deterministic behaviour.
## Visual updates (polygon rebuild) happen in _process for smooth rendering.

class_name WaterSurface

## Total width of the water surface in pixels.
@export var surface_width: float = 2400.0

## Depth of the water body below the surface line (for polygon fill).
@export var surface_depth: float = 178.0

## Spacing between adjacent spring columns in pixels.
@export var column_width: float = 4.0

## Spring stiffness (Hooke's law constant). Higher = faster oscillation.
@export var spring_constant: float = 0.025

## Velocity damping per frame. Higher = quicker settling.
@export var damping: float = 0.025

## Wave propagation factor per pass. Range [0, 0.5].
@export var spread: float = 0.25

## Number of propagation passes per physics frame.
## More passes = waves travel faster across the surface.
@export var propagation_passes: int = 8

## Minimum splash velocity to create a visible wave.
@export var min_splash_velocity: float = 20.0

## Maximum column displacement (prevents extreme oscillation).
@export var max_displacement: float = 30.0

# ---- Internal state ----

## Number of columns.
var _column_count: int = 0

## Per-column heights (displacement from target_height). Positive = above rest.
var _heights: PackedFloat32Array = PackedFloat32Array()

## Per-column velocities.
var _velocities: PackedFloat32Array = PackedFloat32Array()

## Target height (y=0 is the rest surface line, positive is downward in screen space).
var _target_height: float = 0.0

## Left edge X offset (columns span from -surface_width/2 to +surface_width/2).
var _left_x: float = 0.0

## Polygon2D used to render the water body.
var _polygon: Polygon2D = null

## Line2D for the surface highlight/foam line.
var _surface_line: Line2D = null

## Temporary arrays for propagation (reused to avoid allocation).
var _left_deltas: PackedFloat32Array = PackedFloat32Array()
var _right_deltas: PackedFloat32Array = PackedFloat32Array()

## Whether the surface needs a visual update.
var _dirty: bool = true


func _ready() -> void:
	_left_x = -surface_width * 0.5
	_column_count = int(surface_width / column_width) + 1

	# Initialize arrays
	_heights.resize(_column_count)
	_velocities.resize(_column_count)
	_left_deltas.resize(_column_count)
	_right_deltas.resize(_column_count)

	_heights.fill(0.0)
	_velocities.fill(0.0)
	_left_deltas.fill(0.0)
	_right_deltas.fill(0.0)

	# Create Polygon2D for the water body fill
	_polygon = Polygon2D.new()
	_polygon.color = Color(0.15, 0.55, 0.85, 0.0)  # Transparent — shader does the coloring
	add_child(_polygon)

	# Create Line2D for surface foam/highlight
	_surface_line = Line2D.new()
	_surface_line.width = 2.0
	_surface_line.default_color = Color(0.85, 0.92, 0.98, 0.6)
	_surface_line.z_index = 1
	add_child(_surface_line)

	# Apply water shader to the polygon
	_apply_shader()

	# Force initial polygon build
	_rebuild_polygon()


func _physics_process(delta: float) -> void:
	# Step 1: Update each spring independently (Hooke's law + damping)
	var any_active: bool = false
	for i in range(_column_count):
		var displacement: float = _heights[i] - _target_height
		_velocities[i] += -spring_constant * displacement
		_velocities[i] *= (1.0 - damping)
		_heights[i] += _velocities[i]

		# Clamp displacement to prevent runaway oscillation
		_heights[i] = clampf(_heights[i], -max_displacement, max_displacement)

		if absf(_heights[i]) > 0.1 or absf(_velocities[i]) > 0.01:
			any_active = true

	# Step 2: Wave propagation (multiple passes for faster travel)
	if any_active:
		for _pass in range(propagation_passes):
			_left_deltas.fill(0.0)
			_right_deltas.fill(0.0)

			for i in range(_column_count):
				if i > 0:
					_left_deltas[i] = spread * (_heights[i] - _heights[i - 1])
					_velocities[i - 1] += _left_deltas[i]
				if i < _column_count - 1:
					_right_deltas[i] = spread * (_heights[i] - _heights[i + 1])
					_velocities[i + 1] += _right_deltas[i]

			for i in range(_column_count):
				if i > 0:
					_heights[i - 1] += _left_deltas[i]
				if i < _column_count - 1:
					_heights[i + 1] += _right_deltas[i]

		_dirty = true


func _process(_delta: float) -> void:
	if _dirty:
		_rebuild_polygon()
		_dirty = false


## Create a splash at a world position with given velocity.
## velocity_y is the vertical impact speed (positive = downward).
## width_factor spreads the force across neighboring columns (1.0 = single point).
func splash(world_x: float, velocity_y: float, width_factor: float = 1.0) -> void:
	if absf(velocity_y) < min_splash_velocity:
		return

	# Convert world X to local column index
	var local_x: float = world_x - global_position.x
	var col_index: int = int((local_x - _left_x) / column_width)

	if col_index < 0 or col_index >= _column_count:
		return

	# Scale splash force — negative velocity_y means entering water (push surface down)
	var force: float = clampf(velocity_y * 0.15, -max_displacement * 0.8, max_displacement * 0.8)

	# Spread across neighboring columns based on width_factor
	var spread_cols: int = int(width_factor * 5.0)
	spread_cols = maxi(spread_cols, 1)

	for offset in range(-spread_cols, spread_cols + 1):
		var idx: int = col_index + offset
		if idx >= 0 and idx < _column_count:
			# Gaussian-like falloff from center
			var dist_factor: float = 1.0 - (absf(float(offset)) / float(spread_cols + 1))
			dist_factor *= dist_factor  # quadratic falloff
			_velocities[idx] += force * dist_factor

	_dirty = true


## Create a splash at a world position from an object with given velocity vector and mass.
func splash_from_body(world_x: float, velocity: Vector2, mass: float = 1.0, body_width: float = 20.0) -> void:
	# Use the velocity magnitude projected onto "entering water" direction
	# In top-down 2D, we use the velocity magnitude as the splash force
	var speed: float = velocity.length()
	if speed < min_splash_velocity:
		return

	var force: float = speed * mass * 0.1
	var width_factor: float = body_width / 20.0
	splash(world_x, force, width_factor)


## Create a large explosion splash at a world position.
func explosion_splash(world_x: float, explosion_radius: float = 100.0, force: float = 200.0) -> void:
	var local_x: float = world_x - global_position.x
	var center_col: int = int((local_x - _left_x) / column_width)
	var radius_cols: int = int(explosion_radius / column_width)

	for offset in range(-radius_cols, radius_cols + 1):
		var idx: int = center_col + offset
		if idx >= 0 and idx < _column_count:
			var dist_norm: float = absf(float(offset)) / float(radius_cols + 1)
			# Sinusoidal profile — center goes down, edges go up
			var profile: float = cos(dist_norm * PI)
			_velocities[idx] += force * 0.15 * profile

	_dirty = true


## Continuously disturb the surface at a world X position (for moving objects).
## Call this every frame for objects moving through water.
func disturb(world_x: float, strength: float = 2.0) -> void:
	var local_x: float = world_x - global_position.x
	var col_index: int = int((local_x - _left_x) / column_width)

	if col_index < 1 or col_index >= _column_count - 1:
		return

	_velocities[col_index] += strength
	_velocities[col_index - 1] += strength * 0.5
	_velocities[col_index + 1] += strength * 0.5
	_dirty = true


## Get the current surface height at a world X position.
## Returns the Y offset from the rest position (negative = above rest, positive = below).
func get_surface_height_at(world_x: float) -> float:
	var local_x: float = world_x - global_position.x
	var col_index: int = int((local_x - _left_x) / column_width)

	if col_index < 0 or col_index >= _column_count:
		return 0.0

	return _heights[col_index]


## Rebuild the Polygon2D points from current column heights.
func _rebuild_polygon() -> void:
	var surface_points: PackedVector2Array = PackedVector2Array()
	var line_points: PackedVector2Array = PackedVector2Array()

	# Use a stride to reduce polygon vertex count (every 2nd column for polygon)
	var stride: int = 2

	# Top edge (surface) — left to right
	for i in range(0, _column_count, stride):
		var x: float = _left_x + i * column_width
		var y: float = -_heights[i]  # negative because screen Y is inverted
		surface_points.append(Vector2(x, y))
		line_points.append(Vector2(x, y))

	# Bottom-right corner
	surface_points.append(Vector2(_left_x + (_column_count - 1) * column_width, surface_depth))
	# Bottom-left corner
	surface_points.append(Vector2(_left_x, surface_depth))

	_polygon.polygon = surface_points
	_surface_line.points = line_points

	# Update UV mapping so shader renders correctly on the deformed polygon
	var uvs: PackedVector2Array = PackedVector2Array()
	for i in range(surface_points.size()):
		var pt: Vector2 = surface_points[i]
		var u: float = (pt.x - _left_x) / surface_width
		var v: float = (pt.y + max_displacement) / (surface_depth + max_displacement)
		uvs.append(Vector2(u, clampf(v, 0.0, 1.0)))
	_polygon.uv = uvs


## Apply the water surface shader to the polygon.
func _apply_shader() -> void:
	var shader_path: String = "res://scripts/shaders/water_surface.gdshader"
	if ResourceLoader.exists(shader_path):
		var shader: Shader = load(shader_path)
		if shader != null:
			var mat := ShaderMaterial.new()
			mat.shader = shader
			_polygon.material = mat
	else:
		# Fallback to realistic_water shader if surface shader not found
		var fallback_path: String = "res://scripts/shaders/realistic_water.gdshader"
		if ResourceLoader.exists(fallback_path):
			var shader: Shader = load(fallback_path)
			if shader != null:
				var mat := ShaderMaterial.new()
				mat.shader = shader
				_polygon.material = mat
