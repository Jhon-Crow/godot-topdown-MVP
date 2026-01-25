# Research Sources - Issue #379: Suspicion-Based Grenade Throwing

This document catalogs all external sources and references used for the case study analysis.

## Primary Sources

### GDC and Industry Presentations

1. **F.E.A.R. AI Presentation (2006)**
   - **Title**: "Three States and a Plan: The AI of F.E.A.R."
   - **Author**: Jeff Orkin, Monolith Productions
   - **GDC Vault**: https://gdcvault.com/play/1013282/Three-States-and-a-Plan
   - **PDF Paper**: https://www.gamedevs.org/uploads/three-states-plan-ai-of-fear.pdf
   - **Key Insight**: "if the player is hiding, they'll be offensive and try to flush him out"

2. **Building the AI of F.E.A.R. with Goal Oriented Action Planning**
   - **URL**: https://www.gamedeveloper.com/design/building-the-ai-of-f-e-a-r-with-goal-oriented-action-planning
   - **Key Quote**: "The AI throws grenades at a position where they last saw the player, which gives a reasonable feeling of planning by the AI"

### Stealth Game AI Research

3. **The Predictable Problem: Why Stealth Game AI Needs an Overhaul**
   - **URL**: https://www.wayline.io/blog/predictable-problem-stealth-game-ai-overhaul
   - **Key Insight**: FSM-based AI transitions from "patrolling" to "alert" to "attack" based on suspicion thresholds

4. **Stealth Design Part 2 - AI States**
   - **URL**: https://www.gamedesigndiary.co.uk/post/design-stealth-part-2-ai-behaviours
   - **Key Insight**: AI states progression from "unaware" → "suspicious" → "casual search" → "aggressive search" → "combat"

5. **How do stealth games work? What goes on in the AI of an enemy?**
   - **URL**: https://www.quora.com/How-do-stealth-games-work-What-goes-on-in-the-AI-of-an-enemy
   - **Key Insight**: "Question Mark (Suspicion)" vs "Exclamation Mark (Alert)" state distinction

### Academic Papers

6. **Dynamic Guard Patrol in Stealth Games**
   - **URL**: https://ojs.aaai.org/index.php/AIIDE/article/download/7425/7308/10903
   - **Topic**: Probability-based tracking after player detection

7. **Human-like Bots for Tactical Shooters Using Compute-Efficient Sensors**
   - **URL**: https://arxiv.org/html/2501.00078v1
   - **Topic**: Modern tactical shooter AI including grenade handling

### Game AI Planning Resources

8. **Game AI Planning: GOAP, Utility, and Behavior Trees**
   - **URL**: https://tonogameconsultants.com/game-ai-planning/
   - **Key Insight**: "GOAP is best for adaptive combat or dynamic NPCs"

9. **NPC AI with GOAP - Understanding and Approach**
   - **URL**: https://pankajbasnal17.medium.com/npc-ai-with-goap-1-understanding-and-approach-908312ba7067
   - **Topic**: GOAP fundamentals for NPC decision making

10. **Goal-Oriented Action Planning - Vedant Chaudhari**
    - **URL**: https://medium.com/@vedantchaudhari/goal-oriented-action-planning-34035ed40d0b
    - **Key Insight**: "GOAP was developed by Jeff Orkin in the early 2000's while working on the AI system for F.E.A.R."

### Tactical AI Behavior Patterns

11. **AI: Keys to Believable Enemies**
    - **URL**: https://gdkeys.com/ai-keys-to-believable-enemies/
    - **Key Insight**: "when the player is under-cover for a long time, enemies may want to flank the player or throw a grenade to nullify the cover possibility"

12. **Top 10 Video Games with the Best Enemy AI**
    - **URL**: https://books.twu.ca/isabella/chapter/top-10-video-games-with-the-best-enemy-ai/
    - **Key Insight**: Halo AI "use cover very wisely, and employ suppressing fire and grenades"

13. **Artificial Intelligence in Video Games - Wikipedia**
    - **URL**: https://en.wikipedia.org/wiki/Artificial_intelligence_in_video_games
    - **Key Quote**: "AI is capable of performing flanking maneuvers, using suppressing fire, throwing grenades to flush the player out of cover"

### Stealth Game Mechanics

14. **Hide Effectively in Stealth Games**
    - **URL**: https://xboxplay.games/stealth-exploration/how-to-hide-effectively-in-stealth-games-69899
    - **Key Insight**: "Most AI follows a scripted search pattern where the first step is to go to the player's last known position"

15. **How does AI in stealth games adapt to player behavior?**
    - **URL**: https://m.umu.com/ask/a11122301573853809256
    - **Topic**: AI adaptation to repeated player tactics

---

## Key Takeaways for Implementation

### Suspicion-to-Attack Pattern (Industry Standard)

From F.E.A.R. and modern stealth games:

1. **Suspicion Threshold**: When confidence about player location exceeds threshold (typically 0.7-0.9)
2. **Investigation Phase**: AI moves toward suspected position cautiously
3. **Attack Decision**: If player not found but suspicion remains high, escalate to aggressive action
4. **Flush Tactics**: Use grenades/explosives to force player out of suspected cover
5. **Follow-up Assault**: Immediately move in after flush attempt

### Grenade Decision Logic (F.E.A.R. Model)

From multiple sources about F.E.A.R.'s AI:

> "The AI throws grenades at a position where they last saw the player"

This directly supports the requested feature:
- Use `suspected_position` from memory system
- Require high confidence (≥0.8 matches "strongly suspects")
- Player must not be visible (grenade is for unseen targets)
- Follow up with assault behavior

### Confidence Threshold Selection

Based on existing thresholds in `EnemyMemory`:
- `HIGH_CONFIDENCE_THRESHOLD = 0.8` - Already defined, matches "strongly suspects"

The 0.8 threshold is appropriate because:
- 1.0 = Visual contact (no need to throw grenade, can shoot)
- 0.8 = Very recent visual or high-quality information
- 0.7 = Sound of gunshot (slightly below threshold)
- 0.6 = Reload/empty click sound (significantly below threshold)

### Time Delay Rationale

Adding a 3-second delay before triggering:
- Prevents immediate grenade on losing sight
- Gives player time to relocate
- Creates tactical tension
- Matches F.E.A.R.'s delayed response pattern

### Post-Grenade Assault Behavior

From tactical shooter best practices:
- Grenades are for **flushing**, not killing
- Enemy should immediately advance after throw
- ASSAULT state provides cover-to-cover movement toward target
- Creates pressure on player who survived the grenade

---

## Existing Codebase References

### Enemy Memory System
- **File**: `scripts/ai/enemy_memory.gd`
- **Key Methods**: `is_high_confidence()`, `has_target()`, `suspected_position`

### Grenade System
- **File**: `scripts/objects/enemy.gd` (lines 5130-5710)
- **Key Functions**: `_update_grenade_triggers()`, `_should_trigger_*_grenade()`, `try_throw_grenade()`

### Related Case Studies
- `docs/case-studies/issue-363/` - Original grenade system design
- `docs/case-studies/issue-375/` - Grenade self-damage prevention

---

*Research compiled: 2026-01-25*
