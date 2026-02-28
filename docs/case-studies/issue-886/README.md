# Issue #886 Case Study: HIGH — Grenade Blast Radius Instantiates Scene Every Call

## Issue Description

**Title**: fix HIGH: Grenade Blast Radius Instantiates Scene Every Call

**Summary**: `_get_blast_radius()` in `scripts/components/enemy_grenade_component.gd` creates a temporary grenade scene instance on every call just to read the `effect_radius` property. This function was called 10,621 times during a session when throw conditions were met but blocked (e.g., unsafe distance). The fix is to cache the result after first access.

**File**: `scripts/components/enemy_grenade_component.gd:296`

**Reported by**: Jhon-Crow

**Fixed in**: PR #916

---

## Timeline / Sequence of Events

### 1. Background: Issue #375 Introduces `_get_blast_radius()`

Issue #375 added a safe-throw distance check to prevent enemies from killing themselves with their own grenades. The developer needed to know the grenade's blast radius at throw-check time. The simplest implementation was to instantiate the scene temporarily and read the exported property:

```gdscript
func _get_blast_radius() -> float:
    if grenade_scene == null:
        return 225.0

    var temp_grenade = grenade_scene.instantiate()
    if temp_grenade == null:
        return 225.0

    var radius := 225.0
    if temp_grenade.get("effect_radius") != null:
        radius = temp_grenade.effect_radius
    temp_grenade.queue_free()
    return radius
```

This is functionally correct and safe, but carries hidden performance cost.

### 2. `try_throw()` Calls `_get_blast_radius()` on Every Attempt

`try_throw()` is called every frame (or near-every-frame) for each enemy that is in grenade-throwing range:

```gdscript
func try_throw(target: Vector2, is_alive: bool, is_stunned: bool, is_blinded: bool) -> bool:
    ...
    var blast_radius := _get_blast_radius()   # ← called unconditionally
    var min_safe_distance := blast_radius + safety_margin

    if dist < min_safe_distance:
        _log("Unsafe throw distance ...")
        return false
    ...
```

Even when the player is too close (unsafe distance), the function returns `false` — but only **after** instantiating and freeing a scene. The safety check is a common early-exit path.

### 3. 10,621 Instantiations Observed

The issue reports 10,621 calls in a single session. This arises from:
- Multiple enemies, each with a `EnemyGrenadeComponent`.
- Game running at 60 FPS.
- Typical game session of several minutes with enemies attempting (but failing) to throw grenades.
- Each enemy component independently instantiates the grenade scene on each attempt.

At 60 FPS with 3 enemies over a 60-second period: `60 × 3 × 60 = 10,800` — consistent with the reported 10,621.

### 4. Root Cause

The root cause is the absence of caching in `_get_blast_radius()`. The `effect_radius` property of a grenade is a static `@export var` that does not change at runtime:

```gdscript
# scripts/projectiles/frag_grenade.gd
@export var effect_radius: float = 225.0
```

Since the value is constant for a given `grenade_scene` and does not change after loading, caching is both safe and correct.

---

## Root Cause Analysis

### Primary Cause: No Memoization of Static Data

The `effect_radius` property is an exported constant that is set at scene design time and never mutated during gameplay. Reading it requires instantiating the packed scene, which involves:

1. Allocating memory for the node tree.
2. Calling `_init()` and `_ready()` on each node in the scene (including physics bodies, collision shapes, etc.).
3. Reading the property.
4. Calling `queue_free()` to schedule deallocation.

All of this work is wasted when the result is always the same value.

### Contributing Factor: Early-Exit Path Is the Hot Path

In normal gameplay, enemies frequently want to throw grenades but are blocked by the safe-distance check. This means the **most common code path** is:

1. Call `_get_blast_radius()` → instantiate scene → read property → free instance.
2. Check: `dist < min_safe_distance` → `true` → return `false`.

The expensive operation occurs on the path that does the least actual work.

### Why This Is Classified as HIGH (Not CRITICAL)

- The instantiation is fast (microseconds per call), so 10,621 calls may add tens of milliseconds of overhead — noticeable but not catastrophic.
- Memory usage is transient: each instance is freed immediately.
- The game remains playable, but CPU/GC pressure increases.
- At higher enemy counts or longer sessions, this could degrade to CRITICAL.

---

## Performance Impact Analysis

### Godot Scene Instantiation Cost

Godot's `PackedScene.instantiate()` is not free. For a `FragGrenade` scene (a `RigidBody2D` with collision shape, sprite, timer, and script), each instantiation involves:

- Node allocation and tree construction.
- Script `_init()` execution.
- Property default assignment.
- Registration with the scene tree (via `queue_free()`, not immediately, but still tracked by the GC).

Benchmarks on typical Godot 4 scenes suggest 10–100 µs per instantiation depending on scene complexity. At 10,621 calls:
- **Low estimate (10 µs/call)**: ~106 ms total overhead per session.
- **High estimate (100 µs/call)**: ~1,062 ms (~1 second) total overhead per session.

Additionally, `queue_free()` defers deallocation, which means the GC accumulates work that must be processed at end-of-frame, adding frame-time spikes.

### References

- [Godot 4 PackedScene.instantiate() documentation](https://docs.godotengine.org/en/stable/classes/class_packedscene.html#class-packedscene-method-instantiate)
- [Godot performance best practices — avoid instantiation in hot loops](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html)
- [GDScript performance tips](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html)

---

## Solution

### Approach 1: Hard-code the Radius (Rejected)

Replace `_get_blast_radius()` with a constant `225.0`.

- **Pros**: Zero overhead.
- **Cons**: If `grenade_scene` is ever changed to a different grenade type (e.g., a flashbang with a different radius), the hard-coded value will be wrong. Removes the dynamic capability introduced by Issue #375.

### Approach 2: Read from Scene Resource Directly (Not Feasible)

Access `effect_radius` directly from the `PackedScene` resource without instantiation.

- **Pros**: Would avoid instantiation.
- **Cons**: GDScript's `PackedScene` does not expose exported property values without instantiation. Packed scene state is stored in binary resource format; there is no public API to read export var values without creating an instance.

### Approach 3: Cache After First Instantiation (Chosen)

Add a `_blast_radius_cache: float = -1.0` member variable. On first call, instantiate, read, cache, and free. On subsequent calls, return the cached value immediately.

- **Pros**:
  - Reduces 10,621 instantiations to exactly 1.
  - No behavior change: the correct value is still read from the actual scene.
  - Safe: `effect_radius` is a static export var that does not change at runtime.
  - Minimal code change, easy to review and verify.
- **Cons**:
  - If `grenade_scene` is changed after initialization (hypothetically), the cache would return a stale value. However, `grenade_scene` is set once in `initialize()` and never changed, so this is not a real concern in practice.

### Chosen Implementation

**Added to State section (line 47–48):**
```gdscript
## Cache for blast radius to avoid repeated scene instantiation (Issue #886)
var _blast_radius_cache: float = -1.0
```

**Updated `_get_blast_radius()` function:**
```gdscript
## Get grenade blast radius (Issue #375).
## Result is cached after first access to avoid repeated scene instantiation (Issue #886).
func _get_blast_radius() -> float:
    if _blast_radius_cache >= 0.0:
        return _blast_radius_cache

    if grenade_scene == null:
        _blast_radius_cache = 225.0  # Default frag grenade radius
        return _blast_radius_cache

    # Instantiate grenade once to read effect_radius, then cache the result
    var temp_grenade = grenade_scene.instantiate()
    if temp_grenade == null:
        _blast_radius_cache = 225.0  # Fallback
        return _blast_radius_cache

    # Check if grenade has effect_radius property
    if temp_grenade.get("effect_radius") != null:
        _blast_radius_cache = temp_grenade.effect_radius
    else:
        _blast_radius_cache = 225.0  # Default

    # Clean up temporary instance
    temp_grenade.queue_free()

    return _blast_radius_cache
```

The sentinel value `-1.0` is used because a valid blast radius cannot be negative. The check `_blast_radius_cache >= 0.0` will be `false` only on the very first call, after which the cached value (always `>= 0`) is returned immediately.

---

## Verification

### Before Fix
- `_get_blast_radius()` called `grenade_scene.instantiate()` on every invocation.
- 10,621 calls → 10,621 scene instantiations per session.

### After Fix
- `_get_blast_radius()` calls `grenade_scene.instantiate()` exactly **once** per `EnemyGrenadeComponent` instance (on first call).
- 10,621 calls → **1** scene instantiation per component instance.
- Subsequent calls return `_blast_radius_cache` immediately (single float comparison).

### Impact Reduction
- **CPU overhead**: Reduced by ~99.99% (from 10,621 instantiations to 1).
- **GC pressure**: Eliminated. No longer accumulates `queue_free()` deferred work on every frame.
- **Behavior**: Unchanged. The blast radius value is identical to what was computed before.
