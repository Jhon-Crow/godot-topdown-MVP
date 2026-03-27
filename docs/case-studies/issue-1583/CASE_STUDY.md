# Case Study: Issue #1583 — Combat Disposition Speed Modifier + Drift Fix

## Overview

**Issue:** Update the "Боевой настрой" (Combat Disposition) passive item to:
1. Double movement speed before taking damage (×4 on Black Metal difficulty)
2. Halve movement speed after taking the first hit
3. *(Added in PR feedback)* When speed is doubled, also halve the drift/sliding (`Friction` × 2)

**Log file:** `game_log_20260327_075724.txt` — recorded 2026-03-27T07:57:24–07:58:53 on Windows (Godot 4.3-stable, Power Fantasy difficulty)

---

## Timeline Reconstruction

| Time       | Event |
|------------|-------|
| 07:57:24   | Game starts on LabyrinthLevel, Power Fantasy difficulty (value: 3) |
| 07:57:24   | Player initializes — Combat Disposition NOT selected |
| 07:57:25   | Player transitions to BuildingLevel (NavigationFallback) |
| 07:57:25   | Player re-initializes — Combat Disposition NOT selected |
| 07:57:30   | Enemy combat begins |
| 07:57:55   | Another level load — Combat Disposition NOT selected |
| 07:58:01   | **ActiveItemManager: Active item changed from None to Combat Disposition** |
| 07:58:01   | `[Player.CombatDisposition] Speed boost applied (Normal x2): 330 -> 660` |
| 07:58:01   | `[Player.CombatDisposition] Active — damage bonus: +0.77, fire rate bonus: +1.1, max speed: 660` |
| 07:58:08+  | Multiple more level reloads, Combat Disposition re-applied each time (speed 330→660) |
| 07:58:53   | Game session ends — no hit penalty was triggered in this session |

**Key observation:** The player never took damage during this session, so `ApplyCombatDispositionHitPenalty()` was never called. The logs confirm the speed boost (330→660) was applied correctly on each level start.

---

## Root Cause Analysis

### Problem 1: Speed boost implemented, but drift not adjusted

The `BaseCharacter.cs` physics model uses two separate properties:
- `MaxSpeed` — the top movement speed (pixels/second)
- `Friction` — the deceleration rate when no input is given (pixels/second²)

When `MaxSpeed` is doubled (from 330 to 660), the character stops at the same rate as before. But since velocity is twice as high, the **stopping distance** quadruples (physics: `d = v² / 2F`). This manifests as noticeably longer sliding/coasting after releasing keys — "занос" (drift).

**Formula:**
- Default stopping distance: `330² / (2 × 1000) = 54.45 px`
- After ×2 speed with unchanged friction: `660² / (2 × 1000) = 217.8 px` — **4× more drift**
- After ×2 speed with ×2 friction: `660² / (2 × 2000) = 108.9 px` — **2× more drift** (proportional, same feel-ratio as before the boost)

The owner's request: *"при увеличенной скорости должен так же уменьшаться занос в 2 раза"* — when speed is doubled, drift should also be halved (i.e., `Friction` should be doubled to compensate).

### Problem 2: Friction not restored on penalty

After taking the first hit, `MaxSpeed` is set to `base_speed / 2`. If `Friction` was doubled during the speed boost, it must be restored to the original value when the penalty is applied — otherwise the player would have slow speed AND high friction (snappy stopping), which feels wrong for the penalized state.

---

## Physics Background

In Godot's `CharacterBody2D` with `MoveToward`-based friction:
```
velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
```

Stopping time from max speed: `t_stop = MaxSpeed / Friction`
- Normal: 330 / 1000 = 0.33 s
- x2 speed, same friction: 660 / 1000 = 0.66 s (2× longer)
- x2 speed, x2 friction: 660 / 2000 = 0.33 s (same feel)

Doubling `Friction` when doubling `MaxSpeed` preserves the **same subjective stopping feel** — the ratio `MaxSpeed/Friction` stays constant.

---

## Solution

### `Player.ActiveItems.cs`

1. Add `_combatDispositionBaseFriction` field to store `Friction` before the boost.
2. In `InitCombatDisposition()`: after applying the speed multiplier, also multiply `Friction` by the same factor (`speedMult`).
3. In `ApplyCombatDispositionHitPenalty()`: restore `Friction = _combatDispositionBaseFriction` when the penalty is applied (since speed returns to `base_speed / 2`, friction should return to base to avoid over-braking).

### Test Updates (`test_combat_disposition.gd`)

Add `friction` and `base_friction` fields to `MockCombatDispositionSystem`, and add unit tests verifying:
- Friction is doubled on speed boost (normal mode)
- Friction is ×4 on Black Metal
- Friction returns to base on hit penalty

---

## Evidence from Log

```
[07:58:01] [ActiveItemManager] Active item changed from None to Combat Disposition
[07:58:01] [Player.CombatDisposition] Speed boost applied (Normal x2): 330 -> 660
[07:58:01] [Player.CombatDisposition] Active — damage bonus: +0.77, fire rate bonus: +1.1, max speed: 660
```

- Base speed in this session: **330** (Power Fantasy difficulty with speed multiplier applied)
- Boosted speed: **660** (×2 normal)
- No friction change logged — confirms the bug: friction was not adjusted
- No hit penalty in this session — player did not take damage

---

## Files Changed

- `Scripts/Characters/Player.ActiveItems.cs` — add friction modifier
- `tests/unit/test_combat_disposition.gd` — add friction tests
