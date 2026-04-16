extends GutTest
## Unit tests for Tutorial level script.
##
## Tests the tutorial flow state machine, multi-hint display logic, and step progression.
## Issue #808: reload and grenade hints are shown simultaneously; each completes independently.
## Issue #945: (1) Reload hint appears after 2 shots. (2) Simultaneous hints use different colors.
## (3) The NEXT button in multi-step actions is highlighted in red using BBCode.
##
## Bug fixes (second review round):
## Fix #1: Hint spacing increased to 50px to prevent overlap when hints wrap to 2 lines.
## Fix #2: `step` in ReloadSequenceProgress is LAST COMPLETED step (0=nothing done);
##          highlight step+1 as next.
## Fix #3: Revolver hammer-cock hint shown from weapon pickup (before 2 shots).
## Fix #4: Bolt-cycle hint (sniper/shotgun) shown after 1st shot, not 2nd.
## Fix #5: Revolver/shotgun reload hints are static; ReloadSequenceProgress must not overwrite them.
##
## Bug fixes (third review round, Issue #945):
## Fix 3rd#1: HINT_SPACING increased to 60px.
## Fix 3rd#2: ShotFired fallback signal.
## Fix 3rd#3: Sniper bolt-cycle hint updates step-by-step.
## Fix 3rd#4: Sniper bolt-action shows 4 separate steps [←][↓][↑][→].
## Fix 3rd#5: Grenade hint shown AFTER reload disappears, not simultaneously.
## Fix 3rd#6: M16 shows fire-mode switch (B) hint after reload.
## Fix 3rd#7: Shotgun reload hint count updates live; dismissed on reload.
## Fix 3rd#8: Revolver hammer-cock hint stays until player manually cocks.
## Fix 3rd#9: Grenade hint only shown when player has grenades.
## Fix 3rd#10: AK GL shows underbarrel grenade launcher hint after reload.
##
## Bug fixes (fourth review round, Issue #945):
## Fix 4th#1: Shotgun shows pump-action hint (open/close bolt) after 1st shot;
##            full reload hint replaces pump hint after 2nd shot.
## Fix 4th#2: Shotgun full reload hint highlights step-by-step via ActionStateChanged;
##            Revolver hint updates step-by-step via ReloadSequenceProgress.
## Fix 4th#3: Sniper bolt-cycle completion only dismisses bolt hint — does NOT advance
##            tutorial; magazine reload (R→F→R) via _on_player_reload_completed advances it.
## Fix 4th#4: Lab map grenade tutorial appears — use GetCurrentGrenades() not get("GrenadeCount").
## Fix 4th#5: AK GL hint uses GrenadeAvailable (bool) instead of GrenadeLauncherAmmo (missing).
##
## Issue #998:
## Scope RMB hint shown from the very start when player has sniper rifle (not only after reload).
## Scope hint dismissed as soon as player activates scope; if scope was used before completing
## reload, SCOPE_TRAINING step is skipped automatically and tutorial advances to THROW_GRENADE.


# ============================================================================
# Mock Tutorial Level Helper
# ============================================================================


class MockTutorialLevel:
	## Tutorial states
	enum TutorialStep {
		SWITCH_FIRE_MODE,
		RELOAD,
		SCOPE_TRAINING,
		THROW_GRENADE,
		COMPLETED
	}

	## Hint keys (mirrors tutorial_level.gd constants)
	const HINT_RELOAD := "reload"
	const HINT_GRENADE := "grenade"
	const HINT_BOLT_CYCLE := "bolt_cycle"
	const HINT_SCOPE := "scope"
	const HINT_FIRE_MODE := "fire_mode"
	const HINT_HAMMER_COCK := "hammer_cock"
	const HINT_GRENADE_LAUNCHER := "grenade_launcher"  ## AK GL underbarrel (fix 3rd#10)

	## Unique colors for each hint (Issue #945)
	const HINT_COLOR_FIRE_MODE := Color(0.3, 0.9, 1.0, 1.0)
	const HINT_COLOR_RELOAD := Color(0.4, 1.0, 0.5, 1.0)
	const HINT_COLOR_GRENADE := Color(1.0, 0.65, 0.0, 1.0)
	const HINT_COLOR_BOLT_CYCLE := Color(0.85, 0.6, 1.0, 1.0)
	const HINT_COLOR_SCOPE := Color(0.3, 0.9, 1.0, 1.0)
	const HINT_COLOR_HAMMER_COCK := Color(1.0, 0.8, 0.3, 1.0)
	const HINT_COLOR_GRENADE_LAUNCHER := Color(1.0, 0.4, 0.2, 1.0)

	## Fix 3rd#1: Hint spacing increased to 60px
	const HINT_SPACING := 60

	var _current_step: TutorialStep = TutorialStep.SWITCH_FIRE_MODE
	var _has_reloaded: bool = false
	var _has_switched_fire_mode: bool = false
	var _has_thrown_grenade: bool = false
	var _has_assault_rifle: bool = false
	var _has_sniper_rifle: bool = false
	var _has_revolver: bool = false
	var _has_shotgun: bool = false
	var _has_makarov_pm: bool = false
	var _has_ak_gl: bool = false  ## Fix 3rd#10: AK GL flag
	var _sniper_bolt_step: int = 0  ## Fix 3rd#3: tracks current sniper bolt step
	var _sniper_bolt_cycled: bool = false
	var _scope_used: bool = false
	## Simulated grenade count for fix 3rd#9
	var _grenade_count: int = 3
	var _grenade_hint_step: int = 0
	var _grenade_g_was_held: bool = false
	var _grenade_hint_drag_completed: bool = false
	var _grenade_hint_rmb_held_after_release: bool = false
	var _grenade_hint_rmb_was_pressed: bool = false
	var _grenade_hint_drag_start_x: float = 0.0
	## Simulated AK GL ammo for fix 3rd#10
	var _ak_gl_has_round: bool = true
	## Simulated shotgun capacity for fix 3rd#7
	var _shotgun_capacity: int = 8
	var _shotgun_current_ammo: int = 0
	var _revolver_can_insert_cartridge: bool = false
	var _revolver_cartridges_loaded_this_reload: int = 0
	var _revolver_current_ammo: int = 0
	var _revolver_current_chamber_index: int = -1
	var _revolver_last_inserted_count: int = 0
	var _revolver_last_inserted_chamber_index: int = -1
	var _revolver_minimum_inserts_required: int = 2
	var _revolver_scroll_completed_since_last_insert: bool = false

	## Issue #945: Shot tracking for delayed reload hint reveal
	var _shots_fired: int = 0
	var _reload_hint_revealed: bool = false
	## Bug fix #4: bolt-cycle hint revealed after 1st shot (sniper/shotgun)
	var _bolt_cycle_hint_revealed: bool = false

	## Active hints dictionary: hint_key -> hint_text (simulates visible labels)
	var _active_hints: Dictionary = {}
	## Active hint colors dictionary: hint_key -> Color (Issue #945)
	var _active_hint_colors: Dictionary = {}

	func get_current_step() -> TutorialStep:
		return _current_step

	func get_active_hints() -> Dictionary:
		return _active_hints.duplicate()

	func get_hint_color(hint_key: String) -> Color:
		return _active_hint_colors.get(hint_key, Color.WHITE)

	func is_hint_active(hint_key: String) -> bool:
		return _active_hints.has(hint_key)

	func is_any_hint_active() -> bool:
		return not _active_hints.is_empty()

	func advance_to_step(step: TutorialStep) -> void:
		_current_step = step
		_show_hints_for_step(step)

	func _dismiss_hint(hint_key: String) -> void:
		_active_hints.erase(hint_key)
		_active_hint_colors.erase(hint_key)

	func _get_hint_color(hint_key: String) -> Color:
		match hint_key:
			HINT_FIRE_MODE:
				return HINT_COLOR_FIRE_MODE
			HINT_RELOAD:
				return HINT_COLOR_RELOAD
			HINT_GRENADE:
				return HINT_COLOR_GRENADE
			HINT_BOLT_CYCLE:
				return HINT_COLOR_BOLT_CYCLE
			HINT_SCOPE:
				return HINT_COLOR_SCOPE
			HINT_HAMMER_COCK:
				return HINT_COLOR_HAMMER_COCK
			HINT_GRENADE_LAUNCHER:
				return HINT_COLOR_GRENADE_LAUNCHER
			_:
				return Color(1.0, 1.0, 0.3, 1.0)

	func _add_hint(hint_key: String, text: String) -> void:
		_active_hints[hint_key] = text
		_active_hint_colors[hint_key] = _get_hint_color(hint_key)

	func _build_grenade_hint_bbcode(step: int) -> String:
		var parts := [
			"[удерживать G+ПКМ]",
			"[дёрнуть мышкой вправо] [отпустить ПКМ]",
			"[зажать ПКМ]",
			"[отпустить G]",
			"[прицелиться и отпустить ПКМ]",
		]
		var highlighted_part := mini(step, parts.size() - 1)
		var styled: PackedStringArray = []
		for i in range(parts.size()):
			if i < highlighted_part:
				styled.append("[color=#888888]%s[/color]" % parts[i])
			elif i == highlighted_part:
				styled.append("[color=#ff4444]%s[/color]" % parts[i])
			else:
				styled.append("[color=#888888]%s[/color]" % parts[i])
		return " ".join(styled)

	## Build BBCode for sniper bolt-cycle hint showing 4-step sequence (fix 3rd#4, 3rd#3).
	func _build_sniper_bolt_hint_bbcode(step: int) -> String:
		const STEPS := ["←", "↓", "↑", "→"]
		var parts: PackedStringArray = []
		for i in range(STEPS.size()):
			if i < step:
				parts.append("[color=#888888][%s][/color]" % STEPS[i])
			elif i == step:
				parts.append("[color=#ff4444][%s][/color]" % STEPS[i])
			else:
				parts.append("[color=#888888][%s][/color]" % STEPS[i])
		return " ".join(parts) + " Передёрни затвор"

	## Build BBCode for shotgun pump-action hint (between shots) (Fix 4th#1).
	func _build_shotgun_pump_hint_bbcode(state: int) -> String:
		match state:
			1:  # NeedsPumpUp
				return "[color=#ff4444][ПКМ↑][/color] [color=#888888][ПКМ↓][/color] Передёрни затвор"
			2:  # NeedsPumpDown
				return "[color=#888888][ПКМ↑][/color] [color=#ff4444][ПКМ↓][/color] Передёрни затвор"
			_:
				return "[color=#ff4444][ПКМ↑][/color] [color=#888888][ПКМ↓][/color] Передёрни затвор"

	## Build BBCode for shotgun full-reload hint with step-based highlighting (Fix 4th#1, #2).
	func _build_shotgun_full_reload_hint_bbcode(state: int) -> String:
		var shells_needed: int = _shotgun_capacity - _shotgun_current_ammo
		match state:
			0, 1:
				return "[color=#ff4444][ПКМ↑ открыть][/color] [color=#888888][СКМ+ПКМ↓ x%d] [ПКМ↓ закрыть][/color]" % shells_needed
			2:
				return "[color=#888888][ПКМ↑ открыть][/color] [color=#ff4444][СКМ+ПКМ↓ x%d][/color] [color=#888888][ПКМ↓ закрыть][/color]" % shells_needed
			3:
				return "[color=#888888][ПКМ↑ открыть] [СКМ+ПКМ↓ x%d][/color] [color=#ff4444][ПКМ↓ закрыть][/color]" % shells_needed
			_:
				return "[color=#888888][ПКМ↑ открыть] [СКМ+ПКМ↓ x%d] [ПКМ↓ закрыть][/color]" % shells_needed

	## Build BBCode for revolver reload hint with step-based highlighting (Fix 4th#2).
	func _build_revolver_reload_hint_bbcode(step: int) -> String:
		match step:
			0:
				return "[color=#ff4444][R открыть][/color] [color=#888888][ПКМ↑ патрон] [скролл] [R закрыть][/color]"
			1:
				return "[color=#888888][R открыть][/color] [color=#ff4444][ПКМ↑ патрон][/color] [color=#888888][скролл] [R закрыть][/color]"
			2:
				return "[color=#888888][R открыть][/color] [ПКМ↑ патрон] [color=#ff4444][скролл][/color] [color=#888888][R закрыть][/color]"
			3:
				return "[color=#888888][R открыть] [ПКМ↑ патрон] [скролл][/color] [color=#ff4444][R закрыть][/color]"
			_:
				return "[color=#888888][R открыть] [ПКМ↑ патрон] [скролл] [R закрыть][/color]"

	## Fix 3rd#7 + Fix 4th#2: Update shotgun hint when shells are loaded.
	func on_shell_count_changed(shell_count: int) -> void:
		_shotgun_current_ammo = shell_count
		if _active_hints.has(HINT_BOLT_CYCLE):
			_active_hints[HINT_BOLT_CYCLE] = _build_shotgun_full_reload_hint_bbcode(0)

	## Called when shotgun action state changes (Fix 4th#1).
	## state=0: Ready (pump done), 1=NeedsPumpUp, 2=NeedsPumpDown
	func on_shotgun_action_state_changed(state: int) -> void:
		if state == 0:
			_dismiss_hint(HINT_BOLT_CYCLE)
		elif _active_hints.has(HINT_BOLT_CYCLE):
			_active_hints[HINT_BOLT_CYCLE] = _build_shotgun_pump_hint_bbcode(state)

	## Called when shotgun reload state changes (Fix 4th#2).
	## Issue #983 Fix 1: state=0 (NotReloading) means reload completed — dismiss hint and advance.
	func on_shotgun_reload_state_changed(state: int) -> void:
		if state == 0:
			# Reload fully complete — dismiss hint and advance tutorial
			_dismiss_hint(HINT_BOLT_CYCLE)
			if not _has_reloaded:
				_has_reloaded = true
				if _has_thrown_grenade:
					advance_to_step(TutorialStep.COMPLETED)
				else:
					advance_to_step(TutorialStep.THROW_GRENADE)
			return
		if _active_hints.has(HINT_BOLT_CYCLE):
			_active_hints[HINT_BOLT_CYCLE] = _build_shotgun_full_reload_hint_bbcode(state)

	## Bug fix: bolt-cycle and hammer-cock hints NOT added here.
	##   Bolt-cycle shown after 1st shot (fix #4), hammer-cock shown from start (fix #3).
	##   Fix 3rd#5: grenade hint NOT added here — shown AFTER reload disappears.
	##   Fix 4th#1: Shotgun shows full reload hint (replacing pump hint) after 2nd shot.
	func _add_reload_hints() -> void:
		if _has_shotgun:
			# Fix 4th#1: replace pump-action hint with full reload hint after 2nd shot.
			_dismiss_hint(HINT_BOLT_CYCLE)
			_add_hint(HINT_BOLT_CYCLE, _build_shotgun_full_reload_hint_bbcode(0))
		elif _has_sniper_rifle:
			# Sniper: reload hint only. Bolt-cycle hint shown after 1st shot.
			_add_hint(HINT_RELOAD, _build_reload_hint_bbcode(0, 3))
		elif _has_revolver:
			# Revolver: cylinder reload hint. Hammer-cock hint shown from start (fix #3).
			_add_hint(HINT_RELOAD, "[color=#ff4444][R открыть][/color] [color=#888888][ПКМ↑ патрон] [скролл] [R закрыть][/color]")
		elif _has_makarov_pm:
			_add_hint(HINT_RELOAD, _build_reload_hint_bbcode(0, 2))
		else:
			_add_hint(HINT_RELOAD, _build_reload_hint_bbcode(0, 3))
		# Fix 3rd#5: grenade hint shown AFTER reload disappears, not simultaneously.

	func _show_hints_for_step(step: TutorialStep) -> void:
		match step:
			TutorialStep.SWITCH_FIRE_MODE:
				_add_hint(HINT_FIRE_MODE, "[color=#ff4444][B][/color] Переключи режим стрельбы")
			TutorialStep.RELOAD:
				# Issue #945: Only show reload hints if already revealed (2 shots fired)
				if _reload_hint_revealed:
					_add_reload_hints()
			TutorialStep.SCOPE_TRAINING:
				# Fix 3rd#5: scope hint only; grenade hint shown after scope done
				_add_hint(HINT_SCOPE, "[color=#ff4444][ПКМ][/color] Прицелься через оптику")
			TutorialStep.THROW_GRENADE:
				# Fix 3rd#9: only show grenade hint if player has grenades
				if _grenade_count > 0:
					if not _active_hints.has(HINT_GRENADE):
						_add_hint(HINT_GRENADE, _build_grenade_hint_bbcode(0))
				# else: no grenades, tutorial auto-completes (handled in advance_to_step)
			TutorialStep.COMPLETED:
				_active_hints.clear()
				_active_hint_colors.clear()

	func set_grenade_hint_progress(g_and_rmb_held: bool, drag_completed: bool, rmb_held_after_release: bool) -> void:
		if not _active_hints.has(HINT_GRENADE):
			return
		_grenade_hint_drag_completed = drag_completed
		_grenade_hint_rmb_held_after_release = rmb_held_after_release
		var step := 0
		if g_and_rmb_held:
			step = 2 if drag_completed else 0
		else:
			step = 4 if rmb_held_after_release else 3
		_active_hints[HINT_GRENADE] = _build_grenade_hint_bbcode(step)

	func _reset_grenade_hint_tracking() -> void:
		_grenade_hint_step = 0
		_grenade_g_was_held = false
		_grenade_hint_drag_completed = false
		_grenade_hint_rmb_held_after_release = false
		_grenade_hint_rmb_was_pressed = false
		_grenade_hint_drag_start_x = 0.0

	func update_grenade_hint_from_input(g_pressed: bool, rmb_pressed: bool, mouse_x: float) -> void:
		if not _active_hints.has(HINT_GRENADE):
			_reset_grenade_hint_tracking()
			return

		var rmb_just_pressed := rmb_pressed and not _grenade_hint_rmb_was_pressed
		var rmb_just_released := not rmb_pressed and _grenade_hint_rmb_was_pressed

		if _grenade_hint_step == 0 and not (g_pressed and rmb_pressed):
			if g_pressed or rmb_pressed or _grenade_hint_rmb_was_pressed:
				_reset_grenade_hint_tracking()
		elif _grenade_hint_step == 1 and not g_pressed and not _grenade_hint_drag_completed:
			_reset_grenade_hint_tracking()
		elif _grenade_hint_step == 2 and not g_pressed and not rmb_pressed:
			_reset_grenade_hint_tracking()
		elif _grenade_hint_step == 3 and not g_pressed and not rmb_pressed:
			_reset_grenade_hint_tracking()
		elif _grenade_hint_step == 4 and not rmb_pressed and not _grenade_hint_rmb_held_after_release:
			_reset_grenade_hint_tracking()

		if _grenade_hint_step <= 1 and g_pressed and rmb_pressed and rmb_just_pressed:
			_grenade_hint_drag_completed = false
			_grenade_hint_drag_start_x = mouse_x
		if _grenade_hint_step == 1 and g_pressed and rmb_pressed:
			if mouse_x - _grenade_hint_drag_start_x > 20.0:
				_grenade_hint_drag_completed = true
				_grenade_hint_step = 2

		if _grenade_hint_step == 0 and g_pressed and rmb_pressed:
			_grenade_hint_step = 1
			_grenade_g_was_held = true
		elif _grenade_hint_step == 2 and _grenade_hint_drag_completed and rmb_just_released:
			_grenade_hint_step = 3
		elif _grenade_hint_step == 3 and g_pressed and rmb_just_pressed:
			_grenade_hint_rmb_held_after_release = true
			_grenade_hint_step = 4
		elif _grenade_hint_step == 4 and not g_pressed and rmb_pressed and _grenade_hint_rmb_held_after_release:
			_grenade_hint_step = 5
			_grenade_g_was_held = false
		elif _grenade_hint_step == 5 and not rmb_pressed and _grenade_hint_rmb_held_after_release:
			_grenade_hint_step = 4

		_grenade_hint_rmb_was_pressed = rmb_pressed
		_active_hints[HINT_GRENADE] = _build_grenade_hint_bbcode(_grenade_hint_step)

	## Issue #945: Called when the weapon fires — counts shots and reveals hints.
	## Bug fix #4: bolt-cycle hint (sniper/shotgun) shown after 1st shot.
	## Bug fix: reload hint still revealed after 2nd shot.
	func on_weapon_fired() -> void:
		_shots_fired += 1
		# Bug fix #4: reveal bolt-cycle hint after 1st shot for sniper/shotgun
		if _shots_fired >= 1 and not _bolt_cycle_hint_revealed:
			if _has_sniper_rifle or _has_shotgun:
				_bolt_cycle_hint_revealed = true
				_reveal_bolt_cycle_hint()
		if not _reload_hint_revealed and _shots_fired >= 2:
			_reload_hint_revealed = true
			_reveal_reload_hint()

	## Fix 3rd#4: Reveal bolt-cycle hint after 1st shot with 4-step sequence.
	## Fix 3rd#3: First step highlighted red (step=0).
	## Fix 4th#1: Shotgun shows pump-action hint (not full reload) after 1st shot.
	func _reveal_bolt_cycle_hint() -> void:
		if _current_step != TutorialStep.RELOAD:
			return
		if _has_sniper_rifle:
			if not _active_hints.has(HINT_BOLT_CYCLE):
				# Fix 3rd#4: 4 separate steps, fix 3rd#3: first step in red
				_add_hint(HINT_BOLT_CYCLE, _build_sniper_bolt_hint_bbcode(0))
		elif _has_shotgun:
			if not _active_hints.has(HINT_BOLT_CYCLE):
				# Fix 4th#1: simple pump-action hint after 1st shot (NeedsPumpUp=1)
				_add_hint(HINT_BOLT_CYCLE, _build_shotgun_pump_hint_bbcode(1))

	func _reveal_reload_hint() -> void:
		if _current_step != TutorialStep.RELOAD:
			return
		_add_reload_hints()

	## Issue #945 + Bug fix #5: Called when reload sequence progresses.
	## Fix 4th#2: Revolver NOW updates hint step-by-step via ReloadSequenceProgress.
	##            Shotgun uses ActionStateChanged/ReloadStateChanged instead.
	## Bug fix #2: `step` is LAST COMPLETED step; highlight step+1 as next action.
	func on_reload_sequence_progress(step: int, total: int) -> void:
		# Fix 4th#2: Revolver updates dynamically via ReloadSequenceProgress
		if _has_revolver:
			if _active_hints.has(HINT_RELOAD):
				_active_hints[HINT_RELOAD] = _build_revolver_reload_hint_bbcode(step)
			return
		# Bug fix #5: shotgun uses ActionStateChanged/ReloadStateChanged — skip dynamic update
		if _has_shotgun:
			return
		if not _active_hints.has(HINT_RELOAD):
			return
		var new_text := _build_reload_hint_bbcode(step, total)
		if not new_text.is_empty():
			_active_hints[HINT_RELOAD] = new_text

	## Fix 3rd#3: Called when sniper bolt step changes — updates hint text step-by-step.
	## Fix 4th#3: Bolt-cycle completion only dismisses bolt hint — does NOT advance tutorial.
	##            Magazine reload (R→F→R) via on_reload_completed advances to SCOPE_TRAINING.
	func on_sniper_bolt_step_changed(step: int, total_steps: int) -> void:
		if _current_step != TutorialStep.RELOAD:
			return
		# Fix 3rd#3: update bolt-cycle hint dynamically
		if _active_hints.has(HINT_BOLT_CYCLE):
			_active_hints[HINT_BOLT_CYCLE] = _build_sniper_bolt_hint_bbcode(step)
		# Fix 4th#3: only dismiss bolt hint when done — do NOT advance tutorial or dismiss reload
		if step >= total_steps and not _sniper_bolt_cycled:
			_sniper_bolt_cycled = true
			_dismiss_hint(HINT_BOLT_CYCLE)
			# Reset for next shot — player still needs to do magazine reload
			_sniper_bolt_cycled = false

	## Issue #945: Build BBCode text for reload hint with NEXT button highlighted red.
	## Bug fix #2: `step` is LAST COMPLETED step (0 = nothing done, 1 = first press done, etc.).
	## Bug fix #5: Shotgun returns empty string (uses ActionStateChanged/ReloadStateChanged).
	## Fix 4th#2: Revolver now updates dynamically (handled in on_reload_sequence_progress).
	func _build_reload_hint_bbcode(step: int, total: int) -> String:
		# Guard: shotgun uses separate action/reload state signals
		if _has_shotgun:
			return ""
		if _has_makarov_pm or (not _has_sniper_rifle and total <= 2):
			# 2-step reload R -> R; step=0 → next is first R
			match step:
				0:
					return "[color=#ff4444][R][/color] [color=#888888][R][/color] Перезарядись"
				1:
					return "[color=#888888][R][/color] [color=#ff4444][R][/color] Перезарядись"
				_:
					return "[color=#888888][R] [R][/color] Перезарядись"
		else:
			# 3-step reload R -> F -> R; step=0 → next is first R
			match step:
				0:
					return "[color=#ff4444][R][/color] [color=#888888][F] [R][/color] Перезарядись"
				1:
					return "[color=#888888][R][/color] [color=#ff4444][F][/color] [color=#888888][R][/color] Перезарядись"
				2:
					return "[color=#888888][R] [F][/color] [color=#ff4444][R][/color] Перезарядись"
				_:
					return "[color=#888888][R] [F] [R][/color] Перезарядись"

	func on_fire_mode_changed() -> void:
		if _current_step != TutorialStep.SWITCH_FIRE_MODE:
			return
		if not _has_switched_fire_mode:
			_has_switched_fire_mode = true
			_dismiss_hint(HINT_FIRE_MODE)
			advance_to_step(TutorialStep.RELOAD)

	## Issue #998: Scope hint dismissed when player uses scope (from any step).
	## If scope used during SCOPE_TRAINING, also advance to THROW_GRENADE.
	func on_scope_state_changed(is_active: bool) -> void:
		if not is_active or _scope_used:
			return
		_scope_used = true
		_dismiss_hint(HINT_SCOPE)
		if _current_step == TutorialStep.SCOPE_TRAINING:
			advance_to_step(TutorialStep.THROW_GRENADE)

	func on_hammer_cocked() -> void:
		## Dismiss hammer cock hint when hammer is manually cocked (Issue #808).
		## Fix 3rd#8: ONLY via this signal, not via reload_completed.
		_dismiss_hint(HINT_HAMMER_COCK)

	func on_revolver_cartridge_inserted(loaded: int, chamber_index: int, current_ammo: int = -1) -> void:
		_revolver_cartridges_loaded_this_reload = loaded
		_revolver_last_inserted_count = loaded
		_revolver_last_inserted_chamber_index = chamber_index
		_revolver_current_chamber_index = chamber_index
		_revolver_scroll_completed_since_last_insert = false
		if current_ammo >= 0:
			_revolver_current_ammo = current_ammo

	func on_revolver_cylinder_rotated(chamber_index: int) -> void:
		_revolver_current_chamber_index = chamber_index
		if _revolver_cartridges_loaded_this_reload <= 0:
			return
		_revolver_scroll_completed_since_last_insert = true
		if _revolver_cartridges_loaded_this_reload >= _revolver_minimum_inserts_required \
		or _revolver_current_ammo >= 5:
			_active_hints[HINT_RELOAD] = _build_revolver_reload_hint_bbcode(3)
		elif _active_hints.has(HINT_RELOAD):
			_active_hints[HINT_RELOAD] = _build_revolver_reload_hint_bbcode(1)

	func on_revolver_reload_state_changed(state: int) -> void:
		if not _active_hints.has(HINT_RELOAD):
			return
		if not _has_revolver:
			return

		var hint_step: int = 0
		match state:
			1:
				hint_step = 1
			2:
				hint_step = _get_revolver_reload_hint_step_for_loading_state()
			_:
				hint_step = 4

		_active_hints[HINT_RELOAD] = _build_revolver_reload_hint_bbcode(hint_step)

	func _get_revolver_reload_hint_step_for_loading_state() -> int:
		if _revolver_cartridges_loaded_this_reload <= 0:
			return 2
		if _revolver_cartridges_loaded_this_reload >= _revolver_minimum_inserts_required \
		or _revolver_current_ammo >= 5:
			return 3
		if _revolver_scroll_completed_since_last_insert \
		and _revolver_cartridges_loaded_this_reload == _revolver_last_inserted_count \
		and _revolver_last_inserted_chamber_index >= 0 \
		and _revolver_current_chamber_index >= 0 \
		and _revolver_current_chamber_index != _revolver_last_inserted_chamber_index:
			return 1
		return 2

	## Fix 3rd#5: Grenade hint shown AFTER reload disappears.
	## Fix 3rd#6: M16 shows fire-mode switch hint after reload.
	## Fix 3rd#7: Shotgun bolt-cycle hint dismissed on reload.
	## Fix 3rd#8: Hammer-cock hint NOT dismissed here.
	## Fix 3rd#9: Grenade hint only shown if player has grenades.
	## Fix 3rd#10: AK GL shows underbarrel grenade launcher hint after reload.
	## Fix 4th#3: Sniper advances to SCOPE_TRAINING via on_reload_completed, not bolt-cycle.
	## Issue #998: If scope was already used early, skip SCOPE_TRAINING and go to THROW_GRENADE.
	func on_reload_completed() -> void:
		if _current_step != TutorialStep.RELOAD:
			return
		if not _has_reloaded:
			_has_reloaded = true
			_dismiss_hint(HINT_RELOAD)
			# Fix 3rd#7: dismiss bolt-cycle hint for shotgun on reload
			if _has_shotgun:
				_dismiss_hint(HINT_BOLT_CYCLE)
			# Fix 4th#3: Sniper advances to SCOPE_TRAINING after magazine reload.
			# Issue #998: If scope was already used early, skip SCOPE_TRAINING.
			if _has_sniper_rifle:
				if _scope_used:
					pass  # Fall through to grenade step below
				else:
					advance_to_step(TutorialStep.SCOPE_TRAINING)
					return
			# Fix 3rd#8: do NOT dismiss hammer-cock — stays until player manually cocks
			# Fix 3rd#6: M16 (not AK GL) shows fire-mode switch hint after reload
			if _has_assault_rifle and not _has_ak_gl:
				_add_hint(HINT_FIRE_MODE, "[color=#ff4444][B][/color] Переключи режим стрельбы")
			# Fix 3rd#10: AK GL shows underbarrel grenade launcher hint after reload
			if _has_ak_gl and _ak_gl_has_round:
				_add_hint(HINT_GRENADE_LAUNCHER, "[color=#ff4444][ПКМ][/color] Выстрели подствольным гранатомётом")
			# If grenade was already thrown, go to COMPLETED; otherwise wait for grenade
			if _has_thrown_grenade:
				advance_to_step(TutorialStep.COMPLETED)
			else:
				advance_to_step(TutorialStep.THROW_GRENADE)

	func on_grenade_thrown() -> void:
		# Grenade is now only shown during THROW_GRENADE step (fix 3rd#5)
		if _current_step != TutorialStep.THROW_GRENADE:
			return
		if not _has_thrown_grenade:
			_has_thrown_grenade = true
			_dismiss_hint(HINT_GRENADE)
			advance_to_step(TutorialStep.COMPLETED)

	func is_tutorial_complete() -> bool:
		return _current_step == TutorialStep.COMPLETED

	func set_initial_step_based_on_weapon(has_assault_rifle: bool) -> void:
		if has_assault_rifle:
			_current_step = TutorialStep.SWITCH_FIRE_MODE
			_add_hint(HINT_FIRE_MODE, "[color=#ff4444][B][/color] Переключи режим стрельбы")
		else:
			_current_step = TutorialStep.RELOAD
			# Issue #945: Reload hints NOT shown at startup — appear only after 2 shots.
			# Bug fix #3: Revolver hammer-cock hint shown immediately from weapon pickup.
			if _has_revolver:
				_add_hint(HINT_HAMMER_COCK, "[color=#ff4444][ПКМ][/color] Взведи курок")
			# Issue #998: Scope hint shown from the very start for sniper rifle.
			if _has_sniper_rifle:
				_add_hint(HINT_SCOPE, "[color=#ff4444][ПКМ][/color] Прицелься через оптику")


var tutorial: MockTutorialLevel


func before_each() -> void:
	tutorial = MockTutorialLevel.new()


func after_each() -> void:
	tutorial = null


# ============================================================================
# Initial State Tests
# ============================================================================


func test_initial_step_is_switch_fire_mode() -> void:
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.SWITCH_FIRE_MODE,
		"Tutorial should start at SWITCH_FIRE_MODE step by default")


func test_initial_step_is_reload_without_rifle() -> void:
	tutorial.set_initial_step_based_on_weapon(false)
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.RELOAD,
		"Tutorial should start at RELOAD step for non-assault rifles")


func test_initial_fire_mode_hint_shown() -> void:
	tutorial.set_initial_step_based_on_weapon(true)
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_FIRE_MODE),
		"Fire mode hint should be active initially for assault rifle")


func test_tutorial_not_complete_initially() -> void:
	assert_false(tutorial.is_tutorial_complete(), "Tutorial should not be complete initially")


# ============================================================================
# Issue #945: Reload Hint Delayed Until 2 Shots Fired
# ============================================================================


func test_reload_hint_not_shown_at_start() -> void:
	## Issue #945: Reload hint must NOT appear at start — only after 2 shots.
	tutorial.set_initial_step_based_on_weapon(false)

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint must NOT be shown at tutorial start (Issue #945 - appears after 2 shots)")
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint must NOT be shown before reload hint (Issue #945)")


func test_reload_hint_not_shown_after_one_shot() -> void:
	## Issue #945: After only 1 shot, reload hint should still be hidden.
	tutorial.set_initial_step_based_on_weapon(false)

	tutorial.on_weapon_fired()

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint should NOT appear after only 1 shot (Issue #945)")


func test_reload_hint_shown_after_two_shots() -> void:
	## Issue #945: After 2 shots, reload hint appears. Grenade hint appears AFTER reload (Fix 3rd#5).
	tutorial.set_initial_step_based_on_weapon(false)

	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint should appear after 2 shots (Issue #945)")
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint should NOT appear during reload step (Fix 3rd#5 — shown after reload)")


func test_reload_hint_shown_after_more_than_two_shots() -> void:
	## Issue #945: If player fires 3+ shots, reload hint still appears.
	tutorial.set_initial_step_based_on_weapon(false)

	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()  # Extra shot after reveal

	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint should remain after more than 2 shots")


func test_shots_before_fire_mode_switch_still_count() -> void:
	## Issue #945: Shots fired during fire mode step should count toward the 2-shot threshold.
	tutorial._has_assault_rifle = true
	tutorial.set_initial_step_based_on_weapon(true)

	# Fire 2 shots during fire mode step (before advancing to RELOAD step)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()
	# _reload_hint_revealed is now true, but step is SWITCH_FIRE_MODE so hints not shown yet

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint should NOT appear before advancing to RELOAD step")

	# Now switch fire mode to advance to RELOAD step
	tutorial.on_fire_mode_changed()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.RELOAD)
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint should appear immediately when advancing to RELOAD step (shots already counted)")


func test_weapon_fired_idempotent_after_reveal() -> void:
	## Issue #945: Additional shots after reveal should not cause duplicate hints.
	## Fix 3rd#5: Only reload hint shown during reload step (grenade shown AFTER reload).
	tutorial.set_initial_step_based_on_weapon(false)

	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()  # Reveal
	tutorial.on_weapon_fired()  # Additional shots should not cause issues
	tutorial.on_weapon_fired()

	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint remains after additional shots")
	# Fix 3rd#5: Only reload hint during reload step (no grenade yet)
	assert_eq(tutorial.get_active_hints().size(), 1,
		"Only 1 hint (reload) should be active during reload step — grenade shown after reload (Fix 3rd#5)")


# ============================================================================
# Issue #945: Unique Colors for Simultaneously Displayed Hints
# ============================================================================


func test_reload_hint_has_green_color() -> void:
	## Issue #945: Reload hint should use green color.
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	assert_eq(tutorial.get_hint_color(MockTutorialLevel.HINT_RELOAD),
		MockTutorialLevel.HINT_COLOR_RELOAD,
		"Reload hint should have green color (Issue #945 - unique colors per hint)")


func test_grenade_hint_has_orange_color() -> void:
	## Issue #945: Grenade hint should use orange color.
	## Fix 3rd#5: Grenade hint shown AFTER reload — need to complete reload first.
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()
	tutorial.on_reload_completed()  # Grenade hint appears after reload (Fix 3rd#5)

	assert_eq(tutorial.get_hint_color(MockTutorialLevel.HINT_GRENADE),
		MockTutorialLevel.HINT_COLOR_GRENADE,
		"Grenade hint should have orange color (Issue #945 - unique colors per hint)")


func test_fire_mode_hint_has_cyan_color() -> void:
	## Issue #945: Fire mode hint should use cyan color.
	tutorial.set_initial_step_based_on_weapon(true)

	assert_eq(tutorial.get_hint_color(MockTutorialLevel.HINT_FIRE_MODE),
		MockTutorialLevel.HINT_COLOR_FIRE_MODE,
		"Fire mode hint should have cyan color (Issue #945 - unique colors per hint)")


func test_bolt_cycle_hint_has_purple_color() -> void:
	## Issue #945: Bolt cycle hint should use purple color.
	## Bug fix #4: Bolt-cycle hint now appears after 1st shot, not 2nd.
	tutorial._has_sniper_rifle = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()  # 1st shot triggers bolt-cycle hint

	assert_eq(tutorial.get_hint_color(MockTutorialLevel.HINT_BOLT_CYCLE),
		MockTutorialLevel.HINT_COLOR_BOLT_CYCLE,
		"Bolt cycle hint should have purple color (Issue #945 - unique colors per hint)")


func test_hammer_cock_hint_has_yellow_color() -> void:
	## Issue #945: Hammer cock hint should use yellow color.
	## Bug fix #3: Hammer-cock hint now appears from weapon pickup (before any shots).
	tutorial._has_revolver = true
	tutorial.set_initial_step_based_on_weapon(false)
	# No shots needed — hammer-cock hint appears immediately

	assert_eq(tutorial.get_hint_color(MockTutorialLevel.HINT_HAMMER_COCK),
		MockTutorialLevel.HINT_COLOR_HAMMER_COCK,
		"Hammer cock hint should have yellow color immediately on revolver pickup (Bug fix #3)")


func test_hints_have_different_colors() -> void:
	## Issue #945: All hint types have unique colors (even though shown sequentially now).
	## Fix 3rd#5: Grenade shown AFTER reload, not simultaneously.
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()
	tutorial.on_reload_completed()  # Reload hint gone; grenade hint now visible

	var grenade_color := tutorial.get_hint_color(MockTutorialLevel.HINT_GRENADE)

	# Grenade color should be orange (different from what reload color was, which is green)
	assert_eq(grenade_color, MockTutorialLevel.HINT_COLOR_GRENADE,
		"Grenade hint must have distinct orange color (Issue #945)")
	assert_ne(grenade_color, MockTutorialLevel.HINT_COLOR_RELOAD,
		"Grenade and reload hints must have different colors (Issue #945)")


# ============================================================================
# Issue #945: Red Highlight on NEXT Button in Multi-Step Actions
# ============================================================================


func test_reload_hint_initial_text_has_red_first_step() -> void:
	## Issue #945: Initial reload hint shows first step (R) in red.
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	var hint_text: String = tutorial.get_active_hints()[MockTutorialLevel.HINT_RELOAD]
	assert_true(hint_text.contains("[color=#ff4444]"),
		"Reload hint should contain red color markup for next button (Issue #945)")
	assert_true(hint_text.begins_with("[color=#ff4444][R]"),
		"First button [R] should be highlighted red at start of reload sequence (Issue #945)")


func test_reload_sequence_step0_highlights_first_r_red() -> void:
	## Bug fix #2: step=0 means nothing done yet; first [R] should be red.
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_reload_sequence_progress(0, 3)

	var hint_text: String = tutorial.get_active_hints()[MockTutorialLevel.HINT_RELOAD]
	assert_true(hint_text.begins_with("[color=#ff4444][R]"),
		"Step 0: first [R] should be highlighted red (Bug fix #2 — step is last completed)")
	assert_true(hint_text.contains("[color=#888888]"),
		"Step 0: subsequent steps should be greyed (Bug fix #2)")


func test_reload_sequence_step1_highlights_f_red() -> void:
	## Bug fix #2: step=1 means R was pressed; next is F (highlighted red).
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_reload_sequence_progress(1, 3)

	var hint_text: String = tutorial.get_active_hints()[MockTutorialLevel.HINT_RELOAD]
	assert_true(hint_text.contains("[color=#ff4444][F]"),
		"Step 1: [F] should be highlighted red as next button (Bug fix #2 — R just pressed)")
	assert_true(hint_text.contains("[color=#888888][R][/color]"),
		"Step 1: first [R] should be greyed (just pressed) (Bug fix #2)")


func test_reload_sequence_step2_highlights_final_r_red() -> void:
	## Bug fix #2: step=2 means R+F pressed; next is final R (highlighted red).
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_reload_sequence_progress(2, 3)

	var hint_text: String = tutorial.get_active_hints()[MockTutorialLevel.HINT_RELOAD]
	assert_true(hint_text.contains("[color=#ff4444][R]"),
		"Step 2: final [R] should be highlighted red (Bug fix #2 — R+F already pressed)")
	assert_true(hint_text.contains("[color=#888888][R] [F]"),
		"Step 2: earlier steps [R] and [F] should be greyed (Bug fix #2)")


func test_reload_sequence_step3_all_greyed() -> void:
	## Bug fix #2: step=3 means all steps done; all greyed out.
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_reload_sequence_progress(3, 3)

	var hint_text: String = tutorial.get_active_hints()[MockTutorialLevel.HINT_RELOAD]
	assert_false(hint_text.contains("[color=#ff4444]"),
		"Step 3: no button should be highlighted red — all steps done (Bug fix #2)")


func test_pistol_reload_step0_highlights_first_r() -> void:
	## Bug fix #2: Makarov PM step=0 — nothing done, first R is red.
	tutorial._has_makarov_pm = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_reload_sequence_progress(0, 2)

	var hint_text: String = tutorial.get_active_hints()[MockTutorialLevel.HINT_RELOAD]
	assert_true(hint_text.begins_with("[color=#ff4444][R]"),
		"Pistol step 0: first [R] should be red (Bug fix #2)")


func test_pistol_reload_step1_highlights_second_r() -> void:
	## Bug fix #2: Makarov PM step=1 means first R pressed; second R is now red.
	tutorial._has_makarov_pm = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_reload_sequence_progress(1, 2)

	var hint_text: String = tutorial.get_active_hints()[MockTutorialLevel.HINT_RELOAD]
	assert_true(hint_text.contains("[color=#888888][R][/color] [color=#ff4444][R]"),
		"Pistol step 1: second [R] should be red, first grayed (Bug fix #2)")


func test_pistol_reload_step2_all_greyed() -> void:
	## Bug fix #2: Makarov PM step=2 means both R pressed; all greyed.
	tutorial._has_makarov_pm = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_reload_sequence_progress(2, 2)

	var hint_text: String = tutorial.get_active_hints()[MockTutorialLevel.HINT_RELOAD]
	assert_false(hint_text.contains("[color=#ff4444]"),
		"Pistol step 2: no button should be highlighted — both pressed (Bug fix #2)")


func test_reload_sequence_progress_ignored_when_hint_not_visible() -> void:
	## Issue #945: If reload hint is not showing (not yet revealed), progress update is safe to ignore.
	tutorial.set_initial_step_based_on_weapon(false)
	# Do NOT fire 2 shots, so reload hint is not visible

	# Should not crash and hint should not appear
	tutorial.on_reload_sequence_progress(1, 3)

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint should remain hidden if not yet revealed (Issue #945)")


# ============================================================================
# Multi-Hint Simultaneous Display Tests (Issue #808)
# ============================================================================


func test_reload_and_grenade_hints_shown_sequentially() -> void:
	## Fix 3rd#5: Grenade hint is shown AFTER reload (not simultaneously).
	## Issue #808: Each hint is still shown and dismissed independently.
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	# During reload — only reload hint active (grenade not yet)
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint should be active during RELOAD step")
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint NOT shown during reload step (Fix 3rd#5 — appears after reload)")

	# After reload — grenade hint appears
	tutorial.on_reload_completed()

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint gone after reload")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint appears AFTER reload (Fix 3rd#5)")


func test_reload_hint_dismissed_grenade_hint_remains() -> void:
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	# Complete reload
	tutorial.on_reload_completed()

	# Only reload hint should be gone; grenade hint should remain
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint should be dismissed after reload completes")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint should remain visible after reload (Issue #808)")


func test_grenade_hint_dismissed_after_throw() -> void:
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()
	tutorial.on_reload_completed()

	tutorial.on_grenade_thrown()

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint should be dismissed after grenade is thrown")


func test_no_hints_after_completion() -> void:
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()
	tutorial.on_reload_completed()
	tutorial.on_grenade_thrown()

	assert_false(tutorial.is_any_hint_active(),
		"No hints should be active after tutorial completion")


# ============================================================================
# Weapon Special Feature Hint Tests (Issue #808)
# ============================================================================


func test_sniper_bolt_cycle_hint_shown_after_first_shot() -> void:
	## Bug fix #4: Sniper bolt-cycle hint appears after 1st shot, not 2nd.
	tutorial._has_sniper_rifle = true
	tutorial.set_initial_step_based_on_weapon(false)

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_BOLT_CYCLE),
		"Bolt-cycle hint should NOT appear before any shots")

	tutorial.on_weapon_fired()  # 1st shot

	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_BOLT_CYCLE),
		"Bolt-cycle hint should appear after 1st shot (Bug fix #4)")
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint should NOT appear after only 1 shot (still needs 2)")


func test_sniper_shows_bolt_cycle_hint_separately() -> void:
	## Sniper: bolt-cycle hint after 1st shot; reload hint after 2nd shot.
	## Fix 3rd#5: Grenade hint NOT shown during reload step (only after scope training).
	tutorial._has_sniper_rifle = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()  # 1st shot → bolt-cycle hint
	tutorial.on_weapon_fired()  # 2nd shot → reload hint

	# Both bolt cycle hint and reload hint should be separate lines
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Sniper should have reload hint after 2nd shot")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_BOLT_CYCLE),
		"Sniper should have separate bolt-cycle hint (weapon special feature, Issue #808)")
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint NOT shown during reload step (Fix 3rd#5 — appears after scope training)")


func test_sniper_bolt_cycle_dismisses_bolt_hint_only() -> void:
	## Fix 4th#3: Bolt cycle only dismisses bolt hint — does NOT advance tutorial.
	## Magazine reload ([R][F][R]) via on_reload_completed advances to SCOPE_TRAINING.
	tutorial._has_sniper_rifle = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	# Simulate bolt cycle completed
	tutorial.on_sniper_bolt_step_changed(4, 4)

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_BOLT_CYCLE),
		"Bolt cycle hint should be dismissed after bolt cycling (Fix 4th#3)")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint STAYS after bolt cycle — player must complete [R][F][R] reload (Fix 4th#3)")
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.RELOAD,
		"Tutorial still in RELOAD step — bolt cycle alone does not advance it (Fix 4th#3)")


func test_sniper_scope_hint_shown_after_magazine_reload() -> void:
	## Fix 4th#3: Scope hint available from start and also remains during SCOPE_TRAINING step.
	## Issue #998: Scope hint now shown from the very start (not just after reload).
	tutorial._has_sniper_rifle = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	# Issue #998: Scope hint already shown from start; bolt cycle does not affect it
	tutorial.on_sniper_bolt_step_changed(4, 4)
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_SCOPE),
		"Scope hint visible from start — shown even before magazine reload (Issue #998)")

	# Magazine reload advances to SCOPE_TRAINING — scope hint persists
	tutorial.on_reload_completed()
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_SCOPE),
		"Scope hint still present after magazine reload in SCOPE_TRAINING (Fix 4th#3 + Issue #998)")


func test_sniper_scope_dismissed_grenade_shown_after_scope() -> void:
	## Fix 4th#3: Scope reached via magazine reload; grenade shown after scope.
	## Fix 3rd#5: Grenade hint shown AFTER scope training step.
	tutorial._has_sniper_rifle = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()
	tutorial.on_sniper_bolt_step_changed(4, 4)
	tutorial.on_reload_completed()  # Magazine reload advances to SCOPE_TRAINING

	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_SCOPE),
		"Scope hint active during scope training")
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint NOT shown during scope training (Fix 3rd#5)")

	tutorial.on_scope_state_changed(true)

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_SCOPE),
		"Scope hint dismissed after scope used")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint appears AFTER scope training (Fix 3rd#5)")


func test_revolver_shows_hammer_cock_hint_from_start() -> void:
	## Bug fix #3: Revolver hammer-cock hint appears immediately on weapon pickup.
	tutorial._has_revolver = true
	tutorial.set_initial_step_based_on_weapon(false)

	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_HAMMER_COCK),
		"Revolver hammer-cock hint should appear immediately from weapon pickup (Bug fix #3)")
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Revolver reload hint should NOT appear yet (needs 2 shots)")


func test_revolver_shows_reload_hint_after_two_shots() -> void:
	## Fix 3rd#5: Grenade hint NOT shown during reload — only after reload completes.
	tutorial._has_revolver = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Revolver should have reload hint after 2 shots")
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint NOT shown during reload step (Fix 3rd#5 — appears after reload)")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_HAMMER_COCK),
		"Hammer cock hint remains visible alongside reload (Bug fix #3)")


func test_revolver_reload_hint_updates_with_sequence_progress() -> void:
	## Fix 4th#2: Revolver reload hint NOW updates step-by-step via ReloadSequenceProgress.
	tutorial._has_revolver = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	# Initial hint at step 0 (open cylinder next)
	var initial_hint_text: String = tutorial.get_active_hints()[MockTutorialLevel.HINT_RELOAD]
	assert_true(initial_hint_text.contains("[R открыть]"),
		"Revolver initial reload hint shows [R открыть] as first step (Fix 4th#2)")

	# Simulate reload progressing to step 1 (insert cartridge next)
	tutorial.on_reload_sequence_progress(1, 3)

	var updated_hint_text: String = tutorial.get_active_hints()[MockTutorialLevel.HINT_RELOAD]
	assert_ne(updated_hint_text, initial_hint_text,
		"Revolver reload hint SHOULD update via ReloadSequenceProgress (Fix 4th#2)")
	assert_true(updated_hint_text.contains("[ПКМ↑ патрон]"),
		"After step 1, [ПКМ↑ патрон] should be highlighted next (Fix 4th#2)")


func test_revolver_reload_hint_shows_scroll_as_separate_step_after_insert() -> void:
	tutorial._has_revolver = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_revolver_cartridge_inserted(1, 2)
	tutorial.on_revolver_reload_state_changed(2)

	var hint_text: String = tutorial.get_active_hints()[MockTutorialLevel.HINT_RELOAD]
	assert_true(hint_text.contains("[color=#ff4444][скролл][/color]"),
		"After inserting a cartridge, scroll must be the separate highlighted step")
	assert_true(hint_text.contains("[ПКМ↑ патрон]"),
		"The insert step should remain visible after the first cartridge is loaded")
	assert_false(hint_text.contains("[color=#888888][ПКМ↑ патрон][/color]"),
		"The first insert must not look completed before the second cartridge is loaded")
	assert_false(hint_text.contains("[color=#ff4444][R закрыть][/color]"),
		"Close cylinder must not be highlighted before the scroll step is done")


func test_revolver_reload_hint_shows_close_after_scroll_advances_slot() -> void:
	tutorial._has_revolver = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_revolver_cartridge_inserted(1, 2)
	tutorial.on_revolver_cylinder_rotated(3)
	tutorial.on_revolver_reload_state_changed(2)

	var hint_text: String = tutorial.get_active_hints()[MockTutorialLevel.HINT_RELOAD]
	assert_true(hint_text.contains("[color=#ff4444][ПКМ↑ патрон][/color]"),
		"After the first scroll, the tutorial should repeat the insert step for the second missing round")
	assert_false(hint_text.contains("[color=#ff4444][R закрыть][/color]"),
		"Close cylinder must stay inactive until two rounds are inserted or the cylinder reaches 5/5")


func test_revolver_reload_hint_keeps_close_after_scroll_to_empty_chamber() -> void:
	tutorial._has_revolver = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_revolver_cartridge_inserted(1, 2)
	tutorial.on_revolver_cylinder_rotated(4)
	tutorial._revolver_can_insert_cartridge = true
	tutorial.on_revolver_reload_state_changed(2)

	var hint_text: String = tutorial.get_active_hints()[MockTutorialLevel.HINT_RELOAD]
	assert_true(hint_text.contains("[color=#ff4444][ПКМ↑ патрон][/color]"),
		"Scrolling to another empty chamber after the first insert should return to the insert step")
	assert_false(hint_text.contains("[color=#ff4444][скролл][/color]"),
		"The tutorial must not keep waiting on scroll after the chamber index changed")


func test_revolver_reload_hint_does_not_count_scroll_without_rotation_event() -> void:
	tutorial._has_revolver = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_revolver_cartridge_inserted(1, 2)
	tutorial._revolver_current_chamber_index = 3
	tutorial.on_revolver_reload_state_changed(2)

	var hint_text: String = tutorial.get_active_hints()[MockTutorialLevel.HINT_RELOAD]
	assert_true(hint_text.contains("[color=#ff4444][скролл][/color]"),
		"Scroll should stay highlighted until the explicit cylinder rotation event arrives")
	assert_false(hint_text.contains("[color=#ff4444][ПКМ↑ патрон][/color]"),
		"Insert must not reactivate from chamber index drift alone")


func test_revolver_reload_hint_shows_close_after_second_insert() -> void:
	tutorial._has_revolver = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_revolver_cartridge_inserted(2, 4, 4)
	tutorial.on_revolver_reload_state_changed(2)

	var hint_text: String = tutorial.get_active_hints()[MockTutorialLevel.HINT_RELOAD]
	assert_true(hint_text.contains("[color=#ff4444][R закрыть][/color]"),
		"After two inserted rounds during this tutorial prompt, only close cylinder should remain")


func test_revolver_reload_hint_shows_close_when_cylinder_becomes_full() -> void:
	tutorial._has_revolver = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_revolver_cartridge_inserted(1, 2, 5)
	tutorial.on_revolver_reload_state_changed(2)

	var hint_text: String = tutorial.get_active_hints()[MockTutorialLevel.HINT_RELOAD]
	assert_true(hint_text.contains("[color=#ff4444][R закрыть][/color]"),
		"When the cylinder reaches 5/5, the tutorial should skip straight to the close step")


func test_shotgun_shows_bolt_cycle_hint_after_first_shot() -> void:
	## Bug fix #4: Shotgun bolt-cycle hint appears after 1st shot.
	## Bug fix: Shotgun uses HINT_BOLT_CYCLE (not HINT_RELOAD) for its reload instruction.
	tutorial._has_shotgun = true
	tutorial.set_initial_step_based_on_weapon(false)

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_BOLT_CYCLE),
		"Shotgun bolt-cycle hint should NOT appear before any shots")

	tutorial.on_weapon_fired()  # 1st shot

	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_BOLT_CYCLE),
		"Shotgun bolt-cycle hint should appear after 1st shot (Bug fix #4)")
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Shotgun does not use separate RELOAD hint — it uses bolt-cycle hint")


func test_shotgun_shows_full_reload_hint_after_two_shots() -> void:
	## Fix 4th#1: After 2nd shot, shotgun replaces pump hint with full reload hint.
	## Fix 3rd#5: Grenade hint NOT shown during reload step.
	tutorial._has_shotgun = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()  # 1st shot → pump hint
	tutorial.on_weapon_fired()  # 2nd shot → full reload hint replaces pump hint

	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_BOLT_CYCLE),
		"Shotgun should have bolt-cycle hint (full reload hint after 2nd shot)")
	var hint_text: String = tutorial._active_hints.get(MockTutorialLevel.HINT_BOLT_CYCLE, "")
	assert_true(hint_text.contains("открыть"),
		"After 2nd shot, shotgun shows full reload hint with 'открыть' (Fix 4th#1)")
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint NOT shown during reload step (Fix 3rd#5)")


# ============================================================================
# Step Progression Tests
# ============================================================================


func test_fire_mode_change_advances_to_reload() -> void:
	tutorial.set_initial_step_based_on_weapon(true)

	tutorial.on_fire_mode_changed()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.RELOAD,
		"Should advance to RELOAD after switching fire mode")


func test_fire_mode_hint_dismissed_on_switch() -> void:
	tutorial.set_initial_step_based_on_weapon(true)

	tutorial.on_fire_mode_changed()

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_FIRE_MODE),
		"Fire mode hint should be dismissed after switching fire mode")


func test_reload_advances_to_grenade() -> void:
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_reload_completed()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.THROW_GRENADE,
		"Should advance to THROW_GRENADE after reload")


func test_grenade_throw_completes_tutorial() -> void:
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()
	tutorial.on_reload_completed()

	tutorial.on_grenade_thrown()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.COMPLETED,
		"Should advance to COMPLETED after throwing grenade")
	assert_true(tutorial.is_tutorial_complete(), "Tutorial should be complete")


# ============================================================================
# State Guard Tests
# ============================================================================


func test_fire_mode_change_ignored_in_wrong_step() -> void:
	tutorial.advance_to_step(MockTutorialLevel.TutorialStep.RELOAD)

	tutorial.on_fire_mode_changed()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.RELOAD,
		"Fire mode change should be ignored in RELOAD step")


func test_reload_ignored_in_wrong_step() -> void:
	tutorial.set_initial_step_based_on_weapon(true)

	tutorial.on_reload_completed()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.SWITCH_FIRE_MODE,
		"Reload should be ignored in SWITCH_FIRE_MODE step")


func test_grenade_throw_ignored_in_wrong_step() -> void:
	# Grenade is ignored only in SWITCH_FIRE_MODE, SCOPE_TRAINING, COMPLETED steps
	tutorial.advance_to_step(MockTutorialLevel.TutorialStep.SCOPE_TRAINING)

	tutorial.on_grenade_thrown()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.SCOPE_TRAINING,
		"Grenade throw should be ignored in SCOPE_TRAINING step")


# ============================================================================
# Bug Fix Tests: Grenade thrown before reload (Issue #808)
# ============================================================================


func test_grenade_thrown_during_reload_dismisses_grenade_hint() -> void:
	## When grenade is thrown before reload completes, grenade hint should disappear
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	# Throw grenade while still in RELOAD step
	tutorial.on_grenade_thrown()

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint should be dismissed even when thrown before reload (bug fix)")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint should still be visible after grenade thrown early")


func test_grenade_thrown_during_reload_keeps_reload_step() -> void:
	## When grenade is thrown during RELOAD step, should stay in RELOAD step
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_grenade_thrown()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.RELOAD,
		"Should stay in RELOAD step when grenade thrown before reload")


func test_reload_after_early_grenade_completes_tutorial() -> void:
	## When grenade thrown first and then reload completes, tutorial should finish
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_grenade_thrown()  # Grenade first
	tutorial.on_reload_completed()  # Then reload

	assert_true(tutorial.is_tutorial_complete(),
		"Tutorial should complete when reload done after early grenade throw")
	assert_false(tutorial.is_any_hint_active(),
		"No hints should remain after both actions done")


func test_early_grenade_not_double_dismissed() -> void:
	## Throwing grenade twice should not cause errors (idempotent)
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_grenade_thrown()
	tutorial.on_grenade_thrown()  # Second call should be ignored

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint still gone after double throw")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint still shown after double throw attempt")


# ============================================================================
# Revolver Hammer Cock Hint Tests (Issue #808)
# ============================================================================


func test_revolver_shows_hammer_cock_hint() -> void:
	## Bug fix #3: Hammer-cock hint shown from the very start (no shots needed).
	tutorial._has_revolver = true
	tutorial.set_initial_step_based_on_weapon(false)
	# No shots — hammer-cock hint should already be visible

	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_HAMMER_COCK),
		"Revolver should show hammer cock hint immediately on weapon pickup (Bug fix #3)")


func test_revolver_hammer_cock_hint_stays_after_reload() -> void:
	## Fix 3rd#8: Hammer-cock hint must NOT be dismissed on reload — only when player manually cocks.
	tutorial._has_revolver = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_reload_completed()

	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_HAMMER_COCK),
		"Hammer cock hint must stay after reload — only dismissed on HammerCocked signal (Fix 3rd#8)")


func test_revolver_has_reload_and_hammer_hints_after_2_shots() -> void:
	## Fix 3rd#5: Grenade hint shown AFTER reload, not simultaneously.
	## Revolver should show reload + hammer-cock hints during reload step.
	tutorial._has_revolver = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Revolver reload hint shown")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_HAMMER_COCK),
		"Revolver hammer cock hint shown simultaneously")
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint NOT shown during reload step (Fix 3rd#5 — appears after reload)")


func test_non_revolver_no_hammer_cock_hint() -> void:
	## Other weapons should not show hammer cock hint
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_HAMMER_COCK),
		"Default weapon should not have hammer cock hint")


func test_revolver_hammer_cocked_dismisses_hammer_hint() -> void:
	## When revolver hammer is cocked (RMB), hammer cock hint should disappear (Issue #808).
	## Fix 3rd#5: Grenade hint not shown during reload step.
	tutorial._has_revolver = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_hammer_cocked()

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_HAMMER_COCK),
		"Hammer cock hint dismissed when hammer is cocked (Issue #808)")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint remains after hammer cocked")
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint not shown during reload step (Fix 3rd#5)")


func test_revolver_hammer_cocked_twice_is_safe() -> void:
	## Cocking hammer twice should not cause errors (idempotent)
	tutorial._has_revolver = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_hammer_cocked()
	tutorial.on_hammer_cocked()  # Second call should be ignored

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_HAMMER_COCK),
		"Hammer hint still gone after double cock")


func test_revolver_complete_flow_with_hammer_cock() -> void:
	## Full revolver flow: cock hammer first, then reload, then grenade.
	## Fix 3rd#5: Grenade hint shown AFTER reload disappears.
	## Fix 3rd#8: Hammer-cock hint stays after reload, dismissed only by HammerCocked.
	tutorial._has_revolver = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	# Cock hammer — only hammer hint disappears
	tutorial.on_hammer_cocked()

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_HAMMER_COCK),
		"Hammer hint dismissed after cock")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint remains")
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint NOT shown during reload (Fix 3rd#5)")

	# Complete reload — only reload hint disappears; grenade hint appears now
	tutorial.on_reload_completed()

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint dismissed after reload")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint appears AFTER reload (Fix 3rd#5)")
	# Fix 3rd#8: hammer-cock hint is gone (player already cocked it before reload)
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_HAMMER_COCK),
		"Hammer hint already gone (dismissed by HammerCocked signal before reload)")

	# Throw grenade — complete tutorial
	tutorial.on_grenade_thrown()

	assert_true(tutorial.is_tutorial_complete(),
		"Tutorial completes after all actions")
	assert_false(tutorial.is_any_hint_active(),
		"No hints remain after completion")


# ============================================================================
# Full Tutorial Flow Tests
# ============================================================================


func test_complete_tutorial_flow_with_rifle() -> void:
	tutorial._has_assault_rifle = true
	tutorial.set_initial_step_based_on_weapon(true)

	# Step 1: Switch fire mode
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.SWITCH_FIRE_MODE)
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_FIRE_MODE))

	# Fire 2 shots then switch fire mode
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()
	tutorial.on_fire_mode_changed()

	# Step 2: Reload (2 shots already fired before fire mode switch — reload hint appears)
	# Fix 3rd#5: Grenade hint NOT shown simultaneously with reload.
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.RELOAD)
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint active (2 shots already fired before fire mode switch)")
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint NOT shown during reload step (Fix 3rd#5)")

	tutorial.on_reload_completed()

	# Step 3: Throw grenade (reload hint gone, grenade hint now visible)
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.THROW_GRENADE)
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint gone")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint appears AFTER reload (Fix 3rd#5)")

	tutorial.on_grenade_thrown()

	# Step 4: Complete
	assert_true(tutorial.is_tutorial_complete(), "Tutorial should be complete")
	assert_false(tutorial.is_any_hint_active(), "No hints remain after completion")


func test_complete_tutorial_flow_without_rifle() -> void:
	tutorial._has_assault_rifle = false
	tutorial.set_initial_step_based_on_weapon(false)

	# Should skip fire mode step and start with RELOAD step
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.RELOAD,
		"Should start with reload step without assault rifle")
	# Issue #945: NO hints yet — waiting for 2 shots
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint NOT shown yet (Issue #945 — wait for 2 shots)")

	# Fire 2 shots to reveal hints
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint now visible after 2 shots")
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint NOT shown during reload (Fix 3rd#5 — appears after reload)")

	tutorial.on_reload_completed()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.THROW_GRENADE)
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD))
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint visible AFTER reload (Fix 3rd#5)")

	tutorial.on_grenade_thrown()

	assert_true(tutorial.is_tutorial_complete())
	assert_false(tutorial.is_any_hint_active())


func test_complete_sniper_flow() -> void:
	## Fix 3rd#4: bolt-cycle shows 4 separate steps.
	## Fix 3rd#3: bolt-cycle hint updates per step.
	## Fix 3rd#5: grenade hint shown AFTER scope training, not during reload.
	## Fix 4th#3: bolt cycle only dismisses bolt hint; magazine reload advances to SCOPE_TRAINING.
	## Issue #998: Scope hint shown from the very start (alongside reload/bolt hints).
	tutorial._has_sniper_rifle = true
	tutorial.set_initial_step_based_on_weapon(false)

	# Issue #998: Scope hint visible from the very start
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_SCOPE),
		"Scope hint shown from start for sniper (Issue #998)")

	# Fire 1st shot to reveal bolt-cycle hint
	tutorial.on_weapon_fired()
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_BOLT_CYCLE),
		"Bolt-cycle hint shown after 1st shot")
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint NOT shown after 1st shot (appears after 2nd)")

	# Fire 2nd shot to reveal reload hint
	tutorial.on_weapon_fired()
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint [R][F][R] shown after 2nd shot")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_BOLT_CYCLE),
		"Bolt-cycle hint still active")
	# Issue #998: Scope hint still visible alongside reload hint
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_SCOPE),
		"Scope hint still visible during reload step (Issue #998)")
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint NOT shown during reload step (Fix 3rd#5)")

	# Fix 3rd#3: bolt step updates dynamically
	tutorial.on_sniper_bolt_step_changed(1, 4)
	var bolt_text: String = tutorial._active_hints[MockTutorialLevel.HINT_BOLT_CYCLE]
	assert_true(bolt_text.contains("[↓]"),
		"Bolt hint shows [↓] after step 1")

	# Complete bolt cycling — only bolt hint dismissed (Fix 4th#3)
	tutorial.on_sniper_bolt_step_changed(4, 4)

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_BOLT_CYCLE),
		"Bolt cycle hint dismissed after cycling (Fix 4th#3)")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint [R][F][R] STILL shown — bolt cycle alone does not advance (Fix 4th#3)")
	# Issue #998: Scope hint still visible (not yet used by player)
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_SCOPE),
		"Scope hint still visible after bolt cycle — not yet used (Issue #998)")
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.RELOAD,
		"Still in RELOAD step after bolt cycle (Fix 4th#3)")

	# Magazine reload advances to SCOPE_TRAINING
	tutorial.on_reload_completed()

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint dismissed after magazine reload")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_SCOPE),
		"Scope hint still shown in SCOPE_TRAINING step (Fix 4th#3 + Issue #998)")
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint NOT shown during scope training (Fix 3rd#5)")
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.SCOPE_TRAINING,
		"Advanced to SCOPE_TRAINING after magazine reload (Fix 4th#3)")

	# Use scope
	tutorial.on_scope_state_changed(true)

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_SCOPE))
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint appears AFTER scope training (Fix 3rd#5)")

	# Throw grenade
	tutorial.on_grenade_thrown()

	assert_true(tutorial.is_tutorial_complete())
	assert_false(tutorial.is_any_hint_active())


func test_complete_revolver_flow() -> void:
	tutorial._has_revolver = true
	tutorial.set_initial_step_based_on_weapon(false)

	# Fire 2 shots to reveal reload hints
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	# Revolver shows reload + hammer-cock; grenade NOT shown simultaneously (Fix 3rd#5)
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD))
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_HAMMER_COCK))
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade NOT shown during reload (Fix 3rd#5)")

	# Complete reload — dismisses reload; hammer-cock STAYS (Fix 3rd#8), grenade appears (Fix 3rd#5)
	tutorial.on_reload_completed()

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD))
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_HAMMER_COCK),
		"Hammer-cock hint stays after reload (Fix 3rd#8 — only dismissed via HammerCocked)")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint now visible after reload (Fix 3rd#5)")
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.THROW_GRENADE)

	# Throw grenade to complete
	tutorial.on_grenade_thrown()

	assert_true(tutorial.is_tutorial_complete())
	# Note: hammer-cock hint may still be active if never cocked — tutorial still completes


func test_complete_flow_grenade_first_then_reload() -> void:
	## Fix 3rd#5: Grenade hint is NOT shown during RELOAD step; player must complete reload first.
	## This test verifies that grenade thrown during RELOAD step is ignored.
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	# Grenade thrown during RELOAD step — grenade hint not active, so nothing happens
	tutorial.on_grenade_thrown()

	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint still active (grenade throw ignored when not in THROW_GRENADE step)")
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.RELOAD,
		"Still in RELOAD step (grenade thrown too early — hint not shown yet)")

	# Complete reload — grenade hint now appears
	tutorial.on_reload_completed()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.THROW_GRENADE,
		"Now in THROW_GRENADE step")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint visible after reload (Fix 3rd#5)")
	assert_false(tutorial.is_tutorial_complete(),
		"Tutorial NOT complete yet — grenade still needs to be thrown")

	# Throw grenade to complete
	tutorial.on_grenade_thrown()
	assert_true(tutorial.is_tutorial_complete(), "Tutorial completes after grenade thrown")


# ============================================================================
# Third Review Round Bug Fix Tests
# ============================================================================


func test_hint_spacing_is_60() -> void:
	## Fix 3rd#1: HINT_SPACING should be 60 to prevent overlap.
	assert_eq(MockTutorialLevel.HINT_SPACING, 60,
		"HINT_SPACING should be 60px (Fix 3rd#1)")


func test_shotgun_bolt_cycle_hint_appears_after_first_shot() -> void:
	## Fix 3rd#2: Shotgun bolt-cycle hint appears after 1st shot.
	tutorial._has_shotgun = true
	tutorial._shotgun_capacity = 8
	tutorial._shotgun_current_ammo = 0
	tutorial.set_initial_step_based_on_weapon(false)

	tutorial.on_weapon_fired()

	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_BOLT_CYCLE),
		"Shotgun bolt-cycle hint shown after 1st shot (Fix 3rd#2)")


func test_shotgun_bolt_cycle_hint_shows_pump_action_after_first_shot() -> void:
	## Fix 4th#1: After 1st shot, shotgun shows pump-action hint [ПКМ↑][ПКМ↓] (not full reload).
	## Full reload hint with shell count only appears after 2nd shot when ammo runs out.
	tutorial._has_shotgun = true
	tutorial._shotgun_capacity = 8
	tutorial._shotgun_current_ammo = 3  # 3 shells loaded, still have ammo
	tutorial.set_initial_step_based_on_weapon(false)

	tutorial.on_weapon_fired()  # Reveals bolt-cycle hint (pump-action hint)

	var hint_text: String = tutorial._active_hints.get(MockTutorialLevel.HINT_BOLT_CYCLE, "")
	assert_true(hint_text.contains("ПКМ↑"),
		"After 1st shot, shotgun shows pump-action hint with [ПКМ↑] (Fix 4th#1)")
	assert_true(hint_text.contains("Передёрни затвор"),
		"Pump-action hint text says 'Передёрни затвор' (Fix 4th#1)")
	assert_false(hint_text.contains("открыть"),
		"Pump hint does NOT show full reload sequence after 1st shot (Fix 4th#1)")


func test_shotgun_reload_count_updates_on_shell_loaded() -> void:
	## Fix 3rd#7: Shell count updates live as each shell is loaded.
	tutorial._has_shotgun = true
	tutorial._shotgun_capacity = 8
	tutorial._shotgun_current_ammo = 0
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()

	# Load 2 shells
	tutorial.on_shell_count_changed(2)

	var hint_text: String = tutorial._active_hints.get(MockTutorialLevel.HINT_BOLT_CYCLE, "")
	assert_true(hint_text.contains("x6"),
		"Shotgun reload count updates to x6 after loading 2 shells (Fix 3rd#7)")


func test_sniper_bolt_hint_shows_4_steps() -> void:
	## Fix 3rd#4: Sniper bolt-cycle hint shows 4 separate steps [←][↓][↑][→].
	tutorial._has_sniper_rifle = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()  # Reveals bolt-cycle hint

	var hint_text: String = tutorial._active_hints.get(MockTutorialLevel.HINT_BOLT_CYCLE, "")
	assert_true(hint_text.contains("[←]"), "Hint shows [←] step (Fix 3rd#4)")
	assert_true(hint_text.contains("[↓]"), "Hint shows [↓] step (Fix 3rd#4)")
	assert_true(hint_text.contains("[↑]"), "Hint shows [↑] step (Fix 3rd#4)")
	assert_true(hint_text.contains("[→]"), "Hint shows [→] step (Fix 3rd#4)")


func test_sniper_bolt_hint_first_step_in_red() -> void:
	## Fix 3rd#3: First step [←] should be highlighted red initially.
	tutorial._has_sniper_rifle = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()  # Reveals bolt-cycle hint (step=0)

	var hint_text: String = tutorial._active_hints.get(MockTutorialLevel.HINT_BOLT_CYCLE, "")
	assert_true(hint_text.contains("#ff4444][←]"),
		"First step [←] is red at step=0 (Fix 3rd#3)")
	assert_true(hint_text.contains("#888888][↓]"),
		"Second step [↓] is grey at step=0 (Fix 3rd#3)")


func test_sniper_bolt_hint_updates_per_step() -> void:
	## Fix 3rd#3: Bolt-cycle hint text updates to show current step in red.
	tutorial._has_sniper_rifle = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()  # Step 0: [←] in red
	tutorial.on_weapon_fired()  # Step 2nd shot reveals reload hint too

	# Advance bolt to step 2
	tutorial.on_sniper_bolt_step_changed(2, 4)

	var hint_text: String = tutorial._active_hints.get(MockTutorialLevel.HINT_BOLT_CYCLE, "")
	assert_true(hint_text.contains("#888888][←]"),
		"[←] is grey after step 2 (Fix 3rd#3)")
	assert_true(hint_text.contains("#888888][↓]"),
		"[↓] is grey after step 2 (Fix 3rd#3)")
	assert_true(hint_text.contains("#ff4444][↑]"),
		"[↑] is red at step 2 (Fix 3rd#3)")


func test_grenade_hint_appears_after_reload_not_simultaneously() -> void:
	## Fix 3rd#5: Grenade hint must appear AFTER reload disappears, not during.
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	# During reload — no grenade hint
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD))
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint must NOT appear during reload (Fix 3rd#5)")

	# After reload — grenade hint appears
	tutorial.on_reload_completed()

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD))
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint appears AFTER reload (Fix 3rd#5)")


func test_m16_shows_fire_mode_hint_after_reload() -> void:
	## Fix 3rd#6: M16 (assault rifle, not AK GL) shows fire-mode switch hint after reload.
	tutorial._has_assault_rifle = true
	tutorial._has_ak_gl = false
	tutorial.set_initial_step_based_on_weapon(true)

	# Fire mode step: switch mode
	tutorial.on_fire_mode_changed()

	# Fire 2 shots for reload hint (already fired during fire mode step)
	# Manually set reload_hint_revealed since shots were fired
	tutorial._reload_hint_revealed = true
	tutorial._shots_fired = 2
	tutorial.advance_to_step(MockTutorialLevel.TutorialStep.RELOAD)

	tutorial.on_reload_completed()

	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_FIRE_MODE),
		"M16 shows fire-mode switch (B) hint after reload (Fix 3rd#6)")


func test_ak_gl_shows_grenade_launcher_hint_after_reload() -> void:
	## Fix 3rd#10: AK GL shows underbarrel grenade launcher hint after reload.
	tutorial._has_assault_rifle = true
	tutorial._has_ak_gl = true
	tutorial._ak_gl_has_round = true
	tutorial.set_initial_step_based_on_weapon(true)
	tutorial.on_fire_mode_changed()
	tutorial._reload_hint_revealed = true
	tutorial._shots_fired = 2
	tutorial.advance_to_step(MockTutorialLevel.TutorialStep.RELOAD)

	tutorial.on_reload_completed()

	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE_LAUNCHER),
		"AK GL shows underbarrel grenade launcher hint after reload (Fix 3rd#10)")
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_FIRE_MODE),
		"AK GL does NOT show separate fire-mode hint (Fix 3rd#10)")


func test_ak_gl_no_grenade_launcher_hint_when_no_round() -> void:
	## Fix 3rd#10: AK GL should NOT show launcher hint if no round is loaded.
	tutorial._has_assault_rifle = true
	tutorial._has_ak_gl = true
	tutorial._ak_gl_has_round = false
	tutorial.set_initial_step_based_on_weapon(true)
	tutorial.on_fire_mode_changed()
	tutorial._reload_hint_revealed = true
	tutorial._shots_fired = 2
	tutorial.advance_to_step(MockTutorialLevel.TutorialStep.RELOAD)

	tutorial.on_reload_completed()

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE_LAUNCHER),
		"AK GL does NOT show launcher hint when no round loaded (Fix 3rd#10)")


func test_shotgun_reload_hint_dismissed_after_reload() -> void:
	## Fix 3rd#7: Shotgun bolt-cycle hint is dismissed when reload completes.
	tutorial._has_shotgun = true
	tutorial._shotgun_capacity = 8
	tutorial._shotgun_current_ammo = 0
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()  # Reveals bolt-cycle hint

	tutorial.on_reload_completed()

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_BOLT_CYCLE),
		"Shotgun bolt-cycle hint dismissed after reload (Fix 3rd#7)")


func test_revolver_hammer_cock_hint_stays_until_manual_cock() -> void:
	## Fix 3rd#8: Revolver hammer-cock hint stays after reload; dismissed only by HammerCocked signal.
	tutorial._has_revolver = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_reload_completed()

	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_HAMMER_COCK),
		"Hammer-cock hint stays after reload (Fix 3rd#8)")

	# Manual cock dismisses it
	tutorial.on_hammer_cocked()

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_HAMMER_COCK),
		"Hammer-cock hint dismissed after manual cock (Fix 3rd#8)")


func test_grenade_hint_not_shown_without_grenades() -> void:
	## Fix 3rd#9: Grenade hint should NOT appear if player has no grenades.
	tutorial._grenade_count = 0
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_reload_completed()

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint NOT shown when player has no grenades (Fix 3rd#9)")
	assert_true(tutorial.is_tutorial_complete(),
		"Tutorial auto-completes when no grenades available (Fix 3rd#9)")


func test_grenade_hint_shown_when_has_grenades() -> void:
	## Fix 3rd#9: Grenade hint IS shown when player has at least 1 grenade.
	tutorial._grenade_count = 3
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_reload_completed()

	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint shown when player has grenades (Fix 3rd#9)")


# ============================================================================
# Issue #983 Bug Fix Tests
# ============================================================================


func test_shotgun_hint_dismissed_via_reload_state_not_reload_completed() -> void:
	## Issue #983 Fix 1: Shotgun hint is dismissed when ReloadStateChanged(0) fires,
	## NOT via on_reload_completed (which is never emitted for shotgun).
	tutorial._has_shotgun = true
	tutorial._shotgun_capacity = 8
	tutorial._shotgun_current_ammo = 0
	tutorial._grenade_count = 0
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()   # 1st shot: reveals pump hint
	tutorial.on_weapon_fired()   # 2nd shot: reveals full reload hint

	# Simulate full reload sequence: open(1) → loading(2) → close(3) → done(0)
	tutorial.on_shotgun_reload_state_changed(1)
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_BOLT_CYCLE),
		"Hint still visible during reload (state=1)")
	tutorial.on_shotgun_reload_state_changed(2)
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_BOLT_CYCLE),
		"Hint still visible while loading shells (state=2)")
	tutorial.on_shotgun_reload_state_changed(3)
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_BOLT_CYCLE),
		"Hint still visible waiting to close bolt (state=3)")

	# Reload complete: state=0 should dismiss hint
	tutorial.on_shotgun_reload_state_changed(0)

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_BOLT_CYCLE),
		"Issue #983 Fix 1: Shotgun bolt-cycle hint dismissed when ReloadStateChanged(0)")


func test_shotgun_hint_not_reset_to_first_step_on_reload_complete() -> void:
	## Issue #983 Fix 1: When reload completes (state=0), hint must NOT reset to
	## show the first step [ПКМ↑ открыть] highlighted in red.
	tutorial._has_shotgun = true
	tutorial._shotgun_capacity = 8
	tutorial._shotgun_current_ammo = 0
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	# Simulate full reload and completion
	tutorial.on_shotgun_reload_state_changed(1)
	tutorial.on_shotgun_reload_state_changed(2)
	tutorial.on_shotgun_reload_state_changed(3)
	tutorial.on_shotgun_reload_state_changed(0)

	# Hint must be gone — not showing "ПКМ↑ открыть" highlighted red again
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_BOLT_CYCLE),
		"Issue #983 Fix 1: Hint is gone after reload complete — not reset to first step")


func test_shotgun_tutorial_advances_to_grenade_on_reload_complete() -> void:
	## Issue #983 Fix 1: Tutorial advances to THROW_GRENADE after shotgun reload completes.
	tutorial._has_shotgun = true
	tutorial._shotgun_capacity = 8
	tutorial._shotgun_current_ammo = 0
	tutorial._grenade_count = 3
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_shotgun_reload_state_changed(0)  # Reload complete

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.THROW_GRENADE,
		"Issue #983 Fix 1: Tutorial advances to THROW_GRENADE after shotgun reload completes")


func test_shotgun_shells_to_load_uses_shells_in_tube() -> void:
	## Issue #983 Fix 2: _get_shotgun_shells_to_load (via _build_shotgun_full_reload_hint_bbcode)
	## uses ShellsInTube / TubeMagazineCapacity, not CurrentAmmo / MaxAmmo.
	## In the mock, these are _shotgun_current_ammo and _shotgun_capacity.
	tutorial._has_shotgun = true
	tutorial._shotgun_capacity = 8
	tutorial._shotgun_current_ammo = 6  # 6 shells loaded, 2 empty slots
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()  # Full reload hint appears

	var hint_text: String = tutorial._active_hints.get(MockTutorialLevel.HINT_BOLT_CYCLE, "")
	assert_true(hint_text.contains("x2"),
		"Issue #983 Fix 2: Shotgun hint shows x2 when 6 shells already loaded (capacity 8)")
	assert_false(hint_text.contains("x8"),
		"Issue #983 Fix 2: Shotgun hint does NOT show x8 when only 2 shells needed")


func test_shotgun_shells_to_load_zero_when_full() -> void:
	## Issue #983 Fix 2: When tube is full, shells_to_load = 0.
	tutorial._has_shotgun = true
	tutorial._shotgun_capacity = 8
	tutorial._shotgun_current_ammo = 8  # Fully loaded
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	var hint_text: String = tutorial._active_hints.get(MockTutorialLevel.HINT_BOLT_CYCLE, "")
	assert_true(hint_text.contains("x0"),
		"Issue #983 Fix 2: Shotgun hint shows x0 when tube is full")


func test_grenade_hint_uses_issue_1818_reviewed_text() -> void:
	tutorial.advance_to_step(MockTutorialLevel.TutorialStep.THROW_GRENADE)

	var hint_text: String = tutorial.get_active_hints().get(MockTutorialLevel.HINT_GRENADE, "")
	assert_true(hint_text.contains("[удерживать G+ПКМ]"),
		"Grenade hint should start with hold G+RMB text from issue #1818")
	assert_true(hint_text.contains("[дёрнуть мышкой вправо] [отпустить ПКМ]"),
		"Grenade hint should merge drag-right and RMB release into one reviewed step")
	assert_true(hint_text.contains("[зажать ПКМ]"),
		"Grenade hint should include RMB hold step from issue #1818")
	assert_true(hint_text.contains("[отпустить G]"),
		"Grenade hint should include G release step from issue #1818")
	assert_true(hint_text.contains("[прицелиться и отпустить ПКМ]"),
		"Grenade hint should include final aim-and-release step from issue #1818")


func test_grenade_hint_progression_updates_next_reviewed_step() -> void:
	tutorial.advance_to_step(MockTutorialLevel.TutorialStep.THROW_GRENADE)

	tutorial.set_grenade_hint_progress(true, false, false)
	var hint_text: String = tutorial.get_active_hints().get(MockTutorialLevel.HINT_GRENADE, "")
	assert_true(hint_text.contains("[color=#ff4444][удерживать G+ПКМ][/color]"),
		"Without RMB the first reviewed step should stay highlighted")

	tutorial.set_grenade_hint_progress(true, true, false)
	hint_text = tutorial.get_active_hints().get(MockTutorialLevel.HINT_GRENADE, "")
	assert_true(hint_text.contains("[color=#ff4444][зажать ПКМ][/color]"),
		"After drag+release, the hold-RMB-again step should be highlighted next")

	tutorial.set_grenade_hint_progress(false, true, false)
	hint_text = tutorial.get_active_hints().get(MockTutorialLevel.HINT_GRENADE, "")
	assert_true(hint_text.contains("[color=#ff4444][зажать ПКМ][/color]"),
		"Without re-holding RMB the hold-RMB-again step should stay highlighted")

	tutorial.set_grenade_hint_progress(false, true, true)
	hint_text = tutorial.get_active_hints().get(MockTutorialLevel.HINT_GRENADE, "")
	assert_true(hint_text.contains("[color=#ff4444][отпустить G][/color]"),
		"After holding RMB again, the release-G step should be highlighted next")


func test_grenade_hint_requires_actual_input_transitions_for_reviewed_steps() -> void:
	tutorial.advance_to_step(MockTutorialLevel.TutorialStep.THROW_GRENADE)

	tutorial.update_grenade_hint_from_input(true, false, 0.0)
	var hint_text: String = tutorial.get_active_hints().get(MockTutorialLevel.HINT_GRENADE, "")
	assert_true(hint_text.contains("[color=#ff4444][удерживать G+ПКМ][/color]"),
		"Holding G alone should not complete the first reviewed step")

	tutorial.update_grenade_hint_from_input(true, true, 10.0)
	hint_text = tutorial.get_active_hints().get(MockTutorialLevel.HINT_GRENADE, "")
	assert_true(hint_text.contains("[color=#ff4444][дёрнуть мышкой вправо] [отпустить ПКМ][/color]"),
		"Pressing G+RMB should complete the first step and highlight the combined drag+release step")

	tutorial.update_grenade_hint_from_input(true, true, 40.0)
	hint_text = tutorial.get_active_hints().get(MockTutorialLevel.HINT_GRENADE, "")
	assert_true(hint_text.contains("[color=#ff4444][дёрнуть мышкой вправо] [отпустить ПКМ][/color]"),
		"Dragging right should complete only the right-flick action and keep the RMB release action highlighted")

	tutorial.update_grenade_hint_from_input(true, false, 40.0)
	hint_text = tutorial.get_active_hints().get(MockTutorialLevel.HINT_GRENADE, "")
	assert_true(hint_text.contains("[color=#ff4444][зажать ПКМ][/color]"),
		"Releasing RMB should immediately complete that step and highlight RMB hold next")

	tutorial.update_grenade_hint_from_input(false, false, 40.0)
	hint_text = tutorial.get_active_hints().get(MockTutorialLevel.HINT_GRENADE, "")
	assert_true(hint_text.contains("[color=#ff4444][удерживать G+ПКМ][/color]"),
		"Canceling preparation before re-activating grenade should roll back to the first step")

	tutorial.update_grenade_hint_from_input(true, true, 40.0)
	tutorial.update_grenade_hint_from_input(true, true, 70.0)
	tutorial.update_grenade_hint_from_input(true, false, 70.0)
	tutorial.update_grenade_hint_from_input(true, true, 70.0)
	hint_text = tutorial.get_active_hints().get(MockTutorialLevel.HINT_GRENADE, "")
	assert_true(hint_text.contains("[color=#ff4444][отпустить G][/color]"),
		"Holding G+RMB again should advance to the release-G step")

	tutorial.update_grenade_hint_from_input(false, true, 40.0)
	hint_text = tutorial.get_active_hints().get(MockTutorialLevel.HINT_GRENADE, "")
	assert_true(hint_text.contains("[color=#ff4444][прицелиться и отпустить ПКМ][/color]"),
		"Releasing G while RMB stays held should immediately highlight the final throw step")

	tutorial.update_grenade_hint_from_input(false, false, 40.0)
	hint_text = tutorial.get_active_hints().get(MockTutorialLevel.HINT_GRENADE, "")
	assert_true(hint_text.contains("[color=#ff4444][прицелиться и отпустить ПКМ][/color]"),
		"The final step should remain highlighted until the actual grenade throw dismisses the hint")


func test_grenade_hint_rolls_back_when_preparation_is_canceled() -> void:
	tutorial.advance_to_step(MockTutorialLevel.TutorialStep.THROW_GRENADE)

	tutorial.update_grenade_hint_from_input(true, true, 0.0)
	tutorial.update_grenade_hint_from_input(true, true, 40.0)
	tutorial.update_grenade_hint_from_input(true, false, 40.0)

	var hint_text: String = tutorial.get_active_hints().get(MockTutorialLevel.HINT_GRENADE, "")
	assert_true(hint_text.contains("[color=#ff4444][зажать ПКМ][/color]"),
		"After the combined drag+release step the next step should be hold RMB again")

	tutorial.update_grenade_hint_from_input(false, false, 40.0)
	hint_text = tutorial.get_active_hints().get(MockTutorialLevel.HINT_GRENADE, "")
	assert_true(hint_text.contains("[color=#ff4444][удерживать G+ПКМ][/color]"),
		"Canceling grenade preparation should reset the hint to the first incomplete step")


# ============================================================================
# Issue #998: Scope RMB hint shown from the very start for sniper rifle
# ============================================================================


func test_sniper_scope_hint_shown_from_start() -> void:
	## Issue #998: Scope hint appears immediately when sniper rifle is equipped.
	tutorial._has_sniper_rifle = true
	tutorial.set_initial_step_based_on_weapon(false)

	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_SCOPE),
		"Scope RMB hint must appear from the very start for sniper rifle (Issue #998)")
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.RELOAD,
		"Tutorial starts at RELOAD step with scope hint visible (Issue #998)")


func test_sniper_scope_hint_dismissed_when_scope_used_early() -> void:
	## Issue #998: If player uses scope during RELOAD step, scope hint is dismissed immediately.
	tutorial._has_sniper_rifle = true
	tutorial.set_initial_step_based_on_weapon(false)

	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_SCOPE),
		"Scope hint visible from start (Issue #998)")

	tutorial.on_scope_state_changed(true)

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_SCOPE),
		"Scope hint dismissed after scope used (Issue #998)")
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.RELOAD,
		"Tutorial still in RELOAD step — scope used early, reload not done yet (Issue #998)")


func test_sniper_scope_training_skipped_when_scope_used_before_reload() -> void:
	## Issue #998: If scope was used before reload completes, SCOPE_TRAINING is skipped.
	tutorial._has_sniper_rifle = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	# Use scope before completing reload
	tutorial.on_scope_state_changed(true)
	assert_true(tutorial._scope_used, "Scope marked as used (Issue #998)")

	# Complete reload — should skip SCOPE_TRAINING and go directly to THROW_GRENADE
	tutorial.on_reload_completed()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.THROW_GRENADE,
		"After early scope use + reload, jump to THROW_GRENADE (skip SCOPE_TRAINING, Issue #998)")
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_SCOPE),
		"Scope hint not shown again after early use (Issue #998)")


func test_sniper_scope_hint_color_is_cyan() -> void:
	## Issue #998: Scope hint uses cyan color (same as scope training in original flow).
	tutorial._has_sniper_rifle = true
	tutorial.set_initial_step_based_on_weapon(false)

	assert_eq(tutorial.get_hint_color(MockTutorialLevel.HINT_SCOPE),
		MockTutorialLevel.HINT_COLOR_SCOPE,
		"Scope hint should use cyan color (Issue #998)")


func test_sniper_scope_training_still_works_normally_when_scope_not_used_early() -> void:
	## Issue #998: If player does NOT use scope early, normal SCOPE_TRAINING flow still works.
	tutorial._has_sniper_rifle = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	# Complete reload without using scope — should advance to SCOPE_TRAINING
	tutorial.on_reload_completed()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.SCOPE_TRAINING,
		"Tutorial advances to SCOPE_TRAINING after reload if scope not used early (Issue #998)")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_SCOPE),
		"Scope hint remains active in SCOPE_TRAINING step (Issue #998)")
