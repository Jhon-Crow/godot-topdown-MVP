# Case Study: Issue #546 — Add Active Item: Flashlight

## Overview

- **Issue**: [#546](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/546) — добавить активный предмет - фонарик
- **PR**: [#551](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/551)
- **Date**: 2026-02-07
- **Severity**: Feature request + bug fix
- **Status**: In progress (second bug report from owner)

## Issue Description

The owner requested a new category of items — **active items** — with a flashlight as the first item:
- New "active items" category in the armory menu (separate section)
- Flashlight equipped via armory → appears under weapon barrel
- Hold Space to activate bright white light in weapon direction
- Release Space to immediately turn off
- Light intensity between normal and flashbang level

## Timeline of Events

| Time (UTC) | Event | Details |
|------------|-------|---------|
| 2026-02-07 02:38 | Issue created | Owner opens #546 with flashlight specification and reference image |
| 2026-02-07 03:43 | First AI session starts | Solution draft begins on branch `issue-546-4037c72ccfd7` |
| 2026-02-07 03:44 | Rate limit hit | First session interrupted immediately (usage limit) |
| 2026-02-07 09:47 | Second AI session starts | Auto-resume after limit reset |
| 2026-02-07 09:58 | Implementation committed | Commits `81dbb10` (feat) and `cd2b8fc` (tests) pushed |
| 2026-02-07 10:02 | PR marked ready | Title updated, PR marked ready for review |
| 2026-02-07 10:02 | Auto-restart | Cleanup of `pr_diff.txt` artifact |
| 2026-02-07 ~11:58 | Owner feedback | Three issues reported (see below) |
| 2026-02-07 12:03 | Third AI session starts | Fix session begins |
| 2026-02-07 12:06+ | Fixes implemented | Icon replaced, flashlight bug fixed, sound added |
| 2026-02-07 12:18 | PR updated | Third session completed |
| 2026-02-07 12:30 | Owner reports bug again | "при нажатии пробела ничего не происходит" (nothing happens on Space press) — attached `game_log_20260207_152902.txt` |
| 2026-02-07 12:31 | Fourth AI session starts | Investigation begins |
| 2026-02-07 ~12:35 | **Critical root cause found** | All flashlight code was in GDScript `player.gd`, but game uses C# `Player.cs` |
| 2026-02-07 ~12:40 | Fix implemented | Flashlight system ported to C# `Player.cs`, icon updated to 64×48 |

## Owner Feedback (4 Issues Reported)

### Round 1 (11:58 UTC)

### 1. Replace Armory Icon
The original implementation used a placeholder 32×32 pixel-art icon. The owner provided two reference images of tactical weapon-mounted flashlights (Nextorch WL14 and a generic tactical flashlight) and requested the icon be replaced.

### 2. Flashlight Not Working
The owner reported that the flashlight does not work at runtime and attached a game log file (`game_log_20260207_145348.txt`).

### 3. Missing Sound Effect
The owner requested adding `assets/audio/звук включения и выключения фанарика.mp3` as the toggle sound for flashlight on/off.

### Round 2 (12:30 UTC)

### 4. Flashlight Still Not Working After Fixes
The owner reported that pressing Space still does nothing. Attached `game_log_20260207_152902.txt` showing:
- `[ActiveItemManager] Active item changed from None to Flashlight` — the manager correctly sets the item
- Level reloads successfully
- `[Player] Ready!` message appears after restart
- **Zero flashlight-related log messages** from `_init_flashlight()` in `player.gd`

## Root Cause Analysis

### Critical Bug: Flashlight Code in Wrong Script File (ROUND 2)

**This is the primary root cause that made the flashlight completely non-functional.**

The project has a dual GDScript/C# architecture:
- `scripts/characters/player.gd` — GDScript player (NOT used by any level)
- `Scripts/Characters/Player.cs` — C# player (used by ALL levels)

All level scenes reference the C# player:
```
scenes/levels/BuildingLevel.tscn → scenes/characters/csharp/Player.tscn → Scripts/Characters/Player.cs
scenes/levels/CastleLevel.tscn → scenes/characters/csharp/Player.tscn → Scripts/Characters/Player.cs
scenes/levels/TestTier.tscn → scenes/characters/csharp/Player.tscn → Scripts/Characters/Player.cs
scenes/levels/csharp/TestTier.tscn → scenes/characters/csharp/Player.tscn → Scripts/Characters/Player.cs
```

The initial AI implementation added `_init_flashlight()` and `_handle_flashlight_input()` to `scripts/characters/player.gd` (the GDScript version), which is **never loaded by any scene in the game**. The C# `Player.cs` (3791 lines) had zero flashlight code.

**Evidence from game log** (`game_log_20260207_152902.txt`):
- Line 245: `[ActiveItemManager] Active item changed from None to Flashlight` — autoload correctly stores the selection
- Lines 309-315: Player init log messages (`[Player.Init]`, `[Player] Ready!`) all originate from C# `Player.cs`
- **Zero `[Player.Flashlight]` messages** — because `Player.cs` had no flashlight code at all
- The `_init_flashlight()` function in `player.gd` has log messages on every code path, so the complete absence of any flashlight log confirms the GDScript player is not the one running

**Fix**: Ported the flashlight initialization (`InitFlashlight()`) and input handling (`HandleFlashlightInput()`) to `Scripts/Characters/Player.cs`, following the same C#-to-GDScript autoload call pattern used for `GrenadeManager` (using `GetNodeOrNull`, `HasMethod`, `Call`).

### Previous Bugs Fixed (ROUND 1)

The following bugs were also fixed in round 1, but were secondary to the critical root cause above:

#### Root Cause 1: `_flashlight_equipped` Set Outside Guard (CONFIRMED)

In `player.gd`, the `_init_flashlight()` function had a bug where `_flashlight_equipped` was set to `true` **outside** the `if _player_model:` guard block:

```gdscript
# BEFORE (buggy):
if _player_model:
    _player_model.add_child(_flashlight_node)
    _flashlight_node.position = Vector2(bullet_spawn_offset, 0)

_flashlight_equipped = true  # ← Always set to true, even if node wasn't attached!
```

If `_player_model` were null for any reason, the flashlight node would be instantiated but never added to the scene tree. Its `_ready()` would never fire, so `_point_light` inside `FlashlightEffect` would remain null. The `_set_light_visible()` method silently does nothing when `_point_light` is null due to the `if _point_light:` guard.

**Fix**: Moved `_flashlight_equipped = true` inside the `if _player_model:` block and added cleanup of the orphaned node in the else branch.

#### Root Cause 2: Double Position Offset (CONFIRMED)

The PointLight2D in `FlashlightEffect.tscn` was positioned at `Vector2(80, 0)` within the scene. But `_init_flashlight()` also set the FlashlightEffect node's position to `Vector2(bullet_spawn_offset, 0)` = `Vector2(20, 0)`. This created a total offset of `(100, 0)` from the PlayerModel center — significantly farther than the actual weapon barrel.

**Fix**: Removed the `position = Vector2(80, 0)` from the PointLight2D in the scene file. The parent FlashlightEffect node is positioned at the barrel via `bullet_spawn_offset`.

#### Root Cause 3: Insufficient Light Energy (LIKELY)

The flashlight energy was set to 5.0. In a fully-lit scene (without CanvasModulate/night mode), a PointLight2D at energy 5.0 may not produce a clearly visible effect since the base scene is already at full brightness. The additive light blending only shows noticeable results with higher energy values or in darker environments.

**Fix**: Increased light energy from 5.0 to 8.0 (matching flashbang brightness level).

#### Root Cause 4: Silent Failure with No Logging (CONTRIBUTING)

The original flashlight initialization had minimal logging — most early-return paths had no log messages. This made it impossible to diagnose which step was failing from the game log.

**Fix**: Added comprehensive `FileLogger.info()` calls at every decision point in the initialization chain and in the FlashlightEffect script itself.

### Missing Features

#### Sound Effect
The flashlight toggle sound file (`звук включения и выключения фанарика.mp3`) was uploaded to `assets/audio/` on the main branch after the initial implementation. The original flashlight code did not include sound support.

**Fix**: Added `AudioStreamPlayer` to `flashlight_effect.gd` that loads and plays the sound file on both `turn_on()` and `turn_off()`.

#### Icon
The original implementation generated a placeholder 32×32 icon. The owner provided proper reference images.

**Fix**: Replaced with a 48×36 tactical flashlight image with transparent background, matching the style of other weapon icons in the armory.

## Architecture Decisions

### Pattern: Following GrenadeManager

The active item system follows the same architectural pattern as the existing `GrenadeManager`:

| Component | GrenadeManager | ActiveItemManager |
|-----------|---------------|-------------------|
| Autoload singleton | `grenade_manager.gd` | `active_item_manager.gd` |
| Enum types | `GrenadeType` | `ActiveItemType` |
| Data dictionary | `GRENADE_DATA` | `ACTIVE_ITEM_DATA` |
| Selection method | `set_grenade_type()` | `set_active_item()` |
| Signal | `grenade_type_changed` | `active_item_changed` |
| Armory UI | Grenade grid section | Active items grid section |

### PointLight2D Approach

The flashlight uses `PointLight2D` with `shadow_enabled = true` rather than a `Sprite2D` with additive blending. This choice:
- **Pros**: Light realistically doesn't pass through walls (shadow occlusion), consistent with flashbang effect pattern
- **Cons**: Less visible without CanvasModulate/night mode, higher GPU cost due to shadow calculations
- **Mitigation**: High energy (8.0) ensures visibility even in bright scenes

## Files Modified

| File | Change |
|------|--------|
| `scripts/autoload/active_item_manager.gd` | New autoload for active item management |
| `scripts/effects/flashlight_effect.gd` | Flashlight effect with PointLight2D, sound, logging |
| `scenes/effects/FlashlightEffect.tscn` | Scene with PointLight2D, shadow, gradient texture |
| `Scripts/Characters/Player.cs` | **Flashlight init + input handling (C# — the actual player script used by all levels)** |
| `scripts/characters/player.gd` | Flashlight init + input handling (GDScript — unused by levels, kept for reference) |
| `scripts/ui/armory_menu.gd` | Active items section in armory UI |
| `assets/sprites/weapons/flashlight_icon.png` | Tactical flashlight icon (48×36, transparent) |
| `project.godot` | ActiveItemManager autoload + flashlight_toggle input |
| `tests/unit/test_active_item_manager.gd` | Comprehensive unit tests |
| `tests/unit/test_armory_menu.gd` | Armory integration tests |

## Lessons Learned

1. **CRITICAL: Verify which script a scene actually uses** — In mixed GDScript/C# projects, level scenes may reference C# scripts while GDScript versions exist in parallel. Always check the `.tscn` scene files to confirm which script is loaded. The `ext_resource` path in the scene file is the definitive reference.
2. **Trace from scene → script, not from script → scene** — When adding features, start from the scene file that Godot actually loads (e.g., `BuildingLevel.tscn → csharp/Player.tscn → Player.cs`) to identify the correct script to modify.
3. **Guard all dependent state changes** — `_flashlight_equipped = true` must only be set when the node is actually attached to the scene tree.
4. **Avoid double position offsets** — When a parent node is positioned, child nodes should use relative `(0, 0)` to avoid unexpected additive offsets.
5. **Log every decision point** — Silent early returns make debugging impossible. Every guard should log why it's returning.
6. **Consider visibility context** — PointLight2D in Godot 4 is additive; in bright scenes without CanvasModulate, the effect may be subtle at low energy values.
7. **Include sound from the start** — Audio feedback is essential for player input actions; toggling equipment without sound feels broken.
8. **When game logs show missing expected output, check if the right file is running** — The complete absence of flashlight log messages (not even "not found" or "not selected") was the key clue that the GDScript player.gd was simply not the script being executed.
