# Case Study: Issue #1069 — Dead Eye Passive Item Not Working

## Summary

Issue #1069 requested a new passive item called "Dead Eye" (Мёртвый глаз / Дэд ай) with the following mechanics:
- Starts with **-20% damage** (multiplier = 0.8)
- Each successful hit **increases damage by +5%** (stacks: 0.8 → 0.85 → 0.90 → ...)
- After a miss, **damage resets** to -20%
- "Volley" definition: for shotguns/snipers (multi-projectile), at least one pellet must hit to count as a hit; for automatic weapons, a continuous burst within 1 second counts as one volley

The initial implementation (PR #1070, commit `9f1ce199`) registered the item in `ActiveItemManager` and created `DeadEyeManager`, but the owner reported the item was **not working** after testing with a production build.

## Logs Analyzed

| Log file | Duration | Session |
|---|---|---|
| `game_log_20260317_215744.txt` | ~2 min | Windows export, 2026-03-17 21:57–21:59 |

**Session details:**
- OS: Windows (production export, non-debug build)
- Engine: Godot 4.3-stable
- Weapon: Makarov PM (pistol)
- Dead Eye selected as active item (type 10)
- Levels visited: LabyrinthLevel, multiple rapid restarts

## Timeline Reconstruction

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

## Root Cause Summary

| # | Root Cause | Impact | Fix Applied |
|---|---|---|---|
| RCA-1 | Implementation was absent in the tested build | Item had no effect | PR #1070 (commit `9f1ce199`) adds full Dead Eye implementation |
| RCA-2 | No HUD indicator for hit streak / multiplier state | No player feedback | Added `dead_eye_hud.gd` — red eye + counter displayed above player |
| RCA-3 | Dead Eye icon was copy of Laser Sight icon | Visual confusion in armory | Regenerated unique red-eye-with-crosshair icon |

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
