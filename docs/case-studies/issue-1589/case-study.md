# Case Study: Issue #1589 — Unlock conditions not always triggering item unlocks

**Date:** 2026-03-27
**Issue:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1589
**PR:** https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1595
**Log files analyzed:**
- [`game_log_20260327_081355.txt`](game_log_20260327_081355.txt) — 49,572 lines, session starting from scratch
- [`game_log_20260327_082925.txt`](game_log_20260327_082925.txt) — 14,259 lines, continuation of same play session

---

## 1. Summary

After an initial fix (commit `d9975af5`) that updated unlock thresholds and added missing
unlock conditions, the game owner reported a secondary bug:

> "после выполнения условий (например прохождения уровня) не всегда открывается предмет."
> ("after fulfilling conditions (e.g., completing a level), items don't always unlock.")

This case study traces the full event chain in both log files, reconstructs the timeline
of each condition-met event, identifies why unlocks are missed, and documents the root
causes and fixes.

---

## 2. How the Unlock System Works

```
Level completed
     │
     ▼
ScoreManager.complete_level()
     │   emits score_calculated (synchronous)
     ├──► GameManager._on_score_calculated()
     │        - increments no_damage_levels_completed / levels_completed_rank_a_or_higher
     │        - emits <stat>_updated signal  ──► UnlockManager checks condition
     │
     ├──► ProgressManager._on_score_calculated()
     │        - saves progress
     │        - emits progress_updated  ──► UnlockManager checks condition
     │
     └──► (returns score_data to level script)
              │
              ▼
         _show_score_screen(score_data)
              │
              ▼
         AnimatedScoreScreen plays animation
              │   (seconds later)
              ▼
         animation_completed signal
              │
              ▼
         _add_score_screen_buttons()
              │  calls has_any_available_unlock()
              ├─── TRUE  → shows ★ Armory button
              └─── FALSE → no armory button shown
```

**Key design principle:** Items are NOT auto-unlocked. The player must hold LMB on the
gold slot in the Armory UI to permanently unlock an item. The armory button on the score
screen is the intended path.

---

## 3. Timeline Reconstruction from Logs

### 3.1 Successful unlock: LabyrinthLevel (log2, line 1024)

```
[08:29:47] Condition met for LabyrinthLevel — items now available
[08:29:49] LabyrinthLevel: Armory button pressed from score screen
[08:29:50] Active item unlocked: Recoil Compensator
```

✅ Working correctly. Animation completed, armory button appeared, player used it.

### 3.2 Working unlock via PauseMenu armory: BuildingLevel (log1, line 9868)

```
[08:17:05] Condition met for BuildingLevel
[08:17:09] Weapon unlocked: shotgun          ← via score-screen armory (no button-press log in C#)
[08:17:12] Grenade unlocked: Frag Grenade    ← via score-screen armory
[08:17:19] Scene changed to TestTier
```

✅ Items DID unlock — the `LevelInitFallback.cs` armory path has no log for button press,
but the unlocks are confirmed. No bug here.

### 3.3 BUG INSTANCE: SewerLevel Breaker Bullets (log2, lines 13484–13921)

```
[08:33:14] Level completed — damage_taken: 35
[08:33:14] Rank-A level condition met — Breaker Bullets now available to unlock in armory
[08:33:14] Rank-A level completed — levels_completed_rank_a_or_higher: 7
[08:33:14] Progress saved: rank=S, score=180777
[08:33:14] ScoreManager: Level completed! Final score: 180777, Rank: S
[08:33:15] GameManager.restart_scene() — starting scene reload    ← ⚠️ Q KEY PRESSED!
[08:33:16] Scene changed (SewerLevel reloaded)
...
[08:33:22] PauseMenu: Armory button pressed                        ← player found it via pause menu
[08:33:27] Active item unlocked: Breaker Bullets
```

**What happened:**
1. Breaker Bullets condition became satisfied (7 rank-A levels).
2. The animated score screen started playing its animation.
3. The player pressed **Q** (1 second after level completion).
4. `GameManager._input()` handles Q globally — `restart_scene()` fired immediately.
5. The animation never finished → `animation_completed` never fired → armory button never appeared.
6. The player found the armory via the PauseMenu on the NEXT run and unlocked it there.

**Why this is a bug:** The player had NO OPPORTUNITY to see the armory button. The Q key
shortcut runs globally with no check for whether the score animation is still playing.

### 3.4 BUG INSTANCE: TestTier skipped to next level (log2, line 5192)

```
[08:31:00] Level completed — damage_taken: 65
[08:31:00] Condition met for TestTier.tscn — items now available to unlock in armory
[08:31:00] ScoreManager: Level completed! Final score: 174648, Rank: S
[08:31:00] BffCompanion ROT_CHANGE (combat events still firing after level complete!)
[08:31:01] Shot fired with ak_gl (49 total)   ← player still shooting after level end
[08:31:02] Shot fired with ak_gl (50 total)   ← player walking into exit zone at y=1544
[08:31:03] Scene changed to CastleLevel       ← player pressed Next Level on score screen
```

**What happened:**
- TestTier's `_complete_level_with_score()` does NOT disable player controls first.
- The player walked into the exit zone while shooting, which simultaneously triggered
  the score screen.
- Player clicked "Next Level" on the score screen within 3 seconds — too fast to notice
  the armory button (which appeared only after the animation finished).
- The Sniper unlock from TestTier was already unlocked in a previous session, so
  `has_any_available_unlock()` → false → no armory button. This is correct behavior
  for this specific case, but the lack of player-control disabling causes confusion.

---

## 4. Root Cause Analysis

### Root Cause 1 (PRIMARY): Q key bypass of score screen

**Location:** `scripts/autoload/game_manager.gd` lines 265–269

```gdscript
func _input(event: InputEvent) -> void:
    if event is InputEventKey:
        if event.pressed and event.physical_keycode == KEY_Q:
            restart_scene()   # ← NO check for score screen state
```

**Effect:** Pressing Q during the animated score screen animation immediately calls
`restart_scene()`. The animation never completes, `animation_completed` never fires,
`_add_score_screen_buttons()` never runs, and the armory button is never shown.

**Confirmed in logs:** SewerLevel (log2, 08:33:15) — 1 second after condition met.

### Root Cause 2 (SECONDARY): TestTier does not disable player controls

**Location:** `scripts/levels/test_tier.gd` lines 826–833

```gdscript
func _complete_level_with_score() -> void:
    var score_manager: Node = get_node_or_null("/root/ScoreManager")
    if score_manager and score_manager.has_method("complete_level"):
        var score_data: Dictionary = score_manager.complete_level()
        _show_score_screen(score_data)   # ← no _disable_player_controls() first!
```

`building_level.gd` and `LevelInitFallback.cs` both disable player controls before
calling `complete_level()`. TestTier skips this step, allowing the player to keep
moving and firing after the level completes.

### Root Cause 3 (TERTIARY): Labyrinth2Level has its own Q key handler

**Location:** `scripts/levels/labyrinth2_level.gd` lines 1364–1369

```gdscript
func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_Q:
            get_tree().reload_current_scene()   # ← no score-screen check
```

Same issue as Root Cause 1 — pressing Q during the score screen animation immediately
reloads the scene before the armory button can appear.

---

## 5. Evidence Summary

| Event | Log | Line | Condition Met | Armory Button Appeared? | Items Unlocked? | How |
|---|---|---|---|---|---|---|
| LabyrinthLevel | log2 | 1024 | ✅ | ✅ (line 1028) | ✅ | Score screen armory |
| BuildingLevel | log1 | 9868 | ✅ | ✅ (no C# log, but items unlocked) | ✅ | Score screen armory |
| TestTier | log1 | 16067 | ✅ | ✅ | ✅ | Score screen armory |
| CastleLevel | log1 | 21468 | ✅ | ✅ | ✅ | Score screen armory |
| FactoryLevel | log1 | 36802 | ✅ | ✅ | ✅ | Score screen armory |
| BeachLevel | log1 | 41166 | ✅ | ✅ | ✅ | Score screen armory |
| DecadenceLevel | log1 | 48522 | ✅ | ✅ | ✅ | Score screen armory |
| LabyrinthLevel | log2 | 1024 | ✅ | ✅ | ✅ | Score screen armory |
| TestTier | log2 | 5192 | ✅ | ❌ (sniper already unlocked) | N/A | Nothing to unlock |
| **SewerLevel** | **log2** | **13484** | **✅** | **❌ Q pressed at 13486** | **⚠️ Later via PauseMenu** | **Pause menu (8s later)** |

---

## 6. Fix

### Fix 1 (PRIMARY): Block Q-key restart during score animation

Add a `score_screen_active` flag to `GameManager` that is set true when the animated
score screen starts and false when `animation_completed` fires. The Q-key handler
checks this flag before calling `restart_scene()`.

**`scripts/autoload/game_manager.gd`:**
```gdscript
## Set to true while the animated score screen is playing (blocks Q-key restart).
var score_screen_active: bool = false

func _input(event: InputEvent) -> void:
    if event is InputEventKey:
        if event.pressed and event.physical_keycode == KEY_Q:
            if score_screen_active:
                return  # Block restart during score animation
            restart_scene()
```

**`scripts/ui/animated_score_screen.gd`:**
```gdscript
func show_animated_score(ui: Control, score_data: Dictionary) -> void:
    # Notify GameManager that score screen is active (blocks Q-key restart)
    var game_manager := get_node_or_null("/root/GameManager")
    if game_manager:
        game_manager.score_screen_active = true
    ...

func _finalize_animation(container: VBoxContainer) -> void:
    # Re-enable Q-key restart now that buttons are visible
    var game_manager := get_node_or_null("/root/GameManager")
    if game_manager:
        game_manager.score_screen_active = false
    ...
```

### Fix 2 (SECONDARY): Disable player controls in TestTier before showing score

**`scripts/levels/test_tier.gd`:**
```gdscript
func _complete_level_with_score() -> void:
    # Disable player controls so clicks on score screen don't trigger shooting
    if _player != null:
        _player.set_physics_process(false)
        _player.set_process(false)
        _player.set_process_input(false)
        _player.set_process_unhandled_input(false)
    var score_manager: Node = get_node_or_null("/root/ScoreManager")
    ...
```

### Fix 3 (TERTIARY): Block Q-key in Labyrinth2Level during score screen

**`scripts/levels/labyrinth2_level.gd`:**
```gdscript
func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_Q:
            var game_manager := get_node_or_null("/root/GameManager")
            if game_manager and game_manager.score_screen_active:
                return  # Block restart during score animation
            get_tree().reload_current_scene()
```

---

## 7. Why Previous Fix Was Incomplete

The initial fix (commit `d9975af5`) correctly resolved:
- Laser Sight: threshold reduced from 1000 → 400 kills
- Force Field: added FactoryLevel condition (was missing entirely)
- Breaker Bullets: added `levels_completed_rank_a_or_higher` counter and condition

However, it did not address the presentation layer bug: even when conditions are correctly
detected and signaled, the player may not see the armory button because:
1. The Q key bypass fires before the score animation completes
2. The armory button only appears AFTER `animation_completed` (post-animation)

The fix in this case study addresses the reliability of the armory button presentation,
ensuring the player always has the opportunity to access the armory when items are available.
