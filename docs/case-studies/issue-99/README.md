# Case Study: Issue #99 - Group AI Tactical Behavior

## Overview

**Issue**: [#99 - update ai групповая тактика](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/99)
**Status**: In Progress
**Affected Component**: Enemy AI System (GOAP)
**Created By**: Jhon-Crow

## Issue Summary

The request is to implement group behavior for enemies that are within communication distance of each other. The communication range should be approximately 1/4 of the viewport (the distance at which they could realistically talk and hear each other).

### Original Requirements (Russian → English)

> добавь групповое поведение близко друг к другу находящихся врагов (на расстоянии, на котором они могли бы переговариваться и звук долетал бы, примерно четверти вьюпорта).

**Translation**: Add group behavior for enemies that are close to each other (at a distance where they could communicate and sound would reach, approximately a quarter of the viewport).

### Reference Material

The issue references tactical building clearance techniques from [poligon64.ru](https://poligon64.ru/tactics/70-building-catch-tactics) which describes:
- Team-based room clearance (3-5 person teams)
- Sector-based responsibility zones
- Entry techniques (Hook, Cross, Corner, Diagonal)
- Communication protocols (coded terms: "Red", "Green", "Working")
- Formation maintenance with physical/visual contact

### Additional Requirements

1. Integrate this behavior into the existing GOAP system
2. Preserve all existing behavior in the executable

## Timeline Reconstruction

| Date/Time | Event |
|-----------|-------|
| Issue Creation | Request for group tactical behavior submitted |
| Analysis Phase | Codebase exploration to understand existing AI systems |
| Design Phase | Group behavior system design (this document) |
| 2026-01-20 20:10 UTC | First implementation PR created with squad coordination system |
| 2026-01-20 20:14 UTC | User reports: "enemies broken, debug also broken" with game log |
| 2026-01-20 20:17 UTC | Bug investigation started - identified missing `if` statement |
| 2026-01-20 20:23 UTC | Fix applied for missing `if` statement in `_process_flanking_state` |
| 2026-01-20 20:27 UTC | User reports: "still not working" with new game log |
| 2026-01-20 21:17 UTC | Second bug investigation started |

## Bug Analysis (Post-Implementation)

### Reported Symptoms

User (@Jhon-Crow) reported:
1. "враги сломались" (enemies are broken)
2. "дебаг тоже" (debug also broken)
3. Attached game log: `game_log_20260120_231338.txt`

### Game Log Analysis

From the attached log file (`logs/game_log_20260120_231338.txt`):

```
[23:13:47] [SoundPropagation] Sound emitted: type=GUNSHOT, pos=(624.6003, 777.6966),
           source=PLAYER (AssaultRifle), range=1469, listeners=0
[23:13:47] [SoundPropagation] Sound result: notified=0, out_of_range=0, self=0, below_threshold=0
```

**Key Finding**: `listeners=0` indicates that no enemies were registered as sound listeners. This means either:
- Enemies failed to initialize properly
- Enemies crashed during initialization
- The scene had no enemies spawned

### Root Cause Identified

**Critical Syntax Error in `_process_flanking_state` function**

The original code (main branch):
```gdscript
func _process_flanking_state(delta: float) -> void:
    _flank_state_timer += delta

    # Check for overall FLANKING state timeout
    if _flank_state_timer >= FLANK_STATE_MAX_TIME:
        var msg := "FLANKING timeout..."
        # ... timeout handling code
        return
```

The broken code (after PR changes):
```gdscript
func _process_flanking_state(delta: float) -> void:
    _flank_state_timer += delta

    var has_covering_fire := (_squad_role == SquadRole.FLANKER and _is_suppression_active())

    # Check for overall FLANKING state timeout
        var msg := "FLANKING timeout..."  # <-- INDENTED WITHOUT IF STATEMENT!
        # ... timeout handling code
        return
```

**The `if` statement was accidentally removed**, leaving an orphaned code block with incorrect indentation. In GDScript, this creates a syntax/parsing error that prevents the script from loading properly.

### Why This Happened

During the implementation of squad coordination, the developer intended to modify the timeout logic to account for covering fire (extending the timeout when a flanker has suppression support). However, the `if` statement was removed instead of being modified, creating invalid GDScript syntax.

### Fix Applied

```gdscript
func _process_flanking_state(delta: float) -> void:
    _flank_state_timer += delta

    # Squad coordination: Extend timeout when we have covering fire.
    var has_covering_fire := (_squad_role == SquadRole.FLANKER and _is_suppression_active())
    var effective_max_time := FLANK_STATE_MAX_TIME * (1.5 if has_covering_fire else 1.0)

    # Check for overall FLANKING state timeout
    if _flank_state_timer >= effective_max_time:
        var msg := "FLANKING timeout..."
        # ... rest of timeout handling
```

This fix:
1. Restores the `if` statement that was accidentally removed
2. Implements the intended feature: flankers with covering fire get 50% more time before timeout
3. Preserves all existing timeout behavior for enemies without covering fire

### Second Bug Report (2026-01-20 20:27 UTC)

**User Feedback**: "всё ещё не работает" (still not working)

The user provided a second game log (`logs/game_log_20260120_232702.txt`) which showed the same `listeners=0` problem persisting after the first fix.

### Second Root Cause: Duplicate Function Definition

Upon deeper investigation, a second critical error was found:

**Duplicate `is_alive()` function definition**

The squad coordination implementation accidentally added a second `is_alive()` function:

```gdscript
# First definition (line 3166 - added with squad coordination):
## Check if enemy is alive.
func is_alive() -> bool:
    return _is_alive

# Second definition (line 4218 - original):
## Returns whether this enemy is currently alive.
## Used by bullets to check if they should pass through or hit.
func is_alive() -> bool:
    return _is_alive
```

In GDScript, duplicate function definitions cause a parser error, preventing the entire script from loading. This explains why:
- Enemies weren't registering as sound listeners (`listeners=0`)
- No `[Enemy] Spawned` log messages appeared
- Debug mode toggling didn't show enemy data

### Fix Applied

Removed the duplicate function definition at line 3166-3167, keeping only the original function at line 4218.

### Lessons Learned

1. **When adding new code to large files**: Always search for existing functions with the same name before adding new ones
2. **Test incremental changes**: After each significant change, verify the script still loads
3. **Verify fixes thoroughly**: The first fix resolved one syntax error but didn't catch the duplicate function
4. **GDScript error messages**: Duplicate function definitions can be hard to spot without explicit compiler feedback

## Existing System Analysis

### Current AI Architecture

The game uses a sophisticated AI system with the following components:

1. **AI States** (9 states):
   - IDLE, COMBAT, SEEKING_COVER, IN_COVER, FLANKING
   - SUPPRESSED, RETREATING, PURSUING, ASSAULT

2. **GOAP System** (14 actions):
   - AttackDistractedPlayerAction, AttackVulnerablePlayerAction
   - PursueVulnerablePlayerAction, RetreatWithFireAction
   - AssaultPlayerAction, ReturnFireAction, EngagePlayerAction
   - PursuePlayerAction, FlankPlayerAction, RetreatAction
   - FindCoverAction, SeekCoverAction, StaySuppressedAction, PatrolAction

3. **Existing Group Coordination**:
   - `_count_enemies_in_combat()` function counts enemies in combat states
   - `AssaultPlayerAction` triggers when 2+ enemies are in combat
   - 5-second wait period before coordinated assault
   - Sound propagation system for alerting nearby enemies

### Current Communication Constants

From `sound_propagation.gd`:
```gdscript
const VIEWPORT_WIDTH: float = 1280.0
const VIEWPORT_HEIGHT: float = 720.0
const VIEWPORT_DIAGONAL: float = 1468.6  # sqrt(1280² + 720²)
```

### Calculated Communication Range

Per the issue requirement (1/4 viewport):
- **Viewport diagonal**: 1468.6 pixels
- **Communication range**: 367.15 pixels (1468.6 / 4)
- **Rounded value**: 360 pixels (practical value)

This is about half of the gunshot propagation range (1468.6px) and less than reload sound range (900px), which makes sense - verbal/tactical communication has shorter range than loud noises.

## Root Cause Analysis

### Why Group Behavior is Needed

1. **Current Limitation**: Enemies operate independently with minimal coordination
2. **Existing AssaultPlayerAction**: Only counts enemies in combat, doesn't coordinate tactics
3. **No Formation/Role System**: Enemies don't assume complementary roles
4. **No Spatial Awareness**: Enemies don't consider positions of nearby allies

### Key Insights from Research

#### From F.E.A.R. (GOAP Pioneer)
> "None of the enemy AI in FEAR know that each other exists and co-operative behaviours are simply two AI characters being given goals that line up nicely to create what look like coordinated behaviours."

This reveals that even F.E.A.R. didn't have true squad coordination - it was designed to appear coordinated.

#### From Days Gone
- Uses "Frontline" concept for spatial coordination
- Lane assignments minimize travel distances
- Confidence system affects squad aggression
- Flanking detection with timed responses

#### From Brothers in Arms
- Fire team provides suppression
- Assault team attacks in close quarters
- Both friendly and enemy AI use same tactics

## Proposed Solution

### Design Philosophy

Based on the reference material (Russian military tactics), the system should:

1. **Enable verbal communication** between nearby enemies (1/4 viewport range)
2. **Assign tactical roles** based on position and situation
3. **Coordinate actions** like flanking, suppression, and assault
4. **Maintain formation** when multiple enemies are present

### New GOAP World State Variables

```gdscript
# Group coordination state
"squad_size": int,              # Number of enemies in communication range
"has_squad": bool,              # true if squad_size >= 2
"squad_role": SquadRole,        # This enemy's current role
"squad_formation": bool,        # Whether in tactical formation
"squad_suppressing": bool,      # Squad is providing suppression fire
"squad_flanking": bool,         # Squad has flanker in position
"squad_leader": bool,           # This enemy is the squad leader
```

### New AI States

```gdscript
enum SquadRole {
    NONE,           # Operating independently
    LEADER,         # Coordinates squad, makes tactical decisions
    SUPPRESSOR,     # Provides covering fire
    FLANKER,        # Moves to flank position
    ASSAULT,        # Primary attacker
    REAR_GUARD      # Covers retreat path
}
```

### New GOAP Actions

1. **ProvideSuppressionAction**: Keep player pinned while allies flank
2. **CoordinatedFlankAction**: Flank while suppressor provides cover
3. **StackFormationAction**: Form up near doorways/corners
4. **CrossCoverAction**: Move between covers with overwatch
5. **BoundingOverwatchAction**: Alternating movement with cover

### Communication Range Constant

```gdscript
## Distance at which enemies can communicate verbally (1/4 viewport diagonal)
const SQUAD_COMMUNICATION_RANGE: float = 360.0
```

## Implementation Plan

### Phase 1: Squad Detection System
- Add `_find_squad_members()` function
- Create squad membership tracking
- Implement leader election (closest to player or most HP)

### Phase 2: Role Assignment
- Add SquadRole enum
- Implement `_assign_squad_role()` function
- Add role-based cost modifiers to existing actions

### Phase 3: New GOAP Actions
- Create suppression action
- Create coordinated flank action
- Update GOAP planner with new actions

### Phase 4: Communication System
- Add "silent communication" for enemies in range
- Share player position knowledge
- Coordinate timing of attacks

### Phase 5: Testing & Refinement
- Test with 2-5 enemy groups
- Verify existing behaviors preserved
- Balance timing parameters

## Files to Modify

| File | Changes |
|------|---------|
| `scripts/objects/enemy.gd` | Add squad detection, role system, new state variables |
| `scripts/ai/enemy_actions.gd` | Add new group-focused GOAP actions |
| `scripts/ai/goap_planner.gd` | Update if needed for new actions |

## Success Criteria

1. Enemies within 360px form tactical squads
2. Squad members assume complementary roles
3. Visible coordination (suppression while flanking)
4. All existing individual behaviors preserved
5. Natural-looking group movements
6. No performance degradation with multiple squads

## References

### Online Research Sources

1. [Building the AI of F.E.A.R. with Goal Oriented Action Planning](https://www.gamedeveloper.com/design/building-the-ai-of-f-e-a-r-with-goal-oriented-action-planning) - GOAP fundamentals
2. [Days Gone Squad Coordination Explained](https://80.lv/articles/days-gone-squad-coordination-explained) - Frontline system, confidence
3. [Squad Coordination in Days Gone - Game AI Pro](http://www.gameaipro.com/GameAIProOnlineEdition2021/) - Technical implementation
4. [GDC Vault - Believable Tactics for Squad AI](https://gdcvault.com/play/1015665/Believable-Tactics-for-Squad) - Presentation on squad AI
5. [Group Tactics Utilizing Suppression and Shelter](https://www.researchgate.net/publication/269725791_Group_Tactics_Utilizing_Suppression_and_Shelter) - Academic paper on group tactics

### Reference Material from Issue

- [Russian Tactical Building Clearance](https://poligon64.ru/tactics/70-building-catch-tactics) - Team structure, entry techniques, sector responsibility
