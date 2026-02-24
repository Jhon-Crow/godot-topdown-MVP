# Case Study: Game Optimization Plan (Issue #880)

## Problem Statement

The game requires a comprehensive optimization audit to identify and address performance bottlenecks across all systems. The user has provided a game log from a live session (`game_log_20260224_181048.txt`) covering ~19 minutes of gameplay across multiple levels.

**User Request:** Analyze all unoptimized elements of the game and produce an optimization plan.

## Documentation Structure

| Document | Description |
|----------|-------------|
| [README.md](./README.md) | This overview and case study index |
| [analysis.md](./analysis.md) | Deep analysis of game log data and code bottlenecks |
| [optimization-plan.md](./optimization-plan.md) | Prioritized action plan with solutions and estimates |
| [research.md](./research.md) | Godot 4 optimization best practices and external references |
| [logs/](./logs/) | User-provided game log and analysis output |

## Summary of Findings

From analysis of the game log (217,290 lines, ~19 minutes of gameplay) and the codebase, we identified **6 major categories** of optimization opportunities:

### Category 1: File I/O Logging in Hot Paths (CRITICAL)
- The `FileLogger` writes to disk on **every** call, including `flush()` after each line
- This logger is called from physics-process-level loops (every frame)
- **Evidence from log:** 217,290 log lines = ~190 writes/second with disk flush
- Top contributors: `[SoundPropagation]` (59,439 messages), `[EnemyGrenade]` (29,250), `[Bullet]` (21,251), `[BloodDecal]` (12,425)

### Category 2: Per-Frame Physics Raycasts (HIGH)
- Every enemy calls `_check_player_visibility()` **every physics frame** (60 fps)
- Each visibility check performs **5 raycasts** using direct space state queries
- With 20 enemies (DocksLevel), this is **100 raycasts/frame** just for player visibility
- Additional raycasts: grenade path checks, grenade target visibility, LOS for aggression

### Category 3: Sound Propagation No-Op Events (HIGH)
- **6,437 out of 29,095 Sound result events** (22%) had zero recipients (`notified=0, out_of_range=0, self=0, below_threshold=0`)
- These represent sounds emitted with **no valid source or target** that still iterate all listeners
- Sound system iterates ALL listeners for every sound event, even zero-listener cases

### Category 4: Enemy Grenade Component Overhead (MEDIUM)
- **8,201 "Unsafe throw distance"** messages (logged per frame when trigger conditions met)
- **8,201 times** `_get_blast_radius()` was called, which **instantiates a temporary grenade scene** each time
- This means temporary scene instantiation is happening repeatedly during gameplay

### Category 5: Unbounded Blood Decal Accumulation (MEDIUM)
- **12,425 blood decals** created in 19 minutes with **no cleanup** (MAX_BLOOD_DECALS = 0)
- Each decal has an Area2D child node with a collision shape for footprint detection
- Every collision system check iterates these indefinitely-growing objects
- Decals are tracked in an Array that grows without bound, even if decals are never visible

### Category 6: Replay Manager Per-Frame File Logging (MEDIUM)
- ReplayManager logs frame data every physics frame during recording
- At 60 fps, this generates thousands of log entries over a short game session
- Replay log data passes through the FileLogger I/O system with disk flush per message

## Quick Reference: Files Affected

| File | Bottleneck | Priority |
|------|-----------|----------|
| `scripts/autoload/file_logger.gd` | Flush-per-write I/O | CRITICAL |
| `scripts/objects/enemy.gd` | 5 raycasts/frame/enemy | HIGH |
| `scripts/components/enemy_grenade_component.gd` | temp scene instantiation | HIGH |
| `scripts/autoload/sound_propagation.gd` | no-op event processing | HIGH |
| `scripts/autoload/impact_effects_manager.gd` | unbounded decal arrays | MEDIUM |
| `scripts/effects/blood_decal.gd` | per-decal Area2D nodes | MEDIUM |
| `scripts/autoload/replay_system.gd` | per-frame file logging | MEDIUM |
| `scripts/components/aggression_component.gd` | per-frame group lookup | MEDIUM |
| `scripts/components/vision_component.gd` | 5 raycasts per check | MEDIUM |
