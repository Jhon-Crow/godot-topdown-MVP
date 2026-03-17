# Case Study: Issue #1097 — Fix weapon training on first use

## Problem Statement

Weapon hints in **FIRST_TIME_ONLY** mode did not function correctly:

1. The default hint display mode was `FIRST_TIME_ONLY`, but the issue requires the default to be `ALWAYS`.
2. If a player died or restarted before completing a weapon's training, hints would **not** reappear on the next attempt — meaning the player could never complete the training.

## Root Cause Analysis

### Bug 1 — Wrong default mode

`weapon_hints_settings.gd` had:
```gdscript
var hint_mode: HintMode = HintMode.FIRST_TIME_ONLY
```
Both the in-memory default and the `_load_settings()` fallback used `FIRST_TIME_ONLY`.

The same incorrect default was mirrored in `gameplay_menu.gd`:
```gdscript
weapon_hints_option.select(1)  # First time only
```

### Bug 2 — Training marked complete immediately on start

In `weapon_hints_component.gd`, `_try_start_hints()` called `mark_weapon_seen()` as soon as the hint sequence **started**:

```gdscript
func _try_start_hints(weapon_id: String) -> void:
    ...
    if settings == null or settings.should_show_hints(weapon_id):
        _start_hint_sequence(weapon_id)
        if settings:
            settings.mark_weapon_seen(weapon_id)  # <-- wrong: called at start, not completion
```

This meant:
- Player enters level → hints appear → weapon **immediately marked as seen**
- Player dies/restarts before performing the training actions
- On next level entry, `should_show_hints()` returns `false` — hints never shown again
- Player is permanently locked out of training for that weapon

## Solution

### Fix 1 — Change default to ALWAYS

Changed all three default locations to `HintMode.ALWAYS`:
- `weapon_hints_settings.gd` line 25: `var hint_mode: HintMode = HintMode.ALWAYS`
- `weapon_hints_settings.gd` `_load_settings()`: default fallback = `ALWAYS`
- `gameplay_menu.gd` `_setup_weapon_hints_option()`: fallback `select(0)` (Always)

### Fix 2 — Mark weapon seen only on training completion

Added a flag `_last_dismiss_was_player_action: bool` to `weapon_hints_component.gd`:

- Set to `true` **only** in player-action dismiss handlers: `_on_hammer_cocked()`, `_on_scope_state_changed()`, `_on_fire_mode_changed()`, `_on_grenade_launcher_fired()`, `_on_reload_completed()`, `_on_sniper_bolt_step_changed()`, `_on_shotgun_action_state_changed()`.
- Remains `false` when hints are dismissed by auto-dismiss timer (`_on_dismiss_timer_timeout`) or by weapon switch (`_dismiss_hints_immediate`).
- Removed `mark_weapon_seen()` from `_try_start_hints()`.
- Added `mark_weapon_seen()` call in `_finalize_hint_dismiss()` when the **last** hint is dismissed **and** `_last_dismiss_was_player_action` is `true`.

```gdscript
if _hint_labels.is_empty() and _animating_hints.is_empty():
    _hints_showing = false
    _hints_active = false
    _dismiss_timer.stop()
    if _last_dismiss_was_player_action and not _current_weapon_id.is_empty():
        var settings: Node = get_node_or_null("/root/WeaponHintsSettings")
        if settings:
            settings.mark_weapon_seen(_current_weapon_id)
```

## Behavior After Fix

| Scenario | Before fix | After fix |
|---|---|---|
| New player, no save file | Hints shown once (FIRST_TIME_ONLY) | Hints shown always (ALWAYS default) |
| FIRST_TIME_ONLY: player dies before completing training | Hints never shown again | Hints shown again on next attempt |
| FIRST_TIME_ONLY: player completes all training actions | Hints shown again next time (bug) | Weapon marked seen, hints not shown again |
| Auto-dismiss timer fires before player acts | Weapon marked seen (bug) | Weapon NOT marked seen, hints reappear |

## Files Changed

- `scripts/autoload/weapon_hints_settings.gd` — default mode changed to ALWAYS
- `scripts/components/weapon_hints_component.gd` — `mark_weapon_seen()` moved to training completion
- `scripts/ui/gameplay_menu.gd` — UI default fallback changed to ALWAYS
