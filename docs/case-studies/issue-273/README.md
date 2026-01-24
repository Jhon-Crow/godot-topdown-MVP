# Case Study: Issue #273 - Tactical Grenade Throwing for Enemies

## Executive Summary

This case study documents the analysis of GitHub Issue #273, which requests the implementation of tactical grenade throwing behavior for enemy AI in a top-down shooter game built with Godot Engine.

### Key Facts
- **Issue**: [#273](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/273)
- **Pull Request**: [#274](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/274)
- **Created**: 2026-01-22T21:30:16Z
- **Status**: In Progress (case study phase)
- **First AI Attempt**: Failed due to rate limit (0 tokens consumed)

---

## Table of Contents

1. [Problem Description](#problem-description)
2. [Timeline of Events](#timeline-of-events)
3. [Root Cause Analysis](#root-cause-analysis)
4. [Codebase Analysis](#codebase-analysis)
5. [Industry Research](#industry-research)
6. [Proposed Solutions](#proposed-solutions)
7. [Recommendations](#recommendations)

---

## Problem Description

### Original Issue (Russian)
> внимание - по дефолту у врагов нет гранат, для каждой карты я сам скажу, у кого и какие гранаты.
> враг с гранатой может перейти в режим "готов кинуть гранату"...

### Translated Requirements

The issue requests a comprehensive tactical grenade system for enemy AI with the following features:

#### Grenade Throw Mode Behavior
1. **Ally Notification**: Thrower notifies allies in blast zone/throw trajectory to evacuate with maximum priority
2. **Positioning**: Move to throw range OR to cover that protects from player's line-of-sight (ignoring one obstacle); throw has ±5° random deviation
3. **Coordinated Waiting**: Evacuated allies wait for explosion to begin organized assault
4. **Throw Execution**: Thrower exits cover if needed and throws grenade
5. **Post-Throw Safety**: Thrower aims at landing spot and moves to safe distance; seeks cover if grenade is non-lethal
6. **Assault**: Immediately after explosion, assault through the passage where grenade was thrown

#### Trigger Conditions
1. Player suppressed enemies then hid for 6+ seconds
2. Player is chasing a suppressed thrower
3. Thrower witnessed player kill 2+ enemies
4. Thrower heard reload/empty magazine sound but can't see player
5. Continuous gunfire for 10 seconds in 1/6 viewport zone
6. Thrower has 1 HP or less

#### Specific Request
> Give 2 offensive grenades to the enemy in the building map in the main hall room.

---

## Timeline of Events

```
2026-01-22 21:30:16 UTC - Issue #273 created
2026-01-22 21:30:39 UTC - AI solver started
2026-01-22 21:31:14 UTC - PR #274 created (draft)
2026-01-22 21:31:33 UTC - RATE LIMIT ERROR (454ms, 0 tokens)
2026-01-22 21:31:36 UTC - Session terminated, rate limit comment posted
          ~23 hours gap - No automated activity
2026-01-23 20:28:09 UTC - User requests case study analysis
2026-01-23 20:28:44 UTC - New AI session started (current)
```

See [analysis/timeline.md](analysis/timeline.md) for detailed timeline.

---

## Root Cause Analysis

### Why the First Session Failed

**Primary Cause**: API rate limit was already exhausted before the session started.

**Evidence**:
- Session duration: 454ms
- Tokens consumed: 0 input, 0 output
- Error message: "You've hit your limit · resets Jan 27, 10am"

**Contributing Factors**:
1. No pre-flight rate limit check
2. Auto-resume feature not actually implemented
3. Temporary directory lifecycle issues
4. Unclear user expectations about auto-resume

See [analysis/root-cause-analysis.md](analysis/root-cause-analysis.md) for detailed 5-Whys and fishbone analysis.

---

## Codebase Analysis

### Existing Systems Relevant to This Feature

| System | Location | Status |
|--------|----------|--------|
| Enemy AI (4720 lines) | `scripts/objects/enemy.gd` | Exists |
| GOAP Planner | `scripts/ai/goap_planner.gd` | Exists |
| Cover Component | `scripts/components/cover_component.gd` | Exists |
| Grenade Base | `scripts/projectiles/grenade_base.gd` | Exists |
| Frag Grenade | `scripts/projectiles/frag_grenade.gd` | Exists |
| Flashbang Grenade | `scripts/projectiles/flashbang_grenade.gd` | Exists |
| Sound Propagation | `scripts/autoload/sound_propagation.gd` | Exists |
| Status Effects | `scripts/autoload/status_effects_manager.gd` | Exists |

### Key Findings

1. **Grenade mechanics exist** but only for player use
2. **GOAP system exists** and can be extended with grenade actions
3. **Cover system exists** but needs enhancement for grenade-specific positioning
4. **State machine exists** but lacks throw grenade state
5. **Sound propagation exists** and can trigger grenade throws

---

## Industry Research

Research into tactical AI grenade systems reveals established patterns:

### Key Sources
- [Killzone's AI: Dynamic Procedural Combat Tactics](http://cse.unl.edu/~choueiry/Documents/straatman_remco_killzone_ai.pdf)
- [Close Quarters Development: Realistic Combat AI](https://www.gamedev.net/tutorials/programming/artificial-intelligence/close-quarters-development-realistic-combat-ai-part-1-r5156/)
- [GOAP and Utility AI in Games](https://goldensyrupgames.com/blog/2024-05-04-grab-n-throw-utility-goap-ai/)

### Industry Best Practices
1. **Opportunistic grenade use** - Don't move specifically for grenades, but evaluate during normal pathing
2. **Position evaluation** - Check safety before throwing (friendlies, distance, cover)
3. **GOAP integration** - Grenades as alternative action with dynamic cost
4. **Squad coordination** - Influence maps and spacing systems

See [research/tactical-grenade-ai-research.md](research/tactical-grenade-ai-research.md) for full research notes.

---

## Proposed Solutions

### Architecture Overview

```
┌─────────────────────────────────────────────────┐
│              GRENADE THROWING SYSTEM            │
├─────────────────────────────────────────────────┤
│  1. GrenadeInventory       - Tracks grenade count│
│  2. GrenadeTriggerEvaluator - Monitors triggers │
│  3. GrenadeCoordination    - Ally notification  │
│  4. ThrowGrenadeState      - State machine      │
│  5. ThrowGrenadeAction     - GOAP integration   │
└─────────────────────────────────────────────────┘
```

### New Components Required

| Component | Purpose | Complexity |
|-----------|---------|------------|
| GrenadeInventory | Track grenade types/counts | Low |
| GrenadeTriggerEvaluator | Monitor 6 trigger conditions | Medium |
| GrenadeCoordination | Ally notification & evacuation | High |
| ThrowGrenadeState | Execute throw behavior | High |
| ThrowGrenadeAction | GOAP cost evaluation | Medium |

### Implementation Phases

1. **Phase 1**: Core throw mechanics (inventory, basic throw)
2. **Phase 2**: Trigger system (6 conditions)
3. **Phase 3**: Squad coordination (notification, evacuation, assault)
4. **Phase 4**: GOAP integration

See [analysis/proposed-solutions.md](analysis/proposed-solutions.md) for detailed code examples.

---

## Recommendations

### For This Issue

1. **Implement in phases** - Start with basic throw, then add triggers and coordination
2. **Reuse existing systems** - GOAP, cover component, sound propagation
3. **Test each trigger independently** - 6 different conditions need individual testing

### For Process Improvement

1. **Add pre-flight rate limit check** to solver
2. **Implement actual auto-resume infrastructure** with scheduler
3. **Clearer communication** about auto-resume limitations
4. **Persistent session storage** (not in /tmp)

---

## Files in This Case Study

```
docs/case-studies/issue-273/
├── README.md                          # This file
├── data/
│   ├── issue-273.json                 # Issue data
│   └── pr-274.json                    # PR data
├── logs/
│   └── session-e972cdf1-first-attempt.log  # First session log
├── research/
│   └── tactical-grenade-ai-research.md     # Industry research
└── analysis/
    ├── timeline.md                    # Event timeline
    ├── root-cause-analysis.md         # RCA document
    └── proposed-solutions.md          # Technical solutions
```

---

## References

- Issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/273
- PR: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/274
- Codebase: https://github.com/Jhon-Crow/godot-topdown-MVP
