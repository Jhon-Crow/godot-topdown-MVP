# Case Study: Issue #554 — Polygon Map Functions Broke (3rd Recurrence)

## Issue Summary

Issue #554 reports: "от карты Полигон отвалились функции" (functions broke from the Polygon map).
Specifically: "сломались счётчики и выбор оружия" (counters and weapon selection broke).
User notes: "такое уже было, проверь логи" (this has happened before, check the logs).

## Timeline of Events

| Timestamp | Event |
|-----------|-------|
| 2026-02-07 ~05:50 | First game session logged (game_log_20260207_055032.txt) |
| 2026-02-07 ~06:30 | Second game session (game_log_20260207_063024.txt) |
| 2026-02-07 ~06:56 | Third game session (game_log_20260207_065636.txt) |
| 2026-02-07 ~07:01 | Fourth game session (game_log_20260207_070133.txt) |
| 2026-02-07 ~07:18 | Fifth game session (game_log_20260207_071859.txt, longest) |
| 2026-02-07 | Issue #554 filed |
| 2026-02-07 | Issue #555 filed with 5 game logs and specific bug descriptions |

## Historical Pattern (3rd Recurrence)

This is the **third occurrence** of the same class of bug:

| # | Issue/PR | Date | Trigger | Symptoms |
|---|---------|------|---------|----------|
| 1 | PR #127 (rejected) | 2026-01-21 | Adding scoring system | Enemy counter, ammo counter, game end broken |
| 2 | Issue #511 / PR #514 | 2026-02-06 | Adding score tracking to Polygon | Enemy counter, ammo counter, weapon selection, score screen broken |
| 3 | **Issue #554 (current)** | **2026-02-07** | **Scene routing confusion** | **Counters and weapon selection broken on TestTier** |

## Root Cause Analysis

### Primary Root Cause: Scene Routing Confusion

Two different scenes share the name "TestTier" in the scene tree:

| Scene | Node Name | Script | Purpose |
|-------|-----------|--------|---------|
| `res://scenes/levels/TestTier.tscn` | TestTier | `test_tier.gd` | Combat arena (Полигон) with 10 enemies, counters, score |
| `res://scenes/levels/csharp/TestTier.tscn` | TestTier | `tutorial_level.gd` | Tutorial with targets only, no enemies |

**Evidence from all 5 game logs:**

1. Every time TestTier loads, Player.cs logs: `Tutorial level detected - infinite grenades enabled`
   - This means `scenePath.Contains("csharp/TestTier")` is TRUE → tutorial scene loaded
   - The proper Polygon scene would log: `Normal level - starting with 1 grenade`

2. The proper Polygon scene prints "Полигон loaded - Tactical Combat Arena" via `test_tier.gd._ready()` — this message NEVER appears in any log file.

3. `building_level.gd` logs `Enemy tracking complete: 10 enemies registered` — no equivalent appears for TestTier because `tutorial_level.gd` has no enemy tracking code.

4. CinemaEffects reports `Scene changed to: TestTier` for BOTH scenes (identical root node name), making it impossible to distinguish them in logs.

### Contributing Factor: Sniper Rifle Pose Detection

The `Player.cs` weapon pose detection system (`DetectAndApplyWeaponPose()`) did not have a case for the SniperRifle. It checked for: MiniUzi, Shotgun, SilencedPistol, then defaulted to Rifle. The ASVK sniper rifle fell through to the default "Rifle" pose.

**Evidence:** Log entries show `Detected weapon: Rifle (default pose)` immediately after `Weapon selected: sniper`, while the ReplayManager correctly identifies the texture as `asvk_topdown.png`.

### Contributing Factor: Insufficient Logging in test_tier.gd

Unlike `building_level.gd` which uses `_log_to_file()` extensively for enemy tracking and setup, `test_tier.gd` only used `print()` statements (stdout, not captured in game logs) and `_log_to_file()` only for ReplayManager. This made it impossible to verify from logs whether `test_tier.gd` ran at all.

## Game Log Evidence

### Log File Summary

| File | Size | Duration | Scenes Visited |
|------|------|----------|----------------|
| game_log_20260207_055032.txt | 200 KB | 1 min | BuildingLevel, TestTier(tutorial) |
| game_log_20260207_063024.txt | 152 KB | 27 sec | BuildingLevel only |
| game_log_20260207_065636.txt | 454 KB | 2 min | BuildingLevel, TestTier(tutorial) |
| game_log_20260207_070133.txt | 857 KB | 17 min | BuildingLevel, TestTier(tutorial), CastleLevel |
| game_log_20260207_071859.txt | 1.1 MB | 13 min | BuildingLevel, TestTier(tutorial) |

### Key Log Entries

**Proof of tutorial scene loading (game_log_20260207_071859.txt):**
```
Line 238: [07:19:02] [INFO] [Player.Grenade] Tutorial level detected - infinite grenades enabled
Line 285: [07:19:05] [INFO] [Player.Grenade] Tutorial level detected - infinite grenades enabled
...repeated 20+ times...
```

**Proof that Polygon (test_tier.gd) never loads:**
- "Полигон loaded" — NEVER appears in any log
- "[TestTier] Enemy tracking complete" — NEVER appears
- "[ScoreManager] Level started" after TestTier transition — NEVER appears

**BuildingLevel works correctly for comparison:**
```
Line 124: [07:18:59] [INFO] [BuildingLevel] Found Environment/Enemies node with 10 children
Line 135: [07:18:59] [INFO] [BuildingLevel] Enemy tracking complete: 10 enemies registered
Line 136: [07:18:59] [INFO] [ScoreManager] Level started with 10 enemies
```

### Additional Bugs Found in Logs

1. **Sniper rifle gets default rifle pose** — Player.cs shows `Detected weapon: Rifle (default pose)` for ASVK
2. **SoundPropagation stale listeners** — Up to 36 invalid listeners cleaned on scene change
3. **Bullet WARNING** — "Unable to determine shooter position" (~60+ occurrences across all logs)
4. **ReplayManager stale data** — Records `player_valid=False` frames with stale BuildingLevel enemy count

## Fixes Applied

### Fix 1: Rename Tutorial Scene Root Node
- Changed root node name in `csharp/TestTier.tscn` from `TestTier` to `Tutorial`
- CinemaEffects will now log `Scene changed to: Tutorial` instead of `Scene changed to: TestTier`
- This allows clear distinction between Polygon and Tutorial scenes in game logs

### Fix 2: Add FileLogger Logging to test_tier.gd
- Added `_log_to_file()` calls to match `building_level.gd` pattern:
  - Level load: `"Полигон loaded - Tactical Combat Arena"`
  - Enemy tracking: `"Found Environment/Enemies node with N children"`, child enumeration, `"Enemy tracking complete: N enemies registered"`
  - Player setup: `"Player found: PlayerName"`
  - ScoreManager: `"ScoreManager initialized with N enemies"`
- These entries will appear in game log files for future debugging

### Fix 3: Add Sniper Rifle Pose Detection
- Added `WeaponType.Sniper` to the enum in Player.cs
- Added SniperRifle detection in `DetectAndApplyWeaponPose()` (checked before other weapons)
- Added Sniper arm pose in `ApplyWeaponArmOffsets()`:
  - Left arm extended forward (+4, 0) to support heavy barrel
  - Right arm slightly back (-1, 0) for stable trigger control

## Lessons Learned

1. **Same root node names across different scenes causes diagnostic confusion.** All scenes should have unique root node names matching their purpose.

2. **Critical game logic functions need FileLogger output, not just print().** The `print()` function outputs to stdout/console only, which is not captured in the game log files. Using `_log_to_file()` ensures diagnostic data is available in exported builds.

3. **Weapon pose detection must be updated when new weapons are added.** The sniper rifle was added but its pose detection case was missed.

4. **This is a recurring pattern.** The same class of bug has appeared 3 times. Future changes to level scripts should be tested with a checklist that includes:
   - Enemy counter works (decrements on kills)
   - Ammo counter works (updates on fire/reload)
   - Weapon selection works (all 5 weapons equip correctly)
   - Score screen appears after clearing all enemies
   - Level name is distinguishable in logs
