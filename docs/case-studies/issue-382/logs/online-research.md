# Online Research Summary for Issue #382

## Research Queries Performed

1. "tactical AI grenade throwing enemy behavior game programming 2024 2025"
2. "Godot 4 enemy AI grenade throwing implementation tutorial"
3. "GOAP goal oriented action planning grenade throwing game AI behavior"
4. "squad tactical AI coordination team behavior enemy flanking clearing room game development"
5. "AI team coordination before attack grenade callout friendly fire avoidance game development"
6. "blast radius grenade AI evacuation danger zone fleeing game development NPC"
7. "enemy assault after grenade explosion coordinated attack breach room clearing AI"

## Key Findings

### 1. Killzone AI: Dynamic Procedural Combat Tactics

**Source**: [Killzone AI Paper](http://cse.unl.edu/~choueiry/Documents/straatman_remco_killzone_ai.pdf)

#### Grenade Coordination System

The Killzone AI implements a sophisticated grenade system:

> "To generate suitable grenade destinations, the AI performs several steps. First it checks whether a hand grenade attack is safe, for example, based on the distance and proximity of friendly units."

> "The result is an AI capability to surprise and attack out-of-sight threats by delivering grenades near them through windows, or into alleys or trenches, without consuming many ray casts."

#### Key Implementation Details

1. **Safety Check**: Verify friendly units are not in blast zone before throwing
2. **Trajectory Calculation**: Test multiple trajectories (up to 60 degrees from direct line)
3. **Indirect Fire**: Grenades can be bounced off walls for tactical advantage
4. **Out-of-Sight Attacks**: Grenades used specifically against hidden targets

> "One major challenge is having bots use grenades intelligently. Grenade handling is much more complicated than shooting because grenades can be bounced off walls, have an area effect, and take time to throw."

---

### 2. F.E.A.R. AI: Goal-Oriented Action Planning

**Source**: [Building the AI of F.E.A.R.](https://www.gamedeveloper.com/design/building-the-ai-of-f-e-a-r-with-goal-oriented-action-planning)

#### GOAP Architecture

> "GOAP is an artificial intelligence system for autonomous agents that allows them to dynamically plan a sequence of actions to satisfy a set goal."

> "The sequence of actions selected by the agent is contingent on both the current state of the agent and the current state of the world, hence despite two agents being assigned the same goal; both agents could select a completely different sequence of actions."

#### Grenade in GOAP Context

The "Throw" action in GOAP represents: "Why shoot if you can blow them up with a grenade."

Key GOAP concepts applicable to grenade coordination:
- **Preconditions**: e.g., `has_grenades`, `allies_clear_of_zone`
- **Effects**: e.g., `grenade_in_flight`, `player_flushed`
- **Cost calculation**: Dynamic based on situation

#### Squad Behaviors

F.E.A.R. pioneered cohesive squad AI:
> "Player locations were shouted, enemies would call in reinforcements, issue flanking commands, suppress and fire grenades, and even indicate how many of their squad was left alive after an assault."

---

### 3. Valve Combine Soldier AI: Squad Slots

**Source**: [Valve Developer Community](https://developer.valvesoftware.com/wiki/AI_Learning:_CombineSoldier)

#### Slot-Based Coordination

> "Combine soldiers often work in squads together and flank the player by spreading around and using frag grenades. Squad slots are the way squad-based NPCs operate, allowing NPCs to trade roles and take turns."

#### Grenade Slot System

```
SQUAD_SLOT_GRENADE1
SQUAD_SLOT_SPECIAL_ATTACK
```

> "Whenever these slots are used they'll stop the entire squad from committing similar attacks for a period of time."

This prevents multiple grenades being thrown simultaneously and ensures coordination.

---

### 4. Days Gone: Squad Coordination with Frontlines

**Source**: [Game AI Pro - Squad Coordination in Days Gone](http://www.gameaipro.com/GameAIProOnlineEdition2021/GameAIProOnlineEdition2021_Chapter12_Squad_Coordination_in_Days_Gone.pdf)

#### Frontline Concept

> "Days Gone uses a special construct called a 'Frontline' that describes the spatial relationship between a Squad and its enemies and is used to answer all spatial questions needed to coordinate the Squad."

#### Confidence-Based Behavior

> "A squad's confidence is determined by calculating each side's strengths, which can be modified by weapons, armor, health, and confidence, meaning a confident AI will lift up the squad's confidence."

> "If confidence is low, the AI will try to retreat, and if it's high, the squad will go on the offensive."

This maps well to the post-grenade assault requirement.

---

### 5. Blackboard Systems for Inter-AI Communication

**Source**: NOLF 2 AI Architecture

> "To coordinate multiple agents, NOLF 2 uses a Blackboard System. A Blackboard System is a shared object that allows inter-agent communication through posting and querying public information."

#### Record Structure
- ID of posting agent
- ID of target object
- Record information

This pattern is ideal for grenade throw announcements:
```
GrenadeWarning {
    thrower_id: int
    target_position: Vector2
    blast_radius: float
    time_to_impact: float
}
```

---

### 6. UE4 AI FPS Implementation

**Source**: [GitHub - mtrebi/AI_FPS](https://github.com/mtrebi/AI_FPS)

#### Shared Data for Coordination

> "To create a feeling of group within NPCs, shared data between them simulates communication. For example, each bot's attack position is shared and known by all other bots, allowing them to calculate new positions different from others to maximize spread when attacking."

> "This same technique is used to attack, flank, cover, search, and suppress."

This approach can be adapted for evacuation coordination - each enemy knows where others are evacuating to avoid collisions.

---

### 7. Room Clearing Tactics (Military Reference)

**Source**: [U.S. Marine Corps Urban Operations Manual](https://www.trngcmd.marines.mil/Portals/207/Docs/TBS/B4R5379%20Urban%20Ops%20II%20Offense%20and%20Defense%20Operations.pdf)

#### Breach, Bang, and Clear

> "An American armed forces assault tactic for clearing a room by forcing open the door and throwing in a smoke grenade or flashbang in order to incapacitate the enemy before entering."

#### Grenade Employment Protocol

> "To alert all that a grenade will be thrown, a visual showing of the grenade is made to assault element members, and a visual acknowledgment from them is received."

This maps directly to the issue requirement for pre-throw communication.

#### Post-Grenade Entry

> "Fragmentation and/or concussion grenades are the preparatory fires used before the assault."

> "The first action to be taken by the soldier upon entry into a room is to clear the fatal funnel—that area which surrounds the door threshold."

---

### 8. Ready or Not AI Implementation

**Source**: [Steam Community Guide](https://steamcommunity.com/sharedfiles/filedetails/?id=3494083514)

#### AI Tactical Behavior

> "Watch your AI – they clear in slices. First two clear corners, second two push deeper."

> "Rely on solid tactics like using mirrors, wedges, team positioning, and grenades to avoid unnecessary firefights."

This demonstrates how grenades fit into a coordinated tactical sequence.

---

## Implementation Patterns Discovered

### Pattern 1: Pre-Throw Safety Check

```pseudocode
func prepare_grenade_throw(target: Vector2) -> bool:
    # Check all allies
    for ally in nearby_allies:
        if is_in_blast_zone(ally.position, target, blast_radius):
            # Cannot throw - ally in danger
            return false
        if is_in_throw_trajectory(ally.position, my_position, target):
            # Cannot throw - ally in trajectory
            return false
    return true
```

### Pattern 2: Evacuation Notification

```pseudocode
func announce_grenade_throw(target: Vector2):
    # Create warning record
    var warning = GrenadeWarning.new(self, target, blast_radius)

    # Broadcast to blackboard/coordinator
    TacticalCoordinator.post_grenade_warning(warning)

    # Wait for allies to acknowledge/evacuate
    await allies_cleared_zone()

    # Execute throw
    execute_throw(target)
```

### Pattern 3: Squad Slot for Grenades

```pseudocode
class SquadSlots:
    var grenade_slot_occupied: bool = false
    var grenade_cooldown: float = 0.0

    func request_grenade_slot(requester: Enemy) -> bool:
        if grenade_slot_occupied or grenade_cooldown > 0:
            return false
        grenade_slot_occupied = true
        return true

    func release_grenade_slot():
        grenade_slot_occupied = false
        grenade_cooldown = 5.0  # Squad-wide cooldown
```

### Pattern 4: Coordinated Assault Timing

```pseudocode
class AssaultCoordinator:
    var waiting_enemies: Array = []
    var grenade_in_flight: bool = false

    func register_waiting_enemy(enemy: Enemy):
        waiting_enemies.append(enemy)

    func on_grenade_exploded(position: Vector2):
        # Trigger assault for all waiting enemies
        for enemy in waiting_enemies:
            enemy.begin_assault(position)
        waiting_enemies.clear()
```

### Pattern 5: Evacuation Direction Calculation

```pseudocode
func calculate_evacuation_direction(my_pos: Vector2, blast_center: Vector2) -> Vector2:
    # Primary: Direct away from blast
    var away_direction = (my_pos - blast_center).normalized()

    # Check if path is clear
    if is_path_blocked(my_pos, my_pos + away_direction * safe_distance):
        # Find alternative: perpendicular directions
        var left = away_direction.rotated(PI/2)
        var right = away_direction.rotated(-PI/2)

        if not is_path_blocked(my_pos, my_pos + left * safe_distance):
            return left
        elif not is_path_blocked(my_pos, my_pos + right * safe_distance):
            return right

    return away_direction
```

---

## Relevant Libraries and Plugins

### 1. GOAP for Unity (Reference Implementation)

**GitHub**: https://github.com/crashkonijn/GOAP

Multi-threaded GOAP system with:
- Sensor system for world state
- Action preconditions and effects
- Goal selection
- Plan visualization

While for Unity, the concepts translate directly to Godot.

### 2. AI FPS for Unreal Engine

**GitHub**: https://github.com/mtrebi/AI_FPS

Behavior tree implementation with:
- Squad coordination
- Grenade usage
- Cover seeking
- Flanking behavior

Provides visual reference for tactical AI patterns.

### 3. Godot Vision Cone 2D

**Asset Library**: https://godotengine.org/asset-library/asset/1568

Could be useful for:
- Visualizing grenade throw trajectories
- Debugging blast zone coverage

---

## Key Takeaways for Implementation

1. **Safety First**: Always check ally positions before grenade actions
2. **Communication System**: Use blackboard/coordinator pattern for announcements
3. **Slot System**: Prevent multiple simultaneous grenade throws
4. **Evacuation Priority**: Make evacuation highest priority action
5. **Assault Coordination**: Use explosion as trigger for synchronized assault
6. **Fallback Paths**: Calculate alternative evacuation routes when primary blocked
7. **GOAP Integration**: Implement as GOAP actions with proper preconditions/effects

---

## References

### Primary Sources

1. Killzone AI Paper - http://cse.unl.edu/~choueiry/Documents/straatman_remco_killzone_ai.pdf
2. F.E.A.R. GDC Talk - https://gdcvault.com/play/1013282/Three-States-and-a-Plan
3. Building the AI of F.E.A.R. - https://www.gamedeveloper.com/design/building-the-ai-of-f-e-a-r-with-goal-oriented-action-planning
4. Days Gone Squad Coordination - http://www.gameaipro.com/GameAIProOnlineEdition2021/GameAIProOnlineEdition2021_Chapter12_Squad_Coordination_in_Days_Gone.pdf
5. Close Quarters Development - https://www.gamedev.net/articles/programming/artificial-intelligence/close-quarters-development-realistic-combat-ai-part-1-r5156/
6. Valve Combine Soldier AI - https://developer.valvesoftware.com/wiki/AI_Learning:_CombineSoldier

### Godot Resources

1. Enemy AI Tutorial - https://dev.to/christinec_dev/lets-learn-godot-4-by-making-an-rpg-part-9-enemy-ai-setup-3nfl
2. Godot Documentation - https://docs.godotengine.org/en/stable/getting_started/first_2d_game/04.creating_the_enemy.html
3. Vision Cone Asset - https://godotengine.org/asset-library/asset/1568

### GitHub Repositories

1. GOAP for Unity - https://github.com/crashkonijn/GOAP
2. AI FPS (UE4) - https://github.com/mtrebi/AI_FPS
