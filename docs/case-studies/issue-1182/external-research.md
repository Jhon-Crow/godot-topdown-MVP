# External Research: Unlock Systems in Games

Research compiled 2026-03-18 for Issue #1182.

---

## 1. Dead Cells — Blueprint + Meta-Currency System

**Source:** https://deadcells.wiki.gg/wiki/Blueprints | https://store.steampowered.com/app/588650/Dead_Cells/

Dead Cells uses a **two-stage** permanent unlock system:

### Stage 1 — Blueprint Acquisition
Blueprints drop from enemies or are hidden in secret areas. Rarity tiers control pacing:

| Rarity | Drop Chance | Blueprint Count |
|---|---|---|
| Always | 100% | 104 |
| Common | 10% | 33 |
| Uncommon | 1.7% | 53 |
| Rare | 0.4% | 64 |
| Legendary | 0.03% | 2 |

A cap of one outfit blueprint and one item blueprint per biome per run prevents flooding.

### Stage 2 — Collector Purchase
Blueprints are handed to the Collector NPC using **Cells** (meta-currency earned during runs). The Collector also sells blueprints directly if they haven't dropped yet.

### Boss Cell Difficulty Ladder
Completing runs on increasing difficulty (0–5 Boss Cells) gates access to new biomes and late-game items, creating a long-term progression arc.

### Key Design Insights
- **Decoupled discovery from unlock**: finding the blueprint ≠ getting the item (requires spending Cells)
- **Rarity signals value**: players know rare drops are worth grinding for
- **Currency prevents instant completion**: even if you find everything, you must grind Cells to unlock them all

---

## 2. The Binding of Isaac: Rebirth/Repentance — Pure Achievement System

**Source:** https://store.steampowered.com/app/250900/The_Binding_of_Isaac_Rebirth/ | https://bindingofisaacrebirth.fandom.com/wiki/Unlockable_Items

Isaac uses **no meta-currency** — all unlocks are achievement-based.

### Key Facts
- 450+ items, 160+ unlockable in base Rebirth
- 641 Steam Achievements gating nearly all content
- **Completion marks**: defeating final bosses with each character unlocks items, characters, and game alterations
- **Challenge runs**: 20 special runs (pre-defined rules) unlock items on completion
- **Donation machine**: donating coins across runs to a machine unlocks items at thresholds (passive cross-run currency)

### Key Design Insights
- **Memorable unlock stories**: players remember *how* they unlocked something
- **Skill-based, not grind-based**: no farming required — just do things
- **Character-specific arcs**: each character has a personal unlock tree

---

## 3. Hades (Supergiant Games) — Multi-Layer Currency System

**Source:** https://store.steampowered.com/app/1145360/Hades/

Hades has the most sophisticated multi-layer unlock system:

| Layer | Currency | What It Unlocks |
|---|---|---|
| Weapons | Chthonic Keys | 6 weapons (1–8 Keys each) |
| Passive stats | Darkness | Mirror of Night upgrades |
| Hub cosmetics + functions | Gemstones, Diamonds | House Contractor items |
| Relationships | Nectar, Ambrosia | Keepsakes, lore, story |
| Endgame challenge | Heat (self-imposed) | Cosmetics, special items |

### Key Design Insights
- **Separate currencies = no bottleneck**: failing to unlock one thing doesn't block others
- **Dual-nature Mirror upgrades**: two competing paths per slot — meaningful strategic choices
- **All runs feel productive**: even a failed run yields multiple currencies toward different goals

---

## 4. Enter the Gungeon — NPC Rescue Model

**Source:** https://store.steampowered.com/app/311690/Enter_the_Gungeon/

Enter the Gungeon ties progression to **rescuing NPCs** found in the dungeon:

- Rescued NPCs appear at the Breach (hub)
- Each NPC adds new shop inventory, loot pool items, or services
- Some items require defeating character-specific boss encounters ("pasts")

### Key Design Insights
- **Human face on progression**: unlocks feel like helping characters, not checking boxes
- **Narrative motivation**: each NPC has a story, making unlocks feel meaningful

---

## 5. Nuclear Throne (Vlambeer) — Performance-Based Character Unlocks

Nuclear Throne uses **zone-reach or feat-based character unlocks** — no meta-currency:
- Characters unlock by reaching specific zones or performing specific feats in a run
- Weapon mutations are chosen within runs from a fixed pool (not unlocked across runs)
- Very clean, minimal system — no inventory management overhead

### Key Design Insights
- **Lightweight and pure**: no cross-run bookkeeping beyond character availability
- **Limited long-term hook**: lacks the "always making progress" feel of currency systems

---

## 6. Risk of Rain 2 — Challenge-Based Skill Unlocks + Discovery

**Source:** https://store.steampowered.com/app/632360/Risk_of_Rain_2/

- Each Survivor has 3 challenges; completing them unlocks alternate skills for that character
- Items are **discovered once in a run**, then permanently added to the item pool
- Artifacts (gameplay modifiers) unlock via in-game puzzles or hidden areas
- 171 Steam Achievements add completionist targets

### Key Design Insights
- **"Find once, always available"** for items is low-friction — no re-unlocking needed
- **Character-specific challenges** give each character a personal progression arc
- **Discovery model** makes every run potentially meaningful (new item could drop)

---

## 7. Godot Asset Library — Relevant Plugins

**Source:** https://godotengine.org/asset-library/asset?filter=achievement

| Plugin | Version | Godot | Author | License |
|---|---|---|---|---|
| Achievement System | 3.0.1 | 4.4 | 5FB5 | MIT |
| Milestone - Achievements Made Easy | 1.2.0.beta | 4.6 | Jelo | MIT |
| Chief Mints - Achievements | 2.0.0 | 4.5 | samsarette | MIT |
| Achievements Manager | 1.0.2 | 4.2 | Rubonnek | MIT |
| GodotParadiseAchievements | 1.0.1 | 4.1 | BananaHolograma | MIT |
| GodotParadiseAchievements-CSharp | 1.0.1 | 4.1 | BananaHolograma | MIT |

**Save/Persistence plugins** (supporting infrastructure):

| Plugin | Godot | Notes |
|---|---|---|
| Game State Saver Plugin | 4.2 | Manage and persist game state |
| Locker - Saver, loader and storage manager | 4.3 | Unified save/storage interface |
| Save Made Easy | 4.1 / 3.5 | Simple/diverse save-load |
| KSaver | 4.2 | Streamlined save |

**Note:** The game already has a working `PersistManager` with save/load functionality. External plugins are optional scaffolding, not requirements.

---

## 8. Design Principles Summary

| Principle | Description |
|---|---|
| Early Wins, Late Mastery | First unlocks achievable in 1–3 hours; powerful items at 20+ hours |
| Variety Over Linear Power | Unlocks expand options, not just raw power |
| Condition Clarity | Players always know what they're working toward |
| Multiple Parallel Tracks | Something progressing in every session, even after failure |
| Failure as Progress | Kill counts, currency — dead runs still matter |
| Don't Gate Core Gameplay | Starting loadout must be functional and interesting |
| Rarity Signals Value | Tier rarity tells players which items are endgame content |
| Avoid Currency Overload | Either 1 currency or clearly separated currencies |
