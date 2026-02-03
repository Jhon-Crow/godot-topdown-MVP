# Case Study: Enemy Grenade Avoidance - Issue #407

## Issue Summary

**Title:** fix враги не должны убивать себя своей гранатой (enemies should not kill themselves with their own grenade)

**Requirements:**
- Enemies should avoid zones where grenades have been thrown or are likely to be
- This behavior should be integrated into the existing GOAP (Goal Oriented Action Planning) system
- Must follow architectural rules of the codebase

## Current Codebase Analysis

### Existing GOAP Architecture

The codebase has a well-structured GOAP implementation:

1. **GOAPPlanner** (`scripts/ai/goap_planner.gd`): Uses A* search to find optimal action sequences
2. **GOAPAction** (`scripts/ai/goap_action.gd`): Base class for actions with preconditions and effects
3. **EnemyActions** (`scripts/ai/enemy_actions.gd`): Contains all enemy action definitions

Current actions include:
- SeekCoverAction, EngagePlayerAction, FlankPlayerAction, PatrolAction
- StaySuppressedAction, ReturnFireAction, RetreatAction, RetreatWithFireAction
- PursuePlayerAction, AttackDistractedPlayerAction, AttackVulnerablePlayerAction
- InvestigateHighConfidenceAction, InvestigateMediumConfidenceAction, SearchLowConfidenceAction

### Grenade System

Two grenade types exist:
1. **FlashbangGrenade**: 4-second fuse, 400px effect radius, blinds/stuns
2. **FragGrenade**: Impact-triggered (no timer), 225px effect radius, 99 damage

Key grenade properties:
- `effect_radius`: Defines the danger zone
- `_timer_active`: Whether grenade is armed
- `global_position`: Current grenade location
- `linear_velocity`: Movement direction/speed

### Threat Detection Pattern

The codebase has an existing threat detection pattern via `ThreatSphere`:
- Area2D-based detection for bullets
- Triggers suppression behavior
- Uses `_threat_reaction_delay` for realistic response time

### Enemy AI State Machine

AIState enum includes:
- IDLE, COMBAT, SEEKING_COVER, IN_COVER, FLANKING
- SUPPRESSED, RETREATING, PURSUING, ASSAULT, SEARCHING

## Research: GOAP Danger Avoidance Patterns

### Industry Examples

1. **F.E.A.R. (2005)**: Pioneered GOAP in games. AI would use survival instinct - recognize threats and prioritize cover-seeking.

2. **Halo: Combat Evolved**: Enemies throw back grenades or flee from them. Squad members respond to grenade throws.

3. **General Pattern**: GOAP systems handle danger avoidance through:
   - High-priority goals (e.g., "avoid_grenade") that override other goals
   - World state flags (e.g., "grenade_nearby", "in_danger_zone")
   - Actions with effects that set "is_safe" to true

### Key Implementation Patterns

1. **Detection System**:
   - Area2D sensor to detect grenades in range
   - Track active grenades in scene
   - Calculate predicted explosion zones

2. **GOAP Integration**:
   - World state: `in_grenade_danger_zone: bool`
   - Goal: `{in_grenade_danger_zone: false}` with very high priority
   - Action: `EvadeGrenadeAction` that moves enemy away from danger

3. **Movement Strategy**:
   - Find safe position outside blast radius
   - Use navigation to reach safe position
   - Prioritize speed over cover during evasion

## Proposed Solution

### Component 1: Grenade Danger Detection

Create detection system in enemy to track nearby grenades:
- Listen for grenades added to scene
- Check distance to grenade vs effect radius
- Set world state flag when in danger

### Component 2: New GOAP Action - EvadeGrenadeAction

```gdscript
class EvadeGrenadeAction extends GOAPAction:
    func _init() -> void:
        super._init("evade_grenade", 0.01)  # Very low cost = highest priority
        preconditions = {
            "in_grenade_danger_zone": true
        }
        effects = {
            "in_grenade_danger_zone": false
        }
```

### Component 3: Enemy Integration

Add to enemy.gd:
- `_grenades_in_danger_range: Array` - track nearby grenades
- `_grenade_evasion_target: Vector2` - safe position to flee to
- Detection logic in `_physics_process`
- World state update: `in_grenade_danger_zone`

## Architecture Considerations

1. **Follow Existing Patterns**: Use ThreatSphere-like detection
2. **GOAP Integration**: Add new action to `EnemyActions.create_all_actions()`
3. **Avoid Self-Damage**: Only track grenades NOT thrown by self (check source_id)
4. **Performance**: Use group system (`get_tree().get_nodes_in_group("grenades")`)

## References

- [Building the AI of F.E.A.R. with Goal Oriented Action Planning](https://www.gamedeveloper.com/design/building-the-ai-of-f-e-a-r-with-goal-oriented-action-planning)
- [NPC AI planning with GOAP | Excalibur.js](https://excaliburjs.com/blog/goal-oriented-action-planning/)
- [Game AI Planning: GOAP, Utility, and Behavior Trees](https://tonogameconsultants.com/game-ai-planning/)
- [Artificial intelligence in video games - Wikipedia](https://en.wikipedia.org/wiki/Artificial_intelligence_in_video_games)
- [GPGOAP - General Purpose Goal Oriented Action Planning](https://github.com/stolk/GPGOAP)
