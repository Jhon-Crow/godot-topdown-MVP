# Case Study: Issue #1035 — Add Decadence Map (Invisible Walls Bug)

## Overview

**Issue:** [#1035](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1035)
**Title:** добавь новую карту Decadence (Add new Decadence map)
**Status:** Resolved in PR [#1039](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1039)
**Branch:** `issue-1035-6bd8f0a83f4f`
**Fix Commit:** `177438a4`

---

## Executive Summary

The repository owner requested a new playable map named "Decadence", inspired by Chapter 3 of the game Hotline Miami (a nightclub level). An AI agent implemented the map in a first session, creating the scene file (`DecadenceLevel.tscn`), the level script (`decadence_level.gd`), and wiring the map into the game's menu and level-chain systems. The implementation was technically functional at the physics layer — all collision shapes were present and correct — but the map shipped with completely invisible walls.

The root cause was a missing visual layer: in Godot 4, `StaticBody2D` nodes carry no intrinsic rendering. Every wall in the project's other maps pairs its `StaticBody2D` with a `ColorRect` child node that provides the rendered rectangle the player sees. The initial Decadence implementation omitted `ColorRect` from all 11+ wall `StaticBody2D` nodes, so the walls existed only as invisible physics barriers.

The bug was caught during owner review, diagnosed by comparing scene structure with existing levels, and fixed by adding a correctly-sized and correctly-coloured `ColorRect` to every wall node.

---

## Timeline / Sequence of Events

1. **Issue #1035 opened** by Jhon-Crow.
   > "добавь карту Decadence из hotline miami."
   > ("Add the Decadence map from Hotline Miami.")
   The issue referenced an image of the Hotline Miami Chapter 3 Decadence nightclub layout.

2. **First AI session — initial implementation** (commit `9eb0dbde`).
   The agent created:
   - `scenes/levels/DecadenceLevel.tscn` — full scene with room layout, wall `StaticBody2D` nodes (each containing `CollisionShape2D` and `LightOccluder2D`), spawn/exit markers, and area nodes for each sub-room (VIP Room, Bar, Dance Floor, Back Alley, Storage).
   - `scripts/levels/decadence_level.gd` — level controller script.
   - Menu and level-chain integration — Decadence added to level selection UI and chained into the progression sequence.
   All collision geometry and occluder data were correct. `ColorRect` nodes were not added to any wall.

3. **Auto-restart session #1** — a stray uncommitted asset (`decadence_card.png`) was found in the working tree, cleaned up, and the branch was confirmed ready to merge.

4. **Owner review — bug reported.**
   The repository owner tested the map in-engine and commented:
   > "стены либо не видно либо плохо видно. проверь, нет ли невидимых стен."
   > ("The walls are either invisible or barely visible. Check for invisible walls.")

5. **Diagnosis session** — the agent compared `DecadenceLevel.tscn` with `BuildingLevel.tscn` and `DocksLevel.tscn`. The structural difference was immediately apparent: every `StaticBody2D` wall in the existing levels had a `ColorRect` child; no `StaticBody2D` wall in `DecadenceLevel.tscn` had one.

6. **Fix applied** — `ColorRect` nodes were added to all 11 wall nodes in `DecadenceLevel.tscn`. Each `ColorRect` was sized to match its sibling `RectangleShape2D` exactly, and coloured using the neon purple/pink palette appropriate to a nightclub aesthetic (commit `177438a4`).

7. **Branch ready for merge.**

---

## Root Cause Analysis

### Technical Background

Godot 4 separates physics from rendering. A `StaticBody2D` node is a pure physics object: it participates in collision detection but has no visual output. To make a wall visible, a visual child node — typically `ColorRect`, `Sprite2D`, or a mesh instance — must be explicitly added as a child of the `StaticBody2D`.

In this project, the established convention for walls is:

```
StaticBody2D  (WallTop, WallLeft, etc.)
├── CollisionShape2D   ← defines physics boundary
├── LightOccluder2D    ← blocks light propagation
└── ColorRect          ← the visible rectangle the player sees
```

The `ColorRect` offset properties (`offset_left`, `offset_right`, `offset_top`, `offset_bottom`) are set to values that exactly match the half-extents of the sibling `RectangleShape2D`, so the visual and physical rectangles are identical.

### What Went Wrong

The AI agent constructing `DecadenceLevel.tscn` correctly modelled the physics layer (placing `CollisionShape2D` and `LightOccluder2D` in every wall node) but did not add a `ColorRect` to any wall. The result was a scene where:

- Walls **blocked movement** (collision shapes present).
- Walls **blocked light** (occluders present).
- Walls were **not rendered** (no `ColorRect`).

This is a silent failure: Godot does not warn or error when a `StaticBody2D` has no visual child. The game runs without exception; the walls simply cannot be seen.

### Structural Evidence

Comparison of scene node children for a representative boundary wall across three levels:

| Node child        | BuildingLevel.tscn | DocksLevel.tscn | DecadenceLevel.tscn (original) |
|-------------------|--------------------|-----------------|--------------------------------|
| CollisionShape2D  | present            | present         | present                        |
| LightOccluder2D   | present            | present         | present                        |
| ColorRect         | **present**        | **present**     | **absent**                     |

Every wall in every existing level had `ColorRect`. No wall in the initial Decadence scene had `ColorRect`.

### Why the Omission Occurred

The most likely explanation is that the AI agent generated the scene file by authoring `.tscn` text directly, rather than by copying a validated wall template. When constructing new content from scratch it replicated the physics nodes (which are explicitly required to prevent pass-through) but missed the rendering node (which is implicitly required by visual convention but not enforced by the engine).

A contributing factor is the absence of a project-level wall prefab (an instantiable scene) that would force all three children to be present together. Each existing level duplicates the wall structure inline, so there is no single source of truth that an automated tool could reference.

---

## Impact Assessment

| Dimension | Detail |
|-----------|--------|
| **Player-facing severity** | High — the map was unplayable in a meaningful sense. Players could not see where walls were, making navigation and tactical decisions impossible. |
| **Physics correctness** | None — collision and occluder data were correct. Movement blocking and lighting were fully functional. |
| **Scope** | Localised to `DecadenceLevel.tscn`. No other scene, script, or asset was affected. |
| **Detectability** | Not detectable by static analysis or unit tests with the project's existing tooling. Requires visual inspection in-engine or a structural scene audit. |
| **Time to fix** | Low — once diagnosed, the fix was mechanical: add a correctly-sized `ColorRect` to each wall. The diagnosis itself was fast because the pattern was clear from comparing existing levels. |

---

## Solution Applied

### Approach

For each of the 11 affected wall nodes, a `ColorRect` child node was added with:

1. **Dimensions** calculated from the wall's `RectangleShape2D` `size` property:
   - A wall of size `(W, H)` uses `offset_left = -W/2`, `offset_right = W/2`, `offset_top = -H/2`, `offset_bottom = H/2`.
2. **Colour** selected from the nightclub neon palette:
   - Boundary/structural walls: deep purple `Color(0.15, 0.05, 0.2, 1)`.
   - Interior partition walls: dark mauve or near-black variants to give visual depth to the room layout.

### Wall Nodes Fixed

| Wall node name          | Zone              |
|-------------------------|-------------------|
| WallTop                 | Boundary          |
| WallBottom              | Boundary          |
| WallLeft                | Boundary          |
| WallRight               | Boundary          |
| VIPWallRight            | VIP Room          |
| VIPWallBottom           | VIP Room          |
| BarWallLeft             | Bar area          |
| BarWallBottom           | Bar area          |
| BackAlleyWallTop        | Back Alley        |
| BackAlleyWallRight      | Back Alley        |
| StorageWallLeft         | Storage area      |
| StorageWallTop          | Storage area      |
| DanceFloorDividerTop    | Dance Floor       |

### Representative Fix (WallTop, 2464×32)

Before (original scene node, abridged):
```
[node name="WallTop" type="StaticBody2D"]
  [node name="CollisionShape2D" type="CollisionShape2D" parent="WallTop"]
  [node name="LightOccluder2D"  type="LightOccluder2D"  parent="WallTop"]
```

After:
```
[node name="WallTop" type="StaticBody2D"]
  [node name="CollisionShape2D" type="CollisionShape2D" parent="WallTop"]
  [node name="LightOccluder2D"  type="LightOccluder2D"  parent="WallTop"]
  [node name="ColorRect"        type="ColorRect"        parent="WallTop"]
    offset_left   = -1232
    offset_right  =  1232
    offset_top    =   -16
    offset_bottom =    16
    color         = Color(0.15, 0.05, 0.2, 1)
```

---

## Lessons Learned / Proposed Prevention Measures

### 1. Introduce a Reusable Wall Scene (Prefab)

**Problem:** Wall structure is duplicated inline across every level scene. There is no enforcement that all three children (`CollisionShape2D`, `LightOccluder2D`, `ColorRect`) are present.

**Recommendation:** Create a `WallBlock.tscn` instantiable scene that pre-packages all three children. Level designers (human or AI) then instantiate this scene and set only the size/colour properties. Missing the `ColorRect` becomes structurally impossible.

### 2. Add a Guideline to Contributing Documentation

**Problem:** The requirement for a `ColorRect` child on wall nodes is implicit knowledge, not written down anywhere.

**Recommendation:** Add to the project's contributing guidelines:
> "All `StaticBody2D` wall nodes must include a `ColorRect` child node. The `ColorRect` offset values must match the half-extents of the sibling `RectangleShape2D`. Walls without a visible `ColorRect` will be rejected in review."

### 3. Add a CI Scene Audit Script

**Problem:** The invisible-wall bug was not detectable by any automated check.

**Recommendation:** Add a GDScript or Python/gdtoolkit audit script that parses `.tscn` files and reports any `StaticBody2D` node that lacks a `ColorRect` child. This script can run as a CI step on every pull request.

Example pseudologic:
```
for each .tscn file:
    for each StaticBody2D node:
        if node has no ColorRect child:
            FAIL: "Wall '{name}' in '{scene}' has no ColorRect"
```

### 4. Add a Code Review Checklist Item

**Problem:** The PR passed without catching the invisible walls, suggesting the review process does not explicitly verify visual representation.

**Recommendation:** Add to the PR review checklist:
- [ ] All `StaticBody2D` wall nodes in new/modified scenes have a `ColorRect` child.
- [ ] New levels have been visually inspected in-engine (not just reviewed as text diffs).

### 5. Use Annotated Screenshots in Issue Requirements

**Problem:** The original issue provided a reference image of the Hotline Miami Decadence map but no explicit list of required visual elements.

**Recommendation:** For map-addition issues, include a short checklist of required structural elements (e.g., "visible boundary walls", "labelled sub-rooms") alongside the reference image. This gives the implementer — human or AI — a concrete acceptance criterion to check against.

---

## Related Issues and PRs

| Reference | Description |
|-----------|-------------|
| Issue #1035 | Original feature request — add Decadence map |
| PR #1039 | Implementation and fix — feat: add Decadence map |
| Commit `9eb0dbde` | Initial map implementation (walls invisible) |
| Commit `177438a4` | Fix — added ColorRect to all wall nodes |

---

## Related Files

| File | Role |
|------|------|
| `scenes/levels/DecadenceLevel.tscn` | Primary affected file — Decadence map scene |
| `scripts/levels/decadence_level.gd` | Level controller (not affected by the bug) |
| `scenes/levels/BuildingLevel.tscn` | Reference — correct wall node structure |
| `scenes/levels/DocksLevel.tscn` | Reference — correct wall node structure |
