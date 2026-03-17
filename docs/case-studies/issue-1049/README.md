# Case Study: Issue #1049 — Remove bottom progress bar from Trajectory Glasses

## Issue Description

**Title:** убрать нижний прогрессбар с Очков траектории
*(Remove the bottom progress bar from Trajectory Glasses)*

**URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1049
**PR:** https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1055

**Requirements (translated from Russian):**
1. Remove the bottom progress bar that shows remaining active time for the Trajectory Glasses item.
2. Instead: when little active time remains, the trajectory ray should blink (same as the force field's behavior).
3. The count-of-charges HUD should appear only for 400 ms after activation, then auto-hide.
4. Write in the README that it is preferable not to show an extra progress bar if possible.

---

## Timeline / Sequence of Events

| Time (UTC) | Event |
|---|---|
| 2026-03-16T20:19 | Branch `issue-1049-fcac47548b87` created; initial commit |
| 2026-03-16T20:24 | First feature commit: add ray blinking (flash logic, skip draw) |
| 2026-03-16T21:48 | Owner reviews PR — reports bottom bar still visible + charge bar should hide after 400ms |
| 2026-03-16T21:53 | Second fix commit: remove `_show_active_item_combined_bar`, add HUD auto-hide |
| 2026-03-16T21:55 | AI session declares "Ready to merge" |
| 2026-03-16T23:51 | Owner reviews again from the **upstream repo build** (not our branch) — still reports issues |
| 2026-03-17T00:49 | Game log `game_log_20260317_024849.txt` captured (still pre-fix build) |
| 2026-03-17 | Branch merged with `origin/main` (Issue #1080, #1052, #1034 changes included) |

---

## Root Cause Analysis

### 1. Bottom progress bar still visible

**Root cause — two sources of progress bars for Trajectory Glasses:**

**Source A — `ActiveItemProgressBar` (via `_show_active_item_combined_bar`):**
- `player.gd::_on_trajectory_activated()` called `_show_active_item_combined_bar(...)` which created a floating combined bar (charge pips + timer bar) at `BAR_Y_OFFSET = -30px` above the player.
- This was added in Issue #974 to show active item status consistently.

**Source B — `trajectory_glasses_hud.gd` own timer bar:**
- The `trajectory_glasses_hud.gd` `_draw()` method drew its own timer bar (green progress bar) inside the HUD node, positioned at `TIMER_BAR_OFFSET_Y = 8px` below the charge pips.
- The HUD polled `_effect.is_active` every frame to stay visible for the entire 10-second duration.

Both bars were visible simultaneously, creating confusion. The screenshot from the owner's review showed the combined bar (charge pips + orange timer bar) — this was Source B from `trajectory_glasses_hud.gd`.

**Why did the owner see the bug AFTER our commit:**
The game log (`game_log_20260317_024849.txt`) contains the log entry `[Player.InvisibilitySuit] Charge bar created` which does not exist in our branch's code. This proves the owner was testing a build from the **original upstream repo main branch** (Jhon-Crow/godot-topdown-MVP), not from our PR branch. Our PR had not been merged at the time of testing.

### 2. Ray not blinking when time is low

**Root cause:**
The `trajectory_glasses_effect.gd` had no flash/blink logic at all. The `trajectory_ray_visible` flag did not exist. The `_draw_trajectory_glasses()` in `player.gd` always drew the ray while `is_active` was true with no check for remaining time.

### 3. Charge pips showing for entire 10-second duration

**Root cause:**
`trajectory_glasses_hud.gd::_process()` polled `_effect.is_active` and kept `visible = true` for the full 10 seconds. There was no auto-hide timer.

---

## Fix Implementation

### `scripts/effects/trajectory_glasses_effect.gd`
- Added constants `LOW_TIME_WARNING = 2.0` (seconds) and `WARNING_FLASH_FREQUENCY = 3.0` (Hz).
- Added `trajectory_ray_visible: bool` and `_warning_flash_timer: float`.
- In `_process()`: when `_effect_timer <= LOW_TIME_WARNING`, drive blink state using modular arithmetic matching the force field pattern.
- `deactivate()` resets `trajectory_ray_visible = true` and `_warning_flash_timer = 0.0`.

### `scripts/ui/trajectory_glasses_hud.gd`
- Removed all timer bar constants (`TIMER_BAR_WIDTH`, `TIMER_BAR_HEIGHT`, etc.) and the timer bar drawing code from `_draw()`.
- Removed the `_process()` polling of `_effect.is_active`.
- Added `ACTIVATION_SHOW_DURATION = 0.4` (seconds) and `_hide_timer`.
- `set_active(true)` starts a 400ms countdown; `set_active(false)` hides immediately.
- `_process()` counts down `_hide_timer` and hides when it reaches zero.

### `scripts/characters/player.gd`
- `_draw_trajectory_glasses()`: added early return when `trajectory_ray_visible == false`.
- `_on_trajectory_activated()`: removed `_show_active_item_combined_bar(...)` call; only calls `_trajectory_glasses_hud.set_active(true)`.
- `_on_trajectory_deactivated()`: removed `_show_active_item_charge_bar(...)` and charge bar hide timer logic; only calls `_trajectory_glasses_hud.set_active(false)`.
- `_update_charge_bar_timer()`: removed trajectory glasses timer update block; simplified `any_active` check to homing bullets only.

### `README_RU.md`
- Added guideline rule 5: prefer using the item's own visual element (e.g. blinking) instead of an extra progress bar when possible.

---

## Behaviour After Fix

| Remaining time | Ray behaviour |
|---|---|
| > 2 s | Solid, always visible |
| ≤ 2 s | Blinks at 3 Hz (same pattern as force field warning) |
| 0 s (expired) | Ray disappears (deactivated) |

| Event | Charge pip HUD |
|---|---|
| Activation | Shown for 400 ms, then auto-hides |
| Deactivation | Hidden immediately |

---

## Files in This Case Study

- `README.md` — This analysis
- `issue-details.json` — Full GitHub issue JSON (title, body, comments)
- `game_log_20260317_024849.txt` — Game log provided by owner showing pre-fix behavior (captured from upstream main, not from our PR branch)
- `screenshot_pr_review_20260316.png` — Screenshot from owner's PR review showing the bottom progress bar issue

---

## References

- Issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1049
- PR: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1055
- Related Issue #744: Original trajectory glasses implementation
- Related Issue #974: Combined progress bar for active items (added the unwanted timer bar)
- Related Issue #676: Force field blinking pattern that was used as reference
- Force Field effect (`scripts/effects/force_field_effect.gd`): reference for the blink pattern
