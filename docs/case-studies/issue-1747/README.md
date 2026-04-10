# Case Study: Issue #1747 — Fix Blood Puddles Disappearing In View

## Issue Summary

**Title:** fix кровавые лужи (fix blood puddles)
**Reported:** 2026-03-30
**Status:** Open
**Reporter:** Jhon-Crow
**Pull Request:** #1759

Blood puddles (floor decals spawned on lethal/non-lethal hits) were observed
disappearing while still within the player's field of view.  The reporter noted
that the game may be capping the total number of blood decals for optimisation,
but requested that any decal currently visible on screen must not be removed —
only off-screen decals should be culled.

Two game log files were referenced in the issue report
(`game_log_20260330_135455.txt`, `game_log_20260330_135843.txt`); these were not
committed to the repository, so the analysis below is based on source-code
inspection and the history of related issues.

---

## Attached Logs

| File | Notes |
|------|-------|
| `game_log_20260330_135455.txt` | Referenced in issue; not present in repo |
| `game_log_20260330_135843.txt` | Referenced in issue; not present in repo |

---

## Timeline of Events

### Issue #293 / #370 — Unlimited blood decals
Blood decals were originally unlimited (`MAX_BLOOD_DECALS = 0`).  Puddles never
disappeared, which was the desired aesthetic.

### Issue #1693 — FPS drops from unbounded decal accumulation
A 2-minute combat session accumulated 1 215+ `Sprite2D` nodes, causing frame
rate to drop to ~2.6 FPS.  `MAX_BLOOD_DECALS` was capped at **200** and a
FIFO (first-in, first-out) cleanup strategy was introduced:

```gdscript
while _blood_decals.size() > MAX_BLOOD_DECALS:
    var oldest := _blood_decals.pop_front() as Node2D
    if oldest and is_instance_valid(oldest):
        oldest.queue_free()
```

Post-fix, combined stress FPS improved from 2.6 → 7.5.

### Issue #1090 — More blood requested
BLOOD_DECALS_PER_LETHAL_HIT raised from 20 → 30, and
BLOOD_DECALS_PER_NONLETHAL_HIT raised from 10 → 15 per owner request.
At 30 decals per lethal hit, the 200-decal cap is reached after just ~6–7
lethal hits, meaning puddles start disappearing very quickly in combat.

### Issue #1747 — Puddles disappear in view (this issue)
With 200 total decals and 30 per kill, the FIFO strategy removes the oldest
decals regardless of whether the player can see them.  In a small or recently
visited area, the oldest decals may be exactly the ones the player is standing
next to.

---

## Root Cause Analysis

### Root Cause 1: Blind FIFO culling ignores player viewport

The cleanup loop unconditionally removes the *oldest* decal from the front of
`_blood_decals` when the cap is exceeded.  There is no check for whether that
decal is currently visible within the player's camera frustum.

**Evidence:** `impact_effects_manager.gd` lines 736–741 (floor decals) and
835–840 (wall splatters) — identical FIFO loops in both code paths.

**Effect:** After roughly 6–7 lethal hits in a small area, puddles that the
player is actively looking at start vanishing, which is jarring and breaks
immersion.

**Fix:** Replace the blind FIFO with a viewport-aware helper that scans the
decal list from oldest to newest and removes the first decal whose
`global_position` falls outside the camera's visible rectangle.  Only when
every tracked decal is on-screen (edge case: very small map / zoomed-out
camera) does it fall back to removing the oldest regardless of visibility.

---

## Research: Known Approaches and Libraries

### A — Viewport frustum culling (chosen approach)

Use the active `Camera2D`'s screen-center position and viewport size to build
a world-space `Rect2`.  Any decal whose `global_position` is outside that rect
is considered off-screen and safe to remove.

**Pros:** Simple, zero extra dependencies, O(n) scan on the existing list.
**Cons:** Uses the decal's centre point rather than its bounding box; a large
decal partially in view could still be culled.  For the current 8–32 px decal
scales this is acceptable.

**References:**
- Godot docs: `Camera2D.get_screen_center_position()`,
  `Viewport.get_visible_rect()`
- Similar technique used in Godot open-source games for sprite/particle culling

### B — Godot built-in `VisibleOnScreenNotifier2D`

Attach a `VisibleOnScreenNotifier2D` to every `BloodDecal` node and maintain a
separate "off-screen" queue for culling.

**Pros:** Engine-native, handles rotation and scale correctly.
**Cons:** Adds one extra node per decal (defeats the purpose of the 200-node
cap), requires signal wiring, and increases scene complexity.

### C — Spatial partitioning (quadtree / grid)

Maintain decals in a spatial grid; when the cap is hit, remove from the cell
furthest from the player.

**Pros:** Better approximation of "farthest away" rather than "oldest".
**Cons:** Significant implementation complexity for marginal benefit in 2D
top-down gameplay with a moving camera.

### D — LRU (Least Recently Visible) cache

Replace the FIFO array with an LRU cache, updating each decal's access time
whenever it enters the viewport.

**Pros:** Most accurate "keep what the player sees" semantics.
**Cons:** Requires per-frame scanning of all decals to update access times,
which adds CPU overhead proportional to the decal count.

**Chosen approach: A** — lowest complexity, consistent with the existing code
style, satisfies the issue requirement without adding new nodes or CPU overhead.

---

## Proposed Solutions

### Solution 1 ✅ Viewport-aware off-screen culling (implemented)

Add a helper method `_remove_oldest_offscreen_decal()` to
`ImpactEffectsManager`.  The method:

1. Locates the active `Camera2D` (via `"camera"` group, falling back to a
   recursive scene-tree search).
2. Builds a world-space `Rect2` from the camera's screen-centre and viewport
   dimensions.
3. Iterates `_blood_decals` from index 0 (oldest) to end; removes and frees
   the first decal whose `global_position` is outside the rect.
4. Falls back to removing the oldest decal if all decals are on-screen.

Both FIFO cleanup loops (floor decals and wall splatters) are replaced with
calls to this helper.

### Solution 2 ❌ Increase MAX_BLOOD_DECALS

Simply raising the cap to 500 or 1000 would delay the problem but not solve
it.  At 30 decals per kill the cap would still be hit during heavy combat, and
the same FIFO issue would recur.

### Solution 3 ❌ Re-enable unlimited decals (revert Issue #1693 fix)

Removing the cap entirely would restore the pre-#1693 FPS drop (~2.6 FPS in
stress tests).

---

## Implemented Fixes (PR #1759)

### Fix 1: `_remove_oldest_offscreen_decal()` helper

**File:** `scripts/autoload/impact_effects_manager.gd`

New method inserted between `_schedule_delayed_decal` and `clear_blood_decals`.
Builds a viewport rect from the active Camera2D and removes the oldest
off-screen decal.  Falls back to FIFO if no off-screen decal is found.

Also adds `_collect_cameras(parent, result)` — a small recursive helper that
walks the scene tree when the camera is not in the `"camera"` group.

### Fix 2: Replace FIFO loops

**File:** `scripts/autoload/impact_effects_manager.gd` (two locations)

```gdscript
# Before (Issue #1693 FIFO):
while _blood_decals.size() > MAX_BLOOD_DECALS:
    var oldest := _blood_decals.pop_front() as Node2D
    if oldest and is_instance_valid(oldest):
        oldest.queue_free()

# After (Issue #1747 viewport-aware):
while _blood_decals.size() > MAX_BLOOD_DECALS:
    _remove_oldest_offscreen_decal()
```

### Fix 3: Update stale unit test

**File:** `tests/unit/test_impact_effects_manager.gd`

`test_max_blood_decals_is_unlimited()` asserted `MAX_BLOOD_DECALS == 0`, which
has been wrong since Issue #1693 set it to 200.  Updated to
`test_max_blood_decals_is_capped()` asserting the value is `> 0`.

### Fix 4: New unit tests

**File:** `tests/unit/test_impact_effects_manager.gd`

Seven new tests covering the viewport-aware culling logic (method existence,
empty list, null-entry cleanup, count reduction, multiple-decal ordering).

---

## Summary Table

| Cause | Impact | Confidence | Fix Complexity | Status |
|-------|--------|-----------|----------------|--------|
| Blind FIFO removes visible decals | Immersion-breaking puddle pop | High | Low | ✅ Fixed in PR #1759 |
| MAX_BLOOD_DECALS cap too low for hit rate | Frequent culling during combat | Medium | Medium | Deferred (cap left at 200) |
