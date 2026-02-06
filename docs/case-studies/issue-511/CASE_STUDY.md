# Case Study: Issue #511 — Score Tracking Regressions

## Issue Summary

Issue #511 requested two features:
1. Add score tracking after completing the TestTier level
2. Rename TestTier to "Полигон"

The initial PR (#514) implementation introduced several regressions that broke existing gameplay functionality.

## Timeline of Events

| Timestamp | Event |
|-----------|-------|
| 2026-02-06 ~15:10 | PR #514 solution draft completed and posted |
| 2026-02-06 ~18:55 | Owner (Jhon-Crow) tested the build, found critical regressions |
| 2026-02-06 ~18:55 | Owner reported: broken ammo counter, enemy counter, weapon selection, and no score screen |
| 2026-02-06 ~20:22 | Second AI work session started to investigate and fix |

## User-Reported Symptoms

From Jhon-Crow's comment on PR #514:
> сломался счётчик патронов, врагов и выбор оружия как минимум.
> после убийства всех врагов не появляется статистика.

Translation:
- Ammo counter broken
- Enemy counter broken
- Weapon selection broken
- After killing all enemies, statistics don't appear

## Game Log Analysis

**Log file**: `game_log_20260206_214850.txt` (4,446 lines)

### Play Session Summary

The log captures a BuildingLevel session followed by 8 TestTier sessions (player died/restarted multiple times):

| Session # | Time | Scene | Outcome |
|-----------|------|-------|---------|
| 1 | 21:48:50 | BuildingLevel | Transitioned to TestTier |
| 2-7 | 21:49:00-21:49:19 | TestTier | Player died (multiple quick deaths) |
| 8 | 21:53:59 | TestTier | Player opened Armory menu, restarted |
| 9 | 21:54:04 | TestTier | **Player killed all 10 enemies, no score appeared** |

### Final Session Kill Sequence (21:54:04 - 21:54:42)

| Time | Enemy | Remaining (SoundPropagation) |
|------|-------|------------------------------|
| 21:54:09 | PatrolEnemy1 | 9 |
| 21:54:11 | GuardEnemy2 | 8 |
| 21:54:11 | PatrolEnemy3 | 7 |
| 21:54:12 | GuardEnemy4 | 6 |
| 21:54:14 | GuardEnemy3 | 5 |
| 21:54:16 | GuardEnemy1 | 4 |
| 21:54:21 | PatrolEnemy4 | 3 |
| 21:54:24 | GuardEnemy6 | 2 |
| 21:54:29 | PatrolEnemy2 | 1 |
| 21:54:30 | GuardEnemy5 | 0 |

All 10 enemies killed. SoundPropagation correctly tracked 10→0. Game log ended at 21:54:42 with **no score screen messages**.

## Root Cause Analysis

### Bug 1: Double-Counting Enemy Deaths (CRITICAL)

**Root Cause**: The PR changed the enemy death handler structure incorrectly.

**Working pattern** (building_level.gd, main branch test_tier.gd):
```gdscript
# In _setup_enemy_tracking():
child.died.connect(_on_enemy_died)           # Handles counting + game flow
child.died_with_info.connect(_on_enemy_died_with_info)  # Handles ScoreManager only

# Separate handlers:
func _on_enemy_died() -> void:
    _current_enemy_count -= 1
    GameManager.register_kill()
    if _current_enemy_count <= 0: _activate_exit_zone()

func _on_enemy_died_with_info(is_ricochet, is_penetration) -> void:
    score_manager.register_kill(is_ricochet, is_penetration)  # ONLY this
```

**Broken pattern** (PR #514):
```gdscript
# _on_enemy_died_with_info did EVERYTHING (count + GameManager + ScoreManager + level clear)
func _on_enemy_died_with_info(is_ricochet_kill = false, is_penetration_kill = false):
    _current_enemy_count -= 1
    GameManager.register_kill()
    score_manager.register_kill(...)
    if _current_enemy_count <= 0: _activate_exit_zone()

# _on_enemy_died delegated to _on_enemy_died_with_info
func _on_enemy_died():
    _on_enemy_died_with_info(false, false)
```

**Problem**: GDScript enemies emit BOTH `died` AND `died_with_info` signals when dying. With both connected:
1. `died` → `_on_enemy_died()` → calls `_on_enemy_died_with_info()` → decrements count (1st time)
2. `died_with_info` → `_on_enemy_died_with_info()` → decrements count again (2nd time)

**Cascading effects**:
- Enemy counter shows wrong numbers (decrements by 2 per kill)
- `GameManager.register_kill()` called twice per kill (inflates kill count)
- `ScoreManager.register_kill()` called twice per kill (inflates score)
- `_activate_exit_zone()` triggered prematurely (after 5 kills instead of 10)
- After all enemies dead, the exit zone was already activated long ago and the player may have missed it or it may have become stale

### Bug 2: Missing `_combo_label` Variable Declaration

**Root Cause**: The `_on_combo_changed()` function referenced `_combo_label` but this variable was never declared at the class level.

**Impact**: Runtime error in Godot when ScoreManager emits `combo_changed` signal. This would cause a crash/error on the first combo kill, potentially disrupting the entire level script execution.

**Code location**: `scripts/levels/test_tier.gd`, line 127 (original):
```gdscript
func _on_combo_changed(combo: int, points: int) -> void:
    if _combo_label == null:  # ERROR: _combo_label not declared as class member
```

### Bug 3: Unintended Sniper Rifle Removal from Armory

**Root Cause**: The PR locked the ASVK sniper rifle in the armory menu and removed its weapon setup code from test_tier.gd, even though this was not requested in issue #511.

**Changes made by PR**:
- `armory_menu.gd`: Changed sniper entry from unlocked ASVK to locked "???"
- `test_tier.gd`: Removed SniperRifle from weapon lookup chain and `_setup_selected_weapon()` handler

**Impact**: Players who had previously selected the ASVK would find it locked/missing, and any existing weapon selection state would break.

## Fixes Applied

1. **Bug 1**: Restructured `_on_enemy_died()` and `_on_enemy_died_with_info()` to match the building_level.gd pattern:
   - `_on_enemy_died()`: Handles counting, GameManager, and level completion
   - `_on_enemy_died_with_info()`: Only handles ScoreManager special kill tracking

2. **Bug 2**: Added `var _combo_label: Label = null` class member variable declaration

3. **Bug 3**: Restored ASVK sniper rifle entry in armory_menu.gd and sniper rifle weapon setup code in test_tier.gd to match main branch

## Lessons Learned

1. **Follow existing patterns**: When adding new functionality (score tracking) to a level script, follow the exact same pattern used in other levels (building_level.gd). The working pattern separates counting from scoring.

2. **Signal double-fire awareness**: In GDScript, when an object emits multiple signals on the same event (e.g., `died` and `died_with_info`), handlers must not chain/delegate between each other or they'll double-execute.

3. **Minimal changes principle**: Don't modify unrelated functionality (weapon selection/armory) when the issue only asks for score tracking and renaming. Each change increases regression risk.

4. **Variable declarations**: Always verify that all referenced variables are properly declared at the class level, especially when adding new UI elements dynamically.

## Data Files

- `game_log_20260206_214850.txt` - Original game log from user testing session
- `CASE_STUDY.md` - This analysis document
