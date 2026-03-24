# Case Study: Issue #1244 — BFF Companion Reaction Speed (2x Slower)

## Issue Summary

**Title:** update BFF
**Reporter:** Jhon-Crow
**Description (RU):** "скорость реакции напарника должна быть в 2 раза медленнее (сейчас зачищает всю карту)."
**Translation:** "The companion's reaction speed should be 2x slower (currently it clears the whole map)."

The BFF companion (summoned via BFF Pendant active item) is too effective — it eliminates all enemies on the map too quickly, removing gameplay challenge.

---

## Root Cause Analysis

### Code Trace

**File:** `scripts/characters/player.gd` — `_summon_bff_companion()` (line ~3360)

The companion is configured with `BFF_REACTION_MULTIPLIER = 1.5` (50% slower, from issue #926):
```gdscript
const BFF_REACTION_MULTIPLIER: float = 1.5
companion.detection_delay = 0.2 * BFF_REACTION_MULTIPLIER       # 0.2s * 1.5 = 0.3s
companion.threat_reaction_delay = 0.2 * BFF_REACTION_MULTIPLIER  # 0.2s * 1.5 = 0.3s
companion.lead_prediction_delay = 0.3 * BFF_REACTION_MULTIPLIER  # 0.3s * 1.5 = 0.45s
```

**File:** `scripts/components/aggression_component.gd` — `process_combat()` (line 49)

The companion's combat AI runs through `AggressionComponent.process_combat()`, which:
1. Does **NOT** check `detection_delay` or `threat_reaction_delay`
2. Uses only `_parent._shoot_timer >= shoot_cooldown` (default: `0.1s`)
3. Fires as fast as the shoot cooldown allows (~10 shots/sec by default)

This means the `detection_delay` parameters set in `_summon_bff_companion()` are **irrelevant** for the companion's `AggressionComponent`-driven combat — it bypasses them entirely.

### Why the Companion Clears the Map

1. `set_aggressive(true)` is called, routing all combat through `AggressionComponent.process_combat`
2. `process_aggression_tick` returns `true` early, bypassing all normal enemy AI with `detection_delay`
3. The companion fires at `shoot_cooldown = 0.1s` (same as enemies) with no reaction delay
4. `_find_nearest_enemy_any()` finds any enemy regardless of LOS, navigating toward them
5. Result: the companion acts like a perfectly-aimed, infinitely-reacting killing machine

### Previous Partial Fix (Issue #926)

Issue #926 set `BFF_REACTION_MULTIPLIER = 1.5` but:
- Only affected `detection_delay`, `threat_reaction_delay`, `lead_prediction_delay`
- These parameters are bypassed by `AggressionComponent.process_combat`
- The `shoot_cooldown` (primary rate-limiter for the companion) was never adjusted

---

## Solution

### Approach: 2x Multiplier on All Reaction Parameters + Shoot Cooldown

The issue explicitly says "2x slower" — change `BFF_REACTION_MULTIPLIER` from `1.5` to `2.0` and also slow down `shoot_cooldown` for the companion.

**Changes in `scripts/characters/player.gd`:**

```gdscript
# Issue #1244: BFF companion has 2x slower reaction speed than enemies.
# Multiply all reaction/detection delays and shoot cooldown by 2.0.
const BFF_REACTION_MULTIPLIER: float = 2.0
companion.detection_delay = 0.2 * BFF_REACTION_MULTIPLIER       # 0.2s * 2.0 = 0.4s
companion.threat_reaction_delay = 0.2 * BFF_REACTION_MULTIPLIER  # 0.2s * 2.0 = 0.4s
companion.lead_prediction_delay = 0.3 * BFF_REACTION_MULTIPLIER  # 0.3s * 2.0 = 0.6s
companion.shoot_cooldown = 0.1 * BFF_REACTION_MULTIPLIER         # 0.1s * 2.0 = 0.2s
```

Adding `shoot_cooldown = 0.1 * 2.0 = 0.2s` is **critical** because:
- `AggressionComponent.process_combat` uses `_parent._shoot_timer >= shoot_cooldown`
- This is the only rate limiter that actually applies to the companion's aggressive AI
- `0.2s` cooldown = 5 shots/sec instead of 10 shots/sec = 2x slower firing rate

---

## Design Context

### Why Companion Should Be Slower

Game balance research ([Uniday Studio](https://www.uniday.studio/blog/37-optimizing-ai-reaction-times-in-game-development), [Game AI Pro](http://www.gameaipro.com/GameAIProOnlineEdition2021/GameAIProOnlineEdition2021_Chapter11_You_had_me_at_AAAAHHH_On_the_importance_of_reactions_in_game_AI.pdf)) indicates:
- Human reaction time is ~250ms baseline; AI characters with faster reactions feel "unfair"
- Companions should feel "helpful" but not "game-breaking" — they enhance player skill rather than replace it
- A companion clearing the entire map trivializes gameplay and removes player agency

### Game AI Reaction Time Industry Standards
- Enemy base detection delay: `0.2s` (in this codebase)
- Companion at 2x: `0.4s` detection delay — perceptibly slower but still functional
- Shoot cooldown at 2x: `0.2s` → 5 shots/sec — significantly less lethal

### Similar Problem Patterns

- **Halo (Bungie):** ODST companions have suppressed accuracy to keep player feeling central
- **XCOM:** Soldier AI companions have strictly limited actions per turn
- **Left 4 Dead (Valve):** AI Director and bot companions tuned to support, not outperform

The pattern is consistent: companions should assist, not replace player combat.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/characters/player.gd` | `BFF_REACTION_MULTIPLIER: 1.5 → 2.0`; add `shoot_cooldown` scaling |
| `tests/unit/test_bff_pendant.gd` | Add tests verifying 2x multiplier values |

---

## References

- [Optimizing AI Reaction Times in Game Development — Uniday Studio](https://www.uniday.studio/blog/37-optimizing-ai-reaction-times-in-game-development)
- [Game AI Pro: On the Importance of Reactions in Game AI](http://www.gameaipro.com/GameAIProOnlineEdition2021/GameAIProOnlineEdition2021_Chapter11_You_had_me_at_AAAAHHH_On_the_importance_of_reactions_in_game_AI.pdf)
- [Shooting cooldown — Godot Forum](https://forum.godotengine.org/t/shooting-cooldown/40032)
- [Building a basic AI in Godot Engine](https://cyberglads.com/making-cyberglads-4-basic-ai.html)
- [Behavior Tree AI for Godot — BrightCoding](https://www.blog.brightcoding.dev/2025/11/25/behavior-tree-ai-for-godot-the-ultimate-guide-to-creating-intelligent-npcs-that-players-actually-remember-2024/)
