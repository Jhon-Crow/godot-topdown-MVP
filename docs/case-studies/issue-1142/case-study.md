# Case Study: Issue #1142 — Player Item Visual Effects System

## Problem Statement

Issue #1142 requests that the Armored Skin passive item apply the same crystal/glass armor visual
effect to the **player character** that was added to enemies in PR #1124. Additionally, the PR
owner comment (2026-03-20) asks for a **generic, extensible system** for changing player visuals
based on the active item — so that future items can plug in their effects cleanly.

---

## Repository Context

### Affected Files

| File | Role |
|------|------|
| `scripts/characters/player.gd` | ~4800-line monolith; currently owns all per-item initialization |
| `scripts/shaders/armored_skin.gdshader` | Crystal/glass armor overlay shader (from PR #1124) |
| `scripts/components/enemy_armored_skin_component.gd` | Component that already applies the shader to enemies |
| `scripts/autoload/active_item_manager.gd` | Autoload singleton listing all 17+ item types |
| `scripts/effects/invisibility_suit_effect.gd` | Example effect node that manages a shader on player sprites |

### Current Pattern (Before This PR)

`player.gd` has a dedicated `_init_X()` / `_apply_X_visual()` function pair for every item.
Currently `_init_armored_skin()` calls `_apply_armored_skin_visual()` which directly iterates
`PlayerModel` children and assigns a `ShaderMaterial` to each `Sprite2D`.  There is no central
dispatcher that says "for item X, apply visual Y".

### Enemy Reference Implementation

`EnemyArmoredSkinComponent` (added in PR #1124) shows the target pattern for the player:
- A dedicated component node owns the shader and applies/removes it.
- It applies to all `Sprite2D` children inside `EnemyModel`.
- It removes the visual after the shard-spawn trigger fires.

---

## Root-Cause Analysis

The visual effect already exists in the shader (`armored_skin.gdshader`) and already works on
enemies.  The gap is:

1. **No generic dispatch**: there is no central function in `player.gd` that maps
   `ActiveItemType → visual application function`, making it easy to miss when adding new items.
2. **Armored Skin specifically**: `_apply_armored_skin_visual()` exists and applies the shader, but
   it is buried inside `_init_armored_skin()` with no conceptual boundary that separates
   *mechanics* (shard spawning) from *visuals* (shader overlay).

---

## Technical Constraints

### Godot 4 Single-Material-Slot Limitation

`CanvasItem` (Sprite2D) has exactly **one material slot**. The `next_pass` property does **not**
work for 2D CanvasItem shaders ([godot#27726][1], [proposals#7870][2]).  This means you cannot
naively stack multiple shader effects on a single sprite.

**Practical workarounds** (ranked by complexity):

| Approach | Performance | Composability | Complexity |
|----------|-------------|---------------|------------|
| Single combined shader with uniform flags | Best (1 draw call) | Limited (shader grows) | Medium |
| SubViewport chain | Worst (N draw calls) | Unlimited | High |
| One item active at a time (current design) | Best | N/A | Low |

Because the current game design has **one active item per battle** and items with visuals tend to
be mutually exclusive (only one shader per sprite needed), the simplest approach is valid:
**a central dispatch function in `player.gd` that applies the correct shader based on
`current_active_item`**.

[1]: https://github.com/godotengine/godot/issues/27726
[2]: https://github.com/godotengine/godot-proposals/issues/7870

---

## Similar Patterns in the Codebase

| Item | Visual Effect | Implementation |
|------|---------------|----------------|
| Invisibility Suit | Predator-style cloak shader | Separate node (`InvisibilitySuitEffect`) |
| Armored Skin (enemy) | Crystal armor shader | Separate component (`EnemyArmoredSkinComponent`) |
| Force Field | Glowing shield sprite | Separate node (`ForceFieldEffect`) |
| Last Chance | Flash overlay shader | Shader applied in `_update_health_visual` |
| Health tint | Blue→dark modulate | `_update_health_visual()` + `_set_all_sprites_modulate()` |

All long-lived visual effects use dedicated nodes/components. Only transient visual feedback (hit
flash, health tint) is handled inline in `player.gd`.

---

## Design Options

### Option A: Inline dispatch in `_init_armored_skin()` (status quo)
Keep `_apply_armored_skin_visual()` exactly as is.  No central dispatch.

**Pros:** No refactor needed.
**Cons:** Each future item must remember to add its own `_apply_X_visual()`.  No discoverable
mapping from item type to visual.

### Option B: Central `_apply_item_visual()` dispatcher in `player.gd`
Add a single `_apply_item_visual(item_type: int) -> void` function that uses a `match` statement
to call the right per-item visual function.  Call it once from `_ready()` after the active item
is confirmed.

**Pros:** Single entry point for all item visuals.  Easy to see which items have visuals.
**Cons:** Still monolithic; every visual lives in `player.gd`.

### Option C: `ItemVisualManager` child node (full component pattern)
Extract all visual logic into a dedicated child `Node` with a registry of `ShaderMaterial`
resources keyed by `ActiveItemType`.

**Pros:** Cleanest separation; player script is unaware of shader paths.
**Cons:** Requires moving significant code; premature abstraction for the current item count.

---

## Recommendation

**Option B** is the right balance for this codebase now:

- It is a small, targeted change to `player.gd`.
- It creates an explicit, discoverable mapping from active item type to visual effect.
- It can later be promoted to Option C if item count grows significantly.
- The Armored Skin visual already works; this PR adds the dispatch layer and wires it in.

### Implementation Plan

1. Add `_apply_item_visual() -> void` to `player.gd`, called from `_ready()` after all item
   inits complete.
2. Use a `match` on `ActiveItemManager.current_active_item` to delegate to per-item visual
   functions.
3. Wire Armored Skin to its existing `_apply_armored_skin_visual()` function.
4. Document the function clearly so future items know where to add their visual entry.

---

## Online Research Summary

### Key Findings

- **Godot 4 has no native multi-pass CanvasItem shader support** — confirmed in engine issues
  and proposals. The single-material-slot limitation is fundamental.
- **Component pattern** (Game Programming Patterns) is the standard Godot recommendation for
  per-feature logic, matching Godot's own node hierarchy.
- **GDQuest guidelines** recommend extracting effects into nodes when they involve shaders or
  are independently toggle-able.
- **Existing codebase patterns** (`InvisibilitySuitEffect`, `EnemyArmoredSkinComponent`) already
  follow Option C for complex effects. For the simple case of a passive always-on shader, a
  dispatch function (Option B) is sufficient.

### Sources
- [Godot Engine — CanvasItem shaders (4.4 docs)](https://docs.godotengine.org/en/4.4/tutorials/shaders/shader_reference/canvas_item_shader.html)
- [Godot Issue #27726 — multi-pass CanvasItem materials](https://github.com/godotengine/godot/issues/27726)
- [Godot Proposals #7870 — Support multiple shader passes](https://github.com/godotengine/godot-proposals/issues/7870)
- [Game Programming Patterns — Component](https://gameprogrammingpatterns.com/component.html)
- [GDQuest GDScript guidelines](https://gdquest.gitbook.io/gdquests-guidelines/godot-gdscript-guidelines)
- [youer0219/ShadersSprite2D — multi-shader via SubViewport](https://github.com/youer0219/ShadersSprite2D)
- [gdquest-demos/godot-shaders](https://github.com/gdquest-demos/godot-shaders)

---

## Proposed Solution

Add `ApplyItemVisual()` as the central dispatcher for player item visuals, called once during
`Ready()` in `Player.cs`.  The function checks `has_armored_skin()` on `ActiveItemManager` and
delegates to `ApplyArmoredSkinVisual()` for the crystal/glass armor overlay.

Armored Skin is the first item wired into this system; subsequent items add one check here.

See the implementation diff in the pull request for PR #1179.

---

## Bug Report: Visual Not Working (2026-03-20)

### Owner Comment

> «не работает» (it doesn't work)

The owner tested the game with Armored Skin equipped and the crystal armor visual did not appear.
They also requested that build info (branch, commit, date) be added to the game log.

### Log File Analysis

**File:** `game_log_20260320_072454.txt` — downloaded from GitHub issue comment attachment.

**Key observations:**

1. **Log line at 07:24:54 (line 169):**
   ```
   [Player.ArmoredSkin] Armored skin active — shards will spawn when HP ≤2 and hit
   ```
   This matches **`Player.cs` line 6657** (C# code), not the GDScript `player.gd`.

2. **No `[Player.ItemVisual]` log line anywhere in the log.** Our implementation of
   `_apply_item_visual()` lives in `player.gd` (GDScript) and logs
   `[Player.ItemVisual] Visual applied for item type: …` — its complete absence proves the
   GDScript function was never called.

3. **C# player confirmed:** Line 186 in the log:
   ```
   [LabyrinthLevel] MiniUzi already equipped by C# Player — skipping GDScript weapon swap
   ```
   The game uses `scenes/characters/csharp/Player.tscn` which is driven by `Scripts/Characters/Player.cs`,
   **not** by `scripts/characters/player.gd`.

### Root Cause

**The visual dispatcher was implemented in the wrong script.**

`scripts/characters/player.gd` (GDScript) is used only by the legacy GDScript player scene
(`scenes/characters/Player.tscn`). The actual game uses the C# player
(`scenes/characters/csharp/Player.tscn` → `Scripts/Characters/Player.cs`).

All previous armored skin commits correctly modified `Player.cs` for the mechanics (shard spawning,
HP bonus). The visual dispatch code was mistakenly added only to `player.gd`, so the C# player
never called `ApplyArmoredSkinVisual()`.

### Timeline

| Time | Event |
|------|-------|
| 2026-03-18 | First PR draft: visual added to `player.gd` (GDScript) |
| 2026-03-20 04:10 | Second session: dispatcher added to `player.gd` (GDScript) — still wrong file |
| 2026-03-20 07:24 | Owner tests release build — visual missing, log attached |
| 2026-03-20 | Root cause identified: C# player (`Player.cs`) needs the fix |

### Fix Applied

Added `ApplyItemVisual()` and `ApplyArmoredSkinVisual()` to `Scripts/Characters/Player.cs`:
- `ApplyItemVisual()` — calls `ApplyArmoredSkinVisual()` when `has_armored_skin()` is true
- `ApplyArmoredSkinVisual()` — loads `armored_skin.gdshader` and applies it as a `ShaderMaterial`
  to all `Sprite2D` children of `_playerModel`
- Called from `Ready()` after `InitArmoredSkin()`

Also added build info logging to `file_logger.gd`:
- Reads `res://build_info.cfg` (branch, commit, date) and logs it in the game log header
- `build_info.cfg` is updated on each commit/push so every exported build is traceable

---

## Second Bug Report: Shader Applied But Not Visible (2026-03-20 06:05)

### Owner Comment

> «не работает, должно работать примерно как в the binding of isaac — предмет визуал предмета
> должен накладываться поверх игрока. приложи скриншот результата»
>
> Translation: "doesn't work, should work roughly like in The Binding of Isaac — the item's visual
> should be overlaid on top of the player. attach a screenshot of the result."

### Root Cause

The previous fix (shader applied to existing `Sprite2D` materials) may have worked on paper, but
the owner's expectation is a **visual overlay** — a separate set of sprites drawn **on top** of the
player, not a material modification.

In The Binding of Isaac, items overlay as **additional sprites** on the character model: the base
character is untouched and an item-specific sprite layer is composited above it. This is
fundamentally different from a shader modifying the base sprite.

Additionally, Godot's `ResourceLoader.Exists()` can fail silently in exported builds when textures
have not been explicitly preloaded into the export preset, meaning the shader-based approach could
appear to succeed at runtime but produce no visible result.

### Solution: Overlay Sprite System

**Approach:** Create dedicated crystal armor overlay sprites (one per body part), and add them as
new `Sprite2D` children of `PlayerModel` at runtime when Armored Skin is equipped.

| File | Change |
|------|--------|
| `assets/sprites/characters/player/armored_skin/armored_skin_body.png` | New — crystal blue overlay for body |
| `assets/sprites/characters/player/armored_skin/armored_skin_head.png` | New — crystal blue overlay for head |
| `assets/sprites/characters/player/armored_skin/armored_skin_left_arm.png` | New — crystal blue overlay for left arm |
| `assets/sprites/characters/player/armored_skin/armored_skin_right_arm.png` | New — crystal blue overlay for right arm |
| `assets/sprites/characters/player/armored_skin/armored_skin_armband.png` | New — crystal blue overlay for armband |
| `Scripts/Characters/Player.cs` | `ApplyArmoredSkinVisual()` rewrote to add overlay sprites |
| `docs/screenshots/armored_skin_preview.png` | Side-by-side preview screenshot |

### Overlay Sprites

The overlay sprites are derived from the original player body part sprites:
- Same dimensions and silhouette
- All non-transparent pixels filled with `rgba(100, 200, 255, 120)` — azure blue at ~47% opacity
- This lets the original character show through while adding the crystal armor tint

Generated via: `experiments/generate_armored_skin_overlays.py`

### Implementation Detail

`ApplyArmoredSkinVisual()` in `Player.cs`:
1. Iterates `_playerModel` children (only `Sprite2D` nodes in the overlayMap)
2. For each matching body part, creates a new `Sprite2D` overlay node
3. Sets position and offset to match the base sprite
4. Sets `ZIndex = baseSprite.ZIndex + 10` so the overlay is always on top
5. Adds the overlay as a child of `_playerModel`

This exactly matches the Isaac pattern: the player's body is unchanged; new colored sprites float
above each body part.

### Preview Screenshot

See `docs/screenshots/armored_skin_preview.png` — side-by-side comparison of player without armor
and with crystal armor overlays active.

### Timeline Update

| Time | Event |
|------|-------|
| 2026-03-20 06:05 | Owner reports visual still not working; requests Isaac-style overlay + screenshot |
| 2026-03-20 | Root cause: shader approach doesn't match expected overlay visual pattern |
| 2026-03-20 | Fix: overlay sprite system — new crystal overlay PNGs + Sprite2D nodes added at runtime |
