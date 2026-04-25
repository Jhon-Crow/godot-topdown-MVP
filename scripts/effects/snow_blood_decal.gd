extends Sprite2D
## Blood absorbed by snow on the Winter Forest map (Issue #1627).
##
## Unlike BloodDecal (which forms an interactive puddle that transfers blood to boots),
## SnowBloodDecal represents blood that has been absorbed by the snow surface.
## Key differences from BloodDecal:
##   - Does NOT join the "blood_puddle" group → BloodyFeetComponent never detects it,
##     so bloody footprints are never generated from snow-absorbed blood.
##   - Does NOT create an Area2D → fully passive decal with no collision overhead.
##   - Applies a desaturated tint to indicate absorbed/frozen blood (darker red/pink tinge).
##   - Auto-fades after fade_delay seconds (default 60 s) to represent snow covering the stain.
##
## Usage: Spawn this scene instead of BloodDecal whenever blood lands on the Winter Forest
## snow tiles.  The caller sets the position and optionally overrides blood_color.
class_name SnowBloodDecal

## Time in seconds before the stain begins fading (snow slowly covers the blood).
@export var fade_delay: float = 60.0

## Duration of the fade-out tween.
@export var fade_duration: float = 8.0

## Blood color that will be desaturated/tinted to look absorbed by snow.
## Set this before adding the node to the scene tree to control the appearance.
@export var blood_color: Color = Color(0.55, 0.05, 0.05, 1.0)

## Initial alpha (partially transparent — snow doesn't hold vivid color well).
var _initial_alpha: float = 0.6


func _ready() -> void:
	# Apply desaturated snow-absorbed blood appearance.
	_apply_snow_tint()

	# NOT added to "blood_puddle" group — absorbed blood cannot be walked in.

	# Always auto-fade: snow gradually covers the stain.
	_start_fade_timer()


## Applies a tinted modulate color simulating blood absorbed into snow:
## the red channel is preserved but green/blue are raised to create a faded,
## icy appearance rather than a vivid wet puddle.
func _apply_snow_tint() -> void:
	# Mix blood color toward light grey/pink to simulate absorption.
	var absorbed_r := lerpf(blood_color.r, 0.75, 0.35)
	var absorbed_g := lerpf(blood_color.g, 0.70, 0.5)
	var absorbed_b := lerpf(blood_color.b, 0.72, 0.5)
	modulate = Color(absorbed_r, absorbed_g, absorbed_b, _initial_alpha)


## Starts the fade timer so the stain disappears after fade_delay seconds.
func _start_fade_timer() -> void:
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(fade_delay).timeout

	if not is_instance_valid(self) or not is_inside_tree():
		return

	var tween := create_tween()
	if tween == null:
		queue_free()
		return
	tween.tween_property(self, "modulate:a", 0.0, fade_duration)
	tween.tween_callback(queue_free)


## Immediately removes the decal.
func remove() -> void:
	queue_free()
