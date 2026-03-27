# Case Study: Issue #1563 — Weapon Selection Animation: Radial Burst (Phase 2)

## Issue Description

**Title:** update анимация выбора оружия (update weapon selection animation)

**Request (translated from Russian):**
> Add a second animation (glint/shine from center to edges) after the existing one.
> Or ideally, a glint from the tip of the weapon outward in all directions (find references in pixel art animations).
> And implement it.

References PR #1545 which added the initial diagonal-sweep glint + squash-and-stretch animation.

---

## Context: Prior Work (Issue #1544 / PR #1545)

The weapon selection animation was first implemented in Issue #1544 (merged via PR #1545). It consists of:

1. **4-step squash-and-stretch scale punch** on the weapon icon (saint11 pixel-art principle):
   - Anticipation (wide/flat) → Action (tall stretch) → Follow-through (over-squish) → Settle
2. **Diagonal glint sweep shader** (`weapon_select_glint.gdshader`):
   - A ShaderMaterial applied to the weapon icon `TextureRect`
   - Narrow diagonal highlight band sweeps left → right over 0.22 s
   - Confined to icon UV space (cannot bleed onto card or background)
3. **Brightness flash** on the icon modulate (fires in parallel with scale)

---

## Research: Pixel Art "Burst/Flash" Animation Patterns

### saint11.art (Pedro Medeiros) Pixel Art Tutorials

Pedro Medeiros' tutorials (https://saint11.art/blog/pixel-art-tutorials/) describe multi-phase animation for selection/hit feedback:
- A common pattern for "impact flash" or "pick-up sparkle" is:
  1. Bright center flash (all-white for one frame)
  2. Expanding ring/burst radiating outward
  3. Fade to normal

This is well-established in pixel art games (Celeste, Shovel Knight, Enter the Gungeon).

### Radial Burst Pattern in the Codebase

The existing `gold_shine.gdshader` (Issue #1536) already implements a two-phase shine:
- **Phase 0 (0.00–0.45):** diagonal stripe sweep top-right → bottom-left
- **Phase 1 (0.45–0.65):** radial burst — expanding ring from center + solid inner fill

This is the exact pattern requested for Issue #1563 as a second phase to follow the diagonal sweep.

### Pixel Art "Glint from Tip" References

Common pixel art techniques for weapon select/pick-up sparkle:
| Technique | Description | Used In |
|-----------|-------------|---------|
| Expanding ring | Ring expands from center outward | Celeste, Hollow Knight |
| Cross/star burst | 4-directional or 8-directional rays from center | Shovel Knight, Blasphemous |
| Radial gradient flash | Full bright flash, then fades outward | Enter the Gungeon, Dead Cells |

For a small icon (48×48 pixels), the "expanding ring" approach is most readable and least noisy.

---

## Root Cause Analysis

The existing animation (from Issue #1544) provides only Phase 1 — a linear left-to-right diagonal sweep. This works well but feels "one-dimensional." The user requests a second effect that radiates from the center outward, giving a more complete "light bouncing off the weapon" feeling.

**Technical approach:** The existing `weapon_select_glint.gdshader` uses a single `anim_progress` uniform (0.0 → 1.0) driven by a GDScript tween. Extending to two phases is straightforward:
- Phase 1 occupies the first 52.4% of `anim_progress` (0.22 s out of 0.42 s total)
- Phase 2 occupies the remaining 47.6% (0.20 s)
- The tween duration in `armory_menu.gd` is extended from 0.22 s to 0.42 s

---

## Solution

### Changes Made

#### `scripts/shaders/weapon_select_glint.gdshader`

Added Phase 2 after the existing diagonal sweep:
- **Phase 1 (anim_progress 0.0 → 0.524):** Original diagonal sweep unchanged
- **Phase 2 (anim_progress 0.524 → 1.0):** Radial burst from center
  - Expanding ring: `exp(-ring_dist² × 120)` — soft glowing ring expands from center to icon corners
  - Inner fill: solid fill collapses as ring expands (gives "flash then spread" feeling)
  - Both fade in and out with `smoothstep` for smooth transitions
  - New `burst_color` uniform (default white) allows independent coloring of the burst

#### `scripts/ui/armory_menu.gd`

- Extended glint tween duration from `0.22` to `0.42` seconds
- Updated docstring to document both phases

### Why Expanding Ring vs. Cross-Ray

An expanding ring works well in UV space for any icon shape — it responds to the alpha mask naturally. Cross/star rays (4 or 8 directional spikes) require knowing the weapon's axis/orientation, which varies by weapon type. The ring approach is universal and pixel-art authentic (Celeste-style pop).

### Why Keep Phases Sequential (Not Parallel)

The diagonal sweep creates a sense of "light passing over" the icon. The radial burst then creates a sense of "energy radiating from within." These feel most natural sequentially — a sweep followed by a burst — rather than both happening at once (which would be visually noisy on a 48×48 icon).

---

## Possible Alternative Solutions

| Approach | Pros | Cons |
|----------|------|------|
| Expanding ring in shader (chosen) | Clean, UV-space, alpha-masked, zero extra nodes | Requires shader math |
| Cross-ray overlay nodes | Simple to prototype | Requires orientation data; creates extra nodes; may bleed outside icon |
| Particle system (GPUParticles2D) | Very flexible, can handle "from tip" request | Heavy for a UI effect; requires spawn point calculation |
| Spritesheet frame-by-frame burst | Traditional pixel art approach | Requires artist-created frames for each weapon |
| Pre-baked AnimationPlayer clip | Easy to tune visually | Not shader-based; harder to confine to icon |

The shader approach (chosen) is consistent with the existing implementation from Issue #1544 and requires no additional nodes or artist assets.

---

## Testing Checklist

- [ ] Open Armory menu
- [ ] Click an unlocked weapon slot
- [ ] Observe: diagonal sweep (Phase 1, ~0.22 s) immediately followed by radial burst expanding from center (Phase 2, ~0.20 s)
- [ ] Verify neither phase bleeds outside the weapon icon silhouette
- [ ] Verify card border, background, and label are unaffected
- [ ] Click same slot rapidly — no animation stacking or jitter
- [ ] Click grenade slot — same two-phase animation plays
- [ ] Click active item slot — same two-phase animation plays
