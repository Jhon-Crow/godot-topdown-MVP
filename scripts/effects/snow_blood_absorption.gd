extends Node2D
## Blood-soaked snow decal (Issue #1627).
##
## When blood lands on the Winter Forest snow surface this node replaces the
## standard BloodDecal puddle. Key differences from BloodDecal:
##  - NOT added to the "blood_puddle" group → stepping on it does NOT trigger
##    BloodyFeetComponent (requirement #3: stained snow must not generate
##    bloody footprints).
##  - Rendered procedurally as a blood-stained snow patch (no external texture).
##  - Absorbs slowly: fades over ABSORB_DURATION seconds (blood soaks in).
##  - Small random spread to look like blood hitting compacted snow, not pooling.
class_name SnowBloodAbsorption

## Duration for blood to be absorbed into snow (fade-out, seconds).
const ABSORB_DURATION: float = 18.0

## Initial alpha for the stain.
const INITIAL_ALPHA: float = 0.78

## Outer spread radius of the stain (pixels).
const STAIN_RADIUS: float = 14.0

## Blood colour (set by spawner when blood hits the snow).
var _blood_color: Color = Color(0.55, 0.02, 0.02, INITIAL_ALPHA)

## Elapsed time.
var _elapsed: float = 0.0

## Whether absorption is complete.
var _done: bool = false


func _ready() -> void:
	# Render above snow background but below characters.
	z_index = 0


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	if _elapsed >= ABSORB_DURATION:
		_done = true
		queue_free()
	else:
		queue_redraw()


func _draw() -> void:
	if _done:
		return

	var t: float = _elapsed / ABSORB_DURATION  # 0 → 1

	# Stain slightly expands at first (blood spreading on snow surface),
	# then colour fades as it is absorbed.
	var expand_t: float = clampf(_elapsed / 1.2, 0.0, 1.0)
	var radius: float = STAIN_RADIUS * (0.5 + 0.5 * (1.0 - pow(1.0 - expand_t, 2.0)))

	# Alpha: stays at INITIAL_ALPHA for most of duration, then fades out.
	var fade_start: float = 0.55
	var alpha_t: float = clampf((t - fade_start) / (1.0 - fade_start), 0.0, 1.0)
	var alpha: float = INITIAL_ALPHA * (1.0 - alpha_t * alpha_t)

	# The stain blends blood colour with snow (gets lighter and more greyish-pink
	# as blood is absorbed, not pure red).
	var stain_col: Color = _blood_color
	stain_col.a = alpha

	# Draw 3 soft concentric ellipses for an organic, uneven stain shape.
	for i in range(3):
		var r: float = radius * (0.45 + 0.28 * i)
		# Slightly squish the shape to look like a splatter, not a perfect circle.
		var rx: float = r * (0.9 + 0.1 * float(i))
		var ry: float = r * (1.0 - 0.1 * float(i))
		var col: Color = stain_col
		col.a = alpha * (1.0 - 0.22 * float(i))
		if col.a > 0.01:
			_draw_ellipse_filled(Vector2.ZERO, rx, ry, col)


## Draws a filled ellipse with SEGMENTS vertices.
func _draw_ellipse_filled(center: Vector2, rx: float, ry: float, color: Color) -> void:
	const SEGMENTS: int = 16
	var pts: PackedVector2Array = PackedVector2Array()
	for i in range(SEGMENTS):
		var angle: float = TAU * float(i) / float(SEGMENTS)
		pts.append(center + Vector2(cos(angle) * rx, sin(angle) * ry))
	draw_colored_polygon(pts, color)


## Sets the blood colour. Called by the spawner (WinterForestLevel or BloodEffect).
func set_blood_color(color: Color) -> void:
	_blood_color = Color(color.r, color.g, color.b, INITIAL_ALPHA)
