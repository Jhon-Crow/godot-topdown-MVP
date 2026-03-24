class_name EnemyForceFieldComponent
extends Node
## Manages the Force Field for enemies that have has_force_field=true (Issue #1034).
## Extracted from enemy.gd to keep file under CI line limit.
##
## The force field activates when the enemy spots the player or companion,
## stays active for DURATION seconds, then recharges for RECHARGE_TIME seconds.
## While active the enemy ignores suppression (handled in enemy.gd via is_active()).
## A recharge progress bar is shown above the enemy during the recharge phase.

## Duration the force field stays active (seconds).
const DURATION: float = 4.0
## Recharge time after the force field deactivates (seconds).
const RECHARGE_TIME: float = 5.0

var _force_field_effect: Node2D = null  ## ForceFieldEffect instance
var _active: bool = false  ## Force field currently active
var _timer: float = 0.0  ## Counts down while active
var _recharging: bool = false  ## True while recharging after deactivation
var _recharge_elapsed: float = 0.0  ## Recharge elapsed time
var _progress_bar: ActiveItemProgressBar = null  ## Recharge progress bar above enemy
var _parent: Node2D = null

func _ready() -> void:
	_parent = get_parent() as Node2D

## Returns true if the force field is currently active (used by enemy.gd suppression check).
func is_active() -> bool:
	return _active

## Initialize force field effect and progress bar. Call from enemy _ready().
func setup() -> void:
	var ff_scene: PackedScene = load("res://scenes/effects/ForceFieldEffect.tscn")
	if ff_scene == null:
		FileLogger.info("[EnemyForceField] ForceFieldEffect scene not found, skipping setup")
		return
	_force_field_effect = ff_scene.instantiate()
	_force_field_effect.name = "EnemyForceField"
	_parent.add_child(_force_field_effect)
	# Mark as enemy-owned so it traps player bullets instead of enemy bullets (Issue #1034).
	_force_field_effect.set("owner_is_player", false)
	_force_field_effect.force_field_deactivated.connect(_on_force_field_deactivated)
	_force_field_effect.deactivate()
	_progress_bar = ActiveItemProgressBar.new()
	_progress_bar.name = "ForceFieldProgressBar"
	# Use the same blue as the force field bubble so colors match (Issue #1034).
	_progress_bar.fill_color_override = Color(0.4, 0.7, 1.0, 0.85)
	_parent.add_child(_progress_bar)
	_progress_bar.hide_bar()
	FileLogger.info("[EnemyForceField] Setup complete (duration=%.1fs recharge=%.1fs)" % [DURATION, RECHARGE_TIME])

## Update force field logic each physics frame. Call from enemy _physics_process().
## Pass can_see_target=true when the enemy has line-of-sight to the player or companion.
func update(delta: float, can_see_target: bool) -> void:
	if _force_field_effect == null:
		return
	# Activate when target spotted and not recharging
	if not _active and not _recharging and can_see_target:
		_force_field_effect.set("remaining_charge", DURATION + 1.0)
		var ok: bool = _force_field_effect.activate()
		if ok:
			_active = true
			_timer = DURATION
			FileLogger.info("[EnemyForceField] Activated")
	# Countdown while active
	if _active:
		_timer -= delta
		if _timer <= 0.0:
			_timer = 0.0
			_active = false
			_recharging = true
			_recharge_elapsed = 0.0
			_force_field_effect.deactivate()
			if _progress_bar:
				_progress_bar.show_bar(ActiveItemProgressBar.DisplayMode.CONTINUOUS, 0.0, RECHARGE_TIME)
			FileLogger.info("[EnemyForceField] Deactivated — recharging for %.1fs" % RECHARGE_TIME)
	# Recharge countdown
	if _recharging:
		_recharge_elapsed += delta
		if _progress_bar:
			_progress_bar.update_value(_recharge_elapsed)
		if _recharge_elapsed >= RECHARGE_TIME:
			_recharging = false
			_recharge_elapsed = 0.0
			if _progress_bar:
				_progress_bar.hide_bar()
			FileLogger.info("[EnemyForceField] Recharged and ready")

## Handle force_field_deactivated signal from ForceFieldEffect (charge depleted mid-use).
func _on_force_field_deactivated() -> void:
	if not _active:
		return  # Already handled by update() countdown
	_active = false
	_recharging = true
	_recharge_elapsed = 0.0
	if _progress_bar:
		_progress_bar.show_bar(ActiveItemProgressBar.DisplayMode.CONTINUOUS, 0.0, RECHARGE_TIME)
