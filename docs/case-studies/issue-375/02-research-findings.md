# Research Findings: AI Grenade Throwing with Blast Radius Avoidance

## Online Research Summary

### Search Query 1: AI Grenade Throwing Algorithm Avoid Self Damage
**Key Findings:**
- Common issue in many games (S.T.A.L.K.E.R., Arma 3, Battlefield)
- AI often throws grenades too aggressively without self-preservation
- Many mods exist to fix AI grenade behavior in various games

**Sources:**
- [Steam: S.T.A.L.K.E.R. AI Grenade Accuracy Discussion](https://steamcommunity.com/app/41700/discussions/0/2828702373009282577/)
- [Steam: Arma 3 AI Grenade Spamming Issues](https://steamcommunity.com/app/107410/discussions/0/1744521521325105232/)
- [Steam Workshop: Drongo's Grenade Tweaks](https://steamcommunity.com/sharedfiles/filedetails/?id=3435581126)

### Search Query 2: Game AI Enemy Grenade Throw Trajectory Safe Distance
**Key Findings:**
- **Trajectory Calculation**: Physics-based trajectory prediction using:
  - Position formulas: `xf = x0 + s * cos(d) * t` and `yf = y0 + s * sin(d) * t - g * t²/2`
  - Ballistic planning with drag and wind considerations
  - Predictive targeting for moving targets
- **Trajectory Storage**: Store consecutive points of the curve for path validation
- **Academic Reference**: "Analytical Ballistic Trajectories with Approximately Linear Drag" by Giliam J. P. de Carpentier (2014)

**Sources:**
- [GameMaker: Grenade Toss Calculations](http://gmc.yoyogames.com/index.php?showtopic=478624)
- [Game Developer: Movement Prediction](https://www.gamedeveloper.com/programming/movement-prediction)
- [Game Developer: Predictive Aim Mathematics for AI Targeting](https://www.gamedeveloper.com/programming/predictive-aim-mathematics-for-ai-targeting)
- [Planning Ballistic Trajectories with Air Resistance](https://www.decarpentier.nl/ballistic-trajectories)
- [Godot Forums: Grenade Trajectory Coding](https://godotforums.org/d/34759-how-do-i-code-the-trajectory-for-throwing-grenades)
- [Medium: AI Projectile Intercept Formula](https://medium.com/andys-coding-blog/ai-projectile-intercept-formula-for-gaming-without-trigonometry-37b70ef5718b)

### Search Query 3: Godot Enemy AI Grenade Throwing Blast Radius
**Key Findings:**
- **Distance-Based Behavior**: AI can calculate player distance and move toward/away based on radius checks
- **Blast Radius Detection**: Sensors can check if entities are in blast radius
- **Avoidance Patterns**: AI can dodge obstacles by moving perpendicular to threat vectors
- **Component Separation**: Grenade throwing, distance calculations, and avoidance behavior are typically separate systems

**Sources:**
- [Godot Docs: FPS Tutorial Part 5](https://docs.godotengine.org/en/3.0/tutorials/3d/fps_tutorial/part_five.html)
- [Godot Forums: Grenade Throwing Discussion](https://godotforums.org/d/27109-how-to-throw-a-grenade)
- [Godot Forum: 3D Grenade Throwing](https://forum.godotengine.org/t/how-do-i-throw-a-grenage-in-a-3d-enviroment/255)
- [DEV Community: Godot 4 RPG Enemy AI Setup](https://dev.to/christinec_dev/lets-learn-godot-4-by-making-an-rpg-part-9-enemy-ai-setup-3nfl)
- [Medium: Building Complex NPC AI in Godot](https://medium.com/@kennethpetti/building-out-complex-npc-ai-in-godot-230ef3d956ad)
- [Gravity Ace: Coding Enemy AI in Godot](https://gravityace.com/devlog/drone-ai/)

## Industry Best Practices

### 1. Safe Distance Calculation
Most games implement a simple rule:
```
minimum_safe_throw_distance = blast_radius + safety_margin
```

Common safety margins:
- Conservative: 1.5x blast radius (337.5px for our 225px radius)
- Moderate: 1.2x blast radius (270px)
- Minimal: 1.1x blast radius (247.5px)

### 2. Trajectory Prediction (Advanced)
For games with complex physics:
- Calculate full grenade arc
- Check if enemy position intersects with blast radius at any point along trajectory
- Account for enemy movement during grenade flight time

### 3. Pre-Throw Positioning
- Enemy moves to safe position BEFORE throwing
- Part of tactical AI planning (GOAP action)
- Adds delay but increases realism

### 4. Post-Throw Behavior
- Enemy immediately seeks cover after throwing
- Enemy moves away from target area
- Combined with existing retreat/cover behaviors

## Solution Approaches

### Approach 1: Simple Distance Check (Recommended)
**Pros:**
- Minimal code changes
- No performance impact
- Easy to test and debug
- Maintains existing behavior

**Cons:**
- Doesn't account for enemy/player movement
- Doesn't consider complex trajectories

**Implementation:**
- Add check in `_execute_grenade_throw()` before throw
- Ensure `distance_to_target >= blast_radius + safety_margin`
- Log and skip throw if unsafe

### Approach 2: Trajectory Validation
**Pros:**
- More accurate safety calculation
- Accounts for grenade arc
- Professional-grade AI behavior

**Cons:**
- More complex implementation
- Higher computational cost
- May be overkill for this game's physics model

**Implementation:**
- Calculate grenade trajectory points
- Check if enemy position is within blast radius of landing point
- Consider flight time and enemy movement

### Approach 3: Pre-Throw Repositioning
**Pros:**
- Most realistic AI behavior
- Integrates with GOAP system
- Tactical and immersive

**Cons:**
- Requires new GOAP action
- Changes game pacing
- May make enemies too cautious

**Implementation:**
- Add "PrepareGrenadeThrow" GOAP action
- Enemy moves to safe position first
- Then executes throw

### Approach 4: Hybrid (Simple Check + Post-Throw Retreat)
**Pros:**
- Balance of safety and tactical behavior
- Uses existing retreat mechanics
- Minimal new code

**Cons:**
- Enemy may still be close to blast
- Relies on existing state machine

**Implementation:**
- Simple distance check (Approach 1)
- Trigger retreat/cover seeking after throw
- Set temporary "avoid explosion zone" goal

## Recommendation

**Use Approach 1 (Simple Distance Check) with the following parameters:**

```gdscript
const GRENADE_BLAST_RADIUS: float = 225.0  # From FragGrenade
const GRENADE_SAFETY_MARGIN: float = 50.0   # Extra buffer
const GRENADE_MIN_SAFE_DISTANCE: float = GRENADE_BLAST_RADIUS + GRENADE_SAFETY_MARGIN  # 275px
```

**Rationale:**
1. Solves the immediate problem (enemies damaging themselves)
2. Minimal implementation complexity
3. No performance impact
4. Easy to test and validate
5. Can be enhanced later with more sophisticated checks if needed

**Implementation Location:**
Modify `_execute_grenade_throw()` in `scripts/objects/enemy.gd` to add safety check before calculating throw.

**Additional Enhancement:**
Update existing minimum throw distance from 150px to 275px to prevent any edge cases.
