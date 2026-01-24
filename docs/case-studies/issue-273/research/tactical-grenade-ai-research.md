# Tactical Grenade AI Research

## Sources

- [Close Quarters Development: Realistic Combat AI - GameDev.net](https://www.gamedev.net/tutorials/programming/artificial-intelligence/close-quarters-development-realistic-combat-ai-part-1-r5156/)
- [Killzone's AI: dynamic procedural combat tactics](http://cse.unl.edu/~choueiry/Documents/straatman_remco_killzone_ai.pdf)
- [Unreal Engine Enemy NPC AI Behavior Tree - Grenade Throwing Improvements](https://www.codelikeme.com/2022/03/unreal-engine-enemy-npc-ai-behavior.html)
- [GOAP and Utility AI in Grab n' Throw - Golden Syrup Games](https://goldensyrupgames.com/blog/2024-05-04-grab-n-throw-utility-goap-ai/)
- [Game AI Planning: GOAP, Utility, and Behavior Trees](https://tonogameconsultants.com/game-ai-planning/)
- [Goal-Oriented Action Planning - Medium](https://medium.com/@vedantchaudhari/goal-oriented-action-planning-34035ed40d0b)
- [GOAP in Game AI: Using Utility and Planning for Smarter NPCs](https://tonogameconsultants.com/goap/)
- [GitHub - crashkonijn/GOAP: A multi-threaded GOAP system for Unity](https://github.com/crashkonijn/GOAP)

## Key Findings

### 1. Grenade Throwing AI Design Principles

#### Challenge
Grenade handling is much more complicated than shooting because:
- Grenades can be bounced off walls
- They have an area effect
- They take time to throw
- There's a fuse delay before explosion

#### Solution: Opportunistic Approach
"The bots' grenade use is therefore opportunistic as a bot will not move to a position specifically to throw a grenade. However, the path that a bot chooses to attack an enemy will often also be a sensible path from which to throw a grenade."

### 2. Killzone's Position Picking System

Killzone's approach to indirect fire (grenades, missiles):
1. Check whether grenade attack is safe (distance, proximity of friendlies)
2. Generate suitable grenade destinations using position evaluation
3. Deliver grenades through windows, into alleys or trenches
4. Minimize ray cast consumption

### 3. GOAP for Tactical Decisions

GOAP (Goal Oriented Action Planning) was popularized in F.E.A.R. (2005):
- "A* pathfinding, except the destination is your desired world state"
- Actions have costs evaluated dynamically
- Preconditions prevent impossible actions
- Well-suited for "adaptive combat or dynamic NPCs"

#### Example: Grenade Decision in GOAP
"Why shoot if you can blow them up with a grenade" - grenades as alternative action with different cost evaluation.

### 4. Enemy Coordination Patterns

#### Flanking and Suppression
- Use suppressing fire to pin down player
- Throw grenades to flush player out of cover
- Flanking often emerges from good position evaluation

#### Spacing and Positioning
- Penalty for picking positions too close to other units
- Influence maps to enforce spacing between agents
- Limit number of shooters attacking player at a time

#### Priority Systems
- Blind following: always execute order
- Follow orders: postpone only in direct danger (e.g., grenade danger area)

### 5. Reactive Behaviors

Players expect tactical AI to:
- Search for players when they hide
- Throw grenades to flush player out of cover
- Look for vantage points in multi-level spaces
- Take cover before vulnerable actions (reloading, throwing grenades)

### 6. Combining GOAP with Utility AI

Best practice pattern:
- **Utility AI**: "what to do" (which goal is most important)
- **GOAP**: "how to do it" (plan sequence of actions to reach goal)

"GOAP knows how to reach a goal, but it doesn't know which goal should come first. Utility gives each goal a score based on urgency."

## Relevant to Issue #273

The issue requirements align well with established game AI patterns:

| Requirement | Industry Pattern |
|-------------|------------------|
| Notify allies about grenade throw | Enemy coordination, spacing systems |
| Find cover that protects from player | Position evaluation with raycast checking |
| Random deviation in throw | Realistic accuracy modeling |
| Wait for explosion, then assault | State machine with trigger events |
| React to player suppression | Reactive AI with state transitions |
| React to sound cues (reload, sustained fire) | Audio-based perception triggers |

## Implementation Recommendations

1. **Add Grenade GOAP Action** to existing `enemy_actions.gd`:
   - Preconditions: has_grenades, player_in_range, safe_to_throw
   - Effects: player_damaged, area_cleared
   - Cost: variable based on friendlies nearby, player position

2. **Ally Notification System**:
   - Broadcast to nearby allies when entering throw mode
   - Use existing cover_component to find evacuation positions

3. **Throw Mode Triggers** as Utility evaluation:
   - Player suppressed enemies -> high utility
   - Player killing multiple -> high utility
   - Heard reload sound -> medium utility
   - Low HP -> emergency utility

4. **Post-Explosion Assault**:
   - Wait for explosion signal
   - Transition to ASSAULT state
   - Move through cleared passage
