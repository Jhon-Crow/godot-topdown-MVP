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

## Round 3: User Feedback (2026-02-08, 22:37 UTC)

After Round 2 fixes (sprite replacement, VOG speed doubling, ammo counter fix), the user tested again and reported two remaining issues:

### Feedback 1: Weapon shows as a photo, not a sprite model
> "сейчас вместо модельки просто картинка, исправь"

**Root cause**: In Round 2, the topdown sprite was replaced with the user's reference photo (1530x1260 pixels) and scaled down to 5.2% in the scene (`scale = Vector2(0.052, 0.052)`). While this made the weapon appear at the correct size, it looked like a scaled-down photograph rather than a pixel art sprite matching other weapons. All other weapons use small pixel art sprites (30-80px wide, 8-20px tall) at native scale.

**Comparison of topdown sprites**:

| Weapon | File | Dimensions | Scale | Type |
|--------|------|-----------|-------|------|
| M16 | m16_rifle_topdown.png | 64x16 | 1.0 | Pixel art |
| ASVK | asvk_topdown.png | 80x16 | 1.0 | Pixel art |
| Shotgun | shotgun_topdown.png | 64x16 | 1.0 | Pixel art |
| AK+GL (Round 2) | ak_gl_topdown.png | 1530x1260 | 0.052 | **Photo** |
| AK+GL (Round 3 fix) | ak_gl_topdown.png | 72x20 | 1.0 | Pixel art |

**Fix**: Created a proper 72x20 pixel art topdown sprite with dark silhouette style matching other weapons, showing the GP-25 grenade launcher tube below the barrel. Removed scale factor from AKGL.tscn, changed offset from (384,0) to (24,0). Also replaced the 1000x1000 photo icon with an 80x24 pixel art side-view icon.

### Feedback 2: Use AK and grenade launcher sounds from assets/audio
> "используй звуки калашникова и подствольника из assets/audio"

**Root cause**: The AudioManager had no `play_ak_shot()` or `play_grenade_launch()` methods. The AKGL.cs code was already written to call these methods with a fallback chain:
- `play_ak_shot()` → fallback to `play_m16_shot()` (M16 sounds used instead)
- `play_grenade_launch()` → fallback to `play_m16_shot()` (M16 sounds used instead)

The audio files existed in `assets/audio/`:
- `выстрел из АК 1.mp3` through `выстрел из АК 5.mp3` (5 AK shot variants)
- `выстрел из подствольного гранатомёта.mp3` (GP-25 grenade launcher shot)

These were added as part of upstream commit `5753dbec` ("звуки выстрелов АК и подствольного гранатомёта") but the AudioManager methods to play them were never created.

**Fix**: Added to `audio_manager.gd`:
1. `AK_SHOTS` constant array with 5 AK shot sound paths
2. `GRENADE_LAUNCHER_SHOT` constant with GP-25 shot sound path
3. `play_ak_shot(position)` method using random selection from 5 variants
4. `play_grenade_launch(position)` method for single grenade launcher sound
5. Preload entries for all 6 new sounds

### Game logs analysis (Round 3)

**Log 1** (`game_log_20260209_013545.txt`):
- Line 270: `[GameManager] Weapon selected: ak_gl` — weapon selection working
- Line 340-342: `[Player.Weapon] GameManager weapon selection: ak_gl (AKGL)` → `Removed default MakarovPM` → `Equipped AKGL (ammo: 30/30)` — weapon equip working
- Line 441: `[Player] Detected weapon: AK + GL (Rifle pose)` — weapon detection working
- Line 469: Sound propagation: `source=PLAYER (AKGL)` — firing working
- No audio-related errors (fallback to M16 sounds was silent)

**Log 2** (`game_log_20260209_013626.txt`):
- Same pattern, plus line 443: `[Player] AKGL grenade launcher fired!` — grenade launcher working
- VOG grenade launching confirmed (lines 430-438)

### Key insight: Three-layer asset gap

Round 1 fixed the **selection pipeline** (weapon invisible in menus).
Round 2 fixed the **display pipeline** (ammo counter not connected).
Round 3 fixed the **asset pipeline** (wrong visual style, missing audio methods).

A new weapon requires consistency across all three layers:
1. **Selection**: GameManager, ArmoryMenu, level scripts
2. **Display**: HUD signal connections, weapon detection chains
3. **Assets**: Sprites matching art style, audio methods for weapon sounds

## Updated Lessons Learned

7. **Art style consistency matters**: Even if the sprite is technically functional (correct size, correct position), using a photographic image in a pixel art game breaks visual consistency. Always match the existing art style.

8. **Audio fallback chains hide missing implementations**: The AKGL code gracefully fell back to M16 sounds when AK-specific methods were missing. This is good defensive coding but it masks the fact that proper sounds were never wired up. Audio files being in the repository doesn't mean they're connected to the code.

9. **"Works" vs "works correctly" gap**: The weapon worked (fired bullets, launched grenades, appeared in menus) but didn't work correctly (wrong visuals, wrong sounds). Functional correctness is necessary but not sufficient — aesthetic correctness also matters for user acceptance.
