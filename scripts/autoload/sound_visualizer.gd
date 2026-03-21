extends Node
## SoundVisualizer — Debug overlay for sound propagation (Issue #1253).
##
## When enabled via the Experimental menu, draws animated circles at each
## sound emission point showing the propagation radius. This lets developers
## verify that gunshots and other sounds are heard by enemies at the correct
## distance.
##
## Each ring expands from the origin to the full propagation radius, holds
## briefly, then fades out. Rings are color-coded by source type:
##   - Blue  : player sounds
##   - Red   : enemy sounds
##   - White : neutral / environmental sounds
##
## Depends on:
##   - SoundPropagation autoload (connects to its sound_emitted signal)
##   - ExperimentalSettings autoload (checked before drawing)

## Duration of the expanding animation (seconds).
const EXPAND_DURATION: float = 0.5

## Total lifetime of each ring (seconds).
const RING_LIFETIME: float = 1.8

## Width of the drawn ring outline (pixels).
const RING_WIDTH: float = 3.0

## Radius of the dot drawn at the sound origin (pixels).
const ORIGIN_DOT_RADIUS: float = 8.0

## Maximum number of simultaneous rings to prevent clutter.
const MAX_RINGS: int = 20

## Data for a single propagation ring being animated.
class SoundRing:
	var position: Vector2      ## World-space origin of the sound.
	var max_radius: float      ## Full propagation distance (pixels).
	var color: Color           ## Ring colour (based on source type).
	var age: float             ## Seconds since this ring was created.
	var label: String          ## Text label (sound type name).


## The canvas layer that sits above the game world.
var _canvas_layer: CanvasLayer = null

## The node2d that performs the actual draw calls.
var _draw_node: Node2D = null

## Active rings currently being animated.
var _rings: Array[SoundRing] = []


func _ready() -> void:
	# Create rendering nodes.
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.name = "SoundVisualizerCanvas"
	_canvas_layer.layer = 50   # Above game world, below UI menus.
	_canvas_layer.follow_viewport_enabled = true
	add_child(_canvas_layer)

	_draw_node = Node2D.new()
	_draw_node.name = "SoundVisualizerDraw"
	_canvas_layer.add_child(_draw_node)
	_draw_node.draw.connect(_on_draw)
	_draw_node.set_process(true)

	# Connect to SoundPropagation signal.
	var sound_propagation: Node = get_node_or_null("/root/SoundPropagation")
	if sound_propagation and sound_propagation.has_signal("sound_emitted"):
		sound_propagation.sound_emitted.connect(_on_sound_emitted)


func _process(delta: float) -> void:
	if _rings.is_empty():
		return
	# Age all rings and remove expired ones.
	for ring in _rings:
		ring.age += delta
	_rings = _rings.filter(func(r: SoundRing) -> bool: return r.age < RING_LIFETIME)
	_draw_node.queue_redraw()


## Called by SoundPropagation whenever a sound is emitted.
func _on_sound_emitted(sound_type: int, position: Vector2, source_type: int,
		propagation_distance: float) -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings == null or not experimental_settings.is_sound_visualizer_enabled():
		return

	# Drop oldest ring if at capacity.
	if _rings.size() >= MAX_RINGS:
		_rings.remove_at(0)

	var ring := SoundRing.new()
	ring.position = position
	ring.max_radius = propagation_distance
	ring.age = 0.0
	ring.label = _sound_type_name(sound_type)

	match source_type:
		1:  # SourceType.ENEMY
			ring.color = Color(1.0, 0.25, 0.25, 1.0)   # Red
		_:  # SourceType.PLAYER (0) or NEUTRAL (2)
			if source_type == 0:
				ring.color = Color(0.3, 0.6, 1.0, 1.0) # Blue
			else:
				ring.color = Color(0.9, 0.9, 0.9, 1.0) # White

	_rings.append(ring)
	_draw_node.queue_redraw()


## Draw all active rings.
func _on_draw() -> void:
	for ring in _rings:
		_draw_ring(ring)


func _draw_ring(ring: SoundRing) -> void:
	# Compute alpha (fade in during expand, hold, then fade out).
	var alpha: float
	if ring.age < EXPAND_DURATION:
		alpha = ring.age / EXPAND_DURATION
	else:
		var fade_start: float = RING_LIFETIME * 0.6
		if ring.age < fade_start:
			alpha = 1.0
		else:
			alpha = 1.0 - (ring.age - fade_start) / (RING_LIFETIME - fade_start)
	alpha = clampf(alpha, 0.0, 1.0)

	# Compute current radius (expands during EXPAND_DURATION, then stays at max).
	var t: float = clampf(ring.age / EXPAND_DURATION, 0.0, 1.0)
	var current_radius: float = ring.max_radius * t

	var c: Color = ring.color
	c.a = alpha

	# Draw propagation circle outline.
	_draw_node.draw_arc(ring.position, current_radius, 0.0, TAU, 64, c, RING_WIDTH, true)

	# Draw origin dot.
	var dot_color: Color = ring.color
	dot_color.a = alpha * 0.9
	_draw_node.draw_circle(ring.position, ORIGIN_DOT_RADIUS, dot_color)

	# Draw label.
	if alpha > 0.1:
		var label_pos: Vector2 = ring.position + Vector2(ORIGIN_DOT_RADIUS + 4.0, -8.0)
		var font: Font = ThemeDB.fallback_font
		if font:
			_draw_node.draw_string(font, label_pos, ring.label, HORIZONTAL_ALIGNMENT_LEFT,
					-1, 14, Color(1.0, 1.0, 1.0, alpha))


## Return a human-readable name for a SoundType int value.
func _sound_type_name(sound_type: int) -> String:
	# Mirror SoundPropagation.SoundType enum order.
	match sound_type:
		0: return "GUNSHOT"
		1: return "EXPLOSION"
		2: return "FOOTSTEP"
		3: return "RELOAD"
		4: return "IMPACT"
		5: return "EMPTY_CLICK"
		6: return "RELOAD_COMPLETE"
		7: return "GRENADE_LANDING"
		8: return "CASING_KICK"
		_: return "SOUND_%d" % sound_type
