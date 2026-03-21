# Case Study: Issue #1227 — Optimize Combat Enemy Movement with Pre-defined Paths

## Issue Summary

**Title (RU):** оптимизируй перемещение боевых врагов
**Title (EN):** Optimize combat enemy movement

**Request:**
Pre-define paths on the map that enemies use in combat states (all except IDLE and SEARCHING). In those states, the enemy should pick the nearest "attacking" or "retreating" path and follow it.

Implement for the **Building (Здание)** map as a test case.

---

## Problem Analysis

### Current State

The current enemy AI in `scripts/objects/enemy.gd` uses the following approach for combat movement:

1. **PURSUING state** — `_find_pursuit_cover_toward_player()`: Casts 16 raycasts in all directions every frame to find suitable cover obstacles toward the player. Scores each candidate based on distance, hidden status, flashlight penalty, and obstacle diversity. Very expensive with 20+ active enemies.

2. **FLANKING state** — `_find_flank_cover_toward_target()`: Similar raycast-based approach, finding cover positions at an angle to flank the player.

3. **SEEKING_COVER state** — Finds the nearest cover using raycasts from the enemy's current position.

4. **COMBAT state** — When approaching, uses `_move_to_target_nav()` directly toward player.

5. **RETREATING state** — Moves toward a pre-found cover while possibly shooting.

### Pain Points

- **Performance**: 16 raycasts per enemy per frame (or per 0.3s cooldown) is expensive. With 10 enemies in BuildingLevel and up to 20+ in some levels, this is a significant overhead.
- **Predictability**: Enemies can get stuck or make suboptimal decisions due to dynamic cover search failures.
- **Navigation**: Dynamic cover search can produce positions that are unreachable or blocked by geometry.

---

## Solution Design

### Approach: Pre-defined CombatPath nodes

Add `Node2D` "combat path" nodes to each level map. Two types:
- **AttackingPath** — waypoints enemies use when advancing toward the player (PURSUING, COMBAT, FLANKING, ASSAULT states)
- **RetreatPath** — waypoints enemies use when retreating/seeking cover (RETREATING, SEEKING_COVER, SUPPRESSED, IN_COVER states)

Each path consists of `Marker2D` children as waypoints.

A new component `CombatPathComponent` (GDScript, attached as a singleton or autoload) provides:
- `get_nearest_attacking_waypoint(from_pos, toward_player_pos)` — Returns the nearest attacking-path waypoint that advances toward the player
- `get_nearest_retreat_waypoint(from_pos, from_player_pos)` — Returns the nearest retreat-path waypoint that puts distance from the player

The enemy AI queries this component when entering combat states. If a pre-defined path waypoint is found, it is used as the primary movement target instead of the expensive raycast cover-search.

### Implementation Plan

1. **`scripts/components/combat_path_component.gd`** — New script:
   - `register_attacking_path(path_node: Node2D)` — Collect waypoints from AttackingPath nodes
   - `register_retreat_path(path_node: Node2D)` — Collect waypoints from RetreatPath nodes
   - `get_nearest_attacking_waypoint(from, toward)` → `Vector2` or `Vector2.ZERO`
   - `get_nearest_retreat_waypoint(from, away_from)` → `Vector2` or `Vector2.ZERO`
   - Called from level scripts or registered as child of the level root

2. **`scenes/levels/BuildingLevel.tscn`** — Add path nodes:
   - `AttackingPaths` group containing paths for corridors and rooms
   - `RetreatPaths` group containing paths back to initial positions or behind cover

3. **`scripts/objects/enemy.gd`** — Integration:
   - New export `@export var use_combat_paths: bool = true`
   - New var `_combat_path_component: Node = null`
   - In `_ready()`, find CombatPathComponent in the scene
   - In `_find_pursuit_cover_toward_player()`: if combat_path_component has a waypoint near the player direction, use it
   - In `_find_flank_cover_toward_target()`: similar integration

---

## Existing Codebase Patterns

- **PatrolPath**: Enemies already use `patrol_offsets: Array[Vector2]` for patrol points — same concept, extended to combat
- **NavigationAgent2D**: All movement uses `_move_to_target_nav()` which routes via Godot's navigation mesh. Pre-defined paths feed into this system as target positions.
- **Cover raycasts**: `_cover_raycasts[16]` + `_find_pursuit_cover_toward_player()` — expensive, replaced for levels that have predefined paths

---

## Similar Solutions / Reference

- **Unreal Engine "Smart Objects"**: Pre-baked navmesh waypoints for AI cover; same concept
- **Halo AI**: Pre-authored "combat areas" / "firing positions" baked into the level
- **F.E.A.R. (2005)**: World-state-based dynamic cover with designer-authored cover nodes — widely cited as the gold standard for cover AI
- **Godot NavigationLink2D**: Could be used to mark preferred paths in the navmesh
- **Godot Path2D + PathFollow2D**: Built-in mechanism for pre-defined paths

---

## Post-Implementation Bug: Enemy Stuck in Lower-Left Corner of Office 2

### Evidence

**Game log:** `game_log_20260321_071457.txt` (collected 2026-03-21)
**Screenshot:** `office2_stuck_screenshot.png` — multiple enemies clustered in the lower-left corner of Office 2

Key log entry:
```
[07:15:39] [ENEMY] [Enemy4] GLOBAL STUCK: pos=(556.7175, 975.9302) for 20.0s without player contact, State: PURSUING -> SEARCHING
```

Note: No `[CombatPathComponent]` log line appears in the game log, meaning the tested binary predates the CombatPathComponent addition.

### Root Cause Analysis

**Office 2 (Room2) geometry (from BuildingLevel.tscn):**
- Boundaries: x=524–912, y=712–1000
- Left wall: `Room2_WallLeft` at x=512, covering y=800–1000
- Bottom wall: `Room2_WallBottom` at y=1012, covering x=512–912
- Doorway (gap in left wall): x≈512, y=700–800
- Player typical position: (450, 910) — open corridor left of Office 2

**Stuck scenario reconstruction:**
1. Enemy4 spawns at (800, 900), enters PURSUING state
2. Enemy4 navigates into the lower-left corner: pos=(556, 975)
3. Player is at (450, 910): distance from enemy = **124px**
4. `get_nearest_attacking_waypoint` checks all attacking waypoints:
   - `Security_AttackEntrance` (560, 730): 211px from player — **farther than enemy** (124px) → rejected
   - `Security_AttackCenter` (720, 860): 275px from player → rejected
   - All other waypoints: even farther → rejected
5. Function returns `Vector2.ZERO` → fallback raycast logic runs
6. Raycast cover-search finds wall positions in the same corner → enemy cycles between corner positions → **GLOBAL STUCK at 20s**

**Root cause (two layers):**
1. **Waypoint coverage gap**: No waypoints exist in the lower-south area of Office 2 or in the doorway exit area. When the player approaches from outside, enemies in the deep corner of the room cannot find any waypoint that is "closer to the player than the enemy already is."
2. **Waypoint scoring logic too strict**: `get_nearest_attacking_waypoint` requires a waypoint to be strictly closer to the target than the enemy. When the enemy is very close to the player (cornered scenario), all relevant waypoints in the room are farther from the player, returning `Vector2.ZERO` and triggering the broken raycast fallback.

### Fix Applied

**1. New waypoints in `BuildingLevel.tscn` (AttackingPaths):**
- `Office2_ExitDoor` at (440, 760): Just outside the Office 2 doorway gap — gives enemies a navigation anchor to exit the room
- `Office2_AttackApproach` at (460, 870): Open corridor south-left of Office 2 — intermediate position between doorway and player
- `Security_AttackSouthWest` at (620, 940): South-west area inside Office 2 — draws enemies stuck in that corner toward the center of the room

**2. Scoring fallback in `combat_path_component.gd`:**
Changed `get_nearest_attacking_waypoint` to track the raw-nearest waypoint as a fallback. When no "progress waypoint" (closer to target than enemy) exists, return the nearest waypoint instead of `Vector2.ZERO`. This ensures enemies in corners always have a waypoint to navigate toward, breaking the corner cycle.

**Corrected pursuit path for stuck scenario:**
1. Enemy at (556, 975): nearest fallback → `Security_AttackSouthWest` (620, 940), dist≈67px. Enemy moves there.
2. Enemy at (620, 940): player at (450, 910), dist≈172px. Now `Office2_AttackApproach` (460, 870) is 166px from player — **progress waypoint found**! Enemy navigates toward doorway exit.
3. Enemy at (460, 870): player at (450, 910), dist≈41px. Enemy directly engages.

---

## Post-Implementation Bug 2: Enemies Walk Into Walls in PURSUING State (2026-03-21)

### Evidence

**Game log:** `game_log_20260321_073157.txt` (collected 2026-03-21)
**Screenshot:** `pursuing_wall_bug_screenshot.png` — multiple enemies pressed against the right wall of Security Room (Room 2) while in PURSUING state.

User report: "все враги в состоянии Pursuing идут в стену" (all enemies in Pursuing state walk into a wall).

### Root Cause Analysis

**Key architectural fact:**
`Room2_WallRight` at x=912–936 spans y=600–1000 with **NO doorway**. The corridor (x=964–1376, y=712–1012) is separated from the Security Room (x=524–912) by this unbroken wall. The only path from the corridor into the Security Room is by going **around the top** of Room2_WallRight (y<600).

Additionally, the nav agent radius is 24px. The gap between Room2_WallRight (x=936) and the left edge of Corridor_WallTop (x=964) is only 28px — narrower than 2×agent_radius (48px). The nav mesh treats this as impassable, so corridor enemies can only enter the Security Room via the long route around y<600.

**Bug scenario:**
- Corridor enemies (e.g., Enemy3 at (1200, 1000)) enter PURSUING state toward player at (450, 943)
- `get_nearest_attacking_waypoint` scores `Security_AttackSouthWest` (620, 940) very highly: progress=581px, penalty=580*0.3=174, score=407
- `Corridor_AttackWest` (980, 856) scores only: progress=219, penalty=221*0.3=66, score=153
- Security Room interior waypoints WIN over corridor waypoints despite requiring enemies to navigate around the full height of Room2_WallRight
- The nav mesh routes enemies LEFT along the corridor toward x=924 (right edge of Room2_WallRight), then UP to y<600 to get around — creating a path where enemies press against the wall while turning
- Result: **enemies appear to walk into Room2_WallRight**

**Root cause (two layers):**
1. **Scoring penalty too low** (0.3): Security Room interior waypoints win for corridor enemies because high progress gain outweighs the 0.3× distance penalty. The penalty must be high enough that a waypoint requiring twice the straight-line detour scores negatively.
2. **Fallback had no distance cap**: The corner-escape fallback returned ANY nearest waypoint regardless of distance, routing enemies across rooms.

**Mathematical analysis (why penalty ≥ 1.01 is needed):**
For Enemy3 at (1200, 1000) targeting player at (450, 943):
- `Security_AttackSouthWest` (620, 940): progress=581, dist=580 → needs penalty < 1.002 to win
- `Corridor_AttackWest` (980, 856): progress=219, dist=221 → at penalty=1.1: score=219-243=-24
- Break-even: 581-580p = 219-221p → 359p = 362 → p=1.008

So penalty must exceed **1.008** for corridor enemies to prefer local corridor waypoints over distant Security Room waypoints.

### Fix Applied (2026-03-21)

**1. Increased scoring penalty in `combat_path_component.gd`:**
- Changed distance penalty multiplier from `0.3` → `1.1`
- Now only waypoints that can be reached with a net navigation gain score positively
- Corridor enemies naturally select their nearest corridor waypoints first, then chain toward the Security Room via the correct top-entry path

**2. Limited fallback to local radius in `combat_path_component.gd`:**
- Added `FALLBACK_MAX_DIST = 350.0` constant
- The corner-escape fallback now only uses waypoints within 350px straight-line distance
- Prevents cross-room waypoint selection via fallback path

**3. Repositioned `Office2_AttackApproach`:**
- Was at (460, 870): below the doorway gap (y=800–1000 covered by wall), required enemies to navigate around and then back down — confusing path
- Moved to (350, 800): in the open left corridor area, accessible from both the doorway gap and the corridor below Office 1

**4. Added `Security_TopEntry` at (800, 560):**
- Provides a routing anchor for enemies inside the Security Room that need to navigate through the top-open area (above Room2_WallRight top at y=600)

**Corrected pursuit behavior after fix:**
- Enemy3 at (1200, 1000): all Security Room waypoints score negative (penalty 1.1 × distance > progress). Fallback selects `Corridor_AttackCenter` (1164, 856) at 148px → enemy moves left through corridor. Next call finds `Corridor_AttackWest` (980, 856) at 187px, then eventually approaches Security Room from the top entry.
- Enemy2 at (900, 950) inside Security Room: `Security_AttackSouthWest` (620, 940) scores 0 → barely a progress waypoint. Fallback at 280px selects it → enemy moves toward player via waypoint chain.
- No more cross-room wall pressing.

---

## Bug 3: All PURSUING Enemies GLOBAL STUCK After Penalty Increase (2026-03-21)

### Game logs

- `game_log_20260321_111703.txt` — BuildingLevel test, all maps locked
- `game_log_20260321_112257.txt` — BuildingLevel test, all maps unlocked

### Observed Behavior

After the Bug 2 fix (penalty 0.3→1.1), multiple enemies got GLOBAL STUCK in PURSUING state:

| Enemy | Stuck position | Duration |
|-------|---------------|----------|
| Enemy1 | (309, 396) | 4.0s |
| Enemy2 | (411, 663) | 4.0s |
| Enemy3 | (718, 922) | 4.0s |
| Enemy4 | (755, 916) | 4.0s |

### Root Cause Analysis

**The penalty=1.1 was too restrictive.** For any enemy far from the player, the travel distance to waypoints necessarily exceeds the net progress they produce (because waypoints are spread across rooms). With penalty=1.1, virtually every waypoint in the map scores negative:

Example — Enemy1 at (309, 396), player at (450, 923):
- `Office1_AttackFront` (290, 660): progress=238, travel=265, score = 238 − 265×1.1 = **−53** ❌
- `Office2_ExitDoor` (440, 760): progress=382, travel=387, score = 382 − 387×1.1 = **−43** ❌

No waypoint scores positively → fallback selects nearest within 350px = `Office1_AttackMid` (400, 400) at 91px. Enemy navigates there, arrives in ~0.3s, queries again — same zero-positive situation, picks same nearby fallback. The loop continues until the 4s GLOBAL STUCK timer fires.

### Why penalty=1.1 Was Too High

The penalty was derived from the cross-room routing constraint: to prevent corridor enemies (x≈1200) from routing into the Security Room (x≈620) through an impassable wall, the break-even penalty needed to exceed **1.008**. But this penalty level is fundamentally incompatible with same-room advances, where travel distance always equals or exceeds net progress.

### Fix Applied (Bug 3 — 2026-03-21)

**Two-parameter scoring in `combat_path_component.gd`:**

1. **Reduced penalty: 1.1 → 0.5** — Allows same-room waypoints to score positively. At penalty=0.5, `Office2_ExitDoor` scores 382−387×0.5 = **+188** for Enemy1 ✅

2. **Added `MAX_TRAVEL_DIST = 400.0` cap** — Waypoints more than 400px straight-line away from the enemy are excluded from scoring. This replaces the penalty as the cross-room filter:
   - `Security_AttackSouthWest` (620, 940) is 583px from corridor enemy (1200, 1000): **excluded**
   - `Corridor_AttackWest` (980, 856) is 263px from corridor enemy: **included**, scores +105 ✅

Verification table (penalty=0.5, max_travel=400):

| Scenario | Selected waypoint | Score |
|----------|------------------|-------|
| Enemy1 (309, 396) → player (450, 923) | Office2_ExitDoor | +188 |
| Enemy2 (411, 663) → player (450, 923) | Office2_ExitDoor | +49 |
| Enemy3 (718, 922) → player (450, 923) | Security_AttackSouthWest | +47 |
| Enemy4 (755, 916) → player (450, 923) | Security_AttackSouthWest | +66 |
| Corridor (1200, 1000) → player (620, 860) | Corridor_AttackWest | +105 |
| Corridor (1200, 1000) → player (450, 923) | Corridor_AttackWest | +88 |

All GLOBAL STUCK cases resolved without reintroducing cross-room wall-pressing.

---

## Map Layout: BuildingLevel

The BuildingLevel is ~2400×2000 pixels with the following rooms (from the .tscn):

```
Building bounds: (64,64) to (2464,2064)

Rooms (approximate):
- OFFICE 1 (Room1): x=64-512, y=64-700  (Enemies: Enemy1@(300,350), Enemy2@(400,550))
- SECURITY (Room2): x=512-924, y=700-1012 (Enemies: Enemy3@(700,750), Enemy4@(800,900))
- OFFICE 2 (Room3): x=1376-1776, y=64-612 (Enemies: Grenadier@(1700,350), Enemy6@(1950,450))
- ARMORY (Room4):   x=1376-1776, y=788-1388 (Enemies: Enemy7@(1600,900) patrol)
- Corridor:         x=964-1376, y=700-1012
- STORAGE (StorageRoom): x=100-512, y=1600-2064 (lobby area)
- MAIN HALL:        x=900-1500, y=1388-2064 (Enemies: Enemy10@(1200,1550) patrol)
- UPPER RIGHT WING: x=1688-2464, y=1200-2064 (Enemies: Enemy8@(1900,1450), Enemy9@(2100,1550))
```

### Attacking Path Design (corridors/approaches):
- Path from Room1 → Room2: through corridor near (600, 700)
- Path from Room2 → Corridor: through door at (912, 856)
- Path in Corridor: y=856 horizontal strip
- Path from Corridor → Room3/4: through junction at (1376, 856)
- Path in Main Hall: y=1700 strip
- Path in Upper Wing: diagonal approach routes

### Retreat Path Design (back-to-cover):
- Room1 deep cover: (200, 200)
- Room2 deep cover: (620, 800)
- Corridor cover: (1164, 856)
- Room3 deep cover: (1800, 200)
- Storage area cover: (250, 1800)
- Main Hall cover: (1200, 1700)
- Upper Wing cover: (2200, 1400)
