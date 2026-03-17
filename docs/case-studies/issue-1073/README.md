# Case Study: Issue #1073 — Recoil Compensator Active Item

## Issue Summary

**Title:** добавить активный предмет компенсатор отдачи
**Reporter:** Jhon-Crow (owner)
**URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1073

### Requirements
- 15-second charge, depletes at 1 s/s while Space is held
- Unlimited activations while charge lasts
- When active: eliminates weapon spread (random) and screen-shake recoil completely
- Fire rate +10% boost while active
- Progress bar shows remaining charge above player when active

---

## Timeline / Sequence of Events

### 2026-03-16 — Initial Implementation (PR #1074)

The Recoil Compensator was implemented as `ActiveItemType` enum index **10** (directly after `LASER_SIGHT`). At this point the main branch had 10 items (indices 0–9).

**Files changed:**
- `scripts/autoload/active_item_manager.gd` — added enum value, data, `has_recoil_compensator()`
- `scripts/characters/player.gd` — `_init_recoil_compensator()`, `_handle_recoil_compensator_input()`, spread/shake suppression, fire rate boost
- `tests/unit/test_recoil_compensator.gd` — 60 unit tests
- `tests/unit/test_active_item_manager.gd` — updated mock

CI passed. PR marked "Ready to merge."

### 2026-03-16 to 2026-03-17 — Main branch diverges

Between the PR branch creation and the owner's test, **4 new active items** were merged into main:

| Type Index | Item | Issue |
|---|---|---|
| 10 | LOUDSPEAKER | #959 |
| 11 | BREACHING_CHARGES | #1043 |
| 12 | ARMORED_SKIN | #1045 |
| 13 | AUTO_RELOAD | #1067 |

The branch was **not rebased or merged** with these additions.

### 2026-03-17 21:42 — Owner tests the PR build

The owner ran a game export that included the `active_item_manager.gd` changes (RECOIL_COMPENSATOR as type 10) but also had saved state from a newer build.

**Evidence from `game_log_20260317_214250.txt`:**

```
[21:42:50] [INFO] [PersistManager] Restored unlocked active item type: 10
[21:42:50] [INFO] [ActiveItemManager] Invalid active item type: 14
[21:42:50] [INFO] [PersistManager] Restored selected active item type: 14
```

The user's saved game had selected active item **type 14** (which would be RECOIL_COMPENSATOR in the fully-merged state), but the build only knew types 0–10, making type 14 invalid. The game loaded with `None` selected instead.

### Root Cause #1: Enum Index Conflict

The PR added RECOIL_COMPENSATOR at index 10, but main added 4 other items first. The correct index should be **14** (after AUTO_RELOAD). The branch was never rebased onto main.

### 2026-03-17 — Player init missing RecoilCompensator log

After the user selected Recoil Compensator from the Armory and the level restarted:

```
[21:43:02] [INFO] [Player.Flashlight] No flashlight selected in ActiveItemManager
[21:43:02] [INFO] [Player.TeleportBracers] No teleport bracers selected in ActiveItemManager
...
[21:43:02] [INFO] [Player.TrajectoryGlasses] No trajectory glasses selected in ActiveItemManager
[21:43:02] [INFO] [Player] Ready! ...
```

**No `[Player.RecoilCompensator]` log appeared.** This means the `player.gd` changes were not present in the exported build, OR the restarted level picked up a stale active item state. Since the `active_item_manager.gd` changes ARE present (the item appears in the Armory), the likely cause is an **outdated game export** that includes only partial changes.

### Root Cause #2: Missing Icon

Screenshot `screenshot_armory_missing_icon.png` shows the Recoil Compensator with a **question mark** instead of an icon. The referenced asset `res://assets/sprites/weapons/recoil_compensator_icon.png` does not exist in the repository.

---

## Root Causes

1. **Wrong enum index**: RECOIL_COMPENSATOR was added as index 10 on a branch that diverged from main before 4 other items (LOUDSPEAKER=10, BREACHING_CHARGES=11, ARMORED_SKIN=12, AUTO_RELOAD=13) were merged. The correct index is **14**.

2. **Missing icon asset**: `recoil_compensator_icon.png` was never created, causing a question mark in the Armory UI.

3. **Branch not merged with main**: The PR branch was behind `origin/main` by many commits, causing merge conflicts and enum misalignment. The `player.gd` changes may not be present in the version the user tested.

---

## Proposed Solution

1. Merge `origin/main` into the branch and resolve all conflicts.
2. Move `RECOIL_COMPENSATOR` to after `AUTO_RELOAD` (index 14) in the enum.
3. Create `recoil_compensator_icon.png` programmatically.
4. Update all tests to use the new index.
5. Verify all init/handle/suppress calls are in `player.gd` after merge.

---

## Artifacts

- `game_log_20260317_214250.txt` — owner's game session log showing the bugs
- `screenshot_armory_missing_icon.png` — screenshot showing missing icon in Armory

---

## Second Incident — 2026-03-17 23:57 (PR comment)

### Owner Feedback

> предмет не работает при зажатом пробела (возможно сломал отдачу m16)
> ("Item doesn't work when Space is held; may have broken M16 recoil")

Two new game logs were provided:
- `game_log_20260317_235743.txt` — session with Loudspeaker first, then switching to Recoil Compensator
- `game_log_20260317_235852.txt` — session directly with Recoil Compensator selected

### Root Cause Analysis

#### Root Cause #3: Implementation in Wrong Script (C# vs GDScript)

The recoil compensator was implemented in `scripts/characters/player.gd` (GDScript), but **all game levels use `scenes/characters/csharp/Player.tscn`** which attaches `Scripts/Characters/Player.cs` (C#). The GDScript player (`scenes/characters/Player.tscn`) is never instantiated in any level.

**Evidence from `game_log_20260317_235852.txt`:**

```
[23:58:52] [INFO] [ActiveItemManager] Active item changed from None to Recoil Compensator
[23:58:52] [INFO] [Player.Loudspeaker] Checking loudspeaker...
[23:58:52] [INFO] [Player.Loudspeaker] No loudspeaker selected in ActiveItemManager
[23:58:52] [INFO] [Player.AutoReload] Auto-reload not selected in ActiveItemManager
[23:58:52] [INFO] [Player] Ready! Ammo: 30/30, Grenades: 1/3, Health: 2/4
```

After `AutoReload` init, there is **no `[Player.RecoilCompensator]` log at all** — the C# player has no recoil compensator code, so it never initializes it. Even though the `active_item_manager.gd` (GDScript autoload) correctly registered RECOIL_COMPENSATOR at index 14 and selected it, the C# Player had no handler.

The log also showed `AKGL already equipped by C# Player` and `C# autoload - verified OK`, confirming the C# player path is used.

**Level scene file check:**
```
scenes/levels/LabyrinthLevel.tscn → scenes/characters/csharp/Player.tscn → Scripts/Characters/Player.cs
```
All 10 game levels reference `scenes/characters/csharp/Player.tscn`.

#### Why M16 Recoil Appeared Broken

The GDScript `player.gd` was modified to suppress M16 spread in `_get_current_spread()` and shake in `_trigger_screen_shake()`. However, since the GDScript player is never used in actual gameplay, this had no effect on M16. The M16 recoil was always fine — the owner may have been testing with the compensator selected but noticed spread wasn't suppressed, and mistakenly attributed it to a regression.

### Fix Applied

Implemented the recoil compensator fully in the C# Player (`Scripts/Characters/Player.cs`):

1. **`InitRecoilCompensator()`** — called from `_Ready()` after `InitAutoReload()`. Checks `ActiveItemManager.has_recoil_compensator()` and sets `_recoilCompensatorEquipped = true`, `_recoilCompensatorCharge = 15.0`.

2. **`HandleRecoilCompensatorInput(delta)`** — called from `_PhysicsProcess()`. Checks `Input.IsActionPressed("flashlight_toggle")`, depletes charge, sets `_recoilCompensatorActive`, logs activation/deactivation.

3. **`IsRecoilCompensatorActive()`** — public method called by weapon scripts to check if spread/shake should be suppressed.

4. **Fire rate boost** — calls `CurrentWeapon.AccelerateFireTimer(delta * 0.1f)` each frame while active, giving a 10% fire rate boost by advancing the fire cooldown timer 10% faster.

5. **Progress bar** — `DrawRecoilCompensatorBar()` in `_Draw()`, renders a continuous amber/orange bar above the player while active or after partial depletion.

6. **`AccelerateFireTimer(float extraDelta)`** added to `BaseWeapon.cs` (the shared base class for all weapons).

7. **All 8 weapon scripts updated** to call `IsRecoilCompensatorActive()` from the parent Player in both `ApplySpread()` and `TriggerScreenShake()`:
   - `AssaultRifle.cs` (M16)
   - `AKGL.cs`
   - `MakarovPM.cs`
   - `MiniUzi.cs`
   - `SilencedPistol.cs`
   - `Revolver.cs`
   - `Shotgun.cs`
   - `SniperRifle.cs`

---

## Third Incident — 2026-03-17 22:05 (PR conflict)

### Owner Feedback

> разреши конфликт.
> ("Resolve the conflict.")

After the C# fix was merged, a new upstream PR (#1058 — Drilling Bullets, Issue #751) was merged into main, introducing another `ActiveItemType` enum collision:

| Commit | Change |
|---|---|
| Our PR | `RECOIL_COMPENSATOR = 14` (after AUTO_RELOAD=13) |
| upstream/main | `DRILLING_BULLETS = 14` (after AUTO_RELOAD=13) |

Both items claimed index 14.

### Root Cause #4: Enum Index Collision with DRILLING_BULLETS

`DRILLING_BULLETS` (Issue #751) was merged into main and claimed index 14, the same slot our RECOIL_COMPENSATOR occupied.

### Fix Applied (2026-03-17)

1. Merged `upstream/main` into the branch.
2. Resolved all 4 conflicted files:
   - `scripts/autoload/active_item_manager.gd`
   - `scripts/characters/player.gd`
   - `Scripts/Characters/Player.cs`
   - `tests/unit/test_active_item_manager.gd`
3. Final enum ordering:
   - `DRILLING_BULLETS = 14` (Issue #751 — from upstream)
   - `RECOIL_COMPENSATOR = 15` (Issue #1073 — our addition)
   - `COMBAT_DISPOSITION = 16` (Issue #1047)
4. All tests and mocks updated to use new indices.

### Root Cause #5: Missing Jammer Block in Recoil Compensator

While reviewing the code, a secondary bug was found: `HandleRecoilCompensatorInput()` was missing the Radio Jammer blocking check (Issue #1036) that ALL other hold-Space active items have. When a Radio Jammer enemy was in range, the recoil compensator would still activate despite being jammed.

**Fix:** Added `IsActiveItemJammedSilent()` check inside the `Input.IsActionPressed("flashlight_toggle")` branch, consistent with other hold-Space items (Flashlight, TeleportBracers, ForceField).

---

## Artifacts

- `game_log_20260317_214250.txt` — owner's game session log showing the bugs (Session 1)
- `screenshot_armory_missing_icon.png` — screenshot showing missing icon in Armory
- `game_log_20260317_235743.txt` — owner's game session log (Session 2 — Loudspeaker then RC)
- `game_log_20260317_235852.txt` — owner's game session log (Session 3 — RC directly selected)
