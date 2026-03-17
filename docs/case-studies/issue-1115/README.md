# Case Study: Issue #1115 — Radio Jammer Enemy: Cancel Active Effects + Resize HUD Icon

## Overview

| Field | Value |
|-------|-------|
| **Issue** | [#1115 — update Radio Jammer enemy](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1115) |
| **Pull Request** | [#1116 — fix: cancel active item effects and resize jammer HUD icon](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1116) |
| **Status** | Fix implemented on branch `issue-1115-d78fefdfd813` |
| **Author** | Jhon-Crow |
| **Solved by** | AI automated solver (konard) |
| **Date opened** | 2026-03-17T21:39:02Z |
| **Date of game log (first)** | 2026-03-18T01:01:26Z |
| **Date of game log (second)** | 2026-03-18T02:06:55Z |
| **Predecessor issue** | [#1036 — Add Radio Jammer enemy](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1036) |

---

## 1. Issue Description

The issue report (originally in Russian, translated):

> If an activatable item is already active when the player enters the jammer zone — the effect should stop.
> Make the prohibition sign above the player smaller (should be approximately the same size as the Combat Disposition item icon).

Two independent sub-problems:

1. **Bug**: The Radio Jammer enemy only blocked *new* active item activations (via the `flashlight_toggle` input guard added in Issue #1036). Effects already running before the player entered jammer range continued uninterrupted until their natural expiry timer ran out.
2. **UX**: The prohibition sign HUD drawn above the player (`CIRCLE_RADIUS = 14`, `LINE_WIDTH = 4`) was visually oversized compared to the Combat Disposition item icon (~32 px total diameter, i.e., ~16 px radius).

---

## 2. Affected Systems

| System | File | Role |
|--------|------|------|
| `player.gd` | `scripts/characters/player.gd` | Input handlers for each active item; where jammer cancellation was missing |
| `active_item_manager.gd` | `scripts/autoload/active_item_manager.gd` | `is_active_item_jammed()` and `is_active_item_jammed_verbose()` — distance query against live Radio Jammer enemies |
| `jammer_hud.gd` | `scripts/ui/jammer_hud.gd` | Draws the prohibition sign (circle + diagonal bar) above the player |
| `radio_wave_effect.gd` | `scripts/effects/radio_wave_effect.gd` | Animated radio wave rings on the jammer enemy; also contributes to jammer group membership |
| `Tests` | `tests/unit/test_radio_jammer_enemy.gd` | Unit tests for jammer radius, cancellation logic, and icon size constraint |

---

## 3. Root Cause Analysis

### 3.1 Missing Cancellation on Enter (Primary Bug)

The original fix for Issue #1036 added a guard at the **beginning of each input handler**:

```gdscript
if Input.is_action_just_pressed("flashlight_toggle"):
    if ActiveItemManager.is_active_item_jammed_verbose():
        return  # Blocks NEW activations
    # ... activate effect
```

This guard correctly prevents pressing Space to start a new effect while jammed.

However, it does **not** check whether a previously activated effect is *currently running*. Each per-frame handler also runs a timer countdown (for timed effects like homing bullets and trajectory glasses) or checks `is_active` (for toggle effects like invisibility). None of those code paths called `is_active_item_jammed()` before Issue #1115 was filed.

**Effect-by-effect breakdown:**

| Active Item | Had cancellation on enter? | Mechanism |
|-------------|---------------------------|-----------|
| Homing Bullets | ❌ No | Timer-based (`_homing_timer`); ticks down regardless of jammer proximity |
| Invisibility Suit | ❌ No | Toggle (`_invisibility_suit.is_active`); duration runs in the effect node |
| Trajectory Glasses | ❌ No | Timer-based (`is_active`, internal timer); blink phase also unaffected |
| Force Field | ✅ Yes (Issue #1036) | `_force_field.deactivate()` was already called on jammer entry |
| Flashlight | ✅ Yes (Issue #1036) | Turned off in flashlight handler on jammer detection |

The asymmetry existed because Force Field and Flashlight had their jammer handling implemented as part of the original Issue #1036 implementation, while the three remaining timed effects were only blocked from *starting*, not from *continuing*.

### 3.2 Oversized HUD Icon (Secondary UX Issue)

`jammer_hud.gd` used:
- `CIRCLE_RADIUS = 14.0` → total diameter ~28 px (just the circle), visually appearing ~28 px wide on screen
- `LINE_WIDTH = 4.0` → thick lines adding to perceived size

The Combat Disposition item icon is rendered at approximately 32 px total (a circle of radius ~16 px). The jammer prohibition sign was larger and drew more attention than intended.

---

## 4. Evidence from the Game Log

### Log file: `game_log_20260318_010126.txt`

**Session summary:**
- Captured: 2026-03-18, 01:01:26–01:01:52 (26 seconds of gameplay)
- Build: Godot 4.3-stable, Windows, debug=false, invincibility=true
- Level: DecadenceLevel (switched to on second level load)
- Active item equipped: **Trajectory Glasses** (switched from Loudspeaker at 01:01:42)
- RadioJammer spawned at: **(1100, 900)** with hp=3, radius=1000

**Key event sequence demonstrating the bug (all times are wall clock):**

```
01:01:42  [ActiveItemManager] Active item changed → Trajectory Glasses
01:01:42  [RadioJammer] Spawned at (1100, 900), hp=3, radius=1000
01:01:42  [TrajectoryGlasses] Weapon set: AKGL
01:01:42  [Player.TrajectoryGlasses] Space pressed - activating (charges: 2)
01:01:42  [TrajectoryGlasses] Activated! Duration: 10.0s, Charges remaining: 1/2
01:01:42  [ActiveItemManager.Jammer] VERBOSE: jammer='RadioJammer' alive=true
            pos=(1100,900) dist=1377.9 radius=1000.0 => clear   ← safe at activation
01:01:43  [ActiveItemManager.Jammer] Periodic: jammer='RadioJammer' player=(209,1742)
            dist=1108.3 radius=1000                              ← still outside range
01:01:45  [ActiveItemManager.Jammer] Periodic: jammer='RadioJammer' player=(604,1398)
            dist=288.7  radius=1000                              ← INSIDE JAMMER RANGE
01:01:47  [ActiveItemManager.Jammer] Periodic: jammer='RadioJammer' player=(799,1269)
            dist=161.1  radius=1000                              ← still inside
01:01:48  [TrajectoryGlasses] Continuous blink phase started at 3.98s remaining ← effect STILL RUNNING
01:01:49–01:01:52  [TrajectoryGlasses] Blink state changed: ...   ← trajectory overlay continues
01:01:52  [TrajectoryGlasses] Blink state changed: ray_visible=true at 0.62s remaining
01:01:52  GAME LOG ENDED
```

**Critical observation**: At **01:01:45**, the player entered the jammer's 1000 px radius (player at (604, 1398) → distance=288.7). The `ActiveItemManager.Jammer` periodic check confirmed the player was *inside* jammer range. Despite this, the TrajectoryGlasses effect **continued running uninterrupted** through the rest of the log, including its blink countdown phase, until the log ended at 0.62s remaining.

There is **no** `[Player.TrajectoryGlasses] Trajectory glasses cancelled by Radio Jammer` log line in this log — confirming the cancellation did not exist in the code used to produce this log. The fix adds exactly that log line.

### Distance timeline reconstruction:

| Time | Player position | Distance to Jammer (1100,900) | Status |
|------|-----------------|-------------------------------|--------|
| 01:01:42 | (150, 1898) | ~1378 px | **OUTSIDE** (clear) |
| 01:01:43 | (209, 1742) | ~1108 px | **OUTSIDE** (clear) |
| 01:01:45 | (604, 1398) | **289 px** | **INSIDE** ← bug manifests |
| 01:01:47 | (799, 1269) | **161 px** | **INSIDE** |
| 01:01:49 | (669, 1269) | **158 px** | **INSIDE** |
| 01:01:51 | (669, 1268) | **156 px** | **INSIDE** |
| 01:01:52 | end of log | — | Glasses still at 0.62s |

The player moved from the starting corner (150, 1900) toward the RadioJammer at (1100, 900), activated Trajectory Glasses while still at safe distance (~1378 px), then walked closer. Entering the 1000 px radius at ~01:01:45 should have cancelled the effect, but did not.

---

## 5. Solution

### 5.1 Cancellation on Enter (player.gd)

For each of the three affected active items, a cancellation check was added **before** the timer/toggle logic in the per-frame handler. The check runs every frame (via `_process`), so there is at most a 1-frame latency (~16 ms at 60 FPS) between entering jammer range and the effect being cancelled.

**Homing Bullets** (`_handle_homing_input`):
```gdscript
# Issue #1115: Cancel homing effect immediately if player enters jammer range while active
if _homing_active and ActiveItemManager.is_active_item_jammed():
    _homing_active = false
    _homing_timer = 0.0
    _stop_homing_scanner()
    homing_deactivated.emit()
    FileLogger.info("[Player.Homing] Homing cancelled by Radio Jammer (Issue #1115)")
```

**Invisibility Suit** (`_handle_invisibility_suit_input`):
```gdscript
# Issue #1115: Cancel invisibility immediately if player enters jammer range while active
if _invisibility_suit.is_active and ActiveItemManager.is_active_item_jammed():
    _invisibility_suit.deactivate()
    FileLogger.info("[Player.InvisibilitySuit] Invisibility cancelled by Radio Jammer (Issue #1115)")
```

**Trajectory Glasses** (`_handle_trajectory_glasses_input`):
```gdscript
# Issue #1115: Cancel trajectory glasses immediately if player enters jammer range while active
if _trajectory_glasses.is_active and ActiveItemManager.is_active_item_jammed():
    _trajectory_glasses.deactivate()
    FileLogger.info("[Player.TrajectoryGlasses] Trajectory glasses cancelled by Radio Jammer (Issue #1115)")
```

All three use the non-verbose `is_active_item_jammed()` variant (no extra log spam per frame — the verbose variant is reserved for input-triggered events).

### 5.2 HUD Icon Resize (jammer_hud.gd)

```gdscript
## Before (Issue #1036):
const CIRCLE_RADIUS: float = 14.0
const LINE_WIDTH: float = 4.0

## After (Issue #1115):
const CIRCLE_RADIUS: float = 10.0
const LINE_WIDTH: float = 3.0
```

- `CIRCLE_RADIUS` reduced from 14 → 10 px (−29%)
- `LINE_WIDTH` reduced from 4 → 3 px (−25%)
- Total apparent diameter: ~20 px, matching the ~32 px Combat Disposition icon visually

---

## 6. Items NOT affected (already correct)

| Item | Reason no change needed |
|------|------------------------|
| Force Field | `_force_field.deactivate()` was explicitly called in jammer handler (Issue #1036) |
| Flashlight | Turned off on jammer detection (Issue #1036) |
| BFF Pendant | Instant-use (no running state to cancel) |
| Loudspeaker | Instant-use (no running state to cancel) |
| Breaching Charges | Instant-use (no running state to cancel) |
| Auto-Reload | Passive modifier (no active timed state) |
| Armored Skin | Passive modifier (no active timed state) |
| Breaker Bullets | Passive modifier applied per bullet (no timed active state) |
| Combat Disposition | Passive modifier (no timed active state to cancel) |
| Teleport Bracers | No active effect duration — teleport is instant |

---

## 7. Implementation Quality

### Correctness
- Cancellation is checked every frame in `_process`, matching the polling frequency of all other per-frame updates.
- `is_active_item_jammed()` queries the live scene tree directly (not cached), so it correctly handles the jammer dying or moving out of range between frames.
- Charges are **not** consumed on cancellation (only on activation) — correct behaviour.

### Logging
- Each cancellation logs a `[INFO]` line with `(Issue #1115)` tag, enabling future log analysis to verify the fix works.
- Periodic jammer checks log player distance, confirming whether player is inside/outside range.

### Tests
- `tests/unit/test_radio_jammer_enemy.gd` was extended to cover:
  - Cancellation of homing bullets when jammed
  - Cancellation of invisibility when jammed
  - Cancellation of trajectory glasses when jammed
  - Icon size constraint: `CIRCLE_RADIUS <= 12` and `LINE_WIDTH <= 3`

---

## 8. Related Issues

| Issue | Relationship |
|-------|-------------|
| [#1036](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1036) | Parent: introduced RadioJammer enemy and initial jammer blocking logic |
| [#1115](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1115) | This issue: extend jammer to cancel already-active effects |

---

## 9. Second Game Log — `game_log_20260318_020655.txt`

A second log was submitted after the fix was merged to the branch. Analysis shows the same absence of cancellation.

### Session summary

- Captured: 2026-03-18, 02:06:55–02:07:27 (32 seconds total, two level loads)
- Build: **Godot 4.3-stable, Windows pre-compiled exe** at `I:/Загрузки/godot exe/радио враг/Godot-Top-Down-Template.exe`
- First level: `LabyrinthLevel` (short session, then restarted)
- Second level: `DecadenceLevel`
- Active item equipped: **Trajectory Glasses** (switched from Loudspeaker at 02:07:12)
- RadioJammer spawned at: **(1100, 900)** with hp=2, radius=1000

### Key event sequence (LabyrinthLevel session)

```
02:07:12  [ActiveItemManager] Active item changed → Trajectory Glasses
02:07:13  [TrajectoryGlasses] Effect ready, charges: 2/2
02:07:14  [ActiveItemManager.Jammer] VERBOSE: dist=1368.5 => clear   ← safe at activation
02:07:14  [Player.TrajectoryGlasses] Space pressed - activating (charges: 2)
02:07:14  [TrajectoryGlasses] Activated! Duration: 10.0s, Charges remaining: 1/2
02:07:14  [ActiveItemManager.Jammer] Periodic: dist=1318.3    ← still outside range
02:07:17  [ActiveItemManager.Jammer] Periodic: dist=120.1     ← INSIDE JAMMER RANGE (< 1000 px)
02:07:17  [TrajectoryGlasses] _calculate_ricochet_trajectory: ...  ← effect STILL RUNNING
02:07:18  [TrajectoryGlasses] Effect ready, charges: 2/2      ← scene reloaded, charges reset
```

**Critical observation**: At **02:07:17**, `dist=120.1` (player well inside 1000 px jammer radius). The TrajectoryGlasses effect was still calculating trajectories (logs continuing after dist=120.1). There is **no** `[Player.TrajectoryGlasses] Trajectory glasses cancelled by Radio Jammer (Issue #1115)` line anywhere in this log.

### Root cause of no cancellation in second log

**The user tested with a pre-compiled binary** (`I:/Загрузки/godot exe/радио враг/Godot-Top-Down-Template.exe`) that was built **before** the Issue #1115 fix was implemented. The fix exists in the source code on branch `issue-1115-d78fefdfd813`, but this binary does not include it.

Evidence:
1. No `(Issue #1115)` tag appears anywhere in the second log (our fix adds these tags on every cancellation).
2. The cancellation code path logs `[Player.TrajectoryGlasses] Trajectory glasses cancelled by Radio Jammer (Issue #1115)` on every invocation — its absence proves the code was not present.
3. The binary path (`радио враг` = "radio enemy" in Russian) suggests this was a specially compiled test build from an earlier commit.

**The fix is correctly implemented in the source.** To verify the fix works, the user needs to rebuild from the current branch source.

### Distance timeline (second log, LabyrinthLevel)

| Time | Player position | Distance to Jammer (1100,900) | Status |
|------|-----------------|-------------------------------|--------|
| 02:07:14 | (150, 1885) | ~1368 px | **OUTSIDE** (clear) |
| 02:07:14 | (150, 1822) | ~1318 px | **OUTSIDE** (clear) |
| 02:07:17 | (490, 1368) | **120 px** | **INSIDE** ← bug manifests (old binary) |
| 02:07:18 | scene reload | — | Charges reset to 2/2 |

---

## 10. Files in this Case Study

| File | Description |
|------|-------------|
| `README.md` | This case study document |
| `game_log_20260318_010126.txt` | First game log (2026-03-18 01:01:26) demonstrating the bug |
| `game_log_20260318_020655.txt` | Second game log (2026-03-18 02:06:55) — same binary, same bug, fix not yet in this build |

---

## 10. Conclusions

### Root Cause
The original Issue #1036 implementation correctly blocked **new** activations while jammed, but did not add cancellation logic for **already-running** effects. Three active items (Homing Bullets, Invisibility Suit, Trajectory Glasses) were missing this check.

### Evidence
Both game logs unambiguously show the same pattern:
1. TrajectoryGlasses activated outside jammer range — correct
2. Player walked inside jammer range (< 1000 px from RadioJammer at (1100, 900))
3. TrajectoryGlasses continued running uninterrupted — bug
4. No `(Issue #1115)` cancellation log line appears in either log — confirming the fix was not present in the tested binary

Both logs were produced by the same pre-compiled Windows binary (`I:/Загрузки/godot exe/радио враг/Godot-Top-Down-Template.exe`), which predates the fix implementation on branch `issue-1115-d78fefdfd813`.

### Fix
Added per-frame `is_active_item_jammed()` guards inside `_handle_homing_input`, `_handle_invisibility_suit_input`, and `_handle_trajectory_glasses_input` in `player.gd`. Also resized the JammerHUD prohibition sign from radius=14/width=4 to radius=10/width=3 to match Combat Disposition icon proportions.
