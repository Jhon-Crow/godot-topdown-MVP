# Case Study: Improved Enemy Search Behavior (Issue #650)

## Problem Statement

The issue requests two improvements to enemy search behavior:
1. **Realistic looking behavior**: Enemies should look around more realistically when searching (sometimes looking in directions other than directly at the player's last known position)
2. **Coordinated group search**: When multiple enemies search for a player, each enemy should cover their own unique zone without duplicating areas for optimal search speed

## Current Implementation Analysis

### Search State (SEARCHING - Issue #322)
- Enemies use a **square spiral pattern** from the last known player position
- Each enemy generates waypoints independently using `_generate_search_waypoints()`
- At each waypoint, enemies scan by rotating at constant angular speed (`rotation += delta * 1.5`)
- **Problem**: Scanning is uniform and mechanical - always rotates at the same speed
- **Problem**: During SEARCHING state, enemies still face toward the player's actual position (Priority 2 in `_update_enemy_model_rotation()`) rather than scanning realistically

### Individual Zone Tracking
- Each enemy has `_search_visited_zones: Dictionary` to track visited 50px grid cells
- But there is **no coordination between enemies** - each enemy tracks only its own visits
- Multiple enemies searching the same area will overlap completely

### Intel Sharing
- Enemies share intel via `_share_intel_with_nearby_enemies()` every 0.5s
- Shares memory (suspected position + confidence) and prediction hypotheses
- But this does **NOT** share visited search zones

## Solution Design

### 1. Realistic Scanning Behavior
Instead of always facing the player during SEARCHING:
- Remove SEARCHING from Priority 2 rotation (currently forces facing toward actual player position)
- Add natural head/body scanning at each waypoint:
  - Random scan target angles (not just constant rotation)
  - Occasional pauses during scan
  - Sometimes look "wrong" direction before checking correct direction
  - Vary scan speed per waypoint

### 2. Coordinated Group Search (Voronoi-based Zone Assignment)
New `GroupSearchCoordinator` component (RefCounted, no scene needed):
- When multiple enemies enter SEARCHING with similar centers, they coordinate
- Uses **angle-sector division**: divides 360 degrees around search center by number of searching enemies
- Each enemy gets assigned a unique sector to search
- Enemies generate spiral waypoints only within their assigned sector
- When enemy finishes sector, takes unclaimed sectors or adjusts

### Key Algorithms
- **Voronoi-inspired zone division**: For N enemies searching around a center point, divide the area into N angular sectors. Each enemy's spiral pattern is constrained to their sector.
- **Realistic scanning**: Use randomized scan targets from a distribution weighted toward the search direction, with random "look-away" moments

## References

- [Voronoi Diagrams in Game Development](https://www.gamegeniuslab.com/tutorial-post/voronoi-diagrams-in-game-development-procedural-maps-ai-territories-stylish-effects/)
- [How to Use Voronoi Diagrams to Control AI](https://gamedevelopment.tutsplus.com/tutorials/how-to-use-voronoi-diagrams-to-control-ai--gamedev-11778)
- [Dynamic Guard Patrol in Stealth Games (AAAI)](https://ojs.aaai.org/index.php/AIIDE/article/download/7425/7308/10903)
- [Patrolling AI Systems in Video Games](https://www.researchgate.net/publication/364090728_Patrolling_AI_Systems_in_Video_Games)

## Implementation Files

| File | Changes |
|------|---------|
| `scripts/ai/group_search_coordinator.gd` | **NEW** - Coordinates zone assignment for group search |
| `scripts/objects/enemy.gd` | Modified - Integrate coordinator, fix scan rotation, add realistic scanning |
| `scripts/ai/enemy_actions.gd` | Modified - Add CoordinatedSearchAction |
| `tests/unit/test_group_search_coordinator.gd` | **NEW** - Unit tests |
