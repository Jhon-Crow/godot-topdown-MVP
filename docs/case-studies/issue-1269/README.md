# Case Study: Issue #1269 — Reduce Gunshot Sound Propagation Distance

## Overview

**Issue:** [#1269](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1269) — "сделай распространение звуков выстрелов меньше в 3 раза" (make the spread of shooting sounds 3 times smaller)

**Status:** Resolved in PR [#1270](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1270)

**Date of report:** 2026-03-21

**Reporter:** Jhon-Crow (project owner)

---

## 1. Problem Description

The player reported that shooting sounds (gunshots) propagate too far in the game world, causing enemies to detect the player from unrealistically large distances. The request was first to reduce all gunshot ranges by 3x, then refined (via PR comment) to set the PM (Makarov pistol) baseline at **800px** and scale all other weapons by the same proportional coefficient.

---

## 2. Root Cause Analysis

### 2.1 Original Weapon Loudness Values

Before fix, all player weapons used a loudness value derived from the viewport diagonal (1468.6px) or larger:

| Weapon | Original Loudness (px) |
|--------|------------------------|
| PM (Makarov) | 1469.0 |
| Assault Rifle | 1469.0 (no WeaponData) |
| Mini UZI | 1469.0 |
| Shotgun | 1469.0 |
| AK+GL | 1600.0 |
| Revolver (RSh-12) | 2500.0 |
| Sniper Rifle (ASVK) | 6600.0 (already boosted 2.2x in issue #828) |
| Silenced Pistol | 0.0 (silenced, no sound) |

Enemy weapons (WeaponConfigComponent):

| Enemy Weapon | Original Loudness (px) |
|--------------|------------------------|
| RIFLE (type 0) | 1469.0 |
| SHOTGUN (type 1) | 2000.0 |
| UZI (type 2) | 1200.0 |
| MACHETE (type 3) | 200.0 |
| RPG (type 4) | 2500.0 |
| PM (type 5) | 1469.0 |
| MACHINE_GUN PKM (type 6) | 2200.0 |
| SNIPER_RIFLE ASVK (type 7) | 3000.0 |

### 2.2 Evidence from Game Log (`game_log_20260321_113147.txt`)

The game log captured a session on 2026-03-21 11:31–11:33. At timestamp **11:33:32**, the player fired a **Revolver** (range=2500px):

```
[11:33:32] [INFO] [SoundPropagation] Sound emitted: type=GUNSHOT, pos=(80.07, 2004.9), source=PLAYER (Revolver), range=2500, listeners=10
[11:33:32] [ENEMY] [Enemy1] Heard gunshot at (80.07, 2004.9), intensity=0.00, distance=1669
[11:33:32] [ENEMY] [Enemy2] Heard gunshot at (80.07, 2004.9), intensity=0.00, distance=1490
[11:33:32] [ENEMY] [Enemy3] Heard gunshot at (80.07, 2004.9), intensity=0.00, distance=1400
[11:33:32] [ENEMY] [Enemy4] Heard gunshot at (80.07, 2004.9), intensity=0.00, distance=1319
[11:33:32] [ENEMY] [Grenadier] Heard gunshot at (80.07, 2004.9), intensity=0.00, distance=2316
[11:33:32] [ENEMY] [Enemy6] Heard gunshot at (80.07, 2004.9), intensity=0.00, distance=2432
[11:33:32] [ENEMY] [Enemy7] Heard gunshot at (80.07, 2004.9), intensity=0.00, distance=1889
[11:33:32] [ENEMY] [Enemy8] Heard gunshot at (80.07, 2004.9), intensity=0.00, distance=1903
[11:33:32] [ENEMY] [Enemy9] Heard gunshot at (80.07, 2004.9), intensity=0.00, distance=2071
[11:33:32] [ENEMY] [Enemy10] Heard gunshot at (80.07, 2004.9), intensity=0.00, distance=1161
[11:33:32] [INFO] [SoundPropagation] Sound result: notified=10, out_of_range=0, self=0
```

**Key findings from the log:**
- All **10 enemies** heard the single gunshot — `out_of_range=0`
- The farthest alerted enemy (**Enemy6**) was at **2432px** away — nearly 2 full viewport widths (1280px) or 1.65 viewport diagonals
- `intensity=0.00` for all enemies means they are at distances where physical intensity is negligible, yet they are still alerted due to the large propagation radius
- After detection, **all 10 enemies immediately entered COMBAT → PURSUING** state, ending the stealth phase

This confirms the problem: a single Revolver shot could simultaneously alert every enemy on a large map.

### 2.3 Why the Values Were So High

The original values were set equal to (or larger than) the viewport diagonal (1468.6px) to ensure enemies could "always hear" the player — an early design simplification. Issue #828 even intentionally increased the sniper rifle from 3000px to 6600px (2.2x boost) to make snipers more dangerous. This left weapon loudness values wildly beyond any gameplay-reasonable detection radius.

---

## 3. Solution Timeline

### Phase 1 (Initial fix, commit `907527e4`)
- Reduced `PROPAGATION_DISTANCES[SoundType.GUNSHOT]` from 1468.6px to **489.5px** (1/3 of viewport diagonal)
- Applied uniformly to all weapons (they all fell back to the default GUNSHOT distance)

### Phase 2 (Refined fix, this PR update)
After the owner's feedback on 2026-03-21 in the PR comment:
> "сделай меньше радиус звука всего оружия (так чтоб громкость ПМ была 800px, все остальные уменьшить на такой же коэфицент)"
> ("reduce the sound radius of all weapons so that PM loudness is 800px, reduce all others by the same coefficient")

The scaling factor was determined as: **coefficient = 800 / 1469 ≈ 0.5446**

Per-weapon loudness was updated proportionally:

| Weapon | Old Loudness (px) | New Loudness (px) | Coefficient |
|--------|-------------------|-------------------|-------------|
| PM (Makarov) | 1469.0 | **800.0** | 800/1469 (baseline) |
| Assault Rifle (default) | 1469.0 | **800.0** | 800/1469 |
| Mini UZI | 1469.0 | **800.0** | 800/1469 |
| Shotgun | 1469.0 | **800.0** | 800/1469 |
| AK+GL | 1600.0 | **871.3** | 800/1469 |
| Revolver (RSh-12) | 2500.0 | **1361.5** | 800/1469 |
| Sniper Rifle (ASVK) | 6600.0 | **3594.3** | 800/1469 |
| Silenced Pistol | 0.0 | **0.0** | unchanged (silenced) |
| RIFLE enemy | 1469.0 | **800.0** | 800/1469 |
| SHOTGUN enemy | 2000.0 | **1089.2** | 800/1469 |
| UZI enemy | 1200.0 | **653.5** | 800/1469 |
| MACHETE enemy | 200.0 | **108.9** | 800/1469 |
| RPG enemy | 2500.0 | **1361.5** | 800/1469 |
| PM enemy | 1469.0 | **800.0** | 800/1469 |
| MACHINE_GUN (PKM) enemy | 2200.0 | **1198.1** | 800/1469 |
| SNIPER_RIFLE (ASVK) enemy | 3000.0 | **1633.8** | 800/1469 |

The default GUNSHOT propagation distance in `SoundPropagation` was also updated from 489.5px to **800.0px** to match the PM baseline.

---

## 4. Impact Assessment

### Gameplay impact

With PM baseline at 800px:
- A single viewport diagonal is ~1469px
- At 800px range, enemies only ~0.54 viewport diagonals away are alerted
- In the scenario from the game log (Revolver, 2500px range), only enemies within 1361.5px would now be alerted — instead of all 10 that were alerted at 2432px

Relative weapon loudness hierarchy is fully preserved:
- ASVK sniper (3594.3px) > Revolver (1361.5px) > PKM (1198.1px) > Shotgun (1089.2px) > PM/AR/UZI (800px) > MACHETE (108.9px)

### Issue #828 preservation
The ASVK "2.2x louder than base" requirement (issue #828) is preserved proportionally:
- Scaled base = 3000 × (800/1469) = 1633.8px
- Scaled ASVK = 6600 × (800/1469) = 3594.3px ≈ 1633.8 × 2.2 ✓

---

## 5. Files Changed

| File | Change |
|------|--------|
| `scripts/autoload/sound_propagation.gd` | Updated GUNSHOT default from 489.5 to 800.0 |
| `resources/weapons/MakarovPMData.tres` | Loudness: 1469.0 → 800.0 |
| `resources/weapons/MiniUziData.tres` | Loudness: 1469.0 → 800.0 |
| `resources/weapons/ShotgunData.tres` | Loudness: 1469.0 → 800.0 |
| `resources/weapons/AKGLData.tres` | Loudness: 1600.0 → 871.3 |
| `resources/weapons/RevolverData.tres` | Loudness: 2500.0 → 1361.5 |
| `resources/weapons/SniperRifleData.tres` | Loudness: 6600.0 → 3594.3 |
| `scripts/components/weapon_config_component.gd` | All enemy weapon_loudness values scaled |
| `scripts/characters/player.gd` | Default weapon_loudness: 1469.0 → 800.0 |
| `Scripts/Weapons/AssaultRifle.cs` | Fallback loudness: 1469.0 → 800.0 |
| `Scripts/Weapons/MakarovPM.cs` | Fallback loudness: 1469.0 → 800.0 |
| `Scripts/Weapons/MiniUzi.cs` | Fallback loudness: 1469.0 → 800.0 |
| `Scripts/Weapons/Shotgun.cs` | Fallback loudness: 1469.0 → 800.0 |
| `Scripts/Weapons/Revolver.cs` | Fallback loudness: 2500.0 → 1361.5 |
| `Scripts/Weapons/SniperRifle.cs` | Fallback loudness: 3000.0 → 1633.8 |
| `Scripts/Weapons/AKGL.cs` | Fallback loudness: 1600.0 → 871.3 |
| `tests/unit/test_sound_propagation.gd` | Updated GUNSHOT assertion |
| `tests/unit/test_weapon_config_component.gd` | Updated all loudness assertions |
| `tests/unit/test_sniper_rifle_loudness.gd` | Updated to 3594.3, preserved ratio test |
| `tests/unit/test_makarov_pm.gd` | Updated to 800.0 |
| `tests/unit/test_machete_component.gd` | Updated to 108.9 |
| `tests/unit/test_enemy.gd` | Mock default updated to 800.0 |

---

## 6. Attached Logs

- [`game_log_20260321_113147.txt`](./game_log_20260321_113147.txt) — Game session log from 2026-03-21, captured by the owner, showing the Revolver alerting all 10 enemies in one shot (range=2500px)
