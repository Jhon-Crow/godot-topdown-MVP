class_name ExperimentalSampleComponent
extends Node
## Manages the Experimental Sample active item (Issue #1127).
## Extracted from player.gd to keep file under CI line limit.
##
## The Experimental Sample triggers a random active item effect on each use.
## Charges are randomised (1–5) at the start of each level.
## On activation the component re-rolls until a meaningful on-press effect fires;
## if every attempt is passive/unavailable it falls back to Homing Bullets.

## Preloaded icon popup script shown above the player when an effect fires.
const ExperimentalSampleItemPopupScript = preload("res://scripts/ui/experimental_sample_item_popup.gd")

## Minimum / maximum charges per battle (Issue #1127).
const MIN_CHARGES: int = 1
const MAX_CHARGES: int = 5

## Remaining experimental sample charges.
var charges: int = 0

## Whether the experimental sample is equipped.
var equipped: bool = false

## Floating icon popup node shown above the player when an effect fires.
var _popup: Node2D = null

## Reference to the parent player node (set in _ready).
var _player: Node = null


func _ready() -> void:
	_player = get_parent()


## Initialise the component if ActiveItemManager has the experimental sample selected.
## Call from player _ready after adding this node as a child.
func initialize() -> void:
	var active_item_manager: Node = get_node_or_null("/root/ActiveItemManager")
	if active_item_manager == null or not active_item_manager.has_method("has_experimental_sample"):
		FileLogger.info("[Player.ExperimentalSample] ActiveItemManager not available")
		return
	if not active_item_manager.has_experimental_sample():
		FileLogger.info("[Player.ExperimentalSample] Experimental sample not selected")
		return
	equipped = true
	charges = randi_range(MIN_CHARGES, MAX_CHARGES)
	FileLogger.info("[Player.ExperimentalSample] Equipped, charges this run: %d" % charges)
	_player.experimental_sample_charges_changed.emit(charges, MAX_CHARGES)
	_player._show_active_item_charge_bar(charges, MAX_CHARGES)
	_popup = ExperimentalSampleItemPopupScript.new()
	_popup.name = "ExperimentalSampleItemPopup"
	_player.add_child(_popup)


## Handle experimental sample input: press Space to trigger a random active item effect.
## Call from player _physics_process.
func handle_input() -> void:
	if not equipped or not Input.is_action_just_pressed("flashlight_toggle"):
		return
	# Issue #1036: Block active item use when jammed by a Radio Jammer enemy.
	if ActiveItemManager.is_active_item_jammed_verbose():
		FileLogger.info("[Player.ExperimentalSample] Space blocked by Radio Jammer (Issue #1036)")
		return
	if charges <= 0:
		FileLogger.info("[Player.ExperimentalSample] No charges remaining")
		return
	charges -= 1
	_player.experimental_sample_charges_changed.emit(charges, MAX_CHARGES)
	_player._show_active_item_charge_bar(charges, MAX_CHARGES)
	# Pick a random active item type (all types except NONE=0 and EXPERIMENTAL_SAMPLE=18).
	# Re-roll if the chosen type has no visible on-press action.
	const MAX_ATTEMPTS := 20
	var effect_fired := false
	var fired_type: int = -1
	for attempt in range(MAX_ATTEMPTS):
		var random_type: int = randi_range(1, 17)
		FileLogger.info("[Player.ExperimentalSample] Charges: %d — type %d attempt %d" % [charges, random_type, attempt + 1])
		effect_fired = _trigger_effect(random_type)
		if effect_fired:
			fired_type = random_type
			break
	if not effect_fired:
		FileLogger.info("[Player.ExperimentalSample] All attempts passive/skipped — homing fallback triggered")
		_player._homing_active = true
		_player._homing_timer = _player.HOMING_DURATION
		_player._play_homing_sound()
		_player._start_homing_scanner()
		_player.homing_activated.emit()
		fired_type = 2  # HOMING_BULLETS fallback
	# Show floating icon popup for the triggered item (Issue #1127).
	if fired_type >= 0 and _popup and is_instance_valid(_popup):
		var mgr: Node = get_node_or_null("/root/ActiveItemManager")
		if mgr and mgr.has_method("get_active_item_icon_path"):
			_popup.show_icon(mgr.get_active_item_icon_path(fired_type))


## Trigger on-press effect of item_type chosen by experimental sample.
## Returns true if a visible effect fired, false if passive/unavailable (caller re-rolls).
func _trigger_effect(item_type: int) -> bool:
	FileLogger.info("[Player.ExperimentalSample] Executing effect type %d" % item_type)
	# Passive/hold/aim-only types always re-roll (FLASHLIGHT, TELEPORT_BRACERS, BREAKER_BULLETS,
	# FORCE_FIELD, LASER_SIGHT, EXTENDED_MAGAZINE, ARMORED_SKIN, AUTO_RELOAD, DRILLING_BULLETS,
	# RECOIL_COMPENSATOR, COMBAT_DISPOSITION).
	if item_type in [1, 3, 6, 7, 9, 10, 13, 14, 15, 16, 17]:
		return false

	match item_type:
		2:  # HOMING_BULLETS — activate homing for one burst (always available)
			if _player._homing_active: return false
			_player._homing_active = true
			_player._homing_timer = _player.HOMING_DURATION
			_player._play_homing_sound()
			_player._start_homing_scanner()
			_player.homing_activated.emit()
			FileLogger.info("[Player.ExperimentalSample] Homing effect triggered for %.1fs" % _player.HOMING_DURATION)
			return true
		4:  # BFF_PENDANT — summon companion if not yet summoned
			if _player._bff_companion_summoned: return false
			_player._summon_bff_companion()
			FileLogger.info("[Player.ExperimentalSample] BFF companion summoned via experimental sample")
			return true
		5:  # INVISIBILITY_SUIT — activate invisibility if the node is available
			if _player._invisibility_suit_equipped and _player._invisibility_suit != null \
					and is_instance_valid(_player._invisibility_suit) and not _player._invisibility_suit.is_active:
				_player._invisibility_suit.activate()
				FileLogger.info("[Player.ExperimentalSample] Invisibility suit activated via experimental sample")
				return true
			FileLogger.info("[Player.ExperimentalSample] Invisibility suit not equipped or already active; re-roll")
			return false
		8:  # TRAJECTORY_GLASSES — activate glasses if node exists, else skip
			if _player._trajectory_glasses_equipped and _player._trajectory_glasses != null \
					and is_instance_valid(_player._trajectory_glasses) and not _player._trajectory_glasses.is_active:
				_player._update_trajectory_glasses_weapon()
				_player._trajectory_glasses.activate()
				FileLogger.info("[Player.ExperimentalSample] Trajectory glasses activated via experimental sample")
				return true
			FileLogger.info("[Player.ExperimentalSample] Trajectory glasses not equipped or already active; re-roll")
			return false
		11: # LOUDSPEAKER — trigger loudspeaker effect if progress system allows it
			if _player._loudspeaker_equipped and _player._loudspeaker_progress != null \
					and _player._loudspeaker_progress.can_activate():
				var is_first_use: bool = not _player._loudspeaker_progress.used_this_level
				_player._loudspeaker_progress.use()
				_player._apply_loudspeaker_effect(_player._get_aim_direction(),
					1.0 if is_first_use else _player._loudspeaker_progress.get_effect_chance(),
					_player._loudspeaker_progress.get_hostility_chance())
				FileLogger.info("[Player.ExperimentalSample] Loudspeaker activated via experimental sample")
				return true
			FileLogger.info("[Player.ExperimentalSample] Loudspeaker not equipped or no charges; re-roll")
			return false
		12: # BREACHING_CHARGES — detonate existing charges if any placed, else skip
			if _player._breaching_charges != null and is_instance_valid(_player._breaching_charges):
				var detonated := _player._breaching_charges.detonate()
				FileLogger.info("[Player.ExperimentalSample] Breaching charges detonated: %s" % str(detonated))
				return detonated
			return false
		_:
			return false


## Get remaining experimental sample charges.
func get_charges() -> int:
	return charges


## Get the maximum experimental sample charges constant.
func get_max_charges() -> int:
	return MAX_CHARGES
