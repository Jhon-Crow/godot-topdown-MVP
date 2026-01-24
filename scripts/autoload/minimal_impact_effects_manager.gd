extends Node
## Minimal ImpactEffectsManager for testing autoload loading

## Preloaded particle effect scenes.
var _dust_effect_scene: PackedScene = null
var _blood_effect_scene: PackedScene = null
var _sparks_effect_scene: PackedScene = null
var _blood_decal_scene: PackedScene = null

## Reference to FileLogger for persistent logging.
var _file_logger: Node = null


func _ready() -> void:
	# CRITICAL: First line diagnostic - if this doesn't appear, script failed to load
	print("[ImpactEffectsManager] _ready() STARTING...")

	# Get FileLogger reference - print diagnostic if it fails
	_file_logger = get_node_or_null("/root/FileLogger")
	if _file_logger == null:
		print("[ImpactEffectsManager] WARNING: FileLogger not found at /root/FileLogger")

	_preload_effect_scenes()
	print("[ImpactEffectsManager] ImpactEffectsManager ready - scenes loaded")


## Logs to FileLogger and always prints to console for diagnostics.
func _log_info(message: String) -> void:
	var log_message := "[ImpactEffects] " + message
	# Always print to console for debugging exported builds
	print(log_message)
	# Also write to file logger if available
	if _file_logger and _file_logger.has_method("log_info"):
		_file_logger.log_info(log_message)


## Preloads all particle effect scenes for efficient instantiation.
func _preload_effect_scenes() -> void:
	# Load effect scenes if they exist
	var blood_path := "res://scenes/effects/BloodEffect.tscn"

	if ResourceLoader.exists(blood_path):
		_blood_effect_scene = load(blood_path)
		print("[ImpactEffectsManager] Loaded BloodEffect scene")
	else:
		print("[ImpactEffectsManager] BloodEffect scene not found")

	var blood_decal_path := "res://scenes/effects/BloodDecal.tscn"
	if ResourceLoader.exists(blood_decal_path):
		_blood_decal_scene = load(blood_decal_path)
		print("[ImpactEffectsManager] Loaded BloodDecal scene")
	else:
		print("[ImpactEffectsManager] BloodDecal scene not found")


## Spawns a blood splatter effect at the given position for lethal hits.
func spawn_blood_effect(position: Vector2, hit_direction: Vector2, caliber_data: Resource = null, is_lethal: bool = true) -> void:
	_log_info("spawn_blood_effect called at %s" % position)
	print("[ImpactEffectsManager] spawn_blood_effect called")