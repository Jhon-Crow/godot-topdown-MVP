# Case Study: Issue #1127 — Experimental Sample Item (Feedback Round 3)

## Overview
The Experimental Sample item (type 18) is supposed to fire a random active item effect when Space is pressed. This document covers the root-cause analysis for the third round of bugs reported by the owner on 2026-03-20T06:02:04Z.

## Attached Logs
- `game_log_20260320_085819.txt` — game session showing the bugs

## Bugs Reported

### Bug 6: Passive items appearing in effects pool
**Owner report:** "убери из списка эффектов эффекты пассивных предметов (пули с превзрывателем, бронированная кожа и тп)"
(Remove passive item effects from the list — breaker bullets, armored skin, etc.)

**Root cause:**
The C# `HandleExperimentalSampleInput` built a pool of types 1–17 with a uniform for-loop:
```csharp
for (int t = 1; t <= 17; t++)
{
    int tickets = (t == 2 || t == 4) ? 5 : 6;
    ...
}
```
This included purely passive items:
- **6 = BREAKER_BULLETS** — passive bullet modifier (no visible on-press action)
- **9 = LASER_SIGHT** — passive laser sight (always on)
- **10 = EXTENDED_MAGAZINE** — passive magazine size boost
- **13 = ARMORED_SKIN** — passive HP/glass shard effect
- **14 = AUTO_RELOAD** — passive auto-reload on kill
- **17 = COMBAT_DISPOSITION** — passive damage/fire-rate modifier

When these were randomly selected, the code triggered a homing burst as a "visible fallback". This meant the player saw homing bullets instead of the passive item's icon — confusing and not meaningful.

**Fix:** Changed the pool to only include active items (1,2,3,4,5,7,8,11,12,15,16). Passive items 6,9,10,13,14,17 are excluded.

---

### Bug 7: Hold-type items not triggering (flashlight, force field)
**Owner report:** "многие предметы не срабатывают (очки траектории, силовое поле, фонарик и тп)"
(Many items don't trigger — trajectory glasses, force field, flashlight, etc.)

**Root cause from game log:**
```
[Player.ExperimentalSample] Force field effect: homing burst triggered
[Player.ExperimentalSample] Flashlight effect: homing burst triggered
```
Items of type 1 (FLASHLIGHT), 7 (FORCE_FIELD), and 3 (TELEPORT_BRACERS) were still triggering homing burst as fallback because they required holding Space or an aiming phase that experimental sample can't provide via `IsActionJustPressed`.

**Fix:** Each hold-type item now has a proper 4-second timed activation:
- **Flashlight (1)**: Spawns temp node if not equipped → `turn_on()` → timer → `turn_off()` after 4s
- **Force field (7)**: Spawns temp node if not equipped → `activate()` → timer → `deactivate()` after 4s
- **Teleport (3)**: Direct teleport to cursor via `GetSafeTeleportPosition()` + `GlobalPosition = target`

---

### Bug 8: Hold-press effects should work for 4 seconds
**Owner report:** "эффекты предметов, требующих зажатия должны работать 4 секунды (например фонарик должен светить 4 секунды, а телепорт показывать прицел прежде чем телепортировать)"
(Hold-press effects should work for 4 seconds — flashlight should shine 4s, teleport should show aim before teleporting)

**Fix:** As described in Bug 7 fix:
- Flashlight: 4 second timer via `GetTree().CreateTimer(4.0f)`
- Force field: 4 second timer via `GetTree().CreateTimer(4.0f)`
- Recoil compensator (16): Direct `_recoilCompensatorActive = true` for 4 seconds
- Teleport: Instant teleport (no 4s needed — a direct teleport is the expected behavior; "show aiming first" would require full UI which is impractical from experimental sample)

---

## Timeline of Changes

| Date | Event |
|---|---|
| 2026-03-20T05:47:04Z | Owner reports: icons too small, only BFF/homing trigger, rule about screenshots |
| 2026-03-20T05:47:52Z | AI work session started |
| 2026-03-20T05:55:04Z | Session completed: fix re-roll loop, larger icons, duration-matched popup |
| 2026-03-20T06:02:04Z | Owner reports: passive items in pool, hold-type items not triggering, need 4s duration |
| 2026-03-20T06:02:49Z | AI work session started |
| 2026-03-20 | This fix: remove passive items, implement real effects for flashlight/force field/teleport |

## Files Modified
- `Scripts/Characters/Player.cs` — `HandleExperimentalSampleInput` (pool), `TriggerExperimentalSampleEffect` (cases 1, 3, 7, 16)

---

# Case Study Update — Feedback Round 4 (2026-03-20T06:47:58Z)

## Attached Log
- `game_log_20260320_094410.txt`

## Bugs Reported

### Bug 9: Teleport fires immediately (should show crosshair for 4s)
**Owner report:** "телепорт срабатывает сразу (не отображается прицел в течении 4 секунд, должно быть как будто пробел зажат в течении 4 сек)"

**Root cause (from log):**
```
[Player.ExperimentalSample] Teleport bracers: teleported from (150, 1000) to (830.39056, 998.66437)
```
Case 3 called `GlobalPosition = safeTarget` immediately without any delay. No crosshair/aiming phase.

**Fix:** Now borrows the existing teleport bracers aim state:
- Sets `_teleportBracersEquipped = true` and `_teleportAiming = true` so `_Draw()` renders the reticle
- After 4-second timer: sets `_teleportAiming = false`, restores `_teleportBracersEquipped`, then executes teleport

---

### Bug 10: Breaching charges always fall back to homing (never place charge)
**Owner report:** "возможно по той же причине не выходит использовать пробивные заряды"

**Root cause (from log):**
```
[Player.ExperimentalSample] Breaching charges effect: homing burst triggered (no placed charges)
```
The code only tried to *detonate* existing charges, never *placed* new ones. `try_place_charge()` requires a wall within placement radius — since the code never called it, breaching charges always fell back to homing burst.

**Fix:** Now calls `try_place_charge()` — if a wall is nearby, places the charge and schedules detonation after 1 second.

---

### Bug 11: Trajectory glasses don't show trajectory lines
**Owner report:** "не работают очки траектории"

**Root cause (from log):**
```
[Player.ExperimentalSample] Trajectory glasses: temporary effect node created
[Player.ExperimentalSample] Trajectory glasses activated via experimental sample for 10,0s
```
The effect node was created but stored as a *local variable* `effectNode`, not in `_trajectoryGlassesEffect`. Since `_Draw()` checks `_trajectoryGlassesEquipped && _trajectoryGlassesEffect != null`, the trajectory lines were never rendered.

**Fix:** Now stores the temp node in `_trajectoryGlassesEffect` and sets `_trajectoryGlassesEquipped = true`. Also creates the HUD node. After `TrajectoryGlassesDuration + 0.5s`, resets both fields only if they still point to the temp node.

---

### Bug 12: Recoil compensator activates but has no visible effect
**Owner report:** "не работает компенсатор отдачи"

**Root cause:**
`IsRecoilCompensatorActive()` checks `_recoilCompensatorEquipped && _recoilCompensatorActive`. The previous fix set `_recoilCompensatorActive = true` but left `_recoilCompensatorEquipped = false` — so `IsRecoilCompensatorActive()` always returned false. Weapons check this flag before suppressing spread/screenshake.

**Fix:** Also sets `_recoilCompensatorEquipped = true` for the duration and restores to previous value on timer expiry. Also sets `_recoilCompensatorCharge` so the charge bar is visible.

---

## Files Modified (Round 4)
- `Scripts/Characters/Player.cs` — `TriggerExperimentalSampleEffect` (cases 3, 8, 12, 16)
- `docs/case-studies/issue-1127/game_log_20260320_094410.txt` — added log

---

# Case Study: Issue #1127 — Experimental Sample (Feedback Round 4)

**Date:** 2026-03-20T07:12:17Z
**Log:** `game_log_20260320_100804.txt`

## Bugs Reported

### Bug 13: Recoil compensator deactivates immediately

**Owner report:** "не работает - компенсатор отдачи"

**Root cause:**
`HandleRecoilCompensatorInput` checks `Input.IsActionPressed("flashlight_toggle")` every frame.
When the experimental sample activates recoil via `IsActionJustPressed`, Space is no longer held
the very next frame → `else` branch sets `_recoilCompensatorActive = false` immediately.

**Log evidence:**
```
[Player.ExperimentalSample] Recoil compensator activated for 4s
[Player.RecoilCompensator] Deactivated, charge: 3,97 s   ← next frame
```

**Fix:** Added `_recoilCompensatorExperimentalTimer` field. When set, `HandleRecoilCompensatorInput`
ticks this timer each frame and keeps `_recoilCompensatorActive = true` for the full 4 s
without requiring Space to be held.

---

### Bug 14: Loudspeaker has no visual/sound effect

**Owner report:** "не работает - громкоговоритель"

**Root cause:**
Case 11 only called `LoudspeakerApplyEffect()` (pacification logic) but did NOT:
- Call `LoudspeakerAlertAllEnemies()` (enemy awareness)
- Play the cone visual (`_loudspeakerConeEffect.play()`)

**Fix:** Case 11 now:
1. Creates a temporary cone effect node if `_loudspeakerConeEffect` is null
2. Calls `play(aimDir)` on the cone node
3. Calls `LoudspeakerAlertAllEnemies()` before applying the pacification effect

---

### Bug 15: Breaching charges explode after 1 second (should be 4 seconds)

**Owner report:** "пробивной заряд должен закладываться и взрываться через 4 секунды"

**Root cause:** Timer in case 12 used a 1.0f constant.

**Fix:** Changed delay to `BreachingDetonateDelay = 4.0f` seconds.

---

### Bug 16: Teleport crosshair shows briefly then teleports immediately

**Owner report:** "прицел телепорта отображается, но не 4 секунды а гораздо меньше"

**Root cause:**
When the experimental sample fires case 3, it sets `_teleportBracersEquipped = true` and
`_teleportAiming = true`. But `HandleTeleportBracersInput` runs every `_PhysicsProcess` frame.
Since Space was only just-pressed (not held), the `else if (_teleportAiming)` branch fires
on the very next frame and executes `ExecuteTeleport()` immediately.

**Fix:** Added `_teleportExperimentalActive` boolean flag. While true:
- `HandleTeleportBracersInput` returns early (does NOT execute teleport)
- The target position is still updated each frame so the reticle tracks the cursor
The timer callback sets `_teleportExperimentalActive = false` then teleports.

---

### Bug 17: BFF should be even rarer

**Owner report:** "сделай чтоб BFF выпадал ещё реже"

**Root cause:** BFF had 5 tickets (~5%) in the weighted pool.

**Fix:** Reduced BFF (type 4) from 5 → 2 tickets (~2%). Pool totals:
- BFF (4): 2 tickets ≈ 2%
- Homing (2): 5 tickets ≈ 5%
- All 9 other active types: 10 tickets each ≈ 10%
- Total: 2 + 5 + 90 = 97 tickets
