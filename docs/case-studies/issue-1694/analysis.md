# Case Study: Issue #1694 — Teleport Regression After Machete Fix

## Overview

After restoring the machete enemy combat logic (broken in the #1664/#1667 merge), a
regression was discovered: the drone operator enemy and the teleport enemy no longer
teleport when shot at.

**Log file**: `game_log_20260328_175647.txt`
**Build**: Release (Debug build: false), Godot 4.3-stable
**Observed**: 2026-03-28, tester: Jhon-Crow
**Reported**: PR #1702 comment

---

## Timeline of Events

### 1. Original develop branch (before any merge)
- `drone_operator_component.gd` contained a **full dash system**:
  - `DASH_CHARGES = 4`, `DASH_COOLDOWN = 1.2s`, `DASH_DURATION = 0.2s`
  - `should_dash_instead_of_suppress()` — returns true when dash charges available
  - `try_dash_from_threat()` — dashes toward player aggressively
  - `try_dash()`, `_update_dash()`, `_end_dash()`, `_spawn_afterimage()`
- `enemy.gd` (`_update_suppression`) called `_drone_operator.should_dash_instead_of_suppress()`
  before setting `_under_fire`, so drone operators DASH instead of suppress.
- Regular teleport enemies (is_teleporter=true): `_under_fire = true` → cover-teleport fires.

### 2. Merge of Issues #1664 and #1667 to `main`
- The drone operator **dash system was accidentally omitted** from `drone_operator_component.gd`
  when porting to main. The methods `should_dash_instead_of_suppress()`, `try_dash_from_threat()`,
  `try_dash()`, `_update_dash()`, `_end_dash()`, `_spawn_afterimage()`, and all dash state
  variables were left out.
- The `_update_suppression` call in `enemy.gd` that referred to these methods was also dropped,
  so `_under_fire = true` unconditionally for all enemies including drone operators.
- Issue #1664 compensated by adding `_drone_operator.try_teleport()` inside
  `_process_combat_state()` — drone operators now TELEPORT (new feature) instead of DASH (old
  feature). But this only works in COMBAT state.

### 3. PR #1702 — Machete Fix (First Session)
- Restored the missing machete COMBAT logic (melee attack, backstab approach, wall-stuck rerouting).
- However, the previous session also re-added the `should_dash_instead_of_suppress()` call in
  `_update_suppression()`, but did NOT add the actual methods to `drone_operator_component.gd`.
- In **release builds** (Debug build: false), Godot 4 silently swallows calls to non-existent
  methods and returns null. The `if _drone_operator.should_dash_instead_of_suppress()` condition
  evaluates to null/false → falls through to `else: _under_fire = true`.
- So behavior is equivalent to main for release builds, but the code is broken/misleading.

### 4. Teleport Enemy Issue (Root Cause Analysis)
Two separate problems were found:

#### A) Drone operator doesn't teleport from cover/suppressed states
- The teleport code for drone operators is inside `_process_combat_state()` (line 1451).
- When a drone operator is shot while IN_COVER, it transitions to SUPPRESSED → SEEKING_COVER.
- In these states, `_process_combat_state()` is never called.
- Therefore the drone operator teleport at line 1451 never fires for suppressed enemies.
- **Root cause**: The teleport was put in `_process_combat_state` but suppression happens in
  all states. The original `develop` design solved this with DASH (fires from `_update_suppression`,
  which runs every frame regardless of AI state).

#### B) Regular teleport enemy damage-triggered teleport timing
- The experimental menu spawner: instantiates enemy → sets `is_teleporter=true` → calls
  `add_child(enemy)` → enemy's `_ready()` runs → `add_child(_teleport_component)` → teleport
  component's `_ready_flag` set on NEXT FRAME (Godot deferred).
- If the enemy is shot on the same frame it enters the scene tree, `is_ready()` may return false
  because `_ready_flag` is not yet set.
- However, this is a minor timing issue (single-frame window). The bigger issue is (A) above.

---

## Root Causes

1. **Missing dash methods in `DroneOperatorComponent`**: `should_dash_instead_of_suppress()`,
   `try_dash_from_threat()`, `try_dash()`, `_update_dash()`, `_end_dash()`, `_spawn_afterimage()`,
   and all related state variables (`_dash_charges`, `_dash_cooldown_timer`, etc.) were omitted
   when porting from `develop` to `main`.

2. **Drone operator teleport only in COMBAT state**: The teleport-to-cover logic for drone
   operators was placed inside `_process_combat_state()`, but suppression can happen from any
   AI state (IN_COVER, SEEKING_COVER, FLANKING, etc.).

---

## Evidence from Game Log

```
[17:57:34] [DroneOperator] Teleport component set up (teleport evasion, Issue #1664)
[17:57:34] [DroneOperator] Phase: ACTIVE (silenced pistol + laser, teleport evasion)
...
[17:57:40] [EnemyDroneOperator] State: IN_COVER -> SUPPRESSED
[17:57:41] [EnemyDroneOperator] State: SUPPRESSED -> SEEKING_COVER
```
- Drone operator is set up with teleport evasion and transitions to ACTIVE.
- When shot (IN_COVER), goes SUPPRESSED → SEEKING_COVER — never enters COMBAT state.
- The teleport check in `_process_combat_state` never executes.
- No `[Teleporter] Teleported from ... to ...` entries anywhere in the log.
- No `[#1664] Drone operator damage-triggered teleport succeeded` entries.
- No `[Teleporter] Rejected teleport: ...` entries either — meaning `try_teleport` was
  never even called.

For regular teleport enemy:
```
[17:58:22] [ExperimentalMenu] Enemy spawner: spawned 'Teleporter (Rifle)' at (515.2673, 390.8434)
...
[17:58:24] [Enemy] [#1311] Player bullet entered threat sphere — suppression triggered
[17:58:24] [Enemy] Hit: dmg=1, hp=2/2->1/2
...
[17:58:24] [Enemy] State: COMBAT -> RETREATING
[17:58:24] [Enemy] State: RETREATING -> IN_COVER
```
- Teleport enemy is shot in COMBAT state.
- Damage-triggered teleport (`[#1355] Damage-triggered teleport succeeded`) never fires.
- Enemy does normal retreat-to-cover instead.

---

## Proposed Solutions

### Solution A (Recommended): Restore Dash System from `develop`

Port the complete dash system from `develop/drone_operator_component.gd` to
`main/scripts/components/drone_operator_component.gd`:
- Add dash state variables: `_dash_charges`, `_dash_cooldown_timer`, `_dash_active`, etc.
- Add methods: `should_dash_instead_of_suppress()`, `try_dash_from_threat()`, `try_dash()`,
  `_update_dash()`, `_end_dash()`, `_spawn_afterimage()`
- Update `_update_active()` to handle dash cooldown and active dash
- Keep the existing `enemy.gd` call to `should_dash_instead_of_suppress()` (already there)

This restores the intended design: drone operators DASH toward the player instead of
being suppressed or teleporting. Teleport remains as a separate ACTIVE-phase evasion
for when the operator is not in cover.

### Solution B: Move drone operator teleport check to `_process_ai_state`

Move the drone operator teleport check (currently in `_process_combat_state`) to
`_process_ai_state()` before the state dispatch — like the regular teleporter enemy.
This would fire regardless of current AI state.

This is simpler but mixes the dash-vs-teleport design of develop vs main.

### Solution C: Both A + B

Implement the dash system AND move the teleport check. This gives drone operators
both behaviors: dash when charges available, teleport when charges exhausted.

---

## Recommended Fix

Implement **Solution A** (restore dash system from develop).

The dash system is the original design intent for drone operators. Teleport was added
as a workaround when the dash was lost. Restoring the dash properly fixes the behavioral
regression while keeping the Issue #1664 teleport as a fallback for ACTIVE-phase.

Files to modify:
- `scripts/components/drone_operator_component.gd`: Add full dash system
- `scripts/objects/enemy.gd`: Already has `should_dash_instead_of_suppress()` call —
  no changes needed (the existing code will work once the methods exist)
