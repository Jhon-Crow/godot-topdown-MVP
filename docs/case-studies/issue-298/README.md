# Case Study: Issue #298 — AI Player Prediction System

## Overview

Issue #298 requests adding player prediction capabilities to the enemy AI, integrated into the existing GOAP (Goal-Oriented Action Planning) system. When enemies lose sight of the player, they should intelligently predict where the player might be based on retreat paths, flanking routes, shot directions, behavioral patterns, and time-distance analysis.

## Research & Background

### Academic Foundation

The prediction system is inspired by several established game AI techniques:

1. **F.E.A.R. GOAP System** (Jeff Orkin, GDC 2006) — The foundation for this project's AI. Notably, emergent flanking behavior arose from simple squad goals rather than explicit flanking code.
   - Source: [GDC Vault - Three States and a Plan](https://gdcvault.com/play/1013282/Three-States-and-a-Plan)

2. **Velocity Extrapolation** — Predicting future position: `predicted_pos = current_pos + velocity * time`. Used in network game prediction and AI lead shooting.
   - Source: [Gamedeveloper.com - Movement Prediction](https://www.gamedeveloper.com/programming/movement-prediction)

3. **Influence Maps / Probability Maps** — Encoding spatial information about where entities have been and might go. DADIM (Distance Adjustment Dynamic Influence Map) encodes dynamic movement trends.
   - Source: [GameDev.net - Core Mechanics of Influence Mapping](https://www.gamedev.net/tutorials/programming/artificial-intelligence/the-core-mechanics-of-influence-mapping-r2799/)

4. **Killzone Tactical Position Evaluation** — Weighted scoring system for cover and position quality: protection, distance, clustering avoidance. Cover quality gets strongest weight.
   - Source: [Killzone's AI PDF](http://cse.unl.edu/~choueiry/Documents/straatman_remco_killzone_ai.pdf)

5. **Self-Learning Movement Prediction** (Tim Guelke) — Lightweight algorithm that learns player patterns without deep learning, suitable for real-time games.
   - Source: [timguelke.net - Self-Learning AI Movement Prediction](https://www.timguelke.net/blog/2023/10/22/self-learning-ai-movement-prediction-beyond-airstriker-genesis-to-multi-directional-predictions)

### Existing Libraries Considered

| Library | Platform | Approach | Verdict |
|---------|----------|----------|---------|
| GdPlanningAI | Godot 4 | Object-oriented GOAP with SpatialAction | Not needed — project already has custom GOAP |
| godot-goap (viniciusgerevini) | Godot 4 | Clean GOAP example | Reference only — architecture already established |
| ReGoap-Godot | Godot/C# | C# GOAP implementation | Wrong language (project uses GDScript) |

**Decision:** Implement the prediction system as a new GDScript component (`PlayerPredictionComponent`) that integrates with the existing `EnemyMemory` and GOAP systems. No external libraries needed — the existing architecture provides all necessary infrastructure.

## Existing Architecture Analysis

### Current AI Flow (Pre-Prediction)

```
Player Visible? ─── YES ───> Update memory (confidence 1.0) ───> COMBAT/ENGAGE
       │
       NO
       │
       ├── Memory confidence > 0.8? ───> PURSUING (direct)
       ├── Memory confidence > 0.5? ───> PURSUING (cautious)
       ├── Memory confidence > 0.3? ───> SEARCHING (spiral pattern)
       └── Memory confidence < 0.05? ──> PATROL (lost target)
```

### Key Integration Points

1. **`EnemyMemory`** (`scripts/ai/enemy_memory.gd`) — Stores a single `suspected_position` with confidence. The prediction system extends this by generating *multiple* hypotheses about where the player could be.

2. **GOAP World State** (`enemy.gd:_update_goap_state()`) — Currently exposes `has_suspected_position`, `position_confidence`, and confidence level flags. New prediction state will be added.

3. **GOAP Actions** (`scripts/ai/enemy_actions.gd`) — Investigation actions already exist for high/medium/low confidence. New prediction-aware actions will allow enemies to check predicted positions.

4. **Cover System** (`scripts/components/cover_component.gd`) — Already evaluates cover quality with raycasting. The prediction system reuses this to identify likely player cover positions.

5. **Sound Detection** (`enemy.gd:on_sound_heard_with_intensity()`) — Already updates memory. Prediction system uses shot direction data for estimating post-shot repositioning.

## Solution Design

### Architecture: PlayerPredictionComponent

A new `RefCounted` class `PlayerPredictionComponent` that generates player position hypotheses based on:

1. **Retreat Path Analysis** — Find cover positions near last known player position, weighted by distance and player's last velocity direction.

2. **Flank Position Detection** — Calculate positions perpendicular to and behind the enemy, checking if the player could have moved there.

3. **Shot Direction Memory** — Track the player's last shooting direction to predict post-shot repositioning.

4. **Time-Distance Expansion** — Expand possible area based on `PLAYER_SPEED * time_elapsed`, pruned by navigation constraints.

5. **Behavioral Style Tracking** — Classify player as aggressive/cautious/cunning based on observed action frequencies, adjusting hypothesis weights accordingly.

### Hypothesis System

```gdscript
# Each hypothesis represents a predicted player position
var hypotheses: Array[Dictionary] = [
    {"position": Vector2, "type": "cover", "probability": 0.4},
    {"position": Vector2, "type": "flank_left", "probability": 0.2},
    {"position": Vector2, "type": "flank_right", "probability": 0.2},
    {"position": Vector2, "type": "last_direction", "probability": 0.2}
]
```

### GOAP Integration

New world state keys:
- `has_prediction`: Whether predictions are available
- `prediction_confidence`: Confidence in best prediction (0-1)
- `predicted_player_aggressive`: Player predicted to be aggressive
- `predicted_player_cautious`: Player predicted to be cautious

New GOAP action:
- `InterceptPredictedPositionAction`: Move to the most probable predicted position

### Multi-Agent Coordination

When multiple enemies have predictions, they share via the existing intel system:
- Enemies exchange their best hypotheses
- Coordinated checking: if one enemy checks position A, others prioritize position B
- Intel sharing confidence is reduced by factor (0.9) as with existing system

## Files Changed

| File | Change |
|------|--------|
| `scripts/ai/player_prediction_component.gd` | **NEW** — Core prediction logic |
| `scripts/ai/enemy_actions.gd` | Add `InterceptPredictedPositionAction` |
| `scripts/ai/enemy_memory.gd` | Add velocity tracking and shot direction fields |
| `scripts/objects/enemy.gd` | Integrate prediction component, update GOAP state |
| `tests/unit/test_player_prediction.gd` | **NEW** — Unit tests for prediction |
| `tests/unit/test_enemy_actions.gd` | Update action count, add new action tests |
| `tests/unit/test_enemy_memory.gd` | Add tests for new velocity/shot tracking fields |

## References

- [F.E.A.R. GDC 2006 Talk](https://gdcvault.com/play/1013282/Three-States-and-a-Plan)
- [Killzone AI: Dynamic Procedural Combat Tactics](http://cse.unl.edu/~choueiry/Documents/straatman_remco_killzone_ai.pdf)
- [Game AI Pro - Influence Mapping](http://www.gameaipro.com/GameAIPro2/GameAIPro2_Chapter29_Escaping_the_Grid_Infinite-Resolution_Influence_Mapping.pdf)
- [Movement Prediction Algorithms (Thesis)](https://www.diva-portal.org/smash/get/diva2:952076/FULLTEXT02)
- [Self-Learning AI Movement Prediction](https://www.timguelke.net/blog/2023/10/22/self-learning-ai-movement-prediction-beyond-airstriker-genesis-to-multi-directional-predictions)
- [Godot NavigationServer2D Docs](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_introduction_2d.html)
