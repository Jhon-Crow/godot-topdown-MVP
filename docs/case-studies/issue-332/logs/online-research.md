# Online Research Summary for Issue #332

## Research Queries Performed

1. "tactical AI sector coverage game development enemies guard different directions"
2. "game AI enemies coordinated aiming threat direction tactical behavior"
3. "game AI enemy turn face attacker when hit damage response behavior"
4. "Godot field of view debug visualization cone facing direction"
5. "tactical shooter AI squad sector control angles coordinated defense"
6. "FEAR game AI flanking suppression fire tactical behavior implementation"

## Key Findings

### 1. Tactical AI and Sector Coverage

#### F.E.A.R. AI System (GDC 2006)
Source: https://gdcvault.com/play/1013282/Three-States-and-a-Plan

**Core Architecture**: "Three States and a Plan"
- NPCs use a Goal-Oriented Action Planning (GOAP) system
- Goals: "Patrol", "Kill Enemy", "Ambush"
- Actions: "Reload", "Suppression Fire", etc.

**Squad Behaviors**:
1. Get-to-Cover: All soldiers into cover while laying suppression fire
2. Advance-Cover: Move closer with suppression
3. Orderly-Advance: File movement, each covering different side
4. Search: Groups of two, systematic sweep

**Key Quote**: "Assign behaviors to individuals such as laying suppression fire, moving into position, or following orders. This approach with a central coordinator is easier to implement and debug than just having the soldiers try to collaborate with each other locally."

#### Killzone Waypoint System
Source: http://cse.unl.edu/~choueiry/Documents/straatman_remco_killzone_ai.pdf

Each waypoint contains:
- 24-byte array for visibility data
- Each byte = distance to sight-blocking obstacle in one direction
- Allows quick cover testing without line-of-sight checks

**Position Evaluation Functions**:
- Safety/concealment at location during path-finding
- Relevance and priority of goals
- Threat classification

#### Combat Manager Pattern
Source: https://www.gamedev.net/forums/topic/704518-enemy-comunication/

"Creating a combat manager/attacker manager associated with the player creates a list of distinct valid spots for enemies. When an enemy decides to attack, it requests a free space from the manager object and registers itself as the occupant."

**Influence Maps**:
- Enforce spacing between agents
- Reference: Game AI Pro - "Modular Tactical Influence Maps"

### 2. Damage Response Behavior

Source: https://kolosdev.com/2025/07/29/shooter-tutorial-base-enemy-hit-reactions-behavior-tree/

**Standard Implementation**:
1. Store attacker's position/direction when damage is received
2. In hit/stunned state, rotate enemy to face that direction
3. Transition to "alert" or "combat" state targeting that attacker

**FSM Design Note**: "The enemy can transition to a StunnedState practically from any other state (apart from dead state). That's because it is assumed that players can hit enemies regardless of the state they are in."

**Hit Reaction Components**:
- Bounce back with force opposite to attack direction
- Momentary stun/invincibility frames
- Visual feedback (flash, particle effects)
- Audio feedback (grunt, impact sound)

### 3. Vision Cone Visualization in Godot

#### Available Plugins

**Vision Cone 2D** (Godot Asset Library)
- URL: https://godotengine.org/asset-library/asset/1568
- Uses raycast in uniform directions algorithm
- DebugDraw node for editor visualization
- Configurable for stealth games

**godot-vision-cone** (GitHub)
- URL: https://github.com/d-bucur/godot-vision-cone
- Similar functionality
- Open source, MIT license

**godot-field-of-view** (GitHub)
- URL: https://github.com/godot-addons/godot-field-of-view
- 2D Field of View algorithm in GDScript

**Shader Approach**
- URL: https://godotshaders.com/shader/shooting-cone/
- Canvas item shader
- Parameters: cone_angle (0.1-360), start_angle, fading, outlines

### 4. Squad Tactical Behavior

#### Close Combat: First to Fight
Source: https://www.gamedev.net/tutorials/programming/artificial-intelligence/close-quarters-development-realistic-combat-ai-part-1-r5156/

Squad members:
- Automatically scanned blind spots
- Covered areas
- Assumed 360-degree firing positions
- Shifted positions based on player
- Executed precision room-clearing

#### Six Days in Fallujah
Source: https://thebigbois.com/news/inside-the-command-and-control-update-for-six-days-in-fallujah-new-ai-mechanics-immersive-tactical-controls-and-more/

- Procedural architecture
- AI fireteam controls
- Draws from SOCOM and Ghost Recon
- Players can influence AI's every movement

### 5. Adaptive Enemy AI Examples

#### Metal Gear Solid V
- Enemies wear helmets if you favor headshots
- Deploy decoys if you rely on stealth
- Call backup if too aggressive
- Memorize approach routes
- Coordinate flanks
- Respond to weather/time-of-day

#### The Last of Us
- Military soldiers work in teams
- Communicate with one another
- Coordinate attack strategies based on player position
- Impressive line-of-sight system
- Set up ambushes

#### Halo
- Grunts act cowardly, retreat when outgunned
- Elites show advanced tactics
- Taking cover, coordinating attacks
- Flanking from multiple angles

## Implementation Patterns

### Pattern 1: Central Coordinator

```pseudocode
CombatManager:
    - Maintains list of enemies in area
    - Assigns sectors/positions to each
    - Tracks occupied spots
    - Provides "request position" API

Enemy:
    - Registers with CombatManager on spawn
    - Requests sector from manager
    - Faces assigned direction when idle
    - Reports changes (death, combat) to manager
```

### Pattern 2: Local Negotiation

```pseudocode
Enemy.update_sector():
    nearby = get_enemies_within_radius(200)
    covered_angles = [e.facing_angle for e in nearby]
    my_angle = find_largest_gap(covered_angles)
    face(my_angle)
```

### Pattern 3: Influence Map

```pseudocode
ThreatMap:
    buckets[360]  # One per degree

    update():
        # Add threat from passages
        for passage in detected_passages:
            buckets[passage.angle] += 0.3

        # Add threat from suspected player position
        if has_suspected_position:
            buckets[player.angle] += 1.0

        # Subtract friendly coverage
        for enemy in nearby_enemies:
            buckets[enemy.facing] -= 0.5

    get_best_direction():
        return angle_with_max_threat_value()
```

## Recommended Resources for Further Reading

1. **Game AI Pro** series (books)
   - "Modular Tactical Influence Maps"
   - Various chapters on squad tactics

2. **GDC Vault** (free videos)
   - F.E.A.R. AI talks
   - Killzone AI presentations

3. **AIGameDev.com** (archived)
   - "29 Tricks to Arm Your Game" (F.E.A.R. analysis)
   - Various tactical AI articles

4. **Gamasutra/GameDeveloper.com**
   - Enemy design articles
   - Melee combat AI systems
