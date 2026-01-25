# References for Issue #349

## Online Sources

### Ricochet and Reflection Algorithms

1. **Ray Reflection Tutorial (Roblox)**
   - URL: https://devforum.roblox.com/t/how-to-reflect-rays-on-hit/18143
   - Key takeaway: Reflection formula `r = d - 2(d ⋅ n)n`

2. **Godot Ray Reflection Forum**
   - URL: https://godotforums.org/d/26153-how-can-i-bounce-reflect-a-raycast
   - Key takeaway: GDScript examples for ray reflection in Godot

3. **Corona Ray Casting Tutorial**
   - URL: https://docs.coronalabs.com/tutorial/games/rayCasting/index.html
   - Key takeaway: Complete tutorial on ray casting and reflection for games

4. **Introduction to Ray Casting in 2D Game Engines**
   - URL: https://sszczep.dev/blog/ray-casting-in-2d-game-engines
   - Key takeaway: Mathematical foundations of 2D raycasting

### Billiards AI and Bank Shots

5. **PoolTool: The Algorithmic Theory Behind Billiards Simulation**
   - URL: https://ekiefl.github.io/2020/12/20/pooltool-alg/
   - Key takeaway: Event-based simulation, analytical trajectory equations

6. **PoolTool: Physics of Pool/Billiards**
   - URL: https://ekiefl.github.io/2020/04/24/pooltool-theory/
   - Key takeaway: Ball-cushion interactions and reflection physics

7. **Engineering the Perfect Pool Shot (USC Viterbi)**
   - URL: https://illumin.usc.edu/engineering-the-perfect-pool-shot/
   - Key takeaway: Geometry of bank shots and approach angles

8. **Beyond 8-Ball: Realistic Billiards AI for Indie Games**
   - URL: https://www.wayline.io/blog/realistic-billiards-ai-for-indie-games
   - Key takeaway: AI shot selection algorithms for billiards

9. **AI Optimization of a Billiard Player (PDF)**
   - URL: https://www.researchgate.net/publication/225328639_AI_Optimization_of_a_Billiard_Player
   - Key takeaway: Monte-Carlo and probabilistic search for shot selection

### Wall Penetration (Wallbang) Mechanics

10. **Counter-Strike Wiki: Bullet Penetration**
    - URL: https://counterstrike.fandom.com/wiki/Bullet_Penetration
    - Key takeaway: Penetration power, material types, damage reduction

11. **How Wallbangs Work in CS2 (cs.money)**
    - URL: https://cs.money/blog/games/death-through-the-wall/
    - Key takeaway: Weapon penetration levels (100%, 200%), material effects

12. **Steam Guide: How Does Bullet Penetration Work?**
    - URL: https://steamcommunity.com/sharedfiles/filedetails/?id=275573090
    - Key takeaway: Penetration power values, max surfaces (4), damage calculation

13. **CS:GO SDK Tutorial - Terminal Ballistics**
    - URL: https://www.worldofleveldesign.com/categories/csgo-tutorials/csgo-terminal-ballistics-bullet-penetration.php
    - Key takeaway: Testing commands (`sv_showimpacts_penetration`), level design considerations

### AI Targeting and Prediction

14. **Predictive Aim Mathematics for AI Targeting (Game Developer)**
    - URL: https://www.gamedeveloper.com/programming/predictive-aim-mathematics-for-ai-targeting
    - Key takeaway: Lead prediction equations, solving for projectile velocity

15. **Adaptive Shooting for Bots in FPS Games (arXiv)**
    - URL: https://arxiv.org/pdf/1806.05554
    - Key takeaway: Reinforcement learning for shooting adaptation

16. **Human-like Bots for Tactical Shooters (arXiv)**
    - URL: https://arxiv.org/html/2501.00078v1
    - Key takeaway: Compute-efficient sensors and human-like behavior

17. **Reinforcement Learning Applied to AI Bots in FPS (MDPI)**
    - URL: https://www.mdpi.com/1999-4893/16/7/323
    - Key takeaway: Systematic review of RL for FPS bots

### Line of Sight and Detection

18. **Unity Enemy Line of Sight with Raycast2D**
    - URL: https://discussions.unity.com/t/enemy-line-of-sight-with-raycast2d/865347
    - Key takeaway: Raycast for visibility, avoiding "seeing through walls"

19. **How to Use RayCast2D Nodes for Line-of-Sight Detection in Godot**
    - URL: https://www.makeuseof.com/godot-raycast2d-nodes-line-of-sight-detection/
    - Key takeaway: Godot-specific implementation for LOS detection

20. **Giving Enemies the Power of Sight (Unity School)**
    - URL: https://unity.grogansoft.com/enemies-that-can-see/
    - Key takeaway: Three components of vision: range, direction, LOS

### General Pathfinding and AI

21. **A Systematic Review of Intelligence-Based Pathfinding Algorithms (MDPI)**
    - URL: https://www.mdpi.com/2076-3417/12/11/5499
    - Key takeaway: Static vs dynamic pathfinding categories

22. **Tactical Pathfinding on a NavMesh (Game AI Pro)**
    - URL: http://www.gameaipro.com/GameAIPro/GameAIPro_Chapter27_Tactical_Pathfinding_on_a_NavMesh.pdf
    - Key takeaway: Tactical considerations in pathfinding

23. **Some Experiments in Pathfinding + AI (Game Developer)**
    - URL: https://www.gamedeveloper.com/programming/some-experiments-in-pathfinding-ai
    - Key takeaway: Diffusion/heat map method for efficient pathfinding

---

## Codebase References

### Existing Ricochet System

- **File:** `scripts/projectiles/bullet.gd`
- **Key functions:**
  - `_try_ricochet()` (line 367): Attempts ricochet on collision
  - `_get_surface_normal()` (line 417): Gets surface normal via raycast
  - `_calculate_impact_angle()` (line 442): Calculates grazing angle
  - `_calculate_ricochet_probability()` (line 466): Probability based on angle
  - `_perform_ricochet()` (line 494): Executes the ricochet

### Existing Penetration System

- **File:** `scripts/projectiles/bullet.gd`
- **Key functions:**
  - `_try_penetration()` (line 725): Attempts wall penetration
  - `_can_penetrate()` (line 754): Checks if caliber allows penetration
  - `_get_max_penetration_distance()` (line 763): Gets max penetration distance
  - `_is_still_inside_obstacle()` (line 781): Checks if still inside wall
  - `_exit_penetration()` (line 820): Handles exiting penetrated wall

### Caliber Data

- **File:** `scripts/data/caliber_data.gd`
- **Key properties:**
  - `can_ricochet`, `max_ricochets`, `max_ricochet_angle`
  - `base_ricochet_probability`, `velocity_retention`, `ricochet_damage_multiplier`
  - `can_penetrate`, `max_penetration_distance`, `post_penetration_damage_multiplier`

### Enemy AI

- **File:** `scripts/objects/enemy.gd`
- **Key functions:**
  - `_shoot()` (line 3974): Main shooting function
  - `_calculate_lead_prediction()` (line 4114): Predicts player position
  - `_should_shoot_at_target()` (line 3172): Validates shot target
  - Cover raycasts array (line 248): Existing raycast infrastructure

### Tests

- **File:** `tests/unit/test_ricochet.gd` - Ricochet mechanics tests
- **File:** `tests/unit/test_penetration.gd` - Penetration mechanics tests
- **File:** `tests/unit/test_enemy.gd` - Enemy behavior tests

---

## Mathematical Formulas

### Reflection Formula
```
r = d - 2(d ⋅ n)n
```
Where:
- `r` = reflected direction vector
- `d` = incoming direction vector
- `n` = surface normal vector

### Mirror Point Across Line
```
mirror = point - 2 * (point - line_point).dot(line_normal) * line_normal
```

### Ricochet Probability (5.45x39mm curve)
```
probability = base_probability × (0.9 × (1 - (angle/90)^2.17) + 0.1)
```
Where angle is the grazing angle in degrees (0° = parallel to surface).

### Lead Prediction
```
predicted_pos = player_pos + player_velocity × time_to_target
time_to_target = distance / bullet_speed
```
(Iterated 3 times for convergence)

### Penetration Damage
```
damage_after = original_damage × (post_penetration_multiplier)^(walls_penetrated)
```
