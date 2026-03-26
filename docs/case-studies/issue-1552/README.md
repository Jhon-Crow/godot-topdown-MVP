# Case Study: Issue #1552 — Enemies Still Walk Into Machine Gunner Firing Sector

## Overview

**Issue:** Enemies continue moving through the machine gunner's active suppression zone despite
the avoidance implementation in PR #1555.

**Reported:** 2026-03-26 by @Jhon-Crow
**Game log:** [game_log_20260326_174743.txt](game_log_20260326_174743.txt)
**Platform:** Windows, Godot 4.3-stable, non-debug build
**Level:** LabyrinthLevel (inferred from enemy names: Corridor1Guard, ForkGuardUp, etc.)

---

## Timeline Reconstruction (from game log)

| Timestamp | Event |
|-----------|-------|
| 17:47:43 | Game started, LabyrinthLevel loaded |
| 17:47:44 | Initial enemies spawned (Enemy2, Enemy4, Enemy5 — idle patrol) |
| 17:47:45 | LoadingDock_Machete detects player, enters COMBAT |
| 17:48:07 | Corridor/Room guards (Corridor1Guard, ForkGuardUp, etc.) spawn and scan |
| 17:48:08 | Mass enemy activation: Room2Guard, ForkGuardUp, Corridor2Guard → PURSUING/COMBAT |
| 17:48:11 | Intense multi-enemy combat in corridor area |
| 17:48:35 | **Machine Gunner (PKM) spawned** at (1810.683, 1590.122) via ExperimentalMenu |
| 17:48:37 | Machine Gunner detects player, enters COMBAT, starts suppression |
| 17:48:37 | **First MG corridor suppression shot** fired at passage (1705.684, 1650.909), ammo=499 |
| 17:48:39 | MG re-locks on player last position (1254.273, 1532.912), continuous suppression shots |
| 17:48:39 | **ForkGuardUp** observed at (632.983, 1474.505) — same corridor, actively pursuing player |
| 17:48:39 | ForkGuardUp transitions COMBAT → PURSUING — *no MG zone avoidance triggered* |
| 17:48:41+ | MG continues suppressing corridor at (1254.273, 1532.912), ammo draining rapidly |

**Key observation:** `ForkGuardUp` is at x≈633, the MG suppresses a passage at x≈1254 from x≈1810.
The corridor is approximately 580 px wide. ForkGuardUp is moving toward the MG's line of fire,
yet no `in_mg_firing_zone` log appears anywhere in the 4733-line game log.

---

## Root Cause Analysis

### Root Cause #1 (CRITICAL): GOAP `AvoidMachineGunnerZoneAction` has no `execute()` method

**File:** `scripts/ai/enemy_actions.gd` — `AvoidMachineGunnerZoneAction` class

The action defines `preconditions` and `effects` for the GOAP planner, but the base class
`GOAPAction.execute()` simply returns `true` and does nothing. No behavioral change is triggered.

```gdscript
class AvoidMachineGunnerZoneAction extends GOAPAction:
    func _init() -> void:
        super._init("avoid_mg_firing_zone", 1.5)
        preconditions = {"in_mg_firing_zone": true}
        effects = {"in_mg_firing_zone": false, "is_pursuing": true}
    # NO execute() override — base returns true immediately, nothing happens
```

### Root Cause #2 (CRITICAL): GOAP planner results are never acted upon

**File:** `scripts/objects/enemy.gd`

The `_goap_world_state["in_mg_firing_zone"]` flag is updated every frame (line 968),
but the GOAP planner output is never wired to state machine transitions. There is no
`_execute_goap_action()` or similar call that converts a planned action into an actual
behavioral change.

### Root Cause #3 (HIGH): MG zone check only applies during `PURSUING` cover selection

**File:** `scripts/components/pursuit_component.gd` (lines 143–153)

The `MachineGunnerZoneComponent.is_position_in_any_mg_zone()` penalty is applied only inside
`PursuitComponent.find_cover()`. This method is called only when the enemy is in the PURSUING
state and choosing a cover position.

Enemies in **COMBAT** state stand and fight from their current position — no MG zone check
is performed. An enemy already in the firing sector stays there indefinitely.

### Root Cause #4 (HIGH): No logging for MG zone detection

No `_log_to_file` calls exist for MG zone detection. Without these, it is impossible
to verify whether the zone check runs correctly at runtime.

---

## Evidence from Game Log

- **Zero occurrences** of `MachineGunnerZone`, `in_mg_firing_zone`, `AvoidMachineGunner`
  in the 4733-line game log.
- Machine gunner fires continuously (ammo 499 → 461 in ~5 seconds), yet other enemies
  (`ForkGuardUp`, `RoomBGuard`, `TopRoomGuard`) continue PURSUING/COMBAT states in
  the same corridor without any avoidance behavior.
- `ForkGuardUp` position ~(633, 1474) is on the same axis as the suppression corridor
  (1254, 1533) → (1810, 1590). The cone half-angle of 30° at 700 px should easily
  cover this position.

---

## Proposed Fixes

### Fix 1 — Add MG zone check into `_process_combat_state()` and `_process_pursuing_state()`

When `_mg_zone.in_mg_firing_zone` becomes true during COMBAT or PURSUING,
immediately transition to SEEKING_COVER / RETREATING so the enemy moves out of the sector.

### Fix 2 — Add `execute()` to `AvoidMachineGunnerZoneAction`

Implement `execute()` to call the same `_transition_to_seeking_cover()` method
other retreat-triggering code uses, so the GOAP action actually does something.

### Fix 3 — Add debug logging for MG zone events

Call `_log_to_file("[#1552] in MG firing zone — retreating")` when the zone is
detected, so future game logs can confirm the feature is working.

---

## Files Involved

| File | Role |
|------|------|
| `scripts/components/machine_gunner_zone_component.gd` | Zone geometry detection (correct) |
| `scripts/ai/enemy_actions.gd` | `AvoidMachineGunnerZoneAction` — missing `execute()` |
| `scripts/objects/enemy.gd` | Zone flag updated but never drives state transitions |
| `scripts/components/pursuit_component.gd` | Cover penalty applied (partial fix only) |
