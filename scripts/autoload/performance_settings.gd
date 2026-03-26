extends Node
## PerformanceSettings - Global performance toggles manager (Issue #1186).
##
## Provides toggles for every system that can affect performance.
## Use these to isolate unoptimized subsystems during profiling.
## All features are enabled by default (no change in default gameplay).

## Signal emitted when any performance setting changes.
signal settings_changed

## Whether particle effects are enabled (dust, blood spray, sparks, muzzle flash).
## When disabled, no GPUParticles2D are spawned on hits or weapon fire.
## Disabling this has a significant positive impact on GPU performance.
var particles_enabled: bool = true

## Whether blood decals on floors and walls are enabled.
## When disabled, no Sprite2D blood decals are placed on the floor/walls after hits.
## Disabling this reduces the number of Sprite2D nodes in the scene tree.
var blood_decals_enabled: bool = true

## Whether screen shake (camera recoil) is enabled.
## When disabled, the camera stays still while shooting.
## Uses the existing ScreenShakeManager.enabled flag.
var screen_shake_enabled: bool = true

## Whether explosion/flashbang lights (PointLight2D) are enabled.
## When disabled, grenade and flashbang explosions produce no dynamic light flash.
## PointLight2D is a known GPU bottleneck (Issue #724).
var explosion_lights_enabled: bool = true

## Whether vertical sync is enabled (Issue #1514).
## When disabled, the GPU renders frames without waiting for the display refresh.
## Disabling V-Sync can increase FPS on high-end hardware but may cause screen tearing.
var vsync_enabled: bool = true

## Maximum frames per second cap (Issue #1514).
## Valid values: 0 (unlimited), 30, 60, 120.
## Uses Engine.max_fps; 0 means no cap (default Godot behaviour).
var fps_limit: int = 0

## Whether AI is enabled for all enemies.
## When disabled, enemies do not process AI logic (they stand still).
## Disabling this helps identify the CPU cost of the AI system.
var ai_enabled: bool = true

## Per-state AI toggles (Issue #1186).
## When a state is disabled, enemies redirect to another state for performance profiling.
## Use these to isolate CPU cost of individual AI state logic.
var ai_state_idle_enabled: bool = true        ## IDLE state: patrol/guard scanning. Disable to force all enemies into active states.
var ai_state_combat_enabled: bool = true      ## COMBAT state: cover peek, shoot, return.
var ai_state_seeking_cover_enabled: bool = true  ## SEEKING_COVER state: pathfind to cover.
var ai_state_in_cover_enabled: bool = true    ## IN_COVER state: wait, peek-and-shoot.
var ai_state_flanking_enabled: bool = true    ## FLANKING state: flank movement logic.
var ai_state_suppressed_enabled: bool = true  ## SUPPRESSED state: stay in cover under fire.
var ai_state_retreating_enabled: bool = true  ## RETREATING state: retreat to cover.
var ai_state_pursuing_enabled: bool = true    ## PURSUING state: move cover-to-cover toward player.
var ai_state_assault_enabled: bool = true     ## ASSAULT state: coordinated rush.
var ai_state_searching_enabled: bool = true   ## SEARCHING state: search last known position.

## Settings file path for persistence.
const SETTINGS_PATH: String = "user://performance_settings.cfg"


func _ready() -> void:
	_load_settings()
	# Apply screen shake setting immediately
	_apply_screen_shake()
	# Apply vsync and fps limit immediately (Issue #1514)
	_apply_vsync()
	_apply_fps_limit()
	_log_to_file("PerformanceSettings initialized - particles: %s, blood_decals: %s, screen_shake: %s, explosion_lights: %s, ai: %s, vsync: %s, fps_limit: %s" % [
		particles_enabled, blood_decals_enabled, screen_shake_enabled, explosion_lights_enabled, ai_enabled, vsync_enabled, fps_limit])


## Set particles enabled/disabled (Issue #1186).
func set_particles_enabled(enabled: bool) -> void:
	if particles_enabled != enabled:
		particles_enabled = enabled
		settings_changed.emit()
		_save_settings()
		_log_to_file("Particles %s" % ("enabled" if enabled else "disabled"))


## Check if particles are enabled (Issue #1186).
func is_particles_enabled() -> bool:
	return particles_enabled


## Set blood decals enabled/disabled (Issue #1186).
func set_blood_decals_enabled(enabled: bool) -> void:
	if blood_decals_enabled != enabled:
		blood_decals_enabled = enabled
		settings_changed.emit()
		_save_settings()
		_log_to_file("Blood decals %s" % ("enabled" if enabled else "disabled"))


## Check if blood decals are enabled (Issue #1186).
func is_blood_decals_enabled() -> bool:
	return blood_decals_enabled


## Set screen shake enabled/disabled (Issue #1186).
func set_screen_shake_enabled(enabled: bool) -> void:
	if screen_shake_enabled != enabled:
		screen_shake_enabled = enabled
		_apply_screen_shake()
		settings_changed.emit()
		_save_settings()
		_log_to_file("Screen shake %s" % ("enabled" if enabled else "disabled"))


## Check if screen shake is enabled (Issue #1186).
func is_screen_shake_enabled() -> bool:
	return screen_shake_enabled


## Set explosion lights enabled/disabled (Issue #1186).
func set_explosion_lights_enabled(enabled: bool) -> void:
	if explosion_lights_enabled != enabled:
		explosion_lights_enabled = enabled
		settings_changed.emit()
		_save_settings()
		_log_to_file("Explosion lights %s" % ("enabled" if enabled else "disabled"))


## Check if explosion lights are enabled (Issue #1186).
func is_explosion_lights_enabled() -> bool:
	return explosion_lights_enabled


## Set AI enabled/disabled for all enemies (Issue #1186).
func set_ai_enabled(enabled: bool) -> void:
	if ai_enabled != enabled:
		ai_enabled = enabled
		settings_changed.emit()
		_save_settings()
		_log_to_file("AI %s" % ("enabled" if enabled else "disabled"))


## Check if AI is enabled (Issue #1186).
func is_ai_enabled() -> bool:
	return ai_enabled


## Set vertical sync enabled/disabled (Issue #1514).
func set_vsync_enabled(enabled: bool) -> void:
	if vsync_enabled != enabled:
		vsync_enabled = enabled
		_apply_vsync()
		settings_changed.emit()
		_save_settings()
		_log_to_file("V-Sync %s" % ("enabled" if enabled else "disabled"))


## Check if V-Sync is enabled (Issue #1514).
func is_vsync_enabled() -> bool:
	return vsync_enabled


## Set the FPS cap (Issue #1514).
## @param limit  0 = unlimited, or one of: 30, 60, 120.
func set_fps_limit(limit: int) -> void:
	if fps_limit != limit:
		fps_limit = limit
		_apply_fps_limit()
		settings_changed.emit()
		_save_settings()
		_log_to_file("FPS limit set to %s" % (str(limit) if limit > 0 else "unlimited"))


## Get the current FPS cap (Issue #1514).
func get_fps_limit() -> int:
	return fps_limit


## Per-state AI toggle getters/setters (Issue #1186).
func set_ai_state_idle_enabled(enabled: bool) -> void:
	if ai_state_idle_enabled != enabled:
		ai_state_idle_enabled = enabled; settings_changed.emit(); _save_settings()
		_log_to_file("AI state IDLE %s" % ("enabled" if enabled else "disabled"))

func is_ai_state_idle_enabled() -> bool: return ai_state_idle_enabled

func set_ai_state_combat_enabled(enabled: bool) -> void:
	if ai_state_combat_enabled != enabled:
		ai_state_combat_enabled = enabled; settings_changed.emit(); _save_settings()
		_log_to_file("AI state COMBAT %s" % ("enabled" if enabled else "disabled"))

func is_ai_state_combat_enabled() -> bool: return ai_state_combat_enabled

func set_ai_state_seeking_cover_enabled(enabled: bool) -> void:
	if ai_state_seeking_cover_enabled != enabled:
		ai_state_seeking_cover_enabled = enabled; settings_changed.emit(); _save_settings()
		_log_to_file("AI state SEEKING_COVER %s" % ("enabled" if enabled else "disabled"))

func is_ai_state_seeking_cover_enabled() -> bool: return ai_state_seeking_cover_enabled

func set_ai_state_in_cover_enabled(enabled: bool) -> void:
	if ai_state_in_cover_enabled != enabled:
		ai_state_in_cover_enabled = enabled; settings_changed.emit(); _save_settings()
		_log_to_file("AI state IN_COVER %s" % ("enabled" if enabled else "disabled"))

func is_ai_state_in_cover_enabled() -> bool: return ai_state_in_cover_enabled

func set_ai_state_flanking_enabled(enabled: bool) -> void:
	if ai_state_flanking_enabled != enabled:
		ai_state_flanking_enabled = enabled; settings_changed.emit(); _save_settings()
		_log_to_file("AI state FLANKING %s" % ("enabled" if enabled else "disabled"))

func is_ai_state_flanking_enabled() -> bool: return ai_state_flanking_enabled

func set_ai_state_suppressed_enabled(enabled: bool) -> void:
	if ai_state_suppressed_enabled != enabled:
		ai_state_suppressed_enabled = enabled; settings_changed.emit(); _save_settings()
		_log_to_file("AI state SUPPRESSED %s" % ("enabled" if enabled else "disabled"))

func is_ai_state_suppressed_enabled() -> bool: return ai_state_suppressed_enabled

func set_ai_state_retreating_enabled(enabled: bool) -> void:
	if ai_state_retreating_enabled != enabled:
		ai_state_retreating_enabled = enabled; settings_changed.emit(); _save_settings()
		_log_to_file("AI state RETREATING %s" % ("enabled" if enabled else "disabled"))

func is_ai_state_retreating_enabled() -> bool: return ai_state_retreating_enabled

func set_ai_state_pursuing_enabled(enabled: bool) -> void:
	if ai_state_pursuing_enabled != enabled:
		ai_state_pursuing_enabled = enabled; settings_changed.emit(); _save_settings()
		_log_to_file("AI state PURSUING %s" % ("enabled" if enabled else "disabled"))

func is_ai_state_pursuing_enabled() -> bool: return ai_state_pursuing_enabled

func set_ai_state_assault_enabled(enabled: bool) -> void:
	if ai_state_assault_enabled != enabled:
		ai_state_assault_enabled = enabled; settings_changed.emit(); _save_settings()
		_log_to_file("AI state ASSAULT %s" % ("enabled" if enabled else "disabled"))

func is_ai_state_assault_enabled() -> bool: return ai_state_assault_enabled

func set_ai_state_searching_enabled(enabled: bool) -> void:
	if ai_state_searching_enabled != enabled:
		ai_state_searching_enabled = enabled; settings_changed.emit(); _save_settings()
		_log_to_file("AI state SEARCHING %s" % ("enabled" if enabled else "disabled"))

func is_ai_state_searching_enabled() -> bool: return ai_state_searching_enabled


## Filter AI state - redirects disabled states (Issue #1186).
## Used by enemy.gd at transition time to skip disabled states during profiling.
## IDLE disabled -> SEARCHING (keeps enemies busy); other states disabled -> IDLE.
func filter_ai_state(state: int) -> int:
	match state:
		0: if not ai_state_idle_enabled: return 9          # IDLE -> SEARCHING
		1: if not ai_state_combat_enabled: return 0        # COMBAT -> IDLE
		2: if not ai_state_seeking_cover_enabled: return 0 # SEEKING_COVER -> IDLE
		3: if not ai_state_in_cover_enabled: return 0      # IN_COVER -> IDLE
		4: if not ai_state_flanking_enabled: return 0      # FLANKING -> IDLE
		5: if not ai_state_suppressed_enabled: return 0    # SUPPRESSED -> IDLE
		6: if not ai_state_retreating_enabled: return 0    # RETREATING -> IDLE
		7: if not ai_state_pursuing_enabled: return 0      # PURSUING -> IDLE
		8: if not ai_state_assault_enabled: return 0       # ASSAULT -> IDLE
		9: if not ai_state_searching_enabled: return 0     # SEARCHING -> IDLE
	return state


## Applies the V-Sync setting via DisplayServer (Issue #1514).
func _apply_vsync() -> void:
	var mode := DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED
	DisplayServer.window_set_vsync_mode(mode)


## Applies the FPS cap via Engine.max_fps (Issue #1514).
func _apply_fps_limit() -> void:
	Engine.max_fps = fps_limit


## Applies the screen shake setting to ScreenShakeManager.
func _apply_screen_shake() -> void:
	var ssm: Node = get_node_or_null("/root/ScreenShakeManager")
	if ssm and "enabled" in ssm:
		ssm.enabled = screen_shake_enabled


## Save settings to file.
func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("performance", "particles_enabled", particles_enabled)
	config.set_value("performance", "blood_decals_enabled", blood_decals_enabled)
	config.set_value("performance", "screen_shake_enabled", screen_shake_enabled)
	config.set_value("performance", "explosion_lights_enabled", explosion_lights_enabled)
	config.set_value("performance", "ai_enabled", ai_enabled)
	config.set_value("performance", "vsync_enabled", vsync_enabled)
	config.set_value("performance", "fps_limit", fps_limit)
	config.set_value("ai_states", "idle", ai_state_idle_enabled)
	config.set_value("ai_states", "combat", ai_state_combat_enabled)
	config.set_value("ai_states", "seeking_cover", ai_state_seeking_cover_enabled)
	config.set_value("ai_states", "in_cover", ai_state_in_cover_enabled)
	config.set_value("ai_states", "flanking", ai_state_flanking_enabled)
	config.set_value("ai_states", "suppressed", ai_state_suppressed_enabled)
	config.set_value("ai_states", "retreating", ai_state_retreating_enabled)
	config.set_value("ai_states", "pursuing", ai_state_pursuing_enabled)
	config.set_value("ai_states", "assault", ai_state_assault_enabled)
	config.set_value("ai_states", "searching", ai_state_searching_enabled)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("PerformanceSettings: Failed to save settings: " + str(error))


## Load settings from file.
func _load_settings() -> void:
	var config := ConfigFile.new()
	var error := config.load(SETTINGS_PATH)
	if error == OK:
		particles_enabled = config.get_value("performance", "particles_enabled", true)
		blood_decals_enabled = config.get_value("performance", "blood_decals_enabled", true)
		screen_shake_enabled = config.get_value("performance", "screen_shake_enabled", true)
		explosion_lights_enabled = config.get_value("performance", "explosion_lights_enabled", true)
		ai_enabled = config.get_value("performance", "ai_enabled", true)
		vsync_enabled = config.get_value("performance", "vsync_enabled", true)
		fps_limit = config.get_value("performance", "fps_limit", 0)
		ai_state_idle_enabled = config.get_value("ai_states", "idle", true)
		ai_state_combat_enabled = config.get_value("ai_states", "combat", true)
		ai_state_seeking_cover_enabled = config.get_value("ai_states", "seeking_cover", true)
		ai_state_in_cover_enabled = config.get_value("ai_states", "in_cover", true)
		ai_state_flanking_enabled = config.get_value("ai_states", "flanking", true)
		ai_state_suppressed_enabled = config.get_value("ai_states", "suppressed", true)
		ai_state_retreating_enabled = config.get_value("ai_states", "retreating", true)
		ai_state_pursuing_enabled = config.get_value("ai_states", "pursuing", true)
		ai_state_assault_enabled = config.get_value("ai_states", "assault", true)
		ai_state_searching_enabled = config.get_value("ai_states", "searching", true)
	else:
		particles_enabled = true
		blood_decals_enabled = true
		screen_shake_enabled = true
		explosion_lights_enabled = true
		ai_enabled = true
		vsync_enabled = true
		fps_limit = 0
		ai_state_idle_enabled = true
		ai_state_combat_enabled = true
		ai_state_seeking_cover_enabled = true
		ai_state_in_cover_enabled = true
		ai_state_flanking_enabled = true
		ai_state_suppressed_enabled = true
		ai_state_retreating_enabled = true
		ai_state_pursuing_enabled = true
		ai_state_assault_enabled = true
		ai_state_searching_enabled = true


## Log a message to the file logger if available.
func _log_to_file(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[PerformanceSettings] " + message)
	else:
		print("[PerformanceSettings] " + message)
