# Case Study: Issue #1549 — PKM Machine Gun Sound Range Not Fixed

## Overview

**Issue:** The machine gun enemy (PKM) sound range was not updated to 2400px as required.
**Reporter:** Jhon-Crow
**Date reported:** 2026-03-26
**Status:** Incomplete fix — first PR addressed only audio playback distance, missed sound propagation range.

---

## Timeline / Sequence of Events

| Time | Event |
|------|-------|
| Issue #1033 merged | PKM (MACHINE_GUN, type 6) enemy introduced. `weapon_loudness` set to `1198.1` in `weapon_config_component.gd`. |
| Issue #1524 merged | M16 sound range fixed — `M16_MAX_DISTANCE = 840.0` added to `audio_manager.gd`. Pattern established. |
| Issue #1549 opened | Owner reports PKM sound range must be 2400px. |
| PR #1554 first session | Fix adds `AK_MAX_DISTANCE = 2400.0` to `audio_manager.gd` and passes it to `play_ak_shot()`. Only the `AudioStreamPlayer2D.max_distance` is corrected. The `weapon_loudness` in `weapon_config_component.gd` remains at `1198.1`. |
| 2026-03-26 12:45 | Owner tests the build. Game log shows `range=1198` for MachineGunner shots. Owner comments "не изменилось" ("didn't change"). |

---

## Architecture: Two Independent Sound Systems

The codebase has **two independent systems** that both need to be set correctly for the PKM sound range fix:

### System 1: AudioStreamPlayer2D max_distance (what the player hears)
- Location: `scripts/autoload/audio_manager.gd`
- Controlled by: `AK_MAX_DISTANCE` constant → passed to `play_random_sound_2d_with_priority()`
- Effect: Sets the `max_distance` on Godot's `AudioStreamPlayer2D` node
- Determines: **How far away the player can hear the PKM shot audio**
- Status: **Already fixed** in first PR — `AK_MAX_DISTANCE = 2400.0`

### System 2: SoundPropagation range (what enemy AI "hears")
- Location: `scripts/components/weapon_config_component.gd`
- Controlled by: `weapon_loudness` key in `WEAPON_CONFIGS[6]`
- Effect: Passed as `custom_range` to `sound_propagation.emit_sound()`
- Determines: **How far away other enemies are alerted** by the PKM shot
- Status: **NOT fixed** — still `1198.1` instead of `2400.0`

---

## Evidence from Game Log

```
[12:45:38] [INFO] [SoundPropagation] Sound emitted: type=GUNSHOT, pos=(3000, 2200),
  source=ENEMY (BottomRight_MachineGunner), range=1198, listeners=5
[12:45:38] [INFO] [SoundPropagation] Sound result: notified=0, out_of_range=4, self=1
```

- The range is **1198** — matching `weapon_loudness: 1198.1` in `weapon_config_component.gd`
- All 4 other listeners are marked `out_of_range` because the machine gunner is at (3000, 2200) and the player is at (354–665, 2350) — distance ~2400px, which exceeds the 1198px propagation range
- If `weapon_loudness` were `2400.0`, the sound propagation would cover that distance and notify the other enemies

---

## Root Cause

The first PR fix was **incomplete**. It correctly fixed `audio_manager.gd` (audio playback distance), but **missed** `weapon_config_component.gd` (sound propagation / enemy alert range).

The issue description says "дальность звука пулемёта должна быть 2400px" (machine gun *sound range* should be 2400px). "Sound range" in the context of this game refers to both:
1. How far the player can hear the sound (AudioStreamPlayer2D max_distance)
2. How far the SoundPropagation system alerts enemies (weapon_loudness in WeaponConfigComponent)

Both need to be 2400px.

---

## Code Locations

| File | Line | Current Value | Required Value |
|------|------|---------------|----------------|
| `scripts/autoload/audio_manager.gd` | 160 | `AK_MAX_DISTANCE: float = 2400.0` | ✅ Already correct |
| `scripts/components/weapon_config_component.gd` | 163 | `"weapon_loudness": 1198.1` | ❌ Must be `2400.0` |

---

## Fix

Change `weapon_loudness` for the MACHINE_GUN (type 6) in `weapon_config_component.gd`:

```gdscript
# Before:
"weapon_loudness": 1198.1,

# After:
"weapon_loudness": 2400.0,  # Issue #1549: PKM sound range set to 2400px
```

---

## Verification

After the fix, the game log should show:
```
[SoundPropagation] Sound emitted: type=GUNSHOT, source=ENEMY (MachineGunner), range=2400, ...
```

---

## Files

- `game_log_20260326_124500.txt` — game log showing `range=1198` for PKM shots (proves the bug)
