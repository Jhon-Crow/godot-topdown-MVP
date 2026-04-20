# Issue 1868 Case Study

## Source Data

- `game_log_20260418_010143.txt`: user-provided exported Windows build log, 3,239 lines.
- `game_log_20260418_010323.txt`: user-provided exported Windows build log, 1,718 lines.

## Timeline Reconstruction

### Log `game_log_20260418_010323.txt`

- 01:03:23: the save restores the Loudspeaker active item at level 7.
- 01:03:24: the labyrinth level starts and all initial enemies transition to `PACIFIST`.
- 01:03:25: the railway-station level loads and creates four `Exit_DroneOperator*` enemies.
- 01:03:25: the level-7 loudspeaker victory state runs again and transitions the railway-station enemies, including all four drone operators, to `PACIFIST`.
- 01:03:26: despite those pacifist transitions, the drone-operator component reports `Reached cover, deploying drone in 0.5s` for all four operators.
- 01:03:26: all four operators instantiate drones and enter `Phase: CONTROLLING (defenseless)`.

### Log `game_log_20260418_010143.txt`

- 01:02:21-01:02:24: ordinary enemies continue logging `state=PACIFIST` while drone operators repeatedly log `FLANKING corner check`, showing they are no longer following the pacifist state machine.
- 01:02:25: `Exit_DroneOperator2` logs `state=FLANKING`, then `State: FLANKING -> COMBAT`.
- 01:02:26: `Exit_DroneOperator2` emits enemy gunshot sounds.
- 01:02:27-01:02:30: `Exit_DroneOperator1`, `Exit_DroneOperator3`, and `Exit_DroneOperator4` also transition through `FLANKING`/`COMBAT` and emit enemy gunshot sounds.

## Root Cause

The previous fix neutralized a drone after its linked operator was already pacifist, but the operator component still ran its normal DEPLOYING/CONTROLLING loop before normal pacifist processing in `enemy.gd`. In the level-7 victory state, newly spawned railway-station drone operators became pacifist, but their `DroneOperatorComponent` still sought cover, deployed drones, and later allowed ACTIVE/operator combat behavior to resume.

A secondary risk is that pacifism did not explicitly clear an existing aggression component state. If an enemy had aggression/combat residue before becoming pacifist, later AI ticks could observe stale aggressive state.

## Implemented Solution

- `DroneOperatorComponent.update()` now returns immediately when its parent is pacifist. If a controlled drone still exists, it is neutralized before returning.
- `enemy.gd` now checks the pacifist drone-operator case before the normal drone-operator phase-control branch, so pacifist operators cannot seek cover or deploy drones.
- `_transition_to_pacifist()` clears the aggression component state to prevent stale aggressive behavior after pacification.

## Verification Added

- `tests/unit/test_drone_operator.gd` checks that `DroneOperatorComponent.update()` has the pacifist early return.
- `tests/unit/test_drone_operator.gd` checks that `enemy.gd` runs the Issue #1868 pacifist guard before normal Issue #1397 drone-operator phase control.
- Existing `tests/unit/test_drone.gd` still covers spawned drones dying when their operator becomes pacifist.
