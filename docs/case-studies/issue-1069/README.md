# Case Study: Issue #1069 — Dead Eye Passive Item Not Working

## Summary

Issue #1069 requested a new passive item called "Dead Eye" (Мёртвый глаз / Дэд ай) with the following mechanics:
- Starts with **-20% damage** (multiplier = 0.8)
- Each successful hit **increases damage by +5%** (stacks: 0.8 → 0.85 → 0.90 → ...)
- After a miss, **damage resets** to -20%
- "Volley" definition: for shotguns/snipers (multi-projectile), at least one pellet must hit to count as a hit; for automatic weapons, a continuous burst within 0.5 seconds counts as one volley (reduced from 1.0s per owner feedback 2026-03-20)

The initial implementation (PR #1070, commit `9f1ce199`) registered the item in `ActiveItemManager` and created `DeadEyeManager`, but the owner reported the item was **not working** after testing with a production build.

## Logs Analyzed

| Log file | Duration | Session |
|---|---|---|
| `game_log_20260317_215744.txt` | ~2 min | Windows export, 2026-03-17 21:57–21:59 |
| `game_log_20260318_065120.txt` | ~2 min | Windows export, 2026-03-18 06:51–06:54 |
| `game_log_20260320_102550.txt` | ~11 min | Windows export, 2026-03-20 10:25–10:36 |

**Session 1 details (2026-03-17):**
- OS: Windows (production export, non-debug build)
- Engine: Godot 4.3-stable
- Weapon: Makarov PM (pistol)
- Dead Eye selected as active item (type 10)
- Levels visited: LabyrinthLevel, multiple rapid restarts

**Session 2 details (2026-03-18):**
- OS: Windows (production export, non-debug build)
- Engine: Godot 4.3-stable
- Weapon: Mini UZI
- Saved game had active item type 18 (`Invalid active item type: 18`)
- Levels visited: LabyrinthLevel (manual armory → Dead Eye selection at 06:53:40)
- Owner feedback: "counter didn't appear above player, effect probably not working"

## Timeline Reconstruction

### Session 1 (2026-03-17)

```
21:57:44 - Game starts (LabyrinthLevel)
21:57:44 - PersistManager restores: Dead Eye selected (ActiveItemType = 10)
21:57:44 - [ActiveItemManager] Active item changed from None to Dead Eye
21:57:44 - [Player.TrajectoryGlasses] No trajectory glasses selected
           ← [Player.DeadEye] MISSING — dead_eye activation never logged
21:57:44 - [Player] Ready! Ammo: 9/9, Grenades: 1/3, Health: 2/4
... (combat with no Dead Eye effect, multiplier stacks never appear in log)
21:57:55 - Dead Eye changed to Laser Sight (user testing)
21:58:03 - Laser Sight changed back to Dead Eye
21:58:03 - [Player.DeadEye] STILL MISSING
```

### Session 2 (2026-03-18)

```
06:51:20 - Game starts (LabyrinthLevel)
06:51:20 - PersistManager: Restored unlocked active item types 0–14
06:51:20 - [ActiveItemManager] Invalid active item type: 18
           ← Owner's old build saved type 18 (a different item) which was invalid
06:51:20 - PersistManager: Restored selected active item type: 18
           ← No valid item selected, so active item defaults to None
06:51:20 - [Player.AutoReload] Auto-reload not selected
           ← [Player.DeadEye] MISSING (still using old build without Dead Eye init code)
06:51:20 - [Player] Ready! Ammo: 32/32
06:53:40 - [ActiveItemManager] Active item changed from None to Dead Eye
           ← Owner manually selected Dead Eye from armory mid-session
06:53:40 - Scene reloads (LabyrinthLevel restart after armory change)
06:53:40 - [Player.AutoReload] Auto-reload not selected
           ← [Player.DeadEye] STILL MISSING — confirming old build lacks _init_dead_eye()
06:53:40 - [Player] Ready! Ammo: 32/32
```

### Session 3 (2026-03-20)

```
10:25:50 - Game starts (LabyrinthLevel)
10:25:50 - PersistManager: Restored unlocked active item types 0–17
           ← Types 0–17 restored (Dead Eye = 18 was NOT in the unlocked list)
10:25:50 - [ActiveItemManager] Active item changed from None to Invisibility
           ← Owner started with Invisibility selected (not Dead Eye)
10:26:01 - [ActiveItemManager] Active item changed from Invisibility to Dead Eye
           ← Owner went to armory and manually selected Dead Eye
10:26:01 - Scene reloads (LabyrinthLevel restart after armory change)
10:26:01 - [Player.InvisibilitySuit] No invisibility suit selected
           ← [Player.DeadEye] MISSING — old build still lacks _init_dead_eye()
10:26:01 - [Player.RecoilCompensator] Recoil compensator not selected
10:26:01 - [Player.Jammer] JammerHUD initialized
10:26:01 - [Player] Ready! Ammo: 30/30
           ← Dead Eye activated per ActiveItemManager, but _init_dead_eye() never called
```

**Key finding in Session 3:**
- The owner tested with build from folder `I:/Загрузки/godot exe/ДЭДАЙ/` (path suggests a dedicated "Dead Eye" test build)
- `[ActiveItemManager] Active item changed from Invisibility to Dead Eye` — Dead Eye IS recognized
- However `[Player.DeadEye]` is **completely absent** from the player init sequence — confirming old build
- The sequence shows: `[Player.RecoilCompensator]` then `[Player.Jammer]` — our `_init_dead_eye()` call is between `_init_recoil_compensator()` and `_init_active_item_progress_bar()`, which would produce `[Player.DeadEye]` — but it doesn't
- This confirms the build is **still pre-PR #1070** despite the armory showing Dead Eye as an option (item data was added to ActiveItemManager before the full implementation)

## Root Cause Analysis

### RCA-1: Build Did Not Contain Dead Eye Logic

The production build used for testing was **compiled before or from a state where the Dead Eye implementation was not yet in the project files**. The `ActiveItemManager` correctly recognized Dead Eye (item data was present), but the `DeadEyeManager` autoload and `_init_dead_eye()` in `player.gd` were absent from the exported `.pck`.

**Evidence:**
- `[Player]` log shows `[Player.TrajectoryGlasses]` logged, then `[Player] Ready!` — no `[Player.DeadEye]` entry between them, despite the code at line 374 of `player.gd` calling `_init_dead_eye()` immediately after `_init_trajectory_glasses()`
- No `[DeadEyeManager]` log entries anywhere in the 4101-line log
- Dead Eye item was correctly stored and restored from save (PersistManager), confirming item data was present

### RCA-2: No Visual Feedback

Even if the logic worked, there was no visual indicator for the player. Without a HUD element, the player cannot observe:
- Current hit streak count
- When the multiplier resets on miss
- The -20% starting penalty

### RCA-3: Placeholder Icon

The initial icon (`assets/sprites/weapons/dead_eye_icon.png`) was an **exact copy** of the Laser Sight icon (verified by identical MD5 hash: `8c94c1a0f5b52ad2d4f37f36adcfa3fc`). This made Dead Eye indistinguishable from Laser Sight in the armory.

### RCA-4: Enum Index Collision (Session 2)

In session 2, PersistManager logged `Invalid active item type: 18`. This indicates:
- The owner's saved game referenced type 18 (an item from a different build)
- In our initial PR implementation, `DEAD_EYE` was assigned index 14
- Main branch later added `EXTENDED_MAGAZINE` (index 10), `DRILLING_BULLETS` (15), `RECOIL_COMPENSATOR` (16), and `COMBAT_DISPOSITION` (17), shifting all existing items
- After the merge conflict resolution in this PR, `DEAD_EYE` is now **index 18**, which exactly matches the owner's saved game state

This means once the owner tests with the merged build, their existing save game will automatically select Dead Eye (the saved type 18 will correctly map to DEAD_EYE).

## Root Cause Summary

| # | Root Cause | Impact | Fix Applied |
|---|---|---|---|
| RCA-1 | Implementation was absent in the tested build | Item had no effect | PR #1070 adds full Dead Eye implementation |
| RCA-2 | No HUD indicator for hit streak / multiplier state | No player feedback | Added `dead_eye_hud.gd` — red eye + counter displayed above player |
| RCA-3 | Dead Eye icon was copy of Laser Sight icon | Visual confusion in armory | Regenerated unique red-eye-with-crosshair icon |
| RCA-4 | Enum index 18 in save game was "Invalid" in old build | Item type could not be restored | `DEAD_EYE` is now index 18, making old saves automatically valid |

## Implementation Overview

### Files Changed

| File | Change |
|---|---|
| `scripts/autoload/dead_eye_manager.gd` | Added `get_hit_streak()` method for HUD polling |
| `scripts/ui/dead_eye_hud.gd` | **New**: red eye indicator with streak counter, hit/miss flash effects |
| `scripts/characters/player.gd` | `_init_dead_eye()` extended to create `DeadEyeHUD` node |
| `assets/sprites/weapons/dead_eye_icon.png` | Unique red eye + crosshair icon (64×64 RGBA) |

### Dead Eye HUD Description

- **Red elliptical eye** drawn above player using `_draw_ellipse()` polygon approximation
- **Iris/pupil** with specular highlight
- **Hit-flash**: iris flashes bright red (0.25s) when streak increases
- **Reset-flash**: eye flashes gray (0.35s) when miss resets the multiplier
- **Counter label**: shows `x2`, `x3`, ... for active streak, or `-20%` when at base
- Positioned 36px above player center (`OFFSET_Y = -36.0`), always visible while item is equipped

### Dead Eye Manager — `get_hit_streak()` Addition

```gdscript
func get_hit_streak() -> int:
    if not _is_active:
        return 0
    return int(round((_multiplier - BASE_MULTIPLIER) / HIT_STEP))
```

Returns 0 at base multiplier, 1 after first hit, etc.

## Comparison with Similar Features

The HUD implementation follows the same pattern as `invisibility_hud.gd` (Issue #673) and `trajectory_glasses_hud.gd` (Issue #744):
- `extends Node2D` autoloaded as child of Player
- `_draw()` for custom rendering via `queue_redraw()`
- `initialize(manager_ref)` called from `player.gd._init_dead_eye()`
- `_process()` polls manager state and updates display

## Online References

- Godot 4 `_draw()` documentation: https://docs.godotengine.org/en/stable/tutorials/2d/custom_drawing_in_2d.html
- Godot 4 `Node2D.draw_string()` (ThemeDB.fallback_font): https://docs.godotengine.org/en/stable/classes/class_node2d.html
- "Dead Eye" mechanic origin: Red Dead Redemption series — the name refers to a slow-motion targeting ability; the game mechanic here is a damage-stacking variant

## Proposed Solutions (Implemented)

1. **Fix icon** — generate unique red-eye-with-crosshair PNG (64×64) using pure Python (no external deps)
2. **Add HUD** — `scripts/ui/dead_eye_hud.gd` provides persistent visual feedback for the passive item state
3. **Extend manager** — `get_hit_streak()` added to `DeadEyeManager` for HUD polling
4. **Document in player.gd** — `_init_dead_eye()` now creates the HUD node and logs creation
5. **Reduce volley window to 0.5s** — Owner feedback requested that the miss timer be 0.5 seconds instead of 1.0s; `VOLLEY_WINDOW` reduced accordingly in `dead_eye_manager.gd`
