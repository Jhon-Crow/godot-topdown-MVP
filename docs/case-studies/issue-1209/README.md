# Issue #1209 — Case Study: New Enemy Types for the Top-Down Game

> **Issue title (original, Russian):** придумай каких врагов можно ещё добавить
> **Issue title (translated):** Suggest what other enemies could be added
> **Repository:** Jhon-Crow/godot-topdown-MVP
> **Date of analysis:** 2026-03-20

---

## Table of Contents

1. [Current State of the Game](#1-current-state-of-the-game)
2. [Existing Enemy Types](#2-existing-enemy-types)
3. [Existing Special Modifiers](#3-existing-special-modifiers)
4. [Current AI Capabilities](#4-current-ai-capabilities)
5. [Game Mechanics Available as Building Blocks](#5-game-mechanics-available-as-building-blocks)
6. [Research: Enemy Archetypes in Top-Down Games](#6-research-enemy-archetypes-in-top-down-games)
7. [Gap Analysis: What Is Missing](#7-gap-analysis-what-is-missing)
8. [Proposed New Enemy Types](#8-proposed-new-enemy-types)
9. [Existing Tools, Plugins, and References](#9-existing-tools-plugins-and-references)
10. [Implementation Priorities](#10-implementation-priorities)
11. [Sources](#11-sources)

---

## 1. Current State of the Game

The repository is a **Godot 4.3+ top-down tactical shooter template** (`GodotTopDownTemplate`). The project supports both GDScript and C# and features:

- Physics-based player movement with cover and weapon mechanics
- A component-based architecture for enemies
- A **GOAP (Goal-Oriented Action Planning)** AI system with A* planning
- A confidence-based enemy memory system
- Multiple themed levels including a wave-survival Arena
- Multiple grenade types, caliber system, ricochet and penetration mechanics

Key source files:
- `scripts/objects/enemy.gd` — main enemy controller
- `scripts/ai/enemy_actions.gd` — GOAP actions (SeekCover, Engage, Flank, etc.)
- `scripts/ai/enemy_memory.gd` — confidence-based player memory
- `scripts/components/` — 31+ component files for modular enemy abilities
- `scripts/components/weapon_config_component.gd` — weapon/type definitions

---

## 2. Existing Enemy Types

The game defines enemy types by **weapon loadout** (via `WeaponConfigComponent`):

| ID | Type | Weapon | Key Stats |
|----|------|---------|-----------|
| 0 | **RIFLE** | M16 Assault Rifle | 30 mag, 10 rps, 2500 px/s, progressive spread |
| 1 | **SHOTGUN** | Multi-pellet shotgun | 8 mag, 0.8s cooldown, 6–10 pellets, 15° spread |
| 2 | **UZI** | Mini Uzi SMG | 32 mag, fast 0.06s cooldown, 60° max spread |
| 3 | **MACHETE** | Melee weapon | 80px range, dodge mechanics, sneak approach |
| 4 | **RPG** | Rocket launcher | Single shot + PM backup, explosion radius, 2500 loudness |
| 5 | **PM** | Makarov Pistol | 9 mag, 0.3s cooldown, 1000 px/s |
| 6 | **MACHINE_GUN** | PKM Belt-fed MG | 500 mag, 0.12s cooldown, suppression fire |
| 7 | **SNIPER_RIFLE** | ASVK Anti-materiel | 5 mag, hitscan (10000 px/s), 550px standoff |

---

## 3. Existing Special Modifiers

Enemy instances can be decorated with **boolean ability flags**, implemented as independent components:

| Flag | Component | Effect |
|------|-----------|--------|
| `is_grenadier` | `GrenadierComponent` | 3–8 grenades, strategic throw logic (8 trigger conditions) |
| `is_teleporter` | `TeleporterComponent` | Teleports up to 1 viewport diagonal, 10s cooldown |
| `has_force_field` | `ForceFieldComponent` | 4s bubble shield, 5s recharge, negates suppression |
| `start_invisible` | `InvisibilityComponent` | Cloaked until firing; reveals for 2s |
| `has_armored_skin` | `ArmoredSkinComponent` | +1 HP, spawns 20 glass shards at ≤2 HP |

---

## 4. Current AI Capabilities

### States (FSM layer)
`IDLE → PATROL → COMBAT → SEEKING_COVER → IN_COVER → FLANKING → RETREATING → ASSAULT → SEARCHING → EVADING_GRENADE → PACIFIST → SUPPRESSED → PURSUING`

### GOAP Actions
- `SeekCoverAction` (cost 2.0)
- `EngagePlayerAction` (cost 0.5–2.0 dynamic)
- `FlankPlayerAction` (cost 3.0)
- `PatrolAction` (cost 1.0)
- `StaySuppressedAction` (cost 0.5)
- `ReturnFireAction` (cost 1.5)
- `FindCoverAction` (cost 0.5)
- `RetreatAction` (cost 1.0–4.0)
- `RetreatWithFireAction` (cost 1.5)

### Detection System
- 100° FOV by default (configurable; 0/negative = 360°)
- Line-of-sight via raycasts
- 0.2s reaction delay; confidence-based memory (1.0 = seen, 0.7 = gunshot, 0.6 = reload; decays 0.1/s)

### Cover System
- 16 raycasts (300px) per enemy for cover evaluation
- Dynamic cover quality scoring with penalties for re-use
- 8 wall-avoidance raycasts for movement

---

## 5. Game Mechanics Available as Building Blocks

These mechanics already exist and can be recombined into new enemy types without building from scratch:

| Mechanic | Description | Available in |
|----------|-------------|-------------|
| Aggression gas | Turns enemies against each other | `AggressionGasGrenade` |
| Armored shards | Explodes glass on low HP | `ArmoredSkinComponent` |
| Force field | Absorbs incoming shots | `ForceFieldComponent` |
| Teleportation | Repositions instantly | `TeleporterComponent` |
| Invisibility | Cloak with reveal on attack | `InvisibilityComponent` |
| Grenadier logic | Smart grenade throws | `GrenadierComponent` |
| Ricochet bullets | Bouncing projectiles | `CaliberData` + `bullet.gd` |
| Penetrating bullets | Wall-piercing shots | `bullet.gd` |
| Homing projectiles | Tracking bullets | `bullet.gd` flag |
| Flashbang | Stun effect | `FlashbangGrenade` |
| Smoke obscuration | Vision blocker | `VogGrenade` |
| RPG explosion | AoE damage | `rpg_rocket.gd` |
| Machete dodge | Lateral evasion | `MacheteComponent` |
| Pacifist mode | Non-combatant behavior | `PacifistState` |
| Suppressive fire | Blind fire fan | `enemy.gd` suppression logic |

---

## 6. Research: Enemy Archetypes in Top-Down Games

Based on academic research (ACM, Academia.edu) and game design literature, top-down games use several well-established archetypes that the current project has not yet fully covered.

### Universal Taxonomy (from academic sources)

| Archetype | Role | Behavior |
|-----------|------|----------|
| **Grunt/Basic** | Cannon fodder | Simple patrol → chase → attack; tests basic mechanics |
| **Rusher/Charger** | Pressure | Ignores cover; sprints directly at player |
| **Swarmer** | Crowd control | Low HP; dangerous only in groups; flocking movement |
| **Sniper** | Area denial | Long range; high accuracy; punishes open movement |
| **Heavy/Tank** | Resource drain | High HP; high damage; requires sustained fire or flanking |
| **Thrower** | Displacement | Area-denial grenades or AoE attacks force player out of cover |
| **Support/Buffer** | Force multiplier | Buffs allies' stats or heals; flees when targeted |
| **Ambusher** | Surprise | Hidden until player enters trigger zone |
| **Suicide Bomber** | Urgency | Charges in and detonates; high threat to read and react |
| **Runner/Fleer** | Evasion | Retreats on low HP; may call reinforcements |
| **Shield Bearer** | Frontline tank | Blocks frontal damage; requires flanking to kill |

### Behavior Patterns from Reference Games

**Enter the Gungeon:**
- Bullet Kin: flip tables for cover (interaction with environment as cover)
- Keybullet Kin / Chance Kin: flee behavior with reward on kill — creates hunt-and-chase minigame
- Support enemies: buff allies silently from corners; targeted first by experienced players

**Hotline Miami:**
- Dog: immune to unarmed attacks, rushes the player — forces weapon management
- Thug: immune to everything except bullets — forces ammo management
- Mixed groups create mandatory loadout planning before entry

**Nuclear Throne:**
- Biome-specific enemies force adapting tactics per level
- I.D.P.D. Grunt: combines burst fire + grenade — dual-threat role

**Enter the Gungeon / Nuclear Throne shared pattern:**
- "Escort enemy": enemy that must reach a goal position triggers a negative event — creates rush situations and splits player attention

---

## 7. Gap Analysis: What Is Missing

Comparing current enemy types against established archetypes:

| Archetype | Currently present? | Notes |
|-----------|--------------------|-------|
| Basic grunt | ✅ PM / RIFLE | Covered |
| Heavy gunner | ✅ MACHINE_GUN | Covered |
| Sniper | ✅ SNIPER_RIFLE | Covered |
| Melee rusher | ✅ MACHETE | Covered but only one melee type |
| Grenadier | ✅ via modifier | Covered |
| Invisible enemy | ✅ via modifier | Covered |
| Force-field tank | ✅ via modifier | Covered |
| **Swarmer** | ❌ | No fast/low-HP rushing group enemy |
| **Shield Bearer** | ❌ | No frontal block mechanic |
| **Suicide Bomber** | ❌ | No self-destruct enemy |
| **Support/Medic** | ❌ | No enemy that heals or buffs others |
| **Ambusher** | ❌ | No enemy that waits in hiding |
| **Turret/Emplaced** | ❌ | No stationary defender |
| **Scout** | ❌ | No fast enemy that alerts others |
| **Runner/Fleer** | ❌ | No enemy that retreats and calls reinforcements |
| **Drone/Aerial** | ❌ | No flying unit (bypasses cover) |
| **Engineer** | ❌ | No enemy that places objects (mines, traps) |

---

## 8. Proposed New Enemy Types

Each proposal specifies: the archetype it fills, its core behavior, required new components (if any), and what existing mechanics it reuses.

---

### 8.1 — Swarmer (Рой / Стремительный)

**Archetype:** Swarmer / Rusher
**Gap filled:** Low-HP group pressure; crowd control situations

**Behavior:**
- Very fast movement speed (350–400 px/s; current enemies are 220 px/s)
- Low HP (1 HP)
- No ranged attack; charges directly at player once detected (no cover-seeking)
- Uses flocking/steering (Godot's `NavigationAgent2D` with separation avoidance) to rush as a pack
- If 3+ swarmers are active, they coordinate a pincer: one approaches from the front while others flank

**Weapon config:** `MELEE_KNIFE` (new minimal variant of `MACHETE` without dodge animation)
**AI changes:** Disable `SeekCoverAction` and `RetreatAction`; add `ChargeAction` (cost 0.1) that always wins over cover-seeking
**New component needed:** `SwarmCoordinationComponent` — lightweight; signals nearby swarmers to activate flank routes

**Reused mechanics:** Existing MACHETE melee range, NavigationAgent2D separation avoidance

---

### 8.2 — Shield Bearer (Щитоносец)

**Archetype:** Shield Bearer / Front-line tank
**Gap filled:** Frontal damage immunity; forces player repositioning

**Behavior:**
- Carries a ballistic shield; frontal projectile collisions (within ±45° of facing direction) are blocked
- Shield has its own HP (e.g., 6 hits); after being destroyed, enemy is exposed
- Advances slowly (100–120 px/s) toward the player while keeping facing direction locked on the player
- Has a sidearm (PM) that fires from behind the shield — can shoot back without exposing self
- When shield breaks: panics briefly (0.5s stun), then fights normally

**Weapon config:** `PM` (sidearm) + `SHIELD` (new enum value)
**New component needed:** `ShieldComponent` — manages shield HP, directional blocking, shield break event
**AI changes:** Add `AdvanceWithShieldAction` that overrides normal cover logic while shield is intact

---

### 8.3 — Suicide Bomber (Смертник)

**Archetype:** Suicide Bomber
**Gap filled:** Urgency; forces player to prioritize killing fast

**Behavior:**
- Sees player → immediately charges at maximum speed (380 px/s), no cover, no shooting
- When within 80px of player: triggers 1.5s countdown then explosion (AoE; reuses `FragGrenade` explosion logic)
- If killed before reaching player: smaller secondary explosion (half radius, reduced damage)
- On detection: shouts a verbal cue (audio) and flashes a visual indicator (red light / increasing blink rate)
- Cannot be suppressed or retreated

**Weapon config:** `BOMB` (new enum; no ranged attack)
**New component needed:** `SuicideBombComponent` — manages countdown, AoE trigger, death explosion
**Reused mechanics:** `FragGrenade` blast radius/damage logic; `ArmoredSkinComponent` death-trigger pattern

---

### 8.4 — Medic / Support (Санитар)

**Archetype:** Support / Force Multiplier
**Gap filled:** Sustain mechanic; forces player to prioritize target selection

**Behavior:**
- Carries a healing kit; idles near allies
- When an ally's HP drops below threshold (1 HP): Medic moves toward that ally (ignores player) and heals them (+1 HP per heal, 3s channel)
- Can heal up to 2 times per life; cooldown 8s per heal
- Low personal HP (1 HP); armed only with PM for self-defense
- Flees when targeted directly (triggers `RetreatingState`)
- Visual indicator above head (red cross icon)

**Weapon config:** `PM`
**New component needed:** `MedicComponent` — monitors nearby allies' HP via signal; executes heal action; manages heal cooldown
**AI changes:** Add `HealAllyAction` GOAP action (cost 1.0) with precondition: ally in range at low HP

---

### 8.5 — Ambusher (Засадник)

**Archetype:** Ambusher
**Gap filled:** Surprise; punishes careless movement through unexplored areas

**Behavior:**
- Starts in `HIDDEN` state: invisible and completely stationary (no audio, no movement)
- Activates when player enters within 150px trigger radius OR player shoots nearby
- On activation: instant burst of 3 shots, then normal combat behavior
- May be placed in crates, behind cover spots, or as fake-dead bodies
- One-time ambush surprise; fights normally after activation

**Weapon config:** `SHOTGUN` (high damage first burst) or `RIFLE`
**New component needed:** `AmbushComponent` — manages hidden state, trigger radius, activation burst
**Reused mechanics:** `InvisibilityComponent` logic for hidden rendering; `VisionComponent` disabled until trigger

---

### 8.6 — Sentry Turret (Пулемётное гнездо)

**Archetype:** Turret / Emplaced Defender
**Gap filled:** Static area denial; changes level navigation strategy

**Behavior:**
- Stationary (no movement); rotates to track detected targets
- 360° vision (no blind spot); detection range: 500px
- High rate of fire (faster than MACHINE_GUN); unlimited ammo
- Can be destroyed (HP: 4–6)
- Can be placed by level designers as fixed hazard OR by an `EngineerEnemy` (see 8.8)
- Optional variant: requires player to break line-of-sight to disable targeting

**Weapon config:** `TURRET` (new enum; infinite ammo, 0.08s cooldown, 2800 px/s)
**New component needed:** `TurretBehaviorComponent` — replaces full AI; only rotates and fires; no navigation
**AI changes:** Not applicable (no GOAP; pure reactive)

---

### 8.7 — Scout / Alert Runner (Разведчик)

**Archetype:** Scout
**Gap filled:** Alert propagation mechanic; changes stealth dynamics

**Behavior:**
- Fast (300 px/s); armed with PM (pistol; low threat)
- On spotting player: does NOT engage; immediately runs toward nearest ally group or exit
- On reaching allies: all nearby enemies gain full confidence (memory = 1.0) of player's position regardless of distance
- If cornered: fires pistol desperately (inaccurate, low damage)
- Has a 5s head-start window before allies become fully alerted

**Weapon config:** `PM`
**New component needed:** `ScoutComponent` — overrides normal GOAP; adds `AlertAlliesAction` (cost 0.1, always preferred over engage)
**Reused mechanics:** `EnemyMemory` confidence broadcasting (currently enemies share memory at ×0.9 confidence; Scout broadcasts at ×1.0)

---

### 8.8 — Engineer (Сапёр / Инженер)

**Archetype:** Engineer / Trap Setter
**Gap filled:** Environmental hazard creation; persistent threats

**Behavior:**
- Moves carefully, avoiding direct confrontation (prefers `SeekCoverAction`)
- Periodically (every 15–20s) places a land mine or a `SentryTurret` (see 8.6) at a tactically evaluated position
- Land mine: triggers on player proximity (60px); uses `FragGrenade` explosion logic
- Removes mines if player is far away (picks them up, repositions)
- Armed with PM for self-defense; low HP (1 HP)

**Weapon config:** `PM` + `MINE_PLACER` flag
**New component needed:** `EngineerComponent` — manages mine placement logic; evaluates tile positions; tracks active mines; communicates with `SentryTurret` spawning

---

### 8.9 — Berserker (Берсерк)

**Archetype:** Melee Heavy / Berserker
**Gap filled:** High-HP melee threat; forces close-quarters decision making

**Behavior:**
- High HP (5–6)
- Two phases:
  - **Phase 1 (full HP):** Approaches using cover like a normal enemy; armed with SHOTGUN
  - **Phase 2 (≤2 HP):** Discards weapon; charges at maximum speed (400 px/s); melee-only; becomes immune to suppression
- Phase transition: visual/audio cue (rage animation, scream audio)
- Melee attack: wide arc (140° swing); damage: 2; knockback: 100px
- Can kick over light cover objects on path

**Weapon config:** `SHOTGUN` in phase 1; `MELEE_FISTS` (new, wider range than MACHETE) in phase 2
**New component needed:** `BerserkerComponent` — monitors HP threshold; triggers phase transition; manages fist attack arc and knockback
**Reused mechanics:** `ArmoredSkinComponent` HP threshold trigger pattern; `MacheteComponent` melee attack pattern (extended)

---

### 8.10 — Hound / Dog (Пёс)

**Archetype:** Rusher / Tracker
**Gap filled:** Persistent pursuit; counters player hiding behind cover

**Behavior:**
- Moves at 380 px/s; can traverse narrow gaps that block larger enemies
- Does NOT use cover; will not retreat
- Melee only (bite: 1 damage, 0.3s cooldown, 60px range)
- Tracks player by sound signature even without line of sight (confidence 0.9 on any noise source)
- Once within 120px of player, enters leap attack: 0.4s windup + 200px jump + 1 damage on impact
- Cannot be suppressed; no grenade throw fear (smaller AoE profile)

**Weapon config:** `MELEE_BITE` (new; no weapon model; very fast cooldown)
**New component needed:** `HoundComponent` — manages leap attack charge and jump physics; configures vision to use sound-priority detection
**Reused mechanics:** `MacheteComponent` melee hit logic; `VisionComponent` sound-based confidence system

---

### 8.11 — Riot Police (Омоновец)

**Archetype:** Armored Heavy Grunt / Shield + Baton combo
**Gap filled:** High-value tactical enemy combining melee threat + ranged suppression

**Behavior:**
- Wears riot armor: frontal 50% damage reduction even without shield
- Standard patrol and cover-seeking behavior
- Close range (≤150px): switches from PM to baton (MELEE_BATON; 2 damage, 0.5s cooldown, stagger effect)
- Stagger effect: player movement speed reduced by 40% for 1s on hit
- Long range: fires PM accurately from behind riot shield
- Cannot be stunned by flashbang (goggle-equipped)

**Weapon config:** `PM` (ranged) + `MELEE_BATON` (close range; new)
**New component needed:** `RiotArmorComponent` — manages directional damage reduction; `BatonComponent` — stagger application

---

### 8.12 — Sniper Spotter Pair (Пара: Наводчик + Снайпер)

**Archetype:** Coordinated tactical pair
**Gap filled:** Enemy coordination; requires managing multiple priority targets simultaneously

**Behavior:**
- Two enemies that function as a unit: **Spotter** (binoculars, no weapon, fast movement) + **Sniper** (SNIPER_RIFLE, stationary)
- Spotter moves to flank position → calls out player position → Sniper fires through walls at predicted position (blind fire logic reused from `enemy.gd`)
- If Spotter is killed: Sniper falls back to normal behavior (regular vision, no called shots)
- If Sniper is killed: Spotter attempts to flee (Scout behavior)
- Visual: Spotter has signal animation when calling

**Weapon config:** Spotter: `NONE` (no weapon); Sniper: `SNIPER_RIFLE`
**New component needed:** `SpotterComponent` — manages Spotter↔Sniper link; position call-out signal; `SpotterSniperPairManager` — spawns pair together and maintains link

---

## 9. Existing Tools, Plugins, and References

### Godot Plugins / Asset Library
| Name | Description | URL |
|------|-------------|-----|
| **State Machine (Asset #2505)** | Pre-built FSM plugin for Godot 4 | https://godotengine.org/asset-library/asset/2505 |
| **godot-finite-state-machine** | FSM addon from godot-addons | https://github.com/godot-addons/godot-finite-state-machine |
| **2D Top-Down Shooter Engine (Godot 4)** | Patrol/chase/melee/ranged enemies with strafing | https://andre-micheletti.itch.io/2d-top-down-shooter-engine-for-godot |
| **Top Down Shooter Template (RNB Games)** | Component-based architecture, Godot 4.2.1 | https://rnb-games.itch.io/top-down-shooter-template |
| **topdown-2d-multiplayer** | A* pathfinding + flocking/steering | https://github.com/danilko/topdown-2d-multiplayer |

### Design References
| Resource | Description | URL |
|----------|-------------|-----|
| **The Level Design Book — Enemy Design** | Academic treatment of enemy archetypes, metrics, and telegraphing | https://book.leveldesignbook.com/process/combat/enemy |
| **GDKeys — Rational Enemy Design** | Predictability, counter-play, visual telegraphing | https://gdkeys.com/keys-to-rational-enemy-design/ |
| **GDQuest — Patrol, Alert, Attack** | Godot 4 FSM tutorial course | https://school.gdquest.com/courses/learn_3d_gamedev_godot_4/patrol_alert_attack/module_overview |
| **GDQuest — FSM Tutorial** | Node-based FSM in Godot 4 | https://www.gdquest.com/tutorial/godot/design-patterns/finite-state-machine/ |
| **Enter the Gungeon Wiki** | Cult of the Gundead enemy roster | https://enterthegungeon.fandom.com/wiki/Cult_of_the_Gundead |
| **Hotline Miami Wiki** | Enemy Behaviour page | https://hotlinemiami.fandom.com/wiki/Enemy_Behaviour |
| **Nuclear Throne Wiki** | Enemy types per biome | https://nuclear-throne.fandom.com/wiki/Enemies |
| **ACM — Enemy NPC Design Patterns** | Academic research on NPC design patterns in shooters | https://dl.acm.org/doi/10.1145/2427116.2427122 |
| **Designing Enemies With Distinct Functions** | Game Developer / Gamasutra article | https://www.gamedeveloper.com/design/designing-enemies-with-distinct-functions |
| **Top-Down Shooter Level Design** | MY.GAMES / Medium — how enemy types relate to map geometry | https://medium.com/my-games-company/top-down-shooter-level-design-how-map-design-supports-game-mechanics-6ae39fdd095d |

---

## 10. Implementation Priorities

Ordered by implementation effort (ascending) and impact (descending):

| Priority | Enemy | Effort | Impact | Reason |
|----------|-------|--------|--------|--------|
| 1 | **Hound/Dog** | Low | High | Reuses MacheteComponent + VisionComponent sound logic; adds exciting pursuit mechanic |
| 2 | **Swarmer** | Low | High | Mostly a configuration of existing MACHETE type + disable cover actions |
| 3 | **Ambusher** | Low | Medium | InvisibilityComponent + new trigger radius; clean layering |
| 4 | **Scout** | Medium | High | New ScoutComponent + EnemyMemory broadcast; changes stealth gameplay |
| 5 | **Suicide Bomber** | Medium | High | New SuicideBombComponent; reuses FragGrenade blast; clear player feedback |
| 6 | **Medic** | Medium | High | New MedicComponent + HealAllyAction; changes priority targeting |
| 7 | **Berserker** | Medium | Medium | New BerserkerComponent; extends MacheteComponent |
| 8 | **Sentry Turret** | Medium | Medium | New TurretBehaviorComponent; no navigation needed |
| 9 | **Shield Bearer** | High | High | New ShieldComponent with directional collision; significant physics work |
| 10 | **Riot Police** | High | Medium | New directional damage reduction + stagger; builds on Shield Bearer work |
| 11 | **Engineer** | High | Medium | New EngineerComponent + mine spawning + turret placement |
| 12 | **Sniper-Spotter Pair** | High | Medium | Multi-entity coordination system; good for end-game encounters |

---

## 11. Sources

1. ACM Digital Library — Enemy NPC Design Patterns in Shooter Games: https://dl.acm.org/doi/10.1145/2427116.2427122
2. Academia.edu — Enemy NPC Design Patterns in Shooter Games: https://www.academia.edu/2806378/Enemy_NPC_Design_Patterns_in_Shooter_Games
3. The Level Design Book — Enemy Design: https://book.leveldesignbook.com/process/combat/enemy
4. GDKeys — Keys to Rational Enemy Design: https://gdkeys.com/keys-to-rational-enemy-design/
5. Game Developer — Designing Enemies With Distinct Functions: https://www.gamedeveloper.com/design/designing-enemies-with-distinct-functions
6. Medium — On AI systems in top down games: https://willduiker.medium.com/on-ai-systems-in-top-down-games-6d64812daf20
7. GDQuest — Finite State Machine Tutorial (Godot 4): https://www.gdquest.com/tutorial/godot/design-patterns/finite-state-machine/
8. GDQuest — Patrol Alert Attack Course: https://school.gdquest.com/courses/learn_3d_gamedev_godot_4/patrol_alert_attack/module_overview
9. Generalist Programmer — Godot State Machine Complete Tutorial (2025): https://generalistprogrammer.com/tutorials/godot-state-machine-complete-tutorial-game-ai
10. Godot Asset Library — State Machine #2505: https://godotengine.org/asset-library/asset/2505
11. GitHub — godot-finite-state-machine: https://github.com/godot-addons/godot-finite-state-machine
12. itch.io — 2D Top-Down Shooter Engine for Godot 4 (Andre Micheletti): https://andre-micheletti.itch.io/2d-top-down-shooter-engine-for-godot
13. itch.io — Top Down Shooter Template (RNB Games): https://rnb-games.itch.io/top-down-shooter-template
14. GitHub — topdown-2d-multiplayer: https://github.com/danilko/topdown-2d-multiplayer
15. Enter the Gungeon Wiki — Cult of the Gundead: https://enterthegungeon.fandom.com/wiki/Cult_of_the_Gundead
16. Hotline Miami Wiki — Enemy Behaviour: https://hotlinemiami.fandom.com/wiki/Enemy_Behaviour
17. Nuclear Throne Wiki — Enemies: https://nuclear-throne.fandom.com/wiki/Enemies
18. cxong.github.io — A Review of Overhead 8-Directional Shooters: https://cxong.github.io/2016/04/a-review-of-overhead-8-directional-shooters
19. MY.GAMES / Medium — Top-down shooter level design: https://medium.com/my-games-company/top-down-shooter-level-design-how-map-design-supports-game-mechanics-6ae39fdd095d
20. TopDown Engine Documentation — Advanced AI: https://topdown-engine-docs.moremountains.com/advanced-ai.html
