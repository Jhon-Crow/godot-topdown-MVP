extends GutTest
## Unit tests for the LabyrinthLevel tutorial hint system.
##
## Tests Issue #945 changes applied to the Laboratory level:
## (1) Reload hint appears only after 2 shots (same as tutorial_level.gd).
## (2) Each simultaneous hint has a unique color.
## (3) The NEXT button in a multi-step reload is highlighted in red using BBCode.
##
## Also validates Issue #808 behaviour: reload and grenade hints are shown
## simultaneously, and each dismisses independently.
##
## Bug fixes (second review round):
## Fix #1: Hint spacing increased to 50px to prevent overlap.
## Fix #2: `step` in ReloadSequenceProgress is LAST COMPLETED step (0=nothing done).
## Fix #3: Revolver hammer-cock hint shown from weapon pickup (before 2 shots).
## Fix #4: Bolt-cycle hint (sniper/shotgun) shown after 1st shot, not 2nd.
## Fix #5: Revolver/shotgun reload hints are static; ReloadSequenceProgress must not overwrite.
##
## Bug fixes (third review round, Issue #945):
## Fix 3rd#1: HINT_SPACING increased to 60px.
## Fix 3rd#4: Sniper bolt-action shows 4 separate steps [←][↓][↑][→].
## Fix 3rd#3: Sniper bolt-cycle hint updates step-by-step.
## Fix 3rd#5: Grenade hint shown AFTER reload disappears, not simultaneously.
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
##            tutorial; magazine reload (R→F→R) via on_tutorial_reload_completed advances it.
## Fix 4th#4: Lab map grenade tutorial appears — use GetCurrentGrenades() not get("GrenadeCount").
## Fix 4th#5: AK GL hint uses GrenadeAvailable (bool) instead of GrenadeLauncherAmmo (missing).
##
## Bug fixes (sixth review round, Issue #945):
## Fix R6-1: AK GL and Revolver tutorial lines now appear on Labyrinth map.
##   Root cause: _setup_selected_weapon() weapon_names dict was missing "ak_gl" and "revolver"
##   entries, so the early-return check for "already equipped by C# Player" never triggered.
##   C# Player._Ready() calls ApplySelectedWeaponFromGameManager() which adds the correct weapon
##   BEFORE the GDScript level's _ready() runs.  Without the check, _setup_selected_weapon()
##   added a second, duplicate node (Godot auto-renamed it "AKGL2"/"Revolver2").
##   _setup_player_tracking() then connected all signals (AmmoChanged, Fired, etc.) to the
##   first, idle node, while the player actually fired the duplicate.  Result: shot-counter
##   never incremented, tutorial hints never appeared, ammo counter never updated.
##   Fix: add "ak_gl": "AKGL" and "revolver": "Revolver" to weapon_names in labyrinth_level.gd.
## Fix R6-2: Revolver ammo counter now updates live during cylinder reload on Labyrinth map.
##   Root cause: CartridgeInserted signal was connected in tutorial_level.gd but NOT in
##   labyrinth_level.gd. AmmoChanged fires only on full reload completion; CartridgeInserted
##   fires for each cartridge inserted (Issue #626). Without it the counter froze mid-reload.
##   Fix: connect CartridgeInserted to _on_revolver_cartridge_inserted in labyrinth_level.gd.
##
## Issue #998:
## Scope RMB hint shown from the very start for sniper rifle on Laboratory level.
## Dismissed when player activates scope (ScopeStateChanged signal connected).


# ============================================================================
# Mock Labyrinth Tutorial Hint System
# ============================================================================


class MockLabyrinthTutorial:
	## Tutorial step machine (mirrors labyrinth_level.gd).
	enum TutorialStep {
		RELOAD,
		THROW_GRENADE,
		COMPLETED
	}

	## Hint keys (mirrors labyrinth_level.gd constants).
	const TUTORIAL_HINT_RELOAD := "reload"
	const TUTORIAL_HINT_GRENADE := "grenade"
	const TUTORIAL_HINT_HAMMER_COCK := "hammer_cock"
	const TUTORIAL_HINT_BOLT_CYCLE := "bolt_cycle"
	const TUTORIAL_HINT_GRENADE_LAUNCHER := "grenade_launcher"  ## Fix 3rd#10
	const TUTORIAL_HINT_SCOPE := "scope"  ## Issue #998

	## Fix 3rd#1: Hint spacing increased to 60px.
	const TUTORIAL_HINT_SPACING: float = 60.0

	## Unique colors per hint type (Issue #945).
	const TUTORIAL_HINT_COLOR_RELOAD := Color(0.4, 1.0, 0.5, 1.0)
	const TUTORIAL_HINT_COLOR_GRENADE := Color(1.0, 0.65, 0.0, 1.0)
	const TUTORIAL_HINT_COLOR_BOLT_CYCLE := Color(0.85, 0.6, 1.0, 1.0)
	const TUTORIAL_HINT_COLOR_HAMMER_COCK := Color(1.0, 0.8, 0.3, 1.0)
	const TUTORIAL_HINT_COLOR_GRENADE_LAUNCHER := Color(1.0, 0.4, 0.2, 1.0)
	const TUTORIAL_HINT_COLOR_SCOPE := Color(0.3, 0.9, 1.0, 1.0)  ## Issue #998

	var _tutorial_step: TutorialStep = TutorialStep.RELOAD
	var _tutorial_has_reloaded: bool = false
	var _tutorial_has_thrown_grenade: bool = false
	var _tutorial_has_shotgun: bool = false
	var _tutorial_has_sniper_rifle: bool = false
	var _tutorial_has_revolver: bool = false
	var _tutorial_has_makarov_pm: bool = false
	var _tutorial_has_ak_gl: bool = false  ## Fix 3rd#10

	## Fix 3rd#7: Shotgun ammo tracking
	var _shotgun_capacity: int = 8
	var _shotgun_current_ammo: int = 0
	## Fix 3rd#9: Grenade count
	var _grenade_count: int = 3
	## Fix 3rd#10: AK GL round
	var _ak_gl_has_round: bool = true
	var _tutorial_shotgun_reload_started: bool = false
	var _tutorial_revolver_reload_started: bool = false
	var _tutorial_m16_needs_fire_mode_hint: bool = false
	var _tutorial_has_m16: bool = false

	## Issue #945: shot counter and reveal flag.
	var _tutorial_shots_fired: int = 0
	var _tutorial_reload_hint_revealed: bool = false
	## Bug fix #4: bolt-cycle hint revealed after 1st shot.
	var _tutorial_bolt_cycle_hint_revealed: bool = false
	var _tutorial_sniper_bolt_cycled: bool = false
	## Issue #998: scope used tracking.
	var _tutorial_scope_used: bool = false

	## Active hints: hint_key -> hint_text (simulates visible labels).
	var _active_hints: Dictionary = {}
	## Active hint colors: hint_key -> Color (Issue #945).
	var _active_hint_colors: Dictionary = {}

	func is_hint_active(hint_key: String) -> bool:
		return _active_hints.has(hint_key)

	func is_any_hint_active() -> bool:
		return not _active_hints.is_empty()

	func get_hint_text(hint_key: String) -> String:
		return _active_hints.get(hint_key, "")

	func get_hint_color(hint_key: String) -> Color:
		return _active_hint_colors.get(hint_key, Color.WHITE)

	func get_active_hint_count() -> int:
		return _active_hints.size()

	func get_step() -> TutorialStep:
		return _tutorial_step

	func _get_tutorial_hint_color(hint_key: String) -> Color:
		match hint_key:
			TUTORIAL_HINT_RELOAD:
				return TUTORIAL_HINT_COLOR_RELOAD
			TUTORIAL_HINT_GRENADE:
				return TUTORIAL_HINT_COLOR_GRENADE
			TUTORIAL_HINT_BOLT_CYCLE:
				return TUTORIAL_HINT_COLOR_BOLT_CYCLE
			TUTORIAL_HINT_HAMMER_COCK:
				return TUTORIAL_HINT_COLOR_HAMMER_COCK
			TUTORIAL_HINT_GRENADE_LAUNCHER:
				return TUTORIAL_HINT_COLOR_GRENADE_LAUNCHER  ## Fix 3rd#10
			TUTORIAL_HINT_SCOPE:
				return TUTORIAL_HINT_COLOR_SCOPE  ## Issue #998
			_:
				return Color(1.0, 1.0, 0.3, 1.0)

	func _add_hint(hint_key: String, text: String) -> void:
		_active_hints[hint_key] = text
		_active_hint_colors[hint_key] = _get_tutorial_hint_color(hint_key)

	func _dismiss_hint(hint_key: String) -> void:
		_active_hints.erase(hint_key)
		_active_hint_colors.erase(hint_key)

	## Fix 3rd#4, 3rd#3: Build BBCode for sniper bolt-cycle hint with 4-step sequence.
	func _build_tutorial_sniper_bolt_hint_bbcode(step: int) -> String:
		const STEPS := ["←", "↓", "↑", "→"]
		var parts: PackedStringArray = []
		for i in range(STEPS.size()):
			if i == step:
				parts.append("[color=#ff4444][%s][/color]" % STEPS[i])
			else:
				parts.append("[color=#888888][%s][/color]" % STEPS[i])
		return " ".join(parts) + " Передёрни затвор"

	## Fix 3rd#7: Build BBCode for shotgun reload hint with dynamic shell count.
	func _build_tutorial_shotgun_reload_hint_bbcode() -> String:
		var shells_needed: int = _shotgun_capacity - _shotgun_current_ammo
		return "[color=#ff4444][ПКМ↑ открыть][/color] [color=#888888][СКМ+ПКМ↓ x%d] [ПКМ↓ закрыть][/color]" % shells_needed

	## Fix 4th#1: Build BBCode for shotgun pump-action hint (between shots).
	func _build_tutorial_shotgun_pump_hint_bbcode(state: int) -> String:
		match state:
			1:  # NeedsPumpUp
				return "[color=#ff4444][ПКМ↑][/color] [color=#888888][ПКМ↓][/color] Передёрни затвор"
			2:  # NeedsPumpDown
				return "[color=#888888][ПКМ↑][/color] [color=#ff4444][ПКМ↓][/color] Передёрни затвор"
			_:
				return "[color=#ff4444][ПКМ↑][/color] [color=#888888][ПКМ↓][/color] Передёрни затвор"

	## Fix 4th#1, #2: Build BBCode for shotgun full-reload hint with step-based highlighting.
	func _build_tutorial_shotgun_full_reload_hint_bbcode(state: int) -> String:
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

	func _build_tutorial_grenade_hint_bbcode(step: int) -> String:
		var parts := [
			"[удерживать G+ПКМ]",
			"[дёрнуть мышкой вправо] [отпустить ПКМ]",
			"[зажать ПКМ]",
			"[отпустить G]",
			"[прицелиться и отпустить ПКМ]",
		]
		var styled: PackedStringArray = []
		for i in range(parts.size()):
			if i < step:
				styled.append("[color=#888888]%s[/color]" % parts[i])
			elif i == step:
				styled.append("[color=#ff4444]%s[/color]" % parts[i])
			else:
				styled.append("[color=#888888]%s[/color]" % parts[i])
		return " ".join(styled)

	## Fix 4th#2: Build BBCode for revolver reload hint with step-based highlighting.
	func _build_tutorial_revolver_reload_hint_bbcode(step: int) -> String:
		match step:
			0:
				return "[color=#ff4444][R открыть][/color] [color=#888888][ПКМ↑ патрон] [скролл] [R закрыть][/color]"
			1:
				return "[color=#888888][R открыть][/color] [color=#ff4444][ПКМ↑ патрон][/color] [color=#888888][скролл] [R закрыть][/color]"
			2:
				return "[color=#888888][R открыть] [ПКМ↑ патрон] [скролл][/color] [color=#ff4444][R закрыть][/color]"
			_:
				return "[color=#888888][R открыть] [ПКМ↑ патрон] [скролл] [R закрыть][/color]"

	## Fix 3rd#7 + Fix 4th#2: Update shotgun hint when shells are loaded.
	func on_tutorial_shell_count_changed(shell_count: int) -> void:
		_shotgun_current_ammo = shell_count
		if _active_hints.has(TUTORIAL_HINT_BOLT_CYCLE):
			_active_hints[TUTORIAL_HINT_BOLT_CYCLE] = _build_tutorial_shotgun_full_reload_hint_bbcode(0)

	## Called when shotgun action state changes (Fix 4th#1).
	func on_tutorial_shotgun_action_state_changed(state: int) -> void:
		if state == 0:
			_dismiss_hint(TUTORIAL_HINT_BOLT_CYCLE)
		elif _active_hints.has(TUTORIAL_HINT_BOLT_CYCLE):
			_active_hints[TUTORIAL_HINT_BOLT_CYCLE] = _build_tutorial_shotgun_pump_hint_bbcode(state)

	## Called when shotgun reload state changes (Fix 4th#2).
	func on_tutorial_shotgun_reload_state_changed(state: int) -> void:
		if not _active_hints.has(TUTORIAL_HINT_BOLT_CYCLE):
			return
		if state >= 2:
			_tutorial_shotgun_reload_started = true
		if state == 0:
			if _tutorial_shotgun_reload_started:
				_active_hints[TUTORIAL_HINT_BOLT_CYCLE] = _build_tutorial_shotgun_full_reload_hint_bbcode(4)
			else:
				_active_hints[TUTORIAL_HINT_BOLT_CYCLE] = _build_tutorial_shotgun_full_reload_hint_bbcode(0)
			return
		_active_hints[TUTORIAL_HINT_BOLT_CYCLE] = _build_tutorial_shotgun_full_reload_hint_bbcode(state)

	## Build BBCode text for the reload hint based on current step (Issue #945).
	## Bug fix #2: `step` is LAST COMPLETED step (0=nothing done, 1=first press done, etc.).
	## Fix 4th#2: Revolver now updates dynamically (handled in on_tutorial_reload_sequence_progress).
	## Fix 4th#2: Shotgun uses separate action/reload state signals.
	func _build_tutorial_reload_hint_bbcode(step: int, total: int) -> String:
		# Guard: shotgun uses ActionStateChanged/ReloadStateChanged instead
		if _tutorial_has_shotgun:
			return ""
		if _tutorial_has_makarov_pm or (not _tutorial_has_sniper_rifle and total <= 2):
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

	## Bug fix: bolt-cycle and hammer-cock hints NOT added here.
	##   Bolt-cycle shown after 1st shot (fix #4), hammer-cock shown from start (fix #3).
	##   Fix 3rd#5: grenade hint NOT added here — shown AFTER reload disappears.
	##   Fix 4th#1: Shotgun shows full reload hint (replacing pump hint) after 2nd shot.
	func _add_tutorial_reload_hints() -> void:
		if _tutorial_has_shotgun:
			# Fix 4th#1: replace pump-action hint with full reload hint after 2nd shot.
			_dismiss_hint(TUTORIAL_HINT_BOLT_CYCLE)
			_add_hint(TUTORIAL_HINT_BOLT_CYCLE, _build_tutorial_shotgun_full_reload_hint_bbcode(0))
		elif _tutorial_has_sniper_rifle:
			# Sniper: magazine swap reload hint only. Bolt-cycle shown after 1st shot.
			_add_hint(TUTORIAL_HINT_RELOAD, _build_tutorial_reload_hint_bbcode(0, 3))
		elif _tutorial_has_revolver:
			# Revolver: cylinder reload hint. Hammer-cock shown from start (fix #3).
			_add_hint(TUTORIAL_HINT_RELOAD,
				"[color=#ff4444][R открыть][/color] [color=#888888][ПКМ↑ патрон] [скролл] [R закрыть][/color]")
		elif _tutorial_has_makarov_pm:
			_add_hint(TUTORIAL_HINT_RELOAD, _build_tutorial_reload_hint_bbcode(0, 2))
		else:
			_add_hint(TUTORIAL_HINT_RELOAD, _build_tutorial_reload_hint_bbcode(0, 3))
		# Fix 3rd#5: grenade hint shown AFTER reload disappears, not simultaneously.

	## Simulate _setup_tutorial_hints(): sets step, shows hammer-cock for revolver (Bug fix #3)
	## and scope hint for sniper rifle (Issue #998).
	func setup_tutorial_hints() -> void:
		_tutorial_step = TutorialStep.RELOAD
		# Bug fix #3: Revolver hammer-cock hint shown immediately on weapon pickup
		if _tutorial_has_revolver:
			_add_hint(TUTORIAL_HINT_HAMMER_COCK, "[color=#ff4444][ПКМ][/color] Взведи курок")
		# Issue #998: Scope hint shown from the very start for sniper rifle
		if _tutorial_has_sniper_rifle:
			_add_hint(TUTORIAL_HINT_SCOPE, "[color=#ff4444][ПКМ][/color] Прицелься через оптику")

	## Simulate _on_tutorial_weapon_fired() (Issue #945).
	## Bug fix #4: bolt-cycle hint (sniper/shotgun) shown after 1st shot.
	func on_tutorial_weapon_fired() -> void:
		_tutorial_shots_fired += 1
		# Bug fix #4: reveal bolt-cycle hint after 1st shot for sniper/shotgun
		if _tutorial_shots_fired >= 1 and not _tutorial_bolt_cycle_hint_revealed:
			if _tutorial_has_sniper_rifle or _tutorial_has_shotgun:
				_tutorial_bolt_cycle_hint_revealed = true
				_reveal_tutorial_bolt_cycle_hint()
		if not _tutorial_reload_hint_revealed and _tutorial_shots_fired >= 2:
			_tutorial_reload_hint_revealed = true
			_reveal_tutorial_reload_hint()

	## Bug fix #4: Reveal bolt-cycle hint after 1st shot.
	## Fix 3rd#4: Sniper uses 4-step sequence. Fix 4th#1: Shotgun uses pump-action hint.
	func _reveal_tutorial_bolt_cycle_hint() -> void:
		if _tutorial_step != TutorialStep.RELOAD:
			return
		if _tutorial_has_sniper_rifle:
			if not _active_hints.has(TUTORIAL_HINT_BOLT_CYCLE):
				# Fix 3rd#4: 4 separate steps, fix 3rd#3: first step in red
				_add_hint(TUTORIAL_HINT_BOLT_CYCLE, _build_tutorial_sniper_bolt_hint_bbcode(0))
		elif _tutorial_has_shotgun:
			if not _active_hints.has(TUTORIAL_HINT_BOLT_CYCLE):
				# Fix 4th#1: pump-action hint after 1st shot (NeedsPumpUp=1)
				_add_hint(TUTORIAL_HINT_BOLT_CYCLE, _build_tutorial_shotgun_pump_hint_bbcode(1))

	func _reveal_tutorial_reload_hint() -> void:
		if _tutorial_step != TutorialStep.RELOAD:
			return
		_add_tutorial_reload_hints()

	## Simulate _on_tutorial_reload_sequence_progress() (Issue #945).
	## Fix 4th#2: Revolver NOW updates hint step-by-step via ReloadSequenceProgress.
	##            Shotgun uses ActionStateChanged/ReloadStateChanged instead.
	## Bug fix #2: `step` is LAST COMPLETED step.
	func on_tutorial_reload_sequence_progress(step: int, total: int) -> void:
		# Fix 4th#2: Revolver updates dynamically via ReloadSequenceProgress
		if _tutorial_has_revolver:
			if _active_hints.has(TUTORIAL_HINT_RELOAD):
				_active_hints[TUTORIAL_HINT_RELOAD] = _build_tutorial_revolver_reload_hint_bbcode(step)
			return
		# Fix 4th#2: shotgun uses ActionStateChanged/ReloadStateChanged — skip
		if _tutorial_has_shotgun:
			return
		if not _active_hints.has(TUTORIAL_HINT_RELOAD):
			return
		var new_text := _build_tutorial_reload_hint_bbcode(step, total)
		if not new_text.is_empty():
			_active_hints[TUTORIAL_HINT_RELOAD] = new_text

	## Simulate _on_tutorial_reload_completed() (Issue #808).
	## Fix 3rd#5: Grenade shown AFTER reload, not simultaneously.
	## Fix 3rd#7: Shotgun bolt-cycle hint dismissed on reload.
	## Fix 3rd#8: Hammer-cock hint NOT dismissed here.
	## Fix 3rd#9: Grenade hint only shown when player has grenades.
	## Fix 3rd#10: AK GL shows underbarrel grenade launcher hint after reload.
	func on_tutorial_reload_completed() -> void:
		if _tutorial_step != TutorialStep.RELOAD:
			return
		if not _tutorial_has_reloaded:
			_tutorial_has_reloaded = true
			_dismiss_hint(TUTORIAL_HINT_RELOAD)
			# Fix 3rd#7: dismiss bolt-cycle hint for shotgun on reload
			if _tutorial_has_shotgun:
				_dismiss_hint(TUTORIAL_HINT_BOLT_CYCLE)
				_tutorial_shotgun_reload_started = false
			if _tutorial_has_revolver:
				_tutorial_revolver_reload_started = false
			# Fix 3rd#8: do NOT dismiss hammer-cock — stays until player manually cocks
			if _tutorial_has_m16:
				_tutorial_m16_needs_fire_mode_hint = true
			# Fix 3rd#10: AK GL shows underbarrel grenade launcher hint after reload
			if _tutorial_has_ak_gl and _ak_gl_has_round:
				_add_hint(TUTORIAL_HINT_GRENADE_LAUNCHER,
					"[color=#ff4444][ПКМ][/color] Выстрели подствольным гранатомётом")
			if _tutorial_has_thrown_grenade:
				_tutorial_step = TutorialStep.COMPLETED
				_dismiss_all_hints()
			else:
				_tutorial_step = TutorialStep.THROW_GRENADE
				# Fix 3rd#9: only show grenade hint if player has grenades
				if _grenade_count > 0:
					if not _active_hints.has(TUTORIAL_HINT_GRENADE):
						_add_hint(TUTORIAL_HINT_GRENADE, _build_tutorial_grenade_hint_bbcode(0))
				else:
					# Fix 3rd#9: no grenades — auto-complete tutorial
					_tutorial_step = TutorialStep.COMPLETED
					_dismiss_all_hints()

	## Simulate _on_tutorial_grenade_thrown() (Issue #808).
	## Fix 3rd#5: Grenade only handled in THROW_GRENADE step; ignore during RELOAD.
	func on_tutorial_grenade_thrown() -> void:
		if _tutorial_step != TutorialStep.THROW_GRENADE:
			return
		if not _tutorial_has_thrown_grenade:
			_tutorial_has_thrown_grenade = true
			_dismiss_hint(TUTORIAL_HINT_GRENADE)
			if _tutorial_m16_needs_fire_mode_hint:
				_add_hint("fire_mode", "[color=#ff4444][B][/color] Переключи режим стрельбы")
				return
			_tutorial_step = TutorialStep.COMPLETED
			_dismiss_all_hints()

	func on_tutorial_fire_mode_changed(new_mode: int) -> void:
		if _tutorial_m16_needs_fire_mode_hint and _active_hints.has("fire_mode") and new_mode != 0:
			_tutorial_m16_needs_fire_mode_hint = false
			_dismiss_hint("fire_mode")
			_tutorial_step = TutorialStep.COMPLETED
			_dismiss_all_hints()

	func on_tutorial_revolver_reload_state_changed(state: int) -> void:
		if not _active_hints.has(TUTORIAL_HINT_RELOAD):
			return
		if state >= 2:
			_tutorial_revolver_reload_started = true
		var hint_step := 0
		match state:
			0:
				hint_step = 3 if _tutorial_revolver_reload_started else 0
			1:
				hint_step = 1
			2:
				hint_step = 2
			_:
				hint_step = 3
		_active_hints[TUTORIAL_HINT_RELOAD] = _build_tutorial_revolver_reload_hint_bbcode(hint_step)

	## Simulate _on_tutorial_sniper_bolt_step_changed() (Issue #808).
	## Fix 3rd#3: Dynamically update bolt-cycle hint text per step.
	## Fix 4th#3: Bolt-cycle completion only dismisses bolt hint — does NOT advance tutorial.
	##            Magazine reload (R→F→R) via on_tutorial_reload_completed advances to THROW_GRENADE.
	func on_tutorial_sniper_bolt_step_changed(step: int, total_steps: int) -> void:
		if _tutorial_step != TutorialStep.RELOAD:
			return
		# Fix 3rd#3: update bolt-cycle hint dynamically
		if _active_hints.has(TUTORIAL_HINT_BOLT_CYCLE):
			_active_hints[TUTORIAL_HINT_BOLT_CYCLE] = _build_tutorial_sniper_bolt_hint_bbcode(step)
		# Fix 4th#3: only dismiss bolt hint when done — do NOT advance tutorial
		if step >= total_steps and not _tutorial_sniper_bolt_cycled:
			_tutorial_sniper_bolt_cycled = true
			_dismiss_hint(TUTORIAL_HINT_BOLT_CYCLE)
			# Reset for next shot — player still needs to do magazine reload
			_tutorial_sniper_bolt_cycled = false

	## Simulate _on_tutorial_hammer_cocked() (Issue #808).
	func on_tutorial_hammer_cocked() -> void:
		_dismiss_hint(TUTORIAL_HINT_HAMMER_COCK)

	## Simulate _on_tutorial_scope_state_changed() (Issue #998).
	## Dismisses scope hint when player uses scope for the first time.
	func on_tutorial_scope_state_changed(is_active: bool) -> void:
		if not is_active or _tutorial_scope_used:
			return
		_tutorial_scope_used = true
		_dismiss_hint(TUTORIAL_HINT_SCOPE)

	func _dismiss_all_hints() -> void:
		_active_hints.clear()
		_active_hint_colors.clear()


var lab: MockLabyrinthTutorial


func before_each() -> void:
	lab = MockLabyrinthTutorial.new()
	lab.setup_tutorial_hints()


func after_each() -> void:
	lab = null


# ============================================================================
# Issue #945: No Hints at Level Start — Reload Hint Delayed Until 2 Shots
# ============================================================================


func test_no_hints_shown_at_level_start() -> void:
	## Issue #945: No hints (reload or grenade) should appear immediately on level load.
	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD),
		"Reload hint must NOT be shown at Lab level start (Issue #945)")
	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_GRENADE),
		"Grenade hint must NOT be shown at Lab level start (Issue #945)")
	assert_false(lab.is_any_hint_active(),
		"No tutorial hints should be visible at Lab level start (Issue #945)")


func test_labyrinth_tutorial_strings_have_translation_keys_for_english_locale() -> void:
	var script := load("res://scripts/levels/labyrinth_level.gd") as GDScript
	assert_not_null(script, "Labyrinth level script should load")

	var source := script.source_code
	assert_string_contains(source, "tr(\"HINT_COCK_HAMMER\")",
		"Labyrinth hammer-cock tutorial text should use a translation key for English locale support")
	assert_string_contains(source, "tr(\"HINT_SCOPE\")",
		"Labyrinth scope tutorial text should use a translation key for English locale support")
	assert_string_not_contains(source, "[color=#ff4444][ПКМ][/color] Взведи курок",
		"Labyrinth hammer-cock tutorial text should not be hardcoded in Russian")
	assert_string_not_contains(source, "[color=#ff4444][ПКМ][/color] Прицелься через оптику",
		"Labyrinth scope tutorial text should not be hardcoded in Russian")


func test_reload_hint_not_shown_after_one_shot() -> void:
	## Issue #945: After only 1 shot, reload hint should still be hidden.
	lab.on_tutorial_weapon_fired()

	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD),
		"Reload hint should NOT appear after only 1 shot (Issue #945)")
	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_GRENADE),
		"Grenade hint should NOT appear after only 1 shot (Issue #945)")


func test_reload_hint_shown_after_two_shots() -> void:
	## Issue #945: After 2 shots, reload hint should appear.
	## Fix 3rd#5: Grenade hint NOT shown simultaneously with reload — appears after reload.
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()

	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD),
		"Reload hint should appear after 2 shots (Issue #945)")
	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_GRENADE),
		"Grenade hint should NOT appear during reload step (Fix 3rd#5 — appears after reload)")


func test_reload_hint_shown_after_more_than_two_shots() -> void:
	## Issue #945: If player fires 3+ shots, reload hint still appears.
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()  # Extra shot after reveal

	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD),
		"Reload hint should remain after more than 2 shots (Issue #945)")


func test_weapon_fired_idempotent_after_reveal() -> void:
	## Issue #945: Additional shots after reveal should not cause duplicate hints.
	## Fix 3rd#5: Only reload hint shown during reload step (grenade appears after reload).
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()  # Extra shots after reveal
	lab.on_tutorial_weapon_fired()

	# Standard weapon: only reload hint shown during RELOAD step (Fix 3rd#5)
	assert_eq(lab.get_active_hint_count(), 1,
		"Only 1 hint (reload) should be active during reload step (Fix 3rd#5)")


# ============================================================================
# Issue #945: Unique Colors per Hint
# ============================================================================


func test_reload_hint_has_green_color() -> void:
	## Issue #945: Reload hint should use green.
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()

	assert_eq(lab.get_hint_color(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD),
		MockLabyrinthTutorial.TUTORIAL_HINT_COLOR_RELOAD,
		"Reload hint should have green color (Issue #945)")


func test_grenade_hint_has_orange_color() -> void:
	## Issue #945: Grenade hint should use orange.
	## Fix 3rd#5: Grenade hint only shown AFTER reload, so must complete reload first.
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_reload_completed()  # Grenade hint appears after reload

	assert_eq(lab.get_hint_color(MockLabyrinthTutorial.TUTORIAL_HINT_GRENADE),
		MockLabyrinthTutorial.TUTORIAL_HINT_COLOR_GRENADE,
		"Grenade hint should have orange color (Issue #945)")


func test_grenade_hint_uses_reviewed_issue_1818_text_on_labyrinth() -> void:
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_reload_completed()

	var hint_text := lab.get_hint_text(MockLabyrinthTutorial.TUTORIAL_HINT_GRENADE)
	assert_true(hint_text.contains("[удерживать G+ПКМ]"),
		"Grenade hint should start with the reviewed hold G+RMB step")
	assert_true(hint_text.contains("[дёрнуть мышкой вправо] [отпустить ПКМ]"),
		"Grenade hint should include the reviewed drag-right and RMB release step")
	assert_true(hint_text.contains("[прицелиться и отпустить ПКМ]"),
		"Grenade hint should end with the reviewed aim-and-release step")


func test_shotgun_reload_hint_rolls_back_when_player_returns_to_idle_without_shells() -> void:
	var shotgun_lab := MockLabyrinthTutorial.new()
	shotgun_lab._tutorial_has_shotgun = true
	shotgun_lab._add_hint(
		MockLabyrinthTutorial.TUTORIAL_HINT_BOLT_CYCLE,
		shotgun_lab._build_tutorial_shotgun_full_reload_hint_bbcode(0)
	)

	shotgun_lab.on_tutorial_shotgun_reload_state_changed(1)
	shotgun_lab.on_tutorial_shotgun_reload_state_changed(0)

	assert_eq(
		shotgun_lab.get_hint_text(MockLabyrinthTutorial.TUTORIAL_HINT_BOLT_CYCLE),
		shotgun_lab._build_tutorial_shotgun_full_reload_hint_bbcode(0),
		"Closing the shotgun without loading shells should restore the initial tutorial step"
	)


func test_revolver_reload_hint_rolls_back_when_cylinder_is_closed_without_loading() -> void:
	var revolver_lab := MockLabyrinthTutorial.new()
	revolver_lab._tutorial_has_revolver = true
	revolver_lab._add_hint(
		MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD,
		revolver_lab._build_tutorial_revolver_reload_hint_bbcode(0)
	)

	revolver_lab.on_tutorial_revolver_reload_state_changed(1)
	revolver_lab.on_tutorial_revolver_reload_state_changed(0)

	assert_eq(
		revolver_lab.get_hint_text(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD),
		revolver_lab._build_tutorial_revolver_reload_hint_bbcode(0),
		"Closing the revolver cylinder without reaching the load phase should reset the tutorial"
	)


func test_m16_fire_mode_hint_stays_incomplete_until_player_leaves_default_mode() -> void:
	var m16_lab := MockLabyrinthTutorial.new()
	m16_lab._tutorial_has_m16 = true
	m16_lab.on_tutorial_weapon_fired()
	m16_lab.on_tutorial_weapon_fired()
	m16_lab.on_tutorial_reload_completed()
	m16_lab.on_tutorial_grenade_thrown()

	assert_true(m16_lab.is_hint_active("fire_mode"),
		"After grenade training the M16 branch should show the fire-mode tutorial")

	m16_lab.on_tutorial_fire_mode_changed(0)
	assert_true(m16_lab.is_hint_active("fire_mode"),
		"Returning to the neutral fire mode must not complete the tutorial")

	m16_lab.on_tutorial_fire_mode_changed(1)
	assert_false(m16_lab.is_hint_active("fire_mode"),
		"Switching away from the default fire mode should complete the M16 tutorial")


func test_bolt_cycle_hint_has_purple_color() -> void:
	## Issue #945: Bolt cycle hint should use purple (sniper).
	## Bug fix #4: Bolt-cycle hint now appears after 1st shot, not 2nd.
	lab._tutorial_has_sniper_rifle = true
	lab.setup_tutorial_hints()  # Reinit with weapon flag set
	lab.on_tutorial_weapon_fired()  # 1st shot triggers bolt-cycle hint

	assert_eq(lab.get_hint_color(MockLabyrinthTutorial.TUTORIAL_HINT_BOLT_CYCLE),
		MockLabyrinthTutorial.TUTORIAL_HINT_COLOR_BOLT_CYCLE,
		"Bolt cycle hint should have purple color (Bug fix #4 — appears after 1st shot)")


func test_hammer_cock_hint_has_yellow_color() -> void:
	## Issue #945: Hammer cock hint should use yellow (revolver).
	## Bug fix #3: Hammer-cock hint now appears from weapon pickup (no shots needed).
	lab._tutorial_has_revolver = true
	lab.setup_tutorial_hints()  # Reinit with weapon flag set — shows hammer_cock immediately

	assert_eq(lab.get_hint_color(MockLabyrinthTutorial.TUTORIAL_HINT_HAMMER_COCK),
		MockLabyrinthTutorial.TUTORIAL_HINT_COLOR_HAMMER_COCK,
		"Hammer cock hint should have yellow color immediately on pickup (Bug fix #3)")


func test_simultaneous_hints_have_different_colors() -> void:
	## Issue #945: Reload and grenade hints use different colors.
	## Fix 3rd#5: Grenade shown AFTER reload, not simultaneously.
	## Test checks colors when grenade hint is shown (after reload step).
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_reload_completed()  # Now grenade hint is visible

	var grenade_color := lab.get_hint_color(MockLabyrinthTutorial.TUTORIAL_HINT_GRENADE)

	# Grenade hint color should be orange (not the same as reload which was green)
	assert_ne(grenade_color, MockLabyrinthTutorial.TUTORIAL_HINT_COLOR_RELOAD,
		"Grenade hint must use a different color from reload hint (Issue #945)")


# ============================================================================
# Issue #945: Red Highlight on NEXT Button in Multi-Step Reload
# ============================================================================


func test_reload_hint_initial_text_has_red_first_step() -> void:
	## Issue #945: Initial reload hint shows first step (R) in red.
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()

	var hint_text: String = lab.get_hint_text(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD)
	assert_true(hint_text.contains("[color=#ff4444]"),
		"Reload hint should contain red colour markup (Issue #945)")
	assert_true(hint_text.begins_with("[color=#ff4444][R]"),
		"First [R] should be highlighted red in initial reload hint (Issue #945)")


func test_reload_sequence_step0_highlights_first_r_red() -> void:
	## Bug fix #2: step=0 means nothing done yet; first [R] should be red.
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_reload_sequence_progress(0, 3)

	var hint_text: String = lab.get_hint_text(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD)
	assert_true(hint_text.begins_with("[color=#ff4444][R]"),
		"Step 0: first [R] should be highlighted red (Bug fix #2)")
	assert_true(hint_text.contains("[color=#888888]"),
		"Step 0: subsequent steps should be greyed (Bug fix #2)")


func test_reload_sequence_step1_highlights_f_red() -> void:
	## Bug fix #2: step=1 means R was pressed; next is F (highlighted red).
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_reload_sequence_progress(1, 3)

	var hint_text: String = lab.get_hint_text(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD)
	assert_true(hint_text.contains("[color=#ff4444][F]"),
		"Step 1: [F] should be highlighted red (Bug fix #2 — R just pressed)")
	assert_true(hint_text.contains("[color=#888888][R][/color]"),
		"Step 1: first [R] should be greyed (just pressed) (Bug fix #2)")


func test_reload_sequence_step2_highlights_final_r_red() -> void:
	## Bug fix #2: step=2 means R+F pressed; next is final R (highlighted red).
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_reload_sequence_progress(2, 3)

	var hint_text: String = lab.get_hint_text(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD)
	assert_true(hint_text.ends_with("[color=#ff4444][R][/color] Перезарядись"),
		"Step 2: final [R] should be highlighted red (Bug fix #2)")


func test_reload_sequence_step3_all_greyed() -> void:
	## Bug fix #2: step=3 means all done; all buttons greyed.
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_reload_sequence_progress(3, 3)

	var hint_text: String = lab.get_hint_text(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD)
	assert_false(hint_text.contains("[color=#ff4444]"),
		"Step 3: no button should be highlighted — all steps done (Bug fix #2)")


func test_makarov_pm_reload_hint_has_two_steps() -> void:
	## Issue #945: Makarov PM uses R -> R reload (2 steps).
	lab._tutorial_has_makarov_pm = true
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()

	var hint_text: String = lab.get_hint_text(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD)
	assert_true(hint_text.contains("[R]") and hint_text.contains("[R]"),
		"Makarov PM hint should show [R] [R] sequence (Issue #945)")
	assert_false(hint_text.contains("[F]"),
		"Makarov PM hint should NOT contain [F] (only R -> R reload) (Issue #945)")


# ============================================================================
# Issue #808: Simultaneous Hints and Independent Dismissal
# ============================================================================


func test_reload_hint_shown_then_grenade_after() -> void:
	## Fix 3rd#5: Reload hint shown first (during reload step); grenade shown AFTER reload.
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()

	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD),
		"Reload hint should be visible during reload step (Fix 3rd#5)")
	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_GRENADE),
		"Grenade hint should NOT be visible during reload step (Fix 3rd#5)")

	lab.on_tutorial_reload_completed()

	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD),
		"Reload hint dismissed after reload (Fix 3rd#5)")
	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_GRENADE),
		"Grenade hint appears AFTER reload (Fix 3rd#5)")


func test_reload_dismissed_grenade_hint_appears() -> void:
	## Fix 3rd#5: Completing reload removes the reload hint and SHOWS grenade hint.
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_reload_completed()

	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD),
		"Reload hint should be gone after reload (Issue #808)")
	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_GRENADE),
		"Grenade hint should appear after reload (Fix 3rd#5)")


func test_grenade_thrown_during_reload_step_is_ignored() -> void:
	## Fix 3rd#5: Grenade thrown during RELOAD step is ignored (hint not shown yet).
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_grenade_thrown()  # Not in THROW_GRENADE step — ignored

	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD),
		"Reload hint should remain (grenade thrown was ignored during RELOAD step — Fix 3rd#5)")
	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_GRENADE),
		"Grenade hint should NOT be shown (Fix 3rd#5 — not in THROW_GRENADE step)")


func test_both_hints_dismissed_after_both_actions() -> void:
	## Issue #808: When both actions complete, all hints disappear.
	## Fix 3rd#5: Reload first, then grenade hint appears (sequential, not simultaneous).
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_reload_completed()  # Grenade hint appears now
	lab.on_tutorial_grenade_thrown()  # Complete — all hints gone

	assert_false(lab.is_any_hint_active(),
		"All hints should be gone after completing both actions (Issue #808)")


func test_sniper_bolt_cycle_hint_shown_after_first_shot() -> void:
	## Bug fix #4: Sniper bolt-cycle hint appears after 1st shot, not 2nd.
	lab._tutorial_has_sniper_rifle = true
	lab.setup_tutorial_hints()

	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_BOLT_CYCLE),
		"Bolt-cycle hint should NOT appear before any shots")

	lab.on_tutorial_weapon_fired()  # 1st shot

	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_BOLT_CYCLE),
		"Bolt-cycle hint should appear after 1st shot (Bug fix #4)")
	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD),
		"Reload hint should NOT appear yet after only 1 shot")


func test_sniper_shows_bolt_cycle_hint() -> void:
	## Issue #808: Sniper rifle shows bolt-cycle hint after 1st shot, reload after 2nd.
	## Fix 3rd#5: Grenade NOT shown during reload step.
	lab._tutorial_has_sniper_rifle = true
	lab.setup_tutorial_hints()
	lab.on_tutorial_weapon_fired()  # 1st shot → bolt-cycle hint
	lab.on_tutorial_weapon_fired()  # 2nd shot → reload hint

	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD),
		"Sniper: reload hint should be visible after 2nd shot (Issue #808)")
	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_BOLT_CYCLE),
		"Sniper: bolt-cycle hint should be visible (Bug fix #4)")
	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_GRENADE),
		"Sniper: grenade hint NOT shown during reload step (Fix 3rd#5)")


func test_revolver_shows_hammer_cock_hint_from_start() -> void:
	## Bug fix #3: Revolver hammer-cock hint appears immediately on weapon pickup.
	lab._tutorial_has_revolver = true
	lab.setup_tutorial_hints()  # Reinit with revolver flag set

	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_HAMMER_COCK),
		"Revolver: hammer-cock hint should appear immediately on pickup (Bug fix #3)")
	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD),
		"Revolver: reload hint should NOT appear yet (needs 2 shots)")


func test_revolver_shows_hammer_cock_hint() -> void:
	## Issue #808: Revolver shows hammer-cock hint alongside reload hint after 2 shots.
	## Fix 3rd#5: Grenade hint NOT shown during reload step.
	lab._tutorial_has_revolver = true
	lab.setup_tutorial_hints()
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()

	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD),
		"Revolver: reload hint should be visible (Issue #808)")
	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_HAMMER_COCK),
		"Revolver: hammer-cock hint should be visible (Bug fix #3 — shown from start)")
	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_GRENADE),
		"Revolver: grenade hint NOT shown during reload step (Fix 3rd#5)")


func test_revolver_reload_hint_updates_with_sequence_progress() -> void:
	## Fix 4th#2: Revolver reload hint NOW updates step-by-step via ReloadSequenceProgress.
	lab._tutorial_has_revolver = true
	lab.setup_tutorial_hints()
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()

	var initial_hint_text: String = lab.get_hint_text(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD)
	assert_true(initial_hint_text.contains("[R открыть]"),
		"Revolver initial reload hint shows [R открыть] as first step (Fix 4th#2)")

	# Simulate reload progress step 1 — should update hint
	lab.on_tutorial_reload_sequence_progress(1, 3)

	var updated_hint_text: String = lab.get_hint_text(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD)
	assert_ne(updated_hint_text, initial_hint_text,
		"Revolver reload hint SHOULD update via ReloadSequenceProgress (Fix 4th#2)")
	assert_true(updated_hint_text.contains("[ПКМ↑ патрон]"),
		"After step 1, [ПКМ↑ патрон] should be highlighted next (Fix 4th#2)")


func test_hammer_cocked_dismisses_only_hammer_hint() -> void:
	## Issue #808: Cocking the revolver hammer removes only the hammer hint.
	## Fix 3rd#8: Hammer-cock hint stays after reload; dismissed only by HammerCocked.
	lab._tutorial_has_revolver = true
	lab.setup_tutorial_hints()  # reinit with revolver flag → shows hammer_cock immediately
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_hammer_cocked()

	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_HAMMER_COCK),
		"Hammer-cock hint should be dismissed after cocking (Issue #808)")
	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD),
		"Reload hint should remain after cocking the hammer (Issue #808)")
	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_GRENADE),
		"Grenade hint NOT shown during reload step (Fix 3rd#5)")


func test_sniper_bolt_completion_dismisses_only_bolt_hint() -> void:
	## Fix 4th#3: Completing bolt-action cycle removes ONLY bolt hint.
	## Reload hint STAYS — player must complete magazine reload to advance.
	## Grenade shown only AFTER magazine reload completes.
	lab._tutorial_has_sniper_rifle = true
	lab.setup_tutorial_hints()  # reinit with sniper flag
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()

	# During reload step — no grenade
	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_GRENADE),
		"Grenade hint should NOT appear during reload step (Fix 3rd#5)")

	lab.on_tutorial_sniper_bolt_step_changed(4, 4)  # Bolt fully cycled

	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_BOLT_CYCLE),
		"Bolt-cycle hint should be gone after bolt-cycle completion (Fix 4th#3)")
	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD),
		"Reload hint [R][F][R] STAYS after bolt cycle — player must do magazine reload (Fix 4th#3)")
	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_GRENADE),
		"Grenade hint NOT shown yet — need magazine reload first (Fix 4th#3)")
	assert_eq(lab.get_step(), MockLabyrinthTutorial.TutorialStep.RELOAD,
		"Still in RELOAD step after bolt cycle (Fix 4th#3)")

	# Magazine reload advances to THROW_GRENADE and shows grenade hint
	lab.on_tutorial_reload_completed()

	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD),
		"Reload hint dismissed after magazine reload (Fix 4th#3)")
	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_GRENADE),
		"Grenade hint appears after magazine reload (Fix 3rd#5, Fix 4th#3)")
	assert_eq(lab.get_step(), MockLabyrinthTutorial.TutorialStep.THROW_GRENADE,
		"Advanced to THROW_GRENADE after magazine reload (Fix 4th#3)")


func test_grenade_thrown_before_reload_stays_in_reload_step() -> void:
	## Fix 3rd#5: Throwing grenade during RELOAD step is ignored (hint not active, not in THROW_GRENADE step).
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_grenade_thrown()  # Ignored — not in THROW_GRENADE step

	assert_eq(lab.get_step(), MockLabyrinthTutorial.TutorialStep.RELOAD,
		"Should remain in RELOAD step after throwing grenade early (Fix 3rd#5)")
	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD),
		"Reload hint should still be visible (Fix 3rd#5)")


func test_shotgun_bolt_cycle_hint_after_first_shot() -> void:
	## Bug fix #4: Shotgun bolt-cycle hint appears after 1st shot.
	## Bug fix: Shotgun uses HINT_BOLT_CYCLE (not HINT_RELOAD) for its reload instruction.
	lab._tutorial_has_shotgun = true
	lab.setup_tutorial_hints()

	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_BOLT_CYCLE),
		"Shotgun bolt-cycle hint should NOT appear before any shots")

	lab.on_tutorial_weapon_fired()  # 1st shot

	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_BOLT_CYCLE),
		"Shotgun bolt-cycle hint should appear after 1st shot (Bug fix #4)")
	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD),
		"Shotgun does not use separate RELOAD hint — it uses bolt-cycle hint")


func test_shotgun_bolt_cycle_hint_uses_bbcode_red_pump() -> void:
	## Issue #945 + Fix 4th#1: Shotgun bolt-cycle hint uses BBCode with red highlight.
	## After 1st shot shows pump-action hint [ПКМ↑][ПКМ↓] Передёрни затвор (Fix 4th#1).
	lab._tutorial_has_shotgun = true
	lab.setup_tutorial_hints()
	lab.on_tutorial_weapon_fired()  # 1st shot reveals bolt-cycle hint (pump hint)

	var hint_text: String = lab.get_hint_text(MockLabyrinthTutorial.TUTORIAL_HINT_BOLT_CYCLE)
	assert_true(hint_text.contains("[color=#ff4444]"),
		"Shotgun bolt-cycle hint should highlight first action in red (Issue #945)")
	assert_true(hint_text.contains("ПКМ↑"),
		"Pump hint should contain [ПКМ↑] (Fix 4th#1)")
	assert_false(hint_text.contains("открыть"),
		"Pump hint should NOT contain 'открыть' — full reload appears only after 2nd shot (Fix 4th#1)")


# ============================================================================
# Third Review Round Bug Fix Tests
# ============================================================================


func test_hint_spacing_is_60() -> void:
	## Fix 3rd#1: TUTORIAL_HINT_SPACING should be 60 to prevent overlap.
	assert_eq(MockLabyrinthTutorial.TUTORIAL_HINT_SPACING, 60.0,
		"TUTORIAL_HINT_SPACING should be 60px (Fix 3rd#1)")


func test_shotgun_bolt_cycle_hint_shows_pump_action_after_first_shot() -> void:
	## Fix 4th#1: After 1st shot, shotgun shows pump-action hint [ПКМ↑][ПКМ↓].
	## Full reload hint with shell count only shown after 2nd shot.
	lab._tutorial_has_shotgun = true
	lab._shotgun_capacity = 8
	lab._shotgun_current_ammo = 2  # 2 shells loaded, still has ammo
	lab.setup_tutorial_hints()

	lab.on_tutorial_weapon_fired()  # 1st shot → pump-action hint

	var hint_text: String = lab.get_hint_text(MockLabyrinthTutorial.TUTORIAL_HINT_BOLT_CYCLE)
	assert_true(hint_text.contains("ПКМ↑"),
		"After 1st shot, shotgun shows pump-action hint with [ПКМ↑] (Fix 4th#1)")
	assert_true(hint_text.contains("Передёрни затвор"),
		"Pump-action hint text says 'Передёрни затвор' (Fix 4th#1)")
	assert_false(hint_text.contains("открыть"),
		"Pump hint does NOT show full reload sequence after 1st shot (Fix 4th#1)")


func test_shotgun_reload_count_updates_on_shell_loaded() -> void:
	## Fix 3rd#7: Shell count updates live as each shell is loaded.
	lab._tutorial_has_shotgun = true
	lab._shotgun_capacity = 8
	lab._shotgun_current_ammo = 0
	lab.setup_tutorial_hints()
	lab.on_tutorial_weapon_fired()  # Reveals bolt-cycle hint

	# Load 3 shells
	lab.on_tutorial_shell_count_changed(3)

	var hint_text: String = lab.get_hint_text(MockLabyrinthTutorial.TUTORIAL_HINT_BOLT_CYCLE)
	assert_true(hint_text.contains("x5"),
		"Shotgun reload count updates to x5 after loading 3 shells (8-3=5, Fix 3rd#7)")


func test_sniper_bolt_hint_shows_4_steps() -> void:
	## Fix 3rd#4: Sniper bolt-cycle hint shows 4 separate steps [←][↓][↑][→].
	lab._tutorial_has_sniper_rifle = true
	lab.setup_tutorial_hints()
	lab.on_tutorial_weapon_fired()  # Reveals bolt-cycle hint

	var hint_text: String = lab.get_hint_text(MockLabyrinthTutorial.TUTORIAL_HINT_BOLT_CYCLE)
	assert_true(hint_text.contains("[←]"), "Hint shows [←] step (Fix 3rd#4)")
	assert_true(hint_text.contains("[↓]"), "Hint shows [↓] step (Fix 3rd#4)")
	assert_true(hint_text.contains("[↑]"), "Hint shows [↑] step (Fix 3rd#4)")
	assert_true(hint_text.contains("[→]"), "Hint shows [→] step (Fix 3rd#4)")


func test_sniper_bolt_hint_first_step_in_red() -> void:
	## Fix 3rd#3: First step [←] should be highlighted red initially.
	lab._tutorial_has_sniper_rifle = true
	lab.setup_tutorial_hints()
	lab.on_tutorial_weapon_fired()  # Reveals bolt-cycle hint at step=0

	var hint_text: String = lab.get_hint_text(MockLabyrinthTutorial.TUTORIAL_HINT_BOLT_CYCLE)
	assert_true(hint_text.contains("#ff4444][←]"),
		"First step [←] is red at step=0 (Fix 3rd#3)")
	assert_true(hint_text.contains("#888888][↓]"),
		"Second step [↓] is grey at step=0 (Fix 3rd#3)")


func test_sniper_bolt_hint_updates_per_step() -> void:
	## Fix 3rd#3: Bolt-cycle hint text updates to show current step in red.
	lab._tutorial_has_sniper_rifle = true
	lab.setup_tutorial_hints()
	lab.on_tutorial_weapon_fired()  # Step 0: [←] in red
	lab.on_tutorial_weapon_fired()  # 2nd shot reveals reload hint too

	# Advance bolt to step 2
	lab.on_tutorial_sniper_bolt_step_changed(2, 4)

	var hint_text: String = lab.get_hint_text(MockLabyrinthTutorial.TUTORIAL_HINT_BOLT_CYCLE)
	assert_true(hint_text.contains("#888888][←]"),
		"[←] is grey after step 2 (Fix 3rd#3)")
	assert_true(hint_text.contains("#888888][↓]"),
		"[↓] is grey after step 2 (Fix 3rd#3)")
	assert_true(hint_text.contains("#ff4444][↑]"),
		"[↑] is red at step 2 (Fix 3rd#3)")


func test_grenade_hint_appears_after_reload_not_simultaneously() -> void:
	## Fix 3rd#5: Grenade hint must appear AFTER reload disappears, not during.
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()

	# During reload — no grenade hint
	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD))
	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_GRENADE),
		"Grenade hint must NOT appear during reload (Fix 3rd#5)")

	# After reload — grenade hint appears
	lab.on_tutorial_reload_completed()

	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD))
	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_GRENADE),
		"Grenade hint appears AFTER reload (Fix 3rd#5)")


func test_shotgun_reload_hint_dismissed_after_reload() -> void:
	## Fix 3rd#7: Shotgun bolt-cycle hint is dismissed when reload completes.
	lab._tutorial_has_shotgun = true
	lab._shotgun_capacity = 8
	lab._shotgun_current_ammo = 0
	lab.setup_tutorial_hints()
	lab.on_tutorial_weapon_fired()  # Reveals bolt-cycle hint

	lab.on_tutorial_reload_completed()

	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_BOLT_CYCLE),
		"Shotgun bolt-cycle hint dismissed after reload (Fix 3rd#7)")


func test_revolver_hammer_cock_hint_stays_after_reload() -> void:
	## Fix 3rd#8: Hammer-cock hint must NOT be dismissed on reload.
	lab._tutorial_has_revolver = true
	lab.setup_tutorial_hints()
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()

	lab.on_tutorial_reload_completed()

	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_HAMMER_COCK),
		"Hammer cock hint must stay after reload (Fix 3rd#8)")


func test_revolver_hammer_cock_hint_stays_until_manual_cock() -> void:
	## Fix 3rd#8: Revolver hammer-cock hint stays after reload; dismissed only by HammerCocked signal.
	lab._tutorial_has_revolver = true
	lab.setup_tutorial_hints()
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()

	lab.on_tutorial_reload_completed()

	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_HAMMER_COCK),
		"Hammer-cock hint stays after reload (Fix 3rd#8)")

	# Manual cock dismisses it
	lab.on_tutorial_hammer_cocked()

	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_HAMMER_COCK),
		"Hammer-cock hint dismissed after manual cock (Fix 3rd#8)")


func test_grenade_hint_not_shown_without_grenades() -> void:
	## Fix 3rd#9: Grenade hint should NOT appear if player has no grenades.
	lab._grenade_count = 0
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()

	lab.on_tutorial_reload_completed()

	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_GRENADE),
		"Grenade hint NOT shown when player has no grenades (Fix 3rd#9)")
	assert_eq(lab.get_step(), MockLabyrinthTutorial.TutorialStep.COMPLETED,
		"Tutorial auto-completes when no grenades available (Fix 3rd#9)")


func test_grenade_hint_shown_when_has_grenades() -> void:
	## Fix 3rd#9: Grenade hint IS shown when player has at least 1 grenade.
	lab._grenade_count = 3
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()

	lab.on_tutorial_reload_completed()

	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_GRENADE),
		"Grenade hint shown when player has grenades (Fix 3rd#9)")


func test_ak_gl_shows_grenade_launcher_hint_after_reload() -> void:
	## Fix 3rd#10: AK GL shows underbarrel grenade launcher hint after reload.
	lab._tutorial_has_ak_gl = true
	lab._ak_gl_has_round = true
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()  # Triggers reload hint reveal

	lab.on_tutorial_reload_completed()

	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_GRENADE_LAUNCHER),
		"AK GL shows underbarrel grenade launcher hint after reload (Fix 3rd#10)")


func test_ak_gl_no_grenade_launcher_hint_when_no_round() -> void:
	## Fix 3rd#10: AK GL should NOT show launcher hint if no round is loaded.
	lab._tutorial_has_ak_gl = true
	lab._ak_gl_has_round = false
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()

	lab.on_tutorial_reload_completed()

	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_GRENADE_LAUNCHER),
		"AK GL does NOT show launcher hint when no round loaded (Fix 3rd#10)")


func test_grenade_launcher_hint_has_correct_color() -> void:
	## Fix 3rd#10: AK GL grenade launcher hint should use the dedicated orange-red color.
	lab._tutorial_has_ak_gl = true
	lab._ak_gl_has_round = true
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_reload_completed()

	assert_eq(lab.get_hint_color(MockLabyrinthTutorial.TUTORIAL_HINT_GRENADE_LAUNCHER),
		MockLabyrinthTutorial.TUTORIAL_HINT_COLOR_GRENADE_LAUNCHER,
		"AK GL grenade launcher hint should use orange-red color (Fix 3rd#10)")


# ============================================================================
# Issue #998: Scope RMB hint shown from the very start for sniper rifle (Lab level)
# ============================================================================


func test_lab_sniper_scope_hint_shown_from_start() -> void:
	## Issue #998: Scope hint appears immediately when sniper rifle is equipped on Lab level.
	var sniper_lab := MockLabyrinthTutorial.new()
	sniper_lab._tutorial_has_sniper_rifle = true
	sniper_lab.setup_tutorial_hints()

	assert_true(sniper_lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_SCOPE),
		"Scope RMB hint must appear from the very start for sniper rifle on Lab level (Issue #998)")
	assert_eq(sniper_lab.get_step(), MockLabyrinthTutorial.TutorialStep.RELOAD,
		"Tutorial starts at RELOAD step with scope hint visible (Issue #998)")


func test_lab_no_scope_hint_without_sniper() -> void:
	## Issue #998: Scope hint must NOT appear for non-sniper weapons.
	## Default setup_tutorial_hints() is called in before_each with no sniper.
	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_SCOPE),
		"Scope hint must NOT appear without sniper rifle (Issue #998)")


func test_lab_sniper_scope_hint_dismissed_when_scope_used() -> void:
	## Issue #998: Scope hint is dismissed when player activates scope.
	var sniper_lab := MockLabyrinthTutorial.new()
	sniper_lab._tutorial_has_sniper_rifle = true
	sniper_lab.setup_tutorial_hints()

	assert_true(sniper_lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_SCOPE),
		"Scope hint visible from start (Issue #998)")

	sniper_lab.on_tutorial_scope_state_changed(true)

	assert_false(sniper_lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_SCOPE),
		"Scope hint dismissed after player uses scope (Issue #998)")


func test_lab_sniper_scope_hint_not_dismissed_on_scope_deactivate() -> void:
	## Issue #998: Scope hint should only be dismissed when scope is ACTIVATED (not deactivated).
	var sniper_lab := MockLabyrinthTutorial.new()
	sniper_lab._tutorial_has_sniper_rifle = true
	sniper_lab.setup_tutorial_hints()

	sniper_lab.on_tutorial_scope_state_changed(false)  # Deactivate (should not dismiss hint)

	assert_true(sniper_lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_SCOPE),
		"Scope hint stays when scope is deactivated (only dismissed on activation, Issue #998)")


func test_lab_sniper_scope_hint_dismissed_only_once() -> void:
	## Issue #998: Scope hint dismissed only once; second activation does not cause issues.
	var sniper_lab := MockLabyrinthTutorial.new()
	sniper_lab._tutorial_has_sniper_rifle = true
	sniper_lab.setup_tutorial_hints()

	sniper_lab.on_tutorial_scope_state_changed(true)   # First use — dismisses hint
	sniper_lab.on_tutorial_scope_state_changed(false)
	sniper_lab.on_tutorial_scope_state_changed(true)   # Second use — hint already gone

	assert_false(sniper_lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_SCOPE),
		"Scope hint stays dismissed after multiple scope uses (Issue #998)")
	assert_true(sniper_lab._tutorial_scope_used,
		"Scope used flag persists after first use (Issue #998)")


func test_lab_sniper_scope_hint_color_is_cyan() -> void:
	## Issue #998: Scope hint uses cyan color on Lab level.
	var sniper_lab := MockLabyrinthTutorial.new()
	sniper_lab._tutorial_has_sniper_rifle = true
	sniper_lab.setup_tutorial_hints()

	assert_eq(sniper_lab.get_hint_color(MockLabyrinthTutorial.TUTORIAL_HINT_SCOPE),
		MockLabyrinthTutorial.TUTORIAL_HINT_COLOR_SCOPE,
		"Scope hint should use cyan color on Lab level (Issue #998)")


func test_lab_sniper_scope_hint_coexists_with_reload_hint() -> void:
	## Issue #998: Scope hint shown alongside reload hint after 2 shots.
	var sniper_lab := MockLabyrinthTutorial.new()
	sniper_lab._tutorial_has_sniper_rifle = true
	sniper_lab.setup_tutorial_hints()
	sniper_lab.on_tutorial_weapon_fired()
	sniper_lab.on_tutorial_weapon_fired()  # Triggers reload hint

	assert_true(sniper_lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_SCOPE),
		"Scope hint still visible after 2 shots if not used yet (Issue #998)")
	assert_true(sniper_lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD),
		"Reload hint also visible after 2 shots (Issue #998)")
