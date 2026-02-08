# Case Study: Issue #617 — AK with GP-25 Underbarrel Grenade Launcher

## Summary

The user requested adding a new AK assault rifle with an integrated GP-25 underbarrel grenade launcher (VOG-25) to the game. The initial implementation created all the weapon files (AKGL.cs, AKGL.tscn, AKGLData.tres, vog_grenade.gd, VOGGrenade.tscn, caliber_762x39.tres, sprites) and partially integrated them into Player.cs, but **failed to register the weapon in the game's weapon selection pipeline**, making it impossible for players to select and use the weapon.

## Timeline

1. **2026-02-07 18:27**: Initial implementation committed (`a7ff0cc`) with:
   - AKGL weapon class (661 lines C#)
   - VOG grenade projectile (359 lines GDScript)
   - Weapon/caliber data resources
   - Placeholder sprites
   - Partial Player.cs integration (weapon detection, grenade launcher input, weapon switching case)

2. **2026-02-07 18:27**: CI check "Check Architecture Best Practices" failed — `scripts/objects/enemy.gd` exceeded 5000-line limit (5006 lines) due to cosmetic comment reformatting inherited from a prior branch state.

3. **2026-02-08 05:39**: User (Jhon-Crow) tested the build and reported "не добавился" (wasn't added), attaching two game log files showing:
   - Weapon set to `makarov_pm` (default) instead of `ak_gl`
   - No errors in logs — the weapon simply never appeared
   - User opened Armory menu but AK wasn't listed

## Root Cause Analysis

The AKGL weapon was **implemented but not connected** to the game's weapon selection pipeline. The codebase has a multi-layer weapon registration system requiring entries in **6 different locations**:

### Required Registration Points

| # | File | Purpose | Was Registered? |
|---|------|---------|-----------------|
| 1 | `scripts/autoload/game_manager.gd` → `WEAPON_SCENES` | Maps weapon ID to scene path | **NO** |
| 2 | `scripts/ui/armory_menu.gd` → `FIREARMS` | Shows weapon in armory menu | **NO** (had `ak47` placeholder) |
| 3 | `scripts/ui/armory_menu.gd` → `WEAPON_RESOURCE_PATHS` | Loads weapon stats for display | **NO** |
| 4 | `scripts/levels/building_level.gd` → `_setup_selected_weapon()` | Equips weapon in BuildingLevel | **NO** |
| 5 | `scripts/levels/castle_level.gd` → `_setup_selected_weapon()` | Equips weapon in CastleLevel | **NO** |
| 6 | `scripts/levels/test_tier.gd` → `_setup_selected_weapon()` | Equips weapon in TestTier | **NO** |
| 7 | `scripts/levels/tutorial_level.gd` → `_setup_selected_weapon()` | Equips weapon in Tutorial | **NO** |
| 8 | `Scripts/Characters/Player.cs` → `ApplySelectedWeaponFromGameManager()` | C# fallback weapon loading | **YES** (line 2096) |
| 9 | `Scripts/Characters/Player.cs` → `DetectAndApplyWeaponPose()` | Arm pose detection | **YES** (line 1308) |
| 10 | `Scripts/Characters/Player.cs` → `HandleAKGLGrenadeLauncherInput()` | Grenade launcher input | **YES** (line 2223) |

**Root Cause**: 7 out of 10 registration points were missing. The weapon class itself was fully functional, but the selection pipeline (GameManager → Armory Menu → Level Scripts) had no knowledge of it.

### Contributing Factor: CI Failure

The `enemy.gd` file had 5006 lines (6 over the 5000-line CI limit) due to cosmetic comment reformatting. This was unrelated to the AKGL implementation but obscured the real issue — the branch had a pre-existing CI failure that masked the weapon registration problem.

## Game Logs Analysis

### Log 1: `game_log_20260208_083855.txt`
- **Lines 138-139**: `[BuildingLevel] Setting up weapon: makarov_pm` — confirms default weapon loaded
- **Lines 214-215**: `[Player] Detected weapon: Makarov PM (Pistol pose)` — no AKGL detected
- **Lines 249-257**: User opened Armory menu (PauseMenu → ArmoryMenu) but could not find AK weapon
- **No errors** — the game ran normally, weapon was simply absent from selection

### Log 2: `game_log_20260208_083931.txt`
- Same pattern: `makarov_pm` loaded, user opened Armory menu, closed game after ~5 seconds
- No crash, no error — clean exit

## Solution

Added `ak_gl` weapon registration to all 7 missing integration points:

1. **GameManager** `WEAPON_SCENES`: `"ak_gl": "res://scenes/weapons/csharp/AKGL.tscn"`
2. **Armory Menu** `FIREARMS`: Full weapon entry replacing the `ak47` placeholder
3. **Armory Menu** `WEAPON_RESOURCE_PATHS`: `"ak_gl": "res://resources/weapons/AKGLData.tres"`
4. **BuildingLevel** `_setup_selected_weapon()`: AKGL weapon swap code block
5. **CastleLevel** `_setup_selected_weapon()`: AKGL weapon swap code block
6. **TestTier** `_setup_selected_weapon()`: AKGL weapon swap code block
7. **TutorialLevel** `_setup_selected_weapon()`: AKGL weapon swap code block

Also merged main branch to resolve the `enemy.gd` line count CI failure (5006 → 4982 lines).

## Round 2: User Feedback (2026-02-08)

After the weapon registration fix was applied and CI passed, the user (Jhon-Crow) tested again and reported three issues:

### Feedback 1: Wrong weapon model and icon
> "модель автомата и значок должны быть такие"

The initial implementation used placeholder sprites (72x20px pixel art for topdown, no icon). The user provided reference photos of the actual AK with GP-25:
- Topdown view: 1530x1260px photo of AK-103 with GP-25
- Icon: 1000x1000px side profile photo

**Fix**: Replaced `ak_gl_topdown.png` with the provided photo, added `ak_gl_icon.png`, updated AKGL.tscn with scale factor (0.052) to match in-game weapon sizes, and updated `armory_menu.gd` to reference the icon file.

### Feedback 2: VOG grenade too slow
> "ВОГ (граната) должна лететь в 2 раза быстрее"

The initial launch speed was calculated as `sqrt(2 * d * friction)` ≈ 980 px/s to travel 1.5 viewports. User wanted 2x faster flight.

**Fix**: Multiplied `launchSpeed` by 2.0 in `AKGL.cs:FireGrenadeLauncher()`. New speed ≈ 1960 px/s.

### Feedback 3: Ammo counter not working
> "счётчик патронов не работает"

**Root cause**: The AKGL weapon was registered in the selection pipeline but **missing from the weapon detection chains** that connect weapon signals to the HUD ammo display. Each level script has a chain of `get_node_or_null()` calls to find the player's weapon and connect its `AmmoChanged` signal to the ammo label. AKGL was absent from all of these chains.

**Affected locations (9 total across 5 files)**:

| File | Location | Purpose |
|------|----------|---------|
| `LevelInitFallback.cs` | `ConnectWeaponSignals()` | C# fallback weapon detection |
| `beach_level.gd` | Ammo counter init | Primary weapon signal connection |
| `beach_level.gd` | Magazine label | Magazine display detection |
| `beach_level.gd` | `weapon_names` + `_setup_selected_weapon()` | Weapon equip pipeline |
| `building_level.gd` | Ammo counter init | Primary weapon signal connection |
| `building_level.gd` | Magazine label | Magazine display detection |
| `castle_level.gd` | Ammo counter init | Primary weapon signal connection |
| `castle_level.gd` | Magazine label | Magazine display detection |
| `test_tier.gd` | Ammo counter init | Primary weapon signal connection |
| `test_tier.gd` | Magazine label | Magazine display detection |

**Fix**: Added `AKGL` to all weapon detection chains (between `AssaultRifle` and `MakarovPM`).

### Key insight: Two-layer integration gap

The initial fix (Round 1) addressed **weapon selection pipeline** registration (GameManager, ArmoryMenu, level `_setup_selected_weapon()`). Round 2 revealed a second layer: **HUD signal connection pipeline**. The weapon could be selected and equipped, but the ammo display never connected because the HUD code didn't know to look for `AKGL` nodes.

This is a pattern of **n-layer registration**: adding a new weapon requires changes in both the selection layer AND the display layer.

## Lessons Learned

1. **Multi-layer registration patterns need checklists**: When a codebase requires changes in 6+ files for a single feature, the implementation should include a verification checklist to avoid partial registration.

2. **CI failures can mask functional issues**: The `enemy.gd` line-count failure dominated attention while the real problem (weapon not appearing) was a silent integration gap with no error messages.

3. **No-error-is-not-no-bug**: The game ran perfectly with no crashes or errors. The weapon simply wasn't available. This type of silent omission is harder to detect than a crash.

4. **Placeholder entries should be documented**: The `ak47: "Coming soon"` placeholder in the armory menu was close to but different from the actual `ak_gl` weapon ID, creating ambiguity about whether the weapon was already partially registered.

5. **Registration has multiple layers**: Even after fixing weapon selection, the HUD signal connection layer was still broken. Each weapon needs to be added to both the selection pipeline AND the display pipeline — these are separate code paths with independent weapon lists.

6. **Search for ALL weapon detection patterns**: When adding a weapon, grep for all `get_node_or_null` calls that reference other weapons to find every place the new weapon needs to be added.
