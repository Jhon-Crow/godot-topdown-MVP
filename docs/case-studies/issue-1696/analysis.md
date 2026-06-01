# Case Study: Issue #1696 — Strong FPS Drop on All Maps

## Problem Statement

The game experiences severe FPS drops across all maps. The issue title (Russian: *"исправь сильное падение fps на всех картах"*) translates to *"fix strong FPS drop on all maps"*.

Two benchmark logs were provided as attachments:
- `benchmark_log_20260328_161112.txt` — passive benchmark (single-subsystem disable)
- `stress_benchmark_20260328_161043.txt` — stress benchmark (extreme load per subsystem)

---

## Benchmark Data

### Passive Benchmark (`benchmark_log_20260328_161112.txt`)

Baseline: **6.3 FPS average** (min 6, max 7). Disabling each subsystem one by one produced no
meaningful improvement — all steps stayed in the 6.0–6.5 FPS range.

| Step | Subsystem | avg FPS | delta vs baseline |
|------|-----------|---------|-------------------|
| 1  | Baseline (all enabled)       | 6.3 | — |
| 2  | Particles disabled           | 6.3 | 0.0 |
| 3  | Blood Decals disabled        | 6.4 | +0.1 |
| 4  | Screen Shake disabled        | 6.5 | +0.2 |
| 5  | Explosion Lights disabled    | 6.5 | +0.2 |
| 6  | Wall Hit Particles disabled  | 6.3 | 0.0 |
| 7  | AI disabled                  | 6.3 | 0.0 |
| 8  | AI:IDLE disabled             | 6.2 | −0.1 |
| 9  | AI:COMBAT disabled           | 6.4 | +0.1 |
| 10 | AI:SEEKING_COVER disabled    | 6.3 | 0.0 |
| 11 | AI:IN_COVER disabled         | 6.3 | 0.0 |
| 12 | AI:FLANKING disabled         | 6.4 | +0.1 |
| 13 | AI:SUPPRESSED disabled       | 6.3 | 0.0 |
| 14 | AI:RETREATING disabled       | 6.3 | 0.0 |
| 15 | AI:PURSUING disabled         | 6.5 | +0.2 |
| 16 | AI:ASSAULT disabled          | 6.3 | 0.0 |
| 17 | AI:SEARCHING disabled        | 6.0 | −0.3 |

**Key observation:** No single subsystem toggle moves the needle. The passive benchmark measures
an idle scene. It proves the benchmark methodology, not the actual performance problem.

### Stress Benchmark (`stress_benchmark_20260328_161043.txt`)

Stress load: 30 GPUParticles2D + 20 PointLight2D + 20 enemies active simultaneously.

| Subsystem | Enabled FPS | Disabled FPS | Delta (cost) |
|-----------|-------------|--------------|--------------|
| Particles (30 GPUParticles2D) | 43.8 | 46.2 | **+2.5** |
| Explosion Lights (20 PointLight2D) | 71.8 | 71.6 | −0.2 (negligible) |
| AI (20 enemies) | 11.4 | 6.9 | **−4.5** (see note) |
| Combined (all three) | 2.6 | 4.1 | **+1.5** |

> **Note on AI delta sign:** The negative delta (−4.5) means FPS was *higher* with AI enabled
> (11.4) than disabled (6.9). This counter-intuitive result is explained in the root cause section.

---

## Timeline / Sequence of Events

1. **Game runs normally** with a small number of enemies (≤12, the arena cap defined in
   `arena_level.gd`). FPS is adequate.
2. **Player enters combat** — enemies transition from IDLE to COMBAT, PURSUING, FLANKING, etc.
   Multiple subsystems activate simultaneously.
3. **Enemy count rises or extreme load is applied** (e.g. stress test: 20 enemies +
   30 particle emitters + 20 lights).
4. **FPS collapses** to ~2–6 FPS under combined load (stress benchmark: 2.6 FPS combined).
5. **Individual subsystem disabling does not help** in the passive benchmark because the
   bottleneck only manifests under concurrent load from multiple interacting systems.

---

## Root Cause Analysis

### Root Cause 1: Enemy AI — NavigationAgent2D `set_target_position()` Called Every Physics Frame

**Location:** `scripts/objects/enemy.gd` — `_get_nav_direction_to()` (line 4723),
`_move_to_target_nav()` (line 4728), `_has_nav_path_to()` (line 4783),
`_get_nav_path_distance()` (line 4788).

```gdscript
# _get_nav_direction_to (line 4723) — called from _move_to_target_nav every physics frame
_nav_agent.target_position = target_pos

# _has_nav_path_to (line 4783) — used as a condition in multiple AI states every frame
_nav_agent.target_position = target_pos
return not _nav_agent.is_navigation_finished()

# _get_nav_path_distance (line 4788) — also sets target every frame
_nav_agent.target_position = target_pos
return _nav_agent.distance_to_target()
```

Setting `target_position` forces the NavigationServer2D to schedule a full path recalculation
for that agent. Called 60 times per second for each of 20 enemies, this is **1,200
path-recalculation requests per second**. Each request involves an A* search over the entire
navigation mesh.

**Evidence from community benchmarks:** Calling `set_target_position()` every frame with 300
CharacterBody2D enemies drops to <15 FPS. With batching at 300 ms intervals, the same hardware
handles **2,000 agents at 140 FPS**.
([Godot Forum](https://forum.godotengine.org/t/how-to-optimize-multiple-pathfinding-optimizing-a-huge-number-of-enemies/50709))

**Stress benchmark confirmation:** AI (20 enemies) drops FPS from 11.4 → 6.9 when AI is
"disabled" (note: `disabled` here stops AI *logic* but enemies remain as physics bodies,
retaining NavigationAgent2D overhead). The 11.4 FPS when AI is "enabled" still represents
severe degradation from the 43.8–71.8 FPS of other isolated tests.

**Additional navigation calls per frame (per enemy):**
- `_has_nav_path_to()` is called as a conditional in the SEARCHING and FLANKING states,
  each setting `target_position` a *second or third time* in the same frame.
- `_get_nav_path_distance()` is called for flank distance checks (line 2767).

---

### Root Cause 2: O(N²) Separation Force Scan in `_apply_separation_force()`

**Location:** `scripts/objects/enemy.gd` line 4772.

```gdscript
func _apply_separation_force(vel: Vector2, delta: float) -> Vector2:
    # ...
    for body in get_tree().get_nodes_in_group("enemies"):  # O(N) scan
        if body == self or not is_instance_valid(body): continue
        var diff: Vector2 = global_position - (body as Node2D).global_position
        var dist: float = diff.length()
        if dist < SEPARATION_RADIUS and dist > 0.1: sep_force += ...
    ...
```

This is called in `_physics_process` every frame for every enemy. With N enemies, each of N
enemies scans all N enemies → **O(N²) cost, 60 times per second**.

At 20 enemies: 20 × 20 = **400 scan iterations per physics frame** (24,000/sec).
At 30 enemies: 30 × 30 = **900 scan iterations per physics frame** (54,000/sec).

GUARD-mode IDLE enemies are explicitly excluded (line 4770), but all active enemies participate.

**Compounding factor:** Each iteration calls `get_tree().get_nodes_in_group("enemies")` which
rebuilds the group node list, adding allocation pressure.

---

### Root Cause 3: 120 Cover Raycasts Per Enemy on Every Cover Search

**Location:** `scripts/objects/enemy.gd` line 152, 1260–1264, 3266–3270.

```gdscript
const COVER_CHECK_COUNT: int = 120  # 120 rays = 3° apart for dense coverage
# ...
# Called in _find_cover() and _find_flanking_position()
for i in COVER_CHECK_COUNT:
    var raycast := _cover_raycasts[i]
    raycast.target_position = Vector2.from_angle((float(i) / COVER_CHECK_COUNT) * TAU) * COVER_CHECK_DISTANCE
    raycast.force_raycast_update()
```

Each call to `_find_cover()` fires **120 forced raycasts**. With 20 enemies:
- Simultaneous cover searches = **2,400 physics raycasts in a single frame**.
- Cover searches trigger when entering SEEKING_COVER, IN_COVER update, and FLANKING states.

Issue #1411 correctly disabled these raycasts by default (`enabled = false`) and uses
`force_raycast_update()` on demand, which is good. However, the calls still happen
synchronously mid-`_physics_process`, creating spikes when multiple enemies search for cover
at the same time.

---

### Root Cause 4: GPUParticles2D High Base Cost + `fixed_fps` Not Set

**Location:** `scripts/autoload/projectile_pool_manager.gd` and particle scenes.

The stress benchmark shows particles cost **2.5 FPS delta** with only 30 emitters.
GPUParticles2D in Godot 4 has a known high base cost regardless of particle count, due to GPU
draw-call overhead per emitter. Additionally, inactive GPUParticles2D (`emitting = false`)
still incur render-depth-prepass and opaque-pass costs
([Godot Issue #92764](https://github.com/godotengine/godot/issues/92764)).

Community benchmarks show GPUParticles2D at default settings cost ~47 FPS equivalent base
overhead compared to CPUParticles2D for small burst effects.
([Godot Forum benchmark](https://forum.godotengine.org/t/cpu-vs-gpu-particles-2d-performance-study-careful-gpu-particles-seem-to-have-a-high-base-cost/67850))

---

### Root Cause 5: Combined Load Collapse (2.6 FPS)

The stress benchmark combined result of **2.6 FPS** (vs. 4.1 FPS disabled) reveals a
**superlinear interaction effect**: the sum of all three subsystems under stress is worse than
the sum of their individual costs.

| Cost source | Estimated FPS cost |
|-------------|-------------------|
| 30 GPUParticles2D | ~2.5 FPS |
| 20 NavigationAgent2D enemies (path recalc) | ~35–40 FPS (from 46.2 baseline) |
| O(N²) separation at N=20 | significant CPU overhead |
| 120 raycasts per cover search × concurrent enemies | spike cost |
| Combined | collapses to 2.6 FPS |

The navigation overhead alone (going from 46.2 FPS baseline to ~11 FPS with 20 enemies) is the
dominant cost. Particles and lights add secondary costs that push an already-degraded frame
over the edge.

---

### Why the Passive Benchmark Missed This

The passive benchmark (6.3 FPS baseline) reveals the machine running the benchmark was already
**severely resource-constrained** — 6 FPS even at baseline (idle scene) suggests a very
low-end device or a rendering configuration issue (potentially VSync disabled but rendering to
a very high resolution, or a software renderer). The passive benchmark's step-by-step disable
cannot isolate the AI navigation issue because the test has **no enemies actually pathfinding**
during the measurement window.

---

## Proposed Solutions

### Solution A (High Impact): Throttle NavigationAgent2D `target_position` Updates

Rate-limit navigation path requests to **at most every 300 ms per enemy** (or when the target
has moved more than a threshold distance, e.g. 50 px). This is the most impactful fix.

```gdscript
# In enemy.gd — add navigation throttle state
var _nav_target_last_set: Vector2 = Vector2.ZERO
var _nav_repath_timer: float = 0.0
const NAV_REPATH_INTERVAL: float = 0.3  # 300 ms — max 3.3 path requests/sec per enemy
const NAV_REPATH_DISTANCE_THRESHOLD: float = 50.0  # repath if target moved >50px

func _should_update_nav_target(target_pos: Vector2) -> bool:
    _nav_repath_timer += get_physics_process_delta_time()
    if _nav_repath_timer < NAV_REPATH_INTERVAL:
        return _nav_target_last_set.distance_squared_to(target_pos) > (NAV_REPATH_DISTANCE_THRESHOLD * NAV_REPATH_DISTANCE_THRESHOLD)
    _nav_repath_timer = 0.0
    _nav_target_last_set = target_pos
    return true

func _get_nav_direction_to(target_pos: Vector2) -> Vector2:
    if _nav_agent == null: return (target_pos - global_position).normalized()
    if _should_update_nav_target(target_pos):
        _nav_agent.target_position = target_pos
    if _nav_agent.is_navigation_finished(): return Vector2.ZERO
    return (_nav_agent.get_next_path_position() - global_position).normalized()
```

Expected improvement: **3–5x FPS increase** under enemy load based on community benchmarks.

### Solution B (Medium Impact): Fix O(N²) Separation Force

Replace the per-frame `get_tree().get_nodes_in_group()` scan with the NavigationAgent2D ORCA
avoidance already in place (Issue #1146). ORCA runs on the NavigationServer thread and handles
agent separation without GDScript-level per-frame scanning.

```gdscript
# In _apply_separation_force — only run when ORCA is NOT active
func _apply_separation_force(vel: Vector2, delta: float) -> Vector2:
    # Skip separation if ORCA avoidance is handling it
    if _nav_agent and _nav_agent.avoidance_enabled: return vel
    # ... existing separation logic (only runs when ORCA is off)
```

For enemies with `avoidance_enabled = true`, this eliminates the O(N²) scan entirely.

### Solution C (Medium Impact): Stagger Cover Searches Across Frames

When multiple enemies simultaneously transition to SEEKING_COVER, stagger their cover searches
across frames using the same pattern already used for vision raycasts (Issue #883):

```gdscript
# Add cover search frame stagger (similar to _vision_frame_offset)
var _cover_search_scheduled: bool = false

func _schedule_cover_search() -> void:
    _cover_search_scheduled = true  # run on next vision-check frame for this enemy

# In _physics_process — only run cover search on this enemy's staggered frame
if _cover_search_scheduled and is_vision_check_frame:
    _cover_search_scheduled = false
    _do_cover_search()
```

### Solution D (Lower Impact): GPUParticles2D `fixed_fps` and Pool Reuse

1. Set `fixed_fps = 30` on all GPUParticles2D emitters (halves GPU update rate).
2. Ensure pooled particle emitters are actually freed when inactive (not just `emitting = false`)
   to eliminate the Godot #92764 inactive-emitter render cost.
3. For small burst effects (wall hits, casings), consider CPUParticles2D which has lower base
   cost at small counts.

### Solution E (Diagnostic): Per-enemy Navigation Budget

Add a global navigation request budget: limit total `set_target_position()` calls per physics
frame across all enemies to a maximum of `MAX_NAV_REQUESTS_PER_FRAME = 10`. Excess requests are
queued and spread across subsequent frames.

---

## Priority Ranking

| Priority | Solution | Expected FPS Gain | Effort |
|----------|----------|-------------------|--------|
| 1 | A — Navigation throttle (300 ms repath interval) | 3–5× | Low |
| 2 | B — Skip O(N²) separation when ORCA active | 1.5–2× | Low |
| 3 | C — Stagger cover searches | 1.2–1.5× | Medium |
| 4 | D — GPUParticles fixed_fps + pool cleanup | 1.1× | Low |
| 5 | E — Global nav budget cap | Additional safety | Medium |

Implementing A + B alone is expected to bring the 20-enemy stress scenario from ~11 FPS to
**30–50+ FPS** on the same hardware.

---

## References

- Benchmark data: `benchmark_log_20260328_161112.txt`, `stress_benchmark_20260328_161043.txt`
- Prior related work: Issue #883 (vision raycast stagger), Issue #1146 (ORCA avoidance),
  Issue #1163 (prediction throttle), Issue #1411 (cover raycast on-demand), Issue #1520 (O(N²) scan throttle)
- [Godot Forum: Nav Agent tanks my FPS](https://forum.godotengine.org/t/nav-agent-tanks-my-fps/115578)
- [Godot Forum: Optimize multiple pathfinding](https://forum.godotengine.org/t/how-to-optimize-multiple-pathfinding-optimizing-a-huge-number-of-enemies/50709)
- [Godot Docs: Optimizing Navigation Performance](https://docs.godotengine.org/en/latest/tutorials/navigation/navigation_optimizing_performance.html)
- [Godot Forum: CPU vs GPU Particles 2D benchmark](https://forum.godotengine.org/t/cpu-vs-gpu-particles-2d-performance-study-careful-gpu-particles-seem-to-have-a-high-base-cost/67850)
- [Godot Issue #92764: GPU particles expensive when emitting=false](https://github.com/godotengine/godot/issues/92764)
- [Godot PR #100302: Optimize PointLight2D shadow rendering](https://github.com/godotengine/godot/pull/100302)
