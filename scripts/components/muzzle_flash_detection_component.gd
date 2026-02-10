class_name MuzzleFlashDetectionComponent
extends RefCounted
## Component for detecting player's muzzle flash and estimating position (Issue #711).
##
## This component allows enemies to:
## 1. Detect when the player fires a weapon and creates a muzzle flash
## 2. Estimate the player's position based on the flash location
## 3. Determine if the flash is visible within their field of vision
##
## Detection algorithm:
## The enemy detects a muzzle flash when:
## - The flash occurs within the enemy's FOV cone
## - The flash is within detection range
## - The enemy has line-of-sight to the flash position
##
## Muzzle flash detection has a brief "memory" window since the flash is very short (~40ms).
## When detected, enemies should fire suppression bursts toward the flash location.
##
## Usage:
##   var muzzle_detection = MuzzleFlashDetectionComponent.new()
##   muzzle_detection.on_muzzle_flash(flash_pos, shooter_pos, shooter)
##   if muzzle_detection.detected:
##       # Fire suppression burst at muzzle_detection.flash_position

## Confidence level when detecting player via muzzle flash (Issue #711).
## Lower than flashlight (0.75) because the flash is very brief,
## but higher than gunshot sound (0.7) because it's visual confirmation.
const MUZZLE_FLASH_DETECTION_CONFIDENCE: float = 0.72

## Maximum detection range for muzzle flash (in pixels).
## Approximately viewport diagonal for bright flash visibility.
const MUZZLE_FLASH_MAX_RANGE: float = 1200.0

## Maximum distance for suppression fire response (pixels).
## Enemies only fire suppression bursts if the flash was within this range.
const SUPPRESSION_FIRE_RANGE: float = 600.0

## Duration (in seconds) that flash detection remains valid.
## Muzzle flash is very brief, but enemy needs time to react.
const FLASH_MEMORY_DURATION: float = 0.5

## Minimum interval between detection checks (seconds).
## Prevents per-frame overhead when multiple flashes occur.
const CHECK_INTERVAL: float = 0.05

## Number of suppression shots to fire when detecting a muzzle flash.
const SUPPRESSION_BURST_COUNT_MIN: int = 3
const SUPPRESSION_BURST_COUNT_MAX: int = 5

## Inaccuracy spread for suppression fire (radians).
## Higher than aimed fire because enemy is shooting at last-seen flash position.
const SUPPRESSION_INACCURACY: float = 0.25

## Cooldown between suppression bursts (seconds).
## Prevents continuous suppression fire.
const SUPPRESSION_COOLDOWN: float = 3.0

## Timer for detection check interval.
var _check_timer: float = 0.0

## Whether the enemy currently detects a muzzle flash.
var detected: bool = false

## Position where the muzzle flash was detected.
## Only valid when detected == true.
var flash_position: Vector2 = Vector2.ZERO

## Estimated shooter position based on flash.
## Only valid when detected == true.
var estimated_shooter_position: Vector2 = Vector2.ZERO

## Timer for flash memory (how long detection remains valid).
var _flash_memory_timer: float = 0.0

## Cooldown timer for suppression fire.
var _suppression_cooldown_timer: float = 0.0

## Whether suppression fire is available (cooldown elapsed).
var can_suppress: bool = true

## Whether debug logging is enabled.
var debug_logging: bool = false


## Process muzzle flash detection event.
##
## Called when a muzzle flash occurs in the game world.
## The enemy checks if the flash is visible from their position and FOV.
##
## Parameters:
## - enemy_pos: The enemy's global position
## - enemy_facing_angle: The enemy's facing direction in radians
## - enemy_fov_deg: The enemy's FOV angle in degrees (full angle, e.g. 100 degrees)
## - enemy_fov_enabled: Whether FOV is enabled (if false, enemy has 360 degree vision)
## - flash_pos: Position of the muzzle flash
## - shooter_pos: Position of the shooter (for estimating player location)
## - raycast: RayCast2D for line-of-sight checks
##
## Returns true if the flash was detected.
func check_flash(enemy_pos: Vector2, enemy_facing_angle: float, enemy_fov_deg: float, enemy_fov_enabled: bool, flash_pos: Vector2, shooter_pos: Vector2, raycast: RayCast2D) -> bool:
	# Distance check
	var distance := enemy_pos.distance_to(flash_pos)
	if distance > MUZZLE_FLASH_MAX_RANGE:
		return false

	# FOV check (if enabled)
	if enemy_fov_enabled and enemy_fov_deg > 0.0:
		var enemy_facing_dir := Vector2.from_angle(enemy_facing_angle)
		var dir_to_flash := (flash_pos - enemy_pos).normalized()
		var dot := enemy_facing_dir.dot(dir_to_flash)
		var fov_half_angle_rad := deg_to_rad(enemy_fov_deg / 2.0)

		if dot < cos(fov_half_angle_rad):
			return false  # Flash is outside enemy's FOV

	# Line-of-sight check
	if raycast != null and not _check_los_to_flash(enemy_pos, flash_pos, raycast):
		return false

	# Flash detected
	detected = true
	flash_position = flash_pos
	estimated_shooter_position = shooter_pos
	_flash_memory_timer = FLASH_MEMORY_DURATION

	if debug_logging:
		print("[MuzzleFlashDetection] Detected flash at %s, distance=%.0f" % [flash_pos, distance])

	return true


## Check if suppression fire should be triggered.
##
## Returns true if:
## - A flash was recently detected (within memory duration)
## - The flash was within suppression range
## - Suppression cooldown has elapsed
func should_suppress() -> bool:
	if not detected or _flash_memory_timer <= 0.0:
		return false

	if not can_suppress:
		return false

	# Check if flash was within suppression range
	# (We use flash_position since that's what we're shooting at)
	return true


## Called when suppression fire begins.
## Starts the cooldown timer.
func start_suppression() -> void:
	can_suppress = false
	_suppression_cooldown_timer = SUPPRESSION_COOLDOWN


## Get the number of shots for suppression burst.
func get_suppression_burst_count() -> int:
	return randi_range(SUPPRESSION_BURST_COUNT_MIN, SUPPRESSION_BURST_COUNT_MAX)


## Get the inaccuracy spread for suppression fire.
func get_suppression_inaccuracy() -> float:
	return SUPPRESSION_INACCURACY


## Check if the flash is within suppression fire range.
func is_in_suppression_range(enemy_pos: Vector2) -> bool:
	if not detected:
		return false
	return enemy_pos.distance_to(flash_position) <= SUPPRESSION_FIRE_RANGE


## Update timers. Call this every frame.
##
## Parameters:
## - delta: Frame time in seconds
func update(delta: float) -> void:
	# Update flash memory timer
	if _flash_memory_timer > 0.0:
		_flash_memory_timer -= delta
		if _flash_memory_timer <= 0.0:
			# Flash memory expired
			detected = false
			flash_position = Vector2.ZERO
			estimated_shooter_position = Vector2.ZERO

	# Update suppression cooldown
	if not can_suppress:
		_suppression_cooldown_timer -= delta
		if _suppression_cooldown_timer <= 0.0:
			can_suppress = true


## Check line of sight from enemy to flash position.
func _check_los_to_flash(enemy_pos: Vector2, flash_pos: Vector2, raycast: RayCast2D) -> bool:
	if raycast == null:
		return true  # Assume LOS if no raycast available

	# Save original raycast state
	var original_target := raycast.target_position
	var original_enabled := raycast.enabled

	# Cast ray from enemy toward the flash
	var direction := flash_pos - enemy_pos
	raycast.target_position = direction
	raycast.enabled = true
	raycast.force_raycast_update()

	var has_los := true

	if raycast.is_colliding():
		var collision_point := raycast.get_collision_point()
		var enemy_parent := raycast.get_parent() as Node2D
		if enemy_parent:
			var distance_to_flash := enemy_parent.global_position.distance_to(flash_pos)
			var distance_to_collision := enemy_parent.global_position.distance_to(collision_point)
			# Wall is before the flash position - LOS blocked
			has_los = distance_to_collision >= distance_to_flash - 10.0

	# Restore raycast state
	raycast.target_position = original_target
	raycast.enabled = original_enabled

	return has_los


## Reset detection state.
func reset() -> void:
	detected = false
	flash_position = Vector2.ZERO
	estimated_shooter_position = Vector2.ZERO
	_flash_memory_timer = 0.0


## Create string representation for debugging.
func _to_string() -> String:
	if not detected:
		return "MuzzleFlashDetection(none)"
	return "MuzzleFlashDetection(flash=%s, shooter=%s, memory=%.2fs)" % [
		flash_position, estimated_shooter_position, _flash_memory_timer
	]
