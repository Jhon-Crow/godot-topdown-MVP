# Case Study: Issue #959 — Loudspeaker Active Item

## Summary

**Issue:** Add a Loudspeaker active item to the game that emits a sound cone and can pacify enemies.

**Reported Problems (PR comment, 2026-03-17):**
1. Item doesn't work — no effect when activated
2. Item has no icon in the armory UI
3. Player should hold the loudspeaker instead of their weapon during activation

**Log File:** `game_log_20260317_011120.txt` (provided by reporter)

---

## Timeline Reconstruction

### 2026-03-17 01:11:20 — Game Start
- User launched game from Windows EXE build (older build from before PR was merged)
- Game loaded LabyrinthLevel with Invisibility Suit as active item
- All active item initializations logged normally

### 2026-03-17 01:11:27 — Switch to Loudspeaker
```
[ActiveItemManager] Active item changed from Invisibility to Loudspeaker
```
- User selected Loudspeaker from armory
- Level restarted

### 2026-03-17 01:11:28 — Second Level Load
- All `[Player.*]` initializations are logged (Flashlight, TeleportBracers, Homing, etc.)
- **CRITICAL: No `[Player.Loudspeaker]` log entry exists at all**
- This means `_init_loudspeaker()` was either not called OR was not present in the build

### 2026-03-17 01:11:28 — Gameplay with Loudspeaker Selected
- Player played for ~25 seconds
- **No loudspeaker activation events logged** despite user presumably pressing Space
- `[Player.Loudspeaker]` was never logged → confirms loudspeaker code not in this build

### 2026-03-17 01:11:40 — Level Restart
- Scene reloaded again
- Same pattern: Loudspeaker selected but no initialization log

---

## Root Cause Analysis

### Root Cause 1: Build is older than the PR implementation

The game log shows the user tested a Windows EXE build that was built **before** the loudspeaker implementation was added to the branch. The build does not contain:
- `_init_loudspeaker()` call in `_ready()`
- `_handle_loudspeaker_input()` call in `_physics_process()`
- Loudspeaker progress tracker
- Loudspeaker cone effect

**Evidence:**
- The `[Player.Ready]` log shows initialization in the order: Flashlight, TeleportBracers, Homing, BffPendant, InvisibilitySuit, BreakerBullets, ForceField, TrajectoryGlasses — but NO Loudspeaker check.
- This matches the `_ready()` function from BEFORE the loudspeaker implementation commit `5439be63`.

### Root Cause 2: Missing loudspeaker_icon.png asset

The `active_item_manager.gd` references:
```
"icon_path": "res://assets/sprites/weapons/loudspeaker_icon.png"
```

But this file **did not exist** in the repository. This would cause:
- No icon shown in the armory UI
- Possible error when the armory tries to load the icon texture

**Evidence:** `ls assets/sprites/weapons/` shows no `loudspeaker_icon.png` file.

### Root Cause 3: RICOCHET_POINTS enum conflict

After merging `main`, the `active_item_manager.gd` had merge conflicts because:
- Our branch added `RICOCHET_POINTS` (index 10) and `LOUDSPEAKER` (index 11)
- Main branch removed `RICOCHET_POINTS` (issue #1028: its effect merged into Trajectory Glasses)
- This created conflicts and wrong enum values

### Root Cause 4: Player weapon not swapped to loudspeaker during use

The issue description specifically requests: *"в момент использования у игрока вместо оружия в руках должен быть громкоговоритель"* (during use, player should hold loudspeaker instead of weapon).

This feature was not implemented in the original PR — the loudspeaker activation only showed the cone effect, but the player's visual still showed their weapon.

---

## Solutions Implemented

### Fix 1: Create loudspeaker_icon.png
- Created pixel-art loudspeaker icon (32×32 px) at `assets/sprites/weapons/loudspeaker_icon.png`
- Icon shows a classic megaphone/loudspeaker shape with sound wave arcs

### Fix 2: Resolve RICOCHET_POINTS merge conflict
- Removed `RICOCHET_POINTS` from the enum (was removed in main via Issue #1028)
- `LOUDSPEAKER` now occupies index 10 (replacing `RICOCHET_POINTS`)
- Updated unlock conditions to match main branch (HOMING_BULLETS, TELEPORT_BRACERS, INVISIBILITY_SUIT now locked by default)
- Updated test file to expect LOUDSPEAKER at index 10, not RICOCHET_POINTS

### Fix 3: Implement loudspeaker-in-hands visual during activation
Added to `scripts/characters/player.gd`:
- `_loudspeaker_hand_sprite`: Sprite2D created from loudspeaker icon, attached to WeaponMount
- `_loudspeaker_hold_timer`: 0.6 second timer during which loudspeaker is shown
- On activation: hides all other WeaponMount children, shows `_loudspeaker_hand_sprite`
- After 0.6s: restores all weapon children visibility

---

## Technical Details

### Affected Files
| File | Change |
|------|--------|
| `scripts/autoload/active_item_manager.gd` | Remove RICOCHET_POINTS, fix unlock conditions |
| `scripts/characters/player.gd` | Add loudspeaker-in-hands sprite, hold timer |
| `assets/sprites/weapons/loudspeaker_icon.png` | Created new icon asset |
| `tests/unit/test_active_item_manager.gd` | Update mock data and assertions |

### Active Item Enum (after fix)
```gdscript
enum ActiveItemType {
    NONE = 0,              # No item
    FLASHLIGHT = 1,        # Flashlight
    HOMING_BULLETS = 2,    # Homing bullets (locked)
    TELEPORT_BRACERS = 3,  # Teleport bracers (locked)
    BFF_PENDANT = 4,       # BFF pendant
    INVISIBILITY_SUIT = 5, # Invisibility (locked)
    BREAKER_BULLETS = 6,   # Breaker bullets
    FORCE_FIELD = 7,       # Force field
    TRAJECTORY_GLASSES = 8, # Trajectory glasses
    LASER_SIGHT = 9,       # Laser sight
    LOUDSPEAKER = 10       # Loudspeaker (Issue #959)
}
```

### Loudspeaker Activation Flow
1. Player presses Space
2. Cone visual effect plays (0.55s expansion animation)
3. **NEW:** Weapon hidden, loudspeaker sprite shown in player's hands (0.6s)
4. All enemies on map alerted (hear loud sound)
5. Enemies in cone sector checked for pacifism eligibility
6. After 0.6s: weapon restored, loudspeaker sprite hidden

---

## Key Observations from Game Log

- The build tested was from before the loudspeaker implementation
- `[Player.Loudspeaker]` was never logged in the session
- No errors about missing files in the game log (the missing icon would cause silent failure in UI only)
- Gameplay continued normally with the loudspeaker "selected" but non-functional
- The issue manifested as: item appears in UI, can be selected, but does nothing on Space press

---

## References
- Issue #959: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/959
- PR #1018: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1018
- Issue #1028 (RICOCHET_POINTS removal): referenced in test file
- Game log: `game_log_20260317_011120.txt` (this directory)
