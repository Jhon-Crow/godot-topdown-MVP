extends Sprite2D
## Bloody footprint decal that persists on the floor.
##
## Blood footprints are spawned when characters walk after stepping
## in blood puddles. Alpha is set at spawn time (no fade animation).
class_name BloodFootprint

## Initial alpha value (set by spawner based on step count).
var _initial_alpha: float = 0.8


func _ready() -> void:
	# Ensure footprint renders above floor but below characters
	# Higher z_index = rendered on top in Godot
	z_index = 1


## Sets the footprint's alpha value.
## Called by BloodyFeetComponent when spawning.
func set_alpha(alpha: float) -> void:
	_initial_alpha = alpha
	modulate.a = alpha


## Immediately removes the footprint.
func remove() -> void:
	queue_free()
