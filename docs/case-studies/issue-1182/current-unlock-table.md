# Current Item Inventory & Unlock Status

Data extracted from the game source as of 2026-03-18.

---

## Weapons

| ID | Name | Unlocked by Default | Unlock Condition | Notes |
|---|---|---|---|---|
| `makarov_pm` | PM Pistol (9x18mm) | ✅ Yes | Always | Starting weapon |
| `m16` | M16 Assault Rifle | ✅ Yes | Always | Freely available |
| `shotgun` | Pump Shotgun | ❌ No | Building D+ | |
| `mini_uzi` | Mini UZI | ❌ No | Labyrinth D+ | |
| `silenced_pistol` | Silenced Pistol (Beretta M9) | ✅ Yes | Always (also: Building S, Docks D) | Freely available; extra conditions are redundant |
| `sniper` | ASVK Sniper Rifle | ❌ No | Polygon (TestTier) D+ | |
| `revolver` | RSh-12 Revolver | ❌ No | Castle F (any completion) | |
| `ak_gl` | AK-74 + GP-25 GL | ✅ Yes | Always (also: Beach D) | Freely available; extra condition is redundant |
| `smg` | SMG | ❌ No | Not yet available ("coming soon") | Placeholder in code |

**Source:** `/scripts/autoload/game_manager.gd` lines 41–51; `/scripts/autoload/unlock_manager.gd` UNLOCK_CONDITIONS

---

## Grenades

| ID | Name | Unlocked by Default | Unlock Condition | Notes |
|---|---|---|---|---|
| 0 `FLASHBANG` | Flashbang | ✅ Yes | Always | Default grenade |
| 1 `FRAG` | Frag Grenade | ❌ No | Building D+ | |
| 2 `DEFENSIVE` | F-1 Grenade | ❌ No | Beach S | |
| 3 `AGGRESSION_GAS` | Aggression Gas | ✅ Yes | Always | Freely available |

**Source:** `/scripts/autoload/grenade_manager.gd` lines 24–29

---

## Active Items

| ID | Enum Name | Name | Unlocked by Default | Unlock Condition | Type |
|---|---|---|---|---|---|
| 0 | `NONE` | None | ✅ Yes | Always | — |
| 1 | `FLASHLIGHT` | Flashlight | ❌ No | Polygon D+ | Active |
| 2 | `HOMING_BULLETS` | Homing Bullets | ❌ No | 5× S-ranks (Labyrinth+Building+Polygon+Castle+DoubleCorr) | Active |
| 3 | `TELEPORT_BRACERS` | Teleport Bracers | ❌ No | Double Corridor D+ | Active |
| 4 | `BFF_PENDANT` | BFF Pendant | ✅ Yes | **No condition — candidate for unlock gate** | Active |
| 5 | `INVISIBILITY_SUIT` | Invisibility | ❌ No | Beach S + Building S | Active |
| 6 | `BREAKER_BULLETS` | Breaker Bullets | ✅ Yes | **No condition — candidate for unlock gate** | Passive |
| 7 | `FORCE_FIELD` | Force Field | ✅ Yes | **No condition — candidate for unlock gate** | Active |
| 8 | `TRAJECTORY_GLASSES` | Trajectory Glasses | ✅ Yes | **No condition — candidate for unlock gate** | Active |
| 9 | `LASER_SIGHT` | Laser Sight | ✅ Yes | **No condition — candidate for unlock gate** | Passive |
| 10 | `EXTENDED_MAGAZINE` | Extended Magazine | ✅ Yes | **No condition — candidate for unlock gate** | Passive |
| 11 | `LOUDSPEAKER` | Loudspeaker | ✅ Yes | **No condition — candidate for unlock gate** | Active |
| 12 | `BREACHING_CHARGES` | Breaching Charges | ✅ Yes | **No condition — candidate for unlock gate** | Active |
| 13 | `ARMORED_SKIN` | Armored Skin | ✅ Yes | **No condition — candidate for unlock gate** | Passive |
| 14 | `AUTO_RELOAD` | Auto-Reload | ✅ Yes | **No condition — candidate for unlock gate** | Passive |
| 15 | `DRILLING_BULLETS` | Drilling Bullets | ✅ Yes | **No condition — candidate for unlock gate** | Active |
| 16 | `RECOIL_COMPENSATOR` | Recoil Compensator | ✅ Yes | **No condition — candidate for unlock gate** | Active |
| 17 | `COMBAT_DISPOSITION` | Combat Disposition | ✅ Yes | **No condition — candidate for unlock gate** | Passive |

**Source:** `/scripts/autoload/active_item_manager.gd` lines 42–61

---

## Levels Available (Used in Unlock Conditions)

| Scene Path | Display Name | Notes |
|---|---|---|
| `res://scenes/levels/LabyrinthLevel.tscn` | Labyrinth | Maze corridors |
| `res://scenes/levels/BuildingLevel.tscn` | Building | Walled sub-rooms |
| `res://scenes/levels/TestTier.tscn` | Polygon | Shooting test level |
| `res://scenes/levels/CastleLevel.tscn` | Castle | |
| `res://scenes/levels/RevolverLevel.tscn` | Double Corridor | Two parallel corridors |
| `res://scenes/levels/BeachLevel.tscn` | Beach | Open outdoor level |
| `res://scenes/levels/DocksLevel.tscn` | Docks | Container yard |

## Rank System

Ranks from worst to best: **F → D → C → B → A → A+ → S**

"D+" means D or higher (any passing grade). "S" means the top grade.

**Source:** `/scripts/autoload/unlock_manager.gd` line 12: `const RANK_ORDER: Array[String] = ["F", "D", "C", "B", "A", "A+", "S"]`
