# Testing Plan: Issue #273 - Tactical Grenade Throwing

## Overview

This testing plan covers the tactical grenade throwing system for enemy AI as specified in issue #273.

---

## Pre-requisites

- [ ] Game builds successfully without errors
- [ ] BuildingLevel loads correctly
- [ ] Enemy10 is in the main hall area (position ~1200, 1550)
- [ ] DifficultyManager autoload is present

---

## Test Cases

### TC-1: Grenade Configuration at HARD Difficulty

**Objective**: Verify Enemy10 receives 2 offensive grenades only at HARD difficulty

**Steps**:
1. Set difficulty to HARD via DifficultyManager
2. Load BuildingLevel
3. Check Enemy10's `offensive_grenades` property

**Expected Results**:
- [ ] Enemy10.enable_grenades = true
- [ ] Enemy10.offensive_grenades = 2
- [ ] Enemy10.flashbang_grenades = 0

---

### TC-2: No Grenades at EASY/NORMAL Difficulty

**Objective**: Verify enemies have no grenades at lower difficulties

**Steps**:
1. Set difficulty to EASY or NORMAL
2. Load BuildingLevel
3. Check Enemy10's grenade properties

**Expected Results**:
- [ ] Enemy10.enable_grenades = false (or default)
- [ ] Enemy10.offensive_grenades = 0

---

### TC-3: Grenade Throw Execution

**Objective**: Verify grenade throwing mechanics work correctly

**Steps**:
1. Set difficulty to HARD
2. Load BuildingLevel
3. Trigger one of the grenade throw conditions (e.g., get close then hide)
4. Observe enemy behavior

**Expected Results**:
- [ ] Enemy transitions to THROWING_GRENADE state
- [ ] Enemy aims at player position
- [ ] Grenade is instantiated from FragGrenade.tscn
- [ ] Grenade has deviation applied (±5°)
- [ ] Enemy seeks cover after throwing
- [ ] Grenade count decrements by 1

---

### TC-4: Trigger Condition - Player Hidden After Suppression (6s)

**Objective**: Test trigger condition #1 from issue requirements

**Steps**:
1. Suppress enemy (make them take cover)
2. Hide from enemy for 6+ seconds
3. Observe if grenade throw triggers

**Expected Results**:
- [ ] _player_hidden_timer increments while player hidden
- [ ] At 6 seconds, _should_throw_grenade() returns true
- [ ] Enemy throws grenade toward last known player position

---

### TC-5: Trigger Condition - Suppressed Enemy Being Chased

**Objective**: Test trigger condition #2 from issue requirements

**Steps**:
1. Suppress enemy to make them enter SUPPRESSED state
2. Approach enemy while they're suppressed
3. Observe if grenade throw triggers

**Expected Results**:
- [ ] Enemy in SUPPRESSED state with visible player triggers grenade
- [ ] Enemy throws grenade at approaching player

---

### TC-6: Trigger Condition - Witnessed 2+ Ally Deaths

**Objective**: Test trigger condition #3 from issue requirements

**Steps**:
1. Position Enemy10 where they can see combat
2. Kill 2 other enemies while Enemy10 is watching
3. Observe if grenade throw triggers

**Expected Results**:
- [ ] _witnessed_ally_deaths counter increments when ally dies in view
- [ ] At 2 deaths, _should_throw_grenade() returns true
- [ ] Enemy throws grenade

---

### TC-7: Trigger Condition - Critical Health (1 HP)

**Objective**: Test trigger condition #6 from issue requirements

**Steps**:
1. Damage enemy until they have 1 HP
2. Observe if grenade throw triggers

**Expected Results**:
- [ ] At _current_health <= 1, _should_throw_grenade() returns true
- [ ] Enemy throws "desperation" grenade

---

### TC-8: Throw Deviation

**Objective**: Verify ±5° random deviation on throws

**Steps**:
1. Trigger multiple grenade throws
2. Record the deviation angles from logs

**Expected Results**:
- [ ] Deviation is random within ±5° range
- [ ] Not all grenades land exactly on target

---

### TC-9: Cooldown Between Throws

**Objective**: Verify 10-second cooldown between grenade throws

**Steps**:
1. Trigger first grenade throw
2. Attempt to trigger second throw immediately
3. Wait 10 seconds and try again

**Expected Results**:
- [ ] Second throw blocked while _grenade_cooldown_timer > 0
- [ ] After 10 seconds, throws work again

---

### TC-10: Post-Throw Behavior

**Objective**: Verify enemy seeks cover after throwing

**Steps**:
1. Trigger grenade throw
2. Observe enemy state after throw

**Expected Results**:
- [ ] Enemy transitions to SEEKING_COVER state (if cover enabled)
- [ ] Or transitions to COMBAT if cover disabled

---

## Integration Tests

### IT-1: Full Combat Flow with Grenades

**Objective**: Verify grenades integrate with existing combat system

**Steps**:
1. Enter BuildingLevel at HARD difficulty
2. Engage in combat with Enemy10
3. Let various trigger conditions occur naturally

**Expected Results**:
- [ ] Grenades enhance tactical depth without breaking flow
- [ ] AI state machine transitions correctly
- [ ] No crashes or errors

---

### IT-2: Grenade Damage to Player

**Objective**: Verify frag grenades damage the player correctly

**Steps**:
1. Get hit by enemy-thrown frag grenade

**Expected Results**:
- [ ] Player takes 99 damage (from FragGrenade.explosion_damage)
- [ ] Shrapnel spawns as normal

---

## Logging Verification

Check these log messages appear at appropriate times:
- [ ] "Grenade trigger: ..." - when condition is met
- [ ] "Preparing to throw frag grenade at ..." - entering state
- [ ] "Threw frag grenade: target=..., deviation=..., distance=..." - after throw
- [ ] "BuildingLevel: [HARD] Enemy10 (main hall) equipped with 2 offensive grenades" - at level start

---

## Performance Checks

- [ ] No frame rate drops during grenade throw preparation
- [ ] No memory leaks from grenade instantiation
- [ ] Ally death listener doesn't cause issues with many enemies

---

## Edge Cases

- [ ] What happens when enemy runs out of grenades mid-throw?
- [ ] What happens if player dies while enemy is throwing?
- [ ] What happens if enemy dies while throwing?
- [ ] Grenades work correctly after enemy respawn (if not destroy_on_death)

---

## Notes

- All grenade behavior is configurable via enemy exports
- Grenades only available at HARD difficulty per issue spec
- Grenade types can be extended (smoke grenades marked as "future" in requirements)
