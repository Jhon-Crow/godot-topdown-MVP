# Issue 1869 Case Study

## Source Material

- Issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1869
- Pull request: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1871
- User reproduction log: `game_log_20260418_002108.txt`

## Timeline

- The issue reported three symptoms around the loudspeaker true ending: the pacifist completion message did not follow the selected English locale, the true-ending message only advanced on mouse click instead of any key, and left mouse click could still trigger player shooting while the message was visible.
- The first PR revision changed `scripts/levels/railway_station_level.gd`, but owner feedback on April 17, 2026 reported the symptoms still reproduced in an exported Windows build.
- The attached game log shows the player using `LabyrinthLevel` with loudspeaker progression restored at level 7. That points to the active-item loudspeaker victory path, not the Railway Station level's own score-screen path.

## Root Cause

`PlayerLoudspeakerComponent._show_loudspeaker_victory_message()` creates the true-ending overlay used by loudspeaker level 7. That overlay had hard-coded Russian text, only reacted to mouse GUI input, and did not disable or consume player input broadly enough before gameplay input could react. The earlier fix targeted a different end-screen implementation in `railway_station_level.gd`, so it did not affect the reproduction path shown by the log.

## Fix Direction

- Localize the loudspeaker true-ending message, dismiss hint, end title, and thanks text through `resources/translations/translations.csv`.
- Let `PlayerLoudspeakerComponent` dismiss the victory message from any non-echo key press or pressed mouse button.
- Mark the triggering event handled and disable player input processing while the loudspeaker true-ending message is visible, preventing LMB from also firing.
- Keep regression tests focused on the exact source path that generated the feedback.
