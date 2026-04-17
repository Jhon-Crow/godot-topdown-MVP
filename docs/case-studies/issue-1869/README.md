# Issue 1869 Case Study

## Source Material

- Issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1869
- Pull request: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1871
- User reproduction logs:
  - `game_log_20260418_002108.txt`
  - `game_log_20260418_013729.txt`

## Timeline

- The issue reported three symptoms around the loudspeaker true ending: the pacifist completion message did not follow the selected English locale, the true-ending message only advanced on mouse click instead of any key, and left mouse click could still trigger player shooting while the message was visible.
- The first PR revision changed `scripts/levels/railway_station_level.gd`, but owner feedback on April 17, 2026 reported the symptoms still reproduced in an exported Windows build.
- The attached game log shows the player using `LabyrinthLevel` with loudspeaker progression restored at level 7. That points to the active-item loudspeaker victory path, not the Railway Station level's own score-screen path.
- The second PR revision changed the GDScript `PlayerLoudspeakerComponent`, but the follow-up log still used the C# player path. The runtime evidence is the `[Player.Loudspeaker]` log lines emitted by `Scripts/Characters/Player.ActiveItems.cs`, including level-7 victory initialization and hard-to-dismiss overlays.
- In `game_log_20260418_002108.txt`, each click that advances the victory overlay can also reach gameplay: `End screen shown` is immediately followed by `WeaponHintsComponent` shot events at 00:21:47, 00:21:59, 00:22:22, and after switching locale to English at 00:22:51.
- In `game_log_20260418_013729.txt`, the English locale is loaded at 01:37:31. The session repeatedly reaches `Victory message shown (Level 7)`, and the final attempt at 01:38:10 never advances to `End screen shown` before the log ends, matching the reported keyboard dismissal failure.

## Root Cause

The exported game uses the C# loudspeaker implementation in `Scripts/Characters/Player.ActiveItems.cs` for this path. `ShowLoudspeakerVictoryMessage()` still had hard-coded Russian text, only reacted to mouse GUI input, and did not consume the dismissing event before gameplay input could react. Earlier fixes targeted `scripts/levels/railway_station_level.gd` and then `scripts/components/player_loudspeaker_component.gd`, so they did not affect the active C# code path shown by the logs.

## Fix Direction

- Localize the loudspeaker true-ending message, dismiss hint, end title, and thanks text through `resources/translations/translations.csv`.
- Let the C# `Player` loudspeaker path dismiss the victory message from any non-echo key press or pressed mouse button.
- Mark the triggering event handled and disable player input processing while the C# loudspeaker true-ending message is visible, preventing LMB from also firing.
- Keep regression tests focused on the exact source path that generated the feedback.
