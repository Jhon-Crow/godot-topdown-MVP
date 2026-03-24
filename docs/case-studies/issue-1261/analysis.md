# Case Study: Issue #1261 — Enemies Ignore Sounds (Debug Evidence)

## Overview

**Issue:** Enemies in the sound zone do not react to player sounds (gunshots, reloads, empty clicks).
**Reported:** 2026-03-21
**Severity:** Critical — entire sound-based alerting system is silently broken.
**Status:** Fixed in PR #1262.

---

## Evidence

Game log: `game_log_20260321_083300.txt` (2008 lines, session 08:33:00–08:35:16)

Key log pattern repeated throughout the session:

```
[08:33:06] Sound emitted: type=GUNSHOT, pos=(150, 1000), source=PLAYER (MiniUzi), range=1469, listeners=5
[08:33:06] Sound result: notified=0, out_of_range=2, self=0, below_threshold=3
```

Every single sound event — GUNSHOT (range 1469 px), RELOAD (range 900 px), EMPTY_CLICK (range 600 px), and Revolver (range 2500 px) — produced `notified=0`. The `below_threshold` counter accounted for all in-range enemies.

Most damning entry: Revolver (range 2500 px, all 5 enemies within range, zero notified):

```
[08:35:01] Sound emitted: type=GUNSHOT, pos=(321.9805, 1000), source=PLAYER (Revolver), range=2500, listeners=5
[08:35:01] Sound result: notified=0, out_of_range=0, self=0, below_threshold=5
```

---

## Timeline of Events

| Time     | Event |
|----------|-------|
| 08:33:00 | Game started, LabyrinthLevel loaded, Hard difficulty |
| 08:33:02 | 5 enemies registered as sound listeners |
| 08:33:06 | First MiniUzi shot — 0/5 enemies notified (3 below_threshold, 2 out_of_range) |
| 08:33:17 | More MiniUzi shots — same result |
| 08:33:27 | Reload sound emitted — 0/5 notified (2 below_threshold) |
| 08:34:22 | Switched to AssaultRifle — still 0 notified |
| 08:34:33 | Empty click + Shotgun — still 0 notified |
| 08:35:01 | Revolver fired (range=2500, all enemies in range) — 0/5 notified |
| 08:35:16 | Session ends with player never having alerted a single enemy via sound |

---

## Enemy Positions vs. Player Position

Player spawn: approximately `(150, 1000)` for the first half of the session, then `(322, 856)` after repositioning.

Enemy positions from spawn logs:

| Enemy | Position     | Distance from player (~150, 1000) |
|-------|--------------|-----------------------------------|
| 1     | (400, 300)   | ~743 px                           |
| 2     | (900, 950)   | ~752 px                           |
| 3     | (1200, 1000) | ~1050 px                          |
| 4     | (1650, 650)  | ~1540 px                          |
| 5     | (1500, 300)  | ~1521 px                          |

All enemies were well within the GUNSHOT propagation distance of 1469 px (Enemy 1-3) or Revolver 2500 px (all 5).

---

## Root Cause Analysis

### The Bug

`emit_sound()` in `scripts/autoload/sound_propagation.gd` applied two sequential gates:

1. **Distance gate** — `distance <= propagation_distance` ✓ correct
2. **Intensity gate** — `intensity >= MIN_INTENSITY_THRESHOLD` ✗ the bug

The intensity was computed using an **inverse-square law**:

```gdscript
const REFERENCE_DISTANCE: float = 50.0   # pixels
const MIN_INTENSITY_THRESHOLD: float = 0.01

var intensity := pow(REFERENCE_DISTANCE / distance, 2.0)
# = (50 / distance)²
```

This formula produces:

| Distance | Intensity   | Passes threshold (≥ 0.01)? |
|----------|-------------|---------------------------|
| 50 px    | 1.000       | ✓ Yes                     |
| 100 px   | 0.250       | ✓ Yes                     |
| 250 px   | 0.040       | ✓ Yes                     |
| 353 px   | 0.020       | ✓ Yes (barely)            |
| 500 px   | 0.010       | ✓ Yes (on boundary)       |
| 501 px   | 0.00996     | ✗ **No** — silently dropped |
| 743 px   | 0.0045      | ✗ No (Enemy 1)            |
| 752 px   | 0.0044      | ✗ No (Enemy 2)            |
| 1050 px  | 0.0023      | ✗ No (Enemy 3)            |
| 2500 px  | 0.0004      | ✗ No (all 5 enemies)      |

**All 5 enemies in the Labyrinth level spawn more than 500 px from the player.** Every sound event, regardless of its stated `propagation_distance` (up to 2500 px), was silently discarded by the intensity gate for every enemy.

### Why This Bug Was Silent

The `propagation_distance` parameter correctly defines the audible range and was set appropriately (1469–2500 px for gunshots). But `MIN_INTENSITY_THRESHOLD` independently cut off delivery at ~500 px. There was no warning or error — the log only showed `below_threshold=N`, which requires reading the logs carefully to notice.

### Why REFERENCE_DISTANCE = 50 is Mismatched

`REFERENCE_DISTANCE = 50.0` means "full intensity at 50 pixels." With a viewport diagonal of ~1469 px, this reference point represents only 3.4% of the maximum sound range. The inverse-square formula drops below the threshold at just 34% of the maximum range.

The original intent of `MIN_INTENSITY_THRESHOLD` was described as:
> "Minimum intensity threshold below which sound is not propagated. This prevents computation for very distant, inaudible sounds."

But this rationale is flawed: `propagation_distance` **already** defines the inaudibility boundary. The threshold added a second, tighter cutoff that made "inaudible" mean "anything beyond 500 px," defeating the entire sound system.

---

## Fix Applied

**File changed:** `scripts/autoload/sound_propagation.gd`

The `MIN_INTENSITY_THRESHOLD` gate was removed from the notification delivery path. The distance check (`distance <= propagation_distance`) is now the sole gate for notification delivery. Intensity is still computed via `calculate_intensity()` and forwarded to `on_sound_heard_with_intensity()` so enemies can use it for confidence scaling (closer shots produce higher confidence updates), but it no longer blocks delivery.

**Before:**
```gdscript
if distance <= propagation_distance:
    var intensity := calculate_intensity(distance)
    if intensity >= MIN_INTENSITY_THRESHOLD:  # BUG: silent cutoff at ~500 px
        listener.on_sound_heard_with_intensity(...)
    else:
        listeners_below_threshold += 1
```

**After:**
```gdscript
if distance <= propagation_distance:
    var intensity := calculate_intensity(distance)
    # Intensity gates delivery no longer — only distance does.
    listener.on_sound_heard_with_intensity(...)
```

---

## Sound Visualizer — Wall Attenuation Note

The issue mentions that wall attenuation of sounds might not be accounted for in the visualizer. This is a separate, secondary concern:

- **Current behavior:** `sound_propagation.gd` does **no** line-of-sight or wall-intersection checks. All sounds propagate as full circles regardless of obstacles. The comment in the code explicitly states: "RELOAD, EMPTY_CLICK, and RELOAD_COMPLETE sounds propagate through walls."
- **GUNSHOT** also has no wall check implemented currently — it propagates through walls too (by omission rather than explicit design).
- **Visualizer accuracy:** The `sound_visualizer.gd` draws a full circle at the propagation radius, which correctly represents the current game behavior (no wall blocking).
- **Future improvement:** If wall-blocked sound attenuation is added to `emit_sound()`, the visualizer should be updated to show arc segments blocked by walls (e.g., using raycasts to sample wall intersections and drawing the circle with gaps). This is tracked as a future enhancement, not a bug in the current system.

---

## References

- Game log: `game_log_20260321_083300.txt` (same folder as this analysis)
- Fix commit: `8e07e950` — "fix(#1261): remove MIN_INTENSITY_THRESHOLD gate from sound notification delivery"
- Related issue #1253: Added sound propagation visualizer with ripple waves and boundary ring
- Related issue #969: Throttled CASING_KICK propagation to avoid FPS drops
- Related issue #1145: Throttled EMPTY_CLICK propagation to avoid FPS drops
- Godot inverse-square attenuation docs: https://docs.godotengine.org/en/stable/tutorials/audio/audio_streams.html
