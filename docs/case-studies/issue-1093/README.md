# Case Study: Issue #1093 — Breaching Charges Corner Placement

## Overview

**Issue:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1093
**PR:** https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1094
**Status:** Resolved (Phase 2 — visual corner fix)

---

## Timeline / Sequence of Events

| Date | Event |
|------|-------|
| Before #1087 | `_find_nearest_wall_with_hit()` stored only ONE wall in `_charged_wall: Node`. Detonation opened passage in only that one wall. |
| PR #1089 | Issue #1087 implemented: passage carving (split collision shapes), directional explosion, LED marker. Single-wall case worked correctly. Corner case was not addressed. |
| Issue #1093 opened | User reports: placing a charge at the corner between two walls causes **neither** wall to open. |
| PR #1094 (Phase 1) | `_find_walls_with_hits()` → returns Array of all hit walls. `_charged_walls: Array` stores multiple walls. `detonate()` iterates all walls. Logic correct for multiple wall detection. However, all walls were breached using the **same** `det_pos` (primary hit position). |
| User feedback on PR #1094 | Screenshots show: charge placed at corner → only one wall visually broken. The corner looks illogical. User requests both walls to be partially broken at the corner. |
| PR #1094 (Phase 2) | Two bugs fixed — see Root Causes below. |

---

## Root Causes

### Root Cause 1: All walls breached at the same hit position

**Location:** `detonate()` in `scripts/effects/breaching_charges_effect.gd`

**Code (before fix):**
```gdscript
for wall_result in walls:
    _open_wall_passage(wall_result["wall"], det_pos)  # det_pos = primary wall's hit pos
```

**Problem:** `det_pos` is the hit position on the **primary** (nearest) wall. When `_open_wall_passage()` is called on a **secondary** wall (the other wall at the corner) using the primary wall's hit position, the `breach_local` position computed in the secondary wall's local coordinate space may land far from where the player actually touched that wall — often near the wall's edge or beyond it. This leads to the passage being carved at the wrong position on the secondary wall, or being clamped into an imperceptible notch.

**Fix:**
```gdscript
for wall_result in walls:
    _open_wall_passage(wall_result["wall"], wall_result["hit_pos"])  # each wall's OWN hit pos
```

Each wall result dictionary already stores the ray-cast hit position on that specific wall. Using it ensures the passage is carved at the correct surface point on each wall.

---

### Root Cause 2: Passage clamped away from wall ends (corner passages invisible)

**Location:** `_open_wall_passage()` — horizontal and vertical branch

**Code (before fix):**
```gdscript
# Horizontal wall
var bx: float = clamp(breach_local.x, -half_w + half_breach, half_w - half_breach)
```

**Problem:** At a corner, the ray hits the wall's surface near its **end** (the tip that meets the other wall). The `clamp()` was designed to prevent passages from being carved beyond the wall boundary, but it also prevented passages from being carved **at** the wall's end. When the hit is within `half_breach` (60px) of the end, the clamp would snap it inward — meaning the resulting passage is carved 60px from the end, leaving a 60px stub at the corner that looks intact and unbroken.

**Fix:** Replaced the symmetric clamp with explicit end-snap logic:
```gdscript
var bx: float = breach_local.x
if bx < -half_w + half_breach:
    bx = -half_w + half_breach  # snap to left end
elif bx > half_w - half_breach:
    bx = half_w - half_breach   # snap to right end
```

This is mathematically equivalent to the old clamp, but with explicit intent: when the hit is **near or beyond** the wall's end, snap the breach to the end position, so the passage is a notch at the corner tip. This makes both walls look visually broken at the corner junction.

---

## Visual Explanation

### Before Phase 2 fix (illogical):
```
╔══════════════╗
║              ║  ← vertical wall: passage carved in middle, corner intact
║              ║
╚══════════════╝
 ─────────────────  ← horizontal wall: passage at wrong position (primary hit pos)
```

### After Phase 2 fix (logical corner breach):
```
╔══════════════╗
║              ║
║              ║
╚═══════  ═════╝  ← vertical wall: gap at its BOTTOM end (corner)
         ↕ gap
 ──────  ─────────  ← horizontal wall: gap at its LEFT end (corner)
```

Both walls show a passage at the corner junction — visually logical, player can pass through the corner.

---

## Files Changed

- `scripts/effects/breaching_charges_effect.gd`
  - `detonate()`: use `wall_result["hit_pos"]` instead of shared `det_pos` for each wall
  - `_open_wall_passage()`: replace `clamp()` with end-snap logic for both horizontal and vertical branches
- `tests/unit/test_breaching_charges_effect.gd`
  - Updated `test_passage_not_carved_at_wall_edge_stays_clamped` → `test_passage_at_wall_edge_snaps_to_end`
  - Added `test_passage_at_wall_left_edge_snaps_correctly`
  - Added `test_corner_each_wall_uses_its_own_hit_position`

---

## Supporting Data

- `issue-data.json` — full issue JSON from GitHub API
- `pr-data.json` — full PR JSON
- `pr-comments.json` — conversation comments on PR #1094
- `pr-review-comments.json` — inline review comments on PR #1094
- `git-log.txt` — git history showing relevant commits
- `screenshot1.png` — user screenshot showing illogical corner (charge placed at corner, only one wall broken)
- `screenshot2.png` — user screenshot showing the expected visual (both walls broken at corner)

---

## References

- Godot 4 Physics: `PhysicsRayQueryParameters2D`, `direct_space_state.intersect_ray()` — ray cast returns the hit point in world space (`result["position"]`), which is used as `hit_pos` in the wall result dictionary.
- Godot 4 Node2D: `wall.to_local(world_pos)` — converts world-space hit point into wall-local coordinates for shape splitting arithmetic.
- Related PR #1089 (Issue #1087): original breaching charge implementation.
