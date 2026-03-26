# Case Study: Issue #1524 — M16 Sound Range Set to 840px

## Summary

**Issue:** Set the M16 sound range to 840px
**Reporter:** Jhon-Crow
**PR:** #1525
**Date analyzed:** 2026-03-26

---

## 1. Problem Statement

The original issue requested:
> "сделай чтоб дальность звука m16 была 840px"
> ("Make the M16 sound range be 840px")

After the first solution draft was submitted (PR #1525), the user reported:
> "судя по визуализации и поведению врагов изменения не сработали"
> ("Based on visualization and enemy behavior, changes didn't work")

and provided a game log: `game_log_20260326_080756.txt`

---

## 2. Evidence: Game Log Analysis

**File:** `game_log_20260326_080756.txt`
**Session:** 2026-03-26T08:07:56 – 08:10:xx
**Binary:** `I:/Загрузки/godot exe/микро фиксы/Godot-Top-Down-Template.exe` (Windows)
**Engine:** Godot 4.3-stable (official), release build

### Key observations from the log

#### M16 gunshot propagation range = 1469px (not 840px)

All player M16 shots logged with `range=1469`:

```
[08:08:16] [SoundPropagation] Sound emitted: type=GUNSHOT, pos=(450, 1250), source=PLAYER (AssaultRifle), range=1469, listeners=10
[08:08:18] [SoundPropagation] Sound emitted: type=GUNSHOT, pos=(450, 1250), source=PLAYER (AssaultRifle), range=1469, listeners=10
[08:08:21] [SoundPropagation] Sound emitted: type=GUNSHOT, pos=(297.6148, 1140.318), source=PLAYER (AssaultRifle), range=1469, listeners=10
[08:08:24] [SoundPropagation] Sound emitted: type=GUNSHOT, pos=(450, 1250), source=PLAYER (AssaultRifle), range=1469, listeners=10
```

Total M16 shots by player: **21** — all at range=1469.
Enemy rifle shots: `range=800`.

#### Why 1469?

`1469 ≈ VIEWPORT_DIAGONAL = 1468.6 = sqrt(1280² + 720²)` — the old default `weapon_loudness` from before Issue #1269 was fixed.

---

## 3. Root Cause Analysis

### Timeline of events

| Commit | Change | Effect |
|--------|--------|--------|
| Before #1269 | `weapon_loudness = 1469.0` (= viewport diagonal) | M16 alerted enemies within the entire screen |
| PR #1270 (fix #1269) | `weapon_loudness = 800.0` | M16 sound range reduced to PM baseline |
| PR #1525 v1 (fix #1524) | Added `M16_MAX_DISTANCE = 840.0` to `audio_manager.gd` only | **Audio playback** range changed, enemy detection range unchanged |

### Two separate systems

The codebase has **two independent sound systems** with different purposes:

1. **AudioManager** (`scripts/autoload/audio_manager.gd`)
   Controls the **audio playback** max_distance — how far the player *hears* the gunshot sound effect (via `AudioStreamPlayer2D.max_distance`).

2. **SoundPropagation** (`scripts/autoload/sound_propagation.gd`)
   Controls **enemy alerting** — how far enemies detect and react to gunshots. Uses `weapon_loudness` variable passed to `emit_sound()`.

### First fix's scope

PR #1525 v1 only changed `audio_manager.gd`:
- Added `M16_MAX_DISTANCE = 840.0` constant
- Passed it to `AudioStreamPlayer2D.max_distance` for M16 shots

This changed how far players *hear* the M16, but **did not change enemy detection range**.

### Why the test binary showed range=1469

The user's game executable was compiled from code **before Issue #1269 was fixed** (pre-PR #1270), which had `weapon_loudness = 1469.0` in `player.gd`. The PR #1525 changes were not included in that binary. This means the test did not actually test our changes at all.

### Missing fix

The enemy detection range for M16 (player) is controlled by:
- `scripts/characters/player.gd` line 35: `@export var weapon_loudness: float = 800.0`

The enemy M16 (RIFLE type 0) range is controlled by:
- `scripts/components/weapon_config_component.gd` line 22: `"weapon_loudness": 800.0`

Neither was updated in the first fix.

---

## 4. Fix Applied

### Files changed

**`scripts/characters/player.gd`** (line 35):
```gdscript
# Before:
@export var weapon_loudness: float = 800.0

# After:
@export var weapon_loudness: float = 840.0  # Issue #1524
```

**`scripts/components/weapon_config_component.gd`** (type 0 / RIFLE / M16):
```gdscript
# Before:
"weapon_loudness": 800.0,

# After:
"weapon_loudness": 840.0,  # Issue #1524: M16 sound range set to 840px
```

**`scripts/autoload/audio_manager.gd`** (already done in v1):
```gdscript
const M16_MAX_DISTANCE: float = 840.0
# applied to play_m16_shot, play_m16_double_shot, play_m16_bolt
```

### Expected log after fix

After rebuilding with the fixed code, the log should show:
```
Sound emitted: type=GUNSHOT, source=PLAYER (AssaultRifle), range=840
```

---

## 5. Verification Plan

To verify the fix works:
1. Build the game from the current branch code
2. Equip M16, fire shots
3. Check game log for `source=PLAYER (AssaultRifle), range=840`
4. Confirm enemies only react to shots within 840px radius (not 1469px)

---

## 6. References

- Issue #1524: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1524
- PR #1525: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1525
- Related Issue #1269 (original sound range reduction): PR #1270
- `sound_propagation.gd`: `VIEWPORT_DIAGONAL = 1468.6` (origin of the 1469 value)
