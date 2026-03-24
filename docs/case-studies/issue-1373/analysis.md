# Case Study: Issue #1373 — Enemy Squad Coordination & Cover Detection Fix

## Problem Statement

Enemies within proximity interfere with each other during movement and frequently commit
friendly fire. The request is to make enemies within 1000 px behave as a synchronized team:
covering each other, coordinating paths relative to allies, and using a group-level GOAP
so the squad operates as a single organism.

### Root Cause: Cover Detection Regression (identified 2026-03-23)

Owner feedback on PR #1374: "совсем не та логика поиска укрытия (лучи должны исходить из игрока)"
("completely wrong cover-finding logic — rays must originate from the player").

**The core bug**: PR #1352 (commit c740ff7b) implemented correct player-origin raycasts for
cover detection. However, the initial #1373 implementation reverted this by using enemy-origin
child RayCast2D nodes instead of physics queries from the player position.

| Aspect | PR #1352 (correct) | Initial #1373 (broken) |
|--------|-------------------|----------------------|
| Ray origin | Player position | Enemy position |
| Method | Physics queries (intersect_ray) | Child RayCast2D nodes |
| Ray count | 120 (3° resolution) | 16 (22.5° resolution) |
| Ray range | 300 px | 300 px |
| Far-side probing | _get_far_side_cover() (intersect_point) | collision_normal * 35px offset |
| Navmesh snapping | Yes (NavigationServer2D) | No |
| Debug visualization | Cached player-origin ray data | Child raycast state |

**Why player-origin matters**: Cover must be evaluated from the player's perspective. A position
is "cover" if the player's line of sight cannot reach it. Casting rays from the enemy finds
obstacles near the enemy, but doesn't guarantee the enemy will be hidden from the player.

### Evidence from game_log_20260323_141146.txt

- Rapid state oscillation: enemies cycle COMBAT → RETREATING → IN_COVER → SUPPRESSED
  because selected cover positions don't actually hide them from the player
- Enemies in IN_COVER immediately transition to SUPPRESSED (still visible to player)
- No explicit raycast errors — the code works, but selects wrong positions

### Root Cause 2: COVER_CHECK_DISTANCE regression + Debug rays not showing (identified 2026-03-24)

Owner feedback: "сохраняется старая проблема. не отображается дэбаг лучей, не правильно
определяется укрытие (широкие укрытия не считаются, а должны)."
("same old problem persists. debug rays are not displaying, cover detection is wrong
— wide covers are not counted, but they should be.")

Evidence from game_log_20260324_063315.txt:
- `Cover raycast visible: true` is enabled in ExperimentalSettings (line 41)
- CoverRaycastMonitor overlay is created (line 49)
- But debug rays were NOT visible to the user
- State oscillation still present: IN_COVER → SUPPRESSED → IN_COVER → PURSUING cycles
- No "Found cover" or "No valid cover" log messages appear — cover search was being skipped

**Bug 1: COVER_CHECK_DISTANCE was 10000.0 instead of 300.0**

The reference commit c740ff7b has `COVER_CHECK_DISTANCE = 300.0`. A previous session
incorrectly changed it to `10000.0`, causing:
- `_get_far_side_cover()` to probe up to 30,000 px (1000 iterations per ray × 120 rays)
- Extremely slow cover search due to massive probe distance
- Far-side positions placed at wrong distances for wide obstacles
- Debug rays extending far beyond meaningful range, making visualization useless

**Bug 2: Debug rays never populated due to early returns in _find_cover_position()**

`_find_cover_position()` had two early-return paths that skipped `_get_hidden_cover_candidates()`:
1. `_combat_waypoint()` returning a non-zero waypoint (line 3316) — returns immediately
   without calling ray generation, so `_last_cover_search_rays` stays empty
2. Cooldown throttle (line 3318) — skips ray generation when cover is still valid

The CoverRaycastMonitor reads ray data from `get_cover_raycast_data()` which returns
`_last_cover_search_rays`. If this array is never populated, no rays are drawn.

**Fix**: Always generate debug rays when `cover_raycast_visible_enabled` is true,
even during waypoint/cooldown early returns. Restore `COVER_CHECK_DISTANCE = 300.0`.

## Existing Systems (pre-#1373)

| Component | File | Purpose |
|-----------|------|---------|
| `TacticalGroupComponent` | `scripts/components/tactical_group_component.gd` | Enemies within 500 px encircle the player via angular slots (Issue #1287) |
| `TacticalMovementComponent` | `scripts/components/tactical_movement_component.gd` | Passage-blocking yield logic — closer enemy passes first (Issue #1249) |
| `_is_firing_line_clear_of_friendlies()` | `scripts/objects/enemy.gd:3008` | Single ray-check: blocks shot if ally between muzzle and target |
| ORCA avoidance | NavigationAgent2D built-in | Reciprocal velocity obstacle avoidance |
| Separation steering | `enemy.gd:4763-4774` | Push apart when < 60 px |
| Wall avoidance | `enemy.gd:3520-3584` | 8-ray avoidance for walls |
| `EnemyMemory` | `scripts/ai/enemy_memory.gd` | Position confidence, `receive_intel()` for sharing |
| `PlayerPredictionComponent` | `scripts/ai/player_prediction_component.gd` | 7 hypothesis types, style classification |
| GOAP planner | `scripts/ai/goap_planner.gd` | A*-based individual action planning (22 actions) |

### Gap Analysis

1. **No cover deconfliction** — multiple enemies select identical cover positions.
2. **No firing-lane awareness** — enemies don't avoid walking into allies' lines of fire.
3. **No suppressive-fire coordination** — no "cover me while I move" behavior.
4. **No group-level GOAP** — all planning is individual; no shared squad goal.
5. **TacticalGroupComponent radius is 500 px** — issue requests 1000 px.
6. **Friendly fire check is single-ray only** — doesn't account for spread or movement.

## Evidence from Game Log

- **Cover clustering**: Multiple enemies select the same cover point (e.g., Enemy4 and
  Enemy10 both pick (798.76, 906.72)). No deconfliction.
- **Rapid state oscillation**: Enemy3 cycles COMBAT → RETREATING → IN_COVER → SUPPRESSED
  repeatedly, suggesting enemies disrupt each other's cover.
- **FPS drops**: 15 fps when 5+ enemies pursue simultaneously (line 1162).
- **No friendly fire log entries**: The existing `_is_firing_line_clear_of_friendlies()`
  does prevent direct shots, but enemies still cluster and block each other's movement.

## Research: Industry Approaches

### F.E.A.R. (Monolith, 2005) — Gold Standard for Squad AI
- **Two-layer decision**: Individual GOAP + squad-level behavior scripts.
- **Squad behaviors**: "Advance-cover" (one suppresses while others advance),
  "Get-to-cover" (coordinate cover selection so members don't overlap).
- **Slot-based coordination**: Each squad member fills a role (suppressor, flanker, rusher).

Sources:
- [GDC Vault: Three States and a Plan](https://gdcvault.com/play/1013282/Three-States-and-a-Plan)
- [Building the AI of F.E.A.R.](https://www.gamedeveloper.com/design/building-the-ai-of-f-e-a-r-with-goal-oriented-action-planning)
- [29 Tricks: Assaulting F.E.A.R.'s AI](http://aigamedev.com/open/review/fear-ai/)

### Godot-Specific
- NavigationAgent2D ORCA for collision avoidance (already used).
- Beehave addon for behavior trees (not used here; GOAP is the approach).
- Central UnitManager pattern for 100+ units (relevant for performance).

Sources:
- [Godot Forum: enemy path following with avoidance](https://godotengine.org/qa/37341/how-make-enemy-ais-follow-path-while-avoiding-their-fellows)
- [Advanced AI Techniques Using GOAP](https://arnauld-alex.com/using-goap-for-advanced-gaming-ai-techniques)

## Solution Design

### Architecture: SquadCoordinatorComponent (per-enemy, RefCounted)

Inspired by F.E.A.R.'s two-layer approach, but implemented as a per-enemy component
that queries neighbors (like the existing `TacticalGroupComponent` pattern):

```
Enemy AI Layer (existing):
├── Individual GOAP (22 actions)
├── State Machine (11 states)
└── Movement Pipeline
    ├── TacticalGroupComponent (angular slots) — ENHANCED to 1000 px
    ├── TacticalMovementComponent (passage yield)
    └── NEW: SquadCoordinatorComponent
        ├── Cover Deconfliction (claim/reserve system)
        ├── Firing Lane Awareness (avoid allies' LOF)
        ├── Suppressive Fire Coordination (cover-while-move)
        └── Group GOAP (squad-level goal selection)
```

### Key Features

1. **Squad Formation** (1000 px radius): Enemies within range form a dynamic squad.
   Each enemy's `SquadCoordinatorComponent` independently queries neighbors and
   reaches consensus via deterministic algorithms (sorted by instance ID).

2. **Cover Deconfliction**: When selecting cover, enemies check if any squad mate
   has already claimed that position (within 80 px tolerance). If so, they skip it.

3. **Firing Lane Awareness**: Before moving to a position, check if it crosses any
   squad mate's firing line (muzzle → target ray). If so, adjust path laterally.

4. **Suppressive Fire Coordination**: When a squad mate is moving (PURSUING/FLANKING),
   nearby enemies in cover prefer to keep shooting (suppress) rather than also moving.
   This creates natural "covering fire" behavior.

5. **Group GOAP**: A lightweight squad-level planner that assigns roles:
   - SUPPRESSOR: Stay in cover, keep firing.
   - FLANKER: Move to flank position.
   - RUSHER: Close distance aggressively.
   - HOLDER: Hold current position.
   Role assignment based on current position, health, ammo, and angle to player.

6. **Path Coordination**: Enemies adjust their nav target to avoid clustering.
   Minimum inter-enemy distance of 120 px enforced during movement.

### Files to Create/Modify

| File | Action |
|------|--------|
| `scripts/components/squad_coordinator_component.gd` | **NEW** — Main squad coordination |
| `scripts/objects/enemy.gd` | Integrate SquadCoordinatorComponent |
| `scripts/components/tactical_group_component.gd` | Increase radius to 1000 px |
| `scripts/autoload/experimental_settings.gd` | No change needed (reuse tactical_group flag) |
