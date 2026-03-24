# Case Study: Issue #1332 — Revolver Bullet Homing (Aim Assist)

## Timeline

| Date | Event |
|------|-------|
| 2026-03-22 | Issue #1332 opened: "добавь небольшое наведение пули на врага" (add slight bullet homing toward enemies) |
| 2026-03-22 | Initial implementation: weak aim-line homing at 4 rad/s steer speed added to Revolver.cs and Bullet.cs |
| 2026-03-22 | PR #1333 created and marked ready |
| 2026-03-24 | Owner feedback: requested verification of homing, stronger effect, and gameplay menu toggle |

## Data Sources

- `game_log_20260324_085906.txt` — Full game log from owner's test session (23,943 lines)
- Source code: `Scripts/Projectiles/Bullet.cs`, `Scripts/Weapons/Revolver.cs`

## Analysis of Game Log

### Environment
- OS: Windows
- Engine: Godot 4.3-stable
- Difficulty: Hard
- Weapon: Revolver (RSh-12)

### Findings

1. **36 revolver shots fired** during the test session
2. **227 bullet-enemy threat sphere interactions** recorded
3. **Player homing buff was NOT active** — every shot logged `[Player.Homing] No homing bullets selected in ActiveItemManager`
4. **No homing debug output** — `DebugHoming = false` in Bullet.cs, so homing activation/steering is silent in logs

### Root Cause Analysis

The homing implementation was technically correct but had two issues:

1. **Too weak to notice**: 4 rad/s steer speed is ~229 degrees/sec, but bullets travel at 2500 px/s and live 3 seconds max. At typical combat distances (200-600px), bullets reach enemies in 0.08-0.24 seconds. A 4 rad/s correction over 0.1s only deflects the bullet by ~0.4 radians (23 degrees), which at close range is barely perceptible.

2. **No user control**: No setting existed to enable/disable the feature, making it impossible for users to verify it was working or adjust behavior.

## Solution

1. **Increased steer speed** from 4 rad/s to 12 rad/s — noticeable correction without full homing missile behavior
2. **Added gameplay menu toggle** "Revolver Aim Assist" (default: ON) in GameplaySettings
3. **Revolver.cs reads the setting** and only applies homing when enabled

## Comparison: Steer Speed Values

| Value | Effect | Use Case |
|-------|--------|----------|
| 4 rad/s | Barely perceptible nudge | Original (too weak) |
| 12 rad/s | Noticeable correction, still feels natural | New default |
| 50 rad/s | Sharp tracking, guided missile feel | Player homing buff |
