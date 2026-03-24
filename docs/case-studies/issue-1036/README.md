# Case Study: Issue #1036 — Radio Jammer Enemy

## Overview

| Field | Value |
|-------|-------|
| **Issue** | [#1036 — добавь нового врага (Add new enemy)](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1036) |
| **Pull Request** | [#1059 — feat: add Radio Jammer enemy that blocks player active items](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1059) |
| **Status** | Implemented and merged into branch |
| **Author** | Jhon-Crow |
| **Solved by** | AI automated solver (konard) |
| **Date opened** | 2026-03-16 |
| **Date solved** | 2026-03-17 |

---

## 1. Issue Description

The issue requested a new enemy type characterized by:

1. **Appearance**: An enemy with a radio backpack.
2. **Mechanic**: While alive, within a 1000px radius the enemy disables the player's ability to use active items.
3. **Visual effect**: An animated semi-transparent expanding circle radiating outward from the enemy (resembling radio waves).
4. **Map placement**: The enemy should be added to the Decadence map (referenced in issue #1035).
5. **Case study**: Data and analysis of the problem and solution should be compiled to `docs/case-studies/issue-1036`.

**Original request (Russian):**
> враг с радио рюкзаком за спиной. 1. пока он жив в радиусе 1000px вокруг него игрок не может использовать активный предмет. 2. вокруг этого врага анимированный полупрозрачный круг (обозначающий исходящие "радиоволны")

**Reference image provided:** Expanding red radio wave rings (see `reference_image.png`).

---

## 2. Timeline / Sequence of Events

```
2026-03-16
  Issue #1036 opened by Jhon-Crow
  AI solver session started (attempt 1)

2026-03-16 ~20:00 UTC
  Initial implementation created on branch issue-1036-9750cc238363
  - feat commit: add Radio Jammer enemy (42af79b4)
  - Initial commit with task details created and reverted (cc5b1877, 1013212d)

2026-03-16 ~20:30 UTC
  CI failures detected (line limit exceeded in enemy.gd)

2026-03-16 ~20:35 UTC
  Auto-restart triggered by CI failure monitor

2026-03-16 ~20:48 UTC
  Refactor commit: move Radio Jammer logic to RadioWaveEffect child node (283407a6)
  Root cause of CI failure fixed: enemy.gd lines reduced by moving jamming
  logic out of enemy.gd into radio_wave_effect.gd

2026-03-16 ~20:49 UTC
  PR marked as ready for review
  Solution draft log uploaded to GitHub Gist

2026-03-17 09:35 UTC
  Jhon-Crow comments: merge from main, verify enemy, add to Decadence map,
  create case study in docs/case-studies/issue-1036

2026-03-17 ~10:00 UTC
  AI session started (session 2)
  - Merged main (212 commits merged, including DecadenceLevel.tscn)
  - Added RadioJammerEnemy to DecadenceLevel at position (1100, 900)
  - Created this case study

2026-03-17 10:02 UTC
  Jhon-Crow reports two bugs with game log:
  1. Player can still use active items near the radio jammer
  2. Requests a visible icon near the player when in jammer range

2026-03-17 ~10:15 UTC
  AI session started (session 3 — current session)
  - Analyzed game log (game_log_20260317_125825.txt):
    Player at (150,1900) to ~(200,1571), jammer at (1100,900) → always >1000px apart.
    Player was never in jammer range — log does not prove jamming failure.
  - Discovered root cause of potential jamming bug:
    RadioWaveEffect is a child of EnemyModel, not RadioJammerEnemy.
    get_parent() returns EnemyModel (Node2D without is_alive()), so the death
    check `parent.has_method("is_alive")` always returns false, meaning the
    jammer is never released on enemy death. Also enemy.global_position was
    being read from EnemyModel.global_position (works for position, but the
    is_alive() guard was broken).
  - Fixed: RadioWaveEffect now uses get_parent().get_parent() to reach the
    actual RadioJammerEnemy CharacterBody2D.
  - Implemented JammerHUD: prohibition sign (red circle + diagonal bar) drawn
    above the player using Node2D/_draw(), shown only when jammed AND the
    player has an active item equipped (not NONE).
  - Merged latest main (includes auto-reload, machete component, new case studies)

2026-03-17 18:21 UTC
  Jhon-Crow reports jamming still not working with new game log:
  game_log_20260317_211852.txt

2026-03-17 ~19:03 UTC
  AI session started (session 4)
  - Downloaded and analyzed game_log_20260317_211852.txt (3957 lines)
  - Confirmed the bug: Invisibility Suit activated at player (735,1225)
    while jammer was at ~(814,1121) = 130px apart — well within 1000px range.
    The block should have triggered but did NOT.
  - Root cause found: physics-process race condition (Root Cause #3).
    See Technical Root Cause #3 below.
  - Implemented fix: direct scene-tree query in is_active_item_jammed()
  - Added "radio_jammers" group to RadioJammerEnemy.tscn
  - Updated tests with 5 new tests covering the race condition scenario
  - Updated case study with session 4 findings

2026-03-17 20:18 UTC
  Jhon-Crow reports jamming STILL not working with new game log:
  game_log_20260317_231612.txt
  - Reports: "active items are not blocked at all and icon above player is not shown"
  - Asks to verify 2000px diameter (1000px radius) zone exists around jammer

2026-03-17 ~20:20 UTC
  AI session started (session 5)
  - Downloaded and analyzed game_log_20260317_231612.txt (4498 lines)
  - CRITICAL FINDING: game log contains NO "JammerHUD initialized" message,
    which is emitted by _init_jammer_hud() in player.gd on every level load.
    This proves the user's binary predates session 3/4 fixes entirely.
  - TrajectoryGlasses activated at 23:17:03 with player at ~(783,1030)
    and jammer firing from (902,1036) — only ~119px apart — block should fire.
    No block log appeared because the binary is old.
  - Added comprehensive diagnostic logging:
    * is_active_item_jammed_verbose() — called on every Space press, logs
      full jammer group membership, alive status, and exact distances
    * log_jammer_diagnostics() — called every 2s from radio_wave_effect.gd,
      logs periodic jam state for passive monitoring
    * Restructured jammer checks to occur INSIDE is_action_just_pressed()
      branches for press-based items (homing, BFF, invisibility, trajectory,
      loudspeaker), so verbose logging only fires when Space is pressed
    * Added "BLOCKED by Radio Jammer" log lines for each active item handler
  - Added jammer check to breaching charges handler (was missing!)
  - Increased JammerHUD prohibition sign size: radius 9→14px, linewidth 3→4px
    for better in-game visibility
  - Saved reference images and game logs to docs/case-studies/issue-1036/
```

---

## 3. Root Cause Analysis

### Primary Problem

The game lacked a "support disruptor" enemy archetype — an enemy whose combat value comes not from dealing damage but from restricting player capabilities. The existing enemy system only supported combat-oriented enemies.

### Technical Root Cause 1 (CI Failure)

During initial implementation, the jamming logic was placed directly in `scripts/objects/enemy.gd`. This caused the file to exceed the CI line limit (500 lines), which the GitHub Actions workflow enforces via `scripts/ci/check_line_limits.sh`.

**Resolution**: The jamming logic (proximity detection, player group lookup, ActiveItemManager calls, and the visual wave effect) was extracted into a separate `RadioWaveEffect` child node script (`scripts/effects/radio_wave_effect.gd`). This approach:
- Respected the single-responsibility principle
- Kept enemy.gd under the line limit
- Made the visual effect and jamming logic encapsulated in one composable component

### Technical Root Cause 2 (Parent Reference Bug)

When the jamming logic was moved to `RadioWaveEffect`, the node was placed as a child of `EnemyModel` (for visual positioning), not directly under `RadioJammerEnemy`. This introduced a latent bug: `get_parent()` returned `EnemyModel` (a plain `Node2D`), not the enemy `CharacterBody2D`.

**Consequence**: `parent.has_method("is_alive")` always returned `false` since `EnemyModel` has no `is_alive()` method. The condition `(parent.has_method("is_alive") and not parent.is_alive())` therefore never triggered, meaning:
- The jammer was never released when the enemy died (jam persisted after death)
- Enemy position was read from `EnemyModel.global_position` — which happened to be correct since `EnemyModel` has no positional offset, but this was an accidental correctness

**Resolution** (session 3): Changed to `get_parent().get_parent()` to walk up to the actual `RadioJammerEnemy` CharacterBody2D that has `is_alive()`.

### User-Reported Bug (Player Icon Missing)

Jhon-Crow reported that no visual feedback is shown to the player when in the jammer zone. The original implementation only blocked the Space key silently. This violates the feedback principle: players need to know *why* an action is unavailable.

**Resolution** (session 3): Added `JammerHUD` — a `Node2D` child of the player that draws a red prohibition sign (circle with diagonal bar, matching the reference image style) above the player when jammed and the player has an active item equipped. Only shown when both conditions hold (jammed AND has active item), so players who haven't equipped any active item are not shown a confusing icon.

### Technical Root Cause 3 (Physics-Process Race Condition) — Discovered Session 4

After session 3's fixes, Jhon-Crow reported the block was **still not working** with a new game log (`game_log_20260317_211852.txt`). Deep analysis of the log revealed:

- At timestamp 21:19:46, the player activated the Invisibility Suit
- At that moment, the player was at **(735, 1225)** and the jammer was at approximately **(814, 1121)**
- Distance = ~130 px — well within the 1000 px jam radius
- The block should have triggered, but the invisibility suit activated successfully

**Root cause**: Classic physics-process ordering race condition in Godot 4.

The architecture was:
1. `radio_wave_effect.gd._physics_process()`: queries player distance → calls `ActiveItemManager.set_jammed(is_in_range)` → updates `_is_jammed` flag
2. `player.gd._physics_process()`: checks `ActiveItemManager.is_active_item_jammed()` → reads `_is_jammed` flag → if false, allows activation

In Godot, `_physics_process` callbacks are called in **scene tree order** (depth-first, by order added to tree). The `Player` node is a sibling of `RadioJammerEnemy` in the level scene. Depending on placement order, Player's `_physics_process` may run **before** RadioWaveEffect's `_physics_process` in the same physics step.

This means:
- Frame N-1: Player at position A (outside range) → `_is_jammed = false`
- Frame N: Player moves to position B (inside range)
  - Player's `_physics_process` runs **first**: checks `_is_jammed` → still `false` → allows activation!
  - RadioWaveEffect's `_physics_process` runs **after**: computes `is_in_range = true` → sets `_is_jammed = true` (too late!)

This is a **deterministic bug** — every time the player enters the jammer radius and presses Space in the same physics frame they cross the boundary, the block fails. Even once inside the radius, if node order is unfortunate, the block can fail on any given frame.

**Resolution** (session 4):
- Changed `ActiveItemManager.is_active_item_jammed()` to **directly query the scene tree** every call, instead of reading the stale `_is_jammed` flag
- Added `"radio_jammers"` group to `RadioJammerEnemy.tscn` so jammers can be found instantly
- The new implementation loops over all `"radio_jammers"` group nodes, checks `is_alive()`, and computes distance — all in real-time at the moment the player presses Space
- Since the check now happens inside the same `_physics_process` call (player.gd), there is no cross-node ordering dependency

```gdscript
# New implementation — no race condition:
func is_active_item_jammed() -> bool:
    var players := get_tree().get_nodes_in_group("player")
    if players.is_empty(): return false
    var player: Node = players[0]
    var jammers := get_tree().get_nodes_in_group("radio_jammers")
    for jammer in jammers:
        if not is_instance_valid(jammer): continue
        if jammer.has_method("is_alive") and not jammer.is_alive(): continue
        if jammer.global_position.distance_to(player.global_position) <= JAMMER_RADIUS:
            return true
    return false
```

### Observation: User Testing with Stale Builds (Session 5)

When the user reported that jamming was still not working after session 4's race-condition fix, deep analysis of `game_log_20260317_231612.txt` revealed:

1. **Missing "JammerHUD initialized" log line** — this message is emitted in `_ready()` of `player.gd` on every scene load. Its absence is a definitive fingerprint: the binary was built from code that predates session 3 (which added `_init_jammer_hud()`).

2. **Corroborating evidence** — the log also has no "Blocked by Radio Jammer" messages in any active item handler, despite the player being ~119px from the jammer when TrajectoryGlasses activated.

3. **Root cause** — the user had an older game build and was not testing with the latest PR code.

**Resolution** (session 5):
- Added `is_active_item_jammed_verbose()` — a separate verbose variant called only on Space press events, logging full jammer diagnostics (player/jammer positions, distances, alive state) without log spam
- Added `log_jammer_diagnostics()` in `ActiveItemManager` called periodically from `RadioWaveEffect._physics_process()`, logging every 2 seconds when jammers are present
- Restructured all press-based active item handlers to do the jammer check INSIDE the `is_action_just_pressed()` branch, so verbose logging fires exactly when the player presses Space
- Added "BLOCKED by Radio Jammer" log entries for all 7 active item handlers
- Fixed missing jammer check in the breaching charges handler (was never added)
- Enlarged JammerHUD prohibition sign for better visibility (radius 9→14px)

### Architecture Design Choices

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| Extend Enemy class with `is_radio_jammer` flag | Simple, no new files | Bloats enemy.gd, violates SRP | Used initially, caused CI failure |
| RadioWaveEffect child node handles all jammer logic | Clean separation, composable | Slightly indirect parent access | **Chosen** (after CI failure) |
| Separate RadioJammerEnemy.gd script | Maximum isolation | Would duplicate enemy.gd logic | Considered but not needed |

---

## 4. Implementation Details

### Files Created / Modified

| File | Change | Purpose |
|------|--------|---------|
| `scripts/effects/radio_wave_effect.gd` | **New** | Animated expanding cyan rings (jamming logic moved to ActiveItemManager in session 4) |
| `scenes/objects/RadioJammerEnemy.tscn` | **New** | Enemy scene with RadioWaveEffect child node; `"radio_jammers"` group added in session 4 |
| `scripts/autoload/active_item_manager.gd` | Modified | Added `_is_jammed`, `set_jammed()`, `is_active_item_jammed()` (direct-query in session 4) |
| `scripts/characters/player.gd` | Modified | Jammer guard in all 6 `_handle_*_input()` functions; logging added in session 4 |
| `scenes/levels/DecadenceLevel.tscn` | Modified | Added RadioJammerEnemy at position (1100, 900) |
| `tests/unit/test_radio_jammer_enemy.gd` | **New** | 25 unit tests covering jammer behavior (5 new tests for race condition in session 4) |

### Jamming Mechanic

The jamming is implemented as a poll-based check in `_physics_process()` of `RadioWaveEffect`:

```gdscript
func _physics_process(_delta: float) -> void:
    var aim := get_node_or_null("/root/ActiveItemManager")
    if aim == null: return
    var parent := get_parent()
    if not is_instance_valid(parent) or (parent.has_method("is_alive") and not parent.is_alive()):
        aim.set_jammed(false)
        return
    var players := get_tree().get_nodes_in_group("player")
    if players.is_empty(): return
    var player: Node = players[0]
    aim.set_jammed(parent.global_position.distance_to(player.global_position) <= jammer_radius)
```

**Design implications**:
- Every physics frame (60fps), the jammer evaluates whether to jam
- On enemy death, jam is immediately released
- If `ActiveItemManager` is not found (e.g. in tests), the code safely returns

### Player Blocking

All 6 active item input handlers in `player.gd` check the jammer state:

```gdscript
if ActiveItemManager.is_active_item_jammed():
    return  # Early exit blocks item use
```

Hold-type items (flashlight, force field) are also forcibly deactivated when jammed.

### Visual Effect

Expanding cyan rings are drawn via Godot's custom `_draw()` method:

```
MIN_RING_RADIUS = 10px
MAX_RING_RADIUS = 60px
RING_EXPAND_SPEED = 40px/s
RING_SPAWN_INTERVAL = 0.5s
RING_COLOR = Color(0.2, 0.8, 1.0, 0.6) — semi-transparent cyan
```

Rings spawn every 0.5 seconds, expand outward from 10px to 60px, fading from opaque to transparent as they reach maximum radius. This creates the "radio wave pulsing" visual without performance overhead.

---

## 5. Industry Research & Context

### Similar Mechanics in Games

The Radio Jammer enemy belongs to the well-established **"support disruptor"** enemy archetype in game design.

#### Watch Dogs 2 — The Jammer (Closest Parallel)
The most directly analogous real-world example: the Jammer enemy in Watch Dogs 2's DLC prevents the player from using hacking within a ~3m radius (their primary ability system). The only counter inside the jammer field is a specific Profiler hack, costing Botnet resources.
> Source: [Watch Dogs Wiki — Jammer](https://watchdogs.fandom.com/wiki/Jammer)

Key similarities to this implementation:
- Named enemy type whose entire purpose is blocking player special abilities
- Clear visual range indicator
- Requires killing the enemy to permanently end the effect
- Creates forced prioritization

#### DOOM Eternal — Arch-vile
The Arch-vile buffs all demons in the arena (not the player), but demonstrates the **priority target pattern**: a support enemy that demands immediate attention and fundamentally changes encounter dynamics.
> Source: [Doom Wiki — Arch-vile (Doom Eternal)](https://doom.fandom.com/wiki/Arch-vile/Doom_Eternal)

#### Hotline Miami — Enemy Design Philosophy
Hotline Miami (the stylistic reference for this game) does not have a jammer enemy, but its design philosophy is directly relevant:
- Enemy variants (armored thugs, dogs) force **specific tactical responses**
- "Amazingly crafted without being too complicated"
- Special enemies create memorable encounters by requiring behavioral changes, not just increased difficulty

The Radio Jammer fits this philosophy: it does not kill the player directly but forces a tactical adaptation.
> Source: [Analysis of AI in Hotline Miami — Rodrigo Fernandez Diaz](https://medium.com/@RodFernandez91/an-analysis-of-hotline-miami-ai-23c37dbcb156)

---

## 6. Design Principles Applied

### Strengths of the Implementation

1. **Clear counterplay**: Killing the enemy ends the jam — direct, understandable, satisfying.
2. **Visual clarity**: Expanding ring effect communicates the mechanic at a glance.
3. **Partial restriction**: Only active items are blocked, not movement or weapons — preserves player agency.
4. **Composable architecture**: RadioWaveEffect node can be reused on other enemy types.
5. **Death cleanup**: Jam is immediately released on enemy death.

### Known Design Considerations

1. **Multi-jammer stacking**: The current implementation uses a binary `_is_jammed` bool that the last physics frame write to sets. If two Radio Jammers are simultaneously in range, killing one will call `set_jammed(false)` and the player may briefly be unjammed even while the second jammer is still active.

   **Possible solution**: Use a reference counter (`_jammer_count: int`) where `set_jammed(true)` increments and `set_jammed(false)` decrements, only clearing when count reaches 0. Or use a `Set` of jammer node references.

2. **Jammer radius vs. visual effect radius**: The jammer_radius is 1000px, but the visual rings only expand to 60px. The rings communicate "this enemy is a jammer" rather than "this is the exact boundary of the jam field". This is consistent with Hotline Miami's visual abstraction approach but may be confusing for new players.

   **Possible solution**: Draw a faint outer circle at the full jammer_radius, or use a color change on the player's UI when entering the jammer field.

3. **No identification at range**: Without a distinct sprite (e.g., visible backpack), players may not identify the Radio Jammer as different from a regular enemy until they encounter the jamming effect.

   **Possible solution**: Add a distinct sprite asset (teleporter_backpack.png was added to assets in main, a similar asset for the radio backpack would be ideal).

---

## 7. Possible Future Solutions / Enhancements

Based on the research and implementation analysis, here are proposals ranked by impact:

| Priority | Enhancement | Rationale |
|----------|-------------|-----------|
| High | Distinct visual appearance (radio backpack sprite) | Players must identify the enemy type before engaging |
| High | Multi-jammer reference counting | Correctness in multi-enemy scenarios |
| Medium | UI feedback when jammed (e.g., greyed-out item icon, screen effect) | Helps new players understand why items aren't working |
| Medium | Range indicator (outer ring at 1000px or screen-edge indicator) | Communicates the actual jam radius |
| Low | Configurable jam_type enum (block all, block specific items) | Extensibility for future level design |
| Low | Audio cue (static noise when entering jammer field) | Multisensory feedback |

---

## 8. Test Coverage

25 unit tests in `tests/unit/test_radio_jammer_enemy.gd` cover:

- Jammer state management (on/off/toggle)
- `is_active_item_jammed()` reflection
- Export property defaults (`is_radio_jammer`, `jammer_radius`)
- RadioWaveEffect visual constants (radius ranges, speeds, colors)
- Proximity logic (within radius, outside radius, at exact boundary)
- **Session 4 additions**: JAMMER_RADIUS constant consistency, "radio_jammers" group in scene file, race condition bug scenario (player at 735,1225 / jammer at 814,1121 = 130px), and correct out-of-range scenario (player at 150,1900 / jammer at 1100,900 = 1379px)

All tests use pure GDScript value testing (no scene instantiation required), ensuring they run in CI without a Godot editor.

---

## 9. Data Files in This Case Study

| File | Description |
|------|-------------|
| `README.md` | This case study document |
| `issue-data.json` | Raw GitHub API data for issue #1036 |
| `pr-data.json` | Raw GitHub API data for pull request #1059 |
| `pr-comments.json` | All conversation comments on PR #1059 |
| `pr-review-comments.json` | All inline review comments on PR #1059 |
| `pr-diff.txt` | Full unified diff of all changes in PR #1059 |
| `git-log.txt` | Git log of commits on the issue branch |
| `solution-draft-log.txt` | Complete AI solution draft log (41,470 lines) |
| `reference_image.png` | Original radio wave reference image from the issue |
| `game_log_20260317_125825.txt` | Game log from session 3 test — jammer spawned but player never within 1000px |
| `game_log_20260317_211852.txt` | Game log from session 4 test — confirmed race condition bug: invisibility activated at 130px from jammer |
| `jammer_icon_reference.png` | Reference image for the prohibition sign icon above the player when jammed |

---

## 10. References

- [Issue #1036](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1036)
- [Pull Request #1059](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1059)
- [Issue #1035 — Decadence Map](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1035)
- [Watch Dogs Wiki — Jammer Enemy](https://watchdogs.fandom.com/wiki/Jammer)
- [Hotline Miami Enemy Behaviour Wiki](https://hotlinemiami.fandom.com/wiki/Enemy_Behaviour)
- [Designing Enemies With Distinct Functions — Harvey Smith, Game Developer](https://www.gamedeveloper.com/design/designing-enemies-with-distinct-functions)
- [Beyond Bullet Sponges: Designing Engaging Enemy Archetypes — Wayline](https://www.wayline.io/blog/designing-engaging-enemy-archetypes)
- [Enemy NPC Design Patterns in Shooter Games — ACM / Academia](https://www.academia.edu/2806378/Enemy_NPC_Design_Patterns_in_Shooter_Games)
- [Building Counterplay for PvP Games — CritPoints](https://critpoints.net/2025/05/06/building-counterplay-for-pvp-games/)
- [Arch-vile (Doom Eternal) — Doom Wiki](https://doom.fandom.com/wiki/Arch-vile/Doom_Eternal)
- [Analysis of AI in Hotline Miami — Rodrigo Fernandez Diaz](https://medium.com/@RodFernandez91/an-analysis-of-hotline-miami-ai-23c37dbcb156)
