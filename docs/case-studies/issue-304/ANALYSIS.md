# Issue #304 - Grenade Throwing System Case Study

## Overview
This case study documents the implementation of the grenade throwing system for enemies and the debugging process for issues encountered during development.

## Timeline of Events

### Initial Implementation (PR #296)
- Grenade throwing system was first implemented in a separate PR
- GrenadeThrowerComponent (747 lines) was created as a modular component
- The implementation worked in isolation but integration issues emerged

### Integration with SEARCHING State (Issue #322)
- The main branch received updates adding the SEARCHING state for enemy AI
- The PR branch was missing this state, causing script load failures
- Error: "Enemy 'EnemyX' missing died signal - likely script load failure"

### Branch Reset and Rebuild (2026-01-24)
- Branch was reset to `upstream/main` to include SEARCHING state and memory system
- GrenadeThrowerComponent was re-added from PR #296
- THROWING_GRENADE and READY_TO_THROW states were integrated with GOAP

## Key Findings

### Root Cause of "Enemies Completely Broken"
From `game_log_20260125_020631.txt`:
```
[BuildingLevel] Enemy tracking complete: 0/10 enemies registered
[BuildingLevel] WARNING: Enemy 'Enemy1' missing died signal - likely script load failure
```

**Cause:** The PR branch was missing the SEARCHING state that was added to main. When enemy scripts tried to load without this state defined, they failed silently.

### Solution Applied
1. Reset branch to upstream/main (which has SEARCHING state)
2. Re-added GrenadeThrowerComponent
3. Added grenade states (THROWING_GRENADE, READY_TO_THROW)
4. Integrated with GOAP decision making
5. Condensed code to fit within 5000 line CI limit

## Logs

- `logs/game_log_20260125_020631.txt` - Shows the "broken enemies" state before fix

## References

- Issue #304: Enemy Grenade Throwing System
- Issue #322: SEARCHING state implementation
- Issue #330: Enemy IDLE state return bug
- PR #296: Original grenade system implementation
- PR #305: Current implementation (this PR)
