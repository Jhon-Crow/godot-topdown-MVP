# Case Study: Issue #1386 — Flashlight Beam Not Visible on Decadence Level

## Issue Summary

**Reported by:** @Jhon-Crow
**Description (Russian):** "fix на уровне Декаданс не работает фонарик" / "не появляется луч хотя звук активации работает"
**Translation:** On the Decadence level, the flashlight doesn't work — the beam doesn't appear even though the activation sound plays.

## Environment

- Engine: Godot 4.3-stable (official)
- Renderer: `gl_compatibility` (inferred from export target)
- OS: Windows
- Level: DecadenceLevel (Hotline Miami "Chapter Three: Decadence")

## Data Sources

- `logs/game_log_20260323_135325.txt` — Full game session log from the reporter
- Source code analysis of `flashlight_effect.gd`, `player.gd`, `DecadenceLevel.tscn`
- Godot engine issue tracker and documentation

## Timeline of Events (from game log)

| Time | Event |
|------|-------|
| 13:53:25 | Game starts on LabyrinthLevel |
| 13:53:30 | Player switches active item to Flashlight |
| 13:53:30 | FlashlightEffect initializes: `energy=0.0, shadow=true` (off by default) |
| 13:53:34 | Scene change to DecadenceLevel begins |
| 13:53:35 | DecadenceLevel loaded, 13 enemies registered |
| 13:53:35 | Flashlight re-initializes on new level: `energy=0.0, shadow=true` |
| 13:53:36 | Player holds Space — flashlight turns on |
| 13:53:36 | Enemies detect flashlight beam (game logic works) |
| 13:53:36 | `BackAlleyGunman` blinded by beam at distance 309 (blindness applied for 2.0s) |
| 13:53:38 | Multiple enemies (`DanceFloorThug2`, `DanceFloorGunman`) detect beam |
| 13:53:39 | Player enters RadioJammer range (dist=922.9, radius=1000) |
| 13:53:39 | **"Space blocked by Radio Jammer (Issue #1036)"** — flashlight input blocked |
| 13:53:40 | Player dies to enemy gunfire |

## Key Observations

1. **Flashlight game logic works correctly**: Enemies detect the beam, get blinded, pursue the player. The raycast-based beam mechanics function independently of rendering.
2. **Flashlight visual beam is invisible**: Despite the game logic working, the player cannot see the light cone — this is a rendering issue, not a logic issue.
3. **Sound plays correctly**: The toggle sound is independent of the rendering pipeline.
4. **RadioJammer compounds the issue**: On this level, a RadioJammer enemy blocks flashlight activation when the player is within 1000px radius, adding a secondary gameplay blocker.

## Root Cause Analysis

### Initial Hypothesis (Incorrect): Shadow Budget Limit

The initial fix (commit `be56f31b`) hypothesized that Godot's `gl_compatibility` renderer limits shadow-casting 2D lights to 8 per viewport. The fix disabled `shadow_enabled` on all 44 neon PointLight2D nodes.

**Why this was insufficient:** Disabling shadows removes the neon lights from the shadow rendering pipeline, but they still count as active PointLight2D nodes that consume the per-CanvasItem light budget.

### True Root Cause: Godot 4 Per-CanvasItem Light Limit (15 lights)

**Godot's 2D rendering system has a hard limit of 15 PointLight2D nodes per CanvasItem.**

This limit is defined in the renderer source code:
- Forward+/Mobile: `renderer_canvas_render_rd.h`
- Compatibility (GLES3): `rasterizer_canvas_gles3.h`

The limit uses a 4-bit counter per CanvasItem to track overlapping lights. When the counter reaches 15, no additional lights are rendered on that CanvasItem.

**Evidence:**
- Godot Issue [#68812](https://github.com/godotengine/godot/issues/68812): "When the number of PointLight2D nodes is up to 16, all 2D lights are not visible"
- Godot PR [#71776](https://github.com/godotengine/godot/pull/71776): Fixed overflow bug where >15 lights caused ALL lights to disappear (the counter wrapped to 0). In Godot 4.3, the overflow is fixed but the 15-light cap remains.
- Godot Proposals Discussion [#9336](https://github.com/godotengine/godot-proposals/discussions/9336): Confirms "the cap is not smart — it doesn't care if lights overlap each other, and it treats every node as a rectangle"

**In DecadenceLevel:**
- 64 PointLight2D nodes exist (44 directional neon + 20 omnidirectional neon)
- The floor `ColorRect` spans the entire level (2400×2000 pixels)
- Most neon lights overlap the floor rect → floor sees 64+ lights
- The flashlight PointLight2D becomes light #65 — far beyond the 15-light limit
- Result: **the flashlight beam is never rendered on the floor or walls**

### Why the Game Logic Still Works

The flashlight's game mechanics (enemy detection, blindness) use `PhysicsRayQueryParameters2D` raycasts, not the rendering pipeline. These raycasts are completely independent of the PointLight2D rendering budget. So enemies correctly detect and react to the beam even when it's invisible.

## Solutions

### Solution 1: Reduce PointLight2D Count (Implemented)

Reduce the 64 neon PointLight2D nodes to ~8 strategically placed lights. This keeps the total lights in any area well under 15, leaving room for the flashlight (1-2 lights), muzzle flashes, and explosions.

The visual impact is minimized by:
- Using slightly higher `energy` values on remaining lights to compensate
- Placing lights at key visual focal points (room centers, dance floor)
- Keeping the colored `ColorRect` neon strips which provide the base glow appearance

### Solution 2 (Alternative): Replace PointLight2D with Sprite2D + Additive Blend

Convert neon glow effects from PointLight2D to Sprite2D nodes with `CanvasItemMaterial` set to additive blend mode. This achieves a similar visual glow without consuming any light budget slots. Not implemented in this fix but could be explored if more decorative lights are needed.

### Solution 3 (Alternative): Break Floor into Tiles

Split the large floor `ColorRect` into smaller tiles so each tile only overlaps nearby lights. This is architecturally complex and fragile — adding new lights could easily re-trigger the issue.

## References

- [Godot 4 2D Lights and Shadows Documentation](https://docs.godotengine.org/en/stable/tutorials/2d/2d_lights_and_shadows.html)
- [Godot Issue #68812: 16 PointLight2D causes all lights invisible](https://github.com/godotengine/godot/issues/68812)
- [Godot PR #71776: Fix light counter overflow](https://github.com/godotengine/godot/pull/71776)
- [Godot Proposals #9336: Increase 2D Light cap](https://github.com/godotengine/godot-proposals/discussions/9336)
- [Godot Forum: Working around 2D light limitations](https://forum.godotengine.org/t/working-around-godots-2d-light-limitations-for-a-dark-game/81311)

## Lessons Learned

1. **Godot's 2D light limit is per-CanvasItem, not per-viewport or global.** Large CanvasItems (full-level floors) are particularly vulnerable.
2. **The limit applies to ALL PointLight2D nodes, regardless of `shadow_enabled`.** Disabling shadows alone doesn't free light budget slots.
3. **Game logic and rendering are independent.** A flashlight can function correctly for AI/gameplay while being completely invisible to the player.
4. **Decorative lights should use non-PointLight2D techniques** when many are needed (sprites with additive blending, shader effects, etc.).
