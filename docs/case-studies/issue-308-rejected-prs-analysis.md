# Case Study: Analysis of Rejected Pull Requests (Issue #308)

## Executive Summary

This document analyzes rejected pull requests to identify recurring patterns that caused gameplay-breaking issues. The analysis led to the creation of new protection mechanisms in `gameplay-validation.yml` and updated contribution guidelines.

## Methodology

1. Retrieved all closed but not-merged PRs from the repository
2. Analyzed owner comments on rejected PRs to identify specific breaking issues
3. Categorized issues by type and severity
4. Identified common patterns and root causes
5. Implemented automated protection mechanisms

## Rejected PRs Analyzed

### PR #104 - Add enemy search behavior when player escapes from view

**Date Closed**: 2026-01-18

**Issue Reported**:
- "vse povedenie slomalos. vragi ne poluchayut uron i ne deystvuyut" (All behavior broken. Enemies don't receive damage and don't act)
- Debug also not working
- Enemies just standing in place with no interactivity

**Root Cause**: Changes to enemy AI state machine broke the core _physics_process loop or state transitions.

**Category**: Enemy AI Breaking (Critical)

---

### PR #127 - Add scoring system after level clear

**Date Closed**: 2026-01-21

**Issue Reported**:
- "slomalas podschet vragov, posle ubiystva vsekh igra ne konchaetsya" (Enemy counter broke, game doesn't end after killing all)
- "slomals'a schetchik patronov" (Ammo counter broke)
- Combo interface also not working
- Multiple attempts to fix still left it broken

**Root Cause**: Signal connections for enemy counting and ammo tracking were disrupted. The `died` signal emission or GameManager connection was broken.

**Category**: Game Counter Breaking (Critical)

---

### PR #155 - Enhance blood effects with wall collision

**Date Closed**: 2026-01-21

**Issue Reported**:
- "igra vyletaet" (Game crashes)
- Blood particles still passing through walls
- Particles scattering too strongly

**Root Cause**: Procedural blood effect implementation caused memory issues or null pointer access.

**Category**: Game Crashes (Critical)

---

### PR #157 - Fix enemy aiming at player behind cover

**Date Closed**: 2026-01-21

**Issues Reported**:
1. Enemies still don't see player when option is disabled
2. Enemies should be in normal (non-rotated) state when feature disabled
3. Some enemies shoot randomly even when they can't see player
4. Enemy turns toward player through obstacles but doesn't shoot through them

**Root Cause**: Vision/detection logic had conditional paths that weren't properly tested for edge cases.

**Category**: Enemy Vision/Detection Breaking (High)

---

### PR #250 - Fix player model arm joint issues

**Date Closed**: 2026-01-22

**Issues Reported**:
- Right elbow constantly disconnecting (in rifle/shotgun pose)
- Joint disconnecting during grenade throw
- Need to accept changes from main branch and adapt

**Root Cause**: Sprite pivot/offset changes didn't account for all animation states.

**Category**: Visual Glitches (Medium)

---

### PR #296 - Wall-blocking and tactical grenade behaviors

**Status**: Still Open (ongoing issues)

**Issues Reported**:
- "vragi polnostyu slomal'is' (ne dvigayutsya dazhe)" (Enemies completely broken, don't even move)
- Architecture check failing
- Possible C# integration issues
- Grenades hitting walls incorrectly
- Grenade thrower behavior not triggering

**Root Cause**: Multiple issues - C# compilation problems, enemy state machine breaks, and incomplete grenade AI implementation.

**Category**: Enemy AI Breaking + C# Integration (Critical)

---

## Pattern Analysis

### Pattern 1: Enemy AI State Machine Breaking

**Frequency**: 3 PRs (#104, #296, and similar issues in #157)

**Symptoms**:
- Enemies not moving
- Enemies not taking damage
- Enemies not detecting player
- State transitions not working

**Common Causes**:
1. Removing or renaming critical methods (`_ready`, `_physics_process`, `on_hit`, `_die`)
2. Breaking early return conditions in `_physics_process`
3. Modifying state enum without updating all switch/match cases
4. Null references to `_player` variable

**Prevention**:
- Validate presence of critical methods
- Validate AIState enum completeness
- Check for required state variables

---

### Pattern 2: Game Counter/Signal Breaking

**Frequency**: 2 PRs (#127, plus related in #296)

**Symptoms**:
- Enemy count not updating on death
- Game not ending when all enemies killed
- Ammo counter not displaying correctly
- Combo system not working

**Common Causes**:
1. `died` signal not emitted in `_die()` function
2. Signal connection to GameManager broken
3. Ammo changed signal not emitted on shoot

**Prevention**:
- Validate `died` signal is emitted in death function
- Check signal connections in autoloads
- Ensure ammo_changed signal is emitted

---

### Pattern 3: Game Crashes

**Frequency**: 1 PR (#155)

**Symptoms**:
- Game crashes during specific actions
- Memory-related errors
- Null pointer exceptions

**Common Causes**:
1. Accessing freed nodes
2. Infinite loops
3. Division by zero
4. Missing null checks for optional nodes

**Prevention**:
- Use `is_instance_valid()` checks
- Add null guards before node access
- Validate loops have proper exit conditions

---

### Pattern 4: Vision/Detection Issues

**Frequency**: 1 PR (#157)

**Symptoms**:
- Enemies can't see player
- Enemies see through walls
- Detection behaves inconsistently with options

**Common Causes**:
1. Raycast configuration errors
2. Conditional visibility logic bugs
3. Feature toggle not properly implemented

**Prevention**:
- Test all combinations of visibility options
- Verify raycast layer masks
- Add debug visualization for detection

---

## Implemented Protections

Based on this analysis, the following protections were implemented:

### 1. gameplay-validation.yml Workflow

New CI workflow that checks:
- Critical file modification detection
- Enemy state machine integrity (methods, variables, states)
- Dangerous code pattern detection
- Health component validation
- Counter/state reset signal verification
- GDScript syntax validation
- Scene-script reference consistency

### 2. Updated CONTRIBUTING.md

Added new sections:
- Issue #7: Enemy AI Breaking prevention guidelines
- Issue #8: Game Counter Breaking prevention guidelines
- Issue #9: Game Crashes prevention guidelines
- Updated PR checklist to include gameplay-validation.yml
- Added gameplay-validation.yml to CI/CD Workflows section

### 3. Documentation

This case study document provides:
- Historical reference for future contributors
- Pattern recognition for similar issues
- Root cause analysis methodology
- Prevention strategies

## Recommendations

1. **Always run gameplay tests** after modifying enemy.gd or AI scripts
2. **Test signal connections** when modifying death/damage systems
3. **Add null checks** before accessing any node reference
4. **Verify all CI checks pass** including the new gameplay-validation.yml
5. **Test with actual gameplay** before marking PR as ready

## Conclusion

The analysis of rejected PRs revealed consistent patterns of breaking changes, primarily affecting:
- Enemy AI state machine
- Game counter/signal systems
- Core gameplay stability

The new `gameplay-validation.yml` workflow provides automated protection against these issues by validating critical code structures before merge.
