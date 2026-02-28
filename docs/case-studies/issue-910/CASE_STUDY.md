# Case Study: Issue #910 - Enemies Don't Shoot at Invisible Player's Sound/Muzzle Flash

## Issue Summary

**Issue Number:** #910
**Title:** fix враги не выходят из idle когда игрок в Невидимости
**Translation:** Enemies should shoot approximately toward the sound source (in a fan/spread) or at the muzzle flash when the player is invisible.
**Status:** Open
**Author:** Jhon-Crow

### Original Description (Russian)
> когда игрок в Невидимости (активен предмет Невидимость) враги должны стрелять примерно в источник звука (веером) или по вспышке от ствола.

### Translation
> When the player is Invisible (Invisibility item is active), enemies should shoot approximately at the sound source (in a fan pattern) or at the muzzle flash.

### Follow-up Comment (2026-02-24, Russian)
> враги не стреляют по вспышкам игрока (невидимого) даже когда он в их поле зрения и очень близко.

### Translation
> Enemies don't shoot at the player's muzzle flashes (invisible) even when the player is in their field of view and very close.

**Attached game log:** `game_log_20260225_021948.txt`

---

## Timeline of Events (from game_log_20260225_021948.txt)

### Incident 1: Invisible Player Fires in Labyrinth Level (02:20:15–02:20:17)

```
[02:20:15] InvisibilitySuit Activated! Duration: 4.0s, Charges remaining: 1/2
[02:20:15] Player Reset memory for 10 enemies (invisibility activation - Issue #723)
           → All enemy memories wiped, confusion=2.0s

[02:20:16] SoundPropagation: GUNSHOT at (517.6, 743.1), source=PLAYER (AssaultRifle)
           → notified=4, out_of_range=2, below_threshold=4

[02:20:17] Enemy1 Heard gunshot at (561.1, 679.9), intensity=0.01, distance=421
[02:20:17] Enemy2 Heard gunshot at (561.1, 679.9), intensity=0.06, distance=207
[02:20:17] Enemy3 Heard gunshot at (561.1, 679.9), intensity=0.10, distance=156
[02:20:17] Enemy4 Heard gunshot at (561.1, 679.9), intensity=0.02, distance=325

[02:20:17] Enemy1 ROT_CHANGE: P5:idle_scan -> P2:combat_state, state=COMBAT (aimed at player pos)
[02:20:17] Enemy2 ROT_CHANGE: P5:idle_scan -> P2:combat_state, state=COMBAT
[02:20:17] Enemy3 ROT_CHANGE: P5:idle_scan -> P2:combat_state, state=COMBAT
[02:20:17] Enemy4 ROT_CHANGE: P5:idle_scan -> P2:combat_state, state=COMBAT

    ← ENEMIES IN COMBAT STATE, CAN'T SEE INVISIBLE PLAYER, DO NOT FIRE

[02:20:17] Enemy3 State: COMBAT -> RETREATING
[02:20:17] Enemy4 State: COMBAT -> RETREATING -> IN_COVER -> SUPPRESSED
[02:20:17] Enemy1 State: COMBAT -> PURSUING
[02:20:17] Enemy2 State: COMBAT -> PURSUING
```

**Observation**: The log is from a game build **prior to the fix in PR #911**.
After hearing gunshot, all enemies entered COMBAT state and immediately transitioned to RETREATING/PURSUING/SUPPRESSED **without firing a single shot** at the invisible player's known position.

---

## Root Cause Analysis

### Root Cause A: Suppressive Fire Missing from COMBAT State

When the player is invisible and fires, enemies transition IDLE → COMBAT. However, the COMBAT state immediately checks:

```gdscript
# enemy.gd _process_combat_state() line ~1342
if not _can_see_player:
    if _combat_state_timer >= COMBAT_MIN_DURATION_BEFORE_PURSUE:
        _transition_to_pursuing()
        return
    # Just waits (0.5s timeout)
```

The 0.5-second wait does nothing — no suppressive fire is called during this window. After 0.5s, the enemy transitions to PURSUING where suppressive fire was added (PR #911 fix). But:
- There's an unnecessary 0.5s delay before any shooting happens
- If the player stops being invisible before those 0.5s expire, the opportunity is missed

### Root Cause B: Muzzle Flash Not Detected (Primary Missing Feature)

The owner specifically mentions "по вспышкам" (at muzzle flashes) and "в их поле зрения" (in their field of view). This describes a **visual** detection mechanic that is distinct from sound:

1. **Sound detection** (already handled by PR #911): Enemy hears gunshot at sound position → fires toward that position
2. **Muzzle flash detection** (MISSING): Enemy sees bright muzzle flash in FOV at close range → fires directly at player's actual body position

The distinction matters because:
- Sound propagates from `player.global_position` (body center)
- Muzzle flash appears at `player.global_position + shoot_direction * bullet_spawn_offset` (slightly ahead of body)
- The muzzle flash is a **visual event** that reveals the exact player position to enemies with LOS

Currently there is no `MuzzleFlashDetectionComponent` in this codebase (it exists in PR #800 for Issue #754, which is not yet merged).

### Root Cause C: No Suppressive Fire in COMBAT State

Even after PR #911's fix (suppressive fire in PURSUING and IN_COVER), the COMBAT state still doesn't fire at invisible player's position. This means:

1. Player activates invisibility → memory reset (all enemies forget player)
2. Player fires → enemies transition IDLE → COMBAT
3. In COMBAT: no fire (0.5s wait), then PURSUING
4. In PURSUING: suppressive fire NOW works (PR #911 fix)
5. But this 0.5s gap is exploitable

---

## Evidence from Code (enemy.gd)

### Visibility Check (line 3594-3597)
```gdscript
# If player is invisible (invisibility suit active), cannot see player (Issue #673)
if _player.has_method("is_invisible") and _player.is_invisible():
    _continuous_visibility_timer = 0.0
    return  # _can_see_player stays false → no shooting possible from normal shoot code
```

### COMBAT State - Missing Suppressive Fire (line ~1342)
```gdscript
if not _can_see_player:
    if _combat_state_timer >= COMBAT_MIN_DURATION_BEFORE_PURSUE:
        _transition_to_pursuing()
        return
    # Gap: 0-0.5s window where enemy does nothing despite knowing player position
```

### PR #911 Current Integration (PURSUING state)
```gdscript
# line 1949
if _suppressive_fire:
    _suppressive_fire.try_suppress_pursuing(...)  # ← works, but delayed
```

### PR #911 Current Integration (IN_COVER state)
```gdscript
# line 1667
if not _can_see_player and not _under_fire and not (_suppressive_fire and _suppressive_fire.try_suppress_cover(...)):
    _transition_to_pursuing()  # ← works: stays in cover while suppressing
```

---

## Related Issues and PRs

- **Issue #673**: Invisibility Suit implementation (player.gd `is_invisible()`)
- **Issue #723**: Enemy memory reset when player becomes invisible
- **Issue #574**: Flashlight detection component (FlashlightDetectionComponent as pattern)
- **Issue #754 / PR #800**: Muzzle flash detection (MuzzleFlashDetectionComponent - OPEN, not merged)

---

## Solution Design

### Fix 1: Add Suppressive Fire to COMBAT State

In `_process_combat_state()`, after checking `not _can_see_player`, add a call to suppressive fire:

```gdscript
if not _can_see_player:
    # Issue #910: Fire suppressive rounds at invisible player's known position
    if _suppressive_fire:
        _suppressive_fire.try_suppress_pursuing(...)
    if _combat_state_timer >= COMBAT_MIN_DURATION_BEFORE_PURSUE:
        _transition_to_pursuing()
        return
```

### Fix 2: Add MuzzleFlashDetectionComponent for Invisible Player

Create `MuzzleFlashDetectionComponent` (following PR #800 design) that:
1. Tracks active muzzle flashes in `ImpactEffectsManager`
2. Checks if a recent flash is within enemy FOV and has LOS
3. Sets `estimated_player_position` from flash position
4. Updates `_last_known_player_position` when flash detected

Then integrate it to trigger suppressive fire toward the exact flash position — which is more accurate than sound position.

### Fix 3: ImpactEffectsManager Flash Tracking

Add `_active_muzzle_flashes` array to `ImpactEffectsManager`:
- `spawn_muzzle_flash()` records position, direction, timestamp
- `get_active_muzzle_flashes()` returns recent flashes with age

---

## Proposed Solution: Sequence of Events After Fix

```
Player activates invisibility
  → All enemy memories reset (Issue #723)
  → Enemies enter confusion (2s)

Player fires weapon
  → SoundPropagation: GUNSHOT at player.global_position
  → Enemy hears sound → _last_known_player_position = player.global_position
  → Enemy transitions IDLE → COMBAT
  → [NEW Fix 1] COMBAT state: suppressive fire at sound position immediately

  → [NEW Fix 2] Muzzle flash visible at player.global_position + offset
  → Enemy with LOS detects flash → _last_known_player_position = flash-estimated position
  → Enemy in any state fires suppressive fire at accurate flash position

Player fires again while invisible
  → Both sound AND flash update the position
  → Enemy fires fan-shots at player's actual position while player is invisible
```

---

## Test Plan

### Tests for COMBAT state suppressive fire (Fix 1)
1. Invisible player fires → enemy in COMBAT state fires suppressive rounds immediately (not after 0.5s delay)
2. No suppressive fire if player is NOT invisible in COMBAT state

### Tests for MuzzleFlashDetectionComponent (Fix 2)
1. Flash at close range with LOS → detected
2. Flash outside FOV → not detected
3. Flash behind wall (no LOS) → not detected, but ambient glow check still detects
4. Flash too old (>0.35s) → not detected
5. Flash too far (>500px) → not detected
6. Player visible (not invisible) → flash not used (normal combat)
7. Enemy IDLE + flash detected → triggers pursuit

---

## References

- Issue #673: Invisibility Suit (player.gd)
- Issue #723: Memory reset on invisibility
- Issue #574: FlashlightDetectionComponent (pattern for visual detection)
- Issue #754 / PR #800: MuzzleFlashDetectionComponent (parallel feature)
- `SuppressiveFireComponent` (scripts/components/suppressive_fire_component.gd)
