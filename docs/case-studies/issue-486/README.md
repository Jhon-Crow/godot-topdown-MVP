# Case Study: Issue #486 — Проверить играбельность, механики и баланс

## Summary

Comprehensive playability, mechanics, and balance verification plan for the Godot Top-Down MVP project. This document catalogs every gameplay element currently implemented in the `main` branch and provides structured checklists for testing each one.

## Codebase Analysis

### Project Overview

The project is a **top-down tactical shooter** inspired by Hotline Miami, built with Godot 4.3 using a dual-language architecture (GDScript + C#). It features:

- **5 weapons** with unique mechanics (Assault Rifle, Shotgun, Mini UZI, Silenced Pistol, ASVK Sniper)
- **3 grenade types** (Frag, Flashbang, Defensive)
- **3 playable levels** (Здание/Building, Замок/Castle, Полигон/Training)
- **1 tutorial level** (Обучение/Tutorial)
- **4 difficulty modes** (Easy, Normal, Hard, Power Fantasy)
- **Advanced AI** with 11 enemy states, GOAP planner, cover system, and grenade usage
- **Realistic ballistics** with ricochet, wall penetration, caliber physics
- **Replay system** with Ghost and Memory modes
- **Score system** with Hotline Miami-style ranks (F through S)
- **Cinema effects** (film grain, vignette, warm tint, death effects)
- **16+ autoload systems** managing audio, effects, difficulty, etc.

### Source Files Analyzed

| Category | Files | Lines (approx.) |
|----------|-------|-----------------|
| GDScript (scripts/) | 74 files | ~31,700 lines |
| C# (Scripts/) | 14 files | ~8,500 lines |
| Scenes (.tscn) | 30+ files | — |
| Resources (.tres) | 9 files | — |
| Tests | 55+ files | ~15,000 lines |
| **Total** | **180+ files** | **~55,000 lines** |

---

## Gameplay Testing Checklist

### 1. Player Movement & Controls

- [ ] **WASD movement** — Player moves in 4 directions with correct speed (200 px/s base)
- [ ] **Diagonal movement** — Diagonal movement is normalized (no speed boost at 45°)
- [ ] **Acceleration/friction** — Movement feels responsive (1200 acceleration, 1000 friction)
- [ ] **Camera following** — Camera smoothly follows player (smoothing speed 5.0)
- [ ] **Camera limits** — Camera stays within level bounds (0,0 to level edge)
- [ ] **Collision with walls** — Player cannot walk through walls/obstacles
- [ ] **Collision with enemies** — Player collides properly with enemy characters
- [ ] **Player model rotation** — Player model faces toward mouse cursor
- [ ] **Walking animation** — Body bob, head bob, and arm swing during movement
- [ ] **Idle animation** — Smooth return to idle pose when stopping
- [ ] **Casing pushing** — Player pushes shell casings when walking over them (force 20.0)
- [ ] **Bloody footprints** — Blood trail appears after walking through blood (12 steps, 30px distance)

### 2. Weapons — Assault Rifle (M16)

- [ ] **Auto fire mode** — Hold LMB for continuous fire (10 rounds/sec)
- [ ] **Burst fire mode** — Toggle with B key, fires 3-round bursts (0.05s delay between rounds)
- [ ] **Fire mode toggle** — B key switches between Auto and Burst, plays sound
- [ ] **Red laser sight** — Visible red laser from weapon to target area
- [ ] **Bullet spread** — Increases after 3 consecutive shots (0.5° initial, 4.0° max)
- [ ] **Spread reset** — Spread resets after 0.25s pause between shots
- [ ] **Recoil** — Visual recoil on fire (~5° max offset), recovers at 8.0 rad/s
- [ ] **Screen shake** — Shake intensity 5 on each shot
- [ ] **Magazine capacity** — 30 rounds per magazine
- [ ] **Reserve ammo** — 30 reserve (1 spare magazine, 90 total on Normal difficulty)
- [ ] **Reload sequence** — R to eject magazine, F to insert new magazine, R to charge bolt
- [ ] **Simple reload** — Hold R for automatic reload if sequence not desired
- [ ] **Shell casing ejection** — Brass casing ejects on each shot (0.15s delay)
- [ ] **Muzzle flash** — Visual flash + point light on fire
- [ ] **Bullet speed** — 2500 px/s
- [ ] **Bullet range** — 1500 px maximum travel
- [ ] **Sound propagation** — Loudness 1469 px (enemies within range are alerted)
- [ ] **Ricochet** — 5.45x39mm bullets ricochet at all angles (probability varies)
- [ ] **Wall penetration** — Bullets can penetrate walls up to 48px thick
- [ ] **Ricochet damage** — 50% damage after each ricochet
- [ ] **Penetration damage** — 90% damage after wall penetration

### 3. Weapons — Shotgun

- [ ] **Fire** — LMB fires 9 pellets with 15° spread
- [ ] **Pump-action** — After firing: drag RMB UP (eject shell), RMB DOWN (chamber)
- [ ] **Cannot fire without pumping** — Weapon locks until pump cycle is completed
- [ ] **Shell-by-shell reload** — RMB UP → [MMB + RMB DOWN]×N → RMB DOWN to close
- [ ] **Magazine capacity** — 8 shells in tube
- [ ] **Reserve ammo** — 12 shells reserve (20 total on Normal)
- [ ] **Pellet spread pattern** — 9 pellets distributed across 15° cone
- [ ] **Pellet damage** — 1.0 per pellet (9.0 total potential)
- [ ] **Pellet ricochet** — Limited to 35° shallow angles only
- [ ] **No pellet penetration** — Pellets stop on wall impact (unless ricochet)
- [ ] **Pellet speed** — 2500 px/s
- [ ] **Screen shake** — Intensity 25 (heavy)
- [ ] **Sound propagation** — Loudness 1469 px
- [ ] **Shell casing** — Large casing ejects during pump-up action
- [ ] **Casing size** — Buckshot casings are larger than rifle casings (effect_scale 1.2)

### 4. Weapons — Mini UZI

- [ ] **Auto fire** — High rate 25 rounds/sec
- [ ] **Low per-bullet damage** — 0.5 damage per bullet
- [ ] **Progressive spread** — Starts at base angle, increases to 60° over 10 bullets
- [ ] **Progressive screen shake** — Intensity increases 1x to 4x as spread grows
- [ ] **Magazine capacity** — 32 rounds
- [ ] **Reserve ammo** — 64 rounds reserve
- [ ] **Recoil** — Heavy recoil (~8° max), recovers at 6.0 rad/s
- [ ] **Bullet speed** — 1200 px/s (slower than rifle)
- [ ] **Range** — 800 px
- [ ] **Blue laser in Power Fantasy** — Blue laser sight only in Power Fantasy difficulty
- [ ] **9x19mm ballistics** — Limited ricochet (max 1, 70% probability), no penetration

### 5. Weapons — Silenced Pistol

- [ ] **Semi-auto** — 1 shot per click (8 rounds/sec max)
- [ ] **Magazine capacity** — 13 rounds (Beretta M9 style)
- [ ] **Reserve ammo** — 26 rounds reserve
- [ ] **Green laser sight** — Green colored laser
- [ ] **Silent operation** — 0.0 loudness (enemies NOT alerted by gunfire)
- [ ] **Stun effect** — Enemies stunned for 0.6s on hit
- [ ] **Heavy recoil** — ~10° max (2x assault rifle), slow recovery (4.0 rad/s)
- [ ] **Small muzzle flash** — 0.2 scale (much smaller than other weapons)
- [ ] **Bullet speed** — 1350 px/s
- [ ] **Range** — 800 px
- [ ] **Smart ammo** — `ConfigureAmmoForEnemyCount()` distributes ammo to match enemies
- [ ] **9x19mm ballistics** — Limited ricochet, no wall penetration

### 6. Weapons — ASVK Sniper Rifle

- [ ] **Bolt-action** — 4-step cycling: Left→Down→Up→Right (arrow keys only)
- [ ] **WASD movement during bolt** — Player can still move with WASD during bolt cycling
- [ ] **Magazine capacity** — 5 rounds
- [ ] **Reserve ammo** — 5 rounds reserve
- [ ] **Damage** — 50.0 per shot (one-shot most enemies)
- [ ] **Enemy passthrough** — Bullet passes through enemies (hits multiple in line)
- [ ] **Wall penetration** — Penetrates up to 2 walls
- [ ] **Bullet speed** — 10,000 px/s (near-instant)
- [ ] **Slow rotation** — 5x slower aiming sensitivity when not scoped
- [ ] **Smoky tracer** — Visible smoke trail that dissipates over 2 seconds
- [ ] **Large casing** — 12.7x108mm casings are 2x size of M16 casings
- [ ] **Casing ejects on bolt step 2** — Down arrow triggers casing ejection
- [ ] **No laser sight** — Removed on all difficulties except Power Fantasy
- [ ] **Blue laser in Power Fantasy** — Blue laser sight only in Power Fantasy mode
- [ ] **Scope system** — Hold RMB to activate sniper scope
- [ ] **Scope crosshair** — Classic mil-dot reticle at viewport center
- [ ] **Scope zoom** — Mouse wheel adjusts 1.5x-3.0x zoom
- [ ] **Scope fine-tune** — Mouse along aim direction adjusts ~1/3 viewport distance
- [ ] **Distance-based sensitivity** — 5x base × zoom distance
- [ ] **Bullets hit crosshair** — When scoped, bullets go to crosshair position
- [ ] **Minimum scope distance** — 1.5x viewport (half viewport beyond normal)
- [ ] **Heavy recoil** — ~15° max offset, slow recovery (3.0 rad/s)
- [ ] **Heavy screen shake** — Intensity 25
- [ ] **Extreme loudness** — 3000 px propagation (2x normal)
- [ ] **ASVK-specific sounds** — Unique shot and bolt-action sounds

### 7. Grenades — Frag Grenade (РГД)

- [ ] **Throw mechanic** — G to prepare, RMB to throw (drag-based aiming)
- [ ] **Impact detonation** — Explodes on hitting surface/enemy (no timer)
- [ ] **Effect radius** — 225 px explosion zone
- [ ] **Explosion damage** — 99 damage (instant kill most enemies)
- [ ] **Shrapnel** — 4 pieces in random directions
- [ ] **Shrapnel speed** — 5000 px/s (2x bullet speed)
- [ ] **Shrapnel ricochets** — Max 3 ricochets per fragment
- [ ] **Shrapnel damage** — 1 per hit
- [ ] **Line-of-sight blocking** — Walls block explosion damage (Issue #469)
- [ ] **Physics** — Bounces off walls (40% velocity retention)
- [ ] **Ground friction** — Slows and stops after throw (friction 280)
- [ ] **Throw power** — Based on drag distance/mouse velocity
- [ ] **Grenade count** — 3 on Normal, 1 on Hard, 9 on Power Fantasy

### 8. Grenades — Flashbang

- [ ] **Timer detonation** — 4-second fuse (NOT impact-triggered)
- [ ] **Effect radius** — 400 px (larger than frag)
- [ ] **Non-lethal** — 0 damage
- [ ] **Blindness** — 12 seconds (enemies cannot see player)
- [ ] **Stun** — 6 seconds (enemies cannot move)
- [ ] **Wall blocking** — Walls block flash effects
- [ ] **Casing scatter** — Nearby casings scatter (40% of radius = 160px)
- [ ] **Distinct sound** — Different sounds based on player proximity

### 9. Grenades — Defensive Grenade (Ф-1)

- [ ] **Timer detonation** — 4-second fuse
- [ ] **Large radius** — 700 px (area denial)
- [ ] **Heavy shrapnel** — 40 pieces (10x more than frag)
- [ ] **Shrapnel spread** — ±15° deviation
- [ ] **Explosion damage** — 99 (like frag)
- [ ] **Heavier mass** — 0.6 kg (slightly shorter throws)
- [ ] **Purpose** — Area denial, defensive use

### 10. Enemy AI

- [ ] **Idle/patrol** — Enemies patrol between configurable waypoints
- [ ] **Detection** — Line-of-sight with 100° FOV, 0.2s detection delay
- [ ] **Combat engagement** — Enemies open fire when detecting player
- [ ] **Cover seeking** — Enemies find and use cover (16 raycasts, 300px range)
- [ ] **Flanking** — Enemies attempt to circle player position
- [ ] **Suppression** — Under fire, enemies stay in cover
- [ ] **Retreat** — Enemies retreat when at low health or under pressure
- [ ] **Pursuit** — Cover-to-cover movement toward player
- [ ] **Assault** — Coordinated multi-enemy rush (5s wait before attack)
- [ ] **Searching** — Methodical search of last known player position (Issue #322)
- [ ] **Grenade evasion** — Enemies flee from visible grenades (Issue #407)
- [ ] **Lead prediction** — Enemies predict moving player position (0.3s activation delay)
- [ ] **Friendly fire avoidance** — Enemies avoid shooting through allies
- [ ] **Distraction attacks** — Enemies attack when player looks away (Hard mode)
- [ ] **Sound awareness** — Enemies react to gunfire and explosion sounds
- [ ] **Random health** — 2-4 HP per enemy (randomized)
- [ ] **Hit flash** — White flash on damage (0.1s)
- [ ] **Death animation** — 24-directional fall + ragdoll physics (0.8s)
- [ ] **Weapon types** — RIFLE (30 mag, 0.1s cooldown), SHOTGUN (8 mag, 0.8s), UZI (32 mag, 0.06s)
- [ ] **Reload** — 3-second reload cycle for all enemy weapons
- [ ] **Grenade throwing** — 7 AI triggers, 15s cooldown, 275-600px range

### 11. Enemy Grenade AI Triggers

- [ ] **Suppression trigger** — Enemy hidden 6+ seconds → throws grenade at player
- [ ] **Pursuit trigger** — Player approaching rapidly → throws grenade
- [ ] **Witnessed kills** — 3+ ally kills in 30s window → throws grenade
- [ ] **Sound detection** — Hearing sustained combat → throws grenade
- [ ] **Sustained fire** — Caught in crossfire → throws grenade
- [ ] **Suspicion** — Medium+ suspicion, player hidden 3+ seconds → throws grenade (Issue #379)
- [ ] **Safety distance** — Minimum 275px throw distance (blast_radius 225 + margin 50)
- [ ] **Throw cooldown** — 15 seconds between throws
- [ ] **Inaccuracy** — ±0.15 radians deviation from perfect aim

### 12. Difficulty Modes

#### Easy
- [ ] **Longer enemy reaction** — Enemies take longer to detect and shoot
- [ ] **Standard ammo** — 90 rounds (3 magazines)
- [ ] **Standard grenades** — 3 grenades

#### Normal
- [ ] **Default settings** — Balanced gameplay
- [ ] **90 rounds** — 3 magazines × 30 rounds
- [ ] **3 grenades**

#### Hard
- [ ] **Reduced ammo** — 60 rounds total
- [ ] **1 grenade** — Limited explosive options
- [ ] **Distraction attacks** — Enemies attack when player looks away
- [ ] **Ricochet damage** — Player takes ricochet damage
- [ ] **Last chance effects** — Bullet time when near-miss detected
- [ ] **Threat detection** — ThreatSphere detects bullets within 150px heading toward player

#### Power Fantasy
- [ ] **10 HP** — Doubled health
- [ ] **270 rounds** — 3x normal ammo
- [ ] **9 grenades** — 3x normal grenades
- [ ] **Reduced recoil** — Easier aiming
- [ ] **Blue lasers** — Blue laser sights on applicable weapons
- [ ] **No ricochet damage** — Player immune to ricochets
- [ ] **Time freeze effects** — Grenade explosions trigger time freeze
- [ ] **Power fantasy visual effects** — Enhanced saturation, effects on kills

### 13. Scoring & Ranking System

- [ ] **Kill score** — 100 points per enemy kill
- [ ] **Combo system** — Exponential multiplier for rapid kills (5s timeout)
- [ ] **Time bonus** — Up to 5000 points (120s timer)
- [ ] **Accuracy bonus** — Up to 2000 points based on hit ratio
- [ ] **Damage penalty** — -200 points per hit taken
- [ ] **Special kill bonus** — +150 points for ricochet or penetration kills
- [ ] **Rank calculation** — S(100%), A+(85%), A(70%), B(55%), C(38%), D(22%), F(<22%)
- [ ] **Animated score screen** — Sequential stat reveal with counting animation
- [ ] **Rank display** — Large rank letter with gradient background
- [ ] **Score color progression** — Color changes F(red)→D→C→B→A→A+→S(gold) during counting
- [ ] **Gradient background** — Animated contrasting colors during rank reveal
- [ ] **Score screen timing** — 1.5s per item, 0.25s delay between items

### 14. Levels

#### Building Level (Здание)
- [ ] **Level size** — 2464x2064 pixels (multi-room building)
- [ ] **10 enemies** — Strategically placed in rooms
- [ ] **Room structure** — Offices, conference room, break room, server room, storage, hall
- [ ] **Cover objects** — Desks, tables, cabinets, crates
- [ ] **Navigation mesh** — Valid pathfinding for enemies
- [ ] **Exit zone** — Available after all enemies eliminated
- [ ] **Score tracking** — Full scoring with animated end screen
- [ ] **Enemy/ammo UI** — Real-time counters displayed
- [ ] **Combo label** — Kill combo counter in top-right corner

#### Castle Level (Замок)
- [ ] **Outdoor arena** — Circular/fortress design
- [ ] **Tower structures** — Vertical cover options
- [ ] **Pillars** — Engagement points for combat
- [ ] **2x ammo** — Castle gives double ammo (8 magazines instead of 4)
- [ ] **Navigation mesh** — Valid for open-area pathfinding
- [ ] **Exit zone** — Post-completion exit

#### Полигон (Training Grounds)
- [ ] **10 enemies** — Standard enemy count
- [ ] **Score tracking** — Full scoring integration
- [ ] **Exit zone** — Left wall, near spawn
- [ ] **Level label** — Shows "ПОЛИГОН" in top-right
- [ ] **Combo tracking** — Kill combo in top-right corner (golden color, size 28)

#### Tutorial (Обучение)
- [ ] **ASVK tutorial** — Shoot → bolt-action reload → scope training → grenade
- [ ] **Progressive instruction** — Each step advances after completion
- [ ] **Target practice** — Stationary targets for learning

### 15. UI Systems

- [ ] **Pause menu** — ESC opens pause (Resume, Controls, Difficulty, Armory, Levels, Experimental, Quit)
- [ ] **Controls menu** — Full key rebinding with conflict detection
- [ ] **Difficulty menu** — 4 difficulty buttons with description labels
- [ ] **Armory menu** — Left sidebar stats, right grid layout, Apply button
- [ ] **Armory weapon stats** — Fire Mode, Caliber, Damage, Fire Rate, Magazine, Reserve, Reload, Range, Spread, Loudness, Ballistics
- [ ] **Armory pending selection** — Green highlight on click, no restart until Apply
- [ ] **Armory accordion** — "Show all" button if weapons overflow 2 rows
- [ ] **Levels menu** — Building, Castle, Полигон selection
- [ ] **Experimental menu** — FOV toggle, complex grenade throwing toggle
- [ ] **Ammo counter** — Real-time ammo display (current/magazine/reserve)
- [ ] **Enemy counter** — Remaining enemies display
- [ ] **Grenade counter** — Remaining grenades display

### 16. Visual Effects

- [ ] **Blood splatters** — On enemy hits (45 particles, red)
- [ ] **Blood decals** — Persistent blood marks on surfaces
- [ ] **Dust effects** — On wall impacts (25 particles, brown)
- [ ] **Sparks effects** — On ricochet/metal impacts
- [ ] **Bullet holes** — Entry/exit holes in walls
- [ ] **Penetration holes** — Through-wall penetration markers
- [ ] **Muzzle flash** — Flash + point light on weapon fire
- [ ] **Shell casings** — Physics-based ejected casings (caliber-specific size)
- [ ] **Explosion flash** — Grenade detonation visual
- [ ] **Flashbang effect** — Screen flash for flashbang
- [ ] **Cinema effects** — Film grain (0.15), warm tint (0.12), vignette (0.25), film defects (1.5%)
- [ ] **Death circle** — Cigarette burn + expanding spots end-of-reel circle (160px, 2 blinks)
- [ ] **Screen shake** — Camera displacement on weapon fire/explosions
- [ ] **Hit effects** — Time slowdown (0.9x for 3s) + saturation boost on enemy hits
- [ ] **Penultimate hit** — Time scale 0.1 (10x slowdown), saturation 2.0, contrast 1.0, duration 3.0s
- [ ] **Last chance effect** — 6.0s freeze, sepia 0.70, brightness 0.60 (Hard mode)
- [ ] **Power fantasy effects** — Kill effect 300ms, grenade effect 2000ms

### 17. Audio System

- [ ] **M16 sounds** — 3 shot variants, 2 double-shot variants, 4 bolt sounds
- [ ] **Shotgun sounds** — 4 shot variants, pump sound, shell load
- [ ] **UZI sounds** — 3 shot variants
- [ ] **ASVK sounds** — Unique shot and 4 bolt-step sounds
- [ ] **Silenced pistol** — Quiet shot sound
- [ ] **Reload sounds** — Magazine out, magazine in, full charge
- [ ] **Hit sounds** — Lethal and non-lethal variants
- [ ] **Impact sounds** — Wall hit, near player, cover hit
- [ ] **Ricochet sounds** — 2 variant array
- [ ] **Casing sounds** — Rifle, pistol, shotgun variants
- [ ] **Grenade sounds** — Activation, 3 explosion types, landing
- [ ] **Voice cues** — Distraction attack, suspicion voice lines
- [ ] **Sound priority system** — CRITICAL(never cut) > HIGH > MEDIUM > LOW
- [ ] **Sound propagation** — Alerts enemies within loudness radius

### 18. Replay System

- [ ] **Recording** — Captures all entity positions, rotations, velocities per physics frame
- [ ] **Max duration** — 300 seconds (5 minutes)
- [ ] **Watch Replay button** — Available after level completion
- [ ] **Ghost mode** — Red/black/white stylized filter
- [ ] **Memory mode** — Full color with all gameplay effects and motion trails
- [ ] **Mode switcher** — Toggle between Ghost and Memory modes
- [ ] **Walking animation** — Procedural walk animation during playback
- [ ] **Aim rotation** — Ghost entities show correct aiming direction
- [ ] **Death animation** — 0.8s fall + ragdoll effect on enemy death
- [ ] **Muzzle flash** — Flash effects on shooting events
- [ ] **Bullet tracers** — Visible bullet paths during replay
- [ ] **Weapon visible** — Player weapon sprite visible on ghost
- [ ] **Camera follow** — Camera follows ghost player
- [ ] **Score screen hidden** — Score screen hidden during replay
- [ ] **Speed controls** — Adjustable playback speed
- [ ] **Close button** — X button in top-right to exit replay
- [ ] **ESC exit** — Escape key exits replay

### 19. Ballistics System

- [ ] **Ricochet angle calculation** — Grazing angles = high probability, perpendicular = low
- [ ] **5.45x39mm (M16)** — Unlimited ricochets, 85% velocity retention, ±10° deviation
- [ ] **9x19mm (UZI/Pistol)** — Max 1 ricochet, 70% probability, no penetration
- [ ] **Buckshot (Shotgun)** — Max 35° angle ricochets, 75% velocity retention, ±15° deviation
- [ ] **12.7x108mm (ASVK)** — No ricochet, 200px penetration, passes through enemies
- [ ] **Distance-based penetration** — Point-blank=100%, near(40%)=normal rules, far=declining
- [ ] **Dead entity passthrough** — Bullets pass through dead enemies (collision disabled)
- [ ] **Trail effects** — Visual trail showing bullet path (8 points for rifle, 12 for sniper)

### 20. Status Effects

- [ ] **Blindness** — Flashbang-induced, 12 seconds, enemies cannot see
- [ ] **Stun** — Flashbang-induced, 6 seconds, enemies cannot move
- [ ] **Pistol stun** — 0.6 seconds on silenced pistol hit

---

## Balance Analysis

### Time-to-Kill (TTK) Analysis

| Weapon vs Enemy (2-4 HP) | Bullets to Kill | TTK at Max Fire Rate |
|--------------------------|-----------------|---------------------|
| Assault Rifle (1.0 dmg) | 2-4 shots | 0.1-0.3s |
| Shotgun (9 pellets × 1.0) | 1 shot (if most pellets hit) | instant |
| Mini UZI (0.5 dmg) | 4-8 shots | 0.16-0.32s |
| Silenced Pistol (10.0 dmg) | 1 shot | instant |
| ASVK (50.0 dmg) | 1 shot | instant |

### Ammo Economy Analysis

| Weapon | Total Ammo (Normal) | Enemies per Level | Shots/Enemy Needed | Theoretical Surplus |
|--------|--------------------|--------------------|--------------------|--------------------|
| Assault Rifle | 90 rounds | 10 | 2-4 | 50-70 surplus |
| Shotgun | 20 shells | 10 | 1-2 | 0-10 surplus |
| Mini UZI | 96 rounds | 10 | 4-8 | 16-56 surplus |
| Silenced Pistol | 39 rounds | 10 | 1 | 29 surplus |
| ASVK | 10 rounds | 10 | 1 | 0 surplus (tight!) |

### Observations

1. **ASVK ammo is very tight** — With only 10 rounds for 10 enemies, there is zero margin for error. Any miss or multi-enemy engagement means running out of ammo. This may be intentional for a high-skill weapon, but could frustrate players.

2. **Silenced Pistol one-shots** — With 10.0 damage vs 2-4 HP enemies, the pistol is a guaranteed one-shot kill. Combined with silent operation and stun, this may be the strongest weapon for skilled players.

3. **Shotgun ammo on Building level** — 20 shells for 10 enemies leaves little room for error, especially since some shells may be wasted on missed shots at range.

4. **Castle level 2x ammo** — The doubled magazine count (8 instead of 4) addresses the larger/more spread out level design.

5. **Power Fantasy difficulty** — 3x ammo (270 rounds), 3x grenades (9), 2x health (10 HP) — provides a very forgiving experience as intended.

---

## Known Issues & Potential Risks

### From Recent PRs and Game Logs

1. **ReplayManager (C# rewrite)** — The GDScript version fails in exported builds due to Godot 4.3 binary tokenization bugs. The C# rewrite works but required multiple fixes (PascalCase naming, score screen hiding, missing animations, weapon sprites, bullet rendering, death animations). All 7 bugs were addressed in PR #421.

2. **Combo double-counting** (Issue #511) — Both `died` and `died_with_info` signals were connected, causing each kill to be counted twice. Fixed in PR #514.

3. **Casing explosion on Power Fantasy** (Issue #522) — Casings not pushed by explosions because time-freeze happened before scatter logic. Fixed by queuing impulse and applying on unfreeze (PR #527).

4. **ASVK bolt input conflict** — `Input.IsActionJustPressed` responds to both WASD+arrows, blocking movement during bolt cycling. Fixed with separate arrow-only detection (PR #532).

5. **GDScript autoload failures in exports** — Complex GDScript files (800+ lines with advanced features) can silently fail in exported builds. Mitigation: use C# for complex autoloads.

### Potential Balance Concerns to Investigate

1. **Silenced Pistol meta** — One-shot kills + silent + stun may be too strong compared to other weapons
2. **ASVK ammo scarcity** — 10 rounds for 10 enemies leaves zero margin
3. **Enemy grenade frequency** — 15s cooldown may feel too frequent or infrequent depending on difficulty
4. **Flashbang duration** — 12s blindness + 6s stun is very long; may trivialize encounters
5. **Defensive grenade radius** — 700px radius with 40 shrapnel is extremely powerful area denial
6. **Difficulty curve** — Gap between Normal and Hard may be too steep (90→60 ammo, 3→1 grenades, distraction attacks enabled)

---

## Proposed Solutions & Recommendations

### Testing Tools

| Tool/Method | Purpose | Reference |
|-------------|---------|-----------|
| [GUT Framework](https://github.com/bitwes/Gut) | Automated unit testing for GDScript | Already integrated in project |
| [Godot Export Testing](https://docs.godotengine.org/en/4.3/tutorials/export/) | Test exported builds (catches GDScript tokenization bugs) | Godot documentation |
| [Game QA Checklists](https://snoopgame.com/blog/how-to-create-a-game-testing-checklist-for-indie-developers/) | Industry templates for indie game testing | SnoopGame |
| [TTK Calculator](https://protovision.github.io/ttk-calc/index.html) | Game-agnostic time-to-kill analysis tool | ProtoVision |
| [Desktop Game Testing Guide](https://qawerk.com/blog/desktop-game-testing-checklist/) | Comprehensive desktop game QA checklist | QAwerk |

### Recommended Next Steps

1. **Playtest each weapon** — On each level and each difficulty mode (5 weapons × 3 levels × 4 difficulties = 60 combinations)
2. **Verify ASVK ammo economy** — Confirm 10 rounds are sufficient or consider adding 1 spare magazine
3. **Test enemy AI state transitions** — Verify all 11 states trigger correctly and enemies don't get stuck
4. **Test all grenade interactions** — Each grenade type × level × difficulty
5. **Verify replay fidelity** — Record gameplay and confirm replay matches (both Ghost and Memory modes)
6. **Export build testing** — Build Windows export and verify all features work in non-editor environment
7. **Performance testing** — Monitor FPS during intensive scenes (all enemies + grenades + effects)
8. **Edge cases** — Test reload interruptions, weapon switching during actions, grenade cancel, etc.

---

## Game Logs

Game logs from user testing sessions are preserved in the case study for Issue #1 (which contains the most recent testing sessions):
- `docs/case-studies/issue-1/game_log_20260206_235558.txt`
- `docs/case-studies/issue-1/game_log_20260207_002734.txt`

These logs show all autoload initialization, enemy setup, weapon interactions, and replay system operation.

---

## References

- [How to Create a Game Testing Checklist for Indie Developers — SnoopGame](https://snoopgame.com/blog/how-to-create-a-game-testing-checklist-for-indie-developers/)
- [Desktop Game Testing: Comprehensive QA Checklist — QAwerk](https://qawerk.com/blog/desktop-game-testing-checklist/)
- [Game Testing Checklist — checklist.gg](https://checklist.gg/templates/game-testing-checklist)
- [TTK (Time-to-Kill) in Game Balance — Lark Suite](https://www.larksuite.com/en_us/topics/gaming-glossary/time-to-kill-ttk)
- [Game-Agnostic TTK Calculator — ProtoVision](https://protovision.github.io/ttk-calc/index.html)
- [QA in Game Development — Codefinity](https://codefinity.com/blog/QA-in-Game-Development)
- [Godot Cross-Language Scripting — Godot Docs](https://docs.godotengine.org/en/4.3/tutorials/scripting/cross_language_scripting.html)
- [Godot Engine Issue #96065 — GDScript load() with parse errors](https://github.com/godotengine/godot/issues/96065)
- [Godot Engine Issue #94150 — GDScript binary tokenization](https://github.com/godotengine/godot/issues/94150)
