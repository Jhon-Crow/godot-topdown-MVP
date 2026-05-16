# Case Study: Issue #1182 — Unlock System Proposal

> **Issue title (RU):** предложи систему анлоков
> **Issue title (EN):** Propose an unlock system
> **Author:** Jhon-Crow
> **Status:** Open

## Summary

Many items have been added to the game. The task is to propose conditions for unlocking them, or a suitable system for gradually unlocking increasingly powerful equipment.

## Table of Contents

1. [Current State of the Game](#1-current-state-of-the-game)
2. [Item Inventory](#2-item-inventory)
3. [Current Unlock System Analysis](#3-current-unlock-system-analysis)
4. [Gap Analysis — Items Without Unlock Conditions](#4-gap-analysis--items-without-unlock-conditions)
5. [Inspiration From Other Games](#5-inspiration-from-other-games)
6. [Available Godot Tools and Plugins](#6-available-godot-tools-and-plugins)
7. [Proposed Solutions](#7-proposed-solutions)
8. [Recommended Approach](#8-recommended-approach)
9. [Implementation Roadmap](#9-implementation-roadmap)

---

## 1. Current State of the Game

The game is a **Godot 4 top-down tactical shooter** with:
- Multiple distinct levels (Labyrinth, Building, Beach, Docks, Castle, Polygon/TestTier, Double Corridor/RevolverLevel)
- A **rank system** per level: F → D → C → B → A → A+ → S
- An **Armory menu** where players choose weapons, grenades, and active items before each level
- A **roguelike mode** where items can be found on treasure pedestals between rooms
- An existing **UnlockManager** singleton (`/scripts/autoload/unlock_manager.gd`) that gates items behind level completion ranks
- Persistent unlock state via **PersistManager**

See [current-unlock-table.md](current-unlock-table.md) for the full item inventory and current unlock status.

---

## 2. Item Inventory

See [current-unlock-table.md](current-unlock-table.md) for full details.

**Summary counts:**

| Category | Total | Already Unlocked (free) | Condition-gated | No condition yet |
|---|---|---|---|---|
| Weapons | 8 | 4 (makarov_pm, m16, silenced_pistol, ak_gl) | 4 (shotgun, mini_uzi, sniper, revolver) | 1 (`smg` — "coming soon") |
| Grenades | 4 | 2 (flashbang, aggression_gas) | 2 (frag, defensive) | 0 |
| Active Items | 17 | 13 | 4 (flashlight, homing_bullets, teleport_bracers, invisibility_suit) | 0 |

**Key finding:** The existing unlock system already covers most items. The 13 "always available" active items and 2 "always available" weapons have no unlock conditions. These are candidates for adding unlock conditions to create a more gradual progression experience.

---

## 3. Current Unlock System Analysis

### Architecture

The system is well-structured and extensible:

```
ProgressManager (tracks best rank per level/difficulty)
    ↓  signals: progress_updated
UnlockManager (evaluates conditions; highlights gold slots in armory)
    ↓  holds LMB on gold slot
GameManager / ActiveItemManager / GrenadeManager (stores unlocked state)
    ↓  persisted by
PersistManager (saves/loads unlock state to disk)
```

### Existing Unlock Conditions

| Condition | Min Rank | Unlocks |
|---|---|---|
| Labyrinth | D | mini_uzi |
| Building | D | shotgun, Frag grenade |
| Building | S | silenced_pistol |
| Polygon (TestTier) | D | sniper, Flashlight |
| Castle | F (any) | revolver |
| Double Corridor (RevolverLevel) | D | Teleport Bracers |
| Beach | D | ak_gl |
| Beach | S | Defensive grenade (F-1) |
| Docks | D | silenced_pistol (duplicate) |
| Beach S + Building S | S both | Invisibility Suit |
| 5× S-ranks (all major levels) | S all | Homing Bullets |

### Strengths of Current System
1. Clear, readable `UNLOCK_CONDITIONS` dictionary — easy to extend
2. Supports both single-level and multi-level conditions
3. Rank-gated (not just completion) — rewards skill
4. Respects save integrity (reset + reapply on startup)
5. Gold highlighting in armory guides players
6. Signals allow decoupled UI reactions

### Weaknesses / Gaps
1. **13 active items are freely available from the start** — no sense of discovery or earned reward
2. **No kill-count or cumulative conditions** — all conditions are level-rank-based
3. **No in-roguelike progression** — finding items on pedestals doesn't permanently unlock them in the armory
4. **No hints** on what action unlocks a locked item (player must discover organically)
5. **Single condition type** — only "complete level at rank X"
6. **No tiered difficulty** for "weak → strong" power ramp

---

## 4. Gap Analysis — Items Without Unlock Conditions

These 13 active items are "freely available from start" with no unlock gatekeeping:

| Item | Power Level (subjective) | Suggested Tier |
|---|---|---|
| BFF Pendant | Medium (summon ally) | Early |
| Breaker Bullets | Low (passive AoE) | Early |
| Force Field | High (100% reflect) | Mid |
| Trajectory Glasses | Medium (ricochet UI) | Early |
| Laser Sight | Low (QoL) | Starter |
| Extended Magazine | Medium (ammo buff) | Early |
| Loudspeaker | Medium (pacify) | Early |
| Breaching Charges | High (wall breach) | Mid |
| Armored Skin | High (+HP, shards) | Mid |
| Auto-Reload | Medium (kill reward) | Early |
| Drilling Bullets | High (wall pierce) | Mid |
| Recoil Compensator | Medium (accuracy buff) | Early |
| Combat Disposition | High (damage risk/reward) | Late |

---

## 5. Inspiration From Other Games

See [external-research.md](external-research.md) for full research.

### Key Patterns Observed

| Game | Unlock Type | Applicability to This Game |
|---|---|---|
| Dead Cells | Blueprint drop → spend Cells | High: 2-stage (find + spend) fits roguelike mode |
| Binding of Isaac | Achievement-based (specific feats) | High: memorable condition stories |
| Hades | Multiple currencies, Mirror upgrades | Medium: complex, rewards long play |
| Enter the Gungeon | NPC rescue → item pool addition | Low: requires new NPC system |
| Nuclear Throne | Zone reach / feat-based | Medium: single milestone conditions |
| Risk of Rain 2 | Challenge completion per character | Medium: challenge definitions needed |

### Most Applicable Patterns for This Game

1. **Level-rank unlock** (already implemented) — extend to more items
2. **Kill-count unlock** — track cumulative kills across sessions
3. **Specific-feat unlock** — "complete level without grenades", "get S-rank with pistol only"
4. **Roguelike discovery unlock** — finding an item in roguelike mode unlocks it permanently in armory
5. **Multi-level compound condition** — already implemented for Homing Bullets and Invisibility Suit

---

## 6. Available Godot Tools and Plugins

The game already has all required infrastructure. No external plugins are strictly necessary.

**Existing infrastructure that can be extended:**
- `UnlockManager` — add new condition types alongside the existing rank-based system
- `PersistManager` — already saves/loads unlock state
- `GameManager.kills` — kill counter already exists (session-only; needs cross-session accumulation)
- `ProgressManager` — already tracks best ranks

**Godot Asset Library options (if desired):**

| Plugin | Godot | Notes |
|---|---|---|
| Achievement System v3.0.1 by 5FB5 | 4.4 | Full achievement framework, MIT |
| Milestone - Achievements Made Easy v1.2.0 by Jelo | 4.6 | Lightweight, MIT |
| GodotParadiseAchievements-CSharp by BananaHolograma | 4.1 | C# version for mixed projects |

These can serve as scaffolding for the condition-evaluation layer but are not required given the existing `UnlockManager`.

---

## 7. Proposed Solutions

### Solution A: Extend Level-Rank Conditions (Lowest Effort, High Value)

**Summary:** Add rank-based unlock conditions to the 13 "always available" active items using the existing `UNLOCK_CONDITIONS` dictionary. No new system needed.

**Proposed mapping:**

| Item | Unlock Condition | Rationale |
|---|---|---|
| Laser Sight | Labyrinth D | First level, QoL reward |
| Trajectory Glasses | Beach D | Ricochet-heavy open maps |
| BFF Pendant | Docks D | "Find a friend" in the docks |
| Breaker Bullets | Building D | Indoors bullets-hitting-walls level |
| Extended Magazine | Castle D | Castle enemies are tough — reward survivability |
| Loudspeaker | Labyrinth S | Mastery reward for stealth-friendly level |
| Auto-Reload | Building S | Reward kill efficiency in tight rooms |
| Recoil Compensator | Docks S | Reward precision at range |
| Force Field | Beach S + Castle D | Combining outdoor and castle mastery |
| Armored Skin | Castle S | Ultimate tank reward |
| Breaching Charges | Double Corridor S | Mastery of the corridor-heavy level |
| Drilling Bullets | Polygon (TestTier) S | Reward for the "shooting test" level |
| Combat Disposition | All levels A+ or higher | Ultimate challenge reward |

**Pros:** No new code. Immediately implementable in `unlock_manager.gd`. Consistent with existing UX.
**Cons:** Same condition type as all existing conditions — less variety, less memorable.

---

### Solution B: Add Kill-Count Unlock Conditions (Medium Effort, High Variety)

**Summary:** Add a `kill_count` condition type to `UnlockManager` that checks cumulative enemy kills tracked in a persistent `lifetime_kills` variable in `PersistManager`.

**How it works:**
1. `PersistManager` adds a `lifetime_kills: int` variable (persisted to disk)
2. `GameManager.register_kill()` increments both `kills` (session) and `PersistManager.lifetime_kills` (persistent)
3. `UnlockManager` gains a new method `_check_kill_count_condition(required: int) -> bool` that reads `PersistManager.lifetime_kills`
4. A new `KILL_COUNT_UNLOCK_CONDITIONS` dictionary in `UnlockManager` lists items with their required kill counts

**Example conditions:**

| Item | Kill Count Required | Notes |
|---|---|---|
| Laser Sight | 10 kills | Near-instant first reward |
| Trajectory Glasses | 30 kills | After 2–3 sessions |
| BFF Pendant | 50 kills | "You've earned a friend" |
| Breaker Bullets | 75 kills | Passive reward for sustained play |
| Extended Magazine | 100 kills | Full session milestone |
| Loudspeaker | 150 kills | Pacifist option as late alternative |
| Auto-Reload | 200 kills | Kill-efficiency reward for killers |
| Recoil Compensator | 300 kills | Mid-progression weapon skill |
| Breaching Charges | 400 kills | Advanced tactical tool |
| Force Field | 500 kills | Major survivability tool |
| Armored Skin | 600 kills | Tank build enabler |
| Drilling Bullets | 750 kills | Advanced offense tool |
| Combat Disposition | 1000 kills | Endgame high-risk/high-reward item |

**Pros:** Rewards all play styles (not just S-rank players). Clear progress ("73/100 kills to unlock Extended Magazine"). Failure-as-progress — dead runs still count.
**Cons:** Requires new persistent state and new condition logic (small code addition).

**Code sketch:**

```gdscript
# In PersistManager — add to save/load
var lifetime_kills: int = 0

# In GameManager.register_kill()
var pm = get_node_or_null("/root/PersistManager")
if pm:
    pm.lifetime_kills += 1

# In UnlockManager — new condition dict
const KILL_COUNT_CONDITIONS: Dictionary = {
    "laser_sight": {"type": "kill_count", "kills": 10, "active_items": [ActiveItemType.LASER_SIGHT]},
    "trajectory_glasses": {"type": "kill_count", "kills": 30, "active_items": [ActiveItemType.TRAJECTORY_GLASSES]},
    # ... etc
}

func _is_kill_count_condition_met(required_kills: int) -> bool:
    var pm = get_node_or_null("/root/PersistManager")
    return pm != null and pm.lifetime_kills >= required_kills
```

---

### Solution C: Roguelike Discovery Unlocks (Medium Effort, High Engagement)

**Summary:** When a player picks up an item from a treasure pedestal in roguelike mode, that item is **permanently unlocked** in the armory (if it was previously locked). This mirrors Risk of Rain 2's "find once, always available" model.

**How it works:**
1. In `roguelike_level.gd`, when `_collect_pedestal_item()` is called:
   - If the item was locked, call `GameManager.unlock_weapon()` / `ActiveItemManager.unlock_active_item()` / `GrenadeManager.unlock_grenade()`
   - Show a "UNLOCKED!" notification overlay
   - The item is now available in the armory for all future runs

**Design decision:** Items that are currently freely available in the armory would not appear on pedestals (they're already available). Only locked items can appear as pedestal discoveries. Once found, they graduate from "roguelike-only" to "armory-available."

**Pros:** Natural discovery loop perfectly suited to the roguelike mode. Extremely motivating — every run has potential unlocks.
**Cons:** Requires careful thought about which items can appear on pedestals when locked. The current pedestal system only offers `is_weapon_unlocked()` items — inverting this for discovery unlocks needs logic adjustment.

---

### Solution D: Specific-Feat / Achievement-Style Conditions (High Effort, Most Memorable)

**Summary:** Add feat-based unlock conditions, each tied to a memorable in-game challenge.

**Example conditions:**

| Item | Condition | How Tracked |
|---|---|---|
| Combat Disposition | Complete any level with 100% accuracy | `shots_fired == hits_landed` at level end |
| Force Field | Get hit 0 times in a level (no-damage run) | New `damage_taken_this_level: int` stat |
| Armored Skin | Survive with 1 HP for 30 seconds | New `low_hp_survival_timer` |
| Breaching Charges | Kill 3 enemies with a single grenade | New `grenade_multikill` tracking |
| Drilling Bullets | Kill an enemy through 2 walls | New `through_wall_kills` counter |
| Auto-Reload | Complete a level after killing 10 enemies without reloading | Magazine-depletion tracking |

**Pros:** Each unlock has a memorable story. Players will remember how they earned Combat Disposition. Creates satisfying skill-expression challenges.
**Cons:** Significant new stat tracking required. More implementation work per condition.

---

### Solution E: Power Tier System (Structural Change)

**Summary:** Reorganize all items into 3 tiers. Tier 1 items are available from the start. Tier 2 requires completing any level at D+. Tier 3 requires reaching S-rank on specific levels. This is the most dramatic structural change.

**Tiers:**

| Tier | Gate | Items |
|---|---|---|
| 0 (Starter) | Always | makarov_pm, flashbang, laser_sight |
| 1 (Early) | Any level D+ | m16, silenced_pistol, trajectory_glasses, BFF pendant, breaker bullets, extended magazine, auto-reload, aggression_gas, recoil_compensator, loudspeaker |
| 2 (Mid) | Specific level D+ (as today) | shotgun, mini_uzi, sniper, revolver, ak_gl, frag grenade, armored skin, breaching charges, force field, teleport bracers, flashlight, drilling bullets, defensive grenade |
| 3 (Late) | S-rank conditions (as today) | invisibility_suit, homing_bullets, combat_disposition |

**Pros:** Clear power ramp. Beginner players are not overwhelmed by choice.
**Cons:** Removes items from players who already have them. Retrograde change to current "freely available" items would frustrate existing players.

---

## 8. Recommended Approach

The **recommended approach is a combination of Solutions A and B**, with Solution C as an optional enhancement for the roguelike mode:

### Phase 1: Assign Level-Rank Conditions to Currently Free Active Items (Solution A)
Immediately implementable with no new code. Add unlock conditions to the 13 always-available active items in `UNLOCK_CONDITIONS` / `MULTI_UNLOCK_CONDITIONS` in `unlock_manager.gd`.

### Phase 2: Add Kill-Count Conditions for Early Accessibility (Solution B)
Add a `lifetime_kills` persistent counter. Use kill-count as an **alternative** path to unlock items — players who struggle with ranks can still unlock things by playing more. This is the "failure-as-progress" principle.

### Phase 3: Roguelike Discovery Unlocks (Solution C) — Optional
Allow finding locked items on pedestals to permanently unlock them in the armory. This creates a powerful motivation loop for the roguelike mode.

### Suggested Unlock Progression (Combined)

| Step | What Unlocks | Condition | Type |
|---|---|---|---|
| 1 | Laser Sight | Labyrinth D OR 10 kills | Level-rank / Kill-count |
| 2 | Trajectory Glasses | Beach D OR 30 kills | Level-rank / Kill-count |
| 3 | BFF Pendant | Docks D OR 50 kills | Level-rank / Kill-count |
| 4 | Breaker Bullets | Building D (already unlocks shotgun too) OR 75 kills | Level-rank / Kill-count |
| 5 | Extended Magazine | Castle D OR 100 kills | Level-rank / Kill-count |
| 6 | Loudspeaker | Labyrinth S OR 150 kills | Level-rank / Kill-count |
| 7 | Auto-Reload | Building S OR 200 kills | Level-rank / Kill-count |
| 8 | Recoil Compensator | Docks S OR 300 kills | Level-rank / Kill-count |
| 9 | Breaching Charges | Double Corridor S OR 400 kills | Level-rank / Kill-count |
| 10 | Force Field | Beach S + Castle D OR 500 kills | Multi-level / Kill-count |
| 11 | Armored Skin | Castle S OR 600 kills | Level-rank / Kill-count |
| 12 | Drilling Bullets | Polygon S OR 750 kills | Level-rank / Kill-count |
| 13 | Combat Disposition | 5× S-ranks OR 1000 kills | Multi-level / Kill-count |

This creates a **dual-track progression**: skilled players unlock via rank conditions (fast, rewarding), casual players unlock via kill counts (slow, always progressing).

---

## 9. Implementation Roadmap

### Step 1 — Add Level-Rank Conditions (No New Code)

Edit `unlock_manager.gd` → add entries to `UNLOCK_CONDITIONS` and `MULTI_UNLOCK_CONDITIONS` for the 13 active items currently marked `true` in `active_item_manager.gd`.

Update `active_item_manager.gd` → change those 13 items from `true` to `false` in `unlocked_active_items`.

Estimated effort: ~30 minutes. No risk.

### Step 2 — Add lifetime_kills Persistent Counter

1. `persist_manager.gd`: Add `var lifetime_kills: int = 0`, include in save/load
2. `game_manager.gd`: In `register_kill()`, increment `PersistManager.lifetime_kills`
3. `unlock_manager.gd`: Add `KILL_COUNT_CONDITIONS` dictionary + `_is_kill_count_condition_met()` + integrate into `has_any_available_unlock()`, `_on_progress_updated()` equivalent

Estimated effort: ~2 hours.

### Step 3 — Roguelike Discovery Unlocks (Optional)

1. `roguelike_level.gd`: In `_collect_pedestal_item()`, after player picks up locked item → call appropriate `unlock_*` method
2. Show "NEW UNLOCK!" overlay (reuse existing armory gold notification pattern)
3. Optionally: allow locked items to appear on pedestals (modify `_pick_random_pedestal_item()` to include locked items as "discoverable")

Estimated effort: ~3 hours.

### Step 4 — Show Unlock Progress in Armory UI (Optional Polish)

Display kill count progress below locked items: "73 / 100 kills to unlock".

Estimated effort: ~2 hours.

---

*Case study compiled for GitHub Issue #1182 on 2026-03-18.*
