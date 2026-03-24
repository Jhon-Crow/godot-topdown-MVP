# Case Study: Issue #1392 — Debug Visualization Overlays Not Visible

## Problem

The following debug visualizations stopped being visible in the game:
1. Search path display (SearchPathMonitor)
2. Cover search display (CoverRaycastMonitor)
3. Navigation mesh display (NavMeshMonitor)
4. Enemy navigation path display (EnemyPathMonitor)

The user reported these features "stopped working" despite the settings being enabled and persisted.

## Timeline

| Date | Event |
|------|-------|
| 2026-03-21 | PR #1278: Added EnemyPathMonitor (layer 10) |
| 2026-03-22 | PR #1286: Fixed SearchPathMonitor/WaypointMonitor _init vs _ready bug |
| 2026-03-23 | PR #1360: Added CoverRaycastMonitor (layer 10) |
| 2026-03-23 | PR #1366: Reorganized experimental menu into categories |
| 2026-03-23 | PR #1382: Backup PR (includes all working features) |
| 2026-03-23 | PR #1381: Refactored Player.cs into partial classes |
| 2026-03-23 | PR #1385: Fixed sniper laser alignment |
| 2026-03-24 | Issue #1392: Debug visualizations reported as broken |

## Root Cause Analysis

### Observation from Game Logs

Both game logs (`game_log_20260324_055724.txt` and `game_log_20260324_055848.txt`) show:

1. **Settings correctly loaded**: All debug visualization settings were `true`
   ```
   Nav mesh visible: true, Search path visible: true, Enemy path visible: true, Cover raycast visible: true
   ```

2. **Overlays created successfully**: NavMeshMonitor, EnemyPathMonitor, and CoverRaycastMonitor all report creating their overlay nodes.

3. **Data populated**: NavMeshMonitor reports polygons being found and drawn:
   ```
   [NavMeshMonitor] Overlay shown with 97 polygon(s)
   ```

4. **No errors**: No script errors, null references, or crashes reported.

### Root Cause: CanvasLayer Z-Order Conflict

The debug visualization overlays were placed on low CanvasLayer layers:

| Monitor | Original Layer |
|---------|---------------|
| SearchPathMonitor | 10 |
| EnemyPathMonitor | 10 |
| CoverRaycastMonitor | 10 |
| WaypointMonitor | 11 |
| NavMeshMonitor | 50 |
| SoundVisualizer | 50 |

Meanwhile, the game's visual effects system uses much higher layers:

| Effect Manager | Layer |
|---------------|-------|
| BlackMetalEffectsManager | 97 |
| BlackMetalLightningEffectsManager | 98 |
| CinemaEffectsManager | 99 |
| HitEffectsManager | 100 |
| SceneLoader | 100 |
| PenultimateHitEffectsManager | 101 |
| LastChanceEffectsManager | 102 |
| FlashbangPlayerEffectsManager | 103 |
| PowerFantasyEffectsManager | 103 |
| FpsMonitor | 200 |

In Godot 4's CanvasLayer system, **higher layers render on top of lower layers**. The debug overlays at layers 10-50 were rendering BELOW all the visual effects layers (97-103). Several of these effects use **full-screen semi-transparent overlays** (ColorRect with shader materials), which would partially or fully obscure the debug visualizations underneath.

The CinemaEffectsManager in particular creates a full-screen `ColorRect` with a film grain shader at layer 99. Even with relatively low opacity, this overlay—combined with other effects at layers 97-103—made the debug drawings invisible or indistinguishable from the game scene.

### Why It Wasn't Caught Earlier

The NavMeshMonitor had already been raised to layer 50 (from an original lower value), with a comment saying "Below CinemaEffects at 99 so debug overlay doesn't cover vignette." This design decision prioritized aesthetics over functionality—the debug overlay was intentionally placed below effects. However, this made the overlays invisible in practice, defeating their purpose.

## Fix

Raised all debug visualization overlay layers to 150-151, placing them:
- **Above** all visual effects (max layer 103)
- **Below** the FPS counter (layer 200)

| Monitor | Old Layer | New Layer |
|---------|-----------|-----------|
| SearchPathMonitor | 10 | 150 |
| EnemyPathMonitor | 10 | 150 |
| CoverRaycastMonitor | 10 | 150 |
| NavMeshMonitor | 50 | 150 |
| SoundVisualizer | 50 | 150 |
| WaypointMonitor | 11 | 151 |

Additionally fixed a minor bug: `tactical_group_enabled` was missing from the `_load_settings()` else branch (default values when no config file exists).

## Relevant PRs

- PR #1278: feat(#1277): add enemy navigation path display in Experimental menu
- PR #1286: fix(#1285): restore path/search path/navmesh display in Experimental menu
- PR #1360: feat(#1359): add cover raycast visualization toggle
- PR #1366: feat(#1365): reorganize experimental menu into categories

## Key Lesson

Debug/diagnostic overlays should always render above all visual effects layers. Their purpose is to provide visibility into game state for debugging—if they can be obscured by effects, they cannot serve that purpose. The layer ordering should be:

```
Game World: 0 (default)
Visual Effects: 97-103
Debug Overlays: 150-151
FPS Counter: 200
```
