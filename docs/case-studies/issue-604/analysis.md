# Case Study: Issue #604 -- Grenadier Enemy Throws Grenades Too Infrequently

## 1. Issue Summary

**Issue**: The grenadier enemy type does not throw grenades often enough during gameplay.

**Owner Request** (translated from Russian):

> "гренадер должен чаще кидать гранаты (перед заходом за перегородку в Persuming например)"
>
> "The grenadier should throw grenades more often (before entering a partition/wall in Pursuing state, for example)."

**Secondary Request**:

> "добавь модельке разгрузку с гранатами на грудь"
>
> "Add a grenade vest/chest rig to the grenadier model."

## 2. Game Log Analysis

**Source**: `game_log_20260208_170117.txt` (session starting 17:01:17)

### 2.1 Grenadier Spawn and Configuration

The grenadier spawns multiple times across the session due to level restarts. Each time it initializes identically:

```
[17:01:17] [ENEMY] [Grenadier] Spawned at (1700, 350), hp: 2, behavior: GUARD
[17:01:17] [INFO] [EnemyGrenade] Grenadier initialized: 8 grenades in bag
```

- **Position**: (1700, 350)
- **HP**: 2
- **Behavior**: GUARD
- **Grenade loadout**: 8 total (hard mode: 7 Offensive + 1 Defensive)
- **Throw cooldown**: 5.0 seconds (BuildingLevel override of the 15.0s default)

### 2.2 Timeline of Grenade Throws

| Time     | Event                                              | Grenades Remaining |
|----------|----------------------------------------------------|--------------------|
| 17:01:17 | Grenadier spawned with 8 grenades                  | 8                  |
| 17:01:18 | Enters IDLE state, scanning                        | 8                  |
| 17:01:38 | 30+ "Unsafe throw distance" warnings flood the log | 8                  |
| 17:01:52 | Vulnerability sound triggers IDLE -> PURSUING       | 8                  |
| 17:01:54 | **Throw #1**: Offensive grenade, distance 336      | 7                  |
| 17:01:54 | Grenade explodes, "passage clear" logged           | 7                  |
| 17:02:13 | IDLE -> PURSUING -> COMBAT -> RETREATING cycle     | 7                  |
| 17:02:38 | **Throw #2**: Offensive grenade, distance 296      | 7 (see note below) |
| 17:03:06 | **Throw #3**: Offensive grenade, distance 310      | 7 (see note below) |
| 17:03:07 | Grenade explodes, "passage clear"                  | --                 |
| 17:03:39 | **Throw #4**: Offensive grenade, distance 383      | 7 (see note below) |
| 17:03:40 | Grenade explodes, "passage clear"                  | --                 |
| 17:03:47 | **Throw #5**: Non-grenadier enemy throws (Enemy)   | --                 |
| 17:04:28 | **Throw #6**: Offensive grenade, distance 337      | 6                  |

**Note on grenade count**: The log shows "7 remaining" for throws #2-#4 despite consuming grenades. This is because the level restarts between throw sequences (the grenadier re-initializes at 8 grenades each restart). Throws #2-#4 each occur in separate level attempts.

### 2.3 Unsafe Throw Distance Analysis

The game log contains **1,504 occurrences** of "Unsafe throw distance" warnings. A representative sample from 17:01:38-17:01:39:

```
[17:01:38] Unsafe throw distance (240 < 275 safe distance, blast=225, margin=50) - skipping throw
[17:01:38] Unsafe throw distance (236 < 275 safe distance, blast=225, margin=50) - skipping throw
[17:01:38] Unsafe throw distance (231 < 275 safe distance, blast=225, margin=50) - skipping throw
...
[17:01:39] Unsafe throw distance (127 < 275 safe distance, blast=225, margin=50) - skipping throw
```

These entries show non-grenadier enemies (Enemy2, Enemy3) approaching the player at close range. The distances decrease from 240 down to 127, all below the 275px safe distance threshold (225px blast radius + 50px safety margin). While these are mostly from regular enemies, the pattern illustrates how the safety check fundamentally blocks throws when enemies are close to their targets. For the grenadier specifically, this means it cannot throw grenades ahead into corridors when it is near the corridor entrance.

### 2.4 State Machine Behavior

The grenadier cycles rapidly through states during combat:

```
17:02:13  IDLE -> PURSUING
17:02:13  PURSUING -> COMBAT
17:02:13  COMBAT -> RETREATING
17:02:18  RETREATING -> IN_COVER
17:02:18  IN_COVER -> PURSUING
17:02:24  PURSUING -> FLANKING
17:02:24  FLANKING -> COMBAT
17:02:27  COMBAT -> PURSUING
17:02:29  PURSUING -> COMBAT
17:02:31  COMBAT -> PURSUING
17:02:32  PURSUING -> COMBAT
17:02:35  COMBAT -> SEEKING_COVER
```

The grenadier transitions through 12 state changes in 22 seconds. With a 5-second throw cooldown per attempt, this rapid cycling severely limits opportunities to throw. Corner checks during PURSUING state (logged as "PURSUING corner check: angle X") indicate the grenadier is navigating around obstacles but never proactively throws a grenade before entering a corridor.

## 3. Root Cause Analysis

### Root Cause 1: No Proactive Passage-Clearing Trigger

The `EnemyGrenadeComponent` (parent class) defines **7 reactive throw triggers**:

| Trigger | Name              | Condition                                          |
|---------|-------------------|----------------------------------------------------|
| T1      | Suppression       | Under fire + hidden for 6+ seconds                 |
| T2      | Pursuit           | Under fire + approach speed > 50px/s               |
| T3      | Witnessed Kills   | Witnessed 2+ ally deaths within 30 seconds         |
| T4      | Sound             | Heard vulnerability sound, cannot see player        |
| T5      | Sustained Fire    | 10+ seconds of continuous fire in a zone           |
| T6      | Desperation       | Health at or below 1                                |
| T7      | Suspicion         | Medium+ suspicion confidence, player hidden 3+ sec |

All 7 triggers are **reactive** -- they respond to combat events that have already occurred. There is **no trigger** for the scenario the owner describes: "before entering a partition/wall in Pursuing." The grenadier has no mechanism to detect that it is approaching a narrow passage and should throw a grenade ahead to clear it before entering.

The `GrenadierGrenadeComponent` subclass adds passage-blocking signals (`grenade_incoming`, `grenade_exploded_safe`) and ally coordination logic, but it does **not** override the `is_ready()` method or add a Trigger 8 for passage detection. It relies entirely on the parent class's 7 triggers to decide when to throw.

### Root Cause 2: Cooldown Duration Still Too Long

Even with BuildingLevel's 5-second cooldown (reduced from the default 15 seconds), the grenadier managed only approximately 1 throw per 30 seconds across the gameplay session:

- Throw #1 at 17:01:54
- Throw #2 at 17:02:38 (44 seconds later)
- Throw #3 at 17:03:06 (28 seconds later)
- Throw #4 at 17:03:39 (33 seconds later)
- Throw #6 at 17:04:28 (49 seconds later)

The 5-second cooldown is not the bottleneck in isolation. The real problem is that triggers rarely fire during the rapid state transitions. By the time a trigger condition is met, the grenadier has often moved past the optimal throw position.

### Root Cause 3: Unsafe Distance Check Blocks Close-Range Corridor Throws

The safety check in `try_throw()` rejects any throw where the distance to target is less than `blast_radius + safety_margin` (225 + 50 = 275px). When a grenadier approaches a corridor entrance, the target (player's last known position or sound location) may be within 275px, blocking the throw entirely.

The conceptual problem: the grenadier should throw the grenade **ahead** into the corridor, not directly at a close target. A passage-clearing throw targets the corridor itself (a fixed point ahead), not the enemy's current proximity to the player.

### Root Cause 4: `passage_throw_cooldown` Defined But Never Referenced

The `GrenadierGrenadeComponent` defines:

```gdscript
var passage_throw_cooldown: float = 2.0   # Line 43
var _passage_detected: bool = false         # Line 46
var _passage_position: Vector2 = Vector2.ZERO  # Line 49
```

These three properties are clearly intended for a passage-detection throw system:
- `passage_throw_cooldown` (2.0s) is shorter than the combat cooldown (5.0s), suggesting faster throws when clearing corridors
- `_passage_detected` is a boolean flag for passage detection state
- `_passage_position` stores the detected passage entrance location

However, **none of these properties are read or written anywhere in the codebase**. A grep for `passage_throw_cooldown` returns only the declaration on line 43. The `_passage_detected` and `_passage_position` variables are similarly unused. This strongly suggests that a passage-clearing trigger was planned but never implemented.

## 4. Proposed Solutions

### Solution 1: Add Proactive Passage Approach Trigger (T8)

Add a new trigger in `GrenadierGrenadeComponent` that detects when the grenadier is about to navigate through a narrow passage or corridor, and throws a grenade ahead before entering.

**Implementation approach**:
- Override `is_ready()` in `GrenadierGrenadeComponent` to add a `_t8()` check
- Use the existing wall detection raycasts (`_wall_raycasts` array in `enemy.gd`, 8 raycasts for obstacle detection) to detect narrow passages ahead
- When walls are detected on both sides of the forward direction during PURSUING state, set `_passage_detected = true` and record `_passage_position`
- Throw the grenade to a point **beyond** the passage entrance (ahead of the grenadier), not at the player's position
- Use `passage_throw_cooldown` (2.0s) instead of `throw_cooldown` (5.0s) for this trigger

**Relevant existing code in `enemy.gd`**:
```gdscript
var _wall_raycasts: Array[RayCast2D] = []   # Line 152
const WALL_CHECK_COUNT: int = 8              # Line 154
func _setup_wall_detection() -> void:        # Line 490
```

### Solution 2: Reduce Throw Cooldown for Passage Throws

Wire up the existing `passage_throw_cooldown` property (2.0 seconds) so that when a passage-clearing throw occurs (T8), the cooldown resets to 2.0s instead of 5.0s. This allows the grenadier to throw more frequently when clearing rooms.

**In `_execute_grenadier_throw()`**, line 257 currently always sets:
```gdscript
_cooldown = throw_cooldown  # Always uses 5.0s from BuildingLevel
```

Change to:
```gdscript
_cooldown = passage_throw_cooldown if _passage_detected else throw_cooldown
```

### Solution 3: Adjust Unsafe Distance Check for Ahead-Targeting

When the throw is a passage-clearing throw (T8), calculate the target position as a point ahead of the grenadier in its movement direction rather than at the player's position. This ensures the target is far enough away to pass the safety distance check while still clearing the corridor.

**Target calculation**: Project a point 300-400px ahead of the grenadier in its current movement direction, constrained to the corridor's center line. This naturally exceeds the 275px safe distance threshold.

### Solution 4: Visual Enhancement -- Grenade Vest Model

Per the owner's secondary request, add a grenade vest/chest rig to the grenadier sprite. This is a visual-only change to existing sprite assets:
- `assets/sprites/weapons/frag_grenade.png`
- `assets/sprites/weapons/defensive_grenade.png`

## 5. File References

| File | Purpose |
|------|---------|
| `scripts/components/grenadier_grenade_component.gd` | Grenadier-specific grenade component with bag system, passage blocking signals, and unused passage detection properties |
| `scripts/components/enemy_grenade_component.gd` | Base grenade component with 7 reactive triggers and the `is_ready()` / `try_throw()` pipeline |
| `scripts/objects/enemy.gd` | Enemy base class with wall detection raycasts (8-directional), state machine, and grenade component integration |
| `scenes/levels/BuildingLevel.tscn` | Level scene that sets `grenade_throw_cooldown = 5.0` (overriding the default 15.0s) |
| `tests/unit/test_grenadier_grenade_component.gd` | Unit tests for the grenadier grenade component, including passage blocking state tests |

## 6. Quantitative Summary

| Metric | Value |
|--------|-------|
| Total grenadier grenade throws observed | 5 (grenadier) + 1 (regular enemy) |
| Available grenades per spawn | 8 |
| Grenade utilization rate | ~12.5% per spawn (1 throw before re-init) |
| Unsafe throw distance warnings | 1,504 total in session |
| Average time between throws | ~34 seconds |
| Grenadier state transitions in combat | ~12 per 22 seconds |
| Throw cooldown (BuildingLevel) | 5.0 seconds |
| Throw cooldown (default) | 15.0 seconds |
| Passage throw cooldown (unused) | 2.0 seconds |
| Safe distance threshold | 275px (225px blast + 50px margin) |
| Passage detection properties defined | 3 (all unused) |
| Passage detection triggers implemented | 0 |
