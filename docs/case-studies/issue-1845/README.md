# Issue #1845 — Case Study Index

**Problem:** Muzzle flashes are barely visible on the floor of the "Лабиринт Комплекс" (Labyrinth Complex / `Labyrinth2Level`) map. They are visible on enemies, blood and casings.

**Status:** Previous PR [#1846](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1846) was closed (owner still reported the bug + a new "square flash" artefact). Re-opened via comment "попробуй снова" on 2026-04-20. Current attempt is PR [#1913](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1913).

## Files in this folder

| File | Purpose |
| :--- | :--- |
| [`case-study.md`](./case-study.md) | Full analysis: timeline, root cause, candidate solutions, open questions. |
| `issue.json` | Raw issue body from GitHub. |
| `issue-comments.json` | All comments on issue #1845. |
| `pr-1846.json` | Metadata of the closed previous PR. |
| `pr-1846-comments.json` | Full conversation on PR #1846 — every rejected attempt and owner feedback. |
| `pr-1913.json` | Metadata of the current WIP PR. |
| `game_log_20260416_013506.txt` | Initial log attached to the issue. |
| `game_log_20260416_021858.txt` | Log after 1st rejected attempt. |
| `game_log_20260416_231945.txt` | Log after 2nd rejected attempt. |
| `game_log_20260417_041119.txt` | Log after 3rd rejected attempt. |
| `game_log_20260417_233940.txt` | Log after 4th rejected attempt — owner hints at "проблема со слоями". |
| `game_log_20260418_013007.txt` | Log after 5th rejected attempt. |
| `game_log_20260420_122659.txt` | Log after 6th attempt — owner asks to revert brightness. |
| `game_log_20260420_125552.txt` | Log after 7th attempt — marked "не исправлено". |
| `game_log_20260420_135251.txt` | Log after 8th attempt (FloorGlow sprite) — "square flash" artefact reported, PR closed. |

## Short answer

The Labyrinth Complex map dynamically creates **11 warm ceiling `PointLight2D`s** (`scripts/levels/labyrinth2_level.gd::_setup_room_warm_lights`) plus a `DirectionalLight2D`. The floor is already saturated with warm light, so the muzzle flash's `+4.5` energy pulse produces almost no perceptual change on the floor, even though the very same light is clearly visible on walls and particles/blood (which start unlit).

See [`case-study.md`](./case-study.md) §4 for full analysis and §5 for proposed solution directions.
