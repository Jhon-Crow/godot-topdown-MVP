class_name RecoilCompensatorComponent
extends Node
## Recoil compensator active item component (Issue #1073).
## Extracted from player.gd to keep file under CI line limit.
##
## Hold Space to activate: eliminates bullet spread and enables auto-fire at
## 10% boosted rate. Charge depletes at 1 s/s; deactivates automatically when empty.

## Maximum charge duration in seconds.
const MAX_CHARGE: float = 15.0

## Fire rate multiplier when compensator is active (10% boost).
const FIRE_RATE_BOOST: float = 1.1

## Whether the recoil compensator is equipped.
var _equipped: bool = false

## Whether the recoil compensator is currently active (Space held and charge > 0).
var _active: bool = false

## Remaining charge in seconds.
var _charge: float = 0.0

## Shoot cooldown timer for fire rate boost (seconds remaining until next shot allowed).
var shoot_cooldown: float = 0.0

## Signal emitted when the timer bar should be updated (current charge, max charge).
signal charge_bar_update_requested(current: float, maximum: float)


## Initialize if ActiveItemManager has recoil compensator selected.
func setup() -> void:
	var active_item_manager: Node = get_node_or_null("/root/ActiveItemManager")
	if active_item_manager == null:
		FileLogger.info("[Player.RecoilCompensator] ActiveItemManager not found")
		return
	if not active_item_manager.has_method("has_recoil_compensator"):
		FileLogger.info("[Player.RecoilCompensator] ActiveItemManager does not have has_recoil_compensator method")
		return
	if not active_item_manager.has_recoil_compensator():
		FileLogger.info("[Player.RecoilCompensator] Recoil compensator not selected")
		return
	_equipped = true
	_charge = MAX_CHARGE
	FileLogger.info("[Player.RecoilCompensator] Recoil compensator initialized, charge: %.1f s" % _charge)


## Handle input each physics frame. Hold Space to activate, release to deactivate.
func handle_input(delta: float) -> void:
	if not _equipped:
		return
	if shoot_cooldown > 0.0:
		shoot_cooldown -= delta
	if Input.is_action_pressed("flashlight_toggle") and _charge > 0.0:
		if not _active:
			_active = true
			FileLogger.info("[Player.RecoilCompensator] Activated, charge: %.2f s" % _charge)
		_charge -= delta
		if _charge <= 0.0:
			_charge = 0.0
			_active = false
			FileLogger.info("[Player.RecoilCompensator] Charge depleted, deactivating")
		charge_bar_update_requested.emit(_charge, MAX_CHARGE)
	else:
		if _active:
			_active = false
			FileLogger.info("[Player.RecoilCompensator] Deactivated, charge: %.2f s" % _charge)
			if _charge > 0.0:
				charge_bar_update_requested.emit(_charge, MAX_CHARGE)


## Returns true if the compensator is currently active.
func is_active() -> bool:
	return _equipped and _active
