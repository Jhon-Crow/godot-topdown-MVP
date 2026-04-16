# Issue 1810 Case Study

## Issue

- GitHub issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1810
- PR: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1847

## Reported Problems

1. On the `Labyrinth` map, tutorial lines remain in Russian when English language is enabled.
2. On the `Building` and `Factory` maps, tutorial lines do not appear.

## Collected Artifacts

- `issue-comments.json`: current issue comments
- `pr-comments.json`: current PR conversation comments, including follow-up owner reports
- `pr-review-comments.json`: current PR inline review comments
- `pr-reviews.json`: current PR reviews
- `issue-1810-game-log.txt`: owner-provided runtime log from April 11, 2026
- `game_log_20260416_100413.txt`: owner-provided runtime log from April 16, 2026
- `analysis.md`: reconstructed findings and root-cause notes

## Initial Findings

- `scripts/levels/labyrinth_level.gd` still contained hardcoded Russian tutorial strings for several hints instead of relying fully on translation keys.
- `scripts/levels/building_level.gd` already initialized the shared `weapon_hints_component`, while `scripts/levels/factory_level.gd` was missing that hookup.
- The owner log confirms the selected weapon and level initialization path on `Labyrinth`, which matches the issue report timing on April 11, 2026.
