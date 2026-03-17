# Case Study: Issue #959 — Loudspeaker Active Item

## Summary

**Issue:** Add a Loudspeaker active item to the game that emits a sound cone and can pacify enemies.

**Reported Problems (PR comment, 2026-03-17):**
1. Item doesn't work — no effect when activated (after icon fix)
2. Merge conflicts still present in PR
3. *(Previously fixed: icon missing, weapon swap visual)*

**Log Files:**
- `game_log_20260317_011120.txt` — first report (no icon, item not working)
- `game_log_20260317_050705.txt` — second report (icon good, item still not working, conflicts)

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

### Root Cause 1: Loudspeaker code added to wrong player script (GDScript vs C#)

**This is the critical root cause reported in game log `game_log_20260317_050705.txt`.**

The project has **two** player scripts:
- `Scripts/Characters/Player.cs` — the **actual** C# player used at runtime
- `scripts/characters/player.gd` — a GDScript file that is NOT the active player

All other active items (Flashlight, TrajectoryGlasses, ForceField, BreachingCharges, etc.) are implemented in **C# `Player.cs`**, not in GDScript. The initial loudspeaker implementation mistakenly added the code only to `player.gd`.

**Evidence from `game_log_20260317_050705.txt`:**
```
[05:07:05] [ActiveItemManager] Active item changed from None to Loudspeaker
...
[05:07:05] [Player.Flashlight] No flashlight selected in ActiveItemManager
[05:07:05] [Player.TeleportBracers] No teleport bracers selected in ActiveItemManager
[05:07:05] [Player.Homing] No homing bullets selected in ActiveItemManager
...
[05:07:05] [Player] Ready! Ammo: 30/30, Grenades: 1/3, Health: 2/4
```
Loudspeaker IS selected (line 97), but `[Player.Loudspeaker]` is **never logged** — because the GDScript code never runs. The C# Player.cs is the one executing `_Ready()`.

This is confirmed by:
```
[LabyrinthLevel] AssaultRifle already equipped by C# Player - skipping GDScript weapon swap
```
The level script explicitly acknowledges that the C# player is the active one.

### Root Cause 2: Merge conflicts kept PR behind main

The PR branch was 65+ commits behind `origin/main`, causing merge conflicts. The dirty merge state made GitHub show conflicts in the PR, blocking review.

### Root Cause 3: Missing loudspeaker_icon.png asset (previously fixed)

The `active_item_manager.gd` references `res://assets/sprites/weapons/loudspeaker_icon.png` but the file was missing. **Fixed in previous session** (2026-03-16).

### Root Cause 4: RICOCHET_POINTS enum conflict (previously fixed)

After merging `main`, enum indices shifted due to `RICOCHET_POINTS` removal. **Fixed in previous session**.

---

## Solutions Implemented

### Fix 1 (2026-03-17): Add Loudspeaker to C# Player.cs — ROOT CAUSE FIX

Added complete loudspeaker implementation to `Scripts/Characters/Player.cs`:

**Member variables** (`#region Loudspeaker System`):
- `_loudspeakerEquipped`: whether item is active
- `_loudspeakerConeEffect`: `Node2D?` reference to GDScript cone effect
- `_loudspeakerProgress`: `Node?` reference to GDScript progress tracker
- `_loudspeakerHandSprite`: `Sprite2D?` in-hand visual during activation
- `_loudspeakerHoldTimer`: float timer for 0.6s visual duration

**`InitLoudspeaker()`** (called from `_Ready()`):
- Loads `loudspeaker_progress.gd` → creates Node child
- Loads `loudspeaker_cone_effect.gd` → creates Node2D child, calls `initialize(this)`
- Creates `Sprite2D` from `loudspeaker_icon.png`, attaches to `_weaponMount`
- Logs `[Player.Loudspeaker] Loudspeaker equipped, charges: N`

**`HandleLoudspeakerInput(float delta)`** (called from `_PhysicsProcess()`):
- Updates cooldown via `_loudspeakerProgress.Call("update", delta)`
- Manages hold-timer for weapon↔loudspeaker sprite swap
- On `flashlight_toggle` press: checks `can_activate()`, calls `use()`, plays cone, alerts enemies, applies pacifism

**`LoudspeakerApplyEffect()`**:
- 50° half-angle cone check
- Line-of-sight raycast (wall mask = 4)
- Cover-within-500px exception
- Skips attacked enemies, rolls `effectChance`, calls `apply_pacifism(hostilityChance)`

**`LoudspeakerAlertAllEnemies()`**:
- Calls `alert_from_loudspeaker(global_position)` on all enemies in group "enemies"

### Fix 2 (2026-03-17): Merge main into PR branch

Resolved conflicts in:
- `scripts/autoload/active_item_manager.gd`: kept LOUDSPEAKER + BREACHING_CHARGES enum entries
- `scripts/characters/player.gd`: kept both loudspeaker + breaching charges init/handle calls
- `scripts/objects/enemy.gd`: kept PacifistComponent + EnemyForceFieldComponent

### Fix 3 (2026-03-16): Create loudspeaker_icon.png
- Created pixel-art loudspeaker icon (32×32 px) at `assets/sprites/weapons/loudspeaker_icon.png`
- Icon shows a classic megaphone/loudspeaker shape with sound wave arcs

### Fix 4 (2026-03-16): Resolve RICOCHET_POINTS merge conflict
- Removed `RICOCHET_POINTS` from the enum (was removed in main via Issue #1028)
- `LOUDSPEAKER` now occupies index 10 (replacing `RICOCHET_POINTS`)
- Updated unlock conditions to match main branch
- Updated test file to expect LOUDSPEAKER at index 10

### Fix 5 (2026-03-16): Implement loudspeaker-in-hands visual during activation
Added to `scripts/characters/player.gd` (for completeness, though C# is the active player):
- `_loudspeaker_hand_sprite`: Sprite2D created from loudspeaker icon, attached to WeaponMount
- `_loudspeaker_hold_timer`: 0.6 second timer during which loudspeaker is shown
- On activation: hides all other WeaponMount children, shows `_loudspeaker_hand_sprite`
- After 0.6s: restores all weapon children visibility

---

## Technical Details

### Affected Files (2026-03-17 fix)
| File | Change |
|------|--------|
| `Scripts/Characters/Player.cs` | **Add complete loudspeaker implementation** (root cause fix) |
| `scripts/autoload/active_item_manager.gd` | Merge conflict resolved (LOUDSPEAKER + BREACHING_CHARGES) |
| `scripts/characters/player.gd` | Merge conflict resolved (both loudspeaker + breaching charges) |
| `scripts/objects/enemy.gd` | Merge conflict resolved |
| `docs/case-studies/issue-959/game_log_20260317_050705.txt` | New game log added |

### Active Item Enum (current)
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
    LOUDSPEAKER = 10,      # Loudspeaker (Issue #959)
    BREACHING_CHARGES = 11 # Breaching charges (Issue #1043)
}
```

### Loudspeaker Activation Flow (C# Player.cs)
1. `InitLoudspeaker()` called in `_Ready()`:
   - Loads `loudspeaker_progress.gd` and `loudspeaker_cone_effect.gd` as GDScript nodes
   - Creates in-hand sprite from `loudspeaker_icon.png`, attaches to WeaponMount
   - Logs `[Player.Loudspeaker] Loudspeaker equipped, charges: N`
2. `HandleLoudspeakerInput(delta)` called each `_PhysicsProcess()`:
   - Updates cooldown timer via GDScript progress tracker
   - On Space press: checks `can_activate()`, calls `use()`, gets aim direction
   - Hides weapon, shows loudspeaker sprite for 0.6s
   - Plays cone visual, alerts all enemies, applies pacifism to cone sector
   - Logs `[Player.Loudspeaker] Activated!`

---

## Key Observations from Game Logs

### game_log_20260317_050705.txt (second report)
- Loudspeaker selected at startup: `[ActiveItemManager] Active item changed from None to Loudspeaker`
- Player.Ready() shows ALL other item checks but NO `[Player.Loudspeaker]` line
- User switches to Laser Sight then back to Loudspeaker — still no loudspeaker initialization
- Gameplay continues with loudspeaker "selected" but completely non-functional
- `[LabyrinthLevel] AssaultRifle already equipped by C# Player` — confirms C# player is active
- **The game is using `Scripts/Characters/Player.cs`, NOT `scripts/characters/player.gd`**

### Diagnostic: Why the error was missed previously
The previous analysis assumed Godot EXE builds embed scripts (making GDScript unrunnable in old builds). In reality, Godot 4 EXE exports **do** embed `.gd` scripts. The real reason `_init_loudspeaker()` never runs is that `Player.cs` is the active player, and Player.cs never had loudspeaker code at all.

---

## Third Report (2026-03-17 05:56) — Item still not working after C# fix

**User feedback:** After the C# Player.cs fix, the item is still not working. New log: `game_log_20260317_055627.txt`.

### Root Cause 5: `loudspeaker_progress.gd` extends `RefCounted` instead of `Node`

**Evidence from `game_log_20260317_055627.txt`:**
```
[05:56:27] [Player.Loudspeaker] Loudspeaker equipped, charges: 0
[05:56:43] [Player.Loudspeaker] Cannot activate: no charges or cooldown active
```

The C# code now runs (confirming Fix 1 worked — `[Player.Loudspeaker]` lines appear), but `charges_remaining` is always `0`, blocking activation.

**Root cause:** `scripts/components/loudspeaker_progress.gd` declares `extends RefCounted`. In C#, the node is created with `new Node()` and then `.SetScript(progressScript)` is called. You **cannot apply a `RefCounted`-extending script to a `Node` object** — this causes GDScript method calls to return wrong/default values (0 instead of 2 for `get_max_charges()`).

The pattern is the same as `breaching_charges_effect.gd` which correctly `extends Node`. All GDScript components that are dynamically attached to `Node` instances from C# must extend `Node` (or a Node subclass), not `RefCounted`.

**Additionally:** Even after fixing `extends Node`, `reset_for_new_level()` was not called during `InitLoudspeaker()`. The GDScript member variable initializer `var charges_remaining: int = 2` might not be guaranteed to run after `SetScript()`. Explicit `reset_for_new_level()` call was added after `AddChild`.

### Fix 6 (2026-03-17): Change `loudspeaker_progress.gd` to `extends Node`

Changed:
```gdscript
# Before (broken)
extends RefCounted

# After (fixed)
extends Node
```

Also added explicit `reset_for_new_level()` call in `InitLoudspeaker()` in `Scripts/Characters/Player.cs` after `AddChild(_loudspeakerProgress)`.

### Updated Affected Files
| File | Change |
|------|--------|
| `scripts/components/loudspeaker_progress.gd` | **Changed `extends RefCounted` → `extends Node`** (root cause of charges=0) |
| `Scripts/Characters/Player.cs` | Added `reset_for_new_level()` call after AddChild; improved charge logging |
| `docs/case-studies/issue-959/game_log_20260317_055627.txt` | New game log added |

---

## References
- Issue #959: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/959
- PR #1018: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1018
- Issue #1028 (RICOCHET_POINTS removal): referenced in test file
- Game logs: `game_log_20260317_011120.txt`, `game_log_20260317_050705.txt`, `game_log_20260317_055627.txt` (this directory)
