# Case Study: Issue #1213 — New Weapons, Items, and Grenades

## Issue Summary

**Title**: придумай какое оружие предметы или гранаты можно добавить
*(Translation: "Think of what weapons, items, or grenades can be added")*
**Author**: Jhon-Crow
**Repository**: Jhon-Crow/godot-topdown-MVP
**Type**: Feature Proposal / Design Research

### Request

The issue asks for a creative and analytical proposal of new weapons, items, and grenades that could be added to the game, based on:
1. What already exists in the codebase
2. Best practices and patterns from comparable top-down tactical/action games
3. Technical feasibility given the existing Godot architecture

---

## Repository Context: What Already Exists

### Weapons (Player-Usable)

| ID | Name | Caliber | Fire Mode | Key Trait |
|---|---|---|---|---|
| `makarov_pm` | Makarov PM | 9x18 | Semi-auto | Starter pistol, always unlocked |
| `m16` | Assault Rifle (M16/AK-74) | 5.45x39 | Full-auto | Standard rifle, ricochet bullets |
| `shotgun` | Pump-action Shotgun | 12 gauge buckshot | Pump | 9 pellets/shot, 8-shell mag |
| `mini_uzi` | Mini Uzi | 9x19 | Full-auto | Fast fire rate, high spread at range |
| `silenced_pistol` | Silenced Pistol | 9x19 | Semi-auto | Suppressed, stealth-friendly |
| `sniper` | ASVK Sniper Rifle | 12.7x108 | Bolt-action | 50 damage, extreme range |
| `revolver` | Revolver | — | Single-action | Revolving cylinder |
| `ak_gl` | AK + GP-25 Grenade Launcher | 5.45x39 + VOG | Auto + Launch | Dual-mode: rifle + underbarrel launcher |

**Enemy-only weapons** (not player-accessible): PKM machine gun (belt-fed), RPG

### Grenades (Player-Selectable)

| Type | Class | Trigger | Radius | Effect |
|---|---|---|---|---|
| Flashbang | `FlashbangGrenade` | 4s timer | 400px | Blind 12s + Stun 6s |
| Frag (Offensive) | `FragGrenade` | Impact | 225px | 99 damage + 4 shrapnel |
| Defensive (F-1) | `DefensiveGrenade` | 4s timer | 700px | 99 damage + 40 shrapnel |
| Aggression Gas | `AggressionGasGrenade` | 4s timer | 300px | Enemies fight each other (10–20s cloud) |
| VOG-25 | `VOGGrenade` | Impact (launched) | 337px | 99 damage + 8 shrapnel (AK-GL only) |

All grenades extend `GrenadeBase` (physics-based throwing, timer support, sound propagation, blink effects).

### Active Items (Space-Key Equipment)

| Item | Type | Mechanic |
|---|---|---|
| Flashlight | Active | Illuminates in weapon direction |
| Homing Bullets | Active (2 charges) | Bullets steer up to 110° toward nearest enemy |
| Teleport Bracers | Active (6 charges) | Aim-then-teleport through walls |
| BFF Pendant | Active (1 charge) | Summons friendly M16-armed companion |
| Invisibility Suit | Active (2 charges) | Player invisible for 4 seconds |
| Force Field | Active (hold) | 100% projectile/grenade reflection, 8s charge |
| Trajectory Glasses | Active (2 charges) | Show ricochet trajectories for 10s + 30% ricochet boost |
| Loudspeaker | Active (2 charges) | Sound cone pacifies enemies |
| Breaching Charges | Active (2 charges) | Destroy wall sections, stun/blind enemies behind |
| Drilling Bullets | Active (1 charge/mag) | Current magazine pierces walls |
| Experimental Sample | Active (1–5 charges) | Random active item effect each use |

| Item | Type | Mechanic |
|---|---|---|
| Breaker Bullets | Passive | Bullets explode 60px before walls, spawn shrapnel cone |
| Laser Sight | Passive | Always-on purple laser sight regardless of difficulty |
| Extended Magazine | Passive | 2.5× magazine, −5% total ammo |
| Armored Skin | Passive | +1 HP; at ≤2 HP when hit: 20 glass shards outward |
| Auto-Reload | Passive | 2.1× smaller mag, refills from reserve on each kill |
| Recoil Compensator | Active (hold/15s) | Eliminates spread + 10% fire rate boost |
| Combat Disposition | Passive | +0.77 dmg, +1.1 fire rate; losing HP reduces both |

### Components / AI Enemy Abilities

Special behaviors implemented as components:
- `MacheteComponent` — Melee enemy approach, backstab preference, attack phases
- `EnemyGrenadierComponent` / `GrenadierGrenadeComponent` — AI grenade throwing
- `EnemySniperComponent` — AI sniper behavior
- `EnemyForceFieldComponent` — AI shield carrier
- `EnemyInvisibilityComponent` — AI invisible enemy
- `EnemyTeleportComponent` — AI teleporting enemy
- `EnemyArmoredSkinComponent` — AI shard-burst on low HP
- `BFFTargetingComponent` — Friendly companion targeting logic
- `AggessionComponent` — AI-vs-AI combat state
- `SuppressiveFireComponent` — AI suppressive fire

---

## External Research: Top-Down Game Design Patterns

### Sources Analyzed
- **Hotline Miami 1 & 2** — fast, lethal, masked-ability system
- **Enter the Gungeon** — vast weapon variety, item synergies, passive builds
- **Nuclear Throne** — mutation/perk build system, weapon archetypes
- **Alien Swarm: Reactive Drop** — team utility tools, deployable items
- **Helldivers / Helldivers 2** — stratagem-based throwables, cooperative tools
- **Helldivers (original 2015)** — top-down twin-stick, orbital support items

### Key Observations

**What makes items tactically interesting in top-down games:**

1. **Area Denial** — Top-down perspective makes fire zones, gas clouds, and mines fully readable. Players can spatially plan around them.
2. **AI Manipulation** — Decoys and aggro-redirectors work well because top-down AI pathfinding is visible; players can predict enemy movement.
3. **Dual-Mode Weapons** — Two firing modes per weapon slot are easier to manage without the 3D attention split.
4. **Information Utility** — Items that change *what the player knows* (nightvision, map reveal, trajectory preview) are uniquely powerful in top-down.
5. **Reactive/Passive Armor** — Counterattack-on-hit mechanics reward risk-taking rather than passive avoidance.
6. **Terrain Interaction** — Grenades/items that create persistent environment changes (fire patches, acid pools, laser tripwires) make the level geometry part of combat.
7. **Combo/Synergy Systems** — Build-defining passives that scale with specific weapon types create meaningful loadout decisions.

---

## Gap Analysis: What's Missing

Cross-referencing the existing feature set against top-down genre norms, these categories lack coverage:

### Grenades
- No **smoke/vision-blocking** grenade (existing flashbang blinds but doesn't create a concealment zone)
- No **incendiary/napalm** grenade (persistent fire zone)
- No **concussion/knockback** grenade (displacement without lethal damage)
- No **EMP** grenade (vs. electronic/mechanical enemies)
- No **proximity-triggered** grenade (arms then detonates near enemies)
- No **gravity/pull** grenade (groups enemies for follow-up)
- No **stun-only** throwable (like Alien Swarm's freeze grenade, non-lethal incapacitation)

### Weapons
- No **SMG** (in planning, "coming soon" in game_manager.gd)
- No **player-accessible machine gun** (PKM exists for enemies only)
- No **player-accessible RPG** (RPG exists for enemies only)
- No **melee weapon for player** (machete exists as enemy-only component)
- No **crossbow / silent-ranged** weapon (silent pistol exists but no bolt-type projectile)
- No **dual-wield** weapons
- No **flamethrower** (fire-based weapon)
- No **explosive shotgun** (area damage on pellet impact)

### Active Items
- No **deployable trap/mine** (Alien Swarm has laser trip mines, proximity incendiary)
- No **decoy/distraction** item (Alien Swarm's Swarm Bait)
- No **speed boost** item (pure mobility)
- No **healing item** (no HP recovery mechanism beyond Armored Skin's +1 HP)
- No **damage amplifier zone** (Alien Swarm's X-33: double damage beacon)
- No **time-slow** item (Alien Swarm's Adrenaline / Enter the Gungeon's Potion of Lead Skin)
- No **ammo replenishment** active item
- No **enemy scanner** (reveals enemy positions through walls)
- No **deployable turret** (Alien Swarm's Tesla Sentry Coil)
- No **berserker/rage mode** (temporary massive damage increase with drawback)

### Passive Items
- No **on-kill healing** (Enter the Gungeon: Big Bloodthirst)
- No **streak damage multiplier** (Enter the Gungeon: Metronome)
- No **armor-piercing bullets** (penetrate armored skin / force fields)
- No **explosive bullets** (small blast on hit)
- No **ricochet multiplier** (more/faster ricochets)
- No **fire bullets** (DoT burn on hit)
- No **money/score-to-damage** (Enter the Gungeon: Gilded Bullets — score → damage)

---

## Proposed Additions

### Priority 1 — Grenades (Fits Existing GrenadeBase System)

These are the most technically feasible additions — `GrenadeBase` provides everything needed.

---

#### 1.1 Smoke Grenade (`SmokeGrenade`)

**Concept**: Creates a 30-second fog cloud that blocks enemy line-of-sight but not player sight.
**Mechanic**:
- Timer-based (4s fuse), releases a persistent circular smoke cloud
- Enemies cannot detect the player inside or through the cloud (`realistic_visibility_component.gd` queries)
- Player can see through own smoke (partial opacity reduction only)
- Cloud dissipates over 30 seconds with fade-out animation

**Justification**: The current "flashbang" blinds enemies but cannot create a concealment zone. Smoke is the canonical missing grenade type; it enables entirely different tactics (repositioning, reviving, objective movement under cover).

**Technical Fit**: Follows the same pattern as `AggressionGasGrenade` — timer-based, spawns a persistent child scene (smoke cloud), cloud applies status effect to enemies inside it. No new architecture needed.

**Reference**: Standard in virtually all tactical games (CS:GO, Rainbow Six, Helldivers 2).

---

#### 1.2 Incendiary Grenade (`IncendiaryGrenade`)

**Concept**: Creates a persistent napalm fire zone on impact. Deals damage-over-time to enemies walking through the zone for 15 seconds.
**Mechanic**:
- Impact-triggered (like FragGrenade)
- Spawns a 200px fire patch on landing
- Any enemy inside takes 1 damage per second
- Fire patch gradually shrinks over 15 seconds
- Can stack with other fire patches if multiple are thrown

**Justification**: Fills the area-denial niche. Unlike the F-1 defensive grenade (instant radius damage), incendiary creates a *persistent hazard* that denies movement through corridors. Tactically distinct from all existing grenades.

**Technical Fit**: Very similar to `AggressionGasGrenade`'s cloud spawning pattern. The fire patch can be implemented as an `Area2D` that queries enemies per-second, identical to how `aggression_cloud.gd` works.

**Reference**: Standard in Helldivers 2 (Incendiary Grenade), Alien Swarm (M478 Proximity Incendiary Mine), Enter the Gungeon (Molotov).

---

#### 1.3 Concussion Grenade (`ConcussionGrenade`)

**Concept**: Explodes with force but zero damage. All enemies in radius are knocked backward by 400–600px.
**Mechanic**:
- Timer-based (4s fuse), medium radius (350px)
- Enemies hit receive `apply_central_impulse()` away from explosion center (since enemies use `RigidBody2D`)
- Zero damage — purely displacement
- Player cannot be knocked (or receives reduced knockback)

**Justification**: The game already has stunning (flashbang), killing (frag/defensive), blinding (flashbang), AI-flipping (gas). Concussion adds a pure *displacement* option — sending enemies into walls, off patrol routes, or into each other's firing lines. Non-lethal but tactically creative.

**Technical Fit**: Grenade explosion already calls `_get_enemies_in_radius()`. Adding `enemy.apply_central_impulse(direction * force)` requires checking if enemies use `RigidBody2D` (they do via `enemy.gd`). Minimal code addition.

**Reference**: Concussion Grenade (Helldivers), Shockwave Grenade (various games), Blank (Enter the Gungeon — destroys all projectiles with force).

---

#### 1.4 Freeze Grenade (`FreezeGrenade`)

**Concept**: Cryogenic burst that freezes all enemies in radius in place for 5 seconds. Zero damage.
**Mechanic**:
- Timer-based (4s fuse), medium radius (300px)
- Enemies hit receive a `frozen` status effect — movement speed → 0, cannot shoot
- Frozen enemies visually tinted blue/white
- After 5 seconds, enemies unfreeze and resume normal behavior
- Works identically to Alien Swarm's CR-18 Freeze Grenade

**Justification**: The flashbang already stuns, but only for 6 seconds and only if in the blast zone. The freeze grenade would be *reliable* (no wall-blocking consideration like flashbang) and would freeze without blinding, enabling different follow-up tactics (walk through frozen crowd, aim carefully while they're stopped).

**Technical Fit**: `flashbang_status_component.gd` already implements a stun mechanism (`_apply_stun()`). A freeze status could reuse this infrastructure with a different visual modulate.

**Reference**: CR-18 Freeze Grenade (Alien Swarm: Reactive Drop), Cryo Grenade (various games).

---

#### 1.5 Proximity Mine (`ProximityMine`)

**Concept**: A thrown device that arms after 2 seconds, then detonates when an enemy comes within 80px of it. Same explosion stats as FragGrenade.
**Mechanic**:
- Thrown like a grenade (short range, lobs to landing point)
- After landing, blinks (armed indicator) for 2 seconds
- Once armed: small `Area2D` detection zone monitors for enemies
- If enemy enters zone → instant explosion (same radius/damage/shrapnel as Frag)
- Player can place up to 2 at once (second one replaces first if both placed)
- Does not trigger on the player

**Justification**: Enables area-control gameplay. Player can place mines at doorways/chokepoints as a passive defense while engaging elsewhere. Creates *preparation vs. reaction* tactical layer absent from current grenade set.

**Technical Fit**: Extends `GrenadeBase` but overrides `activate_timer()` to arm a proximity detection instead. Small `Area2D` child node already used in many scripts. No new architecture needed.

**Reference**: ML30 Laser Trip Mine (Alien Swarm), Proximity Mine (Enter the Gungeon), Satchel Charge (various military shooters).

---

### Priority 2 — Active Items (Fits ActiveItemManager Enum System)

These additions extend the `ActiveItemType` enum and require a new icon + behavior implementation.

---

#### 2.1 Decoy Flare (`DECOY_FLARE`)

**Concept**: Press Space to throw a flare/noise device that redirects all nearby enemies toward it for 8 seconds.
**Mechanic**:
- Thrown to cursor position (like grenade)
- Flare lands, emits sound and light
- All enemies that hear it switch their AI target to the flare position for 8 seconds
- Enemies that reach the flare and find no player break off after a short confused pause
- 2 charges per battle

**Justification**: Enables pure AI manipulation without damage. The `SoundPropagation` autoload already drives enemy alert behavior. A decoy that emits a loud `SoundPropagation.emit_sound()` at the throw target would redirect enemies without any new AI code.

**Technical Fit**: `SoundPropagation.emit_sound()` already exists. The flare just needs to call it with high sound range. Enemy AI already responds to sounds by moving toward the source.

**Reference**: Swarm Bait (Alien Swarm), thrown firearms stun (Hotline Miami).

---

#### 2.2 Adrenaline Shot (`ADRENALINE`)

**Concept**: Press Space to enter a 3-second bullet-time effect — game slows to 40% speed for the player, full speed enemies (reversed: player moves faster relative to enemies).
**Mechanic**:
- `Engine.time_scale = 0.4` for 3 seconds, player input speed compensated
- Visual effect: slight color desaturation, vignette
- 1 charge per battle

**Justification**: Pure defensive "get out of a bad situation" item. Similar conceptually to Teleport Bracers but rewards reaction skill instead of teleport precision. The `Engine.time_scale` approach is already used in the codebase for effects.

**Technical Fit**: Godot's `Engine.time_scale` is global. The `CinemaEffectsManager` autoload already handles visual effects for similar purposes. Implementation is a few lines.

**Reference**: Adrenaline (Alien Swarm: Reactive Drop), Bullet-time (Max Payne, various).

---

#### 2.3 EMP Device (`EMP_DEVICE`)

**Concept**: Press Space to emit an EMP pulse (radius 500px) that disables enemy force fields for 10 seconds.
**Mechanic**:
- Instant area effect centered on player
- All `EnemyForceFieldComponent`-equipped enemies within range: force field deactivated for 10 seconds
- Also disables player's own Force Field item if active (trade-off)
- 2 charges per battle
- Does not damage or stun

**Justification**: The game already has force field enemies (enemy type with `EnemyForceFieldComponent`). Currently, force fields are hard to defeat — bullets bounce off. EMP provides a counter-play option and tactical diversity: player can choose to spend an EMP charge to neutralize a shielded enemy, or try to outmaneuver it instead.

**Technical Fit**: `EnemyForceFieldComponent` already exists. EMP just needs to call a new `disable_temporarily()` method on it. The component pattern (`get_node_or_null()`) is already standard.

**Reference**: EMP Grenade (Helldivers 2), various electronic-warfare items in tactical games.

---

#### 2.4 Ammo Cache (`AMMO_CACHE`)

**Concept**: Press Space to deploy a small ammo cache that fully restores current weapon reserve ammo.
**Mechanic**:
- Instantly replenishes reserve ammo for current weapon to maximum
- 1 use per battle
- Simple QoL item for extended engagements

**Justification**: Currently there is no way to replenish ammo mid-level without picking up enemy drops. Long levels with many enemies can deplete ammo. An ammo cache gives the player strategic flexibility in choosing *when* to replenish rather than relying on RNG enemy drops.

**Technical Fit**: `AmmoComponent` already tracks and modifies ammo. The `active_item_manager.gd` already handles Space-key activation. Adding ammo restoration is a call to an existing method.

---

#### 2.5 Deployable Turret (`DEPLOYABLE_TURRET`)

**Concept**: Press Space to place a small automated turret that fires at nearby enemies for 15 seconds, then self-destructs.
**Mechanic**:
- Placed at cursor position (max 300px from player)
- Turret: 30px sprite, auto-rotates toward nearest enemy, fires every 0.3s
- Does 1 damage per shot, 300px vision range
- After 15 seconds or 30 shots expended: explodes and disappears
- 1 turret at a time (second placement removes first)
- 1 charge per battle

**Justification**: The `BFFTargetingComponent` and companion BFF already implement auto-targeting behavior. A turret is a stationary, temporary version of the BFF companion — easier to implement because it's static (no movement AI needed).

**Technical Fit**: BFF companion (summoned by BFF Pendant) already implements targeting logic via `BFFTargetingComponent`. A turret variant would be simpler (no movement, just rotate and shoot). Reuse `BFF` scene with movement disabled.

**Reference**: Tesla Sentry Coil (Alien Swarm), Eye of the Beholster companion (Enter the Gungeon).

---

### Priority 3 — Weapons

These require more significant work (new scene, weapon data resource, player integration).

---

#### 3.1 SMG (Submachine Gun)

**Concept**: An SMG (`smg` is already reserved in `game_manager.gd` as "coming soon").
**Mechanic**:
- Higher fire rate than M16 (fire rate ~15/s)
- Smaller magazine than UZI but less extreme spread (mid-point between M16 and UZI)
- 9x19 caliber (reuse existing)
- Unlocked through a new level condition

**Technical Fit**: `game_manager.gd` already has `"smg": false` in `unlocked_weapons`. The weapon data `.tres` file pattern is established. A C# `WeaponBase` subclass already handles all weapon behavior.

**Reference**: All tactical shooters feature an SMG as a mid-tier automatic weapon.

---

#### 3.2 Crossbow

**Concept**: Silent bolt weapon with extreme single-shot damage, very long reload time.
**Mechanic**:
- 1 bolt per magazine, 5 reserve bolts
- 50 damage per bolt (same as ASVK sniper)
- Bolt travels at 3000px/s, no spread
- Completely silent (no `SoundPropagation` event on fire)
- Bolt sticks in walls (no ricochet)
- 3-second reload

**Justification**: Fills a "silent high-damage" niche. Currently the silenced pistol is the only stealth weapon, but it deals low damage. The crossbow enables a stealth-focused playstyle for skilled players.

**Technical Fit**: New caliber `.tres` ("bolt") with `can_ricochet = false`, `loudness = 0`. Reuse `Bullet.tscn` with modified properties. `SilencedPistol` scene demonstrates how to build a no-loudness weapon.

**Reference**: Crossbow (numerous games), Auto Crossbow (Nuclear Throne — synergizes with mutations).

---

#### 3.3 Flamethrower

**Concept**: Short-range continuous fire weapon that deals damage-over-time and creates small fire patches.
**Mechanic**:
- Very short range (300px)
- Fires a continuous stream of particles (using Godot's `GPUParticles2D`)
- Each tick of the stream applies 0.5 damage to enemies in the cone
- Leaves small fire patches behind that deal 1 damage/second
- 100-unit fuel tank, drains rapidly during use

**Justification**: Unique mechanical niche not covered by any existing weapon. Encourages close-range aggressive play with area-denial side effect. Creates risk/reward: get close enough to hurt enemies, but don't burn yourself.

**Technical Fit**: Particle systems (`GPUParticles2D`) are already used for visual effects. A `RayCast2D` cone sweep can handle hit detection, similar to shotgun pellet spread logic.

**Reference**: M868 Flamer Unit (Alien Swarm — napalm primary with CO2 secondary), Flamethrower (various games).

---

#### 3.4 Machete (Player Melee Weapon)

**Concept**: A melee weapon the player can equip. Replaces sidearm slot.
**Mechanic**:
- Replaces one of the weapon slots with melee
- Press attack to perform a forward slash arc (90°) with 80px range
- One-hit kill on unarmored enemies
- No ammo, no reload
- Can deflect projectiles during the swing animation (50ms window)
- Silent — no `SoundPropagation` event

**Justification**: `MacheteComponent` already fully implements this mechanic for *enemies*. A player version would reuse the same animation phases (WINDUP, PAUSE, STRIKE, RECOVERY) and arc geometry. The component already exists — it needs to be exposed to the player.

**Technical Fit**: `MacheteComponent` is a `Node`-based component designed to be attached to any character. Adapting it for the player is primarily a matter of wiring input (attack key) to the existing `MacheteComponent._perform_attack()` logic.

**Reference**: Machete / knife melee in Hotline Miami, Alien Swarm's Power Fist, nuclear Throne's Jackhammer.

---

### Priority 4 — Passive Items

Lower implementation complexity (add to passive item evaluation in `player.gd`).

---

#### 4.1 Fire Bullets (Passive)

**Concept**: All bullets have a 30% chance to set an enemy on fire, dealing 1 damage/second for 5 seconds.
**Mechanic**:
- On hit, 30% chance to spawn a fire status effect on the enemy
- Fire effect: enemy modulate turns orange, loses 1 HP per second
- Effect doesn't stack (second fire bullet on same enemy resets timer)
- Visual: small flame particle above enemy

**Reference**: Dragunfire (Enter the Gungeon), various fire bullet upgrades.

---

#### 4.2 Ricochet Amplifier (Passive)

**Concept**: All calibers gain +2 maximum ricochets and +25% ricochet angle tolerance.
**Mechanic**:
- `caliber_data.gd` has `max_ricochets` and `max_ricochet_angle` fields
- This passive increases both values for the equipped weapon's caliber
- Allows bullets to bounce more and at wider angles, enabling around-corner shots

**Reference**: Bolt Marrow mutation (Nuclear Throne), various ricochet items (Enter the Gungeon).

---

#### 4.3 On-Kill Healing (Passive)

**Concept**: Each enemy kill restores 0.5 HP to the player (rounded down — effective every 2 kills).
**Mechanic**:
- Listens for `GameManager.enemy_killed` signal
- Calls `health_component.heal(0.5)` on player
- Maximum HP still applies

**Technical Fit**: `GameManager` already emits `enemy_killed` signal. `HealthComponent` is already on the player.

**Reference**: Big Bloodthirst (Nuclear Throne), lifesteal (Diablo series), Vampire's Bite (various roguelikes).

---

#### 4.4 Explosive Bullets (Passive)

**Concept**: Each bullet spawns a small explosion on impact (15px radius, 1 damage). Cannot chain-explode.
**Mechanic**:
- On bullet hit, spawn a small explosion effect
- Explosion deals 1 damage to all enemies within 15px radius
- The explosion does not trigger other explosions
- Increases visual and audio noise of firing

**Technical Fit**: `BreakerBulletsComponent` already implements on-bullet explosion logic. Explosive bullets would be a simpler passive version without the "60px before wall" requirement.

**Reference**: Explosive ammo (numerous games), Breaker Bullets (already in this game, directional variation).

---

## Architecture Recommendations

When implementing any of the above, follow these established patterns:

### Adding a New Grenade
1. Create `scripts/projectiles/<name>_grenade.gd` extending `GrenadeBase`
2. Override `_on_explode()` with the unique effect
3. Create `scenes/projectiles/<Name>Grenade.tscn` using the new script
4. Add to `GrenadeManager.GrenadeType` enum and `GRENADE_DATA` dictionary
5. Set `unlocked_grenades[GrenadeType.NEW] = false` initially
6. Add unlock condition in `unlock_manager.gd`'s `UNLOCK_CONDITIONS`

### Adding a New Active Item
1. Add new value to `ActiveItemManager.ActiveItemType` enum
2. Add entry to `ACTIVE_ITEM_DATA` dictionary (name, icon_path, description)
3. Add icon `.png` to `assets/sprites/weapons/`
4. Add `unlocked_active_items[ActiveItemType.NEW] = false` initially
5. In `scripts/characters/player.gd`, add Space-key handler for the new type
6. Add unlock condition in `unlock_manager.gd`'s `UNLOCK_CONDITIONS`

### Adding a New Weapon
1. Create `resources/weapons/<Name>Data.tres` (WeaponData resource)
2. Create caliber `.tres` if needed (`resources/calibers/`)
3. Create `scenes/weapons/csharp/<Name>.tscn` (C# weapon scene)
4. Add to `GameManager.WEAPON_SCENES` and `unlocked_weapons` dictionaries
5. Add `WeaponConfigComponent` entry if enemies should use it
6. Add icon/sprite to `assets/sprites/weapons/`

---

## Summary Table: All Proposals

| Proposal | Priority | Type | Complexity | Key Innovation |
|---|---|---|---|---|
| Smoke Grenade | 1 | Grenade | Low | Creates persistent vision-blocking zone |
| Incendiary Grenade | 1 | Grenade | Low | Persistent fire damage zone (area denial) |
| Concussion Grenade | 1 | Grenade | Low | Knockback only, zero damage, displacement |
| Freeze Grenade | 1 | Grenade | Low | Immobilizes enemies, no damage |
| Proximity Mine | 1 | Grenade | Medium | Arms on landing, triggers near enemies |
| Decoy Flare | 2 | Active Item | Medium | Redirects all nearby enemies via sound |
| Adrenaline Shot | 2 | Active Item | Low | 3-second bullet-time (time slow) |
| EMP Device | 2 | Active Item | Low | Disables enemy force fields |
| Ammo Cache | 2 | Active Item | Very Low | Restores reserve ammo |
| Deployable Turret | 2 | Active Item | Medium | Automated stationary fire support |
| SMG | 3 | Weapon | Medium | Mid-tier auto SMG (already reserved slot) |
| Crossbow | 3 | Weapon | Medium | Silent high-damage bolt weapon |
| Flamethrower | 3 | Weapon | High | Short-range DoT stream + fire patches |
| Machete (player) | 3 | Weapon | Medium | Melee (MacheteComponent already exists) |
| Fire Bullets | 4 | Passive | Low | 30% DoT fire on hit |
| Ricochet Amplifier | 4 | Passive | Very Low | +2 ricochets, +25° ricochet tolerance |
| On-Kill Healing | 4 | Passive | Very Low | Heals 0.5 HP per kill |
| Explosive Bullets | 4 | Passive | Low | Small explosion on bullet impact |

---

## Recommended Implementation Order

Given the codebase architecture, the **highest-value lowest-effort** additions are:

1. **Smoke Grenade** — direct clone of AggressionGasGrenade with different visual/AI effect
2. **Incendiary Grenade** — direct clone with fire patch child scene instead of gas cloud
3. **Concussion Grenade** — direct clone with `apply_central_impulse` instead of damage
4. **Ammo Cache** — 10-line addition to active item space-key handler
5. **EMP Device** — 20-line addition using existing EnemyForceFieldComponent API
6. **On-Kill Healing** — signal connection + health_component.heal() call

The **highest-value higher-complexity** additions worth planning for:

7. **Proximity Mine** — new game mechanic, requires armed-state tracking + Area2D trigger
8. **Decoy Flare** — reuses SoundPropagation system, requires thrown item positioning logic
9. **Machete (player)** — reuses MacheteComponent, requires input wiring + weapon slot integration
10. **SMG** — filling the already-reserved slot in game_manager.gd

---

## References

- [Alien Swarm: Reactive Drop Wiki — Equipment](https://wiki.reactivedrop.com/Equipment)
- [Enter the Gungeon — Guns](https://enterthegungeon.fandom.com/wiki/Guns)
- [Enter the Gungeon — Items](https://enterthegungeon.fandom.com/wiki/Items)
- [Nuclear Throne Wiki — Weapons](https://nuclear-throne.fandom.com/wiki/Weapons)
- [Nuclear Throne Wiki — Mutations](https://nuclear-throne.fandom.com/wiki/Mutations)
- [Hotline Miami Wiki — Weapons](https://hotlinemiami.fandom.com/wiki/Weapons)
- [Helldivers 2 — Stratagems Guide](https://www.thegamer.com/helldivers-2-best-stratagems/)
- [TheGamer — Enter the Gungeon Best Guns](https://www.thegamer.com/enter-the-gungeon-best-guns/)
