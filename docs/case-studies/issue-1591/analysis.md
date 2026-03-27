# Case Study: Issue #1591 — Armory Progress Display for Quantitative Unlock Tasks

## Summary

**Issue:** If weapons/items require quantitative tasks to unlock, display progress (card fill animation with sound) every time the armory is opened.

**Language:** Russian original — "если для открытия оружия нужны количественные задачи - отображай прогресс (заполнение карточки с анимацией) при каждом заходе (со звуком увеличения, похожим на звук на экране счёта)"

**Translation:** "If opening a weapon requires quantitative tasks — display progress (card fill animation) every time you enter (with a rising sound similar to the score screen sound)"

## Existing Code Analysis

### Unlock System

The game has four types of unlock conditions (`unlock_manager.gd`):
1. **Level rank conditions** (`UNLOCK_CONDITIONS`) — complete a level at a minimum rank
2. **Multi-level conditions** (`MULTI_UNLOCK_CONDITIONS`) — complete multiple levels at required ranks
3. **Kill/stat-based conditions** (`KILL_UNLOCK_CONDITIONS`) — quantitative: accumulate a stat (kills, shots, deaths, no-damage runs)
4. **All-difficulties condition** (`ALL_DIFFICULTIES_UNLOCK_CONDITIONS`) — complete at least one level on every difficulty

### Quantitative (Kill-based) Conditions

These are the "quantitative tasks" the issue refers to:
- `kills_without_laser_sight`: 1000 kills → Laser Sight (active item type 9)
- `shots_fired_special_weapons`: 650 shots → Fine Motor Skills (active item type 19)
- `total_deaths`: 100 deaths → Armored Skin (active item type 13)
- `no_damage_levels_completed`: 1 no-damage completion → Combat Disposition (active item type 17)

### Armory Menu (armory_menu.gd)

The armory already has:
- `_slot_progress_overlays` (Dictionary) — tracks unlock-hold progress overlays per slot
- `_create_progress_overlay()` — creates a ColorRect at the bottom of a slot
- `_update_progress_overlay()` — updates overlay height proportional to progress
- `_remove_progress_overlay()` — removes overlay
- `_play_beep()` — plays a sine wave beep at given frequency
- `_play_progress_beep(progress)` — plays a rising-pitch beep
- `_play_unlock_success_sound()` — ascending arpeggio on unlock

The armory currently **only** uses the progress overlay for LMB-hold unlock tracking (real-time hold feedback). There is no startup animation that shows quantitative task progress.

### Score Screen (animated_score_screen.gd)

Has a well-implemented count-up animation with:
- `_play_beep(frequency, duration, volume_db)` — same beep mechanism
- Count-up animation that plays beeps at ~10% intervals
- Final "landing" beep at completion

## Implementation Plan

### Step 1: Add progress query methods to UnlockManager

Add methods that return progress ratio (0.0–1.0) for kill-based conditions for a given item:
- `get_weapon_kill_condition_progress(weapon_id) -> float`
- `get_grenade_kill_condition_progress(grenade_type) -> float`
- `get_active_item_kill_condition_progress(item_type) -> float`

Each returns `clamp(current_stat / min_kills, 0.0, 1.0)` if a kill condition applies; otherwise `-1.0` (no quantitative condition).

### Step 2: Add startup progress animation to ArmoryMenu

In `_build_right_area()` or after slots are built, for each locked slot with a quantitative condition:
1. Show a progress bar (ColorRect) that fills from 0 to the current progress ratio
2. Animate the fill using a Tween (similar to score screen count-up)
3. Play count-up beeps (rising pitch) proportional to fill progress
4. Show a label or tooltip with current/max progress (e.g., "756 / 1000 kills")

### Design Details

- **Progress bar visual**: thin bar at the bottom of the card (extending `_create_progress_overlay()`)
- **Animation**: animate from 0 to actual progress ratio over ~1.5 seconds (like score screen)
- **Sound**: play beeps using same beep mechanism, frequency rising from 220Hz to 880Hz
- **Timing**: animate all qualifying slots on armory open (stagger by slot index for effect)
- **Non-quantitative locked slots**: no change (they show gold shimmer if condition met, no progress bar)

## Files to Modify

1. `scripts/autoload/unlock_manager.gd` — add progress query methods
2. `scripts/ui/armory_menu.gd` — add startup progress animation

## Files to Add/Update

1. `tests/unit/test_armory_kill_progress.gd` — unit tests for new progress methods
