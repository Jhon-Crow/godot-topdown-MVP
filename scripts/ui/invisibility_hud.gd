extends CanvasLayer
## HUD overlay for the invisibility suit (Issue #673).
##
## Displays charges remaining and active effect timer in the bottom-left corner.
## Created programmatically by the player when the invisibility suit is equipped.

## Label displaying charges and active effect status.
var _status_label: Label = null

## Current charges.
var _charges: int = 2

## Maximum charges.
var _max_charges: int = 2

## Whether the effect is currently active.
var _is_active: bool = false

## Remaining duration when active.
var _remaining_time: float = 0.0

## Reference to the invisibility suit effect for polling remaining time.
var _suit_effect: Node = null


func _ready() -> void:
	layer = 100  # On top of everything
	_build_ui()


## Build the HUD UI.
func _build_ui() -> void:
	_status_label = Label.new()
	_status_label.name = "InvisibilityStatusLabel"

	# Position in bottom-left corner, above the bottom edge
	_status_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_status_label.offset_left = 10.0
	_status_label.offset_bottom = -10.0
	_status_label.offset_top = -40.0
	_status_label.offset_right = 300.0

	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0, 0.9))

	# Add shadow for readability against any background
	_status_label.add_theme_constant_override("shadow_offset_x", 1)
	_status_label.add_theme_constant_override("shadow_offset_y", 1)
	_status_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))

	add_child(_status_label)
	_update_display()


## Initialize with suit effect reference.
func initialize(suit_effect: Node) -> void:
	_suit_effect = suit_effect
	if _suit_effect:
		_charges = _suit_effect.charges
		_max_charges = _suit_effect.MAX_CHARGES
	_update_display()


## Update charges display.
func update_charges(current: int, maximum: int) -> void:
	_charges = current
	_max_charges = maximum
	_update_display()


## Update active state.
func set_active(active: bool) -> void:
	_is_active = active
	_update_display()


func _process(_delta: float) -> void:
	if _is_active and _suit_effect and is_instance_valid(_suit_effect):
		_remaining_time = _suit_effect.get_remaining_time()
		_update_display()


## Update the label text based on current state.
func _update_display() -> void:
	if _status_label == null:
		return

	if _is_active:
		_status_label.text = "CLOAK: ACTIVE (%.1fs) [%d/%d]" % [_remaining_time, _charges, _max_charges]
		_status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.6, 0.95))
	elif _charges > 0:
		_status_label.text = "CLOAK: READY [%d/%d] (Space)" % [_charges, _max_charges]
		_status_label.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0, 0.9))
	else:
		_status_label.text = "CLOAK: DEPLETED [0/%d]" % _max_charges
		_status_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.7))
