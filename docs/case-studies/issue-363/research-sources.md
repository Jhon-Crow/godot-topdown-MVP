# Research Sources and References

This document catalogs all external sources and references used for the case study analysis.

## Primary Sources

### GDC Presentations

1. **F.E.A.R. AI Presentation (2006)**
   - **Title**: "Three States and a Plan: The AI of F.E.A.R."
   - **Author**: Jeff Orkin, Monolith Productions
   - **GDC Vault**: https://gdcvault.com/play/1013282/Three-States-and-a-Plan
   - **PDF Paper**: https://www.gamedevs.org/uploads/three-states-plan-ai-of-fear.pdf
   - **Internet Archive**: https://archive.org/details/GDC2006Orkin
   - **Key Insights**:
     - GOAP architecture for game AI
     - Grenade flushing behavior
     - Suppression fire and cover tactics
     - 3-state FSM combined with GOAP planning

2. **Killzone AI Presentation**
   - **Title**: "Killzone's AI: Dynamic Procedural Combat Tactics"
   - **Author**: Remco Straatman, Guerrilla Games
   - **PDF**: http://cse.unl.edu/~choueiry/Documents/straatman_remco_killzone_ai.pdf
   - **Key Insights**:
     - Position evaluation for grenade attacks
     - Indirect fire reasoning
     - Cover analysis and suppression integration

3. **Terrain Reasoning for Tactical AI**
   - **Title**: "Situational Awareness: Terrain Reasoning for Tactical Shooter AI"
   - **GDC Vault**: https://gdcvault.com/play/1015718/Situational-Awareness-Terrain-Reasoning-for
   - **Key Insights**:
     - Terrain analysis for tactical decisions
     - Position picking for grenade attacks

## Academic and Technical Papers

### GOAP Architecture

1. **GOAP Overview by Nordeus**
   - **URL**: https://engineering.nordeus.com/https-www-youtube-com-watch-v-d8nrhltca9y/
   - **Content**: Technical breakdown of F.E.A.R.'s AI system

2. **NPC AI with GOAP Series**
   - **Author**: Pankaj Basnal
   - **Part 1**: https://pankajbasnal17.medium.com/npc-ai-with-goap-1-understanding-and-approach-908312ba7067
   - **Content**: GOAP fundamentals and approach

3. **GOBT: Synergistic Approach**
   - **URL**: https://www.jmis.org/archive/view_article?pid=jmis-10-4-321
   - **Content**: Combining GOAP with Behavior Trees and Utility AI

### Behavior Trees

1. **Behavior Trees for AI: How They Work**
   - **URL**: https://www.gamedeveloper.com/programming/behavior-trees-for-ai-how-they-work
   - **Key Insights**:
     - Modular design patterns
     - Reactive behavior implementation
     - Tree traversal and caching

2. **Hierarchical MP Bot System (Guerrilla Games)**
   - **PDF**: https://www.guerrilla-games.com/media/News/Files/VUA07_Verweij_Hierarchically-Layered-MP-Bot_System.pdf
   - **Content**: Multi-layer AI decision making

## Godot Engine Resources

### Official Documentation

1. **Creating the Enemy - Godot Docs**
   - **URL**: https://docs.godotengine.org/en/stable/getting_started/first_2d_game/04.creating_the_enemy.html
   - **Content**: Basic enemy AI creation

2. **FPS Tutorial Part 5 (Grenades)**
   - **URL**: https://docs.godotengine.org/en/3.0/tutorials/3d/fps_tutorial/part_five.html
   - **Content**: 3D grenade implementation basics

### Community Resources

1. **Godot Behavior Tree Demo**
   - **GitHub**: https://github.com/jhlothamer/behavior_tree_enemy_ai_demo
   - **Content**: Example behavior tree implementation in Godot

2. **Implementing Simple AI in Godot**
   - **URL**: https://robbert.rocks/implementing-a-simple-ai-for-games-in-godot
   - **Content**: State machine approach for enemy AI

3. **LimboAI**
   - **GitHub**: https://github.com/limbonaut/limboai
   - **Content**: Behavior trees and state machines for Godot 4

4. **Beehave**
   - **GitHub**: https://github.com/bitbrain/beehave
   - **Content**: Behavior tree implementation for Godot

### Godot Forums Discussions

1. **How to Throw a Grenade**
   - **URL**: https://godotforums.org/d/27109-how-to-throw-a-grenade
   - **Content**: Basic grenade throwing mechanics

2. **Grenade Trajectory Coding**
   - **URL**: https://godotforums.org/d/34759-how-do-i-code-the-trajectory-for-throwing-grenades
   - **Content**: Physics equations for grenade arcs

3. **Godot Proposals - Behavior Trees**
   - **URL**: https://github.com/godotengine/godot-proposals/issues/281
   - **Content**: Built-in behavior tree functionality discussion

## Game-Specific AI Analysis

### F.E.A.R.

1. **F.E.A.R. Wikipedia**
   - **URL**: https://en.wikipedia.org/wiki/F.E.A.R._(video_game)
   - **Content**: Overview of AI capabilities

2. **N6A3 Fragmentation Grenade (F.E.A.R. Wiki)**
   - **URL**: https://fear.fandom.com/wiki/N6A3_Fragmentation_Grenade
   - **Content**: In-game grenade mechanics

3. **Flashbang Grenade (F.E.A.R. Wiki)**
   - **URL**: https://fear.fandom.com/wiki/Flashbang_Grenade
   - **Content**: Flashbang effects and usage

### Other Games

1. **S.T.A.L.K.E.R. AI Grenade Discussion**
   - **URL**: https://www.moddb.com/mods/stalker-misery/forum/thread/has-anybody-found-an-edit-to-make-it-so-the-ai-doesnt-throw-grenades-all-the-time-with-perfect-precision
   - **Content**: Community discussion on AI grenade accuracy

2. **Ready or Not - SWAT AI Guide**
   - **URL**: https://steamcommunity.com/sharedfiles/filedetails/?id=3494083514
   - **Content**: Tactical AI grenade usage patterns

3. **Counter-Strike Flashbang Guide**
   - **URL**: https://www.strafe.com/news/read/counter-strike-flashbang-guide-blind-your-enemies-effectively/
   - **Content**: Flashbang mechanics and strategies

## AI Research Papers

1. **Human-like Bots for Tactical Shooters**
   - **URL**: https://arxiv.org/html/2501.00078v1
   - **Content**: Neural network-based tactical AI including grenade handling

2. **Game AI Planning: GOAP, Utility, and Behavior Trees**
   - **URL**: https://tonogameconsultants.com/game-ai-planning/
   - **Content**: Comparison of AI planning approaches

## Development Blogs

1. **Implementing GOAP For AI Agents**
   - **Author**: William Box
   - **URL**: https://wpbox.dev/2025/05/02/implementing-goap-for-ai-agents/
   - **Content**: Modern GOAP implementation guide

2. **GOAP and Utility AI in Grab n' Throw**
   - **URL**: https://goldensyrupgames.com/blog/2024-05-04-grab-n-throw-utility-goap-ai/
   - **Content**: Combining GOAP with Utility AI

3. **Rediscovering Behavior Trees**
   - **URL**: https://www.wayline.io/blog/rediscovering-behavior-trees-ai-tool
   - **Content**: Modern applications of behavior trees

4. **Tech Combat Design: Enemy AI & Behavior Trees**
   - **URL**: https://gerlogu.com/game-design/tech-combat-design-enemy-ai-behavior-trees/
   - **Content**: Combat design patterns

## Video Tutorials

1. **LlamaCademy AI Series Part 48**
   - **GitHub**: https://github.com/llamacademy/ai-series-part-48
   - **Content**: Full enemy AI implementation with behavior trees

2. **Survival Game - Behavior Trees & AI Senses**
   - **URL**: https://www.tomlooman.com/unreal-engine-cpp-survival-sample-game/section-three/
   - **Content**: Unreal Engine AI implementation (conceptually applicable)

## Asset Store References

1. **GOAP for Unity**
   - **URL**: https://assetstore.unity.com/packages/tools/behavior-ai/goap-252687
   - **Content**: Commercial GOAP implementation (for comparison)

2. **Tactical Shooter AI (Unity)**
   - **URL**: https://unityassets4free.com/tactical-shooter-ai/
   - **Content**: Tactical AI patterns including grenades

## Courses

1. **Goal-Oriented Action Planning - Advanced AI For Games (Udemy)**
   - **URL**: https://www.udemy.com/course/ai_with_goap/
   - **Content**: Comprehensive GOAP course

---

## Key Takeaways from Research

### F.E.A.R. AI Best Practices
1. Use GOAP for flexible, emergent combat behavior
2. Grenades are for flushing players from cover
3. Combine grenades with flanking for maximum effectiveness
4. AI should respond to player suppression with counter-tactics

### Grenade Decision Triggers (Industry Standard)
1. Player in prolonged cover position
2. Sound-based targeting (reload, footsteps)
3. Teammate deaths witnessed
4. Low health desperation
5. Suppression counter-attack
6. Area denial

### Implementation Patterns
1. GOAP actions with dynamic costs based on situation
2. World state variables tracking trigger conditions
3. Sound propagation for audio-based decisions
4. Vision and memory systems for position tracking

### Common Pitfalls to Avoid
1. AI grenades too accurate (no randomness)
2. Grenades thrown too frequently (feels unfair)
3. No cooldown between grenade throws
4. Ignoring line-of-sight for throwing
5. Not considering friendly fire

---

## Online Research Session (2026-01-25)

### Key F.E.A.R. AI Findings

#### The Illusion of Coordination
According to the GDC presentation and technical analysis:
> "None of the enemy AI in F.E.A.R. know that each other exists and cooperative behaviors are simply two AI characters being given goals that line up nicely to create what look like coordinated behaviors when executed."

This is relevant for our grenade implementation - enemies don't need to explicitly coordinate grenade throws. Each enemy evaluates their own trigger conditions and throws independently, but this creates emergent tactical behavior.

#### Emergent Flanking as Side Effect
> "Imagine a situation where the player has invalidated one of the A.I.'s cover positions, and a squad behavior orders the A.I. to move to the valid cover position. If there is some obstacle in the level, like a solid wall, the A.I. may take a back route and resurface on the player's side. It appears that the A.I. is flanking, but in fact this is just a side effect of moving to the only available valid cover."

Our grenade throwing can follow a similar pattern - the grenade throw appears coordinated with flanking, but is actually just each AI following simple rules.

#### Real-Time Response Architecture
> "Because of this, the AI is constantly changing its plan based upon what the player is doing—if the player throws a grenade, the NPCs will flee; if the player is being very aggressive, they'll be defensive; if the player is hiding, they'll be offensive and try to flush him out."

This aligns perfectly with Issue #363's trigger conditions - the grenade throws are reactive to player behavior (hiding, suppressing, etc.).

### GOAP Grenade Action Design Principles

1. **Throw Action**: "Why shoot if you can blow them up with a grenade" - Grenades are a high-priority action when conditions are met
2. **PreConditions**: "Not all actions are possible all the time - for example, agents can't open a door which is already open. To handle these conditions, PreConditions are evaluated before simulating the action."
3. **Dynamic Costs**: GOAP actions have varying costs based on world state, allowing grenades to become more attractive when trigger conditions are met

### F.E.A.R. Legacy Impact
> "F.E.A.R.'s use of Goal Oriented Action Planning is still held to this day as some of the most exciting and fun enemy opponents in modern video games. GOAP has continued to have a lasting impact within the video games industry, with games like Condemned Criminal Origins, S.T.A.L.K.E.R.: Shadow of Chernobyl, Just Cause 2, Deus Ex Human Revolution, the 2013 reboot of Tomb Raider, and Monolith's Middle-Earth: Shadow of Mordor and Shadow of War adopting the methodology."

### Sources from Web Research
- [Building the AI of F.E.A.R. with Goal Oriented Action Planning](https://www.gamedeveloper.com/design/building-the-ai-of-f-e-a-r-with-goal-oriented-action-planning)
- [Paper Insight: The A.I. of F.E.A.R. (Nordeus Engineering)](https://engineering.nordeus.com/https-www-youtube-com-watch-v-d8nrhltca9y/)
- [Implementing GOAP For AI Agents (2025)](https://wpbox.dev/2025/05/02/implementing-goap-for-ai-agents/)
- [GOAP and Utility AI in Grab n' Throw (2024)](https://goldensyrupgames.com/blog/2024-05-04-grab-n-throw-utility-goap-ai/)
- [Game AI Planning: GOAP, Utility, and Behavior Trees](https://tonogameconsultants.com/game-ai-planning/)
- [GDC Vault - Three States and a Plan: The AI of F.E.A.R.](https://gdcvault.com/play/1013282/Three-States-and-a-Plan)
- [GDC Vault - Goal-Oriented Action Planning: Ten Years Old and No Fear!](https://gdcvault.com/play/1022020/Goal-Oriented-Action-Planning-Ten)
