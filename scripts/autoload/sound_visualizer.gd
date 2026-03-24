extends Node
## SoundVisualizer — Debug overlay for sound propagation (Issue #1253).
##
## When enabled via the Experimental menu, draws an animated ripple effect at
## each sound emission point to clearly show how far the sound travels.
##
## Visualisation elements (all drawn in world-space via CanvasLayer):
##   1. Boundary ring  — a thick, bright ring drawn at the full propagation
##                       radius so the exact hearing limit is always visible.
##   2. Travelling ripples — multiple thin rings that expand from the origin
##                       outward over time, making the wave motion obvious.
##   3. Origin dot     — a small filled circle at the sound source.
##   4. Distance label — the propagation radius in pixels printed near the
##                       boundary ring so the exact value is readable.
##   5. Sound-type label — short text tag (GUNSHOT, RELOAD, …) at origin.
##
## Colour coding by source type:
##   - Blue  : player sounds
##   - Red   : enemy sounds
##   - White : neutral / environmental sounds
##
## Depends on:
##   - SoundPropagation autoload (connects to its sound_emitted signal)
##   - ExperimentalSettings autoload (checked before drawing)

# ---------------------------------------------------------------------------
# Timing constants
# ---------------------------------------------------------------------------

## Duration each travelling ripple ring takes to expand from origin to max_radius (s).
const RIPPLE_TRAVEL_DURATION: float = 1.2

## How often a new ripple is spawned per sound event (s).  Three ripples are
## spawned at t=0, t=RIPPLE_INTERVAL and t=RIPPLE_INTERVAL*2.
const RIPPLE_INTERVAL: float = 0.35

## How long the boundary ring is displayed after a sound is emitted (s).
const BOUNDARY_LIFETIME: float = 2.2

## How long the origin dot is visible (s).
const DOT_LIFETIME: float = 1.8

## Total lifetime of a sound event (drives removal from _events array).
const EVENT_LIFETIME: float = BOUNDARY_LIFETIME

# ---------------------------------------------------------------------------
# Appearance constants
# ---------------------------------------------------------------------------

## Width of each travelling ripple ring (pixels).
const RIPPLE_WIDTH: float = 2.5

## Width of the static boundary ring (pixels).
const BOUNDARY_WIDTH: float = 4.0

## Radius of the origin dot (pixels).
const ORIGIN_DOT_RADIUS: float = 7.0

## Number of arc segments used to draw circles (higher = smoother).
const ARC_SEGMENTS: int = 80

## Maximum simultaneous sound events tracked.
const MAX_EVENTS: int = 20

## Number of ripple rings spawned per sound event.
const RIPPLE_COUNT: int = 3

# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------

## Represents one travelling ripple ring within a sound event.
class Ripple:
	var birth_time: float  ## Age (s) at which this ripple started expanding.
	func _init(t: float) -> void:
		birth_time = t


## Represents a complete sound event (one call to emit_sound).
class SoundEvent:
	var position: Vector2         ## World-space origin.
	var max_radius: float         ## Full propagation distance (pixels).
	var color: Color              ## Ring colour (source type).
	var age: float                ## Seconds since this event was created.
	var label: String             ## Sound type name ("GUNSHOT", …).
	var ripples: Array[Ripple]    ## Active ripple rings.

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------

var _canvas_layer: CanvasLayer = null
var _draw_node: Node2D = null
var _events: Array[SoundEvent] = []


func _ready() -> void:
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.name = "SoundVisualizerCanvas"
	# Issue #1392: raised above visual effects (layers 97-103) to remain visible.
	_canvas_layer.layer = 150
	_canvas_layer.follow_viewport_enabled = true
	add_child(_canvas_layer)

	_draw_node = Node2D.new()
	_draw_node.name = "SoundVisualizerDraw"
	_canvas_layer.add_child(_draw_node)
	_draw_node.draw.connect(_on_draw)
	_draw_node.set_process(true)

	var sound_propagation: Node = get_node_or_null("/root/SoundPropagation")
	if sound_propagation and sound_propagation.has_signal("sound_emitted"):
		sound_propagation.sound_emitted.connect(_on_sound_emitted)


func _process(delta: float) -> void:
	if _events.is_empty():
		return
	for ev in _events:
		ev.age += delta
	_events = _events.filter(func(e: SoundEvent) -> bool: return e.age < EVENT_LIFETIME)
	_draw_node.queue_redraw()


## Called by SoundPropagation whenever a sound is emitted.
func _on_sound_emitted(sound_type: int, position: Vector2, source_type: int,
		propagation_distance: float) -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings == null or not experimental_settings.is_sound_visualizer_enabled():
		return

	if _events.size() >= MAX_EVENTS:
		_events.remove_at(0)

	var ev := SoundEvent.new()
	ev.position = position
	ev.max_radius = propagation_distance
	ev.age = 0.0
	ev.label = _sound_type_name(sound_type)

	match source_type:
		1:  ev.color = Color(1.0, 0.3, 0.3, 1.0)   # Red   — enemy
		0:  ev.color = Color(0.35, 0.65, 1.0, 1.0)  # Blue  — player
		_:  ev.color = Color(0.9, 0.9, 0.9, 1.0)    # White — neutral

	# Spawn RIPPLE_COUNT ripple rings staggered in time.
	for i in range(RIPPLE_COUNT):
		var r := Ripple.new(i * RIPPLE_INTERVAL)
		ev.ripples.append(r)

	_events.append(ev)
	_draw_node.queue_redraw()


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _on_draw() -> void:
	for ev in _events:
		_draw_event(ev)


func _draw_event(ev: SoundEvent) -> void:
	# 1. Boundary ring — visible from the moment the first ripple would reach
	#    it until the event expires.
	var boundary_alpha: float = _boundary_alpha(ev)
	if boundary_alpha > 0.0:
		var bc: Color = ev.color
		bc.a = boundary_alpha
		# Outer glow (wider, more transparent).
		var glow_c: Color = bc
		glow_c.a *= 0.35
		_draw_node.draw_arc(ev.position, ev.max_radius, 0.0, TAU, ARC_SEGMENTS,
				glow_c, BOUNDARY_WIDTH * 2.5, true)
		# Main boundary ring.
		_draw_node.draw_arc(ev.position, ev.max_radius, 0.0, TAU, ARC_SEGMENTS,
				bc, BOUNDARY_WIDTH, true)

	# 2. Travelling ripple rings.
	for ripple in ev.ripples:
		_draw_ripple(ev, ripple)

	# 3. Origin dot.
	if ev.age < DOT_LIFETIME:
		var dot_alpha: float = 1.0 - (ev.age / DOT_LIFETIME)
		dot_alpha = clampf(dot_alpha, 0.0, 1.0)
		var dc: Color = ev.color
		dc.a = dot_alpha
		_draw_node.draw_circle(ev.position, ORIGIN_DOT_RADIUS, dc)

	# 4. Labels (sound type + radius value) — anchored near the origin.
	if boundary_alpha > 0.1:
		var font: Font = ThemeDB.fallback_font
		if font:
			# Sound type label at origin (offset slightly so it does not overlap the dot).
			var origin_label_pos: Vector2 = ev.position + Vector2(ORIGIN_DOT_RADIUS + 5.0, -10.0)
			_draw_node.draw_string(font, origin_label_pos, ev.label,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
					Color(1.0, 1.0, 1.0, boundary_alpha))

			# Radius value label — placed near the origin so it stays on screen
			# even when the boundary ring extends beyond the viewport (Issue #1429).
			var radius_text: String = "%.0f px" % ev.max_radius
			var radius_label_pos: Vector2 = ev.position + Vector2(ORIGIN_DOT_RADIUS + 5.0, 6.0)
			var lc: Color = ev.color
			lc.a = boundary_alpha
			_draw_node.draw_string(font, radius_label_pos, radius_text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 13, lc)


func _draw_ripple(ev: SoundEvent, ripple: Ripple) -> void:
	## Age of this particular ripple relative to its birth_time.
	var ripple_age: float = ev.age - ripple.birth_time
	if ripple_age <= 0.0:
		return  # Not started yet.

	## Normalised progress 0→1 over the travel duration.
	var t: float = ripple_age / RIPPLE_TRAVEL_DURATION
	if t > 1.0:
		return  # Finished travelling — no longer drawn.

	## Ease-out so the ring decelerates as it approaches the boundary.
	var eased_t: float = 1.0 - pow(1.0 - t, 2.0)
	var current_radius: float = ev.max_radius * eased_t

	## Fade: bright in the first half, fade out as it reaches the boundary.
	var alpha: float
	if t < 0.4:
		alpha = t / 0.4   # Fade in.
	else:
		alpha = 1.0 - (t - 0.4) / 0.6  # Fade out towards boundary.
	alpha = clampf(alpha, 0.0, 1.0)

	var rc: Color = ev.color
	rc.a = alpha * 0.85
	_draw_node.draw_arc(ev.position, current_radius, 0.0, TAU, ARC_SEGMENTS,
			rc, RIPPLE_WIDTH, true)


## Compute alpha for the static boundary ring.
## It fades in when the first ripple is ~70 % of the way out, then fades out
## near the end of the event lifetime.
func _boundary_alpha(ev: SoundEvent) -> float:
	var first_ripple_reach: float = RIPPLE_TRAVEL_DURATION  # When ripple 0 hits max_radius.
	var fade_in_start: float = first_ripple_reach * 0.7
	var fade_in_end: float = first_ripple_reach
	var fade_out_start: float = BOUNDARY_LIFETIME * 0.7
	var alpha: float
	if ev.age < fade_in_start:
		alpha = 0.0
	elif ev.age < fade_in_end:
		alpha = (ev.age - fade_in_start) / (fade_in_end - fade_in_start)
	elif ev.age < fade_out_start:
		alpha = 1.0
	else:
		alpha = 1.0 - (ev.age - fade_out_start) / (BOUNDARY_LIFETIME - fade_out_start)
	return clampf(alpha, 0.0, 1.0)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Return a human-readable name for a SoundType int value.
func _sound_type_name(sound_type: int) -> String:
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
