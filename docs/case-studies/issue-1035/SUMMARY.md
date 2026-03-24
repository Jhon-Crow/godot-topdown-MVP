# Summary: Issue #1035 — Invisible Walls in Decadence Map

## Key Facts

**Issue:** #1035 — "добавь новую карту Decadence" (Add new Decadence map from Hotline Miami)
**PR:** #1039 — feat: add Decadence map
**Branch:** `issue-1035-6bd8f0a83f4f`
**Bug-fix commit:** `177438a4`

---

## What Was Asked

Add a new playable map called "Decadence", based on the Chapter 3 nightclub from Hotline Miami.

## What Was Delivered (First Pass)

- `DecadenceLevel.tscn` with full room layout (VIP Room, Bar, Dance Floor, Back Alley, Storage)
- `decadence_level.gd` level controller
- Menu and level-chain integration
- All collision shapes and light occluders in place

## The Bug

All walls in the scene were **completely invisible**. The map was physically correct (movement was blocked) but unplayable because players could not see the walls.

## Root Cause

In Godot 4, `StaticBody2D` has no built-in visual. Every wall in the project requires a `ColorRect` child node to be visible. The initial implementation added `CollisionShape2D` and `LightOccluder2D` to each wall but omitted `ColorRect`. The engine does not warn about this — the scene runs silently with invisible walls.

**Pattern required (and missing):**
```
StaticBody2D
├── CollisionShape2D   ← physics
├── LightOccluder2D    ← lighting
└── ColorRect          ← VISUAL (was absent)
```

## Scope

13 wall nodes affected across 5 zones: boundary walls, VIP Room, Bar, Back Alley, Storage, and the Dance Floor divider.

## Fix

Added `ColorRect` to all 13 wall nodes with:
- Offset dimensions matching the `RectangleShape2D` half-extents exactly
- Neon purple/pink palette (`Color(0.15, 0.05, 0.2, 1)` and variants) matching the nightclub theme

## How It Was Caught

Owner visual inspection after the first implementation was committed.

## Prevention Recommendations

1. Create a reusable `WallBlock.tscn` prefab that bundles all three child nodes together.
2. Document the `ColorRect` requirement in contributing guidelines.
3. Add a CI scene-audit script that flags any `StaticBody2D` wall missing a `ColorRect`.
4. Add "verify walls have visual children" to the PR review checklist.
5. Require in-engine visual sign-off for all new level submissions.
