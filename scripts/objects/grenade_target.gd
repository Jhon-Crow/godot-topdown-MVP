extends Area2D
## Target that tracks grenade hits for training.
##
## Used in the grenade training area of the tutorial level.
## Supports two types: targets that should be hit (valid) and targets
## that should NOT be hit (friendly/civilian).
##
## Provides visual feedback when hit by grenades and emits signals
## for tracking player performance.

## Signal emitted when the target is affected by a grenade.
signal grenade_hit(is_valid_target: bool)

## Signal emitted when the target receives a status effect from grenade.
signal status_effect_received(effect_type: String, duration: float)

## Whether this is a valid target (should be hit) or not (should NOT be hit).
@export var is_valid_target: bool = true

## Color for valid targets (enemies) - red.
@export var valid_target_color: Color = Color(0.9, 0.2, 0.2, 1.0)

## Color for invalid targets (friendlies/civilians) - green.
@export var invalid_target_color: Color = Color(0.2, 0.9, 0.2, 1.0)

## Color when hit by grenade (flash white briefly).
@export var hit_flash_color: Color = Color(1.0, 1.0, 1.0, 1.0)

## Color when blinded by flashbang.
@export var blind_color: Color = Color(1.0, 1.0, 0.5, 1.0)  # Yellow tint

## Color when stunned by flashbang.
@export var stun_color: Color = Color(0.5, 0.5, 1.0, 1.0)  # Blue tint

## Reference to the sprite for color changes.
@onready var sprite: Sprite2D = $Sprite2D

## Reference to the label showing target type.
@onready var label: Label = $Label if has_node("Label") else null

## Whether the target is blinded.
var _is_blinded: bool = false

## Whether the target is stunned.
var _is_stunned: bool = false


func _ready() -> void:
	# Add to enemies group so grenades can detect us
	add_to_group("enemies")

	# Set initial visual state
	_update_visual_state()

	# Update label if present
	if label:
		label.text = "ВРАГ" if is_valid_target else "СВОИХ"
		label.add_theme_color_override("font_color", valid_target_color if is_valid_target else invalid_target_color)


## Apply blindness effect from flashbang grenade.
func apply_blindness(duration: float) -> void:
	if _is_blinded:
		return

	_is_blinded = true
	status_effect_received.emit("blindness", duration)
	grenade_hit.emit(is_valid_target)
	FileLogger.info("[GrenadeTarget] %s (valid=%s) blinded for %.1f seconds" % [name, is_valid_target, duration])

	# Flash white briefly then show blind color
	if sprite:
		sprite.modulate = hit_flash_color
		await get_tree().create_timer(0.1).timeout
		sprite.modulate = blind_color

	# Reset after duration
	await get_tree().create_timer(duration - 0.1).timeout
	_is_blinded = false
	_update_visual_state()


## Apply stun effect from flashbang grenade.
func apply_stun(duration: float) -> void:
	if _is_stunned:
		return

	_is_stunned = true
	status_effect_received.emit("stun", duration)
	# Don't emit grenade_hit here since apply_blindness is usually called first
	FileLogger.info("[GrenadeTarget] %s (valid=%s) stunned for %.1f seconds" % [name, is_valid_target, duration])

	# Show stun color (overrides blind color)
	if sprite:
		sprite.modulate = stun_color

	# Reset after duration
	await get_tree().create_timer(duration).timeout
	_is_stunned = false
	_update_visual_state()


## Update visual state based on current status effects and target type.
func _update_visual_state() -> void:
	if not sprite:
		return

	if _is_stunned:
		sprite.modulate = stun_color
	elif _is_blinded:
		sprite.modulate = blind_color
	else:
		sprite.modulate = valid_target_color if is_valid_target else invalid_target_color
